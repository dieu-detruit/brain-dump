import json
import threading

import httpx

from brain_dump_bridge.server import Bridge, BridgeConfig, make_server


class _FakeBridge(Bridge):
    """Bridge whose client calls the SDK against a MockTransport (no network)."""

    def __init__(self, transport: httpx.MockTransport) -> None:
        super().__init__(BridgeConfig(url="https://example.supabase.co",
                                      anon_key="anon", refresh_token="rt"))
        self._http = httpx.Client(transport=transport)
        sdk = __import__("brain_dump_sdk").BrainDumpClient(
            url="https://example.supabase.co",
            anon_key="anon",
            access_token="expired",
            refresh_token="rt",
            http_client=self._http,
        )
        self._client = sdk

    def close(self) -> None:
        self._http.close()


def _start(transport: httpx.MockTransport):
    bridge = _FakeBridge(transport)
    server = make_server(bridge, port=0)  # ephemeral port
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, f"http://127.0.0.1:{port}"


def _thread_payload() -> dict:
    return {
        "id": "t-1",
        "title": "Write the release notes",
        "delegation": None,
        "created_at": "2026-08-30T10:00:00Z",
        "updated_at": "2026-08-30T10:00:00Z",
    }


def test_post_items_creates_thread() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/auth/v1/token":
            return httpx.Response(200, json={
                "access_token": "fresh", "refresh_token": "rt2",
                "expires_in": 3600, "token_type": "bearer",
                "user": {"id": "u1"}})
        return httpx.Response(200, json=_thread_payload())

    server, url = _start(httpx.MockTransport(handler))
    try:
        with httpx.Client() as http:
            response = http.post(f"{url}/items", json={"title": "Write the release notes"})
            assert response.status_code == 202
            assert response.json()["ok"] is True
            assert response.json()["id"] == "t-1"
            assert http.get(f"{url}/health").json()["ok"] is True
    finally:
        server.shutdown()


def test_post_items_passes_delegation_through() -> None:
    rpc_bodies = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/auth/v1/token":
            return httpx.Response(200, json={
                "access_token": "fresh", "refresh_token": "rt2",
                "expires_in": 3600, "token_type": "bearer",
                "user": {"id": "u1"}})
        rpc_bodies.append(json.loads(request.content))
        return httpx.Response(200, json={**_thread_payload(), "delegation": "ai"})

    server, url = _start(httpx.MockTransport(handler))
    try:
        with httpx.Client() as http:
            response = http.post(
                f"{url}/items",
                json={"title": "Review the PR", "delegation": "ai"})
            assert response.status_code == 202
            assert response.json()["delegation"] == "ai"
    finally:
        server.shutdown()
    assert rpc_bodies[-1]["assigned_to"] == "ai"


def test_post_items_omitted_delegation_stays_null() -> None:
    rpc_bodies = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/auth/v1/token":
            return httpx.Response(200, json={
                "access_token": "fresh", "refresh_token": "rt2",
                "expires_in": 3600, "token_type": "bearer",
                "user": {"id": "u1"}})
        rpc_bodies.append(json.loads(request.content))
        return httpx.Response(200, json=_thread_payload())

    server, url = _start(httpx.MockTransport(handler))
    try:
        with httpx.Client() as http:
            response = http.post(f"{url}/items", json={"title": "Generic item"})
            assert response.status_code == 202
            assert response.json()["delegation"] is None
    finally:
        server.shutdown()
    assert rpc_bodies[-1]["assigned_to"] is None


def test_post_items_rejects_invalid_delegation() -> None:
    server, url = _start(httpx.MockTransport(
        lambda r: httpx.Response(204)))  # never reached
    try:
        with httpx.Client() as http:
            response = http.post(
                f"{url}/items",
                json={"title": "x", "delegation": "human"})
            assert response.status_code == 400
            assert "delegation" in response.json()["error"]
    finally:
        server.shutdown()


def test_post_items_requires_title() -> None:
    server, url = _start(httpx.MockTransport(
        lambda r: httpx.Response(204)))  # never reached
    try:
        with httpx.Client() as http:
            response = http.post(f"{url}/items", json={})
            assert response.status_code == 400
            assert "title" in response.json()["error"]
    finally:
        server.shutdown()


def test_post_items_maps_sdk_error() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/auth/v1/token":
            return httpx.Response(200, json={
                "access_token": "fresh", "refresh_token": "rt2",
                "expires_in": 3600, "token_type": "bearer",
                "user": {"id": "u1"}})
        return httpx.Response(401, json={"message": "JWT expired"})

    server, url = _start(httpx.MockTransport(handler))
    try:
        with httpx.Client() as http:
            response = http.post(
                f"{url}/items", json={"title": "Still failing"})
            # without refresh recovery, the 401 surfaces as 502
            assert response.status_code == 502
    finally:
        server.shutdown()
