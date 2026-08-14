# LastRoute migration plan

The original game (`KyttuXD/LastRoute`) is a dependency-free JavaScript/Canvas project — roughly 15,500 lines across just `maze.js`, `game.js`, `hunter-ai.js`, `game-config.js`, `renderer.js` and the 26 per-hunter AI files, before UI, systems, and the three game modes. Its source is design and behavior reference material; Godot scenes and GDScript replace the browser runtime rather than wrapping it. This is a multi-milestone port, not a single-session rewrite — treat each milestone below as its own scoped unit of work.

## Reuse directly

- PNG/WebP sprites, tiles, backgrounds and UI art — **queued for the 3D milestone below, not the current 2D renderer**
- OGG/WAV audio
- hunter identities, tuning values and design documents
- YAML dialogue and cutscene content after choosing a Godot loader/import format
- the Node room/account server during the early client migration

## Rewrite in Godot

- Canvas renderer → **now a Node3D world with a top-down/first-person camera toggle** (`scenes/main_3d.tscn`, the active default scene); the earlier Node2D/TileMapLayer/Light2D port (`scenes/main.tscn`) still exists and works but is no longer the default — see below
- procedural maze/A* → generator service plus AStarGrid2D *(generator done; AStarGrid2D pathfinding not yet wired to anything, since there's no hunter AI yet)*
- player loop → CharacterBody2D controller and gameplay components
- hunter prototype mixins → hunter scenes with shared and per-identity states
- DOM HUD/menu → Control scenes
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

**Known headless-only artifact:** running the 3D scene under `--headless` prints 14 "`mesh_get_surface_count`... Parameter m is null" errors once, right after the interactables spawn (14 = the interactable count). The error is explicitly scoped to `servers/rendering/dummy/storage` in the engine — the no-GPU stub renderer headless mode falls back to — and is a one-time command-queue timing artifact for procedurally-created meshes, not a logic bug: everything downstream (physics, positions, camera state) verified correct once queried a few frames later. It should not reproduce in the real editor with an actual renderer; if it does, revisit `facility_view_3d.gd`'s `_build_mesh_library()` and `route_interactable_3d.gd`'s runtime mesh construction.

### What's not in the 3D slice yet

- **Real 3D art.** Still flat placeholder colors (GridMap boxes, emissive marker spheres). `art/props-3d/` is the intended scaffold for real imports.
- **Hunter AI.** Not started in either the 2D or 3D layer. Extensive research is already banked for this (see the hunter AI research summaries from this session) — perception/state-machine, movement/tuning/spawn-placement, and sprite-sheet-layout specs are all gathered and ready to implement against, for whichever presentation layer it's built in.
- **Themed rooms/props, hiding spots, coins, the heater station** — see "Deferred from milestone 4" below; none of this changed with the 3D move.
- **A camera-relative HUD nuance:** the interaction/objective HUD text is presentation-agnostic (just strings), but nothing here reads "am I looking at X" for first-person — interaction is still nearest-in-range, same as 2D, not a raycast-from-camera "looking at" check. Worth revisiting once first-person is the primary way people play.

## Recommended milestones

1. **Foundation** — viewport, controls, folder structure and placeholder scene. *(Complete.)*
2. **Asset intake** — copy canonical tiles/player art and define import presets. *(Superseded by the 3D milestone below — 2D art intake is not planned. See "Decided: rendering architecture is moving to 3D".)*
3. **Static room slice** — collision, movement, camera, flashlight and HUD. *(Complete: collision, movement, stamina, lamp, HUD, and a scrolling camera are playable.)*
4. **Procedural facility** — deterministic seed, rooms, corridors and A\* movement. *(Structural generation complete: `src/game/facility_generator.gd` faithfully ports maze.js's sector-grid carving, Kruskal-connected 3-wide corridor graph, and seeded relay/battery/safe-zone/service-lift placement, cross-checked bit-exact against the original's PRNG. Themed room types/furniture (maze.js's `ROOM_TYPES`/`populateRooms`, ~50+ prop types) are deliberately deferred — see "Deferred from milestone 4" below. `AStarGrid2D` pathfinding isn't wired up yet since nothing needs to path — that's part of milestone 6.)*
5. **Last Route loop** — relays, batteries, hiding, safe zone, lift and depth. *(Mostly riding on milestone 4: relay/battery/safe-zone/lift placement and collection, and depth progression via the service lift, are playable. Hiding spots are not — they're props, deferred with the rest of milestone 4's room content.)*
6. **First hunter** — shared perception/chase state machine plus one identity.
7. **Roster** — migrate hunters individually with behavior fixtures.
8. **Persistence** — checkpoint and account-facing client calls.
9. **Co-op** — preserve host-authoritative snapshots against the existing Node server.
10. **Additional modes** — Hide & Seek and Office Survivor after the core is stable.
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
- one hunter — **not started** (milestone 6)
- relays — done, procedurally placed (5 on a Standard floor)
- batteries — done, procedurally placed (7 on a Standard floor)
- one hiding spot — **not started** (deferred prop content, see above)
- one safe zone — done, procedurally placed
- one service lift — done, procedurally placed, gates depth progression

Every piece here is now backed by the real seeded generator rather than a hardcoded test room. The two gaps — a hunter and hiding — are the next two milestones' entire job, not small follow-ups: hunter AI alone is ~1,795 lines in the original (`hunter-ai.js`) before any per-identity behavior.
