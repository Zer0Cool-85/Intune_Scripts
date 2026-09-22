#Requires -Version 5.1
<#
.SYNOPSIS
Enables Adobe automatic updates only for detected, machine-wide Reader DC installs.
.DESCRIPTION
Version 1.0.0. Run using Windows PowerShell 5.1 as SYSTEM or an administrator.
Detects both registry architectures and verifies the installed application file.
Supports traditional Reader and unified Acrobat with SCAPackageLevel = 1.
The installation source (Store Win32, MSI, EXE) does not change this detection.

For each confirmed Continuous/DC Reader installation, this script:
  * Removes the product-update bUpdater override from FeatureLockDown, allowing
    Mode to control updates. It does not change cServices\bUpdater.
  * Sets Mode = 3 and Check = 24 (configurable) on existing Adobe ARM product
    registrations whose product codes match the detected installed product.
  * Enables the existing shared Adobe update service, when present.
  * Enables and optionally starts Adobe's existing updater task without changing
    its principal, arguments, schedule, or other execution settings.

No installer is downloaded. No new updater registration, service, or scheduled
task is fabricated. No application is closed or computer restarted by this script.
Adobe's updater retains control over update timing, UI, and restart requirements.
The shared updater can also service a coinstalled Acrobat product according to
that product's existing settings; its product-specific settings are not modified.

Old Classic/X/XI versions are reported for migration, not treated as current.
Per-user-only, AppX/MSIX-only, portable, and damaged installs are outside scope.
Missing or ambiguous registrations are reported rather than guessed.

INTUNE PLATFORM SCRIPT SETTINGS
  Devices > Scripts and remediations > Platform scripts > Add
  Run using logged-on credentials: No
  Enforce script signature check: No for this unsigned file, or sign it first.
  Run in 64-bit PowerShell host: Yes
  Pilot first, then assign to your Windows device groups.
  Platform scripts do not continuously re-enforce these settings. Adobe's native
  task handles subsequent updates. Remove any old GPO/management policy that
  continues to disable updates. A future app install after an absent-app skip
  is not covered by that run of this script.

EXIT CODES
  0 = In-scope configuration completed, or no in-scope Reader was found.
  1 = Error, incomplete configuration, or installation needs administrator review.
  Neither exit code verifies the latest Adobe patch has been installed.

LOG
  %ProgramData%\AdobeReaderAutoUpdate\Enable-AdobeReaderAutoUpdate.log
  AuditOnly writes to the console only. Absent Reader makes no Adobe changes.

.PARAMETER AuditOnly
Inspects scope/settings without changing the registry, services, tasks, or files.
.PARAMETER SkipUpdateCheck
Configures updates but does not request an immediate run of the Adobe task.
.PARAMETER CheckIntervalHours
Adobe's documented update check interval. Default 24 hours, not an update SLA.
Intune Platform scripts use defaults; edit the default here if necessary.
.EXAMPLE
.\Enable-AdobeReaderAutoUpdate.ps1 -AuditOnly
.EXAMPLE
.\Enable-AdobeReaderAutoUpdate.ps1
.LINK
https://www.adobe.com/devnet-docs/acrobatetk/tools/PrefRef/Windows/Updater-Win.html
.LINK
https://helpx.adobe.com/acrobat/kb/about-acrobat-reader-dc-migration-to-64-bit.html
.LINK
https://learn.microsoft.com/en-us/intune/app-management/deployment/add-microsoft-store
.LINK
https://learn.microsoft.com/en-us/intune/device-management/tools/run-powershell-scripts-windows
#>
[CmdletBinding()]
param(
    [switch]$AuditOnly,
    [switch]$SkipUpdateCheck,
    [ValidateRange(1, 168)]
    [int]$CheckIntervalHours = 24
)

$ErrorActionPreference = 'Stop'
$script:LogFile = $null
$script:ReviewCount = 0

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 }
}

function Write-Review {
    param([string]$Message)
    $script:ReviewCount++
    Write-Log -Message $Message -Level 'REVIEW'
}

function Get-RegValue {
    param([string]$Path, [string]$Name = '')
    if (Test-Path -LiteralPath $Path) {
        $key = Get-Item -LiteralPath $Path
        try { return $key.GetValue($Name, $null) }
        finally { $key.Close() }
    }
}

function Get-AdobeExe {
    param([string[]]$Locations)
    $seen = @{}
    foreach ($location in $Locations) {
        if ([string]::IsNullOrWhiteSpace($location)) { continue }
        $clean = [Environment]::ExpandEnvironmentVariables($location.Trim())
        # Remove the resource index from an ARP DisplayIcon value.
        $clean = ($clean -replace ',\s*-?\d+\s*$', '').Trim().Trim('"')
        $candidates = @($clean)
        if (Test-Path -LiteralPath $clean -PathType Container) {
            $candidates = @('AcroRd32.exe', 'Acrobat.exe', 'Reader\AcroRd32.exe', 'Acrobat\Acrobat.exe') |
                ForEach-Object { Join-Path -Path $clean -ChildPath $_ }
        }
        foreach ($candidate in $candidates) {
            if ([IO.Path]::GetFileName($candidate) -notin @('AcroRd32.exe', 'Acrobat.exe')) { continue }
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
            $item = Get-Item -LiteralPath $candidate
            if ($item.VersionInfo.CompanyName -notmatch '^Adobe\b') { continue }
            if (-not $seen.ContainsKey($item.FullName)) {
                $seen[$item.FullName] = $true
                $item.FullName
            }
        }
    }
}

function Set-UpdateDword {
    param([string]$Path, [string]$Name, [int]$Value)
    # ARM keys must already exist and must have been matched to installed ARP.
    if (-not (Test-Path -LiteralPath $Path)) { throw "Registration disappeared: $Path" }
    $before = Get-RegValue -Path $Path -Name $Name
    $oldText = if ($null -eq $before) { '<absent>' } else { [string]$before }
    Write-Log "$Path : $Name $oldText -> $Value"
    if ($AuditOnly) { return }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
    if ((Get-RegValue -Path $Path -Name $Name) -ne $Value) { throw "Readback failed: $Path\$Name" }
}

function Remove-UpdateBlock {
    param([string]$Path)
    $before = Get-RegValue -Path $Path -Name 'bUpdater'
    if ($null -eq $before) {
        Write-Log "$Path : no product-update bUpdater override"
        return
    }
    Write-Log "$Path : remove product-update bUpdater override (was $before); Mode will apply"
    if ($AuditOnly) { return }
    Remove-ItemProperty -LiteralPath $Path -Name 'bUpdater'
    if ($null -ne (Get-RegValue -Path $Path -Name 'bUpdater')) { throw "Override removal failed: $Path" }
}

function Test-AdobeUpdaterFile {
    param([string]$Path, [string]$ExpectedName)
    if (-not $Path) { return $false }
    if ([IO.Path]::GetFileName($Path) -ine $ExpectedName) { return $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    return ($signature.Status -eq 'Valid' -and
        $null -ne $signature.SignerCertificate -and
        $signature.SignerCertificate.Subject -match '(?i)\bO="?Adobe (Inc\.|Systems Incorporated)')
}

try {
    if ($env:OS -ne 'Windows_NT') { throw 'This script requires Windows.' }
    if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Run in Windows PowerShell 5.1, not PowerShell 7.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        throw 'Run in the 64-bit PowerShell host. Set the Intune host setting to Yes.'
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run as SYSTEM or an administrator.'
    }

    $softwareRoots = @('HKLM:\SOFTWARE')
    if ([Environment]::Is64BitOperatingSystem) { $softwareRoots += 'HKLM:\SOFTWARE\WOW6432Node' }

    # Read ARP directly. Do not query Win32_Product (it can trigger MSI repairs).
    $arp = @(
        foreach ($root in $softwareRoots) {
            $uninstallRoot = "$root\Microsoft\Windows\CurrentVersion\Uninstall"
            if (-not (Test-Path -LiteralPath $uninstallRoot)) { continue }
            foreach ($key in Get-ChildItem -LiteralPath $uninstallRoot) {
                try {
                    $name = [string]$key.GetValue('DisplayName')
                    $publisher = [string]$key.GetValue('Publisher')
                    if ($name -notmatch '^Adobe\s+(Acrobat|Reader)\b' -or $publisher -notmatch '^Adobe\b') { continue }
                    $locations = @([string]$key.GetValue('DisplayIcon'), [string]$key.GetValue('InstallLocation'))
                    [pscustomobject]@{
                        Name = $name
                        Version = [string]$key.GetValue('DisplayVersion')
                        ProductCode = $key.PSChildName
                        Root = $root
                        Exes = @(Get-AdobeExe -Locations $locations)
                    }
                }
                finally { $key.Close() }
            }
        }
    )

    # Reader DC x86 and unified Reader x64 use different product registry hives.
    $products = @(
        foreach ($root in $softwareRoots) {
            foreach ($family in @('Acrobat Reader', 'Adobe Acrobat')) {
                $familyPath = "$root\Adobe\$family"
                if (-not (Test-Path -LiteralPath $familyPath)) { continue }
                $branches = @(Get-ChildItem -LiteralPath $familyPath | Select-Object -ExpandProperty PSChildName)
                foreach ($branch in $branches) {
                    if ($branch -notmatch '^(DC|\d+(\.\d+)?)$') { continue }
                    $productPath = "$familyPath\$branch"
                    $locations = @(
                        [string](Get-RegValue -Path "$productPath\InstallPath"),
                        [string](Get-RegValue -Path $productPath -Name 'InstallPath')
                    )
                    $executables = @(Get-AdobeExe -Locations $locations)
                    foreach ($exe in $executables) {
                        $level = Get-RegValue -Path "$productPath\Installer" -Name 'SCAPackageLevel'
                        $isUnified = [IO.Path]::GetFileName($exe) -ieq 'Acrobat.exe'
                        if ($family -eq 'Adobe Acrobat' -or $isUnified) {
                            if ($null -eq $level -or [string]$level -ne '1') {
                                $label = if ($null -eq $level) { 'unknown' } else { [string]$level }
                                Write-Log "Excluded Acrobat: $exe; SCAPackageLevel=$label. Reader identity is not confirmed."
                                continue
                            }
                        }
                        $fileVersion = (Get-Item -LiteralPath $exe).VersionInfo
                        [pscustomobject]@{
                            Family = $family
                            Branch = $branch
                            Root = $root
                            Exe = $exe
                            Version = $fileVersion.FileVersion
                            IsContinuous = ($branch -eq 'DC' -and $fileVersion.FileMajorPart -ge 15)
                            Arp = @($arp | Where-Object { $_.Exes -contains $exe })
                        }
                    }
                }
            }
        }
    )

    if ($products.Count -eq 0) {
        $namedReaders = @($arp | Where-Object { $_.Name -match '\bReader\b' })
        if ($namedReaders.Count -gt 0) {
            Write-Review ('Reader ARP entries exist, but a Reader installation could not be confirmed. Review stale, damaged, or reclassified installs: ' + ($namedReaders.Name -join '; '))
            exit 1
        }
        Write-Log 'No confirmed machine-wide Reader installation. No Adobe settings, services, or tasks changed.'
        exit 0
    }

    if (-not $AuditOnly) {
        $logDirectory = Join-Path $env:ProgramData 'AdobeReaderAutoUpdate'
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        $script:LogFile = Join-Path $logDirectory 'Enable-AdobeReaderAutoUpdate.log'
    }
    Write-Log "Begin v1.0.0; AuditOnly=$AuditOnly; CheckIntervalHours=$CheckIntervalHours"

    # Surface recognizable Reader entries that could not be mapped; never treat
    # an unknown Reader as successfully configured just because another was found.
    foreach ($entry in @($arp | Where-Object { $_.Name -match '\bReader\b' })) {
        $mapped = @($products | Where-Object { $_.Exe -in $entry.Exes })
        if ($mapped.Count -eq 0) { Write-Review "Unmapped Reader registration: $($entry.Name) $($entry.Version). No settings changed for it." }
    }

    $configuredCount = 0
    foreach ($product in $products) {
        Write-Log "Detected $($product.Family) $($product.Branch), file version $($product.Version), $($product.Exe)"
        if (-not $product.IsContinuous) {
            Write-Review 'Legacy/Classic Reader requires a separately planned upgrade. Enabling its old updater would not establish current patch compliance.'
            continue
        }
        $codes = @($product.Arp | Select-Object -ExpandProperty ProductCode -Unique)
        $armKeys = @(
            foreach ($root in $softwareRoots) {
                foreach ($armFamily in @('Reader', 'Acrobat')) {
                    foreach ($code in $codes) {
                        if ($code -notmatch '^\{[0-9A-Fa-f-]{36}\}$') { continue }
                        $armPath = "$root\Adobe\Adobe ARM\Legacy\$armFamily\$code"
                        if (Test-Path -LiteralPath $armPath) { $armPath }
                    }
                }
            }
        )
        if ($armKeys.Count -eq 0) {
            Write-Review "No existing ARM product registration matched this Reader's installed product code. Repair/redeploy the appropriate Reader package; no guessed GUID is written."
            continue
        }
        try {
            # Explicitly inspect both physical policy paths, including Adobe's
            # documented WOW6432Node\Policies location on 64-bit machines.
            foreach ($root in $softwareRoots) {
                Remove-UpdateBlock -Path "$root\Policies\Adobe\$($product.Family)\$($product.Branch)\FeatureLockDown"
            }
            foreach ($armPath in $armKeys) {
                Set-UpdateDword -Path $armPath -Name 'Mode' -Value 3
                Set-UpdateDword -Path $armPath -Name 'Check' -Value $CheckIntervalHours
            }
            $configuredCount++
        }
        catch { Write-Review "Configuration failed for $($product.Exe): $($_.Exception.Message)" }
    }

    if ($configuredCount -gt 0) {
        # This service is shared by Adobe's Acrobat/Reader updater. Missing
        # service is logged, since layouts can differ; do not invent a service.
        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='AdobeARMservice'"
        if ($service) {
            $servicePath = [Environment]::ExpandEnvironmentVariables([string]$service.PathName)
            $binary = $null
            if ($servicePath -match '^\s*"([^"]+\.exe)"') { $binary = $Matches[1] }
            elseif ($servicePath -match '^\s*(.+?\.exe)(?:\s|$)') { $binary = $Matches[1] }
            if (-not (Test-AdobeUpdaterFile -Path $binary -ExpectedName 'armsvc.exe')) {
                Write-Review 'AdobeARMservice binary could not be verified as signed Adobe armsvc.exe. Service left unchanged; inspect/repair it.'
            }
            else {
                Write-Log "AdobeARMservice: start mode=$($service.StartMode), state=$($service.State); ensure Automatic and request start"
                if (-not $AuditOnly) {
                    try {
                        if ($service.StartMode -ne 'Auto') { Set-Service -Name 'AdobeARMservice' -StartupType Automatic }
                        if ($service.State -ne 'Running') { Start-Service -Name 'AdobeARMservice' }
                    }
                    catch { Write-Review "Unable to enable/start AdobeARMservice: $($_.Exception.Message)" }
                }
            }
        }
        else { Write-Log 'AdobeARMservice is absent. No service created; verify the native update workflow during the pilot.' -Level 'WARN' }

        $tasks = @(Get-ScheduledTask | Where-Object { $_.TaskName -like 'Adobe Acrobat Update Task*' })
        $validTaskCount = 0
        foreach ($task in $tasks) {
            $actions = @($task.Actions)
            if ($actions.Count -ne 1) {
                Write-Review "Unexpected actions in $($task.TaskPath)$($task.TaskName); task left unchanged."
                continue
            }
            $taskExe = [Environment]::ExpandEnvironmentVariables([string]$actions[0].Execute).Trim('"')
            if (-not (Test-AdobeUpdaterFile -Path $taskExe -ExpectedName 'AdobeARM.exe')) {
                Write-Review "Task does not point to a verifiable, signed AdobeARM.exe: $($task.TaskPath)$($task.TaskName). Task left unchanged."
                continue
            }
            $enabledTriggers = @($task.Triggers | Where-Object { $null -ne $_ -and $_.Enabled -ne $false })
            if ($enabledTriggers.Count -eq 0) {
                Write-Review "Updater task has no enabled automatic trigger: $($task.TaskName). Repair its schedule."
            }
            $validTaskCount++
            Write-Log "Adobe task: $($task.TaskPath)$($task.TaskName), state=$($task.State); ensure enabled"
            if ($AuditOnly) { continue }
            try {
                Enable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath | Out-Null
            }
            catch {
                Write-Review "Could not enable Adobe task: $($_.Exception.Message)"
                continue
            }
            if (-not $SkipUpdateCheck) {
                try {
                    if ([string]$task.State -ne 'Running') {
                        Start-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath
                        Write-Log 'Requested native updater task run. This is not confirmation of an update check or installed patch.'
                    }
                    else { Write-Log 'Adobe updater task is already running.' }
                }
                catch {
                    Write-Log "Immediate task run was not accepted: $($_.Exception.Message). A user sign-in may be required; the existing enabled schedule remains." -Level 'WARN'
                }
            }
        }
        if ($validTaskCount -eq 0) {
            Write-Review 'No usable Adobe updater task was found. Settings alone do not establish automatic execution; repair/redeploy Reader and verify its updater.'
        }
    }

    $action = if ($AuditOnly) { 'Inspected configuration for' } else { 'Configured' }
    Write-Log "$action $configuredCount Reader installation(s); review items=$script:ReviewCount. Latest installed patch has NOT been verified."
    if ($script:ReviewCount -gt 0) { exit 1 }
    exit 0
}
catch {
    Write-Log -Message "Failed: $($_.Exception.Message)" -Level 'ERROR'
    exit 1
}
