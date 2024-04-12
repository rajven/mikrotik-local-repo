#!/bin/bash

#wget path & opts
wget_opts="-q -nc"
WGET="/bin/wget"

#path for you repo
TARGET_DIR="/mnt/md0/mirror/routeros"

# ROS 7
versions7=("stable")

#needed architecture's
firmware_arch=("arm" "arm64" "mipsbe" "mmips" "ppc" "smips" "tile" "x86")

##################################### Main ###################################################

new_version=$1

[ -z "${new_version}" ] && exit

echo "Get release: ${new_version}"

for firmware_version in "${versions7[@]}"; do

echo "Try download packages..."

if [ ! -e "${TARGET_DIR}/${new_version}" ]; then
    mkdir -p "${TARGET_DIR}/${new_version}"
    fi

cd "${TARGET_DIR}/${new_version}"
${WGET} ${wget_opts} -U "RouterOS 7.10" "http://upgrade.mikrotik.com/routeros/${new_version}/CHANGELOG"
ret=$?
if [ ${ret} -ne 0 ]; then
    echo "Error get changelog for ${new_version}. Skip release."
    continue
    fi
download_error=
for file_arch in "${firmware_arch[@]}"; do
    #packages
    ${WGET} ${wget_opts}  -U "RouterOS 7.10" "http://upgrade.mikrotik.com/routeros/${new_version}/all_packages-${file_arch}-${new_version}.zip"
    ret=$?
    if [ ${ret} -ne 0 ]; then
	echo "Error get all_packages-${file_arch}-${new_version}.zip"
	download_err=1
        break
	fi
    #routeros
    if [ "${file_arch}" == "x86" ]; then
        ${WGET} ${wget_opts}  -U "RouterOS 7.10" "http://upgrade.mikrotik.com/routeros/${new_version}/routeros-${new_version}.npk"
	else
        ${WGET} ${wget_opts}  -U "RouterOS 7.10" "http://upgrade.mikrotik.com/routeros/${new_version}/routeros-${new_version}-${file_arch}.npk"
        ${WGET} ${wget_opts}  -U "RouterOS 7.10" "http://upgrade.mikrotik.com/routeros/${new_version}/routeros-${file_arch}-${new_version}.npk"
        fi
    ret=$?
    if [ ${ret} -ne 0 ]; then
	echo "Error get routeros-${new_version}-${file_arch}.npk"
	download_err=1
        break
	fi
    done

if [ -n "${download_err}" ]; then
    echo "Found errors by download packages for ${new_version} ${firmware_version}. Skip release"
    download_err=
    [ -e "${TARGET_DIR}/NEWESTa7.${firmware_version}.new" ] && rm -f "${TARGET_DIR}/NEWESTa7.${firmware_version}.new"
    continue
    fi

#other files
${WGET} ${wget_opts} -U "RouterOS 7.10" "http://upgrade.mikrotik.com/routeros/${new_version}/btest.exe"
${WGET} ${wget_opts} -U "RouterOS 7.10" "http://upgrade.mikrotik.com/routeros/${new_version}/dude-install-${new_version}.exe"
${WGET} ${wget_opts} -U "RouterOS 7.10" "http://upgrade.mikrotik.com/routeros/${new_version}/flashfig.exe"
${WGET} ${wget_opts} -U "RouterOS 7.10" "http://upgrade.mikrotik.com/routeros/${new_version}/install-image-${new_version}.zip"
${WGET} ${wget_opts} -U "RouterOS 7.10" "http://upgrade.mikrotik.com/routeros/${new_version}/mikrotik-${new_version}.iso"
${WGET} ${wget_opts} -U "RouterOS 7.10" "http://upgrade.mikrotik.com/routeros/${new_version}/mikrotik.mib"
${WGET} ${wget_opts} -U "RouterOS 7.10" "http://upgrade.mikrotik.com/routeros/${new_version}/netinstall64-${new_version}.zip"
${WGET} ${wget_opts} -U "RouterOS 7.10" "http://upgrade.mikrotik.com/routeros/${new_version}/netinstall-${new_version}.tar.gz"
${WGET} ${wget_opts} -U "RouterOS 7.10" "http://upgrade.mikrotik.com/routeros/${new_version}/netinstall-${new_version}.zip"

#winbox
${WGET} ${wget_opts} -U "RouterOS 7.10" "https://mt.lv/winbox" -O "${TARGET_DIR}/${new_version}/winbox.exe"
${WGET} ${wget_opts} -U "RouterOS 7.10" "https://mt.lv/winbox64" -O "${TARGET_DIR}/${new_version}/winbox64.exe"

echo "ROS 7 version ${new_version} downloaded successfully."
done

exit
