#!/bin/bash
# Export BETA builds (macOS, Windows, Linux) that connect to the PRODUCTION server (public route and rooms) and show a
# BETA badge, zipped into build/beta/ with the build revision in the name. Never committed (build/ is ignored). No version info is changed.
#
#   scripts/export_beta.sh            all three
#   scripts/export_beta.sh macos      one of: macos windows linux
#
# Needs the Godot export templates (installed for 4.7.2). The builds are debug builds with the admin tools gate as usual;
# `--backend=` on the command line still overrides the server.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="$ROOT/build/beta"
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
  export_one "macOS Beta" KyttusLab-BETA-macOS.zip
  # Apple Silicon only: strip the Intel half of the universal binary (about 85 MB) and re-sign ad hoc.
  ( T="$(mktemp -d)"; unzip -q "$OUT/KyttusLab-BETA-macOS.zip" -d "$T"; for B in "$T"/*.app/Contents/MacOS/*; do lipo -thin arm64 "$B" -output "$B.arm64" && mv "$B.arm64" "$B"; done; codesign --force --deep --sign - "$T"/*.app >/dev/null 2>&1; rm -f "$OUT/KyttusLab-BETA-macOS.zip"; ( cd "$T" && zip -q -r -y "$OUT/KyttusLab-BETA-macOS.zip" . ); rm -rf "$T" )
  mv "$OUT/KyttusLab-BETA-macOS.zip" "$OUT/KyttusLab-BETA-$STAMP-macOS.zip"
fi
if [ "$want" = all ] || [ "$want" = windows ]; then
  export_one "Windows Beta" KyttusLab-BETA-Windows.exe
  (cd "$OUT" && zip -q -FS "KyttusLab-BETA-$STAMP-Windows.zip" KyttusLab-BETA-Windows.exe && rm -f KyttusLab-BETA-Windows.exe)
fi
if [ "$want" = all ] || [ "$want" = linux ]; then
  export_one "Linux Beta" KyttusLab-BETA-Linux.x86_64
  (cd "$OUT" && zip -q -FS "KyttusLab-BETA-$STAMP-Linux.zip" KyttusLab-BETA-Linux.x86_64 && rm -f KyttusLab-BETA-Linux.x86_64)
fi
rm -f "$ROOT/build_revision.json"
echo "beta builds in $OUT:"; ls -la "$OUT"
