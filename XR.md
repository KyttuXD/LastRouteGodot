# OpenXR test track

Last Route now has one optional OpenXR player rig shared by SteamVR and
standalone Android headsets. It is an early hardware-test foundation, not a
claim that the whole game is already comfort-reviewed for VR.

## What works in the first pass

- `XROrigin3D`, stereo `XRCamera3D`, and tracked left/right controllers live on
  the existing `PlayerController3D`; there is no forked VR gameplay scene.
- Left primary stick moves relative to head direction.
- Right primary stick snap-turns in 30-degree steps.
- Right trigger interacts, A/X toggles the flashlight, right grip sprints,
  left stick click crouches, B/Y toggles the map, and the left menu button
  pauses.
- The flashlight follows head aim for now.
- The same executable falls back to the desktop camera if OpenXR was not
  requested or no runtime is available.

The bindings use Godot's compatibility/default OpenXR action names. They must
be verified on actual Quest Touch, Index, Vive, and other intended controllers;
the next input pass should replace the broad default action map with a small
Last Route-specific map.

## SteamVR

The `Windows SteamVR Debug` export has the `xr` feature, so it attempts OpenXR
automatically. Set SteamVR as the active OpenXR runtime, connect the headset,
then launch `builds/LastRoute-Windows-SteamVR-Debug.exe` with its matching
`.pck` beside it. The ordinary Windows build does not start XR. From an editor
or ordinary debug executable, the equivalent opt-in is a user argument after
Godot's separator: `-- --xr`.

Steam distribution will eventually need separate Steam depots/launch options
for desktop and VR and a Steamworks app configuration; OpenXR itself does not
require an OpenVR-specific code path.

## Meta Quest

`Meta Quest OpenXR Debug` is an arm64 Android/OpenXR preset with immersive mode
and Internet/network-state permissions. Building it requires:

1. OpenJDK 17 and the Android SDK/platform/build tools configured in Godot.
2. A debug keystore for local APK installation.
3. Developer mode and USB debugging enabled on the headset, plus `adb` access.
4. For store-facing Meta features, install the current Godot OpenXR Vendors
   plugin and switch to a Gradle build. Godot 4.6+ can make a basic portable
   OpenXR APK without it, but the plugin is recommended for vendor/store work.

This workspace does not currently have Java, the Android SDK, `adb`, a Quest,
or a signing identity, so the preset is prepared but its APK cannot yet be
exported or device-verified here. Once configured,
`./scripts/export_test_builds.sh --quest` writes
`builds/LastRoute-Quest-Debug.apk`.

## Hardware-test work still required

- Replace the flat `CanvasLayer` HUD/menu with comfortable world-space panels.
- Make interaction use the right-hand aim pose/raycast instead of head facing.
- Reconcile room-scale head displacement with the capsule so players cannot
  physically lean through walls.
- Add configurable smooth/snap turn, vignette, handedness, seated/standing
  height calibration, and recenter behavior.
- Add visible hands/controllers, haptics, VR-specific pause/admin UI, and
  performance budgets for Quest.
- Test every capture, hiding, vent, map, shop, and Office interaction in a
  headset; forced camera motion must remain prohibited.
