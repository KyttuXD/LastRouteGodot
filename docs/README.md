# Godot 2 documentation index

Branch `ref-look` (Godot 4.7, Compatibility renderer). Everything below is current as of this branch; root-level files predate the restyle and cover the port itself.

## Start here
| Doc | Covers |
| --- | --- |
| [../README.md](../README.md) | Opening the project, controls, menus, exports, updater |
| [TESTING.md](TESTING.md) | Godot path, validator suites, **the 9 known failures**, co-op and public-route tests |
| [../REF_LOOK.md](../REF_LOOK.md) | The restyle: textures, lighting, light budget, single level, taller rooms, halls and arches, apartments, props, UI theme and logo, capture rig |

## Game systems
| Doc | Covers |
| --- | --- |
| [../INFINITE_WORLD.md](../INFINITE_WORLD.md) | Streamed generator, chunks, regions, room sizes and connectors |
| [BLOCKY_HUNTERS.md](BLOCKY_HUNTERS.md) | Blocky A-Z and Void hunters: pipeline, clips, expressions, scythe, toggles |
| [BLOCKY_VOID.md](BLOCKY_VOID.md) | Void-specific notes (cues, emissive eyes, emotes) |
| [../HUNTER_ROSTER.md](../HUNTER_ROSTER.md) | Roster data and gimmicks |
| [HUNTER_EMOTES.md](HUNTER_EMOTES.md) | Hunter emotes: triggers, personality, fallbacks, replication, the clip spec for the animation session |
| [Z_FIGHTING.md](Z_FIGHTING.md) | Coplanar-face detector, camera depth range, findings |
| [SPECTATORS.md](SPECTATORS.md) | Dead/caught runners spectate; party wipe; revive |
| [ADMIN_TOOLS.md](ADMIN_TOOLS.md) | In-game admin overlay (key 0) |
| [../PUBLIC_ROUTE.md](../PUBLIC_ROUTE.md) | The always-open PUBLIC route and multiplayer testing |

## Shipping
| Doc | Covers |
| --- | --- |
| [TEST_MULTIPLAYER.md](TEST_MULTIPLAYER.md) | Several instances on one Mac, test builds for another computer, ports, VPS commands |
| [DEPLOY_VPS3.md](DEPLOY_VPS3.md) | Backend on VPS 3: production and test instance, remote test scripts, rollback |
| [DISTRIBUTION.md](DISTRIBUTION.md) | Exports, updater, and the downloads page plan (kyttuslab.org) |
| [../IOS.md](../IOS.md), [../XR.md](../XR.md) | iOS and XR tracks |
| [../MIGRATION.md](../MIGRATION.md), [../PLAYABILITY.md](../PLAYABILITY.md), [../PORTING_AUDIT.md](../PORTING_AUDIT.md) | Port history and checklists |

Never put secrets (admin setup key, tokens, passwords) in any of these files.
- [HUNTER_PATHING.md](HUNTER_PATHING.md) — real-play hunter stuck causes, stuck telemetry, hunter_real validator
- [HUNTER_PARITY.md](HUNTER_PARITY.md) — 2D vs 3D hunter mechanics audit and what was ported
- [DEATH_SCENES.md](DEATH_SCENES.md) — death lines catalog, the death moment, wipe variant
- [GAME_SCHEMES.md](GAME_SCHEMES.md) — per-game colour/style schemes for the shared menus (Last Route vs the City)
- [DESKTOP_UPDATES.md](DESKTOP_UPDATES.md) — macOS/Windows self-update: rule, confirm, swap, rollback, publish steps
- [HUD_LAYOUT.md](HUD_LAYOUT.md) — in-game HUD: status bar, content-sized panels, safe margins, chat collapse, hud_overlap suite
- [GAME_HUB.md](GAME_HUB.md) — hub shell, game registry, themes, Night Watch 3D port plan
- [PROPS_AUDIT.md](PROPS_AUDIT.md) — props audits (DONE11 chairs and tables, DONE13 rotated parts and weak families, DONE14 materials and finishes, DONE16 performance), measured sizes, fixes, contact sheets
- [RESCUE_AXE.md](RESCUE_AXE.md) — held-tool poses (grip table, wall push-back, remote hand), the rescue axe (cut free of a hold, chop boards, noise, durability), captures
- [Z_FIGHTING_PROPS.md](Z_FIGHTING_PROPS.md) — coplanar faces inside prop models (beds, cabinets, couches, doors): builder fix, prop_coplanar suite, bed flicker before/after
- [HIDING_PROPS.md](HIDING_PROPS.md) — room props by purpose (infirmary, storage, reception, archive, bedroom) and hiding under beds / in wardrobes, hunter checks with a tell
- [MANSION_LUXURY.md](MANSION_LUXURY.md) — mansion finishes (lacquer, marble, velvet, gilt) for the ordinary furniture types, columns and vases, bed scale fix, before/after
- [REST_AND_SLEEP.md](REST_AND_SLEEP.md) — rest camera on chairs and beds (what was wrong, the fix), runner sleep and solo drowsiness, hunter naps
- [LIGHT_SWITCHES.md](LIGHT_SWITCHES.md) — room light switches in the streamed world: lamps per room, light sight, persistence, co-op, hunters
- [PROP_ORIENTATION.md](PROP_ORIENTATION.md) — pairing table: what faces what, backs to walls, seats in front of screens; before/after
- [NIGHT_WATCH_3D.md](NIGHT_WATCH_3D.md) — Night Watch 3D: audit of the 2D game, 2D to 3D mapping, milestones, first playable slice
- [COLLISION.md](COLLISION.md) — colliders from models, door keep-clear and walk-through clean-up, SHOW COLLISION, validators
- [ROOM_SIZES.md](ROOM_SIZES.md) — room-purpose size profiles, 21x21 great halls, table-grid templates, validators
- [WAYPOINTS.md](WAYPOINTS.md) — one waypoint per player, crosshair placement, HUD pin and edge arrow, guidance modes, City support, co-op, audit of the old system
- [MATERIAL_LOOK.md](MATERIAL_LOOK.md) — matte-by-default material and light look: audit, the shared MaterialLook constants, validator, before/after
- [HUNTER_SCALE.md](HUNTER_SCALE.md) — tall hunter variants removed, one shared 1.5x hunter scale and what follows it, validator, before/after
- [WALL_THEMES.md](WALL_THEMES.md) — per-face wall themes (no room bleed onto halls), floor sets per district and room purpose, validator
- [AMBIENCE.md](AMBIENCE.md) — ambient beds per district and room purpose (AmbienceTable), footsteps by floor surface (SurfaceSounds), validator
- [LIGHT_SIGHT.md](LIGHT_SIGHT.md) — mutual light sight: LightField exposure, lit hunters see the runner, validator
- [YSOLDE.md](YSOLDE.md) — Ysolde avoids or runs from the runner (behaviour constant), validator
- [RAVELLE_TRAPS.md](RAVELLE_TRAPS.md) — Ravelle tripwires: stun, bells, visible tell, cut-wire counter, replication, validator
- [CONTROLS.md](CONTROLS.md) — per-game controls tabs, ControlsRegistry API
- [PLAYTEST.md](PLAYTEST.md): the playtest bridge, bots, swarm and how an agent playtests the real game.
- [FLYTHROUGH.md](FLYTHROUGH.md): one-command flythrough videos of every area of a commit, rendered on the test Mac.
- KYTTU: The City (and its OpenStreetMap "real places" maps) is archived on branch `archive/city-20261027` (see its docs/CITY_ARCHIVE.md); it is no longer part of main.
- [XR_ANDROID.md](XR_ANDROID.md) — Android phone and OpenXR (Quest/PC VR) support: PlatformProfile flags and budgets, export presets, building on the mini, milestones
