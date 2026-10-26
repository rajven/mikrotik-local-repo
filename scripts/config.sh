#!/bin/bash

# Config

# Directory with file mirror
TARGET_DIR="/var/www/html/routeros"
# Website address for update policies
SITE_URL="http://localhost"
# Token for cache warm-up script
WARMUP_TOKEN="CHANGE_ME"

WGET="/bin/wget"

# Disable logging
LOG_OFF=0

# for upgrade.mikrotik.com
URL_SCHEMA="https"

[[ ! -f "${WGET}" ]] && WGET=$(command -v wget)
if [[ ! -f "${WGET}" ]]; then
    echo "ERROR: wget not found! Cannot continue." >&2
    return 100
fi

# curl is used to ask the server for Content-Length (completeness checks) and to
# fetch Winbox. Optional: without it the scripts fall back to wget --spider and,
# if that fails too, to "assume the local copy is complete" (the old -nc behaviour).
CURL="$(command -v curl || true)"
# shellcheck disable=SC2034
CURL_OPTS="-sS --connect-timeout 10 --max-time 30"

# Create the mirror directory before checking write permissions, otherwise a
# fresh installation aborts with a misleading "No write permissions".
if [[ ! -d "${TARGET_DIR}" ]] && ! mkdir -p "${TARGET_DIR}" 2>/dev/null; then
    echo "ERROR: cannot create ${TARGET_DIR}! Bye..." >&2
    return 101
fi

# Checking write permissions to the mirror directory
if [[ ! -w "${TARGET_DIR}" ]]; then
    echo "WARNING: No write permissions to ${TARGET_DIR}! Bye..." >&2
    return 102
fi

# -O is always used for markers, archives are renamed from *.part after a
# successful transfer, so no truncated file can ever take the final name.
# NOTE: no -nc here! Incremental behaviour is implemented in fetch_file()
# (functions.sh), which compares the local size with the server's
# Content-Length instead of trusting the file's mere existence.
WGET_OPTS="-q --timeout=15 --read-timeout=60 --tries=2"

# Response caches of the PHP proxy layer (derived from TARGET_DIR, keep in sync
# with 'v6'/'v7' cache_file in html/mt-proxy/mt_proxy_config.php).
ROS6_CACHE_FILE="${TARGET_DIR}/ros6.version.cache"
ROS7_CACHE_FILE="${TARGET_DIR}/ros7.version.cache"

# Lock file shared by sync_mikrotik_repo.sh and download_ros.sh
SYNC_LOCK_FILE="${SYNC_LOCK_FILE:-/tmp/mikrotik-local-repo.sync.lock}"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ROS versions
versions6=("6" "6fix")
versions7=("stable" "long-term")
firmware_arch=("arm" "arm64" "mipsbe" "mmips" "ppc" "smips" "tile" "x86")

# Additional files to download
additional_files=(
    "btest.exe"
    "dude-install-VERSION.exe"
    "flashfig.exe"
    "install-image-VERSION.zip"
    "mikrotik-VERSION.iso"
    "mikrotik.mib"
    "netinstall64-VERSION.zip"
    "netinstall-VERSION.tar.gz"
    "netinstall-VERSION.zip"
)

# Winbox Settings
WINBOX_DIR="${TARGET_DIR}/winbox"
WINBOX_BASE_URL="https://download.mikrotik.com/routeros/winbox"

case "${URL_SCHEMA:-}" in
    http|https) ;;
    *)          URL_SCHEMA="http" ;;
esac
