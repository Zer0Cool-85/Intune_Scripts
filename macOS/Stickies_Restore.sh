#!/bin/bash

LOGFILE="/var/log/stickies_backup_restore.log"
USER_HOME="$HOME"
BACKUP_DIR="$USER_HOME/StickiesBackup"

# Candidate Stickies parent directories
PARENT_PATHS=(
    "$USER_HOME/Library/Containers/com.apple.Stickies/Data/Library/Stickies"
    "$USER_HOME/Library/Containers/Stickies/Data/Library/Stickies"
)

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [RESTORE] $1" | tee -a "$LOGFILE"
}

# Pick most recent backup
LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/StickiesDatabase_* 2>/dev/null | head -n 1)

if [ -z "$LATEST_BACKUP" ]; then
    log "❌ No Stickies backup found in $BACKUP_DIR"
    exit 1
fi

log "📂 Restoring from $LATEST_BACKUP"

# Launch Stickies to generate container if needed
open -a Stickies
sleep 2
pkill Stickies
sleep 1

# Detect which Stickies directory exists
RESTORE_PATH=""
for P in "${PARENT_PATHS[@]}"; do
    if [ -d "$P" ]; then
        RESTORE_PATH="$P/StickiesDatabase"
        break
    fi
done

if [ -z "$RESTORE_PATH" ]; then
    log "❌ Could not determine Stickies path to restore. Stickies container not found."
    exit 1
fi

# Overwrite existing database with backup
cp -f "$LATEST_BACKUP" "$RESTORE_PATH"
log "✅ Stickies database restored to $RESTORE_PATH"

# Relaunch Stickies
open -a Stickies
exit 0
