#!/bin/bash

# Logging functions
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

# Error checking function
check_error() {
    local ret=$1
    local message=$2
    if [ $ret -ne 0 ]; then
        log_error "$message"
        return 1
    fi
    return 0
}

# Additional files download function
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

# Convert version to numeric format
version_to_number() {
    local version=$1
    local major=$(echo $version | cut -d. -f1)
    local minor=$(echo $version | cut -d. -f2)
    local patch=$(echo $version | cut -d. -f3)
    echo $((major * 1000000 + minor * 1000 + patch))
}

# Determine the version type and required user agent
get_ros7_user_agent() {
    local version=$1
    local version_num=$(version_to_number "$version")
    local threshold_num=$(version_to_number "7.12.1")
    
    if [ $version_num -ge $threshold_num ]; then
        # Version is 7.12.1 or later
        echo "after"
    else
        # Version is earlier than 7.12.1
        echo "before"
    fi
}

# Download Winbox and store files by version
download_winbox() {
    log "Downloading Winbox files from mikrotik.com"
    
    mkdir -p "$WINBOX_DIR"
    
    # Fetch the HTML content of the page
    PAGE_CONTENT=$(curl -s "https://mikrotik.com/download/winbox")
    
    # Find all links to .zip, .dmg, and .sha256 files
    LINKS=$(echo "$PAGE_CONTENT" | grep -oP 'href="https?://[^"]*\.(zip|dmg|sha256)"' | sed 's/href="//;s/"//')
    
    # Alternative: find all links containing download.mikrotik.com and winbox
    if [ -z "$LINKS" ]; then
        LINKS=$(echo "$PAGE_CONTENT" | grep -oP 'https?://download\.mikrotik\.com[^"]*winbox[^"]*\.(zip|dmg|sha256)"' | sed 's/"//')
    fi
    
    if [ -z "$LINKS" ]; then
        log_error "No winbox links found (.zip, .dmg or .sha256)"
        return 1
    fi
    
    # Remove duplicate links
    LINKS=$(echo "$LINKS" | sort -u)
    
    log "Found $(echo "$LINKS" | wc -l) unique links"
    
    for LINK in $LINKS; do
        # Extract the version from the URL (part after /winbox/)
        if [[ "$LINK" =~ /routeros/winbox/([^/]+)/ ]]; then
            VERSION="${BASH_REMATCH[1]}"
            # Create a version-specific storage path
            VERSION_DIR="$WINBOX_DIR/$VERSION"
        else
            VERSION_DIR="$WINBOX_DIR"
        fi
        
        # Extract the filename from the URL
        FILENAME=$(basename "$LINK")
        
        # Full path for saving the file
        FILE_PATH="$VERSION_DIR/$FILENAME"
        
        # Create the version directory
        mkdir -p "$VERSION_DIR"
        
        # Check if the file already exists
        if [ -f "$FILE_PATH" ]; then
            log "File already exists: $FILE_PATH"
            continue
        fi
        
        log "Downloading: $LINK"
        
        # Download the file with error handling
        if curl -s -L -o "$FILE_PATH" "$LINK"; then
            # Check that the file is not empty
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
        
        # Small delay between downloads
        sleep 0.5
    done
}
