# LastRoute migration plan

The original game (`KyttuXD/LastRoute`) is a dependency-free JavaScript/Canvas project — roughly 15,500 lines across just `maze.js`, `game.js`, `hunter-ai.js`, `game-config.js`, `renderer.js` and the 26 per-hunter AI files, before UI, systems, and the three game modes. Its source is design and behavior reference material; Godot scenes and GDScript replace the browser runtime rather than wrapping it. This is a multi-milestone port, not a single-session rewrite — treat each milestone below as its own scoped unit of work.

## Reuse directly

- PNG/WebP sprites, tiles, backgrounds and UI art — **see the open rendering-architecture decision below before wiring any of this in**
- OGG/WAV audio
- hunter identities, tuning values and design documents
- YAML dialogue and cutscene content after choosing a Godot loader/import format
- the Node room/account server during the early client migration

## Rewrite in Godot

- Canvas renderer → Node2D, TileMapLayer, Light2D and shaders (or a 3D top-down rewrite — see below)
- procedural maze/A* → generator service plus AStarGrid2D *(generator done; AStarGrid2D pathfinding not yet wired to anything, since there's no hunter AI yet)*
- player loop → CharacterBody2D controller and gameplay components
- hunter prototype mixins → hunter scenes with shared and per-identity states
- DOM HUD/menu → Control scenes
- browser storage → ConfigFile/Resource saves
- HTTP polling client → HTTPRequest-based network service

## Open decision: rendering architecture (2D diorama vs. 3D top-down)

The original's real art (`last-route/assets/environment/*.png`, ~220×220px per tile) is built for its custom fake-3D "2.5D diorama" canvas renderer (`rendering/renderer.js`, 4409 lines: vertically compressed floors, extruded walls, depth-sorted actors, ray-traced light cones). It does not drop into a flat top-down `TileMapLayer` as-is — the pixels are drawn for a specific projection, not orthographic top-down tiles. Character sheets are also large (96×96px/frame, flat 4-directional), authored for that same diorama scale.

The project owner is planning to author new assets as real 3D models (top-down/orthographic view) instead of trying to reproduce the original's canvas trick. That's a clean, arguably simpler path in Godot: `Node3D` scene with an orthogonal `Camera3D`, `Light3D` nodes standing in for the flashlight/beam mechanics the original hand-rolled in 2D raycasting. A placeholder prop scaffold for that workflow lives in `art/props-3d/` (see its README) — grey-box meshes at a defined scale/pivot convention ready to swap for real imports.

Until that's settled, gameplay/simulation code stays engine-agnostic where practical (the facility generator below produces plain grid/room/corridor data with no rendering assumptions baked in — it feeds either a 2D or 3D presentation layer equally). The *current* placeholder rendering (`src/game/facility_view.gd`) is flat 2D primitive-drawn tiles purely to keep the existing slice playable; do not invest further in it as a real art pipeline.

## Recommended milestones

1. **Foundation** — viewport, controls, folder structure and placeholder scene. *(Complete.)*
2. **Asset intake** — copy canonical tiles/player art and define import presets. *(Blocked on the rendering-architecture decision above — investigated, not started. See MIGRATION.md's open decision.)*
3. **Static room slice** — collision, movement, camera, flashlight and HUD. *(Complete: collision, movement, stamina, lamp, HUD, and a scrolling camera are playable.)*
4. **Procedural facility** — deterministic seed, rooms, corridors and A\* movement. *(Structural generation complete: `src/game/facility_generator.gd` faithfully ports maze.js's sector-grid carving, Kruskal-connected 3-wide corridor graph, and seeded relay/battery/safe-zone/service-lift placement, cross-checked bit-exact against the original's PRNG. Themed room types/furniture (maze.js's `ROOM_TYPES`/`populateRooms`, ~50+ prop types) are deliberately deferred — see "Deferred from milestone 4" below. `AStarGrid2D` pathfinding isn't wired up yet since nothing needs to path — that's part of milestone 6.)*
5. **Last Route loop** — relays, batteries, hiding, safe zone, lift and depth. *(Mostly riding on milestone 4: relay/battery/safe-zone/lift placement and collection, and depth progression via the service lift, are playable. Hiding spots are not — they're props, deferred with the rest of milestone 4's room content.)*
6. **First hunter** — shared perception/chase state machine plus one identity.
7. **Roster** — migrate hunters individually with behavior fixtures.
8. **Persistence** — checkpoint and account-facing client calls.
9. **Co-op** — preserve host-authoritative snapshots against the existing Node server.
10. **Additional modes** — Hide & Seek and Office Survivor after the core is stable.
11. **XR experiment** — create a separate 3D/OpenXR scene; do not couple it to the 2D port. *(May be superseded by the 3D top-down direction above — revisit once that's decided.)*

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
