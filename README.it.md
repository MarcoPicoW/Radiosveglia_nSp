<div align="center">

# Radiosveglia_nSp

### Smart Spotify Alarm Clock per Raspberry Pi Zero 2 W

*Svegliati ogni mattina con l'ultimo episodio del tuo podcast preferito, riprodotto da un piccolo Pi Zero collegato a due casse vere.*

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform: Pi Zero 2 W](https://img.shields.io/badge/Platform-Pi%20Zero%202%20W-c51a4a)](https://www.raspberrypi.com/products/raspberry-pi-zero-2-w/)
[![OS: Trixie](https://img.shields.io/badge/OS-Debian%20Trixie-a80030)](https://www.debian.org/releases/trixie/)

[**Scarica l'ultima versione**](https://github.com/USER/Radiosveglia_nSp/releases/latest)
&nbsp;·&nbsp;
[**Guida utente**](docs/user-guide.md)
&nbsp;·&nbsp;
[**Per sviluppatori**](DEVELOPMENT.md)
&nbsp;·&nbsp;
[**🇬🇧 English**](README.md)

<!-- TODO: foto del prodotto finito qui -->
<img src="docs/img/hero.jpg" alt="Radiosveglia in funzione" width="500"/>

</div>

---

## Prerequisiti

> **Questo progetto richiede un account Spotify Premium.**
>
> L'acronimo *nSp* sta proprio per "needs Spotify Premium". Senza Premium, l'API di Spotify non permette di controllare la riproduzione, quindi la sveglia automatica non funzionerà. Se non hai Premium, questo progetto non fa per te.

---

## Cosa fa

- **Sveglia automatica** a orari configurabili — anche diversi per ogni giorno della settimana
- **Ultimo episodio del podcast** che preferisci, scaricato fresco ogni mattina via Spotify Web API
- **Audio di qualità** tramite amplificatore I2S MAX98357A e casse esterne
- **Volume fade-in** all'avvio per ridurre il "click" dell'amplificatore
- **Spotify Connect** integrato — di giorno la radiosveglia diventa una cassa Wi-Fi per Spotify
- **Completamente headless** — niente schermo, niente tastiera, gira da sola

## Hardware necessario

| Componente | Note | Costo indicativo |
|------------|------|------------------|
| Raspberry Pi Zero 2 W | Con header GPIO saldati | ~20 € |
| MicroSD da 8 GB o più | Classe 10 | ~5 € |
| Adafruit MAX98357A | Amplificatore I2S Class-D | ~7 € |
| 2× Casse passive da 4 Ω | Visaton FR 10 o equivalenti | ~25 € |
| Alimentatore 5V ≥ 2.5 A | Micro-USB | ~10 € |
| Cavi jumper | Maschio-femmina | ~3 € |

**Totale: ~70 €** (esclusi attrezzi base come saldatore se non hai i pin pre-saldati).

> **Nota**: per il setup iniziale ti serve anche un PC qualunque (Windows, Mac o Linux) con un browser. Niente Pi 5, niente Mac M2, basta una macchina che apra una pagina web.

## Installazione in 5 step

### Step 1 — Cabla l'hardware

Collega il MAX98357A al Pi Zero secondo questa tabella:

| Pi Zero pin | MAX98357A |
|-------------|-----------|
| 5V (pin 2 o 4) | VIN |
| GND (pin 6) | GND |
| GPIO18 (pin 12) | BCLK |
| GPIO19 (pin 35) | LRC / WS |
| GPIO21 (pin 40) | DIN |

Le casse vanno ai due output dell'amplificatore. Schema dettagliato in [`docs/user-guide.md`](docs/user-guide.md).

### Step 2 — Flasha la SD

1. Scarica l'ultima immagine: [**radiosveglia-vX.Y.img.xz**](https://github.com/USER/Radiosveglia_nSp/releases/latest)
2. Apri **[Raspberry Pi Imager](https://www.raspberrypi.com/software/)**
3. *Choose OS* → *Use custom* → seleziona il file scaricato
4. *Choose Storage* → la tua microSD
5. Clicca l'icona "Edit settings":
   - [] Enable SSH (con password)
   - [] Set username and password — **lascia username `radiosveglia`** (importante!)
   - [] Configure wireless LAN (SSID + password della tua Wi-Fi)
   - [] Set hostname: `radiosveglia`
6. *Write* — aspetta qualche minuto

> ⚠️ **Lascia `radiosveglia` come username**. Se lo cambi, devi modificare manualmente i path nei systemd service. Vedi [DEVELOPMENT.md](DEVELOPMENT.md).

### Step 3 — Configura la sveglia

**Senza estrarre la SD** dopo il flash, apri la partizione `boot` (apparirà come unità rimovibile) e modifica `radiosveglia.conf` con un editor di testo (Blocco Note, TextEdit, nano, qualsiasi cosa):

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
show_id = 16dmTJvMre4YDTUYpuJtuZ    # <-- ID del tuo podcast (vedi sotto)
market = CH                          # <-- il tuo paese (CH, IT, DE, US, ...)
device_name = Radiosveglia
```

**Per disabilitare la sveglia in un giorno**, lascia il campo vuoto:
```ini
saturday =       # niente sveglia il sabato
```

**Come trovare lo `show_id` del tuo podcast**: apri Spotify, cerca il podcast, condividi il link → `https://open.spotify.com/show/16dmTJvMre4YDTUYpuJtuZ`. L'ID è la parte dopo `/show/`.

Salva il file, espelli la SD, **inseriscila nel Pi Zero, accendi**.

### Step 4 — Aspetta il primo boot

Il primo avvio dura **5-10 minuti** (il Pi scarica `spotifyd`, configura i servizi). Quando vedi il LED smettere di lampeggiare freneticamente, è pronto.

Verifica che sia raggiungibile:

```bash
ping radiosveglia.local
```

Se risponde, perfetto. Se non risponde dopo 10 minuti, vedi [Troubleshooting](docs/user-guide.md#troubleshooting).

### Step 5 — Setup Spotify (sul tuo PC)

Questo è l'unico step un po' "tecnico". Lo fai una volta sola e mai più.

#### 5.1 — Crea un'app su Spotify Developer

1. Vai su **https://developer.spotify.com/dashboard**
2. Login con il tuo account Spotify (Premium)
3. Clicca *Create app*
4. Nome: `Radiosveglia` — descrizione: qualsiasi cosa
5. **Redirect URI**: `http://127.0.0.1:8888/callback` ← devi mettere esattamente questo
6. Salva, accetta i termini, clicca sull'app appena creata
7. Copia **Client ID** e **Client Secret** (li userai tra un momento)

#### 5.2 — Esegui setup-spotify.py

Sul tuo PC, scarica [**`setup-spotify.py`**](https://github.com/USER/Radiosveglia_nSp/releases/latest) dalla stessa release.

Apri un terminale dove l'hai scaricato e:

```bash
# Linux / Mac
python3 -m pip install requests
python3 setup-spotify.py

# Windows (PowerShell)
py -m pip install requests
py setup-spotify.py
```

Lo script:
1. Ti chiede Client ID e Client Secret
2. Apre il browser per l'autorizzazione di Spotify
3. Salva un file `spotify_token.json` accanto a sé

#### 5.3 — Copia il token sul Pi

```bash
# Linux / Mac (terminale)
scp spotify_token.json radiosveglia@radiosveglia.local:~/alarm/

# Windows (PowerShell, OpenSSH è preinstallato su Win 10/11)
scp spotify_token.json radiosveglia@radiosveglia.local:/home/radiosveglia/alarm/
```

Su Windows, in alternativa, puoi usare [**WinSCP**](https://winscp.net/) (interfaccia grafica drag-and-drop) — vedi `docs/user-guide.md`.

#### 5.4 — Test

Da SSH sul Pi:

```bash
ssh radiosveglia@radiosveglia.local

# Test alarm immediato
systemctl --user start alarm.service

# Verifica
journalctl --user -u alarm.service -n 20
```

Se tutto va bene, le casse iniziano a riprodurre l'ultimo episodio del podcast a volume crescente. **Ce l'hai fatta!** 🎉

## Cambiare la sveglia

In qualsiasi momento puoi modificare gli orari:

**Metodo 1 — Editi la SD direttamente** (richiede di estrarre la SD):
1. Spegni il Pi: `sudo shutdown now`
2. Inserisci la SD nel PC
3. Modifica `radiosveglia.conf` nella partizione `boot`
4. Reinserisci la SD nel Pi e accendi

**Metodo 2 — Editi via SSH** (Pi acceso):
```bash
ssh radiosveglia@radiosveglia.local
sudo nano /boot/firmware/radiosveglia.conf
sudo reboot
```

## Qualcosa non funziona?

Vedi [Troubleshooting](docs/user-guide.md#troubleshooting). I problemi più comuni:

- **Il Pi non si vede in rete** → controlla SSID/password Wi-Fi nel passo 2.5
- **L'audio non esce dalle casse** → cablaggio MAX98357A, verifica con `aplay -l`
- **"Device 'Radiosveglia' not found"** → spotifyd non è partito, vedi i log
- **Si sente un click all'avvio** → è caratteristico del MAX98357A, il fade-in lo riduce ma non lo elimina

## Contribuire

Pull request benvenute! Vedi [DEVELOPMENT.md](DEVELOPMENT.md) per:
- come ricompilare l'immagine
- come modificare il codice
- come testare le modifiche

## Licenza

[MIT](LICENSE) — fanne quello che vuoi, attribuzione apprezzata.

## Crediti

- [`spotifyd`](https://github.com/Spotifyd/spotifyd) — per il daemon Spotify Connect
- [Adafruit](https://www.adafruit.com/) — per la breakout board MAX98357A
- [Visaton](https://www.visaton.de/) — per le casse FR 10
- [Raspberry Pi Foundation](https://www.raspberrypi.com/) — per il Pi Zero 2 W
- Spotify Web API — per il controllo remoto della riproduzione

---

<div align="center">
<sub>Built with many Beers and Pi Zero. <a href="https://github.com/USER/Radiosveglia_nSp/issues">Issues & feedback</a></sub>
</div>