```text
Radiosveglia_nSp/
├── .gitignore
├── LICENSE
├── README.md
├── README.it.md
├── CHANGELOG.md
├── DEVELOPMENT.md
├── alarm/
│   ├── alarm.py
│   ├── radiosveglia_config.py
│   ├── spotify_client.py
│   └── spotify.env.example
├── boot-overlay/
│   ├── radiosveglia.conf
│   └── README-FIRST.txt
├── docs/
│   ├── user-guide.md
│   └── architecture.md
├── scripts/
│   ├── apply-config.sh
│   ├── firstboot.sh
│   └── spotifyd-bootstrap.sh
├── spotifyd/
│   ├── spotifyd.conf
│   └── asoundrc
├── systemd/
│   ├── alarm.service
│   ├── alarm.timer.template
│   ├── radiosveglia-config.service
│   ├── radiosveglia-firstboot.service
│   ├── spotifyd-bootstrap.service
│   └── spotifyd.service
└── tools/
    ├── setup-spotify.py
    ├── build-spotifyd.sh
    └── build-image.sh
```