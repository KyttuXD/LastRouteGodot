#!/bin/bash
# Multiplayer bot party on one machine: a LOCAL backend, a host bot and N guest
# bots (headless Godot, real ENet/relay join), each playing the route for --minutes game minutes. Never touches a remote
# server unless you point it there yourself: BACKEND_URL=http://127.0.0.1:8205 REMOTE=1 (see tools/build/_target.sh).
#
#   tools/build/playtest_multi.sh [--guests N] [--minutes M] [--seed S] [--passive-guest] [--name NAME] [--room CODE]
# --room=CODE: guests-only join of a reserved private room that a person already opened on the test server (:8205). Bots never host it.
#   Refuse KATHY (always-on production room), production :8105, and non-reserved-looking codes. Leave when done.
# Reports land in .playtest/<name>/{host,guest1,...}/report.json, the exit code is 0 only when every client passed.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
[ -x "$GODOT" ] || GODOT="$HOME/Applications/Godot.app/Contents/MacOS/Godot"
NODE="${NODE_BIN:-node}"
GUESTS=2; MINUTES=3; SEED=PARTY; PASSIVE=""; NAME=""; ROOM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --guests) GUESTS="$2"; shift ;;
    --minutes) MINUTES="$2"; shift ;;
    --seed) SEED="$2"; shift ;;
    --passive-guest) PASSIVE="--passive" ;;
    --name) NAME="$2"; shift ;;
    --room) ROOM="$(printf '%s' "$2" | tr 'a-z' 'A-Z')"; shift ;;
    --room=*) ROOM="$(printf '%s' "${1#--room=}" | tr 'a-z' 'A-Z')" ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
NAME="${NAME:-multi_${SEED}_${GUESTS}g${ROOM:+_$ROOM}}"
TMP="$(mktemp -d)"
HTTP=${PLAYTEST_HTTP_PORT:-19105}; RELAY=${PLAYTEST_RELAY_PORT:-12105}; HOSTPORT=${PLAYTEST_HOST_PORT:-19511}
PIDS=()
cleanup() { for p in ${PIDS[@]+"${PIDS[@]}"}; do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
cd "$ROOT"
. "$ROOT/tools/build/_target.sh"

# --room: join a reserved private room that a person already hosts on the test server. No bot host; no local backend.
if [ -n "$ROOM" ]; then
  case "$ROOM" in
    KATHY)
      echo "REFUSED: KATHY is the always-on production reserved room. Bots never join it." >&2
      exit 9 ;;
    [A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]) ;;
    *)
      echo "REFUSED: --room=$ROOM is not a five-letter reserved code (e.g. AKIRI)." >&2
      exit 9 ;;
  esac
  if [ "$REMOTE" != 1 ]; then
    echo "REFUSED: --room=$ROOM needs REMOTE=1 against the test server (bots never host a reserved room on a local backend)." >&2
    echo "  REMOTE=1 BACKEND_URL=http://127.0.0.1:8205 $0 --room=$ROOM --guests=$GUESTS" >&2
    exit 9
  fi
  # _target.sh already refuses production unless acknowledged; still hard-refuse 8105 for --room.
  lc="$(printf '%s' "${BACKEND_URL:-}" | tr 'A-Z' 'a-z')"
  case "$lc" in
    *:8105)
      echo "REFUSED: --room never targets production (:8105)." >&2
      exit 9 ;;
  esac
  BACKEND="--backend=$BACKEND_URL"
  echo "playtest_multi --room=$ROOM guests-only against REMOTE $BACKEND_URL (a person hosts; bots never host)"
  OUT="$ROOT/.playtest/$NAME"; rm -rf "$OUT"; mkdir -p "$OUT"
  SHARE="$TMP/share"; mkdir -p "$SHARE"
  printf '%s' "$ROOM" > "$SHARE/code.txt"
  common="--playtest-runner --game=last_route --scenario=coop_bot --seed=$SEED --minutes=$MINUTES --dir=$SHARE --guests=$GUESTS --port=$HOSTPORT --room-code=$ROOM $BACKEND $GODOT_FLAGS"
  GPIDS=()
  for i in $(seq 1 "$GUESTS"); do
    "$GODOT" --headless --fixed-fps 60 --path . res://dev/playtest/playtest_runner.tscn -- $common --role=guest $PASSIVE --bot-seed=$i --out=$OUT/guest$i --name=guest$i > "$OUT/guest$i.log" 2>&1 &
    GPIDS+=($!); PIDS+=($!)
  done
  status=0
  for p in "${GPIDS[@]}"; do wait $p || status=1; done
  echo "== playtest_multi $NAME (guests-only room $ROOM, $GUESTS guests, $MINUTES game min)"
  for log in "$OUT"/*.log; do [ -f "$log" ] && echo "  $(basename "$log"): $(grep 'PLAYTEST \(PASS\|FAIL\|SKIP\)' "$log" | tail -1 | cut -c1-170)"; done
  [ "$status" = 0 ] && echo "playtest_multi OK" || echo "playtest_multi FAILED"
  exit $status
fi

if [ "$REMOTE" = 1 ]; then
  BACKEND="--backend=$BACKEND_URL"; echo "playtest_multi against REMOTE $BACKEND_URL"
else
  HOST=127.0.0.1 LASTROUTE_HTTP_PORT=$HTTP LASTROUTE_RELAY_HOST=127.0.0.1 LASTROUTE_RELAY_PORT=$RELAY LASTROUTE_DATA_DIR="$TMP/data" \
    LASTROUTE_AUTO_UPDATE=false LASTROUTE_RESTART_ON_GITHUB_UPDATE=false "$NODE" index.js > "$TMP/server.log" 2>&1 &
  PIDS+=($!); sleep 2
  BACKEND="--backend=http://127.0.0.1:$HTTP"
fi
OUT="$ROOT/.playtest/$NAME"; rm -rf "$OUT"; mkdir -p "$OUT"
common="--playtest-runner --game=last_route --scenario=coop_bot --seed=$SEED --minutes=$MINUTES --dir=$TMP/share --guests=$GUESTS --port=$HOSTPORT $BACKEND $GODOT_FLAGS"
"$GODOT" --headless --fixed-fps 60 --path . res://dev/playtest/playtest_runner.tscn -- $common --role=host --out=$OUT/host --name=host > "$OUT/host.log" 2>&1 &
HOSTPID=$!; PIDS+=($HOSTPID)
sleep 3
GPIDS=()
for i in $(seq 1 "$GUESTS"); do
  "$GODOT" --headless --fixed-fps 60 --path . res://dev/playtest/playtest_runner.tscn -- $common --role=guest $PASSIVE --bot-seed=$i --out=$OUT/guest$i --name=guest$i > "$OUT/guest$i.log" 2>&1 &
  GPIDS+=($!); PIDS+=($!)
done
status=0
wait $HOSTPID || status=1
for p in "${GPIDS[@]}"; do wait $p || status=1; done
echo "== playtest_multi $NAME ($GUESTS guests, $MINUTES game min)"
for log in "$OUT"/*.log; do echo "  $(basename "$log"): $(grep 'PLAYTEST \(PASS\|FAIL\|SKIP\)' "$log" | tail -1 | cut -c1-170)"; done
[ "$status" = 0 ] && echo "playtest_multi OK" || echo "playtest_multi FAILED"
exit $status
