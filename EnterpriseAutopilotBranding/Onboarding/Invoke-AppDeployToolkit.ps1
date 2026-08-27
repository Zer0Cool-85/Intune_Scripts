#requires -Version 5.1

<#
.SYNOPSIS
PSAppDeployToolkit host for the visible first-login onboarding workflow.

.DESCRIPTION
Runs as SYSTEM from the staged scheduled task. PSAppDeployToolkit 4.1.8 securely renders the
progress and completion UI in the active user's session; the actual step orchestration remains in
the parent Invoke-PostEnroll.ps1 script so state, logging, and retry behavior do not depend on UI.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [string]$DeploymentType,

    [Parameter()]
    [ValidateSet('Auto', 'Interactive', 'NonInteractive', 'Silent')]
    [string]$DeployMode,

    [Parameter()]
    [switch]$SuppressRebootPassThru,

    [Parameter()]
    [switch]$TerminalServerMode,

    [Parameter()]
    [switch]$DisableLogging
)

$runtimeRoot = Split-Path -Path $PSScriptRoot -Parent
$runtimeConfigPath = Join-Path $runtimeRoot 'Config.xml'
$organizationName = 'Your Company'
$packageVersion = '4.1.0'
if (Test-Path -LiteralPath $runtimeConfigPath -PathType Leaf) {
    try {
        [xml]$runtimeConfig = Get-Content -LiteralPath $runtimeConfigPath -Raw -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace([string]$runtimeConfig.EnterpriseAutopilotBranding.Metadata.OrganizationName)) {
            $organizationName = [string]$runtimeConfig.EnterpriseAutopilotBranding.Metadata.OrganizationName
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$runtimeConfig.EnterpriseAutopilotBranding.PackageVersion)) {
            $packageVersion = [string]$runtimeConfig.EnterpriseAutopilotBranding.PackageVersion
        }
    }
    catch {}
}

$adtSession = @{
    AppVendor                  = $organizationName
    AppName                    = 'Windows Device Setup'
    AppVersion                 = $packageVersion
    AppArch                    = 'All'
    AppLang                    = 'EN'
    AppRevision                = '01'
    AppSuccessExitCodes        = @(0)
    AppRebootExitCodes         = @(1641, 3010)
    AppProcessesToClose        = @()
    AppScriptVersion           = $packageVersion
    AppScriptDate              = '2026-08-27'
    AppScriptAuthor            = $organizationName
    RequireAdmin               = $true
    InstallName                = 'Enterprise Windows Device Setup'
    InstallTitle               = "$organizationName device setup"
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters  = $PSBoundParameters
    DeployAppScriptVersion     = '4.1.8'
}

function Install-ADTDeployment {
    [CmdletBinding()]
    param()

    $adtSession.InstallPhase = $adtSession.DeploymentType
    $workerPath = Join-Path $runtimeRoot 'Invoke-PostEnroll.ps1'
    if (-not (Test-Path -LiteralPath $workerPath -PathType Leaf)) {
        throw "The post-enrollment worker '$workerPath' is missing."
    }

    $workerResult = & $workerPath -UiMode Psadt -ReturnExitCode
    $workerExitCode = [int](@($workerResult)[-1])
    if ($workerExitCode -ne 0) {
        throw "The post-enrollment worker returned exit code $workerExitCode. Review the EnterpriseAutopilotBranding logs and state files."
    }
}

function Uninstall-ADTDeployment {
    [CmdletBinding()]
    param()

    Write-ADTLogEntry -Message 'The onboarding host has no independent uninstall action.'
}

function Repair-ADTDeployment {
    [CmdletBinding()]
    param()

    Install-ADTDeployment
}

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1

try {
    $moduleManifest = Join-Path $PSScriptRoot 'PSAppDeployToolkit\PSAppDeployToolkit.psd1'
    if (-not (Test-Path -LiteralPath $moduleManifest -PathType Leaf)) {
        throw "PSAppDeployToolkit 4.1.8 is not present at '$moduleManifest'."
    }

    Get-ChildItem -LiteralPath (Split-Path -Path $moduleManifest -Parent) -Recurse -File |
        Unblock-File -ErrorAction Ignore
    Import-Module -FullyQualifiedName @{
        ModuleName    = $moduleManifest
        Guid          = '8c3c366b-8606-4576-9f2d-4051144f7ca2'
        ModuleVersion = '4.1.8'
    } -Force

    $sessionParameters = Get-ADTBoundParametersAndDefaultValues -Invocation $MyInvocation
    $adtSession = Remove-ADTHashtableNullOrEmptyValues -Hashtable $adtSession
    $adtSession = Open-ADTSession @adtSession @sessionParameters -PassThru
}
catch {
    $Host.UI.WriteErrorLine((Out-String -InputObject $_ -Width ([int]::MaxValue)))
    exit 60008
}

try {
    & "$($adtSession.DeploymentType)-ADTDeployment"
    Close-ADTSession
}
catch {
    $errorMessage = "The device setup host failed.`n$(Resolve-ADTErrorRecord -ErrorRecord $_)"
    Write-ADTLogEntry -Message $errorMessage -Severity 3
    Close-ADTSession -ExitCode 60001
}
