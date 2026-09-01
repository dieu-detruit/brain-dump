from datetime import datetime
import json

import httpx
import pytest

from brain_dump_sdk import BrainDumpAPIError, BrainDumpClient


def response_payload() -> dict[str, str | None]:
    return {
        "id": "8c12df30-b2e6-4cc0-9df8-067dea92f89b",
        "title": "Write the release notes",
        "delegation": "ai",
        "created_at": "2026-08-30T10:00:00Z",
        "updated_at": "2026-08-30T10:00:00Z",
    }


def test_add_thread_calls_rpc_and_parses_thread() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert str(request.url) == (
            "https://example.supabase.co/rest/v1/rpc/add_thread"
        )
        assert request.headers["apikey"] == "anon"
        assert request.headers["authorization"] == "Bearer token"
        assert json.loads(request.read()) == {
            "thread_title": "Write the release notes",
            "assigned_to": "ai",
        }
        return httpx.Response(200, json=response_payload())

    http = httpx.Client(transport=httpx.MockTransport(handler))
    client = BrainDumpClient(
        url="https://example.supabase.co/",
        anon_key="anon",
        access_token="token",
        http_client=http,
    )
    thread = client.add_thread("  Write the release notes  ", delegation="ai")
    assert thread.title == "Write the release notes"
    assert thread.created_at == datetime.fromisoformat("2026-08-30T10:00:00+00:00")


def test_add_thread_exposes_api_error() -> None:
    transport = httpx.MockTransport(
        lambda request: httpx.Response(401, json={"message": "JWT expired"})
    )
    client = BrainDumpClient(
        url="https://example.supabase.co",
        anon_key="anon",
        access_token="token",
        http_client=httpx.Client(transport=transport),
    )
    with pytest.raises(BrainDumpAPIError, match="JWT expired") as raised:
        client.add_thread("A thread")
    assert raised.value.status_code == 401


@pytest.mark.parametrize("title", ["", "   ", "x" * 501])
def test_add_thread_rejects_invalid_title(title: str) -> None:
    client = BrainDumpClient(
        url="https://example.supabase.co",
        anon_key="anon",
        access_token="token",
        http_client=httpx.Client(),
    )
    with pytest.raises(ValueError):
        client.add_thread(title)


def test_add_thread_401_refreshes_token_and_retries(tmp_path) -> None:
    seen: list[str] = []
    token_file = tmp_path / "refresh_token"

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request.url.path)
        if request.url.path == "/auth/v1/token":
            assert json.loads(request.read()) == {"refresh_token": "rt"}
            return httpx.Response(
                200,
                json={
                    "access_token": "fresh-token",
                    "refresh_token": "rotated-token",
                    "expires_in": 3600,
                    "token_type": "bearer",
                    "user": {"id": "u1"},
                },
            )
        # add_thread: first call 401, the retry succeeds with the fresh token
        if seen.count("/rest/v1/rpc/add_thread") == 1:
            return httpx.Response(401, json={"message": "JWT expired"})
        assert request.headers["authorization"] == "Bearer fresh-token"
        return httpx.Response(200, json=response_payload())

    http = httpx.Client(transport=httpx.MockTransport(handler))
    client = BrainDumpClient(
        url="https://example.supabase.co",
        anon_key="anon",
        access_token="expired",
        refresh_token="rt",
        token_file=token_file,
        http_client=http,
    )
    thread = client.add_thread("A thread")
    assert thread.title == "Write the release notes"
    assert seen == [
        "/rest/v1/rpc/add_thread",
        "/auth/v1/token",
        "/rest/v1/rpc/add_thread",
    ]
    assert token_file.read_text().strip() == "rotated-token"
