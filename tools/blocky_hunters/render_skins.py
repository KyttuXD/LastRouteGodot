"""Steve (classic) and Alex (slim) reference skins on the player mannequins, side by side (Blender, headless):

blender --background --python tools/blocky_hunters/render_skins.py -- OUT.png

The two glb files are textured with docs/images/player_skin_steve_reference.png / player_skin_alex_reference.png (nearest filtering, so the
pixels read as pixels). Views: front, three-quarter, back."""
import bpy, sys, os, math
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1]
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light = "FLAT"; sh.color_type = "TEXTURE"
sc.display.render_aa = "OFF"
sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.16, 0.17, 0.24)
sc.view_settings.view_transform = "Standard"
sc.render.resolution_x, sc.render.resolution_y = 1500, 760


def load(name, skin, x):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f"{ROOT}/assets/hunters_blocky/{name}/{name}.glb")
    new = [o for o in bpy.data.objects if o not in before]
    image = bpy.data.images.load(f"{ROOT}/docs/{skin}")
    for o in new:
        if o.parent is None:
            o.location.x += x
        for slot in getattr(o, "material_slots", []):
            if slot.material and slot.material.use_nodes:
                for node in slot.material.node_tree.nodes:
                    if node.type == "TEX_IMAGE":
                        node.image = image
                        node.interpolation = "Closest"
    return new


load("player_mannequin", "player_skin_steve_reference.png", -0.8)
load("player_mannequin_slim", "player_skin_alex_reference.png", 0.8)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = 4.6
frames = []
for i, (label, yaw) in enumerate([("front", 180), ("threeq", 215), ("back", 0)]):
    d = 8.0
    cam.location = Vector((math.sin(math.radians(yaw)) * d, -math.cos(math.radians(yaw)) * d, 0.95))
    direction = Vector((0, 0, 0.9)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    path = OUT.replace(".png", f"_{label}.png")
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    frames.append(path)
print("FRAMES", " ".join(frames))
