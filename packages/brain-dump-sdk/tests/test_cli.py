import json

from brain_dump_sdk.cli import run
from brain_dump_sdk.models import Thread


def test_cli_prints_json(monkeypatch, capsys) -> None:
    class FakeClient:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def add_thread(self, title, *, delegation=None):
            return Thread.from_response(
                {
                    "id": "thread-id",
                    "title": title,
                    "delegation": delegation,
                    "created_at": "2026-08-30T10:00:00Z",
                    "updated_at": "2026-08-30T10:00:00Z",
                }
            )

    monkeypatch.setattr(
        "brain_dump_sdk.cli.BrainDumpClient.from_env", lambda: FakeClient()
    )
    result = run(["thread", "add", "--title", "SDK task", "--json"])
    assert result == 0
    assert json.loads(capsys.readouterr().out)["title"] == "SDK task"
