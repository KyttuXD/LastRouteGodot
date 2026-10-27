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
| Masked Hours (`mask`) | `front_office` | the day-shift front office / reception with a mask rack: no doors, hall hunters walk in | hall opening, vents | yes | B: **built** (`mask/mask_office.gd`) |
| Dead Air (`lure`) | `broadcast_booth` | **built** (`src/night_watch/lure/lure_office.gd`): a radio / broadcast booth, foam-lined, a glass window onto a dark studio, a mixing console with the systems monitor, a boom mic, a patch rack, an ON AIR lamp; the two ventilation hatches have slatted covers (the DOOR buttons seal them) and service ducts behind. 2D: ![2D](night_watch_offices/broadcast_booth_2d.png) 3D: ![door](night_watch_offices/broadcast_booth_door.png) ![desk](night_watch_offices/broadcast_booth_desk.png) | vent L, vent R, studio window | yes (systems panel) | A (nw-modes-a) |
| Bedtime (`bedroom`) | `child_bedroom` | **built** (`src/night_watch/bedroom/bedroom_office.gd`): a child's bedroom seen from the pillow, a closet in the west wall, a hall doorway with a long hall in the east wall, the foot of the bed; two flashlight spots, no monitor. 2D: ![2D](night_watch_offices/child_bedroom_2d.png) 3D: ![hall](night_watch_offices/child_bedroom_door.png) ![bed](night_watch_offices/child_bedroom_desk.png) | closet, hall, bed | no | A |
| The Facility (`story`) | `control_room` | **built** (`src/night_watch/story/story_office.gd`): the control room: a wall of monitors either side of the lift door, a task board, the log-in terminal with its number note, the desk you hide under; doorways to the gallery and the workshop. 2D: ![2D](night_watch_offices/control_room_2d.png) 3D: ![lift door](night_watch_offices/control_room_door.png) ![terminal](night_watch_offices/control_room_desk.png) | door L, door R, lift | no camera monitor (the monitor wall station tells the next task) | A |
| The Descent (`descent`) | `lift_landing` | an elevator cabin / shaft landing: wires, signal panel, pipes, a window | window, hatch | no | C (nw-modes-c): **built** |
| Salvage Run (`dayshift`) | `cargo_bay` | a cargo bay / workshop: a rack to salvage from, a budget desk, doors and a window | two doors, window | no monitor (ledger instead) | B: **built** (`dayshift/cargo_bay.gd`) |
| Open Air (`extra`) | `watch_post` | an outdoor guard booth / roof / bus stop / campfire (three watches): daylight and night outdoor | opening, edge, path | no | C (nw-modes-c): **built** |
| Mixed Shift (`mixed`) | `hub_office` | rotates through the set (one office per hour, drawn by the pacing director) or the Classic building hub | per office | yes | this lane / B: **built** as the hub (`mixed/mixed_office.gd`) |

Each lane chooses and documents its own offices in this file (a row of its own, with the 2D screenshot next to the 3D concept) and implements them in its
own folder. Mixed Shift's `rotation` lists the office ids it cycles.

## Lane B offices (Masked Hours, Salvage Run)

Both are subclasses of the Classic room (`NightWatchOffice`, so the desk, chair, lamp and door panels are the same reference mechanics) that override
`_build_shell()` and `_build_wall_props()` and add their own stations; the games build them with `NightWatchOfficeRegistry.make(mode)`.
| Office | 2D (`games/night-watch/assets/offices/`) | 3D, from the entrance | 3D, at the desk / main station |
|---|---|---|---|
| `front_office` (Masked Hours) | ![2D](night_watch_offices/front_office_2d.png) | ![door](night_watch_offices/front_office_door.png) ![desk](night_watch_offices/front_office_desk.png) | FNAF 2 style, its own room (not the Classic security room): a small night guard's office with NO doors, one wide opening straight onto the 15 m MAIN HALL (a velvet rope keeps you in), the desk right in front of you (monitor, mask, music box, lamp, a turning fan, a pizza box), a vent grate in each side wall (left and right air vents) and a decorative front vent above the opening, kids' drawings and a clock; stations `mask`, `musicbox`, `ventL`, `ventR`, `hall_light` (the hall light) |
| `cargo_bay` (Salvage Run) | ![2D](night_watch_offices/cargo_bay_2d.png) | ![door](night_watch_offices/cargo_bay_door.png) ![desk](night_watch_offices/cargo_bay_desk.png) | warm wood panels, green checkerboard, a window in the front wall with a yard outside, pallet racking, crates, a workbench with the four-slot rack (`rack0`..`rack3`), a budget ledger on the desk (`ledger`), the two steel doors and panels; the monitor is off (the 2D mode has no cameras), so `has_monitor` is false |
Lights: Masked Hours has the desk lamp only (vent beams and the hall light are off until held); Salvage Run has the desk lamp (the yard lamp is an emissive cube).
### Mixed Shift: `hub_office`
The Classic building's hub: the Classic security room (doors, panels, desk, monitor, chair, lamp) with the three permanent vents of the 2D Mixed office
(`mixed/mixed_office.gd`, a subclass of `NightWatchOffice`): left and right low on the back wall and one in the ceiling above the desk, each with a shutter (shown while
sealed) and a glowing opening for the vent light (an emissive cube, not a real light). The DOOR buttons stay; the LIGHT buttons are off (the doors' light pulses are the
tell). Entrances: `doorL`, `doorR` (slab), `ventL`, `ventR`, `ventT`. Mixed Shift does not rotate through other offices yet (`rotation` is empty). Lights: the desk lamp.
| `hub_office` (Mixed Shift) | ![2D](night_watch_offices/hub_office_2d.png) | ![door](night_watch_offices/hub_office_door.png) ![desk](night_watch_offices/hub_office_desk.png) |
## Lane C: `lift_landing` (The Descent) and `watch_post` (Open Air)
Both are built from their mode's own world class (`NightWatchDescentWorld`, `NightWatchOpenAirWorld`) wrapped by a `NightWatchOfficeBase` script in the mode's folder
(`src/night_watch/descent/descent_office.gd`, `src/night_watch/openair/openair_office.gd`); the game scenes make them with `NightWatchOfficeRegistry.make(mode)`. Neither has a
monitor. Entrance positions are the last waypoints of the hunters' graphs (Elise at the glass, Verrine at the stair door and hatch, Wynelle at the shelter, the campfire's three).
`NwOfficeWalk` (`scripts/nw_office_walk.gd`) is the capsule flood fill as a helper: the mode suites run it on every variant (`watch_post` is built three ways, by `watch`).
| `lift_landing` (descent): car, panel, two caged windows, shaft | ![descent](night_watch_offices/lift_landing_2d.png) | ![door](night_watch_offices/lift_landing_door.png) | ![panel](night_watch_offices/lift_landing_desk.png) |
| `watch_post`, ROOFTOP (`extra`): stair door left, hatch right, lantern post | ![extra](night_watch_offices/watch_post_2d.png) | ![door](night_watch_offices/watch_post_door.png) | ![lantern](night_watch_offices/watch_post_desk.png) |
| `watch_post`, BUS STOP: shelter, heat lamp, canisters, the road | ![bus stop](night_watch_offices/watch_post_busstop_2d.png) | ![road](night_watch_offices/watch_post_busstop_door.png) | ![lamp](night_watch_offices/watch_post_busstop_desk.png) |
| `watch_post`, CAMPFIRE: fire, log pile, firewood, tent, torch posts | ![campfire](night_watch_offices/watch_post_campfire_2d.png) | ![trees](night_watch_offices/watch_post_campfire_door.png) | ![fire](night_watch_offices/watch_post_campfire_desk.png) |
Captures: `tools/look/night_watch_offices_c_capture.tscn` (run with `--scene ... -- OUT_DIR` on the mini).

## Maps: every mode its own layout

The office is not the only thing that must differ: every mode's MAP (the rooms the hunters walk and the cameras look into) is its own themed layout, never a reskin of Classic's building.
`NightWatchMapRegistry` (`src/night_watch/office/night_watch_map_registry.gd`) has one entry per mode: a script with `static func map_layout() -> Dictionary`
(`{rooms: {id: centre}, edges: [[a, b]], entrances: [room ids the office is reached from], theme: text}`), or `single_space: true` for a mode with no multi-room map (none now: Bedtime has a house wing and Salvage Run a ship / yard).
Validator `night_watch_maps`: no two modes share a layout signature (sorted room centres and edges), no mode shares more than 3 room ids with Classic, every layout is connected from its entrances,
and no mode's map script extends `NightWatchBuilding`. The layout must stay in step with the walking-hunter paths and the office spec entrances. Themes: Bedtime = a house wing (bedroom, hall, kids' room, bathroom, living room, kitchen, stairs / landing, closet), Salvage Run = a ship and yard (cargo bay office, gantry, docks, airlock, engine room, scrap yard, crane, hold, bridge), Masked Hours = a FNAF 2 style
building (not derived from Classic), Dead Air = a radio station / studio floor, The Facility = an industrial complex, The Descent = stairwell / shaft levels, Open Air = open grounds,
Mixed Shift = rotates between the other modes' maps, Classic stays as is.

| Mode | Map script | Layout | Top-down |
|---|---|---|---|
| Dead Air (`lure`) | `src/night_watch/lure/lure_map.gd` (`LureMap`, built by `LureWorld`, walked by `LurePaths`) | a radio station: reception on top of a plus-shaped floor, studio A and B either side of the big live room, the transmitter room below it with the tape library beside it, two crawlspaces out to the booth; rooms of different sizes, doorways in shared walls. The rules graph is unchanged (lobby = reception, arcade = studio A, party = studio B, ballpit = live room, prize = tape library, storage = transmitter, ventl / ventr = the crawlspaces) | ![Dead Air map](night_watch_modes/1280x720_map_lure.png) |
| Bedtime (`bedroom`) | `src/night_watch/bedroom/bedroom_map.gd` (`BedroomMap`; `BedroomOffice` is the bedroom, wardrobe and hall, `BedroomWing` the other rooms, `BedroomPaths` Javelle's route) | a house wing: the bedroom with its wardrobe, a long hall east to the living room (galley beyond), with a kids' room, a bathroom and the stair landing (stairs) off the hall. Mechanics unchanged; Javelle walks from the living room up the hall to the bedroom door and back; no cameras. Single-space no more | ![Bedtime map](night_watch_modes/1280x720_map_bedroom.png) [hall view](night_watch_modes/1280x720_bedroom_hall.png) |
| The Facility (`story`) | `src/night_watch/story/story_map.gd` (`StoryMap`, built by `StoryWorld`) | an industrial complex: the production line of five rooms (breaker room, gallery, control, workshop, auditorium) with the lift north of control. It is the rules' own graph, so the plan is a line with one branch; none of Classic's room ids | ![Facility map](night_watch_modes/1280x720_map_story.png) |

### Map rows (lane B)

| Mode | Map (`map_layout()`) | World | Top-down capture |
|---|---|---|---|
| Masked Hours | `mask/mask_map.gd`: 14 rooms on a hall-and-plaza plan: the Game Area at the heart of the open-plan show floor (Show Stage north, Prize Corner west, Parts / Service east), the 15 m Main Hall south into the door-less office with four Party Rooms off it, Left / Right Halls to the Vent Hub behind the office, two air vent ducts | `mask/mask_world.gd` (own building, AStar graph, no jumps) | ![map](night_watch_modes/mask_map_topdown.png) |
| Salvage Run | `dayshift/dayshift_map.gd`: 9 rooms on a long east-west ship: airlock, dock, gantry, engine room and bridge to the west, gantry and cargo hold to the east, the scrap yard with the crane to the south; Ravelle walks in from the airlock, Ceryth from the hold, Ysolde from the crane to the window | `dayshift/dayshift_yard.gd` (AStar graph over the cargo bay's opened halls) | ![map](night_watch_modes/dayshift_map_topdown.png) |
| Mixed Shift | `mixed/mixed_map.gd`: its own TRANSIT HUB (not Classic's building): a concourse at the heart of the station with the platform and ticket hall to the north, the west and east arcades down both sides to the security office (the two door halls open into them), a cafe between the concourse and the office, lost property and the newsstand at the arcades' south ends, and the vent run as CAM 9 (nine cameras; `cams` / `labels` / `vents` / `office` feed the camera minimap). The golden-tested rules keep Classic's room ids; `MixedMap.SIM_TO_MAP` says which map room each is played in | `mixed/mixed_world.gd` (walls with doorway gaps, AStar graph, feeds) + `hub_office` | ![station](night_watch_modes/mixed_map_station.png) ![party](night_watch_modes/mixed_map_party.png) ![yard](night_watch_modes/mixed_map_yard.png) |

**Mixed Shift's rotation is of DRESSINGS, not of the other modes' maps.** Each night draws one of three dressings from its seed (`MixedMap.set_for_seed`): 0 the station as it is (benches, departure boards, suitcases), 1 a party floor (Masked Hours' balloons, tables, streamers, arcade cabinets), 2 a salvage yard (Salvage Run's containers, scrap, barrels, a crane arm), all on the same transit-hub layout. The other modes' worlds (Dead Air, The Facility, The Descent, Open Air, Bedtime) have their own graphs and APIs and Mixed's golden-tested rules are tied to the nine-camera room graph, so rotating through them would need a common world interface; this is the documented limitation (the office is `hub_office` for every dressing; the spec's `rotation` stays empty).
