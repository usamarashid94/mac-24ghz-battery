#!/bin/bash
# Build the menu bar app and package it as a .dmg for download.
#
# The app is ad-hoc signed, not notarized: there is no Developer ID on this
# machine. macOS will refuse to open it on first launch until the user removes
# the quarantine flag — the README says how. Notarizing would need a paid
# Apple Developer account.
set -euo pipefail

cd "$(dirname "$0")"

APP="build/Wireless Battery.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" app/Info.plist)
DMG="dist/WirelessBattery-${VERSION}.dmg"
STAGE="build/dmg-stage"

./build-app.sh >/dev/null

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/"
# The customary drag-to-install target.
ln -s /Applications "$STAGE/Applications"

# Ship the reason the app will be blocked, next to the app itself.
cat > "$STAGE/READ ME FIRST.txt" <<'NOTE'
Wireless Battery

Drag "Wireless Battery.app" onto the Applications folder, then open it.

macOS will refuse to open it the first time, saying the app is damaged or
from an unidentified developer. That is Gatekeeper reacting to an app that
is not notarized — notarizing requires a paid Apple Developer account.
The app is open source; you can read every line of it and build it yourself.

To open it anyway, either:

  * Right-click the app in Applications and choose Open, then confirm, or
  * run this in Terminal:

        xattr -dr com.apple.quarantine "/Applications/Wireless Battery.app"

Source, and instructions for building it yourself:
https://github.com/usamarashid94/mac-24ghz-battery
NOTE

# The volume's own icon, shown when the .dmg is mounted.
cp build/icons/AppIcon.icns "$STAGE/.VolumeIcon.icns"

# Build read-write first: the "has a custom icon" flag can only be set on a
# mounted, writable volume. Then compress.
TEMP_DMG="build/staging.dmg"
rm -f "$TEMP_DMG"
hdiutil create -volname "Wireless Battery" -srcfolder "$STAGE" \
    -ov -format UDRW "$TEMP_DMG" >/dev/null

MOUNT=$(hdiutil attach -nobrowse -readwrite "$TEMP_DMG" | tail -1 | sed 's/.*\(\/Volumes\/.*\)/\1/')
SetFile -a C "$MOUNT" 2>/dev/null || echo "note: could not flag the volume icon"
hdiutil detach "$MOUNT" >/dev/null

hdiutil convert "$TEMP_DMG" -format UDZO -o "$DMG" >/dev/null
rm -f "$TEMP_DMG"
rm -rf "$STAGE"

# And the .dmg file itself, so it is not a generic disk image in Downloads.
swiftc -O -framework AppKit -o build/set-file-icon tools/set-file-icon.swift 2>/dev/null
build/set-file-icon build/icons/AppIcon.icns "$DMG" >/dev/null 2>&1 \
    || echo "note: could not set the .dmg file icon"

echo "built: $DMG"
shasum -a 256 "$DMG" | awk '{print "sha256: "$1}'
du -h "$DMG" | awk '{print "size:   "$1}'
