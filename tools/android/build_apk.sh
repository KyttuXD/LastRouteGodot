#!/bin/bash
# Android builds through Godot's Gradle template (docs/XR_ANDROID.md), on KT-Mini4-2.
#   tools/android/build_apk.sh phone|quest [source project dir]
# Copies the project into ~/Developer/lanes/android-<target> (never the repo), installs Godot's Android build template
# there on first use, builds the APK installer plugin, adds the OpenXR vendors addon for the Quest (from
# $VENDORS_DIR, default the sha256-checked 5.1.0 cache), and exports builds/KyttusLab-<Target>-Debug.apk.
#
# PUBLISH=1 also stamps the build identity for self-update, in the copy only: build_revision.json gets the git commit
# and build number (git rev-list --count HEAD of $GIT_DIR), and the preset's Android version/code becomes that build
# number. The visible version name is never touched.
#
# Needs ANDROID_HOME, JAVA_HOME (JDK 17) and GODOT_ANDROID_KEYSTORE_DEBUG_PATH / _USER / _PASSWORD.
set -euo pipefail
TARGET="${1:?phone or quest}"
SOURCE="$(cd "${2:-$HOME/Developer/lanes/xr-android}" && pwd)"
GODOT="${GODOT_BIN:-$HOME/Applications/Godot.app/Contents/MacOS/Godot}"
VENDORS_DIR="${VENDORS_DIR:-$HOME/Developer/vendor-cache/godot_openxr_vendors-5.1.0/x/asset/addons/godotopenxrvendors}"
case "$TARGET" in
  phone) PRESET="Android Phone Debug"; OUT="builds/KyttusLab-Android-Debug.apk" ;;
  quest) PRESET="Meta Quest OpenXR Debug"; OUT="builds/KyttusLab-Quest-Debug.apk" ;;
  *) echo "target must be phone or quest" >&2; exit 1 ;;
esac
BUILD="$HOME/Developer/lanes/android-$TARGET"
mkdir -p "$BUILD"
rsync -a --delete --exclude /.godot --exclude /.git --exclude /builds --exclude /android \
  --exclude /addons/godotopenxrvendors --exclude /addons/kyttu_installer/bin "$SOURCE/" "$BUILD/"
cd "$BUILD"
if [ "$TARGET" = quest ]; then
  mkdir -p addons
  rsync -a --delete "$VENDORS_DIR/" addons/godotopenxrvendors/
fi
/usr/bin/python3 - "$TARGET" "$PRESET" <<'PY'
import re, sys
target, preset = sys.argv[1], sys.argv[2]
plugins = ['"res://addons/kyttu_installer/plugin.cfg"']
if target == "quest":
    plugins.append('"res://addons/godotopenxrvendors/plugin.cfg"')
p = "project.godot"; t = open(p).read()
if "[editor_plugins]" not in t:
    t = t.rstrip() + "\n\n[editor_plugins]\n\nenabled=PackedStringArray()\n"
for plugin in plugins:
    if plugin not in t:
        t = re.sub(r"enabled=PackedStringArray\(", "enabled=PackedStringArray(" + plugin + ", ", t, count=1)
t = t.replace(", )", ")")
open(p, "w").write(t)
if target == "quest":
    p = "export_presets.cfg"; t = open(p).read()
    start = t.index('name="%s"' % preset)
    opt = t.index("options]", start)
    end = t.find("\n[preset.", opt)
    end = len(t) if end < 0 else end
    block = t[opt:end]
    if "xr_features/enable_meta_plugin" not in block:
        block = block.replace("xr_features/xr_mode=1", "xr_features/xr_mode=1\nxr_features/enable_meta_plugin=true")
    t = t[:opt] + block + t[end:]
    open(p, "w").write(t)
PY
if [ "${PUBLISH:-0}" = 1 ]; then
  GIT_DIR_ARG="${GIT_DIR:?PUBLISH=1 needs GIT_DIR (the repo the build comes from)}"
  REVISION="$(git --git-dir="$GIT_DIR_ARG" rev-parse HEAD)"
  NUMBER="$(git --git-dir="$GIT_DIR_ARG" rev-list --count HEAD)"
  printf '{"revision": "%s", "build": %s}\n' "$REVISION" "$NUMBER" > build_revision.json
  /usr/bin/python3 - "$PRESET" "$NUMBER" <<'PY'
import re, sys
preset, number = sys.argv[1], sys.argv[2]
p = "export_presets.cfg"; t = open(p).read()
start = t.index('name="%s"' % preset)
opt = t.index("options]", start)
end = t.find("\n[preset.", opt)
end = len(t) if end < 0 else end
block = re.sub(r"version/code=\d+", "version/code=%s" % number, t[opt:end])
open(p, "w").write(t[:opt] + block + t[end:])
PY
  echo "publish identity: $REVISION build $NUMBER"
fi
mkdir -p builds
INSTALL=""
[ -d android/build ] || INSTALL=--install-android-build-template
if [ -n "$INSTALL" ]; then
  # The first export installs the template; the installer plugin builds against it, then the real export follows.
  "$GODOT" --headless --path . $INSTALL --export-debug "$PRESET" "$OUT" > /tmp/android-$TARGET-template.log 2>&1 || true
fi
bash tools/android/build_installer_plugin.sh "$BUILD"
"$GODOT" --headless --path . --editor --quit > /tmp/android-$TARGET-import.log 2>&1 || true
rm -f "$OUT"
"$GODOT" --headless --path . --export-debug "$PRESET" "$OUT" > /tmp/android-$TARGET-export.log 2>&1 || true
[ -f "$OUT" ] || { grep -iE "error|fail" /tmp/android-$TARGET-export.log | tail -20 >&2; exit 1; }
echo "$BUILD/$OUT"
