#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
"$godot_binary" --headless --path "$project_root" \
	res://scenes/validate.tscn

echo "FULL GAME VALIDATION OK"
