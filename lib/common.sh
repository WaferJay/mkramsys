#!/bin/bash
# common.sh — Shared functions for mkramsys subcommands
# Sourced by mkramsys dispatcher and subcommand scripts.

# ── Output helpers ────────────────────────────────────────────────────────────

die() { echo "error: $*" >&2; exit 1; }
info() { echo "=> $*"; }

# ── Precondition checks ──────────────────────────────────────────────────────

require_root() {
    [ "$(id -u)" -eq 0 ] || die "This command must be run as root."
}

require_cmd() {
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "Required command '$cmd' not found."
    done
}

# ── Architecture detection ────────────────────────────────────────────────────

detect_arch() {
    case $(arch) in
        amd64|x86_64) ARCH=amd64 ;;
        i386|x86)     ARCH=i386  ;;
        *)            ARCH=$(arch) ;;
    esac
    export ARCH
}

# ── Session discovery ────────────────────────────────────────────────────────
# Finds the active session directory. If WORKSPACE was set via -w, use that.
# Otherwise, read .mkramsys-session from cwd.

session_find() {
    # If -w was used, WORKSPACE is already set by the dispatcher
    [ -n "${WORKSPACE:-}" ] && return 0

    local session_file=".mkramsys-session"
    [ -f "$session_file" ] || die "No active session (run 'mkramsys open <sqfs>' first)"

    WORKSPACE=$(cat "$session_file")
    [ -d "$WORKSPACE" ] || die "Session directory missing: $WORKSPACE"
    export WORKSPACE
}

# ── Workspace management ─────────────────────────────────────────────────────

workspace_init() {
    local source_sqfs="$1"
    mkdir -p "$WORKSPACE/upper" "$WORKSPACE/.work"
    echo "mkramsys" > "$WORKSPACE/.mkramsys"
    echo "$source_sqfs" > "$WORKSPACE/.source"
}

workspace_require() {
    [ -f "$WORKSPACE/.mkramsys" ] || die "Not a mkramsys session: $WORKSPACE (run 'mkramsys open' first)"
}

workspace_require_sqfs() {
    workspace_require
    [ -f "$WORKSPACE/.source" ] || die "No source sqfs recorded (run 'mkramsys open' first)"
    local sqfs
    sqfs=$(cat "$WORKSPACE/.source")
    [ -f "$sqfs" ] || die "Source sqfs missing: $sqfs"
}

# ── Workspace locking ────────────────────────────────────────────────────────

workspace_lock() {
    session_find
    workspace_require
    # FD 9 is used as the lock file descriptor
    exec 9>"$WORKSPACE/.lock"
    flock -n 9 || die "Another mkramsys process is using this session."
}

# ── Overlay mount/unmount ─────────────────────────────────────────────────────
# overlay_mount creates temporary lower/ and rootfs/ directories, mounts
# the source sqfs as lower and the persistent upper/ as the overlay upper.
# Sets OVERLAY_TMPDIR, LOWER, and ROOTFS for the caller.
#
# overlay_unmount reverses the mounts and removes the temp dir.
# It never touches upper/ — changes persist across commands.

OVERLAY_TMPDIR=""
LOWER=""
ROOTFS=""

overlay_mount() {
    workspace_require_sqfs

    local sqfs
    sqfs=$(cat "$WORKSPACE/.source")

    OVERLAY_TMPDIR=$(mktemp -d)
    LOWER="$OVERLAY_TMPDIR/lower"
    ROOTFS="$OVERLAY_TMPDIR/rootfs"
    mkdir -p "$LOWER" "$ROOTFS"

    # overlayfs requires workdir to be empty on the same filesystem as upperdir
    rm -rf "$WORKSPACE/.work"
    mkdir -p "$WORKSPACE/.work"

    mount -t squashfs -o ro "$sqfs" "$LOWER"
    mount -t overlay -o "lowerdir=$LOWER,upperdir=$WORKSPACE/upper,workdir=$WORKSPACE/.work" none "$ROOTFS"

    mount -o bind /dev     "$ROOTFS/dev"
    mount -o bind /dev/pts "$ROOTFS/dev/pts"
    mount -o bind /proc    "$ROOTFS/proc"
    mount -o bind /sys     "$ROOTFS/sys"

    # DNS resolution inside chroot
    if [ -f /etc/resolv.conf ]; then
        cp -L /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
    fi

    # Prevent host locale from leaking into chroot
    export LC_ALL=C
}

overlay_unmount() {
    [ -z "$ROOTFS" ] && return 0

    umount "$ROOTFS/dev/pts" 2>/dev/null || true
    umount "$ROOTFS/dev"     2>/dev/null || true
    umount "$ROOTFS/proc"    2>/dev/null || true
    umount "$ROOTFS/sys"     2>/dev/null || true
    umount "$ROOTFS"         2>/dev/null || true
    umount "$LOWER"          2>/dev/null || true

    [ -n "$OVERLAY_TMPDIR" ] && rm -rf "$OVERLAY_TMPDIR"

    OVERLAY_TMPDIR=""
    LOWER=""
    ROOTFS=""
}

# ── Session cleanup ──────────────────────────────────────────────────────────

session_close() {
    local session_dir="$WORKSPACE"

    # Remove session marker from cwd
    local session_file=".mkramsys-session"
    if [ -f "$session_file" ]; then
        local recorded
        recorded=$(cat "$session_file")
        if [ "$recorded" = "$session_dir" ]; then
            rm -f "$session_file"
        fi
    fi

    # Remove session directory
    rm -rf "$session_dir"
}

# ── Squashfs creation ─────────────────────────────────────────────────────────

make_squashfs() {
    local src="$1" dst="$2" comp_level="${3:-15}"
    info "Creating squashfs image: $dst"
    mksquashfs "$src" "$dst" \
        -comp zstd -Xcompression-level "$comp_level" \
        -b 1M -noappend \
        -always-use-fragments \
        -root-uid 0 -root-gid 0 \
        -no-recovery \
        -repro
}

# ── Chroot apt cleanup (light — no cleansys) ─────────────────────────────────

chroot_apt_clean() {
    chroot "$ROOTFS" apt-get clean -qq
    chroot "$ROOTFS" apt-get autoremove --purge -y -qq >/dev/null 2>&1 || true
}
