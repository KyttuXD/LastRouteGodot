"""Rebuilds the most visible furniture and fixtures as Minecraft-style block models.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/props/build_blocky_props.py -- PROP_BOUNDS.json art/props-3d/props/blocky

PROP_BOUNDS.json comes from tools/props/measure.gd (the footprint of the model each
prop type uses today), so every rebuilt prop keeps its old size, pivot and front
(+Z in Godot). Each prop is a handful of axis-aligned boxes in fractions of that
footprint, textured from one shared 128x64 pixel atlas (8x4 tiles of 16 px) with
nearest sampling; colour variants swap the `@cloth` / `@wood` placeholders.

Rotation (DONE13): a box may carry two optional trailing items, (x0, y0, z0, x1, y1, z1, kind, (rx, ry, rz), (px, py, pz)): degrees
about the prop axes (x right, y up, z front) and a pivot in the same fractions as the box (default: the box centre). Use it for
backrest tilt (5-15 deg about x), splayed legs, angled lamp shades, lids and rocker curves; everything else stays axis aligned.
"""
import json
import math
import os
import random
import sys

import bmesh
import bpy

BOUNDS = json.load(open(sys.argv[sys.argv.index("--") + 1]))
OUT = sys.argv[sys.argv.index("--") + 2]
os.makedirs(OUT, exist_ok=True)

# ---- atlas ---------------------------------------------------------------------
TILES = ["oak", "dark", "red", "plum", "steel", "brass", "screen", "paper",
         "stone", "black", "green", "glass", "amber", "concrete", "porcelain", "rust",
         "sand", "water", "leaf", "bark", "white", "mirror", "yellow", "blue",
         # DONE14: eight more finishes in the free tiles (appended, so every older UV is unchanged)
         "walnut", "pine", "ash", "mahogany", "linen", "teal", "tile", "grey"]
COLS = 8                 # atlas is 8 tiles wide, 4 tall (128 x 64)
AW, AH = COLS * 16, 64
BASE = {"oak": (150, 112, 62), "dark": (82, 54, 34), "red": (138, 34, 44), "plum": (86, 40, 84),
        "steel": (112, 118, 124), "brass": (176, 138, 52), "screen": (40, 214, 200), "paper": (214, 208, 190),
        "stone": (110, 108, 108), "black": (30, 28, 32), "green": (52, 104, 52), "glass": (70, 110, 160),
        "amber": (255, 176, 64), "concrete": (126, 124, 120), "porcelain": (226, 224, 218), "rust": (128, 74, 44),
        "sand": (214, 190, 126), "water": (52, 140, 190), "leaf": (58, 138, 52), "bark": (92, 66, 40),
        "white": (232, 232, 228), "mirror": (150, 190, 204), "yellow": (222, 190, 52), "blue": (44, 84, 160),
        "walnut": (96, 62, 42), "pine": (200, 164, 106), "ash": (186, 172, 148), "mahogany": (112, 46, 36),
        "linen": (208, 198, 172), "teal": (36, 100, 104), "tile": (212, 224, 226), "grey": (98, 102, 110)}
WOODISH = ("oak", "dark", "walnut", "pine", "ash", "mahogany")
CLOTHISH = ("red", "plum", "green", "teal", "linen", "grey")


def paint_atlas():
    size = AW
    img = bpy.data.images.new("BlockyAtlas", AW, AH, alpha=False)
    px = [0.0] * (AW * AH * 4)
    rng = random.Random(1234)
    for index, name in enumerate(TILES):
        tx, ty = index % COLS, index // COLS
        base = BASE[name]
        for y in range(16):
            for x in range(16):
                shade = 1.0 + rng.choice([-1, 0, 0, 1]) * .09
                r, g, b = base
                if name in WOODISH and y % 5 == 4:
                    shade *= .72
                if name == "steel" and x % 4 == 0:
                    shade *= .9
                if name == "screen":
                    shade *= .8 if y % 2 else 1.15
                if name in CLOTHISH and (x + y) % 4 == 0:
                    shade *= .82
                if name == "stone" and (x % 8 == 0 or y % 8 == 0):
                    shade *= .7
                if name == "tile" and (x % 8 == 0 or y % 8 == 0):
                    shade *= .8                                  # grout lines, 8 px tiles
                if name == "pine" and (x * 5 + y * 2) % 11 < 2:
                    shade *= .86                                 # knots
                if name == "porcelain" and (x in (0, 15) or y in (0, 15)):
                    shade *= .88
                if name == "leaf" and (x * 3 + y * 5) % 7 < 2:
                    shade *= .78
                if name == "bark" and x % 4 == 1:
                    shade *= .78
                if name == "water" and (x + y * 2) % 8 == 0:
                    shade *= 1.25
                if name == "sand" and (x * 7 + y * 3) % 9 == 0:
                    shade *= .9
                if name == "mirror" and (x + y) % 9 == 0:
                    shade *= 1.12
                if x in (0, 15) or y in (0, 15):
                    shade *= .86 if name not in ("screen", "amber") else 1.0
                color = [min(255, max(0, c * shade)) / 255.0 for c in (r, g, b)]
                py = (AH // 16 - 1 - ty) * 16 + (15 - y)   # image origin is bottom-left; tile row 0 is the TOP row (matches the UVs)
                i = (py * AW + tx * 16 + x) * 4
                px[i:i + 4] = color + [1.0]
    img.pixels = px
    img.pack()
    return img


ATLAS = paint_atlas()
MAT = bpy.data.materials.new("BlockyProps")
MAT.use_nodes = True
nodes = MAT.node_tree.nodes
tex = nodes.new("ShaderNodeTexImage")
tex.image = ATLAS
tex.interpolation = "Closest"
bsdf = nodes["Principled BSDF"]
MAT.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 1.0


# ---- geometry ------------------------------------------------------------------
PIXEL = 0.5 / 16.0       # one texel is 3 cm: a 16 px tile covers half a metre, like a block face
SNAP = 0.0625            # geometry sits on a 6 cm voxel grid


def snap(value):
    return round(value / SNAP) * SNAP


def add_face(bm, uv_layer, quad, tile):
    """quad = 4 corners (bl, br, tr, tl); subdivided into <=0.5 m cells so the texel
    density is constant (a Minecraft block face repeats its 16 px texture, it never stretches)."""
    index = TILES.index(tile)
    tx, ty = index % COLS, index // COLS
    p00, p10, p11, p01 = [__import__("mathutils").Vector(c) for c in quad]
    wu = (p10 - p00).length
    wv = (p01 - p00).length
    nu = max(1, math.ceil(wu / 0.5 - 1e-6))
    nv = max(1, math.ceil(wv / 0.5 - 1e-6))
    for i in range(nu):
        for j in range(nv):
            u0, u1 = i / nu, (i + 1) / nu
            v0, v1 = j / nv, (j + 1) / nv
            def at(u, v):
                return p00 + (p10 - p00) * u + (p01 - p00) * v
            # texture region covered by this cell: full tile for a 0.5 m cell, cropped below that
            cu = min(1.0, wu / nu / 0.5)
            cv = min(1.0, wv / nv / 0.5)
            tu0 = (tx * 16 + .5) / float(AW)
            tv_top = 1.0 - (ty * 16 + .5) / float(AH)
            tu1 = tu0 + cu * (15.0 / AW)
            tv1 = tv_top - cv * (15.0 / AH)
            corners = [at(u0, v0), at(u1, v0), at(u1, v1), at(u0, v1)]
            uvs = [(tu0, tv1), (tu1, tv1), (tu1, tv_top), (tu0, tv_top)]
            verts = [bm.verts.new(c) for c in corners]
            face = bm.faces.new(verts)
            face.smooth = False
            for loop, uv in zip(face.loops, uvs):
                loop[uv_layer].uv = uv


def rotation_matrix(rot):
    """rot = (rx, ry, rz) degrees about the prop's own axes (x right, y up, z front, applied z, then y, then x).
    Godot axes map to Blender axes as (x, y, z) -> (X, -Z... i.e. Blender X = x, Blender Y = -z, Blender Z = y), so a turn about
    the prop's +x is a turn about Blender +X, about +y is about Blender +Z, and about +z is about Blender -Y."""
    mu = __import__("mathutils")
    rx, ry, rz = [math.radians(a) for a in rot]
    mx = mu.Matrix.Rotation(rx, 3, mu.Vector((1, 0, 0)))
    my = mu.Matrix.Rotation(ry, 3, mu.Vector((0, 0, 1)))
    mz = mu.Matrix.Rotation(rz, 3, mu.Vector((0, -1, 0)))
    return mx @ my @ mz


def snap_extent(x0, y0, z0, x1, y1, z1):
    """The voxel-snapped extent add_box gives a box (never thinner than one voxel; a box that starts at z == 0 keeps its floor)."""
    def fix(lo, hi, keep_lo=False):
        lo2 = lo if keep_lo else snap(lo)
        hi2 = snap(hi)
        if hi2 - lo2 < SNAP * .9:
            hi2 = lo2 + SNAP
        return lo2, hi2
    x0, x1 = fix(x0, x1)
    y0, y1 = fix(y0, y1)
    z0, z1 = fix(z0, z1, keep_lo=(z0 == 0.0))
    return x0, y0, z0, x1, y1, z1


COPLANAR_EPS = 0.006      # the earlier box's face is set back this far behind the later box's face (6 mm)
COPLANAR_TOL = 0.0035     # planes closer than this fight in the depth buffer at room distances


def aligned_axes(rot):
    """Blender axes whose faces stay axis-aligned under `rot` (degrees about the prop axes x, y up, z front = Blender x, z, -y)."""
    if rot is None or not any(abs(v) > 1e-6 for v in rot):
        return {0, 1, 2}
    turned = [i for i, v in enumerate(rot) if abs(v) > 1e-6]
    if len(turned) > 1:
        return set()
    return {(0, 2, 1)[turned[0]]}


def resolve_coplanar(extents, movable):
    """extents: snapped (x0, y0, z0, x1, y1, z1) per box in build order; movable: False for rotated boxes (skipped). Two same-facing faces of
    different boxes on one plane (and overlapping) z-fight. The LATER box (the detail laid on a base) keeps its plane and the EARLIER box's
    face is set back COPLANAR_EPS behind it (inward, so a prop's overall size never grows: the derived collider sizes stay put).
    Returns the extents with the set-backs applied, and the pairs found (earlier, later, axis, side, overlap area)."""
    cur = [list(e) for e in extents]
    floor = min(e[2] for e in extents) if extents else 0.0
    found = []
    for _pass in range(8):          # a stack of three layers needs the middle one moved again after the bottom one
        before = len(found)
        _resolve_pass(cur, movable, floor, found)
        if len(found) == before:
            break
    return [tuple(e) for e in cur], found


def _resolve_pass(cur, movable, floor, found):
    for i, ei in enumerate(cur):
        for axis in sorted(movable[i]):
            other = [k for k in range(3) if k != axis]
            for side in (-1, 1):
                idx = axis if side < 0 else axis + 3
                plane = ei[idx]
                if axis == 2 and side < 0 and plane <= floor + 1e-6:
                    continue                       # floor contact: the underside is never seen
                for j in range(i):
                    if axis not in movable[j]:
                        continue
                    ej = cur[j]
                    pj = ej[idx]
                    if abs(pj - plane) >= COPLANAR_TOL:
                        continue
                    ov = 1.0
                    for k in other:
                        ov *= max(0.0, min(ei[k + 3], ej[k + 3]) - max(ei[k], ej[k]))
                    if ov < 1e-4:
                        continue
                    found.append((j, i, axis, side, ov))
                    wanted = plane - side * COPLANAR_EPS
                    opposite = ej[axis + 3] if side < 0 else ej[axis]
                    if abs(wanted - opposite) >= 0.02:        # never collapse a thin box
                        ej[idx] = wanted if (side > 0 and wanted < pj) or (side < 0 and wanted > pj) else pj


def add_box(bm, uv_layer, x0, y0, z0, x1, y1, z1, kind, rot=None, pivot=None, extent=None):
    """Blender coords, snapped to the voxel grid (never thinner than one voxel). `rot` (degrees about the prop axes) turns the
    snapped box about `pivot` (Blender coords, default the box centre), so tilted backs, splayed legs and angled shades keep the
    constant texel density and the voxel-sized thickness of the straight boxes. `extent` replaces the snapped extent (build() passes the
    one with its coplanar faces raised)."""
    x0, y0, z0, x1, y1, z1 = extent if extent is not None else snap_extent(x0, y0, z0, x1, y1, z1)
    quads = [
        [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)],   # +z top-facing order handled by winding fix below
        [(x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0)],
        [(x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1)],
        [(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)],
        [(x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)],
        [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)],
    ]
    outward = [(0, 0, 1), (0, 0, -1), (1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0)]
    if rot is not None and any(abs(a) > 1e-6 for a in rot):
        mu = __import__("mathutils")
        m = rotation_matrix(rot)
        c0 = mu.Vector(pivot) if pivot is not None else mu.Vector(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
        quads = [[tuple(c0 + m @ (mu.Vector(p) - c0)) for p in q] for q in quads]
        outward = [tuple(m @ mu.Vector(o)) for o in outward]
    for quad, out in zip(quads, outward):
        a, b, c = [__import__("mathutils").Vector(q) for q in quad[:3]]
        if (b - a).cross(c - a).dot(__import__("mathutils").Vector(out)) < 0:
            quad = [quad[1], quad[0], quad[3], quad[2]]   # mirror: keep (bl, br, tr, tl) order, flip winding
        add_face(bm, uv_layer, quad, kind)


def build(name, boxes, size, center, min_y, subst):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    sx, sy, sz = size
    placed = []
    for box in boxes:
        a, b, c, d, e, f, kind = box[:7]
        rot = box[7] if len(box) > 7 else None          # (rx, ry, rz) degrees about the prop axes
        piv = box[8] if len(box) > 8 else None          # pivot as prop fractions (x, y, z), default the box centre
        kind = subst.get(kind, kind)
        # normalised: x left..right, y bottom..top, z back..front; front = Blender -Y
        x0 = center[0] + (a - .5) * sx
        x1 = center[0] + (d - .5) * sx
        y_lo = -(center[1] + (f - .5) * sz)
        y_hi = -(center[1] + (c - .5) * sz)
        pivot = None
        if piv is not None:
            pivot = (center[0] + (piv[0] - .5) * sx, -(center[1] + (piv[2] - .5) * sz), min_y + piv[1] * sy)
        raw = (min(x0, x1), min(y_lo, y_hi), min_y + b * sy, max(x0, x1), max(y_lo, y_hi), min_y + e * sy)
        placed.append((raw, kind, rot, pivot))
    extents = [snap_extent(*p[0]) for p in placed]
    extents, pairs = resolve_coplanar(extents, [aligned_axes(p[2]) for p in placed])
    if pairs:
        print("BLOCKYCOPLANAR %s %d" % (name, len(pairs)))
    for (raw, kind, rot, pivot), extent in zip(placed, extents):
        add_box(bm, uv, *raw, kind, rot=rot, pivot=pivot, extent=extent)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(MAT)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def export(obj, filename):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, filename), export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=True, export_image_format="AUTO")
    bpy.data.objects.remove(obj, do_unlink=True)


# ---- prop definitions (fractions of the old footprint) --------------------------------------
def legs(top, w, kind="@wood", inset=.0):
    d = w
    return [(inset, 0, inset, inset + d, top, inset + d, kind), (1 - inset - d, 0, inset, 1 - inset, top, inset + d, kind),
            (inset, 0, 1 - inset - d, inset + d, top, 1 - inset, kind), (1 - inset - d, 0, 1 - inset - d, 1 - inset, top, 1 - inset, kind)]


PROPS = {}
CLOTH = ["red", "plum", "green"]
WOODS = ["oak", "dark"]

PROPS["woodenChair"] = (legs(.46, .14, inset=.06) + [(.04, .46, .04, .96, .56, .96, "@wood"), (.04, .56, .04, .96, 1.0, .18, "@wood"),
                        (.12, .62, .18, .88, .92, .22, "dark")], {"@wood": WOODS})
PROPS["woodenChairCushion"] = (legs(.46, .14, inset=.06) + [(.04, .46, .04, .96, .56, .96, "@wood"), (.1, .56, .1, .9, .64, .9, "@cloth"),
                               (.04, .56, .04, .96, 1.0, .18, "@wood")], {"@wood": WOODS, "@cloth": CLOTH})
PROPS["diningChair"] = PROPS["woodenChairCushion"]
PROPS["diningChairCushion"] = PROPS["woodenChairCushion"]
PROPS["woodenTable"] = ([(0, .86, 0, 1, 1, 1, "@wood")] + legs(.86, .1, "dark", .04), {"@wood": WOODS})
PROPS["diningTable"] = ([(0, .88, 0, 1, 1, 1, "dark"), (.04, .82, .06, .96, .88, .94, "@wood")] +
                        [(.02, 0, .1, .08, .82, .9, "dark"), (.92, 0, .1, .98, .82, .9, "dark")], {"@wood": WOODS})
PROPS["restaurantPartyTable"] = PROPS["woodenTable"]
bed_frame = [(0, .30, 0, 1, .42, 1, "dark"), (0, 0, 0, 1, .62, .05, "dark"), (0, .30, .95, 1, .5, 1, "dark"),   # raised: 0.40 m under the bed
             (.03, .42, .05, .97, .66, .95, "paper"), (.05, .66, .07, .95, .78, .3, "paper"),
             (.03, .42, .4, .97, .7, .95, "@cloth")] + [(0, 0, .9, .08, .30, .95, "dark"), (.92, 0, .9, 1, .30, .95, "dark"),
                                                       (0, 0, .05, .08, .30, .1, "dark"), (.92, 0, .05, 1, .30, .1, "dark")]
PROPS["singleBed"] = (bed_frame, {"@cloth": CLOTH})
PROPS["doubleBed"] = (bed_frame, {"@cloth": CLOTH})
PROPS["bedroomNightstand"] = ([(0, 0, 0, 1, 1, .94, "@wood"), (.06, .08, .94, .94, .46, 1, "oak"), (.06, .54, .94, .94, .92, 1, "oak"),
                               (.42, .26, .99, .58, .32, 1, "brass"), (.42, .72, .99, .58, .78, 1, "brass")], {"@wood": ["dark"]})
for t in ("bedroomDresser", "woodenDresserSideboard", "gothicDresser", "gothicNightstand", "diningSideboard", "mansionConsoleTable", "normalTvConsole"):
    PROPS[t] = ([(0, 0, 0, 1, 1, .94, "dark"), (.04, .08, .94, .48, .92, 1, "oak"), (.52, .08, .94, .96, .92, 1, "oak"),
                 (.22, .5, .99, .3, .56, 1, "brass"), (.7, .5, .99, .78, .56, 1, "brass")], {})
PROPS["bedroomWardrobe"] = ([(0, 0, 0, 1, 1, .92, "dark"), (.04, .04, .92, .49, .96, 1, "oak"), (.51, .04, .92, .96, .96, 1, "oak"),
                             (.44, .46, .99, .48, .56, 1, "brass"), (.52, .46, .99, .56, .56, 1, "brass")], {})
PROPS["gothicWardrobe"] = PROPS["bedroomWardrobe"]
shelf = [(0, 0, 0, 1, 1, 1, "dark"), (.06, .04, .12, .94, .3, 1, "black"), (.06, .34, .12, .94, .6, 1, "black"), (.06, .64, .12, .94, .96, 1, "black")]
for row, y in enumerate((.04, .34, .64)):
    x = .08
    for k, kind in enumerate(["red", "plum", "green", "brass", "red", "plum", "paper"]):
        w = .09 + .02 * ((k + row) % 3)
        shelf.append((x, y, .3, x + w, y + .2 + .04 * ((k * 3 + row) % 3), .9, kind))
        x += w + .02
for t in ("normalBookcase", "mansionBookshelf", "gothicBookcase"):
    PROPS[t] = (shelf, {})
PROPS["loungeCouch"] = ([(0, .08, 0, 1, .42, 1, "@cloth"), (0, .42, 0, 1, 1, .26, "@cloth"), (0, .42, 0, .12, .72, 1, "@cloth"),
                         (.88, .42, 0, 1, .72, 1, "@cloth"), (.14, .42, .26, .86, .56, .98, "@cloth"), (0, 0, .04, .1, .08, .12, "dark"),
                         (.9, 0, .04, 1, .08, .12, "dark"), (0, 0, .88, .1, .08, .96, "dark"), (.9, 0, .88, 1, .08, .96, "dark")],
                        {"@cloth": CLOTH})
PROPS["loungeCouchWide"] = PROPS["loungeCouch"]
PROPS["officeDesk"] = ([(0, .86, 0, 1, 1, 1, "oak"), (.02, 0, .04, .3, .86, .96, "steel"), (.7, 0, .04, .98, .86, .96, "steel"),
                        (.04, .56, .96, .28, .64, 1, "black"), (.04, .2, .96, .28, .28, 1, "black"), (.72, .56, .96, .96, .64, 1, "black"),
                        (.72, .2, .96, .96, .28, 1, "black"), (.3, .3, .06, .7, .86, .12, "steel")], {})
PROPS["officeChair"] = ([(.4, 0, .4, .6, .36, .6, "black"), (.1, 0, .1, .9, .06, .9, "black"), (.04, .36, .04, .96, .48, .96, "@cloth"),
                         (.1, .48, .04, .9, 1, .16, "@cloth")], {"@cloth": ["plum", "red"]})
PROPS["retroComputerDesktop"] = ([(0, 0, .1, 1, .12, .9, "paper"), (.1, .12, .15, .9, .9, .85, "paper"), (.18, .24, .85, .82, .82, .92, "black"),
                                  (.22, .3, .92, .78, .76, 1, "screen"), (.1, .0, .86, .9, .06, 1, "paper")], {})
for t in ("retroComputerCompact", "retroComputerTower", "retroComputerTerminal", "officeCrtSecurityConsole"):
    PROPS[t] = PROPS["retroComputerDesktop"]
PROPS["filingCabinet"] = ([(0, 0, 0, 1, 1, .94, "steel")] + [(.06, y, .94, .94, y + .22, 1, "concrete") for y in (.04, .28, .52, .76)] +
                          [(.4, y + .08, .99, .6, y + .12, 1, "black") for y in (.04, .28, .52, .76)], {})
PROPS["locker"] = ([(0, 0, 0, 1, 1, .94, "steel"), (.04, .04, .94, .48, .96, 1, "concrete"), (.52, .04, .94, .96, .96, 1, "concrete"),
                    (.12, .7, .99, .4, .78, 1, "black"), (.6, .7, .99, .88, .78, 1, "black"), (.4, .5, .99, .44, .56, 1, "brass"), (.56, .5, .99, .6, .56, 1, "brass")], {})
PROPS["vendingMachine"] = ([(0, 0, 0, 1, 1, .9, "red"), (.08, .3, .9, .92, .92, 1, "glass"), (.12, .34, .96, .88, .88, 1, "paper"),
                            (.08, .08, .9, .92, .2, 1, "black"), (.7, .22, .96, .9, .28, 1, "brass")], {})
PROPS["arcadeCabinet"] = ([(0, 0, 0, 1, .9, .9, "@cloth"), (.04, .9, .0, .96, 1, .7, "black"), (.1, .5, .9, .9, .86, 1, "black"),
                           (.16, .56, .96, .84, .82, 1, "screen"), (.06, .36, .5, .94, .5, 1, "dark"), (.2, .4, .78, .3, .5, .86, "amber"),
                           (.7, .4, .78, .8, .5, .86, "red")], {"@cloth": ["plum", "dark", "green"]})
PROPS["arcadeCabinetCyanMagenta"] = PROPS["arcadeCabinet"]
PROPS["serverRack"] = ([(0, 0, 0, 1, 1, 1, "black")] + [(.08, y, .9, .92, y + .1, 1, "steel") for y in (.06, .2, .34, .48, .62, .76)] +
                       [(.7, y + .04, .98, .78, y + .06, 1, "screen") for y in (.06, .34, .62)], {})
PROPS["breakerCabinet"] = PROPS["serverRack"]
PROPS["tableLamp"] = ([(.3, 0, .3, .7, .08, .7, "dark"), (.42, .08, .42, .58, .52, .58, "brass"), (.18, .5, .18, .82, 1, .82, "amber")], {})
PROPS["bedsideLamp"] = PROPS["tableLamp"]
PROPS["floorLamp"] = ([(.2, 0, .2, .8, .04, .8, "dark"), (.44, .04, .44, .56, .8, .56, "brass"), (.1, .78, .1, .9, 1, .9, "amber")], {})
PROPS["ceilingLight"] = ([(.05, .7, .05, .95, 1, .95, "steel"), (.15, .2, .15, .85, .7, .85, "amber"), (.05, 0, .05, .95, .2, .95, "steel")], {})
PROPS["wallSconce"] = ([(.2, .0, .0, .8, 1, .2, "brass"), (.3, .15, .2, .7, .85, .6, "amber"), (.25, .05, .2, .75, .15, .65, "brass"),
                        (.25, .85, .2, .75, .95, .65, "brass")], {})
PROPS["tableCandelabra"] = ([(.2, 0, .3, .8, .1, .7, "brass"), (.46, .1, .4, .54, .5, .6, "brass"), (.05, .5, .4, .95, .56, .6, "brass"),
                             (.08, .56, .44, .16, .86, .56, "amber"), (.46, .56, .44, .54, .96, .56, "amber"), (.84, .56, .44, .92, .86, .56, "amber")], {})
PROPS["supplyCrates"] = ([(0, 0, 0, .62, .5, .62, "oak"), (.38, 0, .38, 1, .5, 1, "dark"), (.1, .5, .08, .56, 1, .54, "dark"),
                          (0, .0, 0, .04, .5, .04, "dark"), (.58, 0, .58, .62, .5, .62, "dark")], {})
PROPS["charredSupplyCrate"] = PROPS["supplyCrates"]
PROPS["trashBin"] = ([(.04, 0, .04, .96, .88, .96, "steel"), (0, .88, 0, 1, 1, 1, "concrete"), (.1, .9, .1, .9, 1, .9, "black")], {})
PROPS["normalKitchenCounter"] = ([(0, 0, 0, 1, .9, 1, "oak"), (0, .9, 0, 1, 1, 1, "stone"), (.06, .08, .98, .48, .8, 1, "dark"), (.52, .08, .98, .94, .8, 1, "dark")], {})
for t in ("luxuryKitchenCounter", "gothicKitchenCounter", "normalKitchenIsland", "luxuryKitchenIsland", "gothicKitchenIsland"):
    PROPS[t] = PROPS["normalKitchenCounter"]
PROPS["normalKitchenFridge"] = ([(0, 0, 0, 1, 1, .94, "porcelain"), (.04, .04, .94, .96, .6, 1, "steel"), (.04, .64, .94, .96, .96, 1, "steel"),
                                 (.84, .3, .99, .9, .5, 1, "black")], {})
for t in ("luxuryKitchenFridge", "gothicKitchenFridge"):
    PROPS[t] = PROPS["normalKitchenFridge"]
PROPS["normalKitchenStove"] = ([(0, 0, 0, 1, .92, 1, "steel"), (0, .92, 0, 1, 1, 1, "black"), (.08, .12, .98, .92, .7, 1, "black"),
                                (.15, .94, .15, .4, .98, .4, "rust"), (.6, .94, .15, .85, .98, .4, "rust"), (.15, .94, .6, .4, .98, .85, "rust"), (.6, .94, .6, .85, .98, .85, "rust")], {})
for t in ("luxuryKitchenStove", "gothicKitchenStove"):
    PROPS[t] = PROPS["normalKitchenStove"]
PROPS["houseToilet"] = ([(.15, 0, .3, .85, .45, 1, "porcelain"), (.1, .45, .06, .9, .95, .34, "porcelain"), (.2, .45, .34, .8, .55, .9, "paper")], {})
PROPS["publicRestroomToilet"] = PROPS["houseToilet"]
PROPS["bathroomSink"] = ([(.3, 0, .35, .7, .6, .75, "porcelain"), (.1, .6, .1, .9, .78, .9, "porcelain"), (.45, .78, .12, .55, .94, .2, "brass")], {})
PROPS["houseBathtub"] = ([(0, 0, 0, 1, .6, 1, "porcelain"), (.1, .5, .1, .9, .62, .9, "glass")], {})
PROPS["woodenDresserSideboard"] = PROPS["bedroomDresser"]

exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "blocky_props_extra.py")).read())
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "blocky_props_variants.py")).read())
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "blocky_props_seating.py")).read())
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "blocky_props_doors.py")).read())
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "blocky_props_rework2.py")).read())   # DONE13: TARGET_SIZE, rotated parts
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "blocky_props_rework3.py")).read())   # DONE14: chests, lamps, kitchen, bathroom, crates
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "blocky_props_rework4.py")).read())   # room-purpose catalog: infirmary, library, storage, lobby
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "blocky_props_biomes.py")).read())    # hospital, lab, greenhouse
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "blocky_props_mall.py")).read())      # shopping arcade

# Props rebuilt larger than the old footprint (generator and RoomCatalog footprints follow).
SIZE_SCALE = {"loungeCouch": (1.65, 1.0, 1.55), "loungeCouchWide": (1.48, 1.0, 1.55),
              # DONE11: chairs 0.94 m tall (seat 0.44), tables 0.75 m, restaurant table keeps its 2.23 m balloon cluster over a 0.75 m top
              "woodenChair": (1.0, 0.94 / 1.01, 1.0), "woodenChairCushion": (1.0, 0.94 / 1.01, 1.0),
              "diningChair": (1.0, 0.94 / 1.2, 1.0), "diningChairCushion": (1.0, 0.94 / 1.2, 1.0),
              "woodenTable": (1.0, 0.75 / 0.79, 1.0), "diningTable": (1.0, 0.75 / 1.025, 1.0),
              "normalEntryBench": (1.0, 0.65, 1.0), "gothicPedestalTable": (1.0, 0.75 / 0.9225, 1.0),
              # scale fit (docs/SCALE_FIT.md): beds about 2.25 m long including boards (the old models were 2.67 m)
              "singleBed": (1.0, 1.0, 2.25 / 2.665), "doubleBed": (1.0, 1.0, 2.25 / 2.665)}
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "blocky_props_mansion.py")).read())   # mansion finishes (after SIZE_SCALE)

# ---- build & export -------------------------------------------------------------------------
manifest = {}
# BLOCKY_ONLY=a,b builds just those types and merges them into the existing manifest (the rest stay as built).
ONLY = [n for n in os.environ.get("BLOCKY_ONLY", "").split(",") if n]
if ONLY and os.path.exists(os.path.join(OUT, "manifest.json")):
    manifest = json.load(open(os.path.join(OUT, "manifest.json")))
for name, (base_boxes, base_subs) in PROPS.items():
    if ONLY and name not in ONLY:
        continue
    if name not in BOUNDS and name in TARGET_SIZE:
        BOUNDS[name] = {"size": list(TARGET_SIZE[name]), "center": [0.0, 0.0], "min_y": 0.0}   # new types: no older model
    if name not in BOUNDS:
        print("skip (no bounds):", name)
        continue
    info = dict(BOUNDS[name])
    if name in SIZE_SCALE:
        info["size"] = [c * f for c, f in zip(info["size"], SIZE_SCALE[name])]
    if name in TARGET_SIZE:
        info["size"] = list(TARGET_SIZE[name])       # DONE13: designs authored in metres are built at exactly this size
        if info["min_y"] < 0.1:
            info["min_y"] = 0.0                      # floor props stand on the floor (the old beach chair model floated 4 cm)
    files = []
    shapes = [(base_boxes, base_subs)] + list(VARIANTS.get(name, []))
    combos = []     # (boxes, substitution) for every shape x colour option
    for boxes, subs in shapes:
        options = [{}]
        if subs:
            keys = list(subs)
            count = max(len(v) for v in subs.values())
            options = [{k: subs[k][i % len(subs[k])] for k in keys} for i in range(count)]
        for subst in options:
            combos.append((boxes, subst))
    for i, (boxes, subst) in enumerate(combos):
        obj = build(f"{name}_{i}", boxes, info["size"], info["center"], info["min_y"], subst)
        filename = f"{name}_{i}.glb" if len(combos) > 1 else f"{name}.glb"
        export(obj, filename)
        files.append(filename)
    manifest[name] = files
manifest.update({k: v for k, v in EXTRA_MANIFEST.items() if not k.startswith("__")})
json.dump(manifest, open(os.path.join(OUT, "manifest.json"), "w"), indent=1)
# regenerate src/config/blocky_prop_models.gd:  python3 - < tools/props/emit_models.py (see README)
print("BLOCKY PROPS OK", len(manifest), "types,", sum(len(v) for v in manifest.values()), "models")
