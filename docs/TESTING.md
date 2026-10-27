# Testing

Godot is not on `PATH` on the dev Mac. Use the full path (or set `GODOT_BIN`):

    /Applications/Godot.app/Contents/MacOS/Godot

After adding or renaming a `class_name` script, refresh the class cache first, otherwise scripts fail with
`Identifier "X" not declared`:

    /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import

## Validators (20 suites)

    Godot --headless --path . res://scenes/validate.tscn              # all suites, takes several minutes
    Godot --headless --path . res://scenes/validate.tscn -- streamed_world maze room   # a subset

Always run it as a scene, never with `--script` (no autoloads there). `scripts/validate_all.sh` also runs the Node backend tests.

### Known baseline: 9 failures (unchanged by the restyle, blocky hunters, spectators or the room rework)

| Suite | Failure |
| --- | --- |
| layout | `main_menu.tscn BrandLabel overlaps TitleLabel by 210 x 8 px` |
| layout | `hunter dossier is missing populated DossierCounter` |
| roster | `dossier covers 26 entries for a 38-hunter roster` |
| hunters | `holding the beam on Aki counted as 3 flashes; a held torch is one` |
| hunters | Zellia shop: menu not returned, and the cool, repair and pesticide trades do not complete (4 failures) |
| props | `props are not using the shared matte per-vertex block style (4/26)` (locker parts) |

A change is a regression only if it adds to this list.

## Multiplayer (real processes, local backend)

    scripts/coop_test.sh     # host + guest + late joiner, reconnect, hunter emote replication, spectators: guest dies, host dies, party wipe, revive
    scripts/public_test.sh   # PUBLIC route: authority, guest crash/resume, backend restart, hunter emote replication, authority handoff, spectators

Both use free high ports, a temp data dir, and kill their processes by PID. `REMOTE=1 BACKEND_URL=<test instance>` points them at
the VPS test instance (see [DEPLOY_VPS3.md](DEPLOY_VPS3.md)); `KEEP_LOGS=<dir>` (coop) copies the role logs out.

## Visual checks (`tools/look/`)

Non-headless, write PNGs: `capture.tscn` (route rooms), `hunter_check.tscn` (`HUNTERS=`, `HUNTER_STATE=idle|walk|chase|search|stun|scream`),
`jumpscare_check.tscn`, `locker_check.tscn`, `chunk_map.gd` (top-down map: `Godot --headless --path . -s tools/look/chunk_map.gd -- OUT.png [SEED] [CX0 CZ0 CX1 CZ1]`).

Load matters: the multiplayer scripts use wall-clock timeouts and can flake when another Godot job (a validator run in another session) hogs the CPU. Re-run before assuming a regression. Known relay quirk: after the Node backend restarts mid-session, reliable RPCs between the old peers stop arriving (unreliable state and hunter packets still do).
