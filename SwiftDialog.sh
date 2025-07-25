#!/bin/bash

# Set up
LOG_FILE="/var/tmp/dialog.log"
ICON_INSTALL="/System/Library/CoreServices/Installer.app/Contents/Resources/Installer.icns"
ICON_FINISH="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/CheckMark.icns"
DIALOG_BIN="/usr/local/bin/dialog"

# Clear previous log
rm -f "$LOG_FILE"
touch "$LOG_FILE"

# Launch SwiftDialog
"$DIALOG_BIN" \
  --title "Setting Up Your Mac" \
  --progress \
  --icon "$ICON_INSTALL" \
  --message "Starting setup..." \
  --commandfile "$LOG_FILE" \
  --quitonlastline \
  &
DIALOG_PID=$!

# Function to update the dialog
update_dialog() {
  local message="$1"
  local icon="$2"
  echo '{"progressText": "'"$message"'", "icon": "'"$icon"'"}' >> "$LOG_FILE"
}

# --- Step 1: Chrome ---
update_dialog "Installing Google Chrome..." "$ICON_INSTALL"
/usr/local/bin/jamf policy -event install-chrome

# --- Step 2: Microsoft Office ---
update_dialog "Installing Microsoft Office..." "$ICON_INSTALL"
/usr/local/bin/jamf policy -event install-office

# --- Step 3: Zoom ---
update_dialog "Installing Zoom..." "$ICON_INSTALL"
/usr/local/bin/jamf policy -event install-zoom

# --- All Done ---
update_dialog "Setup Complete!" "$ICON_FINISH"
echo "Setup complete." >> "$LOG_FILE"



<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.company.enrollment</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/usr/local/org/enrollment.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/enrollment_stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/enrollment_stderr.log</string>
</dict>
</plist>
