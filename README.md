# KYTTU: The Last Route — Godot 4

Godot 4 migration workspace for [KYTTU: The Last Route](https://github.com/KyttuXD/LastRoute).

This repository begins with a deliberately small, runnable foundation rather than a generated rewrite, and ports gameplay feature by feature. The active track is a **3D world with a top-down/first-person camera toggle** — see `MIGRATION.md` for why (the original's 2D art is built for a custom perspective canvas renderer that doesn't port cleanly, and the project owner is authoring real 3D assets instead). An earlier 2D `Node2D` port (`scenes/main.tscn`) still exists and works, but is no longer the default scene.

## Open it

1. Start Godot 4.3 or newer.
2. Select **Import** and choose this repository's `project.godot`.
3. Open the project and press **F6** or **F5**.

The default scene (`scenes/main_3d.tscn`) is a playable 3D migration slice: move with **WASD**, hold **Shift** to sprint, hold **C** to crouch, press **F** for the flashlight, **E** to interact, **M** for the map, **V** to toggle between the top-down and first-person cameras (the latter captures the mouse for look), and **Escape/P** to pause.

To run the earlier 2D version instead, open `scenes/main.tscn` directly, or set `run/main_scene` in `project.godot` back to `res://scenes/main.tscn`.

## Current foundation

- a deterministic, seeded procedural facility generator (`src/game/facility_generator.gd`) — sector-grid room carving, a Kruskal-connected 3-wide corridor graph, and relay/battery/safe-zone/service-lift placement, ported from the original's `maze.js` and validated against 1000 seeds (see `MIGRATION.md`). Fully presentation-agnostic — both the 2D and 3D scenes below call the exact same generator unchanged.
- **3D (`scenes/main_3d.tscn`, the default):** a `GridMap`-rendered facility (placeholder flat-colored floor/wall meshes, real physics collision), a `CharacterBody3D` player with two `Camera3D` rigs (orthographic top-down, mouselook first-person) toggled at runtime, and a `SpotLight3D` flashlight. 1 grid cell = 1 meter, matching `art/props-3d/`'s scale convention for future real-art imports.
- **2D (`scenes/main.tscn`, still available):** 480×270 pixel-perfect viewport, nearest-neighbor rendering, a scrolling `Camera2D`, and a runtime-built `TileMapLayer` for facility collision.
- shared between both: stamina exhaustion/recovery and lamp battery drain, relay/battery/safe-zone/service-lift interactions placed procedurally each floor, relay-gated depth progression, and real HUD meters (battery, stamina) with the original's exact color-state and label logic plus a live depth/relay objective readout (`src/ui/hud.gd` + `scenes/hud.tscn`, one shared scene instanced by both presentation layers).
- global run-state autoload, LastRoute input actions, folders that mirror the browser game's modular architecture.

## Project layout

```text
art/props-3d/           Placeholder 3D prop scaffold for real asset imports
assets/                  Imported art, audio, fonts and data
scenes/                  Godot scene files (main.tscn = 2D, main_3d.tscn = 3D, hud.tscn = shared HUD)
scripts/                 Headless validation/dev scripts
src/autoload/            Project-wide state
src/config/              Tuning and content definitions
src/game/                2D simulation and gameplay nodes (facility_generator.gd is shared with 3D)
src/game_3d/             3D presentation layer (GridMap renderer, CharacterBody3D controller, interactables)
src/ui/                  Shared HUD
```

See [`MIGRATION.md`](MIGRATION.md) for the recommended port order and boundaries, and exactly what's done versus deferred in the 3D slice.

## Ground rules

- Keep simulation code independent from presentation where practical — `facility_generator.gd` is the proof this works: identical code drives both the 2D and 3D renderers.
- Build each hunter as a reusable scene plus a state-machine script.
- Store tuning/content in Resources instead of scattering constants across scenes.
- Preserve the existing Node server protocol until the single-player foundation is stable.
- Do not commit `.godot/`, exports, secrets, or runtime account saves.
