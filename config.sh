#!/bin/bash

# Configuration
TARGET_DIR="/var/www/html/routeros"
# this site url
SITE_URL="http://localhost"
# wget path
WGET="/bin/wget"
# disable log
LOG_OFF=0
# url schema for upgrade.mikrotik.com
URL_SCHEMA="http"

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

# Winbox settings
WINBOX_DIR="${TARGET_DIR}/winbox"
# winbox always downlodaded by https
WINBOX_BASE_URL="https://download.mikrotik.com/routeros/winbox"

case "${URL_SCHEMA:-}" in
    http|https) ;;
    *)          URL_SCHEMA="http" ;;
esac

[[ ! -f "${WGET}" ]] && WGET=$(command -v wget)
if [[ ! -f "${WGET}" ]]; then
    echo "ERROR: wget not found! Cannot continue." >&2
    exit 100
fi

# Check write permissions for the mirror directory
if [[ ! -w "${TARGET_DIR}" ]]; then
    echo "WARNING: No write permissions to ${TARGET_DIR}! Bye..." >&2
    exit 101
fi

WGET_OPTS="-q -nc"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
