#!/usr/bin/env bash
# Install the brain-dump-bridge user service and start it.
# Re-run after editing systemd/brain-dump-bridge.service.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR="$HOME/.config/systemd/user"
mkdir -p "$UNIT_DIR"
ln -sf "$HERE/systemd/brain-dump-bridge.service" "$UNIT_DIR/brain-dump-bridge.service"
systemctl --user daemon-reload
systemctl --user enable --now brain-dump-bridge.service
systemctl --user status brain-dump-bridge.service --no-pager
