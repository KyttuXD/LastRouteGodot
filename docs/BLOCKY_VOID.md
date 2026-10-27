# Blocky Void hunters (initialisation pass)

12 cube-style Void hunters on the shared blocky rig (same bones and clips as the A-Z blocky hunters).

    python3 tools/blocky_hunters/build.py void          # -> assets/hunters_blocky/void_<colour>/
    python3 tools/blocky_hunters/check_gaps.py          # joint gaps + loops, now covers Void
    Godot --headless --path . res://scenes/validate.tscn -- blocky

Contact sheet: [void_contact_sheet.png](void_contact_sheet.png) (three-quarter and back views, 6 per row pair).

## Source of truth
- Base look: the audited skins in LastRoute-Archives/audits/voids-2026-09-09 (copied to `tools/blocky_hunters/skins/void_<colour>_source.png`).
  Lore there: humanoid cat figure, giant eyes, **no snout/nose/mouth**, plain solid body, no accessories, no powers stated.
- Gimmicks: `src/config/void_hunter_gimmicks/void_hunter_gimmick_chart.gd`. Palette: the skin's torso and eye-frame colours.
- Size: `VOID_HEIGHT = 2.0` m in `hunters/void_set.py` (roster calls Void presentation "larger"; one constant to tune).

## Cues (one per colour, cubes only, bones named `Cue-*`; named after each colour's ability in the dossier)
black motes drifting at the shoulders (Rear Stalker) | blue icicle crown + 3-segment ice trail (Silent Stalker) | brown board across the back, plank shoulder guards (Spot Jammer) | cyan twin antennae + battery pack (Signal Ping) | gray closed second face plate on the back of the head (Signal Route) | green spore sacs + floating spores (Vent Relocate) | orange swept crest + rear vents (System Saboteur) | pink anglerfish-style lure bulb (False Signal) | purple fading afterimage slabs (Radar Corrupter) | red dorsal spines, shoulder spikes, forearm blades (Hall Runner) | white oversized ears (Light Frozen) | yellow stepped bolt crest + fuse box (Map Pressure).

## Eyes and faces
- **Emissive eyes:** each model carries a second texture, `void_<colour>_emissive.png`, written into the glb as `emissiveTexture`. Only the giant eyes' inner pixels (the skin's `inner_face_accent`) are lit, in every expression cell. Dark accents (black, gray, brown) glow as a lifted, hue-true colour (black = cool grey). Nothing else is emissive.
- **Expressions:** since the animation rework the Void models change eye shape only (no mouth) with state; earlier note:  a Void only has glowing eyes and a blink. The source face is split across the head box and its overlay, so the model flattens it onto the head box (overlay face dropped); the expression cells are then the neutral face, with cell 1 (`blink`) as the only change. Any other expression name just shows the neutral glowing eyes. No mouth, nose or snout is ever drawn.

## Emotes
Void do not wave or cheer. All 12 share `stare`, `tilt`, `twitch`, `loom` and each has one of its own: black devour, blue shiver, brown smash, cyan zap, gray freeze, green exhale, orange rev, pink beckon, purple flicker, red rage, white listen, yellow flick. They are body-only one-shot clips on the same rig (face stays neutral), listed in `emotes.json`.

## Placeholder vs final
- **Final-ish:** skins/face markings (exact supplied pixels), palette, rig, clips, expression cells, emissive eyes, height budget.
- **Placeholder:** every cue, and the Void emotes and motion profiles (first pass, tune by eye). The lore audit says the variants carry no accessories and "colour filenames do not establish lore or abilities"; the cues are design proposals tied to the roster's gimmick chart and need KT's sign-off (or removal).
- **Not done:** `Main` Void (flowers) not built (not in roster); no cue-specific glow (lure, antenna tips are not emissive, eyes only).
- **Wiring:** done. `HunterRoster.USE_BLOCKY` points the roster at `assets/hunters_blocky/void_<colour>/`; see [BLOCKY_HUNTERS.md](BLOCKY_HUNTERS.md).
