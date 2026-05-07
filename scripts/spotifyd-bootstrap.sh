#!/usr/bin/env bash
# =============================================================================
#  Radiosveglia_nSp -- spotifyd-bootstrap.sh
# =============================================================================
#
#  Downloads the spotifyd -slim precompiled binary for armv7 (statically
#  linked, no libssl dependency) and installs it to /usr/local/bin/spotifyd.
#
#  Run automatically on the first boot by spotifyd-bootstrap.service.
#  Can also be run manually to reinstall or upgrade spotifyd:
#
#    ~/scripts/spotifyd-bootstrap.sh
#
#  The SPOTIFYD_VERSION variable below pins the binary to a known-good
#  release. Update it when a new release is tested and approved.
# =============================================================================

set -euo pipefail

SPOTIFYD_VERSION="0.3.5"
ARCH="armv7"
VARIANT="slim"   # statically linked, no libssl dependency -- required on Trixie
BINARY_NAME="spotifyd-linux-${ARCH}-${VARIANT}"
DOWNLOAD_URL="https://github.com/Spotifyd/spotifyd/releases/download/v${SPOTIFYD_VERSION}/${BINARY_NAME}.tar.gz"
INSTALL_PATH="/usr/local/bin/spotifyd"
TMP_DIR="$(mktemp -d)"

cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

log() { echo "[spotifyd-bootstrap] $*"; }

# ---------------------------------------------------------------------------
# Check if already installed at the right version
# ---------------------------------------------------------------------------
if command -v spotifyd &>/dev/null; then
    current="$(spotifyd --version 2>/dev/null | awk '{print $2}' || true)"
    if [[ "${current}" == "${SPOTIFYD_VERSION}" ]]; then
        log "spotifyd ${SPOTIFYD_VERSION} already installed at ${INSTALL_PATH} -- nothing to do."
        exit 0
    fi
    log "Found spotifyd ${current}, upgrading to ${SPOTIFYD_VERSION}."
fi

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
log "Downloading spotifyd v${SPOTIFYD_VERSION} (${ARCH}, ${VARIANT}) ..."
log "URL: ${DOWNLOAD_URL}"

curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --retry 3 \
    --retry-delay 5 \
    --output "${TMP_DIR}/spotifyd.tar.gz" \
    "${DOWNLOAD_URL}"

# ---------------------------------------------------------------------------
# Verify the download is not empty / is a valid tar
# ---------------------------------------------------------------------------
if [[ ! -s "${TMP_DIR}/spotifyd.tar.gz" ]]; then
    echo "ERROR: Downloaded file is empty. Check network connectivity." >&2
    exit 1
fi

tar -xzf "${TMP_DIR}/spotifyd.tar.gz" -C "${TMP_DIR}"

BINARY="${TMP_DIR}/spotifyd"
if [[ ! -f "${BINARY}" ]]; then
    echo "ERROR: Expected 'spotifyd' not found in the archive." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
log "Installing to ${INSTALL_PATH} ..."
sudo install -m 755 "${BINARY}" "${INSTALL_PATH}"

# ---------------------------------------------------------------------------
# Sanity check
# ---------------------------------------------------------------------------
if ! "${INSTALL_PATH}" --version &>/dev/null; then
    echo "ERROR: Installed binary does not run. Wrong arch or missing dependency?" >&2
    exit 1
fi

log "Installed: $("${INSTALL_PATH}" --version)"

# ---------------------------------------------------------------------------
# Enable and start spotifyd user service (if systemd user session is active)
# ---------------------------------------------------------------------------
if systemctl --user is-enabled spotifyd.service &>/dev/null || true; then
    log "Restarting spotifyd.service ..."
    systemctl --user daemon-reload
    systemctl --user restart spotifyd.service || true
fi

log "Done."
