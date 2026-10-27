#!/bin/bash
# Launch N game instances side by side on this Mac, each with its own profile (separate login + settings files),
# tiled across the screen, pointed at the TEST instance or at a throwaway local backend.
#
#   scripts/run_multi.sh 3 --test        3 windows against http://lastroute.kyttuslab.org:8205 (TEST SERVER badge)
#   scripts/run_multi.sh 2 --local       2 windows against a local backend this script starts (and stops)
#   scripts/run_multi.sh 2 --local --scene res://scenes/infinite_route_test.tscn   (default: the main menu)
#
# Debug builds only (the TEST instance is refused by release builds). Every process is killed by exact PID on exit
# (Ctrl-C closes everything). Profiles are p1..pN: user://settings_pN.cfg, user://last_route_account_pN.cfg.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
N="${1:-2}"; shift || true
MODE=test; SCENE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --test) MODE=test ;;
    --local) MODE=local ;;
    --scene) SCENE="$2"; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
case "$N" in ''|*[!0-9]*) echo "N must be a number" >&2; exit 2 ;; esac
[ "$N" -ge 1 ] && [ "$N" -le 8 ] || { echo "N must be 1..8" >&2; exit 2; }
PIDS=()
TMP="$(mktemp -d)"
cleanup() { for p in ${PIDS[@]+"${PIDS[@]}"}; do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT INT TERM
cd "$ROOT"
if [ "$MODE" = test ]; then
  BACKEND="http://lastroute.kyttuslab.org:8205"
  echo "TEST instance: $BACKEND (UDP relay 1205). Make sure it is installed and the provider firewall allows TCP 8205 / UDP 1205."
else
  HTTP=${MULTI_HTTP_PORT:-18305}; RELAY=${MULTI_RELAY_PORT:-11305}
  HOST=127.0.0.1 LASTROUTE_HTTP_PORT=$HTTP LASTROUTE_RELAY_HOST=127.0.0.1 LASTROUTE_RELAY_PORT=$RELAY \
    LASTROUTE_DATA_DIR="$TMP/data" LASTROUTE_AUTO_UPDATE=false LASTROUTE_RESTART_ON_GITHUB_UPDATE=false \
    node index.js > "$TMP/server.log" 2>&1 &
  PIDS+=($!)
  BACKEND="http://127.0.0.1:$HTTP"
  sleep 2
  echo "local backend on $BACKEND (log: $TMP/server.log)"
fi
# screen size for tiling (Finder desktop bounds), fall back to 1728x1080
BOUNDS=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null || echo "0, 0, 1728, 1080")
SW=$(echo "$BOUNDS" | awk -F', *' '{print $3}'); SH=$(echo "$BOUNDS" | awk -F', *' '{print $4}')
COLS=$(python3 -c "import math;print(math.ceil(math.sqrt($N)))"); ROWS=$(python3 -c "import math;print(math.ceil($N/$COLS))")
W=$((SW / COLS)); H=$(( (SH - 40) / ROWS ))
for i in $(seq 1 "$N"); do
  C=$(( (i - 1) % COLS )); R=$(( (i - 1) / COLS ))
  ARGS=(--path . --position "$((C * W)),$((40 + R * H))" --resolution "${W}x$((H - 28))" --windowed)
  [ -n "$SCENE" ] && ARGS+=("$SCENE")
  "$GODOT" "${ARGS[@]}" -- "--profile=p$i" "--backend=$BACKEND" > "$TMP/p$i.log" 2>&1 &
  PIDS+=($!)
  echo "instance $i: profile p$i, pid $!, window ${W}x$((H - 28)) at $((C * W)),$((40 + R * H))"
done
echo "Close the windows or press Ctrl-C here to stop everything."
wait "${PIDS[@]:1}" 2>/dev/null || wait
