# Silent MTU adjustment for physical adapters only (Ethernet, Wi-Fi, Dock)
# Requires administrative privileges

$logFile = "C:\Windows\Temp\MTU_Update_Log.txt"
$desiredMTU = 1360
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function Log {
    param ([string]$message)
    Add-Content -Path $logFile -Value "$timestamp - $message"
}

# Define keywords for acceptable physical adapters
$allowedKeywords = @("ethernet", "wi-fi", "wifi", "dock", "lan")

# Get all network adapters (even if disabled)
$adapters = Get-NetAdapter -IncludeHidden | Where-Object {
    $_.HardwareInterface -eq $true -and
    ($allowedKeywords | Where-Object { $_ -in $_.Name.ToLower() -or $_ -in $_.InterfaceDescription.ToLower() })
}

foreach ($adapter in $adapters) {
    $interfaceAlias = $adapter.Name
    try {
        $ipInterface = Get-NetIPInterface -InterfaceAlias $interfaceAlias -AddressFamily IPv4 -ErrorAction Stop

        if ($ipInterface.NlMtu -ne $desiredMTU) {
            Log "Changing MTU for '$interfaceAlias' from $($ipInterface.NlMtu) to $desiredMTU"
            Set-NetIPInterface -InterfaceAlias $interfaceAlias -NlMtu $desiredMTU -AddressFamily IPv4 -ErrorAction Stop
            Log "Successfully updated MTU for '$interfaceAlias'"
        } else {
            Log "No change needed. MTU for '$interfaceAlias' is already $desiredMTU"
        }
    } catch {
        Log "ERROR: Could not process adapter '$interfaceAlias' - $_"
    }
}
