#!/bin/bash

# Импорт общих функций
source "$(dirname "$0")/functions.sh"

# Функция загрузки ROS 6
download_ros6() {
    local force=$1

    log "Checking ROS 6 releases"

    # Get upgrade version to ROS 7
    $WGET $WGET_OPTS "http://upgrade.mikrotik.com/routeros/NEWEST6.upgrade?version=6.49.13" -O "${TARGET_DIR}/NEWEST6.upgrade"
    check_error $? "Failed to download NEWEST6.upgrade"

    for firmware_version in "${versions6[@]}"; do
        log "Analyzing version ${firmware_version}"
        
        [ -e "${TARGET_DIR}/LATEST.${firmware_version}.new" ] && rm -f "${TARGET_DIR}/LATEST.${firmware_version}.new"
        
        $WGET $WGET_OPTS "http://upgrade.mikrotik.com/routeros/LATEST.${firmware_version}" -O "${TARGET_DIR}/LATEST.${firmware_version}.new"
        if ! check_error $? "Failed to get LATEST.${firmware_version}"; then
            [ -e "${TARGET_DIR}/LATEST.${firmware_version}.new" ] && rm -f "${TARGET_DIR}/LATEST.${firmware_version}.new"
            continue
        fi

        old_version=$(head -1 "${TARGET_DIR}/LATEST.${firmware_version}" 2>/dev/null | awk '{print $1}')
        old_timestamp=$(head -1 "${TARGET_DIR}/LATEST.${firmware_version}" 2>/dev/null | awk '{print $2}')
        old_release_date=$(date -d @${old_timestamp} 2>/dev/null || echo "unknown")

        new_version=$(head -1 "${TARGET_DIR}/LATEST.${firmware_version}.new" | awk '{print $1}')
        new_timestamp=$(head -1 "${TARGET_DIR}/LATEST.${firmware_version}.new" | awk '{print $2}')
        new_release_date=$(date -d @${new_timestamp} 2>/dev/null || echo "unknown")

        log "Latest release: ${new_version}"

        version_changed=1
        if [ "x${new_version}" = "x${old_version}" ] && [ "x${old_timestamp}" = "x${new_timestamp}" ]; then
            version_changed=
        fi

        if [ "x${force}" = "x" ] && [ "x${version_changed}" = "x" ]; then
            log "Current version ${old_version} unchanged. Skipping."
            rm -f "${TARGET_DIR}/LATEST.${firmware_version}.new"
            continue
        fi

        log "New version found: ${new_version} from ${new_release_date}"
        log "Old version: ${old_version} from ${old_release_date}"
        log "Downloading packages..."

        mkdir -p "${TARGET_DIR}/${new_version}"
        cd "${TARGET_DIR}/${new_version}" || continue

        # Download changelog first
        $WGET $WGET_OPTS "http://upgrade.mikrotik.com/routeros/${new_version}/CHANGELOG"
        if ! check_error $? "Failed to download CHANGELOG for ${new_version}"; then
            continue
        fi

        download_err=
        for file_arch in "${firmware_arch[@]}"; do
            # Packages
            $WGET $WGET_OPTS "http://upgrade.mikrotik.com/routeros/${new_version}/all_packages-${file_arch}-${new_version}.zip"
            if ! check_error $? "Failed to download all_packages-${file_arch}-${new_version}.zip"; then
                download_err=1
                break
            fi

            # RouterOS
            if [ "${file_arch}" = "ppc" ]; then
                $WGET $WGET_OPTS "http://upgrade.mikrotik.com/routeros/${new_version}/routeros-powerpc-${new_version}.npk"
            else
                $WGET $WGET_OPTS "http://upgrade.mikrotik.com/routeros/${new_version}/routeros-${file_arch}-${new_version}.npk"
            fi
            if ! check_error $? "Failed to download routeros for ${file_arch}"; then
                download_err=1
                break
            fi
        done

        if [ -n "${download_err}" ]; then
            log_error "Download errors for ${new_version}. Skipping release."
            rm -f "${TARGET_DIR}/LATEST.${firmware_version}.new"
            continue
        fi

        # Download additional files
        download_additional_files "${new_version}"

        mv "${TARGET_DIR}/LATEST.${firmware_version}.new" "${TARGET_DIR}/LATEST.${firmware_version}"
        log_success "ROS 6 version ${new_version} downloaded successfully."
    done
}

# Функция загрузки ROS 6
download_specific_ros6_version() {
    local version=$1

    log "Downloading specific ROS 6 version: $version"

    mkdir -p "${TARGET_DIR}/$version"
    cd "${TARGET_DIR}/${version}" || return 1

    # Download changelog first
    $WGET $WGET_OPTS "http://upgrade.mikrotik.com/routeros/${version}/CHANGELOG"
    if ! check_error $? "Failed to download CHANGELOG for ${version}"; then
        return 1
    fi

    download_err=
    for file_arch in "${firmware_arch[@]}"; do
        # Packages
        $WGET $WGET_OPTS "http://upgrade.mikrotik.com/routeros/${version}/all_packages-${file_arch}-${version}.zip"
        if ! check_error $? "Failed to download all_packages-${file_arch}-${version}.zip"; then
                download_err=1
                break
            fi
        # RouterOS
        if [ "${file_arch}" = "ppc" ]; then
                $WGET $WGET_OPTS "http://upgrade.mikrotik.com/routeros/${version}/routeros-powerpc-${version}.npk"
            else
                $WGET $WGET_OPTS "http://upgrade.mikrotik.com/routeros/${version}/routeros-${file_arch}-${version}.npk"
            fi
        if ! check_error $? "Failed to download routeros for ${file_arch}"; then
                download_err=1
                break
            fi
    done

    if [ -n "${download_err}" ]; then
            log_error "Download errors for ${version}. Skipping release."
            rm -f "${TARGET_DIR}/LATEST.${firmware_version}.new"
            return 1
    fi

    # Download additional files
    download_additional_files "${version}"

    log_success "ROS 6 version ${version} downloaded successfully."
}
