#!/bin/bash
# End-to-end desktop self-update on macOS (run on the Mac mini, in its GUI session, from the project root):
#   tools/update_e2e/run_mac.sh
# Exports build A (fake commit a…, build 100) and build B (fake commit b…, build 101) with the "macOS Debug Tools" preset,
# serves B from a local backend (127.0.0.1:18105, debug channel), starts A with --backend=… --update-smoke and checks that
# A found, downloaded, verified and swapped in B, kept A in .lastroute-backup-previous, and relaunched. Prints E2E lines.
set -u
GODOT="${GODOT_BIN:-$HOME/Applications/Godot.app/Contents/MacOS/Godot}"
NODE="${NODE_BIN:-node}"
WORK="${E2E_DIR:-$HOME/update-e2e}"
PORT=18105
REV_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
REV_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
rm -rf "$WORK"; mkdir -p "$WORK/a" "$WORK/b" "$WORK/serve" "$WORK/install"
export_build() {   # $1 revision, $2 build number, $3 out dir
  LASTROUTE_BUILD_REVISION=$1 LASTROUTE_BUILD_NUMBER=$2 "$NODE" scripts/generate_build_revision.mjs >/dev/null || return 1
  "$GODOT" --headless --path . --export-debug "macOS Debug Tools" "$3/KyttusLab-macOS-Debug.zip" > "$3/export.log" 2>&1
  [ -s "$3/KyttusLab-macOS-Debug.zip" ]
}
export_build $REV_A 100 "$WORK/a" || { echo "E2E FAIL export A"; tail -20 "$WORK/a/export.log"; exit 1; }
export_build $REV_B 101 "$WORK/b" || { echo "E2E FAIL export B"; tail -20 "$WORK/b/export.log"; exit 1; }
git checkout -- build_revision.json 2>/dev/null || rm -f build_revision.json
cp "$WORK/b/KyttusLab-macOS-Debug.zip" "$WORK/serve/"
SHA=$(shasum -a 256 "$WORK/serve/KyttusLab-macOS-Debug.zip" | cut -d' ' -f1)
BYTES=$(stat -f%z "$WORK/serve/KyttusLab-macOS-Debug.zip")
cat > "$WORK/serve/updates.debug.json" <<JSON
{"debug": {"macos": {"version": "0.0.1.0", "revision": "$REV_B", "build": 101, "file": "KyttusLab-macOS-Debug.zip",
 "bytes": $BYTES, "sha256": "$SHA", "notes": "E2E", "required": false}}}
JSON
LASTROUTE_HTTP_PORT=$PORT LASTROUTE_RELAY_PORT=18106 LASTROUTE_UPDATE_DIR="$WORK/serve" \
  LASTROUTE_UPDATE_MANIFEST="$WORK/serve/updates.debug.json" LASTROUTE_ACCOUNT_STORE="$WORK/accounts.json" \
  "$NODE" backend/server.mjs > "$WORK/backend.log" 2>&1 &
BACKEND=$!
sleep 2
curl -s "http://127.0.0.1:$PORT/api/updates/debug/macos" | head -c 300; echo
(cd "$WORK/install" && ditto -x -k "$WORK/a/KyttusLab-macOS-Debug.zip" .)
APP=$(ls -d "$WORK/install"/*.app | head -1)
EXE=$(ls "$APP/Contents/MacOS/" | head -1)
echo "E2E installed A: $APP"
"$APP/Contents/MacOS/$EXE" -- --backend=http://127.0.0.1:$PORT --update-smoke > "$WORK/a-run.log" 2>&1 &
GAME=$!
for i in $(seq 1 120); do
  sleep 1
  kill -0 $GAME 2>/dev/null || break
done
grep -a "UPDATE_SMOKE" "$WORK/a-run.log" | head -20
sleep 6
NEW_PIDS=$(pgrep -f "$APP/Contents/MacOS/" || true)
echo "E2E relaunched pids: ${NEW_PIDS:-none}"
[ -d "$WORK/install/.lastroute-backup-previous" ] && echo "E2E backup kept: $(ls "$WORK/install/.lastroute-backup-previous")" || echo "E2E FAIL no backup"
NEW_SHA=$(cd "$WORK" && rm -rf check && mkdir check && cd check && ditto -x -k "$WORK/b/KyttusLab-macOS-Debug.zip" . && \
  shasum -a 256 */Contents/Resources/*.pck | cut -d' ' -f1)
NOW_SHA=$(shasum -a 256 "$APP"/Contents/Resources/*.pck | cut -d' ' -f1)
[ "$NEW_SHA" = "$NOW_SHA" ] && echo "E2E PASS installed app now carries build B's pck" || echo "E2E FAIL installed pck is not B ($NOW_SHA vs $NEW_SHA)"
cat "$WORK/apply-update.log" 2>/dev/null
for p in $NEW_PIDS; do kill $p 2>/dev/null; done
kill $BACKEND 2>/dev/null
echo "E2E done"
