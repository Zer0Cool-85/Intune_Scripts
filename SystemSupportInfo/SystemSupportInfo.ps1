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
    [string]$ServiceDeskButtonText,

    [Parameter()]
    [switch]$StaRelaunched
)

$runtimeResourceVersion = '1.0.2'

if ($env:OS -ne 'Windows_NT') {
    throw 'SystemSupportInfo requires Windows because its interface uses WPF.'
}

if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    if ($StaRelaunched) {
        throw 'PowerShell did not enter STA mode. Start the script with powershell.exe -STA or pwsh.exe -STA.'
    }

    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        throw 'This host is not running in STA mode and the launcher path is unavailable. Start with powershell.exe -STA or pwsh.exe -STA.'
    }

    $shellExecutableName = if ($PSVersionTable.PSEdition -eq 'Core') {
        'pwsh.exe'
    }
    else {
        'powershell.exe'
    }

    $shellExecutablePath = Join-Path -Path $PSHOME -ChildPath $shellExecutableName
    if (-not (Test-Path -LiteralPath $shellExecutablePath -PathType Leaf)) {
        $shellCommand = Get-Command `
            -Name $shellExecutableName `
            -CommandType Application `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($shellCommand) {
            $shellExecutablePath = $shellCommand.Source
        }
        else {
            throw "Unable to locate $shellExecutableName for the required STA relaunch."
        }
    }

    $forwardedArguments = [System.Collections.Generic.List[string]]::new()
    foreach ($parameterName in @(
        'ConfigPath',
        'WindowTitle',
        'LogoPath',
        'ServiceDeskUrl',
        'ServiceDeskButtonText'
    )) {
        if ($PSBoundParameters.ContainsKey($parameterName)) {
            $forwardedArguments.Add("-$parameterName")
            $forwardedArguments.Add([string]$PSBoundParameters[$parameterName])
        }
    }

    $forwardedArguments.Add('-StaRelaunched')
    $shellArguments = @(
        '-NoLogo'
        '-NoProfile'
        '-STA'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $PSCommandPath
    ) + $forwardedArguments.ToArray()

    & $shellExecutablePath @shellArguments
    if ($LASTEXITCODE -ne 0) {
        throw "The STA PowerShell process exited with code $LASTEXITCODE."
    }

    return
}

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
        $configurationModulePath = Join-Path -Path $candidate -ChildPath 'src\SystemSupportInfo.Configuration.psm1'
        if (
            (Test-Path -LiteralPath $uiModulePath -PathType Leaf) -and
            (Test-Path -LiteralPath $configurationModulePath -PathType Leaf)
        ) {
            return $candidate
        }
    }

    throw 'Unable to locate the SystemSupportInfo application files. Keep the repository folders together or rebuild the EXE.'
}

$applicationRoot = Find-ApplicationRoot
$uiModule = Join-Path -Path $applicationRoot -ChildPath 'src\SystemSupportInfo.UI.psm1'
$configurationModule = Join-Path -Path $applicationRoot -ChildPath 'src\SystemSupportInfo.Configuration.psm1'

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

Import-Module -Name $configurationModule -Force -ErrorAction Stop
$configuration = Import-SystemSupportConfiguration -LiteralPath $resolvedConfigPath

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
