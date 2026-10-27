# Night Watch: one office per mode (the OFFICE CONTRACT)

Every mode of the 2D game has its own office picture (`games/night-watch/assets/offices/<office>.png`, the `office:` field of each mode in
`src/modes/registry.js`). In 3D every mode gets its own **office scene** too, all different, built to one contract so the framework, the menus
and the validators treat them alike. Classic's security room is the reference implementation.

## The contract

Code: `src/night_watch/office/` (`night_watch_office_spec.gd`, `night_watch_office_base.gd`, `night_watch_office_registry.gd`); validator suite
`night_watch_offices` (`scripts/validate_night_watch_offices.gd`).

An office is a script `extends NightWatchOfficeBase` in the mode's own folder (`src/night_watch/<mode>/<mode>_office.gd`) with
`static func make_spec() -> NightWatchOfficeSpec` and `_make_spec()` returning it, plus `build()`. Registered with one line in
`NightWatchOfficeRegistry.OFFICES` (`script`). The spec carries:

| Field | Meaning |
|---|---|
| `id`, `title`, `mode_ids` (`rotation` for Mixed Shift) | unique office id; the mode(s) using it; one office per mode |
| `footprint` (Rect2, XZ, local), `spawn` | the walkable floor and where the player starts; the spawn must lie inside |
| `entrances` | `[{id, kind, position, outward, sim_room, blockable}]`: where hunters/vents/hatches reach the office. `kind` in `door_slab, door_wood, curtain, hatch, vent, window, stairs, lift, gate, opening`; `sim_room` is the node of the mode's graph that arrives here; `blockable` says the player can shut it. The mode's connected map (NightWatchPaths-style waypoints) ends at these positions |
| `required_stations` | station ids the office must expose in `stations` (NightWatchStation nodes: monitor, chair, lamp, door buttons, breaker, radio, hatch ...) |
| `has_monitor` | false for offices with no camera monitor (Bedtime: listen only); then `monitor` is not required |
| `mood` | `{kind: warm_lamp / cold_monitor / emergency_red / daylight / night_outdoor / dusk / fluorescent, ambient, lamp, accent}` |
| `tone_cue` | room tone: one of the shared `NightWatchSounds.CUES` |
| `controls` | the quick-key actions that apply here (others are hidden from the hint line and the controls tab) |
| `references` | 2D screenshot and concept image paths for this doc |

Runtime interface (`NightWatchOfficeBase`): `spec`, `stations`, `props`, `build()`, `spawn_position()`, `entrance_position(id)`, `entrance_outward(id)`,
`light_count()`. The mode's game scene makes its office with `NightWatchOfficeRegistry.make(mode_id)` and wires `stations[...].on_activate`.

Rules for an office:
* New files only; never edit another office or another lane's folder. Cubes only through `NightWatchArt.box` (baked shading, one texel density, hazard tape only
  where a hazard sign belongs); interactables are `NightWatchStation`; solid things have a layer-1 `StaticBody3D`.
* Real lights: at most `NightWatchOfficeSpec.MAX_REAL_LIGHTS` (3) on at once, no shadow casters (docs/REF_LOOK.md budget).
* Shared player (`scenes/night_watch_player.tscn`), shared prompt, crosshair and sounds. Hunters reach the entrances by path (`NightWatchPaths` pattern); no teleports.
* Walkable: the suite does a capsule flood fill from the spawn: it must reach every station (within 3 m) and every entrance (within 2.5 m); no blocked spawn,
  no split room.
* Capture: one image from the entrance and one from the desk (or the mode's main station) in `docs/night_watch_offices/<id>_door.png` / `_desk.png`.
* The registry validator requires distinct office ids for all nine modes; set `REQUIRE_ALL_BUILT = true` there when the last office lands.

## Who builds what, and from which 2D identity

| Mode (2D `office`) | Office id | Concept (from the 2D mode) | Entrances | Monitor | Lane |
|---|---|---|---|---|---|
| Classic (`classic`) | `classic_security` | the existing security room: two steel doors with panels and lights | doorL, doorR (slab) | yes | built (this lane); polish here |
| Masked Hours (`mask`) | `front_office` | the day-shift front office / reception with a mask rack: no doors, hall hunters walk in | hall opening, vents | yes | B (nw-modes-b) |
| Dead Air (`lure`) | `broadcast_booth` | a radio / broadcast booth: reboot panels, vent and a climate dial, glass window | vent, window, door | yes (systems panel) | A (nw-modes-a) |
| Bedtime (`bedroom`) | `child_bedroom` | a child's bedroom with a closet, a bed and a hall door: listen, no cameras | closet, hall door, bed | no | A |
| The Facility (`story`) | `control_room` | a control room: a wall of monitors and task panels, six rooms of tasks | door, lift, vent | yes (wall) | A |
| The Descent (`descent`) | `lift_landing` | an elevator cabin / shaft landing: wires, signal panel, pipes, a window | window, hatch | no | C (nw-modes-c): **built** |
| Salvage Run (`dayshift`) | `cargo_bay` | a cargo bay / workshop: a rack to salvage from, a budget desk, doors and a window | two doors, window | yes | B |
| Open Air (`extra`) | `watch_post` | an outdoor guard booth / roof / bus stop / campfire (three watches): daylight and night outdoor | opening, edge, path | no | C (nw-modes-c): **built** |
| Mixed Shift (`mixed`) | `hub_office` | rotates through the set (one office per hour, drawn by the pacing director) or the Classic building hub | per office | yes | this lane |

Each lane chooses and documents its own offices in this file (a row of its own, with the 2D screenshot next to the 3D concept) and implements them in its
own folder. Mixed Shift's `rotation` lists the office ids it cycles.


## Lane C: `lift_landing` (The Descent) and `watch_post` (Open Air)

Both are built from their mode's own world class (`NightWatchDescentWorld`, `NightWatchOpenAirWorld`) wrapped by a `NightWatchOfficeBase` script in the mode's folder
(`src/night_watch/descent/descent_office.gd`, `src/night_watch/openair/openair_office.gd`); the game scenes make them with `NightWatchOfficeRegistry.make(mode)`. Neither has a
monitor. Entrance positions are the last waypoints of the hunters' graphs (Elise at the glass, Verrine at the stair door and hatch, Wynelle at the shelter, the campfire's three).
`NwOfficeWalk` (`scripts/nw_office_walk.gd`) is the capsule flood fill as a helper: the mode suites run it on every variant (`watch_post` is built three ways, by `watch`).

| Office | 2D (`games/night-watch/assets/offices/`) | 3D, from the entrance | 3D, at the desk / main station |
|---|---|---|---|
| `lift_landing` (descent): car, panel, two caged windows, shaft | ![descent](night_watch_offices/lift_landing_2d.png) | ![door](night_watch_offices/lift_landing_door.png) | ![panel](night_watch_offices/lift_landing_desk.png) |
| `watch_post`, ROOFTOP (`extra`): stair door left, hatch right, lantern post | ![extra](night_watch_offices/watch_post_2d.png) | ![door](night_watch_offices/watch_post_door.png) | ![lantern](night_watch_offices/watch_post_desk.png) |
| `watch_post`, BUS STOP: shelter, heat lamp, canisters, the road | ![bus stop](night_watch_offices/watch_post_busstop_2d.png) | ![road](night_watch_offices/watch_post_busstop_door.png) | ![lamp](night_watch_offices/watch_post_busstop_desk.png) |
| `watch_post`, CAMPFIRE: fire, log pile, firewood, tent, torch posts | ![campfire](night_watch_offices/watch_post_campfire_2d.png) | ![trees](night_watch_offices/watch_post_campfire_door.png) | ![fire](night_watch_offices/watch_post_campfire_desk.png) |

Captures: `tools/look/night_watch_offices_c_capture.tscn` (run with `--scene ... -- OUT_DIR` on the mini).
