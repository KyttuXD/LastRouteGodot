"""Skin -> hunter model, end to end: geometry, clips, glTF.

The step this adds is the one that was never written down. `build_all.py`
emits a `.bbmodel` and stops; `hytale_anim.py` puts clips on a model; only
`bbmodel_to_glb.py` produces something Godot can open. Each hunter in
`art/props-3d/characters/` was made by running all three by hand, which meant
the recipe lived nowhere and the models could not be rebuilt without it.

    python3 tools/characters/build_hunters.py                # every roster hunter
    python3 tools/characters/build_hunters.py --only D,K,W   # just these letters

Needs Pillow (`mc_to_hytale` works on real pixels) and the Hytale asset library
for the clips; both are checked for before anything is written. The player
mannequin does NOT come through here -- see build_mannequin.py for why.
"""
import argparse
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, os.pardir, "office"))

HYTALE = "/home/kyttu/Documents/HytaleAssets/Assets/Common"
OUT = os.path.join(HERE, os.pardir, os.pardir, "art", "props-3d", "characters")
# Godot asks for these five by name and `AnimationPlayer.has_animation` is
# case-sensitive, so the Hytale names are renamed on the way in. The rest of
# the library rides along unrenamed -- it costs little and it is there if a
# cutscene ever wants it.
CANONICAL = {"Idle": "idle", "Walk": "walk", "Run": "chase",
             "Sprint": "sprint", "Crouch": "crouch"}


def clip_sources():
    """The .blockyanim files behind the five clips the game plays."""
    found = []
    for name in CANONICAL:
        hits = glob.glob("%s/Characters/Animations/**/%s.blockyanim" % (HYTALE, name),
                         recursive=True)
        if hits:
            found.append((name, hits[0]))
    return found


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="comma-separated roster letters, e.g. D,K,W")
    ap.add_argument("--outdir", default=OUT)
    args = ap.parse_args()

    try:
        import PIL  # noqa: F401
    except ImportError:
        print("needs Pillow: python3 -m venv .venv && .venv/bin/pip install Pillow")
        return 1

    from build_all import build, DEFAULT_OUT  # noqa: F401
    from mc_to_hytale import HUNTER_NAMES
    from hytale_anim import attach_animations
    from bbmodel_to_glb import convert as to_glb

    pairs = clip_sources()
    if not pairs:
        print("no .blockyanim files under %s -- clips would be missing" % HYTALE)
        return 1
    by_path = {path: name for name, path in pairs}

    letters = [s.strip().upper() for s in args.only.split(",")] if args.only \
        else sorted(HUNTER_NAMES)
    os.makedirs(args.outdir, exist_ok=True)
    for letter in letters:
        name = HUNTER_NAMES[letter]
        bb = os.path.join(args.outdir, "%s.bbmodel" % name.lower())
        result = build(letter, args.outdir)
        # build() names its output after the character; move it to the lowercase
        # name the game loads by.
        made = os.path.join(args.outdir, "%s.bbmodel" % name)
        if made != bb and os.path.exists(made):
            os.replace(made, bb)

        model = json.load(open(bb))
        attached, _skipped = attach_animations(
            model, [p for _n, p in pairs],
            rename=lambda n, p: by_path.get(p, n))
        for anim in model.get("animations", []):
            anim["name"] = CANONICAL.get(anim["name"], anim["name"])
        json.dump(model, open(bb, "w"))

        glb = os.path.join(args.outdir, "%s.glb" % name.lower())
        info = to_glb(bb, glb, collision=False)
        print("  %-9s %d elements -> %d meshes, %d tris, %d clips"
              % (name, result.get("elements", len(model["elements"])),
                 info["meshes"], info["tris"], info["animations"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
