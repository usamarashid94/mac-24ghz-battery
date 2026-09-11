#!/bin/bash
# Renders the app icon and packages it as AppIcon.icns.
# The mark is drawn at each size rather than scaled from one master, so the
# stroke stays crisp at 16pt instead of turning to mush.
set -euo pipefail
cd "$(dirname "$0")/.."

MARK="${1:-B-dongle}"
OUT="build/icons"

swiftc -O -framework AppKit -o "$OUT/../mkicons" tools/make-icons.swift 2>/dev/null \
    || swiftc -O -framework AppKit -o build/mkicons tools/make-icons.swift
mkdir -p "$OUT"
build/mkicons "$OUT" "$MARK" >/dev/null
iconutil -c icns "$OUT/AppIcon.iconset" -o "$OUT/AppIcon.icns"
echo "built: $OUT/AppIcon.icns"
