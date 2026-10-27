#!/bin/bash
# Multiplayer bot party on ONE test machine (run it there, e.g. through mini-run.sh --sh): a LOCAL backend, a host bot and N guest
# bots (headless Godot, real ENet/relay join), each playing the route for --minutes game minutes. Never touches production or the TEST
# instance unless you point it there yourself: BACKEND_URL=http://lastroute.kyttuslab.org:8205 REMOTE=1 (see scripts/_target.sh).
#
#   scripts/playtest_multi.sh [--guests N] [--minutes M] [--seed S] [--passive-guest] [--name NAME]
# Reports land in .playtest/<name>/{host,guest1,...}/report.json, the exit code is 0 only when every client passed.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
[ -x "$GODOT" ] || GODOT="$HOME/Applications/Godot.app/Contents/MacOS/Godot"
NODE="${NODE_BIN:-node}"
GUESTS=2; MINUTES=3; SEED=PARTY; PASSIVE=""; NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --guests) GUESTS="$2"; shift ;;
    --minutes) MINUTES="$2"; shift ;;
    --seed) SEED="$2"; shift ;;
    --passive-guest) PASSIVE="--passive" ;;
    --name) NAME="$2"; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
NAME="${NAME:-multi_${SEED}_${GUESTS}g}"
TMP="$(mktemp -d)"
HTTP=${PLAYTEST_HTTP_PORT:-19105}; RELAY=${PLAYTEST_RELAY_PORT:-12105}; HOSTPORT=${PLAYTEST_HOST_PORT:-19511}
PIDS=()
cleanup() { for p in ${PIDS[@]+"${PIDS[@]}"}; do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
cd "$ROOT"
. "$ROOT/scripts/_target.sh"
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
"$GODOT" --headless --fixed-fps 60 --path . res://scenes/playtest_runner.tscn -- $common --role=host --out=$OUT/host --name=host > "$OUT/host.log" 2>&1 &
HOSTPID=$!; PIDS+=($HOSTPID)
sleep 3
GPIDS=()
for i in $(seq 1 "$GUESTS"); do
  "$GODOT" --headless --fixed-fps 60 --path . res://scenes/playtest_runner.tscn -- $common --role=guest $PASSIVE --bot-seed=$i --out=$OUT/guest$i --name=guest$i > "$OUT/guest$i.log" 2>&1 &
  GPIDS+=($!); PIDS+=($!)
done
status=0
wait $HOSTPID || status=1
for p in "${GPIDS[@]}"; do wait $p || status=1; done
echo "== playtest_multi $NAME ($GUESTS guests, $MINUTES game min)"
for log in "$OUT"/*.log; do echo "  $(basename "$log"): $(grep 'PLAYTEST \(PASS\|FAIL\|SKIP\)' "$log" | tail -1 | cut -c1-170)"; done
[ "$status" = 0 ] && echo "playtest_multi OK" || echo "playtest_multi FAILED"
exit $status
