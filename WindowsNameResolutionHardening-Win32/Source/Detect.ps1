#Requires -Version 5.1

<#
.SYNOPSIS
    Custom Intune Win32 detection script for Windows name-resolution hardening.

.NOTES
    Intune detects the app only when this script exits 0 and writes to STDOUT.
    Every failure path intentionally exits 1 and writes only to STDOUT, never
    STDERR.
#>

[CmdletBinding()]
param()

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    try {
        $nativePowerShell = Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
        & $nativePowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath
        exit $LASTEXITCODE
    }
    catch {
        Write-Output "Not detected: unable to relaunch detection in 64-bit PowerShell: $($_.Exception.Message)"
        exit 1
    }
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageVersion = '1.0.0'
$expectedScriptSha256 = 'DE20AC8DC1992553D106E6AFF35F2F346C55057BD8E4FF54919FF50B7B430635'
$taskName = 'Windows Name Resolution Hardening'
$installRoot = Join-Path $env:ProgramData 'WindowsNameResolutionHardening'
$installedScript = Join-Path $installRoot 'Set-WindowsNameResolutionHardening.ps1'
$markerPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WindowsNameResolutionHardening'
$failures = [System.Collections.Generic.List[string]]::new()

function Add-DetectionFailure {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $failures.Contains($Message)) {
        $failures.Add($Message)
    }
}

function Test-RegistryDword {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [int]$ExpectedValue,

        [Parameter(Mandatory)]
        [string]$ControlName
    )

    try {
        $actual = Get-ItemPropertyValue -LiteralPath $Path -Name $Name -ErrorAction Stop
        if ([int]$actual -ne $ExpectedValue) {
            Add-DetectionFailure -Message "$ControlName is $actual; expected $ExpectedValue."
        }
    }
    catch {
        Add-DetectionFailure -Message "$ControlName is missing or unreadable."
    }
}

function Test-AutoDetectConnectionValue {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$ControlName
    )

    try {
        $value = Get-ItemPropertyValue -LiteralPath $Path -Name $Name -ErrorAction Stop
    }
    catch {
        # A connection blob is optional. If it exists, its auto-detect bit must
        # be disabled; absence isn't noncompliance.
        return
    }

    if ($value -isnot [byte[]] -or $value.Length -lt 9) {
        Add-DetectionFailure -Message "$ControlName has an unexpected binary format."
        return
    }

    if (($value[8] -band 0x08) -ne 0) {
        Add-DetectionFailure -Message "$ControlName still has the automatic proxy detection bit enabled."
    }
}

try {
    if (-not (Test-Path -LiteralPath $markerPath)) {
        Add-DetectionFailure -Message 'The package marker registry key is missing.'
    }
    else {
        try {
            $marker = Get-ItemProperty -LiteralPath $markerPath -ErrorAction Stop
            if ([string]$marker.Version -ne $packageVersion) {
                Add-DetectionFailure -Message "Installed package version '$($marker.Version)' does not equal '$packageVersion'."
            }
            if ([string]$marker.ScriptSha256 -ne $expectedScriptSha256) {
                Add-DetectionFailure -Message 'The installed package marker contains an unexpected script hash.'
            }
            if ([string]$marker.TaskName -ne $taskName) {
                Add-DetectionFailure -Message 'The installed package marker contains an unexpected task name.'
            }
        }
        catch {
            Add-DetectionFailure -Message 'The package marker is incomplete or unreadable.'
        }
    }

    if (-not (Test-Path -LiteralPath $installedScript -PathType Leaf)) {
        Add-DetectionFailure -Message "The installed enforcement script is missing: $installedScript"
    }
    else {
        try {
            $installedHash = (Get-FileHash -LiteralPath $installedScript -Algorithm SHA256).Hash.ToUpperInvariant()
            if ($installedHash -ne $expectedScriptSha256) {
                Add-DetectionFailure -Message "The installed enforcement script hash is $installedHash; expected $expectedScriptSha256."
            }
        }
        catch {
            Add-DetectionFailure -Message 'The installed enforcement script hash could not be calculated.'
        }
    }

    try {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
        if (-not $task.Settings.Enabled) {
            Add-DetectionFailure -Message "Scheduled task '$taskName' is disabled."
        }

        $action = @($task.Actions) | Select-Object -First 1
        if ($null -eq $action) {
            Add-DetectionFailure -Message "Scheduled task '$taskName' has no action."
        }
        else {
            $expectedPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
            if ([string]$action.Execute -ne $expectedPowerShell) {
                Add-DetectionFailure -Message "Scheduled task '$taskName' has an unexpected executable."
            }
            if ([string]$action.Arguments -notlike "*$installedScript*") {
                Add-DetectionFailure -Message "Scheduled task '$taskName' does not reference the installed enforcement script."
            }
        }

        $triggerTypes = @($task.Triggers | ForEach-Object { $_.CimClass.CimClassName })
        foreach ($requiredTrigger in @('MSFT_TaskBootTrigger', 'MSFT_TaskLogonTrigger', 'MSFT_TaskTimeTrigger')) {
            if ($triggerTypes -notcontains $requiredTrigger) {
                Add-DetectionFailure -Message "Scheduled task '$taskName' is missing trigger type $requiredTrigger."
            }
        }

        $recurringTrigger = @($task.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskTimeTrigger' }) | Select-Object -First 1
        if ($null -ne $recurringTrigger) {
            try {
                $repetitionInterval = [System.Xml.XmlConvert]::ToTimeSpan([string]$recurringTrigger.Repetition.Interval)
                if ($repetitionInterval -ne (New-TimeSpan -Hours 4)) {
                    Add-DetectionFailure -Message "Scheduled task '$taskName' doesn't have the expected four-hour repetition interval."
                }
            }
            catch {
                Add-DetectionFailure -Message "Scheduled task '$taskName' has an unreadable repetition interval."
            }
        }
    }
    catch {
        Add-DetectionFailure -Message "Scheduled task '$taskName' is missing or unreadable."
    }

    $dnsPolicyPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
    $dnsRuntimePath = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters'
    $winHttpPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp'
    $machineInternetSettingsPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings'
    $machineConnectionsPath = "$machineInternetSettingsPath\Connections"

    Test-RegistryDword -Path $dnsPolicyPath -Name 'EnableMulticast' -ExpectedValue 0 -ControlName 'LLMNR policy'
    Test-RegistryDword -Path $dnsPolicyPath -Name 'EnableNetbios' -ExpectedValue 0 -ControlName 'NBT-NS DNS Client policy'
    Test-RegistryDword -Path $dnsRuntimePath -Name 'EnableNetbios' -ExpectedValue 0 -ControlName 'NBT-NS DNS Client runtime setting'
    Test-RegistryDword -Path $dnsPolicyPath -Name 'EnableMDNS' -ExpectedValue 0 -ControlName 'mDNS policy'
    Test-RegistryDword -Path $dnsRuntimePath -Name 'EnableMDNS' -ExpectedValue 0 -ControlName 'mDNS DNS Client runtime setting'
    Test-RegistryDword -Path $winHttpPath -Name 'DisableWpad' -ExpectedValue 1 -ControlName 'WinHTTP WPAD setting'
    Test-RegistryDword -Path $machineInternetSettingsPath -Name 'AutoDetect' -ExpectedValue 0 -ControlName 'Machine proxy AutoDetect setting'
    Test-AutoDetectConnectionValue -Path $machineConnectionsPath -Name 'DefaultConnectionSettings' -ControlName 'Machine DefaultConnectionSettings'
    Test-AutoDetectConnectionValue -Path $machineConnectionsPath -Name 'SavedLegacySettings' -ControlName 'Machine SavedLegacySettings'

    $netBtInterfacesPath = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'
    try {
        $interfaceKeys = @(Get-ChildItem -LiteralPath $netBtInterfacesPath -ErrorAction Stop)
        if ($interfaceKeys.Count -eq 0) {
            Add-DetectionFailure -Message 'No NetBT interface registry keys were found.'
        }
        foreach ($interfaceKey in $interfaceKeys) {
            try {
                $netbiosOption = Get-ItemPropertyValue -LiteralPath $interfaceKey.PSPath -Name 'NetbiosOptions' -ErrorAction Stop
                if ([int]$netbiosOption -ne 2) {
                    Add-DetectionFailure -Message "NetBIOS over TCP/IP is not disabled on interface '$($interfaceKey.PSChildName)'."
                }
            }
            catch {
                Add-DetectionFailure -Message "NetBIOS state is missing or unreadable on interface '$($interfaceKey.PSChildName)'."
            }
        }
    }
    catch {
        Add-DetectionFailure -Message 'NetBT interface settings could not be enumerated.'
    }

    $profileListPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    try {
        $loadedUserSids = @(
            Get-ChildItem -LiteralPath $profileListPath -ErrorAction Stop |
                Where-Object { $_.PSChildName -match '^S-1-(5-21|12-1)-' } |
                Select-Object -ExpandProperty PSChildName |
                Where-Object { Test-Path -LiteralPath "Registry::HKEY_USERS\$_" }
        )

        foreach ($sid in $loadedUserSids) {
            $userInternetSettingsPath = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
            $userWpadPath = "$userInternetSettingsPath\Wpad"
            $userConnectionsPath = "$userInternetSettingsPath\Connections"

            Test-RegistryDword -Path $userInternetSettingsPath -Name 'AutoDetect' -ExpectedValue 0 -ControlName "User $sid proxy AutoDetect setting"
            Test-RegistryDword -Path $userWpadPath -Name 'WpadOverride' -ExpectedValue 1 -ControlName "User $sid WPAD override"
            Test-AutoDetectConnectionValue -Path $userConnectionsPath -Name 'DefaultConnectionSettings' -ControlName "User $sid DefaultConnectionSettings"
            Test-AutoDetectConnectionValue -Path $userConnectionsPath -Name 'SavedLegacySettings' -ControlName "User $sid SavedLegacySettings"
        }
    }
    catch {
        Add-DetectionFailure -Message 'Loaded user WPAD settings could not be enumerated.'
    }
}
catch {
    Add-DetectionFailure -Message "Unexpected detection exception: $($_.Exception.Message)"
}

if ($failures.Count -eq 0) {
    Write-Output "Detected Windows Name Resolution Hardening $packageVersion; all controls are compliant."
    exit 0
}

Write-Output "Not detected: $($failures.Count) compliance check(s) failed."
foreach ($failure in $failures) {
    Write-Output " - $failure"
}
exit 1
