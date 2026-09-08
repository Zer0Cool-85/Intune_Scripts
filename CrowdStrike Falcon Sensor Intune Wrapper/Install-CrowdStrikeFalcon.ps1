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
$LogPath = Join-Path $LogRoot ('Install-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

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
    if ($null -eq $Property) {
        throw "$SourceName is missing required setting '$Name'."
    }

    return $Property.Value
}

function Assert-BooleanSetting {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Value -isnot [bool]) {
        throw "Config setting '$Name' must be true or false without quotation marks."
    }
}

function Get-NormalizedVersion {
    param([Parameter(Mandatory = $true)][string]$Value)

    $Match = [regex]::Match($Value, '(?<!\d)\d+(?:\.\d+){2,5}(?!\d)')
    if (-not $Match.Success) {
        throw "Unable to read a numeric version from '$Value'."
    }

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
                    if ($HexValue.Length -ge 32) {
                        return $HexValue.Substring(0, 32).ToLowerInvariant()
                    }
                }
                elseif ($null -ne $Value) {
                    $HexValue = ([string]$Value) -replace '[^A-Fa-f0-9]', ''
                    if ($HexValue.Length -ge 32) {
                        return $HexValue.Substring(0, 32).ToLowerInvariant()
                    }
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
    $Views = @(
        [Microsoft.Win32.RegistryView]::Registry64,
        [Microsoft.Win32.RegistryView]::Registry32
    )

    foreach ($View in $Views) {
        $BaseKey = $null
        $UninstallKey = $null
        try {
            $BaseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                [Microsoft.Win32.RegistryHive]::LocalMachine,
                $View
            )
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
                        RegistryView        = [string]$View
                        KeyName             = $SubKeyName
                        DisplayName         = $DisplayName
                        DisplayVersion      = [string]$ProductKey.GetValue('DisplayVersion')
                        Publisher           = $Publisher
                        UninstallString     = [string]$ProductKey.GetValue('UninstallString')
                        QuietUninstallString = [string]$ProductKey.GetValue('QuietUninstallString')
                        ModifyPath          = [string]$ProductKey.GetValue('ModifyPath')
                        BundleCachePath     = [string]$ProductKey.GetValue('BundleCachePath')
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

function Get-ServiceExecutablePath {
    param([Parameter(Mandatory = $true)][string]$ServiceName)

    $ServiceKeyPath = 'SYSTEM\CurrentControlSet\Services\{0}' -f $ServiceName
    $BaseKey = $null
    $ServiceKey = $null
    try {
        $BaseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64
        )
        $ServiceKey = $BaseKey.OpenSubKey($ServiceKeyPath)
        if ($null -eq $ServiceKey) { return $null }

        $ImagePath = [string]$ServiceKey.GetValue('ImagePath', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ([string]::IsNullOrWhiteSpace($ImagePath)) { return $null }

        $ExpandedPath = [Environment]::ExpandEnvironmentVariables($ImagePath.Trim())
        if ($ExpandedPath.StartsWith('\??\', [StringComparison]::Ordinal)) {
            $ExpandedPath = $ExpandedPath.Substring(4)
        }
        if ($ExpandedPath -match '(?i)^\\SystemRoot\\') {
            $ExpandedPath = Join-Path $env:SystemRoot $ExpandedPath.Substring(12)
        }

        if ($ExpandedPath -match '^"([^"]+\.exe)"') {
            return $Matches[1]
        }
        if ($ExpandedPath -match '^(.*?\.exe)(?:\s|$)') {
            return $Matches[1].Trim()
        }
    }
    finally {
        if ($null -ne $ServiceKey) { $ServiceKey.Dispose() }
        if ($null -ne $BaseKey) { $BaseKey.Dispose() }
    }

    return $null
}

function Get-VersionFromFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }

    $VersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    foreach ($Candidate in @([string]$VersionInfo.ProductVersion, [string]$VersionInfo.FileVersion)) {
        if ([string]::IsNullOrWhiteSpace($Candidate)) { continue }
        try {
            return Get-NormalizedVersion -Value $Candidate
        }
        catch {
            continue
        }
    }

    return $null
}

function Get-InstalledFalconSensor {
    $Service = Get-Service -Name 'CSFalconService' -ErrorAction SilentlyContinue
    $ServicePath = Get-ServiceExecutablePath -ServiceName 'CSFalconService'
    $Entries = @(Get-FalconUninstallEntries)
    $EvidencePresent = ($null -ne $Service -or $Entries.Count -gt 0 -or
        (-not [string]::IsNullOrWhiteSpace($ServicePath) -and (Test-Path -LiteralPath $ServicePath -PathType Leaf)))

    if (-not $EvidencePresent) { return $null }

    $BinaryVersion = $null
    if (-not [string]::IsNullOrWhiteSpace($ServicePath)) {
        $BinaryVersion = Get-VersionFromFile -Path $ServicePath
    }

    $HighestEntry = $null
    $HighestEntryVersion = $null
    foreach ($Entry in $Entries) {
        if ([string]::IsNullOrWhiteSpace($Entry.DisplayVersion)) { continue }
        try {
            $EntryVersion = Get-NormalizedVersion -Value $Entry.DisplayVersion
        }
        catch {
            continue
        }

        if ($null -eq $HighestEntry -or
            (Compare-VersionString -Left $EntryVersion -Right $HighestEntryVersion) -gt 0) {
            $HighestEntry = $Entry
            $HighestEntryVersion = $EntryVersion
        }
    }

    $InstalledVersion = if ($null -ne $BinaryVersion) { $BinaryVersion } else { $HighestEntryVersion }
    if ([string]::IsNullOrWhiteSpace($InstalledVersion)) {
        throw 'CrowdStrike installation evidence was found, but its installed version could not be determined. Refusing to run the installer because downgrade safety cannot be evaluated.'
    }

    return [pscustomobject]@{
        Version              = $InstalledVersion
        VersionSource        = if ($null -ne $BinaryVersion) { 'CSFalconService binary' } else { 'uninstall registry' }
        BinaryPath           = $ServicePath
        BinaryVersion        = $BinaryVersion
        RegistryVersion      = $HighestEntryVersion
        UninstallEntry       = $HighestEntry
    }
}

function Get-FalconHealth {
    param([Parameter(Mandatory = $true)][bool]$RequireRunning)

    $Issues = @()
    foreach ($ServiceName in @('CSFalconService', 'csagent')) {
        $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($null -eq $Service) {
            $Issues += "service '$ServiceName' is missing"
        }
        elseif ($RequireRunning -and $Service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
            $Issues += "service '$ServiceName' is $($Service.Status)"
        }
    }

    $BinaryPath = Get-ServiceExecutablePath -ServiceName 'CSFalconService'
    if ([string]::IsNullOrWhiteSpace($BinaryPath) -or -not (Test-Path -LiteralPath $BinaryPath -PathType Leaf)) {
        $Issues += 'the CSFalconService executable is missing'
    }

    return [pscustomobject]@{
        Healthy = ($Issues.Count -eq 0)
        Issues  = @($Issues)
    }
}

function Get-SensorInstaller {
    $Candidates = @(Get-ChildItem -LiteralPath $SourceRoot -File -Filter '*.exe')
    if ($Candidates.Count -ne 1) {
        throw "Expected exactly one CrowdStrike Windows Sensor EXE in '$SourceRoot'; found $($Candidates.Count)."
    }

    $File = $Candidates[0]
    $Signature = Get-AuthenticodeSignature -LiteralPath $File.FullName
    if ($RequireValidCrowdStrikeSignature) {
        if ($Signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
            throw "The sensor installer does not have a valid Authenticode signature. Status: $($Signature.Status)."
        }
        if ($null -eq $Signature.SignerCertificate -or $Signature.SignerCertificate.Subject -notmatch '(?i)CrowdStrike') {
            throw 'The sensor installer is validly signed, but the signer is not recognized as CrowdStrike.'
        }
    }

    $Version = Get-VersionFromFile -Path $File.FullName
    if ([string]::IsNullOrWhiteSpace($Version)) {
        throw "Unable to read the CrowdStrike sensor version from '$($File.Name)'."
    }

    $VersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($File.FullName)
    return [pscustomobject]@{
        Path          = $File.FullName
        FileName      = $File.Name
        Version       = $Version
        CompanyName   = [string]$VersionInfo.CompanyName
        ProductName   = [string]$VersionInfo.ProductName
        Sha256        = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash
        SignerSubject = if ($null -ne $Signature.SignerCertificate) { [string]$Signature.SignerCertificate.Subject } else { $null }
    }
}

function Invoke-FalconInstall {
    param(
        [Parameter(Mandatory = $true)]$Installer,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $ArgumentString = $Arguments -join ' '
    for ($Attempt = 1; $Attempt -le ($InstallerBusyRetryCount + 1); $Attempt++) {
        Write-Log "Running the CrowdStrike sensor installer for version $($Installer.Version) (attempt $Attempt). Sensitive arguments are redacted."
        $Process = Start-Process `
            -FilePath $Installer.Path `
            -ArgumentList $ArgumentString `
            -WorkingDirectory $SourceRoot `
            -WindowStyle Hidden `
            -Wait `
            -PassThru
        $ExitCode = [int]$Process.ExitCode

        if ($ExitCode -eq 1618 -and $Attempt -le $InstallerBusyRetryCount) {
            Write-Log "Another installation is active. Retrying in $InstallerBusyRetryDelaySeconds seconds." 'WARN'
            Start-Sleep -Seconds $InstallerBusyRetryDelaySeconds
            continue
        }

        if ($ExitCode -in @(0, 1641, 3010)) {
            Write-Log "CrowdStrike installer completed with exit code $ExitCode."
            return $ExitCode
        }

        $Message = if ($ExitCode -eq 1244) {
            'CrowdStrike installer returned 1244 and could not complete cloud provisioning. Verify the CID, provisioning token, proxy, and CrowdStrike cloud connectivity.'
        }
        else {
            "CrowdStrike installer failed with exit code $ExitCode."
        }

        $script:FailureExitCode = $ExitCode
        $Exception = [System.Exception]::new($Message)
        $Exception.Data['ExitCode'] = $ExitCode
        throw $Exception
    }
}

function Wait-ForVerifiedSensor {
    param(
        [Parameter(Mandatory = $true)][string]$MinimumVersion,
        [Parameter(Mandatory = $true)][string]$ExpectedCid,
        [Parameter(Mandatory = $true)][bool]$RequireRunning,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $LastIssue = 'sensor verification has not completed'

    do {
        try {
            $Sensor = Get-InstalledFalconSensor
            if ($null -eq $Sensor) {
                $LastIssue = 'the sensor is not installed'
            }
            elseif ((Compare-VersionString -Left $Sensor.Version -Right $MinimumVersion) -lt 0) {
                $LastIssue = "installed version $($Sensor.Version) is older than $MinimumVersion"
            }
            else {
                $Health = Get-FalconHealth -RequireRunning $RequireRunning
                if (-not $Health.Healthy) {
                    $LastIssue = $Health.Issues -join '; '
                }
                else {
                    $InstalledCid = Get-InstalledCid
                    if ($RequireTenantMatch -and [string]::IsNullOrWhiteSpace($InstalledCid)) {
                        $LastIssue = 'the installed CID is not yet available'
                    }
                    elseif ($RequireTenantMatch -and $InstalledCid -ne $ExpectedCid) {
                        throw 'The installed Falcon sensor CID does not match TenantConfig.json. Refusing to adopt a sensor registered to a different tenant.'
                    }
                    else {
                        return [pscustomobject]@{
                            Sensor = $Sensor
                            Cid    = $InstalledCid
                        }
                    }
                }
            }
        }
        catch {
            if ($_.Exception.Message -match 'different tenant') { throw }
            $LastIssue = $_.Exception.Message
        }

        if ((Get-Date) -lt $Deadline) {
            Start-Sleep -Seconds 5
        }
    } while ((Get-Date) -lt $Deadline)

    throw "CrowdStrike post-install verification timed out after $TimeoutSeconds seconds: $LastIssue."
}

try {
    Write-Log 'Starting CrowdStrike Falcon Sensor installation wrapper.'

    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This installer must run elevated. Configure the Intune app to install in System context.'
    }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        throw 'This wrapper must run in 64-bit PowerShell. Use the SysNative Intune install command documented in README.md.'
    }
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Configuration file not found: '$ConfigPath'."
    }
    if (-not (Test-Path -LiteralPath $TenantConfigPath -PathType Leaf)) {
        throw "Tenant configuration file not found: '$TenantConfigPath'. Copy TenantConfig.json.example to TenantConfig.json and populate it before packaging."
    }
    if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
        throw "Source directory not found: '$SourceRoot'."
    }

    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $TenantConfig = Get-Content -LiteralPath $TenantConfigPath -Raw | ConvertFrom-Json

    $PackageRevision = [string](Get-RequiredProperty -Object $Config -Name 'PackageRevision' -SourceName 'Config.json')
    $RequireValidCrowdStrikeSignature = Get-RequiredProperty -Object $Config -Name 'RequireValidCrowdStrikeSignature' -SourceName 'Config.json'
    $RequireTenantMatch = Get-RequiredProperty -Object $Config -Name 'RequireTenantMatch' -SourceName 'Config.json'
    $RequireRunningServices = Get-RequiredProperty -Object $Config -Name 'RequireRunningServices' -SourceName 'Config.json'
    $RequireProvisioningToken = Get-RequiredProperty -Object $Config -Name 'RequireProvisioningToken' -SourceName 'Config.json'
    $ProvisioningWaitTimeMilliseconds = [int](Get-RequiredProperty -Object $Config -Name 'ProvisioningWaitTimeMilliseconds' -SourceName 'Config.json')
    $GroupingTags = @(Get-RequiredProperty -Object $Config -Name 'GroupingTags' -SourceName 'Config.json')
    $ProxyHost = [string](Get-RequiredProperty -Object $Config -Name 'ProxyHost' -SourceName 'Config.json')
    $ProxyPort = [int](Get-RequiredProperty -Object $Config -Name 'ProxyPort' -SourceName 'Config.json')
    $PostInstallVerificationTimeoutSeconds = [int](Get-RequiredProperty -Object $Config -Name 'PostInstallVerificationTimeoutSeconds' -SourceName 'Config.json')
    $InstallerBusyRetryCount = [int](Get-RequiredProperty -Object $Config -Name 'InstallerBusyRetryCount' -SourceName 'Config.json')
    $InstallerBusyRetryDelaySeconds = [int](Get-RequiredProperty -Object $Config -Name 'InstallerBusyRetryDelaySeconds' -SourceName 'Config.json')

    foreach ($BooleanSetting in @(
        @{ Name = 'RequireValidCrowdStrikeSignature'; Value = $RequireValidCrowdStrikeSignature },
        @{ Name = 'RequireTenantMatch'; Value = $RequireTenantMatch },
        @{ Name = 'RequireRunningServices'; Value = $RequireRunningServices },
        @{ Name = 'RequireProvisioningToken'; Value = $RequireProvisioningToken }
    )) {
        Assert-BooleanSetting -Name $BooleanSetting.Name -Value $BooleanSetting.Value
    }

    if ([string]::IsNullOrWhiteSpace($PackageRevision) -or $PackageRevision -notmatch '^[A-Za-z0-9._-]+$') {
        throw 'PackageRevision must contain only letters, numbers, periods, underscores, or hyphens.'
    }
    if ($ProvisioningWaitTimeMilliseconds -lt 60000 -or $ProvisioningWaitTimeMilliseconds -gt 3600000) {
        throw 'ProvisioningWaitTimeMilliseconds must be between 60000 and 3600000.'
    }
    if ($PostInstallVerificationTimeoutSeconds -lt 30 -or $PostInstallVerificationTimeoutSeconds -gt 900) {
        throw 'PostInstallVerificationTimeoutSeconds must be between 30 and 900.'
    }
    if ($InstallerBusyRetryCount -lt 0 -or $InstallerBusyRetryCount -gt 20) {
        throw 'InstallerBusyRetryCount must be between 0 and 20.'
    }
    if ($InstallerBusyRetryDelaySeconds -lt 1 -or $InstallerBusyRetryDelaySeconds -gt 300) {
        throw 'InstallerBusyRetryDelaySeconds must be between 1 and 300.'
    }
    if ([string]::IsNullOrWhiteSpace($ProxyHost)) {
        if ($ProxyPort -ne 0) { throw 'ProxyPort must be 0 when ProxyHost is empty.' }
    }
    else {
        if ($ProxyHost -notmatch '^[A-Za-z0-9._:-]+$') {
            throw 'ProxyHost may contain only letters, numbers, periods, underscores, colons, and hyphens.'
        }
        if ($ProxyPort -lt 1 -or $ProxyPort -gt 65535) {
            throw 'ProxyPort must be between 1 and 65535 when ProxyHost is configured.'
        }
    }
    foreach ($Tag in $GroupingTags) {
        if ([string]::IsNullOrWhiteSpace([string]$Tag) -or ([string]$Tag) -notmatch '^[A-Za-z0-9._:-]+$') {
            throw "Grouping tag '$Tag' contains unsupported characters. Use only letters, numbers, periods, underscores, colons, and hyphens."
        }
    }

    $Cid = [string](Get-RequiredProperty -Object $TenantConfig -Name 'CID' -SourceName 'TenantConfig.json')
    $ProvisioningToken = [string](Get-RequiredProperty -Object $TenantConfig -Name 'ProvisioningToken' -SourceName 'TenantConfig.json')
    $null = Get-RequiredProperty -Object $TenantConfig -Name 'MaintenanceToken' -SourceName 'TenantConfig.json'
    $NormalizedCid = Get-NormalizedCid -Cid $Cid
    $CidSha256 = Get-TextSha256 -Value $NormalizedCid

    if ($RequireProvisioningToken -and [string]::IsNullOrWhiteSpace($ProvisioningToken)) {
        throw 'RequireProvisioningToken is true, but TenantConfig.json ProvisioningToken is empty.'
    }
    if (-not [string]::IsNullOrWhiteSpace($ProvisioningToken) -and $ProvisioningToken -match '[\s"]') {
        throw 'ProvisioningToken cannot contain whitespace or double-quote characters.'
    }

    $Installer = Get-SensorInstaller
    Write-Log "Validated CrowdStrike sensor installer '$($Installer.FileName)', version $($Installer.Version), SHA-256 $($Installer.Sha256)."

    $ExistingSensor = Get-InstalledFalconSensor
    $InstallRequired = $true
    $InstallAction = 'FreshInstall'

    if ($null -ne $ExistingSensor) {
        Write-Log "Detected CrowdStrike Falcon Sensor $($ExistingSensor.Version) using $($ExistingSensor.VersionSource)."
        if ($null -ne $ExistingSensor.BinaryVersion -and $null -ne $ExistingSensor.RegistryVersion -and
            (Compare-VersionString -Left $ExistingSensor.BinaryVersion -Right $ExistingSensor.RegistryVersion) -ne 0) {
            Write-Log "Sensor binary version $($ExistingSensor.BinaryVersion) and uninstall registry version $($ExistingSensor.RegistryVersion) differ. The service binary version is authoritative." 'WARN'
        }

        if ($RequireTenantMatch) {
            $ExistingCid = Get-InstalledCid
            if ([string]::IsNullOrWhiteSpace($ExistingCid)) {
                throw 'A Falcon sensor is already present, but its CID could not be read. Refusing to install or adopt it because tenant ownership cannot be verified.'
            }
            if ($ExistingCid -ne $NormalizedCid) {
                throw 'The installed Falcon sensor belongs to a different CID. This wrapper will not rehome, uninstall, or overwrite a sensor from another tenant.'
            }
        }

        $Comparison = Compare-VersionString -Left $ExistingSensor.Version -Right $Installer.Version
        if ($Comparison -ge 0) {
            $Health = Get-FalconHealth -RequireRunning ([bool]$RequireRunningServices)
            if (-not $Health.Healthy) {
                throw "An equal or newer Falcon sensor is present but is not healthy: $($Health.Issues -join '; '). Use CrowdStrike's supported repair workflow rather than repeatedly running the installer."
            }

            $InstallRequired = $false
            $InstallAction = if ($Comparison -eq 0) { 'AdoptedEqualVersion' } else { 'AdoptedNewerVersion' }
            Write-Log "The installed sensor is equal to or newer than the packaged version. The installer will not be executed; this deployment will be adopted into Intune state."
        }
        else {
            $InstallAction = 'UpgradedOlderVersion'
            Write-Log "The installed sensor is older than packaged version $($Installer.Version); an in-place upgrade will be run."
        }
    }
    else {
        Write-Log 'CrowdStrike Falcon Sensor is not installed; a fresh installation will be run.'
    }

    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        Remove-Item -LiteralPath $StatePath -Force
    }

    $RebootCode = 0
    if ($InstallRequired) {
        $InstallArguments = @(
            '/install',
            '/quiet',
            '/norestart',
            "CID=$Cid",
            "ProvWaitTime=$ProvisioningWaitTimeMilliseconds"
        )
        if (-not [string]::IsNullOrWhiteSpace($ProvisioningToken)) {
            $InstallArguments += "ProvToken=$ProvisioningToken"
        }
        if ($GroupingTags.Count -gt 0) {
            $InstallArguments += 'GROUPING_TAGS={0}' -f ($GroupingTags -join ',')
        }
        if (-not [string]::IsNullOrWhiteSpace($ProxyHost)) {
            $InstallArguments += "APP_PROXYNAME=$ProxyHost"
            $InstallArguments += "APP_PROXYPORT=$ProxyPort"
        }

        $RebootCode = Invoke-FalconInstall -Installer $Installer -Arguments $InstallArguments
    }
    elseif ($GroupingTags.Count -gt 0 -or -not [string]::IsNullOrWhiteSpace($ProxyHost)) {
        Write-Log 'Grouping-tag or proxy installer properties were not reapplied because the equal/newer sensor installer was intentionally skipped.' 'WARN'
    }

    $VerificationRequiresRunning = ([bool]$RequireRunningServices -and $RebootCode -eq 0)
    $Verified = Wait-ForVerifiedSensor `
        -MinimumVersion $Installer.Version `
        -ExpectedCid $NormalizedCid `
        -RequireRunning $VerificationRequiresRunning `
        -TimeoutSeconds $PostInstallVerificationTimeoutSeconds

    $State = [ordered]@{
        SchemaVersion          = 1
        PackageRevision        = $PackageRevision
        MinimumSensorVersion   = $Installer.Version
        InstalledSensorVersion = $Verified.Sensor.Version
        InstallerFileName      = $Installer.FileName
        InstallerSha256        = $Installer.Sha256
        CidSha256              = $CidSha256
        RequireTenantMatch     = [bool]$RequireTenantMatch
        RequireRunningServices = [bool]$RequireRunningServices
        RequiredServices       = @('CSFalconService', 'csagent')
        InstallAction          = $InstallAction
        InstalledUtc           = (Get-Date).ToUniversalTime().ToString('o')
    }

    $TemporaryStatePath = "$StatePath.tmp"
    $State | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $TemporaryStatePath -Encoding utf8
    Move-Item -LiteralPath $TemporaryStatePath -Destination $StatePath -Force

    Write-Log "CrowdStrike Falcon Sensor wrapper revision $PackageRevision completed successfully. Installed version: $($Verified.Sensor.Version); action: $InstallAction."
    exit $RebootCode
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
