#!/bin/bash
# Two-process content-pack handshake (scripts/pack_smoke.gd): a guest with the host's pack adopts it, one without it is
# refused with the pack named. Usage: scripts/pack_smoke.sh [godot binary]
set -u
GODOT="${1:-godot4}"
GUARD="$HOME/Developer/Claude-Setup/guard.pl"
cd "$(dirname "$0")/.."
rc=0
for scenario in match missing; do
	perl "$GUARD" 60 "$GODOT" --headless --path . res://scenes/pack_smoke.tscn -- host "$scenario" &
	host=$!
	sleep 2
	perl "$GUARD" 60 "$GODOT" --headless --path . res://scenes/pack_smoke.tscn -- client "$scenario" || rc=1
	wait "$host" || rc=1
done
exit $rc
