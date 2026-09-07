from __future__ import annotations

import argparse
import asyncio
from pathlib import Path

from brain_dump_sdk import auth

from . import env
from .archive import Archive
from .sync import HistorySync, required_env


async def run(args: argparse.Namespace) -> None:
    url, key, access, refresh_token = required_env(args.token_file)
    client = None
    session = None
    if args.command == "watch":
        from supabase import acreate_client

        client = await acreate_client(url, key)
        if refresh_token:
            refreshed = auth.refresh(url, key, refresh_token)
            response = await client.auth.set_session(refreshed.access_token, refreshed.refresh_token)
            session = response.session
            if session is None:
                raise RuntimeError("Supabase returned no authenticated session")
            access = session.access_token
            if args.token_file:
                auth.save_refresh_token(session.refresh_token, args.token_file)
        else:
            await client.realtime.set_auth(access)
    elif refresh_token:
        session = auth.refresh(url, key, refresh_token)
        access = session.access_token
        token_file = args.token_file or None
        if token_file and session.refresh_token:
            auth.save_refresh_token(session.refresh_token, token_file)

    archive = Archive(args.repository)
    sync = HistorySync(archive, url=url, anon_key=key, access_token=access)
    try:
        count = await sync.run(commit=not args.no_commit)
        print(f"Synchronized {count} history rows")
        if args.command == "sync":
            return

        assert client is not None
        wake = asyncio.Event()

        def changed(_payload: dict) -> None:
            wake.set()

        async def worker() -> None:
            while True:
                await wake.wait()
                wake.clear()
                if refresh_token:
                    current = await client.auth.get_session()
                    if current is None:
                        raise RuntimeError("Supabase session expired")
                    sync.set_access_token(current.access_token)
                    if args.token_file:
                        auth.save_refresh_token(current.refresh_token, args.token_file)
                count = await sync.run(commit=not args.no_commit)
                if count:
                    print(f"Synchronized {count} history rows")

        channel = client.channel("brain-dump-history")
        for table in ("change_log", "execution_sessions"):
            channel = channel.on_postgres_changes(
                "*", schema="public", table=table, callback=changed
            )
        await channel.subscribe()
        print("Subscribed to Brain Dump history changes")
        # Close the small gap between the initial catch-up and subscription.
        wake.set()
        await worker()
    finally:
        await sync.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Archive Brain Dump history")
    parser.add_argument("command", choices=("sync", "watch", "login"), nargs="?", default="watch")
    # required only for sync/watch (argparse-level `required=True` would also
    # demand it for `login`, which never touches the repository)
    parser.add_argument("--repository", type=Path, default=None)
    parser.add_argument("--token-file", type=Path)
    parser.add_argument("--no-commit", action="store_true")
    parser.add_argument("--no-browser", action="store_true")
    parser.add_argument("--manual-code", action="store_true")
    args = parser.parse_args()
    if args.command == "login":
        url = env.get("BRAIN_DUMP_URL")
        key = env.get("BRAIN_DUMP_ANON_KEY")
        if not url or not key or not args.token_file:
            parser.error(
                "login requires BRAIN_DUMP_URL, BRAIN_DUMP_ANON_KEY, and "
                "--token-file (env vars or ~/.config/brain-dump/env)"
            )
        refresh_token = auth.login(
            url, key, open_browser=not args.no_browser, manual_code=args.manual_code
        )
        auth.save_refresh_token(refresh_token, args.token_file)
        print(f"Saved history refresh token to {args.token_file}")
        return
    if not args.repository:
        parser.error("--repository is required for sync/watch")
    asyncio.run(run(args))
