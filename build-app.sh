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

# Universal: an Apple Silicon Mac happily cross-compiles the Intel slice, and
# shipping arm64-only would silently exclude every Intel Mac from a download.
FRAMEWORKS="-framework AppKit -framework IOKit -framework CoreFoundation -framework ServiceManagement"
mkdir -p build/arch

for arch in arm64 x86_64; do
    swiftc -O $FRAMEWORKS \
        -target "${arch}-apple-macos13.0" \
        -o "build/arch/WirelessBattery-${arch}" \
        $SHARED $APP_SOURCES app/Sources/main.swift
done

lipo -create -output "$MACOS/WirelessBattery" \
    build/arch/WirelessBattery-arm64 build/arch/WirelessBattery-x86_64
rm -rf build/arch

cp app/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature. Enough to run locally; a Developer ID would be needed to
# distribute it or to make the login item reliable.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc signing failed"

echo "built: $APP"
echo "run it with: open '$APP'"
