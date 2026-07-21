#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Disables NBT-NS, LLMNR, mDNS, and WPAD on Windows 10/11 devices.

.DESCRIPTION
    Intended for deployment by Microsoft Intune in the SYSTEM context. The
    script is idempotent and can safely be run repeatedly as an Intune
    remediation.

    Changes made:
      - NBT-NS:
          * Disables NetBIOS name resolution through DNS Client policy.
          * Disables NetBIOS over TCP/IP on every existing adapter.
      - LLMNR:
          * Enables the "Turn off multicast name resolution" policy.
      - mDNS:
          * Disables the Windows DNS Client mDNS resolver.
      - WPAD:
          * Disables WinHTTP WPAD discovery.
          * Disables automatic proxy discovery at the machine level.
          * Disables automatic proxy discovery for currently loaded user
            profiles while preserving their other proxy settings.

    The script does not disable WinHttpAutoProxySvc. Disabling that service can
    interfere with Windows components that use WinHTTP even when WPAD itself is
    disabled.

    For complete mDNS blocking, also deploy MDM-managed inbound and outbound
    firewall block rules for UDP 5353. The registry settings in this script
    disable the Windows resolver but cannot prevent an application from using
    its own mDNS implementation.

.PARAMETER ConfigureLoadedUserWpad
    When true, disables WinINET automatic proxy discovery for every user hive
    that is loaded when the script runs. Default: true.

.PARAMETER LogPath
    Location of the execution log.

.NOTES
    Recommended Intune Platform Script settings:
      Run this script using the logged-on credentials: No
      Enforce script signature check: No (unless you sign the script)
      Run script in 64-bit PowerShell host: Yes

    Exit codes:
      0 = All configured settings verified successfully
      1 = One or more settings failed verification

    A restart is recommended after first application. The script does not
    restart the device automatically.
#>

[CmdletBinding()]
param(
    [bool]$ConfigureLoadedUserWpad = $true,

    [string]$LogPath = "$env:ProgramData\WindowsNameResolutionHardening\WindowsNameResolutionHardening.log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Failures = [System.Collections.Generic.List[string]]::new()
$script:ChangesMade = $false
$script:RebootRecommended = $false

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message

    try {
        $directory = Split-Path -Path $LogPath -Parent
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }

        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    }
    catch {
        Write-Host "Unable to write to log file: $($_.Exception.Message)"
    }

    Write-Host $line
}

function Add-Failure {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $script:Failures.Contains($Message)) {
        $script:Failures.Add($Message)
    }

    Write-Log -Message $Message -Level ERROR
}

function Get-RegistryValue {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name
    )

    try {
        return Get-ItemPropertyValue -LiteralPath $Path -Name $Name -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Set-RegistryDword {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [int]$Value
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }

        $currentValue = Get-RegistryValue -Path $Path -Name $Name
        if ($null -ne $currentValue -and [int]$currentValue -eq $Value) {
            Write-Log -Message "Already configured: $Path\$Name = $Value"
            return $false
        }

        New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
        Write-Log -Message "Configured: $Path\$Name = $Value"
        $script:ChangesMade = $true
        return $true
    }
    catch {
        Add-Failure -Message "Failed to configure $Path\${Name}: $($_.Exception.Message)"
        return $false
    }
}

function Test-RegistryDword {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [int]$ExpectedValue
    )

    $actualValue = Get-RegistryValue -Path $Path -Name $Name
    return ($null -ne $actualValue -and [int]$actualValue -eq $ExpectedValue)
}

function Disable-AutoDetectFlag {
    param(
        [Parameter(Mandatory)]
        [string]$ConnectionsPath,

        [Parameter(Mandatory)]
        [string]$ValueName
    )

    try {
        if (-not (Test-Path -LiteralPath $ConnectionsPath)) {
            return $false
        }

        $value = Get-RegistryValue -Path $ConnectionsPath -Name $ValueName
        if ($null -eq $value) {
            return $false
        }

        if ($value -isnot [byte[]] -or $value.Length -lt 9) {
            Write-Log -Message "Skipped unexpected $ValueName format at $ConnectionsPath" -Level WARN
            return $false
        }

        [byte[]]$updatedValue = $value.Clone()
        $originalFlags = $updatedValue[8]
        $updatedValue[8] = [byte]($updatedValue[8] -band 0xF7)

        if ($updatedValue[8] -eq $originalFlags) {
            Write-Log -Message "Automatic proxy detection already disabled in $ConnectionsPath\$ValueName"
            return $false
        }

        Set-ItemProperty -LiteralPath $ConnectionsPath -Name $ValueName -Value $updatedValue -Force
        Write-Log -Message "Disabled automatic proxy detection in $ConnectionsPath\$ValueName"
        $script:ChangesMade = $true
        return $true
    }
    catch {
        Add-Failure -Message "Failed to update $ConnectionsPath\${ValueName}: $($_.Exception.Message)"
        return $false
    }
}

function Test-AutoDetectFlagDisabled {
    param(
        [Parameter(Mandatory)]
        [string]$ConnectionsPath,

        [Parameter(Mandatory)]
        [string]$ValueName
    )

    $value = Get-RegistryValue -Path $ConnectionsPath -Name $ValueName
    if ($null -eq $value) {
        return $null
    }

    if ($value -isnot [byte[]] -or $value.Length -lt 9) {
        return $false
    }

    return (($value[8] -band 0x08) -eq 0)
}

function Disable-WpadForLoadedUsers {
    $profileListPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'

    try {
        $profileSids = @(
            Get-ChildItem -LiteralPath $profileListPath -ErrorAction Stop |
                Where-Object { $_.PSChildName -match '^S-1-(5-21|12-1)-' } |
                Select-Object -ExpandProperty PSChildName
        )
    }
    catch {
        Add-Failure -Message "Unable to enumerate Windows user profiles: $($_.Exception.Message)"
        return
    }

    foreach ($sid in $profileSids) {
        $hiveRoot = "Registry::HKEY_USERS\$sid"
        if (-not (Test-Path -LiteralPath $hiveRoot)) {
            Write-Log -Message "User hive is not currently loaded; skipped per-user WPAD setting for $sid" -Level WARN
            continue
        }

        $internetSettingsPath = "$hiveRoot\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
        $connectionsPath = "$internetSettingsPath\Connections"
        $wpadPath = "$internetSettingsPath\Wpad"

        [void](Set-RegistryDword -Path $internetSettingsPath -Name 'AutoDetect' -Value 0)
        [void](Set-RegistryDword -Path $wpadPath -Name 'WpadOverride' -Value 1)
        [void](Disable-AutoDetectFlag -ConnectionsPath $connectionsPath -ValueName 'DefaultConnectionSettings')
        [void](Disable-AutoDetectFlag -ConnectionsPath $connectionsPath -ValueName 'SavedLegacySettings')
    }
}

function Disable-NetBiosOnExistingAdapters {
    $interfacesPath = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'

    try {
        $interfaceKeys = @(Get-ChildItem -LiteralPath $interfacesPath -ErrorAction Stop)
        foreach ($interfaceKey in $interfaceKeys) {
            [void](Set-RegistryDword -Path $interfaceKey.PSPath -Name 'NetbiosOptions' -Value 2)
        }

        if ($interfaceKeys.Count -eq 0) {
            Write-Log -Message 'No existing NetBT interface registry keys were found.' -Level WARN
        }
    }
    catch {
        Add-Failure -Message "Unable to configure existing NetBT interfaces: $($_.Exception.Message)"
    }

    # Ask Windows to apply the setting immediately to active IP-enabled adapters.
    # The registry enforcement above remains authoritative if a particular adapter
    # does not expose the WMI method.
    try {
        $activeAdapters = @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = True')
        foreach ($adapter in $activeAdapters) {
            try {
                $result = Invoke-CimMethod -InputObject $adapter -MethodName SetTcpipNetbios -Arguments @{
                    TcpipNetbiosOptions = 2
                }

                if ($result.ReturnValue -eq 1) {
                    $script:RebootRecommended = $true
                    Write-Log -Message "Adapter '$($adapter.Description)' accepted the NetBIOS change and requires a restart."
                }
                elseif ($result.ReturnValue -ne 0) {
                    Write-Log -Message "Adapter '$($adapter.Description)' returned WMI code $($result.ReturnValue); its registry setting remains enforced." -Level WARN
                }
            }
            catch {
                Write-Log -Message "Could not apply the live NetBIOS change to '$($adapter.Description)': $($_.Exception.Message)" -Level WARN
            }
        }
    }
    catch {
        Write-Log -Message "Unable to enumerate active network adapters through CIM: $($_.Exception.Message)" -Level WARN
    }
}

function Test-NetBiosInterfacesDisabled {
    $interfacesPath = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'

    try {
        $interfaceKeys = @(Get-ChildItem -LiteralPath $interfacesPath -ErrorAction Stop)
        foreach ($interfaceKey in $interfaceKeys) {
            $value = Get-RegistryValue -Path $interfaceKey.PSPath -Name 'NetbiosOptions'
            if ($null -eq $value -or [int]$value -ne 2) {
                return $false
            }
        }

        return $true
    }
    catch {
        return $false
    }
}

function Add-VerificationResult {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [bool]$Compliant
    )

    if ($Compliant) {
        Write-Log -Message "Verification passed: $Name"
    }
    else {
        Add-Failure -Message "Verification failed: $Name"
    }
}

Write-Log -Message 'Starting Windows name-resolution hardening.'
Write-Log -Message "Running as '$([Security.Principal.WindowsIdentity]::GetCurrent().Name)' in a $([IntPtr]::Size * 8)-bit PowerShell process."

$dnsPolicyPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
$dnsRuntimePath = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters'
$winHttpPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp'
$machineInternetSettingsPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings'
$machineConnectionsPath = "$machineInternetSettingsPath\Connections"

# LLMNR: Enable the policy named "Turn off multicast name resolution."
if (Set-RegistryDword -Path $dnsPolicyPath -Name 'EnableMulticast' -Value 0) {
    $script:RebootRecommended = $true
}

# NBT-NS: Disable modern DNS Client fallback and NetBIOS over TCP/IP on
# existing interfaces.
if (Set-RegistryDword -Path $dnsPolicyPath -Name 'EnableNetbios' -Value 0) {
    $script:RebootRecommended = $true
}

if (Set-RegistryDword -Path $dnsRuntimePath -Name 'EnableNetbios' -Value 0) {
    $script:RebootRecommended = $true
}

Disable-NetBiosOnExistingAdapters

# mDNS: Configure both the policy location used by newer Windows ADMX files
# and the DNS Client runtime location used across supported Windows 10/11
# releases.
if (Set-RegistryDword -Path $dnsPolicyPath -Name 'EnableMDNS' -Value 0) {
    $script:RebootRecommended = $true
}

if (Set-RegistryDword -Path $dnsRuntimePath -Name 'EnableMDNS' -Value 0) {
    $script:RebootRecommended = $true
}

# WPAD: Disable WinHTTP WPAD without disabling WinHttpAutoProxySvc.
if (Set-RegistryDword -Path $winHttpPath -Name 'DisableWpad' -Value 1) {
    $script:RebootRecommended = $true
}

# Disable machine-level automatic proxy discovery while preserving any proxy
# server or PAC URL already configured.
[void](Set-RegistryDword -Path $machineInternetSettingsPath -Name 'AutoDetect' -Value 0)
[void](Disable-AutoDetectFlag -ConnectionsPath $machineConnectionsPath -ValueName 'DefaultConnectionSettings')
[void](Disable-AutoDetectFlag -ConnectionsPath $machineConnectionsPath -ValueName 'SavedLegacySettings')

if ($ConfigureLoadedUserWpad) {
    Disable-WpadForLoadedUsers
}

# Clear cached name-resolution data. Services are intentionally not restarted
# because DNS Client and WinHTTP have dependencies that can disrupt a session.
try {
    Clear-DnsClientCache -ErrorAction Stop
    Write-Log -Message 'Cleared the Windows DNS Client cache.'
}
catch {
    Write-Log -Message "Unable to clear the DNS Client cache: $($_.Exception.Message)" -Level WARN
}

# Verify the durable device-scoped settings.
Add-VerificationResult -Name 'LLMNR disabled' -Compliant (
    Test-RegistryDword -Path $dnsPolicyPath -Name 'EnableMulticast' -ExpectedValue 0
)

Add-VerificationResult -Name 'NBT-NS DNS Client policy disabled' -Compliant (
    (Test-RegistryDword -Path $dnsPolicyPath -Name 'EnableNetbios' -ExpectedValue 0) -and
    (Test-RegistryDword -Path $dnsRuntimePath -Name 'EnableNetbios' -ExpectedValue 0)
)

Add-VerificationResult -Name 'NetBIOS over TCP/IP disabled on existing adapters' -Compliant (
    Test-NetBiosInterfacesDisabled
)

Add-VerificationResult -Name 'Windows mDNS resolver disabled' -Compliant (
    (Test-RegistryDword -Path $dnsPolicyPath -Name 'EnableMDNS' -ExpectedValue 0) -and
    (Test-RegistryDword -Path $dnsRuntimePath -Name 'EnableMDNS' -ExpectedValue 0)
)

Add-VerificationResult -Name 'WinHTTP WPAD disabled' -Compliant (
    Test-RegistryDword -Path $winHttpPath -Name 'DisableWpad' -ExpectedValue 1
)

Add-VerificationResult -Name 'Machine automatic proxy detection disabled' -Compliant (
    Test-RegistryDword -Path $machineInternetSettingsPath -Name 'AutoDetect' -ExpectedValue 0
)

$machineConnectionFlag = Test-AutoDetectFlagDisabled -ConnectionsPath $machineConnectionsPath -ValueName 'DefaultConnectionSettings'
if ($null -ne $machineConnectionFlag) {
    Add-VerificationResult -Name 'Machine proxy auto-detect connection flag disabled' -Compliant $machineConnectionFlag
}

if ($script:RebootRecommended) {
    Write-Log -Message 'A restart is recommended to fully activate the DNS Client, NetBIOS, mDNS, and WPAD changes.' -Level WARN
}

if ($script:Failures.Count -gt 0) {
    Write-Log -Message "Hardening completed with $($script:Failures.Count) failure(s)." -Level ERROR
    exit 1
}

if ($script:ChangesMade) {
    Write-Log -Message 'Hardening completed successfully; one or more settings were changed.'
}
else {
    Write-Log -Message 'Hardening completed successfully; the device was already compliant.'
}

exit 0
