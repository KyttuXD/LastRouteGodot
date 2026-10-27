#!/bin/bash
# Repeatable headless co-op test: local backend + host + guest + late joiner.
#   scripts/coop_test.sh            (from the project root)
# Uses free high ports (HTTP 18105, relay UDP 11105, host 18511), a temp data dir and
# test-only env values. Every process it starts is killed by exact PID on exit.
set -u
# SERVER_ROOT=/path/to/a/deployed/release runs the backend from that copy instead of this checkout.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
TMP="$(mktemp -d)"
HTTP=${COOP_HTTP_PORT:-18105}; RELAY=${COOP_RELAY_PORT:-11105}
PIDS=()
cleanup() { [ -n "${KEEP_LOGS:-}" ] && cp "$TMP"/*.log "$KEEP_LOGS"/ 2>/dev/null; for p in ${PIDS[@]+"${PIDS[@]}"}; do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
cd "$ROOT"
# Remote mode (see scripts/_target.sh): REMOTE=1 BACKEND_URL=<test instance> scripts/coop_test.sh
# runs host/guest/late against that server instead of starting a local one. Nothing in this test needs
# a local server restart or local server files, so no check is skipped; only the server log is absent.
. "$ROOT/scripts/_target.sh"
if [ "$REMOTE" = 1 ]; then
  echo "coop test against REMOTE $BACKEND_URL"
else
HOST=127.0.0.1 LASTROUTE_HTTP_PORT=$HTTP LASTROUTE_RELAY_HOST=127.0.0.1 LASTROUTE_RELAY_PORT=$RELAY \
  LASTROUTE_DATA_DIR="$TMP/data" LASTROUTE_AUTO_UPDATE=false LASTROUTE_RESTART_ON_GITHUB_UPDATE=false \
  node "${SERVER_ROOT:-.}/index.js" > "$TMP/server.log" 2>&1 &
PIDS+=($!)
sleep 2
fi
if [ "$REMOTE" = 1 ]; then BACKEND="--backend=$BACKEND_URL"; else BACKEND="--backend=http://127.0.0.1:$HTTP"; fi
run() { # role, log
  "$GODOT" --headless --path . res://scenes/coop_test.tscn -- "$1" "$BACKEND" "--dir=$TMP" $GODOT_FLAGS > "$TMP/$1.log" 2>&1 &
  PIDS+=($!); echo $! > "$TMP/$1.pid"
}
run host; sleep 3; run guest
( while [ ! -f "$TMP/claimed.txt" ]; do sleep 1; done; run late ) &
PIDS+=($!)
for i in $(seq 1 ${COOP_TIMEOUT:-240}); do
  sleep 1
  if grep -q "COOP HOST DONE" "$TMP/host.log" 2>/dev/null && grep -q "COOP GUEST DONE" "$TMP/guest.log" 2>/dev/null; then break; fi
  if grep -q "FAIL" "$TMP"/host.log "$TMP"/guest.log "$TMP"/late.log 2>/dev/null; then break; fi
done
STATUS=1
grep -h "^COOP" "$TMP"/host.log "$TMP"/guest.log "$TMP"/late.log 2>/dev/null
if grep -q "COOP HOST DONE" "$TMP/host.log" && grep -q "COOP GUEST DONE" "$TMP/guest.log" && grep -q "COOP LATE DONE" "$TMP/late.log"; then
  echo "coop test OK"; STATUS=0
else
  echo "coop test FAILED"; tail -5 "$TMP"/host.log "$TMP"/guest.log "$TMP"/late.log 2>/dev/null
fi
exit $STATUS
