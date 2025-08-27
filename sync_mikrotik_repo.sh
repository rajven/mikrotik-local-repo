#!/bin/bash

# Импорт конфигурации и функций
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/functions.sh"
source "${SCRIPT_DIR}/ros6_functions.sh"
source "${SCRIPT_DIR}/ros7_functions.sh"

# Создаем директорию если нет
mkdir -p "$TARGET_DIR"

# Начало лога
log "Starting RouterOS mirror script"
log "Target directory: $TARGET_DIR"

##################################### Main ###################################################

force=$1
if [ -n "${force}" ]; then
    log "Force flag for download packages found!"
fi

# Загрузка ROS 6
download_ros6 "$force"

# Загрузка ROS 7 версий
download_ros7 "RouterOS 7.10" "" "ROS 7 before 7.12.1" "$force"
download_ros7 "RouterOS 7.12.1" "a" "ROS 7 after 7.12.1" "$force"

# Загрузка Winbox
download_winbox

log "Mirror script completed successfully"
exit 0
