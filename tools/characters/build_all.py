#!/usr/bin/env python3
"""
Builds every LastRoute hunter model from its source Minecraft skin.

One entry point for the whole roster: the shared pipeline in mc_to_hytale.py
handles the parts every character has (rig, UVs, hair split, skirt), and the
per-letter entries below add only the bespoke geometry a given character's
design doc calls for (ears, tails, halos, glyphs, wings, gills).

    python3 build_all.py [outdir] [--only A,B,K]
"""
import sys, os, argparse
import os as _os, sys as _sys
# The toolchain used to live in a scratch directory that was deleted.
# It lives here now; resolve siblings relative to this file, never a path.
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
_sys.path.insert(0, _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), _os.pardir, "office"))
from mc_to_hytale import convert, hunter_name_for, color_dist, HUNTER_NAMES
from special_characters import (
    add_square_halo, add_ear_pair, add_asymmetric_ear_pair, add_lower_back_tail,
    add_orbiting_stars, add_side_disc_glyph, add_back_wings, add_gill_plates,
    add_skirt,
)

SKINS_DIR = "/home/kyttu/Documents/Skins Yttu"
DEFAULT_OUT = "/home/kyttu/Documents/blockbench test/conv_test"

def _find_pixels(im, box, target, tol=24):
    """1x1 boxes for each pixel matching `target` -- used to erase scattered
    art (Nyxie's stars) that has become standalone geometry."""
    x0, y0, x1, y1 = box
    out = []
    for y in range(y0, y1):
        for x in range(x0, x1):
            p = im.getpixel((x, y))
            if p[3] > 10 and color_dist(p[:3], target) <= tol:
                out.append((x, y, x + 1, y + 1))
    return out

# --- per-character bespoke geometry (everything else is shared) -------------

def _mavrine(data, im, packer):   # plum floating square halo
    add_square_halo(data, im, packer, name="Halo", inner_gap=4)

def _porcelle(data, im, packer):  # dusty-rose square halo
    add_square_halo(data, im, packer, name="Halo", inner_gap=4)

def _ilyra(data, im, packer):     # feline ears + curled lower-back tail
    add_ear_pair(data, im, packer, (40, 5, 44, 8), (44, 5, 48, 8),
                 ear_size=(3.5, 6), spread_x=6, forward_z=-9)
    add_lower_back_tail(data, im, packer, (8, 0, 12, 4),
                        segments=5, base_y=48, curl=True, length=26, size=4.5)

def _haelith(data, im, packer):   # canine ears + tail
    add_ear_pair(data, im, packer, (8, 0, 10, 4), (10, 0, 12, 4),
                 ear_size=(3.5, 6.5), spread_x=6, forward_z=-9)
    add_lower_back_tail(data, im, packer, (12, 0, 16, 4),
                        segments=5, base_y=48, curl=True, length=26, size=4)

def _verrine(data, im, packer):   # ASYMMETRIC canine ears + bushy tail
    add_asymmetric_ear_pair(data, im, packer,
                            l_box=(8, 0, 10, 4), r_box=(10, 0, 12, 4),
                            l_size=(3.5, 8), r_size=(3.5, 5),
                            l_pos=(-5.25, 120, -9.25), r_pos=(5.25, 120, -8))
    add_lower_back_tail(data, im, packer, (12, 0, 16, 4),
                        segments=5, base_y=48, curl=True, length=30, size=6)

def _nyxie(data, im, packer):     # physical-left moon plate + 2 star drones
    add_side_disc_glyph(data, im, packer, glyph_box=(52, 9, 56, 15), side="west",
                        tex_name="MoonPlate", size=6, offset_z=-1)
    add_orbiting_stars(data, im, packer, star_box=(41, 9, 42, 10), count=2,
                       radius=18, base_y=126,
                       clear_boxes=_find_pixels(im, (32, 0, 64, 16), (255, 244, 191)))

def _solyth(data, im, packer):    # source-right sun glyph
    add_side_disc_glyph(data, im, packer, glyph_box=(32, 8, 40, 16), side="east",
                        tex_name="SunGlyph", size=8, offset_z=0)

def _wynelle(data, im, packer):   # two side pigtails + one rear ponytail
    from mc_to_hytale import rect_to_uv, add_free_cube, add_bone_group, find_element
    from special_characters import FLAT
    hair_box = (40, 0, 44, 3)
    packer.clear_source(hair_box)   # promoted to pigtail/ponytail objects
    off = packer.add(im.crop(hair_box))
    uv = rect_to_uv(off[0], off[1], off[0] + 4, off[1] + 3, "north")
    top_y = find_element(data, "Head")["to"][1]
    for name, (px, py, pz), w, h, axis in [
        ("L-Pigtail", (-15, top_y - 2, -2), 4, 9, "x"),
        ("R-Pigtail", (15, top_y - 2, -2), 4, 9, "x"),
        ("Rear-Ponytail", (0, top_y - 4, 13), 8, 19, "z"),
    ]:
        bone = f"{name}-Bone"
        add_bone_group(data, bone, origin=[px, py, pz], parent_group_name="Head")
        if axis == "x":
            frm, to = [px - FLAT / 2, py - h, pz - w / 2], [px + FLAT / 2, py, pz + w / 2]
            faces = {"east": uv, "west": uv}
        else:
            frm, to = [px - w / 2, py - h, pz - FLAT / 2], [px + w / 2, py, pz + FLAT / 2]
            faces = {"north": uv, "south": uv}
        add_free_cube(data, name, frm=frm, to=to, origin=[px, py, pz],
                      faces_uv=faces, tex_index=0, parent_group_name=bone,
                      double_sided=True)

def _xivvy(data, im, packer):     # back-mounted wings, upper+lower blades
    add_back_wings(data, im, packer, wing_box=(32, 36, 40, 48), span=20, height=22)

def _loxelle(data, im, packer):   # six axolotl gill plates
    add_gill_plates(data, im, packer, (0, 8, 2, 14), (6, 8, 8, 14), count_per_side=3)

def _opalie(data, im, packer):    # gills + articulated tail
    add_gill_plates(data, im, packer, (0, 8, 2, 14), (6, 8, 8, 14), count_per_side=3)
    add_lower_back_tail(data, im, packer, (4, 20, 8, 24),
                        segments=4, base_y=45, curl=True, length=20, size=4)

SPECIALS = {
    "H": _haelith, "I": _ilyra, "L": _loxelle, "M": _mavrine, "N": _nyxie,
    "O": _opalie, "P": _porcelle, "S": _solyth, "V": _verrine, "W": _wynelle,
    "X": _xivvy,
}

def build(letter, outdir, with_skirt=True):
    skin = os.path.join(SKINS_DIR, f"{letter}yttu.png")
    name = hunter_name_for(skin)
    special = SPECIALS.get(letter)

    def extra(data, im, packer):
        if special:
            special(data, im, packer)
        if with_skirt:
            add_skirt(data, im, packer)

    return convert(skin, os.path.join(outdir, f"{name}.bbmodel"), extra_fn=extra)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outdir", nargs="?", default=DEFAULT_OUT)
    ap.add_argument("--only", help="comma-separated letters, e.g. A,B,K")
    ap.add_argument("--no-skirt", action="store_true")
    args = ap.parse_args()
    os.makedirs(args.outdir, exist_ok=True)

    letters = [c.strip().upper() for c in args.only.split(",")] if args.only else sorted(HUNTER_NAMES)
    for L in letters:
        r = build(L, args.outdir, with_skirt=not args.no_skirt)
        tag = " +special" if L in SPECIALS else ""
        print(f"  {r['skin']:10s} elements={r['elements']:<3d}{tag}")

if __name__ == "__main__":
    main()
