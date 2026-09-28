#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${APP_BUNDLE_ID:?Set the registered watch-only container bundle ID}"
export WATCH_BUNDLE_ID="${APP_BUNDLE_ID}.watchkitapp"
: "${APPLE_TEAM_ID:?Set the Apple team ID}"
: "${BRAIN_DUMP_WATCH_API_URL:?Set the deployed HTTPS watch-api URL}"
: "${BUILD_NUMBER:?Set a unique numeric build number}"
xcodegen generate --spec brain-dump-watch/project.yml
# Resolve bundle IDs before the profile matcher reads the generated project.
python3 - <<'PY'
import os
import pathlib
import re

project = pathlib.Path('brain-dump-watch/BrainDumpWatch.xcodeproj/project.pbxproj')
contents = project.read_text()
for name in ('APP_BUNDLE_ID', 'WATCH_BUNDLE_ID'):
    value = os.environ[name]
    if not re.fullmatch(r'[A-Za-z0-9.-]+', value):
        raise SystemExit(f'Invalid {name}')
    contents = contents.replace(f'$({name})', value)
project.write_text(contents)
PY
export_options="${RUNNER_TEMP:-/tmp}/brain-dump-export-options.plist"
xcode-project use-profiles --project brain-dump-watch/BrainDumpWatch.xcodeproj \
  --export-options-plist "$export_options"
xcodebuild archive -project brain-dump-watch/BrainDumpWatch.xcodeproj -scheme BrainDumpContainer \
  -destination 'generic/platform=iOS' -archivePath /tmp/BrainDumpWatch.xcarchive \
  APP_BUNDLE_ID="$APP_BUNDLE_ID" WATCH_BUNDLE_ID="$WATCH_BUNDLE_ID" APPLE_TEAM_ID="$APPLE_TEAM_ID" \
  BRAIN_DUMP_WATCH_API_URL="$BRAIN_DUMP_WATCH_API_URL" APNS_ENVIRONMENT=production \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
xcodebuild -exportArchive -archivePath /tmp/BrainDumpWatch.xcarchive \
  -exportOptionsPlist "$export_options" -exportPath /tmp/watch-export
