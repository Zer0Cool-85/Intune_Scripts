#!/bin/bash

scriptLog="/var/log/appInstall.log"
dialogBin="/usr/local/bin/dialog"
commandFile="/var/tmp/appInstallDialog.cmd"
statusFile="/var/tmp/appInstallStatus.txt"

: > "$commandFile"
: > "$scriptLog"
: > "$statusFile"

$dialogBin \
  --title "Installing Application" \
  --message "Please wait while the app installs..." \
  --progress \
  --progresstext "Starting..." \
  --commandfile "$commandFile" &

dialogPID=$!

# Timeout watchdog
(
    sleep 180
    echo "progresstext: Install timed out." >> "$commandFile"
    echo "quit:" >> "$commandFile"
    echo "timeout" > "$statusFile"
    kill $dialogPID 2>/dev/null
) &

# Tail and filter (background)
tail -Fn0 "$scriptLog" | while read -r line; do
    if [[ "$line" == *"Installing"* ]] || \
       [[ "$line" == *"Downloading"* ]]; then
        echo "progresstext: $line" >> "$commandFile"
    fi

    if [[ "$line" == *"Successfully Installed"* ]]; then
        echo "progresstext: Install complete!" >> "$commandFile"
        echo "quit:" >> "$commandFile"
        echo "success" > "$statusFile"
        kill $dialogPID 2>/dev/null
        pkill -P $$ tail
        break
    fi

    if [[ "$line" == *"No policies found"* ]]; then
        echo "progresstext: No applicable policy found." >> "$commandFile"
        echo "quit:" >> "$commandFile"
        echo "nopolicy" > "$statusFile"
        kill $dialogPID 2>/dev/null
        pkill -P $$ tail
        break
    fi
done &

# Run jamf after tail is listening
/usr/local/bin/jamf policy -event appInstall >> "$scriptLog" 2>&1

# Wait until status file is populated
while [[ ! -s "$statusFile" ]]; do
    sleep 1
done

exitStatus=$(<"$statusFile")

# === Handle flows ===
case "$exitStatus" in
    success)
        echo "✅ Flow: App installed successfully."
        ;;
    nopolicy)
        echo "⚠️ Flow: No policy found."
        ;;
    timeout)
        echo "⏱️ Flow: Install timed out."
        ;;
esac