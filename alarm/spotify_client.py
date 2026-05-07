"""
Radiosveglia_nSp -- Spotify OAuth client.

Handles Spotify Web API authentication:
  - First-time login with browser (run once via tools/setup-spotify.py)
  - Token persistence in spotify_token.json
  - Automatic refresh of expired access tokens (used on the headless Pi)

spotify_token.json is created by tools/setup-spotify.py and must contain:
  access_token, refresh_token, client_id, client_secret, expires_at

No spotify.env file is needed on the Pi. All credentials are embedded in
spotify_token.json by setup-spotify.py at authorization time.
"""

import json
import os
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import requests

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
BASE_DIR   = Path(__file__).parent
TOKEN_PATH = BASE_DIR / "spotify_token.json"

AUTH_URL  = "https://accounts.spotify.com/authorize"
TOKEN_URL = "https://accounts.spotify.com/api/token"

SCOPES = " ".join([
    "user-read-playback-state",
    "user-modify-playback-state",
    "user-read-currently-playing",
    "user-library-read",
    "user-library-modify",
    "playlist-read-private",
    "playlist-read-collaborative",
    "playlist-modify-private",
    "playlist-modify-public",
    "user-read-email",
    "user-read-private",
    "user-top-read",
    "user-read-recently-played",
    "user-follow-read",
    "user-follow-modify",
])


# ---------------------------------------------------------------------------
# Token persistence
# ---------------------------------------------------------------------------

def save_token(data: dict) -> None:
    """Persist a token dict, adding an absolute expires_at timestamp."""
    data["expires_at"] = int(time.time()) + int(data.get("expires_in", 3600))
    TOKEN_PATH.write_text(json.dumps(data, indent=2))


def load_token() -> dict:
    """
    Load spotify_token.json. Raises RuntimeError if missing or incomplete.
    The file is created by tools/setup-spotify.py and must contain
    client_id, client_secret, and refresh_token.
    """
    if not TOKEN_PATH.exists():
        raise RuntimeError(
            f"spotify_token.json not found at {TOKEN_PATH}.\n"
            "Run tools/setup-spotify.py on your computer, then copy the\n"
            "resulting spotify_token.json to ~/alarm/ on the Pi."
        )
    token = json.loads(TOKEN_PATH.read_text())
    for key in ("client_id", "client_secret", "refresh_token"):
        if not token.get(key):
            raise RuntimeError(
                f"spotify_token.json is missing '{key}'.\n"
                "Re-run tools/setup-spotify.py and copy the new file to the Pi."
            )
    return token


def token_expired(token: dict) -> bool:
    """True if the access token expires within the next 60 seconds."""
    return int(token.get("expires_at", 0)) - 60 < time.time()


def refresh_access_token(token: dict) -> str:
    """Exchange the refresh_token for a new access_token. Persists the result."""
    r = requests.post(
        TOKEN_URL,
        data={
            "grant_type":    "refresh_token",
            "refresh_token": token["refresh_token"],
            "client_id":     token["client_id"],
            "client_secret": token["client_secret"],
        },
        timeout=20,
    )
    r.raise_for_status()
    data = r.json()
    # Spotify may omit refresh_token in the response -- keep the existing one.
    data["refresh_token"] = token["refresh_token"]
    data["client_id"]     = token["client_id"]
    data["client_secret"] = token["client_secret"]
    save_token(data)
    return data["access_token"]


# ---------------------------------------------------------------------------
# Public API used by alarm.py
# ---------------------------------------------------------------------------

def get_access_token_no_browser() -> str:
    """
    Return a valid access token without opening a browser.
    Used on the headless Pi. Refreshes automatically if expired.
    """
    token = load_token()
    if token_expired(token):
        return refresh_access_token(token)
    return token["access_token"]


# ---------------------------------------------------------------------------
# Legacy / compatibility alias
# ---------------------------------------------------------------------------

def get_access_token(client_id: str = "", client_secret: str = "") -> str:
    """
    Compatibility wrapper. Arguments are ignored -- credentials come from
    spotify_token.json. Kept so any existing callers do not break.
    """
    return get_access_token_no_browser()


# ---------------------------------------------------------------------------
# OAuth callback mini-server (used by first-time browser login only)
# ---------------------------------------------------------------------------
_auth: dict[str, str | None] = {"code": None, "error": None}


class _CallbackHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path != "/callback":
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not found")
            return
        qs = parse_qs(parsed.query)
        _auth["error"] = qs.get("error", [None])[0]
        _auth["code"]  = qs.get("code",  [None])[0]
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(b"<h2>OK. You can close this window.</h2>")

    def log_message(self, fmt, *args):
        return


def _run_server():
    srv = HTTPServer(("127.0.0.1", 8888), _CallbackHandler)
    srv.timeout = 1
    while _auth["code"] is None and _auth["error"] is None:
        srv.handle_request()


# ---------------------------------------------------------------------------
# First-time browser login (called by tools/setup-spotify.py, not alarm.py)
# ---------------------------------------------------------------------------

def get_access_token_first_time_with_browser(
    client_id: str,
    client_secret: str,
    redirect_uri: str = "http://127.0.0.1:8888/callback",
) -> str:
    """
    Full OAuth Authorization Code flow. Opens a browser, waits for the
    callback, exchanges the code for tokens, persists everything to
    spotify_token.json (including client_id and client_secret).
    """
    from urllib.parse import urlencode

    auth_url = AUTH_URL + "?" + urlencode({
        "response_type": "code",
        "client_id":     client_id,
        "scope":         SCOPES,
        "redirect_uri":  redirect_uri,
    })

    print("Opening browser for Spotify authorization ...")
    t = threading.Thread(target=_run_server, daemon=True)
    t.start()
    webbrowser.open(auth_url)

    for _ in range(120):
        if _auth["error"] or _auth["code"]:
            break
        time.sleep(1)

    if _auth["error"]:
        raise SystemExit(f"Spotify auth error: {_auth['error']}")
    if not _auth["code"]:
        raise SystemExit(
            "No authorization code received within 120 s.\n"
            "Make sure port 8888 is free and the redirect URI is correct."
        )

    r = requests.post(
        TOKEN_URL,
        data={
            "grant_type":   "authorization_code",
            "code":         _auth["code"],
            "redirect_uri": redirect_uri,
            "client_id":    client_id,
            "client_secret": client_secret,
        },
        timeout=20,
    )
    r.raise_for_status()
    data = r.json()

    if "refresh_token" not in data:
        raise SystemExit(
            "Spotify did not return a refresh_token. "
            "Check app scopes and redirect URI."
        )

    # Embed credentials so the Pi can refresh without a separate .env file.
    data["client_id"]     = client_id
    data["client_secret"] = client_secret
    save_token(data)
    return data["access_token"]
