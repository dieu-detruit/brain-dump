#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
WATCH_TEST_CONTAINER="brain-dump-watch-test-$$"
trap 'docker rm -f "$WATCH_TEST_CONTAINER" >/dev/null 2>&1 || true' EXIT
docker run --name "$WATCH_TEST_CONTAINER" --rm -d -e POSTGRES_PASSWORD=local-watch-test postgres:17 -c wal_level=logical >/dev/null
for attempt in $(seq 1 30); do
  if docker exec "$WATCH_TEST_CONTAINER" pg_isready -U postgres >/dev/null 2>&1; then break; fi
  sleep 1
done
{ cat tests/bootstrap.sql; cat migrations/*.sql; } | docker exec -i "$WATCH_TEST_CONTAINER" psql -U postgres -v ON_ERROR_STOP=1 >/dev/null
for test in tests/execution.sql tests/devices.sql tests/notifications.sql tests/pairing_recovery.sql tests/legacy_confirmation.sql; do
  docker exec -i "$WATCH_TEST_CONTAINER" psql -U postgres -v ON_ERROR_STOP=1 < "$test"
done

python3 tests/races.py "$WATCH_TEST_CONTAINER"
