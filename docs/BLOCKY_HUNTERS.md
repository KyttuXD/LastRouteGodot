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

## Face swaps and foot slip (expr-lane)

- **Face swaps write only to the Face quad's own material.** `ModelSlot.share_blocky_materials` gives every mesh of a hunter (Belly, Chest, Head, legs, accessories and the Face quad) the SAME shared override material. `BlockyFace.set_expression` used to reuse an existing override, so the expression's `uv1_offset` landed on that shared material and shifted the UVs of the whole body on every chase / scream / search / stun face (garbled torso and legs, bits of hair and eyes on the legs). `BlockyFace.own_material` now always makes a private copy for the quad (remembered in meta, remade if a fade replaces it) and `HunterView3D` re-applies the face if that happens. The scream face also latches (leaves at 1.4x the enter distance) and a face holds for 0.45 s, so a runner at the edge of the range cannot flicker it. Suite `face_transitions` flips every hunter on live views through idle, chase, scream, search, stun, wake and idle and checks the quad's cell, that its material is unique, and that no other material changed. `docs/glyra_face_before_after.png`: top row before, bottom row after.
- **Travel clips play at the real ground speed.** `assets/hunters_blocky/stride_table.json` (and `assets/city/creature_stride_table.json`) hold, per model and clip, the planted-foot reference speed measured by forward kinematics (`tools/look/stride_table.tscn`, `HunterStride.measure`; regenerate after any clip change, `foot_slip` fails on a stale table). `HunterView3D` plays walk / chase / sprint at `speed_scale = ground speed / reference speed` (clamped, with a swap to the neighbouring clip when the pace is far out of range), keeps the stride phase on a swap, blends 0.15 s, and uses a hysteresis between idle and walk (enter above 0.35 m/s, leave after 0.35 s below 0.15). The two spider clips measure as moonwalking (planted legs travel forward), so their table entry is `reverse` and they play backwards at the right speed. Suite `foot_slip`.

## Xivvy's flying chase

`XivvyFlight` (`src/game_3d/xivvy_flight.gd`) turns the old 0.48 m hover into a readable flying chase. The simulation is unchanged (2D nav plane, `XivvyGimmick.flying` after the take-off delay, replicated in the gimmick's network state); everything below is presentation, derived on every peer from that flag, the motion and the look target, so guests see the same lift, bank and swoop with no extra traffic.

- **Clearance-driven mode and altitude.** Every 0.1 s (host side, while chasing or airborne) she surveys the route ahead (0 to 12 m along the A* path, straight ahead when there is no route): a ray up for the ceiling and two chest-height rays to the sides. She **flies** only where the lowest ceiling ahead is at least 3.6 m (stays up above 3.2 m: hysteresis) and no doorway-sized gap (walls within 1 m on both sides) is on the way; otherwise she **lands at once and walks** (the normal stride-table chase/sprint clip) and lifts off again only after the way has been clear for 0.45 s. Cruise altitude scales with the headroom: `headroom - 1.78 (body) - 0.14`, capped at 5.5 m (a 4 m hall: about 2.1 m, a 4.5 m hall: 2.6 m, open ground or a 9 m atrium: 5.5 m); close to the runner she dips (swoop, nose down) to 0.3 m for the grab. Real heights in the game: route halls 3.0 m (non-streamed) so she walks them, 4.0 m in streamed levels, City ceilings 4.0 m with 3.0 m doors, 11 m rims, 7 m gates. Take-off and landing are eased climbs and settles; her wings fold while she comes down and open again on her feet.
- **Replication:** the host's view writes the mode and cruise altitude into the gimmick (`fly_ok`, `altitude_hint`, in `network_state`); a guest follows them for as long as packets arrive (`replicated_recently`) and otherwise measures the route itself.
- **Bank and pitch** on the model root (not the collider): banks into turns (up to 38 deg), noses down when diving. The flight clip's speed follows her ground speed (0.85x-2.3x) and the wing beats (`Sound.xivvy_wing`) follow the same cadence; take-off and closing in play `Sound.xivvy_screech`.
- **Shadow**: a dark disc on the floor under her, smaller and fainter the higher she is.
- The body really leaves the floor now: the hunter body's floor snap (0.32 m) used to pull her straight back down every physics step, so the old "flight" only existed in the clip. Snap is off while she is airborne.
- Head-follows-path (straight travel direction in flight), per-instance face material and the rest of the identity are untouched. The death/jumpscare line is a UI moment (`DeathMoment`, no 3D framing), so a catch while airborne needs no extra framing: the grab is the swoop ending at 0.3 m.
- Checks: suite `xivvy_flight` (a real hall / 3 m doorway / room / 9 m atrium run with colliders: altitude within [floor, ceiling - margin] everywhere, grounded and walking at the door, landed before it, up again beyond, no flapping, wings fold, take-off/landing smooth and end on the floor, swoop dip, bank direction and limit, wing cadence rising with speed, shadow on the floor, cues counted, a guest rebuilt from the replicated flag lifts and banks, other hunters unaffected). Captures: `docs/xivvy_side.png`, `docs/xivvy_chase.png` (chase-cam), the hall-to-atrium side sequence, from `tools/look/xivvy_flight_capture.tscn`.
- Night Watch: `NightWatchPoses` is unchanged; if she appears there, play her normal `flight` clip (the NW lane can set `hunter_view` flight through the gimmick the same way).

## Standing still (idle_stability)

KT: idling hunters wobbled. Three causes, found by logging a standing hunter frame by frame:

1. **The head look swept +-42 deg** while she stood (the "slow left-right scan" of HUNTER HEADS, plus a nod and a sway while walking), a big slow head swing on top of the idle clip. A standing head is now a +-9 deg turn with a 14 s period (nod 2 deg; the walking path sway 5 deg; the search sweep 14 deg).
2. **Spawn speed spike**: the first speed sample measured the jump from the zero default position to the real one (hundreds of m/s), so every hunter "walked in place" for about a second after appearing (and after any teleport: stairs, spawn, a streamed floor). The first sample and any jump over 4 m now count as zero speed.
3. **Sub-centimetre position noise** (network rounding, interpolation) went to `move_and_slide`, which crept within its 3.5 cm safe margin and bobbed the body up and down (a guest with 2 mm of noise drifted 2.7 cm). Corrections under 6 mm are applied directly.

Suite `idle_stability`: four hunters x idle / wander / chase / search for 5 s, every other hunter at a waypoint for 2 s, and a guest with replicated position noise. Root drift under 2 cm, yaw under 2 deg, no animation / gait / expression flips, every part inside the idle clip's own range (+3 cm), head swing within the clip's own plus +-9 deg. `docs/idle_stability_plot.png`: head yaw while standing, before (top-left idle, bottom-left wander; red = a clip change) and after.
