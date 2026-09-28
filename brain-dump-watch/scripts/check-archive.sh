#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
xcodegen generate --spec brain-dump-watch/project.yml
# Verify the actual watch-only distribution layout without Apple credentials.
# Exporting an installable IPA still requires distribution signing.
xcodebuild archive -project brain-dump-watch/BrainDumpWatch.xcodeproj -scheme BrainDumpContainer \
  -destination 'generic/platform=iOS' -archivePath /tmp/BrainDumpWatch-unsigned.xcarchive \
  APP_BUNDLE_ID=dev.braindump WATCH_BUNDLE_ID=dev.braindump.watchkitapp \
  APNS_ENVIRONMENT=production CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM= CURRENT_PROJECT_VERSION=123.4
test -d /tmp/BrainDumpWatch-unsigned.xcarchive/Products/Applications/BrainDumpContainer.app/Watch/BrainDumpWatch.app
test -f /tmp/BrainDumpWatch-unsigned.xcarchive/Products/Applications/BrainDumpContainer.app/Watch/BrainDumpWatch.app/BrainDumpWatch
python3 - <<'PY'
import pathlib
import plistlib

container = pathlib.Path('/tmp/BrainDumpWatch-unsigned.xcarchive/Products/Applications/BrainDumpContainer.app')
with (container / 'Info.plist').open('rb') as file:
    info = plistlib.load(file)
assert info.get('CFBundlePackageType') == 'APPL', 'App Store requires an APPL distribution container'
for app in (container, container / 'Watch/BrainDumpWatch.app'):
    with (app / 'Info.plist').open('rb') as file:
        metadata = plistlib.load(file)
    assert metadata['CFBundleVersion'] == '123.4', 'Build number must follow CURRENT_PROJECT_VERSION'
    assert metadata['CFBundleShortVersionString'] == '1.0'
PY
