#!/bin/bash

#path for you repo
TARGET_DIR="/mnt/mirror/routeros"

#Analyze ROS versions
# ROS 6
#stable=>"6" lts=>"6fix"
versions6=("6" "6fix")

#ROS7
versions7=("7")

#needed architecture's
firmware_arch=("arm" "arm64" "mipsbe" "mmips" "ppc" "smips" "tile" "x86")

#path for wget
WGET="/bin/wget"

##################################### Main ###################################################

#always sync packages
force=$1

wget_opts="-q -nc"

if [ -n "${force}" ]; then
    echo "Force flag for download packages found!"
    fi

###################################### ROS 6 ##################################################

echo "Check ROS 6 releases"
for firmware_version in "${versions6[@]}"; do
echo "Analyze version ${firmware_version}"
echo "Get latest release"
${WGET} ${wget_opts}  "http://upgrade.mikrotik.com/routeros/LATEST.${firmware_version}" -O "${TARGET_DIR}/LATEST.${firmware_version}.new"
ret=$?
if [ ${ret} -ne 0 ]; then
    echo "Error get release version for ${firmware_version}"
    exit 100
    fi

old_version=$(cat "${TARGET_DIR}/LATEST.${firmware_version}" | head -1 | awk '{ print $1 }')
new_version=$(cat "${TARGET_DIR}/LATEST.${firmware_version}.new" | head -1 | awk '{ print $1 }')

if [ "x${force}" == "x" -a "x${new_version}" == "x${old_version}" ]; then
    echo "Version don't changed. Next."
    rm -f "${TARGET_DIR}/LATEST.${firmware_version}.new"
    continue
    fi

echo "Found new version ${new_version}. Old: ${old_version}. Try download packages..."
if [ ! -e "${TARGET_DIR}/${new_version}" ]; then
    mkdir -p "${TARGET_DIR}/${new_version}"
    fi

cd "${TARGET_DIR}/${new_version}"
${WGET} ${wget_opts}  "http://upgrade.mikrotik.com/routeros/${new_version}/CHANGELOG"
ret=$?
if [ ${ret} -ne 0 ]; then
    echo "Error get changelog for ${new_version}. Skip release."
    continue
    fi
download_error=
for file_arch in "${firmware_arch[@]}"; do
    #packages
    ${WGET} ${wget_opts}  "http://upgrade.mikrotik.com/routeros/${new_version}/all_packages-${file_arch}-${new_version}.zip"
    ret=$?
    if [ ${ret} -ne 0 ]; then
	echo "Error get all_packages-${file_arch}-${new_version}.zip"
	download_err=1
        break
	fi
    #routeros
    if [ "${file_arch}" == "ppc" ]; then
        ${WGET} ${wget_opts}  "http://upgrade.mikrotik.com/routeros/${new_version}/routeros-powerpc-${new_version}.npk"
	else
        ${WGET} ${wget_opts}  "http://upgrade.mikrotik.com/routeros/${new_version}/routeros-${file_arch}-${new_version}.npk"
        fi
    ret=$?
    if [ ${ret} -ne 0 ]; then
	echo "Error get routeros-${file_arch}-${new_version}.npk"
	download_err=1
        break
	fi
    done

if [ -n "${download_err}" ]; then
    echo "Found errors by download packages. Skip release"
    rm -f "${TARGET_DIR}/LATEST.${firmware_version}.new"
    download_err=
    continue
    fi

#other files
${WGET} ${wget_opts} "http://upgrade.mikrotik.com/routeros/${new_version}/btest.exe"
${WGET} ${wget_opts} "http://upgrade.mikrotik.com/routeros/${new_version}/dude-install-${new_version}.exe"
${WGET} ${wget_opts} "http://upgrade.mikrotik.com/routeros/${new_version}/flashfig.exe"
${WGET} ${wget_opts} "http://upgrade.mikrotik.com/routeros/${new_version}/install-image-${new_version}.zip"
${WGET} ${wget_opts} "http://upgrade.mikrotik.com/routeros/${new_version}/mikrotik-${new_version}.iso"
${WGET} ${wget_opts} "http://upgrade.mikrotik.com/routeros/${new_version}/mikrotik.mib"
${WGET} ${wget_opts} "http://upgrade.mikrotik.com/routeros/${new_version}/netinstall64-${new_version}.zip"
${WGET} ${wget_opts} "http://upgrade.mikrotik.com/routeros/${new_version}/netinstall-${new_version}.tar.gz"
${WGET} ${wget_opts} "http://upgrade.mikrotik.com/routeros/${new_version}/netinstall-${new_version}.zip"

#winbox
${WGET} ${wget_opts} "https://mt.lv/winbox" -O "${TARGET_DIR}/${new_version}/winbox.exe"
${WGET} ${wget_opts} "https://mt.lv/winbox64" -O "${TARGET_DIR}/${new_version}/winbox64.exe"

rm -f "${TARGET_DIR}/LATEST.${firmware_version}"
mv "${TARGET_DIR}/LATEST.${firmware_version}.new" "${TARGET_DIR}/LATEST.${firmware_version}"
done

###################################### ROS 7 ##################################################

echo "Check ROS 7 releases"
for firmware_version in "${versions7[@]}"; do
echo "Analyze version ${firmware_version}"
echo "Get latest release"
${WGET} ${wget_opts}  "http://upgrade.mikrotik.com/routeros/LATEST.${firmware_version}" -O "${TARGET_DIR}/LATEST.${firmware_version}.new"
ret=$?
if [ ${ret} -ne 0 ]; then
    echo "Error get release version for ${firmware_version}"
    exit 100
    fi

old_version=$(cat "${TARGET_DIR}/LATEST.${firmware_version}" | head -1 | awk '{ print $1 }')
new_version=$(cat "${TARGET_DIR}/LATEST.${firmware_version}.new" | head -1 | awk '{ print $1 }')

if [ "x${force}" == "x" -a "x${new_version}" == "x${old_version}" ]; then
    echo "Version don't changed. Next."
    rm -f "${TARGET_DIR}/LATEST.${firmware_version}.new"
    continue
    fi

echo "Found new version ${new_version}. Old: ${old_version}. Try download packages..."
if [ ! -e "${TARGET_DIR}/${new_version}" ]; then
    mkdir -p "${TARGET_DIR}/${new_version}"
    fi

cd "${TARGET_DIR}/${new_version}"
${WGET} ${wget_opts}  "http://upgrade.mikrotik.com/routeros/${new_version}/CHANGELOG"
ret=$?
if [ ${ret} -ne 0 ]; then
    echo "Error get changelog for ${new_version}. Skip release."
    continue
    fi
download_error=
for file_arch in "${firmware_arch[@]}"; do
    #packages
    ${WGET} ${wget_opts}  "http://upgrade.mikrotik.com/routeros/${new_version}/all_packages-${file_arch}-${new_version}.zip"
    ret=$?
    if [ ${ret} -ne 0 ]; then
	echo "Error get all_packages-${file_arch}-${new_version}.zip"
	download_err=1
        break
	fi
    #routeros
    if [ "${file_arch}" == "x86" ]; then
        ${WGET} ${wget_opts}  "http://upgrade.mikrotik.com/routeros/${new_version}/routeros-${new_version}.npk"
	else
        ${WGET} ${wget_opts}  "http://upgrade.mikrotik.com/routeros/${new_version}/routeros-${new_version}-${file_arch}.npk"
        fi
    ret=$?
    if [ ${ret} -ne 0 ]; then
	echo "Error get routeros-${new_version}-${file_arch}.npk"
	download_err=1
        break
	fi
    done

if [ -n "${download_err}" ]; then
    echo "Found errors by download packages. Skip release"
    rm -f "${TARGET_DIR}/LATEST.${firmware_version}.new"
    download_err=
    continue
    fi

#other files
${WGET} ${wget_opts} "http://upgrade.mikrotik.com/routeros/${new_version}/btest.exe"
${WGET} ${wget_opts} "http://upgrade.mikrotik.com/routeros/${new_version}/dude-install-${new_version}.exe"
${WGET} ${wget_opts} "http://upgrade.mikrotik.com/routeros/${new_version}/flashfig.exe"
${WGET} ${wget_opts} "http://upgrade.mikrotik.com/routeros/${new_version}/install-image-${new_version}.zip"
${WGET} ${wget_opts} "http://upgrade.mikrotik.com/routeros/${new_version}/mikrotik-${new_version}.iso"
${WGET} ${wget_opts} "http://upgrade.mikrotik.com/routeros/${new_version}/mikrotik.mib"
${WGET} ${wget_opts} "http://upgrade.mikrotik.com/routeros/${new_version}/netinstall64-${new_version}.zip"
${WGET} ${wget_opts} "http://upgrade.mikrotik.com/routeros/${new_version}/netinstall-${new_version}.tar.gz"
${WGET} ${wget_opts} "http://upgrade.mikrotik.com/routeros/${new_version}/netinstall-${new_version}.zip"

#winbox
${WGET} ${wget_opts} "https://mt.lv/winbox" -O "${TARGET_DIR}/${new_version}/winbox.exe"
${WGET} ${wget_opts} "https://mt.lv/winbox64" -O "${TARGET_DIR}/${new_version}/winbox64.exe"

rm -f "${TARGET_DIR}/LATEST.${firmware_version}"
mv "${TARGET_DIR}/LATEST.${firmware_version}.new" "${TARGET_DIR}/LATEST.${firmware_version}"
echo "Version ${new_version} downloaded."

done

exit
