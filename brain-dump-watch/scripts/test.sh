#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
xcodegen generate --spec brain-dump-watch/project.yml
WATCH_SIMULATOR_ID=$(xcrun simctl list devices available -j | python3 brain-dump-watch/scripts/select-simulator.py)
xcodebuild test -project brain-dump-watch/BrainDumpWatch.xcodeproj -scheme BrainDumpWatch \
  -destination "platform=watchOS Simulator,id=$WATCH_SIMULATOR_ID" \
  -resultBundlePath "${CM_BUILD_DIR:-/tmp}/watch-tests-${BUILD_NUMBER:-local}.xcresult" \
  WATCH_BUNDLE_ID="${WATCH_BUNDLE_ID:-dev.braindump.watch}" APNS_ENVIRONMENT=development \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
