# Game hub

Boot now lands on `game/menus/game_hub.tscn` (`game/menus/game_hub.gd`) instead of the Last Route menu. The hub is a shell above
the games: one card per game, plus the entries that belong to no single game.

## Skipping the hub (`GameRegistry.SKIP_HUB`)

While Night Watch is locked, Last Route is the only playable game, so the hub is skipped. One switch decides it:
`GameRegistry.SKIP_HUB` (a const, `true`). `GameRegistry.hub_skipped()` is true when the switch is on **and exactly one game is
unlocked** (`locked: false`; `unlocked_ids()`). Dev-open games such as Night Watch do not count, so an admin, a `KYTTU_DEV` build
and a headless validator land the same as a player. `GameRegistry.landing_scene()` is the answer everything asks:

- Hub skipped: boot (`boot_loading.gd`, decided once when the menu load starts), the update screen's way back
  (`update_progress.gd`) and the locked-Night-Watch bounces (`night_watch_menu.gd`, `night_watch_mode.gd`) land on the Last Route
  menu. That menu carries the hub's shared row itself: ACCOUNT and SETTINGS (always there), ADMIN (before QUIT; `GameHub.admin_entry_visible()`,
  opens `HubAdminPanel`, follows sign-in live) and QUIT (the last button, relabelled from BACK TO GAMES at run time; hidden where
  `PlatformProfile.can_quit()` is false, i.e. web and iOS). QUIT asks "QUIT TO DESKTOP?" with the hub's own dialog
  (`game/ui_common/quit_confirm.gd`, shared by both; NO is focused, Esc closes it, YES calls `PlatformProfile.quit_app`).
- Hub shown (switch off, or a second game unlocked): exactly the behaviour described below; the menu's last button is `BACK TO GAMES`.
- Unchanged either way: every "back to the menu" path (lobby back, run report, pause menu, leaving or losing a room, crash restart)
  already goes through `RoomState.menu_scene_path()` to the game's own menu; `Settings.hub_last_game` is still written there. The hub
  scene, the registry and Night Watch stay for when a second game unlocks. Night Watch's own `quit_to_games` still goes to the hub.
- Tests flip the switch with `GameRegistry.skip_hub_override` (-1 follows the const, 0 off, 1 on) and `GameRegistry.test_games`.
  Suites: `skip_hub` (landing for 1 vs 2 games and both switch settings, QUIT/ADMIN, focus order, 480x270 layout), plus the
  switch-aware `hub`, `admin_entry`, `update_gate`, `button_contrast` and `tests/hub_nav_test.tscn` (real scene changes, both modes).


| Piece | Where |
| --- | --- |
| Game list | `game/config/game_registry.gd`: id, title, kicker, tagline, scene, theme, `locked`, `locked_note` |
| Per-game themes | `game/ui_common/theme_lastroute.tres`, `game/night_watch/theme_nightwatch.tres` (regenerate with `tools/build_game_themes.gd`) |
| Shared entries | ACCOUNT, SETTINGS, ADMIN, QUIT. Account and settings open the existing panels in the Last Route menu on arrival (`GameHub.pending_menu_action`) until they move out of that scene. ADMIN is enabled for admin accounts and says that the tools open inside a run |
| Navigation | With the hub shown it is the main menu: boot lands on it (see "Skipping the hub"). The Last Route menu's last button is `BACK TO GAMES` (it no longer quits) and that is what returns to `GameRegistry.HUB_SCENE`. Lobby back (`BACK TO LAST ROUTE`), leaving a route, and a finished run land on that game's own menu (`main_menu.tscn` for Last Route; `RoomState.menu_scene_path()`). A solo leave from the streamed route still returns to staging first, and the lobby's back button then opens the same menu. QUIT exists only on the hub, asks `QUIT TO DESKTOP?` (YES/NO), and is hidden on web builds. Esc on the hub does nothing (it only closes that question) |
| Layout | An arrow carousel, see below |
| Captures | `dev/look/hub_capture.tscn` at 1280x720, 1440x840, 1920x1080, 2560x1440, 3440x1440 and phone-landscape 844x390 (`docs/hub_carousel_<size>.png`, plus `docs/images/hub_carousel_real_1280x720.png` with the real registry) |

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

## Arrow carousel

The games sit in a carousel (`GameHub`), not a row of cards, so any number of games fits at any window size.

- One game is focused: its card is centred and large (200 UI units wide), with a big `<` and `>` arrow button on each side
  (`LeftArrow`, `RightArrow`). The neighbours peek in at half size, dimmed, only when they fit whole beside it; otherwise
  they stay out of the stage (it clips) and the arrows plus the position indicator show where you are.
- A position indicator sits under the stage: dots for up to 8 games and always `k / n`.
- Left/Right and A/D, the d-pad / left stick and the shoulder buttons, the mouse wheel over the stage, a swipe (24 UI units
  sideways) and the arrows move the selection; it wraps around at both ends. Clicking a peeking neighbour brings it forward.
  Enter, Space or PLAY launches the focused game; a locked game stays selectable and its PLAY says LOCKED with the reason shown
  on the card. The shared row (ACCOUNT / SETTINGS / ADMIN / QUIT) keeps its own left/right focus navigation.
- The slide animation takes 0.22 s and is skipped when `Settings.reduced_motion` is on.
- The card scales down to fit a small stage and never up. The stage is measured in UI units, so the real expand-stretch rule
  (480x270 base, wider windows add width) decides what fits: at 480x270 only the focused card and the arrows show, at 584x270
  and wider the neighbours peek.
- The game played last is the default focus: `Settings.hub_last_game` (config section `hub`, key `last_game`), written when a
  game launches. An unknown id falls back to the default game.
- `GameRegistry.test_games` replaces the list (tests use 1, 3, 5 and 12 synthetic games); `GameHub.launch_override` intercepts a
  launch. Accent colours come from each game's theme (`GameCard` frame border) or an optional `accent` key in the registry.

The `hub_carousel` validator (`tests/validate_hub_carousel.gd`) opens the hub at 1280x720, 1440x840, 1920x1080, 2560x1440,
3440x1440 and 844x390 with 1, 3, 5 and 12 games and checks that the stage, the focused card, both arrows, the indicator and the
shared row sit inside the viewport, that the arrows do not touch the stage, that neighbours are either whole inside the stage
or fully outside it and never overlap the focused card, that stepping left/right wraps, that keys, arrows, wheel, swipe and a
click on a neighbour work, that Enter launches the focused game and does nothing on a locked one, and that the last played game
is the default focus.

## Navigation test

`tests/scenes/hub_nav_test.tscn` (`tests/hub_nav_test.gd`) drives real scene changes from a node under the root:

```sh
godot --headless --path . res://tests/scenes/hub_nav_test.tscn
```

Hub -> Last Route menu -> back, twice with the node count compared; Esc stays on the hub; then a real solo route is loaded, left
(`_leave_test`, which returns to the lobby), and the lobby's back button returns to the Last Route menu (`BACK TO LAST ROUTE`);
game state and orphan nodes are checked. It prints `hub_nav ...` and exits non-zero on failure. The `hub` validator also asserts that only the hub contains
`get_tree().quit()` among the menu, pause, lobby, run report, route and admin scripts.

## Accounts (one login for the whole app)

The account is Kyttu's Lab's, not a game's. The signed-in account, session tokens per server, admin/owner status and the debug
flags are app-level state in the `Backend` autoload; nothing about them lives in a game's scene.

| Piece | Where |
| --- | --- |
| The panel | `AccountPanel` (`game/menus/account_panel.gd`, `game/menus/account_panel.tscn`), titled `KYTTU: THE LAST ROUTE`: sign in, create account, sign out, account settings (username, password, the admin setup key field) and a SAVES list |
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
namespaced by a `game` field (added for the City game, default `last_route`).

### For the City and Night Watch games

- Open the shared panel with `AccountPanel.open(self)`; do not build another account dialog or keep game-level login state.
- Register your game in `GameRegistry.GAMES` (the registry is the only list the hub, the panel's SAVES and the controls follow) and
  write saves through `Backend.account_save_game_progress(<id>, {"summary": ...})`.
- Files likely to conflict with this change: `game/config/game_registry.gd` (new `save_summary`, `active_game_id`, `HUB_SCENE`),
  `game/autoload/backend_client.gd` (the per-game progress block after `account_clear_progress`), `game/menus/game_hub.gd`,
  `game/menus/main_menu.gd` (account code removed; saved-route buttons added), `tests/validate_layout.gd` (account dialog checks now
  target the shared panel), `tests/validate_runner.gd` (suite list), `docs/GAME_HUB.md`.

Validators: `account_hub` (one panel from the hub, header follows sign-in, a SAVES row per game, no Last Route wording in the panel,
legacy Last Route save still loads, another game's save does not touch it and clearing one leaves the other).
