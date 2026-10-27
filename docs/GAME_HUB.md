# Game hub

Boot now lands on `scenes/game_hub.tscn` (`src/ui/game_hub.gd`) instead of the Last Route menu. The hub is a shell above
the games: one card per game, plus the entries that belong to no single game.

| Piece | Where |
| --- | --- |
| Game list | `src/config/game_registry.gd`: id, title, kicker, tagline, scene, theme, `locked`, `locked_note` |
| Per-game themes | `src/ui/theme_lastroute.tres`, `src/ui/theme_nightwatch.tres` (regenerate with `tools/build_game_themes.gd`) |
| Shared entries | ACCOUNT, SETTINGS, ADMIN, QUIT. Account and settings open the existing panels in the Last Route menu on arrival (`GameHub.pending_menu_action`) until they move out of that scene. ADMIN is enabled for admin accounts and says that the tools open inside a run |
| Navigation | The hub is the main menu: boot lands on it and every game returns to it. The Last Route menu's last button is `BACK TO GAMES` (it no longer quits), leaving a route, the lobby's `BACK TO GAMES`, and a finished run all go to `GameRegistry.HUB_SCENE`. QUIT exists only on the hub, asks `QUIT TO DESKTOP?` (YES/NO), and is hidden on web builds. Esc on the hub does nothing (it only closes that question) |
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

## Navigation test

`scenes/hub_nav_test.tscn` (`scripts/hub_nav_test.gd`) drives real scene changes from a node under the root:

```sh
godot --headless --path . res://scenes/hub_nav_test.tscn
```

Hub -> Last Route menu -> back, twice with the node count compared; Esc stays on the hub; then a real solo route is loaded, left
(`_leave_test`, which returns to the lobby), and the lobby's back button returns to the hub; game state and orphan nodes are
checked. It prints `hub_nav ...` and exits non-zero on failure. The `hub` validator also asserts that only the hub contains
`get_tree().quit()` among the menu, pause, lobby, run report, route and admin scripts.

## Accounts (one login for the whole app)

The account is Kyttu's Lab's, not a game's. The signed-in account, session tokens per server, admin/owner status and the debug
flags are app-level state in the `Backend` autoload; nothing about them lives in a game's scene.

| Piece | Where |
| --- | --- |
| The panel | `AccountPanel` (`src/ui/account_panel.gd`, `scenes/account_panel.tscn`), titled `KYTTU'S LAB // ACCOUNT`: sign in, create account, sign out, account settings (username, password, the admin setup key field) and a SAVES list |
| Opening it | `AccountPanel.open(self)` from any scene. The hub's ACCOUNT button and every game menu's account button call exactly this; there is no per-game copy |
| Who is signed in | `Backend.signed_in()`, `Backend.account_username`, `Backend.account_admin`; the `Backend.account_changed` signal fires for every sign-in/out/rename, so the hub header (`SIGNED IN // NAME [ADMIN]`), the Last Route menu's account button and an open panel all follow it |
| Saves per game | the panel's SAVES section has one row per `GameRegistry` game: `GameRegistry.save_summary(id)` gives `{has_save, text}`; OPEN is a link into that game's menu scene, CLEAR (with a SURE? confirm) calls `Backend.account_clear_game_progress(id)`. A new game appears with no panel change |
| Last Route's save | `CONTINUE ROUTE` / `CLEAR SAVE` and the saved-route summary are in the Last Route menu, not in the account panel |

### Per-game account data

Last Route's record is the account document itself (route checkpoint, hunter discoveries), exactly as before, so old accounts and
saves load unchanged. Every other game keeps its record under `games.<game_id>` in the same document; the backend stores the
document opaquely, so no server change or migration is involved.

```gdscript
Backend.game_progress("city")                                  # -> Dictionary ({} when none)
Backend.game_has_save("city")
Backend.account_save_game_progress("city", {"summary": "DISTRICT 2", ...})   # "summary" is what SAVES lists
Backend.account_clear_game_progress("city")
```

`account_save_progress` / `account_clear_progress` (Last Route) keep other games' records intact. Rooms and the public route are
namespaced by a `game` field (the City lane added it, default `last_route`).

### For the City and Night Watch lanes

- Open the shared panel with `AccountPanel.open(self)`; do not build another account dialog or keep game-level login state.
- Register your game in `GameRegistry.GAMES` (the registry is the only list the hub, the panel's SAVES and the controls follow) and
  write saves through `Backend.account_save_game_progress(<id>, {"summary": ...})`.
- Files likely to conflict with this change: `src/config/game_registry.gd` (new `save_summary`, `active_game_id`, `HUB_SCENE`),
  `src/autoload/backend_client.gd` (the per-game progress block after `account_clear_progress`), `src/ui/game_hub.gd`,
  `src/ui/main_menu.gd` (account code removed; saved-route buttons added), `scripts/validate_layout.gd` (account dialog checks now
  target the shared panel), `scripts/validate_runner.gd` (suite list), `docs/GAME_HUB.md`.

Validators: `account_hub` (one panel from the hub, header follows sign-in, a SAVES row per game, no Last Route wording in the panel,
legacy Last Route save still loads, another game's save does not touch it and clearing one leaves the other).
