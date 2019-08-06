#!/bin/bash

set -e

function cleanup() {
    # clean up our temp folder
    rm -rf "${TMPDIR}"
}
trap cleanup EXIT


# default config
URL="https://distro.ibiblio.org/tinycorelinux/10.x/x86"
INPUTISO="Core-current.iso"
OUTPUTISO="tinycore-custom.iso"
ROOTFS="rootfs"
VOLUMEID="tinycore-custom"
EXTENSIONS="apache2.4.tcz sqlite3-bin.tcz python3.6.tcz python-pip.tcz mpg123.tcz pygame.tcz libxml2-python.tcz pysqlite2.tcz"
BOOTARGS=""


# optionally load user config
[ ! -z $1 ] && . "$1"


# create our working folders
TMPDIR="$(mktemp -d --tmpdir=$(pwd) 'iso.XXXXXX')"
chmod 755 "${TMPDIR}"
mkdir -p dist/{iso,tcz,dep} "${TMPDIR}/cde/optional"


# downloads a file, only if it's not already cached
function cachefile() {
    [ -f "dist/${2}/${1}" ] || wget --no-check-certificate "${URL}/${3}/${1}" -O "dist/${2}/${1}" \
                            || [[ ${2} == dep ]] && touch "dist/${2}/${1}"
}


# download the ISO
cachefile "${INPUTISO}" iso release


# get the contents of the iso
xorriso -osirrox on -indev "dist/iso/${INPUTISO}" -extract / "${TMPDIR}"


# install extensions and dependencies
while [ -n "${EXTENSIONS}" ] ; do
    DEPS=""
    for EXTENSION in ${EXTENSIONS} ; do
        cachefile "${EXTENSION}" tcz tcz
        cachefile "${EXTENSION}.dep" dep tcz
        cp "dist/tcz/${EXTENSION}" "${TMPDIR}/cde/optional"
        DEPS=$(echo ${DEPS} | cat - "dist/dep/${EXTENSION}.dep" | sort -u)
    done
    EXTENSIONS=$DEPS
done


# set extensions to start on boot
pushd ${TMPDIR}/cde/optional
    ls | tee ../onboot.lst > ../copy2fs.lst
popd


# alter isolinux config to use our changes
ISOLINUX_CFG="${TMPDIR}/boot/isolinux/isolinux.cfg"
sed -i 's/prompt 1/prompt 0/' "${ISOLINUX_CFG}"
sed -i "s/append/append cde ${BOOTARGS}/" "${ISOLINUX_CFG}"


# build the rootfs and place it on the iso
if [ -d ${ROOTFS} ] ; then
    sed -i "/^\tinitrd/ s/$/,\/boot\/overlay.gz/" "${ISOLINUX_CFG}"
    chmod -R u+w "${TMPDIR}/boot"
    pushd "${ROOTFS}"
        find | cpio -o -H newc | gzip -2 > "${TMPDIR}/boot/overlay.gz"
    popd
fi


# build a new iso
xorriso -as mkisofs -iso-level 3 -full-iso9660-filenames -volid "${VOLUMEID}" \
        -eltorito-boot boot/isolinux/isolinux.bin -boot-load-size 4 \
        -eltorito-catalog boot/isolinux/boot.cat -boot-info-table \
        -no-emul-boot -output "${OUTPUTISO}" "${TMPDIR}/"
