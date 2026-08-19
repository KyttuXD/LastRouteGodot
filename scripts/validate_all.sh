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

echo "== import"
"$godot_binary" --headless --path "$project_root" --import

echo "== backend"
node --test "$project_root"/backend/*.test.mjs

echo "== game"
"$godot_binary" --headless --path "$project_root" \
	res://scenes/validate.tscn

echo "FULL GAME VALIDATION OK"
