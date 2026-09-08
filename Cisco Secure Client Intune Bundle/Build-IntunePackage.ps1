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
$FilesPath = Join-Path $ScriptRoot 'Files'
$DetectionPath = Join-Path $ScriptRoot 'Detect-CiscoSecureClient.ps1'
$SetupFile = 'Install-CiscoSecureClient.ps1'

if (-not $OutputPath) {
    $OutputPath = Join-Path (Split-Path -Parent $ScriptRoot) 'Cisco-Secure-Client-Intune-Output'
}

$IntuneWinAppUtilPath = [IO.Path]::GetFullPath($IntuneWinAppUtilPath)
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$SourceFullPath = [IO.Path]::GetFullPath($ScriptRoot).TrimEnd('\') + '\'

if (-not (Test-Path -LiteralPath $IntuneWinAppUtilPath -PathType Leaf)) {
    throw "Microsoft Win32 Content Prep Tool not found: '$IntuneWinAppUtilPath'."
}
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Configuration file not found: '$ConfigPath'."
}
if (-not (Test-Path -LiteralPath (Join-Path $ScriptRoot $SetupFile) -PathType Leaf)) {
    throw "Setup script not found: '$SetupFile'."
}
if ($OutputPath.StartsWith($SourceFullPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputPath must be outside the source folder so an earlier .intunewin file is never packaged inside the next one.'
}

$Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$PackageRevision = [string]$Config.PackageRevision
if ([string]::IsNullOrWhiteSpace($PackageRevision) -or $PackageRevision -notmatch '^[A-Za-z0-9._-]+$') {
    throw 'PackageRevision must contain only letters, numbers, periods, underscores, or hyphens.'
}

$DetectionText = Get-Content -LiteralPath $DetectionPath -Raw
$DetectionPattern = [regex]::Escape('$ExpectedPackageRevision') + "\s*=\s*'([^']+)'"
$DetectionMatch = [regex]::Match($DetectionText, $DetectionPattern)
if (-not $DetectionMatch.Success) {
    throw 'Could not read ExpectedPackageRevision from Detect-CiscoSecureClient.ps1.'
}
if ($DetectionMatch.Groups[1].Value -ne $PackageRevision) {
    throw "Detection revision '$($DetectionMatch.Groups[1].Value)' does not match Config.json revision '$PackageRevision'. Update both before building."
}

$MsiFiles = @(Get-ChildItem -LiteralPath $FilesPath -File -Filter '*.msi')
$RequiredPatterns = @(
    @{ Name = 'Core'; Pattern = '(?i)^cisco-secure-client-win-.+-core(?:-vpn)?-predeploy-k9\.msi$'; Required = $true },
    @{ Name = 'DART'; Pattern = '(?i)^cisco-secure-client-win-.+-dart-predeploy-k9\.msi$'; Required = [bool]$Config.InstallDart },
    @{ Name = 'Umbrella'; Pattern = '(?i)^cisco-secure-client-win-.+-umbrella-predeploy-k9\.msi$'; Required = [bool]$Config.InstallUmbrella }
)

foreach ($Requirement in $RequiredPatterns) {
    if (-not $Requirement.Required) { continue }
    $Matches = @($MsiFiles | Where-Object { $_.Name -match $Requirement.Pattern })
    if ($Matches.Count -ne 1) {
        throw "Expected exactly one $($Requirement.Name) predeploy MSI in '$FilesPath'; found $($Matches.Count)."
    }
}

if ([bool]$Config.RequireOrgInfo) {
    $OrgInfoPath = Join-Path $FilesPath 'Profiles\umbrella\OrgInfo.json'
    if (-not (Test-Path -LiteralPath $OrgInfoPath -PathType Leaf)) {
        throw "Required Umbrella profile not found: '$OrgInfoPath'."
    }
    try {
        $null = Get-Content -LiteralPath $OrgInfoPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "OrgInfo.json is not valid JSON: $($_.Exception.Message)"
    }
}

New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
$DestinationPath = Join-Path $OutputPath ("Cisco-Secure-Client-Bundle-{0}.intunewin" -f $PackageRevision)
if (Test-Path -LiteralPath $DestinationPath) {
    throw "Output already exists: '$DestinationPath'. Increment PackageRevision or move the existing package first."
}

$TemporaryOutput = Join-Path ([IO.Path]::GetTempPath()) ('CiscoSecureClientIntune-{0}' -f [guid]::NewGuid().ToString('N'))
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
