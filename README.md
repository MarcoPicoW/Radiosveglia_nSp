<div align="center">

# Radiosveglia_nSp

### Smart Spotify Alarm Clock for Raspberry Pi Zero 2 W

*Wake up every morning to the latest episode of your favorite podcast, played from a tiny Pi Zero through real speakers.*

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform: Pi Zero 2 W](https://img.shields.io/badge/Platform-Pi%20Zero%202%20W-c51a4a)](https://www.raspberrypi.com/products/raspberry-pi-zero-2-w/)
[![OS: Trixie](https://img.shields.io/badge/OS-Debian%20Trixie-a80030)](https://www.debian.org/releases/trixie/)

[**Download latest release**](https://github.com/MarcoPicoW/Radiosveglia_nSp/releases/latest)
&nbsp;·&nbsp;
[**User guide**](docs/user-guide.md)
&nbsp;·&nbsp;
[**For developers**](DEVELOPMENT.md)
&nbsp;·&nbsp;
[**🇮🇹 Italiano**](README.it.md)

<!-- TODO: photo of the finished product -->
<img src="docs/img/hero.jpg" alt="Radiosveglia in action" width="500"/>

</div>

---

## Prerequisites

> **This project requires a Spotify Premium account.**
>
> The *nSp* in the name stands for "needs Spotify Premium". Without Premium, the Spotify Web API does not allow remote playback control, so the automated alarm cannot work. If you don't have Premium, this project is not for you. 

---

## What it does

- **Automated alarm** at configurable times — different schedule for each day of the week
- **Latest podcast episode** fetched fresh every morning via the Spotify Web API
- **Quality audio** through a MAX98357A I2S amplifier and external speakers
- **Volume fade-in** at startup to soften the amplifier "click"
- **Spotify Connect** built in — during the day the alarm clock doubles as a Wi-Fi speaker for Spotify
- **Fully headless** — no screen, no keyboard, runs unattended

## 🛒 Hardware needed

| Component | Notes | Indicative cost |
|------------|------|------------------|
| Raspberry Pi Zero 2 W | With GPIO header soldered | ~20 € / $22 |
| MicroSD ≥ 8 GB | Class 10 | ~5 € / $6 |
| Adafruit MAX98357A | I2S Class-D amplifier breakout | ~7 € / $8 |
| 2× passive 4 Ω speakers | Visaton FR 10 or equivalent | ~25 € / $28 |
| 5V ≥ 2.5 A power supply | Micro-USB | ~10 € / $11 |
| Jumper wires | Male-to-female | ~3 € / $3 |

**Total: ~70 € / $80** (excluding basic tools like a soldering iron if your GPIO pins aren't pre-soldered).

> **Note**: for the initial setup you'll also need any computer (Windows, Mac, or Linux) with a web browser. No Pi 5 needed, no Mac M2 — just any machine that can open a webpage.

## Installation in 5 steps

### Step 1 — Wire the hardware

Connect the MAX98357A to the Pi Zero following this table:

| Pi Zero pin | MAX98357A |
|-------------|-----------|
| 5V (pin 2 or 4) | VIN |
| GND (pin 6) | GND |
| GPIO18 (pin 12) | BCLK |
| GPIO19 (pin 35) | LRC / WS |
| GPIO21 (pin 40) | DIN |

The speakers go to the two outputs of the amplifier. Detailed schematic in [`docs/user-guide.md`](docs/user-guide.md).

### Step 2 — Flash the SD

1. Download the latest image: [**radiosveglia-vX.Y.img.xz**](https://github.com/MarcoPicoW/Radiosveglia_nSp/releases/latest)
2. Open **[Raspberry Pi Imager](https://www.raspberrypi.com/software/)**
3. *Choose OS* → *Use custom* → select the downloaded file
4. *Choose Storage* → your microSD
5. Click the ⚙️ "Edit settings" icon:
   - [] Enable SSH (with password)
   - [] Set username and password — **leave the username as `radiosveglia`** (important!)
   - [] Configure wireless LAN (your Wi-Fi SSID + password)
   - [] Set hostname: `radiosveglia`
6. *Write* — wait a few minutes

> ⚠️ **Keep `radiosveglia` as the username**. If you change it, you'll need to manually patch the systemd service paths. See [DEVELOPMENT.md](DEVELOPMENT.md).

### Step 3 — Configure the alarm

**Without ejecting the SD** after flashing, open the `boot` partition (it shows up as a removable drive on Windows/macOS) and edit `radiosveglia.conf` with any text editor (Notepad, TextEdit, nano, anything):

```ini
[alarm]
monday    = 06:30
tuesday   = 06:30
wednesday = 06:30
thursday  = 06:30
friday    = 06:30
saturday  = 10:00
sunday    = 08:00

volume = 50

[spotify]
show_id = 16dmTJvMre4YDTUYpuJtuZ    # <-- your podcast's ID (see below)
market = CH                          # <-- your country (CH, IT, DE, US, ...)
device_name = Radiosveglia
```

**To skip the alarm on a given day**, leave the field blank:
```ini
saturday =       # no alarm on Saturday
```

**How to find your podcast's `show_id`**: open Spotify, find the show, share the link → `https://open.spotify.com/show/16dmTJvMre4YDTUYpuJtuZ`. The ID is the part after `/show/`.

Save the file, eject the SD, **insert it into the Pi Zero, power on**.

### Step 4 — Wait for the first boot

The first boot takes **5-10 minutes** (the Pi downloads `spotifyd`, configures services). When the LED stops flashing rapidly, it's ready.

Verify it's reachable:

```bash
ping radiosveglia.local
```

If it responds, you're good. If it doesn't respond after 10 minutes, see [Troubleshooting](docs/user-guide.md#troubleshooting).

### Step 5 — Spotify setup (on your computer)

This is the only "technical" step. You do it once and never again.

#### 5.1 — Create an app on Spotify Developer

1. Go to **https://developer.spotify.com/dashboard**
2. Log in with your Spotify (Premium) account
3. Click *Create app*
4. Name: `Radiosveglia` — description: anything you like
5. **Redirect URI**: `http://127.0.0.1:8888/callback` ← must be exactly this
6. Save, accept the terms, click on the newly created app
7. Copy **Client ID** and **Client Secret** (you'll need them in a moment)

#### 5.2 — Run setup-spotify.py

On your computer, download [**`setup-spotify.py`**](https://github.com/MarcoPicoW/Radiosveglia_nSp/releases/latest) from the same release.

Open a terminal in the download folder and:

```bash
# Linux / Mac
python3 -m pip install -r requirements.txt
python3 setup-spotify.py

# Windows (PowerShell)
py -m pip install -r requirements.txt
py setup-spotify.py
```

> If you downloaded only `setup-spotify.py` from the release page and don't have `requirements.txt`, `pip install requests` works too — `requests` is the only dependency.

The script:
1. Prompts for Client ID and Client Secret
2. Opens the browser for Spotify authorization
3. Saves a `spotify_token.json` file next to itself

#### 5.3 — Copy the token to the Pi

```bash
# Linux / Mac (terminal)
scp spotify_token.json radiosveglia@radiosveglia.local:~/alarm/

# Windows (PowerShell — OpenSSH ships with Win 10/11)
scp spotify_token.json radiosveglia@radiosveglia.local:/home/radiosveglia/alarm/
```

On Windows you can alternatively use [**WinSCP**](https://winscp.net/) (drag-and-drop GUI) — see `docs/user-guide.md`.

#### 5.4 — Test

From SSH on the Pi:

```bash
ssh radiosveglia@radiosveglia.local

# Trigger an immediate alarm
systemctl --user start alarm.service

# Check the result
journalctl --user -u alarm.service -n 20
```

If everything works, the speakers start playing the latest episode of the podcast at increasing volume. **You made it!** 🎉

## Changing the alarm

You can change the times anytime:

**Method 1 — Edit the SD directly** (requires ejecting the SD):
1. Power off the Pi: `sudo shutdown now`
2. Insert the SD in your computer
3. Edit `radiosveglia.conf` in the `boot` partition
4. Reinsert the SD into the Pi and power on

**Method 2 — Edit via SSH** (Pi stays on):
```bash
ssh radiosveglia@radiosveglia.local
sudo nano /boot/firmware/radiosveglia.conf
sudo reboot
```

## Something not working?

See [Troubleshooting](docs/user-guide.md#troubleshooting). Common issues:

- **The Pi isn't on the network** → check Wi-Fi SSID/password from Step 2.5
- **No audio from the speakers** → MAX98357A wiring, check `aplay -l`
- **"Device 'Radiosveglia' not found"** → spotifyd didn't start, check logs
- **A click sound at startup** → known MAX98357A behavior, the fade-in mitigates but doesn't eliminate it

## Contributing

Pull requests welcome! See [DEVELOPMENT.md](DEVELOPMENT.md) for:
- how to rebuild the image
- how to modify the code
- how to test changes

## License

[MIT](LICENSE) — do whatever you want with it, attribution appreciated.

## Credits

- [`spotifyd`](https://github.com/Spotifyd/spotifyd) — Spotify Connect daemon
- [Adafruit](https://www.adafruit.com/) — MAX98357A breakout board
- [Visaton](https://www.visaton.de/) — FR 10 speakers
- [Raspberry Pi Foundation](https://www.raspberrypi.com/) — Pi Zero 2 W
- Spotify Web API — remote playback control

---

<div align="center">
<sub>Built with many Beers and Pi Zero. <a href="https://github.com/MarcoPicoW/Radiosveglia_nSp/issues">Issues & feedback</a></sub>
</div>
