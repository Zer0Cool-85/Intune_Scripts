#!/bin/bash

# Get current logged in user
CURRENT_USER=$(stat -f "%Su" /dev/console)
USER_HOME=$(dscl . -read /Users/$CURRENT_USER NFSHomeDirectory | awk '{print $2}')

# Chrome profile path
CHROME_PATH="$USER_HOME/Library/Application Support/Google/Chrome"

# Backup destination (change as needed)
BACKUP_DIR="$USER_HOME/Desktop/ChromeProfileBackup_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$BACKUP_DIR"

# Verify Chrome profile folder exists
if [ ! -d "$CHROME_PATH" ]; then
    echo "No Chrome profile found at $CHROME_PATH"
    exit 1
fi

# Loop through profile folders
for profile in "$CHROME_PATH"/*; do
    folder_name=$(basename "$profile")

    # Only copy Default and "Profile *", skip "System Profile"
    if [[ "$folder_name" == "Default" || "$folder_name" == Profile* ]]; then
        if [[ "$folder_name" != "System Profile" ]]; then
            echo "Backing up $folder_name..."
            rsync -av --exclude="Crashpad" --exclude="*.tmp" "$profile" "$BACKUP_DIR/"
        fi
    fi
done

echo "Backup complete!"
echo "Profiles saved to: $BACKUP_DIR"
