#!/bin/bash

set -e

FULL=0
for arg in "$@"; do
    case "$arg" in
        --full) FULL=1 ;;
        --help|-h)
            echo "Usage: $0 [--full] <ROOT>"
            echo "  --full  Also clean temp files, logs and debconf cache"
            exit 0
            ;;
        *) ROOT="$arg" ;;
    esac
done

: ${ROOT:?Usage: $0 [--full] <ROOT>}

BASE_DIRS=(
    # ── User history and cache files ──
    ${ROOT}/root/.bash_history
    ${ROOT}/root/.python_history
    ${ROOT}/root/.lesshst
    ${ROOT}/root/.viminfo
    ${ROOT}/root/.wget-hsts
    ${ROOT}/root/.sudo_as_admin_successful
    ${ROOT}/root/.cache
    ${ROOT}/root/.local/share

    ${ROOT}/home/*/.bash_history
    ${ROOT}/home/*/.python_history
    ${ROOT}/home/*/.lesshst
    ${ROOT}/home/*/.viminfo
    ${ROOT}/home/*/.wget-hsts
    ${ROOT}/home/*/.sudo_as_admin_successful
    ${ROOT}/home/*/.cache
    ${ROOT}/home/*/.local/share

    # ── APT cache and package lists ──
    ${ROOT}/var/cache/apt/*
    ${ROOT}/var/cache/apt/archives/*
    ${ROOT}/var/lib/apt/lists/*

    # ── System caches (safe to regenerate) ──
    ${ROOT}/var/cache/man/*
    ${ROOT}/var/backups/*

    # ── Documentation ──
    ${ROOT}/usr/share/man/*
    ${ROOT}/usr/share/info/*
    ${ROOT}/usr/share/doc/*
    ${ROOT}/usr/share/groff/*
    ${ROOT}/usr/share/lintian/*
    ${ROOT}/usr/share/bug/*
    ${ROOT}/usr/share/common-licenses/*

    # ── Locale and i18n ──
    ${ROOT}/usr/share/locale/*

    # ── Desktop / GUI data ──
    ${ROOT}/usr/share/examples/*
    ${ROOT}/usr/share/icons/*
)

# Items that may disrupt running services; only clean with --full
FULL_DIRS=(
    ${ROOT}/tmp/*
    ${ROOT}/var/tmp/*
    ${ROOT}/var/log/*
    ${ROOT}/var/log/journal/*
    ${ROOT}/var/cache/debconf/*
)

[ "$ROOT" == "/" ] && apt clean

rm -rf ${BASE_DIRS[@]}
[ "$FULL" -eq 1 ] && rm -rf ${FULL_DIRS[@]}

# Remove Python bytecode cache
find "${ROOT}/usr" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
