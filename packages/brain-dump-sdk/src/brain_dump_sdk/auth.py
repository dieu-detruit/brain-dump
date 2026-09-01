"""GoTrue (Supabase) authentication: one-time PKCE login + token refresh.

Brain Dump authenticates users with Supabase (Google provider). External code
inserts threads as the logged-in user through the `add_thread` RPC, which
requires that user's JWT. JWTs expire (~1h); the SDK keeps a long-lived *refresh*
token and refreshes automatically, so a persistent process never needs to
re-login.

Login is interactive ONCE (opens a browser with PKCE, no client secret needed).
After that everything here is headless.

Requires in Supabase (Auth settings):
  - "PKCE flow" enabled, and
  - `http://127.0.0.1:<redirect_port>/callback` in
    Authentication → URL Configuration → Redirect URLs.
"""
from __future__ import annotations

import base64
import dataclasses
import hashlib
import http.server
import os
import pathlib
import secrets
import socketserver
import urllib.parse
import urllib.request

import httpx

from .exceptions import BrainDumpAPIError, BrainDumpConfigurationError

DEFAULT_TOKEN_DIR = pathlib.Path.home() / ".config" / "brain-dump"


@dataclasses.dataclass(frozen=True, slots=True)
class AuthSession:
    access_token: str
    refresh_token: str
    expires_in: int
    user_id: str = ""
    email: str = ""


def default_token_path() -> pathlib.Path:
    return DEFAULT_TOKEN_DIR / "refresh_token"


def token_path(path: str | os.PathLike | None) -> pathlib.Path:
    return pathlib.Path(path).expanduser() if path else default_token_path()


def save_refresh_token(
    token: str, path: str | os.PathLike | None = None
) -> pathlib.Path:
    """Persist the (rotating) refresh token, 0600, for headless reuse."""
    p = token_path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(token + "\n", encoding="utf-8")
    os.chmod(p, 0o600)
    return p


def load_refresh_token(path: str | os.PathLike | None = None) -> str | None:
    p = token_path(path)
    if not p.exists():
        return None
    try:
        return p.read_text(encoding="utf-8").strip() or None
    except OSError:
        return None


def _gotrue_call(
    url: str, anon_key: str, path: str, body: dict,
    http_client: httpx.Client | None = None, owns_http: bool = True,
) -> dict:
    http = http_client or httpx.Client(timeout=30)
    try:
        response = http.post(
            f"{url.rstrip('/')}{path}",
            headers={"apikey": anon_key, "Content-Type": "application/json"},
            json=body,
        )
    finally:
        if owns_http:
            http.close()
    if response.is_error:
        raise BrainDumpAPIError(
            f"GoTrue {path} failed: HTTP {response.status_code} "
            f"{response.text[:300]}",
            status_code=response.status_code,
        )
    return response.json()


def _parse_session(body: dict) -> AuthSession:
    if "access_token" not in body:
        raise BrainDumpAPIError("GoTrue returned no access_token")
    user = body.get("user") or {}
    return AuthSession(
        access_token=str(body["access_token"]),
        refresh_token=str(body.get("refresh_token", "")),
        expires_in=int(body.get("expires_in", 3600)),
        user_id=str(user.get("id") or ""),
        email=str(user.get("email") or ""),
    )


def refresh(
    url: str,
    anon_key: str,
    refresh_token: str,
    *,
    http_client: httpx.Client | None = None,
) -> AuthSession:
    """Exchange a refresh token for a fresh access token (token rotates)."""
    body = _gotrue_call(
        url, anon_key, "/auth/v1/token?grant_type=refresh_token",
        {"refresh_token": refresh_token},
        http_client=http_client, owns_http=http_client is None,
    )
    return _parse_session(body)


# --- one-time interactive login (PKCE) -----------------------------------------

def _new_code_verifier() -> str:
    return base64.urlsafe_b64encode(secrets.token_bytes(48)).rstrip(b"=").decode()


def _code_challenge(verifier: str) -> str:
    digest = hashlib.sha256(verifier.encode()).digest()
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode()


def login(
    url: str,
    anon_key: str,
    *,
    redirect_port: int = 8881,
    open_browser: bool = True,
) -> str:
    """Interactive one-time Google login. Returns the refresh token — the caller
    persists it (see save_refresh_token) and everything after this is headless."""
    verifier = _new_code_verifier()
    challenge = _code_challenge(verifier)
    redirect_to = f"http://127.0.0.1:{redirect_port}/callback"

    caught: dict[str, str] = {}

    class Callback(http.server.BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802
            qs = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            caught.update({k: v[0] for k, v in qs.items()})
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(
                b"<h1>Brain Dump login ok</h1><p>Close this tab and return to "
                b"the terminal.</p>"
            )

        def log_message(self, *_: object) -> None:  # keep the terminal quiet
            pass

    class ReusableTCPServer(socketserver.TCPServer):
        allow_reuse_address = True

    authorize_url = (
        f"{url.rstrip('/')}/auth/v1/authorize"
        f"?provider=google"
        f"&response_type=code"
        f"&redirect_to={urllib.parse.quote(redirect_to, safe='')}"
        f"&code_challenge_method=S256"
        f"&code_challenge={challenge}"
    )
    print(f"Open this URL (browser should open automatically):\n  {authorize_url}")
    if open_browser:
        import webbrowser

        webbrowser.open(authorize_url)

    with ReusableTCPServer(("127.0.0.1", redirect_port), Callback) as httpd:
        httpd.timeout = 0.2
        for _ in range(300):  # up to ~60s
            httpd.handle_request()
            if caught.get("code"):
                break
    if not caught.get("code"):
        raise BrainDumpAPIError(
            "login timed out waiting for the auth code; is the redirect URL "
            f"http://127.0.0.1:{redirect_port}/callback registered in Supabase, "
            "and is PKCE flow enabled?",
            status_code=None,
        )

    session = _parse_session(
        _gotrue_call(
            url, anon_key, "/auth/v1/token?grant_type=pkce",
            {"auth_code": caught["code"], "code_verifier": verifier},
        )
    )
    if not session.refresh_token:
        raise BrainDumpAPIError("login returned no refresh token")
    return session.refresh_token
