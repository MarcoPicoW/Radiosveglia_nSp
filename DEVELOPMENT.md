# Development Guide

This document is for people who want to modify the code, build a custom
image, or understand how the project works internally.

---

## Repository layout

```
.
├── alarm/                        -- Python code that runs on the Pi Zero
│   ├── alarm.py                  -- Main alarm script (run by systemd)
│   ├── spotify_client.py         -- Spotify OAuth + token refresh
│   ├── radiosveglia_config.py    -- Reads /boot/firmware/radiosveglia.conf
│   └── spotify.env.example       -- Credentials template (never commit the real file)
│
├── boot-overlay/                 -- Files that go in /boot/firmware/ on the image
│   ├── radiosveglia.conf         -- User-editable alarm schedule and settings
│   └── README-FIRST.txt          -- Visible to Windows/macOS when SD is inserted
│
├── docs/
│   ├── user-guide.md             -- Extended user documentation
│   ├── architecture.md           -- System architecture overview
│   ├── CrossCompiling - Debian Wiki.pdf
│   └── Spotifyd.pdf
│
├── scripts/                      -- Shell scripts that live on the Pi Zero
│   ├── apply-config.sh           -- Reads radiosveglia.conf, regenerates alarm.timer
│   ├── firstboot.sh              -- One-shot bootstrap at first boot (runs as root)
│   └── spotifyd-bootstrap.sh     -- Downloads the spotifyd slim binary
│
├── systemd/                      -- systemd unit files
│   ├── spotifyd.service          -- User service: runs spotifyd daemon
│   ├── alarm.service             -- User service: runs alarm.py
│   ├── alarm.timer.template      -- Template; apply-config.sh writes the real file
│   ├── radiosveglia-config.service -- User service: runs apply-config.sh at boot
│   ├── spotifyd-bootstrap.service  -- User service: runs spotifyd-bootstrap.sh
│   └── radiosveglia-firstboot.service -- System service: runs firstboot.sh once
│
└── tools/                        -- Utilities for maintainers and end users
    ├── setup-spotify.py           -- Run on a PC to do the OAuth flow
    ├── build-spotifyd.sh          -- Cross-compile spotifyd on the Pi 5 for armv7
    └── build-image.sh             -- Clone a configured Pi Zero SD to .img.xz
```

---

## How the system works

At boot the following happens in order:

1. `radiosveglia-firstboot.service` (system, one-shot) — runs only if
   `/var/lib/radiosveglia/firstboot-done` does not exist. Copies scripts
   and units into the user's home, enables linger, enables user services.

2. `spotifyd-bootstrap.service` (user, one-shot) — downloads the spotifyd
   `-slim` binary to `/usr/local/bin/spotifyd` if it is not already present.

3. `radiosveglia-config.service` (user, one-shot) — runs `apply-config.sh`,
   which reads `/boot/firmware/radiosveglia.conf` and writes
   `~/.config/systemd/user/alarm.timer` with one `OnCalendar=` line per
   active day.

4. `spotifyd.service` (user, persistent) — runs `spotifyd --no-daemon`.
   Restarts automatically on failure with a 5 s delay.

5. `alarm.timer` (user) — fires `alarm.service` at the configured times.

6. `alarm.service` (user, one-shot) — runs `alarm.py`, which refreshes the
   Spotify token, finds the latest podcast episode, transfers playback to the
   Radiosveglia Connect device, and starts playback with a volume fade-in.

---

## Development setup

You do not need a Pi Zero to work on the Python code. The Spotify API calls
work from any machine with network access.

```bash
git clone https://github.com/USER/Radiosveglia_nSp.git
cd Radiosveglia_nSp/alarm

# Create a virtual environment
python3 -m venv .venv
source .venv/bin/activate
pip install requests python-dotenv

# Copy and fill in the credentials template
cp spotify.env.example spotify.env
# Edit spotify.env with your CLIENT_ID, CLIENT_SECRET, REDIRECT_URI

# Run the one-time OAuth flow (opens a browser)
python3 -c "
import spotify_client as sc
sc.get_access_token_first_time_with_browser()
print('Token saved.')
"

# Test the alarm (plays on whatever Spotify Connect device is active)
python3 alarm.py
```

To test against the Pi Zero specifically, set the device name in
`/boot/firmware/radiosveglia.conf` (or mock it by editing `alarm.py`
temporarily).

---

## Changing the username

The default username is `radiosveglia`. If you change it, you must update
the following:

- All `%h` references in the systemd unit files expand to the home directory
  at runtime, so those are fine.
- `scripts/firstboot.sh` has `RADIOSVEGLIA_USER="radiosveglia"` hardcoded at
  the top. Change it there.
- `tools/build-image.sh` does not hardcode the username; it uses the path
  from the mounted filesystem.
- The README tells users to keep the username as `radiosveglia`. Update it
  if you change the default.

---

## Building the spotifyd binary

The image ships without a spotifyd binary. It is downloaded at first boot by
`spotifyd-bootstrap.sh`. If you want to include it in the image or produce a
custom build with different features, use `tools/build-spotifyd.sh` on the
Pi 5:

```bash
# On piDiMarco (Pi 5, user marco):
cd Radiosveglia_nSp
./tools/build-spotifyd.sh --build-only
# Produces: ./spotifyd-armv7
```

The script compiles for `armv7-unknown-linux-gnueabihf` with features
`alsa_backend,dbus_mpris`. The result is statically linked (equivalent to the
official `-slim` release) and has no dependency on `libssl`.

To deploy directly to the Pi Zero after building:

```bash
PI_ZERO_HOST=192.168.1.155 ./tools/build-spotifyd.sh
```

### Why the slim binary is required

Debian Trixie ships with OpenSSL 3.x. The official spotifyd precompiled
`-default` binary is linked against `libssl.so.1.1` (OpenSSL 1.1.x), which
does not exist on Trixie. Using the `-slim` binary (statically linked, no
external OpenSSL dependency) avoids this entirely. See spotifyd issue #1389.

---

## Building a release image

Prerequisites: Pi 5 with the Pi Zero's SD card inserted, `xz-utils` and
`pv` installed.

```bash
# 1. Prepare the Pi Zero SD to a known-good state:
#    - all services running
#    - alarm tested manually
#    - no personal spotify_token.json present

# 2. Shut down the Pi Zero cleanly
ssh radiosveglia@radiosveglia.local "sudo shutdown now"

# 3. Remove the SD and insert it in the Pi 5

# 4. On the Pi 5, identify the device
lsblk   # look for a ~8 or 16 GB device, e.g. /dev/sda

# 5. Run the build script
cd Radiosveglia_nSp
sudo ./tools/build-image.sh /dev/sda 1.0
# Produces: radiosveglia-v1.0.img.xz and radiosveglia-v1.0.img.xz.sha256
```

The script automatically removes secrets, SSH host keys, logs, the spotifyd
binary, and the first-boot sentinel before cloning. The resulting image is
safe to distribute.

### Creating a GitHub release

1. Build the image as above.
2. Build the spotifyd binary: `./tools/build-spotifyd.sh --build-only`.
3. Create a new tag and release on GitHub.
4. Attach these files to the release:
   - `radiosveglia-vX.Y.img.xz`
   - `radiosveglia-vX.Y.img.xz.sha256`
   - `tools/setup-spotify.py`
   - `spotifyd-armv7` (optional but useful for manual installs)
5. Update `CHANGELOG.md`.

---

## Running the tests

There are currently no automated tests. Manual verification checklist:

```bash
ssh radiosveglia@radiosveglia.local

# Audio subsystem
aplay -l                               # must show sndrpihifiberry
speaker-test -c 2 -t sine -l 1        # audible sine wave from speakers

# spotifyd
spotifyd --version                     # must print a version number
systemctl --user status spotifyd       # must be active (running)

# Alarm
systemctl --user start alarm.service   # triggers immediate playback
journalctl --user -u alarm.service -n 30

# Timer
systemctl --user list-timers | grep alarm  # next fire time visible

# Config regeneration
~/scripts/apply-config.sh
cat ~/.config/systemd/user/alarm.timer     # OnCalendar lines match config

# Reboot survival
sudo reboot
# after ~90 s:
systemctl --user status spotifyd
systemctl --user list-timers | grep alarm
```

---

## Known issues and limitations

**spotifyd may take 10-30 s after boot to appear in Spotify Connect.**
`alarm.py` retries device discovery for up to 30 s, so scheduled alarms are
not affected. Manual testing immediately after boot may show "device not
found" — wait and retry.

**The amplifier click at startup** is a hardware characteristic of the
MAX98357A. The volume fade-in in `alarm.py` reduces it but does not eliminate
it. A proper fix requires controlling the SD pin via GPIO.

**Single account only.** The OAuth token is for one Spotify account. If you
want to use a different account, re-run `setup-spotify.py` and replace the
token file.

**The username is hardcoded in `firstboot.sh`.** See "Changing the username"
above.

---

## Contributing

Pull requests are welcome. Please:

- Keep changes to individual files focused and minimal.
- Test on actual hardware before opening a PR.
- Update `CHANGELOG.md` with a brief description of the change.
- Do not commit `spotify.env`, `spotify_token.json`, or any file containing
  credentials. Both are in `.gitignore`.
