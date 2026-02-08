#!/usr/bin/env sh

set -e

PROG=${0##*/}
DIR=$(dirname $(readlink -f $0))
OUT_SQFS="${1}"
ROOT="${2:-/tmp/debian-root}"

usage() {
    echo "Usage: sudo $PROG <SQUASHFS_FILE> [TMP_DEBIAN_ROOT]"
    exit ${1:-0}
}

if ! which -s debootstrap; then
    echo "! debootstrap not found. You need to install debootstrap manually." >&2
    exit 1
fi
if ! which -s mksquashfs; then
    echo "! mksquashfs not found. You need to install debootstrap manually." >&2
    exit 1
fi

if [ -z "$ROOT" ]; then
    usage 1
fi

if [ $(id -u) -ne 0 ]; then
    echo "! Run this command with root privileges." >&2
    usage 1
fi

case $(arch) in
    amd64|x86_64)
        ARCH=amd64
        ;;
    i386|x86)
        ARCH=i386
        ;;
    *)
        ARCH=$(arch)
        ;;
esac

DEBIAN_MIRROR_URL="${DEBIAN_MIRROR_URL:-https://deb.debian.org/debian/}"
DEBIAN_CODENAME="${DEBIAN_CODENAME:-trixie}"
SQUASHFS_COMPRESSION_LEVEL=${SQUASHFS_COMPRESSION_LEVEL:-15}

debootstrap --arch="${ARCH}" --include="linux-image-${ARCH},initramfs-tools" "${DEBIAN_CODENAME}" "${ROOT}" "${DEBIAN_MIRROR_URL}"

cp "$DIR/cleansys.sh" "${ROOT}/sbin/cleansys"
chmod 755 "${ROOT}/sbin/cleansys"

mount -o bind /dev "$ROOT/dev"
mount -o bind /dev/pts "$ROOT/dev/pts"
mount -o bind /proc "$ROOT/proc"
mount -o bind /sys "$ROOT/sys"

KERNEL_RELEASE=$(ls /lib/modules | sort -n -r | head -1)
chroot "${ROOT}" /sbin/mkinitramfs -o "/tmp/initrd.img-${KERNEL_RELEASE}"

#cp "${ROOT}/tmp/initrd.img-${KERNEL_RELEASE}" .
#cp "${ROOT}/boot/vmlinuz-${KERNEL_RELEASE}" .

cp -r "${ROOT}/boot" .

chroot "${ROOT}" /bin/apt purge --auto-remove -y "linux-image-${ARCH}" "linux-image-${KERNEL_RELEASE}-${ARCH}"
chroot "${ROOT}" /sbin/cleansys /

"$DIR/cleansys.sh" "${ROOT}"

umount "$ROOT/dev/pts"
umount "$ROOT/dev"
umount "$ROOT/proc"
umount "$ROOT/sys"

mksquashfs "${ROOT}" "${OUT_SQFS}" \
    -comp zstd -Xcompression-level "${SQUASHFS_COMPRESSION_LEVEL}" \
    -b 1M -noappend \
    -always-use-fragments \
    -root-uid 0 -root-gid 0 \
    -no-recovery \
    -repro
