from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Sequence

from .client import BrainDumpClient
from .exceptions import BrainDumpError


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="brain-dump")
    commands = parser.add_subparsers(dest="command", required=True)
    thread = commands.add_parser("thread", help="Manage threads")
    thread_commands = thread.add_subparsers(dest="thread_command", required=True)
    add = thread_commands.add_parser("add", help="Add a thread")
    source = add.add_mutually_exclusive_group(required=True)
    source.add_argument("--title", help="Thread title")
    source.add_argument(
        "--stdin", action="store_true", help="Read the thread title from standard input"
    )
    add.add_argument("--delegation", choices=("ai", "colleague"))
    add.add_argument("--json", action="store_true", dest="as_json")
    return parser


def run(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    title = sys.stdin.read() if args.stdin else args.title
    try:
        with BrainDumpClient.from_env() as client:
            thread = client.add_thread(title, delegation=args.delegation)
    except (BrainDumpError, ValueError) as error:
        print(f"brain-dump: {error}", file=sys.stderr)
        return 1
    if args.as_json:
        print(json.dumps(thread.to_dict(), ensure_ascii=False))
    else:
        print(f"Added thread {thread.id}: {thread.title}")
    return 0


def main() -> None:
    raise SystemExit(run())
