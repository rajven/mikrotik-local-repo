#!/bin/bash

# Logging functions
log() {
    [ "${LOG_OFF:-0}" = "1" ] && return 0
    logger -t "${LOG_TAG:-$(basename "$0")}" -p daemon.info -- "$1"
}

log_error() {
    [ "${LOG_OFF:-0}" = "1" ] && return 0
    logger -t "${LOG_TAG:-$(basename "$0")}" -p daemon.err -- "ERROR: $1"
}

log_success() {
    [ "${LOG_OFF:-0}" = "1" ] && return 0
    logger -t "${LOG_TAG:-$(basename "$0")}" -p daemon.notice -- "SUCCESS: $1"
}

# Error checking function
check_error() {
    local ret=$1
    local message=$2

    if [ "$ret" -ne 0 ]; then
        log_error "$message"
        return 1
    fi

    return 0
}

# ============================================================================
# Integrity helpers
# ============================================================================

# Only "X.Y[.Z] <timestamp>" answers are usable as version markers. A proxy or
# a captive portal returning HTML with HTTP 200 must never be promoted,
# otherwise ${TARGET_DIR}/<!DOCTYPE ... is created and the real marker is lost.
valid_version_line() {
    local file=$1
    [ -s "$file" ] || return 1
    head -n 1 "$file" | LC_ALL=C grep -Eq '^[0-9]+(\.[0-9]+)+[[:space:]]+[0-9]+'
}

# Content-Length of a remote resource; prints nothing when it cannot be
# determined (non-200 answer, no header, server without HEAD support). wget only
# - the whole mirror uses a single transfer tool. Results are cached per URL, so
# a file costs at most one HEAD request per run.
declare -A REMOTE_SIZE_CACHE=()
remote_size() {
    local url=$1
    local user_agent=${2:-}
    local cached headers

    if [[ -n "${REMOTE_SIZE_CACHE[$url]+set}" ]]; then
        printf '%s' "${REMOTE_SIZE_CACHE[$url]}"
        return 0
    fi

    # --server-response prints the reply headers even with -q.
    if [ -n "$user_agent" ]; then
        headers=$($WGET --spider --server-response -q -U "$user_agent" "$url" 2>&1 | tr -d '\r')
    else
        headers=$($WGET --spider --server-response -q "$url" 2>&1 | tr -d '\r')
    fi

    cached=""
    if printf '%s' "$headers" | LC_ALL=C grep -Eq 'HTTP/1\.[0-9] 200([[:space:]]|$)'; then
        cached=$(printf '%s' "$headers" \
                | LC_ALL=C awk 'tolower($1)=="content-length:"{v=$2} END{if(v!="")print v}')
    fi

    REMOTE_SIZE_CACHE[$url]="${cached:-}"
    printf '%s' "${cached:-}"
    return 0
}

# True for an HTML error/gateway body saved under a file name: a transparent
# proxy or a captive portal can answer 200 with a page. Checked at the very
# beginning of the file (up to a BOM tolerated), so a real binary or a plain
# text file can never be misdetected.
is_error_page() {
    local file=$1
    [ -s "$file" ] || return 1
    head -c 64 "$file" | LC_ALL=C tr -d '[:space:]' '\000' \
        | LC_ALL=C grep -qiE '^.{0,4}<(!doctype[[:space:]]*html|html[[:space:]>])'
}

# Does the local copy look finished? Archives are CRC-verified, HTML error
# bodies are rejected, everything else is compared against the server's
# Content-Length. Returns:
#   0 = complete, 1 = broken/absent, 2 = cannot be determined
local_copy_state() {
    local dest=$1
    local url=$2
    local user_agent=${3:-}
    local want have

    [ -s "$dest" ] || return 1
    is_error_page "$dest" && return 1

    want=$(remote_size "$url" "$user_agent")
    have=$(stat -c%s "$dest" 2>/dev/null || echo "")

    if [[ "$dest" == *.zip ]]; then
        unzip -t -q "$dest" >/dev/null 2>&1 || return 1
    fi

    if [ -n "$want" ] && [ -n "$have" ]; then
        [ "$want" = "$have" ] || return 1
        return 0
    fi

    # No size information available: for zips the CRC test above already proved
    # the archive; for anything else assume complete (that is what "-nc" did).
    [[ "$dest" == *.zip ]] && return 0
    return 2
}

# fetch_file <url> <destination> [user_agent]
#
# Incremental and atomic:
#   * a complete local copy is NOT downloaded again (this replaces the old
#     "-nc" behaviour, but unlike "-nc" a truncated/garbage file is repaired);
#   * the transfer goes to "<destination>.part" and is renamed only after it
#     finished, optionally verifying size and archive integrity.
fetch_file() {
    local url=$1
    local dest=$2
    local user_agent=${3:-}
    local state want have tmp

    tmp="${dest}.part"
    rm -f "$tmp"

    local_copy_state "$dest" "$url" "$user_agent"
    state=$?
    case $state in
        0)
            log "Complete copy exists, skipping: $(basename "$dest")"
            return 0
            ;;
        1)
            [ -e "$dest" ] && { log "Damaged or incomplete local copy, re-downloading: $(basename "$dest")"; rm -f "$dest"; }
            ;;
        2)
            log "Remote size unknown, keeping local copy: $(basename "$dest")"
            return 0
            ;;
    esac

    mkdir -p "$(dirname "$dest")" || { log_error "Cannot create $(dirname "$dest")"; return 1; }

    if [ -n "$user_agent" ]; then
        $WGET $WGET_OPTS -U "$user_agent" "$url" -O "$tmp"
    else
        $WGET $WGET_OPTS "$url" -O "$tmp"
    fi
    if [ $? -ne 0 ]; then
        rm -f "$tmp"
        log_error "Download failed: $url"
        return 1
    fi

    if [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        log_error "Empty response: $url"
        return 1
    fi

    want=$(remote_size "$url" "$user_agent")
    have=$(stat -c%s "$tmp" 2>/dev/null || echo "")
    if [ -n "$want" ] && [ -n "$have" ] && [ "$want" != "$have" ]; then
        rm -f "$tmp"
        log_error "Truncated download ($have/$want bytes): $url"
        return 1
    fi

    if is_error_page "$tmp"; then
        rm -f "$tmp"
        log_error "Server returned an HTML page instead of the file: $url"
        return 1
    fi

    if [[ "$dest" == *.zip ]] && ! unzip -t -q "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        log_error "Corrupt archive received: $url"
        return 1
    fi

    mv -f "$tmp" "$dest" || { rm -f "$tmp"; log_error "Cannot install $dest"; return 1; }
    log "Downloaded: $(basename "$dest")$(have=$(stat -c%s "$dest" 2>/dev/null) && echo " (${have} bytes)")"
    return 0
}

# Downloads a "NEWEST*/LATEST*" marker into <dest>.new and prints the validated
# content. Returns non-zero if the answer is missing or malformed.
fetch_marker() {
    local url=$1
    local dest=$2
    local user_agent=${3:-}

    rm -f "$dest"
    fetch_file "$url" "$dest" "$user_agent" || { rm -f "$dest"; return 1; }
    valid_version_line "$dest" || {
        log_error "Malformed marker response: $url ($(head -c 60 "$dest" | tr -c '[:print:]' '?'))"
        rm -f "$dest"
        return 1
    }
    return 0
}

# Drops cached answers of the PHP proxy so devices re-ask upstream and learn
# about a freshly promoted release. The file is truncated in place (cat > file)
# to keep the owner and mode of the web server.
prune_version_cache() {
    local file=$1
    local prefix=${2:-NEWEST}
    local tmp

    [ -f "$file" ] || return 0
    LC_ALL=C grep -q "^${prefix}" "$file" || return 0

    tmp="${file}.tmp.$$"
    LC_ALL=C grep -v "^${prefix}" "$file" > "$tmp" 2>/dev/null
    # grep exits 1 when nothing matched (i.e. the whole file was pruned) - that
    # is a success here, only >=2 is a real error.
    case $? in
        0|1) cat "$tmp" > "$file" 2>/dev/null || log_error "Cannot prune $file (permissions?)" ;;
        *)   log_error "Cannot read $file while pruning" ;;
    esac
    rm -f "$tmp"
    return 0
}

# Only one transfer at a time: overlapping cron runs / manual download_ros.sh
# invocations would race on markers and on unzip -o of the same directory.
acquire_sync_lock() {
    local lock=${1:-${SYNC_LOCK_FILE:-/tmp/mikrotik-local-repo.sync.lock}}

    # A failed "exec" redirection is fatal for a non-interactive shell, so probe
    # the lock file in a subshell first and only then open it on fd 9.
    ( : > "$lock" ) 2>/dev/null || { log_error "Cannot use lock file $lock"; return 1; }
    eval "exec 9>\"\$lock\"" 2>/dev/null || return 1
    if command -v flock >/dev/null 2>&1; then
        flock -n 9 && return 0
        log_error "Another synchronisation is already running (lock: $lock)"
        return 1
    fi
    return 0
}

# ============================================================================
# Downloads
# ============================================================================

# Additional files download function
download_additional_files() {
    local version=$1
    local user_agent=${2:-""}
    local entry file

    for entry in "${additional_files[@]}"; do
        file=$(printf '%s' "$entry" | sed "s/VERSION/${version}/")
        fetch_file "${URL_SCHEMA}://upgrade.mikrotik.com/routeros/${version}/${file}" \
                   "${TARGET_DIR}/${version}/${file}" "$user_agent" || \
            log "Warning: Failed to download ${file}"
    done

    return 0
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

    # Fetch the HTML content of the page (wget again - no second tool needed;
    # -O - writes the body to stdout, redirects are followed by default)
    PAGE_CONTENT=$($WGET --timeout=15 --read-timeout=60 --tries=2 -q -O - "https://mikrotik.com/download/winbox" 2>/dev/null)
    if [ -z "${PAGE_CONTENT}" ]; then
        log_error "Cannot fetch the Winbox download page"
        return 1
    fi

    # Find all links to .zip, .dmg, and .sha256 files
    LINKS=$(printf '%s' "$PAGE_CONTENT" | grep -oP 'href="https?://[^"]*\.(zip|dmg|sha256)"' | sed 's/href="//;s/"//')

    # Alternative: find all links containing download.mikrotik.com and winbox
    if [ -z "$LINKS" ]; then
        LINKS=$(printf '%s' "$PAGE_CONTENT" | grep -oP 'https?://download\.mikrotik\.com[^"]*winbox[^"]*\.(zip|dmg|sha256)"' | sed 's/"//')
    fi

    if [ -z "$LINKS" ]; then
        log_error "No winbox links found (.zip, .dmg or .sha256)"
        return 1
    fi

    # Remove duplicate links
    LINKS=$(printf '%s' "$LINKS" | sort -u)

    log "Found $(printf '%s\n' "$LINKS" | wc -l) unique links"

    for LINK in $LINKS; do
        # Extract the version from the URL (part after /winbox/)
        if [[ "$LINK" =~ /routeros/winbox/([^/]+)/ ]]; then
            VERSION="${BASH_REMATCH[1]}"
            # Create a version-specific storage path
            VERSION_DIR="$WINBOX_DIR/$VERSION"
        else
            VERSION_DIR="$WINBOX_DIR"
        fi

        # Full path for saving the file
        FILE_PATH="$VERSION_DIR/$(basename "$LINK")"

        # Create the version directory
        mkdir -p "$VERSION_DIR"

        # fetch_file() skips complete copies, repairs damaged ones (including a
        # "<!DOCTYPE..." error page stored earlier by the old curl code) and
        # never leaves a partial download under the real name.
        fetch_file "$LINK" "$FILE_PATH" || log "Warning: failed to download $LINK"

        # Small delay between downloads
        sleep 0.5
    done

    return 0
}
