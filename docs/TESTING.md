# Testing

Godot may not be on `PATH`. Use the full path (or set `GODOT_BIN`):

    /Applications/Godot.app/Contents/MacOS/Godot

After adding or renaming a `class_name` script, refresh the class cache first, otherwise scripts fail with
`Identifier "X" not declared`:

    /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import

## Validators (20 suites)

    Godot --headless --path . res://tests/scenes/validate.tscn              # all suites, takes several minutes
    Godot --headless --path . res://tests/scenes/validate.tscn -- streamed_world maze room   # a subset

The `shader_lights` suite (Intel-Mac light workaround) is headless: it proves the maths and the wiring, not the GPU compile.

Always run it as a scene, never with `--script` (no autoloads there). `tools/build/validate_all.sh` also runs the Node backend tests.

### Known baseline: 9 failures (unchanged by the restyle, blocky hunters, spectators or the room rework)

| Suite | Failure |
| --- | --- |
| layout | `main_menu.tscn BrandLabel overlaps TitleLabel by 210 x 8 px` |
| layout | `hunter dossier is missing populated DossierCounter` |
| hunters | `holding the beam on Aki counted as 3 flashes; a held torch is one` |
| props | `props are not using the shared matte per-vertex block style (4/26)` (locker parts) |

A change is a regression only if it adds to this list.

### Validators and the real user data

The suites call the same code the game does (`PlayerSkin.apply_result`, the `Settings` setters, `RunSaves.write`, `NightWatchSave`,
`SkinSync.sync_own`), which writes the real `user://` files and, for a signed-in account, talks to the live server. A validator once left
a 256-byte test skin (grey checker, 8x8 green square at the head front) as a player's own skin. The likely route: the suite wrote it to
`skin.png`, `SkinSync.sync_own` uploaded it to the signed-in account, and the next start on any computer signed in to that account adopts it. So `tests/validate_runner.gd`
runs every suite behind a guard (`tests/user_guard.gd`):

- **Redirects.** Before the first suite the own skin (`PlayerSkin.own_path`), `Settings.SETTINGS_PATH`, the account file
  (`Backend.account_config_path`), `RunSaves.save_dir` (cloud sync off) and `NightWatchSave.path` point at scratch copies in
  `user://.validate_guard/run-<pid>/scratch`, seeded from the real files. The run is also signed out of the account in memory, so no suite
  can upload a skin or overwrite a route checkpoint. The real login is put back at the end; nothing is written.
- **Snapshot / restore.** Every regular file under `user://` (except `logs`, `crash_queue`, `shader_cache`, `objectdb_snapshots`) is
  copied and hashed first. After each suite the tree is compared; a changed or deleted file is put back byte for byte, a file the suite
  created is removed, and each is printed as `  LEAK  <suite>: changed user://skin.png (restored)`. The in-memory `Settings` values are
  put back too (they are all written together at the next save). `VALIDATE_STRICT_USER=1` turns a leak into a FAIL of that suite.
- **Every exit.** Normal end, compile failure, broken autoload, the watchdog timeout and the tree being freed all restore first. A run that
  is killed leaves its manifest; the next run puts back what that run changed (only files modified up to its last heartbeat, so a change the
  player made later is kept).
- **Concurrent runs.** A run that starts while another is alive keeps the redirects but does not compare files (the other run's scratch
  folders would look like leaks); it prints `another validator run is using user:// right now`. Do not play the game against the same
  `user://` while validators run.
- **Off switches.** `VALIDATE_USER_GUARD=0` disables it (suites then touch the real data again). It is also skipped when `user://` is
  already a throw-away folder: an `APPDATA`/`HOME` under the OS temp folder, or `VALIDATE_USER_ISOLATED=1`, as `tools/build/run_suites.py`
  sets up per worker. The guard only ever touches `user://`.

The `user_guard` suite tests the guard on a fake `user://` folder: a fake skin written through `PlayerSkin.apply_result` must leave
`skin.png`, `settings.cfg`, `skin_hash`, `skin_slim` and `skin_arms` identical after a leaking suite, a failing suite, a cut-short run and a
killed run. Night Watch suites that need a save of their own use `NwLeakProbe.scratch_path()`, never `NightWatchSave.DEFAULT_PATH`. For a
fully separate user folder, also set `APPDATA` (Windows; `HOME`/`XDG_DATA_HOME` elsewhere) to a throw-away directory before launching.

The roster suite does not fail on dossier coverage. `HunterDossier.ENTRIES` is the 26 A-Z texts. The 12 Void hunters are listed in the lobby and pause dossier from `VoidHunterGimmickChart` (`category_ids("void")`), so the UI covers the 38-hunter roster.

## Multiplayer (real processes, local backend)

    tools/build/coop_test.sh     # host + guest + late joiner, reconnect, hunter emote replication, spectators: guest dies, host dies, party wipe, revive
    tools/build/public_test.sh   # PUBLIC route: authority, guest crash/resume, backend restart, hunter emote replication, authority handoff, spectators

Both use free high ports, a temp data dir, and kill their processes by PID. `REMOTE=1 BACKEND_URL=<test instance>` points them at
a hosted test instance (see `backend/README.md`); `KEEP_LOGS=<dir>` (coop) copies the role logs out.

## Visual checks (`dev/look/`)

Non-headless, write PNGs: `capture.tscn` (route rooms), `hunter_check.tscn` (`HUNTERS=`, `HUNTER_STATE=idle|walk|chase|search|stun|scream`),
`jumpscare_check.tscn`, `locker_check.tscn`, `chunk_map.gd` (top-down map: `Godot --headless --path . -s dev/look/chunk_map.gd -- OUT.png [SEED] [CX0 CZ0 CX1 CZ1]`).

Load matters: the multiplayer scripts use wall-clock timeouts and can flake when another Godot job (a validator run in another session) hogs the CPU. Re-run before assuming a regression. Known relay quirk: after the Node backend restarts mid-session, reliable RPCs between the old peers stop arriving (unreliable state and hunter packets still do).
