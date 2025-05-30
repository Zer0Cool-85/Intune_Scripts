# MTU check and set script with logging

$logFile = "C:\Windows\Temp\MTU_Update_Log.txt"
$desiredMTU = 1360
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function Log {
    param ([string]$message)
    Add-Content -Path $logFile -Value "$timestamp - $message"
}

# Get all network adapters that are up
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }

foreach ($adapter in $adapters) {
    $interfaceAlias = $adapter.Name
    $ipInterface = Get-NetIPInterface -InterfaceAlias $interfaceAlias -AddressFamily IPv4

    if ($ipInterface.NlMtu -ne $desiredMTU) {
        Log "Changing MTU for '$interfaceAlias' from $($ipInterface.NlMtu) to $desiredMTU"
        try {
            Set-NetIPInterface -InterfaceAlias $interfaceAlias -NlMtu $desiredMTU -AddressFamily IPv4 -ErrorAction Stop
            Log "Successfully updated MTU for '$interfaceAlias'"
        } catch {
            Log "ERROR: Failed to update MTU for '$interfaceAlias' - $_"
        }
    } else {
        Log "No change needed. MTU for '$interfaceAlias' is already $desiredMTU"
    }
}
