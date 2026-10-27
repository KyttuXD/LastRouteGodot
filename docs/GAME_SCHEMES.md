# Per-game colour schemes

Last Route and KYTTU: The City share their menus (settings, pause, account, room lobby, results/death, loading, admin, toasts,
HUD frames) but each dresses them in its own scheme.

- **Source of truth**: `Palette` (`src/config/palette.gd`). Its colour tokens (`INK`, `PANEL`, `ACCENT`, `AMBER`, `TEAL`, ...) plus
  `CORNER`, `EDGE_WIDTH` and `LABEL_TRACKING` are static variables; `Palette.SCHEMES` holds each game's overrides. Last Route's
  values are the defaults (purple/magenta route identity, square chunky frames); the City is night-city navy ink, neon amber primary
  actions, ice-cyan readouts and softly rounded glass-like panels.
- **Switching**: `GameRegistry.active_game_id = id` calls `Palette.apply_scheme(id)`. The hub resets it to Last Route, launching a
  game sets that game's id. `Palette.apply_scheme` also puts the game's Theme (`Palette.theme_for`: the game's theme resource plus a
  generated layer for sliders, tabs, checkboxes, progress and scroll bars) on the root window, so scenes without their own theme
  follow. Last Route and Night Watch keep the project theme (Night Watch dresses its own menus).
- **Rule for screens**: read colours from `Palette` when the screen is built (never literals). Scene files with literal colours
  (`main_menu.tscn`, `hud.tscn`) are Last Route's; the HUD repaints its shared panel frame from the scheme (`HUD._apply_scheme_frames`).
- **Adding a game scheme**: add an entry to `Palette.SCHEMES` and give the game a `theme` in `GameRegistry`.

## Tests and captures

`scheme_styles` opens the settings overlay, pause menu, account panel, room lobby, results screen and HUD under each scheme and checks
the tokens differ, every text/ground pair keeps its contrast, each screen draws the active game's colours (not the other's) and
Last Route's palette returns exactly. `button_contrast` runs every button state of the shared screens under both schemes (4.5:1).
`layout`, `hud_overlap` and `admin_layout` are unchanged.

Side by side (left Last Route, right the City; `tools/look/scheme_capture.tscn`, run on the Mac mini):

| Screen | Capture |
| --- | --- |
| Settings | `scheme_settings_side_by_side.png` |
| Pause | `scheme_pause_side_by_side.png` |
| Account | `scheme_account_side_by_side.png` |
| Room lobby | `scheme_lobby_side_by_side.png` |
| Results / death | `scheme_results_side_by_side.png` |
| HUD | `scheme_hud_side_by_side.png` |
