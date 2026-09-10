#!/bin/bash
# <bitbar.title>2.4 GHz Battery</bitbar.title>
# <bitbar.desc>Battery level for wireless devices on a 2.4 GHz USB dongle.</bitbar.desc>
#
# SwiftBar plugin. Thin wrapper around the wireless-battery binary, which talks
# to the dongle over HID and prints SwiftBar format itself. Refreshes every 60
# seconds (set by the .60s. in the filename).
#
# Source and rebuild instructions: https://github.com/usamarashid94/mac-24ghz-battery

BIN="$HOME/.local/bin/wireless-battery"

if [ ! -x "$BIN" ]; then
    echo "🔌 ?"
    echo "---"
    echo "wireless-battery not installed | color=#E06C5F"
    echo "Expected at $BIN | color=#8A97A5"
    exit 0
fi

"$BIN" --swiftbar
