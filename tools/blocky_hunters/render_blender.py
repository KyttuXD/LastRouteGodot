"""Neutral-light presentation renders of blocky hunter GLBs (Blender, headless).

blender --background --python render_blender.py -- OUTDIR CLIP TIME name[,name...] [views]
views: front,threeq,back,head,side (default front,threeq,back,head). Several hunters are placed
side by side in each view ("lineup")."""
import bpy, sys, math, os
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT, CLIP, T, NAMES = argv[0], argv[1], float(argv[2]), argv[3].split(",")
VIEWS = (argv[4] if len(argv) > 4 else "front,threeq,back,head").split(",")
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.render.fps = 30
sh = sc.display.shading
sh.light = "FLAT"; sh.color_type = "TEXTURE"
sh.show_object_outline = False; sh.object_outline_color = (0.02, 0.02, 0.04)
sc.display.render_aa = "OFF"
sc.render.film_transparent = False
sc.render.use_freestyle = not os.environ.get("NO_OUTLINE")
vl = bpy.context.view_layer
vl.use_freestyle = not os.environ.get("NO_OUTLINE")
fs = vl.freestyle_settings
ls = fs.linesets.new("outline") if len(fs.linesets) == 0 else fs.linesets[0]
ls.linestyle = bpy.data.linestyles.new("o")
ls.select_silhouette = True; ls.select_border = True; ls.select_crease = True
ls.linestyle.color = (0.02, 0.02, 0.05); ls.linestyle.thickness = 3.0
sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.12, 0.12, 0.2)
sc.render.resolution_x, sc.render.resolution_y = 900, 1100
sc.view_settings.view_transform = "Standard"

objs = []
for i, n in enumerate(NAMES):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=n if n.endswith(".glb") else f"{ROOT}/assets/hunters_blocky/{n}/{n}.glb")
    new = [o for o in bpy.data.objects if o not in before]
    root = [o for o in new if o.parent is None][0]
    root.location.x += i * 1.5
    objs.append((n, root, new))
    act = bpy.data.actions.get(CLIP + "-loop") or bpy.data.actions.get(CLIP)
    if act and CLIP != "none":
        for o in new:
            slot = next((s for s in act.slots if s.identifier == "OB" + o.name), None)
            if slot is None:
                continue
            o.animation_data_create()
            o.animation_data.action = act
            o.animation_data.action_slot = slot
ATTACH = os.environ.get("ATTACH")         # "<hunter>:<node>:<glb>": parent an extra GLB (a prop) under that node
if ATTACH:
    from mathutils import Matrix
    who, node_name, glb = ATTACH.split(":", 2)
    for n, root, new in objs:
        if n == who:
            holder = next(o for o in new if o.name == node_name or o.name.startswith(node_name + "."))
            before = set(bpy.data.objects)
            bpy.ops.import_scene.gltf(filepath=glb)
            prop_root = [o for o in bpy.data.objects if o not in before and o.parent is None][0]
            prop_root.parent = holder
            prop_root.matrix_parent_inverse = Matrix()       # identity local transform, like a glTF child node

def flat_alpha_clip(mat):
    """Unlit texture with a hard alpha cut-off, so cut-out texels (hair shell, wings) really are holes."""
    img = None
    for n in mat.node_tree.nodes if mat.use_nodes else []:
        if n.type == "TEX_IMAGE":
            img = n.image
    if img is None:
        return
    nt = mat.node_tree
    nt.nodes.clear()
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img; tex.interpolation = "Closest"
    em = nt.nodes.new("ShaderNodeEmission")
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    gt = nt.nodes.new("ShaderNodeMath"); gt.operation = "GREATER_THAN"; gt.inputs[1].default_value = 0.5
    mix = nt.nodes.new("ShaderNodeMixShader")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(tex.outputs["Color"], em.inputs["Color"])
    nt.links.new(tex.outputs["Alpha"], gt.inputs[0])
    nt.links.new(gt.outputs[0], mix.inputs[0])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    try:
        mat.surface_render_method = "DITHERED"
    except Exception:
        pass


for mat in bpy.data.materials:
    flat_alpha_clip(mat)
sc.render.engine = "BLENDER_EEVEE"
try:
    sc.eevee.taa_render_samples = 1
except Exception:
    pass
sc.frame_set(int(T * 30))
bpy.context.view_layer.update()

cam = bpy.data.cameras.new("c"); cam.type = "ORTHO"
co = bpy.data.objects.new("c", cam); sc.collection.objects.link(co); sc.camera = co
cx = (len(NAMES) - 1) * 0.75


def shot(name, az, h0, h1, aspect=None):
    """camera looks at x=cx, at height mid; az degrees around Z (0 = from the front, -Y... )."""
    mid = (h0 + h1) / 2
    cam.ortho_scale = max(h1 - h0, 0.3) * 1.1
    if name == "head":
        sc.render.resolution_x, sc.render.resolution_y = 900, 900
    elif len(NAMES) > 1:
        sc.render.resolution_x, sc.render.resolution_y = 1400, 1000
        cam.ortho_scale = max((h1 - h0) * 1.1 * 1.4, len(NAMES) * 1.5)
    else:
        sc.render.resolution_x, sc.render.resolution_y = 900, 1100
        cam.ortho_scale = (h1 - h0) * 1.25
    r = 6
    a = math.radians(az)
    co.location = (cx + r * math.sin(a), -r * math.cos(a) - 0, mid)
    # glTF import: character faces -Z glTF = +Y Blender?  camera aims at target
    d = Vector((cx, 0, mid)) - co.location
    co.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = f"{OUT}/{'-'.join(os.path.basename(x).replace('.glb','') for x in NAMES)}_{CLIP}_{name}.png"
    bpy.ops.render.render(write_still=True)


FRAME = os.environ.get("FRAME_Y")
y0f, y1f = (float(x) for x in FRAME.split(",")) if FRAME else (-0.02, 2.1)
for v in VIEWS:
    az = {"front": 180, "threeq": 150, "back": 0, "side": 90, "head": 160}[v]
    if os.environ.get("AZ"):
        az = float(os.environ["AZ"])               # turntable: any camera angle
    if v == "head":
        shot(v, az, 1.0, 1.78 + 0.0) if not FRAME else shot(v, az, y0f, y1f)
    else:
        shot(v, az, y0f, y1f)
