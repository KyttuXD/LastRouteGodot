#!/usr/bin/env python3
"""
Strips hair off the TORSO of the source skins and repaints the garment
underneath, row by row.

Only the body's BASE layer is touched. Hair on the torso is art that the
converted models now carry as real hair objects, so leaving it painted on the
shirt duplicates it. The body OVERLAY layer is deliberately left alone --
that is where tails and wings live (Ilyra's S-curl, Xivvy's wing pair), and
they are not hair.

Originals are copied to a backup folder before anything is written.

    python3 clean_source_skins.py [--dry-run]
"""
import sys, os, shutil, argparse
import os as _os, sys as _sys
# The toolchain used to live in a scratch directory that was deleted.
# It lives here now; resolve siblings relative to this file, never a path.
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
_sys.path.insert(0, _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), _os.pardir, "office"))
from mc_to_hytale import (REGIONS, build_hair_palette, build_clothing_palette,
                          extract_hair_mask, patch_region_with_mask,
                          dominant_color, hunter_name_for)
from PIL import Image

SKINS_DIR = os.environ.get("SKINS_DIR", "./skins")
BACKUP_DIR = os.path.join(os.environ.get("SKINS_DIR", "./skins"), "_original_backup")
# SIDES only. The front and back faces keep their hair: those strands are
# part of the design, and the model pipeline already lifts them into real
# Front-Hair / Body-Hair objects at conversion time without altering the source.
TORSO_FACES = ("left", "right")

# Art that the converter promotes into standalone geometry, per source letter.
# It lives in OVERLAY regions, which are allowed to be transparent, so erasing
# it from the source is safe -- and required, or the piece shows up twice: once
# as the real object and once still painted on the skin.
#   value: (region, face, mode)   mode "all" = every opaque pixel,
#                                 mode "hair" = only character-coloured pixels
PROMOTED_ART = {
    "X": [("body_overlay", "back", "all")],                       # wings
    "I": [("body_overlay", "back", "hair")],                      # tail
    "H": [("body_overlay", "back", "hair")],
    "V": [("body_overlay", "back", "hair")],
    "O": [("body_overlay", "back", "hair"),                       # tail
          ("head_overlay", "left", "hair"),                       # gills
          ("head_overlay", "right", "hair")],
    "L": [("head_overlay", "left", "hair"),
          ("head_overlay", "right", "hair")],
}

def strip_promoted_art(path, letter, dry_run=False):
    """Erase from the source skin whatever the converter turns into its own
    object, so the art is not left duplicated on the skin behind it."""
    entries = PROMOTED_ART.get(letter)
    if not entries:
        return 0
    im = Image.open(path).convert("RGBA")
    hair = build_hair_palette(im)
    px = im.load()
    removed = 0
    for region, face, mode in entries:
        x, y, w, h = REGIONS[region][face]
        if mode == "all":
            for j in range(h):
                for i in range(w):
                    if px[x + i, y + j][3] > 10:
                        removed += 1
                        if not dry_run:
                            px[x + i, y + j] = (0, 0, 0, 0)
        else:
            if not hair:
                continue
            found, mask = extract_hair_mask(im, (x, y, x + w, y + h), hair,
                                            require_top_connection=False)
            if not found:
                continue
            mpx = mask.load()
            for j in range(h):
                for i in range(w):
                    if mpx[i, j][3] > 10:
                        removed += 1
                        if not dry_run:
                            px[x + i, y + j] = (0, 0, 0, 0)
    if removed and not dry_run:
        im.save(path)
    return removed

def strip_arm_overlays(path, dry_run=False):
    """Erase the sleeve/arm OVERLAY layer from the source skin.

    Unlike wings or tails, nothing is extracted from this layer -- it only
    produced a second shell cube around each arm segment -- so clearing it
    simply drops those shells. Overlay regions are allowed to be transparent,
    so the arms themselves are untouched."""
    im = Image.open(path).convert("RGBA")
    px = im.load()
    removed = 0
    for region in ("r_arm_overlay", "l_arm_overlay"):
        for _face, (x, y, w, h) in REGIONS[region].items():
            for j in range(h):
                for i in range(w):
                    if px[x + i, y + j][3] > 10:
                        removed += 1
                        if not dry_run:
                            px[x + i, y + j] = (0, 0, 0, 0)
    if removed and not dry_run:
        im.save(path)
    return removed

def clean(path, dry_run=False):
    im = Image.open(path).convert("RGBA")
    hair = build_hair_palette(im)
    if not hair:
        return 0
    clothing = build_clothing_palette(im, hair_palette=hair)
    removed = 0
    for face in TORSO_FACES:
        x, y, w, h = REGIONS["body_base"][face]
        box = (x, y, x + w, y + h)
        found, mask = extract_hair_mask(im, box, hair, clothing_palette=clothing)
        if not found:
            continue
        n = sum(1 for p in mask.getdata() if p[3] > 10)
        if not n:
            continue
        removed += n
        if not dry_run:
            fallback = dominant_color(im, box)
            patch_region_with_mask(im, box, mask, fallback, prefer_palette=clothing)
    if removed and not dry_run:
        im.save(path)
    return removed

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    skins = sorted(f for f in os.listdir(SKINS_DIR) if f.lower().endswith(".png"))
    if not args.dry_run:
        os.makedirs(BACKUP_DIR, exist_ok=True)
        for f in skins:
            dst = os.path.join(BACKUP_DIR, f)
            if not os.path.exists(dst):          # never overwrite an existing backup
                shutil.copy2(os.path.join(SKINS_DIR, f), dst)

    total = 0
    for f in skins:
        n = clean(os.path.join(SKINS_DIR, f), dry_run=args.dry_run)
        total += n
        print(f"  {hunter_name_for(f):10s} {n:3d} hair px {'would be' if args.dry_run else ''} removed from torso")
    print(f"\n{'(dry run) ' if args.dry_run else ''}total: {total} px across {len(skins)} skins")
    if not args.dry_run:
        print(f"originals backed up to {BACKUP_DIR}")

if __name__ == "__main__":
    main()
