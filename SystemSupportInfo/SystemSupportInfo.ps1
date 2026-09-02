#requires -Version 5.1

<#
.SYNOPSIS
    Launches the modular System Support Information application.

.DESCRIPTION
    Loads the configured WPF interface and displays copy-friendly Windows
    device information. The same entry point supports normal PowerShell use and
    the PS2EXE build included with this repository.

.PARAMETER ConfigPath
    Optional path to an alternate PSD1 configuration file. Relative paths are
    resolved from the project or embedded application root.

.PARAMETER WindowTitle
    Optional runtime override for Application.WindowTitle.

.PARAMETER LogoPath
    Optional runtime override for Branding.LogoPath.

.PARAMETER ServiceDeskUrl
    Optional runtime override for ServiceDesk.Url. Providing a value enables
    the service desk button.

.PARAMETER ServiceDeskButtonText
    Optional runtime override for ServiceDesk.ButtonText.

.EXAMPLE
    powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\SystemSupportInfo.ps1

.EXAMPLE
    .\SystemSupportInfo.ps1 `
        -WindowTitle 'Contoso IT Support' `
        -ServiceDeskUrl 'https://support.contoso.com' `
        -ServiceDeskButtonText 'Open IT Service Desk'
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$WindowTitle,

    [Parameter()]
    [string]$LogoPath,

    [Parameter()]
    [Alias('SupportUrl')]
    [string]$ServiceDeskUrl,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ServiceDeskButtonText
)

$runtimeResourceVersion = '1.0.0'

function Find-ApplicationRoot {
    [CmdletBinding()]
    param()

    $candidates = [System.Collections.Generic.List[string]]::new()

    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $candidates.Add($PSScriptRoot)
    }

    # PS2EXE 1.0.18 provides $ScriptRoot because $PSScriptRoot is empty inside
    # a compiled executable. It identifies the EXE directory, which is useful
    # when troubleshooting or running with external sidecar files.
    $scriptRootVariable = Get-Variable -Name ScriptRoot -ErrorAction SilentlyContinue
    if ($scriptRootVariable -and -not [string]::IsNullOrWhiteSpace([string]$scriptRootVariable.Value)) {
        $candidates.Add([string]$scriptRootVariable.Value)
    }

    if (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
        $embeddedRoot = Join-Path `
            -Path $env:TEMP `
            -ChildPath ('SystemSupportInfo\{0}' -f $runtimeResourceVersion)
        $candidates.Add($embeddedRoot)
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        $uiModulePath = Join-Path -Path $candidate -ChildPath 'src\SystemSupportInfo.UI.psm1'
        if (Test-Path -LiteralPath $uiModulePath -PathType Leaf) {
            return $candidate
        }
    }

    throw 'Unable to locate the SystemSupportInfo application files. Keep the repository folders together or rebuild the EXE.'
}

$applicationRoot = Find-ApplicationRoot
$uiModule = Join-Path -Path $applicationRoot -ChildPath 'src\SystemSupportInfo.UI.psm1'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $resolvedConfigPath = Join-Path -Path $applicationRoot -ChildPath 'config\SystemSupportInfo.config.psd1'
}
elseif ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    $resolvedConfigPath = $ConfigPath
}
else {
    $resolvedConfigPath = Join-Path -Path $applicationRoot -ChildPath $ConfigPath
}

if (-not (Test-Path -LiteralPath $resolvedConfigPath -PathType Leaf)) {
    throw "Configuration file not found: $resolvedConfigPath"
}

$configuration = Import-PowerShellDataFile -LiteralPath $resolvedConfigPath -ErrorAction Stop

if ($PSBoundParameters.ContainsKey('WindowTitle')) {
    $configuration.Application.WindowTitle = $WindowTitle
}

if ($PSBoundParameters.ContainsKey('LogoPath')) {
    $configuration.Branding.LogoPath = $LogoPath
}

if ($PSBoundParameters.ContainsKey('ServiceDeskUrl')) {
    $configuration.ServiceDesk.Url = $ServiceDeskUrl
    $configuration.ServiceDesk.Enabled = $true
}

if ($PSBoundParameters.ContainsKey('ServiceDeskButtonText')) {
    $configuration.ServiceDesk.ButtonText = $ServiceDeskButtonText
}

Import-Module -Name $uiModule -Force -ErrorAction Stop
Show-SystemSupportInfo -Configuration $configuration -ApplicationRoot $applicationRoot
