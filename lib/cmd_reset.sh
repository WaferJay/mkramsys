#!/bin/bash
# cmd_reset.sh — Discard overlay changes
# Sourced by mkramsys dispatcher. Entry point: cmd_run [--force]

cmd_run() {
    local force=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --force) force=1 ;;
            -h|--help)
                echo "Usage: mkramsys reset [--force]"
                echo "  --force  Skip confirmation prompt"
                exit 0
                ;;
            *) die "reset: unknown option '$1'" ;;
        esac
        shift
    done

    require_root
    workspace_require

    if [ "$force" -eq 0 ]; then
        echo "This will discard ALL overlay changes in: $WORKSPACE/upper"
        printf "Continue? [y/N] "
        read -r answer
        case "$answer" in
            [yY]) ;;
            *) echo "Aborted."; exit 1 ;;
        esac
    fi

    info "Resetting overlay..."
    rm -rf "$WORKSPACE/upper" "$WORKSPACE/.work"
    mkdir -p "$WORKSPACE/upper"

    info "Overlay reset. Base image is unchanged."
}
