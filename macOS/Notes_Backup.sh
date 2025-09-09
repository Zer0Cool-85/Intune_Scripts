#!/bin/bash

LOGFILE="/var/log/notes_backup_restore.log"
USER_HOME="$HOME"
NOTES_DIR="$USER_HOME/Library/Group Containers/group.com.apple.notes"
BACKUP_DIR="$USER_HOME/NotesBackup"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [BACKUP] $1" | tee -a "$LOGFILE"
}

mkdir -p "$BACKUP_DIR"

if [ -d "$NOTES_DIR" ]; then
    # Quit Notes to ensure clean DB state
    pkill Notes 2>/dev/null
    sleep 2

    # Create timestamped backup
    tar -czf "$BACKUP_DIR/notes_backup_$TIMESTAMP.tar.gz" -C "$USER_HOME/Library/Group Containers" "group.com.apple.notes"
    log "✅ Notes database and attachments backed up to $BACKUP_DIR/notes_backup_$TIMESTAMP.tar.gz"
    exit 0
else
    log "⚠️ Notes directory not found at $NOTES_DIR. Has Notes ever been used?"
    exit 1
fi
