#!/bin/bash

# Конфигурация
TARGET_DIR="/mnt/md0/mirror/routeros"
WGET="/bin/wget"
LOG_DIR="/var/log/mirror"
LOG_OFF=0

[[ ! -f "${WGET}" ]] && WGET=$(command -v wget)
if [[ ! -f "${WGET}" ]]; then
    echo "ERROR: wget not found! Cannot continue." >&2
    exit 100
fi

# Проверка прав на запись в каталог зеркала
if [[ ! -w "${TARGET_DIR}" ]]; then
    echo "WARNING: No write permissions to ${TARGET_DIR}! Bye..." >&2
    exit 101
fi

# Проверка прав на запись в каталог лога
if [[ ! -w "${LOG_DIR}" ]]; then
    echo "WARNING: No write permissions to ${LOG_DIR}, using target directory for logging: ${TARGET_DIR}" >&2
    LOG_DIR="${TARGET_DIR}/log"
fi

[[ ! -d "${LOG_DIR}" ]] && mkdir -p "${LOG_DIR}"

if [[ ! -d "${LOG_DIR}" ]]; then
    echo "WARNING: No write permissions to ${LOG_DIR}, disable logging to file." >&2
    LOG_OFF=1
    fi

LOG_FILE="${LOG_DIR}/mirror-routeros.log"

WGET_OPTS="-q -nc"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

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
