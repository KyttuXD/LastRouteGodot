"""Contact sheet of prop GLBs, rendered headless with Blender's workbench engine (texture colours, flat light).

    /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/props/render_sheet.py -- \
        OUT.png GLB_DIR name1,name2,... [front|three|side|top] [COLUMNS]

Each name is a file stem in GLB_DIR (e.g. woodenChair_0). Used for before/after sheets.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT, GLB_DIR, NAMES = argv[0], argv[1], [n for n in argv[2].split(",") if n]
VIEW = argv[3] if len(argv) > 3 else "three"
COLS = int(argv[4]) if len(argv) > 4 else min(6, max(1, len(NAMES)))

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "FLAT"
scene.display.shading.color_type = "TEXTURE"
scene.display.shading.show_object_outline = True
scene.display.shading.object_outline_color = (0, 0, 0)
scene.render.film_transparent = False
world = bpy.data.worlds.new("w")
world.color = (0.16, 0.14, 0.18)
scene.world = world

CELL = 3.2
rows = math.ceil(len(NAMES) / COLS)
for i, name in enumerate(NAMES):
    path = os.path.join(GLB_DIR, name + ".glb")
    if not os.path.exists(path):
        print("missing", path)
        continue
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    root = bpy.data.objects.new("root_" + name, None)
    scene.collection.objects.link(root)
    for o in new:
        if o.parent is None:
            o.parent = root
    col, row = i % COLS, i // COLS
    root.location = (col * CELL, -row * CELL, 0)
    # the game faces props toward +Z (Godot) = -Y in Blender: the front looks at the camera in "front" and "three" views

cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
cx, cy = (COLS - 1) * CELL / 2, -(rows - 1) * CELL / 2
height = 1.7 if VIEW != "top" else 0.0
if VIEW == "front":
    cam.location = (cx, cy - 20, 1.0 + 0.0)
    cam.rotation_euler = (math.radians(90), 0, 0)
elif VIEW == "side":
    cam.location = (cx + 20, cy, 1.0)
    cam.rotation_euler = (math.radians(90), 0, math.radians(90))
elif VIEW == "top":
    cam.location = (cx, cy, 20)
    cam.rotation_euler = (0, 0, 0)
else:   # three-quarter from front-right, above
    d = 20
    cam.location = (cx + d * 0.5, cy - d * 0.8 + 0, 9)
    direction = Vector((cx, cy, 0.7)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
cam_data.ortho_scale = COLS * CELL * (1.05 if VIEW != "three" else 0.85)
scene.render.resolution_x = int(COLS * 320)
scene.render.resolution_y = int(max(1, rows) * 320 * (1.0 if VIEW == "top" else 1.0))
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("SHEET", OUT)
