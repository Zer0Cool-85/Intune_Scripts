#!/bin/bash

# Get current logged in user
CURRENT_USER=$(stat -f "%Su" /dev/console)
USER_HOME=$(dscl . -read /Users/$CURRENT_USER NFSHomeDirectory | awk '{print $2}')

# Firefox profile path
FIREFOX_PATH="$USER_HOME/Library/Application Support/Firefox"

# Default backup location
BACKUP_BASE="$USER_HOME/Desktop"

# Try to detect the most recent backup folder
LATEST_BACKUP=$(ls -td "$BACKUP_BASE"/FirefoxProfileBackup_* 2>/dev/null | head -n 1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "No backup found in $BACKUP_BASE"
    exit 1
fi

echo "Restoring Firefox profiles from: $LATEST_BACKUP"

# Ensure Firefox path exists
mkdir -p "$FIREFOX_PATH"

# Restore profiles and profiles.ini
rsync -av "$LATEST_BACKUP/Profiles" "$FIREFOX_PATH/"
if [ -f "$LATEST_BACKUP/profiles.ini" ]; then
    rsync -av "$LATEST_BACKUP/profiles.ini" "$FIREFOX_PATH/"
fi

echo "Restore complete!"
