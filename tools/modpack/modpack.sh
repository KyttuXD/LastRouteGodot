#!/bin/bash
# Mod starter kit: tools/modpack/modpack.sh init <pack_id> [parent dir] | validate <pack dir> | pack <pack dir>
# Runs the game's own pack loader headless (docs/modding/). GODOT_BIN picks the Godot binary; GUARD (a watchdog
# script) wraps it when set.
set -u
GAME="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT_BIN:-}"
if [ -z "$GODOT" ]; then
	for candidate in /Applications/Godot.app/Contents/MacOS/Godot "$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
			"$(command -v godot4 2>/dev/null)" "$(command -v godot 2>/dev/null)"; do
		if [ -n "$candidate" ] && [ -x "$candidate" ]; then GODOT="$candidate"; break; fi
	done
fi
[ -n "$GODOT" ] || { echo "Godot 4 not found: set GODOT_BIN" >&2; exit 2; }
args=("$@")
# directories given to the kit are made absolute, so they do not resolve against the game folder
case "${1:-}" in
	validate|pack) [ $# -ge 2 ] && args[1]="$(cd "$2" 2>/dev/null && pwd || echo "$2")" ;;
	init) [ $# -ge 3 ] && args[2]="$(mkdir -p "$3" && cd "$3" && pwd)" ;;
esac
if [ -n "${GUARD:-}" ]; then
	exec perl "$GUARD" 300 "$GODOT" --headless --path "$GAME" res://tools/modpack/modpack.tscn -- "${args[@]}"
fi
exec "$GODOT" --headless --path "$GAME" res://tools/modpack/modpack.tscn -- "${args[@]}"
