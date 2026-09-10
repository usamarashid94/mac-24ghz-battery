#!/bin/bash
# Full QA run. Everything here must pass before pushing.
#
# Covers what can be checked without owning every supported device: parser
# tests against crafted frames, output format, safety guards, table integrity,
# then real-hardware smoke tests and stability on whatever is plugged in.
set -uo pipefail

cd "$(dirname "$0")"

pass=0
fail=0

step() { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  ✓ %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  ✗ %s\n' "$1"; fail=$((fail + 1)); }

step "1. Build (CLI)"
if ./build.sh >/tmp/qa-build.log 2>&1; then ok "CLI builds and installs"; else bad "CLI build failed"; cat /tmp/qa-build.log; fi

step "2. Build (menu bar app)"
if ./build-app.sh >/tmp/qa-app.log 2>&1; then ok "app bundle builds"; else bad "app build failed"; cat /tmp/qa-app.log; fi

step "3. Compiler warnings"
warnings=$(grep -c 'warning:' /tmp/qa-build.log 2>/dev/null | head -1)
warnings=${warnings:-0}
if [ "$warnings" -eq 0 ]; then ok "no compiler warnings"; else bad "$warnings compiler warning(s)"; grep 'warning:' /tmp/qa-build.log | head -5; fi

step "4. Self-test (parsers, formatting, guards, device table)"
if ./wireless-battery --selftest; then ok "self-test passed"; else bad "self-test failed"; fi

step "5. Output modes do not crash"
for mode in "" "--json" "--swiftbar" "--devices" "--probe" "--help"; do
    if ./wireless-battery $mode >/dev/null 2>&1; then
        ok "wireless-battery ${mode:-(default)}"
    else
        bad "wireless-battery ${mode:-(default)} exited $?"
    fi
done

step "6. JSON is well formed"
if ./wireless-battery --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "devices" in d' 2>/dev/null; then
    ok "JSON parses and has a devices array"
else
    bad "JSON invalid"
fi
if WIRELESS_BATTERY_SHOW_OFFLINE=1 ./wireless-battery --json | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    ok "JSON valid with offline devices included (null levels)"
else
    bad "JSON invalid when a device has no level"
fi

step "7. Stability under repetition"
crashes=0
for _ in $(seq 1 30); do
    case $((RANDOM % 3)) in
        0) ./wireless-battery >/dev/null 2>&1 ;;
        1) ./wireless-battery --json >/dev/null 2>&1 ;;
        2) ./wireless-battery --swiftbar >/dev/null 2>&1 ;;
    esac
    [ $? -ne 0 ] && crashes=$((crashes + 1))
done
if [ "$crashes" -eq 0 ]; then ok "30 mixed runs, no crashes"; else bad "$crashes crash(es) in 30 runs"; fi

step "8. Retained session state stays bounded"
retained=$(./wireless-battery --stress 60 | tail -2 | grep -oE 'buffers = [0-9]+' | grep -oE '[0-9]+' | tail -1)
if [ -n "$retained" ] && [ "$retained" -le 32 ]; then
    ok "retention capped at $retained after 60 cycles"
else
    bad "retention unbounded or unreadable (got '${retained:-none}')"
fi

step "9. Speed"
start=$(python3 -c 'import time; print(time.time())')
for _ in $(seq 1 10); do ./wireless-battery >/dev/null 2>&1; done
elapsed=$(python3 -c "import time; print(round((time.time() - $start) / 10, 3))")
ok "average run: ${elapsed}s"

step "10. Hardware present right now"
WIRELESS_BATTERY_SHOW_OFFLINE=1 ./wireless-battery | sed 's/^/  /'
count=$(WIRELESS_BATTERY_SHOW_OFFLINE=1 ./wireless-battery --json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["devices"]))' 2>/dev/null || echo 0)
if [ "$count" -gt 0 ]; then ok "$count device(s) detected"; else bad "no devices detected at all"; fi

printf '\n\033[1m%d passed, %d failed\033[0m\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
