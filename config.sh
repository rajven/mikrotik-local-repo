#!/bin/bash

# Конфигурация
TARGET_DIR="/mnt/md0/mirror/routeros"
WGET="/bin/wget"

#vars
LOG_FILE="${TARGET_DIR}/mirror.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
WGET_OPTS="-q -nc"

# Версии ROS
versions6=("6" "6fix")
versions7=("stable")
firmware_arch=("arm" "arm64" "mipsbe" "mmips" "ppc" "smips" "tile" "x86")

# Дополнительные файлы для загрузки
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

# Настройки Winbox
WINBOX_DIR="${TARGET_DIR}/winbox"
WINBOX_BASE_URL="https://download.mikrotik.com/routeros/winbox"
