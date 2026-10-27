# Build, export and distribution

## Exports
`export_presets.cfg` carries debug-tools presets for Linux, Windows (64 and legacy 32-bit), macOS (Universal 2), Web (solo only) and Quest/iOS (see
[../XR.md](../XR.md), [../IOS.md](../IOS.md)). `scripts/export_test_builds.sh` exports every current artifact into `builds/`, writes the updater ZIPs and
manifest. It looks for `godot4`, then `godot` on `PATH`; on the dev Mac put `/Applications/Godot.app/Contents/MacOS` on `PATH` or symlink it. Export
templates for the installed Godot version must be present. `builds/`, `dist/` and `build_revision.json` are never committed.

## Updater
Builds check the primary backend for a channel/platform manifest (frozen game version plus Git revision), download the matching ZIP and verify its SHA-256.
Details: root [README.md](../README.md) and `backend/README.md`.

## Backend
Co-op and the PUBLIC route need only the Node service (no Godot server export). Production and a test instance both run on VPS 3 under
`kyttuslab.org`: [DEPLOY_VPS3.md](DEPLOY_VPS3.md). Point the client or scripts at the test instance with `Backend.test_server_active` / `BACKEND_URL`
(the HUD shows a TEST SERVER badge).

## Downloads page
Players get builds from the downloads page on kyttuslab.org, which is **deployed**: <https://kyttuslab.org/home/downloads/> (also `/downloads/`). It is part of the website repo (`LastRoute`). Its manifest is empty until the first release is published with `scripts/publish-downloads.mjs` in that repo; it then lists the exported ZIPs per platform with checksums. Exported archives go to the site through that script, never into this repo.

## App name (Kyttu's Lab)

The application is "Kyttu's Lab" (`application/config/name`, window title, export `application/name`, Windows product and
file description, Android package name); "The Last Route" is the game inside it. Export artifacts are `KyttusLab-<platform>-...`
(test, beta and debug zips; `scripts/generate_update_manifest.mjs` and `backend/updates.example.json` use the same names).
Kept on purpose: the bundle identifier `org.kyttuslab.lastroute`, all version fields, the backend/service/instance names and repo
names, save formats, and the user data folder: `project.godot` pins it with `config/custom_user_dir_name`
(`Godot/app_userdata/KYTTU- The Last Route`, `godot/...` on Linux), because renaming `config/name` alone would silently move
`user://` and orphan accounts, settings, run saves, per-server sessions and update staging. The `app_name` validator checks it.
A macOS bundle is now `Kyttu's Lab.app`: the in-game updater installs whatever `.app` is in the staged zip, so an old
`KYTTU- The Last Route.app` stays beside it until deleted. The site's project title ("The Last Route (Godot)") is separate.
