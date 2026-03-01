#!/bin/bash
# cmd_open.sh — Start a session on an existing squashfs
# Sourced by mkramsys dispatcher. Entry point: cmd_run <sqfs-path> [--force]

cmd_run() {
    local sqfs_path=""
    local force=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --force) force=1 ;;
            -h|--help)
                cat <<EOF
Usage: mkramsys open [--force] <sqfs-path>
  --force      Overwrite existing session marker
EOF
                exit 0
                ;;
            -*) die "open: unknown option '$1'" ;;
            *)
                [ -n "$sqfs_path" ] && die "open: unexpected argument '$1'"
                sqfs_path="$1"
                ;;
        esac
        shift
    done

    [ -z "$sqfs_path" ] && die "open: <sqfs-path> is required"
    [ -f "$sqfs_path" ] || die "open: file not found: $sqfs_path"

    require_root
    require_cmd unsquashfs

    # Validate that it's actually a squashfs
    unsquashfs -s "$sqfs_path" >/dev/null 2>&1 || die "open: not a valid squashfs: $sqfs_path"

    # Resolve to absolute path
    sqfs_path="$(readlink -f "$sqfs_path")"

    # Check for existing session
    local session_file=".mkramsys-session"
    if [ -f "$session_file" ]; then
        if [ "$force" -eq 0 ]; then
            local existing
            existing=$(cat "$session_file")
            die "Session already active: $existing (use --force to overwrite, or 'mkramsys close' first)"
        fi
        # Force: close existing session if its directory still exists
        local old_session
        old_session=$(cat "$session_file")
        if [ -d "$old_session" ] && [ -f "$old_session/.mkramsys" ]; then
            info "Closing existing session: $old_session"
            rm -rf "$old_session"
        fi
        rm -f "$session_file"
    fi

    # Create session directory
    if [ -z "${WORKSPACE:-}" ]; then
        WORKSPACE=$(mktemp -d /tmp/mkramsys-session.XXXXXX)
        export WORKSPACE
    else
        mkdir -p "$WORKSPACE"
    fi

    workspace_init "$sqfs_path"

    # Write session marker in cwd
    echo "$WORKSPACE" > "$session_file"

    info "Session opened: $WORKSPACE"
    info "Source: $sqfs_path"
}
