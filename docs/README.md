# Documentation index

The project overview is in the [top-level README](../README.md).

## Getting started
| Doc | Covers |
| --- | --- |
| [QUICK_START.md](QUICK_START.md) | Controls: keyboard, gamepad, touch, hiding, inventory, chat, saves, co-op rooms |
| [CONTROLS.md](CONTROLS.md) | Per-game controls tabs, the controls registry, default bindings |
| [PROJECT_LAYOUT.md](PROJECT_LAYOUT.md) | Where things live in the repository |
| [TESTING.md](TESTING.md) | Running the validator suites, multiplayer and public-route tests |
| [TEST_MULTIPLAYER.md](TEST_MULTIPLAYER.md) | Several instances on one machine, or another computer |

## Build and distribution
| Doc | Covers |
| --- | --- |
| [DISTRIBUTION.md](DISTRIBUTION.md) | Exports and the updater |
| [DESKTOP_UPDATES.md](DESKTOP_UPDATES.md) | Desktop self-update: rule, swap, rollback |
| [WEB_BUILD.md](WEB_BUILD.md) | Web build and its limits |
| [XR_ANDROID.md](XR_ANDROID.md), [design/XR.md](design/XR.md), [design/IOS.md](design/IOS.md) | Android, OpenXR and iOS tracks |
| [../backend/README.md](../backend/README.md) | The Node backend |

## World and generation
| Doc | Covers |
| --- | --- |
| [design/INFINITE_WORLD.md](design/INFINITE_WORLD.md) | Streamed generator, chunks, regions |
| [design/PUBLIC_ROUTE.md](design/PUBLIC_ROUTE.md) | The always-open public route |
| [DATA_DRIVEN_CONTENT.md](DATA_DRIVEN_CONTENT.md) | Data-driven props, regions and hunters |
| [REGION_RULES.md](REGION_RULES.md) | Making and re-texturing a region |
| [WALL_THEMES.md](WALL_THEMES.md) | Wall and floor themes |
| [ROOM_SIZES.md](ROOM_SIZES.md) | Room sizes by purpose |
| [AMBIENCE.md](AMBIENCE.md) | Ambient beds and footsteps |
| [MATERIAL_LOOK.md](MATERIAL_LOOK.md) | Matte material and light look |
| [LIGHT_SWITCHES.md](LIGHT_SWITCHES.md), [LIGHT_SIGHT.md](LIGHT_SIGHT.md) | Room lights and mutual light sight |
| [COLLISION.md](COLLISION.md) | Colliders, walkways, the collision view |
| [SCALE_FIT.md](SCALE_FIT.md) | Scale of the world, hunters and runners |
| [ORIGINAL_PROPS.md](ORIGINAL_PROPS.md), [HIDING_PROPS.md](HIDING_PROPS.md) | Props and hiding furniture |
| [SEWERS.md](SEWERS.md), [VENTS.md](VENTS.md), [INFERNO_CAVERNS.md](INFERNO_CAVERNS.md), [CARNIVAL_BOOTHS.md](CARNIVAL_BOOTHS.md), [BREACH.md](BREACH.md) | Special areas and breakables |
| [WAYPOINTS.md](WAYPOINTS.md) | Waypoint pins and guidance |

## Hunters
| Doc | Covers |
| --- | --- |
| [BLOCKY_HUNTERS.md](BLOCKY_HUNTERS.md), [BLOCKY_ANIMATION.md](BLOCKY_ANIMATION.md) | Hunter models and animation |
| [HUNTER_ADDONS.md](HUNTER_ADDONS.md) | Rig add-ons |
| [HUNTER_EMOTES.md](HUNTER_EMOTES.md) | Emotes |
| [HUNTER_GRABS.md](HUNTER_GRABS.md) | Grabs and escapes |
| [HUNTER_HARD_ABILITIES.md](HUNTER_HARD_ABILITIES.md) | Abilities per difficulty |
| [HUNTER_PATHING.md](HUNTER_PATHING.md) | Pathing and stuck detection |
| [HUNTER_ID_ALIASES.md](HUNTER_ID_ALIASES.md) | Hunter id aliases |
| [RAVELLE_TRAPS.md](RAVELLE_TRAPS.md) | Ravelle's tripwires |

## Player and gameplay
| Doc | Covers |
| --- | --- |
| [SPECTATORS.md](SPECTATORS.md), [REVIVE.md](REVIVE.md) | Spectating, revive kits, stackable items |
| [RESCUE_AXE.md](RESCUE_AXE.md) | Held tools and the rescue axe |
| [REST_AND_SLEEP.md](REST_AND_SLEEP.md) | Resting, sleeping, hunter naps |
| [DEATH_SCENES.md](DEATH_SCENES.md) | Death lines and the death moment |
| [NPC_TEAMMATES.md](NPC_TEAMMATES.md) | NPC teammates |
| [PLAYER_SKINS.md](PLAYER_SKINS.md) | Custom player skins |
| [VOICE_CHAT.md](VOICE_CHAT.md) | Voice and spoken chat |
| [HUD_LAYOUT.md](HUD_LAYOUT.md) | HUD layout |
| [ANTI_CHEAT.md](ANTI_CHEAT.md) | Co-op host checks |
| [ADMIN_TOOLS.md](ADMIN_TOOLS.md) | In-game admin overlay (debug builds) |
| [GAME_HUB.md](GAME_HUB.md) | Game hub shell and registry |

## Night Watch
[NIGHT_WATCH_MODES.md](NIGHT_WATCH_MODES.md), [NIGHT_WATCH_OFFICES.md](NIGHT_WATCH_OFFICES.md), [NIGHT_WATCH_POSES.md](NIGHT_WATCH_POSES.md), [NIGHT_WATCH_DATA.md](NIGHT_WATCH_DATA.md), [NIGHT_WATCH_ADMIN.md](NIGHT_WATCH_ADMIN.md)

## Modding
Start at [modding/README.md](modding/README.md): [pack format](modding/pack-format.md), [content types](modding/content-types.md), [rules and limits](modding/rules.md), [tools](modding/tools.md), [publishing](modding/publishing.md), [example packs](modding/examples/README.md), and two walkthroughs ([Ember](modding/ember-walkthrough.md), [Poster Shop](modding/poster-shop-walkthrough.md)).

Never put secrets (tokens, keys, passwords) in any of these files.
