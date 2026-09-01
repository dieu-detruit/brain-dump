"""Entry points: `brain-dump-bridge serve` (the daemon) and `auth-login` (one-time)."""
from __future__ import annotations

import argparse
import logging
import sys

from brain_dump_sdk import auth

from . import config
from .config import BridgeConfig
from .server import Bridge, make_server


def _configure_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )


def cmd_serve(args: argparse.Namespace) -> int:
    _configure_logging()
    log = logging.getLogger("brain-dump-bridge")
    cfg: BridgeConfig = BridgeConfig.load()
    if not cfg.url or not cfg.anon_key:
        log.error("BRAIN_DUMP_URL / BRAIN_DUMP_ANON_KEY are not configured "
                  f"(env or {config.ENV_FILE})")
        return 2
    server = make_server(Bridge(cfg), cfg.port)
    log.info("listening on http://127.0.0.1:%d (POST /items)", cfg.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("shutting down")
    finally:
        server.server_close()
    return 0


def cmd_auth_login(args: argparse.Namespace) -> int:
    cfg: BridgeConfig = BridgeConfig.load()
    url = args.url or cfg.url or config.get("BRAIN_DUMP_URL")
    anon = args.anon or cfg.anon_key or config.get("BRAIN_DUMP_ANON_KEY")
    if not url or not anon:
        print("BRAIN_DUMP_URL / BRAIN_DUMP_ANON_KEY are not configured "
              f"(env or {config.ENV_FILE})", file=sys.stderr)
        return 2
    refresh_token = auth.login(url, anon, redirect_port=args.port,
                               open_browser=not args.print_url_only)
    path = auth.save_refresh_token(refresh_token, cfg.token_file)
    print(f"login ok — refresh token saved to {path}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="brain-dump-bridge")
    sub = parser.add_subparsers(dest="command", required=True)

    serve = sub.add_parser("serve", help="run the localhost daemon")
    serve.set_defaults(func=cmd_serve)

    login = sub.add_parser("auth-login", help="one-time Google login (PKCE)")
    login.add_argument("--redirect-port", dest="port", type=int, default=8881,
                       help="local callback port (Supabase redirect must match)")
    login.add_argument("--url", default="")
    login.add_argument("--anon", default="")
    login.add_argument("--print-url-only", action="store_true",
                       help="print the authorize URL without opening a browser")
    login.set_defaults(func=cmd_auth_login)
    return parser


def main(argv: list[str] | None = None) -> None:
    args = build_parser().parse_args(argv)
    raise SystemExit(args.func(args))


if __name__ == "__main__":
    main()
