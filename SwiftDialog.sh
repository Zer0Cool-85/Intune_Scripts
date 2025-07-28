#!/bin/bash

# Define script variables
logFile="/var/tmp/dialog.log"
DIALOG="/usr/local/bin/dialog"
loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
loggedInUserFullName=$( id -F "${loggedInUser}" )
loggedInUserFirstName=$( echo "$loggedInUserFullName" | sed -E 's/^.*, // ; s/([^ ]*).*/\1/' | sed 's/\(.\{25\}\).*/\1…/' | awk '{print ( $0 == toupper($0) ? toupper(substr($0,1,1))substr(tolower($0),2) : toupper(substr($0,1,1))substr($0,2) )}' )
userID=$(id -u "$loggedInUser")

# Get the current hour (24-hour format)
currentHour=$(date +"%H")

# Set greeting based on time
if [ "$currentHour" -ge 5 ] && [ "$currentHour" -lt 12 ]; then
    timeGreeting="Good morning"
elif [ "$currentHour" -ge 12 ] && [ "$currentHour" -lt 17 ]; then
    timeGreeting="Good afternoon"
else
    timeGreeting="Good evening"
fi

rm -f "$logFile"
touch "$logFile"

# Launch SwiftDialog in progress mode as user
sudo -u "$loggedInUser" "$DIALOG" \
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

sleep 4
echo "progresstext: Configuring default dock..." >> "$logFile"
echo "icon: SF=dock.arrow.down.rectangle" >> "$logFile"
#sudo jamf policy -event 
sleep 2
echo "progresstext: Installing application..." >> "$logFile"
echo "icon: SF=macbook" >> "$logFile"
#sudo jamf policy -event 
sleep 2
echo "progresstext: Verifying configuration..." >> "$logFile"
echo "icon: SF=checklist" >> "$logFile"
#sudo jamf policy -event 
sleep 2
echo "progress: hide" >> "$logFile"
echo "message: Configuration Complete!" >> "$logFile"
echo "icon: SF=checkmark.seal,colour=green" >> "$logFile"
#sudo jamf policy -event 
sleep 2
echo "message: + <br><br> Enjoy your Mac, and have a great $( date +'%A' )!" >> "$logFile"
sleep 4
echo "quit:" >> "$logFile"



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
