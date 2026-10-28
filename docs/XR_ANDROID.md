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

## Touch controls (phones)

`TouchControls` (`src/ui/touch_controls.gd`) is a CanvasLayer the run scene attaches only when `PlatformProfile.is_phone`.
Every control feeds the game's ordinary Input actions, so gameplay, networking and validators see the same inputs a
keyboard makes:

- **Move:** a floating stick anywhere in the left 40 % of the screen sets `move_*` with analogue strength; pushing past the
  ring adds `sprint`.
- **Look:** dragging on the right 60 % calls `PlayerController3D.apply_look_delta`, scaled by the mouse sensitivity setting
  times `TOUCH_LOOK_SCALE`. The mouse motion Godot emulates from touches is ignored on phones.
- **Buttons:**
  - bottom-right: USE, JUMP, DUCK, TOOL and LIGHT;
  - either side of the HUD hotbar: the `hotbar_previous` / `hotbar_next` arrows;
  - top-left: pause, map, bag and chat.
- **Sizing:** buttons are at least `MIN_TARGET` (26 canvas units, about 48 dp) and see-through.

Shots: `touch_controls_2400x1080.png`, `touch_controls_1688x780.png` (`tools/look/touch_capture.gd`).

## XR comfort (Quest)

`XRComfort` (`src/game_3d/xr_comfort.gd`) is built by `PlayerController3D` only after OpenXR has started:

- **World scale:** `XROrigin3D.world_scale = 1.60 / Settings.xr_player_height` (default 1.70 m, clamped 1.0 to 2.3 m), so
  every player sees the world as the 1.60 m runner. **Seated mode** (`xr_seated`) lifts the origin 0.45 m.
- **Turning:** a latched 30 degree snap turn by default, or smooth turn at 120 degrees per second (`xr_smooth_turn`).
- **Vignette:** a soft tunnel on the XR camera while moving or smooth-turning (`xr_vignette`, on by default).
- **Recentre:** `XRServer.center_on_hmd` at start, and on demand through `XRComfort.recenter()`.
- **Wrist HUD:** a Label3D on the left controller showing relays, light charge and stamina, refreshed every 0.25 s.
- **Settings:** saved in the `[xr]` section of the settings file. Desktop and phones never read them.

## XR interactions (Quest)

`XRHands` (`src/game_3d/xr_hands.gd`) is built beside `XRComfort`. Every interaction ends in the player code a keyboard
drives, so networking, sounds and validators see nothing new:

- **Ladders:** on a ladder, hold grip on either hand and pull it down to climb up, hand over hand at 1:1. Push up to climb
  down. The stick still works.
- **Swings:** a fast right-hand swing (2.2 m/s or more) with the crowbar or rescue axe selected swings it. The left grip
  uses the selected tool like a left click.
- **Doors and switches:** the right trigger works whatever the right hand points at, because [E]'s aim follows the hand
  (`PlayerController3D.interaction_aim`). Touching a door, switch or relay with the right fingertip works it too.
- **Flashlight:** the beam comes from the left hand.

Hand positions are read in the origin's own space, so walking, snap turns and the climb itself never count as hand
movement.

**The Quest APK needs the Gradle build.** The prebuilt Android template exports a signed Quest APK, but it carries no
OpenXR loader and no VR manifest entries, so a headset runs it as a flat app. Running in VR needs the Gradle build plus
the Godot OpenXR Vendors plugin (Meta loader), which waits for KT's approval.

## Validators

- `platform`:
  - the desktop run keeps the reference budgets;
  - the phone, low-memory and Quest profiles shrink them;
  - the phone and Quest presets exist with the right XR mode and packages;
  - the touch controls build headless, every button drives an existing action, the stick maps to `move_up` and `sprint`,
    and every target meets the minimum size.
- `platform` also checks the XR comfort maths: world scale, the latched snap turn, proportional smooth turn, and that a
  desktop run builds no comfort node.
- `player` checks that a flat run builds no XR helpers and keeps [E] aimed from the head, the climb and swing maths, and
  that a 0.4 m hand pull moves a real ladder climb by 0.4 m and stops at the foot.
- `player` already checks the OpenXR rig and that XR stays off without the feature.

## Milestones

1. Android flat build boots and plays (this file, `PlatformProfile`, the phone preset).
2. Touch controls and phone UI.
3. Quest standalone: world scale to a 1.60 m player, comfort, wrist HUD.
4. XR interactions: hand climb on ladders, physical tool swings, doors, switches, flashlight in hand.
5. PC VR, once there is VR-capable hardware.
