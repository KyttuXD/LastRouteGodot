# iOS build track

LastRoute includes an `iOS Debug Xcode` export preset for iPhone and iPad. It
targets arm64 devices with iOS 12 or newer, uses the existing LastRoute icon,
keeps controller input enabled through Godot's normal input actions, and uses
the bundle identifier `org.kyttuslab.lastroute`.

The game/update version remains frozen at `0.0.1.0`. Apple's bundle metadata
maps that to marketing version `0.0.1`, build `1`, because Apple uses separate
three-part marketing and numeric build fields.

## What is required

Apple requires iOS exports to be produced on macOS with Xcode and the Godot iOS
export templates installed. An Apple Developer membership is also required for
device signing, TestFlight, and App Store distribution. The tracked preset
deliberately leaves the 10-character App Store Team ID empty rather than
guessing or committing somebody else's identity.

On the Mac:

1. Open **Project > Export > iOS Debug Xcode** in Godot.
2. Enter the Apple Developer **App Store Team ID**.
3. Select the appropriate development provisioning profile if Xcode cannot
   manage signing automatically.
4. Run `./scripts/export_ios_xcode.sh`.
5. Unzip `builds/LastRoute-iOS-Debug.zip`, open the generated `.xcodeproj`,
   select a signing team and device, then build from Xcode.

The current gameplay UI assumes a physical controller on touch-only iPhones and
iPads; a dedicated touchscreen movement/action overlay is still a separate UI
task. Bluetooth PlayStation, Xbox, and MFi controllers use the same actions as
the desktop builds.

## Networking and updates

The preset contains a narrow App Transport Security exception for
`lastroute.kyttuslab.org`, because the current primary account/update backend is
the explicitly approved plain-HTTP service on port 8105. Move the backend to
HTTPS and remove this exception before App Store review if possible.

iOS executable updates are delivered through Xcode, TestFlight, or the App
Store. The in-game desktop updater reports `APP STORE UPDATES` on iOS and does
not download or replace the signed application bundle. Local route saves,
settings, and the account session remain in the app's private `user://` sandbox.
