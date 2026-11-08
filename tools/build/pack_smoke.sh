#!/bin/bash
# Content-pack smoke.
#
#   tools/build/pack_smoke.sh [godot binary]
#     Two-process handshake (tests/pack_smoke.gd): a guest with the host's pack adopts it, one without it is
#     refused with the pack named. Uses a watchdog (`timeout`, or the perl script in PACK_SMOKE_GUARD) when available.
#
#   tools/build/pack_smoke.sh examples [godot binary]
#     Validate every published pack under examples/mods with the game's own loader (ModKit.validate), in one
#     headless process. The named packs must exist. Any other sibling directory that has a pack.json is checked
#     too, so a new example cannot skip CI. Folders whose names start with "_" are the refused fixtures and are
#     not required to pass. GODOT_BIN overrides the binary when no argument is given.
set -u
cd "$(dirname "$0")/../.."
ROOT="$(pwd)"

if [ "${1:-}" = "examples" ] || [ "${1:-}" = "--examples" ]; then
	shift
	GODOT="${1:-${GODOT_BIN:-}}"
	if [ -z "$GODOT" ]; then
		if [ -x "$HOME/.local/bin/godot4" ]; then
			GODOT="$HOME/.local/bin/godot4"
		elif command -v godot4 >/dev/null 2>&1; then
			GODOT="$(command -v godot4)"
		elif command -v godot >/dev/null 2>&1; then
			GODOT="$(command -v godot)"
		else
			echo "Godot 4 not found: pass the binary or set GODOT_BIN" >&2
			exit 2
		fi
	fi
	mods="$ROOT/examples/mods"
	# Packs that ship under examples/mods. Every other sibling with a pack.json is checked too.
	required=(
		ember frostbite_aki gentle_grabs library_rooms neon_arcade
		rainy_night record_shop death_lines_plus template poster_shop
	)
	for id in "${required[@]}"; do
		if [ ! -f "$mods/$id/pack.json" ]; then
			echo "missing example pack: $mods/$id/pack.json" >&2
			exit 1
		fi
	done
	log="$(mktemp)"
	trap 'rm -f "$log"' EXIT
	set +e
	"$GODOT" --headless --path "$ROOT" res://tools/modpack/modpack.tscn -- validate-examples "$mods" 2>&1 | tee "$log"
	status=${PIPESTATUS[0]}
	if grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load script|Compile Error|Unicode parsing error' "$log"; then
		echo "example pack smoke: Godot reported a compile or load error" >&2
		status=1
	fi
	if ! grep -q 'EXAMPLE PACKS OK' "$log"; then
		echo "example pack smoke: loader did not accept every published pack" >&2
		status=1
	fi
	exit "$status"
fi

GODOT="${1:-godot4}"
# Optional watchdog: PACK_SMOKE_GUARD (perl script taking <seconds> <cmd...>), else `timeout`, else none.
run_guarded() {
	if [ -n "${PACK_SMOKE_GUARD:-}" ] && [ -f "$PACK_SMOKE_GUARD" ]; then perl "$PACK_SMOKE_GUARD" 120 "$@"
	elif command -v timeout >/dev/null 2>&1; then timeout 120 "$@"
	else "$@"; fi
}
rc=0
for scenario in match missing; do
	run_guarded "$GODOT" --headless --path . res://tests/scenes/pack_smoke.tscn -- host "$scenario" &
	host=$!
	sleep 2
	run_guarded "$GODOT" --headless --path . res://tests/scenes/pack_smoke.tscn -- client "$scenario" || rc=1
	wait "$host" || rc=1
done
exit $rc
