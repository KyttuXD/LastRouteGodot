# Night Watch 3D: the nine modes

The 2D game has nine modes (`games/night-watch/src/modes/registry.js`). The 3D game ports them one at a time on a shared framework so
several people (or sessions) can build different modes at once without touching each other's files. This page is the plan, the
framework contract and the status table. The menus already list all nine (`docs/NIGHT_WATCH_MENUS.md`); a mode that is not built says
"NOT BUILT YET" and does not start.

## Status

| # | Mode (2D id) | Shifts | 2D logic to port | 2D validators to port | 3D status |
|---|---|---|---|---|---|
| 1 | Classic (`classic`) | Night 1-7 (7 = Kathy's alone) | `classic/classic-logic.js` 460, `core/kathy.js`, `core/variety-stream.js` | `validate-ai`, `-rng-moves`, `-variety-classic`, `-kathy`, `-toggles`, `-cams` | Nights 1-6 playable (`NightWatchClassic`); Night 7, variety levers, Custom Night to do |
| 2 | Masked Hours (`mask`) | Night 1-6 | `mask/mask-logic.js` 516, `mask-data.js` | `validate-mask`, `-variety-mask` | not built |
| 3 | Dead Air (`lure`) | Night 1-6 | `lure/lure-logic.js` 242, `lure-data.js` | `validate-lure`, `-lure-air`, `-variety-lure` | **Built** (`src/night_watch/lure/`, scene `night_watch_lure.tscn`, suite `night_watch_lure`): Nights 1-6 and Custom Night; the office's DOOR buttons seal the vents, LIGHT runs the heater / fan, the monitor lures and reboots; Xivvy walks the hall. Replays the 2D shift draw for draw (`NightWatchStream`). [capture](night_watch_modes/1280x720_lure_office.png) [monitor](night_watch_modes/1280x720_lure_monitor.png) |
| 4 | Bedtime (`bedroom`) | Night 1-6 | `bedroom/bedroom-logic.js` 126 | `validate-bedroom`, `-variety-bedroom` | **Built** (`src/night_watch/bedroom/`, scene `night_watch_bedroom.tscn`, suite `night_watch_bedroom`): Nights 1-6 and Custom Night; no cameras, you lie in bed and look around from the pillow; hold A / D / F (closet door, hall light, bed light, one hand); Javelle walks the hall, Haelith crosses the floor, Loxelle is only heard until her scare. Replays the 2D shift draw for draw. Javelle has no 3D model yet (Jyvra stands in, `BedroomData.MODEL_STANDIN`). [hall](night_watch_modes/1280x720_bedroom_hall.png) [bed](night_watch_modes/1280x720_bedroom_bed.png) |
| 5 | The Facility (`story`) | Night 1-6 | `story/story-logic.js` 278, `story-data.js` | `validate-story`, `-variety-facility` | **Built** (`src/night_watch/story/`, scene `night_watch_story.tscn`, suite `night_watch_story`): Nights 1-6 and Custom Night; five walkable rooms plus the lift, a station each (terminal and note, lamp dials, parts bench, stage crank, numbered breakers, the lift's call button), doors are the 2D `move` (the player is carried through on foot, hold C to crawl), F beacon, H hide; Opalie / Porcelle / Quenelle walk in as their steps fall. Replays the 2D shift draw for draw. Quenelle has no 3D model yet (Verrine stands in, `StoryData.MODEL_STANDIN`). [gallery](night_watch_modes/1280x720_story_gallery.png) [control](night_watch_modes/1280x720_story_control.png) |
| 6 | The Descent (`descent`) | Descent 1-5 | `descent/descent-logic.js` 280 | `validate-descent`, `-variety-descent` | not built |
| 7 | Salvage Run (`dayshift`) | Week 1-5 | `dayshift/dayshift-logic.js` 214 | `validate-dayshift`, `-variety-salvage` | not built |
| 8 | Open Air (`extra`, code `openair`) | Rooftop, Bus Stop, Campfire | `openair/openair-logic.js` 245 | `validate-openair`, `-variety-openair`, `-lure-air` | not built |
| 9 | Mixed Shift (`mixed`) | Quiet, Steady, Restless, Chaos, Endless | `mixed/mixed-logic.js` 772, `mixed-data.js` | `validate-mixed`, `-mixed-art`, `-mixed-render` | not built |

Shared across modes (port once, in the framework, not per mode): the Custom Night screen and scoring (done in the menu), progress and
stars (done: `NightWatchSave`), the death lines and scare settings (`DeathLines`, `DeathMoment`, Scare setting), Kathy's appearances
(`core/kathy.js`), Zellia's call box (`NightWatchHud`), the resume/save-and-continue store (`core/resume.js`, to do once, after Classic).

## The framework

* **`NightWatchModesData`** (`src/night_watch/night_watch_modes_data.gd`): the 2D registry as data (ids, titles, taglines, blurbs, shifts,
  presets, casts, Custom Night sliders, ratings). Generated from `registry.js`; do not hand-edit.
* **`NightWatchModeRegistry`** (`night_watch_mode_registry.gd`): `SCENES` maps a mode id to its shift scene. Adding one line makes the
  board start it. `prepare(mode, level, custom)` fills `NightWatchSession` and returns the scene path.
* **`NightWatchSession`**: the hand-over from the menu (`mode_id`, `night` = the 1-based level, `seed_value`, `custom_levels`, `is_custom`).
* **`NightWatchMode`** (`night_watch_mode.gd`): the base class of a shift scene. `read_session()`, `record_win(score)`, `retry()`
  (same seed), `next_level()`, `back_to_board()`, `level_name()`, `has_next_level()`, signal `finished(result)`, `manual_clock` for
  validators. NightWatchGame (Classic) extends it; copy it as the pattern.
* **`NightWatchSave`**: progress per mode (`cleared_levels(mode)`, `record_level_clear`, `level_open`, `stars`, `best_score`,
  `custom_values`); the key family is `cleared_<mode>` (Classic keeps `cleared`/`unlocked`). The section is `night_watch` in
  `user://night_watch.cfg`; no mode writes anywhere else.
* **Shared player, prompt, crosshair and sounds**: every mode that has a walkable room uses `scenes/night_watch_player.tscn`
  (the route's PlayerController3D), `NightWatchStation` for interactables and `NightWatchSounds` for cues (docs/NIGHT_WATCH_3D.md 5c).
  A mode that is not walkable (Bedtime, The Descent) still uses the shared Sound autoload and the shared pause key.
* **HUD**: `NightWatchHud` gives the status labels, call box, pause card (RESUME / QUIT TO HUB) and end card (NEXT / RETRY / MENU) in the
  2D wording. A mode reuses it and adds its own panels in its own file.

### One mode, one folder

```
src/night_watch/<mode>/<mode>_data.gd        constants from the 2D <mode>-data.js (pure)
src/night_watch/<mode>/<mode>_logic.gd       the rules from <mode>-logic.js (pure RefCounted, seeded RNG, step(ms, input) -> events)
src/night_watch/<mode>/<mode>_world.gd       the 3D room(s) (Node3D); uses NightWatchArt for blocky shaded props
src/night_watch/<mode>/<mode>_game.gd        extends NightWatchMode: wires logic, world, hud, input, end cards
scenes/night_watch_<mode>.tscn               one Node3D with the game script
scripts/validate_night_watch_<mode>.gd       ported 2D validators + scene checks (suite name night_watch_<mode>)
```

Rules for the logic file: no nodes, no globals except `NightWatchData`/`<mode>_data`, deterministic for a seed, the same numbers as the
2D file (tests compare them), and a `step(delta_ms, input)` the validators drive. Scene files only draw and route input.

### Merge hotspots (the only shared files a mode lane edits)

| File | What a lane changes | How to avoid a clash |
|---|---|---|
| `src/night_watch/night_watch_mode_registry.gd` | one line in `SCENES` | add your line in mode order; keep the rest |
| `scripts/validate_runner.gd` | append your suite name to `SUITES` | append at the end; rebase and keep both |
| `docs/NIGHT_WATCH_MODES.md` | your row in the Status table | edit only your row |
| `src/night_watch/night_watch_sounds.gd` | new cues | put mode cues in `src/night_watch/<mode>/<mode>_sounds.gd` instead |
| `src/night_watch/night_watch_hud.gd` | nothing; build panels in your own file | ask before editing |

Do not edit: `night_watch_modes_data.gd` (generated), `night_watch_save.gd` (mode keys already exist), `night_watch_menu.gd`
(the board reads the registry), the shared player scene and shared Sound autoload.

### Done-definition for a mode

1. Every shift in `NightWatchModesData` starts from the board, plays and can be won and lost; the win saves `cleared_<mode>` and opens
   the next shift; the end cards use the shared wording.
2. Custom Night works when the mode has presets (sliders -> logic levels; score, best, star recorded by `record_win`).
3. The 2D numbers match: the validator replays the 2D tests (AI levels per night, timings, power/drain, win/loss conditions).
4. Deterministic by seed (`validate` runs the same seed twice and compares logs); Retry replays the same seed.
5. Shared controls and sounds only (no new player controller, no new sound system).
6. Suite `night_watch_<mode>` passes on KT-Mini4-2 (or AK-BEE headless) together with `night_watch`, `night_watch_menus`, `hub`.
7. Docs row updated, a capture at 1280x720 in `docs/night_watch_modes/`.

## Order and plan

1. **Classic complete** (this lane): Kathy's Night 7, the variety levers (`core/variety-stream.js`: per-night variation of hunter pacing),
   Custom Night start (sliders feed `NightWatchClassic` levels, already wired), save-and-continue.
2. **Custom Night** across modes: the menu page is done; each mode makes its sliders real as it lands.
3. **Mixed Shift** (+ Endless): Classic's building, a drawn roster, a pacing director. Reuses Classic's world, so it comes right after Classic.
4. **Dead Air** (vents, reboots, climate), **Bedtime** (no cameras, closet/hall/bed), **The Facility** (six rooms and tasks): independent
   rooms, one lane each.
5. **Masked Hours** (mask, music box, vents, flashlight), **Salvage Run** (budget and salvage), **The Descent** (elevator repair),
   **Open Air** (three outdoor watches): independent, one lane each.

Modes 4 and 5 do not share files with each other, so up to six lanes can run in parallel after the Classic pass, each in its own folder
and worktree. Everything runs on KT-Mini4-2 (or AK-BEE headless), never on the USB drive.
