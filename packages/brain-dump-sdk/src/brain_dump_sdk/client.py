from __future__ import annotations

import os

import httpx

from .exceptions import BrainDumpAPIError, BrainDumpConfigurationError
from .models import Delegation, Thread


class BrainDumpClient:
    """Synchronous client for the Brain Dump Supabase API."""

    def __init__(
        self,
        *,
        url: str,
        anon_key: str,
        access_token: str,
        timeout: float = 10.0,
        http_client: httpx.Client | None = None,
    ) -> None:
        if not url.strip():
            raise BrainDumpConfigurationError("url is required")
        if not anon_key.strip():
            raise BrainDumpConfigurationError("anon_key is required")
        if not access_token.strip():
            raise BrainDumpConfigurationError("access_token is required")
        self._owns_http_client = http_client is None
        self._http = http_client or httpx.Client(timeout=timeout)
        self._rpc_url = f"{url.rstrip('/')}/rest/v1/rpc/add_thread"
        self._headers = {
            "apikey": anon_key,
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
        }

    @classmethod
    def from_env(cls, *, timeout: float = 10.0) -> BrainDumpClient:
        names = (
            "BRAIN_DUMP_URL",
            "BRAIN_DUMP_ANON_KEY",
            "BRAIN_DUMP_ACCESS_TOKEN",
        )
        values = {name: os.environ.get(name, "") for name in names}
        missing = [name for name, value in values.items() if not value]
        if missing:
            raise BrainDumpConfigurationError(
                "Missing environment variables: " + ", ".join(missing)
            )
        return cls(
            url=values["BRAIN_DUMP_URL"],
            anon_key=values["BRAIN_DUMP_ANON_KEY"],
            access_token=values["BRAIN_DUMP_ACCESS_TOKEN"],
            timeout=timeout,
        )

    def add_thread(self, title: str, *, delegation: Delegation = None) -> Thread:
        normalized_title = title.strip()
        if not normalized_title:
            raise ValueError("title must not be empty")
        if len(normalized_title) > 500:
            raise ValueError("title must be at most 500 characters")
        if delegation not in (None, "ai", "colleague"):
            raise ValueError("delegation must be 'ai', 'colleague', or None")
        try:
            response = self._http.post(
                self._rpc_url,
                headers=self._headers,
                json={"thread_title": normalized_title, "assigned_to": delegation},
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
