#!/bin/bash
# Build the menu bar app bundle. Needs only the Xcode Command Line Tools.
set -euo pipefail

cd "$(dirname "$0")"

APP="build/Wireless Battery.app"
MACOS="$APP/Contents/MacOS"

# Rebuilding deletes the bundle. A running instance survives on the deleted
# inode but loses its menu bar item, which looks exactly like the app having
# crashed. Stop it first and put it back afterwards.
WAS_RUNNING=0
# Scoped to this user: pgrep/pkill match other accounts' processes too, but we
# cannot signal those, so an unscoped check would spin waiting for a process
# that is never going to exit.
if pgrep -x -u "$(id -u)" WirelessBattery >/dev/null 2>&1; then
    WAS_RUNNING=1
    echo "stopping the running app before rebuilding…"
    pkill -x -u "$(id -u)" WirelessBattery || true
    # Give it a moment to release the bundle.
    for _ in 1 2 3 4 5; do
        pgrep -x -u "$(id -u)" WirelessBattery >/dev/null 2>&1 || break
        sleep 0.2
    done
fi

# A copy under another login session keeps its own menu bar item and keeps
# polling the same hardware. Nothing here can stop it, so say so rather than
# leaving a mystery second icon.
if pgrep -x WirelessBattery >/dev/null 2>&1 && ! pgrep -x -u "$(id -u)" WirelessBattery >/dev/null 2>&1; then
    echo "note: another user account is running this app; that copy is untouched."
fi

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

if [ "$WAS_RUNNING" -eq 1 ]; then
    open "$APP"
    echo "relaunched the app"
else
    echo "run it with: open '$APP'"
fi
