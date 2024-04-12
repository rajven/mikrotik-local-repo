#!/bin/bash

#wget path & opts
wget_opts="-q -nc"
WGET="/bin/wget"

#path for you repo
TARGET_DIR="/mnt/md0/mirror/routeros"

#Analyze ROS versions
# ROS 6
#stable=>"6" lts=>"6fix"
versions6=("6" "6fix")

# ROS 7
versions7=("stable")

#needed architecture's
firmware_arch=("arm" "arm64" "mipsbe" "mmips" "ppc" "smips" "tile" "x86")

##################################### Main ###################################################

#always sync packages
force=$1

if [ -n "${force}" ]; then
    echo "Force flag for download packages found!"
    fi

###################################### ROS 6 ##################################################

echo "Check ROS 6 releases"

#get upgrade version to ROS 7

${WGET} ${wget_opts}  "http://upgrade.mikrotik.com/routeros/NEWEST6.upgrade?version=6.49.13" -O "${TARGET_DIR}/NEWEST6.upgrade"

for firmware_version in "${versions6[@]}"; do
echo "Analyze version ${firmware_version}"
echo -n "Get latest release: "
[ -e "${TARGET_DIR}/LATEST.${firmware_version}.new" ] && rm -f "${TARGET_DIR}/LATEST.${firmware_version}.new"
${WGET} ${wget_opts}  "http://upgrade.mikrotik.com/routeros/LATEST.${firmware_version}" -O "${TARGET_DIR}/LATEST.${firmware_version}.new"
ret=$?
if [ ${ret} -ne 0 ]; then
    [ -e "${TARGET_DIR}/LATEST.${firmware_version}.new" ] && rm -f "${TARGET_DIR}/LATEST.${firmware_version}.new"
    echo "Error get release 6 version ${firmware_version}"
    exit 100
    fi

old_version=$(cat "${TARGET_DIR}/LATEST.${firmware_version}" | head -1 | awk '{ print $1 }')
old_timestamp=$(cat "${TARGET_DIR}/LATEST.${firmware_version}" | head -1 | awk '{ print $2 }')
old_release_date=$(date -d @${old_timestamp})

new_version=$(cat "${TARGET_DIR}/LATEST.${firmware_version}.new" | head -1 | awk '{ print $1 }')
new_timestamp=$(cat "${TARGET_DIR}/LATEST.${firmware_version}.new" | head -1 | awk '{ print $2 }')
new_release_date=$(date -d @${new_timestamp})

echo "${new_version}"

version_changed=1
if [ "x${new_version}" == "x${old_version}" -a "x${old_timestamp}" == "x${new_timestamp}" ]; then
    version_changed=
    fi

if [ "x${force}" == "x" -a "x${version_changed}" == "x" ]; then
    echo "Current version ${old_version}. Don't changed. Next."
    rm -f "${TARGET_DIR}/LATEST.${firmware_version}.new"
    continue
    fi

echo "Found version: ${new_version} from ${new_release_date}"
echo "Old version: ${old_version} from ${old_release_date}"
echo "Try download packages..."

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

[ -e "${TARGET_DIR}/LATEST.${firmware_version}" ] && rm -f "${TARGET_DIR}/LATEST.${firmware_version}"
mv "${TARGET_DIR}/LATEST.${firmware_version}.new" "${TARGET_DIR}/LATEST.${firmware_version}"

echo "ROS 6 version ${new_version} downloaded."
done

###################################### Before ROS 7.12.1 ##################################################

echo "Check ROS 7 releases before 7.12.1"

#get latest release for ROS7
[ -e "${TARGET_DIR}/LATEST.7.new" ] && rm -f "${TARGET_DIR}/LATEST.7.new"
${WGET} ${wget_opts}  -U "RouterOS 7.10" "http://upgrade.mikrotik.com/routeros/LATEST.7" -O "${TARGET_DIR}/LATEST.7.new"
ret=$?
if [ ${ret} -ne 0 ]; then
    echo "Error get release 7 version"
    [ -e "${TARGET_DIR}/LATEST.7.new" ] && rm -f "${TARGET_DIR}/LATEST.7.new"
    exit 100
    fi
[ -e "${TARGET_DIR}/LATEST.7" ] && rm -f "${TARGET_DIR}/LATEST.7"
mv "${TARGET_DIR}/LATEST.7.new" "${TARGET_DIR}/LATEST.7"

for firmware_version in "${versions7[@]}"; do

echo "Analyze version ${firmware_version}"
echo -n "Get latest release: "

${WGET} ${wget_opts}  -U "RouterOS 7.10" "http://upgrade.mikrotik.com/routeros/NEWEST7.${firmware_version}" -O "${TARGET_DIR}/NEWEST7.${firmware_version}.new"
ret=$?
if [ ${ret} -ne 0 ]; then
    echo "Error get newest release 7 version ${firmware_version}"
    [ -e "${TARGET_DIR}/NEWEST7.${firmware_version}.new" ] && rm -f "${TARGET_DIR}/NEWEST7.${firmware_version}.new"
    exit 100
    fi

old_version=$(cat "${TARGET_DIR}/NEWEST7.${firmware_version}" | head -1 | awk '{ print $1 }')
old_timestamp=$(cat "${TARGET_DIR}/NEWEST7.${firmware_version}" | head -1 | awk '{ print $2 }')
old_release_date=$(date -d @${old_timestamp})

new_version=$(cat "${TARGET_DIR}/NEWEST7.${firmware_version}.new" | head -1 | awk '{ print $1 }')
new_timestamp=$(cat "${TARGET_DIR}/NEWEST7.${firmware_version}.new" | head -1 | awk '{ print $2 }')
new_release_date=$(date -d @${new_timestamp})

echo "${new_version}"

version_changed=1
if [ "x${new_version}" == "x${old_version}" -a "x${old_timestamp}" == "x${new_timestamp}" ]; then
    version_changed=
    fi

if [ "x${force}" == "x" -a "x${version_changed}" == "x" ]; then
    echo "Current version ${old_version}. Don't changed. Next."
    [ -e "${TARGET_DIR}/NEWEST7.${firmware_version}.new" ] && rm -f "${TARGET_DIR}/NEWEST7.${firmware_version}.new"
    continue
    fi

echo "Found version: ${new_version} from ${new_release_date}"
echo "Old version: ${old_version} from ${old_release_date}"
echo "Try download packages..."

if [ ! -e "${TARGET_DIR}/${new_version}" ]; then
    mkdir -p "${TARGET_DIR}/${new_version}"
    fi

cd "${TARGET_DIR}/${new_version}"
${WGET} ${wget_opts}  -U "RouterOS 7.10" "http://upgrade.mikrotik.com/routeros/${new_version}/CHANGELOG"
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
        ret=$?
        if [ ${ret} -ne 0 ]; then
           echo "Error get routeros-${new_version}-${file_arch}.npk"
           download_err=1
           break
           fi
        ${WGET} ${wget_opts}  -U "RouterOS 7.10" "http://upgrade.mikrotik.com/routeros/${new_version}/routeros-${file_arch}-${new_version}.npk" 2>/dev/null
        fi
    done

if [ -n "${download_err}" ]; then
    echo "Found errors by download packages for ${new_version} ${firmware_version}. Skip release"
    download_err=
    [ -e "${TARGET_DIR}/NEWEST7.${firmware_version}.new" ] && rm -f "${TARGET_DIR}/NEWEST7.${firmware_version}.new"
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

[ -e "${TARGET_DIR}/NEWEST7.${firmware_version}" ] && rm -f "${TARGET_DIR}/NEWEST7.${firmware_version}"
mv "${TARGET_DIR}/NEWEST7.${firmware_version}.new" "${TARGET_DIR}/NEWEST7.${firmware_version}"

echo "ROS 7 version ${new_version} downloaded successfully."
done


###################################### After ROS 7.12.1 ##################################################

echo "Check ROS 7 releases after 7.12.1"

echo -n "Get latest release: "

for firmware_version in "${versions7[@]}"; do

echo "Analyze version ${firmware_version}"

${WGET} ${wget_opts} -U "RouterOS 7.12.1" "http://upgrade.mikrotik.com/routeros/NEWESTa7.${firmware_version}?version=7.12.1" -O "${TARGET_DIR}/NEWESTa7.${firmware_version}.new"
ret=$?
if [ ${ret} -ne 0 ]; then
    echo "Error get newest release 7 version ${firmware_version}"
    [ -e "${TARGET_DIR}/NEWESTa7.${firmware_version}.new" ] && rm -f "${TARGET_DIR}/NEWESTa7.${firmware_version}.new"
    exit 100
    fi

old_version=$(cat "${TARGET_DIR}/NEWESTa7.${firmware_version}" | head -1 | awk '{ print $1 }')
old_timestamp=$(cat "${TARGET_DIR}/NEWESTa7.${firmware_version}" | head -1 | awk '{ print $2 }')
old_release_date=$(date -d @${old_timestamp})

new_version=$(cat "${TARGET_DIR}/NEWESTa7.${firmware_version}.new" | head -1 | awk '{ print $1 }')
new_timestamp=$(cat "${TARGET_DIR}/NEWESTa7.${firmware_version}.new" | head -1 | awk '{ print $2 }')
new_release_date=$(date -d @${new_timestamp})

echo "${new_version}"

version_changed=1
if [ "x${new_version}" == "x${old_version}" -a "x${old_timestamp}" == "x${new_timestamp}" ]; then
    version_changed=
    fi

if [ "x${force}" == "x" -a "x${version_changed}" == "x" ]; then
    echo "Current version ${old_version}. Don't changed. Next."
    [ -e "${TARGET_DIR}/NEWESTa7.${firmware_version}.new" ] && rm -f "${TARGET_DIR}/NEWESTa7.${firmware_version}.new"
    continue
    fi

echo "Found version: ${new_version} from ${new_release_date}"
echo "Old version: ${old_version} from ${old_release_date}"
echo "Try download packages..."

if [ ! -e "${TARGET_DIR}/${new_version}" ]; then
    mkdir -p "${TARGET_DIR}/${new_version}"
    fi

cd "${TARGET_DIR}/${new_version}"
${WGET} ${wget_opts} -U "RouterOS 7.12.1" "http://upgrade.mikrotik.com/routeros/${new_version}/CHANGELOG"
ret=$?
if [ ${ret} -ne 0 ]; then
    echo "Error get changelog for ${new_version}. Skip release."
    continue
    fi
download_error=
for file_arch in "${firmware_arch[@]}"; do
    #packages
    ${WGET} ${wget_opts} -U "RouterOS 7.12.1" "http://upgrade.mikrotik.com/routeros/${new_version}/all_packages-${file_arch}-${new_version}.zip"
    ret=$?
    if [ ${ret} -ne 0 ]; then
       echo "Error get all_packages-${file_arch}-${new_version}.zip"
       download_err=1
       break
       fi
    #routeros
    if [ "${file_arch}" == "x86" ]; then
        ${WGET} ${wget_opts}  -U "RouterOS 7.12.1" "http://upgrade.mikrotik.com/routeros/${new_version}/routeros-${new_version}.npk"
        if [ ${ret} -ne 0 ]; then
           echo "Error get routeros-${new_version}-${file_arch}.npk"
           download_err=1
           break
           fi
        else
        ${WGET} ${wget_opts}  -U "RouterOS 7.12.1" "http://upgrade.mikrotik.com/routeros/${new_version}/routeros-${new_version}-${file_arch}.npk"
        ret=$?
        if [ ${ret} -ne 0 ]; then
           echo "Error get routeros-${new_version}-${file_arch}.npk"
           download_err=1
           break
           fi
        ${WGET} ${wget_opts}  -U "RouterOS 7.12.1" "http://upgrade.mikrotik.com/routeros/${new_version}/routeros-${file_arch}-${new_version}.npk" 2>/dev/null
        #wireless
        ${WGET} ${wget_opts}  -U "RouterOS 7.12.1" "http://upgrade.mikrotik.com/routeros/${new_version}/wireless-${new_version}-${file_arch}.npk"
        ret=$?
        if [ ${ret} -ne 0 ]; then
           echo "Error get wireless-${new_version}-${file_arch}.zip"
           download_err=1
           break
           fi
        fi
    done

if [ -n "${download_err}" ]; then
    echo "Found errors by download packages for ${new_version} ${firmware_version}. Skip release"
    download_err=
    [ -e "${TARGET_DIR}/NEWESTa7.${firmware_version}.new" ] && rm -f "${TARGET_DIR}/NEWESTa7.${firmware_version}.new"
    continue
    fi

#other files
${WGET} ${wget_opts} -U "RouterOS 7.12.1" "http://upgrade.mikrotik.com/routeros/${new_version}/btest.exe"
${WGET} ${wget_opts} -U "RouterOS 7.12.1" "http://upgrade.mikrotik.com/routeros/${new_version}/dude-install-${new_version}.exe"
${WGET} ${wget_opts} -U "RouterOS 7.12.1" "http://upgrade.mikrotik.com/routeros/${new_version}/flashfig.exe"
${WGET} ${wget_opts} -U "RouterOS 7.12.1" "http://upgrade.mikrotik.com/routeros/${new_version}/install-image-${new_version}.zip"
${WGET} ${wget_opts} -U "RouterOS 7.12.1" "http://upgrade.mikrotik.com/routeros/${new_version}/mikrotik-${new_version}.iso"
${WGET} ${wget_opts} -U "RouterOS 7.12.1" "http://upgrade.mikrotik.com/routeros/${new_version}/mikrotik.mib"
${WGET} ${wget_opts} -U "RouterOS 7.12.1" "http://upgrade.mikrotik.com/routeros/${new_version}/netinstall64-${new_version}.zip"
${WGET} ${wget_opts} -U "RouterOS 7.12.1" "http://upgrade.mikrotik.com/routeros/${new_version}/netinstall-${new_version}.tar.gz"
${WGET} ${wget_opts} -U "RouterOS 7.12.1" "http://upgrade.mikrotik.com/routeros/${new_version}/netinstall-${new_version}.zip"

#winbox
${WGET} ${wget_opts} -U "RouterOS 7.12.1" "https://mt.lv/winbox" -O "${TARGET_DIR}/${new_version}/winbox.exe"
${WGET} ${wget_opts} -U "RouterOS 7.12.1" "https://mt.lv/winbox64" -O "${TARGET_DIR}/${new_version}/winbox64.exe"

[ -e "${TARGET_DIR}/NEWESTa7.${firmware_version}" ] && rm -f "${TARGET_DIR}/NEWESTa7.${firmware_version}"
mv "${TARGET_DIR}/NEWESTa7.${firmware_version}.new" "${TARGET_DIR}/NEWESTa7.${firmware_version}"

echo "ROS 7 version ${new_version} downloaded successfully."
done

exit
