# KYTTU: The Last Route — Godot 4

Godot 4 migration workspace for [KYTTU: The Last Route](https://github.com/KyttuXD/LastRoute).

This repository begins with a deliberately small, runnable foundation rather than a generated rewrite. It preserves the original game's 480×270 internal resolution, pixel-perfect scaling, control vocabulary, and modular subsystem boundaries while gameplay is ported feature by feature.

## Open it

1. Start Godot 4.3 or newer.
2. Select **Import** and choose this repository's `project.godot`.
3. Open the project and press **F6** or **F5**.

The initial scene is a playable migration slice: move with **WASD**, hold **Shift** to sprint, hold **C** to crouch, press **F** for the flashlight, **E** to interact, **M** for the map, and **Escape/P** to pause.

## Current foundation

- 480×270 base viewport with 2× default window scaling
- nearest-neighbor pixel rendering
- Linux-friendly OpenGL Compatibility renderer
- LastRoute input actions
- global run-state autoload
- a deterministic, seeded procedural facility generator (`src/game/facility_generator.gd`) — sector-grid room carving, a Kruskal-connected 3-wide corridor graph, and relay/battery/safe-zone/service-lift placement, ported from the original's `maze.js` and validated against 1000 seeds (see `MIGRATION.md`)
- a scrolling `Camera2D` following the player through the generated facility, with collision from a runtime-built `TileMapLayer`
- stamina exhaustion/recovery and lamp battery drain
- reusable relay, battery, safe-zone and service-lift interactions, now placed procedurally each floor instead of hardcoded
- relay-gated depth progression loop, regenerating a fresh floor (and moving the player to its spawn) each descent
- folders that mirror the browser game's modular architecture
- migration plan separating reusable content from rewritten runtime systems, including an open rendering-architecture decision — see `MIGRATION.md`

## Project layout

```text
assets/                 Imported art, audio, fonts and data
scenes/                 Godot scene files
src/autoload/           Project-wide state
src/config/             Tuning and content definitions
src/game/               Simulation and gameplay nodes
src/rendering/          Lighting, fog and visual systems
src/systems/            Input, audio, saves and networking
src/ui/                 Menus and HUDs
```

See [`MIGRATION.md`](MIGRATION.md) for the recommended port order and boundaries.

## Ground rules

- Keep simulation code independent from presentation where practical.
- Build each hunter as a reusable scene plus a state-machine script.
- Store tuning/content in Resources instead of scattering constants across scenes.
- Preserve the existing Node server protocol until the single-player foundation is stable.
- Do not commit `.godot/`, exports, secrets, or runtime account saves.
