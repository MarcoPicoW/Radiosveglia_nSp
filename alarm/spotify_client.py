"""
Radiosveglia_nSp — Spotify OAuth client.

Handles the Spotify Web API authentication flow:
  - First-time login with browser (used once on the user's PC)
  - Token persistence to spotify_token.json
  - Automatic refresh of access tokens (used on the headless Pi)

Environment file expected: spotify.env in the same directory.
Required variables:
  CLIENT_ID
  CLIENT_SECRET
  REDIRECT_URI       (typically http://127.0.0.1:8888/callback)
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
from dotenv import load_dotenv

# -----------------------------------------------------------------------------
# Config / Paths
# -----------------------------------------------------------------------------
BASE_DIR = Path(__file__).parent
ENV_PATH = BASE_DIR / "spotify.env"
TOKEN_PATH = BASE_DIR / "spotify_token.json"

AUTH_URL = "https://accounts.spotify.com/authorize"
TOKEN_URL = "https://accounts.spotify.com/api/token"
NOW_PLAYING_URL = "https://api.spotify.com/v1/me/player/currently-playing"

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

# -----------------------------------------------------------------------------
# Load env (robust)
# -----------------------------------------------------------------------------
load_dotenv(ENV_PATH)

CLIENT_ID = os.getenv("CLIENT_ID")
CLIENT_SECRET = os.getenv("CLIENT_SECRET")
REDIRECT_URI = os.getenv("REDIRECT_URI")

if not CLIENT_ID or not CLIENT_SECRET or not REDIRECT_URI:
    raise SystemExit(
        f"spotify.env not loaded or incomplete (looking at {ENV_PATH}). "
        "Required keys: CLIENT_ID, CLIENT_SECRET, REDIRECT_URI."
    )


# -----------------------------------------------------------------------------
# Token persistence
# -----------------------------------------------------------------------------

def save_token(data: dict) -> None:
    """Persist a token dict, computing absolute expires_at timestamp."""
    data["expires_at"] = int(time.time()) + int(data.get("expires_in", 3600))
    TOKEN_PATH.write_text(json.dumps(data, indent=2))


def load_token() -> dict | None:
    """Load the persisted token dict, or None if no file exists."""
    if TOKEN_PATH.exists():
        return json.loads(TOKEN_PATH.read_text())
    return None


def token_expired(token: dict) -> bool:
    """Returns True if the access token is expired (or will expire in <60s)."""
    return int(token.get("expires_at", 0)) - 60 < time.time()


def refresh_access_token(client_id: str, client_secret: str, refresh_token: str) -> str:
    """Exchange a refresh_token for a new access_token. Persists the result."""
    r = requests.post(
        TOKEN_URL,
        data={
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
            "client_id": client_id,
            "client_secret": client_secret,
        },
        timeout=20,
    )
    r.raise_for_status()
    data = r.json()

    # Spotify may omit refresh_token in the response — keep the existing one.
    data["refresh_token"] = refresh_token
    save_token(data)
    return data["access_token"]


def get_access_token(client_id: str, client_secret: str) -> str:
    """Return a valid access token, refreshing if necessary."""
    token = load_token()
    if not token:
        raise RuntimeError(
            "No spotify_token.json found — run the initial browser login once."
        )

    if token_expired(token):
        if "refresh_token" not in token:
            raise RuntimeError(
                "spotify_token.json missing refresh_token — run initial login again."
            )
        return refresh_access_token(client_id, client_secret, token["refresh_token"])

    return token["access_token"]


def get_access_token_no_browser() -> str:
    """
    Return a valid access token without ever opening a browser.
    Used on the headless Pi.
    """
    token = load_token()
    if not token:
        raise RuntimeError(
            "No spotify_token.json — initial browser login required (on a PC)."
        )

    if "refresh_token" not in token:
        raise RuntimeError(
            "spotify_token.json missing refresh_token — re-run initial login."
        )

    if token_expired(token):
        return refresh_access_token(CLIENT_ID, CLIENT_SECRET, token["refresh_token"])

    return token["access_token"]


# -----------------------------------------------------------------------------
# OAuth callback mini-server
# -----------------------------------------------------------------------------
auth_code_holder: dict[str, str | None] = {"code": None, "error": None}


class CallbackHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path != "/callback":
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not found")
            return

        qs = parse_qs(parsed.query)
        if "error" in qs:
            auth_code_holder["error"] = qs["error"][0]
        if "code" in qs:
            auth_code_holder["code"] = qs["code"][0]

        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(b"<h2>OK. You can close this window.</h2>")

    def log_message(self, format, *args):
        return  # silence the default access log


def _start_server() -> None:
    """Run a tiny HTTP server until the OAuth callback arrives (or errors)."""
    server = HTTPServer(("127.0.0.1", 8888), CallbackHandler)
    server.timeout = 1
    while auth_code_holder["code"] is None and auth_code_holder["error"] is None:
        server.handle_request()


# -----------------------------------------------------------------------------
# First-time login (browser)
# -----------------------------------------------------------------------------

def get_access_token_first_time_with_browser() -> str:
    """
    Run the full OAuth Authorization Code flow. Opens a browser, waits for the
    user to authorize, captures the code on http://127.0.0.1:8888/callback,
    and exchanges it for tokens. Persists everything in spotify_token.json.
    """
    auth_link = (
        f"{AUTH_URL}?response_type=code"
        f"&client_id={CLIENT_ID}"
        f"&scope={SCOPES}"
        f"&redirect_uri={REDIRECT_URI}"
    )

    print("Opening browser to authorize Spotify:")
    print(auth_link)

    t = threading.Thread(target=_start_server, daemon=True)
    t.start()

    webbrowser.open(auth_link)

    # Wait up to 120s for the callback
    for _ in range(120):
        if auth_code_holder["error"]:
            raise SystemExit(f"Spotify Auth error: {auth_code_holder['error']}")
        if auth_code_holder["code"]:
            break
        time.sleep(1)

    code = auth_code_holder["code"]
    if not code:
        raise SystemExit(
            "No authorization code received. "
            "Check REDIRECT_URI and that port 8888 is free."
        )

    r = requests.post(
        TOKEN_URL,
        data={
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": REDIRECT_URI,
            "client_id": CLIENT_ID,
            "client_secret": CLIENT_SECRET,
        },
        timeout=20,
    )
    r.raise_for_status()

    data = r.json()
    save_token(data)  # this MUST contain refresh_token

    return data["access_token"]
