#!/bin/bash
# Slow playtest checks (run it directly: tools/build/playtest_check.sh):
#   1. a 60 s game-time bot run on a fixed seed: no stuck/soft-lock/engine error, and the bot finds a relay
#   2. the menu tour (hub -> menu -> lobby -> route -> back to the hub) without engine errors
#   3. determinism: two runs with the same seed and bot seed hash to the same observation at frame 600
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
[ -x "$GODOT" ] || GODOT="$HOME/Applications/Godot.app/Contents/MacOS/Godot"
cd "$ROOT"
fail=0
run() { "$GODOT" --headless --fixed-fps 60 --path . res://dev/playtest/playtest_runner.tscn -- --playtest-runner "$@" 2>&1; }
echo "== 1. bot survives 60 s and finds a relay"
out=$(run --game=last_route --scenario=collect_relays --target=1 --minutes=2 --seed=ALPHA --max-stuck=2 --max-soft-locks=0 --name=check_relay)
echo "$out" | grep "PLAYTEST \(PASS\|FAIL\)"; echo "$out" | grep -q "PLAYTEST PASS" || fail=1
echo "== 2. menu tour"
out=$(run --game=last_route --scenario=menu_tour --seed=ALPHA --name=check_menu)
echo "$out" | grep "PLAYTEST \(PASS\|FAIL\)"; echo "$out" | grep -q "PLAYTEST PASS" || fail=1
echo "== 3. determinism (same seed, same inputs -> same observation hash)"
for n in 1 2; do run --game=last_route --scenario=survive --minutes=0.5 --seed=BRAVO --hash-frames=600 --name=check_hash$n > /dev/null; done
h1=$(grep -o '"state_hash": *[-0-9]*' .playtest/check_hash1/report.json | head -1)
h2=$(grep -o '"state_hash": *[-0-9]*' .playtest/check_hash2/report.json | head -1)
echo "  run1 $h1  run2 $h2"
{ [ -n "$h1" ] && [ "$h1" = "$h2" ]; } || { echo "  FAIL determinism: hashes differ or missing"; fail=1; }
[ "$fail" = 0 ] && echo "playtest_check OK" || echo "playtest_check FAILED"
exit $fail
