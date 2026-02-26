#!/bin/bash
# cmd_build.sh — Produce final squashfs image from overlay
# Sourced by mkramsys dispatcher. Entry point: cmd_run [-o output.sqfs]

cmd_run() {
    local output=""
    local comp_level=15

    while [ $# -gt 0 ]; do
        case "$1" in
            -o) shift; output="${1:?'-o' requires a filename}" ;;
            --comp-level) shift; comp_level="${1:?'--comp-level' requires a value}" ;;
            -h|--help)
                cat <<EOF
Usage: mkramsys build [-o output.sqfs] [--comp-level N]
  -o FILE        Output squashfs path (default: WORKSPACE/output.sqfs)
  --comp-level N zstd compression level (default: 15)

Note: build runs cleansys --full, writing deletions into the overlay upper
directory. This is a terminal operation — run 'mkramsys reset' before further
modifications if needed.
EOF
                exit 0
                ;;
            *) die "build: unknown option '$1'" ;;
        esac
        shift
    done

    : "${output:=$WORKSPACE/output.sqfs}"

    require_root
    require_cmd mksquashfs
    workspace_lock

    overlay_mount
    trap overlay_unmount EXIT

    local scriptdir
    scriptdir="$(dirname "$(readlink -f "$LIBDIR")")"

    # ── Clean inside chroot ───────────────────────────────────────────────────

    info "Running cleansys --full inside chroot..."
    if [ -x "$ROOTFS/sbin/cleansys" ]; then
        chroot "$ROOTFS" /sbin/cleansys --full /
    fi

    # ── Clean from host side ──────────────────────────────────────────────────

    info "Running cleansys --full from host..."
    "$scriptdir/tools/cleansys.sh" --full "$ROOTFS"

    # ── Unmount bind mounts (keep overlay for mksquashfs) ─────────────────────

    umount "$ROOTFS/dev/pts" 2>/dev/null || true
    umount "$ROOTFS/dev"     2>/dev/null || true
    umount "$ROOTFS/proc"    2>/dev/null || true
    umount "$ROOTFS/sys"     2>/dev/null || true

    # ── Create output squashfs ────────────────────────────────────────────────

    make_squashfs "$ROOTFS" "$output" "$comp_level"

    info "Build complete: $output"
}
