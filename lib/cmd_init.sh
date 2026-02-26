#!/bin/bash
# cmd_init.sh — Create base Debian squashfs image via debootstrap
# Sourced by mkramsys dispatcher. Entry point: cmd_run [--force]

cmd_run() {
    local force=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --force) force=1 ;;
            -h|--help)
                echo "Usage: mkramsys init [--force]"
                echo "  --force  Re-initialize, deleting existing overlay changes"
                exit 0
                ;;
            *) die "init: unknown option '$1'" ;;
        esac
        shift
    done

    require_root
    require_cmd debootstrap mksquashfs mkinitramfs

    detect_arch

    if [ -f "$WORKSPACE/.mkramsys" ]; then
        if [ "$force" -eq 0 ]; then
            die "Workspace already initialized. Use --force to re-initialize."
        fi
        info "Re-initializing workspace (--force)..."
        rm -rf "${WORKSPACE:?}/upper" "${WORKSPACE:?}/.work" "${WORKSPACE:?}/base.sqfs" "${WORKSPACE:?}/boot"
    fi

    mkdir -p "$WORKSPACE"

    local tmproot
    tmproot=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$tmproot'" EXIT

    local root="$tmproot/rootfs"

    # ── Debootstrap ───────────────────────────────────────────────────────────

    info "Running debootstrap (arch=$ARCH, release=$DEBIAN_CODENAME)..."
    debootstrap --arch="$ARCH" \
        --include="linux-image-${ARCH},initramfs-tools" \
        "$DEBIAN_CODENAME" "$root" "$DEBIAN_MIRROR_URL"

    # ── Configure image ───────────────────────────────────────────────────────

    local scriptdir
    scriptdir="$(dirname "$(readlink -f "$LIBDIR")")"

    cp "$scriptdir/tools/cleansys.sh" "$root/sbin/cleansys"
    chmod 755 "$root/sbin/cleansys"

    # System locale: C.UTF-8 (built into glibc, survives locale cleanup)
    printf 'LANG=C.UTF-8\nLC_ALL=C.UTF-8\n' > "$root/etc/default/locale"

    # ── Mount system directories ──────────────────────────────────────────────

    mount -o bind /dev     "$root/dev"
    mount -o bind /dev/pts "$root/dev/pts"
    mount -o bind /proc    "$root/proc"
    mount -o bind /sys     "$root/sys"

    export LC_ALL=C

    # ── Install ramsys boot script ────────────────────────────────────────────

    mkdir -p "$root/etc/initramfs-tools/scripts"
    cp "$scriptdir/initramfs-tools/scripts/ramsys" "$root/etc/initramfs-tools/scripts/ramsys"
    cp "$scriptdir/initramfs-tools/modules" "$root/etc/initramfs-tools/modules"

    # ── Generate initramfs and extract boot files ─────────────────────────────

    local kernel_release
    kernel_release=$(find "$root/lib/modules" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort -V -r | head -1)

    info "Generating initramfs for kernel $kernel_release..."
    chroot "$root" /sbin/mkinitramfs -o "/tmp/initrd.img-${kernel_release}" "$kernel_release"

    mkdir -p "$WORKSPACE/boot"
    cp -r "$root/boot/"* "$WORKSPACE/boot/"
    cp "$root/tmp/initrd.img-${kernel_release}" "$WORKSPACE/boot/"

    # ── Purge kernel and clean ────────────────────────────────────────────────

    info "Purging kernel packages..."
    chroot "$root" /bin/apt purge --auto-remove -y \
        "linux-image-${ARCH}" "linux-image-${kernel_release}" >/dev/null 2>&1

    chroot "$root" /sbin/cleansys --full /
    "$scriptdir/tools/cleansys.sh" --full "$root"

    # ── Unmount and create squashfs ───────────────────────────────────────────

    umount "$root/dev/pts"
    umount "$root/dev"
    umount "$root/proc"
    umount "$root/sys"

    make_squashfs "$root" "$WORKSPACE/base.sqfs"

    # Write marker after successful squashfs creation
    workspace_init

    info "Base image created: $WORKSPACE/base.sqfs"
    info "Boot files: $WORKSPACE/boot/"
}
