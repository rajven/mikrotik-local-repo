#!/bin/bash

# ROS 7 download function
download_ros7() {
    local ros_version=$1
    local user_agent="RouterOS $1"
    local version_prefix=$2
    local description=$3
    local force=$4
    local old_version old_timestamp new_version new_timestamp version_changed
    local firmware_version marker marker_new url rc=0

    log "Checking ${description}"

    for firmware_version in "${versions7[@]}"; do
        #skip check long-term before 7.12.1
        if [[ -z ${version_prefix} && "${firmware_version}" == "long-term" ]]; then
            continue
        fi

        marker="${TARGET_DIR}/NEWEST${version_prefix}7.${firmware_version}"
        marker_new="${marker}.new"
        # A leftover marker.new (interrupted run) must never block this check:
        # wget writes the -O target even on failure, and the incremental
        # download logic would then refuse to refresh it.
        rm -f "${marker_new}"
        log "Analyzing version ${firmware_version}"

        url="${URL_SCHEMA}://upgrade.mikrotik.com/routeros/NEWEST${version_prefix}7.${firmware_version}?version=${ros_version}"
        if ! fetch_marker "$url" "$marker_new" "$user_agent"; then
            log_error "Failed to get NEWEST${version_prefix}7.${firmware_version}"
            rc=1
            continue
        fi

        # Read versions with a single command
        read -r old_version old_timestamp _ 2>/dev/null < "${marker}"
        read -r new_version new_timestamp _ < "${marker_new}"

        log "Latest ${description} release: ${new_version}"

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

        log "New version found: ${new_version}"

        # Use a single download function
        if download_specific_ros7_version "${ros_version}" "${new_version}"; then
            mv "${marker_new}" "${marker}"
            # Devices must re-ask upstream, otherwise a cached "no updates"
            # answer would keep the fleet on the previous release forever.
            prune_version_cache "${ROS7_CACHE_FILE}"
            log_success "ROS 7 version ${new_version} downloaded successfully."
        else
            log_error "Failed to download ROS 7 ${new_version}"
            rm -f "${marker_new}"
            rc=1
        fi
    done

    return $rc
}

# Download a specific ROS 7 version
download_specific_ros7_version() {
    local ros_version=$1
    local user_agent="RouterOS $1"
    local version=$2
    local file_arch ros_filename download_err=0 base url

    log "Downloading ROS 7 version: $version"

    base="${TARGET_DIR}/${version}"
    mkdir -p "${base}" || { log_error "Cannot create ${base}"; return 1; }
    cd "${base}" || return 1

    url="${URL_SCHEMA}://upgrade.mikrotik.com/routeros/${version}"

    # CHANGELOG and packages.csv are the two files MikroTik is known to
    # re-publish under the same name, so they are always fetched again.
    rm -f "${base}/CHANGELOG"
    if ! fetch_file "${url}/CHANGELOG" "${base}/CHANGELOG" "$user_agent"; then
        log_error "Failed to download CHANGELOG"
        return 1
    fi

    # packages.csv
    rm -f "${base}/packages.csv"
    fetch_file "${url}/packages.csv" "${base}/packages.csv" "$user_agent"
    check_error $? "Failed to download packages.csv"

    for file_arch in "${firmware_arch[@]}"; do
        # Packages
        ros_filename="all_packages-${file_arch}-${version}.zip"
        if ! fetch_file "${url}/${ros_filename}" "${base}/${ros_filename}" "$user_agent"; then
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
        if [[ "${file_arch}" = "x86" ]]; then
            ros_filename="routeros-${version}.npk"
        else
            ros_filename="routeros-${version}-${file_arch}.npk"
        fi

        if ! fetch_file "${url}/${ros_filename}" "${base}/${ros_filename}" "$user_agent"; then
            log_error "Failed to download ${ros_filename} for ${file_arch}"
            download_err=1
            break
        fi

	#upgrade package
        ros_filename="routeros-${file_arch}-${version}.npk"
        if ! fetch_file "${url}/${ros_filename}" "${base}/${ros_filename}" "$user_agent"; then
            log_error "Failed to download ${ros_filename} for ${file_arch}"
            download_err=1
            break
        fi

        local user_agent_info=$(get_ros7_user_agent "$version")
        if [ "${file_arch}" != "x86" ] && [ "${user_agent_info}" == 'after' ]; then
            # Download wireless after 7.12
            ros_filename="wireless-${version}-${file_arch}.npk"
            if ! fetch_file "${url}/${ros_filename}" "${base}/${ros_filename}" "$user_agent"; then
                log_error "Failed to download ${ros_filename} for ${file_arch}"
                download_err=1
                break
            fi
        fi
    done

    if [[ ${download_err} -ne 0 ]]; then
        log_error "Download errors for ${version}. Skipping."
        return 1
    fi

    # Additional files
    download_additional_files "${version}" "$user_agent"

    return 0
}
