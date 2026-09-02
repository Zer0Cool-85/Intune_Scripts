#requires -Version 5.1

<#
    SystemSupportInfo.Core.psm1

    Collects the local Windows information displayed by the application. This
    module intentionally contains no WPF code so data collection can be tested
    and extended independently from the interface.
#>

function Format-SystemUptime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [TimeSpan]$TimeSpan
    )

    $parts = [System.Collections.Generic.List[string]]::new()

    if ($TimeSpan.Days -gt 0) {
        $suffix = if ($TimeSpan.Days -eq 1) { '' } else { 's' }
        $parts.Add(('{0} day{1}' -f $TimeSpan.Days, $suffix))
    }

    if ($TimeSpan.Hours -gt 0) {
        $suffix = if ($TimeSpan.Hours -eq 1) { '' } else { 's' }
        $parts.Add(('{0} hour{1}' -f $TimeSpan.Hours, $suffix))
    }

    if (($TimeSpan.Days -eq 0) -and ($TimeSpan.Minutes -gt 0)) {
        $suffix = if ($TimeSpan.Minutes -eq 1) { '' } else { 's' }
        $parts.Add(('{0} minute{1}' -f $TimeSpan.Minutes, $suffix))
    }

    if ($parts.Count -eq 0) {
        return 'Less than one minute'
    }

    return ($parts -join ', ')
}

function Get-DeviceJoinStatus {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$UnavailableText = 'Unavailable'
    )

    try {
        $dsregPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\dsregcmd.exe'
        $output = (& $dsregPath /status 2>$null) -join "`n"

        $getValue = {
            param([string]$Name)

            $pattern = '(?m)^\s*{0}\s*:\s*(.*?)\s*$' -f [regex]::Escape($Name)
            $match = [regex]::Match($output, $pattern)
            if ($match.Success) {
                return $match.Groups[1].Value.Trim()
            }

            return $null
        }

        $entraJoined     = (& $getValue 'AzureAdJoined') -eq 'YES'
        $domainJoined    = (& $getValue 'DomainJoined') -eq 'YES'
        $workplaceJoined = (& $getValue 'WorkplaceJoined') -eq 'YES'

        if ($entraJoined -and $domainJoined) {
            return 'Microsoft Entra hybrid joined'
        }

        if ($entraJoined) {
            return 'Microsoft Entra joined'
        }

        if ($domainJoined) {
            return 'Active Directory domain joined'
        }

        if ($workplaceJoined) {
            return 'Microsoft Entra registered'
        }

        return 'Workgroup / not joined'
    }
    catch {
        return $UnavailableText
    }
}

function Get-NetworkSupportDetails {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$UnavailableText = 'Unavailable'
    )

    $result = [ordered]@{
        ActiveConnection = $UnavailableText
        IPv4Address      = $UnavailableText
    }

    try {
        $configurations = @(
            Get-NetIPConfiguration -ErrorAction Stop |
                Where-Object {
                    $_.NetAdapter.Status -eq 'Up' -and
                    $_.IPv4Address -and
                    $_.InterfaceAlias -notmatch 'Loopback|isatap|Teredo'
                } |
                Sort-Object -Property @(
                    @{ Expression = { if ($_.IPv4DefaultGateway) { 0 } else { 1 } } },
                    @{ Expression = { $_.InterfaceIndex } }
                )
        )

        $connectionNames = @(
            $configurations |
                Select-Object -ExpandProperty InterfaceAlias -Unique
        )

        $addresses = @(
            $configurations |
                ForEach-Object { $_.IPv4Address } |
                Where-Object {
                    $_.IPAddress -and
                    $_.IPAddress -ne '127.0.0.1' -and
                    $_.IPAddress -notlike '169.254.*'
                } |
                Select-Object -ExpandProperty IPAddress -Unique
        )

        if ($connectionNames.Count -gt 0) {
            $result.ActiveConnection = $connectionNames -join ', '
        }

        if ($addresses.Count -gt 0) {
            $result.IPv4Address = $addresses -join ', '
        }
    }
    catch {
        # PowerShell 7 can run without the Windows NetTCPIP module in some
        # hosts. Fall back to the edition-neutral .NET network APIs.
        try {
            $connectionNames = [System.Collections.Generic.List[string]]::new()
            $addresses = [System.Collections.Generic.List[string]]::new()

            foreach ($adapter in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
                if (
                    $adapter.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up -or
                    $adapter.NetworkInterfaceType -in @(
                        [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback,
                        [System.Net.NetworkInformation.NetworkInterfaceType]::Tunnel
                    ) -or
                    $adapter.Name -match 'Loopback|isatap|Teredo'
                ) {
                    continue
                }

                $adapterHasAddress = $false
                foreach ($unicastAddress in $adapter.GetIPProperties().UnicastAddresses) {
                    $address = $unicastAddress.Address
                    if (
                        $address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
                        $address.ToString() -ne '127.0.0.1' -and
                        $address.ToString() -notlike '169.254.*'
                    ) {
                        if (-not $addresses.Contains($address.ToString())) {
                            $addresses.Add($address.ToString())
                        }
                        $adapterHasAddress = $true
                    }
                }

                if ($adapterHasAddress -and -not $connectionNames.Contains($adapter.Name)) {
                    $connectionNames.Add($adapter.Name)
                }
            }

            if ($connectionNames.Count -gt 0) {
                $result.ActiveConnection = $connectionNames -join ', '
            }

            if ($addresses.Count -gt 0) {
                $result.IPv4Address = $addresses -join ', '
            }
        }
        catch {
            # Keep the configured unavailable text if both methods fail.
        }
    }

    return [pscustomobject]$result
}

function Get-SystemSupportData {
    <#
    .SYNOPSIS
        Collects the values consumed by the System Support Information UI.

    .PARAMETER UnavailableText
        Text used when a value cannot be collected.

    .PARAMETER DateFormat
        .NET date/time format used for restart and collection timestamps.
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$UnavailableText = 'Unavailable',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$DateFormat = 'MMM d, yyyy h:mm tt'
    )

    $fallbackUser = if (
        ($env:USERNAME -ne 'SYSTEM') -and
        -not [string]::IsNullOrWhiteSpace($env:USERNAME)
    ) {
        if ([string]::IsNullOrWhiteSpace($env:USERDOMAIN)) {
            $env:USERNAME
        }
        else {
            '{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME
        }
    }
    else {
        'No interactive user detected'
    }

    $fallbackArchitecture = if (-not [string]::IsNullOrWhiteSpace($env:PROCESSOR_ARCHITEW6432)) {
        $env:PROCESSOR_ARCHITEW6432
    }
    else {
        $env:PROCESSOR_ARCHITECTURE
    }

    $data = [ordered]@{
        DeviceName       = $env:COMPUTERNAME
        SignedInUser     = $fallbackUser
        Hardware         = $UnavailableText
        SerialNumber     = $UnavailableText
        InstalledMemory  = $UnavailableText
        JoinStatus       = $UnavailableText
        WindowsEdition   = $UnavailableText
        WindowsVersion   = $UnavailableText
        OSBuild          = $UnavailableText
        Architecture     = if ([string]::IsNullOrWhiteSpace($fallbackArchitecture)) { $UnavailableText } else { $fallbackArchitecture }
        LastRestart      = $UnavailableText
        Uptime           = $UnavailableText
        SystemDrive      = $UnavailableText
        ActiveConnection = $UnavailableText
        IPv4Address      = $UnavailableText
        CollectedAt      = (Get-Date).ToString($DateFormat)
    }

    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop

        if (-not [string]::IsNullOrWhiteSpace($computerSystem.Name)) {
            $data.DeviceName = $computerSystem.Name
        }

        if (-not [string]::IsNullOrWhiteSpace($computerSystem.UserName)) {
            $data.SignedInUser = $computerSystem.UserName
        }
        elseif (($env:USERNAME -ne 'SYSTEM') -and -not [string]::IsNullOrWhiteSpace($env:USERNAME)) {
            $data.SignedInUser = '{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME
        }

        $make  = [string]$computerSystem.Manufacturer
        $model = [string]$computerSystem.Model
        $hardwareParts = @($make.Trim(), $model.Trim()) | Where-Object { $_ }
        if ($hardwareParts.Count -gt 0) {
            $data.Hardware = $hardwareParts -join ' '
        }

        if ($computerSystem.TotalPhysicalMemory) {
            $data.InstalledMemory = '{0:N1} GB' -f ($computerSystem.TotalPhysicalMemory / 1GB)
        }
    }
    catch {
        # Continue collecting the remaining independent values.
    }

    try {
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace($bios.SerialNumber)) {
            $data.SerialNumber = $bios.SerialNumber.Trim()
        }
    }
    catch {
        # Keep the configured unavailable text.
    }

    try {
        $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop

        if (-not [string]::IsNullOrWhiteSpace($operatingSystem.Caption)) {
            $data.WindowsEdition = $operatingSystem.Caption.Trim()
        }

        if (-not [string]::IsNullOrWhiteSpace($operatingSystem.OSArchitecture)) {
            $data.Architecture = $operatingSystem.OSArchitecture
        }

        if ($operatingSystem.LastBootUpTime) {
            $lastBoot = [datetime]$operatingSystem.LastBootUpTime
            $data.LastRestart = $lastBoot.ToString($DateFormat)
            $data.Uptime = Format-SystemUptime -TimeSpan ((Get-Date) - $lastBoot)
        }
    }
    catch {
        # Keep the configured unavailable text.
    }

    try {
        $currentVersion = Get-ItemProperty `
            -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
            -ErrorAction Stop

        if (-not [string]::IsNullOrWhiteSpace($currentVersion.DisplayVersion)) {
            $data.WindowsVersion = $currentVersion.DisplayVersion
        }
        elseif (-not [string]::IsNullOrWhiteSpace($currentVersion.ReleaseId)) {
            $data.WindowsVersion = $currentVersion.ReleaseId
        }

        $build = [string]$currentVersion.CurrentBuildNumber
        if (-not [string]::IsNullOrWhiteSpace([string]$currentVersion.UBR)) {
            $build = '{0}.{1}' -f $build, $currentVersion.UBR
        }

        if (-not [string]::IsNullOrWhiteSpace($build)) {
            $data.OSBuild = $build
        }

        if (
            $data.WindowsEdition -eq $UnavailableText -and
            -not [string]::IsNullOrWhiteSpace([string]$currentVersion.ProductName)
        ) {
            $data.WindowsEdition = [string]$currentVersion.ProductName
        }
    }
    catch {
        # Keep the configured unavailable text.
    }

    try {
        $systemDisk = Get-CimInstance `
            -ClassName Win32_LogicalDisk `
            -Filter "DeviceID='C:'" `
            -ErrorAction Stop

        if ($systemDisk.Size) {
            $data.SystemDrive = '{0:N1} GB free of {1:N1} GB' -f `
                ($systemDisk.FreeSpace / 1GB),
                ($systemDisk.Size / 1GB)
        }
    }
    catch {
        try {
            $systemDriveRoot = if (-not [string]::IsNullOrWhiteSpace($env:SystemDrive)) {
                '{0}\' -f $env:SystemDrive.TrimEnd('\')
            }
            else {
                [System.IO.Path]::GetPathRoot($env:SystemRoot)
            }

            $drive = [System.IO.DriveInfo]::new($systemDriveRoot)
            if ($drive.IsReady -and $drive.TotalSize -gt 0) {
                $data.SystemDrive = '{0:N1} GB free of {1:N1} GB' -f `
                    ($drive.AvailableFreeSpace / 1GB),
                    ($drive.TotalSize / 1GB)
            }
        }
        catch {
            # Keep the configured unavailable text if both methods fail.
        }
    }

    $data.JoinStatus = Get-DeviceJoinStatus -UnavailableText $UnavailableText

    $network = Get-NetworkSupportDetails -UnavailableText $UnavailableText
    $data.ActiveConnection = $network.ActiveConnection
    $data.IPv4Address = $network.IPv4Address

    foreach ($key in @($data.Keys)) {
        if ([string]::IsNullOrWhiteSpace([string]$data[$key])) {
            $data[$key] = $UnavailableText
        }
    }

    return [pscustomobject]$data
}

Export-ModuleMember -Function Get-SystemSupportData
