#!/bin/bash
# cmd_init.sh — Create a standalone Debian squashfs image via debootstrap
# Sourced by mkramsys dispatcher. Entry point: cmd_run <output.sqfs> [options]
# No session is created — this is a pure image builder.

cmd_run() {
    local output=""
    local boot_dir=""
    local mirror="https://deb.debian.org/debian/"
    local codename="trixie"
    local comp_level=15
    while [ $# -gt 0 ]; do
        case "$1" in
            --boot-dir) shift; boot_dir="${1:?'--boot-dir' requires a directory}" ;;
            --mirror)  [ -n "${2:-}" ] || die "init: --mirror requires an argument"; mirror="$2"; shift ;;
            --codename) [ -n "${2:-}" ] || die "init: --codename requires an argument"; codename="$2"; shift ;;
            --comp-level) [ -n "${2:-}" ] || die "init: --comp-level requires a value"; comp_level="$2"; shift ;;
            -h|--help)
                cat <<EOF
Usage: mkramsys init [options] <output.sqfs>
  --boot-dir DIR Directory for kernel + initramfs (default: boot/ alongside output)
  --mirror URL   Debian mirror (default: https://deb.debian.org/debian/)
  --codename     Debian release (default: trixie)
  --comp-level N zstd compression level (default: 15)
EOF
                exit 0
                ;;
            -*) die "init: unknown option '$1'" ;;
            *)
                [ -n "$output" ] && die "init: unexpected argument '$1'"
                output="$1"
                ;;
        esac
        shift
    done

    [ -z "$output" ] && die "init: <output.sqfs> is required"

    # Resolve output to absolute path
    output="$(readlink -f "$output")"

    # Default boot dir: boot/ alongside the output file
    if [ -z "$boot_dir" ]; then
        boot_dir="$(dirname "$output")/boot"
    fi
    boot_dir="$(mkdir -p "$boot_dir" && readlink -f "$boot_dir")"

    require_root
    require_cmd debootstrap mksquashfs mkinitramfs

    detect_arch

    local tmproot
    tmproot=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$tmproot'" EXIT

    local root="$tmproot/rootfs"

    # ── Debootstrap ───────────────────────────────────────────────────────────

    info "Running debootstrap (arch=$ARCH, release=$codename)..."
    debootstrap --arch="$ARCH" \
        --include="linux-image-${ARCH},initramfs-tools,zstd,busybox" \
        "$codename" "$root" "$mirror"

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

    cp -r "$root/boot/"* "$boot_dir/"
    cp "$root/tmp/initrd.img-${kernel_release}" "$boot_dir/"

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

    make_squashfs "$root" "$output" "$comp_level"

    info "Base image created: $output"
    info "Boot files: $boot_dir/"
}
