"""Builds the shared player mannequin from a Minecraft skin.

Everyone wears the same figure: this is a body, not a character, so it is one
model rather than one per player.

    python3 tools/characters/build_mannequin.py \
        tools/characters/mannequin_skin.png \
        art/props-3d/characters/mannequin.bbmodel \
        art/props-3d/characters/mannequin.glb

Everything it needs is in this repository. An earlier version of this script
imported its converter from a scratch directory, which was later deleted --
taking the only way to rebuild any of the character models with it. Nothing
here reaches outside `tools/`.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, os.pardir, "office"))

import mc_skin                                    # noqa: E402
import mannequin_anim                             # noqa: E402
from bbmodel_to_glb import convert as to_glb      # noqa: E402


def main(skin, out_bb, out_glb):
    model = mc_skin.build(skin, name=os.path.splitext(os.path.basename(out_bb))[0])
    clips = mannequin_anim.attach(model)
    json.dump(model, open(out_bb, "w"))

    # collision=False: a character's only collider is the CharacterBody3D's own
    # CollisionShape3D. Exporting one "-colonly" mesh per box is what dropped
    # the first mannequin through the floor.
    info = to_glb(out_bb, out_glb, collision=False)
    print("  %d boxes, %d bones  ->  %d meshes, %d tris, %d anims"
          % (len(model["elements"]), len(model["outliner"]),
             info["meshes"], info["tris"], info["animations"]))
    print("  clips:", ", ".join(sorted(clips)))


if __name__ == "__main__":
    main(*sys.argv[1:4])
