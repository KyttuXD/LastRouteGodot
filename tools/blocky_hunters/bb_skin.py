"""Vanilla Minecraft (Alex, 64x64) skin layout: box-UV helpers, the 8x8 expression cells, and
the Hytale-rig cube split of a skin box (upper arm / forearm / hand, thigh / calf / foot,
chest / belly) so the texture stays an ordinary, editable skin.

Skin canvas is 64x128: rows 0-63 are the skin, row 64+ holds the expression cells."""
from PIL import Image
from bb_core import Cube

U = 1.78 / 32.0                      # metres per skin pixel: vanilla 32 px = 1.78 m
CANVAS = (64, 128)
FACE_AT = (0, 64)                    # 3x2 grid of 8x8 expression cells


def m(v):
    return v * U


def box_rects(ou, ov, w, h, d):
    """Standard box-UV face rects for a w x h x d box with origin (ou, ov)."""
    return {"E": (ou, ov + d, d, h), "N": (ou + d, ov + d, w, h), "W": (ou + d + w, ov + d, d, h),
            "S": (ou + 2 * d + w, ov + d, w, h), "U": (ou + d, ov, w, d), "D": (ou + d + w, ov, w, d)}


def segment_rects(ou, ov, w, h, d, r0, r1):
    """Rects of rows r0..r1 (from the top) of a skin box, caps only where the segment ends the box."""
    full = box_rects(ou, ov, w, h, d)
    out = {}
    for f in "ENWS":
        x, y, ww, hh = full[f]
        out[f] = (x, y + r0, ww, r1 - r0)
    out["U"] = full["U"]
    out["D"] = full["D"]
    return out


class Part:
    """One skin box: origin, size, world placement; builds its segment cubes."""
    def __init__(self, ou, ov, w, h, d, cx, ytop, zc=0.0):
        self.ou, self.ov, self.w, self.h, self.d, self.cx, self.ytop, self.zc = ou, ov, w, h, d, cx, ytop, zc

    def seg(self, name, bone, r0, r1, grow=0.0, ygrow=True, caps=True, **kw):
        w, d = self.w + 2 * grow, self.d + 2 * grow
        gy = grow if ygrow else 0.0
        y1, y0 = self.ytop - r0 + (gy if r0 == 0 else 0), self.ytop - r1 - (gy if r1 == self.h else 0)
        rects = segment_rects(self.ou, self.ov, self.w, self.h, self.d, r0, r1)
        faces = "ENWS" + (("U" if r0 == 0 else "") + ("D" if r1 == self.h else "") if caps else "")
        lo = (m(self.cx - w / 2), m(y0), m(self.zc - d / 2))
        hi = (m(self.cx + w / 2), m(y1), m(self.zc + d / 2))
        return Cube(name, bone, lo, hi, faces=faces, uv={f: rects[f] for f in faces}, **kw)


# Joint plugs. Rigid cubes open a wedge at the outer side of a bend (depth/2 * sin(bend) px). Each joint gets a
# plug: a thin, inset box that rides on the child bone and reaches PLUG_EXT skin px across the joint plane into the
# neighbouring segment, textured with that neighbour's nearest texel row. It is hidden when the limb is straight
# and fills the wedge (in the neighbour's own colour) when bent. Sized for bends up to about 60 degrees; the deep
# crouch clip can still open a sliver (check_gaps.py reports it).
PLUG_EXT = {"L-Thigh": 1.8, "R-Thigh": 1.8, "L-Calf": 1.8, "R-Calf": 1.8, "L-Foot": 2.0, "R-Foot": 2.0,
            "L-Forearm": 1.8, "R-Forearm": 1.8, "L-Hand": 1.3, "R-Hand": 1.3, "Belly": 0.6, "Chest": 0.7, "Head": 1.7}
PLUG_BOTTOM = ("Belly", "Chest", "Head")        # the others hang below their joint plane (plane = top of the cube)
PLUG_INSET = {"Head": 1.0}
PLUG_PARENT = {"L-Thigh": "belly", "R-Thigh": "belly", "L-Calf": "{S}-thigh", "R-Calf": "{S}-thigh",
               "L-Foot": "{S}-calf", "R-Foot": "{S}-calf", "L-Forearm": "{S}-arm", "R-Forearm": "{S}-arm",
               "L-Hand": "{S}-forearm", "R-Hand": "{S}-forearm", "Chest": "belly", "Head": "chest"}


def _layer(name):
    for suffix in ("-sleeve", "-pants"):
        if name.endswith(suffix):
            return suffix
    return "jacket-" if name.startswith("jacket-") else "hat" if name == "hat" else ""


def joint_plug(c, by_name):
    """Plug for the joint at the start of cube c (None when its bone has no stacked joint)."""
    ext = PLUG_EXT.get(c.bone)
    if ext is None or not c.uv or os.environ.get("BB_NO_PLUG"):
        return None
    inset = PLUG_INSET.get(c.bone, 0.03) * U
    bottom = c.bone in PLUG_BOTTOM
    plane = c.lo[1] if bottom else c.hi[1]
    side = c.bone[0]
    layer = _layer(c.name)
    pname = PLUG_PARENT.get(c.bone, "")
    parent = None
    if pname:
        core = pname.replace("{S}", side)
        if layer in ("-sleeve", "-pants") and core.startswith(side):
            core += layer                                   # same layer of the neighbouring limb segment
        elif layer == "-pants" and core == "belly":
            core = "jacket-belly"
        elif layer == "jacket-":
            core = "jacket-" + core
        elif layer == "hat":
            core = "jacket-chest"
        elif layer == "-sleeve" and not core.startswith(side):
            core = ""
        parent = by_name.get(core)
    src, row_last = (parent, not bottom) if parent is not None and parent.uv else (c, bottom)
    if bottom:                                             # reaches down into the neighbour below, a hair into the child
        y0, y1 = plane - ext * U, plane + 0.05 * U
    else:                                                  # reaches up into the neighbour above, a hair into the child
        y0, y1 = plane - 0.05 * U, plane + ext * U
    uv = {}
    for f in "ENWS":
        x, y, w, h = src.uv[f]
        uv[f] = (x, y + h - 1, w, 1) if row_last else (x, y, w, 1)
    return Cube(c.name + "-plug", c.bone, (c.lo[0] + inset, y0, c.lo[2] + inset), (c.hi[0] - inset, y1, c.hi[2] - inset),
                faces="ENWS", uv=uv)


def vanilla_cubes(overlays=True):
    """Alex proportions: head 8^3, body 8x12x4, arms 3x12x4, legs 4x12x4 (skin px), rig-split.
    overlays=True adds the skin's second layer (hat, jacket, sleeves, pants) as slightly larger cubes on the
    same bones, exactly as Blockbench's skin model shows it; transparent texels are cut out (alpha mask)."""
    c = []
    head = Part(0, 0, 8, 8, 8, 0, 32)
    c.append(head.seg("head", "Head", 0, 8))
    body = Part(16, 16, 8, 12, 4, 0, 24)
    c += [body.seg("chest", "Chest", 0, 6), body.seg("belly", "Belly", 6, 12)]
    # character's right = +X (MC right limbs at +X), left = -X
    arms = {"R": Part(40, 16, 3, 12, 4, 5.5, 24), "L": Part(32, 48, 3, 12, 4, -5.5, 24)}
    legs = {"R": Part(0, 16, 4, 12, 4, 2.0, 12), "L": Part(16, 48, 4, 12, 4, -2.0, 12)}
    arm_rows = (("arm", "Arm", 0, 6), ("forearm", "Forearm", 6, 10), ("hand", "Hand", 10, 12))
    leg_rows = (("thigh", "Thigh", 0, 6), ("calf", "Calf", 6, 10), ("foot", "Foot", 10, 12))
    for s, a in arms.items():
        c += [a.seg(f"{s}-{n}", f"{s}-{b}", r0, r1) for n, b, r0, r1 in arm_rows]
    for s, l in legs.items():
        c += [l.seg(f"{s}-{n}", f"{s}-{b}", r0, r1) for n, b, r0, r1 in leg_rows]
    if overlays:
        c.append(Part(32, 0, 8, 8, 8, 0, 32).seg("hat", "Head", 0, 8, grow=0.5))
        jacket = Part(16, 32, 8, 12, 4, 0, 24)
        c += [jacket.seg("jacket-chest", "Chest", 0, 6, grow=0.25), jacket.seg("jacket-belly", "Belly", 6, 12, grow=0.25)]
        sleeves = {"R": Part(40, 32, 3, 12, 4, 5.5, 24), "L": Part(48, 48, 3, 12, 4, -5.5, 24)}
        pants = {"R": Part(0, 32, 4, 12, 4, 2.0, 12), "L": Part(0, 48, 4, 12, 4, -2.0, 12)}
        for s, a in sleeves.items():
            c += [a.seg(f"{s}-{n}-sleeve", f"{s}-{b}", r0, r1, grow=0.25) for n, b, r0, r1 in arm_rows]
        for s, l in pants.items():
            c += [l.seg(f"{s}-{n}-pants", f"{s}-{b}", r0, r1, grow=0.25, ygrow=False, caps=False) for n, b, r0, r1 in leg_rows]
    by_name = {x.name: x for x in c}
    c += [pl for pl in (joint_plug(x, by_name) for x in list(c)) if pl is not None]
    c.append(Cube("face", "Head", (m(-4), m(24), m(-4.02)), (m(4), m(32), m(-4.02)), faces="N", group="face"))
    return c


VANILLA_SK = dict(hip_y=12, hip_x=2.0, thigh_y=12, knee_y=6, ankle_y=2, belly_y=12, chest_y=18,
                  neck_y=24, sh_x=5.5, sh_y=22, elbow_y=18, wrist_y=14)


def vanilla_sk(**over):
    d = dict(VANILLA_SK)
    d.update(over)
    return {k: m(v) for k, v in d.items()}


# ---- painting a skin ---------------------------------------------------------

def fill(img, x, y, w, h, c):
    for j in range(y, y + h):
        for i in range(x, x + w):
            img.putpixel((i, j), (*c[:3], c[3] if len(c) > 3 else 255))


def paint_box(img, ou, ov, w, h, d, fn):
    """fn(face, i, j, W, H) -> colour|None for every texel of the box's six face rects."""
    for f, (x, y, ww, hh) in box_rects(ou, ov, w, h, d).items():
        for j in range(hh):
            for i in range(ww):
                c = fn(f, i, j, ww, hh)
                if c is not None:
                    img.putpixel((x + i, y + j), (*c[:3], c[3] if len(c) > 3 else 255))


SKIN_BOXES = {   # name -> (ou, ov, w, h, d)
    "head": (0, 0, 8, 8, 8), "body": (16, 16, 8, 12, 4),
    "rarm": (40, 16, 3, 12, 4), "larm": (32, 48, 3, 12, 4),
    "rleg": (0, 16, 4, 12, 4), "lleg": (16, 48, 4, 12, 4),
}
HAT = (32, 0, 8, 8, 8)


# ---- 8x8 expression cells (row-major pixel lists) -------------------------------

def face8(k, st):
    """Expression cell k on an 8x8 head front: 0 neutral, 1 blink, 2 stun, 3 chase, 4 scream, 5 happy.
    st: skin, dark (lash), iris (dark/mid/light), brow, mouth, blush."""
    img = Image.new("RGBA", (8, 8), (*st["skin"], 255))

    def P(x, y, c):
        if 0 <= x < 8 and 0 <= y < 8:
            img.putpixel((x, y), (*c[:3], 255))
    d, (i0, i1, i2), brow, mouth, blush = st["dark"], st["iris"], st["brow"], st["mouth"], st["blush"]
    W = (255, 255, 255)
    for x0 in (1, 5):                                     # left / right eye, 2 px wide
        if k in (0, 4):                                   # neutral / scream: dark lash row + iris row w/ highlight
            P(x0, 4, d); P(x0 + 1, 4, d); P(x0, 5, i1); P(x0 + 1, 5, i2)
            P(x0 if x0 == 1 else x0 + 1, 5, W)
        elif k == 1:                                      # blink
            P(x0, 4, d); P(x0 + 1, 4, d)
        elif k == 2:                                      # stun: x eyes
            P(x0, 3, d); P(x0 + 1, 4, d); P(x0 + 1, 3, d); P(x0, 4, d)
        elif k == 3:                                      # chase: narrow glare
            P(x0, 4, d); P(x0 + 1, 4, d); P(x0, 5, i1); P(x0 + 1, 5, i2)
        else:                                             # happy: arcs
            P(x0, 4, d); P(x0 + 1, 3, d)
    brows = {3: [(1, 2), (2, 3), (6, 2), (5, 3)], 2: [(1, 1), (2, 1), (5, 1), (6, 1)]}.get(
        k, [(1, 3), (2, 3), (5, 3), (6, 3)])
    for x, y in brows:
        P(x, y, brow)
    mouths = {0: [(3, 6), (4, 6)], 1: [(3, 6), (4, 6)], 2: [(3, 6), (4, 6), (3, 7), (4, 7)],
              3: [(2, 6), (3, 6), (4, 6), (5, 6)], 4: [(3, 6), (4, 6), (3, 7), (4, 7)],
              5: [(2, 6), (3, 7), (4, 7), (5, 6)]}[k]
    for x, y in mouths:
        P(x, y, (70, 24, 34) if k == 4 else mouth)
    if k in (0, 1, 5):
        P(0, 5, blush); P(7, 5, blush)
    return img


# ---- shared skin painting helpers ------------------------------------------------

from bb_core import hash01  # noqa: E402

HEART6 = ["XX..XX", "XXXXXX", ".XXXX.", "..XX.."]


def clump(base, dark, light, seed, glints=.12):
    """Reference-style hair texel: checker clumps of two tones with sparse light glints."""
    def f(i, j, face=0):
        c = dark if (i + j + face) & 1 else base
        h = hash01(i, j, face, seed)
        return light if h < glints else c
    return f


def new_skin():
    return Image.new("RGBA", CANVAS, (0, 0, 0, 0))


def vanilla_kw(skin):
    return dict(skin=skin, face_cell=(8, 8), face_at=FACE_AT)


def eye_locators():
    return {"L": (m(-2.5), m(27.5), m(-4.1)), "R": (m(2.5), m(27.5), m(-4.1))}


# ---- hunters built straight from the supplied Minecraft skins ------------------------

import pathlib  # noqa: E402
import os  # noqa: E402

SKINS = pathlib.Path(__file__).resolve().parent / "skins"


def load_source(name):
    """The hunter's original Minecraft skin (64x64, Alex) copied into skins/ -> 64x128 canvas."""
    src = Image.open(SKINS / f"{name}_source.png").convert("RGBA")
    canvas = new_skin()
    canvas.paste(src, (0, 0))
    return canvas


def expressions_from_face(face):
    """13 expression cells (neutral, blink, stun, chase, scream, happy, derp x4 frames, blank, wink_right, wink_left) edited from the skin's own 8x8
    face: same hair frame, skin, eye and blush colours; only the eye/mouth pixels change."""
    skin, hair = face.getpixel((3, 4)), face.getpixel((0, 0))
    col, dark, blush = face.getpixel((1, 5)), face.getpixel((2, 5)), face.getpixel((1, 7))
    base = face.copy()
    for y in range(5, 7):                       # wipe the two eye rows (inner 6 columns)
        for x in range(1, 7):
            base.putpixel((x, y), skin)
    cells = []

    def make(pix, mouth=None):
        im = base.copy()
        for (x, y), c in pix.items():
            im.putpixel((x, y), c)
        for (x, y), c in (mouth or {}).items():
            im.putpixel((x, y), c)
        return im
    open_eyes = {(1, 5): col, (2, 5): dark, (5, 5): dark, (6, 5): col,
                 (1, 6): dark, (2, 6): col, (5, 6): col, (6, 6): dark}
    # The skin's own eye: 2x2 with the dark (#262626) as the eye background and the hunter's eye colour as
    # the iris. Every open-eye cell below keeps that rule (no white, no colour outside the dark block).
    cells.append(face.copy())                                                                  # 0 neutral (original)
    cells.append(make({(1, 6): dark, (2, 6): dark, (5, 6): dark, (6, 6): dark}))               # 1 blink: dark lids
    band = {(x, 4): dark for x in range(2, 6)}                                                 # (kept as "blank", cell 10)
    band.update({(x, y): dark for y in (5, 6) for x in range(1, 7)})
    blank = make(band)
    cells.append(make({(x, y): dark for y in (5, 6) for x in (1, 2, 5, 6)}))                   # 2 stun: KT's two dark blocks
    cells.append(make({(1, 5): dark, (2, 5): dark, (5, 5): dark, (6, 5): dark,                 # 3 chase: dark glare, inner iris
                       (1, 6): dark, (2, 6): col, (5, 6): col, (6, 6): dark}))
    wide = {(x, y): col for y in (5, 6) for x in (1, 2, 5, 6)}                                 # 4 scream: wide eyes (eye colour only, no brows),
    cells.append(make(wide))
    happy = {(1, 5): dark, (6, 5): dark}                                                       # 5 happy: KT's ^ ^ arcs
    happy.update({(x, 6): dark for x in (0, 1, 2, 5, 6, 7)})                                    # (reach into the hair frame)
    cells.append(make(happy))
    # 6-9 derp: an animation. In each 2x2 eye the iris pixel steps clockwise (TL > TR > BR > BL); the two eyes
    # start half a turn apart (KT's derp frame), the rest of the eye stays the dark background.
    ring = [(0, 0), (1, 0), (1, 1), (0, 1)]
    for t in range(4):
        pix = {}
        for ex, off in ((1, 0), (5, 2)):
            for j, (dx, dy) in enumerate(ring):
                pix[(ex + dx, 5 + dy)] = col if j == (t + off) % 4 else dark
        cells.append(make(pix))
    cells.append(blank)                                                                        # 10 blank: KT's dark band
    # 11 wink_right (character's right eye = image-left eye shut), 12 wink_left (image-right eye shut)
    closed_l = {(1, 6): dark, (2, 6): dark}
    closed_r = {(5, 6): dark, (6, 6): dark}
    open_l = {p: v for p, v in open_eyes.items() if p[0] < 4}
    open_r = {p: v for p, v in open_eyes.items() if p[0] > 4}
    cells.append(make({**closed_l, **open_r}))
    cells.append(make({**open_l, **closed_r}))
    for im in cells:                            # keep the blush row identical on every cell
        im.putpixel((1, 7), blush); im.putpixel((6, 7), blush)
    return cells


def source_hunter(name, mod_globals, modify=None):
    """Fill a hunter module's constants and return (cubes, face painter) from the supplied skin.
    modify(canvas) may edit the skin (remove art that became geometry) and return extra cubes."""
    canvas = load_source(name)
    extra = modify(canvas) if modify else []
    cells = expressions_from_face(canvas.crop((8, 8, 16, 16)))
    mod_globals["MODEL_KW"].update(vanilla_kw(canvas))
    return vanilla_cubes(overlays=True) + list(extra), (lambda k: cells[k] if k < len(cells) else None)
