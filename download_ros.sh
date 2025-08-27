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

# Функция для преобразования версии в числовой формат
version_to_number() {
    local version=$1
    local major=$(echo $version | cut -d. -f1)
    local minor=$(echo $version | cut -d. -f2)
    local patch=$(echo $version | cut -d. -f3)
    echo $((major * 1000000 + minor * 1000 + patch))
}

# Функция для определения типа версии и нужного user agent
get_ros7_user_agent() {
    local version=$1
    local version_num=$(version_to_number "$version")
    local threshold_num=$(version_to_number "7.12.1")
    
    if [ $version_num -ge $threshold_num ]; then
        # Версия равна или выше 7.12.1
        echo "after"
    else
        # Версия ниже 7.12.1
        echo "before"
    fi
}

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
            log "Downloading specific ROS 6 version: $version"
            download_specific_ros6_version "$version"
            ;;
        "ros7")
            log "Downloading specific ROS 7 version: $version"
            local user_agent_info=$(get_ros7_user_agent "$version")
            if [ "${user_agent_info}" == 'after' ]; then
        	download_specific_ros7 "RouterOS 7.12.1" "$version"
        	else
        	download_specific_ros7 "RouterOS 7.10" "$version"
		fi
            ;;
    esac
}

if [ -n "${version}" ]; then
    # Загрузка конкретной версии
    download_specific_version "$version"
else
    # Если версия не передана - не делаем ничего
    log "No version specified. Exiting."
    exit 0
fi

log "Script completed successfully"
exit 0
