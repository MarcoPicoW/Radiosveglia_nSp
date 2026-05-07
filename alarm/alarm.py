#!/usr/bin/env python3
"""
Radiosveglia_nSp — alarm script.

Run by systemd at the configured wake-up time. Fetches the latest episode
of the configured Spotify show, transfers playback to the radiosveglia
Spotify Connect device, and starts playback with a soft volume fade-in
to mask the I2S amplifier click.

This script reads its settings from /boot/firmware/radiosveglia.conf via
radiosveglia_config.py — there are no hardcoded values for show_id,
market, device_name, or volume.
"""

import logging
import sys
import time
from pathlib import Path

# Make sibling modules importable when launched by systemd
sys.path.insert(0, str(Path(__file__).resolve().parent))

import requests

import spotify_client as sc
from radiosveglia_config import load_config

API = "https://api.spotify.com/v1"
HTTP_TIMEOUT = 20  # seconds, applied to every request

logger = logging.getLogger("radiosveglia.alarm")


# -----------------------------------------------------------------------------
# Spotify Web API helpers
# -----------------------------------------------------------------------------

def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def find_device(token: str, device_name: str) -> str:
    """Return the Spotify Connect device ID matching device_name."""
    r = requests.get(
        f"{API}/me/player/devices",
        headers=_headers(token),
        timeout=HTTP_TIMEOUT,
    )
    r.raise_for_status()
    for d in r.json().get("devices", []):
        if d.get("name") == device_name:
            return d["id"]
    available = [d.get("name") for d in r.json().get("devices", [])]
    raise SystemExit(
        f"Spotify Connect device '{device_name}' not found. "
        f"Available: {available}. Is spotifyd running?"
    )


def latest_episode_uri(token: str, show_id: str, market: str) -> str:
    """Return the spotify:episode:... URI of the most recent episode."""
    r = requests.get(
        f"{API}/shows/{show_id}/episodes",
        headers=_headers(token),
        params={"limit": 1, "market": market},
        timeout=HTTP_TIMEOUT,
    )
    r.raise_for_status()
    items = r.json().get("items", [])
    if not items:
        raise SystemExit(
            f"No episodes found for show {show_id} (market={market}). "
            f"Check the show_id and market in radiosveglia.conf."
        )
    return items[0]["uri"]


def set_volume(token: str, device_id: str, percent: int) -> None:
    """Set device volume (0-100). Best-effort, doesn't raise on failure."""
    try:
        requests.put(
            f"{API}/me/player/volume",
            headers=_headers(token),
            params={"volume_percent": percent, "device_id": device_id},
            timeout=HTTP_TIMEOUT,
        )
    except requests.RequestException as e:
        logger.warning("Failed to set volume to %d: %s", percent, e)


def transfer_playback(token: str, device_id: str) -> None:
    """Transfer the active playback session to our device, paused."""
    requests.put(
        f"{API}/me/player",
        headers=_headers(token),
        json={"device_ids": [device_id], "play": False},
        timeout=HTTP_TIMEOUT,
    )


def start_playback(token: str, device_id: str, uri: str) -> None:
    """Start playback of a single track/episode URI."""
    r = requests.put(
        f"{API}/me/player/play",
        headers=_headers(token),
        params={"device_id": device_id},
        json={"uris": [uri]},
        timeout=HTTP_TIMEOUT,
    )
    # Spotify returns 204 on success — that's not an error
    if r.status_code not in (200, 202, 204):
        r.raise_for_status()


# -----------------------------------------------------------------------------
# Main flow
# -----------------------------------------------------------------------------

def main() -> int:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    cfg = load_config()
    logger.info(
        "Config loaded: show=%s market=%s device=%s volume=%d",
        cfg.show_id, cfg.market, cfg.device_name, cfg.volume,
    )

    token = sc.get_access_token_no_browser()
    device_id = find_device(token, cfg.device_name)
    episode_uri = latest_episode_uri(token, cfg.show_id, cfg.market)
    logger.info("Latest episode URI: %s", episode_uri)

    # Start silent to mask the amplifier click on activation
    set_volume(token, device_id, 2)

    transfer_playback(token, device_id)
    start_playback(token, device_id, episode_uri)

    # Let the playback actually start, then fade in
    time.sleep(3)
    set_volume(token, device_id, cfg.volume)

    logger.info("Playback started at volume %d", cfg.volume)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
