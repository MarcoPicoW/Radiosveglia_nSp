"""
Radiosveglia_nSp — User configuration loader.

Reads /boot/firmware/radiosveglia.conf and exposes typed values to the
rest of the codebase. Falls back to sensible defaults if the file is
missing or malformed, and logs warnings (without crashing) for any
invalid individual entries.

Usage:
    from radiosveglia_config import load_config
    cfg = load_config()
    print(cfg.show_id)            # "16dmTJvMre4YDTUYpuJtuZ"
    print(cfg.market)             # "CH"
    print(cfg.volume)             # 50
    print(cfg.alarm_schedule)     # {"monday": "06:30", ..., "saturday": None}
"""

from __future__ import annotations

import configparser
import logging
import re
from dataclasses import dataclass, field
from pathlib import Path

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------

CONFIG_PATH = Path("/boot/firmware/radiosveglia.conf")

DAYS_OF_WEEK = (
    "monday", "tuesday", "wednesday", "thursday",
    "friday", "saturday", "sunday",
)

# HH:MM in 24-hour format. Hours: 00-23, minutes: 00-59.
TIME_RE = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)$")

# Default values used if config is missing, unreadable, or invalid.
DEFAULTS = {
    "schedule": {day: "06:30" for day in DAYS_OF_WEEK},
    "volume": 50,
    "show_id": "16dmTJvMre4YDTUYpuJtuZ",  # placeholder, user should change it
    "market": "CH",
    "device_name": "Radiosveglia",
}

logger = logging.getLogger(__name__)


# -----------------------------------------------------------------------------
# Data class
# -----------------------------------------------------------------------------

@dataclass
class RadiosvegliaConfig:
    """Typed view of the user configuration."""

    # Map: day_name -> "HH:MM" string, or None if no alarm that day.
    alarm_schedule: dict[str, str | None] = field(default_factory=dict)
    volume: int = DEFAULTS["volume"]
    show_id: str = DEFAULTS["show_id"]
    market: str = DEFAULTS["market"]
    device_name: str = DEFAULTS["device_name"]

    @property
    def active_days(self) -> list[str]:
        """Return the list of days with a non-None alarm time."""
        return [day for day, time in self.alarm_schedule.items() if time]


# -----------------------------------------------------------------------------
# Validation helpers
# -----------------------------------------------------------------------------

def _validate_time(value: str, day: str) -> str | None:
    """Return a valid HH:MM string or None (with a warning) if invalid."""
    value = value.strip()
    if not value:
        return None
    if TIME_RE.match(value):
        return value
    logger.warning(
        "Invalid time %r for %s in radiosveglia.conf — alarm disabled for %s",
        value, day, day,
    )
    return None


def _validate_volume(value: str) -> int:
    """Clamp volume to 0-100, fall back to default if not an integer."""
    try:
        v = int(value.strip())
    except (ValueError, AttributeError):
        logger.warning(
            "Invalid volume %r in radiosveglia.conf — using default %d",
            value, DEFAULTS["volume"],
        )
        return DEFAULTS["volume"]
    return max(0, min(100, v))


def _validate_market(value: str) -> str:
    """Two-letter ISO code, uppercased. Falls back to default if malformed."""
    value = (value or "").strip().upper()
    if re.fullmatch(r"[A-Z]{2}", value):
        return value
    logger.warning(
        "Invalid market %r in radiosveglia.conf — using default %s",
        value, DEFAULTS["market"],
    )
    return DEFAULTS["market"]


def _validate_show_id(value: str) -> str:
    """Spotify IDs are 22 alphanumeric chars. Mild sanity check only."""
    value = (value or "").strip()
    if re.fullmatch(r"[A-Za-z0-9]{22}", value):
        return value
    logger.warning(
        "show_id %r doesn't look like a Spotify ID (22 alphanum chars) — "
        "using it anyway, but double-check it",
        value,
    )
    return value or DEFAULTS["show_id"]


# -----------------------------------------------------------------------------
# Loader
# -----------------------------------------------------------------------------

def load_config(path: Path = CONFIG_PATH) -> RadiosvegliaConfig:
    """
    Read and parse the user config file.

    On any error (missing file, parse error, missing sections), returns a
    config populated with defaults. Individual invalid values are warned about
    and replaced with defaults; the rest of the file is still honored.
    """
    cfg = RadiosvegliaConfig(
        alarm_schedule=dict(DEFAULTS["schedule"]),
    )

    if not path.exists():
        logger.warning(
            "Config file %s not found — using defaults", path,
        )
        return cfg

    parser = configparser.ConfigParser(
        inline_comment_prefixes=("#", ";"),
        empty_lines_in_values=False,
    )
    try:
        parser.read(path, encoding="utf-8")
    except configparser.Error as e:
        logger.error("Failed to parse %s: %s — using defaults", path, e)
        return cfg

    # [alarm]
    if parser.has_section("alarm"):
        schedule: dict[str, str | None] = {}
        for day in DAYS_OF_WEEK:
            raw = parser.get("alarm", day, fallback="").strip()
            schedule[day] = _validate_time(raw, day)
        cfg.alarm_schedule = schedule

        if parser.has_option("alarm", "volume"):
            cfg.volume = _validate_volume(parser.get("alarm", "volume"))

    # [spotify]
    if parser.has_section("spotify"):
        if parser.has_option("spotify", "show_id"):
            cfg.show_id = _validate_show_id(parser.get("spotify", "show_id"))
        if parser.has_option("spotify", "market"):
            cfg.market = _validate_market(parser.get("spotify", "market"))
        if parser.has_option("spotify", "device_name"):
            name = parser.get("spotify", "device_name").strip()
            if name:
                cfg.device_name = name

    return cfg


# -----------------------------------------------------------------------------
# CLI for quick inspection
# -----------------------------------------------------------------------------

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    cfg = load_config()
    print("=== Radiosveglia config ===")
    print(f"  show_id     : {cfg.show_id}")
    print(f"  market      : {cfg.market}")
    print(f"  device_name : {cfg.device_name}")
    print(f"  volume      : {cfg.volume}")
    print(f"  schedule    :")
    for day, time in cfg.alarm_schedule.items():
        print(f"    {day:<10s} {time or '(no alarm)'}")
    print(f"  active days : {', '.join(cfg.active_days) or '(none)'}")
