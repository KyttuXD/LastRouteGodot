#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
godot_binary="${GODOT_BIN:-}"

if [[ -z "$godot_binary" ]]; then
	if command -v godot4 >/dev/null 2>&1; then
		godot_binary="$(command -v godot4)"
	elif command -v godot >/dev/null 2>&1; then
		godot_binary="$(command -v godot)"
	else
		echo "Godot not found. Set GODOT_BIN=/absolute/path/to/godot4." >&2
		exit 127
	fi
fi

if [[ ! -f "$godot_binary" || ! -x "$godot_binary" ]]; then
	echo "GODOT_BIN does not point to an executable: $godot_binary" >&2
	exit 127
fi

node_binary="${NODE_BIN:-node}"
if ! command -v "$node_binary" >/dev/null 2>&1 && [[ ! -x "$node_binary" ]]; then
	echo "NODE_BIN does not point to an executable: $node_binary" >&2
	exit 127
fi

echo "== import"
"$godot_binary" --headless --path "$project_root" --import

echo "== backend"
"$node_binary" --test "$project_root"/backend/*.test.mjs

echo "== game"
# A GDScript runtime error does not fail a suite by itself (the call just returns a default), so a project that did
# not compile could print PASS. Keep the output and refuse the run if it shows any compile/load error.
game_log="$(mktemp -t lr-validate-game.XXXXXX)"
trap 'rm -f "$game_log"' EXIT
set +e
"$godot_binary" --headless --path "$project_root" \
	res://tests/scenes/validate.tscn 2>&1 | tee "$game_log"
game_status=${PIPESTATUS[0]}
set -e
if grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load script|Compile Error|res://[^ ]+:[0-9]+ - ' "$game_log"; then
	echo "FAIL: compile/load errors in the game run (a PASS above would be false):" >&2
	grep -E 'SCRIPT ERROR|Parse Error|Failed to load script|Compile Error|res://[^ ]+:[0-9]+ - ' "$game_log" | head -20 >&2
	exit 1
fi
if [[ $game_status -ne 0 ]]; then
	exit "$game_status"
fi

echo "FULL GAME VALIDATION OK"
