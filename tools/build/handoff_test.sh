#!/bin/bash
# Real three-process deliberate host handoff through a LOCAL backend + relay (never a remote server).
#   tools/build/handoff_test.sh            (from the project root; GODOT_BIN=/path/to/godot)
# old host + successor (joins first) + other guest. The old host hands over mid-route; the successor rebuilds the
# route as a fresh ENet peer 1 from the checkpoint; the other guest reconnects, proves its resume identity and gets
# the committed snapshot with its own waypoint rebound to its new peer id. Every process is killed by PID on exit.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
TMP="$(mktemp -d)"
HTTP=${HANDOFF_HTTP_PORT:-18125}; RELAY=${HANDOFF_RELAY_PORT:-11125}
PIDS=()
cleanup() { [ -n "${KEEP_LOGS:-}" ] && cp "$TMP"/*.log "$KEEP_LOGS"/ 2>/dev/null; for p in ${PIDS[@]+"${PIDS[@]}"}; do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
cd "$ROOT"
if [ "${REMOTE:-0}" != 0 ]; then echo "REFUSED: the handoff test only runs against its own local backend" >&2; exit 9; fi
HOST=127.0.0.1 LASTROUTE_HTTP_PORT=$HTTP LASTROUTE_RELAY_HOST=127.0.0.1 LASTROUTE_RELAY_PORT=$RELAY \
  LASTROUTE_DATA_DIR="$TMP/data" LASTROUTE_AUTO_UPDATE=false LASTROUTE_RESTART_ON_GITHUB_UPDATE=false \
  node ./index.js > "$TMP/server.log" 2>&1 &
PIDS+=($!)
sleep 2
BACKEND="--backend=http://127.0.0.1:$HTTP"
run() { # role
  "$GODOT" --headless --path . res://tests/scenes/handoff_test.tscn -- "$1" "$BACKEND" "--dir=$TMP" "--profile=handoff_$1" > "$TMP/$1.log" 2>&1 &
  PIDS+=($!)
}
run old; sleep 3; run succ
( while [ ! -f "$TMP/succ_joined.txt" ]; do sleep 1; done; run other ) &
PIDS+=($!)
for i in $(seq 1 ${HANDOFF_TIMEOUT:-240}); do
  sleep 1
  if grep -q "HANDOFF SUCC DONE" "$TMP/succ.log" 2>/dev/null && grep -q "HANDOFF OTHER DONE" "$TMP/other.log" 2>/dev/null \
      && grep -q "HANDOFF OLD DONE" "$TMP/old.log" 2>/dev/null; then break; fi
  if grep -q "HANDOFF .* FAIL" "$TMP"/old.log "$TMP"/succ.log "$TMP"/other.log 2>/dev/null; then break; fi
done
grep -h "^HANDOFF" "$TMP"/old.log "$TMP"/succ.log "$TMP"/other.log 2>/dev/null
if grep -q "HANDOFF OLD DONE" "$TMP/old.log" && grep -q "HANDOFF SUCC DONE" "$TMP/succ.log" && grep -q "HANDOFF OTHER DONE" "$TMP/other.log"; then
  echo "handoff test OK"; exit 0
fi
echo "handoff test FAILED"; tail -25 "$TMP"/old.log "$TMP"/succ.log "$TMP"/other.log "$TMP"/server.log 2>/dev/null
exit 1
