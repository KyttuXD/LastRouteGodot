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

- **Android Phone Debug** (`builds/KyttusLab-Android-Debug.apk`, Gradle build): arm64, flat (OpenXR off), feature `phone`, package
  `org.kyttuslab.lastroute.phone`, so it installs next to the Quest build.
- **Meta Quest OpenXR Debug** (`builds/KyttusLab-Quest-Debug.apk`, Gradle build with the OpenXR vendors addon): arm64,
  OpenXR, features `xr,quest`.
- **iPhone Debug** (`builds/ios/`): exports an Xcode project only, with feature `phone` (same profile and touch controls
  as Android), bundle id `org.kyttuslab.lastroute.phone`, and KT's free Personal Team (7-day signing). Build, sign and
  install on the mini with `xcodebuild -allowProvisioningUpdates -allowProvisioningDeviceRegistration` and
  `xcrun devicectl device install app`. The phone must be unlocked, in Developer Mode, and trust the developer
  certificate.
- **Windows SteamVR Debug**: feature `xr` (PC VR; waits for VR-capable hardware).

## Building (KT-Mini4-2 only)

Both Android presets use Godot's Gradle build. Build them with `tools/android/build_apk.sh phone|quest [source dir]`
(the default source is the synced lane `~/Developer/lanes/xr-android`):

- **Build copy:** the script copies the project into `~/Developer/lanes/android-<target>`; the repo never holds
  `android/`, the OpenXR vendors addon or any binary. In that copy it then:
  - installs Godot's Android build template on first use;
  - builds the APK installer plugin (`tools/android/build_installer_plugin.sh`, Gradle offline from the mini's cache);
  - for the Quest, adds the official GodotVR OpenXR Vendors 5.1.0 addon, sha256-checked, from
    `~/Developer/vendor-cache`;
  - exports `builds/KyttusLab-Android-Debug.apk` or `builds/KyttusLab-Quest-Debug.apk`.
- **Toolchain:** Godot 4.7.2 templates and Gradle 8.11.1 (AGP 8.6.1, Kotlin 2.1.21, as the template pins them). The
  Android SDK is at `~/Developer/android-sdk` (platform-tools, build-tools 35.0.0, platform android-35). Temurin JDK 17
  is at `~/Developer/jdk/jdk-17.0.21+9`; the existing JDK 25 is untouched.
- **Debug keystore:** `~/.android/godot-debug.keystore`, with Android's standard debug credentials. It never goes in the
  repo; release signing is a separate, later step.
- **Environment:** `ANDROID_HOME`, `JAVA_HOME` (JDK 17), and `GODOT_ANDROID_KEYSTORE_DEBUG_PATH`, `_USER` and
  `_PASSWORD`.
- **Install:** with the device on the mini's USB, `adb -s <serial> install -r <apk>`. Use the SDK's adb (37.0.1), never
  the one bundled with Meta Quest Developer Hub: two adb versions keep killing each other's server.

## Self-update (phone and Quest)

The git commit is the build identity. A publish stamps `build_revision.json` with the commit and its build number
(`git rev-list --count`), and the Android versionCode becomes that build number in the publish copy only.
`version/name` stays "0.0.1.0" and the repo's `version/code` stays 1.

- **Client (`UpdateManager`):**
  - Phones check the `phone` channel, the Quest the `quest` channel (`platform_key_for`).
  - An update is offered when the published commit differs from this build's and its `build` is higher
    (`mobile_update_needed`); Android refuses a lower versionCode.
  - The APK downloads to `user://updates` with a progress bar and a sha256 check (`parse_manifest` accepts only HTTPS
    or the backend's own file route).
  - It is then handed to Android's installer through the `KyttuInstaller` plugin. The user always confirms on the
    system screen; nothing installs silently.
  - If installs from this app aren't allowed yet, the plugin opens that settings page and the game says where it is
    (on the Quest it also offers installing from the mini).
  - Phone and Quest builds show `VERSION 0.0.1.0 // BUILD <commit>` on the title screen.
- **Installer plugin:** `platform/android/kyttu_installer` (Kotlin; `REQUEST_INSTALL_PACKAGES`). It shares the APK
  through Godot's own FileProvider (`<package>.fileprovider`), and `addons/kyttu_installer` links the built AAR into
  Gradle exports.
- **Device test without a server (debug builds):** copy an APK to the app as `files/self-update-test.apk` with
  `adb shell run-as <package> cp ...` and launch. The game hands it to the installer and logs `SELF_UPDATE_TEST
  <status>`. Remove the file afterwards with `run-as rm`.
- **Server (`backend/server.mjs`):**
  - `/api/updates/<channel>/phone` and `/quest` serve entries with `version`, `revision`, `build`, `file` or `url`,
    `sha256` and `bytes`.
  - An entry without a revision or a positive build number is withheld.
  - Mobile entries are never `required`.
- **Publishing a phone or Quest update:**
  1. On the mini, from a clean checkout of the commit being published:
     `PUBLISH=1 GIT_DIR=<checkout>/.git tools/android/build_apk.sh phone <checkout>` (and `quest`). This prints the
     commit and build number it stamped.
  2. Copy the APKs into `builds/` beside the desktop builds for the same commit.
     `scripts/generate_update_manifest.mjs` adds the `phone` and `quest` entries with `build` from
     `build_revision.json`; `scripts/generate_build_revision.mjs` writes it. One release holds one commit.
  3. Upload the APKs and `updates.debug.json` to the GitHub `debug` release as today; the backend's release sync
     fetches them.
- **Deploying the server change:** VPS 3 runs the backend as the systemd service `lastroute-godot2` and is deployed by
  hand by the coordinator, after KT's approval. Run `deploy/deploy.sh` on the VPS for a dry run, then
  `deploy/deploy.sh --apply` to deploy; `--rollback --apply` returns to the previous release. Nothing redeploys on its
  own. Afterwards check `GET /api/updates/debug/phone`: 404 until a phone APK is published, then the entry with its
  `build`.

## Touch controls (phones)

`TouchControls` (`src/ui/touch_controls.gd`) is a CanvasLayer the run scene attaches only when `PlatformProfile.is_phone`.
Every control feeds the game's ordinary Input actions, so gameplay, networking and validators see the same inputs a
keyboard makes:

- **Move (default: D-pad):** fixed arrows in the bottom-left corner set `move_*` at full strength.
  - Diagonals: touch between two arrows, slide between them, or use two fingers.
  - Sprint: double-tap an arrow and hold it (second press within 0.3 s); it sprints that way until released.
  - Settings → `MOVE: ARROWS / STICK` (phones only, `Settings.touch_move`) swaps in the floating analogue stick, which
    sprints when pushed past its ring.
- **Look:** dragging on any free part of the screen turns the view on every drag event
  (`TouchControls.look_turn` → `PlayerController3D.apply_look_turn`).
  - Screen-independent: a drag across the screen's short side turns 180° at LOOK SPEED 1.0, on any phone.
  - Not scaled by the mouse sensitivity. The mouse motion Godot emulates from touches is ignored on phones.
  - Settings → CONTROLS → TOUCH LOOK (phones only, saved): LOOK SPEED, VERTICAL SPEED, INVERT Y, SMOOTHING (off by
    default; low and high ease the turn in over 30 or 80 ms) and ACCELERATION (a fast flick turns up to 2.5×).
- **Buttons:**
  - bottom-right: USE, JUMP, DUCK, TOOL and LIGHT;
  - either side of the HUD hotbar (measured from its real slots): the `hotbar_previous` / `hotbar_next` arrows;
  - top-left: pause, map, bag and chat.
- **No conflicts:** no movement zone overlaps the hotbar or its arrows. While the inventory is open it gets every touch;
  only BAG and pause stay.
- **Silent:** the buttons carry `silent_ui`, so `Sound` does not give them the menu blip. Every jump or step used to
  beep.
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

## Menus in the headset

The game's screens are 2D, and the root viewport only becomes an XR viewport once the route's player enters XR.
`XRMenuPanel` (`src/ui/xr_menu_panel.gd`, created by `PlatformProfile` only when OpenXR is running) draws the root
viewport's picture on a floating panel 1.5 m in front of the head:

- **Pointer:** a laser from the right controller moves the mouse, and the trigger clicks with ordinary mouse events, so
  every menu works unchanged.
- **Recentre:** the left menu button puts the panel back in front of the head.
- **In a route:** the panel steps aside while a route's XR player owns the view, and comes back when the route ends.

## Screens inside a route (headset)

In a route the root viewport renders in XR, so CanvasLayers no longer reach the eyes. `XRRoutePanel`
(`src/ui/xr_route_panel.gd`, attached by the route when `PlatformProfile.is_xr`) takes over once the player is in XR:

- **Drawing:** every CanvasLayer of the route (HUD, pause menu, map, inventory, chat, story, death moment) draws into
  the panel's own 2D viewport through `CanvasLayer.custom_viewport`, including layers created later.
- **When it shows:** while any of those screens is open (`InfiniteRouteTest._xr_overlay_open`, which also covers the
  escape struggle), as a panel 1.2 m in front of the head.
- **Input:** the right laser and trigger send mouse events to the root viewport. The Controls still belong to it, since
  `custom_viewport` only moves where they are drawn.
- **Scrolling:** on both panels the right stick scrolls what the laser points at. Scroll containers only drag-scroll
  for touch, so this is what reaches ENTER ROUTE on the staging screen.
- **Validator:** `platform` drives it headless. A fake XR player shows the panel only while a screen is open, in front
  of the head, and a laser click presses the button under it.

## Typing in the headset

An immersive OpenXR app gets no system keyboard on the Quest. `XRKeyboard` (`src/ui/xr_keyboard.gd`, owned by
`XRMenuPanel`) shows a key grid whenever a LineEdit has focus: digits, letters, `. ? ! -`, space, delete, case, ENTER
and DONE. It sits clear of the field and is clicked with the laser, so room codes, names and chat can be typed. The keys
never take focus. Inside a route the keyboard draws on the route panel.

## Quest build (Gradle)

The prebuilt Android template carries no OpenXR loader and no VR manifest entries, so the Quest needs:

- `xr/openxr/enabled.quest=true` in `project.godot`. Only builds with the `quest` feature start OpenXR at boot; desktop
  and phones are unaffected.
- **Godot's Gradle build and the official GodotVR OpenXR Vendors addon** (5.1.0, Meta loader). Both live only on the
  mini, outside the repo:
  - the addon is in `~/Developer/vendor-cache/godot_openxr_vendors-5.1.0`, sha256-checked against the release digest;
  - the build directory is `~/Developer/lanes/xr-quest`. It copies the lane, adds the addon, enables the plugin, and
    switches the Quest preset to `use_gradle_build` with `enable_meta_plugin`.
- **Verified on a Quest 3S:** the build starts on the Meta OpenXR runtime at 72/72 FPS and shows the menu panel.

## Validators

- `platform`:
  - the desktop run keeps the reference budgets;
  - the phone, low-memory and Quest profiles shrink them;
  - the phone and Quest presets exist with the right XR mode and packages;
  - the touch controls build headless, default to the D-pad, and each arrow and diagonal maps to the right move actions;
  - a double tap held on an arrow sprints, and nothing overlaps the hotbar or its arrows;
  - the open inventory takes every touch, no touch button plays the menu blip, the stick mode still maps to `move_up` and
    `sprint`, and every target meets the minimum size.
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
