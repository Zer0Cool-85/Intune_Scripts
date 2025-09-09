#!/bin/bash

# Output file
output="/tmp/system_info.txt"

# Computer Name
compName=$(scutil --get ComputerName)

# Serial Number
serial=$(system_profiler SPHardwareDataType | awk '/Serial Number/{print $4}')

# OS Name/Build
osName=$(sw_vers -productName)
osVersion=$(sw_vers -productVersion)
osBuild=$(sw_vers -buildVersion)

# IP Address (primary interface)
ipAddress=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)

# Current User
currentUser=$(stat -f%Su /dev/console)

# Last Reboot
lastReboot=$(uptime | sed 's/.*up \([^,]*\), .*/\1/')

# Jamf plist location
jamfPlist="/Library/Preferences/com.jamfsoftware.jamf.plist"

# Last Jamf Check-in
if [[ -f "$jamfPlist" ]]; then
    lastCheckin=$(defaults read "$jamfPlist" lastContactTime 2>/dev/null)
else
    lastCheckin="Not Available"
fi

# Last Jamf Inventory
if [[ -f "$jamfPlist" ]]; then
    lastInventory=$(defaults read "$jamfPlist" lastEnrollmentComplete 2>/dev/null)
    if [[ -z "$lastInventory" ]]; then
        lastInventory="Not Available"
    fi
else
    lastInventory="Not Available"
fi

# Write results to file
{
    echo "Computer Name: $compName"
    echo "Serial Number: $serial"
    echo "OS Name/Build: $osName $osVersion ($osBuild)"
    echo "IP Address: $ipAddress"
    echo "Current User: $currentUser"
    echo "Last Reboot: $lastReboot"
    echo "Last Jamf Check-in: $lastCheckin"
    echo "Last Jamf Inventory: $lastInventory"
} > "$output"

echo "System info written to $output"
