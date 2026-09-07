from __future__ import annotations

import asyncio
from pathlib import Path
from datetime import datetime, timezone
from typing import Any

import httpx

from . import env
from .archive import Archive


class HistorySync:
    def __init__(self, archive: Archive, *, url: str, anon_key: str, access_token: str) -> None:
        self.archive = archive
        self.base_url = url.rstrip("/")
        self.headers = {"apikey": anon_key, "Authorization": f"Bearer {access_token}"}
        self.http = httpx.AsyncClient(timeout=30)
        self.lock = asyncio.Lock()

    async def close(self) -> None:
        await self.http.aclose()

    def set_access_token(self, token: str) -> None:
        self.headers["Authorization"] = f"Bearer {token}"

    async def fetch(self, table: str, *, after_id: int = 0, order: str = "id.asc") -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        offset = 0
        while True:
            response = await self.http.get(
                f"{self.base_url}/rest/v1/{table}",
                headers=self.headers,
                params={"select": "*", "id": f"gt.{after_id}", "order": order, "offset": offset, "limit": 1000},
            )
            if response.status_code == 404:
                raise RuntimeError(
                    f"Supabase table {table!r} was not found; apply the Brain Dump migrations first"
                )
            response.raise_for_status()
            page = response.json()
            rows.extend(page)
            if len(page) < 1000:
                return rows
            offset += 1000

    async def fetch_threads(self) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        offset = 0
        while True:
            response = await self.http.get(
                f"{self.base_url}/rest/v1/threads",
                headers=self.headers,
                params={
                    "select": "*", "order": "created_at.asc,id.asc",
                    "offset": offset, "limit": 1000,
                },
            )
            response.raise_for_status()
            page = response.json()
            rows.extend(page)
            if len(page) < 1000:
                return rows
            offset += 1000

    async def run(self, *, commit: bool = True) -> int:
        async with self.lock:
            self.archive.prepare()
            changes = await self.fetch("change_log", after_id=self.archive.last_id("change-log.jsonl"))
            # A session is inserted when work starts and updated when it ends.
            # Refresh this materialized view so ended_at updates are not missed.
            sessions = await self.fetch("execution_sessions")
            count = self.archive.append("change-log.jsonl", changes)
            sessions_changed = self.archive.write_jsonl("execution-sessions.jsonl", sessions)
            if count or sessions_changed or not (self.archive.data / "threads.json").exists():
                self.archive.write_json("threads.json", await self.fetch_threads())
                self.archive.update_metrics()
                if commit:
                    stamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
                    self.archive.commit(f"history: sync {stamp}")
            return count + int(sessions_changed)


def required_env(token_file_override: Path | None = None) -> tuple[str, str, str, str | None]:
    url = env.get("BRAIN_DUMP_URL")
    key = env.get("BRAIN_DUMP_ANON_KEY")
    access = env.get("BRAIN_DUMP_ACCESS_TOKEN")
    refresh = env.get("BRAIN_DUMP_REFRESH_TOKEN") or None
    token_file = str(token_file_override) if token_file_override else env.get("BRAIN_DUMP_TOKEN_FILE")
    if not refresh and token_file:
        path = Path(token_file).expanduser()
        if path.exists():
            refresh = path.read_text(encoding="utf-8").strip() or None
    if not url or not key or (not access and not refresh):
        raise ValueError(
            "BRAIN_DUMP_URL, BRAIN_DUMP_ANON_KEY, and BRAIN_DUMP_ACCESS_TOKEN "
            "or BRAIN_DUMP_REFRESH_TOKEN are required"
        )
    return url, key, access, refresh
