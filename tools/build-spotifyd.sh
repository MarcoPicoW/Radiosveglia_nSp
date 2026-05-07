#!/usr/bin/env bash
# =============================================================================
#  Radiosveglia_nSp -- build-spotifyd.sh
# =============================================================================
#
#  Cross-compiles spotifyd for armv7 (Pi Zero 2 W) on a Raspberry Pi 5.
#  Produces a statically linked binary equivalent to the -slim precompiled
#  release, with features: alsa_backend,dbus_mpris.
#
#  Run this on the Pi 5 (hostname piDiMarco, user marco), NOT on the Pi Zero.
#
#  Usage:
#    ./build-spotifyd.sh                     # build and copy to Pi Zero
#    ./build-spotifyd.sh --build-only        # build, do not deploy
#    PI_ZERO_HOST=192.168.1.155 ./build-spotifyd.sh
#
#  Prerequisites (installed automatically if missing):
#    - Rust + cargo   (via rustup)
#    - gcc-arm-linux-gnueabihf  (apt)
#    - pkg-config, libasound2-dev, libdbus-1-dev  (apt)
#
#  Output:
#    ./spotifyd-armv7  (local copy of the compiled binary)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SPOTIFYD_VERSION="${SPOTIFYD_VERSION:-0.3.5}"
TARGET="armv7-unknown-linux-gnueabihf"
FEATURES="alsa_backend,dbus_mpris"
OUTPUT_BINARY="./spotifyd-armv7"

PI_ZERO_USER="${PI_ZERO_USER:-radiosveglia}"
PI_ZERO_HOST="${PI_ZERO_HOST:-radiosveglia.local}"
DEPLOY_PATH="/usr/local/bin/spotifyd"

BUILD_ONLY=false
if [[ "${1:-}" == "--build-only" ]]; then
    BUILD_ONLY=true
fi

step() { printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
ok()   { printf "\033[1;32m    ok\033[0m\n"; }

# ---------------------------------------------------------------------------
# 1. Install build dependencies
# ---------------------------------------------------------------------------
step "Checking build dependencies ..."

if ! command -v cargo &>/dev/null; then
    echo "Rust/cargo not found. Installing via rustup ..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
    # shellcheck source=/dev/null
    source "${HOME}/.cargo/env"
fi
ok

step "Installing cross-compiler and dev libraries ..."
sudo apt-get update -qq
sudo apt-get install -y \
    gcc-arm-linux-gnueabihf \
    pkg-config \
    libasound2-dev \
    libdbus-1-dev
ok

# ---------------------------------------------------------------------------
# 2. Add the armv7 Rust target
# ---------------------------------------------------------------------------
step "Adding Rust target ${TARGET} ..."
rustup target add "${TARGET}"
ok

# ---------------------------------------------------------------------------
# 3. Configure the linker for the target
# ---------------------------------------------------------------------------
step "Configuring cargo linker for ${TARGET} ..."
CARGO_CONFIG="${HOME}/.cargo/config.toml"
LINKER_ENTRY="[target.${TARGET}]
linker = \"arm-linux-gnueabihf-gcc\""

if ! grep -q "${TARGET}" "${CARGO_CONFIG}" 2>/dev/null; then
    mkdir -p "$(dirname "${CARGO_CONFIG}")"
    printf "\n%s\n" "${LINKER_ENTRY}" >> "${CARGO_CONFIG}"
    echo "    Added linker config to ${CARGO_CONFIG}"
else
    echo "    Linker config already present."
fi
ok

# ---------------------------------------------------------------------------
# 4. Clone or update spotifyd source
# ---------------------------------------------------------------------------
SPOTIFYD_SRC_DIR="${HOME}/spotifyd-src"

step "Fetching spotifyd v${SPOTIFYD_VERSION} source ..."
if [[ -d "${SPOTIFYD_SRC_DIR}" ]]; then
    cd "${SPOTIFYD_SRC_DIR}"
    git fetch --tags
else
    git clone https://github.com/Spotifyd/spotifyd.git "${SPOTIFYD_SRC_DIR}"
    cd "${SPOTIFYD_SRC_DIR}"
fi
git checkout "v${SPOTIFYD_VERSION}"
ok

# ---------------------------------------------------------------------------
# 5. Build
# ---------------------------------------------------------------------------
step "Building spotifyd for ${TARGET} (features: ${FEATURES}) ..."
echo "    This takes ~10-15 minutes on a Pi 5."
echo ""

PKG_CONFIG_ALLOW_CROSS=1 \
PKG_CONFIG_PATH=/usr/lib/arm-linux-gnueabihf/pkgconfig \
cargo build \
    --release \
    --target "${TARGET}" \
    --no-default-features \
    --features "${FEATURES}"

BUILT_BINARY="${SPOTIFYD_SRC_DIR}/target/${TARGET}/release/spotifyd"
if [[ ! -f "${BUILT_BINARY}" ]]; then
    echo "ERROR: Expected binary not found at ${BUILT_BINARY}" >&2
    exit 1
fi

cp "${BUILT_BINARY}" "${OUTPUT_BINARY}"
ls -lh "${OUTPUT_BINARY}"
file "${OUTPUT_BINARY}"
ok

# ---------------------------------------------------------------------------
# 6. Deploy to Pi Zero (optional)
# ---------------------------------------------------------------------------
if "${BUILD_ONLY}"; then
    echo ""
    echo "Binary ready at: ${OUTPUT_BINARY}"
    echo "Deploy manually:"
    echo "  scp ${OUTPUT_BINARY} ${PI_ZERO_USER}@${PI_ZERO_HOST}:${DEPLOY_PATH}"
    exit 0
fi

step "Deploying to ${PI_ZERO_USER}@${PI_ZERO_HOST}:${DEPLOY_PATH} ..."
scp "${OUTPUT_BINARY}" "${PI_ZERO_USER}@${PI_ZERO_HOST}:/tmp/spotifyd-new"
ssh "${PI_ZERO_USER}@${PI_ZERO_HOST}" "
    sudo install -m 755 /tmp/spotifyd-new ${DEPLOY_PATH}
    rm /tmp/spotifyd-new
    ${DEPLOY_PATH} --version
    systemctl --user restart spotifyd.service || true
"
ok

echo ""
echo "spotifyd v${SPOTIFYD_VERSION} deployed to ${PI_ZERO_HOST}."
