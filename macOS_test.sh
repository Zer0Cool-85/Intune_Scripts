#!/bin/bash

## Get available Software Updates and determine which need reboots when installed

##################### Script behavior options (Choose one or both options) #####################

EAScript="Yes"   # Set to "Yes" to operate as an Extension Attribute
LogScript="Yes"  # Set to "Yes" to log output to file

################################################################################################

Reboot_Needed_Log="/Library/Application Support/Reboot_Updates_Needed"

# Initialize arrays
updateIdentifiers=()
updateVersions=()
productKeys=()
displayNames=()
RestartPkgs=()

# Function to find downloaded updates that require a reboot
get_Reboot_Updates () {
    i=0
    while read -r folder; do
        if [[ -e "/Library/Updates/${folder}" ]]; then
            while read -r distFile; do
                if grep -iq restart "$distFile"; then
                    RestartPkgs+=("${updateIdentifiers[$i]}-${updateVersions[$i]}")
                fi
            done < <(find "/Library/Updates/${folder}" -name "*.dist")
            ((i++))
        else
            echo "Could not find path /Library/Updates/${folder}"
        fi
    done < <(printf '%s\n' "${productKeys[@]}")

    if [[ ${#RestartPkgs[@]} -gt 0 ]]; then
        echo "Some updates require a reboot"
        if [[ "$EAScript" == "Yes" ]]; then
            echo "<result>$(printf '%s\n' "${RestartPkgs[@]}")</result>"
        fi
        if [[ "$LogScript" == "Yes" ]]; then
            echo "Adding details to local file..."
            printf '%s\n' "${RestartPkgs[@]}" > "$Reboot_Needed_Log"
        fi
    else
        echo "No reboot updates are available at this time..."
        if [[ "$EAScript" == "Yes" ]]; then
            echo "<result>None</result>"
        fi
        if [[ "$LogScript" == "Yes" ]]; then
            echo "Nothing to write to log file"
        fi
    fi
}

# Function to read software update info into arrays
get_Update_Stats () {
    echo "Getting update stats..."
    RecommendedUpdatesData=$(/usr/bin/defaults read /Library/Preferences/com.apple.SoftwareUpdate.plist RecommendedUpdates)

    while read -r identifier; do updateIdentifiers+=("$identifier"); done < <(awk -F'= ' '/Identifier/{print $NF}' <<< "$RecommendedUpdatesData" | sed 's/[\";]//g')
    while read -r version; do updateVersions+=("$version"); done < <(awk -F'= ' '/Display Version/{print $NF}' <<< "$RecommendedUpdatesData" | sed 's/[\";]//g')
    while read -r key; do productKeys+=("$key"); done < <(awk -F'= ' '/Product Key/{print $NF}' <<< "$RecommendedUpdatesData" | sed 's/[\";]//g')
    while read -r name; do displayNames+=("$name"); done < <(awk -F'= ' '/Display Name/{print $NF}' <<< "$RecommendedUpdatesData" | sed 's/[\";]//g')

    echo "Looking for reboot required updates..."
    get_Reboot_Updates
}

# Function to compare downloaded updates against available
check_Downloads_Vs_AvailUpdates () {
    getDownloads="No"
    while read -r item; do
        if ! grep -q "$item" <<< "$downloadedUpdates"; then
            getDownloads="Yes"
        fi
    done < <(printf '%s\n' "$RecommendedUpdateKeys")

    if [[ "$getDownloads" == "Yes" ]]; then
        echo "Some available updates are not already downloaded. Downloading all available updates..."
        softwareupdate -d -a
        get_Update_Stats
    else
        echo "All available updates have been downloaded. Skipping to checking the update stats..."
        get_Update_Stats
    fi
}

# Remove previous log if it exists
if [[ -e "$Reboot_Needed_Log" ]]; then
    rm "$Reboot_Needed_Log"
fi

# Read available update product keys
RecommendedUpdateKeys=$(/usr/bin/defaults read /Library/Preferences/com.apple.SoftwareUpdate.plist RecommendedUpdates | awk -F'= ' '/Product Key/{print $NF}' | sed 's/[\";]//g')

# Get list of downloaded update folders
downloadedUpdates=$(find "/Library/Updates" -maxdepth 1 -type d | sed '1d')

echo "Running check for available updates..."
check_Downloads_Vs_AvailUpdates
