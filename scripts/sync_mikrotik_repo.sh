#!/bin/bash

# Import configuration and functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# Installed layout (cron, container): the scripts live in /usr/local/bin and
# only config.sh is a symlink into the data directory.
if [[ ! -f "${SCRIPT_DIR}/functions.sh" || ! -f "${SCRIPT_DIR}/config.sh" ]]; then
    SCRIPT_DIR="/usr/local/bin"
fi

source "${SCRIPT_DIR}/config.sh" || exit $?
source "${SCRIPT_DIR}/functions.sh"
source "${SCRIPT_DIR}/ros6_functions.sh"
source "${SCRIPT_DIR}/ros7_functions.sh"

# Create a directory if not
mkdir -p "$TARGET_DIR"

# Only one transfer at a time (cron + container loop + manual download_ros.sh)
acquire_sync_lock || exit 0

# Start of log
log "Starting RouterOS mirror script"
log "Target directory: $TARGET_DIR"

##################################### Main ####################################################

force=$1
if [ -n "${force}" ]; then
    log "Force flag for download packages found!"
fi

rc=0

# Download ROS 6
download_ros6 "$force" || rc=1

# Download ROS 7 versions
download_ros7 "7.10" "" "ROS 7 before 7.12.1" "$force" || rc=1
download_ros7 "7.12.1" "a" "ROS 7 after 7.12.1" "$force" || rc=1

# Loading Winbox
download_winbox || rc=1

#warmup version cache
WARMUP_URL="${SITE_URL}/routeros/ros-warmup.php?token=${WARMUP_TOKEN}"
$WGET -q --timeout=15 --tries=1 -O /dev/null "$WARMUP_URL" >/dev/null 2>&1 \
    || log "Warning: cache warm-up request failed"

if [ "$rc" -ne 0 ]; then
    log_error "RouterOS mirror script finished with errors"
else
    log_success "RouterOS mirror script finished successfully"
fi

exit $rc
