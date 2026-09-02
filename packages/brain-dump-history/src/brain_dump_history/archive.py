from __future__ import annotations

import json
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable


def parse_time(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def summarize(sessions: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    totals: dict[str, dict[str, Any]] = {}
    for session in sessions:
        thread_id = session["thread_id"]
        total = totals.setdefault(
            thread_id,
            {
                "thread_id": thread_id,
                "latest_title": session["thread_title"],
                "completed_seconds": 0,
                "completed_sessions": 0,
                "active_since": None,
            },
        )
        total["latest_title"] = session["thread_title"]
        if session.get("ended_at"):
            elapsed = round(
                (parse_time(session["ended_at"]) - parse_time(session["started_at"])).total_seconds()
            )
            total["completed_seconds"] += max(0, elapsed)
            total["completed_sessions"] += 1
            total["active_since"] = None
        else:
            total["active_since"] = session["started_at"]
    return [totals[key] for key in sorted(totals)]


class Archive:
    """Files owned by the history repository; no program source lives there."""

    def __init__(self, repository: Path) -> None:
        self.repository = repository.resolve()
        self.data = self.repository / "data"

    def prepare(self) -> None:
        if not (self.repository / ".git").exists():
            raise ValueError(f"not a Git repository: {self.repository}")
        self.data.mkdir(parents=True, exist_ok=True)

    def rows(self, name: str) -> list[dict[str, Any]]:
        path = self.data / name
        if not path.exists():
            return []
        return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]

    def last_id(self, name: str) -> int:
        rows = self.rows(name)
        return int(rows[-1]["id"]) if rows else 0

    def append(self, name: str, rows: Iterable[dict[str, Any]]) -> int:
        new_rows = list(rows)
        if not new_rows:
            return 0
        path = self.data / name
        with path.open("a", encoding="utf-8") as output:
            for row in new_rows:
                output.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
        return len(new_rows)

    def write_json(self, name: str, value: Any) -> None:
        path = self.data / name
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary.replace(path)

    def write_jsonl(self, name: str, rows: Iterable[dict[str, Any]]) -> bool:
        path = self.data / name
        content = "".join(
            json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n"
            for row in rows
        )
        previous = path.read_text(encoding="utf-8") if path.exists() else None
        if content == previous:
            return False
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_text(content, encoding="utf-8")
        temporary.replace(path)
        return True

    def update_metrics(self) -> None:
        self.write_json("time-summary.json", summarize(self.rows("execution-sessions.jsonl")))

    def commit(self, message: str) -> bool:
        subprocess.run(["git", "add", "data"], cwd=self.repository, check=True)
        changed = subprocess.run(
            ["git", "diff", "--cached", "--quiet"], cwd=self.repository, check=False
        ).returncode != 0
        if changed:
            subprocess.run(["git", "commit", "-m", message], cwd=self.repository, check=True)
        return changed
