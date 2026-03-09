function Get-ComputerChassisType {
<#
.SYNOPSIS
Returns a simplified chassis type for the current computer.

.DESCRIPTION
Determines whether the device is a Desktop (DT), Laptop (LT), 
Virtual Machine (VM), or Server (SRV) using CIM queries.

.OUTPUTS
DT  = Desktop
LT  = Laptop
VM  = Virtual Machine
SRV = Server
UNK = Unknown
#>

    try {

        # Get system information
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
        $enclosure = Get-CimInstance -ClassName Win32_SystemEnclosure

        # Detect Virtual Machine first
        if ($computerSystem.Model -match "Virtual|VMware|KVM|VirtualBox|Hyper-V") {
            return "VM"
        }

        # Server detection
        if ($computerSystem.DomainRole -ge 3) {
            return "SRV"
        }

        # Chassis type codes from Win32_SystemEnclosure
        $chassis = $enclosure.ChassisTypes

        switch ($chassis) {

            # Laptop types
            {$_ -in 8,9,10,11,12,14,18,21,30,31,32} { return "LT" }

            # Desktop types
            {$_ -in 3,4,5,6,7,13,15,16,35,36} { return "DT" }

            default { return "UNK" }
        }

    }
    catch {
        Write-Warning "Unable to determine chassis type: $_"
        return "UNK"
    }
}
