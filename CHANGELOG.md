# Changelog

All notable changes to this project will be documented here.

---

## [Unreleased]

### Added

- Local wake-up sound: a random ambient clip from `alarm/alarm_sounds/`
  plays on the Pi for 60 s before the podcast, with the volume fading from
  1 up to the configured level. Uses `mpg123` (installed at first boot) and
  the ALSA softvol `Master` control; degrades gracefully if unavailable.

### Fixed

- `apply-config.sh` now installs `~/.asoundrc` if it's missing (idempotent,
  runs every boot). It was previously only written once by
  `radiosveglia-firstboot.service`, so devices provisioned before that unit
  existed — or updated by hand — never got it, silently breaking the
  wake-up-sound volume fade (the `Master` softvol control it depends on
  doesn't exist without it).
- `alarm.py` now logs a warning when `amixer` exits with a non-zero status,
  instead of swallowing the failure entirely.

---

## [0.1.0] - 2026-05-20

First public release.

### What's included

- Automated daily alarm via systemd timer, configurable per day of the week
- Latest podcast episode fetched from Spotify Web API at alarm time
- Volume fade-in to reduce MAX98357A amplifier click on startup
- Spotify Connect support — the device doubles as a Wi-Fi speaker during
  the day
- User configuration via `radiosveglia.conf` on the boot partition
  (editable from Windows/macOS without SSH)
- `setup-spotify.py` for one-time OAuth authorization on any computer
- `spotifyd-bootstrap.sh` downloads the correct slim binary at first boot
- `apply-config.sh` regenerates `alarm.timer` from config on every boot
- Fully headless operation on Raspberry Pi Zero 2 W, Debian Trixie 32-bit

### Hardware support

- Raspberry Pi Zero 2 W
- Adafruit MAX98357A I2S amplifier (hifiberry-dac ALSA overlay)
- Any 4 ohm passive speakers (tested with Visaton FR 10)
