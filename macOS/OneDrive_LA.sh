#!/bin/bash

# Path to check
AUTH_FILE="/usr/local/auth"
# App name (case-sensitive as it appears in Activity Monitor)
APP_NAME="OneDrive"
# Path to the app bundle
APP_PATH="/Applications/OneDrive.app"

# Function to quit OneDrive
quit_app() {
    echo "Quitting $APP_NAME..."
    pkill -x "$APP_NAME"
}

# Function to start OneDrive
start_app() {
    echo "Starting $APP_NAME..."
    open -a "$APP_PATH"
}

# Main logic
if [ ! -f "$AUTH_FILE" ]; then
    quit_app
    echo "Waiting for $AUTH_FILE to appear..."
    # Wait until the file exists
    while [ ! -f "$AUTH_FILE" ]; do
        sleep 5
    done
    echo "$AUTH_FILE found. Restarting $APP_NAME..."
    start_app
else
    echo "$AUTH_FILE exists. Nothing to do."
fi

exit 0
