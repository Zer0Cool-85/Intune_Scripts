#!/bin/bash

LOGFILE="/var/log/stickies_backup_restore.log"
USER_HOME="$HOME"
BACKUP_DIR="$USER_HOME/StickiesBackup"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Candidate Stickies database paths
PATHS=(
    "$USER_HOME/Library/Containers/com.apple.Stickies/Data/Library/Stickies/StickiesDatabase"
    "$USER_HOME/Library/Containers/Stickies/Data/Library/Stickies/StickiesDatabase"
)

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [BACKUP] $1" | tee -a "$LOGFILE"
}

mkdir -p "$BACKUP_DIR"

FOUND_PATH=""
for P in "${PATHS[@]}"; do
    if [ -f "$P" ]; then
        FOUND_PATH="$P"
        break
    fi
done

if [ -n "$FOUND_PATH" ]; then
    cp -f "$FOUND_PATH" "$BACKUP_DIR/StickiesDatabase_$TIMESTAMP"
    log "✅ Stickies database backed up from $FOUND_PATH to $BACKUP_DIR/StickiesDatabase_$TIMESTAMP"
    exit 0
else
    log "⚠️ No Stickies database found. Stickies may never have been launched."
    exit 1
fi
