#!/bin/bash

# Get current logged in user
CURRENT_USER=$(stat -f "%Su" /dev/console)
USER_HOME=$(dscl . -read /Users/$CURRENT_USER NFSHomeDirectory | awk '{print $2}')

# Chrome profile path
CHROME_PATH="$USER_HOME/Library/Application Support/Google/Chrome"

# Default backup location (Desktop)
BACKUP_BASE="$USER_HOME/Desktop"

# Try to detect the most recent backup folder
LATEST_BACKUP=$(ls -td "$BACKUP_BASE"/ChromeProfileBackup_* 2>/dev/null | head -n 1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "No backup found in $BACKUP_BASE"
    exit 1
fi

echo "Restoring Chrome profiles from: $LATEST_BACKUP"

# Verify Chrome profile folder exists, create if missing
mkdir -p "$CHROME_PATH"

# Restore each profile folder
for profile in "$LATEST_BACKUP"/*; do
    folder_name=$(basename "$profile")

    if [[ "$folder_name" == "Default" || "$folder_name" == Profile* ]]; then
        if [[ "$folder_name" != "System Profile" ]]; then
            echo "Restoring $folder_name..."
            rsync -av "$profile" "$CHROME_PATH/"
        fi
    fi
done

echo "Restore complete!"
