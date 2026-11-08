# Blocky hunters (cube / Minecraft-skin style)

All 26 A-Z hunters as cube models built from Minecraft (Alex) skins, on one shared rig (Hytale bone names).

    python3 tools/blocky_hunters/build.py all            # every hunter -> assets/hunters_blocky/<id>/
    python3 tools/blocky_hunters/build_scythe.py         # Kathy's scythe -> assets/props/hunter_items/kathy_scythe.glb
    python3 tools/blocky_hunters/check_gaps.py           # joint wedge gaps + seamless loops, every clip
    Godot --headless --path . res://tests/scenes/validate.tscn -- blocky

Needs only Pillow + numpy. Layout: `bb_*.py` core, `hunters/<id>.py` per-hunter extras (hair, ears, horns, wings,
tails, halos), `hunters/motion.py` (personality motion profiles), `hunters/emotes.py` (shared + personal emotes).

## Holding a prop (Kathy's scythe)
Every hunter has `L-HandProp` / `R-HandProp` empties at the palm centre (children of the hand bones, following all
clips) and carry no tilt: the lean comes from the wrist bend in the `scythe_*` clips (`WRIST` in `hunters/scythe_clips.py`), so the shaft leans ~40 degrees forward away from the arm. `assets/props/hunter_items/kathy_scythe.glb` has its origin at the grip (`Grip` node), shaft along +Y, blade curving
forward (-Z), so with an identity transform under `R-HandProp` the blade points up and forward (the wrist bend in the scythe clips does the rest):

    var scythe := ModelSlot.instantiate("res://assets/props/hunter_items/kathy_scythe.glb")
    hunter_model.find_child("R-HandProp", true, false).add_child(scythe)

Kathy's glb also has clips for carrying it: `scythe_idle` and `scythe_walk` (loops: right elbow bent about 90 degrees,
forearm forward, fist round an upright shaft) and `scythe_swing` (one-shot). Play these instead of idle/walk while
she carries it: with the plain idle (arm hanging) the shaft would lie along her arm and look like it is inside it.

## Stun, expressions, filmstrips
- `stun` (loop, 1.6 s: knees buckled, head lolling, arms limp, body swaying) and `stun_recover` (1 s one-shot wake-up) are authored in `bb_rig.py`; Kathy also has `scythe_stun` / `scythe_stun_recover` (hand keeps the shaft). `chase`/`sprint` lean in with bent, harder-pumping arms.
- `HunterView3D` plays the wake-up after a stun, shows faces from state (stun / blank while waking / chase / scream when the runner is within 2.6 cells / derp while searching / neutral + blinks) through `BlockyFace`, and circles three stars over a stunned head. Void models have eye-shape-only expressions (no mouth).
- `python3 tools/blocky_hunters/filmstrip.py OUT.png HUNTER CLIP[,CLIP] [frames] [view] [prop.glb:node]` renders a clip filmstrip.
