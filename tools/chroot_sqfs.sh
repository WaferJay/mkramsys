#!/bin/sh

set -e

PROG=${0##*/}
DIR=$(dirname $(readlink -f "$0"))

usage() {
    echo "Usage: sudo $PROG <SQUASHFS> [MOUNT_POINT]"
    exit ${1:-0}
}

case $1 in
    help|--help)
        usage 0
        ;;
esac

if [ $(id -u) -ne 0 ]; then
    echo "! Run this command with root privileges." >&2
    usage 1
fi

SRC="${1}"
TGT="${2:-/tmp}"

if [ -z "$SRC" ]; then
    usage 1
fi

if ! [ -d "$SRC" ]; then
    echo "! '$SRC': not such file or directory."
    exit 1
fi

mkdir -p "$TGT/rootfs" "$TGT/lower" "$TGT/upper" "$TGT/work"

mount -t squashfs "$SRC" "$TGT/lower"
mount -t overlay -o "lowerdir=$DIR/overlay:$TGT/lower,upperdir=$TGT/upper,workdir=$TGT/work" none "$TGT/rootfs"

mount -o bind /dev "$TGT/rootfs/dev"
mount -o bind /dev/pts "$TGT/rootfs/dev/pts"
mount -o bind /proc "$TGT/rootfs/proc"
mount -o bind /sys "$TGT/rootfs/sys"

chroot "$TGT/rootfs" /bin/bash
