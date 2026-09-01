"""The localhost daemon.

Listens on 127.0.0.1:<port>; `POST /items` with a small generic JSON body
(`{"title": "..."}`) becomes a Brain Dump Thread through `brain-dump-sdk`.
`GET /health` for readiness.
"""
from __future__ import annotations

import json
import logging
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from brain_dump_sdk import BrainDumpClient
from brain_dump_sdk.exceptions import BrainDumpError

from .config import BridgeConfig

log = logging.getLogger("brain-dump-bridge")


class Bridge:
    """Holds the shared SDK client (reuses a live access token across calls)."""

    def __init__(self, bridge_config: BridgeConfig) -> None:
        self.config = bridge_config
        self._client: BrainDumpClient | None = None

    def client(self) -> BrainDumpClient:
        if self._client is None:
            self._client = self.config.new_client()
        return self._client


class ItemHandler(BaseHTTPRequestHandler):
    bridge: Bridge | None = None

    # -- endpoints ------------------------------------------------------------
    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/health":
            self._json(200, {"ok": True})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path.rstrip("/") != "/items":
            self._json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0") or 0)
            payload = json.loads(self.rfile.read(length) or b"{}")
        except (ValueError, json.JSONDecodeError) as error:
            self._json(400, {"error": f"invalid JSON body: {error}"})
            return
        if not isinstance(payload, dict):
            self._json(400, {"error": "body must be a JSON object"})
            return

        title = (payload.get("title") or "").strip()
        if not title:
            self._json(400, {"error": "field `title` is required"})
            return

        bridge = self._bridge()
        try:
            thread = bridge.client().add_thread(title)
        except ValueError as error:  # SDK-side validation
            self._json(400, {"error": str(error)})
            return
        except BrainDumpError as error:
            log.warning("add_thread rejected: %s", error)
            self._json(502, {"error": str(error)})
            return
        except Exception:  # noqa: BLE001 — never leak to the caller
            log.exception("unexpected error adding thread")
            self._json(500, {"error": "internal error"})
            return

        log.info("added thread %s: %s", thread.id, title)
        self._json(202, {"ok": True, "id": thread.id, "title": title})

    # -- helpers ---------------------------------------------------------------
    def _bridge(self) -> Bridge:
        if ItemHandler.bridge is None:
            raise RuntimeError("bridge not wired")
        return ItemHandler.bridge

    def _json(self, status: int, obj: dict) -> None:
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt: str, *args: object) -> None:  # route to logging
        log.info("%s - %s", self.address_string(), fmt % args)


def make_server(bridge: Bridge, port: int) -> ThreadingHTTPServer:
    ItemHandler.bridge = bridge
    server = ThreadingHTTPServer(("127.0.0.1", port), ItemHandler)
    server.daemon_threads = True
    return server
