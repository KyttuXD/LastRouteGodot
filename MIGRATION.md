# LastRoute migration plan

The original game is a dependency-free JavaScript/Canvas project. Its source is design and behavior reference material; Godot scenes and GDScript replace the browser runtime rather than wrapping it.

## Reuse directly

- PNG/WebP sprites, tiles, backgrounds and UI art
- OGG/WAV audio
- hunter identities, tuning values and design documents
- YAML dialogue and cutscene content after choosing a Godot loader/import format
- the Node room/account server during the early client migration

## Rewrite in Godot

- Canvas renderer → Node2D, TileMapLayer, Light2D and shaders
- procedural maze/A* → generator service plus AStarGrid2D
- player loop → CharacterBody2D controller and gameplay components
- hunter prototype mixins → hunter scenes with shared and per-identity states
- DOM HUD/menu → Control scenes
- browser storage → ConfigFile/Resource saves
- HTTP polling client → HTTPRequest-based network service

## Recommended milestones

1. **Foundation** — viewport, controls, folder structure and placeholder scene. *(Complete.)*
2. **Asset intake** — copy canonical tiles/player art and define import presets.
3. **Static room slice** — collision, movement, camera, flashlight and HUD. *(In progress: collision, movement, stamina, lamp and HUD are playable.)*
4. **Procedural facility** — deterministic seed, rooms, corridors and A* movement.
5. **Last Route loop** — relays, batteries, hiding, safe zone, lift and depth.
6. **First hunter** — shared perception/chase state machine plus one identity.
7. **Roster** — migrate hunters individually with behavior fixtures.
8. **Persistence** — checkpoint and account-facing client calls.
9. **Co-op** — preserve host-authoritative snapshots against the existing Node server.
10. **Additional modes** — Hide & Seek and Office Survivor after the core is stable.
11. **XR experiment** — create a separate 3D/OpenXR scene; do not couple it to the 2D port.

## First playable target

The first meaningful target should be one deterministic floor containing:

- one player
- one hunter
- one relay
- one battery
- one hiding spot
- one safe zone
- one service lift

Completing that slice validates the architecture before the full hunter roster and multiplayer multiply the workload.
