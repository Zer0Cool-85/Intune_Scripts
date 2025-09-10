#!/bin/bash

PLIST="/Library/Preferences/org.appinstall.deferral.plist"
DAEMON="/Library/LaunchDaemons/org.appinstall.reminder.plist"
LABEL="org.appinstall.reminder"
APP="/Applications/OrgApp.app"
REQUIRED_VERSION="2.5.0"  # <--- set your target version here

log() {
    echo "[$(date)] $1" >> /var/log/orgapp_reminder.log
}

# Function to compare app versions
version_greater_equal() {
    [ "$(printf '%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

# Get installed version (if app exists)
if [ -d "$APP" ]; then
    INSTALLED_VERSION=$(/usr/bin/defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
    log "Detected OrgApp version: $INSTALLED_VERSION"
else
    INSTALLED_VERSION=""
fi

# Evaluate install status
if [[ -n "$INSTALLED_VERSION" ]] && version_greater_equal "$INSTALLED_VERSION" "$REQUIRED_VERSION"; then
    log "OrgApp meets required version ($INSTALLED_VERSION >= $REQUIRED_VERSION). Cleaning up."

    # Write completion status
    defaults write "$PLIST" Status -string "Installed"
    defaults write "$PLIST" InstalledVersion -string "$INSTALLED_VERSION"

    # Unload & remove LaunchDaemon
    launchctl bootout system "$DAEMON" 2>/dev/null
    rm -f "$DAEMON"

    exit 0
else
    log "OrgApp missing or outdated (Installed: ${INSTALLED_VERSION:-None}, Required: $REQUIRED_VERSION). Showing reminder."

    # Track deferral count
    DEFERRALS=$(defaults read "$PLIST" Deferral 2>/dev/null || echo 0)
    DEFERRALS=$((DEFERRALS + 1))
    defaults write "$PLIST" Deferral -int "$DEFERRALS"

    # Show reminder via SwiftDialog
    /usr/local/bin/dialog \
        --title "Application Update Required" \
        --message "OrgApp version $REQUIRED_VERSION is required.\n\nCurrently installed: ${INSTALLED_VERSION:-Not Installed}\n\nPlease install/update as soon as possible.\n(Deferrals: $DEFERRALS)" \
        --icon "/usr/local/orgapp/logo.png" \
        --button1text "OK"

    log "Displayed reminder dialog. Deferrals: $DEFERRALS"
fi


######### DAEMON plist 

<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>org.appinstall.reminder</string>

    <!-- Run every 2 hours (7200 sec) -->
    <key>StartInterval</key>
    <integer>7200</integer>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/orgapp_reminder.sh</string>
    </array>

    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>


######### Jamf script (After)

#!/bin/bash
DAEMON="/Library/LaunchDaemons/org.appinstall.reminder.plist"
LABEL="org.appinstall.reminder"

if [ -f "$DAEMON" ]; then
    launchctl bootstrap system "$DAEMON"
    launchctl enable system/$LABEL
fi



##### OTHER INFO

Script → root:wheel, 755

Daemon → root:wheel, 644

