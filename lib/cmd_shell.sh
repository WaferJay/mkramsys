#!/bin/bash
# cmd_shell.sh — Chroot into the overlay image
# Interface mirrors bash(1): shell, shell -c CMD, shell -l, shell SCRIPT [ARGS]
# Sourced by mkramsys dispatcher. Entry point: cmd_run [options] [script [args]]

cmd_run() {
    local cmd_string="" login=""

    while [ $# -gt 0 ]; do
        case "$1" in
            -c) shift; cmd_string="${1:?'-c' requires a command string}" ;;
            -l|--login) login=1 ;;
            -h|--help)
                cat <<EOF
Usage: mkramsys shell [options] [SCRIPT [ARGS...]]

Options:
  -c STRING   Execute command string
  -l          Start a login shell (source /etc/profile)

Without arguments, opens an interactive bash shell.
With a script path, copies it into the chroot and executes it.
EOF
                exit 0
                ;;
            *) break ;;
        esac
        shift
    done

    require_root
    workspace_lock

    overlay_mount
    trap overlay_unmount EXIT

    if [ -n "$cmd_string" ]; then
        chroot "$ROOTFS" /bin/bash -c "$cmd_string" || true
    elif [ $# -gt 0 ]; then
        local script="$1"; shift
        [ ! -f "$script" ] && die "shell: file not found: $script"
        local script_name
        script_name=$(basename "$script")
        cp "$script" "$ROOTFS/tmp/$script_name"
        chmod 755 "$ROOTFS/tmp/$script_name"
        chroot "$ROOTFS" "/tmp/$script_name" "$@" || true
        rm -f "$ROOTFS/tmp/$script_name"
    elif [ -n "$login" ]; then
        chroot "$ROOTFS" /bin/bash -l || true
    else
        chroot "$ROOTFS" /bin/bash || true
    fi
}
