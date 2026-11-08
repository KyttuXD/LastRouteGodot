#!/usr/bin/env python3
"""
Converts a 64x64 Minecraft skin (base + overlay layers) into a Hytale
character .bbmodel, built on the "Player" rig template.

Design rules (derived and verified against the live template + a reference
render, see conversation history for how each was established):

  - Front = north (-Z), right = east (+X). Verified from the template's own
    eyelid placement and independently from compass math. Minecraft skin
    regions are already defined in the character's own frame, so no mirroring
    is needed once the L-/R- naming bug in the raw template is corrected.
  - The raw template on disk has a naming bug: most L-/R- paired bones sit on
    the wrong side (a leftover from a manual Z-flip the rig previously went
    through). Eyelid/Eyelid-Bot bones were NOT affected. This is fixed here,
    in memory, every run -- the on-disk template is never modified.
  - Flat surface art (shirt patterns, belts, pants, socks, hair painted into
    the base layer) is reproduced purely through correct box-UV texturing of
    the existing rig cubes. No invented/placeholder geometry is added for it.
  - Any real overlay-layer content (hat/hair fringe, jacket, sleeves, pants)
    becomes a genuine second shell cube for that body part, sized to the
    same box, textured from the overlay UV region, and inflated outward --
    exactly how vanilla Minecraft's own hat layer works. Only added where the
    overlay region actually has opaque pixels, keeping node count down.
  - Arms are always resized to slim (Alex-style) proportions, regardless of
    whether the source skin's pixel data happens to fill the wide 4px column
    (this is a standing style rule for this project, not a per-skin
    detection -- the same 64x64 texture data still maps correctly, just
    slightly compressed onto the narrower geometry).

Usage:
    python3 mc_to_hytale.py <skin.png> <output.bbmodel> [--template PATH]
    python3 mc_to_hytale.py --batch <skins_dir> <output_dir> [--template PATH]
"""
import json, sys, os, argparse
from PIL import Image

DEFAULT_TEMPLATE = os.environ.get("TEMPLATE_BBMODEL", "./test-base.bbmodel")

# Official LastRoute hunter names per source letter (from char-design/ROSTER.md).
# Models and their textures are named for the character, never the Xyttu tag.
HUNTER_NAMES = {
    "A": "Aki", "B": "Briselle", "C": "Ceryth", "D": "Dovelle", "E": "Elise",
    "F": "Ferryn", "G": "Glyra", "H": "Haelith", "I": "Ilyra", "J": "Javelle",
    "K": "Kathy", "L": "Loxelle", "M": "Mavrine", "N": "Nyxie", "O": "Opalie",
    "P": "Porcelle", "Q": "Quenelle", "R": "Ravelle", "S": "Solyth",
    "T": "Thessine", "U": "Umbriel", "V": "Verrine", "W": "Wynelle",
    "X": "Xivvy", "Y": "Ysolde", "Z": "Zellia",
}

SKIN_TONE = (255, 233, 219)   # #ffe9db -- the roster's shared skin tone

def normalize_skin_tone(im, target=SKIN_TONE):
    """Force the character's skin onto the roster's shared tone.

    Only the exact colour found on the face is remapped, never anything
    merely *near* it: pale socks, shoes and shirts sit within a small colour
    distance of skin, so a tolerance-based sweep would repaint garments too.
    Returns True if anything changed (it is a no-op for skins already on
    tone, which today is every character except Briselle)."""
    fx, fy, fw, fh = REGIONS["head_base"]["front"]
    face_tone = dominant_color(im, (fx + 2, fy + 5, fx + fw - 2, fy + fh))
    if face_tone == target:
        return False
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a > 10 and (r, g, b) == face_tone:
                px[x, y] = (target[0], target[1], target[2], a)
    return True

def hunter_name_for(skin_path):
    """Maps 'Kyttu.png' -> 'Kathy'. Falls back to the bare stem if the file
    doesn't follow the <Letter>yttu naming scheme."""
    stem = os.path.splitext(os.path.basename(skin_path))[0]
    if len(stem) >= 1 and stem[1:].lower() == "yttu":
        return HUNTER_NAMES.get(stem[0].upper(), stem)
    return stem

# ---------------------------------------------------------------------------
# Standard Minecraft 64x64 skin UV regions: (x, y, w, h) per face.
# ---------------------------------------------------------------------------
REGIONS = {
    "head_base": {"top": (8,0,8,8), "bottom": (16,0,8,8), "right": (0,8,8,8),
                  "front": (8,8,8,8), "left": (16,8,8,8), "back": (24,8,8,8)},
    "head_overlay": {"top": (40,0,8,8), "bottom": (48,0,8,8), "right": (32,8,8,8),
                      "front": (40,8,8,8), "left": (48,8,8,8), "back": (56,8,8,8)},
    "body_base": {"top": (20,16,8,4), "bottom": (28,16,8,4), "right": (16,20,4,12),
                  "front": (20,20,8,12), "left": (28,20,4,12), "back": (32,20,8,12)},
    "body_overlay": {"top": (20,32,8,4), "bottom": (28,32,8,4), "right": (16,36,4,12),
                      "front": (20,36,8,12), "left": (28,36,4,12), "back": (32,36,8,12)},
    "r_arm_base": {"top": (44,16,4,4), "bottom": (48,16,4,4), "right": (40,20,4,12),
                   "front": (44,20,4,12), "left": (48,20,4,12), "back": (52,20,4,12)},
    "r_arm_overlay": {"top": (44,32,4,4), "bottom": (48,32,4,4), "right": (40,36,4,12),
                       "front": (44,36,4,12), "left": (48,36,4,12), "back": (52,36,4,12)},
    "l_arm_base": {"top": (36,48,4,4), "bottom": (40,48,4,4), "right": (32,52,4,12),
                   "front": (36,52,4,12), "left": (40,52,4,12), "back": (44,52,4,12)},
    "l_arm_overlay": {"top": (52,48,4,4), "bottom": (56,48,4,4), "right": (48,52,4,12),
                       "front": (52,52,4,12), "left": (56,52,4,12), "back": (60,52,4,12)},
    "r_leg_base": {"top": (4,16,4,4), "bottom": (8,16,4,4), "right": (0,20,4,12),
                   "front": (4,20,4,12), "left": (8,20,4,12), "back": (12,20,4,12)},
    "r_leg_overlay": {"top": (4,32,4,4), "bottom": (8,32,4,4), "right": (0,36,4,12),
                       "front": (4,36,4,12), "left": (8,36,4,12), "back": (12,36,4,12)},
    "l_leg_base": {"top": (20,48,4,4), "bottom": (24,48,4,4), "right": (16,52,4,12),
                   "front": (20,52,4,12), "left": (24,52,4,12), "back": (28,52,4,12)},
    "l_leg_overlay": {"top": (4,48,4,4), "bottom": (8,48,4,4), "right": (0,52,4,12),
                       "front": (4,52,4,12), "left": (8,52,4,12), "back": (12,52,4,12)},
}
FACE_TO_MC = {"north": "front", "south": "back", "east": "right", "west": "left", "up": "top", "down": "bottom"}

def _slim_arm_region(region):
    """Return Minecraft's actual Alex/slim unwrap for an arm region.

    The previous version only shortened every wide front/back/top/bottom rect.
    In the slim layout, however, bottom, left, and back also move one pixel
    left because the top/front island before them is one pixel narrower. That
    old offset sampled the unused transparent column behind every arm, which
    appeared in Godot as a missing/black stripe down the back of every hunter.
    """
    out = dict(REGIONS[region])
    for face in ("front", "top"):
        x, y, w, h = out[face]
        out[face] = (x, y, w - 1, h)
    for face in ("bottom", "back"):
        x, y, w, h = out[face]
        out[face] = (x - 1, y, w - 1, h)
    for face in ("left",):
        x, y, w, h = out[face]
        out[face] = (x - 1, y, w, h)
    return out

for _arm in ("r_arm_base", "r_arm_overlay", "l_arm_base", "l_arm_overlay"):
    REGIONS[_arm + "_slim"] = _slim_arm_region(_arm)

# Y extents of the rig's three torso cubes, and the whole torso, taken from
# the Player template. Used to divide Minecraft's single 12-row body region
# proportionally between them.
TORSO_CUBE_Y = {"Chest": (68, 90), "Belly": (55, 71), "Pelvis": (45, 57)}
TORSO_TOP = max(y1 for _, y1 in TORSO_CUBE_Y.values())      # 90
TORSO_BOTTOM = min(y0 for y0, _ in TORSO_CUBE_Y.values())   # 45

def _torso_rows(y0, y1, rows=12):
    """Texture-row span (start, length) for a torso cube occupying y0..y1,
    measured from the top of the body region downward."""
    span = TORSO_TOP - TORSO_BOTTOM
    start = (TORSO_TOP - y1) / span * rows
    end = (TORSO_TOP - y0) / span * rows
    return (start, end - start)

TORSO_ROWS = {name: _torso_rows(*yr) for name, yr in TORSO_CUBE_Y.items()}

# Same idea for the leg: Minecraft stores thigh+calf+foot as one 12-row
# region, the rig splits it into three cubes.
LEG_CUBE_Y = {"Thigh": (29, 49), "Calf": (5, 29), "Foot": (0, 8)}
LEG_TOP = max(y1 for _, y1 in LEG_CUBE_Y.values())      # 49
LEG_BOTTOM = min(y0 for y0, _ in LEG_CUBE_Y.values())   # 0

def _leg_rows(y0, y1, rows=12):
    span = LEG_TOP - LEG_BOTTOM
    start = (LEG_TOP - y1) / span * rows
    end = (LEG_TOP - y0) / span * rows
    return (start, end - start)

LEG_ROWS = {name: _leg_rows(*yr) for name, yr in LEG_CUBE_Y.items()}
FACES = ["north", "south", "east", "west", "up", "down"]

def rect_to_uv(x0, y0, x1, y1, face):
    if face in ("north", "south", "east", "west"):
        return [x0, y0, x1, y1]
    return [x0, y1, x1, y0]

def region_face_rect(region_name, face):
    x, y, w, h = REGIONS[region_name][FACE_TO_MC[face]]
    return (x, y, x + w, y + h)

def uv_for(region_name, face):
    return rect_to_uv(*region_face_rect(region_name, face), face)

def slice_rect(rect, axis_total, part_start, part_len):
    x0, y0, x1, y1 = rect
    scale = (y1 - y0) / axis_total
    return (x0, y0 + part_start * scale, x1, y0 + (part_start + part_len) * scale)

def sliced_uv(region_name, face, axis_total, part_start, part_len):
    return rect_to_uv(*slice_rect(region_face_rect(region_name, face), axis_total, part_start, part_len), face)

def build_hair_palette(im, alpha_thresh=10):
    """Collects every distinct color found on the head's non-face surfaces
    (top/back/left/right, base + overlay). Handles multi-tone hair (streaks,
    highlights, accent colors like Byttu's red streak) since it's a full
    palette, not a single averaged color."""
    colors = set()
    for region in ("head_base", "head_overlay"):
        for face in ("top", "back", "left", "right"):
            x, y, w, h = REGIONS[region][face]
            if w == 0 or h == 0:
                continue
            for p in im.crop((x, y, x + w, y + h)).getdata():
                if p[3] > alpha_thresh:
                    colors.add(p[:3])
    return _drop_garment_colors(im, colors, alpha_thresh)

def _drop_garment_colors(im, colors, alpha_thresh=10, arm_share=0.4):
    """Remove colours that are really the character's SLEEVES.

    A dark-haired character in a dark uniform puts the same colour on the head
    and the jacket, so head-sampled colours alone can't tell them apart. The
    arms settle it: they are sleeve or bare skin, never hair. Any colour
    covering a large share of the arms is garment, so it is dropped from the
    hair palette -- this is what stopped Briselle's navy jacket being read as
    hair and hauled onto her hair objects, while her crimson hair (0% of the
    arms) is still detected."""
    counts, total = {}, 0
    for region in ("r_arm_base", "l_arm_base"):
        for face in ("front", "back", "left", "right"):
            x, y, w, h = REGIONS[region][face]
            for p in im.crop((x, y, x + w, y + h)).getdata():
                if p[3] > alpha_thresh:
                    counts[p[:3]] = counts.get(p[:3], 0) + 1
                    total += 1
    if not total:
        return list(colors)
    garment = {c for c, n in counts.items() if n / total >= arm_share}
    # Drop at the same tolerance the hair matcher uses (35). A tighter figure
    # leaves a near-neighbour of the sleeve colour in the palette, and that
    # neighbour then re-matches the sleeve anyway -- Briselle's graphite
    # (33,29,40) sits 22 away from her navy sleeve, so a 20 cutoff kept the
    # jacket classified as hair.
    return [c for c in colors if not any(color_dist(c, g) <= 35 for g in garment)]

def color_dist(c1, c2):
    return sum((a - b) ** 2 for a, b in zip(c1, c2)) ** 0.5

def build_clothing_palette(im, hair_palette=(), alpha_thresh=10, hair_thresh=35):
    """Colors that are definitely CLOTHING, sampled from the torso's front
    and side faces. Any color that is also a hair color is dropped: front
    faces routinely show hair falling over the shoulders, and leaving those
    in would make every genuine hair pixel tie against itself and get
    rejected."""
    colors = set()
    for face in ("front", "left", "right"):
        x, y, w, h = REGIONS["body_base"][face]
        for p in im.crop((x, y, x + w, y + h)).getdata():
            if p[3] > alpha_thresh:
                colors.add(p[:3])
    if hair_palette:
        colors = {c for c in colors if _min_dist(c, hair_palette) > hair_thresh}
    # Skin is not clothing. The front face always carries some bare skin (the
    # neck hole, and any exposed midriff/arms), and leaving it in made the
    # inpainter treat skin as a valid "garment" donor -- which is how removing
    # collar hair repainted the whole collar row skin-coloured.
    colors = {c for c in colors if color_dist(c, SKIN_TONE) > 30}
    return list(colors)

def _keep_top_connected(mask):
    """Keeps only mask regions contiguous with the TOP edge. Hair on the back
    of the torso physically descends from the head, so a hair-colored blob
    floating in the middle of the shirt is shirt art (a printed motif or a
    tone the hair happens to share), not hair."""
    w, h = mask.size
    px = mask.load()
    seen = [[False] * w for _ in range(h)]
    stack = [(x, 0) for x in range(w) if px[x, 0][3] > 10]
    for x, y in stack:
        seen[y][x] = True
    while stack:
        x, y = stack.pop()
        # 8-connected, not 4. Hair strands taper to single pixels that meet
        # only at their corners -- a 4-connected fill stops at the first
        # diagonal step and abandons the rest of the strand on the shirt.
        # The top-edge requirement still rejects free-floating shirt motifs,
        # which is what this function is actually guarding against.
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1),
                       (1, 1), (1, -1), (-1, 1), (-1, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] and px[nx, ny][3] > 10:
                seen[ny][nx] = True
                stack.append((nx, ny))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    opx = out.load()
    found = False
    for y in range(h):
        for x in range(w):
            if seen[y][x]:
                opx[x, y] = px[x, y]
                found = True
    return found, out

def _min_dist(rgb, palette):
    return min((color_dist(rgb, p) for p in palette), default=float("inf"))

def is_hair_color(pixel, palette, thresh=35, clothing_palette=None):
    if pixel[3] <= 10:
        return False
    d_hair = _min_dist(pixel[:3], palette)
    if d_hair > thresh:
        return False
    # Nearest-neighbour classification: a pixel that looks MORE like the
    # shirt than like the hair is shirt, even if it's within the hair
    # threshold -- this is what keeps shirt remnants off the ponytail.
    if clothing_palette:
        return d_hair <= _min_dist(pixel[:3], clothing_palette)
    return True

def extract_hair_mask(im, region_box, palette, thresh=35, clothing_palette=None,
                       require_top_connection=True):
    """Returns (has_hair, masked_rgba_crop) for a region, where non-hair
    pixels are made transparent."""
    crop = im.crop(region_box).convert("RGBA")
    w, h = crop.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    src = crop.load()
    dst = out.load()
    found = False
    for j in range(h):
        for i in range(w):
            p = src[i, j]
            if is_hair_color(p, palette, thresh, clothing_palette):
                dst[i, j] = p
                found = True
    if not found:
        return False, out
    if not require_top_connection:
        # For art that legitimately starts partway down a region -- a tail
        # curling out of the mid/lower back, say -- the top-edge rules below
        # would throw the whole thing away.
        return True, out
    found, out = _keep_top_connected(out)
    if not found:
        return False, out
    # A real ponytail/braid enters the back of the torso NARROW (it descends
    # from the head as a bunch). A mask that spans the full width at the top
    # is the shirt itself -- which happens when a character's hair and
    # costume share a color (measured: real hair tops out at ~50% width,
    # shirt-as-hair false positives at 100%). Front-vs-back color coverage
    # was tried first and overlapped too much to separate them.
    w, h = out.size
    px = out.load()
    # A garment field, not hair: every covered row has the IDENTICAL shape.
    # Real hair on a torso always varies -- it tapers, splits, or ends at
    # different heights -- so an unchanging column pattern is a solid garment
    # whose colour happens to match the hair, and treating it as hair drags
    # the shirt onto the hair objects.
    #
    # Note this deliberately replaces an earlier "full-width top row = shirt"
    # rule. Hair very often DOES span the full width at the collar before
    # tapering (Verrine, Nyxie, Haelith all do), so that rule threw away real
    # hair; shape variation separates the two cases correctly.
    rows = [tuple(px[x, y][3] > 10 for x in range(w)) for y in range(h)]
    covered = [r for r in rows if any(r)]
    if covered:
        widest = max(sum(r) for r in covered)
        if len(set(covered)) == 1 and widest >= w * 0.5:
            return False, Image.new("RGBA", (w, h), (0, 0, 0, 0))
    return True, out

def dominant_color(im, box, alpha_thresh=10):
    from collections import Counter
    c = Counter()
    for p in im.crop(box).getdata():
        if p[3] > alpha_thresh:
            c[p[:3]] += 1
    return c.most_common(1)[0][0] if c else (200, 200, 200)

def patch_region_with_mask(im, box, mask_crop, fill_color, prefer_palette=None):
    """Wherever mask_crop is opaque, repaint the corresponding pixels of im
    (within box) with the surrounding garment color -- used to erase hair
    pixels from the base clothing texture once they've been split into a
    real Body-Hair object, so the base layer doesn't show a duplicate hair
    patch behind it.

    Fills ROW BY ROW from the nearest uncovered pixel on the same row, rather
    than flooding the whole area with one average color. The back of a torso
    is banded horizontally (shirt, then belt, then skirt), so a single flat
    fill bleeds the shirt color down over the belt and skirt."""
    x0, y0, x1, y1 = box
    px = im.load()
    mpx = mask_crop.load()
    w, h = mask_crop.size

    def masked(i, j):
        return mpx[i, j][3] > 10

    def is_preferred(rgb):
        return prefer_palette is None or _min_dist(rgb, prefer_palette) <= 35

    # Per-row donor colors, so each band keeps its own color. Preferred
    # (clothing) colors win: the collar row reads hair/skin/skin/hair, so
    # without this the shoulders behind removed hair fill with the skin tone
    # from the middle of the row instead of the garment.
    row_fallback = {}
    for j in range(h):
        opaque = [px[x0 + i, y0 + j][:3] for i in range(w)
                  if not masked(i, j) and px[x0 + i, y0 + j][3] > 10]
        pref = [c for c in opaque if is_preferred(c)]
        pool = pref or opaque
        if pool:
            row_fallback[j] = max(set(pool), key=pool.count)

    for j in range(h):
        for i in range(w):
            if not masked(i, j):
                continue
            donor = None
            # 1) nearest GARMENT pixel on this row
            if prefer_palette:
                for d in range(1, w):
                    for ni in (i - d, i + d):
                        if 0 <= ni < w and not masked(ni, j) and px[x0 + ni, y0 + j][3] > 10:
                            cand = px[x0 + ni, y0 + j][:3]
                            if is_preferred(cand):
                                donor = cand
                                break
                    if donor:
                        break
                # 2) garment from the closest row that has one. Needed for the
                # collar row, which is often only hair and bare skin -- without
                # this it fell through to the skin beside it.
                if donor is None:
                    for d in range(1, h):
                        for nj in (j - d, j + d):
                            if nj in row_fallback and is_preferred(row_fallback[nj]):
                                donor = row_fallback[nj]
                                break
                        if donor:
                            break
            # 3) last resort: any neighbour on this row
            if donor is None:
                for d in range(1, w):
                    for ni in (i - d, i + d):
                        if 0 <= ni < w and not masked(ni, j) and px[x0 + ni, y0 + j][3] > 10:
                            donor = px[x0 + ni, y0 + j][:3]
                            break
                    if donor:
                        break
            if donor is None:
                # whole row covered -- borrow the closest row that isn't
                for d in range(1, h):
                    for nj in (j - d, j + d):
                        if nj in row_fallback:
                            donor = row_fallback[nj]
                            break
                    if donor:
                        break
            if donor is None:
                donor = fill_color
            a = px[x0 + i, y0 + j][3]
            px[x0 + i, y0 + j] = (donor[0], donor[1], donor[2], a)

def close_collar_gap(im, clothing_palette, rows=2, tol=30):
    """Paint the garment across the torso's collar row.

    A Minecraft skin leaves the neck hole open on the body's TOP TWO rows --
    those pixels are skin-toned because vanilla hides them under the head,
    which sits directly on the body. This rig has a real Neck cube in that
    space and a taller head, so they are exposed and read as a pale collar
    band. Replacing just those skin-toned pixels with the surrounding garment
    keeps the shirt continuous over the shoulders.

    Two rows is measured, not guessed: across the roster the neck hole spans
    rows 0-1 (14 characters carry skin on row 1) and no character has skin on
    row 2, so this cleans the hole without eating a low neckline."""
    px = im.load()
    for face in ("front", "back", "left", "right"):
        x, y, w, h = REGIONS["body_base"][face]
        for j in range(min(rows, h)):
            # Look down the region for the garment colour: the collar row
            # itself is frequently just hair and the bare neck, with the shirt
            # only starting a row or two lower.
            fill = None
            for jj in range(j, h):
                cand = [px[x + i, y + jj][:3] for i in range(w)
                        if px[x + i, y + jj][3] > 10
                        and color_dist(px[x + i, y + jj][:3], SKIN_TONE) > tol
                        and (not clothing_palette or _min_dist(px[x + i, y + jj][:3], clothing_palette) <= 35)]
                if cand:
                    fill = max(set(cand), key=cand.count)
                    break
            if fill is None:
                continue
            for i in range(w):
                c = px[x + i, y + j]
                if c[3] > 10 and color_dist(c[:3], SKIN_TONE) <= tol:
                    px[x + i, y + j] = (fill[0], fill[1], fill[2], c[3])

def region_has_content(im, region_name, alpha_thresh=10):
    for (x, y, w, h) in REGIONS[region_name].values():
        if w == 0 or h == 0:
            continue
        crop = im.crop((x, y, x + w, y + h))
        if any(p[3] > alpha_thresh for p in crop.getdata()):
            return True
    return False

# ---------------------------------------------------------------------------
# L-/R- naming fix -- see module docstring. Verified against the live rig;
# these are the exact base names (prefix stripped) that are backwards in the
# raw template. Eyelid/Eyelid-Bot are intentionally excluded (already correct).
# ---------------------------------------------------------------------------
SWAP_BASENAMES = {
    "Eyebrow-Attachment", "Eye-Attachment", "Ear-Attachment", "Shoulder",
    "Arm", "Forearm", "Hand", "Attachment", "Shoulder2", "Thigh", "Calf", "Foot",
}

def fix_bone_spelling(data):
    """The template ships one bone misspelled: "Fofrontm" for "Forearm".

    Corrected in memory, like the L-/R- bug above and for the same reason --
    the file on disk is somebody else's asset and is never written to. Every
    plan key, swap-list entry and animation binding in this toolchain spells it
    correctly, so this is the one place the template's typo is absorbed. Do it
    BEFORE fix_lr_naming, whose swap list is keyed on the corrected name.
    """
    for coll in (data["groups"], data["elements"]):
        for item in coll:
            if "Fofrontm" in item.get("name", ""):
                item["name"] = item["name"].replace("Fofrontm", "Forearm")


def fix_lr_naming(data):
    for coll in (data["groups"], data["elements"]):
        for item in coll:
            name = item.get("name", "")
            if name.startswith(("L-", "R-")):
                base = name[2:]
                if base in SWAP_BASENAMES:
                    item["name"] = ("R-" if name[0] == "L" else "L-") + base

# ---------------------------------------------------------------------------
# Body-part -> UV plan builder
# ---------------------------------------------------------------------------
def build_uv_plan(im):
    plan = {}
    overlay_present = {}

    plan["Head"] = {f: uv_for("head_base", f) for f in FACES}
    overlay_present["head"] = region_has_content(im, "head_overlay")
    if overlay_present["head"]:
        plan["Hair-Overlay"] = {f: uv_for("head_overlay", f) for f in FACES}

    overlay_present["body"] = region_has_content(im, "body_overlay")
    # The rig splits the torso into three stacked cubes, but Minecraft stores
    # it as ONE 12-row region. Each cube therefore gets the slice of those 12
    # rows matching the share of the torso's height it actually occupies --
    # so a 1px belt row renders 1px tall, not smeared over a whole cube.
    # (The earlier hand-tuned split gave Pelvis a single stretched row, which
    # is what made belts render enormous, and its hardcoded UVs were also
    # still in the pre-mirror-fix left/right-flipped form.)
    for part, (start, length) in TORSO_ROWS.items():
        plan[part] = {f: sliced_uv("body_base", f, 12, start, length) for f in ["north","south","east","west"]}
        if overlay_present["body"]:
            plan[part + "-Overlay"] = {f: sliced_uv("body_overlay", f, 12, start, length) for f in ["north","south","east","west"]}
    # Caps: real top/bottom of the torso region at the ends, thin seam slices
    # at the internal joins (barely visible, they sit inside the body).
    chest_end = sum(TORSO_ROWS["Chest"])
    belly_end = sum(TORSO_ROWS["Belly"])
    plan["Chest"]["up"] = uv_for("body_base", "up")
    plan["Chest"]["down"] = sliced_uv("body_base", "north", 12, chest_end, 0.5)
    plan["Belly"]["up"] = sliced_uv("body_base", "north", 12, TORSO_ROWS["Belly"][0], 0.5)
    plan["Belly"]["down"] = sliced_uv("body_base", "north", 12, belly_end, 0.5)
    plan["Pelvis"]["up"] = sliced_uv("body_base", "north", 12, TORSO_ROWS["Pelvis"][0], 0.5)
    plan["Pelvis"]["down"] = uv_for("body_base", "down")

    # Arms use the SLIM sampling to match the slim geometry the rig is resized
    # to; the wide regions would stretch 4px of art across a 3px-wide arm.
    for side, base_region, overlay_region in [("R", "r_arm_base_slim", "r_arm_overlay_slim"),
                                               ("L", "l_arm_base_slim", "l_arm_overlay_slim")]:
        overlay_present[f"{side}_arm"] = region_has_content(im, overlay_region)
        for part, (start, length) in [(f"{side}-Arm", (0,5)), (f"{side}-Forearm", (5,4)), (f"{side}-Hand", (9,3))]:
            plan[part] = {f: sliced_uv(base_region, f, 12, start, length) for f in ["north","south","east","west"]}
            if overlay_present[f"{side}_arm"]:
                plan[part + "-Overlay"] = {f: sliced_uv(overlay_region, f, 12, start, length) for f in ["north","south","east","west"]}
        plan[f"{side}-Arm"]["up"] = uv_for(base_region, "up")
        plan[f"{side}-Arm"]["down"] = sliced_uv(base_region, "north", 12, 4, 1)
        plan[f"{side}-Forearm"]["up"] = sliced_uv(base_region, "north", 12, 4, 1)
        plan[f"{side}-Forearm"]["down"] = sliced_uv(base_region, "north", 12, 8, 1)
        plan[f"{side}-Hand"]["up"] = sliced_uv(base_region, "north", 12, 8, 1)
        plan[f"{side}-Hand"]["down"] = uv_for(base_region, "down")

    for side, base_region, overlay_region in [("R", "r_leg_base", "r_leg_overlay"), ("L", "l_leg_base", "l_leg_overlay")]:
        overlay_present[f"{side}_leg"] = region_has_content(im, overlay_region)
        # Same proportional split as the torso: the leg is one 12-row region
        # in the skin but three stacked cubes in the rig, so each cube takes
        # the row span matching the share of leg height it occupies. The old
        # hand-picked spans had Calf and Foot BOTH sampling rows 8-12, which
        # is why sock stripes appeared duplicated and smeared across the foot.
        for part, (start, length) in LEG_ROWS.items():
            name = f"{side}-{part}"
            plan[name] = {f: sliced_uv(base_region, f, 12, start, length) for f in ["north","south","east","west"]}
            if overlay_present[f"{side}_leg"] and part != "Foot":
                plan[name + "-Overlay"] = {f: sliced_uv(overlay_region, f, 12, start, length) for f in ["north","south","east","west"]}
        thigh_end = sum(LEG_ROWS["Thigh"])
        calf_end = sum(LEG_ROWS["Calf"])
        plan[f"{side}-Thigh"]["up"] = uv_for(base_region, "up")
        plan[f"{side}-Thigh"]["down"] = sliced_uv(base_region, "north", 12, thigh_end, 0.5)
        plan[f"{side}-Calf"]["up"] = sliced_uv(base_region, "north", 12, LEG_ROWS["Calf"][0], 0.5)
        plan[f"{side}-Calf"]["down"] = sliced_uv(base_region, "north", 12, calf_end, 0.5)
        plan[f"{side}-Foot"]["up"] = sliced_uv(base_region, "north", 12, LEG_ROWS["Foot"][0], 0.5)
        plan[f"{side}-Foot"]["down"] = uv_for(base_region, "down")

    plan["Neck"] = {f: sliced_uv("body_base", f, 12, 0, 1) for f in ["north","south","east","west"]}
    plan["Neck"]["down"] = sliced_uv("body_base", "north", 12, 0, 1)

    eyelid_patch = (44, 20, 46, 22)
    for name in ["L-Eyelid", "R-Eyelid", "L-Eyelid-Bot", "R-Eyelid-Bot"]:
        plan[name] = {"north": rect_to_uv(*eyelid_patch, "north")}

    return plan, overlay_present


def repair_character_layers(data):
    """Normalize shared arm UVs and garment shells on reviewed BBModels.

    The committed A-Z sources are reviewed art rather than disposable build
    products, so the importer calls this small deterministic repair instead of
    regenerating their bespoke geometry. It also makes future Blockbench
    re-exports inherit the corrected shared character contract.
    """
    arm_plan = {}
    for side, base_region, overlay_region in (
            ("R", "r_arm_base_slim", "r_arm_overlay_slim"),
            ("L", "l_arm_base_slim", "l_arm_overlay_slim")):
        for part, (start, length) in (
                (f"{side}-Arm", (0, 5)),
                (f"{side}-Forearm", (5, 4)),
                (f"{side}-Hand", (9, 3))):
            arm_plan[part] = {f: sliced_uv(base_region, f, 12, start, length)
                              for f in ("north", "south", "east", "west")}
            arm_plan[part + "-Overlay"] = {
                f: sliced_uv(overlay_region, f, 12, start, length)
                for f in ("north", "south", "east", "west")}
        arm_plan[f"{side}-Arm"].update({
            "up": uv_for(base_region, "up"),
            "down": sliced_uv(base_region, "north", 12, 4, 1),
        })
        arm_plan[f"{side}-Forearm"].update({
            "up": sliced_uv(base_region, "north", 12, 4, 1),
            "down": sliced_uv(base_region, "north", 12, 8, 1),
        })
        arm_plan[f"{side}-Hand"].update({
            "up": sliced_uv(base_region, "north", 12, 8, 1),
            "down": uv_for(base_region, "down"),
        })

    garment_shells = {
        "Chest-Overlay", "Belly-Overlay", "Pelvis-Overlay",
        "R-Arm-Overlay", "R-Forearm-Overlay", "R-Hand-Overlay",
        "L-Arm-Overlay", "L-Forearm-Overlay", "L-Hand-Overlay",
        "R-Thigh-Overlay", "R-Calf-Overlay",
        "L-Thigh-Overlay", "L-Calf-Overlay",
    }
    for element in data.get("elements", []):
        name = element.get("name", "")
        faces = element.get("faces") or {}
        for face, uv in arm_plan.get(name, {}).items():
            if face in faces:
                faces[face]["uv"] = uv
        # A segmented jacket/sleeve copied the base cube's cap textures. Those
        # caps overlap at every chest, elbow, wrist, and knee join and become
        # the bright horizontal shelves/z-fighting seen in-game. Minecraft's
        # visible second layer is the outward shell; internal segment caps are
        # neither authored nor useful.
        if name in garment_shells:
            for face in ("up", "down"):
                if face in faces:
                    faces[face]["texture"] = None
    return data

# ---------------------------------------------------------------------------
# .bbmodel manipulation
# ---------------------------------------------------------------------------
SLIM_ARM_SHIFTS = {
    "R-Arm": ("to", 17.5), "R-Forearm": ("to", 17.50167), "R-Hand": ("to", 18.501669),
    "L-Arm": ("from", -17.5), "L-Forearm": ("from", -17.50167), "L-Hand": ("from", -18.501669),
}

def find_element(data, name):
    return next((e for e in data["elements"] if e["name"] == name), None)

def find_group(data, name):
    return next((g for g in data["groups"] if g["name"] == name), None)

def add_bone_group(data, name, origin, parent_group_name, template_name="Neck"):
    """Creates a new animatable bone (group), pivoted at `origin`, nested
    under an existing group -- for any appendage that should be posable
    on its own (wing flap, ear twitch, tail sway), not just a bare cube
    with no dedicated pivot in the bone hierarchy."""
    template = find_group(data, template_name)
    g = json.loads(json.dumps(template))
    uuid = _new_uuid(name + "-bone")
    g["name"] = name
    g["uuid"] = uuid
    g["origin"] = list(origin)
    g["rotation"] = [0, 0, 0]
    g["children"] = []
    data["groups"].append(g)

    parent = find_group(data, parent_group_name)
    parent_uuid = parent["uuid"] if parent else None

    def insert(node):
        if isinstance(node, list):
            for child in node:
                if isinstance(child, dict):
                    if child.get("uuid") == parent_uuid:
                        child["children"].append({"uuid": uuid, "isOpen": True, "children": []})
                        return True
                    if insert(child.get("children", [])):
                        return True
        return False
    insert(data["outliner"])
    return name

def apply_uv_plan(data, plan, tex_index=0):
    for cube_name, faces in plan.items():
        el = find_element(data, cube_name)
        if el is None:
            continue
        el["autouv"] = 0
        for face, uv in faces.items():
            if uv is None:
                continue
            el["faces"][face]["uv"] = uv
            el["faces"][face]["texture"] = tex_index

def apply_slim_arms(data):
    for name, (key, val) in SLIM_ARM_SHIFTS.items():
        el = find_element(data, name)
        if el is None:
            continue
        arr = list(el[key])
        arr[0] = val
        el[key] = arr

def add_texture_entry(data, image, name):
    """Appends a texture (PIL Image, already the exact crop/canvas to use) and
    returns its array index. The texture's `id` is kept equal to that index as
    a string -- Blockbench resolves a face's integer `texture` value against
    each texture's `id` field, NOT its array position, so these must match or
    faces silently resolve to the wrong texture (this was the bug where a hair
    face still 'connected to' the original skin texture)."""
    import base64, io
    buf = io.BytesIO()
    image.save(buf, format="PNG")
    b64 = base64.b64encode(buf.getvalue()).decode("ascii")
    idx = len(data["textures"])
    entry = {
        "name": name, "relative_path": name, "folder": "", "namespace": "", "id": str(idx),
        "group": "", "scope": 0, "width": image.width, "height": image.height,
        "uv_width": image.width, "uv_height": image.height, "particle": False, "use_as_default": False,
        "layers_enabled": False, "sync_to_project": "", "file_format": "png", "render_mode": "default",
        # "double" (not "auto") so the flat zero-thickness planes -- wings,
        # ears, tails, halos, ponytails -- stay visible from both sides. This
        # is a core texture property, so it survives regardless of whether the
        # active format understands the per-cube `double_sided` flag.
        "render_sides": "double", "wrap_mode": "clamp", "pbr_channel": "color", "fps": 7, "frame_time": 1,
        "frame_order_type": "loop", "frame_order": "", "frame_interpolate": False, "visible": True,
        "internal": True, "saved": True,
        "uuid": f"00000000-0000-0000-0000-{idx:012d}",
        "source": f"data:image/png;base64,{b64}",
    }
    data["textures"].append(entry)
    return idx

def face_has_content(im, region_name, face, alpha_thresh=10):
    x, y, w, h = REGIONS[region_name][FACE_TO_MC[face]]
    return any(p[3] > alpha_thresh for p in im.crop((x, y, x + w, y + h)).getdata())

def add_hair_planes(data, plan, im=None, uv_offset=(0, 0), inflate=2.0, tex_index=0):
    """Replaces the head's hat-layer shell with five separate flat planes --
    fringe, back, both side locks, and the crown -- each on its own bone.

    As one inflated box the hair was a rigid copy of the skull that could not
    move independently; as boned planes each section can sway, and it matches
    how the tails/ears/wings are built."""
    head = find_element(data, "Head")
    if head is None:
        return
    ox, oy = uv_offset
    x0, y0, z0 = [head["from"][i] - inflate for i in range(3)]
    x1, y1, z1 = [head["to"][i] + inflate for i in range(3)]
    t = 0.05
    # face: (from, to, bone pivot) -- pivots sit where each section attaches
    # to the skull, so rotation swings the hair rather than sliding it.
    specs = {
        "north": ([x0, y0, z0], [x1, y1, z0 + t], [0, y1, z0]),          # fringe
        "south": ([x0, y0, z1 - t], [x1, y1, z1], [0, y1, z1]),          # back length
        "west":  ([x0, y0, z0], [x0 + t, y1, z1], [x0, y1, 0]),          # left lock
        "east":  ([x1 - t, y0, z0], [x1, y1, z1], [x1, y1, 0]),          # right lock
        "up":    ([x0, y1 - t, z0], [x1, y1, z1], [0, y1, 0]),           # crown
    }
    names = {"north": "Hair-Fringe", "south": "Hair-Back", "west": "Hair-L-Lock",
             "east": "Hair-R-Lock", "up": "Hair-Top"}
    for face, (frm, to, pivot) in specs.items():
        uv = plan.get("Hair-Overlay", {}).get(face)
        if uv is None:
            continue
        # Skip sections with no art at all -- e.g. a skin edited to remove a
        # hood leaves the back/top overlay empty, and an invisible plane is
        # just a wasted node in the rig.
        if im is not None and not face_has_content(im, "head_overlay", face):
            continue
        uv = [uv[0] - ox, uv[1] - oy, uv[2] - ox, uv[3] - oy]
        name = names[face]
        bone = f"{name}-Bone"
        add_bone_group(data, bone, origin=pivot, parent_group_name="Head")
        # ONLY the outward face is textured. These planes are 0.05 thick and
        # already double_sided, so also texturing the opposite face produced
        # two coincident double-sided surfaces that z-fought -- which is what
        # made the side/front hair look like it was drawing both sides at once.
        add_free_cube(
            data, name, frm=frm, to=to, origin=pivot,
            faces_uv={face: uv},
            tex_index=tex_index, parent_group_name=bone, double_sided=True,
        )

def add_overlay_cube(data, base_name, new_name, plan, inflate=2.0, tex_index=0, uv_offset=(0, 0)):
    base = find_element(data, base_name)
    if base is None:
        return
    new_el = json.loads(json.dumps(base))
    new_el["name"] = new_name
    new_el["uuid"] = f"{base['uuid'][:-8]}{abs(hash(new_name)) % 99999999:08x}"[:36]
    new_el["inflate"] = inflate
    new_el["autouv"] = 0
    # The base cube's cap UVs belong to the skin underneath, not the garment
    # overlay. Retaining them creates overlapping horizontal plates anywhere
    # this articulated rig splits one Minecraft body part into several bones.
    for face_data in new_el.get("faces", {}).values():
        face_data["texture"] = None
    ox, oy = uv_offset
    for face, uv in plan.get(new_name, {}).items():
        if uv is not None:
            new_el["faces"][face]["uv"] = [uv[0] - ox, uv[1] - oy, uv[2] - ox, uv[3] - oy]
            new_el["faces"][face]["texture"] = tex_index
    data["elements"].append(new_el)

    base_group_uuid = base["uuid"]
    def insert_after(node):
        if isinstance(node, list):
            for i, child in enumerate(node):
                if child == base_group_uuid:
                    node.insert(i + 1, new_el["uuid"])
                    return True
                if isinstance(child, dict) and insert_after(child.get("children", [])):
                    return True
        return False
    insert_after(data["outliner"])

def _new_uuid(seed):
    h = abs(hash(seed))
    hexs = f"{h:032x}"[:32]
    return f"{hexs[0:8]}-{hexs[8:12]}-{hexs[12:16]}-{hexs[16:20]}-{hexs[20:32]}"

def add_free_cube(data, name, frm, to, origin, faces_uv, tex_index, parent_group_name, after_child_uuid=None, template_name="Head", double_sided=False, rotation=None):
    """Builds a brand-new cube by CLONING an existing valid element (default
    'Head') and overwriting the relevant fields, rather than hand-assembling
    the dict from scratch -- a from-scratch dict was missing something
    Blockbench's loader needs and silently mis-resolved its face textures to
    index 0 on load, even though the saved JSON itself was correct."""
    template = find_element(data, template_name)
    el = json.loads(json.dumps(template))
    uuid = _new_uuid(name)
    el["name"] = name
    el["from"] = list(frm)
    el["to"] = list(to)
    el["origin"] = list(origin)
    el["inflate"] = 0
    el["autouv"] = 0
    el["stretch"] = [1, 1, 1]
    el["double_sided"] = double_sided
    el["rotation"] = list(rotation) if rotation else [0, 0, 0]
    el["uuid"] = uuid
    for f in FACES:
        if f in faces_uv and faces_uv[f] is not None:
            el["faces"][f]["uv"] = faces_uv[f]
            el["faces"][f]["texture"] = tex_index
        else:
            el["faces"][f]["texture"] = None
    data["elements"].append(el)
    parent = find_group(data, parent_group_name)
    parent_uuid = parent["uuid"] if parent else None

    def insert(node):
        if isinstance(node, list):
            for i, child in enumerate(node):
                cu = child if isinstance(child, str) else child.get("uuid")
                if (after_child_uuid and cu == after_child_uuid) or (not after_child_uuid and cu == parent_uuid and isinstance(child, dict)):
                    if after_child_uuid:
                        node.insert(i + 1, uuid)
                    else:
                        child["children"].append(uuid)
                    return True
                if isinstance(child, dict) and insert(child.get("children", [])):
                    return True
        return False
    insert(data["outliner"])
    return uuid

OVERLAY_RECTS = [
    (x, y, x + w, y + h)
    for name, faces in REGIONS.items() if name.endswith("_overlay")
    for (x, y, w, h) in faces.values()
]

def _box_is_overlay(box):
    """True only if `box` lies entirely inside one of the skin's OVERLAY
    (second-layer) regions. Overlay regions are allowed to be transparent,
    so erasing from them is safe; erasing from a BASE region would punch a
    literal hole in the body, so those are never cleared."""
    x0, y0, x1, y1 = box
    return any(x0 >= rx0 and y0 >= ry0 and x1 <= rx1 and y1 <= ry1
               for (rx0, ry0, rx1, ry1) in OVERLAY_RECTS)

class TexturePacker:
    """Packs pieces top-to-bottom into one canvas. Returns each piece's
    (x, y) offset so callers can translate their local UVs into the shared
    canvas's coordinate space.

    Parts may declare `src_origin` -- where they came from in the original
    64x64 skin. That lets `clear_source()` erase a source-space region from
    every packed copy that would otherwise still display it, so art split
    out into its own object doesn't stay stuck on the skin underneath it."""
    def __init__(self, width=32):
        self.width = width
        self.y = 0
        self.parts = []
        self.clears = []

    def add(self, image, x=0, src_origin=None):
        pos = (x, self.y)
        self.parts.append((image, pos, src_origin))
        self.y += image.height + 2
        self.width = max(self.width, image.width + x)
        return pos

    def clear_source(self, box):
        """Queue a source-space (original 64x64 skin coords) region to be
        erased from every packed copy that maps back to it. Ignored for
        base-layer regions, which must stay opaque."""
        if _box_is_overlay(tuple(box)):
            self.clears.append(tuple(box))
            return True
        return False

    def build(self):
        canvas = Image.new("RGBA", (self.width, max(self.y, 1)), (0, 0, 0, 0))
        for img, (x, y), _src in self.parts:
            canvas.paste(img, (x, y), img)
        # Erase extracted regions from any copy that still shows them. Each
        # part that declared a src_origin is a window onto the original skin,
        # so a source-space box maps into it at (box - src_origin).
        blank = None
        for img, (x, y), src in self.parts:
            if src is None:
                continue
            sx, sy = src
            for (bx0, by0, bx1, by1) in self.clears:
                lx0, ly0 = bx0 - sx, by0 - sy
                lx1, ly1 = bx1 - sx, by1 - sy
                lx0, ly0 = max(lx0, 0), max(ly0, 0)
                lx1, ly1 = min(lx1, img.width), min(ly1, img.height)
                if lx1 <= lx0 or ly1 <= ly0:
                    continue
                blank = Image.new("RGBA", (lx1 - lx0, ly1 - ly0), (0, 0, 0, 0))
                canvas.paste(blank, (x + lx0, y + ly0))
        return canvas

def convert(skin_path, output_path, template_path=DEFAULT_TEMPLATE, extra_fn=None,
            model_format="free"):
    """model_format: Blockbench format id for the output.
      "free"             -- Generic Model (default). Allows fractional cube
                            sizes, which the flat 0.05-thick appendage planes
                            need; Hytale Character sets integer_size=True and
                            can snap them. Also lifts the single-texture rule.
      "hytale_character" -- keep the original Hytale format.
    Geometry, the bone rig, and per-face UVs are identical either way; only
    the format tag and its editor-side constraints differ."""
    with open(template_path) as f:
        data = json.load(f)
    fix_bone_spelling(data)
    fix_lr_naming(data)
    data.setdefault("meta", {})["model_format"] = model_format

    im = Image.open(skin_path).convert("RGBA")
    plan, overlay_present = build_uv_plan(im)
    skin_name = hunter_name_for(skin_path)

    # Detect body/back hair-colored pixels BEFORE packing the base texture,
    # so the base copy can have them patched out to the shirt's own color --
    # otherwise the new separate Body-Hair piece duplicates against the same
    # hair-colored pixels still showing through the base clothing behind it.
    hair_palette = build_hair_palette(im)
    body_hair_added = False
    base_im = im.copy()
    if hair_palette:
        rx, ry, rw, rh = REGIONS["body_base"]["back"]
        clothing_palette = build_clothing_palette(im, hair_palette=hair_palette)
        found, hair_crop = extract_hair_mask(
            im, (rx, ry, rx + rw, ry + rh), hair_palette, clothing_palette=clothing_palette)
        if found:
            fx, fy, fw, fh = REGIONS["body_base"]["front"]
            shirt_color = dominant_color(im, (fx, fy, fx + fw, fy + fh))
            patch_region_with_mask(base_im, (rx, ry, rx + rw, ry + rh), hair_crop, shirt_color)
            pad = 4
            expanded = Image.new("RGBA", (rw + pad * 2, rh + 8), (0, 0, 0, 0))
            expanded.paste(hair_crop, (pad, 0), hair_crop)
            body_hair_added = True

    # Same treatment for hair that falls over the shoulders onto the CHEST /
    # stomach: lift it off the shirt into its own object and repaint the
    # garment underneath, so the strands aren't baked flat into the clothing.
    front_hair_added = False
    if hair_palette:
        fx, fy, fw, fh = REGIONS["body_base"]["front"]
        clothing_palette = build_clothing_palette(im, hair_palette=hair_palette)
        f_found, front_crop = extract_hair_mask(
            im, (fx, fy, fx + fw, fy + fh), hair_palette, clothing_palette=clothing_palette)
        if f_found:
            shirt_color = dominant_color(im, (fx, fy, fx + fw, fy + fh))
            patch_region_with_mask(base_im, (fx, fy, fx + fw, fy + fh), front_crop, shirt_color)
            front_hair_added = True

    # Hair also gets painted into the OVERLAY (jacket) layer on some skins --
    # e.g. long back hair drawn on the body overlay rather than the base. That
    # art would otherwise render as a stiff jacket shell, so merge any
    # hair-colored overlay pixels into the corresponding hair object and clear
    # them from the overlay. Overlay regions are allowed to be transparent, so
    # erasing there is safe.
    overlay_hair_clears = []
    if hair_palette:
        for region, face, target in (("body_overlay", "back", "back"),
                                      ("body_overlay", "front", "front"),
                                      ("body_overlay", "left", "side"),
                                      ("body_overlay", "right", "side")):
            ox_, oy_, ow_, oh_ = REGIONS[region][face]
            found_o, mask_o = extract_hair_mask(
                im, (ox_, oy_, ox_ + ow_, oy_ + oh_), hair_palette,
                clothing_palette=build_clothing_palette(im, hair_palette=hair_palette))
            if not found_o:
                continue
            mpx = mask_o.load()
            for j in range(oh_):
                for i in range(ow_):
                    if mpx[i, j][3] > 10:
                        overlay_hair_clears.append((ox_ + i, oy_ + j, ox_ + i + 1, oy_ + j + 1))
            if target == "back" and not body_hair_added:
                # No base-layer ponytail, but the overlay has one -- promote it.
                pad = 4
                expanded = Image.new("RGBA", (ow_ + pad * 2, oh_ + 8), (0, 0, 0, 0))
                expanded.paste(mask_o, (pad, 0), mask_o)
                body_hair_added = True
            elif target == "front" and not front_hair_added:
                front_crop = mask_o
                front_hair_added = True

    # Everything -- base skin, hair, body-hair, and any bespoke extras a
    # special-case character needs -- packs into ONE shared canvas that
    # becomes the model's only texture. The (patched) base skin's pixels
    # land at (0,0), so every base-layer UV computed against the raw 64x64
    # layout below stays valid as-is. A single texture also sidesteps a
    # multi-texture-index resolution bug seen in live testing.
    packer = TexturePacker(width=im.width)
    packer.add(base_im, x=0, src_origin=(0, 0))
    for _b in overlay_hair_clears:
        packer.clear_source(_b)

    apply_uv_plan(data, plan, tex_index=0)
    apply_slim_arms(data)

    # The neck is another Hytale-rig addition Minecraft has no art for -- the
    # head simply sits on the body. It was sampling the torso's top row, but
    # that row is the collar, with hair framing both sides, so the throat came
    # out hair-coloured. Use the face's own skin tone instead.
    fx_, fy_, fw_, fh_ = REGIONS["head_base"]["front"]
    skin_tone = dominant_color(im, (fx_ + 2, fy_ + 5, fx_ + fw_ - 2, fy_ + fh_))
    neck_sw = Image.new("RGBA", (2, 2), skin_tone + (255,))
    nx, ny = packer.add(neck_sw)
    neck = find_element(data, "Neck")
    if neck is not None:
        for f in FACES:
            if neck["faces"][f].get("texture") is None and f == "up":
                continue
            neck["faces"][f]["uv"] = rect_to_uv(nx, ny, nx + 2, ny + 2, f)
            neck["faces"][f]["texture"] = 0

    # Feet are a Hytale-rig addition with no Minecraft counterpart: the skin
    # just ends at the ankle. Sampling the leg's last rows and stretching them
    # across a 14x20 shoe smears the sock stripes into garbage, so instead
    # take the shoe's actual color from the bottom of the leg and paint the
    # shoe with a flat swatch of it. The sole keeps the leg's real bottom art.
    for side, base_region in (("R", "r_leg_base"), ("L", "l_leg_base")):
        lx, ly, lw, lh = REGIONS[base_region]["front"]
        shoe = dominant_color(im, (lx, ly + lh - 2, lx + lw, ly + lh))
        swatch = Image.new("RGBA", (2, 2), shoe + (255,))
        sx, sy = packer.add(swatch)
        foot = find_element(data, f"{side}-Foot")
        if foot is None:
            continue
        for f in ("north", "south", "east", "west", "up"):
            foot["faces"][f]["uv"] = rect_to_uv(sx, sy, sx + 2, sy + 2, f)
            foot["faces"][f]["texture"] = 0
        foot["faces"]["down"]["uv"] = uv_for(base_region, "down")
        foot["faces"]["down"]["texture"] = 0

    hair_overlay_uv_offset = None  # value X such that final_uv = plan_uv - X, i.e. X = source_origin - canvas_placement

    if overlay_present.get("head"):
        hair_crop = im.crop((32, 0, 64, 16))  # 32x16, exact copy -- existing UV math needs no change
        off = packer.add(hair_crop, src_origin=(32, 0))
        hair_overlay_uv_offset = (32 - off[0], 0 - off[1])

    if body_hair_added:
        off = packer.add(expanded)
        body_hair_tex_placement = off

    if front_hair_added:
        front_hair_tex_placement = packer.add(front_crop)

    # Jacket/sleeve/pant overlay pieces (if present) stay mapped directly to
    # the main skin texture below -- they're real, already-finished skin art
    # (not a redesign target like the hair pieces), so there's nothing to pack.

    if body_hair_added:
        rx, ry, rw, rh = REGIONS["body_base"]["back"]
        pad = 4
        bx, by = body_hair_tex_placement
        uv_full = rect_to_uv(bx + pad, by, bx + pad + rw, by + rh, "south")
        # Flat, double-sided plane on its own bone. Parented to the HEAD and
        # pivoted at the back of the skull so the ponytail is attached to the
        # head (turning with it, swaying from its root) instead of floating
        # behind the torso.
        head = find_element(data, "Head")
        chest = find_element(data, "Chest")
        root_y = head["to"][1] - 4          # just below the crown
        # Hug the TORSO's back, not the head's. The head sits further back than
        # the chest, so anchoring to it left the hair hanging off the body.
        back_z = chest["to"][2] + 0.5
        add_bone_group(data, "Body-Hair-Bone", origin=[0, root_y, back_z], parent_group_name="Head")
        add_free_cube(
            data, "Body-Hair",
            frm=[-14, 45, back_z], to=[14, root_y, back_z + 0.05], origin=[0, root_y, back_z],
            faces_uv={"south": uv_full, "north": uv_full},
            tex_index=0, parent_group_name="Body-Hair-Bone", double_sided=True,
        )

    if front_hair_added:
        fx, fy, fw, fh = REGIONS["body_base"]["front"]
        px, py = front_hair_tex_placement
        uv_front = rect_to_uv(px, py, px + fw, py + fh, "north")
        # Sits just in front of the chest, spanning exactly the torso rows the
        # art came from so the strands stay aligned with the shirt they were
        # lifted off. Parented to the Head, like the back hair, since these
        # strands hang from the head rather than being part of the garment.
        chest = find_element(data, "Chest")
        front_z = chest["from"][2] - 0.5
        top_y = chest["to"][1]
        add_bone_group(data, "Front-Hair-Bone", origin=[0, top_y, front_z], parent_group_name="Head")
        add_free_cube(
            data, "Front-Hair",
            frm=[-14, TORSO_BOTTOM, front_z - 0.05], to=[14, top_y, front_z],
            origin=[0, top_y, front_z],
            faces_uv={"north": uv_front, "south": uv_front},
            tex_index=0, parent_group_name="Front-Hair-Bone", double_sided=True,
        )

    # Garment overlay shells are created after extra_fn (below), once the
    # bespoke pieces have claimed their pixels -- otherwise a character whose
    # entire body overlay IS the extracted art (Xivvy: her overlay holds only
    # the wing pair) keeps three fully transparent shells hanging off the
    # torso, which still read as "the wings are part of the chest overlay".

    data["name"] = skin_name
    if extra_fn is not None:
        extra_fn(data, im, packer)

    # Hair planes are built LAST, after the bespoke extras have claimed their
    # pixels. A section is only worth a plane if art remains there once those
    # claims are honoured -- e.g. Ilyra's crown holds nothing but the cat-ear
    # dots, which become the ears, so a Hair-Top plane would be invisible.
    effective = im.copy()
    for (cx0, cy0, cx1, cy1) in packer.clears:
        effective.paste((0, 0, 0, 0), (cx0, cy0, cx1, cy1))

    if overlay_present.get("head"):
        # Small inflate keeps the hair shell hugging the skull instead of
        # standing off it -- at 2.0 the planes read as a helmet floating
        # around the head rather than hair lying on it.
        add_hair_planes(data, plan, im=effective, uv_offset=hair_overlay_uv_offset,
                        inflate=0.75, tex_index=0)

    # Garment shells, also judged against what SURVIVES extraction. Xivvy's
    # body overlay holds nothing but her wing pair, so once the wings become
    # real objects there is no jacket left and the three torso shells would
    # otherwise linger as invisible geometry attached to the chest.
    if region_has_content(effective, "body_overlay"):
        for part in ["Chest", "Belly", "Pelvis"]:
            add_overlay_cube(data, part, part + "-Overlay", plan, inflate=1.5)
    for side, arm_reg, leg_reg in (("R", "r_arm_overlay", "r_leg_overlay"),
                                    ("L", "l_arm_overlay", "l_leg_overlay")):
        if region_has_content(effective, arm_reg):
            for seg in ["Arm", "Forearm", "Hand"]:
                add_overlay_cube(data, f"{side}-{seg}", f"{side}-{seg}-Overlay", plan, inflate=1.5)
        if region_has_content(effective, leg_reg):
            for seg in ["Thigh", "Calf"]:
                add_overlay_cube(data, f"{side}-{seg}", f"{side}-{seg}-Overlay", plan, inflate=1.5)

    # Build the ONE final combined texture now that every piece -- base skin,
    # hair, body-hair, and any bespoke extras extra_fn just packed -- has
    # been placed. This is the model's only texture (index 0).
    final_canvas = packer.build()
    data["textures"] = []
    add_texture_entry(data, final_canvas, f"{skin_name}.png")

    with open(output_path, "w") as f:
        json.dump(data, f)
    return {"skin": skin_name, "elements": len(data["elements"]), "overlays": overlay_present}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--template", default=DEFAULT_TEMPLATE)
    ap.add_argument("--batch", action="store_true")
    ap.add_argument("input")
    ap.add_argument("output")
    args = ap.parse_args()

    if args.batch:
        os.makedirs(args.output, exist_ok=True)
        results = []
        for fn in sorted(os.listdir(args.input)):
            if not fn.lower().endswith(".png"):
                continue
            skin_path = os.path.join(args.input, fn)
            out_path = os.path.join(args.output, hunter_name_for(fn) + ".bbmodel")
            results.append(convert(skin_path, out_path, args.template))
        print(json.dumps(results, indent=1))
    else:
        result = convert(args.input, args.output, args.template)
        print(json.dumps(result, indent=1))

if __name__ == "__main__":
    main()
