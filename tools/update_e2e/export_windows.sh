#!/bin/bash
# Exports the two Windows builds for the Windows end-to-end update test (run on the Mac mini from the project root):
#   tools/update_e2e/export_windows.sh   ->  $E2E_DIR/win/{a,b}/KyttusLab-Windows-Debug.zip (exe + pck) and serve/updates.debug.json
set -u
GODOT="${GODOT_BIN:-$HOME/Applications/Godot.app/Contents/MacOS/Godot}"
NODE="${NODE_BIN:-node}"
WORK="${E2E_DIR:-$HOME/update-e2e}/win"
REV_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
REV_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
rm -rf "$WORK"; mkdir -p "$WORK/a/pkg" "$WORK/b/pkg" "$WORK/serve"
build() {   # rev, number, dir
  LASTROUTE_BUILD_REVISION=$1 LASTROUTE_BUILD_NUMBER=$2 "$NODE" scripts/generate_build_revision.mjs >/dev/null || return 1
  "$GODOT" --headless --path . --export-debug "Windows Debug Tools" "$3/pkg/KyttusLab.exe" > "$3/export.log" 2>&1
  [ -s "$3/pkg/KyttusLab.exe" ] || return 1
  (cd "$3/pkg" && zip -qr ../KyttusLab-Windows-Debug.zip .)
}
build $REV_A 100 "$WORK/a" || { echo "E2E FAIL export A"; tail -20 "$WORK/a/export.log"; exit 1; }
build $REV_B 101 "$WORK/b" || { echo "E2E FAIL export B"; tail -20 "$WORK/b/export.log"; exit 1; }
rm -f build_revision.json
cp "$WORK/b/KyttusLab-Windows-Debug.zip" "$WORK/serve/"
SHA=$(shasum -a 256 "$WORK/serve/KyttusLab-Windows-Debug.zip" | cut -d' ' -f1)
BYTES=$(stat -f%z "$WORK/serve/KyttusLab-Windows-Debug.zip")
cat > "$WORK/serve/updates.debug.json" <<JSON
{"debug": {"windows": {"version": "0.0.1.0", "revision": "$REV_B", "build": 101, "file": "KyttusLab-Windows-Debug.zip",
 "bytes": $BYTES, "sha256": "$SHA", "notes": "E2E", "required": false}}}
JSON
echo "E2E exported windows A and B to $WORK"
