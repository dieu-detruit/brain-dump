#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
xcodegen generate --spec brain-dump-watch/project.yml
# Verify the actual watch-only distribution layout without Apple credentials.
# Exporting an installable IPA still requires distribution signing.
xcodebuild archive -project brain-dump-watch/BrainDumpWatch.xcodeproj -scheme BrainDumpContainer \
  -destination 'generic/platform=iOS' -archivePath /tmp/BrainDumpWatch-unsigned.xcarchive \
  APP_BUNDLE_ID=dev.braindump WATCH_BUNDLE_ID=dev.braindump.watchkitapp \
  APNS_ENVIRONMENT=production CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM=
test -d /tmp/BrainDumpWatch-unsigned.xcarchive/Products/Applications/BrainDumpContainer.app/Watch/BrainDumpWatch.app
test -f /tmp/BrainDumpWatch-unsigned.xcarchive/Products/Applications/BrainDumpContainer.app/Watch/BrainDumpWatch.app/BrainDumpWatch
