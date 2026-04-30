radiosveglia/
│
├── README.md                          ← Pagina principale del repo
├── DEVELOPMENT.md                     ← Guida per chi vuole modificare/contribuire
├── CHANGELOG.md                       ← Storia delle release
├── LICENSE                            ← MIT, GPL, ecc.
├── .gitignore
│
├── docs/
│   ├── architecture.md                ← Il piano che abbiamo scritto
│   ├── user-guide.md                  ← Guida utente con screenshot
│   └── img/                           ← Screenshot del processo
│       ├── imager-settings.png
│       └── developer-app.png
│
├── alarm/                             ← Codice che gira sul Pi Zero
│   ├── alarm.py
│   ├── spotify_client.py
│   └── radiosveglia_config.py
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
│   ├── radiosveglia.conf              ← Template config utente
│   └── README-FIRST.txt               ← Visibile da Win/Mac al primo flash
│
├── scripts/                           ← Script che vivono sul Pi
│   ├── firstboot.sh
│   ├── apply-config.sh
│   └── spotifyd-bootstrap.sh
│
└── tools/                             ← Utility per maintainer + utente
    ├── setup-spotify.py               ← L'utente lo esegue sul proprio PC
    ├── build-image.sh                 ← Tu lo esegui sul Pi 5
    └── build-spotifyd.sh              ← Tu lo esegui sul Pi 5