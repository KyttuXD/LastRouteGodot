#!/bin/bash
# Headless PUBLIC route test: A (authority) collects a relay, B joins as a guest and
# crashes, B2 resumes B's place, the backend restarts, then A dies and B2 takes over.
#   scripts/public_test.sh        (from the project root)
# Free high ports (HTTP 18205, relay UDP 11205), temp data dir, test-only values.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
TMP="$(mktemp -d)"
HTTP=${PUBLIC_HTTP_PORT:-18205}; RELAY=${PUBLIC_RELAY_PORT:-11205}
declare -a PIDS=()
cleanup() { for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done; [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
cd "$ROOT"
start_server() {
  HOST=127.0.0.1 LASTROUTE_HTTP_PORT=$HTTP LASTROUTE_RELAY_HOST=127.0.0.1 LASTROUTE_RELAY_PORT=$RELAY \
    LASTROUTE_DATA_DIR="$TMP/data" LASTROUTE_AUTO_UPDATE=false LASTROUTE_RESTART_ON_GITHUB_UPDATE=false \
    node index.js >> "$TMP/server.log" 2>&1 &
  SERVER_PID=$!
}
client() { # role key
  "$GODOT" --headless --path . res://scenes/public_test.tscn -- "$1" "--backend=http://127.0.0.1:$HTTP" "--dir=$TMP" "--key=$2" > "$TMP/$1.log" 2>&1 &
  eval "PID_$1=$!"; PIDS+=($!)
}
waitfile() { for i in $(seq 1 ${2:-120}); do [ -f "$TMP/$1" ] && return 0; grep -q "PUBLIC .* FAIL" "$TMP"/*.log 2>/dev/null && return 1; sleep 1; done; return 1; }
KEYA=aaaaaaaaaaaaaaaaaaaaaaaa; KEYB=bbbbbbbbbbbbbbbbbbbbbbbb
start_server; sleep 2
client a $KEYA
waitfile a_relay.txt 120 || { echo "FAIL: authority relay"; }
client b $KEYB
waitfile b_pos.txt 150 || echo "FAIL: guest never posted"
sleep 1
client b2 $KEYB
waitfile b2_ok.txt 150 || echo "FAIL: resume"
# restart the backend: kill it, start it again on the same data dir
kill $SERVER_PID; wait $SERVER_PID 2>/dev/null; sleep 2; start_server; sleep 3
echo 1 > "$TMP/server_restarted.txt"
waitfile a_after_restart.txt 90 || echo "FAIL: authority did not survive the restart"
# the authority dies; the remaining client takes over
kill $PID_a 2>/dev/null
waitfile b2_authority.txt 150 || echo "FAIL: no handoff"
STATUS=1
grep -h "^PUBLIC" "$TMP"/a.log "$TMP"/b.log "$TMP"/b2.log
STATE=$(curl -s http://127.0.0.1:$HTTP/api/public/status)
echo "status after: $STATE"
if [ -f "$TMP/a_after_restart.txt" ] && [ -f "$TMP/b2_authority.txt" ] && [ -f "$TMP/b2_ok.txt" ] && ! grep -q "PUBLIC .* FAIL" "$TMP"/*.log; then echo "public route test OK"; STATUS=0; else echo "public route test FAILED"; tail -6 "$TMP"/a.log "$TMP"/b.log "$TMP"/b2.log; fi
exit $STATUS
