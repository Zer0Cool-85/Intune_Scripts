#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$IntuneWinAppUtilPath,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptRoot 'Config.json'
$TenantConfigPath = Join-Path $ScriptRoot 'TenantConfig.json'
$FilesPath = Join-Path $ScriptRoot 'Files'
$DetectionPath = Join-Path $ScriptRoot 'Detect-CrowdStrikeFalcon.ps1'
$SetupFile = 'Install-CrowdStrikeFalcon.ps1'

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

if (-not $OutputPath) {
    $OutputPath = Join-Path (Split-Path -Parent $ScriptRoot) 'CrowdStrike-Falcon-Sensor-Intune-Output'
}

$IntuneWinAppUtilPath = [IO.Path]::GetFullPath($IntuneWinAppUtilPath)
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$SourceFullPath = [IO.Path]::GetFullPath($ScriptRoot).TrimEnd('\') + '\'

if (-not (Test-Path -LiteralPath $IntuneWinAppUtilPath -PathType Leaf)) {
    throw "Microsoft Win32 Content Prep Tool not found: '$IntuneWinAppUtilPath'."
}
foreach ($RequiredFile in @(
    $ConfigPath,
    $TenantConfigPath,
    $DetectionPath,
    (Join-Path $ScriptRoot $SetupFile),
    (Join-Path $ScriptRoot 'Uninstall-CrowdStrikeFalcon.ps1')
)) {
    if (-not (Test-Path -LiteralPath $RequiredFile -PathType Leaf)) {
        throw "Required package file not found: '$RequiredFile'."
    }
}
if (-not (Test-Path -LiteralPath $FilesPath -PathType Container)) {
    throw "Files directory not found: '$FilesPath'."
}
if ($OutputPath.TrimEnd('\') -eq $ScriptRoot.TrimEnd('\') -or
    $OutputPath.StartsWith($SourceFullPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputPath must be outside the source folder so an earlier .intunewin file is never packaged inside the next one.'
}

$Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$TenantConfig = Get-Content -LiteralPath $TenantConfigPath -Raw | ConvertFrom-Json
$PackageRevision = [string](Get-RequiredProperty -Object $Config -Name 'PackageRevision' -SourceName 'Config.json')
$RequireValidSignature = Get-RequiredProperty -Object $Config -Name 'RequireValidCrowdStrikeSignature' -SourceName 'Config.json'
$RequireTenantMatch = Get-RequiredProperty -Object $Config -Name 'RequireTenantMatch' -SourceName 'Config.json'
$RequireRunningServices = Get-RequiredProperty -Object $Config -Name 'RequireRunningServices' -SourceName 'Config.json'
$RequireProvisioningToken = Get-RequiredProperty -Object $Config -Name 'RequireProvisioningToken' -SourceName 'Config.json'
$EnableUninstall = Get-RequiredProperty -Object $Config -Name 'EnableUninstall' -SourceName 'Config.json'
$AllowPackagedUninstall = Get-RequiredProperty -Object $Config -Name 'AllowPackagedInstallerForUninstall' -SourceName 'Config.json'
$ProvisioningWaitTime = [int](Get-RequiredProperty -Object $Config -Name 'ProvisioningWaitTimeMilliseconds' -SourceName 'Config.json')
$VerificationTimeout = [int](Get-RequiredProperty -Object $Config -Name 'PostInstallVerificationTimeoutSeconds' -SourceName 'Config.json')
$RetryCount = [int](Get-RequiredProperty -Object $Config -Name 'InstallerBusyRetryCount' -SourceName 'Config.json')
$RetryDelay = [int](Get-RequiredProperty -Object $Config -Name 'InstallerBusyRetryDelaySeconds' -SourceName 'Config.json')
$GroupingTags = @(Get-RequiredProperty -Object $Config -Name 'GroupingTags' -SourceName 'Config.json')
$ProxyHost = [string](Get-RequiredProperty -Object $Config -Name 'ProxyHost' -SourceName 'Config.json')
$ProxyPort = [int](Get-RequiredProperty -Object $Config -Name 'ProxyPort' -SourceName 'Config.json')

foreach ($BooleanSetting in @(
    @{ Name = 'RequireValidCrowdStrikeSignature'; Value = $RequireValidSignature },
    @{ Name = 'RequireTenantMatch'; Value = $RequireTenantMatch },
    @{ Name = 'RequireRunningServices'; Value = $RequireRunningServices },
    @{ Name = 'RequireProvisioningToken'; Value = $RequireProvisioningToken },
    @{ Name = 'EnableUninstall'; Value = $EnableUninstall },
    @{ Name = 'AllowPackagedInstallerForUninstall'; Value = $AllowPackagedUninstall }
)) {
    if ($BooleanSetting.Value -isnot [bool]) {
        throw "Config setting '$($BooleanSetting.Name)' must be true or false without quotation marks."
    }
}

if ([string]::IsNullOrWhiteSpace($PackageRevision) -or $PackageRevision -notmatch '^[A-Za-z0-9._-]+$') {
    throw 'PackageRevision must contain only letters, numbers, periods, underscores, or hyphens.'
}
if ($ProvisioningWaitTime -lt 60000 -or $ProvisioningWaitTime -gt 3600000) {
    throw 'ProvisioningWaitTimeMilliseconds must be between 60000 and 3600000.'
}
if ($VerificationTimeout -lt 30 -or $VerificationTimeout -gt 900) {
    throw 'PostInstallVerificationTimeoutSeconds must be between 30 and 900.'
}
if ($RetryCount -lt 0 -or $RetryCount -gt 20) { throw 'InstallerBusyRetryCount must be between 0 and 20.' }
if ($RetryDelay -lt 1 -or $RetryDelay -gt 300) { throw 'InstallerBusyRetryDelaySeconds must be between 1 and 300.' }
if ([string]::IsNullOrWhiteSpace($ProxyHost)) {
    if ($ProxyPort -ne 0) { throw 'ProxyPort must be 0 when ProxyHost is empty.' }
}
else {
    if ($ProxyHost -notmatch '^[A-Za-z0-9._:-]+$') { throw 'ProxyHost contains unsupported characters.' }
    if ($ProxyPort -lt 1 -or $ProxyPort -gt 65535) { throw 'ProxyPort must be between 1 and 65535.' }
}
foreach ($Tag in $GroupingTags) {
    if ([string]::IsNullOrWhiteSpace([string]$Tag) -or ([string]$Tag) -notmatch '^[A-Za-z0-9._:-]+$') {
        throw "Grouping tag '$Tag' contains unsupported characters."
    }
}

$DetectionText = Get-Content -LiteralPath $DetectionPath -Raw
$DetectionPattern = [regex]::Escape('$ExpectedPackageRevision') + "\s*=\s*'([^']+)'"
$DetectionMatch = [regex]::Match($DetectionText, $DetectionPattern)
if (-not $DetectionMatch.Success) {
    throw 'Could not read ExpectedPackageRevision from Detect-CrowdStrikeFalcon.ps1.'
}
if ($DetectionMatch.Groups[1].Value -ne $PackageRevision) {
    throw "Detection revision '$($DetectionMatch.Groups[1].Value)' does not match Config.json revision '$PackageRevision'. Update both before building."
}

$Cid = [string](Get-RequiredProperty -Object $TenantConfig -Name 'CID' -SourceName 'TenantConfig.json')
$ProvisioningToken = [string](Get-RequiredProperty -Object $TenantConfig -Name 'ProvisioningToken' -SourceName 'TenantConfig.json')
$MaintenanceToken = [string](Get-RequiredProperty -Object $TenantConfig -Name 'MaintenanceToken' -SourceName 'TenantConfig.json')
if ($Cid -notmatch '^[A-Fa-f0-9]{32}-[A-Fa-f0-9]{2}$') {
    throw 'TenantConfig.json CID must contain 32 hexadecimal characters, a hyphen, and the two-character checksum.'
}
if ($RequireProvisioningToken -and [string]::IsNullOrWhiteSpace($ProvisioningToken)) {
    throw 'RequireProvisioningToken is true, but TenantConfig.json ProvisioningToken is empty.'
}
foreach ($TokenSetting in @(
    @{ Name = 'ProvisioningToken'; Value = $ProvisioningToken },
    @{ Name = 'MaintenanceToken'; Value = $MaintenanceToken }
)) {
    if (-not [string]::IsNullOrWhiteSpace($TokenSetting.Value) -and $TokenSetting.Value -match '[\s"]') {
        throw "TenantConfig.json $($TokenSetting.Name) cannot contain whitespace or double-quote characters."
    }
}
if (-not [string]::IsNullOrWhiteSpace($MaintenanceToken)) {
    Write-Warning 'TenantConfig.json contains a maintenance token. Anyone who can recover the decrypted Intune content may be able to remove protected sensors. Use a narrowly scoped removal package and retire it promptly.'
}
elseif ($EnableUninstall) {
    Write-Warning 'Uninstall is enabled without a maintenance token. It will succeed only while CrowdStrike uninstall protection permits removal.'
}
if ($AllowPackagedUninstall) {
    Write-Warning 'Packaged-installer uninstall fallback is enabled. Confirm this sensor installer is supported for uninstalling the versions currently in your fleet.'
}

$InstallerFiles = @(Get-ChildItem -LiteralPath $FilesPath -File -Filter '*.exe')
if ($InstallerFiles.Count -ne 1) {
    throw "Expected exactly one CrowdStrike Windows Sensor EXE in '$FilesPath'; found $($InstallerFiles.Count)."
}
$Installer = $InstallerFiles[0]
$Signature = Get-AuthenticodeSignature -LiteralPath $Installer.FullName
if ($RequireValidSignature) {
    if ($Signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "The sensor installer does not have a valid Authenticode signature. Status: $($Signature.Status)."
    }
    if ($null -eq $Signature.SignerCertificate -or $Signature.SignerCertificate.Subject -notmatch '(?i)CrowdStrike') {
        throw 'The sensor installer is validly signed, but the signer is not recognized as CrowdStrike.'
    }
}

$VersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Installer.FullName)
$InstallerVersion = $null
foreach ($Candidate in @([string]$VersionInfo.ProductVersion, [string]$VersionInfo.FileVersion)) {
    if ([string]::IsNullOrWhiteSpace($Candidate)) { continue }
    try {
        $InstallerVersion = Get-NormalizedVersion -Value $Candidate
        break
    }
    catch {
        continue
    }
}
if ([string]::IsNullOrWhiteSpace($InstallerVersion)) {
    throw "Unable to read the CrowdStrike sensor version from '$($Installer.Name)'."
}
$InstallerHash = (Get-FileHash -LiteralPath $Installer.FullName -Algorithm SHA256).Hash
Write-Output "Validated CrowdStrike installer '$($Installer.Name)', version $InstallerVersion, SHA-256 $InstallerHash."

New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
$DestinationPath = Join-Path $OutputPath ("CrowdStrike-Falcon-Sensor-{0}.intunewin" -f $PackageRevision)
if (Test-Path -LiteralPath $DestinationPath) {
    throw "Output already exists: '$DestinationPath'. Increment PackageRevision or move the existing package first."
}

$TemporaryOutput = Join-Path ([IO.Path]::GetTempPath()) ('CrowdStrikeFalconIntune-{0}' -f [guid]::NewGuid().ToString('N'))
New-Item -Path $TemporaryOutput -ItemType Directory -Force | Out-Null

try {
    $Arguments = @(
        '-c', ('"{0}"' -f $ScriptRoot),
        '-s', ('"{0}"' -f $SetupFile),
        '-o', ('"{0}"' -f $TemporaryOutput),
        '-q'
    )
    $Process = Start-Process -FilePath $IntuneWinAppUtilPath -ArgumentList $Arguments -Wait -PassThru
    if ($Process.ExitCode -ne 0) {
        throw "Microsoft Win32 Content Prep Tool failed with exit code $($Process.ExitCode)."
    }

    $GeneratedPackages = @(Get-ChildItem -LiteralPath $TemporaryOutput -File -Filter '*.intunewin')
    if ($GeneratedPackages.Count -ne 1) {
        throw "Expected one generated .intunewin file; found $($GeneratedPackages.Count)."
    }

    Move-Item -LiteralPath $GeneratedPackages[0].FullName -Destination $DestinationPath
    Write-Output "Created: $DestinationPath"
}
finally {
    if (Test-Path -LiteralPath $TemporaryOutput -PathType Container) {
        Remove-Item -LiteralPath $TemporaryOutput -Recurse -Force
    }
}
