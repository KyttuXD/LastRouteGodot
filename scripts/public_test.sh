#!/bin/bash
# Headless PUBLIC route test: A (authority) collects a relay, B joins as a guest and
# crashes, B2 resumes B's place, the backend restarts, then A dies and B2 takes over.
#   scripts/public_test.sh        (from the project root)
# GAME=city runs the same scenario on the City public route (CTYPR, its own backend store).
# Free high ports (HTTP 18205, relay UDP 11205), temp data dir, test-only values.
set -u
# SERVER_ROOT=/path/to/a/deployed/release runs the backend from that copy instead of this checkout.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
TMP="$(mktemp -d)"
HTTP=${PUBLIC_HTTP_PORT:-18205}; RELAY=${PUBLIC_RELAY_PORT:-11205}
declare -a PIDS=()
cleanup() { [ -n "${KEEP_LOGS:-}" ] && cp "$TMP"/*.log "$KEEP_LOGS"/ 2>/dev/null; for p in ${PIDS[@]+"${PIDS[@]}"}; do kill "$p" 2>/dev/null; done; [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
cd "$ROOT"
# Remote mode (see scripts/_target.sh): REMOTE=1 BACKEND_URL=<test instance> scripts/public_test.sh
# SKIPPED when remote: the local backend restart (so "authority survives a backend restart" is not
# exercised; the marker is written immediately and only re-checks the authority still holds) and the
# local server log. Note the PUBLIC route keeps its state for the UTC day: wipe the test instance first
# (deploy.sh --instance test --wipe-data) or a relay already collected earlier makes the test fail.
. "$ROOT/scripts/_target.sh"
if [ "$REMOTE" = 1 ]; then echo "public route test against REMOTE $BACKEND_URL"; fi
start_server() {
  [ "$REMOTE" = 1 ] && return 0
  HOST=127.0.0.1 LASTROUTE_HTTP_PORT=$HTTP LASTROUTE_RELAY_HOST=127.0.0.1 LASTROUTE_RELAY_PORT=$RELAY \
    LASTROUTE_DATA_DIR="$TMP/data" LASTROUTE_AUTO_UPDATE=false LASTROUTE_RESTART_ON_GITHUB_UPDATE=false \
    node "${SERVER_ROOT:-.}/index.js" >> "$TMP/server.log" 2>&1 &
  SERVER_PID=$!
}
client() { # role key
  "$GODOT" --headless --path . res://scenes/public_test.tscn -- "$1" "--backend=$TARGET" "--dir=$TMP" "--key=$2" ${GAME:+--game=$GAME} $GODOT_FLAGS > "$TMP/$1.log" 2>&1 &
  eval "PID_$1=$!"; PIDS+=($!)
}
waitfile() { for i in $(seq 1 ${2:-120}); do [ -f "$TMP/$1" ] && return 0; grep -q "PUBLIC .* FAIL" "$TMP"/*.log 2>/dev/null && return 1; sleep 1; done; return 1; }
if [ "$REMOTE" = 1 ]; then TARGET="$BACKEND_URL"; else TARGET="http://127.0.0.1:$HTTP"; fi
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
if [ "$REMOTE" = 1 ]; then echo "(remote) skipping the backend restart"; else kill $SERVER_PID; wait $SERVER_PID 2>/dev/null; sleep 2; start_server; sleep 3; fi
echo 1 > "$TMP/server_restarted.txt"
waitfile a_after_restart.txt 90 || echo "FAIL: authority did not survive the restart"
waitfile a_spectate_done.txt 150 || echo "FAIL: spectator scenario"
# the authority dies; the remaining client takes over
kill $PID_a 2>/dev/null
waitfile b2_authority.txt 150 || echo "FAIL: no handoff"
STATUS=1
grep -h "^PUBLIC" "$TMP"/a.log "$TMP"/b.log "$TMP"/b2.log
STATE=$(curl -s "$TARGET/api/public/status${GAME:+?game=$GAME}")
echo "status after: $STATE"
if [ -f "$TMP/a_after_restart.txt" ] && [ -f "$TMP/b2_authority.txt" ] && [ -f "$TMP/b2_ok.txt" ] && [ -f "$TMP/a_spectate_done.txt" ] && [ -f "$TMP/b2_spectating.txt" ] && ! grep -q "PUBLIC .* FAIL" "$TMP"/*.log; then echo "public route test OK"; STATUS=0; else echo "public route test FAILED"; tail -6 "$TMP"/a.log "$TMP"/b.log "$TMP"/b2.log; fi
exit $STATUS
