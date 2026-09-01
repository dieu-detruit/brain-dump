"""Resolve the daemon's configuration.

Sources, in priority order: process environment vars, then
`~/.config/brain-dump/env`. The (rotating) refresh token lives in
`~/.config/brain-dump/refresh_token` (0600, managed by the SDK) unless
BRAIN_DUMP_REFRESH_TOKEN is set.
"""
from __future__ import annotations

import os
import pathlib

from brain_dump_sdk import auth as sdk_auth
from brain_dump_sdk import BrainDumpClient

CONFIG_DIR = pathlib.Path.home() / ".config" / "brain-dump"
ENV_FILE = CONFIG_DIR / "env"

_env_file_cache: dict[str, str] | None = None


def env_file_values(path: pathlib.Path = ENV_FILE) -> dict[str, str]:
    global _env_file_cache
    if _env_file_cache is None:
        values: dict[str, str] = {}
        if path.exists():
            for line in path.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, value = line.partition("=")
                values[key.strip()] = value.strip().strip('"').strip("'")
        _env_file_cache = values
    return _env_file_cache


def get(name: str, default: str = "") -> str:
    return os.environ.get(name, "").strip() or env_file_values().get(name, default)


def token_path() -> pathlib.Path:
    """Where the rotating refresh token is persisted (managed by the SDK)."""
    explicit = get("BRAIN_DUMP_TOKEN_FILE")
    return pathlib.Path(explicit).expanduser() if explicit else CONFIG_DIR / "refresh_token"


class BridgeConfig:
    """Everything the daemon needs to reach Brain Dump."""

    def __init__(self, *, url: str, anon_key: str, port: int = 8877,
                 refresh_token: str = "", token_file: str = "") -> None:
        self.url = url
        self.anon_key = anon_key
        self.port = port
        self.refresh_token = refresh_token
        self.token_file = token_file or str(token_path())

    @classmethod
    def load(cls) -> "BridgeConfig":
        url = get("BRAIN_DUMP_URL")
        anon = get("BRAIN_DUMP_ANON_KEY")
        port = int(get("BRAIN_DUMP_BRIDGE_PORT", "8877"))
        explicit_file = get("BRAIN_DUMP_TOKEN_FILE")
        token_file = explicit_file or str(token_path())
        refresh = get("BRAIN_DUMP_REFRESH_TOKEN")
        if not refresh:
            # `auth-login` persisted it on disk; fall back to that.
            refresh = sdk_auth.load_refresh_token(token_file) or ""
        return cls(url=url, anon_key=anon, port=port,
                   refresh_token=refresh, token_file=token_file)

    def new_client(self) -> BrainDumpClient:
        return BrainDumpClient(
            url=self.url,
            anon_key=self.anon_key,
            refresh_token=self.refresh_token,
            token_file=self.token_file,
        )
