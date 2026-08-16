#!/usr/bin/env python3
"""Render labelled character-animation frames with the gallery's Blender setup.

Run with Blender (not ordinary Python), then assemble the PNG sequence into a
GIF or video with the encoder of your choice:

    flatpak run org.blender.Blender --background --python \
      /absolute/path/to/render_animation_preview.py -- \
      --output-dir /tmp/last-route-animation-frames \
      --models Player,Aki --clips idle,walk,sprint,chase,crouch

The glTF clips are imported at their authored 30 FPS timing and sampled without
stretching them to the preview segment length. The label reports the actual
imported action span, so the result matches the cadence Godot receives.
"""
from __future__ import annotations

import argparse
import math
import os
import sys
from dataclasses import dataclass

import bpy
from mathutils import Vector


HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
CHARACTERS = os.path.join(ROOT, "art", "props-3d", "characters")

VIEW_ROTATIONS = {
    "front": math.pi,
    "threequarter": math.pi * 0.75,
    "side": math.pi / 2,
    "rear": 0.0,
}
CLIP_LABELS = {
    "idle": "IDLE",
    "walk": "WALK",
    "sprint": "SPRINT / RUN",
    "chase": "HUNTER CHASE",
    "crouch": "CROUCH",
}


@dataclass
class Character:
    title: str
    objects: list[bpy.types.Object]
    actions: list[bpy.types.Action]


def arguments() -> argparse.Namespace:
    values = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--models", default="Player,Aki")
    parser.add_argument("--clips", default="idle,walk,sprint,chase,crouch")
    parser.add_argument("--view", choices=tuple(VIEW_ROTATIONS), default="threequarter")
    parser.add_argument("--fps", type=int, default=10)
    parser.add_argument("--seconds-per-clip", type=float, default=1.2)
    parser.add_argument("--width", type=int, default=960)
    parser.add_argument("--height", type=int, default=600)
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


def shader_material(name: str, color: tuple[float, float, float, float],
                    emission: tuple[float, float, float, float] | None = None) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Roughness"].default_value = 1
    if emission:
        shader.inputs["Emission Color"].default_value = emission
        shader.inputs["Emission Strength"].default_value = 0.55
    return material


def make_card(x: float, width: float, material: bpy.types.Material) -> None:
    bpy.ops.mesh.primitive_plane_add(size=2, location=(x, 0.75, 0))
    card = bpy.context.object
    card.name = "PreviewCard"
    card.scale = (width / 2, 1.42, 1)
    card.rotation_euler.x = math.pi / 2
    card.data.materials.append(material)


def make_text(text: str, name: str, x: float, z: float, size: float,
              material: bpy.types.Material) -> bpy.types.Object:
    curve = bpy.data.curves.new(name, "FONT")
    curve.body = text
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    curve.size = size
    curve.extrude = 0.002
    curve.materials.append(material)
    label = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(label)
    label.location = (x, -0.78, z)
    label.rotation_euler.x = math.pi / 2
    return label


def model_path(title: str) -> str:
    stem = "mannequin" if title.lower() == "player" else title.lower()
    path = os.path.join(CHARACTERS, f"{stem}.glb")
    if not os.path.isfile(path):
        raise SystemExit(f"No shipped character named {title}")
    return path


def normalized_action_name(name: str) -> str:
    base, separator, suffix = name.rpartition(".")
    return base.lower() if separator and suffix.isdigit() else name.lower()


def find_action(character: Character, clip: str) -> bpy.types.Action:
    wanted = clip.lower()
    action = next((item for item in character.actions
                   if normalized_action_name(item.name) == wanted), None)
    if action is None:
        action = next((item for item in character.actions if wanted in item.name.lower()), None)
    if action is None:
        raise SystemExit(f"{character.title} has no {clip!r} animation")
    return action


def import_character(title: str, x: float, ground: float, view: str) -> Character:
    old_objects = set(bpy.data.objects)
    old_actions = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=model_path(title), import_shading="NORMALS")
    objects = [obj for obj in bpy.data.objects if obj not in old_objects]
    actions = [action for action in bpy.data.actions if action not in old_actions]
    character = Character(title, objects, actions)

    # Give bounds evaluation a stable authored pose before positioning.
    idle = find_action(character, "idle")
    assign_action(character, idle)
    bpy.context.scene.frame_set(round(idle.frame_range[0]))

    pivot = bpy.data.objects.new(f"{title}PreviewPivot", None)
    bpy.context.collection.objects.link(pivot)
    imported = set(objects)
    for obj in objects:
        if obj.parent not in imported:
            obj.parent = pivot
    scale = 0.9 if title.lower() == "player" else 1.1
    pivot.scale = (scale, scale, scale)
    pivot.rotation_euler.z = VIEW_ROTATIONS[view]
    bpy.context.view_layer.update()
    minimum, maximum = evaluated_bounds(objects)
    pivot.location.x += x - (minimum.x + maximum.x) / 2
    pivot.location.z += ground - minimum.z
    return character


def assign_action(character: Character, action: bpy.types.Action) -> None:
    """Assign a glTF action's matching slot to every rigid animated node.

    This exporter intentionally uses a hierarchy of rigid mesh nodes rather
    than one skinned Armature. Blender 5 imports their shared glTF animation as
    a slot-based Action (``OBL-Thigh``, ``OBChest``, ...). Assigning only an
    armature silently leaves every object on the default idle action, which is
    exactly how the first animation-review GIF mislabeled idle as every clip.
    """
    slots = {slot.identifier: slot for slot in action.slots}
    for obj in character.objects:
        slot = slots.get(f"OB{obj.name}")
        if slot is None:
            if obj.animation_data is not None:
                obj.animation_data.action = None
            continue
        obj.animation_data_create()
        obj.animation_data.action = action
        obj.animation_data.action_slot = slot


def pose(character: Character, clip: str, elapsed: float, source_fps: float) -> float:
    action = find_action(character, clip)
    assign_action(character, action)
    start, end = action.frame_range
    duration_frames = max(1.0, end - start)
    source_frame = start + (elapsed * source_fps) % duration_frames
    whole = math.floor(source_frame)
    bpy.context.scene.frame_set(whole, subframe=source_frame - whole)
    return duration_frames / source_fps


def main() -> None:
    args = arguments()
    titles = [item.strip().title() for item in args.models.split(",") if item.strip()]
    clips = [item.strip().lower() for item in args.clips.split(",") if item.strip()]
    if not titles or not clips or args.fps <= 0 or args.seconds_per_clip <= 0:
        raise SystemExit("models, clips, fps, and seconds-per-clip must be non-empty/positive")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = args.width
    scene.render.resolution_y = args.height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.film_transparent = False
    scene.render.image_settings.color_depth = "8"
    # glTF import converts key times into the scene's current FPS. Keep that at
    # the exporter's authored rate; `args.fps` controls only how often we sample
    # those actions into output images/GIF frames below.
    scene.render.fps = 30
    scene.world = bpy.data.worlds.new("AnimationPreviewWorld")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.004, 0.007, 0.015, 1)
    background.inputs["Strength"].default_value = 0.08
    scene.view_settings.look = "AgX - Medium High Contrast"

    card = shader_material("PreviewCard", (0.012, 0.018, 0.032, 1))
    cyan = shader_material("PreviewLabel", (0.35, 0.75, 1.0, 1), (0.08, 0.3, 0.55, 1))
    amber = shader_material("ClipLabel", (1.0, 0.66, 0.18, 1), (0.55, 0.18, 0.02, 1))
    tile_width = 2.35
    total_width = tile_width * len(titles)
    ground = -1.05
    characters = []
    for index, title in enumerate(titles):
        x = (index + 0.5) * tile_width - total_width / 2
        make_card(x, tile_width - 0.06, card)
        characters.append(import_character(title, x, ground, args.view))
        make_text(title, f"{title}Label", x, -1.28, 0.18, cyan)
    clip_label = make_text("", "CurrentClipLabel", 0, 1.28, 0.20, amber)

    bpy.ops.object.light_add(type="AREA", location=(0, -7, 4))
    key = bpy.context.object
    key.data.energy = 700
    key.data.shape = "RECTANGLE"
    key.data.size = total_width
    key.data.size_y = 3.2
    look_at(key, Vector((0, 0, 0)))
    bpy.ops.object.light_add(type="AREA", location=(-total_width / 2, -3, 1.5))
    fill = bpy.context.object
    fill.data.energy = 350
    fill.data.color = (0.3, 0.48, 1.0)
    fill.data.size = 3.5
    look_at(fill, Vector((0, 0, 0)))

    bpy.ops.object.camera_add(location=(0, -32, 0))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    aspect = args.width / args.height
    camera.data.ortho_scale = max(total_width + 0.35, 3.2 * aspect)
    look_at(camera, Vector((0, 0, 0)))
    scene.camera = camera

    output_dir = os.path.abspath(args.output_dir)
    os.makedirs(output_dir, exist_ok=True)
    for name in os.listdir(output_dir):
        if name.startswith("frame_") and name.endswith(".png"):
            os.remove(os.path.join(output_dir, name))
    frames_per_clip = max(1, round(args.fps * args.seconds_per_clip))
    source_fps = float(scene.render.fps)
    output_index = 0
    for clip in clips:
        action = find_action(characters[0], clip)
        duration = max(1.0, action.frame_range[1] - action.frame_range[0]) / source_fps
        label = CLIP_LABELS.get(clip, clip.upper())
        clip_label.data.body = f"{label}  //  {duration:.1f}s LOOP"
        for local_frame in range(frames_per_clip):
            elapsed = local_frame / args.fps
            # Both shipped rigs use the same authored timing. Pose each one,
            # then restore the shared scene time selected by the last call.
            for character in characters:
                pose(character, clip, elapsed, source_fps)
            scene.render.filepath = os.path.join(output_dir, f"frame_{output_index:04d}.png")
            bpy.ops.render.render(write_still=True)
            output_index += 1
    print(f"Rendered {output_index} animation frames to {output_dir}")


if __name__ == "__main__":
    main()
