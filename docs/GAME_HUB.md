# Game hub

Boot now lands on `scenes/game_hub.tscn` (`src/ui/game_hub.gd`) instead of the Last Route menu. The hub is a shell above
the games: one card per game, plus the entries that belong to no single game.

| Piece | Where |
| --- | --- |
| Game list | `src/config/game_registry.gd`: id, title, kicker, tagline, scene, theme, `locked`, `locked_note` |
| Per-game themes | `src/ui/theme_lastroute.tres`, `src/ui/theme_nightwatch.tres` (regenerate with `tools/build_game_themes.gd`) |
| Shared entries | ACCOUNT, SETTINGS, ADMIN, QUIT. Account and settings open the existing panels in the Last Route menu on arrival (`GameHub.pending_menu_action`) until they move out of that scene. ADMIN is enabled for admin accounts and says that the tools open inside a run |
| Back to the hub | `ALL GAMES` in the Last Route menu |
| Captures | `tools/look/hub_capture.tscn` at 1280x720, 1920x1080 and 3440x1440 (`docs/hub_1280x720.png`, `docs/hub_1920x1080.png`, `docs/hub_ultrawide3440x1440.png`) |

The Last Route card plays; the Night Watch card is shown locked with its reason. Flipping `locked` to false and setting a
`scene` in the registry is all it takes to launch a ported Night Watch from the hub.

## Night Watch 3D port plan

Night Watch (`games/night-watch` in the 2D repo) is a first-person overnight desk game: an office you sit in, a camera
monitor with a floor map, rooms with hunters moving between them on a graph, doors/lights/masks as defences, a clock
from 12 AM to 6 AM, and several modes (`src/modes/`: classic, mask, dayshift, bedroom, mixed, descent, lure, openair, story;
player-facing names Classic, Masked Hours, Dead Air, Bedtime, The Facility, The Descent, Salvage Run, Open Air).
Each mode has its own office art and hunter roles (`docs/LAST_ROUTE_MATCH.md` in the 2D repo maps every hunter to a role).
It shares the hunter roster and the death lines with Last Route (`kyttu-death-lines/v1`).

Plan, in order:

1. **Shell and data.** Port `core/roster.js`, `graph.js`, `time.js`, `rng.js` and the mode registry to GDScript as pure
   simulation (no scenes), with validators like the Last Route ones. Reuse `HunterRoster`, the blocky hunter models and
   `DeathLines`/`DeathMoment` as they are.
2. **The office as a 3D room.** One authored room in the blocky style (desk, monitor, two doors, lamp), a fixed seated
   camera with look-around limits. Door/light/mask state is plain flags driven by the simulation.
3. **Camera feeds.** Each camera is a SubViewport looking at its room (the hunters are real models posed from
   `core/poses.js`); the monitor shows the feed with the existing pixel/noise effect. `cam-floors.js` / `cam-spots.js`
   become camera nodes.
4. **Night loop.** Clock, power/pressure (`pressure.js`), scare (`scare.js`), snapshot/resume (`snapshot.js`) as autoload
   state, saved through the same `/api/v1/saves/:gameId/:slot` path with game id `night-watch`.
5. **Modes.** Classic first, then the rest in registry order (`modes/registry.js`), one office scene per mode.
6. **Account and admin.** Reuse `Backend` and the admin menu tabs; the admin rules in `src/account/admin-rules.js` map to the
   same permission names.
7. **Launch.** Flip `locked` to false in `GameRegistry`, set `scene`, add the Night Watch theme to its own menus.

Nothing of Night Watch is ported yet; this page is the plan only.
