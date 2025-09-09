#!/bin/bash

LOGFILE="/var/log/notes_backup_restore.log"
USER_HOME="$HOME"
NOTES_DIR="$USER_HOME/Library/Group Containers/group.com.apple.notes"
BACKUP_DIR="$USER_HOME/NotesBackup"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [RESTORE] $1" | tee -a "$LOGFILE"
}

# Pick most recent backup
LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/notes_backup_*.tar.gz 2>/dev/null | head -n 1)

if [ -z "$LATEST_BACKUP" ]; then
    log "❌ No Notes backup found in $BACKUP_DIR"
    exit 1
fi

log "📂 Restoring Notes from $LATEST_BACKUP"

# Quit Notes if running
pkill Notes 2>/dev/null
sleep 2

# Remove existing Notes data
if [ -d "$NOTES_DIR" ]; then
    rm -rf "$NOTES_DIR"
    log "🗑️ Existing Notes data removed from $NOTES_DIR"
fi

# Extract backup
tar -xzf "$LATEST_BACKUP" -C "$USER_HOME/Library/Group Containers/"
log "✅ Notes database restored to $NOTES_DIR"

# Relaunch Notes
open -a Notes
exit 0
