radiosveglia_nSp/
│
├── [x] README.md                          ← Pagina principale del repo
├── DEVELOPMENT.md                     ← Guida per chi vuole modificare/contribuire
├── CHANGELOG.md                       ← Storia delle release
├── [x] LICENSE                            ← MIT, GPL, ecc.
├── [x] .gitignore
│
├── docs/
│   ├── [x] architecture.md                ← Il piano che abbiamo scritto
│   ├── user-guide.md                  ← Guida utente con screenshot
|   ├── CrossCompiling - Debian Wiki.pdf
|   ├── Spotifyd.pdf
│   └── img/                           ← Screenshot del processo
│       ├── imager-settings.png
│       └── developer-app.png
│
├── alarm/                             ← Codice che gira sul Pi Zero
│   ├── [x] alarm.py
│   ├── [x] spotify_client.py
│   └── [x] radiosveglia_config.py
│
├── systemd/                           ← Unit files
│   ├── spotifyd.service
│   ├── alarm.service
│   ├── alarm.timer.template           ← Template, generato dinamicamente
│   ├── spotifyd-bootstrap.service
│   ├── radiosveglia-config.service
│   └── radiosveglia-firstboot.service
│
├── boot-overlay/                      ← Va in /boot/firmware/ dell'immagine
│   ├── [x] radiosveglia.conf              ← Template config utente
│   └── README-FIRST.txt               ← Visibile da Win/Mac al primo flash
│
├── scripts/                           ← Script che vivono sul Pi
│   ├── firstboot.sh
│   ├── [x] apply-config.sh
│   └── spotifyd-bootstrap.sh
│
└── tools/                             ← Utility per maintainer + utente
    ├── [x] setup-spotify.py               ← L'utente lo esegue sul proprio PC
    ├── [x] build-image.sh                 ← Tu lo esegui sul Pi 5
    └── [x] build-spotifyd.sh              ← Tu lo esegui sul Pi 5