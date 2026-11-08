"""Render prop GLBs one per image (same camera and metres-per-pixel for every image of a call), for labelled before/after sheets.

    blender --background --python tools/props/render_each.py -- OUT_DIR GLB_DIR name1,name2,... ORTHO_METRES [three|side] [PX]

Writes OUT_DIR/<name>.png. Blender workbench, flat light, texture colours, black outlines (the render_sheet.py look); the camera
aims at a fixed point 0.6 m up, so props in one call share one scale and one floor line. Used by make_078_seating_sheet.py.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT, GLB_DIR, NAMES, ORTHO = argv[0], argv[1], [n for n in argv[2].split(",") if n], float(argv[3])
VIEW = argv[4] if len(argv) > 4 else "three"
PX = int(argv[5]) if len(argv) > 5 else 360
os.makedirs(OUT, exist_ok=True)

for name in NAMES:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "FLAT"
    scene.display.shading.color_type = "TEXTURE"
    scene.display.shading.show_object_outline = True
    scene.display.shading.object_outline_color = (0, 0, 0)
    world = bpy.data.worlds.new("w")
    world.color = (0.42, 0.40, 0.45)
    scene.world = world
    bpy.ops.import_scene.gltf(filepath=os.path.join(GLB_DIR, name + ".glb"))
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ORTHO
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    target = Vector((0, 0, ORTHO * 0.2))
    if VIEW == "side":
        cam.location = target + Vector((20, 0, 0))
    else:
        cam.location = target + Vector((10, -16, 9))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x = PX
    scene.render.resolution_y = PX
    scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
print("RENDERED", len(NAMES))
