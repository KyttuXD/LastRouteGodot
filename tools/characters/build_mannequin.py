"""Builds the shared player mannequin from a Minecraft skin.

Everyone wears the same figure: this is a body, not a character, so it is one
model rather than one per player. Goes through the SAME pipeline the hunters
do (mc_to_hytale -> hytale_anim -> bbmodel_to_glb) so a player and a hunter
are built the same way, on the same rig, needing one converter instead of two.

    python3 -m venv .venv && .venv/bin/pip install Pillow   # first time only
    .venv/bin/python tools/characters/build_mannequin.py \
        tools/characters/mannequin_skin.png \
        art/props-3d/characters/mannequin.bbmodel \
        art/props-3d/characters/mannequin.glb

The mannequin does NOT call normalize_skin_tone(): that exists to pull a
roster face onto the shared flesh tone, and would drag a wooden mannequin
toward it. mc_to_hytale.convert() never calls it either unless the caller
does, so this is simply omitting an opt-in step, not disabling one.

Not what this script used to do. It went through mc_skin.py -- a from-scratch
six-box exporter, deliberately NOT this rig -- because the first attempt
through this same pipeline came out with the head, arms and legs standing
apart with daylight between them: a 64x64 skin has exactly six UV islands,
and mapping it onto this rig's ~21 parts left most of them sampling whatever
happened to lie under their coordinates. That was a real bug in the shared
converter at the time (a corrupted bone name from a botched recovery -- see
mc_to_hytale.py's fix_bone_spelling()), not a structural problem with the rig
itself, and it is fixed now: rebuilding the mannequin through this pipeline
today comes out as one cohesive figure (verified with the same cohesion check
scripts/validate_body.gd runs against every hunter model). mc_skin.py and
mannequin_anim.py are left in tools/characters/ rather than deleted -- a
smaller, dependency-free alternative is still a real option if this rig ever
regresses again -- but nothing calls them by default any more.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, os.pardir, "office"))

from mc_to_hytale import convert          # noqa: E402
from hytale_anim import attach_animations  # noqa: E402
from bbmodel_to_glb import convert as to_glb  # noqa: E402
from character_floor_lifts import PLAYER_ANIMATION_GROUND_LIFTS  # noqa: E402

HYTALE = "/home/kyttu/Documents/HytaleAssets/Assets/Common"
# Godot asks for these by name and AnimationPlayer.has_animation is
# case-sensitive, so the Hytale clip names are renamed on the way in --
# identical to build_hunters.py's own CANONICAL map.
CANONICAL = {"Idle": "idle", "Walk": "walk", "Run": "chase",
             "Sprint": "sprint", "Crouch": "crouch"}


def main(skin, out_bb, out_glb):
    import glob
    result = convert(skin, out_bb, extra_fn=None)

    pairs = []
    for name in CANONICAL:
        hits = glob.glob("%s/Characters/Animations/**/%s.blockyanim" % (HYTALE, name),
                         recursive=True)
        if hits:
            pairs.append((name, hits[0]))
    model = json.load(open(out_bb))
    by_path = {p: n for n, p in pairs}
    attached, _skipped = attach_animations(model, [p for _n, p in pairs],
                                           rename=lambda n, p: by_path.get(p, n))
    for anim in model.get("animations", []):
        anim["name"] = CANONICAL.get(anim["name"], anim["name"])
    json.dump(model, open(out_bb, "w"))

    # collision=False: the player's own CollisionShape3D is the only collider
    # a character should carry. A "-colonly" mesh per element is what dropped
    # the very first mannequin export through the floor.
    # The Hytale source rig expresses limb deltas in the inverse local-bone
    # convention from glTF. Conjugating every animation delta makes elbows,
    # knees, walk, sprint, and idle all bend in their intended direction.
    info = to_glb(out_bb, out_glb, collision=False,
                  invert_animation_rotations=True,
                  animation_ground_lifts=PLAYER_ANIMATION_GROUND_LIFTS)
    print("  %d elements  ->  %d meshes, %d tris, %d anims"
          % (result["elements"], info["meshes"], info["tris"], info["animations"]))
    print("  clips:", ", ".join(sorted(a["name"] for a in model.get("animations", []))))


if __name__ == "__main__":
    main(*sys.argv[1:4])
