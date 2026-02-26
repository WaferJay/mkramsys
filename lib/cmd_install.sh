#!/bin/bash
# cmd_install.sh — Install packages inside the overlay image
# Sourced by mkramsys dispatcher. Entry point: cmd_run [-f file] [PKG...]

cmd_run() {
    local pkg_file=""
    local -a packages=()

    while [ $# -gt 0 ]; do
        case "$1" in
            -f) shift; pkg_file="${1:?'-f' requires a filename}" ;;
            -h|--help)
                cat <<EOF
Usage: mkramsys install [-f packages.txt] [PKG...]
  -f FILE   Read package names from FILE (one per line)
  PKG...    Packages to install
EOF
                exit 0
                ;;
            -*) die "install: unknown option '$1'" ;;
            *)  packages+=("$1") ;;
        esac
        shift
    done

    if [ ${#packages[@]} -eq 0 ] && [ -z "$pkg_file" ]; then
        die "install: nothing to do (provide packages or -f file)"
    fi

    [ -n "$pkg_file" ] && [ ! -f "$pkg_file" ] && die "install: file not found: $pkg_file"

    require_root
    workspace_lock

    overlay_mount
    trap overlay_unmount EXIT

    # ── Read packages from file ───────────────────────────────────────────────

    if [ -n "$pkg_file" ]; then
        while IFS= read -r line; do
            line="${line%%#*}"       # strip comments
            line="${line## }"        # trim leading space
            line="${line%% }"        # trim trailing space
            [ -n "$line" ] && packages+=("$line")
        done < "$pkg_file"
    fi

    # ── Install packages ──────────────────────────────────────────────────────

    if [ ${#packages[@]} -gt 0 ]; then
        info "Installing packages: ${packages[*]}"
        chroot "$ROOTFS" apt-get update -qq
        chroot "$ROOTFS" apt-get install -y "${packages[@]}"
    fi

    # ── Cleanup ───────────────────────────────────────────────────────────────

    chroot_apt_clean

    info "Install complete."
}
