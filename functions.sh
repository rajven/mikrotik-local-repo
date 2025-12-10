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

# Функция загрузки Winbox с сохранением по версиям
download_winbox() {
    log "Downloading Winbox files from mikrotik.com"
    
    mkdir -p "$WINBOX_DIR"
    
    # Получаем HTML-контент страницы
    PAGE_CONTENT=$(curl -s "https://mikrotik.com/download/winbox")
    
    # Ищем все ссылки на .zip, .dmg и .sha256 файлы
    LINKS=$(echo "$PAGE_CONTENT" | grep -oP 'href="https?://[^"]*\.(zip|dmg|sha256)"' | sed 's/href="//;s/"//')
    
    # Альтернативный вариант: ищем все ссылки, содержащие download.mikrotik.com и winbox
    if [ -z "$LINKS" ]; then
        LINKS=$(echo "$PAGE_CONTENT" | grep -oP 'https?://download\.mikrotik\.com[^"]*winbox[^"]*\.(zip|dmg|sha256)"' | sed 's/"//')
    fi
    
    if [ -z "$LINKS" ]; then
        log_error "No winbox links found (.zip, .dmg or .sha256)"
        return 1
    fi
    
    # Удаляем дубликаты ссылок
    LINKS=$(echo "$LINKS" | sort -u)
    
    log "Found $(echo "$LINKS" | wc -l) unique links"
    
    for LINK in $LINKS; do
        # Извлекаем версию из URL (часть после /winbox/)
        if [[ "$LINK" =~ /routeros/winbox/([^/]+)/ ]]; then
            VERSION="${BASH_REMATCH[1]}"
            # Создаем путь для сохранения с учетом версии
            VERSION_DIR="$WINBOX_DIR/$VERSION"
        else
            VERSION_DIR="$WINBOX_DIR"
        fi
        
        # Извлекаем имя файла из URL
        FILENAME=$(basename "$LINK")
        
        # Полный путь для сохранения
        FILE_PATH="$VERSION_DIR/$FILENAME"
        
        # Создаем каталог для версии
        mkdir -p "$VERSION_DIR"
        
        # Проверяем, существует ли файл уже
        if [ -f "$FILE_PATH" ]; then
            log "File already exists: $FILE_PATH"
            continue
        fi
        
        log "Downloading: $LINK"
        
        # Скачиваем файл с обработкой ошибок
        if curl -s -L -o "$FILE_PATH" "$LINK"; then
            # Проверяем, что файл не пустой
            if [ -s "$FILE_PATH" ]; then
                FILE_SIZE=$(du -h "$FILE_PATH" | cut -f1)
                log_success "Downloaded: $FILE_PATH ($FILE_SIZE)"
            else
                log_error "Downloaded empty file: $LINK"
                rm -f "$FILE_PATH"
            fi
        else
            log_error "Failed to download: $LINK"
            rm -f "$FILE_PATH"
        fi
        
        # Небольшая пауза между загрузками
        sleep 0.5
    done
}