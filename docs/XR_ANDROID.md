# XR and Android

The game runs on desktop (the reference), on Android phones (flat, touch) and on XR headsets through OpenXR (Meta Quest
standalone now; PC VR later). Desktop behaviour never changes: everything else sits behind the platform flags below.

## Flags

- `PlatformProfile` (autoload, `src/autoload/platform_profile.gd`) reads the device class once at boot:
  - `is_phone`: Android/mobile and not XR, or `--touch`.
  - `is_xr`: the `xr` export feature or `--xr`. `PlayerController3D` starts OpenXR and falls back to the flat camera.
  - `is_quest`: the `quest` export feature.
  - `low_memory`: a phone with 4.8 GB of RAM or less, or `--lowmem`.
- **Budgets.** Desktop keeps every reference value: 8 pooled lamps, the scene's camera far plane, storeys parked for
  ladder trips, and the default pixel effect.
  - **Phones:** 4 lamps, far plane 140 m, pixel effect off on first run. A low-memory phone does not pre-build or park
    linked storeys (about 30 MB each), so a ladder trip rebuilds them.
  - **Quest:** 4 lamps, far plane 60 m, no parked storeys.
- **Keep-awake.** Phones and the Quest keep the screen awake.
- **Updater.** Android builds report the update platform `android`. There is no server channel for it, so a sideloaded
  build never self-updates.

## Export presets

- **Android Phone Debug** (`builds/KyttusLab-Android-Debug.apk`): arm64, flat (OpenXR off), feature `phone`, package
  `org.kyttuslab.lastroute.phone`, so it installs next to the Quest build.
- **Meta Quest OpenXR Debug** (`builds/KyttusLab-Quest-Debug.apk`): arm64, OpenXR, features `xr,quest`.
- **Windows SteamVR Debug**: feature `xr` (PC VR; waits for VR-capable hardware).

## Building (KT-Mini4-2 only)

- **Toolchain:** Godot 4.7.2 Android templates (prebuilt, no Gradle build). The Android SDK is at
  `~/Developer/android-sdk` (platform-tools, build-tools 35.0.0, platform android-35). Temurin JDK 17 is at
  `~/Developer/jdk/jdk-17.0.21+9`; the existing JDK 25 is untouched.
- **Debug keystore:** `~/.android/godot-debug.keystore`, with Android's standard debug credentials. It never goes in the
  repo; release signing is a separate, later step.
- **Environment for an export:**
  - `ANDROID_HOME`
  - `JAVA_HOME` (JDK 17)
  - `GODOT_ANDROID_KEYSTORE_DEBUG_PATH`, `_USER` and `_PASSWORD`
- **Install on a device:** `adb install -r builds/KyttusLab-Android-Debug.apk` with the phone on the mini's USB.

## Validators

- `platform`: the desktop run keeps the reference budgets; the phone, low-memory and Quest profiles shrink them; the phone
  and Quest presets exist with the right XR mode and packages.
- `player` already checks the OpenXR rig and that XR stays off without the feature.

## Milestones

1. Android flat build boots and plays (this file, `PlatformProfile`, the phone preset).
2. Touch controls and phone UI.
3. Quest standalone: world scale to a 1.60 m player, comfort, wrist HUD.
4. XR interactions: hand climb on ladders, physical tool swings, doors, switches, flashlight in hand.
5. PC VR, once there is VR-capable hardware.
