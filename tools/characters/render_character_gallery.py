#!/usr/bin/env python3
"""Render every shipped character GLB as a labelled Blender contact sheet.

Run with Blender (not ordinary Python):

    flatpak run org.blender.Blender --background --python \
      tools/characters/render_character_gallery.py -- \
      --output /tmp/last-route-characters.png --animation idle --view front

The scale multipliers match the Godot import settings: 0.9 for the player and
1.1 for hunters. This makes the sheet a useful visual companion to the
headless structural checks in scripts/validate_body.gd.
"""
from __future__ import annotations

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector


HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
CHARACTERS = os.path.join(ROOT, "art", "props-3d", "characters")


def arguments() -> argparse.Namespace:
    values = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--animation", default="idle")
    parser.add_argument("--view", choices=("front", "threequarter", "side", "rear"), default="front")
    parser.add_argument("--columns", type=int, default=7)
    parser.add_argument("--only", help="one model name, for example Aki or Player")
    parser.add_argument("--source", help="render one GLB outside the shipped character directory")
    return parser.parse_args(values)


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def evaluated_bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    points = []
    for obj in objects:
        if obj.type != "MESH":
            continue
        evaluated = obj.evaluated_get(depsgraph)
        points.extend(evaluated.matrix_world @ Vector(corner) for corner in evaluated.bound_box)
    if not points:
        return Vector((0, 0, 0)), Vector((0, 0, 0))
    return (
        Vector(tuple(min(point[index] for point in points) for index in range(3))),
        Vector(tuple(max(point[index] for point in points) for index in range(3))),
    )


def select_action(objects: list[bpy.types.Object], actions: list[bpy.types.Action], name: str) -> None:
    wanted = name.lower()
    action = next((item for item in actions if item.name.lower().split(".")[0] == wanted), None)
    if action is None:
        action = next((item for item in actions if wanted in item.name.lower()), None)
    if action is None:
        return
    slots = {slot.identifier: slot for slot in action.slots}
    for obj in objects:
        # Character glTFs are rigid node hierarchies, not skinned Armatures.
        # Blender imports each shared animation as a slot-based Action whose
        # identifiers match the animated objects (OBL-Thigh, OBChest, ...).
        # Assigning only an armature leaves the import's default idle action on
        # every mesh and makes a requested walk/sprint gallery silently lie.
        slot = slots.get(f"OB{obj.name}")
        if slot is None:
            if obj.animation_data is not None:
                obj.animation_data.action = None
            continue
        obj.animation_data_create()
        obj.animation_data.action = action
        obj.animation_data.action_slot = slot
    start, end = action.frame_range
    bpy.context.scene.frame_set(round(start + (end - start) * 0.35))


def card_material() -> bpy.types.Material:
    material = bpy.data.materials.new("GalleryCard")
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (0.012, 0.018, 0.032, 1)
    shader.inputs["Roughness"].default_value = 1
    return material


def label_material() -> bpy.types.Material:
    material = bpy.data.materials.new("GalleryLabel")
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (0.35, 0.75, 1.0, 1)
    shader.inputs["Emission Color"].default_value = (0.08, 0.3, 0.55, 1)
    shader.inputs["Emission Strength"].default_value = 0.5
    return material


def make_card(x: float, z: float, width: float, height: float, material: bpy.types.Material) -> None:
    bpy.ops.mesh.primitive_plane_add(size=2, location=(x, 0.75, z + height / 2))
    card = bpy.context.object
    card.name = "GalleryCard"
    card.scale = (width / 2, height / 2, 1)
    card.rotation_euler.x = math.pi / 2
    card.data.materials.append(material)


def make_label(text: str, x: float, z: float, material: bpy.types.Material) -> None:
    curve = bpy.data.curves.new(f"{text}Label", "FONT")
    curve.body = text
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    curve.size = 0.19
    curve.extrude = 0.002
    curve.materials.append(material)
    label = bpy.data.objects.new(f"{text}Label", curve)
    bpy.context.collection.objects.link(label)
    label.location = (x, -0.78, z - 0.19)
    label.rotation_euler.x = math.pi / 2


def import_character(path: str, title: str, x: float, ground: float, animation: str, view: str) -> None:
    old_objects = set(bpy.data.objects)
    old_actions = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=path, import_shading="NORMALS")
    objects = [obj for obj in bpy.data.objects if obj not in old_objects]
    actions = [action for action in bpy.data.actions if action not in old_actions]
    select_action(objects, actions, animation)

    pivot = bpy.data.objects.new(f"{title}Pivot", None)
    bpy.context.collection.objects.link(pivot)
    imported = set(objects)
    for obj in objects:
        if obj.parent not in imported:
            obj.parent = pivot
    scale = 0.9 if title == "Player" else 1.1
    pivot.scale = (scale, scale, scale)
    pivot.rotation_euler.z = {
        # The glTF Y-up -> Blender Z-up conversion maps the model's -Z front
        # toward Blender +Y. The gallery camera looks from -Y, so turn the
        # imported model around for a true face-on view.
        "front": math.pi,
        "threequarter": math.pi * 0.75,
        "side": math.pi / 2,
        "rear": 0.0,
    }[view]
    bpy.context.view_layer.update()
    minimum, maximum = evaluated_bounds(objects)
    center_x = (minimum.x + maximum.x) / 2
    pivot.location.x += x - center_x
    pivot.location.z += ground - minimum.z


def main() -> None:
    args = arguments()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1792
    scene.render.resolution_y = 1120
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.render.filepath = os.path.abspath(args.output)
    scene.world = bpy.data.worlds.new("GalleryWorld")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.004, 0.007, 0.015, 1)
    background.inputs["Strength"].default_value = 0.08
    scene.view_settings.look = "AgX - Medium High Contrast"

    if args.source:
        paths = [(os.path.splitext(os.path.basename(args.source))[0].title(), os.path.abspath(args.source))]
    else:
        paths = [("Player", os.path.join(CHARACTERS, "mannequin.glb"))]
        paths.extend((os.path.splitext(name)[0].title(), os.path.join(CHARACTERS, name))
                     for name in sorted(os.listdir(CHARACTERS))
                     if name.endswith(".glb") and name != "mannequin.glb")
    if args.only:
        paths = [item for item in paths if item[0].lower() == args.only.lower()]
        if not paths:
            raise SystemExit(f"No shipped character named {args.only}")
    columns = min(len(paths), max(1, args.columns))
    rows = math.ceil(len(paths) / columns)
    tile_width = 2.35
    tile_height = 2.5
    total_width = columns * tile_width
    total_height = rows * tile_height
    if len(paths) == 1:
        scene.render.resolution_x = 720
        scene.render.resolution_y = 900
    card = card_material()
    label = label_material()

    for index, (title, path) in enumerate(paths):
        column = index % columns
        row = index // columns
        x = (column + 0.5) * tile_width - total_width / 2
        ground = total_height / 2 - (row + 1) * tile_height + 0.36
        make_card(x, ground - 0.32, tile_width - 0.06, tile_height - 0.06, card)
        import_character(path, title, x, ground, args.animation, args.view)
        make_label(title, x, ground, label)

    bpy.ops.object.light_add(type="AREA", location=(0, -8, total_height / 2 + 4))
    key = bpy.context.object
    key.data.energy = 750
    key.data.shape = "RECTANGLE"
    key.data.size = total_width
    key.data.size_y = total_height
    look_at(key, Vector((0, 0, 0)))
    bpy.ops.object.light_add(type="AREA", location=(-total_width / 2, -3, total_height / 2))
    fill = bpy.context.object
    fill.data.energy = 350
    fill.data.color = (0.3, 0.48, 1.0)
    fill.data.size = total_height
    look_at(fill, Vector((0, 0, 0)))

    bpy.ops.object.camera_add(location=(0, -32, 0))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    # Blender's orthographic scale is the horizontal camera-frame span. A
    # height-only value cropped the outer columns and the heads of row one on
    # the wide 7-column roster sheet even though single-character previews
    # looked correct. Fit both axes at the actual output aspect ratio.
    aspect = scene.render.resolution_x / scene.render.resolution_y
    camera.data.ortho_scale = max(total_width + 0.35,
                                  (total_height + 0.35) * aspect)
    look_at(camera, Vector((0, 0, 0)))
    scene.camera = camera
    os.makedirs(os.path.dirname(scene.render.filepath), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    print(f"Rendered {len(paths)} characters to {scene.render.filepath}")


if __name__ == "__main__":
    main()
