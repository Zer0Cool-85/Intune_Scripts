#requires -version 5.1
<#
.SYNOPSIS
    Installs a scheduled remediation runner as a SYSTEM scheduled task.

.DESCRIPTION
    Intended for deployment as a Microsoft Intune Win32 app.
    Copies Invoke-RemediationRunner.ps1 to ProgramData, creates/updates a SYSTEM scheduled task,
    and writes a registry marker for detection/reporting.

.INTUNE INSTALL COMMAND
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-ScheduledRemediation.ps1

.NOTES
    Customize the variables in the "Configuration" region before packaging.
#>

[CmdletBinding()]
param(
    [string]$CompanyName = 'Contoso',
    [string]$AppName = 'ScheduledRemediation',
    [string]$TaskName = 'Contoso - Scheduled Remediation',
    [string]$TaskPath = '\Contoso\',
    [string]$Version = '1.0.0',

    # Daily trigger begins at this local time, then repeats using $RepeatIntervalHours for one day.
    [string]$DailyStartTime = '08:00',
    [ValidateRange(1,23)]
    [int]$RepeatIntervalHours = 4,

    # Startup trigger delay. Useful so the network and Intune Management Extension can settle first.
    [ValidateRange(0,120)]
    [int]$StartupDelayMinutes = 5
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
        $argList += "-$key"
        $argList += "`"$value`""
    }

    Start-Process -FilePath $sysNativePowerShell -ArgumentList $argList -Wait
    exit $LASTEXITCODE
}
#endregion

#region Configuration
$InstallRoot = Join-Path -Path $env:ProgramData -ChildPath "$CompanyName\$AppName"
$ScriptName  = 'Invoke-RemediationRunner.ps1'
$SourceScript = Join-Path -Path $PSScriptRoot -ChildPath $ScriptName
$TargetScript = Join-Path -Path $InstallRoot -ChildPath $ScriptName

$RegistryPath = "HKLM:\SOFTWARE\$CompanyName\$AppName"
$LogRoot = Join-Path -Path $InstallRoot -ChildPath 'Logs'
$InstallLog = Join-Path -Path $LogRoot -ChildPath 'Install.log'
#endregion

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
    Add-Content -LiteralPath $InstallLog -Value "[$timestamp][$Level] $Message"
}

try {
    Write-Log "Starting install. Version=$Version"

    if (-not (Test-Path -LiteralPath $SourceScript)) {
        throw "Required source script not found: $SourceScript"
    }

    New-Item -Path $InstallRoot -ItemType Directory -Force | Out-Null
    New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null

    Copy-Item -LiteralPath $SourceScript -Destination $TargetScript -Force
    Write-Log "Copied runner to $TargetScript"

    if (-not (Test-Path -LiteralPath $RegistryPath)) {
        New-Item -Path $RegistryPath -Force | Out-Null
    }

    New-ItemProperty -Path $RegistryPath -Name 'Version' -Value $Version -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegistryPath -Name 'InstallRoot' -Value $InstallRoot -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegistryPath -Name 'TaskName' -Value $TaskName -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegistryPath -Name 'TaskPath' -Value $TaskPath -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegistryPath -Name 'InstalledUtc' -Value ((Get-Date).ToUniversalTime().ToString('o')) -PropertyType String -Force | Out-Null

    $powerShellExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $actionArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$TargetScript`""
    $action = New-ScheduledTaskAction -Execute $powerShellExe -Argument $actionArgs

    $dailyAt = [datetime]::ParseExact($DailyStartTime, 'HH:mm', $null)
    $dailyTrigger = New-ScheduledTaskTrigger -Daily -At $dailyAt
    $dailyTrigger.Repetition.Interval = "PT$($RepeatIntervalHours)H"
    $dailyTrigger.Repetition.Duration = 'P1D'

    $startupTrigger = New-ScheduledTaskTrigger -AtStartup
    if ($StartupDelayMinutes -gt 0) {
        $startupTrigger.Delay = "PT$($StartupDelayMinutes)M"
    }

    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

    $task = New-ScheduledTask -Action $action -Trigger @($startupTrigger, $dailyTrigger) -Principal $principal -Settings $settings

    Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -InputObject $task -Force | Out-Null
    Write-Log "Registered scheduled task: $TaskPath$TaskName"

    # Optional: Run once shortly after installation so devices don't wait until next scheduled trigger.
    Start-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
    Write-Log "Started scheduled task once after install."

    Write-Log 'Install completed successfully.'
    exit 0
}
catch {
    Write-Log -Message "Install failed: $($_.Exception.Message)" -Level ERROR
    exit 1
}
