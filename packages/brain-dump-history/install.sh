#!/bin/sh
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
UNIT_DIR=${XDG_CONFIG_HOME:-"$HOME/.config"}/systemd/user

mkdir -p "$UNIT_DIR"
ln -sf "$HERE/systemd/brain-dump-history.service" "$UNIT_DIR/brain-dump-history.service"
systemctl --user daemon-reload
systemctl --user enable --now brain-dump-history.service
systemctl --user status brain-dump-history.service --no-pager
