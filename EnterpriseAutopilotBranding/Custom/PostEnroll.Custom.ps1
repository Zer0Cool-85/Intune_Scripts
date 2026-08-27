#requires -Version 5.1

<#
.SYNOPSIS
Optional organization-owned manifest step for post-enrollment work.

.DESCRIPTION
This sample is configured as a disabled Device-scoped PowerShell step. Keep it idempotent: check
the current state before changing anything, throw on failures that should cause a retry, increment
the step Version after behavioral changes, and never embed credentials or shared passwords.

Replace the example body with your existing post-enrollment workflow. Any supporting scripts or
installers can be placed under Custom\Payloads; the complete Custom directory is staged under
%ProgramData%\EnterpriseAutopilotBranding\Runtime before the scheduled task is registered.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigurationPath,

    [Parameter(Mandatory)]
    [string]$LogDirectory,

    [Parameter(Mandatory)]
    [string]$StateDirectory,

    [Parameter()]
    [AllowNull()]
    [string]$InteractiveUser,

    [Parameter()]
    [AllowNull()]
    [string]$InteractiveUserSid
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$runtimeRoot = Split-Path -Path $PSScriptRoot -Parent
$modulePath = Join-Path $runtimeRoot 'Modules\EnterpriseAutopilotBranding.psm1'
Import-Module -Name $modulePath -Force -ErrorAction Stop
Initialize-EabLogging -LogDirectory $LogDirectory -Component 'CustomPostEnroll'

Write-EabLog -Component 'CustomPostEnroll' -Message "Custom hook reached for interactive user '$InteractiveUser' (SID '$InteractiveUserSid')."

# Example payload path:
# $installer = Join-Path $PSScriptRoot 'Payloads\YourInstaller.exe'
# if (Test-Path -LiteralPath $installer) {
#     Invoke-EabNativeProcess -FilePath $installer -ArgumentString '/quiet /norestart' -AcceptedExitCodes @(0, 1641, 3010) -TimeoutSeconds 1800 | Out-Null
# }

# Example: call an existing organization script and allow terminating errors to bubble up:
# $existingScript = Join-Path $PSScriptRoot 'Your-Existing-PostEnroll.ps1'
# & $existingScript -InteractiveUser $InteractiveUser -InteractiveUserSid $InteractiveUserSid

Write-EabLog -Component 'CustomPostEnroll' -Message 'No organization-specific actions are configured in the sample custom hook.'
