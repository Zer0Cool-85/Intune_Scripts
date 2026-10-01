#requires -Version 5.1
<#
Standalone Intune custom detection; no dependency on the extracted app content.
Exit 0 + STDOUT only when Notepad++ is present and WinGet reports no newer version.
All other outcomes exit 1 without STDOUT/STDERR; diagnostic detail goes to the log.
Uses the WinGet CLI SYSTEM workaround, which Microsoft does not officially support.
#>
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:LogName = 'NotepadPlusPlus-WinGet-Detection.log'

function Get-MachineNotepadPlusPlus {
    # Explicit registry views work from either 32-bit or 64-bit PowerShell.
    $views = @([Microsoft.Win32.RegistryView]::Registry32)
    if ([Environment]::Is64BitOperatingSystem) {
        $views += [Microsoft.Win32.RegistryView]::Registry64
    }
    foreach ($view in $views) {
        $base = $null
        $uninstall = $null
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                [Microsoft.Win32.RegistryHive]::LocalMachine, $view)
            $uninstall = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
            if ($null -eq $uninstall) { continue }
            foreach ($keyName in $uninstall.GetSubKeyNames()) {
                $key = $null
                try {
                    $key = $uninstall.OpenSubKey($keyName)
                    if ($null -eq $key) { continue }
                    $name = [string]$key.GetValue('DisplayName')
                    if ($name -match '^Notepad\+\+(?:\s|$)') {
                        [pscustomobject]@{
                            Name = $name
                            Version = [string]$key.GetValue('DisplayVersion')
                            RegistryView = [string]$view
                            KeyName = $keyName
                        }
                    }
                }
                finally { if ($null -ne $key) { $key.Dispose() } }
            }
        }
        finally {
            if ($null -ne $uninstall) { $uninstall.Dispose() }
            if ($null -ne $base) { $base.Dispose() }
        }
    }
}

function Write-UpdateLog {
    param([string]$Message)
    # Do not leak log messages into Intune detection STDOUT or STDERR.
    try {
        $directory = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
        if (-not (Test-Path -LiteralPath $directory)) {
            $null = New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop
        }
        $path = Join-Path $directory $script:LogName
        if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -gt 2MB) {
            Move-Item -LiteralPath $path -Destination ($path + '.1') -Force -ErrorAction Stop
        }
        $line = '{0} [{1}] {2}{3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $PID, $Message, [Environment]::NewLine
        [IO.File]::AppendAllText($path, $line, [Text.UTF8Encoding]::new($false))
    }
    catch { } # A logging failure must not change the detection result.
}

function Resolve-SystemWinGet {
    # Only search the protected App Installer location; never a user's PATH/profile.
    $programFiles = $env:ProgramW6432
    if ([string]::IsNullOrWhiteSpace($programFiles)) { $programFiles = $env:ProgramFiles }
    $windowsApps = Join-Path $programFiles 'WindowsApps'
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($architecture)) { $architecture = $env:PROCESSOR_ARCHITECTURE }
    $nativeArchitecture = switch ($architecture.ToUpperInvariant()) {
        'AMD64' { 'x64' }
        'ARM64' { 'arm64' }
        'X86'   { 'x86' }
        default { throw "Unsupported processor architecture: $architecture" }
    }
    $candidates = @(
        Get-ChildItem -LiteralPath $windowsApps -Directory -Filter 'Microsoft.DesktopAppInstaller_*' -ErrorAction Stop |
            ForEach-Object {
                if ($_.Name -match '^Microsoft\.DesktopAppInstaller_(?<Version>\d+\.\d+\.\d+\.\d+)_(?<Arch>x64|x86|arm64)__8wekyb3d8bbwe$') {
                    $version = [version]$Matches.Version
                    $arch = $Matches.Arch
                    $exe = Join-Path $_.FullName 'winget.exe'
                    if ($arch -eq $nativeArchitecture -and (Test-Path -LiteralPath $exe -PathType Leaf)) {
                        [pscustomobject]@{ Path = $exe; Version = $version }
                    }
                }
            }
    )
    $latest = $candidates | Sort-Object Version -Descending | Select-Object -First 1
    if ($null -eq $latest) { throw 'WinGet was not found. Deploy or repair Microsoft App Installer first.' }
    return $latest.Path
}

function Invoke-WinGetProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [int]$TimeoutSeconds = 20
    )
    # All arguments in this package are fixed single tokens, with no shell expansion.
    foreach ($argument in $Arguments) {
        if ($argument -match '[\s"]') { throw 'Unexpected whitespace/quote in a WinGet argument.' }
    }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Path
    $start.Arguments = $Arguments -join ' '
    $start.WorkingDirectory = Split-Path -Parent $Path
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        Write-UpdateLog "Running: winget $($start.Arguments)"
        $null = $process.Start()
        # Drain both pipes concurrently to avoid a redirected-output deadlock.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch { }
            throw "WinGet exceeded $TimeoutSeconds seconds. A launched installer may still be running; inspect before retrying manually."
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $code = $process.ExitCode
        $hex = '0x{0:X8}' -f [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$code), 0)
        Write-UpdateLog "Exit $code ($hex). STDOUT: $stdout STDERR: $stderr"
        return [pscustomobject]@{ ExitCode = $code; Hex = $hex; StdOut = $stdout; StdErr = $stderr }
    }
    finally { $process.Dispose() }
}

function Update-WinGetCatalog {
    param([string]$Path, [int]$TimeoutSeconds = 20)
    # Refresh only the winget source; never reset sources or enable a disabled policy.
    $result = Invoke-WinGetProcess -Path $Path -TimeoutSeconds $TimeoutSeconds -Arguments @(
        'source', 'update', '--name', 'winget', '--disable-interactivity'
    )
    if ($result.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($result.StdErr)) {
        throw "WinGet source refresh failed ($($result.Hex)). Check the log and SYSTEM network access."
    }
}

function ConvertFrom-NppList {
    param([Parameter(Mandatory = $true)][string]$Text)
    # Parse only the exact package's row, not localized column names or status text.
    # With --source winget, the source column may be omitted by some client versions.
    $clean = [regex]::Replace($Text, '\x1B\[[0-?]*[ -/]*[@-~]', '')
    $rows = @(
        foreach ($line in ($clean -split '[\r\n]+')) {
            if ($line -match '^.+?[ \t]+Notepad\+\+\.Notepad\+\+[ \t]+(?<Tail>.+?)\s*$') {
                $Matches.Tail.Trim()
            }
        }
    )
    if ($rows.Count -ne 1) {
        throw "Expected exactly one Notepad++.Notepad++ row; found $($rows.Count). WinGet could not uniquely correlate this installation."
    }
    $tokens = @($rows[0] -split '\s+')
    if ($tokens[-1] -eq 'winget') { $tokens = @($tokens | Select-Object -SkipLast 1) }
    if ($tokens.Count -lt 1 -or $tokens.Count -gt 2) { throw 'Unrecognized WinGet table output; refusing to assume compliance.' }
    $installed = $tokens[0]
    $available = $null
    if ($tokens.Count -eq 2) {
        $available = $tokens[1]
        if ($available -notmatch '^\d+(?:\.\d+){1,3}$') { throw "Unrecognized available version: $available" }
    }
    $knownInstalled = $installed -match '^\d+(?:\.\d+){1,3}$'
    # An unknown installed version must never be treated as up to date.
    [pscustomobject]@{
        InstalledVersion = $installed
        AvailableVersion = $available
        NeedsUpdate = (-not $knownInstalled -or $null -ne $available)
    }
}

function Get-NppUpdateState {
    param([string]$Path, [int]$TimeoutSeconds = 20)
    $result = Invoke-WinGetProcess -Path $Path -TimeoutSeconds $TimeoutSeconds -Arguments @(
        'list', '--id', 'Notepad++.Notepad++', '--exact', '--scope', 'machine',
        '--source', 'winget', '--accept-source-agreements', '--disable-interactivity'
    )
    if ($result.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($result.StdErr)) {
        throw "WinGet list failed ($($result.Hex)). Missing packages and source errors are not success."
    }
    return ConvertFrom-NppList -Text $result.StdOut
}

try {
    $installed = @(Get-MachineNotepadPlusPlus)
    if ($installed.Count -eq 0) { exit 1 }
    if ($installed.Count -ne 1) { throw 'Multiple machine-wide Notepad++ registrations exist; resolve the duplicate installations first.' }
    $winget = Resolve-SystemWinGet
    Update-WinGetCatalog -Path $winget -TimeoutSeconds 20
    $state = Get-NppUpdateState -Path $winget -TimeoutSeconds 20
    if ($state.NeedsUpdate) {
        Write-UpdateLog "Update needed: installed=$($state.InstalledVersion); available=$($state.AvailableVersion)"
        exit 1
    }
    Write-Output "Notepad++ $($state.InstalledVersion): no newer version in the refreshed WinGet catalog."
    exit 0
}
catch {
    Write-UpdateLog "Detection could not establish compliance: $($_.Exception.Message)"
    exit 1
}
