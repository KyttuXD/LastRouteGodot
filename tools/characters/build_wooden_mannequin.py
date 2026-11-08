"""Builds the low-poly wooden artist's mannequin used as the player body.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/characters/build_wooden_mannequin.py -- \
        assets/characters/wooden_mannequin.glb

Separate faceted segment meshes parented as a plain object hierarchy (pelvis ->
waist -> chest -> neck -> head / shoulders -> arms; hips -> legs), flat shaded,
ONE neutral warm-grey material. Joint rings (ball joints) are their own tiny
meshes. Eight heads tall, 1.70 m, feet at z=0 in Blender (y=0 in Godot).

Front is Blender +Y, which the glTF exporter turns into -Z: the direction the
Godot player faces. The model is exported in a relaxed arms-down pose (so its
bounds fit the player capsule); the T-pose of the references is the `tpose`
clip. Clips (rigid joint rotations, authored as NLA tracks so each becomes one
glTF animation): idle, walk, sprint, chase, crouch, sit, lay, tpose.
"""
import math
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "/tmp/wooden_mannequin.glb"
FPS = 30

# ---- clean scene -------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = FPS

MAT = bpy.data.materials.new("Wood")
MAT.use_nodes = True
bsdf = MAT.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.80, 0.77, 0.72, 1.0)
bsdf.inputs["Roughness"].default_value = 0.8
bsdf.inputs["Metallic"].default_value = 0.0


# ---- geometry helpers ----------------------------------------------------------
def loft(name, rings, sides=8, cap_top=True, cap_bottom=True, rot=0.0):
    """rings: [(z, rx, ry, cx, cy)], bottom to top; faceted lofted solid."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    layers = []
    for z, rx, ry, cx, cy in rings:
        layer = []
        for i in range(sides):
            a = rot + 2 * math.pi * i / sides
            layer.append(bm.verts.new((cx + math.cos(a) * rx, cy + math.sin(a) * ry, z)))
        layers.append(layer)
    for l in range(len(layers) - 1):
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((layers[l][i], layers[l][j], layers[l + 1][j], layers[l + 1][i]))
    if cap_bottom:
        bm.faces.new(list(reversed(layers[0])))
    if cap_top:
        bm.faces.new(layers[-1])
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    me.materials.append(MAT)
    return me


def ring_z(z0, z1, rx, ry=None, cx=0.0, cy=0.0, sides=8):
    ry = rx if ry is None else ry
    return [(z0, rx, ry, cx, cy), (z1, rx, ry, cx, cy)]


def box_points(name, pts_bottom, pts_top):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    b = [bm.verts.new(p) for p in pts_bottom]
    t = [bm.verts.new(p) for p in pts_top]
    n = len(b)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((b[i], b[j], t[j], t[i]))
    bm.faces.new(list(reversed(b)))
    bm.faces.new(t)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    me.materials.append(MAT)
    return me


def axis_loft(name, a, b, r0, r1, sides=8, mid=None):
    """Tapered segment along an arbitrary axis from point a to b."""
    a, b = Vector(a), Vector(b)
    axis = (b - a)
    length = axis.length
    rings = [(0.0, r0, r0, 0, 0)]
    if mid:
        rings.append((length * mid[0], mid[1], mid[1], 0, 0))
    rings.append((length, r1, r1, 0, 0))
    me = loft(name, rings, sides)
    q = Vector((0, 0, 1)).rotation_difference(axis.normalized())
    m = Matrix.Translation(a) @ q.to_matrix().to_4x4()
    me.transform(m)
    return me


# ---- hierarchy -----------------------------------------------------------------
objects = {}
pivots = {}   # name -> world pivot (T-pose rest)


def make(name, mesh, pivot, parent=None):
    """Object whose origin sits at `pivot`; mesh vertices are given in world coords."""
    pivot = Vector(pivot)
    if mesh is not None:
        mesh.transform(Matrix.Translation(-pivot))
        obj = bpy.data.objects.new(name, mesh)
    else:
        obj = bpy.data.objects.new(name, None)
    scene.collection.objects.link(obj)
    if parent is not None:
        obj.parent = objects[parent]
        obj.location = pivot - pivots[parent]
    else:
        obj.location = pivot
    objects[name] = obj
    pivots[name] = pivot
    return obj


def joint_ball(name, at, r, parent):
    me = loft(name + "_mesh", [(at[2] - r, r * .5, r * .5, at[0], at[1]),
                               (at[2], r, r, at[0], at[1]),
                               (at[2] + r, r * .5, r * .5, at[0], at[1])], 6)
    make(name, me, at, parent)


H = 1.70
make("Mannequin", None, (0, 0, 0))

# pelvis block + waist ring + chest
make("Pelvis", loft("pelvis_m", [(0.86, .115, .075, 0, 0), (0.93, .140, .090, 0, 0),
                                 (1.05, .125, .082, 0, 0)], 8), (0, 0, 0.96), "Mannequin")
make("Waist", loft("waist_m", [(1.045, .105, .072, 0, 0), (1.115, .105, .072, 0, 0)], 8),
     (0, 0, 1.08), "Pelvis")
make("Chest", loft("chest_m", [(1.115, .135, .085, 0, 0), (1.22, .175, .100, 0, 0),
                               (1.36, .200, .105, 0, 0), (1.43, .165, .090, 0, 0)], 8),
     (0, 0, 1.115), "Waist")
make("Neck", loft("neck_m", [(1.43, .045, .045, 0, 0), (1.50, .040, .040, 0, 0)], 8),
     (0, 0, 1.43), "Chest")
# egg-shaped plain head, tapered toward the chin, flat top
make("Head", loft("head_m", [(1.49, .040, .045, 0, 0), (1.54, .070, .085, 0, 0),
                             (1.60, .088, .100, 0, 0), (1.67, .082, .092, 0, 0),
                             (1.70, .055, .062, 0, 0)], 8, rot=math.pi / 8), (0, 0, 1.49), "Neck")
for side, sx in (("L", 1), ("R", -1)):
    # arms (T-pose geometry along +/-X), pivots at shoulder / elbow / wrist
    sh = (sx * .215, 0, 1.37)
    el = (sx * .485, 0, 1.37)
    wr = (sx * .735, 0, 1.37)
    tip = (sx * .905, 0, 1.37)
    joint_ball(f"Shoulder{side}", sh, .048, "Chest")
    make(f"UpperArm{side}", axis_loft(f"ua_{side}", sh, el, .040, .033, 6, (.35, .042)), sh, f"Shoulder{side}")
    joint_ball(f"Elbow{side}", el, .038, f"UpperArm{side}")
    make(f"Forearm{side}", axis_loft(f"fa_{side}", el, wr, .034, .027, 6, (.3, .036)), el, f"Elbow{side}")
    joint_ball(f"Wrist{side}", wr, .030, f"Forearm{side}")
    make(f"Hand{side}", axis_loft(f"hand_{side}", wr, tip, .028, .004, 4), wr, f"Wrist{side}")
    # legs, pivots at hip / knee / ankle
    hip = (sx * .072, 0, .88)
    knee = (sx * .072, 0, .48)
    ank = (sx * .072, 0, .09)
    joint_ball(f"Hip{side}", hip, .056, "Pelvis")
    make(f"Thigh{side}", axis_loft(f"th_{side}", hip, knee, .058, .042, 8, (.35, .062)), hip, f"Hip{side}")
    joint_ball(f"Knee{side}", knee, .044, f"Thigh{side}")
    make(f"Shin{side}", axis_loft(f"sh_{side}", knee, ank, .043, .030, 8, (.3, .046)), knee, f"Knee{side}")
    joint_ball(f"Ankle{side}", ank, .034, f"Shin{side}")
    # wedge foot: heel at back, toe pointed forward (+Y), sole at z=0
    x = sx * .072
    foot = box_points(f"foot_{side}",
                      [(x - .042, -.07, 0.0), (x + .042, -.07, 0.0), (x + .034, .17, 0.0), (x - .034, .17, 0.0)],
                      [(x - .036, -.06, .085), (x + .036, -.06, .085), (x + .008, .10, .035), (x - .008, .10, .035)])
    make(f"Foot{side}", foot, ank, f"Ankle{side}")

# eye attachments (the controller aligns the camera to them)
for side, sx in (("L", 1), ("R", -1)):
    make(f"{side}-Eye-Attachment", None, (sx * .035, .08, 1.62), "Head")

for obj in objects.values():
    obj.rotation_mode = "XYZ"
for name in objects:
    if name.startswith(("Shoulder", "UpperArm", "Elbow", "Forearm", "Wrist", "Hand")):
        objects[name].rotation_mode = "YXZ"   # Ry (arm down) then Rx (swing)

JOINTS = [n for n in objects if n not in ("Mannequin",) and not n.endswith("-Eye-Attachment")]
REST = {n: (objects[n].location.copy()) for n in objects}


# ---- poses & clips ---------------------------------------------------------------
def d(*v):
    return tuple(math.radians(x) for x in v)


ARM_DOWN = 78.0


def pose(**kw):
    """name -> (rx, ry, rz) degrees for the named joints (others stay neutral)."""
    return kw


def arms(swing_l=0.0, swing_r=0.0, elbow_l=0.0, elbow_r=0.0, down=ARM_DOWN, wrist=0.0):
    return {
        "ShoulderL": (0, 0, 0), "ShoulderR": (0, 0, 0),
        "UpperArmL": (swing_l, down, 0), "UpperArmR": (swing_r, -down, 0),
        "ForearmL": (elbow_l, 0, 0), "ForearmR": (elbow_r, 0, 0),
        "WristL": (wrist, 0, 0), "WristR": (wrist, 0, 0),
    }


def legs(thigh_l=0.0, thigh_r=0.0, knee_l=0.0, knee_r=0.0, ankle_l=0.0, ankle_r=0.0):
    return {"HipL": (0, 0, 0), "HipR": (0, 0, 0),
            "ThighL": (thigh_l, 0, 0), "ThighR": (thigh_r, 0, 0),
            "KneeL": (0, 0, 0), "KneeR": (0, 0, 0),
            "ShinL": (knee_l, 0, 0), "ShinR": (knee_r, 0, 0),
            "AnkleL": (0, 0, 0), "AnkleR": (0, 0, 0),
            "FootL": (ankle_l, 0, 0), "FootR": (ankle_r, 0, 0)}


def frame(root_z=0.0, root_rot=(0, 0, 0), pelvis_rot=(0, 0, 0), chest_rot=(0, 0, 0), head_rot=(0, 0, 0),
          root_y=0.0, **extra):
    f = {"Mannequin": ("loc", (0, root_y, root_z)), "_root_rot": root_rot}
    f["Pelvis"] = pelvis_rot
    f["Chest"] = chest_rot
    f["Head"] = head_rot
    f.update(extra)
    return f


def walk_frames(length, thigh, knee, arm, elbow, bob, lean, twist):
    """Four key poses over `length` seconds plus the loop close."""
    out = []
    for i, ph in enumerate((0.0, .25, .5, .75, 1.0)):
        a = math.sin(ph * 2 * math.pi)
        lift = max(0.0, math.sin(ph * 2 * math.pi + math.pi / 2))   # forward leg lifts the knee
        liftr = max(0.0, math.sin(ph * 2 * math.pi - math.pi / 2))
        f = frame(root_z=-abs(math.cos(ph * 2 * math.pi)) * bob + bob,
                  pelvis_rot=(0, 0, a * twist), chest_rot=(lean, 0, -a * twist * 1.4), head_rot=(-lean * .5, 0, 0))
        f.update(legs(thigh * a, -thigh * a, -knee * liftr, -knee * lift))
        f.update(arms(-arm * a, arm * a, elbow * (.5 + .5 * a), elbow * (.5 - .5 * a)))
        out.append((ph * length, f))
    return out


CLIPS = {}
CLIPS["idle"] = (2.4, [
    (0.0, {**frame(), **legs(), **arms(), }),
    (1.2, {**frame(root_z=.004, chest_rot=(1.5, 0, 0), head_rot=(-1.0, 1.5, 0)), **legs(), **arms(2, -2, 3, 3)}),
    (2.4, {**frame(), **legs(), **arms()}),
])
CLIPS["walk"] = (1.0, walk_frames(1.0, 26, 38, 22, 14, .012, 3, 5))
CLIPS["sprint"] = (2.0 / 3.0, walk_frames(2.0 / 3.0, 48, 70, 52, 78, .03, 12, 9))
CLIPS["chase"] = (0.5, walk_frames(0.5, 52, 75, 58, 85, .035, 15, 10))
crouch_base = lambda sway: frame(root_z=-.335, root_y=sway * .01, chest_rot=(28, 0, 0), head_rot=(-18, 0, 0),
                                 pelvis_rot=(8, 0, 0))
CLIPS["crouch"] = (1.0, [
    (0.0, {**crouch_base(0), **legs(62, 62, -105, -105, 40, 40), **arms(25, 25, 40, 40)}),
    (0.5, {**crouch_base(1), **legs(58, 66, -100, -110, 38, 42), **arms(28, 20, 42, 36)}),
    (1.0, {**crouch_base(0), **legs(62, 62, -105, -105, 40, 40), **arms(25, 25, 40, 40)}),
])
sit_pose = {**frame(root_z=-.45, chest_rot=(-4, 0, 0), pelvis_rot=(0, 0, 0)),
            **legs(88, 88, -88, -88, 0, 0), **arms(30, 30, 55, 55)}
CLIPS["sit"] = (2.4, [(0.0, sit_pose), (1.2, {**sit_pose, "Chest": (-2, 0, 0), "Head": (2, 0, 0), **arms(31, 29, 56, 54)}), (2.4, sit_pose)])
lay_pose = {**frame(root_z=.115, root_rot=(-90, 0, 0)), **legs(), **arms(0, 0, 0, 0, down=ARM_DOWN + 4)}
CLIPS["lay"] = (2.4, [(0.0, lay_pose), (1.2, {**lay_pose, "Chest": (1.2, 0, 0)}), (2.4, lay_pose)])
tpose = {**frame(), **legs(), **arms(down=0.0)}
# a hair of motion so the exporter does not drop the clip as constant
tpose_b = {**frame(), **legs(), **arms(down=0.6)}
CLIPS["tpose"] = (1.0, [(0.0, tpose), (0.5, {**tpose_b, "Head": (0, 0, 1.0)}), (1.0, tpose)])


def apply_frame(f):
    """Set every joint from a pose dict, neutral where unspecified."""
    for name in JOINTS:
        objects[name].rotation_euler = (0, 0, 0)
    objects["Mannequin"].location = REST["Mannequin"]
    objects["Mannequin"].rotation_euler = (0, 0, 0)
    for key, val in f.items():
        if key == "Mannequin":
            objects["Mannequin"].location = REST["Mannequin"] + Vector(val[1])
        elif key == "_root_rot":
            objects["Mannequin"].rotation_euler = d(*val)
        elif key in objects:
            objects[key].rotation_euler = d(*val)


# per-clip safety margin: Godot interpolates between keys, so the deepest foot
# between two keys can sit a little below the keyed minimum
EXTRA_LIFT = {"crouch": 0.03, "walk": 0.014, "sprint": 0.01, "chase": 0.01}


def lowest_z():
    """Lowest world-space vertex of the posed figure."""
    bpy.context.view_layer.update()
    low = 1e9
    for o in objects.values():
        if o.data is None:
            continue
        mw = o.matrix_world
        for v in o.data.vertices:
            low = min(low, (mw @ v.co).z)
    return low


def key_clip(clip, length, frames):
    scene_frame_scale = FPS
    for obj in objects.values():
        obj.animation_data_create()
        # earlier clips must not drive the joints while this one is posed
        for earlier in obj.animation_data.nla_tracks:
            earlier.mute = True
    for t, f in frames:
        apply_frame(f)
        # never let a pose sink through the floor: lift the root by whatever it
        # sinks (poses that float, like a bobbing jog, are left alone)
        sink = lowest_z()
        if sink < 0.0:
            objects["Mannequin"].location.z += -sink
        objects["Mannequin"].location.z += EXTRA_LIFT.get(clip, 0.0)
        fr = 1 + round(t * scene_frame_scale)
        for name in JOINTS + ["Mannequin"]:
            o = objects[name]
            o.keyframe_insert("rotation_euler", frame=fr, group=clip)
            if name == "Mannequin":
                o.keyframe_insert("location", frame=fr, group=clip)
    # move the freshly keyed action into its own NLA track named after the clip
    for name in JOINTS + ["Mannequin"]:
        o = objects[name]
        act = o.animation_data.action
        if act is None:
            continue
        act.name = f"{clip}_{name}"
        track = o.animation_data.nla_tracks.new()
        track.name = clip + "-loop"
        strip = track.strips.new(clip, 1, act)
        strip.name = clip
        o.animation_data.action = None


# NLA evaluates bottom-to-top and the last track wins the exported rest pose, so
# idle (frame 1 = relaxed arms-down stance) is keyed last and tpose first.
ORDER = ["tpose", "sit", "lay", "crouch", "walk", "chase", "sprint", "idle"]
for clip in ORDER:
    length, frames = CLIPS[clip]
    key_clip(clip, length, frames)

# exported rest pose: relaxed, arms down (fits the player capsule)
apply_frame({**frame(), **legs(), **arms()})
scene.frame_set(1)
for o in objects.values():
    for track in o.animation_data.nla_tracks if o.animation_data else []:
        track.mute = False
bpy.context.view_layer.update()

# Hand attachment empties: the game hangs held items on "R-Attachment", whose
# local +Y points along the avatar's forward axis (a -90 degree turn about X).
# Created last so they pick up the evaluated relaxed rest pose, then parented
# with an inverse so they follow the hands through every clip.
for side, sx in (("R", -1), ("L", 1)):
    hand = objects[f"Hand{side}"]
    empty = bpy.data.objects.new(f"{side}-Attachment", None)
    scene.collection.objects.link(empty)
    empty.matrix_world = Matrix.Translation(hand.matrix_world.translation) @ Matrix.Rotation(math.radians(-90), 4, "X")
    empty.parent = hand
    empty.matrix_parent_inverse = hand.matrix_world.inverted()
    objects[f"{side}-Attachment"] = empty

bpy.ops.export_scene.gltf(
    filepath=OUT, export_format="GLB", export_animations=True,
    export_animation_mode="NLA_TRACKS", export_apply=False, export_yup=True,
    export_force_sampling=True, export_optimize_animation_size=False,
    export_extras=False, export_lights=False, export_cameras=False)
tris = sum(len(o.data.polygons) for o in objects.values() if o.data)
print("WOODEN MANNEQUIN OK:", OUT, "parts", sum(1 for o in objects.values() if o.data), "faces", tris)
