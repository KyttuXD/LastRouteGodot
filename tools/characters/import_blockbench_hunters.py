#!/usr/bin/env python3
"""Import a reviewed Blockbench hunter roster into the Godot project.

Each source .bbmodel remains the editable source of truth. Its embedded PNG is
exported beside it for inspection/Godot import, and bbmodel_to_glb produces the
runtime scene with animation and without per-part collision bodies.

    python3 tools/characters/import_blockbench_hunters.py \
      "/path/to/conv_test/Hunters"
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import struct
import sys


HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
DEFAULT_OUT = os.path.join(ROOT, "assets", "characters")
sys.path.insert(0, os.path.join(HERE, os.pardir, "office"))

from bbmodel_to_glb import CROUCH_GROUND_LIFT, convert as export_glb  # noqa: E402
from character_floor_lifts import (  # noqa: E402
    HUNTER_ANIMATION_GROUND_LIFTS,
    PLAYER_ANIMATION_GROUND_LIFTS,
)
from refine_hunter_animations import refine_hunter_animations
from mc_to_hytale import repair_character_layers


EXPECTED = {
    "aki", "briselle", "ceryth", "dovelle", "elise", "ferryn", "glyra",
    "haelith", "ilyra", "javelle", "kathy", "loxelle", "mavrine", "nyxie",
    "opalie", "porcelle", "quenelle", "ravelle", "solyth", "thessine",
    "umbriel", "verrine", "wynelle", "xivvy", "ysolde", "zellia",
}
VOID_HUNTERS = {
    "void_black", "void_blue", "void_brown", "void_cyan", "void_gray",
    "void_green", "void_orange", "void_pink", "void_purple", "void_red",
    "void_white", "void_yellow",
}
CANONICAL_CLIPS = {"idle", "walk", "chase", "sprint", "crouch"}


def embedded_png(model: dict, source_path: str) -> bytes:
    textures = model.get("textures") or []
    source = str(textures[0].get("source", "")) if textures else ""
    if not source.startswith("data:image/png;base64,"):
        raise ValueError(f"{source_path}: first texture is not an embedded PNG")
    png = base64.b64decode(source.split(",", 1)[1])
    if png[:8] != b"\x89PNG\r\n\x1a\n" or len(png) < 24:
        raise ValueError(f"{source_path}: embedded texture has an invalid PNG header")
    return png


def write_runtime_model(model: dict, slug: str, outdir: str, source_path: str,
                        reverse_animation_facing: bool = False,
                        invert_animation_rotations: bool = False) -> dict:
    png = embedded_png(model, source_path)
    width, height = struct.unpack(">II", png[16:24])
    texture = model["textures"][0]
    texture["width"] = width
    texture["height"] = height
    texture["uv_width"] = width
    texture["uv_height"] = height
    bb_path = os.path.join(outdir, f"{slug}.bbmodel")
    png_path = os.path.join(outdir, f"{slug}_0.png")
    glb_path = os.path.join(outdir, f"{slug}.glb")
    with open(bb_path, "w", encoding="utf8") as destination:
        json.dump(model, destination, separators=(",", ":"))
    with open(png_path, "wb") as destination:
        destination.write(png)
    # The reviewed hunters were turned from south to north in Blockbench after
    # their motion was authored. Rotate those deltas into the new forward basis
    # without applying the old all-axis inverse. The player was never turned
    # and deliberately keeps the exporter default.
    info = export_glb(bb_path, glb_path, collision=False,
                      invert_animation_rotations=invert_animation_rotations,
                      reverse_animation_facing=reverse_animation_facing,
                      crouch_ground_lift=0.0 if reverse_animation_facing
                      else CROUCH_GROUND_LIFT,
                      animation_ground_lifts=HUNTER_ANIMATION_GROUND_LIFTS
                      if reverse_animation_facing
                      else PLAYER_ANIMATION_GROUND_LIFTS)
    return {"width": width, "height": height, **info}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_dir", help="directory containing the reviewed *.bbmodel files")
    parser.add_argument("--outdir", default=DEFAULT_OUT)
    parser.add_argument("--only", help="comma-separated model names, e.g. Aki,Kathy")
    parser.add_argument("--include-void", action="store_true",
                        help="also refine and re-export the committed Void hunter sources")
    parser.add_argument("--include-player", action="store_true",
                        help="also re-export the committed mannequin source with the fixed exporter")
    args = parser.parse_args()

    allowed = EXPECTED | VOID_HUNTERS
    requested = {value.strip().lower() for value in args.only.split(",")} \
        if args.only else EXPECTED | (VOID_HUNTERS if args.include_void else set())
    unknown = requested - allowed
    if unknown:
        raise SystemExit("unknown hunter name(s): " + ", ".join(sorted(unknown)))
    sources = {}
    for filename in os.listdir(args.source_dir):
        if filename.lower().endswith(".bbmodel"):
            sources[os.path.splitext(filename)[0].lower()] = os.path.join(args.source_dir, filename)
    missing = requested - set(sources)
    if missing:
        raise SystemExit("missing reviewed model(s): " + ", ".join(sorted(missing)))

    os.makedirs(args.outdir, exist_ok=True)
    for slug in sorted(requested):
        source_path = sources[slug]
        with open(source_path, encoding="utf8") as source_file:
            model = json.load(source_file)
        repair_character_layers(model)
        refine_hunter_animations(model)
        clip_names = {str(animation.get("name", "")) for animation in model.get("animations", [])}
        missing_clips = CANONICAL_CLIPS - clip_names
        if missing_clips:
            raise ValueError(f"{source_path}: missing canonical clips {sorted(missing_clips)}")
        info = write_runtime_model(model, slug, args.outdir, source_path,
                                   reverse_animation_facing=True)
        print(f"{slug:9s} {len(model.get('elements', [])):2d} elements  "
              f"{info['animations']:2d} clips  {info['width']}x{info['height']} PNG  {info['bytes']} B GLB")
    if args.include_player:
        player_path = os.path.join(args.outdir, "mannequin.bbmodel")
        with open(player_path, encoding="utf8") as source_file:
            player = json.load(source_file)
        repair_character_layers(player)
        missing_clips = CANONICAL_CLIPS - {str(animation.get("name", "")) for animation in player.get("animations", [])}
        if missing_clips:
            raise ValueError(f"{player_path}: missing canonical clips {sorted(missing_clips)}")
        info = write_runtime_model(player, "mannequin", args.outdir, player_path,
                                   invert_animation_rotations=True)
        print(f"{'player':9s} {len(player.get('elements', [])):2d} elements  "
              f"{info['animations']:2d} clips  {info['width']}x{info['height']} PNG  {info['bytes']} B GLB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
