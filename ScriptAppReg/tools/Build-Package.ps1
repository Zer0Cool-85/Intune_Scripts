#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigurationPath = (Join-Path $PSScriptRoot '..\config\AppRegistration.json'),

    [Parameter()]
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\build'),

    [Parameter()]
    [string]$IntuneWinAppUtilPath,

    [Parameter()]
    [switch]$SkipIntuneWin
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Assert-NotBlank {
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        throw "Configuration property '$Name' must not be empty."
    }
}

function Assert-WindowsAbsolutePath {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $isDrivePath = $Path -match '^[A-Za-z]:\\'
    $isUncPath = $Path -match '^\\\\[^\\]+\\[^\\]+'

    if (-not ($isDrivePath -or $isUncPath)) {
        throw "Configuration property '$Name' must be an absolute Windows path. Current value: $Path"
    }
}

function Write-Utf8BomFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Content
    )

    $parent = Split-Path -Parent $Path
    [void](New-Item -Path $parent -ItemType Directory -Force)

    $encoding = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

$resolvedConfigurationPath = [System.IO.Path]::GetFullPath($ConfigurationPath)
$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$templateDirectory = Join-Path $repositoryRoot 'templates'

if (-not (Test-Path -LiteralPath $resolvedConfigurationPath -PathType Leaf)) {
    throw "Configuration file not found: $resolvedConfigurationPath"
}

$rawConfiguration = Get-Content -LiteralPath $resolvedConfigurationPath -Raw
$configuration = $rawConfiguration | ConvertFrom-Json

Assert-NotBlank -Value $configuration.Package.Name -Name 'Package.Name'
Assert-NotBlank -Value $configuration.Package.Version -Name 'Package.Version'
Assert-NotBlank -Value $configuration.Application.DisplayName -Name 'Application.DisplayName'
Assert-NotBlank -Value $configuration.Application.DisplayVersion -Name 'Application.DisplayVersion'
Assert-NotBlank -Value $configuration.Application.Publisher -Name 'Application.Publisher'
Assert-NotBlank -Value $configuration.Application.InstallLocation -Name 'Application.InstallLocation'
Assert-NotBlank -Value $configuration.Application.RegistryKeyName -Name 'Application.RegistryKeyName'
Assert-NotBlank -Value $configuration.Presence.MatchMode -Name 'Presence.MatchMode'

try {
    [void][version]$configuration.Package.Version
    [void][version]$configuration.Application.DisplayVersion
}
catch {
    throw 'Package.Version and Application.DisplayVersion must be valid dotted versions, such as 1.0.0.'
}

Assert-WindowsAbsolutePath -Path ([string]$configuration.Application.InstallLocation) -Name 'Application.InstallLocation'

if (-not [string]::IsNullOrWhiteSpace([string]$configuration.Application.UninstallScriptPath)) {
    Assert-WindowsAbsolutePath -Path ([string]$configuration.Application.UninstallScriptPath) -Name 'Application.UninstallScriptPath'
}

if (-not [string]::IsNullOrWhiteSpace([string]$configuration.Application.DisplayIconPath)) {
    Assert-WindowsAbsolutePath -Path ([string]$configuration.Application.DisplayIconPath) -Name 'Application.DisplayIconPath'
}

if ([string]$configuration.Application.RegistryKeyName -match '[\\/]') {
    throw 'Application.RegistryKeyName must be a single registry subkey name and cannot contain slashes.'
}

$matchMode = [string]$configuration.Presence.MatchMode
if ($matchMode -notin @('All', 'Any')) {
    throw "Presence.MatchMode must be either 'All' or 'Any'."
}

$requiredFiles = @(
    $configuration.Presence.RequiredFiles |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
)

$requiredTasks = @(
    $configuration.Presence.RequiredScheduledTasks |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
)

if (($requiredFiles.Count + $requiredTasks.Count) -eq 0) {
    throw 'Configure at least one Presence.RequiredFiles or Presence.RequiredScheduledTasks marker.'
}

for ($index = 0; $index -lt $requiredFiles.Count; $index++) {
    Assert-WindowsAbsolutePath -Path ([string]$requiredFiles[$index]) -Name "Presence.RequiredFiles[$index]"
}

$estimatedSize = [long]$configuration.Application.EstimatedSizeKB
if ($estimatedSize -lt 0 -or $estimatedSize -gt [uint32]::MaxValue) {
    throw 'Application.EstimatedSizeKB must be between 0 and 4294967295.'
}

$normalizedJson = $configuration | ConvertTo-Json -Depth 20 -Compress
$configurationBytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedJson)
$configurationBase64 = [Convert]::ToBase64String($configurationBytes)

$templateMappings = @(
    [pscustomobject]@{
        Template = 'Install.ps1.template'
        Destination = (Join-Path (Join-Path $resolvedOutputDirectory 'Source') 'Install.ps1')
    }
    [pscustomobject]@{
        Template = 'Uninstall.ps1.template'
        Destination = (Join-Path (Join-Path $resolvedOutputDirectory 'Source') 'Uninstall.ps1')
    }
    [pscustomobject]@{
        Template = 'Requirement.ps1.template'
        Destination = (Join-Path (Join-Path $resolvedOutputDirectory 'Rules') 'Requirement.ps1')
    }
    [pscustomobject]@{
        Template = 'Detection.ps1.template'
        Destination = (Join-Path (Join-Path $resolvedOutputDirectory 'Rules') 'Detection.ps1')
    }
)

foreach ($mapping in $templateMappings) {
    $templatePath = Join-Path $templateDirectory $mapping.Template

    if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
        throw "Template file not found: $templatePath"
    }

    $templateContent = Get-Content -LiteralPath $templatePath -Raw

    if ($templateContent -notmatch [regex]::Escape('@@CONFIG_BASE64@@')) {
        throw "Template does not contain the required configuration token: $templatePath"
    }

    $generatedContent = $templateContent.Replace('@@CONFIG_BASE64@@', $configurationBase64)
    Write-Utf8BomFile -Path $mapping.Destination -Content $generatedContent
}

$packageCreated = $false
$packageDirectory = Join-Path $resolvedOutputDirectory 'Package'

if (-not $SkipIntuneWin -and -not [string]::IsNullOrWhiteSpace($IntuneWinAppUtilPath)) {
    $resolvedToolPath = [System.IO.Path]::GetFullPath($IntuneWinAppUtilPath)

    if (-not (Test-Path -LiteralPath $resolvedToolPath -PathType Leaf)) {
        throw "IntuneWinAppUtil.exe not found: $resolvedToolPath"
    }

    [void](New-Item -Path $packageDirectory -ItemType Directory -Force)

    $sourceDirectory = Join-Path $resolvedOutputDirectory 'Source'
    $setupFile = Join-Path $sourceDirectory 'Install.ps1'

    & $resolvedToolPath `
        -c $sourceDirectory `
        -s $setupFile `
        -o $packageDirectory `
        -q

    if ($LASTEXITCODE -ne 0) {
        throw "IntuneWinAppUtil.exe failed with exit code $LASTEXITCODE."
    }

    $packageCreated = $true
}
elseif (-not $SkipIntuneWin) {
    Write-Warning 'No IntuneWinAppUtilPath was provided. Generated scripts only.'
}

Write-Host ''
Write-Host 'Build completed successfully.' -ForegroundColor Green
Write-Host "Generated source: $(Join-Path $resolvedOutputDirectory 'Source')"
Write-Host "Generated rules:  $(Join-Path $resolvedOutputDirectory 'Rules')"

if ($packageCreated) {
    Write-Host "Intune package:   $packageDirectory"
}

[pscustomobject]@{
    PackageName = [string]$configuration.Package.Name
    PackageVersion = [string]$configuration.Package.Version
    OutputDirectory = $resolvedOutputDirectory
    IntuneWinCreated = $packageCreated
}
