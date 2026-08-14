# LastRoute migration plan

The original game (`KyttuXD/LastRoute`) is a dependency-free JavaScript/Canvas project — roughly 15,500 lines across just `maze.js`, `game.js`, `hunter-ai.js`, `game-config.js`, `renderer.js` and the 26 per-hunter AI files, before UI, systems, and the three game modes. Its source is design and behavior reference material; Godot scenes and GDScript replace the browser runtime rather than wrapping it. This is a multi-milestone port, not a single-session rewrite — treat each milestone below as its own scoped unit of work.

## Reuse directly

- PNG/WebP sprites, tiles, backgrounds and UI art — **queued for the 3D milestone below, not the current 2D renderer**
- OGG/WAV audio
- hunter identities, tuning values and design documents
- YAML dialogue and cutscene content after choosing a Godot loader/import format
- the Node room/account server during the early client migration

## Rewrite in Godot

- Canvas renderer → Node2D/TileMapLayer/Light2D now, **superseded by a Node3D world with a top-down/first-person camera toggle** once the 2D gameplay milestones are further along — see below
- procedural maze/A* → generator service plus AStarGrid2D *(generator done; AStarGrid2D pathfinding not yet wired to anything, since there's no hunter AI yet)*
- player loop → CharacterBody2D controller and gameplay components
- hunter prototype mixins → hunter scenes with shared and per-identity states
- DOM HUD/menu → Control scenes
- browser storage → ConfigFile/Resource saves
- HTTP polling client → HTTPRequest-based network service

## Decided: rendering architecture is moving to 3D (queued, not started)

The original's real art (`last-route/assets/environment/*.png`, ~220×220px per tile) is built for its custom fake-3D "2.5D diorama" canvas renderer (`rendering/renderer.js`, 4409 lines: vertically compressed floors, extruded walls, depth-sorted actors, ray-traced light cones). It does not drop into a flat top-down `TileMapLayer` as-is — the pixels are drawn for a specific projection, not orthographic top-down tiles. Character sheets are also large (96×96px/frame, flat 4-directional), authored for that same diorama scale — none of it is being ported into the current 2D renderer.

**Confirmed direction:** the project owner is authoring real 3D models and wants an eventual **top-down / first-person camera toggle**. The decided approach is a single `Node3D` world as the source of truth with two camera rigs on it — an orthographic top-down `Camera3D` and a mouselook first-person one — rather than maintaining the current 2D `Node2D` port and a separate 3D scene in parallel (that would mean building every gameplay feature twice, forever). This **supersedes** the old milestone 11 ("XR experiment, decoupled 3D scene") — it's now a planned replacement of the render/control layer, not a side experiment.

**Sequencing (explicitly decided):** this is queued behind the current 2D gameplay milestone track, not started now. Keep shipping milestones 5 onward (hunter AI next) in the existing 2D `Node2D`/`CharacterBody2D` setup. When the 3D milestone is taken up:

- `src/game/facility_generator.gd` carries over untouched — it already produces plain grid/room/corridor data with zero rendering assumptions baked in (confirmed by design: it feeds a 2D or 3D presentation layer equally).
- `src/game/facility_view.gd` (the 2D `TileMapLayer` renderer), `player_controller.gd`'s `CharacterBody2D` movement, and the `Control`-based HUD all get rebuilt for 3D — they do not carry over.
- `art/props-3d/` (grey-box placeholders, scale/pivot convention documented there) is the starting scaffold for real art.
- Simulation/gameplay logic added between now and then (hunter AI, hiding, etc.) should stay presentation-agnostic where practical, the same way the facility generator does, so it doesn't have to be rewritten a second time for the 3D pass.

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
11. **3D rewrite: top-down/first-person camera toggle** *(decided direction, explicitly queued — not started)* — rebuild the render/control layer as a single `Node3D` world with two camera rigs, replacing `facility_view.gd`, the `CharacterBody2D` player controller, and the `Control` HUD. Supersedes the old "XR experiment, decoupled" plan. See "Decided: rendering architecture is moving to 3D" above for what carries over and what doesn't.

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
