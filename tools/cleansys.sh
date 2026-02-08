#!/bin/bash

set -e

ROOT=${1?}
DIRS=(
    ${ROOT}/root/.bash_history
    ${ROOT}/root/.python_history
    ${ROOT}/root/.lesshst
    ${ROOT}/root/.viminfo

    ${ROOT}/home/*/.bash_history
    ${ROOT}/home/*/.python_history
    ${ROOT}/home/*/.lesshst
    ${ROOT}/home/*/.viminfo

    ${ROOT}/var/cache/apt/*
    ${ROOT}/var/cache/apt/archives/*
    ${ROOT}/var/lib/apt/lists/*

    ${ROOT}/var/lib/dpkg/info/*.list
    ${ROOT}/var/lib/dpkg/info/*.md5sums
    ${ROOT}/var/log/*

    ${ROOT}/usr/share/man/*
    ${ROOT}/usr/share/info/*
    ${ROOT}/usr/share/doc/*

    ${ROOT}/usr/share/locale/*

    ${ROOT}/usr/share/examples/*
    ${ROOT}/usr/share/icons/*
)

[ "$1" == "/" ] && apt clean

rm -rf ${DIRS[@]}

