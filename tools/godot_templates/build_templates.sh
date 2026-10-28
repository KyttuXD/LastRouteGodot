#!/bin/bash
# Encrypted Godot 4.7.2 export templates on KT-Mini4-2 (docs/XR_ANDROID.md, "Encrypted player builds"). Lives in the repo at
# tools/godot_templates/build_templates.sh; run it from ~/Developer/godot-build with the official source checked out in ./godot.
#   build_templates.sh macos|ios|android|windows
# Reads the PCK key from ~/Developer/secrets/godot_pck.key into SCRIPT_AES256_ENCRYPTION_KEY (never printed).
# The game renders with the Compatibility (OpenGL) renderer, so macOS/iOS templates skip Vulkan/MoltenVK and ANGLE.
# Output: ~/Developer/godot-build/templates/<platform>/...
set -euo pipefail
PLATFORM="${1:?platform}"
SRC="$HOME/Developer/godot-build/godot"
OUT="$HOME/Developer/godot-build/templates"
SCONS="$HOME/Library/Python/3.9/bin/scons"
export SCRIPT_AES256_ENCRYPTION_KEY="$(tr -d '\n' < "$HOME/Developer/secrets/godot_pck.key")"
# Speed-ups (KT, 2026-10-28): every core, a shared scons cache so rebuilds only recompile what changed, release
# templates only (Player Release exports are release; Android keeps debug because Gradle's template packaging needs
# both), macOS arm64-only (KT's Macs are all Apple Silicon). TARGETS / MACOS_ARCHS override.
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
export SCONS_CACHE="${SCONS_CACHE:-$HOME/Developer/godot-build/cache}"
mkdir -p "$SCONS_CACHE"
TARGETS="${TARGETS:-template_release}"
# Intel Macs only on request (KT): MAC_UNIVERSAL=1 builds arm64 + x86_64 and joins them.
MACOS_ARCHS="${MACOS_ARCHS:-arm64}"
[ "${MAC_UNIVERSAL:-0}" = 1 ] && MACOS_ARCHS="arm64 x86_64"
STARTED=$(date +%s)
echo "TEMPLATES_START $PLATFORM $(date '+%F %T') jobs=$JOBS targets=$TARGETS"
cd "$SRC"
mkdir -p "$OUT/$PLATFORM"
case "$PLATFORM" in
  macos)
    for target in $TARGETS; do
      parts=()
      for arch in $MACOS_ARCHS; do
        "$SCONS" platform=macos arch=$arch target=$target -j"$JOBS" debug_symbols=no vulkan=no angle=no
        parts+=("bin/godot.macos.$target.$arch")
      done
      lipo -create "${parts[@]}" -output bin/godot.macos.$target.universal
    done
    # A release-only build reuses the release binary for the debug slot (the template app needs both names).
    [ -f bin/godot.macos.template_debug.universal ] || cp bin/godot.macos.template_release.universal bin/godot.macos.template_debug.universal
    rm -rf "$OUT/macos/macos_template.app"
    cp -R misc/dist/macos_template.app "$OUT/macos/"
    mkdir -p "$OUT/macos/macos_template.app/Contents/MacOS"
    cp bin/godot.macos.template_release.universal "$OUT/macos/macos_template.app/Contents/MacOS/godot_macos_release.universal"
    cp bin/godot.macos.template_debug.universal "$OUT/macos/macos_template.app/Contents/MacOS/godot_macos_debug.universal"
    chmod +x "$OUT/macos/macos_template.app/Contents/MacOS/"*
    (cd "$OUT/macos" && rm -f macos.zip && zip -q -9 -r macos.zip macos_template.app)
    ;;
  ios)
    for target in $TARGETS; do
      "$SCONS" platform=ios arch=arm64 target=$target -j"$JOBS" debug_symbols=no vulkan=no generate_bundle=yes
    done
    cp bin/godot_ios.zip "$OUT/ios/ios.zip" 2>/dev/null || cp bin/*ios*.zip "$OUT/ios/" 
    ;;
  android)
    export ANDROID_HOME="$HOME/Developer/android-sdk"
    export JAVA_HOME="$HOME/Developer/jdk/jdk-17.0.21+9/Contents/Home"
    for target in template_release template_debug; do   # Gradle's template packaging needs both
      "$SCONS" platform=android arch=arm64 target=$target -j"$JOBS" debug_symbols=no
    done
    (cd platform/android/java && ./gradlew --no-daemon generateGodotTemplates)
    cp bin/android_source.zip bin/android_release.apk bin/android_debug.apk "$OUT/android/"
    ;;
  windows)
    for target in $TARGETS; do
      "$SCONS" platform=windows arch=x86_64 target=$target -j"$JOBS" debug_symbols=no use_mingw=yes ${MINGW_LLVM:+use_llvm=yes}
    done
    cp bin/godot.windows.template_release.x86_64.exe "$OUT/windows/windows_release_x86_64.exe"
    [ -f bin/godot.windows.template_debug.x86_64.exe ] && cp bin/godot.windows.template_debug.x86_64.exe "$OUT/windows/windows_debug_x86_64.exe"
    ;;
esac
echo "TEMPLATES_DONE $PLATFORM $(date '+%F %T') took $(( ($(date +%s) - STARTED) / 60 )) min"
ls -la "$OUT/$PLATFORM"
