#!/bin/bash
# Builds platform/android/kyttu_installer into addons/kyttu_installer/bin/kyttu_installer.aar (docs/XR_ANDROID.md).
#   tools/android/build_installer_plugin.sh <project dir with android/build installed>
# Uses the Gradle wrapper and godot-lib AAR of that project's Godot Android build template, so no other Gradle or
# Godot download is involved. Needs ANDROID_HOME and JAVA_HOME (JDK 17).
set -euo pipefail
PROJECT="$(cd "${1:?project dir}" && pwd)"
TEMPLATE="$PROJECT/android/build"
[ -x "$TEMPLATE/gradlew" ] || { echo "no Godot Android build template in $TEMPLATE" >&2; exit 1; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -R "$PROJECT/platform/android/kyttu_installer/." "$WORK/"
cp "$TEMPLATE/gradlew" "$WORK/"
cp -R "$TEMPLATE/gradle" "$WORK/"
echo "sdk.dir=$ANDROID_HOME" > "$WORK/local.properties"
(cd "$WORK" && ./gradlew --no-daemon --quiet assembleRelease -PgodotLib="$TEMPLATE/libs/release/godot-lib.template_release.aar")
mkdir -p "$PROJECT/addons/kyttu_installer/bin"
cp "$WORK/build/outputs/aar/"*release*.aar "$PROJECT/addons/kyttu_installer/bin/kyttu_installer.aar"
echo "built addons/kyttu_installer/bin/kyttu_installer.aar"
