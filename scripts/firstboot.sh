#!/usr/bin/env bash
# =============================================================================
#  Radiosveglia_nSp -- firstboot.sh
# =============================================================================
#
#  One-shot system-level script run by radiosveglia-firstboot.service on the
#  very first boot after flashing the SD card.
#
#  Responsibilities:
#    1. Wait for network (spotifyd download depends on it).
#    2. Enable loginctl linger for the 'radiosveglia' user so that user
#       systemd services start at boot without a login session.
#    3. Enable and start the spotifyd-bootstrap user service (which downloads
#       the spotifyd binary).
#    4. Enable the radiosveglia-config user service (which regenerates
#       alarm.timer from radiosveglia.conf on every boot).
#    5. Enable the alarm.timer user service.
#
#  This script runs as root (via systemd).
#  It does NOT touch secrets, tokens, or Wi-Fi credentials.
# =============================================================================

set -euo pipefail

RADIOSVEGLIA_USER="radiosveglia"
RADIOSVEGLIA_UID="$(id -u "${RADIOSVEGLIA_USER}")"
RADIOSVEGLIA_HOME="$(eval echo "~${RADIOSVEGLIA_USER}")"
SCRIPTS_SRC="/opt/radiosveglia/scripts"
SYSTEMD_USER_SRC="/opt/radiosveglia/systemd"

log()  { echo "[firstboot] $*"; }
fail() { echo "[firstboot] ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Helper: run a command as the radiosveglia user
# ---------------------------------------------------------------------------
as_user() {
    sudo -u "${RADIOSVEGLIA_USER}" \
        XDG_RUNTIME_DIR="/run/user/${RADIOSVEGLIA_UID}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${RADIOSVEGLIA_UID}/bus" \
        "$@"
}

# ---------------------------------------------------------------------------
# 1. Sanity: make sure the user exists
# ---------------------------------------------------------------------------
id "${RADIOSVEGLIA_USER}" &>/dev/null || \
    fail "User '${RADIOSVEGLIA_USER}' not found. Did you use the correct username in Raspberry Pi Imager?"

log "Running first-boot setup for user '${RADIOSVEGLIA_USER}' (UID ${RADIOSVEGLIA_UID}) ..."

# ---------------------------------------------------------------------------
# 2. Copy scripts and systemd units from /opt/radiosveglia into the user's home
# ---------------------------------------------------------------------------
log "Installing scripts to ${RADIOSVEGLIA_HOME}/scripts/ ..."
sudo -u "${RADIOSVEGLIA_USER}" mkdir -p "${RADIOSVEGLIA_HOME}/scripts"
cp -v "${SCRIPTS_SRC}/apply-config.sh"       "${RADIOSVEGLIA_HOME}/scripts/"
cp -v "${SCRIPTS_SRC}/spotifyd-bootstrap.sh" "${RADIOSVEGLIA_HOME}/scripts/"
chmod +x "${RADIOSVEGLIA_HOME}/scripts/"*.sh
chown -R "${RADIOSVEGLIA_USER}:${RADIOSVEGLIA_USER}" "${RADIOSVEGLIA_HOME}/scripts"

log "Installing alarm code to ${RADIOSVEGLIA_HOME}/alarm/ ..."
sudo -u "${RADIOSVEGLIA_USER}" mkdir -p "${RADIOSVEGLIA_HOME}/alarm"
cp -vn "${SCRIPTS_SRC}/../alarm/"*.py "${RADIOSVEGLIA_HOME}/alarm/" 2>/dev/null || true

# Bundled wake-up sounds played locally before the podcast starts.
if [ -d "${SCRIPTS_SRC}/../alarm/alarm_sounds" ]; then
    cp -rvn "${SCRIPTS_SRC}/../alarm/alarm_sounds" \
        "${RADIOSVEGLIA_HOME}/alarm/" 2>/dev/null || true
fi
chown -R "${RADIOSVEGLIA_USER}:${RADIOSVEGLIA_USER}" "${RADIOSVEGLIA_HOME}/alarm"

log "Installing systemd user units ..."
sudo -u "${RADIOSVEGLIA_USER}" mkdir -p "${RADIOSVEGLIA_HOME}/.config/systemd/user"
cp -v "${SYSTEMD_USER_SRC}/spotifyd.service"            "${RADIOSVEGLIA_HOME}/.config/systemd/user/"
cp -v "${SYSTEMD_USER_SRC}/spotifyd-bootstrap.service"  "${RADIOSVEGLIA_HOME}/.config/systemd/user/"
cp -v "${SYSTEMD_USER_SRC}/alarm.service"               "${RADIOSVEGLIA_HOME}/.config/systemd/user/"
cp -v "${SYSTEMD_USER_SRC}/radiosveglia-config.service" "${RADIOSVEGLIA_HOME}/.config/systemd/user/"
chown -R "${RADIOSVEGLIA_USER}:${RADIOSVEGLIA_USER}" \
    "${RADIOSVEGLIA_HOME}/.config/systemd"

# ---------------------------------------------------------------------------
# 3. Enable linger so user services start at boot without an interactive login
# ---------------------------------------------------------------------------
log "Enabling linger for '${RADIOSVEGLIA_USER}' ..."
loginctl enable-linger "${RADIOSVEGLIA_USER}"

# ---------------------------------------------------------------------------
# 4. Start the user systemd session if not already running
# ---------------------------------------------------------------------------
# On first boot the session bus may not be up yet. Give it a moment.
log "Waiting for user session bus ..."
for i in $(seq 1 20); do
    if [ -S "/run/user/${RADIOSVEGLIA_UID}/bus" ]; then
        break
    fi
    sleep 1
done

if [ ! -S "/run/user/${RADIOSVEGLIA_UID}/bus" ]; then
    log "Session bus not available; reloading after reboot will pick up the units."
    # Units are already in place; they will be picked up on the next boot.
    exit 0
fi

# ---------------------------------------------------------------------------
# 5. Reload systemd user daemon and enable units
# ---------------------------------------------------------------------------
log "Enabling user services ..."
as_user systemctl --user daemon-reload

as_user systemctl --user enable spotifyd-bootstrap.service
as_user systemctl --user enable radiosveglia-config.service
as_user systemctl --user enable spotifyd.service
as_user systemctl --user enable alarm.timer

# ---------------------------------------------------------------------------
# 6. Start spotifyd-bootstrap immediately (downloads spotifyd)
# ---------------------------------------------------------------------------
log "Starting spotifyd-bootstrap (downloading spotifyd binary) ..."
as_user systemctl --user start spotifyd-bootstrap.service || \
    log "spotifyd-bootstrap failed -- will retry on next boot."

# ---------------------------------------------------------------------------
# 7. Configure spotifyd directory and audio
# ---------------------------------------------------------------------------

# mpg123 plays the local wake-up sound before the podcast. Small, optional:
# if the install fails, alarm.py logs a warning and skips the sound.
if ! command -v mpg123 >/dev/null 2>&1; then
    log "Installing mpg123 (local wake-up sound player) ..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y mpg123 \
        || log "mpg123 install failed -- wake-up sound will be skipped."
fi

sudo -u "${RADIOSVEGLIA_USER}" mkdir -p "${RADIOSVEGLIA_HOME}/.config/spotifyd"

if [ ! -f "${RADIOSVEGLIA_HOME}/.config/spotifyd/spotifyd.conf" ]; then
    cp -v "${SCRIPTS_SRC}/../spotifyd/spotifyd.conf" \
        "${RADIOSVEGLIA_HOME}/.config/spotifyd/spotifyd.conf" 2>/dev/null || \
        log "spotifyd.conf not found in /opt/radiosveglia -- user must configure manually."
    chown "${RADIOSVEGLIA_USER}:${RADIOSVEGLIA_USER}" \
        "${RADIOSVEGLIA_HOME}/.config/spotifyd/spotifyd.conf" 2>/dev/null || true
fi

# Install .asoundrc (ALSA softvol routing for hifiberry-dac / MAX98357A).
# Only written if not already present, so manual customisations are preserved.
if [ ! -f "${RADIOSVEGLIA_HOME}/.asoundrc" ]; then
    cp -v "${SCRIPTS_SRC}/../spotifyd/asoundrc" \
        "${RADIOSVEGLIA_HOME}/.asoundrc" 2>/dev/null || \
        log "asoundrc not found in /opt/radiosveglia -- ALSA routing not configured."
    chown "${RADIOSVEGLIA_USER}:${RADIOSVEGLIA_USER}" \
        "${RADIOSVEGLIA_HOME}/.asoundrc" 2>/dev/null || true
fi

log "First-boot setup complete."
log "Reboot the Pi to start all services cleanly:"
log "  sudo reboot"
