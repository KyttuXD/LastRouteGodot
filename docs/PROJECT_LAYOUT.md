# Where things live

Rule of thumb: **scene and script live together by feature.** Tests, tools and raw art sources stay out of the game folders.

| Folder | What |
|---|---|
| `game/autoload/` | 12 autoloads (GameState, Settings, RoomState, ...) |
| `game/boot/` | boot_loading / route_loading / update_progress (.tscn + .gd). `run/main_scene` = `res://game/boot/boot_loading.tscn`; boot lands on `GameRegistry.landing_scene()` (the Last Route menu while `GameRegistry.SKIP_HUB` and one unlocked game, else the hub; see `docs/GAME_HUB.md`) |
| `game/menus/` | main_menu, game_hub, room_lobby, account_panel, settings_overlay, run_report, pause/settings/skin/mods/voice panels |
| `game/hud/` | hud.tscn + hud*, crosshair, radar, facility_map, waypoints, touch controls, perf_overlay, toasts |
| `game/ui_common/` | ui_theme, menu list, hud bar, input glyphs, signal effects, `ref_theme.tres`, `theme_lastroute.tres` |
| `game/player/` | player controller, first-person body, held items, faces/emotes, meters, skins, revive, NPC teammates |
| `game/hunters/ai/` | hunter brain/director/roam/naps/peek/seats/emoter/inspect, streamed navigation, hard abilities |
| `game/hunters/gimmicks/` | per-hunter gimmicks (+ `void_hunter_gimmicks/`) |
| `game/hunters/view/` | hunter_view_3d, stride, facing, grab, jumpscare (.tscn), addons, model_slot, creature_view |
| `game/world/generation/` | route generators, facility_generator, room recipes/capacity, seeded_random, custom maps, stairwells, levels |
| `game/world/streaming/` | streamed world state, (streamed_)facility_view_3d, prop_mesh_merge, ceiling decor, doorway frames |
| `game/world/regions/` | sewers/floods, vents, inferno, void, music wing, breach, `carnival/` (+ booth/carousel 3D) |
| `game/world/interactables/` | route_interactable_3d, ladders, breakables, music boxes, seals, loot, hide/seat occupancy |
| `game/world/collision/` | collision world, audits, geometry resolve, placement clearance, collision overlay |
| `game/look/` | lighting/material look, shaders, quality governor, light_field, quality_tier |
| `game/network/` | net protocol/peers, remote players, voice, route gates, guest guard |
| `game/xr/` | XR panels, hands, comfort |
| `game/night_watch/` | Night Watch (per-mode subfolders; each mode's `night_watch_<mode>.tscn` sits in its folder) |
| `game/admin/` | admin menu/panels, debug view, troll ads, admin pulse |
| `game/infinite_route/` | the endless Infinite Route scene (`infinite_route_test.tscn/.gd`, name kept) |
| `game/main_3d.tscn/.gd`, `game/audio`, `game/config`, `game/mods`, `game/story` | as before |
| `assets/props/<set>/` | room-prop GLBs + atlases (blocky, mansion, maze, sewer, prison, nether, beach, carnival, hunter_items) |
| `assets/interactables/`, `assets/environment/` | runtime models/textures |
| `assets/custom_maps/` | sample custom-map PNGs + palette |
| `assets/hunters_blocky/`, `assets/ui/hunter_portraits/` | **unchanged on purpose** (mod API paths) |
| `art_source/` | `.blend`, `.bbmodel`, `source/` textures (`.gdignore`, excluded from export) |
| `data/story/` | infinite route stories json |
| `tests/` | `validate_*.gd`, `validate_runner.gd`, smoke/coop/handoff tests, `fixtures/`, `data/` goldens, `scenes/validate.tscn` + smoke scenes |
| `dev/playtest/` | Playtest autoload + `playtest_runner.tscn` (ships, like before) |
| `dev/look/` | look-dev capture scenes (excluded from export) |
| `tools/build/` | `run_suites.py`, `setup_godot.sh`, `export_*.sh`, `*.bat` launchers, `generate_*.mjs` |
| `docs/design/`, `docs/modding/`, `docs/images/` | design notes, modding guide, doc screenshots (`docs/` is `.gdignore`'d) |

Common commands:

```sh
python3 tools/build/run_suites.py --jobs 1 playtest room          # suites
godot --headless --path . res://tests/scenes/validate.tscn -- sync # one suite in-process
godot --headless --fixed-fps 60 --path . res://dev/playtest/playtest_runner.tscn -- --playtest-runner ...
```

Mods: `res://assets/hunters_blocky/<id>/<id>.glb` and `res://assets/ui/hunter_portraits/` are stable. A third-party pack must use `res://assets/props/...` etc.
