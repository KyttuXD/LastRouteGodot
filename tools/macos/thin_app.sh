#!/usr/bin/env bash
# Thin an exported macOS .zip to one architecture, in place: every binary in *.app/Contents/MacOS is cut down with
# `lipo -thin` (already-thin binaries are left alone) and the app is re-signed ad hoc. Godot's macOS templates, the
# official ones and our encrypted ones alike, only ship *.universal binaries, so every macOS preset exports universal
# and this makes the arm64-only build KT ships (KT's Macs are all Apple Silicon).
# Usage: tools/macos/thin_app.sh <in.zip> [arch=arm64] [out.zip=in.zip]
set -euo pipefail
IN="$1"; ARCH="${2:-arm64}"; OUT="${3:-$1}"
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ditto -x -k "$IN" "$T"
for B in "$T"/*.app/Contents/MacOS/*; do
  [ "$(lipo -archs "$B")" = "$ARCH" ] && continue
  lipo -thin "$ARCH" "$B" -output "$B.thin" && mv "$B.thin" "$B"
done
codesign --force --deep --sign - "$T"/*.app >/dev/null 2>&1
rm -f "$OUT"
( cd "$T" && zip -q -r -y "$OUT" . )
echo "THINNED $ARCH $(basename "$OUT") $(lipo -archs "$T"/*.app/Contents/MacOS/* | sort -u | tr '\n' ' ')"
