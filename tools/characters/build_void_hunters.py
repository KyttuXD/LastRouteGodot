#!/usr/bin/env python3
"""Build the Void hunter set and the reserved KYTTU admin player skin.

The source directory contains standard 64x64 Minecraft skins.  The twelve
colour files become hunter-rig BBModels/GLBs at 1.22 display scale. Main.png
is deliberately excluded from that roster and becomes an admin player model
at the ordinary player scale.

    .venv/bin/python tools/characters/build_void_hunters.py \
        "/var/home/kyttu/Documents/Skins Void"
"""
from __future__ import annotations

import argparse
import base64
import glob
import json
import os
import sys


HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
OUT = os.path.join(ROOT, "art", "props-3d", "characters")
HYTALE = "/home/kyttu/Documents/HytaleAssets/Assets/Common"
VOID_COLOURS = (
    "black", "blue", "brown", "cyan", "gray", "green", "orange", "pink",
    "purple", "red", "white", "yellow",
)
CANONICAL = {"Idle": "idle", "Walk": "walk", "Run": "chase",
             "Sprint": "sprint", "Crouch": "crouch"}

sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, os.pardir, "office"))

from bbmodel_to_glb import convert as export_glb  # noqa: E402
from character_floor_lifts import (  # noqa: E402
    HUNTER_ANIMATION_GROUND_LIFTS,
    PLAYER_ANIMATION_GROUND_LIFTS,
)
from hytale_anim import attach_animations  # noqa: E402
from mc_to_hytale import convert as convert_skin  # noqa: E402
from refine_hunter_animations import refine_hunter_animations  # noqa: E402


def clip_sources() -> list[tuple[str, str]]:
    found = []
    for name in CANONICAL:
        hits = glob.glob(
            f"{HYTALE}/Characters/Animations/**/{name}.blockyanim",
            recursive=True,
        )
        if hits:
            found.append((name, hits[0]))
    missing = set(CANONICAL) - {name for name, _path in found}
    if missing:
        raise RuntimeError("missing Hytale clips: " + ", ".join(sorted(missing)))
    return found


def attach_gameplay_clips(model: dict, pairs: list[tuple[str, str]],
                          hunter: bool) -> None:
    by_path = {path: name for name, path in pairs}
    attach_animations(model, [path for _name, path in pairs],
                      rename=lambda name, path: by_path.get(path, name))
    for animation in model.get("animations", []):
        animation["name"] = CANONICAL.get(animation["name"], animation["name"])
    if hunter:
        refine_hunter_animations(model)


def write_scene(path: str, display_name: str, glb_name: str, scale: float,
                note: str) -> None:
    contents = f'''[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://art/props-3d/characters/{glb_name}.glb" id="1_model"]

; {note}
[node name="{display_name}" type="Node3D"]

[node name="Model" parent="." instance=ExtResource("1_model")]
scale = Vector3({scale:.2f}, {scale:.2f}, {scale:.2f})
'''
    with open(path, "w", encoding="utf8") as target:
        target.write(contents)


def build_one(skin: str, slug: str, hunter: bool,
              pairs: list[tuple[str, str]]) -> None:
    bbmodel = os.path.join(OUT, f"{slug}.bbmodel")
    glb = os.path.join(OUT, f"{slug}.glb")
    png = os.path.join(OUT, f"{slug}_0.png")
    result = convert_skin(skin, bbmodel, extra_fn=None)
    with open(bbmodel, encoding="utf8") as source:
        model = json.load(source)
    attach_gameplay_clips(model, pairs, hunter)
    with open(bbmodel, "w", encoding="utf8") as target:
        json.dump(model, target, separators=(",", ":"))
    # convert_skin packs hair swatches and Hytale-only neck/foot art beneath
    # the original 64x64 skin. Export that final atlas beside the BBModel; the
    # old source-skin copy left a 64x64 file next to a 64x96 BBModel/GLB and
    # made editor reimports sample the wrong rows even though the GLB embed was
    # correct.
    texture_source = str(model["textures"][0].get("source", ""))
    if not texture_source.startswith("data:image/png;base64,"):
        raise ValueError(f"{bbmodel}: generated texture is not an embedded PNG")
    with open(png, "wb") as target:
        target.write(base64.b64decode(texture_source.split(",", 1)[1]))
    info = export_glb(
        bbmodel,
        glb,
        collision=False,
        invert_animation_rotations=not hunter,
        reverse_animation_facing=hunter,
        crouch_ground_lift=0.0,
        animation_ground_lifts=(HUNTER_ANIMATION_GROUND_LIFTS if hunter
                                else PLAYER_ANIMATION_GROUND_LIFTS),
    )
    display_name = slug.removeprefix("void_").replace("_", " ").title()
    if hunter:
        display_name += " Void"
        note = ("Void hunter converted from the reviewed Minecraft skin. "
                "The extra scene scale keeps this category taller than A-Z hunters.")
        scale = 1.22
    else:
        display_name = "KYTTU Admin"
        note = ("Main.png is reserved for the authenticated KYTTU admin player; "
                "it is never part of the Void hunter draw.")
        scale = 0.90
    write_scene(os.path.join(OUT, f"{slug}.tscn"), display_name, slug, scale, note)
    print(f"{slug:18s} {result['elements']:2d} elements, "
          f"{info['animations']:2d} clips, {info['tris']:5d} tris")


def main() -> int:
    global OUT
    parser = argparse.ArgumentParser()
    parser.add_argument("source_dir")
    parser.add_argument("output_dir", nargs="?", default=OUT)
    parser.add_argument("--void-only", action="store_true",
                        help="rebuild the twelve Void hunters without touching the admin skin")
    args = parser.parse_args()
    OUT = os.path.abspath(args.output_dir)
    pairs = clip_sources()
    files = {os.path.splitext(name)[0].lower(): os.path.join(args.source_dir, name)
             for name in os.listdir(args.source_dir)
             if name.lower().endswith(".png")}
    required = set(VOID_COLOURS) | (set() if args.void_only else {"main"})
    missing = required - set(files)
    if missing:
        raise SystemExit("missing Void skin(s): " + ", ".join(sorted(missing)))
    os.makedirs(OUT, exist_ok=True)
    for colour in VOID_COLOURS:
        build_one(files[colour], f"void_{colour}", True, pairs)
    if not args.void_only:
        build_one(files["main"], "admin_kyttu", False, pairs)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
