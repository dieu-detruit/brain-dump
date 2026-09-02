import json
import asyncio
import subprocess

from brain_dump_history.archive import Archive, summarize
from brain_dump_history.sync import HistorySync


def test_summarize_completed_and_active_sessions():
    sessions = [
        {"thread_id": "b", "thread_title": "Old", "started_at": "2026-08-30T00:00:00Z", "ended_at": "2026-08-30T00:01:30Z"},
        {"thread_id": "b", "thread_title": "New", "started_at": "2026-08-30T01:00:00Z", "ended_at": None},
    ]
    assert summarize(sessions) == [{
        "thread_id": "b", "latest_title": "New", "completed_seconds": 90,
        "completed_sessions": 1, "active_since": "2026-08-30T01:00:00Z",
    }]


def test_archive_appends_and_tracks_cursor(tmp_path):
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    archive = Archive(tmp_path)
    archive.prepare()
    assert archive.append("change-log.jsonl", [{"id": 1}, {"id": 2}]) == 2
    assert archive.last_id("change-log.jsonl") == 2
    assert [json.loads(line) for line in (tmp_path / "data/change-log.jsonl").read_text().splitlines()] == [{"id": 1}, {"id": 2}]


def test_sync_rewrites_session_when_it_ends(tmp_path):
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    archive = Archive(tmp_path)
    sync = HistorySync(archive, url="https://example.test", anon_key="key", access_token="token")
    ended_at = None

    async def fetch(table, **_kwargs):
        if table == "change_log":
            return []
        return [{
            "id": 1, "thread_id": "thread", "thread_title": "Work",
            "started_at": "2026-08-30T00:00:00Z", "ended_at": ended_at,
        }]

    async def fetch_threads():
        return []

    sync.fetch = fetch
    sync.fetch_threads = fetch_threads

    async def scenario():
        nonlocal ended_at
        await sync.run(commit=False)
        ended_at = "2026-08-30T00:02:00Z"
        await sync.run(commit=False)
        await sync.close()

    asyncio.run(scenario())
    summary = json.loads((tmp_path / "data/time-summary.json").read_text())
    assert summary[0]["completed_seconds"] == 120
    assert summary[0]["active_since"] is None
