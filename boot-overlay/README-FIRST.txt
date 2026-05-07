============================================================
  Radiosveglia_nSp
  Smart Spotify Alarm Clock for Raspberry Pi Zero 2 W
============================================================

Welcome! You are reading this from the SD card's boot partition.

QUICK START
-----------

1. CONFIGURE YOUR ALARM
   Open the file "radiosveglia.conf" in this folder with any
   text editor (Notepad, TextEdit, nano, etc.) and set:
     - The alarm time for each day of the week
     - Your podcast's show_id (instructions in the file)
     - Your country code (market = CH / IT / DE / US / ...)

2. EJECT THE SD AND INSERT IT INTO THE PI ZERO
   Power on the Pi. The first boot takes 5-10 minutes.

3. AUTHORIZE SPOTIFY (once, from your computer)
   Run setup-spotify.py from the release package. Full
   instructions in the README at:
     https://github.com/USER/Radiosveglia_nSp

============================================================

CHANGING THE ALARM LATER
-------------------------

Method 1 (SD ejected):
  Edit radiosveglia.conf here, reinsert and reboot the Pi.

Method 2 (via SSH, Pi running):
  ssh radiosveglia@radiosveglia.local
  sudo nano /boot/firmware/radiosveglia.conf
  sudo reboot

============================================================

SUPPORT
-------
  Full documentation: https://github.com/USER/Radiosveglia_nSp
  Troubleshooting:    https://github.com/USER/Radiosveglia_nSp/blob/main/docs/user-guide.md
  Issues:             https://github.com/USER/Radiosveglia_nSp/issues

============================================================
