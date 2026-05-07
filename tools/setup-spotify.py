#!/usr/bin/env python3
"""
Radiosveglia_nSp -- Spotify one-time setup.

Run this script ONCE on your own computer (not the Pi) to authorize the
Radiosveglia app with your Spotify account. It will:

  1. Ask for your Client ID and Client Secret (from developer.spotify.com).
  2. Open your browser for the Spotify authorization page.
  3. Capture the OAuth callback on http://127.0.0.1:8888/callback.
  4. Save the resulting tokens to spotify_token.json next to this script.

After running, copy spotify_token.json to the Pi:

  Linux / Mac:
    scp spotify_token.json radiosveglia@radiosveglia.local:~/alarm/

  Windows (PowerShell):
    scp spotify_token.json radiosveglia@radiosveglia.local:/home/radiosveglia/alarm/

Requirements:
  pip install requests

Python 3.8 or later required.
"""

import json
import os
import sys
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlparse

try:
    import requests
except ImportError:
    sys.exit(
        "ERROR: 'requests' is not installed.\n"
        "Run:  pip install requests\n"
        "Then re-run this script."
    )

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
AUTH_URL    = "https://accounts.spotify.com/authorize"
TOKEN_URL   = "https://accounts.spotify.com/api/token"
REDIRECT_URI = "http://127.0.0.1:8888/callback"
PORT        = 8888
TIMEOUT_S   = 120   # seconds to wait for the browser callback

SCOPES = " ".join([
    "user-read-playback-state",
    "user-modify-playback-state",
    "user-read-currently-playing",
    "user-library-read",
    "playlist-read-private",
    "playlist-read-collaborative",
    "user-read-private",
    "user-read-email",
])

TOKEN_PATH = Path(__file__).resolve().parent / "spotify_token.json"

# ---------------------------------------------------------------------------
# OAuth callback mini-server
# ---------------------------------------------------------------------------
_callback: dict[str, str | None] = {"code": None, "error": None}


class _CallbackHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path != "/callback":
            self._respond(404, b"Not found")
            return
        qs = parse_qs(parsed.query)
        _callback["error"] = qs.get("error", [None])[0]
        _callback["code"]  = qs.get("code",  [None])[0]
        self._respond(200, b"<h2>Authorization complete. You can close this window.</h2>")

    def _respond(self, status: int, body: bytes):
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):  # silence access log
        return


def _run_server():
    srv = HTTPServer(("127.0.0.1", PORT), _CallbackHandler)
    srv.timeout = 1
    while _callback["code"] is None and _callback["error"] is None:
        srv.handle_request()


# ---------------------------------------------------------------------------
# Token helpers
# ---------------------------------------------------------------------------
def _save_token(data: dict) -> None:
    data["expires_at"] = int(time.time()) + int(data.get("expires_in", 3600))
    TOKEN_PATH.write_text(json.dumps(data, indent=2))
    print(f"\nToken saved to: {TOKEN_PATH}")


# ---------------------------------------------------------------------------
# Main flow
# ---------------------------------------------------------------------------
def _prompt(label: str, secret: bool = False) -> str:
    import getpass
    fn = getpass.getpass if secret else input
    while True:
        value = fn(f"{label}: ").strip()
        if value:
            return value
        print("  (cannot be empty)")


def main() -> int:
    print("=" * 60)
    print("  Radiosveglia_nSp -- Spotify setup")
    print("=" * 60)
    print()
    print("You need a Spotify Developer app with:")
    print(f"  Redirect URI: {REDIRECT_URI}")
    print()
    print("If you haven't created one yet, go to:")
    print("  https://developer.spotify.com/dashboard")
    print()

    client_id     = _prompt("Client ID")
    client_secret = _prompt("Client Secret", secret=True)

    params = {
        "response_type": "code",
        "client_id":     client_id,
        "scope":         SCOPES,
        "redirect_uri":  REDIRECT_URI,
    }
    auth_url = AUTH_URL + "?" + urlencode(params)

    print()
    print("Starting local callback server on port", PORT, "...")
    t = threading.Thread(target=_run_server, daemon=True)
    t.start()

    print("Opening browser for Spotify authorization ...")
    print(f"  {auth_url}")
    webbrowser.open(auth_url)

    print(f"Waiting up to {TIMEOUT_S}s for authorization ...")
    for _ in range(TIMEOUT_S):
        if _callback["error"] or _callback["code"]:
            break
        time.sleep(1)

    if _callback["error"]:
        print(f"\nERROR: Spotify returned: {_callback['error']}")
        return 1

    if not _callback["code"]:
        print("\nERROR: Timed out waiting for authorization.")
        print("Make sure nothing else is using port 8888 and try again.")
        return 1

    print("Authorization received. Exchanging code for tokens ...")
    try:
        r = requests.post(
            TOKEN_URL,
            data={
                "grant_type":   "authorization_code",
                "code":         _callback["code"],
                "redirect_uri": REDIRECT_URI,
                "client_id":    client_id,
                "client_secret": client_secret,
            },
            timeout=20,
        )
        r.raise_for_status()
    except requests.RequestException as e:
        print(f"\nERROR: Token exchange failed: {e}")
        return 1

    data = r.json()
    if "refresh_token" not in data:
        print("\nERROR: Spotify response missing refresh_token.")
        print("Make sure your app has the correct scopes and redirect URI.")
        return 1

    # Also persist client credentials so the Pi can refresh without prompts.
    data["client_id"]     = client_id
    data["client_secret"] = client_secret

    _save_token(data)

    print()
    print("All done! Next step:")
    print()
    print("  scp spotify_token.json radiosveglia@radiosveglia.local:~/alarm/")
    print()
    print("Then test on the Pi:")
    print()
    print("  ssh radiosveglia@radiosveglia.local")
    print("  systemctl --user start alarm.service")
    print("  journalctl --user -u alarm.service -n 20")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
