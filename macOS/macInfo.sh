#!/bin/zsh

# ================================
# Collect System Info
# ================================

get_info() {
  PC_NAME=$(scutil --get ComputerName)
  OS_NAME=$(sw_vers -productName)
  OS_VERSION=$(sw_vers -productVersion)
  OS_BUILD=$(sw_vers -buildVersion)
  ARCH=$(uname -m)

  # Calculate uptime in human-friendly format
  BOOTTIME_EPOCH=$(sysctl -n kern.boottime | awk -F'[ ,:]+' '{print $4}')
  NOW_EPOCH=$(date +%s)
  UPTIME_SEC=$((NOW_EPOCH - BOOTTIME_EPOCH))
  DAYS=$((UPTIME_SEC/86400))
  HOURS=$(((UPTIME_SEC%86400)/3600))
  MINS=$(((UPTIME_SEC%3600)/60))
  UPTIME="${DAYS} day(s), ${HOURS} hour(s), ${MINS} min(s)"

  LAST_REBOOT=$(who -b | awk '{print $3,$4}')

  MAKE=$(sysctl -n hw.model)
  MODEL=$(system_profiler SPHardwareDataType | awk -F": " '/Model Identifier/ {print $2}')
  SERIAL=$(system_profiler SPHardwareDataType | awk -F": " '/Serial Number/ {print $2}')
  MEMORY=$(system_profiler SPHardwareDataType | awk -F": " '/Memory/ {print $2}')
  FREE_SPACE=$(df -h / | awk 'NR==2 {print $4}')

  IP_ADDRESS=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
  MAC_ADDRESS=$(ifconfig en0 | awk '/ether/{print $2}')

  INFO_TABLE="### 🖥️ System
| Property       | Value |
|----------------|-------|
| Computer Name  | $PC_NAME |
| OS             | $OS_NAME $OS_VERSION ($OS_BUILD) |
| Architecture   | $ARCH |
| Uptime         | $UPTIME |
| Last Reboot    | $LAST_REBOOT |

### 🔧 Hardware
| Property       | Value |
|----------------|-------|
| Make           | $MAKE |
| Model          | $MODEL |
| Serial Number  | $SERIAL |
| Memory         | $MEMORY |
| Free Space     | $FREE_SPACE |

### 🌐 Network
| Property       | Value |
|----------------|-------|
| IP Address     | $IP_ADDRESS |
| MAC Address    | $MAC_ADDRESS |"
}

# ================================
# Clipboard Function
# ================================
copy_info() {
  echo "$INFO_TABLE" | pbcopy
  /usr/local/bin/dialog \
    --title "✅ Copied" \
    --message "All information has been copied to the clipboard." \
    --button1text "OK" \
    --width 400 --height 200
}

# ================================
# Main Dialog Function
# ================================
show_dialog() {
  get_info

  CHOICE=$(/usr/local/bin/dialog \
    --title "💻 Mac Information" \
    --icon "SF=desktopcomputer" \
    --message "$INFO_TABLE" \
    --button1text "Copy Info" \
    --button2text "Refresh" \
    --button3text "Close" \
    --width 700 --height 600 \
    --position center \
    --buttonstyle filled)

  EXIT_CODE=$?

  case $EXIT_CODE in
    0) copy_info ;;   # Copy Info
    2) show_dialog ;; # Refresh
    3) exit 0 ;;      # Close
  esac
}

# ================================
# Run Script
# ================================
show_dialog