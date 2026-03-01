#!/bin/bash
# cmd_commit.sh — Finalize: cleansys + squashfs + close session
# Sourced by mkramsys dispatcher. Entry point: cmd_run <output.sqfs>

cmd_run() {
    local output=""
    local comp_level=15

    while [ $# -gt 0 ]; do
        case "$1" in
            --comp-level) shift; comp_level="${1:?'--comp-level' requires a value}" ;;
            -h|--help)
                cat <<EOF
Usage: mkramsys commit [--comp-level N] <output.sqfs>
  --comp-level N zstd compression level (default: 15)

Runs cleansys, creates final squashfs, and closes the session.
This is a terminal operation — the session is deleted after commit.
EOF
                exit 0
                ;;
            -*) die "commit: unknown option '$1'" ;;
            *)
                [ -n "$output" ] && die "commit: unexpected argument '$1'"
                output="$1"
                ;;
        esac
        shift
    done

    [ -z "$output" ] && die "commit: <output.sqfs> is required"

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

    # ── Close session ─────────────────────────────────────────────────────────

    overlay_unmount
    trap - EXIT

    session_close

    info "Commit complete: $output"
    info "Session closed."
}
