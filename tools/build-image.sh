#!/usr/bin/env bash
# =============================================================================
#  Radiosveglia_nSp -- build-image.sh
# =============================================================================
#
#  Creates a distributable radiosveglia-vX.Y.img.xz from a live Pi Zero SD.
#
#  Run this on the Pi 5 (piDiMarco) with the Pi Zero's SD card inserted.
#
#  Usage:
#    sudo ./build-image.sh /dev/sdX [vX.Y]
#
#  Example:
#    sudo ./build-image.sh /dev/sda 1.0
#
#  What it does:
#    1. Sanity-checks that the device is not the Pi 5's own disk.
#    2. Mounts the SD partitions in loopback.
#    3. Cleans sensitive and ephemeral data (logs, tokens, SSH host keys,
#       spotifyd binary, firstboot sentinel).
#    4. Unmounts, clones the raw device with dd.
#    5. Compresses with xz.
#    6. Prints a SHA256 checksum.
#
#  PREREQUISITES:
#    sudo apt install xz-utils pv
#
#  ⚠️  The SD card must be UNMOUNTED before running this script.
#  ⚠️  Run as root (sudo).
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
DEVICE="${1:-}"
VERSION="${2:-$(date +%Y%m%d)}"
OUTPUT_IMAGE="radiosveglia-v${VERSION}.img"
OUTPUT_COMPRESSED="${OUTPUT_IMAGE}.xz"

if [[ -z "${DEVICE}" ]]; then
    echo "Usage: sudo $0 /dev/sdX [version]" >&2
    echo "  /dev/sdX  -- the Pi Zero SD card (check with: lsblk)" >&2
    exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: This script must be run as root (sudo $0 ...)" >&2
    exit 1
fi

step() { printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
ok()   { printf "\033[1;32m    ok\033[0m\n"; }

# ---------------------------------------------------------------------------
# 1. Sanity checks
# ---------------------------------------------------------------------------
step "Sanity checks ..."

# Must be a block device
if [[ ! -b "${DEVICE}" ]]; then
    echo "ERROR: ${DEVICE} is not a block device." >&2
    exit 1
fi

# Must NOT be the Pi 5's root device
ROOT_DEVICE="$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null | head -1 || true)"
if [[ "/dev/${ROOT_DEVICE}" == "${DEVICE}" ]]; then
    echo "ERROR: ${DEVICE} appears to be the Pi 5's own boot device. Aborting." >&2
    exit 1
fi

# Must be unmounted
if mount | grep -q "^${DEVICE}"; then
    echo "ERROR: ${DEVICE} has mounted partitions. Unmount first:" >&2
    mount | grep "^${DEVICE}" >&2
    exit 1
fi

echo "    Device : ${DEVICE}"
echo "    Size   : $(lsblk -dno SIZE "${DEVICE}")"
echo "    Output : ${OUTPUT_COMPRESSED}"
echo ""
read -r -p "Proceed? [y/N] " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
    echo "Aborted."
    exit 0
fi
ok

# ---------------------------------------------------------------------------
# 2. Mount partitions and clean sensitive data
# ---------------------------------------------------------------------------
step "Mounting SD card partitions ..."

BOOT_MNT="$(mktemp -d)"
ROOT_MNT="$(mktemp -d)"

# Typical layout: partition 1 = boot (FAT32), partition 2 = root (ext4)
BOOT_PART="${DEVICE}1"
ROOT_PART="${DEVICE}2"

mount -o ro "${BOOT_PART}" "${BOOT_MNT}" || \
    { echo "ERROR: Could not mount ${BOOT_PART}. Wrong partition layout?" >&2; exit 1; }
mount "${ROOT_PART}" "${ROOT_MNT}" || \
    { umount "${BOOT_MNT}"; echo "ERROR: Could not mount ${ROOT_PART}." >&2; exit 1; }

ok

cleanup() {
    echo "[build-image] Cleaning up mounts ..."
    umount "${ROOT_MNT}" 2>/dev/null || true
    umount "${BOOT_MNT}" 2>/dev/null || true
    rmdir  "${ROOT_MNT}" "${BOOT_MNT}" 2>/dev/null || true
}
trap cleanup EXIT

step "Removing sensitive and ephemeral data ..."

HOME_DIR="${ROOT_MNT}/home/radiosveglia"

# Tokens and credentials
rm -fv "${HOME_DIR}/alarm/spotify_token.json"
rm -fv "${HOME_DIR}/alarm/spotify.env"

# SSH host keys (regenerated on first boot by OpenSSH)
rm -fv "${ROOT_MNT}/etc/ssh/ssh_host_"*

# Logs
find "${ROOT_MNT}/var/log" -type f -delete 2>/dev/null || true

# Shell history
rm -fv "${HOME_DIR}/.bash_history"
rm -fv "${ROOT_MNT}/root/.bash_history"

# spotifyd binary (re-downloaded at first boot by spotifyd-bootstrap)
rm -fv "${ROOT_MNT}/usr/local/bin/spotifyd"

# First-boot sentinel (ensures firstboot.sh runs again on a fresh flash)
rm -fv "${ROOT_MNT}/var/lib/radiosveglia/firstboot-done"

# apt cache
rm -rf "${ROOT_MNT}/var/cache/apt/archives/"*.deb 2>/dev/null || true

ok

# ---------------------------------------------------------------------------
# 3. Unmount before cloning
# ---------------------------------------------------------------------------
step "Unmounting partitions ..."
sync
umount "${ROOT_MNT}"
umount "${BOOT_MNT}"
rmdir  "${ROOT_MNT}" "${BOOT_MNT}"
trap - EXIT
ok

# ---------------------------------------------------------------------------
# 4. Clone raw device
# ---------------------------------------------------------------------------
step "Cloning ${DEVICE} to ${OUTPUT_IMAGE} ..."
DEVICE_SIZE_BYTES="$(blockdev --getsize64 "${DEVICE}")"
echo "    Device size: $((DEVICE_SIZE_BYTES / 1024 / 1024)) MiB"

if command -v pv &>/dev/null; then
    pv -s "${DEVICE_SIZE_BYTES}" "${DEVICE}" > "${OUTPUT_IMAGE}"
else
    echo "    (install 'pv' for a progress bar)"
    dd if="${DEVICE}" of="${OUTPUT_IMAGE}" bs=4M status=progress conv=fsync
fi
ok

# ---------------------------------------------------------------------------
# 5. Compress
# ---------------------------------------------------------------------------
step "Compressing to ${OUTPUT_COMPRESSED} ..."
echo "    This takes several minutes."
xz -v --threads=0 -9 "${OUTPUT_IMAGE}"
ok

# ---------------------------------------------------------------------------
# 6. Checksum
# ---------------------------------------------------------------------------
step "SHA256 checksum ..."
sha256sum "${OUTPUT_COMPRESSED}" | tee "${OUTPUT_COMPRESSED}.sha256"
ok

echo ""
echo "Release artifact ready:"
ls -lh "${OUTPUT_COMPRESSED}"
echo ""
echo "Attach to the GitHub Release:"
echo "  ${OUTPUT_COMPRESSED}"
echo "  ${OUTPUT_COMPRESSED}.sha256"
echo "  tools/setup-spotify.py"
echo "  spotifyd-armv7  (if freshly built)"
