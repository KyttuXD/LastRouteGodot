#!/usr/bin/env bash
# macOS/Linux performance pass (windowed; needs the machine's own GPU, so run it ON the test machine, e.g. over SSH
# into a logged-in desktop session). Same benches as perf_pass.ps1, then perf_report.py against the budgets.
#   tools/build/perf_pass.sh                          LOW graphics, route + levels + play + ladder, speed 14, air budgets
#   tools/build/perf_pass.sh --graphics MEDIUM --modes route,levels --seconds 60
#   tools/build/perf_pass.sh --profile proxy          budgets for a fast dev machine
# Godot: $GODOT_BIN, else godot4/godot on PATH, else /Applications/Godot.app/Contents/MacOS/Godot.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"   # no git needed: the Airs have only the macOS git stub

MODES="route,levels,play,ladder"; SECONDS_RUN=90; SPEED=14; SEED="-"; GRAPHICS="LOW"; PROFILE="air"
while [[ $# -gt 0 ]]; do
	case "$1" in
		--modes) MODES="$2"; shift 2 ;;
		--seconds) SECONDS_RUN="$2"; shift 2 ;;
		--speed) SPEED="$2"; shift 2 ;;
		--seed) SEED="$2"; shift 2 ;;
		--graphics) GRAPHICS="$2"; shift 2 ;;
		--profile) PROFILE="$2"; shift 2 ;;
		*) echo "unknown option $1" >&2; exit 2 ;;
	esac
done

GODOT="${GODOT_BIN:-$(command -v godot4 || command -v godot || true)}"
[[ -n "$GODOT" ]] || GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
[[ -x "$GODOT" ]] || { echo "Godot not found (set GODOT_BIN)" >&2; exit 2; }

if pgrep -if "godot" >/dev/null 2>&1; then
	echo "WARNING: another Godot process is running; frame times will be unreliable." >&2
fi

OUT="$PWD/.artifacts/perf/$(date +%Y%m%d-%H%M%S)-${GRAPHICS}"
mkdir -p "$OUT"
[[ -d .godot/imported ]] || "$GODOT" --headless --path . --import >/dev/null 2>&1 || true

{
	echo "host: $(uname -a)"
	# `git`/`python3` on a Mac without the command line tools are stubs that pop an install dialog: probe first
	if [[ "$(uname)" != "Darwin" ]] || xcode-select -p >/dev/null 2>&1; then
		echo "git: $(git rev-parse --short HEAD 2>/dev/null) $(git status -s 2>/dev/null | wc -l | tr -d ' ') changed paths"
	fi
	command -v sysctl >/dev/null && sysctl -n machdep.cpu.brand_string hw.memsize 2>/dev/null
} > "$OUT/machine.txt"

IFS=',' read -ra MODE_LIST <<< "$MODES"
for mode in "${MODE_LIST[@]}"; do
	echo "== bench: $mode (${SECONDS_RUN}s, speed $SPEED, graphics $GRAPHICS)"
	# --graphics must come AFTER `--`: PlatformProfile reads only OS.get_cmdline_user_args() (before it, the flag is ignored)
	"$GODOT" --path . res://dev/look/stream_bench.tscn -- \
		"$OUT" "$mode" "$mode" "$SECONDS_RUN" "$SEED" "$SPEED" --graphics="$GRAPHICS" 2>&1 | tee "$OUT/bench_$mode.log" | grep -E '^(BENCH|TRIP|HITCH|GPU|COLLECT|PLAY|TOGGLE|STARTUP)'
done

if [[ "$(uname)" == "Darwin" ]] && ! xcode-select -p >/dev/null 2>&1; then
	echo "No python3 here (macOS stub); copy $OUT back and run: python tools/build/perf_report.py --profile $PROFILE <dir>"
	echo "Results: $OUT"
	exit 0
fi
echo "== report ($PROFILE budgets)"
python3 tools/build/perf_report.py --profile "$PROFILE" "$OUT" | tee "$OUT/report.txt"
status=${PIPESTATUS[0]}
echo "Results: $OUT"
exit "$status"
