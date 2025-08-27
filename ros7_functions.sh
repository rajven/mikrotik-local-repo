#!/bin/bash

# Импорт общих функций
source "$(dirname "$0")/functions.sh"

# Функция загрузки ROS 7
download_ros7() {
    local user_agent=$1
    local version_prefix=$2
    local description=$3
    local force=$4

    log "Checking ${description}"

    for firmware_version in "${versions7[@]}"; do
        log "Analyzing version ${firmware_version}"

        $WGET $WGET_OPTS -U "$user_agent" "http://upgrade.mikrotik.com/routeros/NEWEST${version_prefix}7.${firmware_version}" -O "${TARGET_DIR}/NEWEST${version_prefix}7.${firmware_version}.new"
        if ! check_error $? "Failed to get NEWEST${version_prefix}7.${firmware_version}"; then
            continue
        fi

        old_version=$(head -1 "${TARGET_DIR}/NEWEST${version_prefix}7.${firmware_version}" 2>/dev/null | awk '{print $1}')
        old_timestamp=$(head -1 "${TARGET_DIR}/NEWEST${version_prefix}7.${firmware_version}" 2>/dev/null | awk '{print $2}')
        new_version=$(head -1 "${TARGET_DIR}/NEWEST${version_prefix}7.${firmware_version}.new" | awk '{print $1}')
        new_timestamp=$(head -1 "${TARGET_DIR}/NEWEST${version_prefix}7.${firmware_version}.new" | awk '{print $2}')

        log "Latest ${description} release: ${new_version}"

        version_changed=1
        if [ "x${new_version}" = "x${old_version}" ] && [ "x${old_timestamp}" = "x${new_timestamp}" ]; then
            version_changed=
        fi

        if [ "x${force}" = "x" ] && [ "x${version_changed}" = "x" ]; then
            log "Current version ${old_version} unchanged. Skipping."
            rm -f "${TARGET_DIR}/NEWEST${version_prefix}7.${firmware_version}.new"
            continue
        fi

        log "New version found: ${new_version}"
        log "Downloading packages..."

        mkdir -p "${TARGET_DIR}/${new_version}"
        cd "${TARGET_DIR}/${new_version}" || continue

        $WGET $WGET_OPTS -U "$user_agent" "http://upgrade.mikrotik.com/routeros/${new_version}/CHANGELOG"
        if ! check_error $? "Failed to download CHANGELOG"; then
            continue
        fi

        download_err=
        for file_arch in "${firmware_arch[@]}"; do
            # Packages
            $WGET $WGET_OPTS -U "$user_agent" "http://upgrade.mikrotik.com/routeros/${new_version}/all_packages-${file_arch}-${new_version}.zip"
            if ! check_error $? "Failed to download all_packages-${file_arch}-${new_version}.zip"; then
                download_err=1
                break
            fi

            # RouterOS
            if [ "${file_arch}" = "x86" ]; then
                $WGET $WGET_OPTS -U "$user_agent" "http://upgrade.mikrotik.com/routeros/${new_version}/routeros-${new_version}.npk"
            else
                $WGET $WGET_OPTS -U "$user_agent" "http://upgrade.mikrotik.com/routeros/${new_version}/routeros-${new_version}-${file_arch}.npk"
            fi
            if ! check_error $? "Failed to download routeros for ${file_arch}"; then
                download_err=1
                break
            fi
        done

        if [ -n "${download_err}" ]; then
            log_error "Download errors for ${new_version}. Skipping."
            continue
        fi

        # Additional files
        download_additional_files "${new_version}" "$user_agent"

        mv "${TARGET_DIR}/NEWEST${version_prefix}7.${firmware_version}.new" "${TARGET_DIR}/NEWEST${version_prefix}7.${firmware_version}"
        log_success "ROS 7 version ${new_version} downloaded successfully."
    done
}

# Функция загрузки ROS 7
download_specific_ros7() {
    local user_agent=$1
    local version=$2

    log "Downloading packages..."

    mkdir -p "${TARGET_DIR}/${version}"
    cd "${TARGET_DIR}/${version}" || return 1

    $WGET $WGET_OPTS -U "$user_agent" "http://upgrade.mikrotik.com/routeros/${version}/CHANGELOG"
    if ! check_error $? "Failed to download CHANGELOG"; then
        return 1
    fi

    download_err=
    for file_arch in "${firmware_arch[@]}"; do
            # Packages
            $WGET $WGET_OPTS -U "$user_agent" "http://upgrade.mikrotik.com/routeros/${version}/all_packages-${file_arch}-${version}.zip"
            if ! check_error $? "Failed to download all_packages-${file_arch}-${version}.zip"; then
                download_err=1
                break
            fi

            # RouterOS
            if [ "${file_arch}" = "x86" ]; then
                $WGET $WGET_OPTS -U "$user_agent" "http://upgrade.mikrotik.com/routeros/${version}/routeros-${version}.npk"
            else
                $WGET $WGET_OPTS -U "$user_agent" "http://upgrade.mikrotik.com/routeros/${version}/routeros-${version}-${file_arch}.npk"
            fi
            if ! check_error $? "Failed to download routeros for ${file_arch}"; then
                download_err=1
                break
            fi
    done

    if [ -n "${download_err}" ]; then
            log_error "Download errors for ${version}. Skipping."
            return 1
    fi

    # Additional files
    download_additional_files "${version}" "$user_agent"

    log_success "ROS 7 version ${version} downloaded successfully."
}
