# Architecture

This document describes the internal structure of Radiosveglia_nSp: the
components, how they fit together, and what each one is responsible for.

For instructions on modifying the code, see [DEVELOPMENT.md](../DEVELOPMENT.md).
For end-user setup, see [README.md](../README.md) and [user-guide.md](user-guide.md).

---

## High-level overview

```
                                       Spotify Web API
                                              ^
                                              |  (OAuth, fetch episodes,
                                              |   transfer playback)
                                              |
   /boot/firmware/radiosveglia.conf           |
              |                               |
              v                               |
   apply-config.sh  --writes-->  ~/.config/systemd/user/alarm.timer
                                              |
                                              | OnCalendar fires
                                              v
                                       alarm.service
                                              |
                                              v
                                         alarm.py  ----> Spotify Web API
                                              |
                                              | transfers playback to
                                              v
                                       spotifyd  --ALSA-->  MAX98357A  -->  Speakers
                                              ^
                                              |  Spotify Connect
                                              |  (also reachable from phones
                                              |   during the day)
                                       Spotify clients on LAN
```

Three independent things run on the Pi at any moment:

- **spotifyd** (long-running) — advertises a Spotify Connect device and
  plays whatever audio is sent to it.
- **alarm.timer** (idle) — a systemd user timer that fires `alarm.service`
  at the scheduled wake times.
- **alarm.service** (one-shot) — runs `alarm.py`, which finds the latest
  podcast episode and tells Spotify to play it on the `spotifyd` device.

There is no central daemon, no database, no web server.

---

## Boot sequence

When the Pi powers on, the following services run in order. Each step
either completes once and stays done, or stays running until shutdown.

| Order | Service | Type | Runs as | Purpose |
|-------|---------|------|---------|---------|
| 1 | `radiosveglia-firstboot.service` | system, one-shot | root | First boot only: copy scripts and unit files into `~radiosveglia/`, enable user linger, enable user services. Creates `/var/lib/radiosveglia/firstboot-done` so it does not run again. |
| 2 | `spotifyd-bootstrap.service` | user, one-shot | radiosveglia | Downloads the spotifyd `-slim` binary to `/usr/local/bin/spotifyd` if missing. |
| 3 | `radiosveglia-config.service` | user, one-shot | radiosveglia | Runs `apply-config.sh`. Reads `/boot/firmware/radiosveglia.conf` and writes `~/.config/systemd/user/alarm.timer` with one `OnCalendar=` per active day. |
| 4 | `spotifyd.service` | user, persistent | radiosveglia | Runs `spotifyd --no-daemon`. Restarts on failure with a 5 s delay. |
| 5 | `alarm.timer` | user | radiosveglia | Idle until the next scheduled wake time. |

After boot, only `spotifyd.service` is actually running. Everything else is
either done or waiting for a timer.

---

## Components

### `alarm/` (Python, runs on the Pi)

- **`alarm.py`** — Entry point invoked by `alarm.service`. Refreshes the
  Spotify token, finds the latest episode of the configured podcast,
  transfers playback to the `Radiosveglia` Connect device, and ramps the
  volume up from a low value to the configured target ("fade-in" — softens
  the MAX98357A click on startup).
- **`spotify_client.py`** — OAuth flow (first-time authorization on a
  laptop, refresh-token thereafter), wrapper around the Spotify Web API
  calls used by `alarm.py`.
- **`radiosveglia_config.py`** — Parses `/boot/firmware/radiosveglia.conf`
  (INI format). Used by `alarm.py` for `show_id`, `market`, `volume`, and
  `device_name`; used by `apply-config.sh` (indirectly) for the schedule.

### `boot-overlay/` (lives in `/boot/firmware/`)

- **`radiosveglia.conf`** — User-editable. The only file an end user
  normally touches after flashing. Visible from Windows/macOS as soon as
  the SD card is inserted.
- **`README-FIRST.txt`** — Friendly hello shown on the boot partition.

### `scripts/` (Bash, runs on the Pi)

- **`firstboot.sh`** — Idempotent first-boot bootstrap. Copies project
  files into `~radiosveglia/`, enables linger so the user session survives
  logout, enables user services. Username is hardcoded as `radiosveglia`
  at the top of the script.
- **`apply-config.sh`** — Translates `radiosveglia.conf` into
  `alarm.timer`. Writes one `OnCalendar=` line per active day. Skips blank
  days. Re-runs on every boot, so editing the config and rebooting is
  enough to update the schedule.
- **`spotifyd-bootstrap.sh`** — Downloads the spotifyd slim binary from
  GitHub releases the first time. Verified against an expected SHA before
  installing to `/usr/local/bin/`.

### `spotifyd/` (config files for spotifyd)

- **`spotifyd.conf`** — Device name, ALSA backend, softvol controller,
  bitrate. Copied to `~/.config/spotifyd/spotifyd.conf` at first boot.
- **`asoundrc`** — ALSA configuration that exposes a `softvol` PCM in
  front of the `sndrpihifiberry` device. Copied to `~/.asoundrc`.

### `systemd/` (unit files)

User-mode units (no root, follow the user session):
`spotifyd.service`, `alarm.service`, `alarm.timer.template`,
`radiosveglia-config.service`, `spotifyd-bootstrap.service`.

System-mode units (run as root, one time):
`radiosveglia-firstboot.service`.

### `tools/` (utilities, run elsewhere)

- **`setup-spotify.py`** — Runs on the user's PC. One-time OAuth flow that
  produces `spotify_token.json`, which is then copied to the Pi.
- **`build-spotifyd.sh`** — Cross-compiles spotifyd for `armv7` on a Pi 5
  with features `alsa_backend,dbus_mpris`. Produces a statically linked
  binary equivalent to the official `-slim` release.
- **`build-image.sh`** — Clones a configured Pi Zero SD card into a
  `.img.xz` ready for distribution. Strips secrets, SSH host keys, logs,
  the spotifyd binary, and the first-boot sentinel.

---

## What happens when the alarm fires

1. `alarm.timer` triggers `alarm.service` at the configured `OnCalendar`
   time. systemd handles missed firings (e.g. the Pi was off) according
   to `Persistent=true` semantics — it does not fire late on resume.
2. `alarm.service` runs `alarm.py` as the `radiosveglia` user.
3. `alarm.py` loads `spotify_token.json`. If the access token is expired
   it uses the refresh token to mint a new one and rewrites the file.
4. It queries the Spotify Web API for the most recent episode of
   `show_id`, filtered by `market`.
5. It looks for an available Spotify Connect device named `Radiosveglia`.
   If `spotifyd` has not registered yet (can take 10–30 s after boot),
   it retries for up to 30 s.
6. It calls `PUT /me/player` to transfer playback to that device, then
   `PUT /me/player/play` with the episode URI.
7. It sets the softvol volume to a low value, then ramps it up over a few
   seconds to the configured `volume`.

If any step fails, `alarm.py` exits non-zero. The failure is visible in
`journalctl --user -u alarm.service`.

---

## Design decisions worth knowing

**Config lives on the boot partition.** End users edit
`radiosveglia.conf` from Windows or macOS without ever opening a terminal.
SSH is only needed for the one-time Spotify setup and for debugging.

**spotifyd `-slim`, not `-default`.** Debian Trixie ships OpenSSL 3.x. The
official `-default` spotifyd binary is linked against `libssl.so.1.1`
(OpenSSL 1.1.x) which Trixie does not provide. The `-slim` binary is
statically linked and has no external `libssl` dependency. See spotifyd
issue #1389.

**User systemd, not system.** All services that the project owns run as
the `radiosveglia` user, with linger enabled. This avoids running Python
and Spotify network code as root. Only `firstboot.sh` runs as root, and
only once.

**Timer regenerated on every boot.** `apply-config.sh` rewrites
`alarm.timer` unconditionally. This means editing `radiosveglia.conf` and
rebooting is sufficient to change the schedule — no manual `systemctl
daemon-reload` required.

**Token refresh in the alarm process.** Spotify access tokens are valid
for one hour. Rather than running a separate refresher daemon, `alarm.py`
refreshes the token at the start of every alarm. The refresh token does
not expire (until the user revokes the app).

**Volume fade-in instead of GPIO-controlled SD pin.** The MAX98357A has
an SD (shutdown) pad that, if pulled high only after audio starts, would
eliminate the startup click entirely. Implementing that requires GPIO
control and additional wiring. The fade-in is a software-only workaround
that reduces the click without hardware changes.
