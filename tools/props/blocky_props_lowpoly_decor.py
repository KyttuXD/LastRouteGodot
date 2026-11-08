"""Decor/mansion group: 51 types redone low-poly (rugs and carpets, frames, mirrors, clock, drapes and curtains, signs,
mansion pieces, sideboards and TV consoles, room doors, cell gate, cage, acoustic panel).
Exec'd by build_blocky_props.py after SIZE_SCALE and before mansion finishes, so the "<type>Mansion" sets (bedroomRugMansion,
mansionAreaRugMansion, mansionTeaCartMansion, diningSideboardMansion, normalTvConsoleMansion) are built from the new base shapes.
Keep type ids, variant slot counts, colour options, TARGET_SIZE / bounds (outer extents unchanged), fronts, colliders, atlas tiles.
Fewer boxes (repeated rows merged, back plates and trim dropped), no bevels, shared tiles; hidden_faces() culling via LOWPOLY.
mansionMarbleColumn and mansionPorcelainVase are defined later (blocky_props_mansion.py), so they get the culling only.
The six room doors are not PROPS entries (blocky_props_doors.py builds them as hinge rigs while it is exec'd): this file swaps in
simpler leaf boxes, shorter crowns and hidden-face culling and rebuilds those six GLBs (same node names, hinge positions and bounds).
"""

_DECOR_078 = [
    "apartmentCarpet", "bedroomRug", "gothicBedroomRug", "hotelCarpet", "mansionAreaRug", "corridorCarpet", "arcadeCarpetRunner",
    "arcadeCarpetCircle", "houseBathMat", "bedroomRugMansion", "mansionAreaRugMansion", "normalPaintingFrameEmpty",
    "normalPictureFrameEmpty", "luxuryPaintingFrameEmpty", "luxuryPictureFrameEmpty", "gothicPaintingFrameEmpty",
    "gothicPictureFrameEmpty", "framedWallPortrait", "bathroomMirror", "bedroomWallClock", "heavyMansionDrapes", "privacyCurtain",
    "publicMensRoomSign", "publicWomensRoomSign", "hospitalWardSign", "onAirSign", "standingMirror", "libraryGlobe",
    "mansionTeaCart", "mansionUprightPiano", "mansionGrandfatherClock", "mansionFireplace", "mansionCoatRack", "mansionBustPedestal",
    "mansionRoomDivider", "mansionMarbleColumn", "mansionPorcelainVase", "mansionTeaCartMansion", "diningSideboard",
    "diningSideboardMansion", "normalTvConsole", "normalTvConsoleMansion", "prisonCellGate", "dungeonCage", "acousticPanel",
]
# built by the door rig below, not through PROPS: normalRoomDoor normalDoubleRoomDoor luxuryRoomDoor luxuryDoubleRoomDoor gothicRoomDoor
# gothicDoubleRoomDoor


def _dc_keep_variants(name, shapes):
    old = [PROPS[name]] + list(VARIANTS.get(name, []))
    assert len(old) == len(shapes), (name, len(old), len(shapes))
    PROPS[name] = (shapes[0], old[0][1])
    VARIANTS[name] = [(s, o[1]) for s, o in zip(shapes[1:], old[1:])]


def _dc_keep_one(name, shape):
    assert name in PROPS and not VARIANTS.get(name), (name, VARIANTS.get(name))
    PROPS[name] = (shape, PROPS[name][1])


# ---- floor coverings --------------------------------------------------------------------------

def lp_rug():
    """Dark border ring + cloth field (the inner brass ring is dropped: 5 boxes, was 9)."""
    return [
        (0, 0, 0, 1, 1, .07, "dark"),
        (0, 0, .93, 1, 1, 1, "dark"),
        (0, 0, .07, .07, 1, .93, "dark"),
        (.93, 0, .07, 1, 1, .93, "dark"),
        (.07, 0, .07, .93, 1, .93, "@cloth"),
    ]


# ---- frames / mirrors / clock -----------------------------------------------------------------

def lp_frame(canvas, trim):
    """Four frame bars run to the wall and the canvas fills the back (no separate back plate)."""
    return [
        (0, 0, 0, 1, .1, 1, trim),
        (0, .9, 0, 1, 1, 1, trim),
        (0, .1, 0, .1, .9, 1, trim),
        (.9, .1, 0, 1, .9, 1, trim),
        (.1, .1, 0, .9, .9, .8, canvas),
    ]


# ---- drapes / curtains ------------------------------------------------------------------------

def lp_drapes():
    """Brass rail, one back drape and three pleats in front (was six separate pleats)."""
    out = [(0, .96, 0, 1, 1, .5, "brass"), (0, 0, .1, 1, .96, .55, "@cloth")]
    for i in (1, 3, 5):
        out.append((i / 6, 0, .55, (i + 1) / 6, .96, .8, "@cloth"))
    return out


def lp_privacy_curtain():
    """Steel rail, one curtain sheet and two pleats in front (was five panels)."""
    return [
        (0, .9, .3, 1, 1, .7, "steel"),
        (0, 0, .3, 1, .9, .6, "paper"),
        (.2, 0, .6, .4, .9, .72, "paper"),
        (.6, 0, .6, .8, .9, .72, "paper"),
    ]


# ---- signs ------------------------------------------------------------------------------------

def lp_ward_sign():
    """Plate, white cross badge with red cross, one white lettering strip (was four letter blocks)."""
    return [
        (0.0, 0.0, 0.0, 1.0, 1.0, 0.6667, "@sign"),
        (0.0632, 0.2222, 0.6667, 0.2947, 0.7778, 0.8333, "white"),
        (0.1474, 0.3056, 0.8333, 0.2105, 0.6944, 0.9167, "red"),
        (0.1053, 0.4167, 0.8333, 0.2526, 0.5833, 0.9167, "red"),
        (0.3579, 0.3889, 0.6667, 0.9053, 0.6111, 0.8333, "white"),
    ]


# ---- mansion pieces ---------------------------------------------------------------------------

def lp_globe():
    """Base, stem, meridian ring, globe, one continent, cap (second continent dropped)."""
    return [
        (0.1008, 0.0, 0.1008, 0.8992, 0.059, 0.8992, "@wood"),
        (0.4032, 0.059, 0.4032, 0.6048, 0.4717, 0.6048, "@wood"),
        (0.0, 0.4717, 0.4032, 1.0, 0.5307, 0.6048, "brass"),
        (0.2016, 0.5307, 0.2016, 0.7984, 0.8844, 0.7984, "blue"),
        (0.3024, 0.6486, 0.3024, 0.7056, 0.7665, 0.7984, "green"),
        (0.4032, 0.8844, 0.4032, 0.6048, 0.9434, 0.6048, "brass"),
    ]


def lp_room_divider():
    """Base, three cloth panels, one top rail (was three caps)."""
    return [
        (0, 0, 0, 1, .06, 1, "dark"),
        (.01, .06, .1, .3233, .94, .9, "@cloth"),
        (.3433, .06, .1, .6567, .94, .9, "@cloth"),
        (.6767, .06, .1, .99, .94, .9, "@cloth"),
        (.01, .94, .1, .99, 1, .9, "dark"),
    ]


# ---- sideboards / TV consoles -----------------------------------------------------------------

_SB_LEGS = [
    (0.02, 0.0, 0.0435, 0.0617, 0.1132, 0.1341, "dark"),
    (0.02, 0.0, 0.8659, 0.0617, 0.1132, 0.9565, "dark"),
    (0.9383, 0.0, 0.0435, 0.98, 0.1132, 0.1341, "dark"),
    (0.9383, 0.0, 0.8659, 0.98, 0.1132, 0.9565, "dark"),
]


def lp_sideboard(style):
    """Legs, one carcass (body and face frame merged), top, fronts. style 0: three drawers over one wide door (was six drawers and
    six pulls); 1 and 2: three tall doors with one pull each (the old variant layouts)."""
    out = list(_SB_LEGS) + [
        (0.02, 0.1132, 0.0, 0.98, 0.941, 0.9094, "dark"),
        (0.0, 0.941, 0.0, 1.0, 1.0, 1.0, "@top"),
    ]
    if style == 0:
        out.append((0.06, 0.1698, 0.9094, 0.94, 0.4976, 1.0, "@wood"))
        out.append((0.4583, 0.3054, 0.9094, 0.5417, 0.362, 1.0, "brass"))
        for x0, x1, k0, k1 in ((0.06, 0.3256, 0.1511, 0.2344), (0.3672, 0.6328, 0.4583, 0.5417), (0.6744, 0.94, 0.7656, 0.8489)):
            out.append((x0, 0.5566, 0.9094, x1, 0.8844, 1.0, "@wood"))
            out.append((k0, 0.6922, 0.9094, k1, 0.7488, 1.0, "brass"))
        return out
    pulls = {1: ((0.2456, 0.2872), (0.4072, 0.4489), (0.86, 0.9017)),
             2: ((0.1511, 0.2344), (0.4583, 0.5417), (0.7656, 0.8489))}[style]
    py = {1: (0.4611, 0.612), 2: (0.4988, 0.5554)}[style]
    for (x0, x1), (k0, k1) in zip(((0.06, 0.3256), (0.3672, 0.6328), (0.6744, 0.94)), pulls):
        out.append((x0, 0.1698, 0.9094, x1, 0.8844, 1.0, "@wood"))
        out.append((k0, py[0], 0.9094, k1, py[1], 1.0, "brass"))
    return out


def lp_tv_console_doors():
    """Plinth, body, three tall doors (was six), top."""
    return [
        (0, 0, 0, 1, .12, 1, "dark"),
        (0, .12, 0, 1, .88, .94, "oak"),
        (.04, .18, .94, .32, .8, 1, "dark"),
        (.36, .18, .94, .64, .8, 1, "dark"),
        (.68, .18, .94, .96, .8, 1, "dark"),
        (0, .88, 0, 1, 1, 1, "dark"),
    ]


def lp_tv_console_legs():
    """Four legs, body, two doors, top (centre knob dropped)."""
    return [
        (.04, 0, .04, .14, .5, .14, "dark"),
        (.86, 0, .04, .96, .5, .14, "dark"),
        (.04, 0, .86, .14, .5, .96, "dark"),
        (.86, 0, .86, .96, .5, .96, "dark"),
        (0, .5, 0, 1, .9, 1, "oak"),
        (.06, .56, .96, .48, .84, 1, "dark"),
        (.52, .56, .96, .94, .84, 1, "dark"),
        (0, .9, 0, 1, 1, 1, "dark"),
    ]


# ---- gates / cage / acoustic panel ------------------------------------------------------------

def lp_cell_gate():
    """Top and bottom rails, eight bars (was twelve), cross bar."""
    out = [(0, 0, 0, 1, .06, 1, "black"), (0, .94, 0, 1, 1, 1, "black")]
    for i in range(8):
        x = .02 + i * (.94 / 7)
        out.append((x, .06, .2, x + .04, .94, .8, "steel"))
    out.append((0, .45, .2, 1, .5, .8, "steel"))
    return out


def lp_cage():
    """Floor and roof slabs, five bars on the front and back (was eight), four on each side (was seven)."""
    out = [(0, 0, 0, 1, .06, 1, "black"), (0, .94, 0, 1, 1, 1, "black")]
    for i in range(5):
        x = i * .24
        out.append((x, .06, 0, x + .04, .94, .04, "steel"))
        out.append((x, .06, .96, x + .04, .94, 1, "steel"))
    for i in range(1, 5):
        z = i * .2 - .02
        out.append((0, .06, z, .04, .94, z + .04, "steel"))
        out.append((.96, .06, z, 1, .94, z + .04, "steel"))
    return out


def lp_acoustic_panel():
    """One recessed @foam2 board and eight proud @foam blocks in the same checker (was sixteen tiles)."""
    out = [(0.0, 0.0, 0.0, 1.0, 1.0, 0.625, "@foam2")]
    for cx in range(4):
        for cy in range(4):
            if (cx + cy) % 2 == 0:
                out.append((cx * .25, cy * .25, 0.625, (cx + 1) * .25, (cy + 1) * .25, 1.0, "@foam"))
    return out


for _n in ("apartmentCarpet", "bedroomRug", "gothicBedroomRug", "hotelCarpet", "mansionAreaRug", "corridorCarpet",
           "arcadeCarpetRunner", "arcadeCarpetCircle"):
    _dc_keep_one(_n, lp_rug())
for _n, _trim in (("normalPaintingFrameEmpty", "oak"), ("normalPictureFrameEmpty", "oak"), ("luxuryPaintingFrameEmpty", "brass"),
                  ("luxuryPictureFrameEmpty", "brass"), ("gothicPaintingFrameEmpty", "brass"), ("gothicPictureFrameEmpty", "brass")):
    _dc_keep_one(_n, lp_frame("@canvas", _trim))
_dc_keep_one("framedWallPortrait", lp_frame("@canvas", "brass") + [(.3, .52, .8, .7, .84, .86, "paper"), (.2, .12, .8, .8, .5, .86, "dark")])
_dc_keep_one("bathroomMirror", lp_frame("mirror", "steel"))
_dc_keep_one("heavyMansionDrapes", lp_drapes())
_dc_keep_one("privacyCurtain", lp_privacy_curtain())
_dc_keep_one("hospitalWardSign", lp_ward_sign())
_dc_keep_one("libraryGlobe", lp_globe())
_dc_keep_one("mansionRoomDivider", lp_room_divider())
_dc_keep_variants("diningSideboard", [lp_sideboard(0), lp_sideboard(1), lp_sideboard(2)])
_dc_keep_variants("normalTvConsole", [PROPS["normalTvConsole"][0], lp_tv_console_doors(), lp_tv_console_legs()])
_dc_keep_one("prisonCellGate", lp_cell_gate())
_dc_keep_one("dungeonCage", lp_cage())
_dc_keep_one("acousticPanel", lp_acoustic_panel())

LOWPOLY.update(_DECOR_078)


# ---- room doors (rebuilt: blocky_props_doors.py already exported the staging rigs while it was exec'd) ------------------------

def _dc_mesh_object(name, boxes, cull_floor=True):
    """Door-part mesh with hidden_faces() culling. Undersides are only dropped at the part's floor when cull_floor (frame, threshold);
    leaves keep theirs (a leaf hangs 6 cm above the floor)."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    raw = [(min(b[0], b[3]), min(b[1], b[4]), min(b[2], b[5]), max(b[0], b[3]), max(b[1], b[4]), max(b[2], b[5]), b[6]) for b in boxes]
    movable = [{0, 1, 2}] * len(raw)
    extents, _pairs = resolve_coplanar([snap_extent(*r[:6]) for r in raw], movable)
    floor = min(e[2] for e in extents) if cull_floor else -1e9
    skips = hidden_faces(extents, movable, floor)
    for r, extent, skip in zip(raw, extents, skips):
        add_box(bm, uv, *r[:6], r[6], extent=extent, skip=skip)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(MAT)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def _dc_leaf_boxes(style, width, height, handle_side):
    """Closed leaf from the hinge (x = 0..width, thickness 0.1 about y = 0). One raised panel per column per face (luxury keeps two
    rows), gothic keeps its two iron straps (rivets dropped), luxury its kick plate; one handle block per face (was rose + lever)."""
    t = .05
    sgn = handle_side

    def X(a, b):
        lo, hi = sorted((sgn * a, sgn * b))
        return lo, hi
    base = {"normal": "oak", "luxury": "dark", "gothic": "black"}[style]
    panel = {"normal": "dark", "luxury": "oak", "gothic": "dark"}[style]
    x0, x1 = X(0, width)
    boxes = [(x0, -t, 0.06, x1, t, height, base)]
    if style == "luxury":
        cols = [(.1, width / 2 - .05), (width / 2 + .05, width - .1)]
        row_y = [(.12, 1.0), (1.12, 2.2)]
    elif style == "gothic":
        cols = [(.1, width - .1)]
        row_y = [(.12, 2.2)]
    else:
        cols = [(.12, width - .12)]
        row_y = [(.14, 2.2)]
    for (a, b) in cols:
        for (c, d) in row_y:
            d = min(d, height - .08)
            px0, px1 = X(a, b)
            boxes.append((px0, t, c, px1, t + .03, d, panel))
            boxes.append((px0, -t - .03, c, px1, -t, d, panel))
    if style == "gothic":
        sx0, sx1 = X(0, width)
        for yy in (.55, 1.65):
            boxes.append((sx0, t + .03, yy, sx1, t + .07, yy + .13, "steel"))
            boxes.append((sx0, -t - .07, yy, sx1, -t - .03, yy + .13, "steel"))
    if style == "luxury":
        a, b = X(.08, width - .08)
        boxes.append((a, t + .03, .06, b, t + .06, .3, "brass"))
        boxes.append((a, -t - .06, .06, b, -t - .03, .3, "brass"))
    hx = width - .12
    a, b = X(hx - .05, hx + .05)
    key = "steel" if style == "gothic" else "brass"
    boxes.append((a, t, 1.1, b, t + .13, 1.26, key))
    boxes.append((a, -t - .13, 1.1, b, -t, 1.26, key))
    return boxes


def _dc_frame_boxes(style, half_open):
    """The staging posts, lintel, casing and threshold (DoorwayFrames measures the opening from them, and the threshold must not
    share a plane with the posts), with shorter crowns: luxury two steps (was three), gothic three (was four), same top heights."""
    depth = .09
    frame_kind = {"normal": "dark", "luxury": "oak", "gothic": "stone"}[style]
    trim = {"normal": "oak", "luxury": "brass", "gothic": "steel"}[style]
    fx = half_open + .07
    boxes = [
        (-fx - .07, -depth, 0, -fx + .07, depth, 2.5, frame_kind),
        (fx - .07, -depth, 0, fx + .07, depth, 2.5, frame_kind),
        (-fx - .07, -depth, 2.39, fx + .07, depth, 2.55, frame_kind),
    ]
    for face in (-1, 1):
        y0, y1 = (depth, depth + .025) if face > 0 else (-depth - .025, -depth)
        boxes.append((-fx - .1, y0, 0, -fx - .04, y1, 2.58, trim))
        boxes.append((fx + .04, y0, 0, fx + .1, y1, 2.58, trim))
        boxes.append((-fx - .1, y0, 2.52, fx + .1, y1, 2.6, trim))
    if style == "luxury":
        boxes.append((-.36, -depth, 2.55, .36, depth, 2.65, "brass"))
        boxes.append((-.12, -depth, 2.65, .12, depth, 2.77, "oak"))
    if style == "gothic":
        boxes.append((-.3, -depth, 2.55, .3, depth, 2.67, "stone"))
        boxes.append((-.1, -depth, 2.67, .1, depth, 2.79, "stone"))
        boxes.append((-.05, -depth, 2.79, .05, depth, 2.88, "steel"))
        for s in (-1, 1):
            boxes.append((s * (fx - .07 - .12) - .06 if s > 0 else s * (fx - .07), -depth, 2.27,
                          s * (fx - .07) if s > 0 else s * (fx - .07) + .12, depth, 2.39, "stone"))
    threshold = [(-fx - .1, -depth - .01, 0, fx + .1, depth + .01, .07, "stone" if style != "luxury" else "brass")]
    return boxes, threshold


def _dc_build_door(name, style, double):
    half_open = .96 if double else .44
    height = 2.31 if style == "gothic" else 2.36
    objs = []
    frame, thr = _dc_frame_boxes(style, half_open)
    objs.append(_dc_mesh_object("DoorFrame", frame))
    objs.append(_dc_mesh_object("Threshold", thr))
    hinge_x = -.43 if not double else -.96
    hinge = bpy.data.objects.new("DoorHinge", None)
    hinge.location = (hinge_x, 0, 0)
    bpy.context.scene.collection.objects.link(hinge)
    width = .88 if not double else .96
    leaf = _dc_mesh_object("OpenDoorLeaf" if not double else "OpenDoorLeafLeft", _dc_leaf_boxes(style, width, height, +1), cull_floor=False)
    leaf.parent = hinge
    leaf.rotation_euler = (0, 0, math.radians(68))
    objs.append(hinge)
    objs.append(leaf)
    if double:
        hinge_r = bpy.data.objects.new("DoorHingeRight", None)
        hinge_r.location = (.96, 0, 0)
        bpy.context.scene.collection.objects.link(hinge_r)
        leaf_r = _dc_mesh_object("OpenDoorLeafRight", _dc_leaf_boxes(style, width, height, -1), cull_floor=False)
        leaf_r.parent = hinge_r
        leaf_r.rotation_euler = (0, 0, math.radians(-68))
        objs += [hinge_r, leaf_r]
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    for o in objs:
        if o.parent is None:
            o.parent = root
    bpy.ops.object.select_all(action="DESELECT")
    for o in [root] + objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=True, export_image_format="AUTO")
    for o in [root] + objs:
        bpy.data.objects.remove(o, do_unlink=True)
    EXTRA_MANIFEST[name] = [name + ".glb"]


for _style in ("normal", "luxury", "gothic"):
    _dc_build_door("%sRoomDoor" % _style, _style, False)
    _dc_build_door("%sDoubleRoomDoor" % _style, _style, True)
