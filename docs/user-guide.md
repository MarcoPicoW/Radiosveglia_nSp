# User Guide

This guide covers everything after the five-step quick start in the README:
detailed wiring diagrams, alternative ways to copy the Spotify token, and a
troubleshooting reference for the most common problems.

---

## Hardware wiring

### Components

| Component | Notes |
|-----------|-------|
| Raspberry Pi Zero 2 W | GPIO header must be soldered |
| Adafruit MAX98357A | I2S Class-D mono amplifier breakout |
| 2x speaker, 4 ohm | Visaton FR 10 or equivalent full-range driver |
| 5 V power supply, min 2.5 A | Micro-USB |
| Jumper wires | Male-to-female |

### I2S wiring table

| Pi Zero 2 W signal | Physical pin | MAX98357A pad |
|--------------------|-------------|---------------|
| 5 V | Pin 2 or 4 | VIN |
| GND | Pin 6 | GND |
| GPIO18 (PCM CLK) | Pin 12 | BCLK |
| GPIO19 (PCM FS) | Pin 35 | LRC / WS |
| GPIO21 (PCM DOUT) | Pin 40 | DIN |

The two speakers connect to the **+** and **-** screw terminals on the
MAX98357A. Polarity matters for stereo imaging if you ever run two units, but
a single amplifier in mono is fine either way.

### Notes on the Gain and SD pins

The **Gain** pad sets the amplifier gain (default 9 dB when floating). Leave
it unconnected unless you need a different gain level.

The **SD** (shutdown) pad enables or disables the amplifier output. When left
floating the amplifier is active, which is the correct default. If you hear
a pop or click at startup, connecting SD to a GPIO and pulling it high only
after playback starts can reduce the artifact — but this requires additional
software changes and is not implemented in v1.

### Verified audio configuration

The following configuration is what the image ships with. You should not need
to change it.

`/boot/firmware/config.txt` (relevant lines):

```ini
dtparam=audio=off
dtoverlay=hifiberry-dac
```

`~/.asoundrc`:

```
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
```

`~/.config/spotifyd/spotifyd.conf` (relevant lines):

```toml
device_name = "Radiosveglia"
backend = "alsa"
device = "default"
audio_format = "S16"
volume_controller = "softvol"
bitrate = 320
```

---

## Copying spotify_token.json to the Pi

After running `setup-spotify.py` on your computer you need to transfer the
resulting `spotify_token.json` to `~/alarm/` on the Pi.

### Linux or macOS (terminal)

```bash
scp spotify_token.json radiosveglia@radiosveglia.local:~/alarm/
```

If mDNS does not work on your network, replace `radiosveglia.local` with the
Pi's IP address (visible in your router's DHCP table or via `ping
radiosveglia.local`).

### Windows — PowerShell (OpenSSH)

OpenSSH ships with Windows 10 and 11. Open PowerShell and run:

```powershell
scp spotify_token.json radiosveglia@radiosveglia.local:/home/radiosveglia/alarm/
```

### Windows — WinSCP (graphical)

1. Download and install [WinSCP](https://winscp.net/).
2. Open WinSCP. In the login dialog:
   - File protocol: **SFTP**
   - Host name: `radiosveglia.local` (or the IP address)
   - User name: `radiosveglia`
   - Password: the password you set in Raspberry Pi Imager
3. Click **Login**.
4. On the right panel, navigate to `/home/radiosveglia/alarm/`.
5. Drag `spotify_token.json` from your computer (left panel) to the right panel.
6. Close WinSCP.

---

## Changing the alarm schedule

### Method 1 — Edit the SD card directly (Pi powered off)

This is the simplest method and does not require SSH.

1. Power off the Pi: connect via SSH and run `sudo shutdown now`, then wait
   for the LED to stop blinking before unplugging power.
2. Remove the microSD card and insert it into your computer.
3. The card appears as a removable drive called `bootfs` (or similar).
4. Open `radiosveglia.conf` in any text editor and change the times.
5. Save, eject the card, reinsert it into the Pi and power on.

### Method 2 — Edit via SSH (Pi stays on)

```bash
ssh radiosveglia@radiosveglia.local
sudo nano /boot/firmware/radiosveglia.conf
sudo reboot
```

The reboot triggers `radiosveglia-config.service`, which reads the new
schedule and regenerates `alarm.timer` automatically.

### Config file format reference

```ini
[alarm]
monday    = 06:30    # HH:MM, 24-hour
tuesday   = 06:30
wednesday = 06:30
thursday  = 06:30
friday    = 06:30
saturday  =          # empty = no alarm this day
sunday    =

volume = 40          # 0-100

[spotify]
show_id = 16dmTJvMre4YDTUYpuJtuZ   # your podcast's Spotify ID
market = CH                         # ISO country code
device_name = Radiosveglia          # must match spotifyd device_name
```

**Finding a podcast's show_id**: open Spotify, right-click the show, choose
"Share" then "Copy link to show". The URL looks like
`https://open.spotify.com/show/16dmTJvMre4YDTUYpuJtuZ`. The ID is the
segment after `/show/`.

---

## Manual alarm test

To trigger the alarm immediately without waiting for the scheduled time:

```bash
ssh radiosveglia@radiosveglia.local
systemctl --user start alarm.service
journalctl --user -u alarm.service -n 30
```

The speakers should start playing the latest episode of your podcast at a low
volume, then ramp up to the configured volume after about three seconds.

---

## Troubleshooting

### The Pi does not appear on the network

Check these in order:

1. Did you set the correct Wi-Fi SSID and password in Raspberry Pi Imager
   before flashing? The field is case-sensitive.
2. Is the Pi within range of the Wi-Fi router? The Pi Zero 2 W antenna is
   small; walls reduce range significantly.
3. Wait at least 3 minutes after powering on. The first boot takes longer
   than subsequent ones.
4. Try pinging by IP instead of hostname:
   ```bash
   ping radiosveglia.local   # try this first
   # if that fails, look up the IP in your router's DHCP client list
   ping 192.168.x.x
   ```
5. On some routers, mDNS (`.local` hostnames) is blocked. Use the IP address
   directly in all subsequent commands.

---

### No audio from the speakers

Check in this order:

```bash
# 1. Verify the I2S overlay loaded
aplay -l
# Expected: a line containing "sndrpihifiberry" or "HifiBerry DAC"
# If you only see "vc4-hdmi", the overlay is not active — check config.txt
```

```bash
# 2. Play a test tone
speaker-test -c 2 -t sine
# You should hear a sine wave from both speakers
# Press Ctrl+C to stop
```

```bash
# 3. Check .asoundrc is present
cat ~/.asoundrc
```

```bash
# 4. Check spotifyd is using the correct device
grep "^device" ~/.config/spotifyd/spotifyd.conf
# Expected: device = "default"
```

If `aplay -l` does not show the hifiberry device after the overlay is in
config.txt, double-check the wiring. The most common mistake is swapping
GPIO19 (pin 35) and GPIO21 (pin 40).

---

### "Device 'Radiosveglia' not found"

This error from `alarm.py` means spotifyd is either not running or not
visible as a Spotify Connect device.

```bash
# Check if spotifyd is running
systemctl --user status spotifyd

# If it failed, check the logs
journalctl --user -u spotifyd -n 50

# Restart it manually
systemctl --user restart spotifyd

# Wait 5 seconds, then check if it appears in device list
python3 -c "
import json, subprocess
# requires a valid token
"
```

Common causes:

- spotifyd binary not installed. Run:
  ```bash
  ls -lh /usr/local/bin/spotifyd
  spotifyd --version
  ```
  If missing, run `~/scripts/spotifyd-bootstrap.sh` manually.

- The binary is the `-default` variant linked against `libssl.so.1.1`, which
  does not exist on Debian Trixie. You must use the `-slim` variant
  (statically linked). Check with:
  ```bash
  ldd /usr/local/bin/spotifyd
  # "statically linked" is correct
  # any "not found" library line means wrong variant
  ```

- `spotify_token.json` is missing or expired. Re-run `setup-spotify.py` on
  your computer and copy the new file to the Pi.

---

### The alarm does not fire at the scheduled time

```bash
# Check the timer is loaded and enabled
systemctl --user list-timers | grep alarm

# Check when it will next fire
systemctl --user status alarm.timer

# Check the generated timer file
cat ~/.config/systemd/user/alarm.timer
```

If the timer file shows `OnCalendar=*-*-* 06:30:00` (the fallback default)
instead of your configured days, `apply-config.sh` may not have run or may
have found an error in the config file.

Run it manually and check for warnings:

```bash
~/scripts/apply-config.sh
systemctl --user daemon-reload
systemctl --user restart alarm.timer
```

---

### A click sound at speaker startup

This is a known characteristic of the MAX98357A: the amplifier produces a
brief pop when it activates. The alarm script starts playback at volume 2
and ramps up to the configured volume after 3 seconds, which mitigates but
does not fully eliminate the click.

Connecting the **SD** pin to a GPIO and controlling it in software is the
proper hardware fix, but this is not implemented in v1. If the click bothers
you, a resistor from SD to GND (to hold the amplifier in shutdown until
explicitly enabled) combined with GPIO control in `alarm.py` is the approach
to pursue.

---

### Checking all service logs at once

```bash
# All Radiosveglia-related user units
journalctl --user -u spotifyd -u alarm.service -u alarm.timer \
           -u radiosveglia-config.service -u spotifyd-bootstrap.service \
           --since "24 hours ago"
```

```bash
# System-level first-boot service
sudo journalctl -u radiosveglia-firstboot.service
```

---

### Refreshing the Spotify token manually

The token in `spotify_token.json` refreshes automatically when `alarm.py`
runs. If it becomes completely invalid (e.g. you revoked access in your
Spotify account settings), you need to re-run the initial authorization:

1. On your computer, run `tools/setup-spotify.py` again.
2. Copy the new `spotify_token.json` to the Pi:
   ```bash
   scp spotify_token.json radiosveglia@radiosveglia.local:~/alarm/
   ```

---

## Factory reset

To return the Pi to its out-of-the-box state, simply reflash the SD card
with the official image using Raspberry Pi Imager. All user data
(token, config changes) is on the card and will be overwritten.

If you want to keep the hardware but start fresh with new Spotify credentials,
it is enough to replace `~/alarm/spotify_token.json` as described above.
