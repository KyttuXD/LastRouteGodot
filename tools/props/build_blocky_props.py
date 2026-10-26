"""Rebuilds the most visible furniture and fixtures as Minecraft-style block models.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/props/build_blocky_props.py -- PROP_BOUNDS.json art/props-3d/props/blocky

PROP_BOUNDS.json comes from tools/props/measure.gd (the footprint of the model each
prop type uses today), so every rebuilt prop keeps its old size, pivot and front
(+Z in Godot). Each prop is a handful of axis-aligned boxes in fractions of that
footprint, textured from one shared 64x64 pixel atlas (4x4 tiles of 16 px) with
nearest sampling; colour variants swap the `@cloth` / `@wood` placeholders.
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
         "stone", "black", "green", "glass", "amber", "concrete", "porcelain", "rust"]
BASE = {"oak": (150, 112, 62), "dark": (82, 54, 34), "red": (138, 34, 44), "plum": (86, 40, 84),
        "steel": (112, 118, 124), "brass": (176, 138, 52), "screen": (40, 214, 200), "paper": (214, 208, 190),
        "stone": (110, 108, 108), "black": (30, 28, 32), "green": (52, 104, 52), "glass": (70, 110, 160),
        "amber": (255, 176, 64), "concrete": (126, 124, 120), "porcelain": (226, 224, 218), "rust": (128, 74, 44)}


def paint_atlas():
    size = 64
    img = bpy.data.images.new("BlockyAtlas", size, size, alpha=False)
    px = [0.0] * (size * size * 4)
    rng = random.Random(1234)
    for index, name in enumerate(TILES):
        tx, ty = index % 4, index // 4
        base = BASE[name]
        for y in range(16):
            for x in range(16):
                shade = 1.0 + rng.choice([-1, 0, 0, 1]) * .09
                r, g, b = base
                if name in ("oak", "dark") and y % 5 == 4:
                    shade *= .72
                if name == "steel" and x % 4 == 0:
                    shade *= .9
                if name == "screen":
                    shade *= .8 if y % 2 else 1.15
                if name in ("red", "plum", "green") and (x + y) % 4 == 0:
                    shade *= .82
                if name == "stone" and (x % 8 == 0 or y % 8 == 0):
                    shade *= .7
                if name == "porcelain" and (x in (0, 15) or y in (0, 15)):
                    shade *= .88
                if x in (0, 15) or y in (0, 15):
                    shade *= .86 if name not in ("screen", "amber") else 1.0
                color = [min(255, max(0, c * shade)) / 255.0 for c in (r, g, b)]
                py = ty * 16 + (15 - y)   # image origin is bottom-left
                i = (py * size + tx * 16 + x) * 4
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
def add_box(bm, uv_layer, x0, y0, z0, x1, y1, z1, kind):
    """Blender coords; each face maps the kind's whole 16x16 tile."""
    index = TILES.index(kind)
    tx, ty = index % 4, index // 4
    u0, u1 = (tx * 16 + .5) / 64.0, ((tx + 1) * 16 - .5) / 64.0
    v0, v1 = 1.0 - ((ty + 1) * 16 - .5) / 64.0, 1.0 - (ty * 16 + .5) / 64.0
    c = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
         (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    verts = [bm.verts.new(p) for p in c]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (2, 3, 7, 6), (1, 2, 6, 5), (0, 4, 7, 3)]
    for f in faces:
        face = bm.faces.new([verts[i] for i in f])
        face.smooth = False
        for loop, uv in zip(face.loops, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]):
            loop[uv_layer].uv = uv


def build(name, boxes, size, center, min_y, subst):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    sx, sy, sz = size
    for (a, b, c, d, e, f, kind) in boxes:
        kind = subst.get(kind, kind)
        # normalised: x left..right, y bottom..top, z back..front; front = Blender -Y
        x0 = center[0] + (a - .5) * sx
        x1 = center[0] + (d - .5) * sx
        y_lo = -(center[1] + (f - .5) * sz)
        y_hi = -(center[1] + (c - .5) * sz)
        add_box(bm, uv, min(x0, x1), min(y_lo, y_hi), min_y + b * sy, max(x0, x1), max(y_lo, y_hi), min_y + e * sy, kind)
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
bed_frame = [(0, .12, 0, 1, .42, 1, "dark"), (0, .12, 0, 1, .62, .05, "dark"), (0, .12, .95, 1, .5, 1, "dark"),
             (.03, .42, .05, .97, .66, .95, "paper"), (.05, .66, .07, .95, .78, .3, "paper"),
             (.03, .42, .4, .97, .7, .95, "@cloth")] + [(0, 0, 0, .08, .12, .05, "dark"), (.92, 0, 0, 1, .12, .05, "dark"),
                                                       (0, 0, .95, .08, .12, 1, "dark"), (.92, 0, .95, 1, .12, 1, "dark")]
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

# ---- build & export -------------------------------------------------------------------------
manifest = {}
for name, (boxes, subs) in PROPS.items():
    if name not in BOUNDS:
        print("skip (no bounds):", name)
        continue
    info = BOUNDS[name]
    variants = [{}]
    if subs:
        keys = list(subs)
        count = max(len(v) for v in subs.values())
        variants = [{k: subs[k][i % len(subs[k])] for k in keys} for i in range(count)]
    files = []
    for i, subst in enumerate(variants):
        obj = build(f"{name}_{i}", boxes, info["size"], info["center"], info["min_y"], subst)
        filename = f"{name}_{i}.glb" if len(variants) > 1 else f"{name}.glb"
        export(obj, filename)
        files.append(filename)
    manifest[name] = files
json.dump(manifest, open(os.path.join(OUT, "manifest.json"), "w"), indent=1)
# regenerate src/config/blocky_prop_models.gd:  python3 - < tools/props/emit_models.py (see README)
print("BLOCKY PROPS OK", len(manifest), "types,", sum(len(v) for v in manifest.values()), "models")
