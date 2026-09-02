#requires -Version 5.1

<#
.SYNOPSIS
    Builds a single-file Windows EXE for SystemSupportInfo.

.DESCRIPTION
    Validates the project, embeds the modules/configuration/optional logo, and
    compiles the launcher with PS2EXE 1.0.18 or later. Run this script on a
    Windows device. The finished EXE does not require the repository folders.

.PARAMETER ConfigurationPath
    Configuration to embed. Defaults to config/SystemSupportInfo.config.psd1.

.PARAMETER OutputPath
    EXE output path. Defaults to dist plus Build.OutputFileName from config.

.PARAMETER IconPath
    Optional .ico file used as the Windows executable icon. Overrides
    Build.IconPath from config.

.PARAMETER Architecture
    Runtime architecture. Defaults to x64; AnyCPU omits both architecture flags.

.PARAMETER InstallPS2EXE
    Installs PS2EXE for the current user when version 1.0.18+ is unavailable.

.PARAMETER SkipTests
    Skips build/Test-Project.ps1. Intended only for build troubleshooting.

.EXAMPLE
    .\build\Build-Exe.ps1 -InstallPS2EXE

.EXAMPLE
    .\build\Build-Exe.ps1 `
        -ConfigurationPath .\config\SystemSupportInfo.config.psd1 `
        -OutputPath .\dist\ContosoSupportInfo.exe `
        -IconPath .\assets\app.ico
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigurationPath,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [string]$IconPath,

    [Parameter()]
    [ValidateSet('x64', 'x86', 'AnyCPU')]
    [string]$Architecture = 'x64',

    [Parameter()]
    [switch]$InstallPS2EXE,

    [Parameter()]
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$minimumPS2EXEVersion = [version]'1.0.18'
$runtimeResourceVersion = '1.0.2'

if ($env:OS -ne 'Windows_NT') {
    throw 'Build-Exe.ps1 must be run on Windows.'
}

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$launcherPath = Join-Path $projectRoot 'SystemSupportInfo.ps1'
$configurationModulePath = Join-Path $projectRoot 'src\SystemSupportInfo.Configuration.psm1'
$coreModulePath = Join-Path $projectRoot 'src\SystemSupportInfo.Core.psm1'
$uiModulePath = Join-Path $projectRoot 'src\SystemSupportInfo.UI.psm1'

if ([string]::IsNullOrWhiteSpace($ConfigurationPath)) {
    $ConfigurationPath = Join-Path $projectRoot 'config\SystemSupportInfo.config.psd1'
}
elseif (-not [System.IO.Path]::IsPathRooted($ConfigurationPath)) {
    $ConfigurationPath = Join-Path (Get-Location).Path $ConfigurationPath
}

$ConfigurationPath = (Resolve-Path -LiteralPath $ConfigurationPath).Path
Import-Module -Name $configurationModulePath -Force -ErrorAction Stop
$configuration = Import-SystemSupportConfiguration -LiteralPath $ConfigurationPath

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectRoot ('dist\{0}' -f [string]$configuration.Build.OutputFileName)
}
elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path (Get-Location).Path $OutputPath
}

$outputDirectory = Split-Path -Path $OutputPath -Parent
$null = New-Item -Path $outputDirectory -ItemType Directory -Force
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

if (-not $SkipTests) {
    & (Join-Path $PSScriptRoot 'Test-Project.ps1') -ConfigurationPath $ConfigurationPath
}

$availablePS2EXE = Get-Module -ListAvailable -Name ps2exe |
    Where-Object { $_.Version -ge $minimumPS2EXEVersion } |
    Sort-Object -Property Version -Descending |
    Select-Object -First 1

if (-not $availablePS2EXE -and $InstallPS2EXE) {
    Install-Module `
        -Name ps2exe `
        -MinimumVersion $minimumPS2EXEVersion `
        -Repository PSGallery `
        -Scope CurrentUser `
        -Force `
        -AllowClobber

    $availablePS2EXE = Get-Module -ListAvailable -Name ps2exe |
        Where-Object { $_.Version -ge $minimumPS2EXEVersion } |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1
}

if (-not $availablePS2EXE) {
    throw "PS2EXE $minimumPS2EXEVersion or later is required. Run this build again with -InstallPS2EXE, or install it with: Install-Module ps2exe -MinimumVersion $minimumPS2EXEVersion -Scope CurrentUser"
}

Import-Module -Name $availablePS2EXE.Path -Force

$embeddedRoot = '%TEMP%\SystemSupportInfo\{0}' -f $runtimeResourceVersion
$embeddedFiles = [ordered]@{}
$embeddedFiles[(Join-Path $embeddedRoot 'src\SystemSupportInfo.Configuration.psm1')] = $configurationModulePath
$embeddedFiles[(Join-Path $embeddedRoot 'src\SystemSupportInfo.Core.psm1')] = $coreModulePath
$embeddedFiles[(Join-Path $embeddedRoot 'src\SystemSupportInfo.UI.psm1')] = $uiModulePath
$embeddedFiles[(Join-Path $embeddedRoot 'config\SystemSupportInfo.config.psd1')] = $ConfigurationPath

$configuredLogoPath = [string]$configuration.Branding.LogoPath
if (-not [string]::IsNullOrWhiteSpace($configuredLogoPath)) {
    if ([System.IO.Path]::IsPathRooted($configuredLogoPath)) {
        throw 'Branding.LogoPath must be project-relative for a portable EXE, for example assets\logo.png.'
    }

    $logoSourcePath = Join-Path $projectRoot $configuredLogoPath
    if (-not (Test-Path -LiteralPath $logoSourcePath -PathType Leaf)) {
        throw "Configured logo not found: $logoSourcePath"
    }

    $embeddedFiles[(Join-Path $embeddedRoot $configuredLogoPath)] = (Resolve-Path -LiteralPath $logoSourcePath).Path
}

$duplicateSourceNames = $embeddedFiles.Values |
    ForEach-Object { Split-Path -Path $_ -Leaf } |
    Group-Object |
    Where-Object { $_.Count -gt 1 }

if ($duplicateSourceNames) {
    $names = ($duplicateSourceNames.Name -join ', ')
    throw "PS2EXE requires embedded source filenames to be unique. Rename: $names"
}

if ([string]::IsNullOrWhiteSpace($IconPath)) {
    $IconPath = [string]$configuration.Build.IconPath
}

$resolvedIconPath = $null
if (-not [string]::IsNullOrWhiteSpace($IconPath)) {
    if (-not [System.IO.Path]::IsPathRooted($IconPath)) {
        $IconPath = Join-Path $projectRoot $IconPath
    }

    $resolvedIconPath = (Resolve-Path -LiteralPath $IconPath).Path
    if ([System.IO.Path]::GetExtension($resolvedIconPath) -ne '.ico') {
        throw 'The executable icon must be an .ico file.'
    }
}

$version = [string]$configuration.Build.Version
if ($version -notmatch '^\d+\.\d+\.\d+\.\d+$') {
    throw 'Build.Version must contain four numeric components, for example 1.0.0.0.'
}

$invokeParameters = @{
    InputFile   = $launcherPath
    OutputFile  = $OutputPath
    EmbedFiles  = $embeddedFiles
    NoConsole   = $true
    NoOutput    = $true
    STA         = $true
    DPIAware    = $true
    SupportOS   = $true
    Title       = [string]$configuration.Application.WindowTitle
    Product     = [string]$configuration.Build.ProductName
    Description = [string]$configuration.Build.Description
    Company     = [string]$configuration.Build.Company
    Copyright   = [string]$configuration.Build.Copyright
    Version     = $version
}

switch ($Architecture) {
    'x64' { $invokeParameters.X64 = $true }
    'x86' { $invokeParameters.X86 = $true }
}

if ($resolvedIconPath) {
    $invokeParameters.IconFile = $resolvedIconPath
}

if (Test-Path -LiteralPath $OutputPath -PathType Leaf) {
    Remove-Item -LiteralPath $OutputPath -Force
}

Invoke-ps2exe @invokeParameters

if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
    throw 'PS2EXE completed without creating the expected output file.'
}

$builtFile = Get-Item -LiteralPath $OutputPath
Write-Host ''
Write-Host 'Build complete' -ForegroundColor Green
Write-Host ('  File: {0}' -f $builtFile.FullName)
Write-Host ('  Size: {0:N2} MB' -f ($builtFile.Length / 1MB))
Write-Host ('  PS2EXE: {0}' -f $availablePS2EXE.Version)
