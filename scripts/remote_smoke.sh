#!/bin/bash
# Smoke test of a REMOTE backend, normally the TEST instance on the VPS:
#   scripts/remote_smoke.sh                                   (default target: http://lastroute.kyttuslab.org:8205)
#   BACKEND_URL=http://127.0.0.1:18505 scripts/remote_smoke.sh   (any allowed target, e.g. a local server)
# 1. node deploy/smoke.mjs   health + instance label + room register/resolve/unregister + PUBLIC status
# 2. backend_smoke.tscn      the real Godot client registers/resolves/unregisters a room
# 3. coop_test.sh (REMOTE)   two real clients (host + guest, plus a late joiner) through the relay
# Production (port 8105) is refused unless --i-know-this-is-production is passed (see scripts/_target.sh).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
export REMOTE=1
. "$ROOT/scripts/_target.sh"
cd "$ROOT"
WANT=test; case "$BACKEND_URL" in *:8105) WANT=production ;; esac
FAIL=0
echo "== remote smoke against $BACKEND_URL (expect instance: $WANT)"
if [ "$(printf '%s' "$BACKEND_URL" | grep -c 127.0.0.1)" = 1 ]; then INST_ARGS=""; else INST_ARGS="--instance $WANT"; fi
node deploy/smoke.mjs "$BACKEND_URL" $INST_ARGS || FAIL=1
if [ "$FAIL" = 0 ]; then
  "$GODOT" --headless --path . res://scenes/backend_smoke.tscn -- "--backend=$BACKEND_URL" $GODOT_FLAGS 2>&1 | grep -E "backend smoke|refusing" || FAIL=1
fi
if [ "$FAIL" = 0 ]; then
  BACKEND_URL="$BACKEND_URL" bash scripts/coop_test.sh "$@" || FAIL=1
fi
[ "$FAIL" = 0 ] && echo "remote smoke OK" || echo "remote smoke FAILED"
exit $FAIL
