#requires -Version 5.1

<#
.SYNOPSIS
Optional first-login AWS VPN Client installation step.

.DESCRIPTION
Calls the organization's existing AWS VPN PSADT package after confirming that the machine-wide
client is not already installed. Copy that complete package to Custom\Payloads\AWSVPN_PSADT and
enable the AwsVpn.Install step in Config.xml. The AWS installer itself is intentionally not bundled.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigurationPath,
    [Parameter(Mandatory)][string]$LogDirectory,
    [Parameter(Mandatory)][string]$StateDirectory,
    [Parameter()][AllowEmptyString()][string]$InteractiveUser,
    [Parameter()][AllowEmptyString()][string]$InteractiveUserSid
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$runtimeRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$modulePath = Join-Path $runtimeRoot 'Modules\EnterpriseAutopilotBranding.psm1'
Import-Module -Name $modulePath -Force -ErrorAction Stop
Initialize-EabLogging -LogDirectory $LogDirectory -Component 'AwsVpn'

function Test-AwsVpnClientInstalled {
    $executableCandidates = New-Object System.Collections.Generic.List[string]
    foreach ($programFilesRoot in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not [string]::IsNullOrWhiteSpace([string]$programFilesRoot)) {
            $executableCandidates.Add((Join-Path $programFilesRoot 'Amazon\AWS VPN Client\AWSVPNClient.exe'))
        }
    }

    if (@($executableCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count -gt 0) {
        return $true
    }

    return @(
        Get-EabClassicApplicationInventory |
            Where-Object { [string]$_.DisplayName -like '*AWS VPN Client*' } |
            Select-Object -First 1
    ).Count -gt 0
}

if (Test-AwsVpnClientInstalled) {
    Write-EabLog -Component 'AwsVpn' -Message 'AWS VPN Client is already installed; no action is required.'
    exit 0
}

$payloadRoot = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'Payloads\AWSVPN_PSADT'
$launcher = Join-Path $payloadRoot 'Invoke-AppDeployToolkit.exe'
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
    throw "AWS VPN payload is missing. Copy the existing PSADT package to '$payloadRoot' or keep AwsVpn.Install disabled in Config.xml."
}

Write-EabLog -Component 'AwsVpn' -Message "Launching the staged AWS VPN installer for '$InteractiveUser'."
$exitCode = Invoke-EabNativeProcess -FilePath $launcher -ArgumentString '-DeploymentType Install -DeployMode Silent' -AcceptedExitCodes @(0, 1641, 3010) -TimeoutSeconds 1800 -WorkingDirectory $payloadRoot

if (-not (Test-AwsVpnClientInstalled)) {
    throw "The AWS VPN installer returned exit code $exitCode, but the client could not be detected."
}

Write-EabLog -Component 'AwsVpn' -Message "AWS VPN Client installation completed with exit code $exitCode."
exit $exitCode
