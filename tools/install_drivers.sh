#!/usr/bin/env sh

# install_drivers.sh - Detect host hardware firmware requirements, overlay mount
# a base squashfs image, install only the needed firmware packages, and create a
# new squashfs image.
#
# Detection strategy:
#   1. Scan loaded kernel modules (lsmod) for firmware dependencies (modinfo -F firmware)
#   2. Scan all hardware device modaliases (/sys/bus/*/devices/*/modalias), resolve
#      them to kernel modules (modprobe --resolve-alias), then query firmware deps
#   3. Detect CPU vendor and select matching microcode package (amd64-microcode /
#      intel-microcode), following the same approach as the Debian installer (hw-detect)
#   4. Deduplicate all firmware file paths
#   5. Use apt-file inside the chroot to reverse-map firmware files to Debian packages
#   6. Install only the matched firmware packages + microcode

set -e

PROG=${0##*/}
DIR=$(dirname $(readlink -f $0))
INPUT_SQFS="${1}"
OUTPUT_SQFS="${2}"
MOUNT_POINT="${3:-/tmp}"

DEBIAN_MIRROR_URL="${DEBIAN_MIRROR_URL:-https://deb.debian.org/debian/}"
DEBIAN_CODENAME="${DEBIAN_CODENAME:-trixie}"
SQUASHFS_COMPRESSION_LEVEL="${SQUASHFS_COMPRESSION_LEVEL:-15}"

usage() {
    cat <<EOF
Usage: sudo $PROG <INPUT_SQUASHFS> <OUTPUT_SQUASHFS> [MOUNT_POINT]

Detect host hardware, install matching firmware packages into a squashfs
overlay, and produce a new squashfs image.

Environment variables:
  DEBIAN_MIRROR_URL            Debian mirror  (default: https://deb.debian.org/debian/)
  DEBIAN_CODENAME              Debian release (default: trixie)
  SQUASHFS_COMPRESSION_LEVEL   zstd level     (default: 15)
  EXTRA_PACKAGES               Extra packages to install (space-separated)
EOF
    exit ${1:-0}
}

case "${1:-}" in
    help|--help) usage 0 ;;
esac

if [ -z "$INPUT_SQFS" ] || [ -z "$OUTPUT_SQFS" ]; then
    usage 1
fi

if [ $(id -u) -ne 0 ]; then
    echo "! Run this command with root privileges." >&2
    usage 1
fi

if ! [ -f "$INPUT_SQFS" ]; then
    echo "! '$INPUT_SQFS': no such file." >&2
    exit 1
fi

for cmd in mksquashfs modinfo modprobe; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "! Required command '$cmd' not found." >&2
        exit 1
    fi
done

case $(arch) in
    amd64|x86_64) ARCH=amd64 ;;
    i386|x86)     ARCH=i386  ;;
    *)            ARCH=$(arch) ;;
esac

LOWER="$MOUNT_POINT/lower"
UPPER="$MOUNT_POINT/upper"
WORK="$MOUNT_POINT/work"
ROOTFS="$MOUNT_POINT/rootfs"

cleanup() {
    echo "=> Cleaning up mounts..."
    umount "$ROOTFS/dev/pts" 2>/dev/null || true
    umount "$ROOTFS/dev"     2>/dev/null || true
    umount "$ROOTFS/proc"    2>/dev/null || true
    umount "$ROOTFS/sys"     2>/dev/null || true
    umount "$ROOTFS"         2>/dev/null || true
    umount "$LOWER"          2>/dev/null || true
    rm -rf "$LOWER" "$UPPER" "$WORK" "$ROOTFS"
}
trap cleanup EXIT

# ── Phase 1: Detect firmware required by host hardware ──────────────────────

echo "=> Detecting hardware firmware requirements..."

FW_LIST=$(mktemp)

# Method 1: loaded kernel modules
for mod in $(awk '{print $1}' /proc/modules); do
    modinfo -F firmware "$mod" 2>/dev/null >> "$FW_LIST" || true
done

# Method 2: all device modaliases → resolve to modules → query firmware
for mf in /sys/bus/*/devices/*/modalias; do
    [ -f "$mf" ] || continue
    alias=$(cat "$mf" 2>/dev/null) || continue
    for mod in $(modprobe --resolve-alias "$alias" 2>/dev/null); do
        modinfo -F firmware "$mod" 2>/dev/null >> "$FW_LIST" || true
    done
done

# Method 3: CPU microcode (same approach as Debian installer hw-detect)
MICROCODE_PKG=""
if grep -q "vendor_id.*AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
    MICROCODE_PKG="amd64-microcode"
    echo "   AMD CPU detected, will install amd64-microcode."
elif grep -q "vendor_id.*GenuineIntel" /proc/cpuinfo 2>/dev/null; then
    MICROCODE_PKG="intel-microcode"
    echo "   Intel CPU detected, will install intel-microcode."
fi

# Deduplicate and drop empty lines
sort -u "$FW_LIST" | sed '/^$/d' > "${FW_LIST}.tmp"
mv "${FW_LIST}.tmp" "$FW_LIST"

FW_COUNT=$(wc -l < "$FW_LIST")
echo "   Found $FW_COUNT unique firmware file(s) required by host hardware."

if [ "$FW_COUNT" -eq 0 ] && [ -z "${EXTRA_PACKAGES:-}" ] && [ -z "$MICROCODE_PKG" ]; then
    echo "=> No firmware needed and no extra packages requested."
    echo "   Copying input squashfs as-is."
    cp "$INPUT_SQFS" "$OUTPUT_SQFS"
    rm -f "$FW_LIST"
    trap - EXIT
    exit 0
fi

# ── Phase 2: Mount squashfs with overlay ────────────────────────────────────

echo "=> Mounting squashfs with overlay..."
mkdir -p "$LOWER" "$UPPER" "$WORK" "$ROOTFS"

mount -t squashfs -o ro "$INPUT_SQFS" "$LOWER"
mount -t overlay -o "lowerdir=$LOWER,upperdir=$UPPER,workdir=$WORK" none "$ROOTFS"

mount -o bind /dev     "$ROOTFS/dev"
mount -o bind /dev/pts "$ROOTFS/dev/pts"
mount -o bind /proc    "$ROOTFS/proc"
mount -o bind /sys     "$ROOTFS/sys"

# Ensure DNS resolution works inside chroot
if [ -f /etc/resolv.conf ]; then
    cp -L /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
fi

# Prevent host locale from leaking into chroot (locale files are cleaned)
export LC_ALL=C

# ── Phase 3: Enable non-free-firmware repository ───────────────────────────

echo "=> Configuring package repositories..."

chroot "$ROOTFS" sh -c '
    add_nff() {
        # DEB822 format (.sources)
        for f in /etc/apt/sources.list.d/*.sources; do
            [ -f "$f" ] || continue
            if grep -q "^Components:" "$f" && ! grep -q "non-free-firmware" "$f"; then
                sed -i "s/^Components:.*/& non-free-firmware/" "$f"
                return 0
            fi
            # already present
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

# ── Phase 4: Map firmware files → Debian packages via apt-file ─────────────

echo "=> Installing apt-file for firmware package lookup..."
chroot "$ROOTFS" apt-get install -y -qq apt-file >/dev/null
chroot "$ROOTFS" apt-file update >/dev/null

echo "=> Mapping firmware files to packages..."

# Prepare a grep-friendly pattern file (one pattern per line: lib/firmware/<path>)
PATTERNS=$(mktemp)
sed 's|^|lib/firmware/|' "$FW_LIST" > "$PATTERNS"

# Iterate over candidate firmware packages; check each against the pattern list.
# There are only ~20-30 firmware-* packages, so this is fast.
cp "$PATTERNS" "$ROOTFS/tmp/fw_patterns.txt"
rm -f "$PATTERNS" "$FW_LIST"

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

PACKAGES=$(cat "$ROOTFS/tmp/fw_packages.txt" 2>/dev/null | sort -u | tr '\n' ' ')
rm -f "$ROOTFS/tmp/fw_packages.txt"

# ── Phase 5: Install firmware packages ─────────────────────────────────────

ALL_PACKAGES="$PACKAGES $MICROCODE_PKG ${EXTRA_PACKAGES:-}"
ALL_PACKAGES=$(echo "$ALL_PACKAGES" | xargs)   # trim whitespace

if [ -n "$ALL_PACKAGES" ]; then
    echo "=> Installing: $ALL_PACKAGES"
    chroot "$ROOTFS" apt-get install -y $ALL_PACKAGES
else
    echo "=> No matching firmware packages found in repository."
fi

# ── Phase 6: Cleanup ───────────────────────────────────────────────────────

echo "=> Removing temporary tools and cleaning up..."

chroot "$ROOTFS" apt-get remove --purge -y apt-file >/dev/null
chroot "$ROOTFS" apt-get autoremove --purge -y >/dev/null

if [ -x "$ROOTFS/sbin/cleansys" ]; then
    chroot "$ROOTFS" /sbin/cleansys --full /
fi

"$DIR/cleansys.sh" --full "$ROOTFS"

# ── Phase 7: Create output squashfs ────────────────────────────────────────

echo "=> Unmounting system directories..."
umount "$ROOTFS/dev/pts"
umount "$ROOTFS/dev"
umount "$ROOTFS/proc"
umount "$ROOTFS/sys"

echo "=> Creating squashfs image..."
mksquashfs "$ROOTFS" "$OUTPUT_SQFS" \
    -comp zstd -Xcompression-level "$SQUASHFS_COMPRESSION_LEVEL" \
    -b 1M -noappend \
    -always-use-fragments \
    -root-uid 0 -root-gid 0 \
    -no-recovery \
    -repro

echo "=> Done: $OUTPUT_SQFS"
