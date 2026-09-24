#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${APP_BUNDLE_ID:?Set the registered watch-only container bundle ID}"
export WATCH_BUNDLE_ID="${APP_BUNDLE_ID}.watchkitapp"
: "${APPLE_TEAM_ID:?Set the Apple team ID}"
: "${BRAIN_DUMP_WATCH_API_URL:?Set the deployed HTTPS watch-api URL}"
: "${BUILD_NUMBER:?Set a unique numeric build number}"
xcodegen generate --spec brain-dump-watch/project.yml
xcode-project use-profiles
xcodebuild archive -project brain-dump-watch/BrainDumpWatch.xcodeproj -scheme BrainDumpContainer \
  -destination 'generic/platform=iOS' -archivePath /tmp/BrainDumpWatch.xcarchive \
  APP_BUNDLE_ID="$APP_BUNDLE_ID" WATCH_BUNDLE_ID="$WATCH_BUNDLE_ID" APPLE_TEAM_ID="$APPLE_TEAM_ID" \
  BRAIN_DUMP_WATCH_API_URL="$BRAIN_DUMP_WATCH_API_URL" APNS_ENVIRONMENT=production \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
xcodebuild -exportArchive -archivePath /tmp/BrainDumpWatch.xcarchive \
  -exportOptionsPlist /Users/builder/export_options.plist -exportPath /tmp/watch-export
