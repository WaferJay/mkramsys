#!/bin/bash
# cmd_driver.sh — Detect host firmware and install matching packages
# Sourced by mkramsys dispatcher. Entry point: cmd_run

cmd_run() {
    case "${1:-}" in
        -h|--help)
            echo "Usage: mkramsys driver"
            echo "  Detect host hardware firmware needs and install matching packages."
            exit 0
            ;;
    esac

    require_root
    require_cmd modinfo modprobe
    workspace_lock

    detect_arch

    # ── Phase 1: Detect firmware required by host hardware ────────────────────

    info "Detecting hardware firmware requirements..."

    local fw_list
    fw_list=$(mktemp)

    # Method 1: loaded kernel modules
    local mod
    # shellcheck disable=SC2013
    for mod in $(awk '{print $1}' /proc/modules); do
        modinfo -F firmware "$mod" 2>/dev/null >> "$fw_list" || true
    done

    # Method 2: all device modaliases -> resolve to modules -> query firmware
    local mf alias
    for mf in /sys/bus/*/devices/*/modalias; do
        [ -f "$mf" ] || continue
        alias=$(cat "$mf" 2>/dev/null) || continue
        for mod in $(modprobe --resolve-alias "$alias" 2>/dev/null); do
            modinfo -F firmware "$mod" 2>/dev/null >> "$fw_list" || true
        done
    done

    # Method 3: CPU microcode
    local microcode_pkg=""
    if grep -q "vendor_id.*AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
        microcode_pkg="amd64-microcode"
        info "AMD CPU detected, will install amd64-microcode."
    elif grep -q "vendor_id.*GenuineIntel" /proc/cpuinfo 2>/dev/null; then
        microcode_pkg="intel-microcode"
        info "Intel CPU detected, will install intel-microcode."
    fi

    # Deduplicate and drop empty lines
    sort -u "$fw_list" | sed '/^$/d' > "${fw_list}.tmp"
    mv "${fw_list}.tmp" "$fw_list"

    local fw_count
    fw_count=$(wc -l < "$fw_list")
    info "Found $fw_count unique firmware file(s) required by host hardware."

    if [ "$fw_count" -eq 0 ] && [ -z "$microcode_pkg" ]; then
        info "No firmware needed. Nothing to do."
        rm -f "$fw_list"
        return 0
    fi

    # ── Phase 2: Mount overlay ────────────────────────────────────────────────

    overlay_mount
    trap 'rm -f "$fw_list"; overlay_unmount' EXIT

    # ── Phase 3: Enable non-free-firmware repository ──────────────────────────

    info "Configuring package repositories..."

    # shellcheck disable=SC2016
    chroot "$ROOTFS" sh -c '
        add_nff() {
            # DEB822 format (.sources)
            for f in /etc/apt/sources.list.d/*.sources; do
                [ -f "$f" ] || continue
                if grep -q "^Components:" "$f" && ! grep -q "non-free-firmware" "$f"; then
                    sed -i "s/^Components:.*/& non-free-firmware/" "$f"
                    return 0
                fi
                grep -q "non-free-firmware" "$f" && return 0
            done

            # Traditional format (.list)
            for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
                [ -f "$f" ] || continue
                if grep -q "^deb " "$f" && ! grep -q "non-free-firmware" "$f"; then
                    sed -i "/^deb /s/main/main non-free-firmware/" "$f"
                    return 0
                fi
                grep -q "non-free-firmware" "$f" && return 0
            done
        }
        add_nff
    '

    chroot "$ROOTFS" apt-get update -qq

    # ── Phase 4: Map firmware files -> Debian packages via apt-file ───────────

    info "Installing apt-file for firmware package lookup..."
    chroot "$ROOTFS" apt-get install -y -qq apt-file >/dev/null
    chroot "$ROOTFS" apt-file update >/dev/null

    info "Mapping firmware files to packages..."

    # Prepare pattern file with lib/firmware/ prefix
    local patterns
    patterns=$(mktemp)
    sed 's|^|lib/firmware/|' "$fw_list" > "$patterns"

    cp "$patterns" "$ROOTFS/tmp/fw_patterns.txt"
    rm -f "$patterns" "$fw_list"

    # Runs inside chroot — dollar signs are intentionally single-quoted
    # shellcheck disable=SC2016
    chroot "$ROOTFS" sh -c '
        : > /tmp/fw_packages.txt

        for pkg in $(apt-cache search "^firmware-" 2>/dev/null | awk "{print \$1}"); do
            files=$(apt-file list "$pkg" 2>/dev/null) || continue
            if echo "$files" | grep -qFf /tmp/fw_patterns.txt; then
                matched=$(echo "$files" | grep -Ff /tmp/fw_patterns.txt | wc -l)
                echo "  $pkg  ($matched file(s) matched)"
                echo "$pkg" >> /tmp/fw_packages.txt
            fi
        done

        rm -f /tmp/fw_patterns.txt
    '

    local packages
    packages=$(sort -u "$ROOTFS/tmp/fw_packages.txt" 2>/dev/null | tr '\n' ' ')
    rm -f "$ROOTFS/tmp/fw_packages.txt"

    # ── Phase 5: Install firmware packages ────────────────────────────────────

    local all_packages
    all_packages=$(echo "$packages $microcode_pkg" | xargs)

    if [ -n "$all_packages" ]; then
        info "Installing: $all_packages"
        # shellcheck disable=SC2086
        chroot "$ROOTFS" apt-get install -y $all_packages
    else
        info "No matching firmware packages found in repository."
    fi

    # ── Phase 6: Cleanup ──────────────────────────────────────────────────────

    info "Removing temporary tools and cleaning up..."
    chroot "$ROOTFS" apt-get remove --purge -y apt-file >/dev/null
    chroot_apt_clean

    info "Driver installation complete."
}
