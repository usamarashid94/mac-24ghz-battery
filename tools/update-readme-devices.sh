#!/bin/bash
# Regenerate the README's supported-devices table from the built-in device
# table, so the documentation cannot drift from the code.
set -euo pipefail
cd "$(dirname "$0")/.."

BIN=./wireless-battery
[ -x "$BIN" ] || BIN="$HOME/.local/bin/wireless-battery"

python3 - "$($BIN --devices-markdown)" <<'PY'
import pathlib, sys
table = sys.argv[1].rstrip() + "\n"
p = pathlib.Path("README.md")
t = p.read_text()
begin, end = "<!-- BEGIN DEVICES -->", "<!-- END DEVICES -->"
if begin not in t or end not in t:
    sys.exit("README is missing the device-table markers")
head = t[: t.index(begin) + len(begin)]
tail = t[t.index(end):]
p.write_text(head + "\n\n" + table + "\n" + tail)
print("README device table updated")
PY
