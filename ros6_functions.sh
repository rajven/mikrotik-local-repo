#!/bin/bash

# ROS 6 download function
download_ros6() {
    local force=$1
    local old_version old_timestamp old_release_date
    local new_version new_timestamp new_release_date version_changed

    cd "${TARGET_DIR}" || return 1
    touch "LATEST.6fix" "LATEST.6"

    log "Checking ROS 6 releases"

    for firmware_version in "${versions6[@]}"; do
        log "Analyzing version ${firmware_version}"
        
        rm -f "${TARGET_DIR}/LATEST.${firmware_version}.new"
        
        $WGET $WGET_OPTS "http://upgrade.mikrotik.com/routeros/LATEST.${firmware_version}" -O "${TARGET_DIR}/LATEST.${firmware_version}.new"
        if ! check_error $? "Failed to get LATEST.${firmware_version}"; then
            rm -f "${TARGET_DIR}/LATEST.${firmware_version}.new"
            continue
        fi

        # Read versions with a single command
        read -r old_version old_timestamp _ 2>/dev/null < "${TARGET_DIR}/LATEST.${firmware_version}"
        read -r new_version new_timestamp _ < "${TARGET_DIR}/LATEST.${firmware_version}.new"

        old_release_date=$(date -d "@${old_timestamp}" 2>/dev/null || echo "unknown")
        new_release_date=$(date -d "@${new_timestamp}" 2>/dev/null || echo "unknown")

        log "Latest release: ${new_version}"

        # Simplified version change check
        if [[ "${new_version}" == "${old_version}" && "${old_timestamp}" == "${new_timestamp}" ]]; then
            version_changed=""
        else
            version_changed=1
        fi

        if [[ -z "${force}" && -z "${version_changed}" ]]; then
            log "Current version ${old_version} unchanged. Skipping."
            rm -f "${TARGET_DIR}/LATEST.${firmware_version}.new"
            continue
        fi

        log "New version found: ${new_version} from ${new_release_date}"
        log "Old version: ${old_version} from ${old_release_date}"

        # Use a single download function
        if download_specific_ros6_version "${new_version}"; then
            mv "${TARGET_DIR}/LATEST.${firmware_version}.new" "${TARGET_DIR}/LATEST.${firmware_version}"
            log_success "ROS 6 version ${new_version} downloaded successfully."
        else
            log_error "Failed to download ROS 6 ${new_version}"
            rm -f "${TARGET_DIR}/LATEST.${firmware_version}.new"
        fi
    done

}

# Download a specific ROS 6 version
download_specific_ros6_version() {
    local version=$1
    local file_arch ros_filename download_err=0

    log "Downloading ROS 6 version: $version"

    mkdir -p "${TARGET_DIR}/${version}"
    cd "${TARGET_DIR}/${version}" || return 1

    # Download changelog first
    $WGET $WGET_OPTS "http://upgrade.mikrotik.com/routeros/${version}/CHANGELOG"
    check_error $? "Failed to download CHANGELOG for ${version}" || return 1

    for file_arch in "${firmware_arch[@]}"; do
        # Packages
        $WGET $WGET_OPTS "http://upgrade.mikrotik.com/routeros/${version}/all_packages-${file_arch}-${version}.zip"
        if ! check_error $? "Failed to download all_packages-${file_arch}-${version}.zip"; then
            download_err=1
            break
        fi

        # Extract the all_packages archive, automatically overwriting existing files
        log "Extracting all_packages-${file_arch}-${version}.zip"
        unzip -o -q "all_packages-${file_arch}-${version}.zip"
        if ! check_error $? "Failed to extract all_packages-${file_arch}-${version}.zip"; then
            download_err=1
            break
        fi

        # RouterOS - determine the filename
        if [[ "${file_arch}" = "ppc" ]]; then
            ros_filename="routeros-powerpc-${version}.npk"
        else
            ros_filename="routeros-${file_arch}-${version}.npk"
        fi

        $WGET $WGET_OPTS "http://upgrade.mikrotik.com/routeros/${version}/${ros_filename}"
        if ! check_error $? "Failed to download routeros for ${file_arch}"; then
            download_err=1
            break
        fi
    done

    if [[ ${download_err} -ne 0 ]]; then
        log_error "Download errors for ${version}. Skipping release."
        return 1
    fi

    # Download additional files
    download_additional_files "${version}"


    return 0
}
