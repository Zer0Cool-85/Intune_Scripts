#requires -Version 5.1

<#
.SYNOPSIS
Audits or enforces the standalone Enterprise Autopilot Branding debloat catalog.

.DESCRIPTION
Runs only the debloat engine from Config.xml. Audit is the default and makes no application or
shortcut changes. Enforce requires confirmation unless -Confirm:$false is supplied for an
unattended, previously tested deployment.

.PARAMETER Mode
Audit reports matching items. Enforce removes only enabled catalog matches that are not protected
by a preservation rule.

.PARAMETER ConfigurationPath
Path to the configuration file. Defaults to Config.xml beside this script.

.PARAMETER OutputPath
Path for the JSON report. Defaults to the product state directory under ProgramData.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateSet('Audit', 'Enforce')]
    [string]$Mode = 'Audit',

    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ConfigurationPath = (Join-Path $PSScriptRoot 'Config.xml'),

    [Parameter()]
    [string]$OutputPath = (Join-Path $env:ProgramData 'EnterpriseAutopilotBranding\State\Debloat-Manual.json')
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if (-not [Environment]::Is64BitProcess) {
    throw 'Run Invoke-Debloat.ps1 from 64-bit Windows PowerShell.'
}

$modulePath = Join-Path $PSScriptRoot 'Modules\EnterpriseAutopilotBranding.psm1'
$logDirectory = Join-Path $env:ProgramData 'EnterpriseAutopilotBranding\Logs'

Import-Module -Name $modulePath -Force -ErrorAction Stop
if (-not (Test-EabIsAdministrator)) {
    throw 'Invoke-Debloat.ps1 must run from an elevated administrator or SYSTEM context.'
}

Initialize-EabLogging -LogDirectory $logDirectory -Component 'ManualDebloat'
$config = Import-EabConfiguration -Path $ConfigurationPath
$config.Debloat.SetAttribute('Mode', $Mode)

if ($Mode -eq 'Enforce' -and -not $PSCmdlet.ShouldProcess(
        $env:COMPUTERNAME,
        'Remove enabled Config.xml debloat matches that are not protected by preservation rules')) {
    Write-EabLog -Component 'ManualDebloat' -Message 'Enforcement was not approved; no changes were made.'
    exit 0
}

$inventory = Get-EabDebloatInventory
$summary = Invoke-EabDebloat -Config $config -Phase Manual
$report = [ordered]@{
    Summary   = $summary
    Inventory = $inventory
}
Write-EabStateFile -Path $OutputPath -State $report
Write-EabLog -Component 'ManualDebloat' -Message "Debloat report written to '$OutputPath'."

if ($Mode -eq 'Enforce' -and [int]$summary.FailureCount -gt 0) {
    exit 1
}

Write-Output "Debloat $Mode completed. Matches: $($summary.AuditCount); removed: $($summary.RemovedCount); failed or unsupported: $($summary.FailureCount). Report: $OutputPath"
exit 0
