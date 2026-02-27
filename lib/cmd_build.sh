#!/bin/bash
# cmd_build.sh — Snapshot current overlay state as squashfs (non-destructive)
# Sourced by mkramsys dispatcher. Entry point: cmd_run -o <output.sqfs>

cmd_run() {
    local output=""
    local comp_level=15

    while [ $# -gt 0 ]; do
        case "$1" in
            -o) shift; output="${1:?'-o' requires a filename}" ;;
            --comp-level) shift; comp_level="${1:?'--comp-level' requires a value}" ;;
            -h|--help)
                cat <<EOF
Usage: mkramsys build -o <output.sqfs> [--comp-level N]
  -o FILE        Output squashfs path (required)
  --comp-level N zstd compression level (default: 15)

Snapshots the current overlay state without running cleansys.
The session remains active for further modifications.
EOF
                exit 0
                ;;
            *) die "build: unknown option '$1'" ;;
        esac
        shift
    done

    [ -z "$output" ] && die "build: -o <output.sqfs> is required"

    require_root
    require_cmd mksquashfs
    workspace_lock

    overlay_mount
    trap overlay_unmount EXIT

    # ── Unmount bind mounts (keep overlay for mksquashfs) ─────────────────────

    umount "$ROOTFS/dev/pts" 2>/dev/null || true
    umount "$ROOTFS/dev"     2>/dev/null || true
    umount "$ROOTFS/proc"    2>/dev/null || true
    umount "$ROOTFS/sys"     2>/dev/null || true

    # ── Create output squashfs ────────────────────────────────────────────────

    make_squashfs "$ROOTFS" "$output" "$comp_level"

    info "Build complete: $output"
}
