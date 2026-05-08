#requires -version 5.1
<#
.SYNOPSIS
    Removes the scheduled remediation runner and scheduled task.

.INTUNE UNINSTALL COMMAND
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-ScheduledRemediation.ps1
#>

[CmdletBinding()]
param(
    [string]$CompanyName = 'Contoso',
    [string]$AppName = 'ScheduledRemediation',
    [string]$TaskName = 'Contoso - Scheduled Remediation',
    [string]$TaskPath = '\Contoso\',
    [switch]$KeepLogs
)

#region Relaunch 64-bit PowerShell if needed
if ($env:PROCESSOR_ARCHITEW6432 -and $PSHOME -like '*SysWOW64*') {
    $sysNativePowerShell = "$env:WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
    $argList = @(
        '-ExecutionPolicy', 'Bypass',
        '-NoProfile',
        '-File', "`"$PSCommandPath`""
    )

    foreach ($key in $PSBoundParameters.Keys) {
        $value = $PSBoundParameters[$key]
        if ($value -is [switch] -and $value.IsPresent) {
            $argList += "-$key"
        }
        else {
            $argList += "-$key"
            $argList += "`"$value`""
        }
    }

    Start-Process -FilePath $sysNativePowerShell -ArgumentList $argList -Wait
    exit $LASTEXITCODE
}
#endregion

$InstallRoot = Join-Path -Path $env:ProgramData -ChildPath "$CompanyName\$AppName"
$RegistryPath = "HKLM:\SOFTWARE\$CompanyName\$AppName"
$LogRoot = Join-Path -Path $InstallRoot -ChildPath 'Logs'
$UninstallLog = Join-Path -Path $LogRoot -ChildPath 'Uninstall.log'

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO'
    )

    if (-not (Test-Path -LiteralPath $LogRoot)) {
        New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
    }

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-Content -LiteralPath $UninstallLog -Value "[$timestamp][$Level] $Message"
}

try {
    Write-Log 'Starting uninstall.'

    $existingTask = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
    if ($existingTask) {
        try {
            Stop-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
        }
        catch {}
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false
        Write-Log "Removed scheduled task: $TaskPath$TaskName"
    }
    else {
        Write-Log "Scheduled task not found: $TaskPath$TaskName"
    }

    if (Test-Path -LiteralPath $RegistryPath) {
        Remove-Item -LiteralPath $RegistryPath -Recurse -Force
        Write-Log "Removed registry marker: $RegistryPath"
    }

    if (Test-Path -LiteralPath $InstallRoot) {
        if ($KeepLogs) {
            Get-ChildItem -LiteralPath $InstallRoot -Force |
                Where-Object { $_.Name -ne 'Logs' } |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

            Write-Log "Removed app files but preserved logs at $LogRoot"
        }
        else {
            Remove-Item -LiteralPath $InstallRoot -Recurse -Force
        }
    }

    exit 0
}
catch {
    Write-Log -Message "Uninstall failed: $($_.Exception.Message)" -Level ERROR
    exit 1
}
