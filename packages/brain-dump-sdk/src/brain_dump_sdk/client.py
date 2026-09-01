from __future__ import annotations

import os
import pathlib

import httpx

from . import auth
from .exceptions import BrainDumpAPIError, BrainDumpConfigurationError
from .models import Delegation, Thread


class BrainDumpClient:
    """Synchronous client for the Brain Dump Supabase API.

    Give it `access_token` (a fresh user JWT), or `refresh_token` (headless mode:
    a fresh access token is obtained automatically, and a 401 triggers a refresh
    + retry so long-running processes never re-login).
    """

    def __init__(
        self,
        *,
        url: str,
        anon_key: str,
        access_token: str = "",
        refresh_token: str | None = None,
        token_file: str | os.PathLike | None = None,
        timeout: float = 10.0,
        http_client: httpx.Client | None = None,
    ) -> None:
        if not url.strip():
            raise BrainDumpConfigurationError("url is required")
        if not anon_key.strip():
            raise BrainDumpConfigurationError("anon_key is required")
        if not access_token.strip() and not refresh_token:
            raise BrainDumpConfigurationError(
                "access_token or refresh_token is required"
            )
        self._url = url.rstrip("/")
        self._anon_key = anon_key
        self._owns_http_client = http_client is None
        self._http = http_client or httpx.Client(timeout=timeout)
        self._rpc_url = f"{self._url}/rest/v1/rpc/add_thread"
        self._refresh_token = refresh_token
        self._token_file = pathlib.Path(token_file).expanduser() if token_file else None
        self._access_token = access_token
        if not self._access_token and refresh_token:
            self._reauthenticate()  # bootstrap headless mode
        self._set_headers()

    @classmethod
    def from_env(cls, *, timeout: float = 10.0) -> BrainDumpClient:
        names = (
            "BRAIN_DUMP_URL",
            "BRAIN_DUMP_ANON_KEY",
            "BRAIN_DUMP_ACCESS_TOKEN",
            "BRAIN_DUMP_REFRESH_TOKEN",
            "BRAIN_DUMP_TOKEN_FILE",
        )
        values = {name: os.environ.get(name, "") for name in names}
        missing = [
            name for name in ("BRAIN_DUMP_URL", "BRAIN_DUMP_ANON_KEY") if not values[name]
        ]
        if not values["BRAIN_DUMP_ACCESS_TOKEN"] and not values["BRAIN_DUMP_REFRESH_TOKEN"]:
            missing.append("BRAIN_DUMP_ACCESS_TOKEN or BRAIN_DUMP_REFRESH_TOKEN")
        if missing:
            raise BrainDumpConfigurationError(
                "Missing environment variables: " + ", ".join(missing)
            )
        return cls(
            url=values["BRAIN_DUMP_URL"],
            anon_key=values["BRAIN_DUMP_ANON_KEY"],
            access_token=values["BRAIN_DUMP_ACCESS_TOKEN"],
            refresh_token=values["BRAIN_DUMP_REFRESH_TOKEN"] or None,
            token_file=values["BRAIN_DUMP_TOKEN_FILE"] or None,
            timeout=timeout,
        )

    def _set_headers(self) -> None:
        self._headers = {
            "apikey": self._anon_key,
            "Authorization": f"Bearer {self._access_token}",
            "Content-Type": "application/json",
        }

    def _reauthenticate(self) -> None:
        """Refresh the access token (and persist the rotated refresh token)."""
        if not self._refresh_token:
            raise BrainDumpAPIError(
                "no refresh token available to re-authenticate", status_code=401
            )
        session = auth.refresh(
            self._url, self._anon_key, self._refresh_token, http_client=self._http
        )
        self._access_token = session.access_token
        if session.refresh_token:
            self._refresh_token = session.refresh_token
            if self._token_file:
                auth.save_refresh_token(session.refresh_token, self._token_file)
        self._set_headers()

    def add_thread(self, title: str, *, delegation: Delegation = None) -> Thread:
        normalized_title = title.strip()
        if not normalized_title:
            raise ValueError("title must not be empty")
        if len(normalized_title) > 500:
            raise ValueError("title must be at most 500 characters")
        if delegation not in (None, "ai", "colleague"):
            raise ValueError("delegation must be 'ai', 'colleague', or None")
        try:
            return self._add_thread_attempt(normalized_title, delegation)
        except BrainDumpAPIError as error:
            if error.status_code == 401 and self._refresh_token:
                self._reauthenticate()  # access token expired → retry once
                return self._add_thread_attempt(normalized_title, delegation)
            raise

    def _add_thread_attempt(self, title: str, delegation: Delegation) -> Thread:
        try:
            response = self._http.post(
                self._rpc_url,
                headers=self._headers,
                json={"thread_title": title, "assigned_to": delegation},
            )
        except httpx.HTTPError as error:
            raise BrainDumpAPIError(
                f"Could not connect to Brain Dump: {error}"
            ) from error
        if response.is_error:
            raise BrainDumpAPIError(
                _error_message(response), status_code=response.status_code
            )
        try:
            return Thread.from_response(response.json())
        except (KeyError, TypeError, ValueError) as error:
            raise BrainDumpAPIError("Brain Dump returned an invalid response") from error

    def close(self) -> None:
        if self._owns_http_client:
            self._http.close()

    def __enter__(self) -> BrainDumpClient:
        return self

    def __exit__(self, *_: object) -> None:
        self.close()


def _error_message(response: httpx.Response) -> str:
    try:
        payload = response.json()
    except ValueError:
        return f"Brain Dump request failed with HTTP {response.status_code}"
    if isinstance(payload, dict):
        for key in ("message", "error_description", "error", "hint"):
            value = payload.get(key)
            if isinstance(value, str) and value:
                return value
    return f"Brain Dump request failed with HTTP {response.status_code}"
