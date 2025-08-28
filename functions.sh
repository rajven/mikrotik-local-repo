#!/bin/bash

# Функции логирования
log() {
    if [ "${LOG_OFF}" = "1" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1".
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
    fi
}

log_error() {
    if [ "${LOG_OFF}" = "1" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
    fi
}

log_success() {
    if [ "${LOG_OFF}" = "1" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1" | tee -a "$LOG_FILE"
    fi
}

# Функция проверки ошибок
check_error() {
    local ret=$1
    local message=$2
    if [ $ret -ne 0 ]; then
        log_error "$message"
        return 1
    fi
    return 0
}

# Функция загрузки дополнительных файлов
download_additional_files() {
    local version=$1
    local user_agent=${2:-""}
    
    for file in "${additional_files[@]}"; do
	file=$(echo ${file} | sed "s/VERSION/${version}/")
        if [ -n "$user_agent" ]; then
            $WGET $WGET_OPTS -U "$user_agent" "http://upgrade.mikrotik.com/routeros/${version}/${file}" || \
            log "Warning: Failed to download ${file}"
        else
            $WGET $WGET_OPTS "http://upgrade.mikrotik.com/routeros/${version}/${file}" || \
            log "Warning: Failed to download ${file}"
        fi
    done
}

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

# Функция загрузки Winbox
download_winbox() {
    log "Downloading Winbox"

    mkdir -p "$WINBOX_DIR"

    LINKS=$($WGET $WGET_OPTS https://mikrotik.com/download -O - | grep -oP 'https?://[^"]*winbox[^"]*\.(exe|zip)' || echo "")
    if [ -z "$LINKS" ]; then
        log_error "No winbox links found"
        return 1
    fi

    for LINK in $LINKS; do
        if [[ "$LINK" == ${WINBOX_BASE_URL}/* ]]; then
            RELATIVE_PATH="${WINBOX_DIR}/${LINK#${WINBOX_BASE_URL}/}"
            mkdir -p "$(dirname "$RELATIVE_PATH")"

            if [ -f "$RELATIVE_PATH" ]; then
                log "File already exists: $RELATIVE_PATH"
                continue
            fi

            log "Downloading: $LINK"
            if curl -s -L -o "$RELATIVE_PATH" "$LINK"; then
                FILE_SIZE=$(du -h "$RELATIVE_PATH" | cut -f1)
                log_success "Downloaded: $RELATIVE_PATH ($FILE_SIZE)"
            else
                log_error "Failed to download: $LINK"
                rm -f "$RELATIVE_PATH"
            fi
        else
            log "Skipping external link: $LINK"
        fi
    done
}
