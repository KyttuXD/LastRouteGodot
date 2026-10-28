#!/bin/bash
# Live co-op bot test across machines (coop_bot --coop-check): one host, N guests, each windowed on its own Mac, through the TEST
# instance's relay (the real co-op path: no LAN, so macOS Local Network privacy never matters). The tree must already be synced and
# imported in ~/Developer/lanes/<lane> on every machine. The room code is carried from the host to the guests over SSH.
#
#   tools/playtest/coop_airs.sh <lane> <out-dir> <minutes> <host> <guest> [<guest> ...]
# Pulls every peer's report, coop_samples.jsonl and screenshots into <out-dir>/<machine>/; compare with tools/playtest/coop_compare.py.
set -u
LANE="$1"; OUT="$2"; MIN="$3"; HOSTM="$4"; shift 4; GUESTS=("$@")
BACKEND="http://lastroute.kyttuslab.org:8205"
SEED="${SEED:-COOPCHECK}"
G='~/Applications/Godot.app/Contents/MacOS/Godot'
DIR="Developer/lanes/$LANE"
mkdir -p "$OUT"
TIMEOUT=$(( MIN * 60 + 600 ))
run() {  # machine role botseed
  local m="$1" role="$2" seed="$3"
  ssh -o BatchMode=yes "$m" "cd ~/$DIR && rm -rf .share .playtest/coop_$role$seed && mkdir -p .share && ~/.local/bin/guard.pl $TIMEOUT $G --path . --resolution 1280x720 res://scenes/playtest_runner.tscn -- --playtest-runner --game=last_route --scenario=coop_bot --coop-check --role=$role --bot-seed=$seed --seed=$SEED --minutes=$MIN --dir=\$HOME/$DIR/.share --guests=${#GUESTS[@]} --backend=$BACKEND --name=coop_$role$seed > .playtest-coop-$role$seed.log 2>&1; echo \"$m rc=\$?\"" 2>&1 | grep -v zshenv
}
run "$HOSTM" host 0 &
PIDS=($!)
sleep 4
i=1
for g in "${GUESTS[@]}"; do run "$g" guest $i & PIDS+=($!); i=$((i + 1)); done
# carry the room code
code=""
for _ in $(seq 1 120); do
  code=$(ssh -o BatchMode=yes "$HOSTM" "cat ~/$DIR/.share/code.txt 2>/dev/null" 2>/dev/null | tr -d '[:space:]')
  [ -n "$code" ] && break
  sleep 2
done
echo "room code: ${code:-NONE}"
for g in "${GUESTS[@]}"; do ssh -o BatchMode=yes "$g" "printf %s '$code' > ~/$DIR/.share/code.txt" 2>&1 | grep -v zshenv; done
for p in "${PIDS[@]}"; do wait "$p"; done
i=1
pull() { mkdir -p "$OUT/$1"; rsync -a "$1:$DIR/.playtest/$2/" "$OUT/$1/" 2>/dev/null; rsync -a "$1:$DIR/.playtest-coop-$3.log" "$OUT/$1/" 2>/dev/null; }
pull "$HOSTM" coop_host0 host0
for g in "${GUESTS[@]}"; do pull "$g" "coop_guest$i" "guest$i"; i=$((i + 1)); done
for m in "$HOSTM" "${GUESTS[@]}"; do echo "== $m: $(grep -a 'PLAYTEST \(PASS\|FAIL\)' "$OUT/$m"/.playtest-coop-*.log 2>/dev/null | tail -1 | cut -c1-200)"; done
