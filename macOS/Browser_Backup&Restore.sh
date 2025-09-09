#!/bin/bash

# ==========================================================
# macOS Browser Backup & Restore Script with Logging
# Supports: Chrome, Firefox, Safari
# Usage:
#   ./browser_backup.sh backup chrome firefox
#   ./browser_backup.sh restore safari
#   ./browser_backup.sh restore chrome /path/to/specific/backup
#   ./browser_backup.sh backup all
#   ./browser_backup.sh restore all /path/to/base/folder
# ==========================================================

# Get logged in user + home directory
CURRENT_USER=$(stat -f "%Su" /dev/console)
USER_HOME=$(dscl . -read /Users/$CURRENT_USER NFSHomeDirectory | awk '{print $2}')

# Base backup directory
BACKUP_BASE="$USER_HOME/Desktop/BrowserBackups"

# Log file
LOG_FILE="/var/log/browser_backup.log"

# Ensure log file exists and is writable
sudo touch "$LOG_FILE"
sudo chmod 666 "$LOG_FILE"

log() {
    local MSG="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$MSG"
    echo "$MSG" >> "$LOG_FILE"
}

mkdir -p "$BACKUP_BASE"

ACTION=$1
shift
BROWSERS=("$@")

# If restore and last arg is a path, treat it as backup source
CUSTOM_PATH=""
LAST_ARG="${BROWSERS[-1]}"
if [ "$ACTION" == "restore" ] && [ -d "$LAST_ARG" ]; then
    CUSTOM_PATH="$LAST_ARG"
    unset 'BROWSERS[-1]'
fi

if [ "$ACTION" != "backup" ] && [ "$ACTION" != "restore" ]; then
    log "Usage: $0 [backup|restore] [chrome|firefox|safari|all] [optional_backup_path]"
    exit 1
fi

if [[ " ${BROWSERS[*]} " =~ " all " ]] || [ ${#BROWSERS[@]} -eq 0 ]; then
    BROWSERS=("chrome" "firefox" "safari")
fi

timestamp=$(date +%Y%m%d_%H%M%S)

# ==========================================================
# Chrome Backup / Restore
# ==========================================================
handle_chrome() {
    local CHROME_PATH="$USER_HOME/Library/Application Support/Google/Chrome"

    if [ "$ACTION" == "backup" ]; then
        local BACKUP_DIR="$BACKUP_BASE/ChromeBackup_$timestamp"
        mkdir -p "$BACKUP_DIR"

        if [ ! -d "$CHROME_PATH" ]; then
            log "[Chrome] No Chrome profile found."
            return
        fi

        log "[Chrome] Backing up profiles..."
        for profile in "$CHROME_PATH"/*; do
            folder_name=$(basename "$profile")
            if [[ "$folder_name" == "Default" || "$folder_name" == Profile* ]]; then
                if [[ "$folder_name" != "System Profile" ]]; then
                    rsync -a --exclude="Crashpad" "$profile" "$BACKUP_DIR/"
                fi
            fi
        done
        log "[Chrome] Backup saved to $BACKUP_DIR"

    elif [ "$ACTION" == "restore" ]; then
        local SOURCE="$CUSTOM_PATH"
        if [ -z "$SOURCE" ]; then
            SOURCE=$(ls -td "$BACKUP_BASE"/ChromeBackup_* 2>/dev/null | head -n 1)
        fi
        if [ -z "$SOURCE" ] || [ ! -d "$SOURCE" ]; then
            log "[Chrome] No backup found."
            return
        fi
        log "[Chrome] Restoring from $SOURCE..."
        mkdir -p "$CHROME_PATH"
        for profile in "$SOURCE"/*; do
            folder_name=$(basename "$profile")
            if [[ "$folder_name" == "Default" || "$folder_name" == Profile* ]]; then
                if [[ "$folder_name" != "System Profile" ]]; then
                    rsync -a "$profile" "$CHROME_PATH/"
                fi
            fi
        done
        log "[Chrome] Restore complete."
    fi
}

# ==========================================================
# Firefox Backup / Restore
# ==========================================================
handle_firefox() {
    local FIREFOX_PATH="$USER_HOME/Library/Application Support/Firefox"

    if [ "$ACTION" == "backup" ]; then
        local BACKUP_DIR="$BACKUP_BASE/FirefoxBackup_$timestamp"
        mkdir -p "$BACKUP_DIR"

        if [ ! -d "$FIREFOX_PATH/Profiles" ]; then
            log "[Firefox] No profiles found."
            return
        fi

        log "[Firefox] Backing up profiles..."
        rsync -a "$FIREFOX_PATH/Profiles" "$BACKUP_DIR/"
        rsync -a "$FIREFOX_PATH/profiles.ini" "$BACKUP_DIR/" 2>/dev/null
        log "[Firefox] Backup saved to $BACKUP_DIR"

    elif [ "$ACTION" == "restore" ]; then
        local SOURCE="$CUSTOM_PATH"
        if [ -z "$SOURCE" ]; then
            SOURCE=$(ls -td "$BACKUP_BASE"/FirefoxBackup_* 2>/dev/null | head -n 1)
        fi
        if [ -z "$SOURCE" ] || [ ! -d "$SOURCE" ]; then
            log "[Firefox] No backup found."
            return
        fi
        log "[Firefox] Restoring from $SOURCE..."
        mkdir -p "$FIREFOX_PATH"
        rsync -a "$SOURCE/Profiles" "$FIREFOX_PATH/"
        if [ -f "$SOURCE/profiles.ini" ]; then
            rsync -a "$SOURCE/profiles.ini" "$FIREFOX_PATH/"
        fi
        log "[Firefox] Restore complete."
    fi
}

# ==========================================================
# Safari Backup / Restore
# ==========================================================
handle_safari() {
    local SAFARI_PATH="$USER_HOME/Library/Safari"
    local WEBKIT_PATH="$USER_HOME/Library/WebKit"
    local COOKIES_PATH="$USER_HOME/Library/Cookies"
    local PREFS_PATH="$USER_HOME/Library/Preferences/com.apple.Safari.plist"

    if [ "$ACTION" == "backup" ]; then
        local BACKUP_DIR="$BACKUP_BASE/SafariBackup_$timestamp"
        mkdir -p "$BACKUP_DIR"

        log "[Safari] Backing up data..."
        rsync -a "$SAFARI_PATH" "$BACKUP_DIR/" 2>/dev/null
        rsync -a "$WEBKIT_PATH" "$BACKUP_DIR/" 2>/dev/null
        rsync -a "$COOKIES_PATH" "$BACKUP_DIR/" 2>/dev/null
        [ -f "$PREFS_PATH" ] && rsync -a "$PREFS_PATH" "$BACKUP_DIR/"
        log "[Safari] Backup saved to $BACKUP_DIR"

    elif [ "$ACTION" == "restore" ]; then
        local SOURCE="$CUSTOM_PATH"
        if [ -z "$SOURCE" ]; then
            SOURCE=$(ls -td "$BACKUP_BASE"/SafariBackup_* 2>/dev/null | head -n 1)
        fi
        if [ -z "$SOURCE" ] || [ ! -d "$SOURCE" ]; then
            log "[Safari] No backup found."
            return
        fi
        log "[Safari] Restoring from $SOURCE..."
        rsync -a "$SOURCE/Safari" "$USER_HOME/Library/" 2>/dev/null
        rsync -a "$SOURCE/WebKit" "$USER_HOME/Library/" 2>/dev/null
        rsync -a "$SOURCE/Cookies" "$USER_HOME/Library/" 2>/dev/null
        [ -f "$SOURCE/com.apple.Safari.plist" ] && rsync -a "$SOURCE/com.apple.Safari.plist" "$USER_HOME/Library/Preferences/"
        log "[Safari] Restore complete."
    fi
}

# ==========================================================
# Main Execution
# ==========================================================
for browser in "${BROWSERS[@]}"; do
    case "$browser" in
        chrome) handle_chrome ;;
        firefox) handle_firefox ;;
        safari) handle_safari ;;
        *) log "Unknown browser: $browser" ;;
    esac
done
