# Night Watch UI audit

`scripts/validate_night_watch_ui.gd` (suite `night_watch_ui`, checks in `scripts/night_watch_ui_audit.gd`) runs every Night Watch screen at 480x270, 1280x720, 1480x860, 1920x1080, 2560x1440 and the odd
aspects 1000x400, 800x800 and 540x960 (each rendered at the game's expand-stretch design size):

- screens: title, Shift Board for all nine modes, Custom Night for each mode, Account, Settings, Credits; the HUD (status, toast, Zellia's call, the camera screen with each map's minimap and the CLOSE CAMERAS strip,
  pause, night complete with and without NEXT, caught); the admin menu's tabs.
- per screen: nothing clipped by the window or a scroll area, no two text controls overlapping, font size floor (5 units, 5 px on screen), contrast 4.5:1 (3:1 for 14-unit and larger text) against the panel or the
  darkened menu scene behind the text, every enabled control reachable by Tab / arrows / d-pad with a focus ring (pointer-only buttons are listed in `NightWatchUiAudit.POINTER_ONLY`: each has a key), and the
  Night Watch theme behind every control (`NightWatchTheme`, never the project's Last Route theme).
- menus also: hovering any control selects nothing, Esc goes back, the cursor is free. Admin: Esc closes, the cursor is free while it is open.

`NW_UI_CAPTURE=<dir> godot --path . res://scenes/validate.tscn -- night_watch_ui` (not headless) writes every screen at 1480x860 and 1920x1080; the contact sheets here are made from those.

## What the audit found and what changed

- Sliders, check boxes, text fields and the admin menu's controls fell back to the project's purple Last Route theme (a purple volume slider, an invisible Calm check box, purple text fields): `NightWatchTheme` styles them in amber on black.
- The admin menu inside Night Watch was Last Route purple and teal: the shared `Palette` has a `night_watch` scheme now, applied when Night Watch opens, and `AdminMenu.apply_theme` takes the Night Watch theme.
- Text straight on the menu scene (key hints, title sub-lines, the Custom Night note, Account notes) was 1.5-3:1 over the lit office: the scene is dimmed 60% and that text is `BODY`; `DIM` is brighter (4.5:1 on the panels).
- The red logo / REC text was 3.5:1: `RED_TEXT` for text, `RED` for fills.
- Camera screen: the power / usage block, the clock and Pause ghosted through a 96% cover; the cover is opaque and they are drawn above it (the 2D HUD keeps power on the cameras), with the camera name centred and REC beside the clock.
- Lure, Masked Hours, Mixed and the monitor-less modes did not wire the Pause / CAMERAS / CLOSE CAMERAS buttons (see `NIGHT_WATCH_3D.md`, mouse capture): fixed earlier, covered by `night_watch_keys`.
- Menus now release the cursor on entry.

## Known limits

- Phone-portrait (540x960) draws the 5-6 unit text at 5.6-6.7 px: the same sizes as the 2D game's 480x270 canvas.
- The loading screens belong to the app (`boot_loading`), not Night Watch; entering a mode is a scene change with no screen of its own.
- The death jump-scare overlay (`DeathMoment`) is the shared one and is not part of this audit; the CAUGHT card after it is.
