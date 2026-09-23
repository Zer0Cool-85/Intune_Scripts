#Requires -Version 5.1
<#
.SYNOPSIS
Updates an existing Adobe Reader installation using WinGet. Never installs Reader when absent.
.DESCRIPTION
Version 1.1.0. Windows PowerShell 5.1 or PowerShell 7; native 64-bit on 64-bit Windows.

Uses winget.exe directly in both user and SYSTEM execution contexts. Resolves
the current account's command path, registered App Installer package paths,
then matching WindowsApps package directories as a fallback. Candidates are
ordered by context, architecture preference, and numeric package version.
Each candidate must successfully run --version before it is selected.
No Microsoft.WinGet.Client module is installed or required.

Uses winget list, exact Reader package IDs, list --upgrade-available, then
winget upgrade. It parses the exact ID and installed version from the table;
WinGet performs the version comparison. No fixed column offsets or translated
column labels are used. Truncated/unrecognized results fail instead of guessing.

Direct CLI use under SYSTEM is a practical workaround, not Microsoft's supported
SYSTEM interface. Resolving an executable does not impersonate its registered
user or fix missing dependencies/sources/policies. Subsequent command failures
are reported. App Installer/WinGet must already be installed and functional.
No WindowsApps permissions or package registrations are changed.

Only these IDs from the winget community source are eligible:
  Adobe.Acrobat.Reader.64-bit
  Adobe.Acrobat.Reader.32-bit
Store-installed or migrated copies work if WinGet correlates their installation
with one of those IDs. Unmapped Reader/generic Acrobat candidates are reported
for review, never installed over. Default Scope machine targets machine-wide
Reader. Scope user is for the current user only and cannot be used as SYSTEM;
the installer must support that scope. This is not an Acrobat Pro updater.

Latest means the newest applicable version WinGet offers from its catalog,
which can lag Adobe's releases. The script refreshes the winget source first.
Unknown installed versions,
blocked upgrades, source failures and failed verification are not success.
No --force, --include-unknown upgrade, hash bypass, or reboot request is used.

EXIT CODES
  0    Reader absent, no update offered, or update verified with WinGet.
       With -CheckOnly, 0 also includes an update available but not installed.
  1    Prerequisite, matching, source, update, or verification failure.
  3010 Update reports a reboot needed to finish. Recheck after a managed reboot.
       Intune Win32 apps can map 3010 to soft reboot. Platform scripts treat
       nonzero as failure; account for that if using Platform scripts.

LOG: %ProgramData%\AdobeReaderWinGet\Update-AdobeReaderWithWinGet.log for
SYSTEM/elevated runs; %LOCALAPPDATA%\AdobeReaderWinGet for standard-user runs.
CheckOnly still writes logs and can refresh WinGet metadata; it does not update Reader.

INTUNE: Run as SYSTEM, 64-bit host, default Scope machine. Pilot the direct
CLI path in SYSTEM context. Platform scripts are not a recurring patch schedule.

.PARAMETER Engine
CLI (default) or Auto. Both use CLI; Auto is retained for old command lines.
.PARAMETER Scope
machine (default) or user. Machine updates require elevation; CheckOnly may run
without elevation. User scope operates only on the account running this script.
.PARAMETER CheckOnly
Report installed packages and upgrade availability without upgrading Reader.
.EXAMPLE
.\Update-AdobeReaderWithWinGet.ps1 -Engine CLI -CheckOnly
.EXAMPLE
.\Update-AdobeReaderWithWinGet.ps1 -Engine CLI
.EXAMPLE
.\Update-AdobeReaderWithWinGet.ps1 -CheckOnly
.EXAMPLE
.\Update-AdobeReaderWithWinGet.ps1 -Scope user -CheckOnly
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
    [ValidateSet('Auto', 'CLI')]
    [string]$Engine = 'CLI',
    [ValidateSet('machine', 'user')]
    [string]$Scope = 'machine',
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

function Invoke-WinGetProcess {
    param([string]$Path, [string[]]$Arguments, [int]$TimeoutSeconds = 0)
    # All arguments are internal fixed tokens/allowlisted IDs without spaces.
    # Process APIs capture both streams without PowerShell 5.1 native-stderr traps.
    if (@($Arguments | Where-Object { $_ -match '[\s"]' }).Count -gt 0) {
        throw 'Unexpected argument requiring quoting.'
    }
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Path
    $info.WorkingDirectory = Split-Path -Path $Path -Parent
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
        if ($TimeoutSeconds -gt 0) {
            if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
                try { $process.Kill() } catch { }
                throw "WinGet executable probe timed out after $TimeoutSeconds seconds."
            }
        }
        else { $process.WaitForExit() }
        $exitCode = $process.ExitCode
        $text = $stdout.GetAwaiter().GetResult() + [Environment]::NewLine + $stderr.GetAwaiter().GetResult()
        $text = $text -replace '\x1B\[[0-?]*[ -/]*[@-~]', ''
        $hex = Get-ExitHex -Code $exitCode
        [pscustomobject]@{ Code = $exitCode; Hex = $hex; Text = $text }
    }
    finally { $process.Dispose() }
}

function Resolve-WinGetPath {
    param([bool]$IsSystem, [bool]$IsElevated)

    $architecture = if ($env:PROCESSOR_ARCHITEW6432) {
        $env:PROCESSOR_ARCHITEW6432
    }
    else { $env:PROCESSOR_ARCHITECTURE }
    $architectureOrder = switch ($architecture.ToUpperInvariant()) {
        'ARM64' { @('arm64', 'x64', 'x86', 'neutral') }
        'AMD64' { @('x64', 'x86', 'neutral') }
        default { @('x86', 'neutral') }
    }
    $candidates = @(
        # SYSTEM must not borrow another user's execution alias. Direct package
        # paths below are launched with the current token, without impersonation.
        if (-not $IsSystem) {
            foreach ($command in @(Get-Command -Name winget.exe -CommandType Application -All -ErrorAction SilentlyContinue)) {
                [pscustomobject]@{ Path = $command.Source; Priority = 0; ArchitectureRank = 0; Version = [version]'0.0'; Origin = 'Current account command' }
            }
        }

        # Get-AppxPackage may be unavailable in some PowerShell environments;
        # the directory fallback does not depend on the Appx module.
        if (Get-Command -Name Get-AppxPackage -ErrorAction SilentlyContinue) {
            $queries = @()
            if (-not $IsSystem) { $queries += [pscustomobject]@{ AllUsers = $false; Priority = 1 } }
            if ($IsElevated) { $queries += [pscustomobject]@{ AllUsers = $true; Priority = 2 } }
            foreach ($query in $queries) {
                try {
                    $appxArgs = @{ Name = 'Microsoft.DesktopAppInstaller'; ErrorAction = 'Stop' }
                    if ($query.AllUsers) { $appxArgs.AllUsers = $true }
                    foreach ($package in @(Get-AppxPackage @appxArgs)) {
                        if ($package.PackageFamilyName -ne 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe') { continue }
                        $packageArchitecture = ([string]$package.Architecture).ToLowerInvariant()
                        if ($packageArchitecture -notin $architectureOrder -or -not $package.InstallLocation) { continue }
                        [pscustomobject]@{
                            Path = Join-Path -Path $package.InstallLocation -ChildPath 'winget.exe'
                            Priority = $query.Priority
                            ArchitectureRank = [array]::IndexOf($architectureOrder, $packageArchitecture)
                            Version = [version]$package.Version
                            Origin = 'App Installer registration'
                        }
                    }
                }
                catch { Write-Log "App Installer discovery unavailable for this query: $($_.Exception.Message)" }
            }
        }

        $programDirectories = @(@($env:ProgramW6432, $env:ProgramFiles) | Where-Object { $_ } | Select-Object -Unique)
        foreach ($programDirectory in $programDirectories) {
            $windowsApps = Join-Path -Path $programDirectory -ChildPath 'WindowsApps'
            try {
                if (-not (Test-Path -LiteralPath $windowsApps -PathType Container)) { continue }
                $folders = @(Get-ChildItem -LiteralPath $windowsApps -Directory -Filter 'Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe' -ErrorAction Stop)
                foreach ($folder in $folders) {
                    if ($folder.Name -notmatch '^Microsoft\.DesktopAppInstaller_(?<PackageVersion>\d+\.\d+\.\d+\.\d+)_(?<Architecture>x64|x86|arm64|neutral)__8wekyb3d8bbwe$') { continue }
                    $folderVersion = [version]$Matches.PackageVersion
                    $folderArchitecture = $Matches.Architecture.ToLowerInvariant()
                    if ($folderArchitecture -notin $architectureOrder) { continue }
                    [pscustomobject]@{
                        Path = Join-Path -Path $folder.FullName -ChildPath 'winget.exe'
                        Priority = 3
                        ArchitectureRank = [array]::IndexOf($architectureOrder, $folderArchitecture)
                        Version = $folderVersion
                        Origin = 'WindowsApps directory'
                    }
                }
            }
            catch { Write-Log "WindowsApps discovery unavailable: $($_.Exception.Message)" }
        }
    )
    $sortProperties = @('Priority', 'ArchitectureRank', @{ Expression = { $_.Version }; Descending = $true })
    $seen = @{}
    foreach ($candidate in @($candidates | Sort-Object -Property $sortProperties)) {
        if (-not $candidate.Path -or $seen.ContainsKey($candidate.Path)) { continue }
        $seen[$candidate.Path] = $true
        try {
            if (-not (Test-Path -LiteralPath $candidate.Path -PathType Leaf)) { continue }
            $probe = Invoke-WinGetProcess -Path $candidate.Path -Arguments @('--version') -TimeoutSeconds 15
            if ($probe.Code -ne 0 -or $probe.Text.Trim() -notmatch '^v?\d+(\.\d+)+') {
                Write-Log "Rejected WinGet candidate: $($candidate.Path); exit=$($probe.Hex); $($probe.Text.Trim())"
                continue
            }
            Write-Log "Resolved WinGet: $($candidate.Path); version=$($probe.Text.Trim()); via=$($candidate.Origin)"
            return $candidate.Path
        }
        catch { Write-Log "WinGet candidate failed: $($candidate.Path); $($_.Exception.Message)" }
    }
    throw 'No working winget.exe was found for this execution context. Verify App Installer and its dependencies.'
}

function Invoke-WinGetCli {
    param([string[]]$Arguments)
    Write-Log ('winget ' + ($Arguments -join ' '))
    $result = Invoke-WinGetProcess -Path $script:WinGetPath -Arguments $Arguments
    Write-Log $result.Text.Trim()
    Write-Log "WinGet exit: $($result.Code) ($($result.Hex))"
    return $result
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
    $result = Invoke-WinGetCli -Arguments @('list', '--id', $Id, '--exact', '--source', $sourceName, '--scope', $Scope, '--upgrade-available', '--include-unknown', '--include-pinned', '--accept-source-agreements', '--disable-interactivity')
    if ($result.Hex -in @('0x8A150014', '0x8A15002B')) { return }
    if ($result.Code -ne 0) { throw "Upgrade query failed: $($result.Hex)" }
    $rows = @(Get-CliReaderRow -Text $result.Text -Id $Id)
    if ($rows.Count -eq 0 -and @((Get-CliDataLines -Text $result.Text) | Where-Object { $_ -match '^Adobe\b' }).Count -gt 0) {
        throw 'Upgrade table is unrecognized or truncated. Inspect the logged output; no upgrade decision was made.'
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
    $refresh = Invoke-WinGetCli -Arguments @('source', 'update', '--name', $sourceName, '--disable-interactivity')
    if ($refresh.Code -ne 0) { throw "WinGet source refresh failed: $($refresh.Hex)" }

    # Also inspect broad inventory for Reader entries which cannot be correlated
    # to the two allowed IDs, instead of reporting those as Reader absent.
    $inventory = Invoke-WinGetCli -Arguments @('list', '--query', 'Adobe', '--source', $sourceName, '--scope', $Scope, '--accept-source-agreements', '--disable-interactivity')
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
            $queryArgs = @('list', '--id', $id, '--exact', '--source', $sourceName, '--scope', $Scope, '--accept-source-agreements', '--disable-interactivity')
            $installed = Invoke-WinGetCli -Arguments $queryArgs
            if ($installed.Hex -eq '0x8A150014') { continue }
            if ($installed.Code -ne 0) { throw "Installed query failed: $($installed.Hex)" }
            $rows = @(Get-CliReaderRow -Text $installed.Text -Id $id)
            if ($rows.Count -ne 1) { throw 'Expected one exact installed match; inspect the log for an ambiguous/truncated table.' }
            $foundCount++
            Assert-KnownReaderVersion -Version $rows[0].InstalledVersion
            Write-Log "Installed: $id $($rows[0].InstalledVersion)"
            $updates = @(Get-CliUpgradeRows -Id $id)
            if ($updates.Count -eq 0) { Write-Log "$id : no newer update offered by WinGet."; continue }
            if ($updates.Count -ne 1) { throw 'Multiple upgrade matches; no installer started.' }
            Write-Log ('Upgrade candidate: ' + $updates[0].Row)
            if ($CheckOnly) { Write-Log 'CheckOnly: update not installed.'; continue }

            $upgrade = Invoke-WinGetCli -Arguments @('upgrade', '--id', $id, '--exact', '--source', $sourceName, '--scope', $Scope, '--silent', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
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
    if ($foundCount -eq 0 -and $script:Failures -eq 0) { Write-Log "Reader absent from the queried $Scope inventory. Nothing installed." }
}

try {
    if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use the native 64-bit PowerShell host.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $isSystem = $identity.User.Value -eq 'S-1-5-18'
    if ($Scope -eq 'machine' -and -not $isElevated -and -not $CheckOnly) { throw 'Machine-scope updates require elevation or SYSTEM.' }
    if ($isSystem -and $Scope -eq 'user') { throw 'User scope requires running as that user. A resolved path does not switch execution accounts.' }
    $Engine = 'CLI'
    $logRoot = if ($isElevated) { $env:ProgramData } else { $env:LOCALAPPDATA }
    $logDirectory = Join-Path $logRoot 'AdobeReaderWinGet'
    New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
    $script:LogFile = Join-Path $logDirectory 'Update-AdobeReaderWithWinGet.log'
    Write-Log "Begin v1.1.0; engine=$Engine; SYSTEM=$isSystem; scope=$Scope; CheckOnly=$CheckOnly"
    $script:WinGetPath = Resolve-WinGetPath -IsSystem $isSystem -IsElevated $isElevated
    Invoke-CliWorkflow
    Write-Log "Finished; failures=$script:Failures; reboot needed=$script:NeedsReboot"
    if ($script:Failures -gt 0) { exit 1 }
    if ($script:NeedsReboot) { exit 3010 }
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
}
