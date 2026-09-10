#!/bin/bash
# Build the menu bar app bundle. Needs only the Xcode Command Line Tools.
set -euo pipefail

cd "$(dirname "$0")"

APP="build/Wireless Battery.app"
MACOS="$APP/Contents/MacOS"

rm -rf "$APP"
mkdir -p "$MACOS"

# Shared drivers, minus the CLI entry point; the app brings its own main.swift.
SHARED=$(find src -name '*.swift' ! -name 'main.swift' | sort)
APP_SOURCES=$(find app/Sources -name '*.swift' ! -name 'main.swift' | sort)

swiftc -O -framework AppKit -framework IOKit -framework CoreFoundation \
    -framework ServiceManagement \
    -o "$MACOS/WirelessBattery" \
    $SHARED $APP_SOURCES app/Sources/main.swift

cp app/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature. Enough to run locally; a Developer ID would be needed to
# distribute it or to make the login item reliable.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc signing failed"

echo "built: $APP"
echo "run it with: open '$APP'"
