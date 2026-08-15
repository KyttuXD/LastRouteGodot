"""Builds the shared player mannequin from a Minecraft skin.

Everyone is the same figure: this is the body every player wears, not a
character, so it goes through the hunter pipeline with the per-character extras
switched OFF -- no skirt, no ears, no glyphs -- and WITHOUT skin-tone
normalisation, which exists to pull a roster face onto the shared palette and
would drag a wooden mannequin toward flesh.
"""
import sys, os, glob, json
sys.path.insert(0, "/tmp/claude-1000/-home-kyttu-Documents-blockbench-test/1ca1681a-887e-4993-bce5-2141bc9d5618/scratchpad")
from mc_to_hytale import convert
from hytale_anim import attach_animations
from bbmodel_to_glb import convert as to_glb

HYTALE = "/home/kyttu/Documents/HytaleAssets/Assets/Common"
# Godot asks for these by name and AnimationPlayer.has_animation is
# case-sensitive, so the Hytale clip names are renamed on the way in.
CANONICAL = {"Idle": "idle", "Walk": "walk", "Run": "chase",
             "Sprint": "sprint", "Crouch": "crouch"}

skin, out_bb, out_glb = sys.argv[1], sys.argv[2], sys.argv[3]
result = convert(skin, out_bb, extra_fn=None, normalize_skin=False)

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

# collision=False: see above -- the player's own CollisionShape3D is the
# only collider a character should have.
info = to_glb(out_bb, out_glb, collision=False)
print("  elements %d  animations %d  ->  %d meshes, %d tris, %d anims"
      % (result["elements"], len(attached), info["meshes"], info["tris"],
         info["animations"]))
print("  clips:", ", ".join(sorted(a["name"] for a in model.get("animations", []))))
