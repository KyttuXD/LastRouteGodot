"""Blocky room doors (single and double, normal/luxury/gothic) and the locked relay barrel.
exec'd by build_blocky_props.py after the main PROPS, so the atlas, MAT, add_box() and
OUT are in scope. Coordinates here are Blender's (x right, y depth with +y = back, z up);
Godot's z is -y.

A door keeps the contract of the old models: frame pieces and a Threshold fixed in the
doorway, plus a `DoorHinge` (and `DoorHingeRight` for doubles) node at the hinge line whose
child leaf mesh is authored in the OPEN pose (yawed 68 degrees). RouteInteractable3D closes the
door by turning the hinge by -68 degrees, so the leaf geometry is built flat (closed) and then
rotated 68 degrees about the hinge origin.
"""
import math

import mathutils

EXTRA_MANIFEST = {}


def _mesh_object(name, boxes, subst=None):
    """boxes: (x0, y0, z0, x1, y1, z1, kind) in Blender metres, no footprint normalisation."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    raw = [(min(b[0], b[3]), min(b[1], b[4]), min(b[2], b[5]), max(b[0], b[3]), max(b[1], b[4]), max(b[2], b[5]), b[6]) for b in boxes]
    extents, _pairs = resolve_coplanar([snap_extent(*r[:6]) for r in raw], [{0, 1, 2}] * len(raw))   # layered faces: see build_blocky_props
    for r, extent in zip(raw, extents):
        add_box(bm, uv, *r[:6], r[6], extent=extent)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(MAT)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def _leaf_boxes(style, width, height, handle_side):
    """A closed door leaf spanning x = 0..width from the hinge, thickness 0.1 about y = 0.
    handle_side = +1 when the free edge is at +x, -1 when it is at -x (mirrored leaf)."""
    t = .05
    sgn = handle_side
    def X(a, b):   # interval along the leaf, measured from the hinge, mirrored for the right-hand leaf
        lo, hi = sorted((sgn * a, sgn * b))
        return lo, hi
    base = {"normal": "oak", "luxury": "dark", "gothic": "black"}[style]
    panel = {"normal": "dark", "luxury": "oak", "gothic": "dark"}[style]
    boxes = []
    x0, x1 = X(0, width)
    boxes.append((x0, -t, 0.06, x1, t, height, base))
    # raised panels on both faces
    rows = [(.2, .66)] if False else None
    if style == "luxury":
        cols = [(.1, width / 2 - .05), (width / 2 + .05, width - .1)]
        row_y = [(.12, .72), (.84, 1.5), (1.62, 2.2)]
    elif style == "gothic":
        cols = [(.1, width - .1)]
        row_y = [(.12, 1.0), (1.14, 2.2)]
    else:
        cols = [(.12, width - .12)]
        row_y = [(.14, 1.04), (1.16, 2.2)]
    for (a, b) in cols:
        for (c, d) in row_y:
            if d > height - .08:
                d = height - .08
            px0, px1 = X(a, b)
            for face in (-1, 1):
                boxes.append((px0, face * t if face > 0 else -t - .03, c, px1, t + .03 if face > 0 else -t, d, panel))
    if style == "gothic":
        for yy in (.55, 1.65):
            sx0, sx1 = X(0, width)
            for face in (-1, 1):
                boxes.append((sx0, (t + .03) if face > 0 else -t - .07, yy, sx1, (t + .07) if face > 0 else -t - .03, yy + .13, "steel"))
            for rx in (.12, width * .5, width - .12):
                a, b = X(rx - .035, rx + .035)
                for face in (-1, 1):
                    boxes.append((a, (t + .07) if face > 0 else -t - .1, yy + .03, b, (t + .1) if face > 0 else -t - .07, yy + .1, "brass"))
    if style == "luxury":
        a, b = X(.08, width - .08)
        for face in (-1, 1):
            boxes.append((a, (t + .03) if face > 0 else -t - .06, .06, b, (t + .06) if face > 0 else -t - .03, .3, "brass"))
    # handle near the free edge
    hx = width - .12
    a, b = X(hx - .05, hx + .05)
    key = "steel" if style == "gothic" else "brass"
    for face in (-1, 1):
        boxes.append((a, (t) if face > 0 else -t - .06, 1.13, b, (t + .06) if face > 0 else -t, 1.23, key))
        boxes.append((a, (t + .06) if face > 0 else -t - .13, 1.1, b, (t + .13) if face > 0 else -t - .06, 1.26, key))
    return boxes


def _frame_boxes(style, half_open):
    """Fixed parts: posts, lintel, casing, threshold and the style's crown, around an opening whose
    inner half width is half_open (0.44 single, 0.96 double). Returns (frame_boxes, threshold_boxes)."""
    post = .14
    depth = .09
    outer = half_open + post * .5 + .0
    frame_kind = {"normal": "dark", "luxury": "oak", "gothic": "stone"}[style]
    trim = {"normal": "oak", "luxury": "brass", "gothic": "steel"}[style]
    fx = half_open + .07
    boxes = [
        (-fx - .07, -depth, 0, -fx + .07, depth, 2.5, frame_kind),
        (fx - .07, -depth, 0, fx + .07, depth, 2.5, frame_kind),
        (-fx - .07, -depth, 2.39, fx + .07, depth, 2.55, frame_kind),
    ]
    # casing: a thin trim just proud of both faces along the posts and lintel
    for face in (-1, 1):
        y0, y1 = (depth, depth + .025) if face > 0 else (-depth - .025, -depth)
        boxes.append((-fx - .1, y0, 0, -fx - .04, y1, 2.58, trim))
        boxes.append((fx + .04, y0, 0, fx + .1, y1, 2.58, trim))
        boxes.append((-fx - .1, y0, 2.52, fx + .1, y1, 2.6, trim))
    if style == "luxury":
        # stepped pediment crown above the lintel (both faces share it)
        boxes.append((-.36, -depth, 2.55, .36, depth, 2.63, "oak"))
        boxes.append((-.24, -depth, 2.63, .24, depth, 2.7, "brass"))
        boxes.append((-.12, -depth, 2.7, .12, depth, 2.77, "oak"))
    if style == "gothic":
        # stepped pointed crown (a spire in blocks) and chamfer blocks at the top inner corners
        boxes.append((-.3, -depth, 2.55, .3, depth, 2.63, "stone"))
        boxes.append((-.2, -depth, 2.63, .2, depth, 2.71, "stone"))
        boxes.append((-.1, -depth, 2.71, .1, depth, 2.79, "stone"))
        boxes.append((-.05, -depth, 2.79, .05, depth, 2.88, "steel"))
        for s in (-1, 1):
            boxes.append((s * (fx - .07 - .12) - .06 if s > 0 else s * (fx - .07) , -depth, 2.27, s * (fx - .07) if s > 0 else s * (fx - .07) + .12, depth, 2.39, "stone"))
    threshold = [(-fx - .1, -depth - .01, 0, fx + .1, depth + .01, .07, "stone" if style != "luxury" else "brass")]
    return boxes, threshold


def build_door(name, style, double):
    half_open = .96 if double else .44
    height = 2.31 if style == "gothic" else 2.36      # the gothic chamfer blocks end at 2.375: a leaf top there would share their plane
    objs = []
    frame, thr = _frame_boxes(style, half_open)
    objs.append(_mesh_object("DoorFrame", frame))
    objs.append(_mesh_object("Threshold", thr))
    hinge_x = -.43 if not double else -.96
    hinge = bpy.data.objects.new("DoorHinge", None)
    hinge.location = (hinge_x, 0, 0)
    bpy.context.scene.collection.objects.link(hinge)
    width = .88 if not double else .96
    leaf = _mesh_object("OpenDoorLeaf" if not double else "OpenDoorLeafLeft", _leaf_boxes(style, width, height, +1))
    leaf.parent = hinge
    leaf.rotation_euler = (0, 0, math.radians(68))
    objs.append(hinge)
    objs.append(leaf)
    if double:
        hinge_r = bpy.data.objects.new("DoorHingeRight", None)
        hinge_r.location = (.96, 0, 0)
        bpy.context.scene.collection.objects.link(hinge_r)
        leaf_r = _mesh_object("OpenDoorLeafRight", _leaf_boxes(style, width, height, -1))
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
    build_door("%sRoomDoor" % _style, _style, False)
    build_door("%sDoubleRoomDoor" % _style, _style, True)


def build_barrel():
    # A square-cut barrel: oak body, three iron bands, brass lock plate and padlock, antenna and signal head.
    boxes = [
        (-.33, -.33, 0, .33, .33, .8, "oak"),
        (-.27, -.27, .8, .27, .27, .86, "dark"),
        (-.37, -.37, .06, .37, .37, .13, "steel"),
        (-.37, -.37, .37, .37, .37 + 0, .44, "steel"),
        (-.37, -.37, .68, .37, .37, .75, "steel"),
        (-.09, -.395, .33, .09, -.35, .53, "brass"),
        (-.05, -.43, .32, .05, -.395, .45, "steel"),
        (-.03, -.03, .86, .03, .03, 1.16, "steel"),
        (-.12, -.06, .98, .12, .06, 1.12, "screen"),
    ]
    boxes = [(a, b, c, d, e, f, k) for (a, b, c, d, e, f, k) in boxes]
    obj = _mesh_object("locked_relay_barrel", boxes)
    export(obj, "locked_relay_barrel.glb")
    EXTRA_MANIFEST["__barrel"] = ["locked_relay_barrel.glb"]


build_barrel()
