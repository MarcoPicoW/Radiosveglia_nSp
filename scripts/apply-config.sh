#!/usr/bin/env bash
# =============================================================================
#  Radiosveglia_nSp — apply-config.sh
# =============================================================================
#
#  Reads /boot/firmware/radiosveglia.conf and regenerates
#  ~/.config/systemd/user/alarm.timer with one OnCalendar= line per active day.
#
#  Run automatically at every boot by radiosveglia-config.service (a oneshot
#  user unit). Can also be run manually after editing the config:
#
#    /home/radiosveglia/scripts/apply-config.sh
#    systemctl --user daemon-reload
#    systemctl --user restart alarm.timer
#
#  Failure modes:
#    - missing config         → uses defaults (06:30 every day)
#    - malformed line         → that day is skipped, warning to stderr
#    - no valid days at all   → falls back to a single OnCalendar=06:30 daily
#
#  Also ensures ~/.asoundrc exists (idempotent, every boot). It's normally
#  installed once by radiosveglia-firstboot.service, but that unit only ever
#  runs on a device's very first boot — devices provisioned before it existed,
#  or updated by hand, can be missing it. Without it the "Master" softvol
#  control alarm.py uses for the wake-up-sound volume fade doesn't exist.
# =============================================================================

set -euo pipefail

CONFIG_FILE="${RADIOSVEGLIA_CONFIG:-/boot/firmware/radiosveglia.conf}"
TIMER_FILE="${HOME}/.config/systemd/user/alarm.timer"
TIMER_DIR="$(dirname "${TIMER_FILE}")"
ASOUNDRC_FILE="${HOME}/.asoundrc"

# Ordered list — systemd is fine with any order, but humans prefer Mon→Sun
DAYS=(monday tuesday wednesday thursday friday saturday sunday)

# Map day name → systemd-readable abbreviation
declare -A DAY_ABBREV=(
  [monday]=Mon  [tuesday]=Tue  [wednesday]=Wed
  [thursday]=Thu [friday]=Fri  [saturday]=Sat  [sunday]=Sun
)

mkdir -p "${TIMER_DIR}"

# -----------------------------------------------------------------------------
# Write ~/.asoundrc if it isn't already there. Never overwrites an existing
# file, so manual customisations survive.
# -----------------------------------------------------------------------------
ensure_asoundrc() {
  if [[ -f "${ASOUNDRC_FILE}" ]]; then
    return 0
  fi

  echo "~/.asoundrc missing — installing default (hifiberry-dac softvol routing)"
  cat > "${ASOUNDRC_FILE}" <<'EOF'
# ~/.asoundrc for Radiosveglia
#
# Routes all audio to the hifiberry-dac (MAX98357A) with a software
# volume control (softvol), since the MAX98357A has no hardware mixer.
#
# The MAX98357A is mono. The "plug" plugin handles stereo-to-mono
# downmix automatically when needed.

pcm.!default {
    type plug
    slave.pcm "softvol"
}

pcm.softvol {
    type softvol
    slave.pcm "plughw:CARD=sndrpihifiberry,DEV=0"
    control {
        name "Master"
        card "sndrpihifiberry"
    }
    min_dB -50.0
    max_dB 0.0
    resolution 100
}

ctl.!default {
    type hw
    card "sndrpihifiberry"
}
EOF
}

ensure_asoundrc

# -----------------------------------------------------------------------------
# Read raw value for a given key under [alarm], stripping inline comments and
# whitespace. Returns empty string if missing/blank.
# -----------------------------------------------------------------------------
read_alarm_value() {
  local key="$1"
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    return 0
  fi
  awk -v key="${key}" '
    /^\[/ { section = $0; next }
    section == "[alarm]" {
      # split on = (only the first occurrence)
      idx = index($0, "=")
      if (idx == 0) next
      k = $0; sub(/=.*/, "", k); gsub(/[ \t]+/, "", k)
      if (k != key) next
      v = substr($0, idx + 1)
      sub(/#.*/, "", v)             # strip inline comment
      sub(/^[ \t]+/, "", v)         # left trim
      sub(/[ \t]+$/, "", v)         # right trim
      print v
      exit
    }
  ' "${CONFIG_FILE}"
}

# -----------------------------------------------------------------------------
# Validate HH:MM (24-hour). Returns 0 if valid, 1 otherwise.
# -----------------------------------------------------------------------------
is_valid_time() {
  [[ "$1" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]
}

# -----------------------------------------------------------------------------
# Build the body of the new timer file
# -----------------------------------------------------------------------------
build_timer_content() {
  local oncalendar_lines=""
  local active_count=0

  for day in "${DAYS[@]}"; do
    local raw
    raw="$(read_alarm_value "${day}")"

    # Empty (or commented out, which yields empty here) → skip this day
    if [[ -z "${raw}" ]]; then
      continue
    fi

    if ! is_valid_time "${raw}"; then
      echo "WARNING: invalid time '${raw}' for ${day} — skipping" >&2
      continue
    fi

    local abbrev="${DAY_ABBREV[${day}]}"
    oncalendar_lines+="OnCalendar=${abbrev} *-*-* ${raw}:00"$'\n'
    active_count=$((active_count + 1))
  done

  # Fallback: nothing valid → single safe default
  if (( active_count == 0 )); then
    echo "WARNING: no valid alarm days configured — using default 06:30 daily" >&2
    oncalendar_lines="OnCalendar=*-*-* 06:30:00"$'\n'
  fi

  cat <<EOF
# Auto-generated by apply-config.sh — do not edit by hand.
# Edit /boot/firmware/radiosveglia.conf instead, then reboot or run:
#   ~/scripts/apply-config.sh && systemctl --user daemon-reload \\
#     && systemctl --user restart alarm.timer

[Unit]
Description=Radiosveglia daily alarm

[Timer]
${oncalendar_lines}Persistent=true
Unit=alarm.service

[Install]
WantedBy=timers.target
EOF
}

# -----------------------------------------------------------------------------
# Atomic write: build into a tmp file, then mv. Avoids half-written timers.
# Also: only rewrite if content actually changed (avoids spurious daemon-reload).
# -----------------------------------------------------------------------------
new_content="$(build_timer_content)"

if [[ -f "${TIMER_FILE}" ]] && \
   diff -q <(printf '%s' "${new_content}") "${TIMER_FILE}" >/dev/null 2>&1; then
  echo "alarm.timer is already up to date — no change."
  exit 0
fi

tmp_file="$(mktemp "${TIMER_FILE}.XXXXXX")"
printf '%s' "${new_content}" > "${tmp_file}"
mv "${tmp_file}" "${TIMER_FILE}"

echo "alarm.timer regenerated:"
echo "---"
grep -E '^OnCalendar=' "${TIMER_FILE}" || true
echo "---"
echo "Run 'systemctl --user daemon-reload && systemctl --user restart alarm.timer' to apply."
