#!/bin/bash
# Export TEST-SERVER builds (macOS, Windows, Linux) that connect to the TEST instance by default and show the
# TEST SERVER badge, zipped into build/test/ with the build revision in the name. Never committed (build/ is ignored).
#
#   scripts/export_test_multiplayer.sh            all three
#   scripts/export_test_multiplayer.sh macos      one of: macos windows linux
#
# Needs the Godot export templates (installed for 4.7.2). The builds are debug builds with the admin tools gate as usual;
# `--backend=` on the command line still overrides the server.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="$ROOT/build/test"
cd "$ROOT"
mkdir -p "$OUT"
node scripts/generate_build_revision.mjs
REV="$(node -e 'const r=require("./build_revision.json");console.log(String(r.revision||r.build||r.version||"dev").slice(0,10))' 2>/dev/null || echo dev)"
STAMP="$(date +%Y%m%d-%H%M)-$REV"
want="${1:-all}"
export_one() { # preset file zip-name
  rm -f "$OUT/$2"
  "$GODOT" --headless --path "$ROOT" --export-debug "$1" "$OUT/$2"
}
if [ "$want" = all ] || [ "$want" = macos ]; then
  export_one "macOS Test Server" KyttusLab-TEST-macOS.zip
  mv "$OUT/KyttusLab-TEST-macOS.zip" "$OUT/KyttusLab-TEST-$STAMP-macOS.zip"
fi
if [ "$want" = all ] || [ "$want" = windows ]; then
  export_one "Windows Test Server" KyttusLab-TEST-Windows.exe
  (cd "$OUT" && zip -q -FS "KyttusLab-TEST-$STAMP-Windows.zip" KyttusLab-TEST-Windows.exe && rm -f KyttusLab-TEST-Windows.exe)
fi
if [ "$want" = all ] || [ "$want" = linux ]; then
  export_one "Linux Test Server" KyttusLab-TEST-Linux.x86_64
  (cd "$OUT" && zip -q -FS "KyttusLab-TEST-$STAMP-Linux.zip" KyttusLab-TEST-Linux.x86_64 && rm -f KyttusLab-TEST-Linux.x86_64)
fi
rm -f "$ROOT/build_revision.json"
echo "test builds in $OUT:"; ls -la "$OUT"
