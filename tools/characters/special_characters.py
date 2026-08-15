"""
Bespoke geometry additions for the characters whose identity requires real
extra geometry beyond hair (ears, tails, halos, glyphs, wings, gills), driven
by ground-truth descriptions pulled from the LastRoute char-design docs.
Each function takes the already-converted `data` dict (post mc_to_hytale.py's
convert()), the source PIL image, and the shared TexturePacker -- every piece
packs into the same single combined canvas/texture (index 0) as the rest of
the model.

Thin cosmetic appendages (ears, wings, gills, halos) are built as genuinely
FLAT planes (near-zero thickness, double-sided) rather than boxes with real
depth. Anything meant to be independently posable (wings, ears, tail
segments) gets its own dedicated bone (group) with a pivot at its natural
attachment point, not just a bare cube parented straight into an existing
body-part group -- so it can actually be animated (flap/twitch/sway) as its
own rotatable joint, matching how the rest of the rig is bone-per-part.
"""
import sys
import os as _os, sys as _sys
# The toolchain used to live in a scratch directory that was deleted.
# It lives here now; resolve siblings relative to this file, never a path.
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
_sys.path.insert(0, _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), _os.pardir, "office"))
from mc_to_hytale import rect_to_uv, add_free_cube, add_bone_group, find_element, FACES
from PIL import Image

def _dominant_rgb(img):
    px = [p[:3] for p in img.getdata() if p[3] > 10]
    return max(set(px), key=px.count) if px else (128, 128, 128)

FLAT = 0.05  # near-zero thickness for a "flat plane" box, avoids z-fighting at true 0

def add_square_halo(data, im, packer, name="Halo", inner_gap=4):
    """Mavrine/Porcelle: a flat hollow square-ring plane floating above the hair."""
    ring_box = (40, 0, 48, 8)
    ring_crop = im.crop(ring_box)
    packer.clear_source(ring_box)  # ring now lives on its own object only
    off = packer.add(ring_crop)
    top_uv = rect_to_uv(off[0], off[1], off[0] + 8, off[1] + 8, "up")
    head = find_element(data, "Head")
    y0 = head["to"][1] + inner_gap
    # Own bone so the ring can hover/tilt independently of the head.
    add_bone_group(data, f"{name}-Bone", origin=[0, y0, -1], parent_group_name="Head")
    add_free_cube(
        data, name,
        frm=[-15, y0, -15], to=[15, y0, 13], origin=[0, y0, -1],
        faces_uv={"up": top_uv, "down": top_uv},
        tex_index=0, parent_group_name=f"{name}-Bone", double_sided=True,
    )

def add_ear_pair(data, im, packer, region_left_box, region_right_box,
                  ear_size=(4, 6), head_top_y=None, spread_x=8, forward_z=-3, tex_name="Ears"):
    """Two flat, twitchable ears -- each its own bone, pivoted at the base
    where it meets the head, not a bare cube."""
    left_crop = im.crop(region_left_box)
    right_crop = im.crop(region_right_box)
    lw, lh = left_crop.size
    rw, rh = right_crop.size
    packer.clear_source(region_left_box)
    packer.clear_source(region_right_box)
    l_off = packer.add(left_crop)
    r_off = packer.add(right_crop)
    head = find_element(data, "Head")
    top_y = head_top_y if head_top_y is not None else head["to"][1]
    w, h = ear_size
    l_uv = rect_to_uv(l_off[0], l_off[1], l_off[0] + lw, l_off[1] + lh, "north")
    r_uv = rect_to_uv(r_off[0], r_off[1], r_off[0] + rw, r_off[1] + rh, "north")

    add_bone_group(data, "L-Ear-Bone", origin=[-spread_x, top_y - 1, forward_z], parent_group_name="Head")
    add_free_cube(
        data, "L-Ear",
        frm=[-spread_x - w / 2, top_y - 1, forward_z - FLAT / 2], to=[-spread_x + w / 2, top_y - 1 + h, forward_z + FLAT / 2],
        origin=[-spread_x, top_y - 1, forward_z],
        faces_uv={"north": l_uv, "south": l_uv},
        tex_index=0, parent_group_name="L-Ear-Bone", double_sided=True,
    )
    add_bone_group(data, "R-Ear-Bone", origin=[spread_x, top_y - 1, forward_z], parent_group_name="Head")
    add_free_cube(
        data, "R-Ear",
        frm=[spread_x - w / 2, top_y - 1, forward_z - FLAT / 2], to=[spread_x + w / 2, top_y - 1 + h, forward_z + FLAT / 2],
        origin=[spread_x, top_y - 1, forward_z],
        faces_uv={"north": r_uv, "south": r_uv},
        tex_index=0, parent_group_name="R-Ear-Bone", double_sided=True,
    )

def add_asymmetric_ear_pair(data, im, packer, l_box, r_box, l_size, r_size, l_pos, r_pos, tex_name="Ears"):
    """Like add_ear_pair but each ear gets its own independent size/position
    (e.g. Verrine's one-upright-one-folded canine ears)."""
    l_crop = im.crop(l_box)
    r_crop = im.crop(r_box)
    # Rule: art promoted to its own object is removed from the skin. No-ops
    # safely when the source is a base-layer region, which must stay opaque.
    packer.clear_source(l_box)
    packer.clear_source(r_box)
    l_off = packer.add(l_crop)
    r_off = packer.add(r_crop)
    l_uv = rect_to_uv(l_off[0], l_off[1], l_off[0] + l_crop.width, l_off[1] + l_crop.height, "north")
    r_uv = rect_to_uv(r_off[0], r_off[1], r_off[0] + r_crop.width, r_off[1] + r_crop.height, "north")
    lx, ly, lz = l_pos
    lw, lh = l_size
    rx, ry, rz = r_pos
    rw, rh = r_size

    add_bone_group(data, "L-Ear-Bone", origin=[lx, ly, lz], parent_group_name="Head")
    add_free_cube(
        data, "L-Ear",
        frm=[lx - lw / 2, ly, lz - FLAT / 2], to=[lx + lw / 2, ly + lh, lz + FLAT / 2],
        origin=[lx, ly, lz],
        faces_uv={"north": l_uv, "south": l_uv},
        tex_index=0, parent_group_name="L-Ear-Bone", double_sided=True,
    )
    add_bone_group(data, "R-Ear-Bone", origin=[rx, ry, rz], parent_group_name="Head")
    add_free_cube(
        data, "R-Ear",
        frm=[rx - rw / 2, ry, rz - FLAT / 2], to=[rx + rw / 2, ry + rh, rz + FLAT / 2],
        origin=[rx, ry, rz],
        faces_uv={"north": r_uv, "south": r_uv},
        tex_index=0, parent_group_name="R-Ear-Bone", double_sided=True,
    )

def add_lower_back_tail(data, im, packer, region_box, segments=4, tex_name="Tail",
                         base_y=45, curl=True, length=28, size=5):
    """Curved, segmented tail from the lower back -- each segment is its own
    flat plane AND its own bone, chained parent-to-child, so the whole tail
    sways/curls as a joint chain rather than one rigid lump.

    The planes face SIDEWAYS (normal along X), so the tail reads in profile
    the way a tail is actually seen. Facing them front/back instead made the
    tail vanish into a hairline sliver from any side view."""
    crop = im.crop(region_box)
    off = packer.add(crop)
    uv = rect_to_uv(off[0], off[1], off[0] + crop.width, off[1] + crop.height, "east")
    seg_len = length / segments
    z = 9.0
    y = base_y
    parent = "Pelvis"
    for i in range(segments):
        s = size * (1.0 - 0.15 * i)          # profile depth, tapering to the tip
        bone_name = f"Tail-{i+1}-Bone"
        add_bone_group(data, bone_name, origin=[0, y, z], parent_group_name=parent)
        add_free_cube(
            data, f"Tail-{i+1}",
            frm=[-FLAT / 2, y - seg_len, z], to=[FLAT / 2, y, z + s],
            origin=[0, y, z],
            faces_uv={"east": uv, "west": uv},
            tex_index=0, parent_group_name=bone_name, double_sided=True,
        )
        # Advance so each segment STARTS inside the previous one. Stepping by a
        # curl amount independent of the segment's own depth let the taper
        # outrun the geometry and the tail broke into floating chunks.
        y -= seg_len * 0.8
        z += s * (0.7 if curl else 0.9)
        parent = bone_name

def _extract_art(im, region, face, palette, clothing_palette=None):
    """Pulls the character-colored art out of one skin region, without
    requiring it to touch the top edge -- tails and gills start partway into
    their region, unlike hair hanging from the head.

    `palette=None` keeps every opaque pixel instead of colour-matching, for
    art that isn't hair-toned (wings, plates)."""
    from mc_to_hytale import REGIONS, extract_hair_mask
    x, y, w, h = REGIONS[region][face]
    box = (x, y, x + w, y + h)
    if palette is None:
        crop = im.crop(box).convert("RGBA")
        found = any(p[3] > 10 for p in crop.getdata())
        return found, crop, box
    found, mask = extract_hair_mask(im, box, palette,
                                    clothing_palette=clothing_palette,
                                    require_top_connection=False)
    return found, mask, box

def _repaint_matching_on_base(packer, im, region, face, art, tol=20):
    """Repaint, on the BASE layer, any pixel whose colour matches `art`.

    Used when a promoted piece is drawn into both skin layers: the overlay
    copy can simply be cleared, but a base region must stay opaque, so the
    duplicate is painted over with the surrounding garment instead."""
    from mc_to_hytale import REGIONS, patch_region_with_mask, dominant_color, color_dist
    base_im = getattr(packer, "base_im", None)
    if base_im is None:
        return 0
    palette = {p[:3] for p in art.getdata() if p[3] > 10}
    if not palette:
        return 0
    x, y, w, h = REGIONS[region][face]
    box = (x, y, x + w, y + h)
    mask = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    mpx, n = mask.load(), 0
    src = base_im.load()
    for j in range(h):
        for i in range(w):
            p = src[x + i, y + j]
            if p[3] > 10 and any(color_dist(p[:3], c) <= tol for c in palette):
                mpx[i, j] = p
                n += 1
    if n:
        patch_region_with_mask(base_im, box, mask, dominant_color(im, box),
                               prefer_palette=getattr(packer, "clothing_palette", None))
    return n

def add_source_wings(data, im, packer, span=22, height=30):
    """Xivvy's wings, taken from the wing art actually painted into the body
    overlay's back rather than a flat colour swatch. The art is a symmetric
    pair, so it is split down the middle and each half drives its own boned
    plane; the source is cleared so the jacket shell stops redrawing it."""
    from mc_to_hytale import (rect_to_uv, add_free_cube, add_bone_group, find_element)
    found, art, box = _extract_art(im, "body_overlay", "back", None)
    if not found:
        return False
    packer.clear_source(box)
    # The wing shape is painted into BOTH layers -- the overlay copy (cleared
    # above) and an identical copy on the body's base back. The base layer has
    # to stay opaque, so that copy is repainted with the jacket around it
    # instead of erased; otherwise the wings stay printed on her back.
    _repaint_matching_on_base(packer, im, "body_base", "back", art)
    w, h = art.size
    halves = {"L": art.crop((0, 0, w // 2, h)), "R": art.crop((w // 2, 0, w, h))}
    # Trim each half to its opaque bounding box. Mapping the full 4x12 source
    # half wasted ~40% of the plane on empty rows, so the visible wing only
    # filled part of its geometry and read as stubby.
    halves = {k: (v.crop(v.getbbox()) if v.getbbox() else v) for k, v in halves.items()}
    art_w, art_h = next(iter(halves.values())).size
    # Keep the plane's aspect equal to the art's, so the wing is not squashed.
    height = span * (art_h / art_w) if art_w else height
    chest = find_element(data, "Chest")
    mount_y = 49.0          # low on the back, around the Y45-53 band
    mount_z = chest["to"][2] + 1.0
    # Root the wings partway in from the torso's edge, toward the spine. Fully
    # outboard at the edge left a visible gap between body and wing, so they
    # read as two detached slabs floating either side of her.
    edge_x = chest["to"][0] * 0.45
    for side, img in halves.items():
        off = packer.add(img)
        uv = rect_to_uv(off[0], off[1], off[0] + img.width, off[1] + img.height, "south")
        sign = 1 if side == "R" else -1
        inner = edge_x * sign
        xs = sorted([inner, inner + span * sign])
        bone = f"{side}-Wing-Bone"
        add_bone_group(data, bone, origin=[inner, mount_y, mount_z], parent_group_name="Chest")
        add_free_cube(
            data, f"{side}-Wing",
            frm=[xs[0], mount_y - height / 2, mount_z],
            to=[xs[1], mount_y + height / 2, mount_z + FLAT],
            origin=[inner, mount_y, mount_z],
            faces_uv={"south": uv, "north": uv},
            tex_index=0, parent_group_name=bone, double_sided=True,
        )
    return True

def add_source_tail(data, im, packer, name="Tail"):
    """ONE boned plane carrying the tail exactly as it is drawn in the skin.

    These characters already have their tail painted into the body's back
    art (Ilyra's doc calls out "the source's readable curled S-shape"), so
    the tail is extracted from that art rather than approximated with a
    procedural chain of segments -- which is what produced the disconnected
    look. The source pixels are cleared so the shape isn't also left flat on
    the shirt behind the new object."""
    from mc_to_hytale import (build_hair_palette, build_clothing_palette,
                              rect_to_uv, add_free_cube, add_bone_group, find_element)
    palette = build_hair_palette(im)
    if not palette:
        return False
    clothing = build_clothing_palette(im, hair_palette=palette)
    for region in ("body_overlay", "body_base"):
        found, mask, box = _extract_art(im, region, "back", palette,
                                        None if region == "body_overlay" else clothing)
        if not found:
            continue
        if region == "body_overlay":
            packer.clear_source(box)          # overlay may be transparent -- safe to erase
        off = packer.add(mask)
        uv = rect_to_uv(off[0], off[1], off[0] + mask.width, off[1] + mask.height, "south")
        chest = find_element(data, "Chest")
        back_z = chest["to"][2] + 1.0
        top_y, bot_y = 90.0, 45.0             # the torso rows this art maps to
        add_bone_group(data, f"{name}-Bone", origin=[0, top_y, back_z], parent_group_name="Pelvis")
        add_free_cube(
            data, name,
            frm=[-14, bot_y, back_z], to=[14, top_y, back_z + FLAT],
            origin=[0, top_y, back_z],
            faces_uv={"south": uv, "north": uv},
            tex_index=0, parent_group_name=f"{name}-Bone", double_sided=True,
        )
        return True
    return False

def add_source_gills(data, im, packer):
    """Gill fronds taken straight from the head's side art -- one boned plane
    per side -- instead of six invented plates. The art lives in the head
    overlay's left/right faces, so it is cleared from there to stop the side
    hair planes redrawing it."""
    from mc_to_hytale import (build_hair_palette, rect_to_uv, add_free_cube,
                              add_bone_group, find_element)
    palette = build_hair_palette(im)
    if not palette:
        return False
    head = find_element(data, "Head")
    made = False
    for side, face, x_at in (("R", "right", head["to"][0]), ("L", "left", head["from"][0])):
        found, mask, box = _extract_art(im, "head_overlay", face, palette)
        if not found:
            continue
        packer.clear_source(box)
        off = packer.add(mask)
        uv_face = "east" if side == "R" else "west"
        uv = rect_to_uv(off[0], off[1], off[0] + mask.width, off[1] + mask.height, uv_face)
        x0 = x_at if side == "R" else x_at - FLAT
        name = f"{side}-Gills"
        pivot = [x_at, head["to"][1] - 6, 0]
        add_bone_group(data, f"{name}-Bone", origin=pivot, parent_group_name="Head")
        add_free_cube(
            data, name,
            frm=[x0, head["from"][1], head["from"][2]],
            to=[x0 + FLAT, head["to"][1], head["to"][2]],
            origin=pivot,
            faces_uv={uv_face: uv, ("west" if side == "R" else "east"): uv},
            tex_index=0, parent_group_name=f"{name}-Bone", double_sided=True,
        )
        made = True
    return made

def add_orbiting_stars(data, im, packer, star_box, count=2, tex_name="Stars", radius=20, base_y=125,
                        clear_boxes=()):
    crop = im.crop(star_box)
    # Star pixels scattered through the hair overlay are now real drone
    # objects, so erase them from the overlay art they were lifted from.
    for b in clear_boxes:
        packer.clear_source(b)
    off = packer.add(crop)
    uv = rect_to_uv(off[0], off[1], off[0] + crop.width, off[1] + crop.height, "north")
    import math
    for i in range(count):
        ang = (2 * math.pi / count) * i + 0.6
        x = radius * math.cos(ang)
        z = radius * math.sin(ang) - 1
        # Each drone gets its own bone pivoted at the head's center, so
        # rotating the bone carries the star around its orbit.
        bone = f"Star-{i+1}-Bone"
        add_bone_group(data, bone, origin=[0, base_y, -1], parent_group_name="Head")
        add_free_cube(
            data, f"Star-{i+1}",
            frm=[x - 2, base_y - 2, z - FLAT / 2], to=[x + 2, base_y + 2, z + FLAT / 2],
            origin=[x, base_y, z],
            faces_uv={"north": uv, "south": uv},
            tex_index=0, parent_group_name=bone, double_sided=True,
        )

def add_side_disc_glyph(data, im, packer, glyph_box, side="east", tex_name="Glyph", size=8, offset_z=0):
    """Solyth's sun / Nyxie's moon: a flat, flush-mounted disc on ONE side of
    the head only."""
    crop = im.crop(glyph_box)
    packer.clear_source(glyph_box)  # glyph is its own plate now, not painted on the head
    off = packer.add(crop)
    uv = rect_to_uv(off[0], off[1], off[0] + crop.width, off[1] + crop.height, side)
    head = find_element(data, "Head")
    x_face = head["to"][0] if side == "east" else head["from"][0]
    if side == "east":
        frm = [x_face, 100, offset_z - size / 2]
        to = [x_face + FLAT, 100 + size, offset_z + size / 2]
    else:
        frm = [x_face - FLAT, 100, offset_z - size / 2]
        to = [x_face, 100 + size, offset_z + size / 2]
    pivot = [(frm[0] + to[0]) / 2, 100 + size / 2, offset_z]
    add_bone_group(data, f"{tex_name}-Bone", origin=pivot, parent_group_name="Head")
    add_free_cube(
        data, tex_name,
        frm=frm, to=to, origin=pivot,
        faces_uv={side: uv, ("west" if side == "east" else "east"): uv},
        tex_index=0, parent_group_name=f"{tex_name}-Bone", double_sided=True,
    )

def add_back_wings(data, im, packer, wing_box, tex_name="Wings", span=22, height=20):
    """Xivvy: fairy wings as separate UPPER and LOWER blade panels per side
    (four panels total), not one full slab each -- matching the design doc's
    'articulated violet blade panels' and its 'blade order' invariant.

    Each side gets a root bone at the shoulder-blade hinge; the upper panel
    hangs off that root and the lower panel off its own child bone, so the
    whole wing can flap while the lower blade still articulates separately."""
    # NOTE: the wings are an invented conversion feature -- the source skin has
    # no wing art. Earlier this sampled the body-overlay back region, but that
    # is the character's jacket: the wings then wore her jacket art AND the
    # jacket lost it, so the torso overlay shells read as duplicate wings.
    # Now the panels get their own swatch from the costume's own color and
    # nothing is cleared, leaving the jacket intact.
    base = im.crop(wing_box)
    tone = _dominant_rgb(base)
    crop = Image.new("RGBA", (8, 12), tone + (255,))
    cw, ch = crop.size
    upper_crop = crop.crop((0, 0, cw, ch // 2))
    lower_crop = crop.crop((0, ch // 2, cw, ch))
    up_off = packer.add(upper_crop)
    lo_off = packer.add(lower_crop)
    up_uv = rect_to_uv(up_off[0], up_off[1], up_off[0] + upper_crop.width, up_off[1] + upper_crop.height, "south")
    lo_uv = rect_to_uv(lo_off[0], lo_off[1], lo_off[0] + lower_crop.width, lo_off[1] + lower_crop.height, "south")

    chest = find_element(data, "Chest")
    mount_y = (chest["from"][1] + chest["to"][1]) / 2 + 5
    mount_z = chest["to"][2] - 1
    upper_h = height * 0.55   # forewing: longer reach, sits higher
    lower_h = height * 0.45   # hindwing: shorter, tucked below
    upper_span = span
    lower_span = span * 0.75

    for side, sign in (("R", 1), ("L", -1)):
        root = f"{side}-Wing-Bone"
        inner = 0.5 * sign
        add_bone_group(data, root, origin=[inner, mount_y, mount_z], parent_group_name="Chest")
        ux = [inner, inner + upper_span * sign]
        add_free_cube(
            data, f"{side}-Wing-Upper",
            frm=[min(ux), mount_y, mount_z - FLAT / 2],
            to=[max(ux), mount_y + upper_h, mount_z + FLAT / 2],
            origin=[inner, mount_y, mount_z],
            faces_uv={"south": up_uv, "north": up_uv},
            tex_index=0, parent_group_name=root, double_sided=True,
        )
        lower_bone = f"{side}-Wing-Lower-Bone"
        add_bone_group(data, lower_bone, origin=[inner, mount_y, mount_z], parent_group_name=root)
        lx = [inner, inner + lower_span * sign]
        add_free_cube(
            data, f"{side}-Wing-Lower",
            frm=[min(lx), mount_y - lower_h, mount_z - FLAT / 2],
            to=[max(lx), mount_y, mount_z + FLAT / 2],
            origin=[inner, mount_y, mount_z],
            faces_uv={"south": lo_uv, "north": lo_uv},
            tex_index=0, parent_group_name=lower_bone, double_sided=True,
        )

def detect_garment_band(im, tol=45):
    """How many texture rows at the TOP of the legs are covered by the lower
    garment (skirt/shorts) rather than bare leg. Returns the row count."""
    from mc_to_hytale import REGIONS, color_dist
    lx, ly, lw, lh = REGIONS["r_leg_base"]["front"]
    rows = []
    for r in range(lh):
        row = [im.getpixel((lx + i, ly + r))[:3] for i in range(lw)]
        rows.append(max(set(row), key=row.count))
    top = rows[0]
    band = 0
    for r in rows:
        if color_dist(r, top) <= tol:
            band += 1
        else:
            break
    return band

def _stack_bands(im, body_face, leg_faces, band_rows):
    """Skirt art = the torso's lower band (hip) stacked on top of the legs'
    garment band (the part that hangs past the hip), so the real painted
    pattern carries straight through the seam."""
    from mc_to_hytale import REGIONS
    bx, by, bw, bh = REGIONS["body_base"][body_face]
    hip = im.crop((bx, by + 9, bx + bw, by + bh))          # bottom 3 rows of torso
    legs = []
    for reg in leg_faces:
        lx, ly, lw, lh = REGIONS[reg][body_face]
        legs.append(im.crop((lx, ly, lx + lw, ly + min(band_rows, lh))))
    total_w = sum(c.width for c in legs) or hip.width
    leg_strip = Image.new("RGBA", (total_w, legs[0].height if legs else 0), (0, 0, 0, 0))
    x = 0
    for c in legs:
        leg_strip.paste(c, (x, 0))
        x += c.width
    if hip.width != total_w:
        hip = hip.resize((total_w, hip.height), Image.NEAREST)
    out = Image.new("RGBA", (total_w, hip.height + leg_strip.height), (0, 0, 0, 0))
    out.paste(hip, (0, 0))
    out.paste(leg_strip, (0, hip.height))
    return out

SKIRT_THICKNESS = 2.0  # skirt panels get real cloth thickness, unlike the
                       # zero-thickness cosmetic planes (ears/wings/hair)

def add_skirt(data, im, packer, band_rows=None, flare_deg=5, waist_y=None, tex_name="Skirt",
              thickness=SKIRT_THICKNESS):
    """A flared skirt built from four flat panels hanging off the pelvis, on
    its own bone so it can sway. The hem's depth comes from how far the
    garment actually extends down the legs in the source art, and each panel
    is textured from that same painted band (hip rows + leg rows stacked),
    so the skirt matches the art it replaces instead of being invented."""
    from mc_to_hytale import REGIONS, TORSO_CUBE_Y
    if band_rows is None:
        band_rows = detect_garment_band(im)
    if band_rows <= 0:
        return False
    if waist_y is None:
        # Hang from the top of the pelvis -- the rig's actual waistline, which
        # is where the belt sits. Starting lower left a visible gap between the
        # belt and the skirt's top edge.
        waist_y = float(TORSO_CUBE_Y["Pelvis"][1])

    # Leg texture rows -> world units: the 12-row leg region spans y 49..5.
    units_per_row = (49.0 - 5.0) / 12.0
    hem_y = 49.0 - band_rows * units_per_row
    height = waist_y - hem_y

    # Character-left is -X. For the front (north) face texture-x runs left to
    # right as -X to +X, so the left leg's strip comes first; the back face
    # reads mirrored, so its order flips.
    panels = {
        "north": (_stack_bands(im, "front", ["l_leg_base", "r_leg_base"], band_rows), "north"),
        "south": (_stack_bands(im, "back", ["r_leg_base", "l_leg_base"], band_rows), "south"),
        "east":  (_stack_bands(im, "right", ["r_leg_base"], band_rows), "east"),
        "west":  (_stack_bands(im, "left", ["l_leg_base"], band_rows), "west"),
    }
    # The side faces are only 4px of source art against the front/back's 8px,
    # so stretched over a panel of similar world size they rendered at half
    # the pixel density and visibly failed to match. Normalise every panel to
    # the widest one (nearest-neighbour, so the pixel art stays crisp) and the
    # banding then lines up all the way around the skirt.
    target_w = max(img.width for img, _ in panels.values())
    target_h = max(img.height for img, _ in panels.values())
    panels = {
        face: (img.resize((target_w, target_h), Image.NEAREST) if img.size != (target_w, target_h) else img, uvf)
        for face, (img, uvf) in panels.items()
    }

    add_bone_group(data, "Skirt-Bone", origin=[0, waist_y, 0], parent_group_name="Pelvis")

    # Waist half-extents, set so the panel's OUTER surface (half + thickness)
    # lands flush with the pelvis (13 x 9) instead of standing proud of it.
    half_x, half_z = 13.0 - thickness, 9.0 - thickness
    t = thickness
    # Each panel pivots about ITS OWN top edge, not a shared center point.
    # Rotating everything around one origin swung the panels apart and opened
    # tall wedge gaps at the corners; pivoting on its own top edge keeps the
    # waist ring closed and only spreads the hems. The front/back panels are
    # also widened past the side panels (and the side panels run the full
    # depth) so the corners overlap instead of butting together.
    specs = {
        # face: (frm, to, rotation, origin)
        "north": ([-half_x - t, hem_y, -half_z - t], [half_x + t, waist_y, -half_z],
                  [flare_deg, 0, 0], [0, waist_y, -half_z]),
        "south": ([-half_x - t, hem_y, half_z], [half_x + t, waist_y, half_z + t],
                  [-flare_deg, 0, 0], [0, waist_y, half_z]),
        "east":  ([half_x, hem_y, -half_z - t], [half_x + t, waist_y, half_z + t],
                  [0, 0, flare_deg], [half_x, waist_y, 0]),
        "west":  ([-half_x - t, hem_y, -half_z - t], [-half_x, waist_y, half_z + t],
                  [0, 0, -flare_deg], [-half_x, waist_y, 0]),
    }
    OPPOSITE = {"north": "south", "south": "north", "east": "west",
                "west": "east", "up": "down", "down": "up"}
    for face, (img, uv_face) in panels.items():
        off = packer.add(img)
        ox, oy = off
        w, h = img.width, img.height
        uv = rect_to_uv(ox, oy, ox + w, oy + h, uv_face)
        # Every face samples the real garment art, including the cut edges the
        # thickness exposes: the top edge takes the waistband row so it blends
        # into the torso above it (a flat averaged swatch there read as an
        # obviously wrong solid cap), the bottom edge takes the hem row, and
        # the vertical edges take the art's outermost columns.
        top_row    = lambda f: rect_to_uv(ox, oy, ox + w, oy + 1, f)
        bottom_row = lambda f: rect_to_uv(ox, oy + h - 1, ox + w, oy + h, f)
        left_col   = lambda f: rect_to_uv(ox, oy, ox + 1, oy + h, f)
        right_col  = lambda f: rect_to_uv(ox + w - 1, oy, ox + w, oy + h, f)
        faces_uv = {uv_face: uv, OPPOSITE[uv_face]: uv}
        for edge in FACES:
            if edge in faces_uv:
                continue
            if edge == "up":
                faces_uv[edge] = top_row(edge)
            elif edge == "down":
                faces_uv[edge] = bottom_row(edge)
            elif edge in ("west", "north"):
                faces_uv[edge] = left_col(edge)
            else:
                faces_uv[edge] = right_col(edge)
        frm, to, rot, origin = specs[face]
        add_free_cube(
            data, f"Skirt-{face.capitalize()}",
            frm=frm, to=to, origin=origin,
            faces_uv=faces_uv,
            tex_index=0, parent_group_name="Skirt-Bone",
            double_sided=True, rotation=rot,
        )
    return True

def add_gill_plates(data, im, packer, gill_box_left, gill_box_right, count_per_side=3, tex_name="Gills", spread_z=6):
    """Flat gill plates/fins -- each one its own small bone so they can fan
    out or twitch independently, matching the design docs calling them
    'articulated' plates."""
    left_crop = im.crop(gill_box_left)
    right_crop = im.crop(gill_box_right)
    lw, lh = left_crop.size
    rw, rh = right_crop.size
    l_off = packer.add(left_crop)
    r_off = packer.add(right_crop)
    l_uv = rect_to_uv(l_off[0], l_off[1], l_off[0] + lw, l_off[1] + lh, "west")
    r_uv = rect_to_uv(r_off[0], r_off[1], r_off[0] + rw, r_off[1] + rh, "east")
    head = find_element(data, "Head")
    for i in range(count_per_side):
        z = head["from"][2] + 3 + i * spread_z * (14 / max(count_per_side, 1))
        y = 100 - i * 2
        # Flat fins, like every other cosmetic appendage -- each on its own
        # bone so the six plates can fan independently.
        l_bone = f"L-Gill-{i+1}-Bone"
        lx = head["from"][0]
        add_bone_group(data, l_bone, origin=[lx, y, z + 2.5], parent_group_name="Head")
        add_free_cube(
            data, f"L-Gill-{i+1}",
            frm=[lx - 4, y - 3, z + 2.5 - FLAT / 2], to=[lx, y + 3, z + 2.5 + FLAT / 2],
            origin=[lx, y, z + 2.5],
            faces_uv={"north": l_uv, "south": l_uv},
            tex_index=0, parent_group_name=l_bone, double_sided=True,
        )
        r_bone = f"R-Gill-{i+1}-Bone"
        rx = head["to"][0]
        add_bone_group(data, r_bone, origin=[rx, y, z + 2.5], parent_group_name="Head")
        add_free_cube(
            data, f"R-Gill-{i+1}",
            frm=[rx, y - 3, z + 2.5 - FLAT / 2], to=[rx + 4, y + 3, z + 2.5 + FLAT / 2],
            origin=[rx, y, z + 2.5],
            faces_uv={"north": r_uv, "south": r_uv},
            tex_index=0, parent_group_name=r_bone, double_sided=True,
        )
