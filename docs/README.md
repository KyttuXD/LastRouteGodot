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
- [GAME_HUB.md](GAME_HUB.md) — hub shell, game registry, themes, Night Watch 3D port plan
- [NIGHT_WATCH_3D.md](NIGHT_WATCH_3D.md) — Night Watch 3D: audit of the 2D game, 2D to 3D mapping, milestones, first playable slice
- [PROPS_AUDIT.md](PROPS_AUDIT.md) — props audits (DONE11 chairs and tables, DONE13 rotated parts and weak families, DONE14 materials and finishes, DONE16 performance), measured sizes, fixes, contact sheets
- [COLLISION.md](COLLISION.md) — colliders from models, door keep-clear and walk-through clean-up, SHOW COLLISION, validators
- [ROOM_SIZES.md](ROOM_SIZES.md) — room-purpose size profiles, 21x21 great halls, table-grid templates, validators
- [CONTROLS.md](CONTROLS.md) — per-game controls tabs, ControlsRegistry API
