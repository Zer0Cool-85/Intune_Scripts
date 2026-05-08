#requires -version 5.1
<#
.SYNOPSIS
    Intune Win32 custom detection script for the scheduled remediation app.

.INTUNE DETECTION
    Add this as a custom detection script.
    Intune considers the app detected when the script exits 0 and writes output.
#>

[CmdletBinding()]
param(
    [string]$CompanyName = 'Contoso',
    [string]$AppName = 'ScheduledRemediation',
    [string]$TaskName = 'Contoso - Scheduled Remediation',
    [string]$TaskPath = '\Contoso\',
    [string]$RequiredVersion = '1.0.0'
)

$InstallRoot = Join-Path -Path $env:ProgramData -ChildPath "$CompanyName\$AppName"
$Runner = Join-Path -Path $InstallRoot -ChildPath 'Invoke-RemediationRunner.ps1'
$RegistryPath = "HKLM:\SOFTWARE\$CompanyName\$AppName"

try {
    $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop

    if (-not (Test-Path -LiteralPath $Runner)) {
        throw "Runner missing: $Runner"
    }

    if (-not (Test-Path -LiteralPath $RegistryPath)) {
        throw "Registry marker missing: $RegistryPath"
    }

    $props = Get-ItemProperty -Path $RegistryPath -ErrorAction Stop
    if ($props.Version -ne $RequiredVersion) {
        throw "Version mismatch. Found '$($props.Version)', expected '$RequiredVersion'."
    }

    if ($task.State -eq 'Disabled') {
        throw 'Scheduled task is disabled.'
    }

    Write-Output "Detected $AppName $RequiredVersion"
    exit 0
}
catch {
    Write-Output "Not detected: $($_.Exception.Message)"
    exit 1
}
