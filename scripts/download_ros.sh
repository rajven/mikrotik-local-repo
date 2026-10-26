#!/bin/bash

# Импорт конфигурации и функций
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [[ ! -f "${SCRIPT_DIR}/functions.sh" || ! -f "${SCRIPT_DIR}/config.sh" ]]; then
    SCRIPT_DIR="/usr/local/bin"
fi

source "${SCRIPT_DIR}/config.sh" || exit $?
source "${SCRIPT_DIR}/functions.sh"
source "${SCRIPT_DIR}/ros6_functions.sh"
source "${SCRIPT_DIR}/ros7_functions.sh"

# Создаем директорию если нет
mkdir -p "$TARGET_DIR"

# Не мешаем работающей синхронизации (и наоборот)
acquire_sync_lock || exit 1

# Начало лога
log "Starting RouterOS download script"
#log "Target directory: $TARGET_DIR"

##################################### Main ###################################################

force=$1
version=$2

if [ -n "${force}" ] && [ "${force}" != "force" ]; then
    # Если первый параметр не "force", то это может быть версия
    if [ -z "${version}" ]; then
        version="${force}"
        force=""
    fi
fi

if [ -n "${force}" ]; then
    log "Force flag for download packages found!"
fi

# Функция для загрузки конкретной версии
download_specific_version() {
    local version=$1
    local version_type=""
    
    if [[ "$version" =~ ^6\. ]]; then
        version_type="ros6"
    elif [[ "$version" =~ ^7\. ]]; then
        version_type="ros7"
    else
        log_error "Unknown version format: $version"
        exit 1
    fi
    
    case $version_type in
        "ros6")
            download_specific_ros6_version "$version"
            ;;
        "ros7")
            local user_agent_info=$(get_ros7_user_agent "$version")
            if [ "${user_agent_info}" == 'after' ]; then
        	download_specific_ros7_version "7.12.1" "$version"
        	else
        	download_specific_ros7_version "7.10" "$version"
		fi
            ;;
    esac
}

if [ -n "${version}" ]; then
    # Загрузка конкретной версии
    download_specific_version "$version" || { log_error "Download of ${version} failed"; exit 1; }
else
    # Если версия не передана - не делаем ничего
    log "No version specified. Exiting."
    exit 0
fi

log "Script completed successfully"
exit 0
