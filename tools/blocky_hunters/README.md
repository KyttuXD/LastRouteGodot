# Blocky hunters (cube / Minecraft-skin style)

All 26 A-Z hunters as cube models built from KT's Minecraft (Alex) skins, on one shared rig (Hytale bone names).

    python3 tools/blocky_hunters/build.py all            # every hunter -> assets/hunters_blocky/<id>/
    python3 tools/blocky_hunters/build.py kathy --tall=5 # taller variant -> kathy_tall
    python3 tools/blocky_hunters/build_scythe.py         # Kathy's scythe -> assets/props_3d/kathy_scythe.glb
    python3 tools/blocky_hunters/check_gaps.py           # joint wedge gaps + seamless loops, every clip
    Godot --headless --path . res://scenes/validate.tscn -- blocky

Needs only Pillow + numpy. Layout: `bb_*.py` core, `hunters/<id>.py` per-hunter extras (hair, ears, horns, wings,
tails, halos), `hunters/motion.py` (personality motion profiles), `hunters/emotes.py` (shared + personal emotes).

## Holding a prop (Kathy's scythe)
Every hunter has `L-HandProp` / `R-HandProp` empties at the palm centre (children of the hand bones, following all
clips) and are tilted 25 degrees forward / 8 outward so a held shaft leans away from the arm. `assets/props_3d/kathy_scythe.glb` has its origin at the grip (`Grip` node), shaft along +Y, blade curving
forward (-Z), so with an identity transform under `R-HandProp` the blade points up and forward (the mount's tilt does the rest):

    var scythe := ModelSlot.instantiate("res://assets/props_3d/kathy_scythe.glb")
    hunter_model.find_child("R-HandProp", true, false).add_child(scythe)

Kathy's glb also has clips for carrying it: `scythe_idle` and `scythe_walk` (loops: right elbow bent about 90 degrees,
forearm forward, fist round an upright shaft) and `scythe_swing` (one-shot). Play these instead of idle/walk while
she carries it: with the plain idle (arm hanging) the shaft would lie along her arm and look like it is inside it.
