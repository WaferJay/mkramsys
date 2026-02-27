#!/bin/bash
# cmd_close.sh — Delete session entirely
# Sourced by mkramsys dispatcher. Entry point: cmd_run [--force]

cmd_run() {
    local force=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --force) force=1 ;;
            -h|--help)
                echo "Usage: mkramsys close [--force]"
                echo "  --force  Skip confirmation prompt"
                exit 0
                ;;
            *) die "close: unknown option '$1'" ;;
        esac
        shift
    done

    require_root
    session_find
    workspace_require

    if [ "$force" -eq 0 ]; then
        echo "This will delete the session and ALL overlay changes in: $WORKSPACE"
        printf "Continue? [y/N] "
        read -r answer
        case "$answer" in
            [yY]) ;;
            *) echo "Aborted."; exit 1 ;;
        esac
    fi

    info "Closing session: $WORKSPACE"
    session_close

    info "Session closed."
}
