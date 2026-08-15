# LastRoute migration plan

The original game (`KyttuXD/LastRoute`) is a dependency-free JavaScript/Canvas project — roughly 15,500 lines across just `maze.js`, `game.js`, `hunter-ai.js`, `game-config.js`, `renderer.js` and the 26 per-hunter AI files, before UI, systems, and the three game modes. Its source is design and behavior reference material; Godot scenes and GDScript replace the browser runtime rather than wrapping it. This is a multi-milestone port, not a single-session rewrite — treat each milestone below as its own scoped unit of work.

## Engine version

The project targets **Godot 4.7** (`config/features` in `project.godot`); development and all headless verification run on **4.7.1**. It was originally built against 4.3 and moved up with no code changes required — every scene, the facility validator, the hunter/gimmick tests and the Office Mode suite all passed unmodified on 4.7.1. Two things changed for the better: the headless dummy-renderer mesh error is gone (see the note below), and `@abstract` and other 4.5+ GDScript features are now available if ever wanted.

## Reuse directly

- PNG/WebP sprites, tiles, backgrounds and UI art — **queued for the 3D milestone below, not the current 2D renderer**
- OGG/WAV audio
- hunter identities, tuning values and design documents
- YAML dialogue and cutscene content after choosing a Godot loader/import format
- the Node room/account server during the early client migration

## Rewrite in Godot

- Canvas renderer → **now a Node3D world with a top-down/first-person camera toggle** (`scenes/main_3d.tscn`, the active default scene); the earlier Node2D/TileMapLayer/Light2D port (`scenes/main.tscn`) still exists and works but is no longer the default — see below
- procedural maze/A* → generator service plus AStarGrid2D *(done — `facility_generator.gd`'s `find_path()`, used by hunter_brain.gd)*
- player loop → CharacterBody2D controller and gameplay components *(3D: CharacterBody3D, see below)*
- hunter prototype mixins → `hunter_brain.gd`, a presentation-agnostic shared brain, plus a thin per-scene view wrapper *(Dovelle done, see "First hunter" below)*
- DOM HUD/menu → Control scenes *(HUD done and shared across both presentation layers; a main menu with settings is also done, see below)*
- browser storage → ConfigFile/Resource saves
- HTTP polling client → HTTPRequest-based network service

## Decided: rendering architecture is moving to 3D (basic slice playable)

The original's real art (`last-route/assets/environment/*.png`, ~220×220px per tile) is built for its custom fake-3D "2.5D diorama" canvas renderer (`rendering/renderer.js`, 4409 lines: vertically compressed floors, extruded walls, depth-sorted actors, ray-traced light cones). It does not drop into a flat top-down `TileMapLayer` as-is — the pixels are drawn for a specific projection, not orthographic top-down tiles. Character sheets are also large (96×96px/frame, flat 4-directional), authored for that same diorama scale — none of it is being ported into the 3D renderer either (it's a placeholder-grey-box stage, see below).

**Confirmed direction:** the project owner is authoring real 3D models and wants a **top-down / first-person camera toggle**. The approach is a single `Node3D` world as the source of truth with two camera rigs on it — an orthographic top-down `Camera3D` and a mouselook first-person one — rather than maintaining the 2D `Node2D` port and a separate 3D scene in parallel (that would mean building every gameplay feature twice, forever). This **supersedes** the old milestone 11 ("XR experiment, decoupled 3D scene") and the original "queue it behind 2D gameplay" sequencing — the project owner asked to start on it directly, so it's now the active track.

**`project.godot`'s `run/main_scene` now points at `scenes/main_3d.tscn`.** `scenes/main.tscn` (the 2D port) is untouched and still fully functional — nothing was deleted — but it's no longer what runs by default. Switch `run/main_scene` back to `res://scenes/main.tscn` to return to it.

### What's in the 3D slice today

Feature-parity with the 2D slice it replaces, rebuilt for 3D:

- `src/game/facility_generator.gd` carries over **completely untouched** — proof the "presentation-agnostic simulation" design worked. The 3D scene calls the exact same generator the 2D one does.
- `src/game_3d/facility_view_3d.gd` — a `GridMap` (3D's `TileMapLayer` equivalent) with a runtime-built two-item `MeshLibrary` (placeholder flat-colored floor/wall boxes, physics collision included), painted from the generator's grid. 1 grid cell = 1 meter (matches `art/props-3d/README.md`'s scale convention).
- `src/game_3d/player_controller_3d.gd` — `CharacterBody3D`, same stamina/lamp math as the 2D controller (`GameConfig` is shared), plus two `Camera3D` rigs toggled by the new `toggle_view` input action (bound to `V`): orthographic top-down (position-only follow, doesn't inherit player facing) and perspective first-person (mouselook yaw/pitch, movement relative to facing). Flashlight is now a real `SpotLight3D`.
- `src/game_3d/route_interactable_3d.gd` — same `kind`/`activate()` contract as the 2D `RouteInteractable`, rendered as an emissive marker sphere for now.
- `src/ui/hud.gd` + `scenes/hud.tscn` — **shared as-is** between the 2D and 3D scenes (extracted into its own scene specifically to make this possible; see `src/main.gd`/`src/main_3d.gd` both instancing it). It's pure `Control`/screen-space UI, so it never needed a 3D rewrite.
- Verified headlessly: facility/player/interactable counts and positions, physical wall collision (a `PhysicsRayQueryParameters3D` raycast confirms the `GridMap`'s collision lines up exactly with the generator's grid boundary), and the camera toggle flipping both cameras' `current` flag and mouse capture mode correctly in both directions.

**Resolved headless-only artifact (historical note):** on Godot 4.3, running the 3D scene under `--headless` printed one "`mesh_get_surface_count`... Parameter m is null" error per interactable, right after they spawned. It was a command-queue timing artifact in the no-GPU stub renderer (`servers/rendering/dummy/storage`) rather than a logic bug — everything downstream verified correct a few frames later. **It no longer reproduces on 4.7.1**, so headless runs are now expected to be completely silent; treat any such error as a real regression rather than background noise.

### Model import pipeline (ready for real assets)

`art/props-3d/` is reorganized into `environment/`, `characters/`, `interactables/`, and `props/` subfolders, and every 3D visual the game code uses — `wall_block`, `floor_tile`, `player`, `dovelle`, `relay`, `battery`, `safe_zone`, `lift` — now loads from a `.tscn` file there at runtime via `src/game_3d/model_slot.gd`, instead of being hardcoded as inline `PrimitiveMesh`/material calls in each script. `ModelSlot` has two strategies: `load_gridmap_item()` extracts a `Mesh`/`Shape3D` (by walking the scene for the first `MeshInstance3D`/`CollisionShape3D` *by type*, not by node name) for the `GridMap`'s `MeshLibrary`; `instantiate()` just instances the whole scene as-is for characters/interactables, so a real model can carry a skeleton, `AnimationPlayer`, or multiple mesh parts with no code changes. Interactable "completed" visual feedback moved from mutating a placeholder's material directly (which assumed a specific, simple mesh) to toggling an `OmniLight3D`'s visibility, so it still works regardless of what the real model looks like. Source format is **FBX**, exported from Blockbench (Godot has a native `ufbx`-based FBX importer since 4.3 — confirmed compiled into this project's Godot build via `ClassDB.class_exists("FBXDocument")` — so no external FBX2glTF conversion step is needed; ufbx also reads the ASCII-only FBX Blockbench's exporter produces). glTF (`.glb`, e.g. from Blender) works identically since `ModelSlot` only ever inspects the imported result, never the source format. See `art/props-3d/README.md` for the full swap-in workflow (import collision settings, node-structure requirements, per-slot table). Verified headlessly: models attach with the expected child counts, the `MeshLibrary`'s floor/wall mesh entries are non-null, and — most importantly — the `GridMap` wall collision raycast still hits the exact same world position it did before the refactor, confirming the extracted collision shape's transform is preserved correctly.

### What's not in the 3D slice yet

- **Real 3D art.** Still flat placeholder colors (GridMap boxes, emissive marker spheres) — but the loading pipeline is now real; see "Model import pipeline" above. Dropping an exported `.fbx` (or `.glb`) into `art/props-3d/` and following its README's swap-in steps is the entire remaining task, no code changes.
- **The rest of the hunter roster.** Dovelle and Quirith only, 2 of 26 — see "Hunter roster" below.
- **Themed rooms/props, hiding spots, coins, the heater station** — see "Deferred from milestone 4" below; none of this changed with the 3D move.
- **A camera-relative HUD nuance:** the interaction/objective HUD text is presentation-agnostic (just strings), but nothing here reads "am I looking at X" for first-person — interaction is still nearest-in-range, same as 2D, not a raycast-from-camera "looking at" check. Worth revisiting once first-person is the primary way people play.

## Hunter roster: 12 of 26 ported (data-driven, playable)

Milestone 6 is done for two identities, on an architecture built to keep adding more. `src/game/hunter_brain.gd` ports the shared perception/state-machine/movement/capture brain from `hunter-ai.js`. The shared rules ARE **Dovelle**'s behavior — the original's own zero-gimmick baseline (`HUNTER_ABILITIES.dovelle = {}`; her one method, `isBaselineHunter`, is a pure identity check) — so any hunter whose gimmick only changes tuning numbers, not behavior, needs zero changes to `hunter_brain.gd`. Built from three parallel research passes (perception/state-machine, movement/tuning/spawn-placement, sprite-sheet layout) banked earlier in this session — see git history for the full specs if extending this to another hunter.

**Data-driven roster.** `src/config/hunter_roster.gd` (`HunterRoster`) is a small registry mapping a hunter id to her tuning (kept in `GameConfig`, this just points at it) and her `art/props-3d/characters/` model scene. `HunterBrain._init()` takes an id and pulls its stats from there instead of hardcoding Dovelle's numbers as field defaults (the previous shape, when she was the only identity). `HunterRoster.pick_for_floor(seed_text, depth)` seeds a hunter pick the same way the original's `selectRouteHunters()` does — keyed by seed+depth so a replay draws the same hunter while a new run/descent reshuffles — simplified to a uniform draw across `IMPLEMENTED_IDS` rather than porting the full 26-hunter difficulty-tier weighting for a 2-hunter pool. `main_3d.gd` calls it once per floor build.

**Quirith's flashlight tracker** (`hunterAbilities.quirith.flashlightTracker`) is the first real per-hunter *behavior* gimmick, not just different tuning: keep the flashlight on for `QUIRITH_FLASHLIGHT_LOCK_SECONDS` (8s) straight and she locks onto the player permanently; every flashlight on/off flick after that ramps her chase speed, capped at `QUIRITH_MAX_SPEED_SCALE` (1.45×) after `QUIRITH_SPEED_RAMP_ACTIVATIONS` (10) flicks. Implemented as a single `if hunter_id == "quirith":` hook in `HunterBrain.update()`/`_current_speed()` (see the doc comment on `_update_flashlight_tracker`) rather than a plugin/subclass system — with only two hunters implemented and the other 24 gimmicks in the original ranging from multi-hunter summon interactions to positional audio to brand-new player stats (an "exposure" meter, for one), it's premature to guess at a general shape before more examples exist. She was picked specifically because her gimmick only touches systems that already exist in this port (flashlight state, the chase state machine, delta timers) — most of the roster isn't this self-contained; see "Deliberately out of scope" below.

**Six more hunters ported**, completing every identity portable without new simulation systems (see [`HUNTER_ROSTER.md`](HUNTER_ROSTER.md) for the full plan and what blocks the other 18):

- **Eirys** — a cumulative ratchet on time spent sprinting outside a safe zone that *never decays*; at 50s she locks into a permanent blind chase with no sight or hearing involved.
- **Xivvy** — locks on by pure proximity, ignoring line of sight entirely, then her chase speed ramps the longer the chase runs (capped at 1.8x, reset when it ends). Her lock radius scales with player exposure in the original; with no exposure meter here, the constant used is that same formula's value at exposure 0 — its genuine rest value, not an invented number.
- **Kathy** — a search-beam cone along her own facing that spots the player at 11.5 cells, well past the roster's ~8-cell ordinary sight, still gated on line of sight. This added `HunterBrain.facing` (tracked from her real movement) and a shared `beam_reaches()` cone helper.
- **Ravelle** — two invisible tripwires on doorway-shaped cells detected by scanning the grid; crossing one locks a chase and *permanently* compounds her speed. Her chase speed starts below the roster floor on purpose. The subtle rule is preserved exactly: a window in which a wire fired earns no relocation.
- **Mavrine** — a cooldown/survey/project/ping cycle that plants an armed frame elsewhere on the floor and pursues the *frame's* position when crossed. Survey pins her in place via a new `holds_position()` hook. A live chase holds the cycle off rather than advancing it.
- **Umbriel** — swaps her apparent identity every 30s. Purely cosmetic on Standard (attribute-copying is Nightmare-only, and no difficulty selection exists), so it's resolved in `HunterView3D`, never in the brain.

Gimmicks now draw from the brain's own seeded RNG rather than a global one, so a replayed run reproduces wire placement and mark cells as well as movement. Three hunters' abilities were deliberately **not** ported because they are structurally inert rather than merely unimplemented: Kathy's `affectedSummon` needs other concurrently-active route hunters (impossible at one hunter per floor in *both* codebases), Ravelle's fake doorway is read only by the original's renderer, and Xivvy's `flight` blocks nothing that walking doesn't already block.

**Presentation-agnostic, like the facility generator.** `hunter_brain.gd` is a `RefCounted` that only knows grid-cell coordinates and calls into `facility_generator.gd` (which gained `find_path()` — an `AStarGrid2D` wrapper, finally wiring up the "generator service plus AStarGrid2D" from the rewrite plan — and `has_line_of_sight()`, a grid-raymarch port of `maze.js`'s `hasLineOfSight`). `src/game_3d/hunter_view_3d.gd` is the only 3D-specific piece: reads `brain.position`/`brain.state` each frame, converts position to world space, and (see "Animation-driving infrastructure" below) drives a named animation clip from state. Porting this to the 2D scene later would mean writing an equally small 2D wrapper, not touching the brain at all.

### Facility pressure meters, and the hunters they unblocked

`src/game/player_meters.gd` ports the original's three facility-pressure meters, all shown on the shared HUD:

- **Exposure** (0-100) — how findable you are right now, eased toward a target from flashlight, gait noise and cover. Hunters can push it directly (Aki's burst).
- **Noise** (0-100, facility-wide) — accumulated racket that rises with your gait and decays toward quiet, with per-frame contributions banked by props and hunters.
- **Temperature** (0-100) — your body eases toward a facility ambient that warms on its own, on a *shortening* interval, so a run that never manages it is eventually forced to an extreme. A safe zone pulls hard back to neutral. Freezing slows movement; overheating burns lamp and stamina faster. Per-room climate profiles are **not** ported — the original drives them from a room `region`, and this port's rooms are still geometric-only pending the deferred room-content milestone, so a single facility-wide ambient is the honest equivalent.

Two smaller unlocks landed with them: `activate()` now writes the `collected` flag the generator had always declared but nothing ever set (so hunters reading relays/batteries finally see the truth), and the player's facing is threaded into the target dict for beam-aim checks.

**`main_3d.gd` now owns a collection of hunters rather than one**, because the rule-summoned specials hunt *alongside* the drawn route hunter rather than replacing her. Capture resolves against whichever hunter actually grabbed you, and a gimmick can declare its grab inescapable (Nyxie's dead-lamp wake skips the escape struggle entirely, matching the original calling `triggerGameOver` directly).

That unblocked three more hunters:

- **Nyxie** (special) — sustained darkness wakes her to hunt; a *dead* lamp held 10s is an inescapable capture instead. A live beam aimed at her dispels a timer wake and resets the darkness clock, so keeping the lamp alive is the whole counterplay.
- **Solyth** (special) — temperature reaching 100 latches her permanently, which also pins temperature to a 90F floor so cooling can never send her away again. The latch lives on the meters rather than the gimmick precisely because it outlives her. While locked in she burns an uncollected battery every 30s.
- **Wynelle** — drawn normally but starts dormant, waking on cold instead of the relay count. Cold builds a hidden meter; at 100 she materialises directly on the player and opens a 10-second freeze grace. The new **heater station** interactable is her counterplay, with the original's two distinct states preserved: merely *thawed* dematerialises her partway, only *powered* holds her at zero.

A design bug surfaced and was fixed during this: `HunterBrain.update()` returned early for inactive hunters, which meant the very gimmick code that decides when a summon-rule hunter wakes never ran. Gimmicks now declare `runs_while_inactive()`, true only for the three self-summoning hunters, so ordinary gimmicks still stay dormant until the relay schedule activates them.

### Animation-driving infrastructure (ready for rigged models)

`ModelSlot` (`src/game_3d/model_slot.gd`) gained `find_animation_player()` (same by-type lookup as its mesh/collision helpers — an imported rig's `AnimationPlayer` can be named anything) and `play_if_available()` (plays a named clip if the player exists and has it; a silent no-op otherwise). `player_controller_3d.gd` and `hunter_view_3d.gd` both call these every frame with a state-derived clip name (`idle`/`walk`/`sprint`/`crouch` for the player, driven by `movement_mode`; `idle`/`walk`/`chase` for hunters, driven by `HunterBrain.state`) — see `art/props-3d/README.md`'s "Animations" section for the exact convention. Every placeholder model today has no `AnimationPlayer` at all, so these calls are currently no-ops everywhere; naming an animated import's clips to match is the entire remaining step once one exists. Verified headlessly against a synthetic `AnimationPlayer` test scene (confirms the lookup/playback logic itself) and against the real placeholder scenes across multiple runs (confirms the no-op path is silent and error-free).

**What's implemented**, matching the original's exact constants and formulas (now in `GameConfig`, `src/config/game_config.gd`):

- Sight (range + line-of-sight, reduced when the player's flashlight is off — `UNLIT_SIGHT_SCALE`) and hearing (outer straight-line gate, then a real pathfind-length gate — walls muffle sound in walking distance, not straight-line distance).
- States `IDLE → WANDER → (CHASE | INVESTIGATE) → SEARCH → IDLE`, with the exact priority order and timers from the original (0.45s lost-sight grace before dropping out of chase, 3.2s search duration, arrival-triggered transitions).
- Chase speed scaling by relays collected and depth, stamina drain/winded-slowdown while chasing.
- Capture is pure proximity (hidden/safe-zone exempt) → the escape struggle (`GameState`, `src/autoload/game_state.gd`): mash `[E]` `ESCAPE_PRESSES` (6) times within `ESCAPE_DURATION` (3.2s). Success knocks the player back, staggers the hunter 3s into a short search, costs a life, and starts a shrinking reuse cooldown (16s × 0.95 per use). Failure (or being caught again while on cooldown) spends a life and respawns at the start with the hunter calmed, or ends the run once out of lives (Standard's 2-life pool — no difficulty selection exists yet, so it's the only pool used).
- Activation ties to the 3rd relay (`ROUTE_HUNTER_ACTIVATION_SPACING` from the original), matching `facility_generator.gd`'s new `place_hunter_spawn()` (a simplified single-spawn version of `maze.js`'s `placeHunterSpawns`/`pickHunterSpawns`, called on demand — not part of `generate()`, so the validator's contract is unaffected).
- HUD: a lives readout next to the objective panel, and an escape-struggle overlay (press prompt + progress/time bars) in the shared `hud.gd`/`hud.tscn` — both scenes get it, though only `main_3d.gd` drives it today.

**Verified**, not just written: an isolated `HunterBrain` test exercised every transition (idle→wander with real movement, sight→chase, hearing→investigate with real pathfind-length gating, chase→search→idle on timeout, capture proximity, hidden/safe-zone exemption, stun/`enter_search_from`/`calm_reset`). A full integration run through the real `main_3d.tscn` exercised the entire capture pipeline end to end — including an unplanned second cycle the test surfaced organically: successful escape → grace-protected window → cooldown-gated instant-fail capture → respawn (second-to-last life) → stun window → another cooldown-gated capture → game over at 0 lives — with every transition matching the original's semantics exactly. Quirith's tracker got its own isolated test: confirmed she does *not* lock on a frame before her 8s threshold, locks and stays locked (state stays `CHASE` across many subsequent frames with the target far outside sight/hearing range, proving the every-frame `lost_sight_timer` reset actually holds the lock rather than decaying) exactly at it, ramps chase speed correctly across flicks up to the exact expected cap, and correctly suppresses the forced chase while the target is in a safe zone. `HunterRoster.pick_for_floor()` was checked for both replay-stability (same seed+depth ⇒ same pick) and actually producing both ids across a spread of seeds/depths — confirmed live in `main_3d.tscn` too, both hunters spawn correctly across repeated runs with their own model attached.

**Deliberately out of scope for this pass** (all confirmed no-ops for these two hunters by the research, not silently dropped): multi-hunter separation, lures, temperature/room-power sight modifiers, most per-hunter gimmicks, difficulty scaling (fixed at Standard's 1.0 multiplier throughout — no difficulty selection UI exists), and the other 24 hunters. A no-game-over-screen-yet gap: `main_3d.gd` currently just shows "GAME OVER" and auto-restarts a fresh run after 3 seconds — a real end screen is a natural pairing with milestone 7 (roster) or the eventual menu/UI pass.

## Main menu (playable)

`scenes/main_menu.tscn` is now `project.godot`'s `run/main_scene` — the game boots into a title screen instead of straight into a run. **PLAY** starts a real solo run (`scenes/main_3d.tscn`). **CREATE ROOM**/**JOIN ROOM** are visibly present (matching the original's real menu) but disabled with a "COMING SOON" caption — milestone 9 (Co-op) is completely unstarted, so there's nothing for them to call; they're not faked. **SETTINGS** opens a same-scene overlay (mirroring the HUD's `MapOverlay` pattern) with a working master-volume slider (real `AudioServer` bus control — no audio content is routed through it yet, but the infrastructure is genuine) and full key-rebinding for every input action, both persisted to `user://settings.cfg` via a new `Settings` autoload (`src/autoload/settings.gd`) that applies them at startup regardless of which scene boots first.

## Office Mode (simulation complete, no UI yet)

**Office Mode does not use the A-Z hunter roster.** This is worth stating plainly because the name suggests otherwise: the original's own mode definition calls it "a fully self-contained FNAF-style stationary-defense simulation... Ten Void signals (never the A-Z roster)", and `office-survivor-system.js`'s startup explicitly clears `this.hunters = []` / `this.routeHunterIds = []` with the comment that its actor "never enters movement, collision, rendering, or hunter perception". It has its own separate cast of ten colour-named **Void signals** (Crimson, Azure, Amber, Emerald, Rose, Orange, Violet, White, Gray, Black), each with an independent 0-20 AI dial (Custom Night). Nothing in `src/game/office/` touches `HunterRoster`, `HunterBrain`, `FacilityGenerator`, or `GameConfig`.

`src/game/office/office_simulation.gd` ports the whole night simulation; `src/config/office_config.gd` holds its static data (the 8-camera map, which doubles as the threat-navigation graph, plus power costs and per-threat definitions). Presentation-agnostic in the same way the facility generator and hunter brain are — it owns every timer and the complete state, and renders nothing.

**`scenes/office.tscn` is the playable mode**, reachable from the main menu's OFFICE MODE button. `src/main_office.gd` owns the simulation, forwards input to its named controls, and reflects its state into the UI — the simulation stays authoritative for every outcome. Two UI pieces are adapted from the **Cupcakes Framework** (MIT, © Oplexitie — see `third_party/cupcakes-framework/`): `src/ui/office/office_view.gd` (mouse-edge office panning) and `src/ui/office/camera_monitor.gd` (feed switching with a static burst, and the tablet lowering to re-enable panning). Its CRT shader drives the monitor feed. Its *AI* is deliberately not used — see that folder's README for why. The office itself is still placeholder `ColorRect` geometry; the equirectangular perspective shader (and the hitbox-offset trick that goes with it) waits on real office art.

Office Mode's controls live in their own `office_*` input namespace, mirroring the original's deliberate split so rebinding a Last Route key can never collide with an Office one. All ten are rebindable in Settings; the 1-8 camera bank is a fixed hotbar, as in the original.

**What each Void signal does, and its counter** — all ported with the original's exact formulas:

| Signal | Threat | Counter |
| --- | --- | --- |
| Crimson | Walks a camera route to one door, then a 2s window | Shut the correct door — she retreats and re-routes to a fresh side |
| Azure | Builds continuously while the office is dark | *Flash* the desk light (fires on the off→on edge only — holding it on doesn't keep helping) |
| Amber | Builds while the camera monitor is raised, accelerating the longer it stays up | Lower the monitor; she bleeds back down |
| Emerald | Crawls the vent on a constant timer | Seal the hatch once she's past 70% |
| Rose | Never attacks — emits false cues so every other warning becomes untrustworthy | (none — she's pure misinformation) |
| Orange | Knocks systems offline, and periodically floods the office with gas | Breaker reset (a live CAM 7 view also clears her parasitic power drain); hold the mask through a leak |
| Violet | Corrupts cameras one at a time; three forces a monitor blackout | Reboot the feed, at the cost of a short blind window |
| White | Advances only in darkness, freezes solid in light — no warning, no minigame | Keep the desk light on, weighed against what it costs in power |
| Gray | Opens a shuffled 4-node parkour challenge cold off a timer | Click the nodes in the shuffled order before it expires |
| Black | Already behind you — a 1s window | Rear counter-flash (spends its own charge, not office power) |

Plus the systems they play against: a power budget that drains per active system (and is itself a loss condition), the 8-camera monitor, doors, vent seal, radio (pushes back three specific signals), a one-use emergency flash that stuns everything for 5s, and the shared HUD meter set (battery/stamina/noise/exposure) computed from office state rather than a player that doesn't exist here.

**Verified headlessly**, 31 checks: every signal's failure path fires *and* every counter genuinely counters it, power depletion ends the shift, surviving to the shift duration wins, AI 0 fully disables a signal (no timer, sabotage, challenge or failure path runs at all), the camera graph is fully connected with correct BFS routes, the Gray challenge accepts only the shuffled order and instant-fails any other node, and the same seed reproduces the same night. Three failures the suite initially reported turned out to be bugs in the test rather than the port — at AI 20 several signals are lethal faster than the test's setup assumed, so it was asserting against an already-ended shift.

**Not ported** (absent, not stubbed): audio cues (`queueOfficeCue` — no audio system exists in this port yet; every cue in the original was paired with an on-screen event message, which *is* ported), the developer/admin invulnerability shield, and co-op (Office is host-only, and this port is single-player).

## Recommended milestones

1. **Foundation** — viewport, controls, folder structure and placeholder scene. *(Complete.)*
2. **Asset intake** — copy canonical tiles/player art and define import presets. *(Superseded by the 3D milestone below — 2D art intake is not planned. See "Decided: rendering architecture is moving to 3D".)*
3. **Static room slice** — collision, movement, camera, flashlight and HUD. *(Complete: collision, movement, stamina, lamp, HUD, and a scrolling camera are playable.)*
4. **Procedural facility** — deterministic seed, rooms, corridors and A\* movement. *(Structural generation complete: `src/game/facility_generator.gd` faithfully ports maze.js's sector-grid carving, Kruskal-connected 3-wide corridor graph, and seeded relay/battery/safe-zone/service-lift placement, cross-checked bit-exact against the original's PRNG. Themed room types/furniture (maze.js's `ROOM_TYPES`/`populateRooms`, ~50+ prop types) are deliberately deferred — see "Deferred from milestone 4" below. `AStarGrid2D` pathfinding isn't wired up yet since nothing needs to path — that's part of milestone 6.)*
5. **Last Route loop** — relays, batteries, hiding, safe zone, lift and depth. *(Mostly riding on milestone 4: relay/battery/safe-zone/lift placement and collection, and depth progression via the service lift, are playable. Hiding spots are not — they're props, deferred with the rest of milestone 4's room content.)*
6. **First hunter** — shared perception/chase state machine plus one identity. *(Done — Dovelle, plus a data-driven roster architecture (`HunterRoster`) built to keep adding more. See "Hunter roster: Dovelle + Quirith" above.)*
7. **Roster** — migrate hunters individually with behavior fixtures. *(Started: Quirith (flashlight tracker) is the second of 26. **Full port plan for the remaining 24 lives in [`HUNTER_ROSTER.md`](HUNTER_ROSTER.md)** — per-hunter classification, tuning tables, and which shared systems unblock the most hunters. See "Hunter roster" above for why she was next and what's genuinely reusable vs. hunter-specific about the approach.)*
8. **Persistence** — checkpoint and account-facing client calls. *(A slice exists early: Settings' `user://settings.cfg` persists volume/key-bindings. Run/score checkpoint persistence is still unstarted.)*
9. **Co-op** — preserve host-authoritative snapshots against the existing Node server.
10. **Additional modes** — Hide & Seek and Office Mode after the core is stable. *(Office Mode's simulation is complete and verified — see "Office Mode" above; its UI is the remaining piece. Hide & Seek is unstarted, and is the mode that actually reuses the hunter roster: its round loop layers NPC hunters in via an `npcHunters` rule, unlike Office.)*
11. **3D rewrite: top-down/first-person camera toggle** *(active — basic slice playable)* — a single `Node3D` world with two camera rigs, replacing `facility_view.gd`, the `CharacterBody2D` player controller (`facility_generator.gd` and the HUD carry over unchanged). `run/main_scene` now points here. Supersedes the old "XR experiment, decoupled" plan. See "Decided: rendering architecture is moving to 3D" above for exactly what's done and what's left — the placeholder-art-to-real-art swap and hunter AI are the big remaining pieces.

### Deferred from milestone 4

maze.js's room population is enormous on its own: `ROOM_TYPES` defines dozens of themed rooms (arcade, stage, circus tent, beach cove, dining room, garden, server room, ...), each with per-type furniture lists and placement heuristics (`populateRooms`, `canPlaceRoomProp`, `propFacingScore` — hundreds of lines), plus `PROP_COLLIDERS` for ~60 prop types. None of that is ported yet. `src/game/facility_generator.gd`'s rooms are geometric only (`type: "generic"`, no `propTypes`). This is its own content milestone, likely worth doing alongside real art intake rather than before it, since prop placement is asset-dependent (footprint sizes come from `PROP_COLLIDERS`).

Also not ported: custom/authored map layouts (`custom-map.js`), the single-room Office Survivor floor mode, coins, the heater station, hunter spawn placement, and multiplayer spawn slots. All of these are structurally easy additions to `facility_generator.gd` following the same pattern once they're needed by their respective milestones.

**Seed-fidelity note:** because the original consumes RNG draws during room population *before* it places relays/batteries/safe-zones/the lift, and this port skips that population step entirely, the same seed text will not currently produce a pixel-identical layout to the original JS game — only the same *kind* of layout, deterministically, within this port. Full cross-engine seed parity would require porting `populateRooms` too.

## Validating the generator

```sh
godot4 --headless --script scripts/validate_facility.gd --path . -- --count 1000
```

Checks full-floor reachability from spawn, exact 3-wide corridors, an intact border wall, correct relay/battery counts, no overlapping objectives, and that the service lift is reachable and not on spawn — across as many seeds as you give it. All 1000 pass as of this milestone. Run it after any change to `facility_generator.gd`.

## First playable target

The first meaningful target was one deterministic floor containing:

- one player — done (movement, stamina, sprint, crouch)
- one hunter — **done** (Dovelle + Quirith, on a data-driven roster: full perception/chase/capture/escape loop, see above)
- relays — done, procedurally placed (5 on a Standard floor)
- batteries — done, procedurally placed (7 on a Standard floor)
- one hiding spot — **not started** (deferred prop content, see above)
- one safe zone — done, procedurally placed
- one service lift — done, procedurally placed, gates depth progression

Every piece here is now backed by the real seeded generator and a real hunter rather than a hardcoded test room. The remaining gap — hiding — is coupled to the deferred prop/room-content milestone (hiding spots are props), not a small standalone follow-up.
