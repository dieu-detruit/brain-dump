"""Env-file resolution for local CLI use (mirrors brain-dump-bridge's config).

The systemd units load `~/.config/brain-dump/env` via `EnvironmentFile=`, so a
daemon sees `BRAIN_DUMP_URL` / `BRAIN_DUMP_ANON_KEY` without help. A one-off CLI
run (`login`, manual `sync`) from a plain shell does not, so these helpers give
an `os.getenv`-style lookup that falls back to the env file.
"""
from __future__ import annotations

import os
from pathlib import Path

CONFIG_DIR = Path.home() / ".config" / "brain-dump"
ENV_FILE = CONFIG_DIR / "env"


def env_values(path: Path | None = None) -> dict[str, str]:
    """Parse KEY=VALUE lines from an env file (systemd EnvironmentFile format).

    Process environment is NOT consulted here; see :func:`get` for the lookup
    that prefers the process env.
    """
    p = path or ENV_FILE
    values: dict[str, str] = {}
    if not p.exists():
        return values
    for line in p.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        if not key:  # a bare "=" line is malformed, not an empty var
            continue
        values[key] = value.strip().strip('"').strip("'")
    return values


def get(name: str, default: str = "", *, env_file: Path | None = None) -> str:
    """Look up ``name`` in the process env first, then the env file."""
    value = os.environ.get(name, "").strip()
    if value:
        return value
    return env_values(env_file).get(name, default)
