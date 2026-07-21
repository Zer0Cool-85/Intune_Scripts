#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs Windows name-resolution hardening as an Intune Win32 app.

.DESCRIPTION
    Copies the enforcement script to ProgramData, applies it immediately, and
    registers a SYSTEM scheduled task that reapplies it at startup, at any user
    logon, and every four hours.
#>

[CmdletBinding()]
param()

# Intune launches command-line Win32 installers in a 32-bit process. Relaunch
# this installer in native 64-bit Windows PowerShell before touching HKLM.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $nativePowerShell = Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $nativeArguments = @(
        '-NoProfile'
        '-NonInteractive'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        ('"{0}"' -f $PSCommandPath)
    )

    $nativeProcess = Start-Process -FilePath $nativePowerShell -ArgumentList $nativeArguments -Wait -PassThru
    exit $nativeProcess.ExitCode
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageVersion = '1.0.0'
$expectedScriptSha256 = 'DE20AC8DC1992553D106E6AFF35F2F346C55057BD8E4FF54919FF50B7B430635'
$taskName = 'Windows Name Resolution Hardening'
$installRoot = Join-Path $env:ProgramData 'WindowsNameResolutionHardening'
$installedScript = Join-Path $installRoot 'Set-WindowsNameResolutionHardening.ps1'
$sourceScript = Join-Path $PSScriptRoot 'Set-WindowsNameResolutionHardening.ps1'
$markerPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WindowsNameResolutionHardening'
$installerLog = Join-Path $installRoot 'Installer.log'

function Write-InstallerLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try {
        if (-not (Test-Path -LiteralPath $installRoot)) {
            New-Item -Path $installRoot -ItemType Directory -Force | Out-Null
        }
        Add-Content -LiteralPath $installerLog -Value $line -Encoding UTF8
    }
    catch {
        # Logging must not turn an otherwise successful install into a failure.
    }
    Write-Output $line
}

try {
    Write-InstallerLog -Message "Installing package version $packageVersion in a $([IntPtr]::Size * 8)-bit process."

    if (-not (Test-Path -LiteralPath $sourceScript -PathType Leaf)) {
        throw "Required payload is missing: $sourceScript"
    }

    $sourceHash = (Get-FileHash -LiteralPath $sourceScript -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($sourceHash -ne $expectedScriptSha256) {
        throw "The enforcement script hash is $sourceHash; expected $expectedScriptSha256. Rebuild the package after an intentional script change."
    }

    if (-not (Test-Path -LiteralPath $installRoot)) {
        New-Item -Path $installRoot -ItemType Directory -Force | Out-Null
    }

    Copy-Item -LiteralPath $sourceScript -Destination $installedScript -Force
    Write-InstallerLog -Message "Installed enforcement script at $installedScript."

    $taskCommand = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $taskArguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $installedScript
    $taskAction = New-ScheduledTaskAction -Execute $taskCommand -Argument $taskArguments -WorkingDirectory $installRoot
    $recurringTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Hours 4) -RepetitionDuration (New-TimeSpan -Days 3650)
    $taskTriggers = @(
        (New-ScheduledTaskTrigger -AtStartup)
        (New-ScheduledTaskTrigger -AtLogOn)
        $recurringTrigger
    )
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $taskSettingsParameters = @{
        AllowStartIfOnBatteries = $true
        DontStopIfGoingOnBatteries = $true
        StartWhenAvailable = $true
        ExecutionTimeLimit = (New-TimeSpan -Minutes 15)
        MultipleInstances = 'IgnoreNew'
    }
    $taskSettings = New-ScheduledTaskSettingsSet @taskSettingsParameters
    $registrationParameters = @{
        TaskName = $taskName
        Action = $taskAction
        Trigger = $taskTriggers
        Principal = $taskPrincipal
        Settings = $taskSettings
        Description = 'Reapplies NBT-NS, LLMNR, mDNS, and WPAD hardening.'
        Force = $true
    }

    Register-ScheduledTask @registrationParameters | Out-Null
    $registeredTask = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    if (-not $registeredTask.Settings.Enabled) {
        throw "Scheduled task '$taskName' was registered but is disabled."
    }
    Write-InstallerLog -Message "Registered SYSTEM scheduled task '$taskName'."

    $enforcementArguments = @(
        '-NoProfile'
        '-NonInteractive'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        ('"{0}"' -f $installedScript)
    )
    $enforcementProcess = Start-Process -FilePath $taskCommand -ArgumentList $enforcementArguments -Wait -PassThru -WindowStyle Hidden
    if ($enforcementProcess.ExitCode -ne 0) {
        throw "Initial enforcement returned exit code $($enforcementProcess.ExitCode). Review WindowsNameResolutionHardening.log."
    }
    Write-InstallerLog -Message 'Initial hardening completed successfully.'

    if (-not (Test-Path -LiteralPath $markerPath)) {
        New-Item -Path $markerPath -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $markerPath -Name 'Version' -PropertyType String -Value $packageVersion -Force | Out-Null
    New-ItemProperty -LiteralPath $markerPath -Name 'ScriptSha256' -PropertyType String -Value $expectedScriptSha256 -Force | Out-Null
    New-ItemProperty -LiteralPath $markerPath -Name 'InstallPath' -PropertyType String -Value $installRoot -Force | Out-Null
    New-ItemProperty -LiteralPath $markerPath -Name 'TaskName' -PropertyType String -Value $taskName -Force | Out-Null
    New-ItemProperty -LiteralPath $markerPath -Name 'InstalledUtc' -PropertyType String -Value ([DateTime]::UtcNow.ToString('o')) -Force | Out-Null

    Write-InstallerLog -Message "Package version $packageVersion installed successfully. A restart is recommended after first deployment."
    exit 0
}
catch {
    Write-InstallerLog -Message $_.Exception.Message -Level ERROR
    exit 1
}
