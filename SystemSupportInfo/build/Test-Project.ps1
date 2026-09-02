#requires -Version 5.1

<#
.SYNOPSIS
    Performs static validation for the SystemSupportInfo project.

.PARAMETER ConfigurationPath
    Configuration to validate. Defaults to the repository configuration.

.PARAMETER IncludeDataCollection
    Also runs Get-SystemSupportData on the current Windows device.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigurationPath,

    [Parameter()]
    [switch]$IncludeDataCollection
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

if ([string]::IsNullOrWhiteSpace($ConfigurationPath)) {
    $ConfigurationPath = Join-Path $projectRoot 'config\SystemSupportInfo.config.psd1'
}
elseif (-not [System.IO.Path]::IsPathRooted($ConfigurationPath)) {
    $ConfigurationPath = Join-Path (Get-Location).Path $ConfigurationPath
}

$ConfigurationPath = (Resolve-Path -LiteralPath $ConfigurationPath).Path
$parseFailures = [System.Collections.Generic.List[string]]::new()

$powerShellFiles = Get-ChildItem -LiteralPath $projectRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.ps1', '.psm1', '.psd1') }

foreach ($file in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )

    foreach ($parseError in @($parseErrors)) {
        $relativePath = $file.FullName.Substring($projectRoot.Length).TrimStart('\')
        $parseFailures.Add(('{0}:{1}:{2} {3}' -f `
            $relativePath,
            $parseError.Extent.StartLineNumber,
            $parseError.Extent.StartColumnNumber,
            $parseError.Message))
    }
}

if ($parseFailures.Count -gt 0) {
    throw "PowerShell parse validation failed:`n$($parseFailures -join "`n")"
}

$configuration = Import-PowerShellDataFile -LiteralPath $ConfigurationPath
$uiModulePath = Join-Path $projectRoot 'src\SystemSupportInfo.UI.psm1'
$coreModulePath = Join-Path $projectRoot 'src\SystemSupportInfo.Core.psm1'

Import-Module -Name $uiModulePath -Force
$null = Test-SystemSupportInfoConfiguration -Configuration $configuration

$supportedFieldKeys = @(
    'DeviceName',
    'SignedInUser',
    'Hardware',
    'SerialNumber',
    'InstalledMemory',
    'JoinStatus',
    'WindowsEdition',
    'WindowsVersion',
    'OSBuild',
    'Architecture',
    'LastRestart',
    'Uptime',
    'SystemDrive',
    'ActiveConnection',
    'IPv4Address',
    'CollectedAt'
)

$unknownKeys = @($configuration.Fields.Key | Where-Object { $_ -notin $supportedFieldKeys })
if ($unknownKeys.Count -gt 0) {
    throw "The configuration references fields not supplied by the core module: $($unknownKeys -join ', ')"
}

foreach ($assetSetting in @(
    @{ Name = 'Branding.LogoPath'; Value = [string]$configuration.Branding.LogoPath },
    @{ Name = 'Build.IconPath'; Value = [string]$configuration.Build.IconPath }
)) {
    if ([string]::IsNullOrWhiteSpace($assetSetting.Value)) {
        continue
    }

    $assetPath = $assetSetting.Value
    if (-not [System.IO.Path]::IsPathRooted($assetPath)) {
        $assetPath = Join-Path $projectRoot $assetPath
    }

    if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
        throw "$($assetSetting.Name) points to a missing file: $assetPath"
    }
}

if ($IncludeDataCollection) {
    Import-Module -Name $coreModulePath -Force
    $data = Get-SystemSupportData `
        -UnavailableText ([string]$configuration.Text.Unavailable) `
        -DateFormat ([string]$configuration.Text.DateFormat)

    foreach ($key in $supportedFieldKeys) {
        if ($null -eq $data.PSObject.Properties[$key]) {
            throw "Get-SystemSupportData did not return the expected '$key' property."
        }
    }
}

Write-Host 'Validation passed' -ForegroundColor Green
Write-Host ('  PowerShell files: {0}' -f $powerShellFiles.Count)
Write-Host ('  Configuration: {0}' -f $ConfigurationPath)
$visibleFieldCount = @(
    $configuration.Fields |
        Where-Object { -not $_.ContainsKey('Visible') -or $_.Visible }
).Count
Write-Host ('  Visible fields: {0}' -f $visibleFieldCount)
