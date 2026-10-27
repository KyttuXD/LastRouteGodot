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

## Hunter emotes
In-world personality moments (taunt, shrug, yawn, victory...) are decided by the host and replayed on every peer: see [HUNTER_EMOTES.md](HUNTER_EMOTES.md), which also lists the `emote_*` clips the rig should gain. Missing clips fall back to the face.

## Player body
The player mannequin is built by the same pipeline (`build.py player_mannequin`) and is wired as the default player body: see the Player model section of [../REF_LOOK.md](../REF_LOOK.md) and `docs/BLOCKY_ANIMATION.md`.

## Facing: body and head follow the path

`src/game_3d/hunter_facing.gd` (`HunterFacing`) holds the logic; `HunterView3D` applies it.

- **Body yaw** follows the way she actually travels (smoothed position delta, not the brain's stored `facing`), so it works on guests with no extra network data. Eased turn, capped at 420 deg/s walking and 600 deg/s chasing or sprinting. Standing still keeps the last heading (a standing chaser turns toward the runner). Teleports (> 3 m in a frame) are ignored.
- **Head look** is additive on the `Head` bone, on top of whatever the clip does with it (rest pose is the base when the clip has no Head track). Yaw clamp +-70 deg, pitch +-35 deg relative to the body, exponential damping.
  - wander / patrol: looks 2-4 m ahead along the A* route (`HunterBrain.path_look_ahead`), so the head leads corners before the body; without a route (guests, Xivvy flight, Loxelle charge) it uses the travel direction. Gentle sway on top; standing = slow left-right scan.
  - chase: locks on `look_target_position` (the runner while she has sight, otherwise last known); search / investigate: sweeps around the noise point.
  - stun, stun recovery, inactive, and emotes that play a clip: the layer fades out (4 /s) so the clip owns the head.
  - not evaluated beyond 40 m from the camera.
- Pitch is only a small nod: the view has no target height, so the head does not look up or down at the runner.
- Validator: `hunter_facing` (real `HunterView3D` walking a polyline with a deliberately wrong `brain.facing`). Captures: `facing_strip_before.png` (look layer off) and `facing_strip_after.png` from `tools/look/facing_strip.tscn` (`OLD=1` for the before).
- The spider creature view is not on this branch; it can reuse `HunterFacing` (`track`, `steer`, `update_head`).
