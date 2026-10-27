# Blocky hunters (default presentation)

All 26 A-Z hunters and the 12 Void hunters are Minecraft-style cube models. This is the default: billboard sprites and the older rigged models are fallbacks only.

## Toggles (`src/config/hunter_roster.gd`)
- `USE_BLOCKY := true` uses `assets/hunters_blocky/<id>/<id>.glb`; false falls back to the older models in `art/props-3d/characters/`.
- `USE_SPRITES := false`; true shows the flat cutout billboards (only when `USE_BLOCKY` is off).
- `SCYTHE_CARRY_CHANCE := 1/8`: Kathy (and Umbriel disguised as her) carries the scythe on a seeded roll, identical on every peer.
- `HunterJumpscare.ENABLED := false`: a catch goes straight to the death/spectator flow, no lunge or sting.

## Pipeline (`tools/blocky_hunters/`, Python with Pillow + numpy)

    python3 tools/blocky_hunters/build.py all          # -> assets/hunters_blocky/<id>/ (glb, atlas, bbmodel)
    python3 tools/blocky_hunters/build.py void
    python3 tools/blocky_hunters/build_scythe.py       # -> assets/props_3d/kathy_scythe.glb
    python3 tools/blocky_hunters/check_gaps.py         # joint gaps and loop seams, every clip

`hunters/<id>.py` holds per-hunter extras (hair, ears, horns, wings, tails, halos). Accessory colours are derived from the skin/hair
pixels where possible (Elise's ears follow her hair colour). Skins are in `tools/blocky_hunters/skins/`. Details: `tools/blocky_hunters/README.md`.

## Clips
`idle, walk, chase, sprint, stun, stun_recover, emotes` plus Kathy's `scythe_idle, scythe_walk, scythe_swing, scythe_stun, scythe_stun_recover`.
`HunterView3D` plays sprint while the runner is in direct sight, the wake-up after a stun, flight (Xivvy) and charge (Loxelle).

## Faces and stun feedback
`BlockyFace` shows expressions from state (neutral and blinks, chase, scream when the runner is within 2.6 cells, derp while searching, stun, blank while waking).
A stunned hunter has three stars circling its head. Void models only change eye shape (no mouth). The old glowing eye quads were removed.

## Checks
`Godot --headless --path . res://scenes/validate.tscn -- blocky`, `tools/look/hunter_check.tscn`, `tools/blocky_hunters/filmstrip.py OUT.png HUNTER CLIP`.
