#!/bin/bash

# ===== Define Variables =====
DIALOG="/usr/local/bin/dialog"
logFile="/var/tmp/dialog.log"
loggedInUser=$(stat -f%Su /dev/console)
userID=$(id -u "$loggedInUser")

# ==== Greeting Logic ====
loggedInUserFullName=$(id -F "${loggedInUser}")
loggedInUserFirstName=$(echo "$loggedInUserFullName" | awk '{print $1}')
currentHour=$(date +"%H")

if [ "$currentHour" -ge 5 ] && [ "$currentHour" -lt 12 ]; then
    timeGreeting="Good morning"
elif [ "$currentHour" -ge 12 ] && [ "$currentHour" -lt 17 ]; then
    timeGreeting="Good afternoon"
else
    timeGreeting="Good evening"
fi

# ==== Prepare command file ====
rm -f "$logFile"
touch "$logFile"
chmod 666 "$logFile"

# ==== Launch SwiftDialog as user ====
launchctl asuser "$userID" sudo -u "$loggedInUser" "$DIALOG" \
  --title none \
  --bannerimage /usr/local/org/banner.jpeg \
  --bannerheight 200 \
  --progress \
  --progresstext "Getting ready..." \
  --message "${timeGreeting}, ${loggedInUserFirstName}! <br><br> Welcome! We are finishing the setup of your Mac.<br><br>It will be ready to use shortly." \
  --messagefont size=24 \
  --icon SF=pencil.and.list.clipboard \
  --appearance dark \
  --background colour=black \
  --commandfile "$logFile" \
  --width 750 \
  --height 450 \
  --button1text none \
  --blurscreen \
  --quitonlastline &

DIALOG_PID=$!

# ==== Run privileged actions (root context) ====
sleep 4
echo "progresstext: Configuring default dock..." >> "$logFile"
echo "icon: SF=dock.arrow.down.rectangle" >> "$logFile"
/usr/local/bin/jamf policy -event dock

sleep 2
echo "progresstext: Installing application..." >> "$logFile"
echo "icon: SF=macbook" >> "$logFile"
/usr/local/bin/jamf policy -event app_install

sleep 2
echo "progresstext: Verifying configuration..." >> "$logFile"
echo "icon: SF=checklist" >> "$logFile"
/usr/local/bin/jamf policy -event verify_setup

sleep 2
echo "progress: hide" >> "$logFile"
echo "message: Configuration Complete!" >> "$logFile"
echo "icon: SF=checkmark.seal,colour=green" >> "$logFile"

sleep 2
echo "message: + <br><br> Enjoy your Mac, and have a great $(date +'%A')!" >> "$logFile"

sleep 4
echo "quit:" >> "$logFile"

exit 0



<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.company.enrollment</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/org/enrollment-wrapper.sh</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/var/log/enrollment_stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/enrollment_stderr.log</string>

    <key>LaunchOnlyOnce</key>
    <true/>

    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
</dict>
</plist>

#!/bin/bash

# Target script you want to allow
SUDO_SCRIPT="/usr/local/org/enrollment-root.sh"
SUDOERS_FILE="/etc/sudoers.d/enrollment"

# Set who can run it
# Option A: Allow ALL users (use with caution)
echo "ALL ALL=(ALL) NOPASSWD: $SUDO_SCRIPT" > "$SUDOERS_FILE"

# Option B: Only allow admin group (safer alternative)
# echo "%admin ALL=(ALL) NOPASSWD: $SUDO_SCRIPT" > "$SUDOERS_FILE"

# Set correct permissions
chmod 440 "$SUDOERS_FILE"
chown root:wheel "$SUDOERS_FILE"
