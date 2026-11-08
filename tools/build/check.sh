#!/usr/bin/env bash
# Runs the same checks tools/build/push_to_github.sh runs, without committing or pushing:
# whitespace check, Node backend tests, then the Godot validation scene (the full run takes 10+ minutes).
#   tools/build/check.sh                        everything
#   tools/build/check.sh --godot                only the Godot validation scene
#   tools/build/check.sh vents_view hunters     only the named validation suites (see tests/validate_runner.gd)
# Needs Godot 4 on PATH as godot4/godot; run tools/build/setup_godot.sh first.
set -euo pipefail
cd "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"

GODOT_ONLY=false
if [[ "${1:-}" == "--godot" ]]; then
	GODOT_ONLY=true
	shift
fi
if [[ "$GODOT_ONLY" == false && $# -eq 0 ]]; then
	git diff --check
	if command -v npm >/dev/null 2>&1; then
		npm test
	else
		echo "npm not found; skipping backend tests" >&2
	fi
fi

GODOT="$(command -v godot4 || command -v godot || true)"
[[ -n "$GODOT" ]] || { echo "Godot 4 not found; run tools/build/setup_godot.sh" >&2; exit 1; }
# a fresh clone has no .godot/ import cache yet; the validators load imported models and textures
[[ -d .godot/imported ]] || "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
if [[ $# -gt 0 ]]; then
	"$GODOT" --headless --path . res://tests/scenes/validate.tscn -- "$@"
else
	"$GODOT" --headless --path . res://tests/scenes/validate.tscn
fi
