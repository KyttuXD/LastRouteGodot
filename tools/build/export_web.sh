#!/bin/bash
# Export the HTML5 build (single-threaded: no COOP/COEP headers needed), strip editor-only files and pre-compress it.
#   tools/build/export_web.sh [output dir]        default: build/web   (build/ is git-ignored)
# The result is a static folder you can host on any web server.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="${1:-$ROOT/build/web}"
cd "$ROOT"
mkdir -p "$OUT"
rm -f "$OUT"/index.* 
node tools/build/generate_build_revision.mjs
"$GODOT" --headless --path "$ROOT" --export-debug "Web Debug Tools" "$OUT/index.html"
rm -f "$OUT"/*.import "$OUT"/*.uid "$OUT"/._*
node tools/build/compress_web.mjs "$OUT"
du -sh "$OUT"
