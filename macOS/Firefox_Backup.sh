#!/bin/bash

# Get current logged in user
CURRENT_USER=$(stat -f "%Su" /dev/console)
USER_HOME=$(dscl . -read /Users/$CURRENT_USER NFSHomeDirectory | awk '{print $2}')

# Firefox profile path
FIREFOX_PATH="$USER_HOME/Library/Application Support/Firefox"

# Backup destination
BACKUP_DIR="$USER_HOME/Desktop/FirefoxProfileBackup_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$BACKUP_DIR"

# Verify Firefox folder exists
if [ ! -d "$FIREFOX_PATH/Profiles" ]; then
    echo "No Firefox profiles found at $FIREFOX_PATH/Profiles"
    exit 1
fi

echo "Backing up Firefox profiles..."

# Copy all profiles + profiles.ini
rsync -av --exclude="Crash Reports" --exclude="*.tmp" "$FIREFOX_PATH/Profiles" "$BACKUP_DIR/"
rsync -av "$FIREFOX_PATH/profiles.ini" "$BACKUP_DIR/" 2>/dev/null

echo "Backup complete!"
echo "Profiles saved to: $BACKUP_DIR"
