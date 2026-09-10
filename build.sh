#!/bin/bash
# Rebuild the wireless-battery binary and install it to ~/.local/bin.
# Needs only the Xcode Command Line Tools, no full Xcode.
set -euo pipefail

cd "$(dirname "$0")"

# main.swift must come last: Swift requires top-level code in a file of that
# name, and listing it last keeps the driver files ordinary declarations.
SOURCES=$(find src -name '*.swift' ! -name 'main.swift' | sort)

swiftc -O -framework IOKit -framework CoreFoundation \
    -o wireless-battery $SOURCES src/main.swift

mkdir -p "$HOME/.local/bin"
install -m 755 wireless-battery "$HOME/.local/bin/wireless-battery"

echo "installed: $HOME/.local/bin/wireless-battery"
"$HOME/.local/bin/wireless-battery"
