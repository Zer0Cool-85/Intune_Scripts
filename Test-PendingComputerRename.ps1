function Test-PendingComputerRename {
    [CmdletBinding()]
    param()

    $ActiveNamePath  = 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName'
    $PendingNamePath = 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName'

    try {
        $ActiveName = (Get-ItemProperty -Path $ActiveNamePath -Name ComputerName -ErrorAction Stop).ComputerName
        $PendingName = (Get-ItemProperty -Path $PendingNamePath -Name ComputerName -ErrorAction Stop).ComputerName

        $CimName = (Get-CimInstance -ClassName Win32_ComputerSystem).Name

        [PSCustomObject]@{
            PendingComputerRename = ($ActiveName -ne $PendingName)
            CurrentActiveName     = $ActiveName
            PendingNextBootName   = $PendingName
            CimComputerName       = $CimName
            EnvComputerName       = $env:COMPUTERNAME
        }
    }
    catch {
        [PSCustomObject]@{
            PendingComputerRename = $null
            CurrentActiveName     = $null
            PendingNextBootName   = $null
            CimComputerName       = $null
            EnvComputerName       = $env:COMPUTERNAME
            Error                 = $_.Exception.Message
        }
    }
}

<#
$ActiveNamePath  = 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName'
$PendingNamePath = 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName'

$ActiveName = (Get-ItemProperty -Path $ActiveNamePath -Name ComputerName).ComputerName
$PendingName = (Get-ItemProperty -Path $PendingNamePath -Name ComputerName).ComputerName

if ($ActiveName -ne $PendingName) {
    Write-Output "Pending computer rename detected. Current active name: $ActiveName. Pending next boot name: $PendingName."
    exit 1
}
else {
    Write-Output "No pending computer rename detected. Current name: $ActiveName."
    exit 0
}
#>
