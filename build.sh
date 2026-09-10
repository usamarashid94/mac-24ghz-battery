#!/bin/bash
# Rebuild the wireless-battery binary and install it to ~/.local/bin.
# Needs only the Xcode Command Line Tools, no full Xcode.
set -euo pipefail

cd "$(dirname "$0")"

swiftc -O -framework IOKit -framework CoreFoundation -o wireless-battery src/main.swift

mkdir -p "$HOME/.local/bin"
install -m 755 wireless-battery "$HOME/.local/bin/wireless-battery"

echo "installed: $HOME/.local/bin/wireless-battery"
"$HOME/.local/bin/wireless-battery"
