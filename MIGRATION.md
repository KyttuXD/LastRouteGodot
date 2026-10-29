# LastRoute migration plan

The supported Godot runtime is now the first-person 3D Infinite route. The
former 2D and Office gameplay prototypes have been removed; references below
to those prototypes are historical migration notes only.

The original game (`KyttuXD/LastRoute`) is a dependency-free JavaScript/Canvas project — roughly 15,500 lines across just `maze.js`, `game.js`, `hunter-ai.js`, `game-config.js`, `renderer.js` and the 26 per-hunter AI files, before UI, systems, and the three game modes. Its source is design and behavior reference material; Godot scenes and GDScript replace the browser runtime rather than wrapping it. This is a multi-milestone port, not a single-session rewrite — treat each milestone below as its own scoped unit of work.

## Engine version

The project targets **Godot 4.7** (`config/features` in `project.godot`); development and all headless verification run on **4.7.1**. It was originally built against 4.3 and moved up with no code changes required — every scene, the facility validator, the hunter/gimmick tests and the Office Mode suite all passed unmodified on 4.7.1. Two things changed for the better: the headless dummy-renderer mesh error is gone (see the note below), and `@abstract` and other 4.5+ GDScript features are now available if ever wanted.

## Reuse directly

- PNG/WebP sprites, tiles, backgrounds and UI art — **queued for the 3D milestone below, not the current 2D renderer**
- procedural Web Audio cue definitions *(ported to `src/autoload/sound.gd`; the original contains no OGG/WAV files)*
- hunter identities, tuning values and design documents
- YAML dialogue and cutscene content after choosing a Godot loader/import format
- the Node room/account server during the early client migration

## Rewrite in Godot

- Canvas renderer → **now a first-person Node3D world** (`scenes/main_3d.tscn`)
- procedural maze/A* → generator service plus AStarGrid2D *(done — `facility_generator.gd`'s `find_path()`, used by hunter_brain.gd)*
- player loop → CharacterBody2D controller and gameplay components *(3D: CharacterBody3D, see below)*
- hunter prototype mixins → `hunter_brain.gd`, a presentation-agnostic shared brain, plus a thin per-scene view wrapper *(Dovelle done, see "First hunter" below)*
- DOM HUD/menu → Control scenes *(HUD done and shared across both presentation layers; a main menu with settings is also done, see below)*
- browser storage → ConfigFile/Resource saves
- HTTP polling client → HTTPRequest-based network service

## Decided: rendering architecture is 3D, first-person only

The original's real art (`last-route/assets/environment/*.png`, ~220×220px per tile) is built for its custom fake-3D "2.5D diorama" canvas renderer (`rendering/renderer.js`, 4409 lines: vertically compressed floors, extruded walls, depth-sorted actors, ray-traced light cones). It does not drop into a flat top-down `TileMapLayer` as-is — the pixels are drawn for a specific projection, not orthographic top-down tiles. Character sheets are also large (96×96px/frame, flat 4-directional), authored for that same diorama scale. The Godot route instead uses authored Blockbench/glTF characters and props plus generated modular 3D region surfaces.

**Confirmed direction:** the project owner is authoring real 3D models. The approach is a single `Node3D` world as the source of truth, rather than maintaining the 2D `Node2D` port and a separate 3D scene in parallel (that would mean building every gameplay feature twice, forever). This **supersedes** the old milestone 11 ("XR experiment, decoupled 3D scene") and the original "queue it behind 2D gameplay" sequencing.

**The top-down camera has been removed.** It shipped briefly as a `V` toggle between an orthographic overhead rig and the first-person one, and it rendered black in play. Three attempts to fix it (adding a ceiling, changing the light type, stopping the player climbing) each fixed a real bug without fixing the view, and the project owner's read was the correct one: the overhead view is a leftover from the 2D map concept and has no job left now that the whole facility is 3D. It, the `toggle_view` action and the `V` binding are gone; `player_controller_3d.gd` is first-person only. A discovered-only persistent minimap now reads the Infinite facility as a plan without exposing ungenerated space or other floors.

**`project.godot`'s `run/main_scene` points at `scenes/main_menu.tscn`.** The
removed prototype scenes are no longer part of the project runtime.

### What's in the 3D slice today

Feature-parity with the 2D slice it replaces, rebuilt for 3D:

- `src/game/facility_generator.gd` carries over **completely untouched** — proof the "presentation-agnostic simulation" design worked. The 3D scene calls the exact same generator the 2D one does.
- `src/game_3d/facility_view_3d.gd` and `streamed_facility_view_3d.gd` render the canonical walkability grid through collidable `GridMap` modules. 1 grid cell = 1 meter (matching `art/props-3d/README.md`). Floors, walls, ceilings and physical stair flights have collision; the `CharacterBody3D` controller has gravity, grounded jumping, stair support, fall-stun thresholds and admin drone-style noclip. Infinite regions select generated floor/wall texture families while prop art stays independent from structural collision.
- **Wall texture, retiled.** `_cube_material()`'s own "largest single triangle group" patch for the wall turned out to be a real, correctly-identified 12x27px trim seam on the model — just a sliver, stretched once across a full 1m x 3m face with nothing else to sample from, which is what "walls look bland" actually was. `_widen_wall_crop()` repeats that same patch (`WALL_REPEAT_X`/`WALL_REPEAT_Y`, both 6) instead of substituting a different, unverified region of the shared atlas — this model's atlas is shared with other environment props, and nothing here can confirm which of its other regions actually belong to the wall piece rather than the door frame or floor tile beside it. The repeat reads as panelled wall segments; `scripts/validate_maze.gd`'s collage guard (a cube sampling most of its atlas is showing several unrelated patches at once) now divides the wall's `uv1_scale` by its known repeat factor before checking, since a tiled small patch and an un-tiled large one produce the same raw scale.
- **Ceiling decoration.** `src/game_3d/ceiling_decor.gd` hangs a handful of fairy-light strands (a wire, a few small emissive bulbs, one dim `OmniLight3D` per bulb) from a seeded, sparse selection of open ceiling cells — capped at 8-18 total regardless of facility size, not a fraction of it: an early version scaled with open-cell *count*, and the largest map scale turned "a few strands here and there" into well over a hundred. Each bulb flickers on its own slightly-irregular cycle rather than a shared clock.
- `src/game_3d/player_controller_3d.gd` — `CharacterBody3D`, same stamina/lamp math as the 2D controller (`GameConfig` is shared), first-person mouselook at `Settings.mouse_sensitivity`, and a real `SpotLight3D` flashlight owned from spawn but switched **off** until the player uses it. It wears the same mannequin every other player does, hidden from its own camera.
- `src/game_3d/route_interactable_3d.gd` — same `kind`/`activate()` contract as the 2D `RouteInteractable`. Pickups genuinely **leave** when collected: the model hides and its collider is disabled, not just the glow light, because a collected relay that stayed on screen read as a failed interaction.
- `src/ui/hud.gd` + `scenes/hud.tscn` — pure `Control`/screen-space UI, so it never needed a 3D rewrite. Display adapts to the host machine: `canvas_items` stretch with `aspect="expand"` and 480×270 treated as a *minimum* design size, checked across five aspect ratios by the `layout` suite.
- Verified headlessly: facility/player/interactable counts and positions, physical wall collision (a `PhysicsRayQueryParameters3D` raycast confirms the `GridMap`'s collision lines up exactly with the generator's grid boundary), that every fabric item is a box rather than an imported model, and that the spawn is lit and unobstructed.

**Resolved headless-only artifact (historical note):** on Godot 4.3, running the 3D scene under `--headless` printed one "`mesh_get_surface_count`... Parameter m is null" error per interactable, right after they spawned. It was a command-queue timing artifact in the no-GPU stub renderer (`servers/rendering/dummy/storage`) rather than a logic bug — everything downstream verified correct a few frames later. **It no longer reproduces on 4.7.1**, so headless runs are now expected to be completely silent; treat any such error as a real regression rather than background noise.

### Model import pipeline (ready for real assets)

`art/props-3d/` is reorganized into `environment/`, `characters/`, `interactables/`, and `props/` subfolders, and every 3D visual the game code uses — `wall_block`, `floor_tile`, `player`, `dovelle`, `relay`, `battery`, `safe_zone`, `lift` — now loads from a `.tscn` file there at runtime via `src/game_3d/model_slot.gd`, instead of being hardcoded as inline `PrimitiveMesh`/material calls in each script. `ModelSlot` has two strategies: `load_gridmap_item()` extracts a `Mesh`/`Shape3D` (by walking the scene for the first `MeshInstance3D`/`CollisionShape3D` *by type*, not by node name) for the `GridMap`'s `MeshLibrary`; `instantiate()` just instances the whole scene as-is for characters/interactables, so a real model can carry a skeleton, `AnimationPlayer`, or multiple mesh parts with no code changes. Interactable "completed" visual feedback moved from mutating a placeholder's material directly (which assumed a specific, simple mesh) to toggling an `OmniLight3D`'s visibility, so it still works regardless of what the real model looks like. Source format is **glTF (`.glb`)**. Models are authored in Blockbench and converted by `tools/office/bbmodel_to_glb.py`, a hand-written `.bbmodel` → glTF exporter, because the round trip through Blockbench's own exporters kept losing things this project needs. `autouv` must stay `0` or Blockbench regenerates the UVs on open; cube-level geometry rotations and per-face UV rotations are now preserved (Aki's flared skirt is the regression case). The exporter reads the embedded PNG's real dimensions rather than a stale 64×64 project grid, writes parent-relative animation translations, preserves loop flags through Godot's import naming convention, keeps the crouch soles above y=0, and exports double-sided materials so Xivvy's one-face wing cards are visible from the front. Character instantiation preserves authored alpha instead of forcing opaque materials; Quenelle and Elise's transparent torso overlays are the regression cases. 64 Blockbench units = 1 metre. A `-colonly` suffix marks a mesh as collision-only and must never appear on a character model (21 of them on the first mannequin export is what dropped the player through the floor). `ModelSlot` only ever inspects the imported result, never the source format, so anything Godot imports works.

**The reviewed `.bbmodel` files in `art/props-3d/characters/` are committed editable source**, with their PNG texture embedded. `tools/characters/import_blockbench_hunters.py` extracts that texture into the inspectable `_0.png` beside it and rebuilds the animated `.glb`; it can rebuild entirely from the committed directory or accept an explicitly supplied external review directory. See `tools/characters/README.md` for the reproducible commands and visual-review renderer.

The mannequin goes through the **same** pipeline the hunters do now — `mc_to_hytale.py` onto the ~21-part Hytale rig, via `build_mannequin.py`. It didn't at first: a 64×64 skin has exactly six UV islands, and the first attempt through this rig left most of its ~21 parts sampling whatever lay under their coordinates — a uniform tan figure with its limbs floating apart. The real cause turned out to be a corrupted bone name in the shared converter itself (`Fofrontm` for `Forearm`, from a botched recovery after the toolchain was lost and rebuilt — see `tools/characters/README.md`), not a structural mismatch between a skin and this rig. A from-scratch six-box exporter (`mc_skin.py`) shipped as the workaround while that was still true. With the converter fixed, rebuilding the mannequin through the real pipeline comes out as one cohesive figure — confirmed by the same cohesion check now run against every hunter model, not just asserted for the player. `mc_skin.py`/`mannequin_anim.py` are left in `tools/characters/` as a smaller fallback, but nothing calls them by default any more.

Sized apart from the hunters on purpose now too: the mannequin's `.glb.import` carries `root_scale=0.9`, every hunter's carries `1.1`, so a hunter reads as visibly larger than the player without either model's own geometry needing to change. See `art/props-3d/README.md` for the full swap-in workflow (import collision settings, node-structure requirements, per-slot table). Verified headlessly: models attach with the expected child counts, the `MeshLibrary`'s floor/wall mesh entries are non-null, and — most importantly — the `GridMap` wall collision raycast still hits the exact same world position it did before the refactor, confirming the extracted collision shape's transform is preserved correctly.

### What's not in the 3D slice yet

- **Final modular environment art.** Region-specific walls, floors, carpets and authored prop families are live, but the structural shell still needs a complete corner/door/trim/damage module art pass without changing canonical collision.
- **Original custom-map scripted metadata.** PNG topology and regions are live; explicit per-pixel props, dialogue triggers and scripted mechanics from the browser editor remain to be ported.
- **Interaction now agrees with the crosshair:** route props are chosen from a camera-relative aim cone, ranked by crosshair alignment, and rejected when facility collision blocks line of sight. The host retains a wider planar facing envelope when validating remote guest requests, because camera pitch is intentionally not trusted network authority.

## Hunter roster: all 26 ported (data-driven, playable)

`src/game/hunter_brain.gd` ports the shared perception/state-machine/movement/capture brain from `hunter-ai.js`; `src/game/hunter_gimmicks/` carries every identity-specific rule. The shared rules are **Dovelle**'s zero-gimmick baseline, while the data-driven roster selects and tunes all 26 identities plus the Nyxie/Solyth summon rules.

**Data-driven roster.** `src/config/hunter_roster.gd` (`HunterRoster`) is a small registry mapping a hunter id to her tuning (kept in `GameConfig`, this just points at it) and her `art/props-3d/characters/` model scene. `HunterBrain._init()` takes an id and pulls its stats from there instead of hardcoding Dovelle's numbers as field defaults (the previous shape, when she was the only identity). `HunterRoster.pick_for_floor(seed_text, depth)` seeds a hunter pick the same way the original's `selectRouteHunters()` does — keyed by seed+depth so a replay draws the same hunter while a new run/descent reshuffles — simplified to a uniform draw across `IMPLEMENTED_IDS` rather than porting the full 26-hunter difficulty-tier weighting for a 2-hunter pool. `main_3d.gd` calls it once per floor build.

**Quenelle's flashlight tracker** (`hunterAbilities.quenelle.flashlightTracker`) is the first real per-hunter *behavior* gimmick, not just different tuning: keep the flashlight on for `QUENELLE_FLASHLIGHT_LOCK_SECONDS` (8s) straight and she locks onto the player permanently; every flashlight on/off flick after that ramps her chase speed, capped at `QUENELLE_MAX_SPEED_SCALE` (1.45×) after `QUENELLE_SPEED_RAMP_ACTIVATIONS` (10) flicks. Implemented as a single `if hunter_id == "quenelle":` hook in `HunterBrain.update()`/`_current_speed()` (see the doc comment on `_update_flashlight_tracker`) rather than a plugin/subclass system — with only two hunters implemented and the other 24 gimmicks in the original ranging from multi-hunter summon interactions to positional audio to brand-new player stats (an "exposure" meter, for one), it's premature to guess at a general shape before more examples exist. She was picked specifically because her gimmick only touches systems that already exist in this port (flashlight state, the chase state machine, delta timers) — most of the roster isn't this self-contained; see "Deliberately out of scope" below.

**Six more hunters ported**, completing every identity portable without new simulation systems (see [`HUNTER_ROSTER.md`](HUNTER_ROSTER.md) for the full plan and what blocks the other 18):

- **Elise** — a cumulative ratchet on time spent sprinting outside a safe zone that *never decays*; at 50s she locks into a permanent blind chase with no sight or hearing involved.
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
- **Temperature** (0-100) — your body eases toward a facility ambient that warms on its own, on a *shortening* interval, so a run that never manages it is eventually forced to an extreme. A safe zone pulls hard back to neutral. Freezing slows movement; overheating burns lamp and stamina faster. Per-room climate profiles are **not** ported yet; themed room regions now exist, but temperature remains one facility-wide pressure value rather than changing at every room boundary.

Two smaller unlocks landed with them: `activate()` now writes the `collected` flag the generator had always declared but nothing ever set (so hunters reading relays/batteries finally see the truth), and the player's facing is threaded into the target dict for beam-aim checks.

**`main_3d.gd` now owns a collection of hunters rather than one**, because the rule-summoned specials hunt *alongside* the drawn route hunter rather than replacing her. Capture resolves against whichever hunter actually grabbed you, and a gimmick can declare its grab inescapable (Nyxie's dead-lamp wake skips the escape struggle entirely, matching the original calling `triggerGameOver` directly).

That unblocked three more hunters:

- **Nyxie** (special) — sustained darkness wakes her to hunt; a *dead* lamp held 10s is an inescapable capture instead. A live beam aimed at her dispels a timer wake and resets the darkness clock, so keeping the lamp alive is the whole counterplay.
- **Solyth** (special) — temperature reaching 100 latches her permanently, which also pins temperature to a 90F floor so cooling can never send her away again. The latch lives on the meters rather than the gimmick precisely because it outlives her. While locked in she burns an uncollected battery every 30s.
- **Wynelle** — drawn normally but starts dormant, waking on cold instead of the relay count. Cold builds a hidden meter; at 100 she materialises directly on the player and opens a 10-second freeze grace. The new **heater station** interactable is her counterplay, with the original's two distinct states preserved: merely *thawed* dematerialises her partway, only *powered* holds her at zero.

A design bug surfaced and was fixed during this: `HunterBrain.update()` returned early for inactive hunters, which meant the very gimmick code that decides when a summon-rule hunter wakes never ran. Gimmicks now declare `runs_while_inactive()`, true only for the three self-summoning hunters, so ordinary gimmicks still stay dormant until the relay schedule activates them.

### Animated character pipeline (live)

`ModelSlot` (`src/game_3d/model_slot.gd`) finds an `AnimationPlayer` by type and plays the shared `idle`/`walk`/`sprint`/`chase`/`crouch` vocabulary without assuming an imported node name. The mannequin and all 26 hunter GLBs now carry those clips, and the player/hunter views drive them from live movement/AI state. The broken crouch pose remains authored for source review but gameplay deliberately keeps the stable idle skeleton and fades the body instead; remote copies reproduce the same fade. The body validator samples all 27 models through multiple phases of every full loop for floor penetration, foot contact, finite bounds and seam continuity.

**What's implemented**, matching the original's exact constants and formulas (now in `GameConfig`, `src/config/game_config.gd`):

- Sight (range + line-of-sight, reduced when the player's flashlight is off — `UNLIT_SIGHT_SCALE`) and hearing (outer straight-line gate, then a real pathfind-length gate — walls muffle sound in walking distance, not straight-line distance). Direct visible pursuit avoids pathfinding; routed hearing reuses its one computed path instead of immediately asking A* for the same route again.
- States `IDLE → WANDER → (CHASE | INVESTIGATE) → SEARCH → IDLE`, with a three-second retained-pursuit window so turning one corner does not cancel a chase, followed by the 3.2s search duration and arrival-triggered transitions. Perception and replanning run at bounded intervals rather than every rendered frame.
- Chase speed scaling by relays collected and depth, stamina drain/winded-slowdown while chasing.
- Capture is pure proximity (hidden/safe-zone exempt) → the escape struggle (`GameState`, `src/autoload/game_state.gd`): mash `[E]` `ESCAPE_PRESSES` (6) times within `ESCAPE_DURATION` (3.2s). Success knocks the player back, staggers the hunter 3s into a short search and starts a shrinking reuse cooldown (16s × 0.95 per use). Failure, a cooldown-gated recapture or an inescapable grab plays the capturing hunter through a local camera-lunge presentation and ends that runner's route. The unreliable lives/automatic-respawn layer has been removed.
- Activation ties to the 3rd relay (`ROUTE_HUNTER_ACTIVATION_SPACING` from the original), matching `facility_generator.gd`'s new `place_hunter_spawn()` (a simplified single-spawn version of `maze.js`'s `placeHunterSpawns`/`pickHunterSpawns`, called on demand — not part of `generate()`, so the validator's contract is unaffected).
- HUD: the escape-struggle overlay (press prompt + progress/time bars) remains in shared `hud.gd`/`hud.tscn`; the retired lives counter is gone.

**Verified**, not just written: the hunter suite exercises the shared brain and all identity gimmicks; the body suite samples all 27 character models across every phase of all five clips for finite bounds, loop seams, floor penetration and per-foot contact. The run-report suite drives a failed capture through the correct hunter model, temporary camera takeover and final report, while sync verifies targeted capture/escape packets and late-join hunter state.

**Current difficulty status:** Relaxed, Standard and Hard are selectable and synchronized. Their player movement/lamp, hunter movement/sight/hearing/capture, safe-zone and seeded tier-weight rules all feed simulation. Hard is the exact midpoint between the Standard and original Nightmare multipliers. Nightmare is selectable (KT 2026-10-28): the original's top profile, two hunters awake from the start plus one per relay, HunterDirector's Nightmare teams and a per-frame separation push so a pack never stacks into one body, and Quenelle's 5 s lock. Still missing: Zellia's shop instant-death roll, Umbriel copying abilities, Loxelle's 60 s locker regen, Kathy's summon, lures and room-power sight modifiers. Failed capture opens a real run report after the jumpscare: solo can restart or leave; a co-op guest leaves and a captured host ends the route.

## Main menu and rooms (playable)

`scenes/main_menu.tscn` is `project.godot`'s `run/main_scene` — the game boots through the update/loading gate into the restored archive-style title screen instead of straight into a run. It exposes **CREATE ROOM**, room-code **JOIN ROOM**, **PLAY OFFLINE**, **SETTINGS**, **REGISTER / SIGN IN**, **TUTORIAL**, and **QUIT**, inside the original dual edge frame. **SETTINGS** opens a same-scene overlay with Audio, Display and Controls categories: master volume, mouse sensitivity, fullscreen and full key-rebinding, persisted to `user://settings.cfg` via the `Settings` autoload.

**CREATE ROOM is online-first and leads to the room lobby** (`scenes/room_lobby.tscn`), which is where mode, map scale, difficulty and seed are configured. The complete hunter dossier lives here beside those route decisions rather than on the title screen. CREATE ROOM probes the primary service, opens/lists the ENet room automatically and falls back to the same room as solo if the service or initial registration is unavailable. JOIN ROOM exists only on the main menu; staging has no duplicate create/join/code/network controls. Raw addresses and ports are internal and never shown or accepted. Native sessions pass through the authenticated UDP relay, so player routers need no inbound port or UPnP. `RoomState` (`src/autoload/room_state.gd`) remains the single source of truth. Hide & Seek is removed from the selector; Office remains visible but disabled until its next gameplay pass.

**Map scale is four sizes, not five.** SPRAWLING and CAVERNOUS merged into one top tier, `Scale.IMMENSE` (99×99, the bigger of the two — the merge dropped the redundant middle-of-big step, not the biggest option available). Not named LARGE: that name was already the tier below it, and renaming an existing tier just to free the word felt like a bigger change than "merge the two biggest" asked for.

## Custom maps (admin-only, playable)

A colour-coded PNG stands in for procedural generation, ported from the original's own developer format (`src/game/custom-map.js`) into `src/game/custom_map_parser.gd`: black wall, white floor, zero or more green player-spawn pixels, an optional red exit, and region colours (office, maintenance, arcade, circus, nether, beach, mansion, garden) flood-filled into rooms by contiguous colour. Multiple green cells become ordered co-op spawn slots; with none, the seeded generator picks a random open cell identically on every peer. It does not inherit the procedural generator's narrow 35..121 range: each dimension may reach 512, with a 65,536 decoded-cell ceiling. The HTTP/ENet source PNG is independently capped at 2 MiB and its IHDR dimensions are checked before decompression.

**Fed into the same generator, not a separate one.** `FacilityGenerator._init()` takes an optional `custom_layout` dict; given one, it skips procedural carving and loads the parsed grid/rooms/start/exit directly, then runs the exact same relay/battery/safe-zone/service-lift placement a procedural floor gets — those algorithms only ever read `self.grid`/`self.rooms`, so a hand-painted layout is populated by the same seeded, deterministic code a carved one is.

**Loaded by URL, not hardcoded.** The admin overlay (0 key) gained a text field — `AdminMenu.attach()` now takes an optional `text_fields` param, one `LineEdit` per entry — that fetches a raw PNG over `HTTPRequest` and rebuilds the current floor from it via `FacilityView3D.generate_floor_from_custom_map()`.

**Two real gaps from the original, both by necessity rather than oversight:**
- **No unpainted-exit floors.** The original leaves a map with no red pixel entirely without a service lift (`Maze.hasExit`); this port has nowhere for a floor with no way down to go — `GameState.descend()` and the whole relay-gated lift flow assume one exists. An unpainted exit falls back to the same `pick_service_lift()` auto-pick a procedural floor gets instead.
- **No props, no dialog triggers.** The original's `props`/`dialogTriggers` settings-file keys and paint-palette prop colours need systems this port doesn't have yet (a prop catalogue, a dialog runner). Region colours are recorded on the room (see below) rather than dropped, since a future prop pass can read them; prop pixels themselves are treated as unrecognised — a wall, with a warning — rather than silently ignored.

**Region colours get a real, if first-pass, visual result today.** `FacilityView3D.REGION_FLOOR_TINTS` maps each region name to a colour, registered as extra `MeshLibrary` floor items alongside the ordinary one; `_paint_grid()` looks up each open cell's room via `room_at()` and picks the matching tinted item, falling through to the ordinary floor for any cell with no region (which is every cell on a procedural floor — `room.get("region", "")` is only ever non-empty on a custom map, so this is a no-op for the whole existing game). The tint multiplies the *existing* floor texture rather than replacing it, so the tile pattern still shows through, just recoloured — real, bespoke art per theme (a mansion's own herringbone, a beach's own sand) is a much bigger asset pass than this covers, and there is no Blockbench connection this session to author or verify one. "Frozen tideline" reads as beach's own region rather than a second one: it is a beach with the tide iced over, not a separate room type nothing places yet.

Verified by the `custom_map` and `sync` suites: authored multi-spawns survive parsing, generation and late-join reconstruction; a map without green uses a deterministic seeded random open cell; practical maps outside the old dimension bounds are retained without clamping; all-wall, disconnected and oversized layouts fail safely; irregular region membership stays exact; and parsed maps produce real relays through the same generic placement as procedural floors. A new custom floor resets old objective counters, while same-revision state snapshots reconcile pickups/sabotage/hiding exactly without rebuilding the base, respawning hunters or teleporting an existing guest.

## Player effects for hunters to use (infrastructure, unused so far)

Two generic screen/beam effects, threaded onto the player the same way `interaction_veto`/`hiding_trap_resolver` already are — a gimmick reaching for one only needs the `player` reference it already has, nothing routed per-hunter through `main_3d`.

- **`PlayerController3D.force_flashlight_flicker(duration, min_period, max_period)`** — strobes the beam on/off at random short intervals, overriding the player's own `[F]` state for the duration (checked via `flashlight_seized()`, so a forced effect can't be shrugged off by holding the key) and restoring the real state when it ends.
- **`HUD.trigger_static(duration, intensity)`**, reachable as `player.trigger_static_effect.call(duration)` — a full-screen TV-static overlay, a small `canvas_item` shader hashing screen position and `TIME` per pixel rather than an imported noise texture, fading in and out over the first/last fifth of its duration.

Neither is wired to a specific hunter's gimmick yet — this is the infrastructure a future one calls into, the same relationship `interaction_veto` had to Opalie before she existed. Verified by the `player_effects` suite: a forced flicker seizes the beam, changes it, survives a real `[F]` press without the player's own preference changing, and releases back to the true state on schedule; static triggers, holds through its duration, and clears itself.

## Bigger models, hunters bigger than the player

Two things share one mechanism now: the mannequin and every hunter's `.glb.import` carries `nodes/root_scale` (`0.9` for the mannequin, `1.1` for every hunter) rather than either model's own geometry changing size. A hunter reads as visibly larger than the player without needing a second, larger rig or export pass — and it survives a model rebuild without needing to be reapplied by hand, since it lives in import metadata rather than exporter code.

## Procedural audio

The original has no audio assets to copy: `src/systems/audio.js` builds every sound from oscillators, low thumps and filtered noise. `src/autoload/sound.gd` ports that vocabulary into cached stereo `AudioStreamWAV` data at runtime, routed through SFX and UI buses beneath the persisted Master level. Pickups, charging, UI feedback, footsteps, proximity heartbeat, capture/struggle/escape, Haelith's directional steps, Nyxie's two distinct wakes, disruptive hunter events and all Office warnings/controls/jumpscares are wired. The source's continuous ambient drone remains intentionally disabled. The `audio` suite renders and inspects every cue, verifies left/right energy, debounce, UI wiring and Office event emission under the headless dummy driver.

## Co-op: direct-IP/LAN multiplayer (playable core route)

ENet high-level multiplayer, host/join on a port, with `RemotePlayers` (`src/game_3d/remote_players.gd`) as the one netcode node — it sits at a fixed path under `World`, which is what makes its RPCs addressable on every peer.

- **Room lifecycle.** The host owns configuration and route launch. Starting switches every staged peer through a threaded route-loading screen into the same seeded scene; joining a live room enters behind that opaque surface and requests a snapshot. The loading readout carries seed, mode, difficulty and progress without field-note/tutorial text, and a guest remains input-frozen and covered until the authoritative floor is accepted. A host ending the route returns the connected room to staging, a guest may leave independently, and connection failure/server loss returns the client safely with a visible reason. The lobby creates and joins only through primary-service room codes; resolved ENet endpoints remain an internal transport detail.
- **Bodies.** Each peer sends its own position, facing, animation clip and perception-facing state at 20 Hz; every other peer interpolates a mannequin toward those samples. No client-side prediction is attempted.
- **Hunters are host-authoritative.** `simulates()` gates the brain loop; the host chooses the closest available runner for each hunter, runs every brain, and broadcasts position, facing, active/state and Umbriel disguise. Capture, Ilyra stun, Javelle/Loxelle forced hiding exit, escape success and respawn are targeted reliable outcomes rather than host-only local effects. A short pending-capture gate prevents the same client receiving repeated struggles while packets cross. `simulates()` answers `true` offline, which keeps the solo path from forking.
- **The shared world.** Relays, batteries, hiding-spot disablement, sabotage, the heater station and the service lift are shared through host-relayed reliable events. Events carry a **grid cell**, not a node path — which only names the same object on two machines because `main_3d` seeds the run from `RoomState.run_seed()` rather than a fresh `randi()`.
- **Late joiners** get a snapshot of collected cells, heater state, sabotaged relays, disabled hiding spots and depth, so a peer arriving mid-floor catches up before playing.
- **Pause and capture presentation are per runner.** A co-op pause overlay freezes that local controller without stopping the host simulation. A caught player's jumpscare is a local model/camera clone and cannot move the authoritative hunter. The report offers Leave to a guest or End Route to a host; solo reports archive final statistics and require an explicit Restart/Main Menu choice.

Verified by the `sync` and `pause` suites plus `scenes/enet_smoke.tscn`, which launches as a real host/client pair and checks the ENet handshake, host configuration, named roster, synchronized route-start RPC, guest-to-host gameplay/admin requests, a host-to-guest targeted effect, reliable fragmentation, and transport/decoding of the real 49×49 authored-map PNG.

**Node backend boundary.** `backend/server.mjs` is one dependency-free Node service carrying both the original account/room API and the Godot HTTP rendezvous API. Original-style rooms retain host ownership, settings, route/office starts, live world/item/discovery state, custom-map/dialog control and TTL cleanup; accounts use scrypt password records, restart-safe hashed sessions and persistent JSON save slots. The ENet side registers a five-character code, issues a private mutation token, heartbeats player/session state, expires stale hosts and tunnels native gameplay through the authenticated public UDP relay. Test builds use the hardcoded primary backend at `http://lastroute.kyttuslab.org:8105`, with the ENet relay on UDP `1105`; no environment, command-line, or direct-address override remains. Room discovery and updates use the HTTP allocation once TCP `8105` is exposed, but account/password transport remains rejected until TLS is deployed. The service continues to apply request throttles. `backend/server.test.mjs` covers both protocols and `scenes/backend_smoke.tscn` verifies the real Godot host register → resolve → unregister path. `backend/README.md` documents Pterodactyl variables and persistent storage.

**Remaining co-op boundaries:** the public relay removes player-router/NAT requirements, but there is still no reconnect grace, host migration, gameplay encryption, or mandatory account-bound room identity; a run ends if peer 1 disconnects. The temporary HTTP deployment also leaves room-directory metadata and update downloads unencrypted and disables accounts; TLS remains required before a secure release. Proxy/firewall rate limits remain useful defense in depth around the service's built-in throttles. Within a live route, the host validates guest pickups, heaters, relay repair and lift descent; arbitrates hunter interactions including Zellia trades, Glyra's music box, Ceryth answers, Opalie warnings and Verrine vents; sends hunter meter mutations back to the affected runner; and publishes canonical economy/counter results plus hunter gimmick state in late-join snapshots. Custom-map snapshots include the validated PNG and a floor revision, rebuild the authoritative base before applying cell mutations, keep a joining guest frozen until successful, and retry malformed/incomplete delivery. Debug-tools guests can request shared admin changes, but peer 1 executes and persists them. Movement remains owner-reported with host freshness/depth/range checks rather than server-side physics replay, which is appropriate for friendly co-op but not an anti-cheat boundary.

**Client updates install themselves.** The startup gate now downloads the platform artifact instead of opening a browser, verifies the backend manifest's SHA-256, rejects unsafe ZIP paths, unpacks into `user://updates`, and launches an independent helper which waits for the game process to stop before replacing and relaunching the desktop build. Web refreshes with a commit cache-buster; Quest hands the verified APK to Android's installer because sideloaded package replacement still requires OS/user approval. Read-only desktop installation folders fail closed with the verified package left staged for retry.

## Retired prototypes

**Office Mode does not use the A-Z hunter roster.** This is worth stating plainly because the name suggests otherwise: the original's own mode definition calls it "a fully self-contained FNAF-style stationary-defense simulation... Ten Void signals (never the A-Z roster)", and `office-survivor-system.js`'s startup explicitly clears `this.hunters = []` / `this.routeHunterIds = []` with the comment that its actor "never enters movement, collision, rendering, or hunter perception". It has its own separate cast of ten colour-named **Void signals** (Crimson, Azure, Amber, Emerald, Rose, Orange, Violet, White, Gray, Black), each with an independent 0-20 AI dial (Custom Night). Nothing in `src/game/office/` touches `HunterRoster`, `HunterBrain`, `FacilityGenerator`, or `GameConfig`.

The former Office simulation and its presentation files have been removed from
the Godot project. Office-themed authored props remain available to the active
3D route where they are used as ordinary room dressing.

The former Office mode is no longer selectable or included in the runtime. Its
dedicated scenes, simulation, UI, and build tooling were removed when the
project consolidated on the Infinite 3D route.

The old Office-only input namespace is no longer part of the supported game.

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

**Not ported** (absent, not stubbed): the developer/admin invulnerability shield and co-op (Office is host-only, and this port is single-player). Its full procedural cue vocabulary is ported through `OfficeSimulation.audio_cue` → `Sound.queue_office_cue`, including directional warnings, recurring breathing, controls, shift cue and Void jumpscares.

## Recommended milestones

1. **Foundation** — viewport, controls, folder structure and placeholder scene. *(Complete.)*
2. **Asset intake** — copy canonical tiles/player art and define import presets. *(Superseded by the 3D milestone below — 2D art intake is not planned. See "Decided: rendering architecture is moving to 3D".)*
3. **Static room slice** — collision, movement, camera, flashlight and HUD. *(Complete: collision, movement, stamina, lamp, HUD, and a scrolling camera are playable.)*
4. **Procedural facility** — deterministic seed, rooms, corridors and A\* movement. *(Complete mechanically: `src/game/facility_generator.gd` ports maze.js's sector-grid carving, Kruskal-connected 3-wide corridor graph, themed room identities, deterministic prop lists/footprints, navigation occupancy and seeded objective/service-lift placement. `AStarGrid2D` pathfinding is live. Bespoke prop art remains a presentation milestone.)*
5. **Last Route loop** — relays, batteries, hiding, safe zone, lift and depth. *(Complete as a gameplay slice: placement, collection, hiding/exit, safe zones, relay gating and lift depth progression are playable. Hiding uses a placeholder locker until the prop-art milestone.)*
6. **First hunter** — shared perception/chase state machine plus one identity. *(Done — Dovelle, plus a data-driven roster architecture (`HunterRoster`) built to keep adding more. See "Hunter roster: Dovelle + Quenelle" above.)*
7. **Roster** — migrate hunters individually with behavior fixtures. *(Complete: all 26 identities, their shared brain, model slots, tuning and individual gimmicks are live; [`HUNTER_ROSTER.md`](HUNTER_ROSTER.md) is the detailed mechanic/validation reference.)*
8. **Persistence** — checkpoint and account-facing client calls. *(Complete for this milestone: Settings persist locally; accounts restore restart-safe 30-day sessions; procedural solo routes save a validated floor-boundary checkpoint and expose Continue/Clear. Co-op and custom-map state remain host/map-owned rather than personal saves.)*
9. **Co-op** — host-authoritative shared state. *(The core route is playable through the primary Node UDP relay: synchronized room lifecycle, interpolated remote mannequins, multi-runner host-authoritative hunters and targeted capture/jumpscare/effects, host-validated guest interactions and shared economy/world changes, and live-session snapshots including gimmick state. Hosts and guests need no inbound player-router port.)*
10. **Additional modes** — Hide & Seek and Office Mode after the core is stable. *(Office retains its playable implementation but is greyed out during its next pass. Hide & Seek is removed from staging and remains unstarted.)*
11. **3D rewrite** *(active)* — a single first-person `Node3D` world, replacing `facility_view.gd` and the `CharacterBody2D` player controller (`facility_generator.gd` and the HUD carry over unchanged). Supersedes the old "XR experiment, decoupled" plan. See "Decided: rendering architecture is 3D" above for what's done and what's left — deeper regional art and streamed specialist encounters are the big remaining pieces.

### Remaining presentation work from milestone 4

`RoomCatalog` and `FacilityGenerator.populate_rooms()` now carry the original themed identities, prop lists, footprints, deterministic placement and solid occupancy. Procedural and region-painted custom rooms consume the same data; navigation, objectives and late-join generation therefore agree on furniture. The current 3D representation is intentionally a coloured silhouette box per prop. Replacing those slots with authored arcade, mansion, garden, beach, maintenance, circus and nether GLBs is the remaining content/art pass.

## Checks

```sh
godot4 --headless --path . res://scenes/validate.tscn
```

Seventeen suites — `room`, `player`, `body`, `pause`, `maze`, `admin`, `layout`, `run_report`, `camera_console`, `sync`, `roster`, `hunters`, `office_monitor`, `custom_map`, `props`, `player_effects`, `audio` — in a few seconds. Name any subset after `--`.

**Run them as a scene, never with `--script`.** In `--script` mode Godot registers no autoloads at all, so every script that so much as mentions `GameState` or `MouseLock` fails to *compile*, and the suite hangs with no output — a worse failure than the one it exists to catch. The runner has one related guard: a suite that fails to parse loads as `null`, and awaiting a call on `null` never returns, so it now reports the bad file and keeps going instead of looking like a hung game.

The generator has its own long-form validator, still `--script` (it touches no autoloads):

```sh
godot4 --headless --script scripts/validate_facility.gd --path . -- --count 1000
```

Full-floor reachability from spawn, exact 3-wide corridors, an intact border wall, correct relay/battery counts, no overlapping objectives, and a service lift that is reachable and not on spawn — across as many seeds as you give it. All 1000 pass. Run it after any change to `facility_generator.gd`.

**The recurring lesson**, worth stating because it has cost this port more than any bug: *a check that confirms a mechanism rather than the player's action passes while the feature is unusable.* A test called `stand()` directly and passed while the office chair was inescapable in game. A reach sweep ran from a seated pose and passed while the controls could not be reached standing. A camera check counted `MeshInstance3D` nodes and passed while the view rendered black. The mannequin passed everything and had its limbs floating apart. Every one of those was rewritten to drive the thing the way a player does.

## First playable target

The first meaningful target was one deterministic floor containing:

- one player — done (movement, stamina, sprint, crouch)
- one hunter — **done** (Dovelle + Quenelle, on a data-driven roster: full perception/chase/capture/escape loop, see above)
- relays — done, procedurally placed (5 on a Standard floor)
- batteries — done, procedurally placed (7 on a Standard floor)
- one hiding spot — **done mechanically** (placeholder locker art; shared state and hunter counters work)
- one safe zone — done, procedurally placed
- one service lift — done, procedurally placed, gates depth progression

Every piece here is now backed by the real seeded generator and a real hunter rather than a hardcoded test room. The remaining gaps are public-network reliability and content/art depth rather than a missing core route interaction.
