#!/bin/bash

# Функция загрузки ROS 7
download_ros7() {
    local user_agent=$1
    local version_prefix=$2
    local description=$3
    local force=$4
    local old_version old_timestamp new_version new_timestamp version_changed

    log "Checking ${description}"

    for firmware_version in "${versions7[@]}"; do
        log "Analyzing version ${firmware_version}"

        $WGET $WGET_OPTS -U "$user_agent" "http://upgrade.mikrotik.com/routeros/NEWEST${version_prefix}7.${firmware_version}" -O "${TARGET_DIR}/NEWEST${version_prefix}7.${firmware_version}.new"
        if ! check_error $? "Failed to get NEWEST${version_prefix}7.${firmware_version}"; then
            continue
        fi

        # Чтение версий одной командой
        read -r old_version old_timestamp _ 2>/dev/null < "${TARGET_DIR}/NEWEST${version_prefix}7.${firmware_version}"
        read -r new_version new_timestamp _ < "${TARGET_DIR}/NEWEST${version_prefix}7.${firmware_version}.new"

        log "Latest ${description} release: ${new_version}"

        # Упрощенная проверка изменения версии
        if [[ "${new_version}" == "${old_version}" && "${old_timestamp}" == "${new_timestamp}" ]]; then
            version_changed=""
        else
            version_changed=1
        fi

        if [[ -z "${force}" && -z "${version_changed}" ]]; then
            log "Current version ${old_version} unchanged. Skipping."
            rm -f "${TARGET_DIR}/NEWEST${version_prefix}7.${firmware_version}.new"
            continue
        fi

        log "New version found: ${new_version}"

        # Использование единой функции загрузки
        if download_specific_ros7_version "${user_agent}" "${new_version}"; then
            mv "${TARGET_DIR}/NEWEST${version_prefix}7.${firmware_version}.new" "${TARGET_DIR}/NEWEST${version_prefix}7.${firmware_version}"
            log_success "ROS 7 version ${new_version} downloaded successfully."
        else
            log_error "Failed to download ROS 7 ${new_version}"
            rm -f "${TARGET_DIR}/NEWEST${version_prefix}7.${firmware_version}.new"
        fi
    done
}

# Функция загрузки конкретной версии ROS 7
download_specific_ros7_version() {
    local user_agent=$1
    local version=$2
    local file_arch ros_filename download_err=0

    log "Downloading ROS 7 version: $version"

    mkdir -p "${TARGET_DIR}/${version}"
    cd "${TARGET_DIR}/${version}" || return 1

    $WGET $WGET_OPTS -U "$user_agent" "http://upgrade.mikrotik.com/routeros/${version}/CHANGELOG"
    check_error $? "Failed to download CHANGELOG" || return 1

    for file_arch in "${firmware_arch[@]}"; do
        # Packages
        $WGET $WGET_OPTS -U "$user_agent" "http://upgrade.mikrotik.com/routeros/${version}/all_packages-${file_arch}-${version}.zip"
        if ! check_error $? "Failed to download all_packages-${file_arch}-${version}.zip"; then
            download_err=1
            break
        fi

        # RouterOS - определяем имя файла
        if [[ "${file_arch}" = "x86" ]]; then
            ros_filename="routeros-${version}.npk"
        else
            ros_filename="routeros-${version}-${file_arch}.npk"
        fi

        $WGET $WGET_OPTS -U "$user_agent" "http://upgrade.mikrotik.com/routeros/${version}/${ros_filename}"
        if ! check_error $? "Failed to download routeros for ${file_arch}"; then
            download_err=1
            break
        fi
    done

    if [[ ${download_err} -ne 0 ]]; then
        log_error "Download errors for ${version}. Skipping."
        return 1
    fi

    # Additional files
    download_additional_files "${version}" "$user_agent"

    log_success "ROS 7 version ${version} downloaded successfully."
    return 0
}
