#!/bin/bash

# ROS 6 download function
download_ros6() {
    local force=$1
    local old_version old_timestamp old_release_date
    local new_version new_timestamp new_release_date version_changed
    local firmware_version marker marker_new url rc=0

    cd "${TARGET_DIR}" || return 1
    touch "LATEST.6fix" "LATEST.6"

    log "Checking ROS 6 releases"

    for firmware_version in "${versions6[@]}"; do
        log "Analyzing version ${firmware_version}"

        marker="${TARGET_DIR}/LATEST.${firmware_version}"
        marker_new="${marker}.new"
        rm -f "${marker_new}"

        url="${URL_SCHEMA}://upgrade.mikrotik.com/routeros/LATEST.${firmware_version}"
        if ! fetch_marker "$url" "$marker_new"; then
            log_error "Failed to get LATEST.${firmware_version}"
            rc=1
            continue
        fi

        # Read versions with a single command
        read -r old_version old_timestamp _ 2>/dev/null < "${marker}"
        read -r new_version new_timestamp _ < "${marker_new}"

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
            rm -f "${marker_new}"
            continue
        fi

        log "New version found: ${new_version} from ${new_release_date}"
        log "Old version: ${old_version} from ${old_release_date}"

        # Use a single download function
        if download_specific_ros6_version "${new_version}"; then
            mv "${marker_new}" "${marker}"
            # Devices must re-ask upstream, otherwise a cached "no updates"
            # answer would keep the fleet on the previous release forever.
            prune_version_cache "${ROS6_CACHE_FILE}"
            log_success "ROS 6 version ${new_version} downloaded successfully."
        else
            log_error "Failed to download ROS 6 ${new_version}"
            rm -f "${marker_new}"
            rc=1
        fi
    done

    return $rc
}

# Download a specific ROS 6 version
download_specific_ros6_version() {
    local version=$1
    local file_arch ros_filename download_err=0 base url

    log "Downloading ROS 6 version: $version"

    base="${TARGET_DIR}/${version}"
    mkdir -p "${base}" || { log_error "Cannot create ${base}"; return 1; }
    cd "${base}" || return 1

    url="${URL_SCHEMA}://upgrade.mikrotik.com/routeros/${version}"

    # Download changelog first
    if ! fetch_file "${url}/CHANGELOG" "${base}/CHANGELOG"; then
        log_error "Failed to download CHANGELOG for ${version}"
        return 1
    fi

    for file_arch in "${firmware_arch[@]}"; do
        # Packages
        ros_filename="all_packages-${file_arch}-${version}.zip"
        if ! fetch_file "${url}/${ros_filename}" "${base}/${ros_filename}"; then
            log_error "Failed to download ${ros_filename}"
            download_err=1
            break
        fi

        # Extract the all_packages archive, automatically overwriting existing files
        log "Extracting ${ros_filename}"
        if ! unzip -o -q "${ros_filename}" -d "${base}"; then
            log_error "Failed to extract ${ros_filename}"
            download_err=1
            break
        fi

        # RouterOS - determine the filename
        if [[ "${file_arch}" = "ppc" ]]; then
            ros_filename="routeros-powerpc-${version}.npk"
        else
            ros_filename="routeros-${file_arch}-${version}.npk"
        fi

        if ! fetch_file "${url}/${ros_filename}" "${base}/${ros_filename}"; then
            log_error "Failed to download ${ros_filename} for ${file_arch}"
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
