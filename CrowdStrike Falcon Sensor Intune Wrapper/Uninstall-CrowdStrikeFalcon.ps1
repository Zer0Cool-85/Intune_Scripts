#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptRoot 'Config.json'
$TenantConfigPath = Join-Path $ScriptRoot 'TenantConfig.json'
$SourceRoot = Join-Path $ScriptRoot 'Files'
$StateRoot = Join-Path $env:ProgramData 'CrowdStrikeFalconIntune'
$StatePath = Join-Path $StateRoot 'InstallState.json'
$LogRoot = Join-Path $StateRoot 'Logs'
$script:FailureExitCode = $null

New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
$LogPath = Join-Path $LogRoot ('Uninstall-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $Line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
    $Line | Out-File -FilePath $LogPath -Append -Encoding utf8
    Write-Host $Line
}

function Get-RequiredProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$SourceName
    )

    $Property = $Object.PSObject.Properties[$Name]
    if ($null -eq $Property) { throw "$SourceName is missing required setting '$Name'." }
    return $Property.Value
}

function Get-NormalizedVersion {
    param([Parameter(Mandatory = $true)][string]$Value)

    $Match = [regex]::Match($Value, '(?<!\d)\d+(?:\.\d+){2,5}(?!\d)')
    if (-not $Match.Success) { throw "Unable to read a numeric version from '$Value'." }
    $Parts = @($Match.Value.Split('.') | ForEach-Object { [uint64]$_ })
    return ($Parts -join '.')
}

function Compare-VersionString {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    $LeftVersion = Get-NormalizedVersion -Value $Left
    $RightVersion = Get-NormalizedVersion -Value $Right
    $LeftParts = @($LeftVersion.Split('.') | ForEach-Object { [uint64]$_ })
    $RightParts = @($RightVersion.Split('.') | ForEach-Object { [uint64]$_ })
    $PartCount = [Math]::Max($LeftParts.Count, $RightParts.Count)
    for ($Index = 0; $Index -lt $PartCount; $Index++) {
        $LeftPart = if ($Index -lt $LeftParts.Count) { $LeftParts[$Index] } else { [uint64]0 }
        $RightPart = if ($Index -lt $RightParts.Count) { $RightParts[$Index] } else { [uint64]0 }
        if ($LeftPart -gt $RightPart) { return 1 }
        if ($LeftPart -lt $RightPart) { return -1 }
    }
    return 0
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)

    $Sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return ([System.BitConverter]::ToString($Sha256.ComputeHash($Bytes))).Replace('-', '')
    }
    finally {
        $Sha256.Dispose()
    }
}

function Get-NormalizedCid {
    param([Parameter(Mandatory = $true)][string]$Cid)

    if ($Cid -notmatch '^[A-Fa-f0-9]{32}-[A-Fa-f0-9]{2}$') {
        throw 'TenantConfig.json CID must contain 32 hexadecimal characters, a hyphen, and the two-character checksum.'
    }
    return $Cid.Substring(0, 32).ToLowerInvariant()
}

function Get-InstalledCid {
    $Locations = @(
        'SYSTEM\CrowdStrike\{9b03c1d9-3138-44ed-9fae-d9f4c034b88d}\{16e0423f-7058-48c9-a204-725362b67639}\Default',
        'SYSTEM\CurrentControlSet\Services\CSAgent\Sim'
    )

    $BaseKey = $null
    try {
        $BaseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64
        )
        foreach ($Location in $Locations) {
            $Key = $null
            try {
                $Key = $BaseKey.OpenSubKey($Location)
                if ($null -eq $Key) { continue }
                $Value = $Key.GetValue('CU', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                if ($Value -is [byte[]]) {
                    $HexValue = (($Value | ForEach-Object { $_.ToString('x2') }) -join '')
                    if ($HexValue.Length -ge 32) { return $HexValue.Substring(0, 32).ToLowerInvariant() }
                }
                elseif ($null -ne $Value) {
                    $HexValue = ([string]$Value) -replace '[^A-Fa-f0-9]', ''
                    if ($HexValue.Length -ge 32) { return $HexValue.Substring(0, 32).ToLowerInvariant() }
                }
            }
            finally {
                if ($null -ne $Key) { $Key.Dispose() }
            }
        }
    }
    finally {
        if ($null -ne $BaseKey) { $BaseKey.Dispose() }
    }

    return $null
}

function Get-FalconUninstallEntries {
    $Entries = @()
    $UninstallPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    foreach ($View in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
        $BaseKey = $null
        $UninstallKey = $null
        try {
            $BaseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $View)
            $UninstallKey = $BaseKey.OpenSubKey($UninstallPath)
            if ($null -eq $UninstallKey) { continue }

            foreach ($SubKeyName in $UninstallKey.GetSubKeyNames()) {
                $ProductKey = $null
                try {
                    $ProductKey = $UninstallKey.OpenSubKey($SubKeyName)
                    if ($null -eq $ProductKey) { continue }
                    $DisplayName = [string]$ProductKey.GetValue('DisplayName')
                    $Publisher = [string]$ProductKey.GetValue('Publisher')
                    $IsFalconSensor = (
                        $DisplayName -match '(?i)^CrowdStrike (?:(?:Falcon|Windows) )?Sensor(?: Platform)?(?:\s.*)?$' -or
                        ($Publisher -match '(?i)CrowdStrike' -and $DisplayName -match '(?i)^(?:Falcon|Windows) Sensor(?:\s.*)?$')
                    )
                    if (-not $IsFalconSensor) { continue }

                    $Entries += [pscustomobject]@{
                        RegistryView         = [string]$View
                        KeyName              = $SubKeyName
                        DisplayName          = $DisplayName
                        DisplayVersion       = [string]$ProductKey.GetValue('DisplayVersion')
                        Publisher            = $Publisher
                        QuietUninstallString = [string]$ProductKey.GetValue('QuietUninstallString')
                        UninstallString      = [string]$ProductKey.GetValue('UninstallString')
                        ModifyPath           = [string]$ProductKey.GetValue('ModifyPath')
                        BundleCachePath      = [string]$ProductKey.GetValue('BundleCachePath')
                    }
                }
                finally {
                    if ($null -ne $ProductKey) { $ProductKey.Dispose() }
                }
            }
        }
        finally {
            if ($null -ne $UninstallKey) { $UninstallKey.Dispose() }
            if ($null -ne $BaseKey) { $BaseKey.Dispose() }
        }
    }

    return @($Entries | Sort-Object RegistryView, KeyName -Unique)
}

function Get-ExecutableFromCommandLine {
    param([Parameter(Mandatory = $true)][string]$CommandLine)

    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    $Expanded = [Environment]::ExpandEnvironmentVariables($CommandLine.Trim())
    if ($Expanded -match '^"([^"]+\.exe)"') { return $Matches[1] }
    if ($Expanded -match '^(.*?\.exe)(?:\s|$)') { return $Matches[1].Trim() }
    return $null
}

function Assert-CrowdStrikeSignature {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($Signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
        $null -eq $Signature.SignerCertificate -or
        $Signature.SignerCertificate.Subject -notmatch '(?i)CrowdStrike') {
        throw "Refusing to execute '$Path' because it does not have a valid CrowdStrike Authenticode signature."
    }
}

function Get-UninstallTool {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Entries,
        [Parameter(Mandatory = $true)][bool]$AllowPackagedFallback
    )

    $BestEntry = $null
    $BestVersion = $null
    foreach ($Entry in $Entries) {
        if ([string]::IsNullOrWhiteSpace([string]$Entry.DisplayVersion)) { continue }
        try { $EntryVersion = Get-NormalizedVersion -Value ([string]$Entry.DisplayVersion) } catch { continue }
        if ($null -eq $BestEntry -or (Compare-VersionString -Left $EntryVersion -Right $BestVersion) -gt 0) {
            $BestEntry = $Entry
            $BestVersion = $EntryVersion
        }
    }

    $EntriesToInspect = @()
    if ($null -ne $BestEntry) { $EntriesToInspect += $BestEntry }
    $EntriesToInspect += @($Entries | Where-Object {
        $null -eq $BestEntry -or
        $_.RegistryView -ne $BestEntry.RegistryView -or
        $_.KeyName -ne $BestEntry.KeyName
    })

    foreach ($Entry in $EntriesToInspect) {
        foreach ($CommandLine in @(
            [string]$Entry.QuietUninstallString,
            [string]$Entry.UninstallString,
            [string]$Entry.ModifyPath,
            [string]$Entry.BundleCachePath
        )) {
            if ([string]::IsNullOrWhiteSpace($CommandLine)) { continue }
            $ExecutablePath = Get-ExecutableFromCommandLine -CommandLine $CommandLine
            if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { continue }
            if ([IO.Path]::GetFileName($ExecutablePath) -match '(?i)^msiexec\.exe$') { continue }
            if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) { continue }

            Assert-CrowdStrikeSignature -Path $ExecutablePath
            return [pscustomobject]@{
                Path = $ExecutablePath
                Mode = if ([IO.Path]::GetFileName($ExecutablePath) -match '(?i)^CsUninstallTool\.exe$') { 'Standalone' } else { 'SensorInstaller' }
                Source = 'InstalledCache'
            }
        }
    }

    if ($AllowPackagedFallback) {
        $Candidates = @(Get-ChildItem -LiteralPath $SourceRoot -File -Filter '*.exe')
        if ($Candidates.Count -ne 1) {
            throw "Packaged-installer uninstall fallback is enabled, but exactly one EXE was not found in '$SourceRoot'."
        }
        Assert-CrowdStrikeSignature -Path $Candidates[0].FullName
        return [pscustomobject]@{
            Path   = $Candidates[0].FullName
            Mode   = 'SensorInstaller'
            Source = 'PackagedInstaller'
        }
    }

    throw 'The installed CrowdStrike uninstall cache could not be located. The packaged-installer fallback is disabled to prevent an older cached Intune payload from uninstalling a newer sensor.'
}

function Test-SensorPresent {
    if ($null -ne (Get-Service -Name 'CSFalconService' -ErrorAction SilentlyContinue)) { return $true }
    if ($null -ne (Get-Service -Name 'csagent' -ErrorAction SilentlyContinue)) { return $true }
    if (@(Get-FalconUninstallEntries).Count -gt 0) { return $true }
    return $false
}

try {
    Write-Log 'Starting CrowdStrike Falcon Sensor uninstall wrapper.'

    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This uninstaller must run elevated. Configure the Intune app to install in System context.'
    }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        throw 'This wrapper must run in 64-bit PowerShell. Use the SysNative Intune uninstall command documented in README.md.'
    }
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Configuration file not found: '$ConfigPath'." }
    if (-not (Test-Path -LiteralPath $TenantConfigPath -PathType Leaf)) { throw "Tenant configuration file not found: '$TenantConfigPath'." }
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        throw "Wrapper state file is missing: '$StatePath'. Refusing an untracked removal of endpoint protection."
    }

    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $TenantConfig = Get-Content -LiteralPath $TenantConfigPath -Raw | ConvertFrom-Json
    $State = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json

    $PackageRevision = [string](Get-RequiredProperty -Object $Config -Name 'PackageRevision' -SourceName 'Config.json')
    $EnableUninstall = Get-RequiredProperty -Object $Config -Name 'EnableUninstall' -SourceName 'Config.json'
    $AllowPackagedInstallerForUninstall = Get-RequiredProperty -Object $Config -Name 'AllowPackagedInstallerForUninstall' -SourceName 'Config.json'
    $InstallerBusyRetryCount = [int](Get-RequiredProperty -Object $Config -Name 'InstallerBusyRetryCount' -SourceName 'Config.json')
    $InstallerBusyRetryDelaySeconds = [int](Get-RequiredProperty -Object $Config -Name 'InstallerBusyRetryDelaySeconds' -SourceName 'Config.json')

    if ($EnableUninstall -isnot [bool] -or $AllowPackagedInstallerForUninstall -isnot [bool]) {
        throw 'EnableUninstall and AllowPackagedInstallerForUninstall must be JSON booleans.'
    }
    if (-not $EnableUninstall) {
        throw 'Uninstall is disabled in Config.json. This safeguard prevents an accidental Intune uninstall assignment from removing endpoint protection.'
    }
    if ($InstallerBusyRetryCount -lt 0 -or $InstallerBusyRetryCount -gt 20) {
        throw 'InstallerBusyRetryCount must be between 0 and 20.'
    }
    if ($InstallerBusyRetryDelaySeconds -lt 1 -or $InstallerBusyRetryDelaySeconds -gt 300) {
        throw 'InstallerBusyRetryDelaySeconds must be between 1 and 300.'
    }
    if ([int]$State.SchemaVersion -ne 1) { throw 'InstallState.json has an unsupported schema version.' }
    if ([string]$State.PackageRevision -ne $PackageRevision) {
        throw "Installed wrapper revision '$($State.PackageRevision)' does not match this uninstall payload '$PackageRevision'. Refusing to let an older or different package remove the sensor."
    }

    $Cid = [string](Get-RequiredProperty -Object $TenantConfig -Name 'CID' -SourceName 'TenantConfig.json')
    $null = Get-RequiredProperty -Object $TenantConfig -Name 'ProvisioningToken' -SourceName 'TenantConfig.json'
    $MaintenanceToken = [string](Get-RequiredProperty -Object $TenantConfig -Name 'MaintenanceToken' -SourceName 'TenantConfig.json')
    $NormalizedCid = Get-NormalizedCid -Cid $Cid
    $ConfiguredCidHash = Get-TextSha256 -Value $NormalizedCid

    if ($ConfiguredCidHash -ne [string]$State.CidSha256) {
        throw 'TenantConfig.json CID does not match the CID recorded by the successful install wrapper.'
    }
    if (-not [string]::IsNullOrWhiteSpace($MaintenanceToken) -and $MaintenanceToken -match '[\s"]') {
        throw 'MaintenanceToken cannot contain whitespace or double-quote characters.'
    }

    if (-not (Test-SensorPresent)) {
        Remove-Item -LiteralPath $StatePath -Force
        Write-Log 'The Falcon sensor is already absent. Removed the stale wrapper state file.'
        exit 0
    }

    if ([bool]$State.RequireTenantMatch) {
        $InstalledCid = Get-InstalledCid
        if ([string]::IsNullOrWhiteSpace($InstalledCid)) {
            throw 'The installed Falcon sensor CID could not be read. Refusing to remove endpoint protection whose tenant ownership cannot be verified.'
        }
        if ((Get-TextSha256 -Value $InstalledCid) -ne [string]$State.CidSha256) {
            throw 'The installed Falcon sensor CID does not match the wrapper state. Refusing to remove a sensor from a different tenant.'
        }
    }

    $Entries = @(Get-FalconUninstallEntries)
    $UninstallTool = Get-UninstallTool -Entries $Entries -AllowPackagedFallback ([bool]$AllowPackagedInstallerForUninstall)
    Write-Log "Using the CrowdStrike $($UninstallTool.Source) uninstall executable. Sensitive arguments are redacted."

    $Arguments = @('/quiet', '/norestart')
    if ($UninstallTool.Mode -eq 'SensorInstaller') { $Arguments = @('/uninstall') + $Arguments }
    if (-not [string]::IsNullOrWhiteSpace($MaintenanceToken)) {
        $Arguments += "MAINTENANCE_TOKEN=$MaintenanceToken"
    }
    $ArgumentString = $Arguments -join ' '

    $ExitCode = $null
    for ($Attempt = 1; $Attempt -le ($InstallerBusyRetryCount + 1); $Attempt++) {
        Write-Log "Running the CrowdStrike uninstaller (attempt $Attempt)."
        $Process = Start-Process `
            -FilePath $UninstallTool.Path `
            -ArgumentList $ArgumentString `
            -WorkingDirectory (Split-Path -Parent $UninstallTool.Path) `
            -WindowStyle Hidden `
            -Wait `
            -PassThru
        $ExitCode = [int]$Process.ExitCode

        if ($ExitCode -eq 1618 -and $Attempt -le $InstallerBusyRetryCount) {
            Write-Log "Another installation is active. Retrying in $InstallerBusyRetryDelaySeconds seconds." 'WARN'
            Start-Sleep -Seconds $InstallerBusyRetryDelaySeconds
            continue
        }
        break
    }

    if ($ExitCode -eq 106) {
        $script:FailureExitCode = 106
        throw 'CrowdStrike uninstall protection is enabled. Supply the correct maintenance token or temporarily use a CrowdStrike policy that permits uninstall.'
    }
    if ($ExitCode -notin @(0, 1641, 3010)) {
        $script:FailureExitCode = $ExitCode
        throw "CrowdStrike uninstaller failed with exit code $ExitCode."
    }

    if ($ExitCode -eq 0) {
        $Deadline = (Get-Date).AddSeconds(120)
        while ((Get-Date) -lt $Deadline -and (Test-SensorPresent)) {
            Start-Sleep -Seconds 5
        }
        if (Test-SensorPresent) {
            throw 'The uninstaller returned success, but Falcon service or registry evidence remains after 120 seconds.'
        }
    }

    Remove-Item -LiteralPath $StatePath -Force
    Write-Log "CrowdStrike Falcon Sensor wrapper revision $PackageRevision uninstalled successfully with exit code $ExitCode."
    exit $ExitCode
}
catch {
    $FailureCode = 1
    if ($null -ne $script:FailureExitCode) {
        $FailureCode = [int]$script:FailureExitCode
    }
    elseif ($_.Exception.Data.Contains('ExitCode')) {
        $FailureCode = [int]$_.Exception.Data['ExitCode']
    }

    Write-Log $_.Exception.Message 'ERROR'
    exit $FailureCode
}
