# KYTTU: The Last Route — Godot 4

Godot 4 migration workspace for [KYTTU: The Last Route](https://github.com/KyttuXD/LastRoute).

This repository begins with a deliberately small, runnable foundation rather than a generated rewrite, and ports gameplay feature by feature. The active track is a **3D world with a top-down/first-person camera toggle** — see `MIGRATION.md` for why (the original's 2D art is built for a custom perspective canvas renderer that doesn't port cleanly, and the project owner is authoring real 3D assets instead). An earlier 2D `Node2D` port (`scenes/main.tscn`) still exists and works, but is no longer the default scene.

## Open it

1. Start Godot 4.3 or newer.
2. Select **Import** and choose this repository's `project.godot`.
3. Open the project and press **F6** or **F5**.

The game now boots into a **main menu** (`scenes/main_menu.tscn`): **PLAY** starts a real solo run, **SETTINGS** opens key rebinding and a master volume slider, and **CREATE ROOM**/**JOIN ROOM** are visibly present but disabled — there's no multiplayer backend yet (see `MIGRATION.md`).

In a run: move with **WASD**, hold **Shift** to sprint, hold **C** to crouch, press **F** for the flashlight, **E** to interact (also used to mash your way out of a hunter's grip), **M** for the map, **V** to toggle between the top-down and first-person cameras (the latter captures the mouse for look), and **Escape/P** to pause.

To run the earlier 2D version instead, open `scenes/main.tscn` directly.

## Current foundation

- a deterministic, seeded procedural facility generator (`src/game/facility_generator.gd`) — sector-grid room carving, a Kruskal-connected 3-wide corridor graph, `AStarGrid2D` pathfinding, grid-raymarch line of sight, and relay/battery/safe-zone/service-lift/hunter-spawn placement, ported from the original's `maze.js` and validated against 1000 seeds (see `MIGRATION.md`). Fully presentation-agnostic — both the 2D and 3D scenes below call the exact same generator unchanged.
- **a hunter: Dovelle** (`src/game/hunter_brain.gd`) — the original's shared perception/state-machine/movement/capture brain, ported faithfully (sight+hearing detection, idle/wander/investigate/chase/search states, chase-speed scaling, a real mash-`[E]` escape struggle with knockback/stagger/cooldown/lives), scoped to the one baseline identity that uses zero bespoke gimmicks. Presentation-agnostic like the generator — `src/game_3d/hunter_view_3d.gd` is a ~20-line 3D rendering wrapper around it.
- **a main menu** (`scenes/main_menu.tscn`, the default scene) with working settings (`src/autoload/settings.gd`): master volume and full key-rebinding, persisted across sessions.
- **3D (`scenes/main_3d.tscn`):** a `GridMap`-rendered facility (placeholder flat-colored floor/wall meshes, real physics collision), a `CharacterBody3D` player with two `Camera3D` rigs (orthographic top-down, mouselook first-person) toggled at runtime, and a `SpotLight3D` flashlight. 1 grid cell = 1 meter, matching `art/props-3d/`'s scale convention for future real-art imports.
- **2D (`scenes/main.tscn`, still available):** 480×270 pixel-perfect viewport, nearest-neighbor rendering, a scrolling `Camera2D`, and a runtime-built `TileMapLayer` for facility collision. Not yet wired to the hunter.
- shared between both presentation layers: stamina exhaustion/recovery and lamp battery drain, relay/battery/safe-zone/service-lift interactions placed procedurally each floor, relay-gated depth progression, and real HUD meters/overlays (battery, stamina, lives, escape struggle) with the original's exact color-state and label logic (`src/ui/hud.gd` + `scenes/hud.tscn`, one shared scene instanced by both).
- global run-state autoload, LastRoute input actions, folders that mirror the browser game's modular architecture.

## Project layout

```text
art/props-3d/           3D prop scaffold — every model the game loads at runtime; drop real assets in to replace the placeholders (see its README)
assets/                 Imported art, audio, fonts and data
scenes/                 Godot scene files (main_menu.tscn = boot scene, main.tscn = 2D, main_3d.tscn = 3D, hud.tscn = shared HUD)
scripts/                Headless validation/dev scripts
src/autoload/           Project-wide state (GameState, Settings)
src/config/             Tuning and content definitions
src/game/                Presentation-agnostic simulation (facility_generator.gd, hunter_brain.gd) and 2D gameplay nodes
src/game_3d/             3D presentation layer (GridMap renderer, CharacterBody3D controller, interactables, hunter view, model_slot.gd loads visuals from art/props-3d/)
src/ui/                  Shared HUD, main menu, settings panel
```

See [`MIGRATION.md`](MIGRATION.md) for the recommended port order and boundaries, and exactly what's done versus deferred.

## Ground rules

- Keep simulation code independent from presentation where practical — `facility_generator.gd` and `hunter_brain.gd` are the proof this works: identical code drives both the 2D and 3D renderers (2D wiring is currently unfinished for the hunter, but the brain itself needs no changes to support it).
- Build each hunter as a reusable scene plus a state-machine script.
- Store tuning/content in Resources instead of scattering constants across scenes.
- Preserve the existing Node server protocol until the single-player foundation is stable.
- Do not commit `.godot/`, exports, secrets, or runtime account saves.
