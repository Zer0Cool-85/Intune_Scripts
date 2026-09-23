#Requires -Version 5.1
<#
.SYNOPSIS
Updates an existing Adobe Reader installation using WinGet. Never installs Reader when absent.
.DESCRIPTION
Version 1.0.0. Windows PowerShell 5.1 or PowerShell 7; run elevated, native 64-bit.

Engine Auto selects CLI for a user account and Module for NT AUTHORITY\SYSTEM.
CLI uses winget list, exact Reader package IDs, list --upgrade-available, then
winget upgrade. It parses the exact ID and installed version from the table;
WinGet performs the version comparison. No fixed column offsets or translated
column labels are used. Truncated/unrecognized results fail instead of guessing.

Module uses Microsoft.WinGet.Client structured objects and IsUpdateAvailable.
This is Microsoft's supported WinGet interface for SYSTEM/machine-wide apps.
Preinstall Microsoft.WinGet.Client in AllUsers scope and provision/repair WinGet
before deploying this script. This script does not install its prerequisites.

Only these IDs from the winget community source are eligible:
  Adobe.Acrobat.Reader.64-bit
  Adobe.Acrobat.Reader.32-bit
Store-installed or migrated copies work if WinGet correlates their installation
with one of those IDs. Unmapped Reader/generic Acrobat candidates are reported
for review, never installed over. Per-user-only installations are outside the
intended SYSTEM deployment scope. This is not an Acrobat Pro updater.

Latest means the newest applicable version WinGet offers from its catalog,
which can lag Adobe's releases. CLI refreshes the winget source first. Module
uses the client's normal source refresh behavior. Unknown installed versions,
blocked upgrades, source failures and failed verification are not success.
No --force, --include-unknown upgrade, hash bypass, or reboot request is used.

EXIT CODES
  0    Reader absent, no update offered, or update verified with WinGet.
       With -CheckOnly, 0 also includes an update available but not installed.
  1    Prerequisite, matching, source, update, or verification failure.
  3010 Update reports a reboot needed to finish. Recheck after a managed reboot.
       Intune Win32 apps can map 3010 to soft reboot. Platform scripts treat
       nonzero as failure; account for that if using Platform scripts.

LOG: %ProgramData%\AdobeReaderWinGet\Update-AdobeReaderWithWinGet.log
CheckOnly still writes logs and can refresh WinGet metadata; it does not update Reader.

INTUNE: Run as SYSTEM, 64-bit host, using Engine Auto/Module. Deploy the WinGet
module/prerequisites first. Platform scripts are not a recurring patch schedule.

.PARAMETER Engine
Auto (default), CLI (elevated user only), or Module (SYSTEM supported).
.PARAMETER CheckOnly
Report installed packages and upgrade availability without upgrading Reader.
.EXAMPLE
.\Update-AdobeReaderWithWinGet.ps1 -Engine CLI -CheckOnly
.EXAMPLE
.\Update-AdobeReaderWithWinGet.ps1 -Engine CLI
.EXAMPLE
.\Update-AdobeReaderWithWinGet.ps1 -Engine Module
.LINK
https://learn.microsoft.com/en-us/windows/package-manager/winget/list
.LINK
https://learn.microsoft.com/en-us/windows/package-manager/winget/upgrade
.LINK
https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting
.LINK
https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md
#>
[CmdletBinding()]
param(
    [ValidateSet('Auto', 'CLI', 'Module')]
    [string]$Engine = 'Auto',
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$script:LogFile = $null
$script:Failures = 0
$script:NeedsReboot = $false
$readerIds = @('Adobe.Acrobat.Reader.64-bit', 'Adobe.Acrobat.Reader.32-bit')
$sourceName = 'winget'

function Write-Log {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 }
}

function Write-Failure {
    param([string]$Message)
    $script:Failures++
    Write-Log "REVIEW: $Message"
}

function Test-ReaderCandidate {
    param([string]$Name)
    # Generic Acrobat may be unified Reader or paid Acrobat: flag ambiguity.
    return ($Name -match '^Adobe\s+(?:Acrobat\s+)?Reader\b' -or
        $Name -match '^Adobe\s+Acrobat(?:\s+DC)?(?:\s+\((?:32|64)-bit\))?$')
}

function Get-ExitHex {
    param([int]$Code)
    return '0x{0:X8}' -f [BitConverter]::ToUInt32([BitConverter]::GetBytes($Code), 0)
}

function Invoke-WinGetCli {
    param([string[]]$Arguments)
    # All arguments are internal fixed tokens/allowlisted IDs without spaces.
    # Process APIs capture both streams without PowerShell 5.1 native-stderr traps.
    if (@($Arguments | Where-Object { $_ -match '[\s"]' }).Count -gt 0) {
        throw 'Unexpected argument requiring quoting.'
    }
    Write-Log ('winget ' + ($Arguments -join ' '))
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $script:WinGetPath
    $info.Arguments = $Arguments -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.Encoding]::UTF8
    $info.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'Could not start WinGet.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $exitCode = $process.ExitCode
        $text = $stdout.GetAwaiter().GetResult() + [Environment]::NewLine + $stderr.GetAwaiter().GetResult()
        $text = $text -replace '\x1B\[[0-?]*[ -/]*[@-~]', ''
        Write-Log $text.Trim()
        $hex = Get-ExitHex -Code $exitCode
        Write-Log "WinGet exit: $exitCode ($hex)"
        [pscustomobject]@{ Code = $exitCode; Hex = $hex; Text = $text }
    }
    finally { $process.Dispose() }
}

function Get-CliDataLines {
    param([string]$Text)
    $afterSeparator = $false
    foreach ($line in ($Text -split '[\r\n]+')) {
        if ($line.Trim() -match '^-{3,}$') { $afterSeparator = $true; continue }
        if ($afterSeparator -and $line.Trim()) { $line.Trim() }
    }
}

function Get-CliReaderRow {
    param([string]$Text, [string]$Id)
    $pattern = '^(?<Name>.+?)\s+' + [regex]::Escape($Id) + '\s+(?<InstalledVersion>\S+)(?:\s|$)'
    foreach ($line in @(Get-CliDataLines -Text $Text)) {
        if ($line -match $pattern) {
            [pscustomobject]@{ Id = $Id; Name = $Matches.Name; InstalledVersion = $Matches.InstalledVersion; Row = $line }
        }
    }
}

function Get-CliUpgradeRows {
    param([string]$Id)
    # Include unknown/pinned in the report so they aren't silently called current.
    # These flags are NOT passed to the installer/upgrade operation.
    $result = Invoke-WinGetCli -Arguments @('list', '--id', $Id, '--exact', '--source', $sourceName, '--scope', 'machine', '--upgrade-available', '--include-unknown', '--include-pinned', '--accept-source-agreements', '--disable-interactivity')
    if ($result.Hex -in @('0x8A150014', '0x8A15002B')) { return }
    if ($result.Code -ne 0) { throw "Upgrade query failed: $($result.Hex)" }
    $rows = @(Get-CliReaderRow -Text $result.Text -Id $Id)
    if ($rows.Count -eq 0 -and @((Get-CliDataLines -Text $result.Text) | Where-Object { $_ -match '^Adobe\b' }).Count -gt 0) {
        throw 'Upgrade table is unrecognized or truncated. Use Engine Module to avoid table parsing.'
    }
    $rows
}

function Assert-KnownReaderVersion {
    param([string]$Version)
    if ($Version -notmatch '^\d+(\.\d+){1,3}$') {
        throw "Cannot establish the installed Reader version ('$Version'). No forced upgrade attempted."
    }
}

function Invoke-CliWorkflow {
    $command = Get-Command -Name winget.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $script:WinGetPath = $command.Source
    $refresh = Invoke-WinGetCli -Arguments @('source', 'update', '--name', $sourceName, '--disable-interactivity')
    if ($refresh.Code -ne 0) { throw "WinGet source refresh failed: $($refresh.Hex)" }

    # Also inspect broad inventory for Reader entries which cannot be correlated
    # to the two allowed IDs, instead of reporting those as Reader absent.
    $inventory = Invoke-WinGetCli -Arguments @('list', '--query', 'Adobe', '--source', $sourceName, '--scope', 'machine', '--accept-source-agreements', '--disable-interactivity')
    if ($inventory.Code -ne 0 -and $inventory.Hex -ne '0x8A150014') { throw "Inventory failed: $($inventory.Hex)" }
    if ($inventory.Code -eq 0) {
        foreach ($line in @(Get-CliDataLines -Text $inventory.Text)) {
            if ($line -notmatch '^Adobe\b') { continue }
            $isAllowed = $false
            foreach ($id in $readerIds) {
                if ($line -match ('\s' + [regex]::Escape($id) + '\s')) { $isAllowed = $true }
            }
            $displayName = ($line -split '\s{2,}')[0]
            if (-not $isAllowed -and (Test-ReaderCandidate -Name $displayName)) {
                Write-Failure "Reader/ambiguous Acrobat is listed but not matched to an allowed ID: $line"
            }
        }
    }

    $foundCount = 0
    foreach ($id in $readerIds) {
        try {
            $queryArgs = @('list', '--id', $id, '--exact', '--source', $sourceName, '--scope', 'machine', '--accept-source-agreements', '--disable-interactivity')
            $installed = Invoke-WinGetCli -Arguments $queryArgs
            if ($installed.Hex -eq '0x8A150014') { continue }
            if ($installed.Code -ne 0) { throw "Installed query failed: $($installed.Hex)" }
            $rows = @(Get-CliReaderRow -Text $installed.Text -Id $id)
            if ($rows.Count -ne 1) { throw 'Expected one exact installed match; table may be ambiguous/truncated. Use Engine Module.' }
            $foundCount++
            Assert-KnownReaderVersion -Version $rows[0].InstalledVersion
            Write-Log "Installed: $id $($rows[0].InstalledVersion)"
            $updates = @(Get-CliUpgradeRows -Id $id)
            if ($updates.Count -eq 0) { Write-Log "$id : no newer update offered by WinGet."; continue }
            if ($updates.Count -ne 1) { throw 'Multiple upgrade matches; no installer started.' }
            Write-Log ('Upgrade candidate: ' + $updates[0].Row)
            if ($CheckOnly) { Write-Log 'CheckOnly: update not installed.'; continue }

            $upgrade = Invoke-WinGetCli -Arguments @('upgrade', '--id', $id, '--exact', '--source', $sourceName, '--scope', 'machine', '--silent', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
            if ($upgrade.Hex -eq '0x8A150109' -or $upgrade.Code -eq 3010) {
                $script:NeedsReboot = $true
                Write-Log "$id : reboot required to finish. Verify after reboot."
                continue
            }
            # A native updater could win the race between checking and upgrading.
            if ($upgrade.Code -ne 0 -and $upgrade.Hex -ne '0x8A15002B') { throw "Upgrade failed: $($upgrade.Hex)" }
            $after = Invoke-WinGetCli -Arguments $queryArgs
            $afterRows = @(Get-CliReaderRow -Text $after.Text -Id $id)
            if ($after.Code -ne 0 -or $afterRows.Count -ne 1) { throw 'Reader could not be matched after upgrade.' }
            Assert-KnownReaderVersion -Version $afterRows[0].InstalledVersion
            if (@(Get-CliUpgradeRows -Id $id).Count -gt 0) { throw 'WinGet still reports an update after the upgrade attempt.' }
            Write-Log "Verified: $id $($afterRows[0].InstalledVersion); no newer update offered."
        }
        catch { Write-Failure "$id : $($_.Exception.Message)" }
    }
    if ($foundCount -eq 0 -and $script:Failures -eq 0) { Write-Log 'Reader absent from the queried machine inventory. Nothing installed.' }
}

function Invoke-ModuleWorkflow {
    if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) {
        throw 'Microsoft.WinGet.Client is missing. Provision it in AllUsers scope before SYSTEM deployment.'
    }
    Import-Module Microsoft.WinGet.Client -ErrorAction Stop
    $inventory = @(Get-WinGetPackage -Query 'Adobe' -Source $sourceName -ErrorAction Stop)
    foreach ($package in $inventory) {
        if ($package.Id -notin $readerIds -and (Test-ReaderCandidate -Name $package.Name)) {
            Write-Failure "Unmapped Reader/ambiguous Acrobat: $($package.Name), ID=$($package.Id). No install attempted for this entry."
        }
    }
    $foundCount = 0
    foreach ($id in $readerIds) {
        try {
            $query = @{ Id = $id; Source = $sourceName; MatchOption = 'Equals'; ErrorAction = 'Stop' }
            $installedPackages = @(Get-WinGetPackage @query)
            if ($installedPackages.Count -eq 0) { continue }
            if ($installedPackages.Count -ne 1) { throw 'Multiple installed matches; no installer started.' }
            $foundCount++
            $package = $installedPackages[0]
            Assert-KnownReaderVersion -Version $package.InstalledVersion
            if (@($package.AvailableVersions).Count -eq 0) { throw 'No catalog versions available; current version cannot be checked.' }
            Write-Log "Installed: $id $($package.InstalledVersion); update offered=$($package.IsUpdateAvailable)"
            if (-not $package.IsUpdateAvailable) { Write-Log "$id : no newer update offered by WinGet."; continue }
            if ($CheckOnly) { Write-Log 'CheckOnly: update not installed.'; continue }
            $results = @(Update-WinGetPackage -PSCatalogPackage $package -Scope System -Mode Silent -Confirm:$false -ErrorAction Stop)
            if ($results.Count -ne 1) { throw 'Unexpected number of update results.' }
            $result = $results[0]
            Write-Log "Update status=$($result.Status); installer=$($result.InstallerErrorCode); extended=$($result.ExtendedErrorCode); reboot=$($result.RebootRequired)"
            $extendedHex = if ($null -ne $result.ExtendedErrorCode) { Get-ExitHex -Code $result.ExtendedErrorCode.HResult } else { '0x00000000' }
            if ($extendedHex -eq '0x8A150109' -or ([string]$result.Status -eq 'Ok' -and $result.RebootRequired)) {
                $script:NeedsReboot = $true
                Write-Log "$id : reboot required to finish. Verify after reboot."
                continue
            }
            # ErrorAction Stop alone does not cover failure statuses in results.
            if ([string]$result.Status -notin @('Ok', 'NoApplicableUpgrade')) { throw "Update result was $($result.Status)." }
            $after = @(Get-WinGetPackage @query)
            if ($after.Count -ne 1) { throw 'Reader could not be matched after upgrade.' }
            Assert-KnownReaderVersion -Version $after[0].InstalledVersion
            if (@($after[0].AvailableVersions).Count -eq 0 -or $after[0].IsUpdateAvailable) { throw 'Could not verify that no newer update is offered after upgrade.' }
            Write-Log "Verified: $id $($after[0].InstalledVersion); no newer update offered."
        }
        catch { Write-Failure "$id : $($_.Exception.Message)" }
    }
    if ($foundCount -eq 0 -and $script:Failures -eq 0) { Write-Log 'Reader absent from the queried WinGet inventory. Nothing installed.' }
}

try {
    if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use the native 64-bit PowerShell host.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run elevated or as SYSTEM.' }
    $isSystem = $identity.User.Value -eq 'S-1-5-18'
    if ($Engine -eq 'Auto') { $Engine = if ($isSystem) { 'Module' } else { 'CLI' } }
    if ($isSystem -and $Engine -eq 'CLI') { throw 'WinGet CLI is unsupported under SYSTEM. Use Engine Module.' }
    $logDirectory = Join-Path $env:ProgramData 'AdobeReaderWinGet'
    New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
    $script:LogFile = Join-Path $logDirectory 'Update-AdobeReaderWithWinGet.log'
    Write-Log "Begin v1.0.0; engine=$Engine; SYSTEM=$isSystem; CheckOnly=$CheckOnly"
    if ($Engine -eq 'CLI') { Invoke-CliWorkflow } else { Invoke-ModuleWorkflow }
    Write-Log "Finished; failures=$script:Failures; reboot needed=$script:NeedsReboot"
    if ($script:Failures -gt 0) { exit 1 }
    if ($script:NeedsReboot) { exit 3010 }
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
}
