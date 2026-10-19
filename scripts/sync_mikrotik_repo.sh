#!/bin/bash

# Import configuration and functions
#SCRIPT_DIR="$(dirname "$0")"
SCRIPT_DIR="/usr/local/bin"

source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/functions.sh"
source "${SCRIPT_DIR}/ros6_functions.sh"
source "${SCRIPT_DIR}/ros7_functions.sh"

# Create a directory if not
mkdir -p "$TARGET_DIR"

# Start of log
log "Starting RouterOS mirror script"
log "Target directory: $TARGET_DIR"

##################################### Main ####################################################

force=$1
if [ -n "${force}" ]; then
    log "Force flag for download packages found!"
fi

# Download ROS 6
download_ros6 "$force"

# Download ROS 7 versions
download_ros7 "7.10" "" "ROS 7 before 7.12.1" "$force"
download_ros7 "7.12.1" "a" "ROS 7 after 7.12.1" "$force"

# Loading Winbox
download_winbox

#warmup version cache
$WGET -q "${SITE_URL}/routeros/ros-warmup.php?token=${WARMUP_TOKEN}" -O /dev/null 2>/dev/null 1>&2

exit 0
