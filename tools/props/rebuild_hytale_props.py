import bpy
import math
import os
import sys
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
ROOT = os.path.join(PROJECT_ROOT, "assets", "interactables")
SOURCE = os.path.join(PROJECT_ROOT, "art_source", "interactables")
TEXTURES = os.path.join(SOURCE, "textures")
PREVIEWS = os.path.join(ROOT, "previews")
INVENTORY_ICONS = os.path.join(PROJECT_ROOT, "assets", "ui", "inventory")
MAZE_ROOT = os.path.join(PROJECT_ROOT, "assets", "props", "maze")
MAZE_SOURCE = os.path.join(PROJECT_ROOT, "art_source", "props", "maze")
MAZE_TEXTURES = os.path.join(MAZE_SOURCE, "textures")
MAZE_PREVIEWS = os.path.join(MAZE_ROOT, "previews")
MANSION_ROOT = os.path.join(PROJECT_ROOT, "assets", "props", "mansion")
MANSION_SOURCE = os.path.join(PROJECT_ROOT, "art_source", "props", "mansion")
MANSION_TEXTURES = os.path.join(MANSION_SOURCE, "textures")
MANSION_PREVIEWS = os.path.join(MANSION_ROOT, "previews")
BEACH_ROOT = os.path.join(PROJECT_ROOT, "assets", "props", "beach")
BEACH_SOURCE = os.path.join(PROJECT_ROOT, "art_source", "props", "beach")
BEACH_TEXTURES = os.path.join(BEACH_SOURCE, "textures")
BEACH_PREVIEWS = os.path.join(BEACH_ROOT, "previews")
NETHER_ROOT = os.path.join(PROJECT_ROOT, "assets", "props", "nether")
NETHER_SOURCE = os.path.join(PROJECT_ROOT, "art_source", "props", "nether")
NETHER_TEXTURES = os.path.join(NETHER_SOURCE, "textures")
NETHER_PREVIEWS = os.path.join(NETHER_ROOT, "previews")
PRISON_ROOT = os.path.join(PROJECT_ROOT, "assets", "props", "prison")
PRISON_SOURCE = os.path.join(PROJECT_ROOT, "art_source", "props", "prison")
PRISON_TEXTURES = os.path.join(PRISON_SOURCE, "textures")
PRISON_PREVIEWS = os.path.join(PRISON_ROOT, "previews")
CARNIVAL_ROOT = os.path.join(PROJECT_ROOT, "assets", "props", "carnival")
CARNIVAL_SOURCE = os.path.join(PROJECT_ROOT, "art_source", "props", "carnival")
CARNIVAL_TEXTURES = os.path.join(CARNIVAL_SOURCE, "textures")
CARNIVAL_PREVIEWS = os.path.join(CARNIVAL_ROOT, "previews")
os.makedirs(TEXTURES, exist_ok=True)
os.makedirs(PREVIEWS, exist_ok=True)
os.makedirs(INVENTORY_ICONS, exist_ok=True)
os.makedirs(MAZE_TEXTURES, exist_ok=True)
os.makedirs(MAZE_PREVIEWS, exist_ok=True)
os.makedirs(MANSION_TEXTURES, exist_ok=True)
os.makedirs(MANSION_PREVIEWS, exist_ok=True)
os.makedirs(BEACH_TEXTURES, exist_ok=True)
os.makedirs(BEACH_PREVIEWS, exist_ok=True)
os.makedirs(NETHER_TEXTURES, exist_ok=True)
os.makedirs(NETHER_PREVIEWS, exist_ok=True)
os.makedirs(PRISON_TEXTURES, exist_ok=True)
os.makedirs(PRISON_PREVIEWS, exist_ok=True)
os.makedirs(CARNIVAL_TEXTURES, exist_ok=True)
os.makedirs(CARNIVAL_PREVIEWS, exist_ok=True)
SEWER_ROOT = os.path.join(PROJECT_ROOT, "assets", "props", "sewer")
SEWER_SOURCE = os.path.join(PROJECT_ROOT, "art_source", "props", "sewer")
SEWER_TEXTURES = os.path.join(SEWER_SOURCE, "textures")
SEWER_PREVIEWS = os.path.join(SEWER_ROOT, "previews")
os.makedirs(SEWER_TEXTURES, exist_ok=True)
os.makedirs(SEWER_PREVIEWS, exist_ok=True)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials,
                       bpy.data.images, bpy.data.cameras, bpy.data.lights):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def rgba(hex_color):
    value = hex_color.lstrip("#")
    return tuple(int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)) + (1.0,)


def mix(a, b, amount):
    return tuple(a[i] * (1.0 - amount) + b[i] * amount for i in range(4))


def make_pixel_atlas(name, colors, directory=None):
    """Build one small, deliberately painted atlas per prop.

    Each 16 px swatch has broad highlight/shadow blocks rather than random
    noise.  At nearest-neighbour sampling this reads like authored Hytale-ish
    pixel paint instead of a procedural material or a collection of coloured
    toy parts.
    """
    swatch = 16
    width = swatch * len(colors)
    height = swatch
    image = bpy.data.images.new(name, width=width, height=height, alpha=True)
    pixels = [0.0] * (width * height * 4)
    white = (1.0, 1.0, 1.0, 1.0)
    black = (0.0, 0.0, 0.0, 1.0)
    for region, source in enumerate(colors):
        base = rgba(source)
        light = mix(base, white, 0.16)
        high = mix(base, white, 0.28)
        dark = mix(base, black, 0.18)
        low = mix(base, black, 0.30)
        for y in range(swatch):
            for x in range(swatch):
                color = base
                if y >= 14 or x <= 1:
                    color = light
                if y == 15 and x <= 8:
                    color = high
                if y <= 1 or x >= 14:
                    color = dark
                if y == 0 and x >= 6:
                    color = low
                # A few large, repeatable brush/pixel clusters.
                if ((x // 3) + (y // 4) + region) % 7 == 0:
                    color = mix(color, light, 0.42)
                if ((x // 4) * 3 + (y // 3) + region * 2) % 11 == 0:
                    color = mix(color, dark, 0.52)
                px = ((y * width) + region * swatch + x) * 4
                pixels[px:px + 4] = color
    image.pixels[:] = pixels
    image.file_format = "PNG"
    image.filepath_raw = os.path.join(directory or TEXTURES, name + ".png")
    image.save()
    image.pack()
    return image


def make_material(name, image, roughness=0.78, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Closest"
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def apply_bevel(obj, width):
    if width <= 0.0:
        return
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    modifier = obj.modifiers.new("Single pixel chamfer", "BEVEL")
    modifier.width = width
    modifier.segments = 1
    modifier.limit_method = "ANGLE"
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False


def ensure_uv(obj):
    if obj.data.uv_layers:
        return
    # Custom meshes may be created while the preceding primitive is still
    # selected.  Isolate the target so smart-project cannot overwrite the UVs
    # of an already painted prop part.
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15192, island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")


def map_region(obj, region, region_count):
    ensure_uv(obj)
    layer = obj.data.uv_layers.active.data
    width = 1.0 / region_count
    margin = width * 0.055
    u0 = region * width + margin
    usable = width - margin * 2.0
    for loop in layer:
        u = min(1.0, max(0.0, float(loop.uv.x)))
        v = min(1.0, max(0.0, float(loop.uv.y)))
        loop.uv = (u0 + u * usable, 0.055 + v * 0.89)


def finish_object(obj, material, region, region_count, export_objects):
    obj.data.materials.append(material)
    map_region(obj, region, region_count)
    export_objects.append(obj)
    return obj


def box(name, location, dimensions, material, region, region_count,
        export_objects, bevel=0.0, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    apply_bevel(obj, min(bevel, min(dimensions) * 0.22))
    return finish_object(obj, material, region, region_count, export_objects)


def cylinder(name, location, radius, depth, vertices, material, region,
             region_count, export_objects, rotation=(0.0, 0.0, 0.0), bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius,
                                       depth=depth, location=location,
                                       rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    apply_bevel(obj, bevel)
    return finish_object(obj, material, region, region_count, export_objects)


def cone(name, location, radius1, radius2, depth, vertices, material, region,
         region_count, export_objects, rotation=(0.0, 0.0, 0.0), bevel=0.0):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius1,
                                    radius2=radius2, depth=depth,
                                    location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    apply_bevel(obj, bevel)
    return finish_object(obj, material, region, region_count, export_objects)


def triangular_prism(name, location, width, height, depth, material, region,
                     region_count, export_objects):
    """Make a flat, upright triangular pictogram piece in the X/Z plane."""
    half_width = width * 0.5
    half_height = height * 0.5
    half_depth = depth * 0.5
    vertices = [
        (-half_width, -half_depth, -half_height),
        (half_width, -half_depth, -half_height),
        (0.0, -half_depth, half_height),
        (-half_width, half_depth, -half_height),
        (half_width, half_depth, -half_height),
        (0.0, half_depth, half_height),
    ]
    faces = [
        (0, 2, 1),
        (3, 4, 5),
        (0, 1, 4, 3),
        (1, 2, 5, 4),
        (2, 0, 3, 5),
    ]
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    return finish_object(obj, material, region, region_count, export_objects)


def make_coin():
    colors = ["#543116", "#9D651E", "#D99B32", "#FFD56B", "#71303A"]
    image = make_pixel_atlas("coin_pixel_atlas", colors)
    mat = make_material("Coin pixel paint", image, roughness=0.52, metallic=0.45)
    count = len(colors)
    objects = []
    # A sharp eight-sided upright token: recognisably a coin but much closer
    # to a clipped block than a smooth minted disc.
    cylinder("CoinBody", (0.0, 0.0, 0.36), 0.17, 0.05, 8, mat, 2, count,
             objects, rotation=(math.radians(90), 0.0, 0.0), bevel=0.0)
    cylinder("CoinFrontInset", (0.0, -0.031, 0.36), 0.132, 0.018, 8, mat,
             1, count, objects, rotation=(math.radians(90), 0.0, 0.0), bevel=0.0)
    cylinder("CoinBackInset", (0.0, 0.031, 0.36), 0.132, 0.018, 8, mat,
             1, count, objects, rotation=(math.radians(90), 0.0, 0.0), bevel=0.0)
    # Block-built LR mint gives the pickup a readable game icon at a distance.
    y = -0.044
    box("Mint_L_Stem", (-0.072, y, 0.36), (0.026, 0.015, 0.105), mat, 4,
        count, objects, bevel=0.0)
    box("Mint_L_Foot", (-0.045, y, 0.319), (0.075, 0.015, 0.025), mat, 4,
        count, objects, bevel=0.0)
    box("Mint_R_Stem", (0.018, y, 0.36), (0.025, 0.015, 0.105), mat, 4,
        count, objects, bevel=0.0)
    box("Mint_R_Top", (0.055, y, 0.399), (0.075, 0.015, 0.026), mat, 4,
        count, objects, bevel=0.0)
    box("Mint_R_Mid", (0.052, y, 0.365), (0.066, 0.015, 0.022), mat, 4,
        count, objects, bevel=0.0)
    box("Mint_R_Bowl", (0.084, y, 0.384), (0.021, 0.015, 0.055), mat, 4,
        count, objects, bevel=0.0)
    box("Mint_R_Leg", (0.066, y, 0.333), (0.024, 0.015, 0.058), mat, 4,
        count, objects, bevel=0.0, rotation=(0.0, 0.0, math.radians(-22)))
    return objects, (1.08, -2.45, 1.2), (0.0, 0.0, 0.36)


def make_vent():
    colors = ["#11181C", "#344147", "#536269", "#78858A", "#844735", "#B59255"]
    image = make_pixel_atlas("vent_pixel_atlas", colors)
    mat = make_material("Vent pixel paint", image, roughness=0.82, metallic=0.18)
    count = len(colors)
    objects = []
    # Authored horizontally: Blender XY becomes Godot XZ, so the grate lands
    # flat on the floor with no scene/script rotation.
    box("VentVoid", (0.0, 0.0, 0.025), (0.74, 0.64, 0.055), mat, 0,
        count, objects, bevel=0.006)
    box("FrameFar", (0.0, 0.285, 0.06), (0.78, 0.09, 0.12), mat, 2,
        count, objects, bevel=0.014)
    box("FrameNear", (0.0, -0.285, 0.06), (0.78, 0.09, 0.12), mat, 1,
        count, objects, bevel=0.014)
    box("FrameLeft", (-0.345, 0.0, 0.06), (0.09, 0.50, 0.12), mat, 2,
        count, objects, bevel=0.014)
    box("FrameRight", (0.345, 0.0, 0.06), (0.09, 0.50, 0.12), mat, 1,
        count, objects, bevel=0.014)
    # Five broad slats replace the fussy realistic grate and stay legible in a dark maze.
    for index, y in enumerate((-0.19, -0.095, 0.0, 0.095, 0.19)):
        box("Slat_%d" % (index + 1), (0.0, y, 0.095),
            (0.59, 0.055, 0.065), mat, 2 if index % 2 == 0 else 1,
            count, objects, bevel=0.008,
            rotation=(math.radians(-5), 0.0, 0.0))
    for index, (x, y) in enumerate(((-0.34, -0.285), (0.34, -0.285),
                                    (-0.34, 0.285), (0.34, 0.285))):
        box("SquareBolt_%d" % (index + 1), (x, y, 0.126),
            (0.045, 0.045, 0.025), mat, 5 if index < 2 else 4,
            count, objects, bevel=0.004)
    # Keep the lowest chamfer safely above the floor instead of letting it
    # clip a couple of millimetres below the slot's zero-height contract.
    for obj in objects:
        obj.location.z += 0.004
    return objects, (1.20, -1.80, 1.55), (0.0, 0.0, 0.05)


def make_music_box():
    colors = ["#2B1718", "#563023", "#7E4930", "#A96D3B", "#D0A34F", "#4C2038"]
    image = make_pixel_atlas("music_box_pixel_atlas", colors)
    mat = make_material("Music box pixel paint", image, roughness=0.72, metallic=0.06)
    count = len(colors)
    objects = []
    for index, (x, y) in enumerate(((-0.205, -0.135), (-0.205, 0.135),
                                    (0.205, -0.135), (0.205, 0.135))):
        box("BlockFoot_%d" % (index + 1), (x, y, 0.03),
            (0.075, 0.075, 0.06), mat, 0, count, objects, bevel=0.0)
    box("BoxBody", (0.0, 0.0, 0.17), (0.52, 0.38, 0.28), mat, 2,
        count, objects, bevel=0.004)
    box("FrontInset", (0.0, -0.204, 0.18), (0.37, 0.025, 0.13), mat, 1,
        count, objects, bevel=0.001)
    box("FrontGoldLine", (0.0, -0.22, 0.18), (0.26, 0.014, 0.022), mat, 4,
        count, objects, bevel=0.0)
    box("VelvetWell", (0.0, -0.015, 0.325), (0.40, 0.25, 0.04), mat, 5,
        count, objects, bevel=0.001)
    # Chunky open lid with a broad inset rather than thin ornamental moulding.
    box("OpenLid", (0.0, 0.085, 0.405), (0.53, 0.32, 0.085), mat, 3,
        count, objects, bevel=0.003,
        rotation=(math.radians(-17), 0.0, 0.0))
    box("LidInset", (0.0, -0.079, 0.42), (0.34, 0.025, 0.16), mat, 1,
        count, objects, bevel=0.0,
        rotation=(math.radians(-17), 0.0, 0.0))
    for x in (-0.18, 0.18):
        box("LidHinge_%s" % ("L" if x < 0 else "R"),
            (x, 0.165, 0.34), (0.075, 0.055, 0.055), mat, 0,
            count, objects, bevel=0.001)
    box("MusicDrum", (0.0, -0.025, 0.385), (0.26, 0.105, 0.105), mat,
        4, count, objects, bevel=0.002)
    for x in (-0.15, 0.15):
        box("CylinderPost_%s" % ("L" if x < 0 else "R"),
            (x, -0.025, 0.37), (0.04, 0.07, 0.11), mat, 1,
            count, objects, bevel=0.001)
    # Square-to-octagonal crank reads as hand-authored low-poly machinery.
    box("CrankAxle", (0.295, 0.0, 0.205), (0.09, 0.045, 0.045), mat, 4,
        count, objects, bevel=0.0)
    box("CrankArm", (0.35, 0.0, 0.265), (0.035, 0.045, 0.13), mat, 4,
        count, objects, bevel=0.0,
        rotation=(0.0, math.radians(-18), 0.0))
    box("CrankKnob", (0.385, 0.0, 0.325), (0.075, 0.07, 0.07), mat,
        0, count, objects, bevel=0.001)
    return objects, (1.28, -2.2, 1.25), (0.0, 0.0, 0.24)


def make_locker():
    colors = ["#10161B", "#293944", "#3C5260", "#587080", "#9E7741", "#71413B", "#B6AD91"]
    image = make_pixel_atlas("locker_pixel_atlas", colors)
    mat = make_material("Locker pixel paint", image, roughness=0.82, metallic=0.08)
    dark_mat = make_material("Locker recess pixel paint", image, roughness=0.94, metallic=0.0)
    trim_mat = make_material("Locker trim pixel paint", image, roughness=0.70, metallic=0.18)
    hardware_mat = make_material("Locker hardware pixel paint", image, roughness=0.48, metallic=0.42)
    count = len(colors)
    objects = []
    # Build a genuinely hollow shell.  The older single solid cabinet cube sat
    # immediately behind the decorative vent marks, so a camera placed inside
    # the locker could never actually see through them.  A back and two side
    # walls preserve the same exterior silhouette while leaving the front
    # opening physically clear.
    box("LockerBack", (0.0, 0.22, 0.97), (0.70, 0.06, 1.84), mat, 1,
        count, objects, bevel=0.018)
    for side, x in (("L", -0.32), ("R", 0.32)):
        box("LockerSide_%s" % side, (x, 0.0, 0.97),
            (0.06, 0.50, 1.84), mat, 1, count, objects, bevel=0.018)
    box("ChunkyTop", (0.0, 0.0, 1.91), (0.75, 0.56, 0.10), trim_mat, 3,
        count, objects, bevel=0.022)
    box("ChunkyBase", (0.0, 0.0, 0.09), (0.73, 0.54, 0.18), trim_mat, 1,
        count, objects, bevel=0.018)
    for index, x in enumerate((-0.265, 0.265)):
        box("Foot_%d" % (index + 1), (x, -0.14, 0.035),
            (0.13, 0.18, 0.07), dark_mat, 0, count, objects, bevel=0.012)
    # The door is assembled around three narrow, real sight cracks at the
    # hidden player's eye line.  These are empty geometry gaps, not dark
    # stickers, so both inside and outside views work naturally.
    box("DoorLowerMass", (0.0, -0.293, 0.89), (0.56, 0.04, 1.38), mat, 2,
        count, objects, bevel=0.014)
    box("DoorTopMass", (0.0, -0.293, 1.80), (0.56, 0.04, 0.20), mat, 2,
        count, objects, bevel=0.012)
    box("SightCrackLeftRail", (-0.245, -0.293, 1.565),
        (0.07, 0.04, 0.27), mat, 2, count, objects, bevel=0.006)
    box("SightCrackRightRail", (0.245, -0.293, 1.565),
        (0.07, 0.04, 0.27), mat, 2, count, objects, bevel=0.006)
    for index, z in enumerate((1.47, 1.565, 1.66)):
        # Narrow slats leave 5.5 cm clear between them: enough for a readable
        # first-person glimpse, still restrictive enough to feel concealed.
        box("SightSlat_%d" % (index + 1), (0.0, -0.293, z),
            (0.42, 0.04, 0.04), mat, 3, count, objects, bevel=0.004)
    # Two broad stamped panels give the face depth without realistic micro-detail.
    box("LowerInset", (0.0, -0.322, 0.61), (0.42, 0.026, 0.55), dark_mat, 1,
        count, objects, bevel=0.012)
    box("LowerPanel", (0.0, -0.34, 0.61), (0.36, 0.018, 0.48), mat, 2,
        count, objects, bevel=0.009)
    box("NumberPlate", (0.0, -0.35, 1.80), (0.19, 0.025, 0.085), trim_mat, 6,
        count, objects, bevel=0.008)
    box("HandlePlate", (0.205, -0.35, 1.02), (0.10, 0.03, 0.27), dark_mat, 0,
        count, objects, bevel=0.008)
    box("Handle", (0.205, -0.385, 1.02), (0.055, 0.055, 0.19), hardware_mat, 4,
        count, objects, bevel=0.009)
    for index, z in enumerate((0.48, 1.48)):
        box("BlockHinge_%d" % (index + 1), (-0.30, -0.342, z),
            (0.055, 0.055, 0.16), hardware_mat, 5, count, objects, bevel=0.007)
    # Broad trim modules keep the modular quality contract while strengthening
    # the block-built silhouette instead of reintroducing realistic micro-parts.
    for side, x in (("L", -0.275), ("R", 0.275)):
        box("DoorRail_%s" % side, (x, -0.326, 1.00),
            (0.035, 0.03, 1.48), trim_mat, 1, count, objects, bevel=0.006)
        box("BaseBracket_%s" % side, (x, -0.335, 0.19),
            (0.09, 0.045, 0.11), trim_mat, 5, count, objects, bevel=0.008)
    box("BlockLatch", (0.205, -0.389, 0.89), (0.07, 0.055, 0.065),
        hardware_mat, 4, count, objects, bevel=0.008)
    return objects, (2.65, -4.3, 2.75), (0.0, 0.0, 0.98)


def make_battery():
    colors = ["#13191E", "#303C43", "#526169", "#C58B35", "#9D3D3D", "#5EC6A3", "#D7D7B0"]
    image = make_pixel_atlas("battery_pixel_atlas", colors)
    mat = make_material("Battery pixel paint", image, roughness=0.80, metallic=0.10)
    count = len(colors)
    objects = []
    box("BatteryBody", (0.0, 0.0, 0.205), (0.34, 0.24, 0.33), mat, 1,
        count, objects, bevel=0.004)
    box("BottomCap", (0.0, 0.0, 0.04), (0.36, 0.26, 0.08), mat, 0,
        count, objects, bevel=0.002)
    box("TopCap", (0.0, 0.0, 0.385), (0.36, 0.26, 0.06), mat, 2,
        count, objects, bevel=0.002)
    box("ChargeRecess", (0.0, -0.117, 0.21), (0.20, 0.020, 0.20), mat, 0,
        count, objects, bevel=0.001)
    for index, z in enumerate((0.15, 0.21, 0.27)):
        box("ChargeBar_%d" % (index + 1), (0.0, -0.129, z),
            (0.14, 0.002, 0.035), mat, 5 if index < 2 else 3,
            count, objects, bevel=0.0)
    box("PositiveTerminal", (-0.09, 0.0, 0.435), (0.07, 0.08, 0.05), mat, 4,
        count, objects, bevel=0.0)
    box("NegativeTerminal", (0.09, 0.0, 0.435), (0.07, 0.08, 0.05), mat, 6,
        count, objects, bevel=0.0)
    return objects, (0.9, -1.8, 1.05), (0.0, 0.0, 0.23)


def make_relay():
    colors = ["#111820", "#273640", "#40545E", "#65747A", "#48B5B3", "#B64A43", "#C69B4A"]
    image = make_pixel_atlas("relay_pixel_atlas", colors)
    mat = make_material("Relay pixel paint", image, roughness=0.78, metallic=0.12)
    count = len(colors)
    objects = []
    box("RelayBase", (0.0, 0.0, 0.09), (0.48, 0.48, 0.18), mat, 1,
        count, objects, bevel=0.010)
    box("RelayBaseStep", (0.0, 0.0, 0.225), (0.36, 0.36, 0.09), mat, 2,
        count, objects, bevel=0.006)
    box("RelayMast", (0.0, 0.0, 0.49), (0.12, 0.12, 0.46), mat, 1,
        count, objects, bevel=0.002)
    box("SignalHead", (0.0, 0.0, 0.79), (0.40, 0.18, 0.34), mat, 2,
        count, objects, bevel=0.006)
    box("SignalFace", (0.0, -0.102, 0.79), (0.32, 0.024, 0.26), mat, 0,
        count, objects, bevel=0.002)
    # Pixel broadcast glyph: broad at the bottom, narrowing upward.
    for index, (z, width) in enumerate(((0.72, 0.24), (0.79, 0.16), (0.86, 0.08))):
        box("SignalBar_%d" % (index + 1), (0.0, -0.119, z),
            (width, 0.012, 0.034), mat, 4, count, objects, bevel=0.0)
    box("SignalLamp", (0.0, 0.0, 0.97), (0.08, 0.08, 0.06), mat, 5,
        count, objects, bevel=0.0)
    box("SideAntennaL", (-0.195, 0.0, 0.84), (0.04, 0.08, 0.24), mat, 6,
        count, objects, bevel=0.001,
        rotation=(0.0, math.radians(-8), math.radians(-8)))
    box("SideAntennaR", (0.195, 0.0, 0.84), (0.04, 0.08, 0.24), mat, 6,
        count, objects, bevel=0.001,
        rotation=(0.0, math.radians(8), math.radians(8)))
    return objects, (1.35, -2.35, 1.55), (0.0, 0.0, 0.50)


def make_locked_relay_crate():
    colors = ["#171719", "#382820", "#624532", "#896346", "#B1855D",
              "#3A4147", "#76838B", "#42B7B4"]
    image = make_pixel_atlas("locked_relay_crate_pixel_atlas", colors)
    mat = make_material("Locked relay crate pixel paint", image,
                        roughness=0.88, metallic=0.05)
    count = len(colors)
    objects = []
    box("CrateBody", (0, 0, .35), (.72, .68, .70), mat, 2, count,
        objects, bevel=.012)
    for z in (.08, .62):
        box("CrateBand_%s" % z, (0, 0, z), (.76, .72, .10), mat, 5,
            count, objects, bevel=.006)
    for x in (-.31, .31):
        box("FrontBrace_%s" % x, (x, -.35, .35), (.08, .055, .56), mat,
            3, count, objects, bevel=.003)
    box("FrontCrossBrace", (0, -.382, .35), (.64, .06, .095), mat, 4,
        count, objects, bevel=.003, rotation=(0, 0, math.radians(-24)))
    box("LockPlate", (0, -.395, .43), (.20, .045, .19), mat, 5, count,
        objects, bevel=.006)
    box("Padlock", (0, -.43, .40), (.10, .07, .12), mat, 6, count,
        objects, bevel=.008)
    # A cyan aerial peeking through the lid communicates that this is an
    # objective cache rather than an ordinary room-dressing crate.
    box("RelayAntenna", (0, 0, .82), (.07, .07, .30), mat, 7, count,
        objects, bevel=.002)
    box("RelaySignalHead", (0, 0, .96), (.25, .12, .16), mat, 7, count,
        objects, bevel=.004)
    return objects, (1.45, -2.35, 1.55), (0, 0, .48)


def make_locked_relay_barrel():
    colors = ["#171719", "#2C211D", "#563B2B", "#80593B", "#A5784E",
              "#333A40", "#727F87", "#42B7B4"]
    image = make_pixel_atlas("locked_relay_barrel_pixel_atlas", colors)
    mat = make_material("Locked relay barrel pixel paint", image,
                        roughness=.87, metallic=.06)
    count = len(colors)
    objects = []
    cylinder("BarrelBody", (0, 0, .40), .34, .80, 8, mat, 3, count,
             objects, bevel=.008)
    for z in (.09, .40, .71):
        cylinder("IronBand_%s" % z, (0, 0, z), .365, .075, 8, mat, 5,
                 count, objects, bevel=.003)
    box("LockPlate", (0, -.347, .43), (.18, .045, .20), mat, 6, count,
        objects, bevel=.006)
    box("Padlock", (0, -.39, .39), (.095, .07, .13), mat, 5, count,
        objects, bevel=.006)
    box("RelayAntenna", (0, 0, .90), (.065, .065, .27), mat, 7, count,
        objects, bevel=.002)
    box("RelaySignalHead", (0, 0, 1.02), (.23, .11, .15), mat, 7, count,
        objects, bevel=.004)
    return objects, (1.45, -2.35, 1.55), (0, 0, .50)


def make_boarded_door():
    colors = ["#171719", "#38251C", "#5C3E2A", "#805A3A", "#A77B50",
              "#343A3F", "#737E84", "#9B473B"]
    image = make_pixel_atlas("boarded_door_pixel_atlas", colors)
    mat = make_material("Boarded doorway pixel paint", image,
                        roughness=.91, metallic=.03)
    count = len(colors)
    objects = []
    # Full doorway frame gives the boards believable supports and fits the
    # route's one-metre doorway/collision contract.
    for x in (-.47, .47):
        box("DoorFrame_%s" % x, (x, .025, 1.12), (.10, .15, 2.24), mat,
            1, count, objects, bevel=.008)
    box("DoorHeader", (0, .025, 2.22), (1.04, .15, .12), mat, 1, count,
        objects, bevel=.008)
    plank_data = [(.42, -7), (.84, 5), (1.27, -6), (1.70, 7)]
    for index, (z, angle) in enumerate(plank_data):
        box("Board_%02d" % index, (0, -.075, z), (.94, .115, .22), mat,
            3 + index % 2, count, objects, bevel=.006,
            rotation=(0, 0, math.radians(angle)))
        for x in (-.34, .34):
            box("Nail_%02d_%s" % (index, x), (x, -.139, z),
                (.045, .025, .045), mat, 6, count, objects, bevel=.002)
    box("WarningStripe", (0, -.145, 1.06), (.44, .028, .08), mat, 7,
        count, objects, bevel=.002, rotation=(0, 0, math.radians(-6)))
    return objects, (2.05, -3.25, 2.55), (0, 0, 1.10)


def make_lockpick_set():
    colors = ["#15171A", "#343A40", "#626C74", "#A7B1B8", "#753F4A"]
    image = make_pixel_atlas("lockpick_set_pixel_atlas", colors)
    mat = make_material("Lockpick set pixel paint", image,
                        roughness=.48, metallic=.42)
    count = len(colors)
    objects = []
    box("PickHandle", (-.045, 0, .13), (.075, .055, .26), mat, 4,
        count, objects, bevel=.008)
    box("PickShaft", (-.045, 0, .40), (.022, .022, .30), mat, 3,
        count, objects, bevel=.002)
    box("PickTip", (-.015, 0, .55), (.08, .022, .022), mat, 3,
        count, objects, bevel=.002, rotation=(0, math.radians(-18), 0))
    box("TensionHandle", (.075, .015, .10), (.07, .05, .20), mat, 1,
        count, objects, bevel=.006)
    box("TensionShaft", (.075, .015, .31), (.022, .022, .24), mat, 2,
        count, objects, bevel=.002)
    box("TensionFoot", (.105, .015, .43), (.08, .022, .022), mat, 2,
        count, objects, bevel=.002)
    return objects, (.8, -1.5, .9), (0, 0, .28)


def make_crowbar():
    colors = ["#171719", "#43232A", "#743441", "#A54A58", "#C66B70",
              "#59636A", "#9AA5AA"]
    image = make_pixel_atlas("crowbar_pixel_atlas", colors)
    mat = make_material("Crowbar pixel paint", image, roughness=.50,
                        metallic=.36)
    count = len(colors)
    objects = []
    box("CrowbarShaft", (0, 0, .48), (.075, .075, .82), mat, 3, count,
        objects, bevel=.012)
    box("CrowbarHook", (.10, 0, .91), (.27, .075, .075), mat, 4, count,
        objects, bevel=.012, rotation=(0, math.radians(-18), 0))
    box("CrowbarClaw", (.22, 0, .86), (.075, .075, .18), mat, 6, count,
        objects, bevel=.010, rotation=(0, math.radians(28), 0))
    box("CrowbarFoot", (-.07, 0, .075), (.20, .075, .075), mat, 2,
        count, objects, bevel=.010, rotation=(0, math.radians(20), 0))
    return objects, (1.0, -2.0, 1.25), (0, 0, .48)


def make_rescue_axe():
    colors = ["#171719", "#35261F", "#6B4931", "#A66A3A", "#A33F36",
              "#D35B43", "#666F75", "#B4BCC0"]
    image = make_pixel_atlas("rescue_axe_pixel_atlas", colors)
    mat = make_material("Rescue axe pixel paint", image, roughness=.58,
                        metallic=.22)
    count = len(colors)
    objects = []
    box("AxeHandle", (0, 0, .47), (.085, .085, .82), mat, 3, count,
        objects, bevel=.012)
    box("AxeGrip", (0, 0, .13), (.12, .12, .26), mat, 1, count,
        objects, bevel=.012)
    box("AxeHead", (.02, 0, .88), (.48, .12, .26), mat, 5, count,
        objects, bevel=.012)
    box("AxeBlade", (.25, 0, .85), (.18, .10, .35), mat, 7, count,
        objects, bevel=.008, rotation=(0, math.radians(-8), 0))
    box("AxePick", (-.26, 0, .91), (.17, .09, .10), mat, 6, count,
        objects, bevel=.006)
    return objects, (1.2, -2.2, 1.35), (0, 0, .50)


def make_revive_kit():
    """Revive Kit (docs/REVIVE.md): a charcoal hard case with a hi-vis lid, defib paddles clipped on top, a white
    pulse-line emblem (deliberately no cross) and a green charge lamp."""
    colors = ["#1D2126", "#30363D", "#D9692B", "#F08A44", "#E6E2D6", "#5EE08C",
              "#8E989E", "#121416"]
    image = make_pixel_atlas("revive_kit_pixel_atlas", colors)
    mat = make_material("Revive kit pixel paint", image, roughness=.62,
                        metallic=.08)
    count = len(colors)
    objects = []
    box("CaseBody", (0, 0, .11), (.50, .30, .18), mat, 1, count, objects,
        bevel=.012)
    box("CaseLid", (0, 0, .225), (.52, .32, .07), mat, 2, count, objects,
        bevel=.012)
    box("CaseFoot", (0, 0, .015), (.48, .28, .03), mat, 0, count, objects,
        bevel=.004)
    for side, x in (("L", -.15), ("R", .15)):
        box("Latch%s" % side, (x, -.162, .19), (.06, .02, .07), mat, 6,
            count, objects, bevel=.004)
        box("HandlePost%s" % side, (x * .7, 0, .285), (.035, .05, .06), mat,
            7, count, objects, bevel=.004)
    box("Handle", (0, 0, .315), (.26, .05, .035), mat, 7, count, objects,
        bevel=.006)
    box("EmblemPlate", (0, -.152, .105), (.24, .012, .11), mat, 3, count,
        objects, bevel=.002)
    for index, (x, z, w, h) in enumerate(((-.085, .105, .05, .016),
                                          (-.052, .125, .016, .056),
                                          (-.034, .085, .016, .076),
                                          (-.016, .115, .016, .046),
                                          (.035, .105, .085, .016))):
        box("Pulse%d" % index, (x, -.160, z), (w, .006, h), mat, 4, count,
            objects)
    box("ChargeLamp", (.20, -.12, .265), (.04, .04, .025), mat, 5, count,
        objects, bevel=.003)
    for side, x in (("L", -.14), ("R", .10)):
        box("Paddle%s" % side, (x, .075, .275), (.13, .09, .03), mat, 1,
            count, objects, bevel=.006)
        box("PaddleFace%s" % side, (x, .075, .262), (.12, .08, .006), mat, 6,
            count, objects)
        box("PaddleGrip%s" % side, (x, .075, .305), (.05, .04, .04), mat, 2,
            count, objects, bevel=.005)
    box("Cable", (-.02, .135, .262), (.20, .02, .02), mat, 7, count, objects)
    return objects, (1.05, -1.25, .85), (0, 0, .16)


def make_stim_pack():
    """Stim Pack: a chunky autoinjector, long axis up like the other hand items (plunger at the grip end, safety cap
    on top), ribbed grip, white label and a cyan dose window."""
    colors = ["#202428", "#353B42", "#E2B526", "#F4D35E", "#3FD3E6", "#A9E6EE",
              "#8E989E", "#E6E2D6"]
    image = make_pixel_atlas("stim_pack_pixel_atlas", colors)
    mat = make_material("Stim pack pixel paint", image, roughness=.50,
                        metallic=.12)
    count = len(colors)
    objects = []
    box("PlungerButton", (0, 0, .0125), (.05, .05, .025), mat, 3, count,
        objects, bevel=.004)
    box("Plunger", (0, 0, .05), (.09, .09, .05), mat, 2, count, objects,
        bevel=.008)
    box("Grip", (0, 0, .185), (.11, .11, .22), mat, 1, count, objects,
        bevel=.01)
    for index, z in enumerate((.115, .155)):
        box("GripRib%d" % index, (0, 0, z), (.118, .118, .02), mat, 0,
            count, objects)
    box("Label", (0, -.057, .205), (.05, .006, .10), mat, 7, count, objects)
    box("Fluid", (0, 0, .345), (.096, .096, .10), mat, 4, count, objects)
    for index, (x, y) in enumerate(((-.05, -.05), (.05, -.05), (-.05, .05),
                                    (.05, .05))):
        box("Frame%d" % index, (x, y, .345), (.014, .014, .10), mat, 5, count,
            objects)
    box("Collar", (0, 0, .41), (.09, .09, .03), mat, 6, count, objects,
        bevel=.004)
    box("SafetyCap", (0, 0, .46), (.08, .08, .07), mat, 2, count, objects,
        bevel=.008)
    return objects, (.75, -1.1, .65), (0, 0, .24)


def make_flashlight_item():
    colors = ["#121518", "#2D3339", "#4B555D", "#79858C", "#D5C778",
              "#FFF0A5"]
    image = make_pixel_atlas("flashlight_item_pixel_atlas", colors)
    mat = make_material("Flashlight item pixel paint", image,
                        roughness=.54, metallic=.20)
    count = len(colors)
    objects = []
    box("FlashlightGrip", (0, 0, .25), (.16, .16, .50), mat, 1, count,
        objects, bevel=.018)
    box("FlashlightNeck", (0, 0, .54), (.20, .20, .12), mat, 2, count,
        objects, bevel=.016)
    box("FlashlightHead", (0, 0, .68), (.31, .27, .20), mat, 3, count,
        objects, bevel=.022)
    box("FlashlightLens", (0, -.146, .68), (.23, .025, .14), mat, 5,
        count, objects, bevel=.010)
    box("FlashlightSwitch", (0, -.095, .39), (.08, .025, .11), mat, 4,
        count, objects, bevel=.006)
    return objects, (1.0, -1.9, 1.0), (0, 0, .37)


def make_taser_item():
    colors = ["#15141A", "#27252D", "#4B315E", "#70488C", "#9A67BC",
              "#9EA8AF", "#D7E0E4", "#F0C95A"]
    image = make_pixel_atlas("taser_item_pixel_atlas", colors)
    mat = make_material("Taser item pixel paint", image,
                        roughness=.55, metallic=.16)
    count = len(colors)
    objects = []
    box("TaserBody", (0, 0, .44), (.28, .22, .42), mat, 3, count,
        objects, bevel=.025)
    box("TaserGrip", (0, .035, .16), (.18, .18, .30), mat, 1, count,
        objects, bevel=.022, rotation=(0, math.radians(-8), 0))
    box("TaserMuzzle", (0, -.13, .61), (.25, .10, .16), mat, 2, count,
        objects, bevel=.015)
    for x in (-.075, .075):
        box("TaserProbe_%s" % x, (x, -.205, .63), (.035, .11, .035), mat,
            6, count, objects, bevel=.003)
    box("ChargeDisplay", (0, -.121, .45), (.13, .025, .07), mat, 7,
        count, objects, bevel=.006)
    return objects, (1.05, -1.9, 1.0), (0, 0, .34)


def make_backpack(model_name, scale, accent):
    """A real block-built wearable pack, not a pickup placeholder.

    The three sizes share a recognizable family while gaining depth, side
    pockets and bedroll capacity. Their back face stays flat enough to read as
    wearable and their floor pivot lets the same GLB work as a world pickup.
    """
    colors = ["#15171A", "#2A2E31", "#4A382F", "#76523D", accent,
              "#B18A5A", "#9AA2A6", "#D2B77A"]
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors)
    mat = make_material(model_name.replace("_", " ").title() + " pixel paint",
                        image, roughness=.74, metallic=.04)
    count = len(colors)
    objects = []
    width = .48 + .11 * scale
    depth = .20 + .055 * scale
    height = .58 + .14 * scale
    body_z = .12 + height * .5
    box("PackBody", (0, 0, body_z), (width, depth, height), mat, 3,
        count, objects, bevel=.025)
    box("TopFlap", (0, -.018 - depth * .52, body_z + height * .25),
        (width * .92, .045, height * .30), mat, 4, count, objects, bevel=.015)
    box("FrontPocket", (0, -.045 - depth * .52, body_z - height * .13),
        (width * .70, .085, height * .27), mat, 5, count, objects, bevel=.014)
    box("Buckle", (0, -.095 - depth * .52, body_z + .02),
        (.09, .025, .09), mat, 7, count, objects, bevel=.004)
    # Visible shoulder straps and their lower anchors make the object read as
    # a backpack from rear/three-quarter views, not a decorated supply crate.
    for x in (-width * .29, width * .29):
        box("ShoulderStrap_%s" % x, (x, depth * .52 + .026, body_z),
            (.075, .042, height * .72), mat, 1, count, objects, bevel=.012)
        box("StrapAnchor_%s" % x, (x, depth * .52 + .032, .13),
            (.09, .045, .15), mat, 6, count, objects, bevel=.008)
    if scale >= 2:
        for x in (-width * .58, width * .58):
            box("SidePocket_%s" % x, (x, 0, body_z - height * .16),
                (.16, depth * .85, height * .30), mat, 4, count, objects,
                bevel=.014)
    if scale >= 3:
        box("Bedroll", (0, 0, .10), (width * 1.06, depth * .82, .18), mat,
            7, count, objects, bevel=.025)
        for x in (-width * .28, width * .28):
            box("BedrollTie_%s" % x, (x, -depth * .43, .10),
                (.055, .035, .20), mat, 1, count, objects, bevel=.005)
    return objects, (1.35, -2.35, 1.25), (0, 0, body_z)


def make_backpack_small():
    return make_backpack("backpack_small", 1, "#506A5A")


def make_backpack_medium():
    return make_backpack("backpack_medium", 2, "#5B668A")


def make_backpack_large():
    return make_backpack("backpack_large", 3, "#6F4E78")


def make_boarded_hallway():
    colors = ["#151517", "#33231B", "#593D29", "#7D593A", "#A47A50",
              "#343A3F", "#78838A", "#9B473B"]
    image = make_pixel_atlas("boarded_hallway_pixel_atlas", colors)
    mat = make_material("Boarded hallway pixel paint", image,
                        roughness=.92, metallic=.03)
    count = len(colors)
    objects = []
    for x in (-1.45, 0, 1.45):
        box("HallPost_%s" % x, (x, .03, 1.48), (.12, .18, 2.96), mat,
            1, count, objects, bevel=.008)
    box("HallHeader", (0, .03, 2.92), (3.0, .18, .14), mat, 1, count,
        objects, bevel=.008)
    for index, (z, angle) in enumerate(((.40, -4), (.88, 5), (1.36, -5),
                                         (1.84, 4), (2.32, -4))):
        box("HallBoard_%02d" % index, (0, -.08, z), (2.90, .13, .26),
            mat, 3 + index % 2, count, objects, bevel=.008,
            rotation=(0, 0, math.radians(angle)))
        for x in (-1.15, 0, 1.15):
            box("HallNail_%02d_%s" % (index, x), (x, -.153, z),
                (.055, .025, .055), mat, 6, count, objects, bevel=.002)
    box("HallWarning", (0, -.16, 1.42), (.80, .03, .13), mat, 7, count,
        objects, bevel=.003)
    return objects, (4.6, -6.2, 3.8), (0, 0, 1.45)


def make_service_ladder():
    colors = ["#151719", "#30363B", "#59636A", "#889298", "#B16A3D",
              "#D29454"]
    image = make_pixel_atlas("service_ladder_pixel_atlas", colors)
    mat = make_material("Service ladder pixel paint", image,
                        roughness=.60, metallic=.30)
    count = len(colors)
    objects = []
    for x in (-.27, .27):
        box("LadderRail_%s" % x, (x, 0, .72), (.075, .09, 1.44), mat,
            2, count, objects, bevel=.010)
    for index in range(7):
        z = .12 + index * .20
        box("LadderRung_%02d" % index, (0, -.015, z), (.58, .10, .065),
            mat, 3 if index % 2 else 4, count, objects, bevel=.008)
    box("LadderTopMark", (0, -.065, 1.39), (.30, .035, .07), mat, 5,
        count, objects, bevel=.005)
    return objects, (1.35, -2.4, 1.8), (0, 0, .72)


def make_wall_light_switch():
    colors = ["#151719", "#30363B", "#59636A", "#8C969B", "#D7D1B7",
              "#D89B46", "#65C0A6"]
    image = make_pixel_atlas("wall_light_switch_pixel_atlas", colors)
    mat = make_material("Wall light switch pixel paint", image,
                        roughness=.62, metallic=.18)
    count = len(colors)
    objects = []
    box("SwitchPlate", (0, 0, .20), (.30, .08, .40), mat, 2, count,
        objects, bevel=.018)
    box("SwitchInset", (0, -.052, .20), (.18, .035, .24), mat, 1, count,
        objects, bevel=.010)
    box("SwitchToggle", (0, -.09, .22), (.08, .06, .16), mat, 4, count,
        objects, bevel=.012, rotation=(math.radians(-10), 0, 0))
    box("SwitchLamp", (0, -.088, .34), (.07, .03, .04), mat, 6, count,
        objects, bevel=.004)
    return objects, (.8, -1.5, .9), (0, 0, .20)


def make_safe_zone():
    colors = ["#111820", "#27343D", "#3D505A", "#58717B", "#43C0B1", "#8BE4CF", "#C7A44C"]
    image = make_pixel_atlas("safe_zone_pixel_atlas", colors)
    mat = make_material("Safe zone pixel paint", image, roughness=0.82, metallic=0.06)
    count = len(colors)
    objects = []
    box("SafePad", (0.0, 0.0, 0.03), (1.60, 1.60, 0.06), mat, 1,
        count, objects, bevel=0.035)
    box("SafePadInset", (0.0, 0.0, 0.072), (1.34, 1.34, 0.035), mat, 2,
        count, objects, bevel=0.020)
    # A segmented square circuit ring avoids a smooth torus and stays readable
    # as authored pixel geometry from every corridor direction.
    for index, (location, dimensions) in enumerate((
            ((0.0, -0.61, 0.102), (1.14, 0.09, 0.035)),
            ((0.0, 0.61, 0.102), (1.14, 0.09, 0.035)),
            ((-0.61, 0.0, 0.102), (0.09, 1.14, 0.035)),
            ((0.61, 0.0, 0.102), (0.09, 1.14, 0.035)))):
        box("SafeRing_%d" % (index + 1), location, dimensions, mat,
            4 if index % 2 == 0 else 5, count, objects, bevel=0.0)
    for index, (x, y) in enumerate(((-0.62, -0.62), (0.62, -0.62),
                                    (-0.62, 0.62), (0.62, 0.62))):
        box("CornerBeacon_%d" % (index + 1), (x, y, 0.135),
            (0.16, 0.16, 0.10), mat, 6 if index % 2 else 4,
            count, objects, bevel=0.006)
    box("SafePost", (0.0, 0.0, 0.46), (0.22, 0.22, 0.70), mat, 2,
        count, objects, bevel=0.004)
    box("PostBand", (0.0, 0.0, 0.58), (0.27, 0.27, 0.10), mat, 4,
        count, objects, bevel=0.002)
    box("SafeBeacon", (0.0, 0.0, 0.805), (0.30, 0.30, 0.07), mat, 5,
        count, objects, bevel=0.004)
    return objects, (2.50, -3.20, 2.30), (0.0, 0.0, 0.22)


def make_lift():
    colors = ["#11171D", "#293842", "#41535C", "#68777B", "#C99A3D", "#A33D3D", "#61B8B1"]
    image = make_pixel_atlas("lift_pixel_atlas", colors)
    mat = make_material("Lift pixel paint", image, roughness=0.80, metallic=0.10)
    count = len(colors)
    objects = []
    box("LiftPlatform", (0.0, 0.0, 0.06), (2.00, 2.00, 0.12), mat, 0,
        count, objects, bevel=0.015)
    box("PlatformInset", (0.0, 0.0, 0.135), (1.72, 1.72, 0.05), mat, 2,
        count, objects, bevel=0.008)
    # Side cage modules retain the original open front/back footprint.
    for side, x in (("L", -0.91), ("R", 0.91)):
        box("LiftRail_%s" % side, (x, 0.0, 1.11), (0.14, 1.82, 1.98), mat, 1,
            count, objects, bevel=0.008)
        for index, z in enumerate((0.42, 0.86, 1.30, 1.74)):
            box("RailBand_%s_%d" % (side, index + 1),
                (x + (0.08 if x < 0 else -0.08), -0.55, z),
                (0.06, 0.58, 0.10), mat, 3, count, objects, bevel=0.001)
    box("LiftRoof", (0.0, 0.0, 2.20), (1.90, 1.90, 0.20), mat, 1,
        count, objects, bevel=0.014)
    box("FrontHeader", (0.0, -0.91, 2.08), (1.82, 0.14, 0.24), mat, 2,
        count, objects, bevel=0.006)
    # Four hard-edged hazard blocks along the entrance lip.
    for index, x in enumerate((-0.66, -0.22, 0.22, 0.66)):
        box("Hazard_%d" % (index + 1), (x, -0.91, 0.175),
            (0.34, 0.08, 0.035), mat, 4 if index % 2 == 0 else 0,
            count, objects, bevel=0.0,
            rotation=(0.0, 0.0, math.radians(10 if index % 2 == 0 else -10)))
    box("CallPanel", (0.90, -0.53, 1.30), (0.14, 0.25, 0.40), mat, 0,
        count, objects, bevel=0.003)
    box("CallScreen", (0.815, -0.58, 1.34), (0.025, 0.13, 0.18), mat, 6,
        count, objects, bevel=0.0)
    box("CallButton", (0.81, -0.58, 1.18), (0.03, 0.08, 0.07), mat, 5,
        count, objects, bevel=0.0)
    return objects, (3.55, -4.85, 3.25), (0.0, 0.0, 1.05)


def make_heater_station():
    colors = ["#11171D", "#29353D", "#46545A", "#6C7473", "#D05A32", "#F3A23B", "#74BFD0", "#B6A05F"]
    image = make_pixel_atlas("heater_station_pixel_atlas", colors)
    mat = make_material("Heater station pixel paint", image, roughness=0.80, metallic=0.10)
    count = len(colors)
    objects = []
    box("HeaterBase", (0.0, 0.0, 0.06), (0.64, 0.64, 0.12), mat, 0,
        count, objects, bevel=0.008)
    box("HeaterBody", (0.0, 0.0, 0.58), (0.56, 0.54, 0.92), mat, 1,
        count, objects, bevel=0.008)
    box("HeaterTop", (0.0, 0.0, 1.075), (0.62, 0.60, 0.10), mat, 3,
        count, objects, bevel=0.006)
    box("HeatRecess", (0.0, -0.298, 0.61), (0.43, 0.025, 0.64), mat, 0,
        count, objects, bevel=0.004)
    for index, z in enumerate((0.38, 0.52, 0.66, 0.80)):
        box("HeatBar_%d" % (index + 1), (0.0, -0.318, z),
            (0.34, 0.004, 0.065), mat, 5 if index in (1, 2) else 4,
            count, objects, bevel=0.0)
    box("ControlPanel", (0.0, -0.306, 0.98), (0.32, 0.018, 0.14), mat, 2,
        count, objects, bevel=0.002)
    box("HeatGauge", (-0.07, -0.318, 0.98), (0.11, 0.004, 0.07), mat, 5,
        count, objects, bevel=0.0)
    box("HeatSwitch", (0.09, -0.318, 0.98), (0.07, 0.004, 0.07), mat, 7,
        count, objects, bevel=0.0)
    # Icy corner blocks preserve the old heater/frost contrast without a smooth shell.
    for index, (x, y, z) in enumerate(((-0.275, -0.275, 0.18),
                                        (0.275, 0.275, 0.28),
                                        (-0.275, 0.275, 0.93),
                                        (0.275, -0.275, 1.17))):
        box("FrostBlock_%d" % (index + 1), (x, y, z),
            (0.08, 0.08, 0.10), mat, 6, count, objects, bevel=0.0)
    box("SidePipe", (0.29, 0.05, 0.66), (0.05, 0.10, 0.56), mat, 7,
        count, objects, bevel=0.001)
    return objects, (1.65, -2.65, 1.80), (0.0, 0.0, 0.60)


def make_arcade_variant(model_name, colors, glyph=0):
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors, MAZE_TEXTURES)
    mat = make_material(model_name.replace("_", " ").title() + " pixel paint",
                        image, roughness=0.76, metallic=0.08)
    count = len(colors)
    objects = []
    box("CabinetBase", (0.0, 0.0, 0.36), (0.54, 0.60, 0.72), mat, 1,
        count, objects, bevel=0.005)
    box("CabinetUpper", (0.0, 0.04, 1.17), (0.54, 0.50, 0.92), mat, 1,
        count, objects, bevel=0.005)
    box("Marquee", (0.0, 0.00, 1.73), (0.60, 0.52, 0.18), mat, 2,
        count, objects, bevel=0.004)
    box("MarqueeFace", (0.0, -0.268, 1.73), (0.46, 0.012, 0.10), mat, 3,
        count, objects, bevel=0.0)
    box("ScreenRecess", (0.0, -0.218, 1.37), (0.42, 0.025, 0.40), mat, 0,
        count, objects, bevel=0.002)
    box("ScreenGlass", (0.0, -0.233, 1.37), (0.35, 0.006, 0.32), mat, 5,
        count, objects, bevel=0.001)
    box("ControlDeck", (0.0, -0.245, 0.88), (0.56, 0.36, 0.15), mat, 2,
        count, objects, bevel=0.003,
        rotation=(math.radians(10), 0.0, 0.0))
    box("CoinDoor", (0.0, -0.305, 0.38), (0.32, 0.012, 0.34), mat, 0,
        count, objects, bevel=0.001)
    box("CoinSlot", (0.0, -0.313, 0.45), (0.055, 0.006, 0.09), mat, 6,
        count, objects, bevel=0.0)
    for side, x in (("L", -0.275), ("R", 0.275)):
        box("EdgeTrim_%s" % side, (x, -0.005, 0.93),
            (0.03, 0.59, 1.70), mat, 3, count, objects, bevel=0.0)
    box("JoystickStem", (-0.12, -0.405, 0.94), (0.025, 0.025, 0.13), mat, 6,
        count, objects, bevel=0.0,
        rotation=(0.0, math.radians(-8), 0.0))
    box("JoystickTop", (-0.13, -0.405, 1.01), (0.07, 0.07, 0.055), mat, 4,
        count, objects, bevel=0.001)
    for index, x in enumerate((0.02, 0.10, 0.18)):
        box("ActionButton_%d" % (index + 1), (x, -0.408, 0.925 + (index % 2) * 0.018),
            (0.055, 0.055, 0.025), mat, 4 if index != 1 else 3,
            count, objects, bevel=0.0)
    # Each cabinet family receives a distinct block glyph as well as a palette.
    patterns = (
        ((-0.075, 0.0, 0.11, 0.035), (0.025, 0.0, 0.035, 0.11), (0.08, 0.0, 0.035, 0.07)),
        ((-0.07, 0.04, 0.12, 0.03), (-0.03, -0.025, 0.035, 0.10), (0.055, -0.025, 0.035, 0.10)),
        ((-0.07, 0.03, 0.055, 0.035), (0.0, 0.0, 0.055, 0.035), (0.07, -0.03, 0.055, 0.035)),
        ((-0.06, 0.0, 0.035, 0.12), (0.0, 0.0, 0.035, 0.075), (0.06, 0.0, 0.035, 0.12)),
    )
    for index, (x, zoff, width, height) in enumerate(patterns[glyph % len(patterns)]):
        box("ScreenGlyph_%d" % (index + 1), (x, -0.239, 1.37 + zoff),
            (width, 0.004, height), mat, 4 if index % 2 == 0 else 3,
            count, objects, bevel=0.0)
    return objects, (2.05, -3.15, 2.15), (0.0, 0.0, 0.85)


WOOD_PALETTES = {
    # Indices 0-4 are timber shadow-to-highlight; 5-6 are matching upholstery
    # or painted accents, and 7 is hardware. Keeping this ordering identical
    # lets one room seed select a named timber finish across every furniture
    # silhouette without baking duplicate placement rules into gameplay code.
    "oak": ["#20120D", "#513020", "#7C4B2A", "#AE7440", "#D3A15E",
            "#6B2637", "#A34A61", "#C19A4E"],
    "walnut": ["#120C09", "#2A1912", "#4A2C20", "#6B4633", "#96705A",
               "#263848", "#49657B", "#B69A61"],
    "mahogany": ["#180909", "#391417", "#65252A", "#913B42", "#B75B5F",
                 "#45203D", "#744E78", "#C1A064"],
    "ash": ["#252525", "#53504B", "#807B73", "#AAA398", "#D6CEC0",
            "#6B776E", "#9DA89D", "#B9A56B"],
}


COMPUTER_PALETTES = {
    # The four shells are intentionally aged rather than brand-identical.
    # Screen/key/hardware positions remain fixed so palette changes cannot
    # affect silhouettes, collision, or room usability.
    "ivory": ["#111416", "#4A4B48", "#77756E", "#AAA69A", "#D8D1C0",
              "#101B1D", "#376F72", "#A9D4C8", "#B8A55F", "#ECE5D5"],
    "charcoal": ["#07090A", "#171C1F", "#2B3439", "#48565D", "#718086",
                 "#0A1719", "#28656A", "#74C5C0", "#B69750", "#B9C4C4"],
    "teal": ["#061011", "#123033", "#1D5155", "#337B7D", "#68AAA5",
              "#091719", "#2D7277", "#83D4CD", "#C1A057", "#D2E8E1"],
    "burgundy": ["#11090B", "#30151B", "#57232E", "#83384A", "#AD5D6E",
                  "#10171A", "#34626D", "#82BEC2", "#C09B54", "#E6D3C9"],
}


def make_wooden_chair(model_name, cushioned=False, colors=None):
    colors = colors or WOOD_PALETTES["oak"]
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors, MAZE_TEXTURES)
    mat = make_material(model_name.replace("_", " ").title() + " pixel paint",
                        image, roughness=0.86, metallic=0.0)
    count = len(colors)
    objects = []
    for index, (x, y) in enumerate(((-0.19, -0.19), (0.19, -0.19),
                                    (-0.19, 0.19), (0.19, 0.19))):
        box("ChairLeg_%d" % (index + 1), (x, y, 0.24),
            (0.07, 0.07, 0.48), mat, 1 if index % 2 else 2,
            count, objects, bevel=0.001)
    box("ChairSeat", (0.0, 0.0, 0.51), (0.50, 0.50, 0.10), mat, 3,
        count, objects, bevel=0.003)
    for side, x in (("L", -0.21), ("R", 0.21)):
        box("BackPost_%s" % side, (x, 0.20, 0.74),
            (0.065, 0.065, 0.54), mat, 2, count, objects, bevel=0.001)
    box("BackTop", (0.0, 0.20, 0.93), (0.48, 0.085, 0.15), mat, 3,
        count, objects, bevel=0.003)
    box("BackRail", (0.0, 0.20, 0.72), (0.38, 0.065, 0.09), mat, 2,
        count, objects, bevel=0.001)
    if cushioned:
        box("SeatCushion", (0.0, -0.01, 0.585), (0.42, 0.42, 0.08), mat, 6,
            count, objects, bevel=0.006)
        box("BackCushion", (0.0, 0.155, 0.82), (0.34, 0.07, 0.25), mat, 5,
            count, objects, bevel=0.005)
        for x in (-0.13, 0.13):
            box("CushionTack_%s" % ("L" if x < 0 else "R"),
                (x, 0.114, 0.82), (0.025, 0.012, 0.025), mat, 7,
                count, objects, bevel=0.0)
    return objects, (1.45, -2.15, 1.55), (0.0, 0.0, 0.50)


def make_wooden_table(model_name="wooden_table", colors=None):
    colors = colors or WOOD_PALETTES["oak"]
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors, MAZE_TEXTURES)
    mat = make_material(model_name.replace("_", " ").title() + " pixel paint",
                        image, roughness=0.87, metallic=0.0)
    count = len(colors)
    objects = []
    for index, (x, y) in enumerate(((-0.52, -0.29), (0.52, -0.29),
                                    (-0.52, 0.29), (0.52, 0.29))):
        box("TableLeg_%d" % (index + 1), (x, y, 0.34),
            (0.11, 0.11, 0.68), mat, 1 if index % 2 else 2,
            count, objects, bevel=0.001)
    box("TableTop", (0.0, 0.0, 0.73), (1.20, 0.76, 0.12), mat, 3,
        count, objects, bevel=0.004)
    box("FrontApron", (0.0, -0.32, 0.61), (1.00, 0.09, 0.18), mat, 2,
        count, objects, bevel=0.001)
    box("BackApron", (0.0, 0.32, 0.61), (1.00, 0.09, 0.18), mat, 1,
        count, objects, bevel=0.001)
    box("TableDrawer", (0.0, -0.375, 0.63), (0.44, 0.025, 0.15), mat, 4,
        count, objects, bevel=0.001)
    box("DrawerHandle", (0.0, -0.392, 0.63), (0.16, 0.012, 0.035), mat, 6,
        count, objects, bevel=0.0)
    return objects, (2.05, -2.85, 1.65), (0.0, 0.0, 0.38)


def make_restaurant_party_table():
    """Original block-built family restaurant table with attached place settings.

    The long cloth, party hats, plates, cups and balloon cluster ship as one
    authored prop so streamed dining recipes stay coherent and inexpensive.
    It evokes a festive arcade restaurant without copying a branded character,
    logo or wall treatment from the visual reference.
    """
    colors = [
        "#130D18", "#382044", "#672E68", "#9D3F78", "#D45B83",
        "#F0C84B", "#42B9C7", "#D9E0D8", "#5C2C22", "#AD6940",
    ]
    image = make_pixel_atlas(
        "restaurant_party_table_pixel_atlas", colors, MAZE_TEXTURES)
    mat = make_material("Restaurant party table pixel paint", image,
                        roughness=0.88, metallic=0.0)
    count = len(colors)
    objects = []

    # A sturdy dark restaurant table under a burgundy-violet cloth.
    for index, (x, y) in enumerate(((-1.05, -0.34), (1.05, -0.34),
                                    (-1.05, 0.34), (1.05, 0.34))):
        box("PartyTableLeg_%d" % (index + 1), (x, y, 0.34),
            (0.12, 0.12, 0.68), mat, 8 if index % 2 else 9,
            count, objects, bevel=0.002)
    box("PartyTableTop", (0.0, 0.0, 0.73), (2.55, 0.90, 0.13), mat, 8,
        count, objects, bevel=0.005)
    box("PartyClothTop", (0.0, 0.0, 0.815), (2.62, 0.96, 0.05), mat, 2,
        count, objects, bevel=0.003)
    for y, name in ((-0.475, "Front"), (0.475, "Back")):
        box("PartyCloth%s" % name, (0.0, y, 0.61), (2.62, 0.05, 0.42),
            mat, 3, count, objects, bevel=0.001)

    # Chunky moon/star-like cloth motifs made from original geometric glyphs.
    for index, x in enumerate((-0.98, -0.32, 0.36, 1.00)):
        box("ClothGlyph_%d_A" % index, (x, -0.505, 0.64),
            (0.18, 0.012, 0.055), mat, 5 if index % 2 else 6,
            count, objects)
        box("ClothGlyph_%d_B" % index, (x, -0.511, 0.64),
            (0.055, 0.012, 0.18), mat, 5 if index % 2 else 6,
            count, objects)

    # Four paired place settings are deliberately low-poly and pixel-painted.
    for index, x in enumerate((-0.92, -0.31, 0.31, 0.92)):
        for side, y in (("F", -0.27), ("B", 0.27)):
            cylinder("Plate_%d_%s" % (index + 1, side),
                     (x, y, 0.865), 0.13, 0.025, 8, mat, 7,
                     count, objects)
            cylinder("Cup_%d_%s" % (index + 1, side),
                     (x + 0.16, y, 0.925), 0.045, 0.13, 8, mat,
                     6 if index % 2 else 5, count, objects)
            cone("PartyHat_%d_%s" % (index + 1, side),
                 (x - 0.03, y, 0.995), 0.09, 0.012, 0.24, 8, mat,
                 5 if (index + (0 if side == "F" else 1)) % 2 else 4,
                 count, objects)

    # A compact block-balloon centrepiece gives the room its festive silhouette.
    cylinder("BalloonStem", (0.0, 0.0, 1.34), 0.035, 0.96, 8, mat, 7,
             count, objects)
    for index, (x, y, z, color) in enumerate((
            (-0.16, 0.00, 1.77, 4), (0.14, -0.05, 1.91, 5),
            (0.02, 0.12, 2.05, 6), (0.25, 0.08, 1.72, 3))):
        box("BlockBalloon_%d" % (index + 1), (x, y, z),
            (0.28, 0.24, 0.36), mat, color, count, objects, bevel=0.025,
            rotation=(0.0, 0.0, math.radians(-8 + index * 6)))
        box("BalloonTie_%d" % (index + 1), (x, y, z - 0.22),
            (0.06, 0.06, 0.07), mat, color, count, objects)

    return objects, (3.65, -4.75, 2.80), (0.0, 0.0, 0.95)


def make_wooden_dresser(model_name="wooden_dresser_sideboard", colors=None):
    colors = colors or WOOD_PALETTES["oak"]
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors, MAZE_TEXTURES)
    mat = make_material(model_name.replace("_", " ").title() + " pixel paint", image,
                        roughness=0.86, metallic=0.0)
    count = len(colors)
    objects = []
    box("DresserBody", (0.0, 0.0, 0.44), (1.16, 0.56, 0.80), mat, 1,
        count, objects, bevel=0.004)
    box("DresserTop", (0.0, 0.0, 0.88), (1.24, 0.64, 0.10), mat, 4,
        count, objects, bevel=0.004)
    box("DresserPlinth", (0.0, 0.0, 0.07), (1.20, 0.60, 0.14), mat, 0,
        count, objects, bevel=0.002)
    for index, x in enumerate((-0.39, 0.0, 0.39)):
        box("TopDrawer_%d" % (index + 1), (x, -0.293, 0.69),
            (0.34, 0.025, 0.16), mat, 3, count, objects, bevel=0.001)
        box("DrawerPull_%d" % (index + 1), (x, -0.311, 0.69),
            (0.12, 0.012, 0.03), mat, 6, count, objects, bevel=0.0)
        box("LowerDoor_%d" % (index + 1), (x, -0.293, 0.35),
            (0.34, 0.025, 0.42), mat, 2, count, objects, bevel=0.002)
        box("DoorInset_%d" % (index + 1), (x, -0.310, 0.35),
            (0.26, 0.012, 0.32), mat, 1, count, objects, bevel=0.001)
    return objects, (2.15, -3.15, 1.75), (0.0, 0.0, 0.45)


def make_retro_computer(model_name, style="compact", colors=None):
    """Block-authored desk computer families based on the supplied references.

    All four silhouettes sit on an existing desk/table surface with a floor-
    flush local pivot.  Their maximum height stays below 0.92 m so a mounted
    workstation clears both the camera and the 2.20 m A-Z hunter envelope.
    """
    colors = colors or COMPUTER_PALETTES["ivory"]
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors, MAZE_TEXTURES)
    mat = make_material(model_name.replace("_", " ").title() + " pixel paint",
                        image, roughness=0.88, metallic=0.03)
    count = len(colors)
    objects = []

    def screen(x, y, z, width, height):
        # Deep CRT bezel and inset phosphor glass keep the display readable
        # from a dark corridor without copying an operating-system logo.
        box("MonitorShell", (x, y, z), (width, .40, height), mat, 3,
            count, objects, bevel=.012)
        box("MonitorFace", (x, y - .208, z), (width * .79, .022, height * .68),
            mat, 0, count, objects, bevel=.008)
        box("MonitorGlow", (x, y - .222, z), (width * .68, .012, height * .54),
            mat, 5, count, objects, bevel=.003)
        # Original block glyph: a tiny route prompt, not branded UI artwork.
        for index, (gx, gz, gw, gh) in enumerate((
                (-.13, .08, .17, .025), (-.13, .01, .25, .025),
                (-.13, -.06, .20, .025), (.14, -.07, .055, .16))):
            box("ScreenGlyph_%d" % (index + 1),
                (x + gx * width, y - .231, z + gz * height),
                (gw * width, .008, gh * height), mat,
                6 if index < 3 else 7, count, objects)

    def keyboard(x=0.0, y=-.40, z=.075, width=.78, depth=.30):
        box("KeyboardBody", (x, y, z), (width, depth, .105), mat, 4,
            count, objects, bevel=.006, rotation=(math.radians(-4), 0.0, 0.0))
        for row in range(4):
            for column in range(10):
                box("Key_%d_%d" % (row, column),
                    (x - width * .39 + column * width * .086,
                     y - depth * .10 + row * depth * .18,
                     z + .065 + row * .004),
                    (width * .06, depth * .11, .025), mat,
                    9 if (row + column) % 5 else 8, count, objects,
                    bevel=.001)
        box("SpaceBar", (x, y + depth * .22, z + .072),
            (width * .38, depth * .105, .025), mat, 9, count, objects,
            bevel=.001)

    def mouse(x=.48, y=-.43, z=.065):
        box("Mouse", (x, y, z), (.15, .22, .10), mat, 4,
            count, objects, bevel=.018)
        box("MouseButton", (x, y - .045, z + .058), (.11, .09, .018), mat, 9,
            count, objects, bevel=.002)

    if style == "compact":
        box("CompactBase", (0.0, .02, .13), (1.02, .55, .26), mat, 2,
            count, objects, bevel=.009)
        screen(.12, .04, .56, .78, .66)
        box("SideExpansion", (-.49, .02, .43), (.23, .46, .72), mat, 3,
            count, objects, bevel=.006)
        for index, z in enumerate((.19, .28, .37, .46, .55)):
            box("SideVent_%d" % index, (-.615, -.085, z), (.015, .20, .025),
                mat, 1, count, objects)
        keyboard(.08, -.43, .075, .78, .28)
        mouse(.55, -.43, .065)
    elif style == "tower":
        box("Tower", (-.49, .06, .39), (.31, .48, .78), mat, 2,
            count, objects, bevel=.007)
        box("TowerFace", (-.49, -.188, .42), (.25, .018, .66), mat, 1,
            count, objects, bevel=.002)
        box("DriveBay", (-.49, -.201, .58), (.18, .012, .075), mat, 4,
            count, objects)
        box("PowerLight", (-.49, -.209, .18), (.045, .008, .045), mat, 7,
            count, objects)
        screen(.12, .06, .54, .68, .60)
        for side, x in (("L", -.26), ("R", .52)):
            box("Speaker_%s" % side, (x, -.10, .35), (.12, .20, .40), mat, 1,
                count, objects, bevel=.004)
            box("SpeakerCone_%s" % side, (x, -.207, .37), (.065, .012, .15),
                mat, 0, count, objects, bevel=.006)
        keyboard(.14, -.43, .075, .72, .28)
        mouse(.55, -.43, .065)
    elif style == "desktop":
        box("DesktopCase", (0.0, .02, .14), (1.00, .54, .28), mat, 2,
            count, objects, bevel=.008)
        box("FloppySlot", (-.20, -.258, .16), (.29, .012, .045), mat, 0,
            count, objects)
        box("DriveButton", (.27, -.266, .16), (.055, .010, .055), mat, 8,
            count, objects)
        screen(.08, .05, .60, .73, .64)
        box("MonitorFoot", (.08, .02, .31), (.30, .25, .10), mat, 1,
            count, objects, bevel=.004)
        keyboard(.02, -.43, .075, .80, .28)
        mouse(.53, -.43, .065)
    else:  # keyboard-terminal / wedge computer
        # The shallow keyboard rake lowers the front lip by about 1.5 cm;
        # lift the shell so its authored surface pivot remains exactly flush.
        box("TerminalWedge", (0.0, -.03, .166), (1.02, .60, .30), mat, 2,
            count, objects, bevel=.010, rotation=(math.radians(-3), 0.0, 0.0))
        screen(.05, .10, .61, .68, .61)
        keyboard(.0, -.29, .24, .80, .29)
        box("CassetteSlot", (-.34, .02, .27), (.18, .012, .055), mat, 0,
            count, objects)
        box("TerminalBadge", (.34, -.32, .26), (.11, .018, .055), mat, 8,
            count, objects)

    return objects, (2.25, -3.15, 1.85), (0.0, -0.05, 0.42)


OFFICE_PALETTES = {
    "charcoal": ["#070A0D", "#151B20", "#29343C", "#46545D",
                 "#657278", "#9AA5A5", "#24434A", "#4F8B8D"],
    "teal": ["#071012", "#102A2E", "#1C4A4E", "#337176",
              "#64A6A4", "#A5CBC4", "#D9E5DB", "#BE9B55"],
}


def make_office_desk(model_name="office_desk", colors=None):
    colors = colors or ["#16191D", "#343B43", "#626C75", "#A9B0B5",
                        "#6B452B", "#9A6841", "#D4B07A", "#3A8A8B"]
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors,
                             MAZE_TEXTURES)
    mat = make_material(model_name.replace("_", " ").title() + " pixel paint",
                        image, roughness=.84, metallic=.05)
    count = len(colors)
    objects = []
    box("DeskTop", (0, 0, .77), (1.65, .72, .12), mat, 5, count, objects, bevel=.008)
    for x in (-.73, .73):
        box("DeskLeg", (x, .0, .39), (.12, .60, .72), mat, 1, count, objects, bevel=.004)
    box("ModestyPanel", (0, .27, .45), (1.42, .10, .55), mat, 2, count, objects, bevel=.004)
    box("DrawerPedestal", (.52, -.12, .39), (.44, .48, .66), mat, 2, count, objects, bevel=.005)
    for index, z in enumerate((.20, .40, .60)):
        box("Drawer_%d" % index, (.52, -.366, z), (.36, .025, .15), mat, 3,
            count, objects, bevel=.002)
        box("Pull_%d" % index, (.52, -.386, z), (.13, .018, .025), mat, 7,
            count, objects)
    box("CableGrommet", (-.52, -.12, .845), (.16, .16, .025), mat, 0,
        count, objects, bevel=.02)
    return objects, (2.4, -3.4, 2.0), (0, 0, .42)


def make_office_task_chair(model_name="office_task_chair", colors=None):
    colors = colors or ["#111418", "#272D35", "#48515B", "#79838C",
                        "#286A70", "#3F9A9C", "#A9D5D0", "#D8E3E0"]
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors,
                             MAZE_TEXTURES)
    mat = make_material(model_name.replace("_", " ").title() + " pixel paint",
                        image, roughness=.82, metallic=.08)
    count = len(colors)
    objects = []
    box("Seat", (0, 0, .56), (.62, .62, .14), mat, 4, count, objects, bevel=.025)
    box("SeatCushion", (0, -.03, .655), (.54, .52, .08), mat, 5, count, objects, bevel=.025)
    box("Back", (0, .27, 1.02), (.58, .13, .75), mat, 4, count, objects, bevel=.025)
    box("BackInset", (0, .192, 1.03), (.48, .035, .61), mat, 5, count, objects, bevel=.018)
    cylinder("Stem", (0, 0, .31), .055, .42, 8, mat, 2, count, objects, bevel=.004)
    for index, angle in enumerate(range(0, 360, 72)):
        rad = math.radians(angle)
        x, y = math.cos(rad) * .27, math.sin(rad) * .27
        box("CasterArm_%d" % index, (x * .55, y * .55, .15),
            (.34, .07, .07), mat, 2, count, objects,
            rotation=(0, 0, rad), bevel=.004)
        cylinder("Caster_%d" % index, (x, y, .10), .055, .08, 8, mat, 0,
                 count, objects, bevel=.002)
    return objects, (2.5, -3.2, 1.85), (0, 0, .58)


def make_office_security_console(model_name="office_crt_security_console",
                                 colors=None):
    colors = colors or ["#101318", "#2A313A", "#535F69", "#89949A",
                        "#2B7679", "#58B6B0", "#A9F1DF", "#E9F8EF"]
    objects, _, _ = make_office_desk(model_name, colors)
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors,
                             MAZE_TEXTURES)
    mat = make_material(model_name.replace("_", " ").title() + " pixel paint",
                        image, roughness=.84, metallic=.08)
    count = len(colors)
    for index, x in enumerate((-.48, 0, .48)):
        box("MonitorShell_%d" % index, (x, .08, 1.18), (.43, .35, .48), mat,
            2, count, objects, bevel=.012)
        box("MonitorScreen_%d" % index, (x, -.101, 1.19), (.34, .018, .34), mat,
            5 if index == 1 else 4, count, objects, bevel=.006)
        box("MonitorGlow_%d" % index, (x, -.113, 1.19), (.26, .009, .25), mat,
            6, count, objects, bevel=.003)
        box("MonitorStand_%d" % index, (x, .08, .88), (.12, .18, .18), mat,
            1, count, objects, bevel=.004)
    box("ConsoleKeyboard", (0, -.25, .86), (.88, .28, .09), mat, 3, count,
        objects, bevel=.006, rotation=(math.radians(-4), 0, 0))
    return objects, (2.8, -3.8, 2.3), (0, 0, .70)


def make_office_cubicle_partition(model_name="office_cubicle_partition",
                                  colors=None):
    colors = colors or ["#171B20", "#39434B", "#687681", "#A5AFB3",
                        "#305F68", "#4E8D91", "#A8C5C1", "#D7DDD8"]
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors,
                             MAZE_TEXTURES)
    mat = make_material(model_name.replace("_", " ").title() + " pixel paint",
                        image, roughness=.93, metallic=.03)
    count = len(colors)
    objects = []
    box("PartitionPanel", (0, 0, .85), (1.80, .12, 1.60), mat, 4, count,
        objects, bevel=.006)
    for x in (-.88, .88):
        box("FramePost", (x, 0, .85), (.08, .18, 1.70), mat, 1, count,
            objects, bevel=.003)
        box("Foot", (x, 0, .06), (.36, .42, .10), mat, 2, count, objects,
            bevel=.004)
    box("TopRail", (0, 0, 1.68), (1.82, .18, .08), mat, 2, count, objects,
        bevel=.003)
    return objects, (2.7, -3.7, 2.2), (0, 0, .78)


def make_office_printer(model_name="office_printer", colors=None):
    colors = colors or ["#101419", "#303840", "#58636B", "#929B9E",
                        "#D5D8D4", "#F1F0E8", "#43898B", "#83CFCA"]
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors,
                             MAZE_TEXTURES)
    mat = make_material(model_name.replace("_", " ").title() + " pixel paint",
                        image, roughness=.86, metallic=.03)
    count = len(colors)
    objects = []
    box("PrinterBody", (0, 0, .29), (.72, .58, .48), mat, 3, count, objects,
        bevel=.016)
    box("ScannerLid", (0, .02, .57), (.68, .54, .10), mat, 5, count, objects,
        bevel=.010)
    box("PaperTray", (0, -.33, .18), (.56, .22, .12), mat, 1, count, objects,
        bevel=.006)
    box("Paper", (0, -.41, .22), (.45, .28, .025), mat, 5, count, objects)
    box("ControlPanel", (.23, -.30, .47), (.20, .11, .10), mat, 6, count,
        objects, bevel=.004)
    return objects, (2.2, -3.1, 1.55), (0, 0, .30)


def make_office_water_cooler(model_name="office_water_cooler", colors=None):
    colors = colors or ["#12161A", "#343D43", "#67737A", "#B7C0C0",
                        "#DDE7E5", "#7BC5C7", "#BEEBED", "#3C7E83"]
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors,
                             MAZE_TEXTURES)
    mat = make_material(model_name.replace("_", " ").title() + " pixel paint",
                        image, roughness=.82, metallic=.03)
    count = len(colors)
    objects = []
    box("CoolerBody", (0, 0, .62), (.55, .48, 1.12), mat, 3, count, objects,
        bevel=.014)
    box("DispenserWell", (0, -.255, .78), (.38, .055, .32), mat, 0, count,
        objects, bevel=.006)
    for index, x in enumerate((-.10, .10)):
        box("Tap_%d" % index, (x, -.32, .88), (.08, .12, .12), mat,
            6 if index else 7, count, objects, bevel=.004)
    cylinder("Bottle", (0, 0, 1.48), .25, .60, 12, mat, 6, count, objects,
             bevel=.008)
    cylinder("BottleNeck", (0, 0, 1.16), .10, .20, 10, mat, 7, count,
             objects, bevel=.004)
    return objects, (2.3, -3.3, 1.95), (0, 0, .82)


def office_equipment_material(model_name, colors=None):
    colors = colors or ["#101419", "#303840", "#59646C", "#919A9D",
                        "#D7DAD5", "#F0EFE7", "#31777C", "#76C5C1"]
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors, MAZE_TEXTURES)
    return (make_material(model_name.replace("_", " ").title() + " pixel paint",
                          image, roughness=.86, metallic=.05), len(colors))


def make_office_photocopier(model_name="office_photocopier", colors=None):
    mat, count = office_equipment_material(model_name, colors)
    o = []
    box("CopierBase", (0, .03, .49), (.84, .72, .98), mat, 2, count, o,
        bevel=.014)
    for index, z in enumerate((.22, .43, .64)):
        box("PaperDrawer_%d" % index, (0, -.342, z), (.70, .035, .16), mat,
            3, count, o, bevel=.003)
        box("DrawerHandle_%d" % index, (0, -.368, z), (.25, .018, .025), mat,
            6, count, o)
    box("ScannerBody", (0, 0, 1.03), (.92, .80, .22), mat, 3, count, o,
        bevel=.012)
    box("ScannerLid", (-.04, .03, 1.19), (.78, .70, .10), mat, 5, count, o,
        bevel=.008)
    box("ControlPanel", (.42, -.31, 1.08), (.28, .18, .12), mat, 6, count,
        o, bevel=.006)
    box("OutputTray", (0, -.42, .84), (.58, .28, .08), mat, 1, count, o,
        bevel=.004)
    return o, (2.5, -3.5, 2.0), (0, 0, .63)


def make_office_shredder(model_name="office_shredder", colors=None):
    mat, count = office_equipment_material(model_name, colors)
    o = []
    box("ShredderBin", (0, 0, .43), (.48, .40, .78), mat, 1, count, o,
        bevel=.012)
    box("ShredderHead", (0, 0, .87), (.54, .44, .18), mat, 2, count, o,
        bevel=.010)
    box("PaperSlot", (0, -.04, .972), (.34, .08, .025), mat, 0, count, o,
        bevel=.004)
    box("PowerButton", (.17, -.225, .89), (.07, .018, .07), mat, 7, count, o,
        bevel=.005)
    box("PaperStrip", (-.06, -.02, 1.19), (.28, .025, .50), mat, 5, count,
        o, rotation=(math.radians(-7), 0, 0), bevel=.002)
    return o, (1.9, -2.7, 1.6), (0, 0, .55)


def make_office_file_boxes(model_name="office_file_boxes", colors=None):
    mat, count = office_equipment_material(model_name, colors)
    o = []
    for index, (x, y, z, yaw) in enumerate(((-.28, 0, .22, 0),
                                             (.27, .03, .23, 0),
                                             (-.12, .01, .66, .08),
                                             (.31, .02, .69, -.05))):
        box("ArchiveBox_%d" % index, (x, y, z), (.48, .58, .42), mat,
            4 if index % 2 else 3, count, o, rotation=(0, 0, yaw), bevel=.006)
        box("Label_%d" % index, (x, y - .302, z + .03), (.22, .018, .11),
            mat, 5, count, o)
    return o, (2.1, -3.0, 1.7), (0, 0, .45)


def make_office_corner_workstation(model_name="office_corner_workstation",
                                   colors=None):
    mat, count = office_equipment_material(model_name, colors)
    o = []
    box("MainTop", (-.25, 0, .78), (1.55, .70, .12), mat, 4, count, o,
        bevel=.008)
    box("ReturnTop", (.55, .48, .78), (.65, 1.18, .12), mat, 4, count, o,
        bevel=.008)
    for x, y in ((-.92, 0), (.42, -.26), (.77, .95)):
        box("DeskLeg_%s_%s" % (x, y), (x, y, .39), (.11, .11, .72), mat,
            2, count, o, bevel=.004)
    box("DrawerPedestal", (-.62, .08, .40), (.44, .48, .68), mat, 2,
        count, o, bevel=.006)
    for index, z in enumerate((.23, .45, .66)):
        box("Drawer_%d" % index, (-.62, -.171, z), (.36, .025, .15), mat,
            3, count, o, bevel=.002)
    return o, (3.1, -4.2, 2.3), (0, .15, .45)


def make_catalog_furnishing(model_name):
    """Authored low-poly models for catalog entries that previously had no GLB."""
    colors = ["#101419", "#303840", "#5C6870", "#929B9E",
              "#6B452B", "#B27A45", "#3F8F8C", "#D8C978",
              "#8D3959", "#D97A9A", "#E5E0D1", "#7BA55B"]
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors, MAZE_TEXTURES)
    mat = make_material(model_name.replace("_", " ").title() + " pixel paint",
                        image, roughness=.88, metallic=.06)
    count = len(colors)
    o = []
    eye, look = (2.8, -4.0, 2.4), (0, 0, .8)

    if model_name in {"arcade_carpet_circle", "arcade_carpet_runner"}:
        dims = (1.9, 1.9, .035) if model_name.endswith("circle") else (1.1, 3.2, .035)
        box("CarpetBase", (0, 0, .018), dims, mat, 8, count, o, bevel=.015)
        for i in range(-3, 4):
            box("PixelStripe_%d" % i, (i * .18, 0, .040), (.08, dims[1] * .84, .012),
                mat, 6 if i % 2 else 7, count, o)
        eye, look = (2.8, -3.8, 2.3), (0, 0, 0)
    elif model_name in {"flower_blue", "flower_rose", "flower_sun", "flower_violet"}:
        bloom = {"flower_blue": 6, "flower_rose": 8, "flower_sun": 7,
                 "flower_violet": 9}[model_name]
        cylinder("Stem", (0, 0, .38), .035, .72, 6, mat, 11, count, o)
        for i in range(6):
            a = math.radians(i * 60)
            cylinder("Petal_%d" % i, (math.cos(a) * .13, math.sin(a) * .13, .78),
                     .09, .08, 6, mat, bloom, count, o, bevel=.008)
        cylinder("FlowerCenter", (0, 0, .80), .10, .10, 8, mat, 7, count, o)
        box("LeafL", (-.12, 0, .39), (.22, .06, .10), mat, 11, count, o,
            rotation=(0, math.radians(-25), 0), bevel=.006)
        eye, look = (1.8, -2.5, 1.5), (0, 0, .42)
    elif model_name in {"locker", "maintenance_tool_cabinet", "breaker_cabinet"}:
        width = .68 if model_name == "locker" else .82
        height = 2.02 if model_name == "locker" else 1.65
        box("CabinetBody", (0, 0, height / 2), (width, .62, height), mat, 2,
            count, o, bevel=.008)
        box("FrontDoor", (0, -.321, height / 2), (width * .88, .025, height * .88),
            mat, 3, count, o, bevel=.004)
        for i in range(5):
            box("Vent_%d" % i, (0, -.342, height - .28 - i * .07),
                (width * .45, .012, .025), mat, 0, count, o)
        box("Handle", (width * .28, -.355, height * .48), (.05, .03, .28),
            mat, 7, count, o, bevel=.004)
        if model_name == "breaker_cabinet":
            for row in range(3):
                for col in range(2):
                    box("Breaker_%d_%d" % (row, col),
                        ((col - .5) * .22, -.353, .62 + row * .22),
                        (.12, .035, .13), mat, 8 if row == 2 else 1, count, o)
    elif model_name in {"utility_cart", "maintenance_cleaning_cart",
                        "backstage_repair_stand"}:
        box("CartDeck", (0, 0, .38), (1.12, .62, .12), mat, 2, count, o,
            bevel=.008)
        for x in (-.48, .48):
            for y in (-.24, .24):
                cylinder("Wheel_%s_%s" % (x, y), (x, y, .15), .12, .09, 8,
                         mat, 0, count, o, bevel=.004)
        for z in (.78, 1.20):
            box("Shelf_%s" % z, (0, .05, z), (1.02, .54, .10), mat, 3,
                count, o, bevel=.006)
        for x in (-.48, .48):
            box("Post_%s" % x, (x, .25, .86), (.07, .07, 1.10), mat, 2,
                count, o)
        if model_name == "maintenance_cleaning_cart":
            cylinder("Bucket", (-.23, -.05, .59), .22, .34, 10, mat, 7,
                     count, o, bevel=.008)
            box("MopHandle", (.23, .10, 1.10), (.06, .06, 1.65), mat, 5,
                count, o, rotation=(0, math.radians(-10), 0))
        else:
            box("ToolChest", (0, .02, .65), (.82, .42, .42), mat, 8,
                count, o, bevel=.008)
    elif model_name in {"stage_platform", "stage_speaker"}:
        if model_name == "stage_platform":
            box("StageBase", (0, 0, .30), (2.7, 2.1, .60), mat, 1, count, o,
                bevel=.012)
            box("StageTop", (0, 0, .64), (2.82, 2.22, .10), mat, 4, count, o,
                bevel=.008)
            for x in (-.8, 0, .8):
                box("Footlight_%s" % x, (x, -1.08, .72), (.36, .12, .12),
                    mat, 7, count, o, bevel=.006)
        else:
            box("SpeakerCabinet", (0, 0, .78), (.82, .62, 1.56), mat, 0,
                count, o, bevel=.012)
            for z, radius in ((.52, .24), (1.10, .20)):
                cylinder("SpeakerCone_%s" % z, (0, -.323, z), radius, .035,
                         12, mat, 3, count, o, bevel=.006)
            box("Handle", (0, .0, 1.45), (.34, .16, .08), mat, 6, count, o)
    elif model_name in {"arcade_token_changer", "prize_claw_machine",
                        "snack_kiosk", "prize_counter"}:
        width = 1.15 if model_name in {"snack_kiosk", "prize_counter"} else .82
        box("MachineBody", (0, 0, .92), (width, .72, 1.84), mat, 2, count, o,
            bevel=.012)
        box("Header", (0, 0, 1.78), (width * .92, .76, .18), mat, 8,
            count, o, bevel=.008)
        box("Display", (0, -.371, 1.28), (width * .68, .025, .48), mat, 6,
            count, o, bevel=.006)
        box("Control", (0, -.39, .76), (width * .58, .07, .20), mat, 7,
            count, o, bevel=.004)
        box("CollectionBin", (0, -.39, .30), (width * .58, .08, .30), mat,
            0, count, o, bevel=.006)
        if model_name == "prize_claw_machine":
            for x in (-.28, .28):
                box("GlassPost_%s" % x, (x, -.36, 1.34), (.05, .04, .70),
                    mat, 10, count, o)
            box("ClawRail", (0, -.39, 1.54), (.52, .04, .05), mat, 7,
                count, o)
    elif model_name in {"arcade_basketball_hoop", "garden_planter_bench"}:
        if model_name == "arcade_basketball_hoop":
            box("Backboard", (0, .36, 1.95), (1.18, .12, .78), mat, 10,
                count, o, bevel=.008)
            cylinder("Hoop", (0, -.08, 1.68), .30, .06, 16, mat, 8,
                     count, o, bevel=.004)
            box("BallRamp", (0, .25, .48), (1.12, 1.70, .16), mat, 2,
                count, o, rotation=(math.radians(-12), 0, 0), bevel=.008)
            for x in (-.5, .5):
                box("RampRail_%s" % x, (x, .25, .78), (.07, 1.72, .60), mat,
                    1, count, o)
        else:
            box("Planter", (0, .32, .42), (2.1, .72, .84), mat, 4, count, o,
                bevel=.012)
            box("Soil", (0, .32, .82), (1.88, .56, .08), mat, 0, count, o)
            box("BenchSeat", (0, -.48, .54), (2.15, .62, .14), mat, 5,
                count, o, bevel=.010)
            for x in (-.82, .82):
                box("BenchLeg_%s" % x, (x, -.48, .27), (.14, .48, .54), mat,
                    4, count, o)
    elif model_name in {"broken_aquarium", "mascot_statue", "giant_tree",
                        "grass_fern"}:
        if model_name == "broken_aquarium":
            box("TankStand", (0, 0, .42), (1.35, .72, .84), mat, 4, count, o,
                bevel=.008)
            for x in (-.62, .62):
                box("TankSide_%s" % x, (x, 0, 1.23), (.08, .68, .82), mat,
                    6, count, o)
            box("TankBack", (0, .31, 1.23), (1.22, .06, .82), mat, 6,
                count, o)
            box("CrackedBase", (0, 0, .84), (1.28, .68, .08), mat, 3,
                count, o)
        elif model_name == "mascot_statue":
            cylinder("Plinth", (0, 0, .16), .52, .32, 8, mat, 3, count, o,
                     bevel=.008)
            box("Body", (0, 0, .90), (.62, .44, 1.10), mat, 8, count, o,
                bevel=.08)
            box("Head", (0, 0, 1.62), (.72, .62, .62), mat, 9, count, o,
                bevel=.10)
            for x in (-.20, .20):
                box("Eye_%s" % x, (x, -.325, 1.70), (.10, .03, .12), mat,
                    10, count, o)
        elif model_name == "giant_tree":
            cylinder("Trunk", (0, 0, 1.55), .48, 3.10, 10, mat, 4, count, o,
                     bevel=.012)
            for i, (x, y, z) in enumerate(((-.7, 0, 2.8), (.7, 0, 2.9),
                                            (0, -.6, 3.25), (0, .6, 3.1))):
                cone("LeafCrown_%d" % i, (x, y, z), .82, .30, 1.35, 8,
                     mat, 11, count, o, bevel=.012)
            eye, look = (6.0, -7.0, 4.8), (0, 0, 1.8)
        else:
            for i in range(9):
                a = math.radians(i * 40)
                box("FernLeaf_%d" % i, (math.cos(a) * .28, math.sin(a) * .28, .42),
                    (.12, .65, .10), mat, 11, count, o,
                    rotation=(math.radians(-28), 0, a), bevel=.010)
            eye, look = (2.2, -2.8, 1.8), (0, 0, .35)
    elif model_name == "carnival_carousel":
        cylinder("CarouselBase", (0, 0, .22), 2.10, .44, 20, mat, 8,
                 count, o, bevel=.012)
        cylinder("CenterColumn", (0, 0, 1.80), .28, 3.10, 12, mat, 7,
                 count, o, bevel=.008)
        cone("Canopy", (0, 0, 3.15), 2.25, .35, .90, 20, mat, 9,
             count, o, bevel=.010)
        for i in range(8):
            a = math.radians(i * 45)
            x, y = math.cos(a) * 1.35, math.sin(a) * 1.35
            cylinder("Pole_%d" % i, (x, y, 1.72), .035, 2.45, 8, mat,
                     10, count, o)
            box("HorseBody_%d" % i, (x, y, 1.25), (.72, .26, .42), mat,
                5 if i % 2 else 6, count, o, rotation=(0, 0, a), bevel=.06)
            box("HorseHead_%d" % i,
                (x + math.cos(a) * .32, y + math.sin(a) * .32, 1.48),
                (.28, .25, .38), mat, 9, count, o, bevel=.05)
        eye, look = (6.5, -8.0, 5.2), (0, 0, 1.7)
    else:
        # Remaining special props receive a purpose-shaped carnival/arcade
        # structure rather than a generic cube placeholder.
        box("Base", (0, 0, .12), (1.25, .85, .24), mat, 2, count, o,
            bevel=.010)
        box("Body", (0, 0, .88), (.92, .62, 1.30), mat, 8, count, o,
            bevel=.018)
        box("Face", (0, -.326, 1.02), (.68, .025, .62), mat, 6, count, o,
            bevel=.008)
        box("Header", (0, 0, 1.62), (1.10, .70, .22), mat, 9, count, o,
            bevel=.010)
    return o, eye, look


def make_filing_cabinet():
    colors = ["#14191B", "#343D40", "#596467", "#899092", "#A64B43", "#C4A35C"]
    image = make_pixel_atlas("filing_cabinet_pixel_atlas", colors, MAZE_TEXTURES)
    mat = make_material("Filing cabinet pixel paint", image, roughness=0.82, metallic=0.16)
    count = len(colors)
    objects = []
    box("FileBody", (0.0, 0.0, 0.62), (0.58, 0.66, 1.20), mat, 1,
        count, objects, bevel=0.006)
    box("FileTop", (0.0, 0.0, 1.24), (0.60, 0.68, 0.08), mat, 3,
        count, objects, bevel=0.003)
    box("FileBase", (0.0, 0.0, 0.06), (0.60, 0.68, 0.12), mat, 0,
        count, objects, bevel=0.002)
    for index, z in enumerate((0.31, 0.66, 1.01)):
        box("FileDrawer_%d" % (index + 1), (0.0, -0.337, z),
            (0.48, 0.025, 0.28), mat, 2, count, objects, bevel=0.002)
        box("FileHandle_%d" % (index + 1), (0.0, -0.355, z + 0.04),
            (0.18, 0.012, 0.06), mat, 5, count, objects, bevel=0.0)
        box("LabelSlot_%d" % (index + 1), (0.0, -0.362, z - 0.055),
            (0.13, 0.004, 0.055), mat, 0, count, objects, bevel=0.0)
    for index, x in enumerate((-0.26, 0.26)):
        box("RustCorner_%d" % (index + 1), (x, -0.342, 1.23),
            (0.06, 0.03, 0.06), mat, 4, count, objects, bevel=0.0)
    return objects, (1.65, -2.55, 1.80), (0.0, 0.0, 0.62)


def make_supply_crates():
    colors = ["#111719", "#2B3436", "#455153", "#647174", "#8D6840", "#B28A52"]
    image = make_pixel_atlas("supply_crates_pixel_atlas", colors, MAZE_TEXTURES)
    mat = make_material("Supply crates pixel paint", image, roughness=0.84, metallic=0.10)
    count = len(colors)
    objects = []
    specs = (("Large", (0.0, 0.0, 0.23), (0.74, 0.58, 0.46)),
             ("Medium", (0.07, 0.02, 0.59), (0.56, 0.45, 0.28)),
             ("Small", (-0.08, 0.01, 0.84), (0.40, 0.34, 0.22)))
    for index, (label, location, dimensions) in enumerate(specs):
        box("Crate%s" % label, location, dimensions, mat, 1 + index,
            count, objects, bevel=0.004)
        x, y, z = location
        sx, sy, sz = dimensions
        for band, bx in enumerate((x - sx * 0.42, x + sx * 0.42)):
            band_z = max(z, (sz + 0.015) * 0.5)
            box("%sBand_%d" % (label, band + 1), (bx, y, band_z),
                (0.055, sy + 0.025, sz + 0.015), mat, 4,
                count, objects, bevel=0.001)
        box("%sHandle" % label, (x, y - sy * 0.515, z),
            (sx * 0.30, 0.018, sz * 0.18), mat, 0,
            count, objects, bevel=0.001)
    return objects, (1.65, -2.45, 1.55), (0.0, 0.0, 0.43)


def make_server_rack():
    colors = ["#0B1014", "#202C33", "#3B4B52", "#68777C", "#45BCAE", "#D2553F", "#D3A64D"]
    image = make_pixel_atlas("server_rack_pixel_atlas", colors, MAZE_TEXTURES)
    mat = make_material("Server rack pixel paint", image, roughness=0.78, metallic=0.18)
    count = len(colors)
    objects = []
    box("RackBody", (0.0, 0.0, 0.94), (0.64, 0.74, 1.84), mat, 1,
        count, objects, bevel=0.005)
    box("RackRecess", (0.0, -0.382, 0.98), (0.52, 0.025, 1.62), mat, 0,
        count, objects, bevel=0.002)
    for index, z in enumerate((0.29, 0.53, 0.77, 1.01, 1.25, 1.49, 1.68)):
        box("ServerTray_%d" % (index + 1), (0.0, -0.400, z),
            (0.45, 0.016, 0.15), mat, 2 if index % 2 else 3,
            count, objects, bevel=0.001)
        box("Status_%d" % (index + 1), (0.17, -0.412, z),
            (0.035, 0.006, 0.035), mat, 4 if index % 3 else 5,
            count, objects, bevel=0.0)
    box("RackTop", (0.0, 0.0, 1.88), (0.68, 0.78, 0.08), mat, 2,
        count, objects, bevel=0.003)
    box("RackBase", (0.0, 0.0, 0.06), (0.68, 0.78, 0.12), mat, 0,
        count, objects, bevel=0.002)
    return objects, (1.85, -2.85, 2.15), (0.0, 0.0, 0.95)


def make_vending_machine():
    colors = ["#101316", "#3B2024", "#6C3033", "#9D4341", "#222D30", "#63B7AC", "#D39A42", "#D9D0A8"]
    image = make_pixel_atlas("vending_machine_pixel_atlas", colors, MAZE_TEXTURES)
    mat = make_material("Vending machine pixel paint", image, roughness=0.78, metallic=0.10)
    count = len(colors)
    objects = []
    box("VendingBody", (0.0, 0.0, 0.91), (0.62, 0.74, 1.80), mat, 2,
        count, objects, bevel=0.006)
    box("DisplayRecess", (-0.07, -0.382, 1.15), (0.40, 0.025, 1.02), mat, 0,
        count, objects, bevel=0.002)
    box("DisplayGlass", (-0.07, -0.399, 1.15), (0.35, 0.008, 0.94), mat, 4,
        count, objects, bevel=0.001)
    for row, z in enumerate((0.84, 1.13, 1.42)):
        for col, x in enumerate((-0.18, -0.07, 0.04)):
            box("Drink_%d_%d" % (row + 1, col + 1), (x, -0.408, z),
                (0.07, 0.008, 0.14), mat, (5 + row + col) % 3 + 5,
                count, objects, bevel=0.0)
    box("ControlPanel", (0.22, -0.392, 1.21), (0.11, 0.022, 0.52), mat, 0,
        count, objects, bevel=0.001)
    box("VendingScreen", (0.22, -0.408, 1.36), (0.07, 0.010, 0.10), mat, 5,
        count, objects, bevel=0.0)
    box("VendingKeys", (0.22, -0.408, 1.15), (0.07, 0.010, 0.20), mat, 7,
        count, objects, bevel=0.0)
    box("Dispenser", (-0.07, -0.397, 0.34), (0.34, 0.020, 0.20), mat, 0,
        count, objects, bevel=0.002)
    return objects, (1.85, -2.85, 2.10), (0.0, 0.0, 0.90)


def make_floor_lamp(model_name="floor_lamp", colors=None, style="classic"):
    colors = colors or ["#17130F", "#40362B", "#6C5842", "#A08155", "#C9A86E", "#E0C994"]
    texture_dir = MAZE_TEXTURES if model_name == "floor_lamp" else MANSION_TEXTURES
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors, texture_dir)
    mat = make_material(model_name.replace("_", " ").title() + " pixel paint",
                        image, roughness=0.82, metallic=0.10)
    count = len(colors)
    objects = []
    if style == "tripod":
        for index, (x, y) in enumerate(((-.16, -.10), (.16, -.10), (0, .16))):
            box("TripodLeg_%d" % index, (x, y, .72), (.055, .055, 1.38),
                mat, 1, count, objects, bevel=.001,
                rotation=(math.radians(7 if y < 0 else -7),
                          math.radians(-7 if x < 0 else 7), 0))
        box("TripodBrace", (0, 0, 1.23), (.28, .28, .08), mat, 2,
            count, objects, bevel=.002)
    else:
        box("LampBase", (0.0, 0.0, 0.055), (0.36, 0.36, 0.11), mat, 0,
            count, objects, bevel=0.004)
        box("LampPole", (0.0, 0.0, 0.77), (0.06, 0.06, 1.36), mat, 2,
            count, objects, bevel=0.001)
        if style == "modern":
            box("ArcArm", (.14, 0, 1.36), (.34, .06, .06), mat, 2,
                count, objects, bevel=.002, rotation=(0, math.radians(-18), 0))
    shade_x = .16 if style == "modern" else 0.0
    box("ShadeBottom", (shade_x, 0.0, 1.48), (0.44, 0.44, 0.18), mat, 3,
        count, objects, bevel=0.004)
    box("ShadeMiddle", (shade_x, 0.0, 1.61), (0.34, 0.34, 0.12), mat, 4,
        count, objects, bevel=0.003)
    box("ShadeTop", (shade_x, 0.0, 1.70), (0.22, 0.22, 0.08), mat, 5,
        count, objects, bevel=0.002)
    box("LampGlow", (shade_x, -0.225, 1.54), (0.20, 0.010, 0.17), mat, 5,
        count, objects, bevel=0.0)
    return objects, (1.25, -2.05, 2.00), (0.0, 0.0, 0.85)


def make_trash_bin():
    colors = ["#171A1B", "#3A4142", "#646B6B", "#9A9990", "#7B3839", "#C6A052"]
    image = make_pixel_atlas("trash_bin_pixel_atlas", colors, MAZE_TEXTURES)
    mat = make_material("Trash bin pixel paint", image, roughness=0.84, metallic=0.12)
    count = len(colors)
    objects = []
    cylinder("BinBody", (0.0, 0.0, 0.32), 0.25, 0.60, 8, mat, 3,
             count, objects, bevel=0.0)
    cylinder("BinBottom", (0.0, 0.0, 0.045), 0.26, 0.09, 8, mat, 0,
             count, objects, bevel=0.0)
    cylinder("BinLid", (0.0, 0.0, 0.65), 0.27, 0.08, 8, mat, 1,
             count, objects, bevel=0.0)
    box("BinBandFront", (0.0, -0.242, 0.38), (0.34, 0.012, 0.10), mat, 4,
        count, objects, bevel=0.0)
    box("FootPedal", (0.0, -0.275, 0.08), (0.18, 0.08, 0.08), mat, 5,
        count, objects, bevel=0.001)
    return objects, (1.20, -1.90, 1.30), (0.0, 0.0, 0.34)


def make_privacy_curtain():
    colors = ["#171016", "#4B1828", "#77243B", "#A33B55", "#C8677C", "#9B7B45", "#D1AF64"]
    image = make_pixel_atlas("privacy_curtain_pixel_atlas", colors, MAZE_TEXTURES)
    mat = make_material("Privacy curtain pixel paint", image, roughness=0.90, metallic=0.0)
    count = len(colors)
    objects = []
    for side, x in (("L", -0.37), ("R", 0.37)):
        box("CurtainPost_%s" % side, (x, 0.0, 1.20), (0.06, 0.06, 2.40), mat, 5,
            count, objects, bevel=0.001)
        box("CurtainFoot_%s" % side, (x, 0.0, 0.04), (0.20, 0.30, 0.08), mat, 0,
            count, objects, bevel=0.002)
    box("CurtainRail", (0.0, 0.0, 2.36), (0.80, 0.07, 0.07), mat, 6,
        count, objects, bevel=0.001)
    # Layered rigid pixel folds keep it readable as cloth without smooth simulation.
    for index, x in enumerate((-0.285, -0.17, -0.055, 0.06, 0.175, 0.29)):
        box("CurtainFold_%d" % (index + 1), (x, -0.005 if index % 2 else -0.025, 1.24),
            (0.14, 0.055, 2.12), mat, 2 + index % 3,
            count, objects, bevel=0.001)
    box("CurtainTie", (0.24, -0.055, 1.10), (0.14, 0.045, 0.11), mat, 6,
        count, objects, bevel=0.001)
    return objects, (1.85, -2.75, 2.55), (0.0, 0.0, 1.20)


def make_lounge_couch():
    colors = ["#171014", "#4B2025", "#732D33", "#A04045", "#C45B5F", "#372126", "#B58A49"]
    image = make_pixel_atlas("lounge_couch_red_pixel_atlas", colors, MAZE_TEXTURES)
    mat = make_material("Lounge couch red pixel paint", image, roughness=0.90, metallic=0.0)
    count = len(colors)
    objects = []
    box("CouchBase", (0.0, 0.0, 0.24), (0.92, 0.60, 0.42), mat, 1,
        count, objects, bevel=0.006)
    box("CouchBack", (0.0, 0.23, 0.62), (0.92, 0.18, 0.58), mat, 2,
        count, objects, bevel=0.006)
    for side, x in (("L", -0.43), ("R", 0.43)):
        box("CouchArm_%s" % side, (x, -0.01, 0.46),
            (0.16, 0.56, 0.46), mat, 3, count, objects, bevel=0.005)
    for index, x in enumerate((-0.22, 0.22)):
        box("SeatCushion_%d" % (index + 1), (x, -0.08, 0.49),
            (0.40, 0.42, 0.16), mat, 4 if index == 0 else 3,
            count, objects, bevel=0.004)
        box("BackCushion_%d" % (index + 1), (x, 0.12, 0.70),
            (0.40, 0.12, 0.34), mat, 3 if index == 0 else 4,
            count, objects, bevel=0.004)
    for x in (-0.34, 0.34):
        box("CouchFoot_%s" % ("L" if x < 0 else "R"),
            (x, -0.13, 0.045), (0.10, 0.10, 0.09), mat, 6,
            count, objects, bevel=0.001)
    return objects, (1.95, -2.75, 1.60), (0.0, 0.0, 0.45)


def mansion_material(model_name, colors, roughness=0.84, metallic=0.0):
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors, MANSION_TEXTURES)
    return make_material(model_name.replace("_", " ").title() + " pixel paint",
                         image, roughness=roughness, metallic=metallic)


def make_grand_dining_table():
    colors = ["#151012", "#35201A", "#5B3424", "#845239", "#6A202A",
              "#A23D48", "#D6C7A2", "#B88A46"]
    mat = mansion_material("grand_dining_table", colors)
    count = len(colors)
    objects = []
    box("DiningTop", (0.0, 0.0, 0.76), (2.20, 0.84, 0.15), mat, 2,
        count, objects, bevel=0.008)
    box("BurgundyRunner", (0.0, -0.005, 0.845), (1.72, 0.34, 0.035), mat, 5,
        count, objects, bevel=0.002)
    box("LongApronFront", (0.0, -0.355, 0.65), (1.92, 0.09, 0.20), mat, 1,
        count, objects, bevel=0.003)
    box("LongApronBack", (0.0, 0.355, 0.65), (1.92, 0.09, 0.20), mat, 1,
        count, objects, bevel=0.003)
    for x in (-0.94, 0.94):
        for y in (-0.31, 0.31):
            box("Leg_%s_%s" % ("L" if x < 0 else "R", "F" if y < 0 else "B"),
                (x, y, 0.34), (0.16, 0.16, 0.68), mat, 1,
                count, objects, bevel=0.004)
    for index, x in enumerate((-0.68, 0.68)):
        cylinder("Plate_%d" % (index + 1), (x, -0.13, 0.885), 0.14, 0.025, 8,
                 mat, 6, count, objects)
        cylinder("Goblet_%d" % (index + 1), (x, 0.17, 0.94), 0.045, 0.17, 8,
                 mat, 7, count, objects)
        box("GobletHighlight_%d" % (index + 1), (x - 0.018, 0.135, 0.97),
            (0.018, 0.018, 0.06), mat, 6, count, objects, bevel=0.0)
    return objects, (2.85, -3.65, 2.35), (0.0, 0.0, 0.48)


def make_dining_chair(model_name, cushioned=False, colors=None):
    colors = colors or ["#160F11", "#32201B", "#5C3728", "#7D4A33", "#651F2B",
                        "#A53C4D", "#CB7A76", "#B8904C"]
    mat = mansion_material(model_name, colors)
    count = len(colors)
    objects = []
    for x in (-0.19, 0.19):
        for y in (-0.18, 0.18):
            box("ChairLeg_%s_%s" % ("L" if x < 0 else "R", "F" if y < 0 else "B"),
                (x, y, 0.225), (0.065, 0.065, 0.45), mat, 1,
                count, objects, bevel=0.002)
    box("ChairSeat", (0.0, 0.0, 0.48), (0.50, 0.48, 0.13), mat, 2,
        count, objects, bevel=0.005)
    box("SeatCushion", (0.0, -0.015, 0.57), (0.43, 0.40, 0.12), mat,
        5 if cushioned else 4, count, objects, bevel=0.007)
    for x in (-0.21, 0.21):
        box("BackPost_%s" % ("L" if x < 0 else "R"), (x, 0.205, 0.84),
            (0.07, 0.07, 0.72), mat, 1, count, objects, bevel=0.002)
    if cushioned:
        box("SquareBack", (0.0, 0.20, 0.88), (0.37, 0.085, 0.43), mat, 5,
            count, objects, bevel=0.008)
        box("BackBand", (0.0, 0.15, 0.88), (0.31, 0.02, 0.055), mat, 6,
            count, objects, bevel=0.001)
    else:
        cylinder("ArchedBack", (0.0, 0.20, 0.89), 0.22, 0.085, 8, mat, 5,
                 count, objects, rotation=(math.radians(90), 0.0, 0.0))
        box("ArchedBackLower", (0.0, 0.20, 0.78), (0.40, 0.085, 0.24), mat, 5,
            count, objects, bevel=0.006)
    return objects, (1.55, -2.15, 1.55), (0.0, 0.0, 0.56)


def make_dining_chandelier(model_name="dining_chandelier", colors=None,
                           style="classic"):
    colors = colors or ["#120F0C", "#33291B", "#68502A", "#A87B32", "#D4A94F",
                        "#E8D49B", "#9A3A36"]
    mat = mansion_material(model_name, colors, roughness=0.58, metallic=0.28)
    count = len(colors)
    objects = []
    # Highest point .90 m, lowest .20 m. At the 3 m finite-route ceiling the
    # fixture leaves 2.30 m clear for every 2.20 m A-Z hunter silhouette.
    cylinder("CeilingMount", (0.0, 0.0, 0.86), 0.16, 0.08, 8, mat, 2,
             count, objects)
    for index, z in enumerate((0.76, 0.68, 0.60)):
        box("ChainLink_%d" % (index + 1), (0.0, 0.0, z),
            (0.07 if index % 2 else 0.12, 0.12 if index % 2 else 0.07, 0.07),
            mat, 3, count, objects, bevel=0.001)
    cylinder("ChandelierHub", (0.0, 0.0, 0.48), 0.20, 0.18, 8, mat, 2,
             count, objects)
    cylinder("LowerFinial", (0.0, 0.0, 0.29), 0.10, 0.18, 8, mat, 3,
             count, objects)
    arm_points = ((-.38, 0), (.38, 0), (0, -.38), (0, .38))
    if style == "crystal":
        arm_points = ((-.32, -.32), (.32, -.32), (-.32, .32), (.32, .32))
    for index, (x, y) in enumerate(arm_points):
        box("Arm_%d" % (index + 1), (x * 0.5, y * 0.5, 0.47),
            (abs(x) + 0.08 if x else 0.07, abs(y) + 0.08 if y else 0.07, 0.07),
            mat, 3, count, objects, bevel=0.002)
        cylinder("CandleCup_%d" % (index + 1), (x, y, 0.50), 0.09, 0.07, 8,
                 mat, 4, count, objects)
        box("Candle_%d" % (index + 1), (x, y, 0.62), (0.09, 0.09, 0.20),
            mat, 5, count, objects, bevel=0.002)
        box("Flame_%d" % (index + 1), (x, y, 0.765), (0.055, 0.055, 0.09),
            mat, 6, count, objects, bevel=0.001, rotation=(0.0, math.radians(45), 0.0))
        if style == "crystal":
            box("Crystal_%d" % (index + 1), (x * .72, y * .72, .27),
                (.08, .08, .20), mat, 5, count, objects, bevel=.001,
                rotation=(0, 0, math.radians(45)))
    if style == "gothic":
        for x in (-.16, .16):
            box("GothicSpike_%s" % ("L" if x < 0 else "R"),
                (x, 0, .30), (.10, .10, .20), mat, 6, count, objects,
                bevel=.001, rotation=(0, 0, math.radians(45)))
    return objects, (2.05, -2.75, 2.10), (0.0, 0.0, 0.95)


def make_mansion_bookshelf():
    colors = ["#130E0C", "#302018", "#533624", "#795239", "#A0744B",
              "#6F2430", "#29464A", "#8A7331", "#C2AE7F"]
    mat = mansion_material("mansion_bookshelf", colors)
    count = len(colors)
    objects = []
    box("BookcaseBack", (0.0, 0.18, 0.96), (0.70, 0.10, 1.82), mat, 1,
        count, objects, bevel=0.003)
    for x in (-0.37, 0.37):
        box("BookcasePost_%s" % ("L" if x < 0 else "R"), (x, 0.0, 0.96),
            (0.09, 0.62, 1.92), mat, 2, count, objects, bevel=0.004)
    box("BookcaseTop", (0.0, 0.0, 1.89), (0.82, 0.64, 0.12), mat, 4,
        count, objects, bevel=0.005)
    box("BookcaseBase", (0.0, 0.0, 0.07), (0.82, 0.64, 0.14), mat, 2,
        count, objects, bevel=0.004)
    for shelf_index, shelf_z in enumerate((0.46, 0.87, 1.28, 1.69)):
        box("Shelf_%d" % (shelf_index + 1), (0.0, -0.03, shelf_z),
            (0.70, 0.56, 0.075), mat, 3, count, objects, bevel=0.002)
        for book_index, x in enumerate((-0.25, -0.13, -0.01, 0.11, 0.23)):
            height = 0.25 + 0.035 * ((book_index + shelf_index) % 3)
            box("Book_%d_%d" % (shelf_index + 1, book_index + 1),
                (x, -0.275, shelf_z + 0.04 + height * 0.5),
                (0.085, 0.09, height), mat, 5 + (book_index + shelf_index) % 4,
                count, objects, bevel=0.001)
    return objects, (1.85, -2.65, 2.25), (0.0, 0.0, 0.93)


def make_magazine_rack():
    colors = ["#111112", "#2A2421", "#4E3A2A", "#76563A", "#6B2330",
              "#A4414C", "#C3A86D", "#DED1AA"]
    mat = mansion_material("magazine_rack", colors, roughness=0.80, metallic=0.08)
    count = len(colors)
    objects = []
    box("RackBase", (0.0, 0.0, 0.06), (0.60, 0.50, 0.12), mat, 1,
        count, objects, bevel=0.003)
    box("RackBack", (0.0, 0.20, 0.55), (0.50, 0.07, 0.96), mat, 2,
        count, objects, bevel=0.003)
    for x in (-0.27, 0.27):
        box("RackPost_%s" % ("L" if x < 0 else "R"), (x, 0.0, 0.55),
            (0.07, 0.50, 1.02), mat, 1, count, objects, bevel=0.002)
    for index, z in enumerate((0.28, 0.52, 0.76)):
        box("RackRail_%d" % (index + 1), (0.0, -0.23, z),
            (0.55, 0.06, 0.07), mat, 3, count, objects, bevel=0.002)
        box("Magazine_%d" % (index + 1), (0.0, -0.17, z + 0.12),
            (0.40, 0.035, 0.30), mat, 4 + index, count, objects,
            bevel=0.002, rotation=(math.radians(-6 + index * 4), 0.0, 0.0))
        box("MagazineLabel_%d" % (index + 1), (-0.06, -0.195, z + 0.14),
            (0.20, 0.012, 0.055), mat, 7, count, objects, bevel=0.0)
    return objects, (1.55, -2.25, 1.55), (0.0, 0.0, 0.51)


def make_mansion_fireplace():
    colors = ["#100E0D", "#282320", "#4A4139", "#74685B", "#A49A80",
              "#C6B891", "#752B21", "#E06A28", "#F0B34A"]
    mat = mansion_material("mansion_fireplace", colors, roughness=0.90)
    count = len(colors)
    objects = []
    box("Hearth", (0.0, -0.04, 0.09), (0.92, 0.64, 0.18), mat, 3,
        count, objects, bevel=0.004)
    box("FireplaceBody", (0.0, 0.08, 0.72), (0.84, 0.50, 1.28), mat, 4,
        count, objects, bevel=0.006)
    box("FireOpening", (0.0, -0.19, 0.55), (0.48, 0.035, 0.68), mat, 0,
        count, objects, bevel=0.004)
    box("FireboxBack", (0.0, -0.215, 0.54), (0.38, 0.025, 0.55), mat, 1,
        count, objects, bevel=0.002)
    for x in (-0.34, 0.34):
        box("StoneColumn_%s" % ("L" if x < 0 else "R"), (x, -0.19, 0.68),
            (0.20, 0.18, 1.08), mat, 3, count, objects, bevel=0.003)
    box("Mantel", (0.0, 0.0, 1.40), (1.02, 0.62, 0.18), mat, 5,
        count, objects, bevel=0.006)
    box("MantelTrim", (0.0, -0.32, 1.30), (0.90, 0.07, 0.12), mat, 3,
        count, objects, bevel=0.002)
    for index, (x, z, region) in enumerate(((-0.12, 0.36, 6), (0.03, 0.39, 7),
                                            (0.14, 0.35, 8))):
        box("FireBlock_%d" % (index + 1), (x, -0.245, z),
            (0.15, 0.04, 0.30 + index * 0.04), mat, region, count, objects,
            bevel=0.002, rotation=(0.0, math.radians(-12 + index * 12), 0.0))
    for x in (-0.22, 0.0, 0.22):
        box("Grate_%s" % str(x), (x, -0.27, 0.49), (0.035, 0.035, 0.48),
            mat, 2, count, objects, bevel=0.001)
    box("GrateRail", (0.0, -0.285, 0.31), (0.52, 0.035, 0.05), mat, 2,
        count, objects, bevel=0.001)
    return objects, (2.15, -2.85, 2.10), (0.0, 0.0, 0.72)


def make_bathroom_stall():
    colors = ["#131719", "#343A3B", "#656B68", "#AAA697", "#D2C9B2",
              "#87404A", "#4A737B", "#B8874C"]
    mat = mansion_material("bathroom_stall", colors, roughness=0.86, metallic=0.10)
    count = len(colors)
    objects = []
    for x in (-0.32, 0.32):
        box("StallPost_%s" % ("L" if x < 0 else "R"), (x, 0.0, 0.96),
            (0.075, 0.56, 1.92), mat, 1, count, objects, bevel=0.002)
        box("StallFoot_%s" % ("L" if x < 0 else "R"), (x, 0.0, 0.06),
            (0.12, 0.62, 0.12), mat, 0, count, objects, bevel=0.002)
    box("StallBack", (0.0, 0.255, 1.02), (0.57, 0.05, 1.68), mat, 3,
        count, objects, bevel=0.002)
    box("StallDoor", (0.0, -0.275, 1.06), (0.55, 0.045, 1.58), mat, 4,
        count, objects, bevel=0.002)
    box("DoorRedBand", (0.0, -0.302, 1.12), (0.55, 0.012, 0.16), mat, 5,
        count, objects, bevel=0.0)
    box("DoorBlueBand", (0.0, -0.304, 0.93), (0.55, 0.012, 0.22), mat, 6,
        count, objects, bevel=0.0)
    box("DoorHandle", (0.20, -0.315, 1.04), (0.06, 0.025, 0.11), mat, 7,
        count, objects, bevel=0.001)
    box("TopRail", (0.0, 0.0, 1.90), (0.68, 0.62, 0.08), mat, 2,
        count, objects, bevel=0.002)
    return objects, (1.65, -2.45, 2.15), (0.0, 0.0, 0.95)


def make_bathroom_sink():
    colors = ["#121719", "#394447", "#778183", "#B6B5A8", "#DBD3BD",
              "#8E3741", "#4A7777", "#C09A49"]
    mat = mansion_material("bathroom_sink", colors, roughness=0.72, metallic=0.12)
    count = len(colors)
    objects = []
    box("SinkBacksplash", (0.0, 0.17, 1.05), (0.80, 0.10, 0.38), mat, 4,
        count, objects, bevel=0.005)
    box("SinkDeck", (0.0, 0.0, 0.88), (0.80, 0.44, 0.14), mat, 4,
        count, objects, bevel=0.008)
    box("BasinInset", (0.0, -0.07, 0.96), (0.52, 0.26, 0.035), mat, 2,
        count, objects, bevel=0.004)
    cylinder("Drain", (0.0, -0.07, 0.985), 0.055, 0.018, 8, mat, 0,
             count, objects)
    for index, x in enumerate((-0.17, 0.17)):
        cylinder("TapBase_%d" % (index + 1), (x, 0.11, 1.12), 0.055, 0.10, 8,
                 mat, 7, count, objects)
        box("TapCross_%d" % (index + 1), (x, 0.11, 1.20),
            (0.16, 0.045, 0.045), mat, 7, count, objects, bevel=0.001)
    box("FaucetStem", (0.0, 0.11, 1.17), (0.07, 0.07, 0.22), mat, 7,
        count, objects, bevel=0.002)
    box("FaucetSpout", (0.0, -0.01, 1.26), (0.07, 0.27, 0.07), mat, 7,
        count, objects, bevel=0.002)
    cylinder("DrainPipe", (0.0, 0.02, 0.44), 0.07, 0.76, 8, mat, 1,
             count, objects)
    box("WallTrap", (0.0, 0.14, 0.22), (0.28, 0.12, 0.16), mat, 1,
        count, objects, bevel=0.003)
    return objects, (1.75, -2.55, 1.75), (0.0, 0.0, 0.72)


def make_bathroom_mirror():
    colors = ["#111518", "#30393D", "#55656A", "#7D999B", "#A8C3C1",
              "#742B33", "#B07D42"]
    mat = mansion_material("bathroom_mirror", colors, roughness=0.42, metallic=0.18)
    count = len(colors)
    objects = []
    box("MirrorBack", (0.0, 0.0, 1.20), (0.70, 0.14, 1.20), mat, 0,
        count, objects, bevel=0.006)
    box("MirrorGlass", (0.0, -0.081, 1.20), (0.56, 0.025, 1.02), mat, 4,
        count, objects, bevel=0.004)
    for side, x in (("L", -0.32), ("R", 0.32)):
        box("MirrorFrame%s" % side, (x, -0.08, 1.20), (0.08, 0.07, 1.20),
            mat, 1, count, objects, bevel=0.002)
    for side, z in (("Top", 1.76), ("Bottom", 0.64)):
        box("MirrorFrame%s" % side, (0.0, -0.08, z), (0.70, 0.07, 0.08),
            mat, 6 if side == "Top" else 1, count, objects, bevel=0.002)
    for index, (x, z, length, angle) in enumerate((
            (0.12, 1.54, 0.30, 38), (0.22, 1.41, 0.26, -42),
            (-0.18, 0.92, 0.24, 52))):
        box("MirrorCrack_%d" % (index + 1), (x, -0.099, z),
            (length, 0.009, 0.018), mat, 2, count, objects,
            bevel=0.0, rotation=(0.0, math.radians(angle), 0.0))
    return objects, (1.55, -2.15, 1.95), (0.0, 0.0, 1.18)


def make_bathroom_vanity():
    colors = ["#120F0E", "#302018", "#543523", "#7B5235", "#B5A98C",
              "#D9CEB6", "#4F7B7C", "#B88842"]
    mat = mansion_material("bathroom_vanity", colors, roughness=0.80, metallic=0.05)
    count = len(colors)
    objects = []
    box("VanityBody", (0.0, 0.02, 0.42), (0.76, 0.44, 0.78), mat, 2,
        count, objects, bevel=0.005)
    box("VanityPlinth", (0.0, 0.02, 0.07), (0.80, 0.48, 0.14), mat, 0,
        count, objects, bevel=0.003)
    box("VanityTop", (0.0, 0.0, 0.86), (0.82, 0.50, 0.13), mat, 5,
        count, objects, bevel=0.007)
    box("VanityBasin", (0.0, -0.07, 0.935), (0.42, 0.24, 0.035), mat, 4,
        count, objects, bevel=0.004)
    for index, x in enumerate((-0.19, 0.19)):
        box("VanityDoor_%d" % (index + 1), (x, -0.215, 0.44),
            (0.32, 0.025, 0.57), mat, 1, count, objects, bevel=0.002)
        box("VanityHandle_%d" % (index + 1), (x * 0.38, -0.235, 0.48),
            (0.045, 0.018, 0.09), mat, 7, count, objects, bevel=0.001)
    box("VanityMirrorFrame", (0.0, 0.16, 1.36), (0.50, 0.10, 0.67), mat, 3,
        count, objects, bevel=0.006)
    box("VanityMirrorGlass", (0.0, 0.10, 1.36), (0.40, 0.025, 0.55), mat, 6,
        count, objects, bevel=0.004)
    box("VanityFaucet", (0.0, 0.07, 1.00), (0.07, 0.08, 0.20), mat, 7,
        count, objects, bevel=0.002)
    return objects, (1.75, -2.45, 1.95), (0.0, 0.0, 0.82)


PUBLIC_BATHROOM_PALETTE = [
    "#111416", "#343B3D", "#687173", "#AAA99D", "#D8D2BF",
    "#4B7779", "#8A3D49", "#B88A48", "#8CB2B1", "#E5D46E",
]
HOUSE_BATHROOM_PALETTE = [
    "#141311", "#483326", "#76583E", "#B5A88C", "#E0D8C4",
    "#659091", "#315B63", "#B88A48", "#A7C9C7", "#E8D77A",
]


def bathroom_expansion_material(model_name, house=False, metallic=0.06):
    colors = HOUSE_BATHROOM_PALETTE if house else PUBLIC_BATHROOM_PALETTE
    return mansion_material(model_name, colors, roughness=0.78,
                            metallic=metallic), len(colors)


def make_restroom_toilet(model_name, house=False):
    mat, count = bathroom_expansion_material(model_name, house)
    objects = []
    body_region = 4
    box("ToiletPedestal", (0.0, 0.02, 0.27), (0.34, 0.42, 0.54), mat,
        body_region, count, objects, bevel=0.008)
    box("ToiletBowl", (0.0, -0.08, 0.48), (0.48, 0.58, 0.27), mat,
        body_region, count, objects, bevel=0.012)
    box("ToiletSeat", (0.0, -0.09, 0.63), (0.48, 0.58, 0.08), mat,
        3, count, objects, bevel=0.010)
    box("ToiletOpening", (0.0, -0.12, 0.68), (0.30, 0.37, 0.025), mat,
        6 if house else 1, count, objects, bevel=0.009)
    box("ToiletTank", (0.0, 0.19, 0.83), (0.45, 0.24, 0.62), mat,
        body_region, count, objects, bevel=0.008)
    box("ToiletTankLid", (0.0, 0.19, 1.17), (0.49, 0.27, 0.08), mat,
        3, count, objects, bevel=0.005)
    box("FlushLever", (0.17, 0.045, 0.99), (0.10, 0.04, 0.05), mat,
        7, count, objects, bevel=0.002)
    return objects, (1.55, -2.15, 1.45), (0.0, 0.0, 0.55)


def make_public_mens_urinal():
    mat, count = bathroom_expansion_material("public_mens_urinal")
    objects = []
    box("UrinalBack", (0.0, 0.12, 0.75), (0.48, 0.15, 0.82), mat, 4,
        count, objects, bevel=0.010)
    box("UrinalBasin", (0.0, -0.04, 0.52), (0.46, 0.40, 0.42), mat, 4,
        count, objects, bevel=0.014)
    box("UrinalOpening", (0.0, -0.23, 0.59), (0.29, 0.05, 0.22), mat, 1,
        count, objects, bevel=0.006)
    cylinder("UrinalDrain", (0.0, -0.24, 0.49), 0.045, 0.025, 8, mat, 2,
             count, objects, rotation=(math.radians(90), 0.0, 0.0))
    box("FlushPipe", (0.0, 0.11, 1.16), (0.07, 0.07, 0.46), mat, 7,
        count, objects, bevel=0.002)
    box("FlushValve", (0.0, 0.10, 1.39), (0.15, 0.12, 0.12), mat, 7,
        count, objects, bevel=0.004)
    box("FlushButton", (0.0, 0.03, 1.40), (0.07, 0.025, 0.07), mat, 9,
        count, objects, bevel=0.002)
    return objects, (1.40, -1.95, 1.65), (0.0, 0.0, 0.72)


def make_public_sink_bank():
    mat, count = bathroom_expansion_material("public_sink_bank", metallic=0.10)
    objects = []
    box("SinkBankBacksplash", (0.0, 0.19, 1.04), (1.62, 0.10, 0.38), mat,
        3, count, objects, bevel=0.005)
    box("SinkBankDeck", (0.0, 0.0, 0.88), (1.66, 0.48, 0.14), mat, 4,
        count, objects, bevel=0.007)
    for index, x in enumerate((-0.52, 0.0, 0.52)):
        box("PublicBasin_%d" % (index + 1), (x, -0.08, 0.96),
            (0.40, 0.27, 0.035), mat, 2, count, objects, bevel=0.005)
        box("PublicFaucetPost_%d" % (index + 1), (x, 0.12, 1.15),
            (0.065, 0.065, 0.28), mat, 7, count, objects, bevel=0.002)
        box("PublicFaucetSpout_%d" % (index + 1), (x, 0.02, 1.26),
            (0.065, 0.22, 0.065), mat, 7, count, objects, bevel=0.002)
    for x in (-0.69, 0.69):
        box("SinkBankLeg%s" % str(x), (x, 0.08, 0.43),
            (0.10, 0.12, 0.86), mat, 1, count, objects, bevel=0.002)
    box("SinkBankPipeRail", (0.0, 0.14, 0.39), (1.38, 0.08, 0.09), mat, 1,
        count, objects, bevel=0.002)
    return objects, (2.45, -3.25, 1.75), (0.0, 0.0, 0.67)


def make_public_wall_utility(model_name, kind):
    mat, count = bathroom_expansion_material(model_name, metallic=0.09)
    objects = []
    if kind == "dryer":
        box("HandDryerBody", (0.0, 0.0, 1.36), (0.40, 0.24, 0.42), mat, 3,
            count, objects, bevel=0.010)
        box("DryerSensor", (0.0, -0.133, 1.45), (0.12, 0.025, 0.08), mat, 6,
            count, objects, bevel=0.002)
        for index, x in enumerate((-0.12, 0.0, 0.12)):
            box("DryerVent_%d" % index, (x, -0.134, 1.24),
                (0.065, 0.025, 0.06), mat, 1, count, objects, bevel=0.001)
        eye, look = (1.35, -1.85, 1.75), (0.0, 0.0, 1.36)
    elif kind == "soap":
        box("SoapDispenser", (0.0, 0.0, 1.22), (0.22, 0.17, 0.36), mat, 5,
            count, objects, bevel=0.007)
        box("SoapWindow", (0.0, -0.096, 1.27), (0.09, 0.025, 0.13), mat, 8,
            count, objects, bevel=0.002)
        box("SoapNozzle", (0.0, -0.13, 1.02), (0.11, 0.12, 0.07), mat, 7,
            count, objects, bevel=0.002)
        eye, look = (1.05, -1.45, 1.55), (0.0, 0.0, 1.20)
    elif kind == "paper":
        box("PaperTowelCabinet", (0.0, 0.0, 1.43), (0.40, 0.20, 0.50), mat,
            3, count, objects, bevel=0.008)
        box("PaperTowelWindow", (0.0, -0.112, 1.51), (0.20, 0.025, 0.13), mat,
            6, count, objects, bevel=0.002)
        box("PaperSheet", (0.0, -0.08, 1.10), (0.28, 0.035, 0.24), mat, 4,
            count, objects, bevel=0.002)
        eye, look = (1.30, -1.75, 1.80), (0.0, 0.0, 1.36)
    elif kind == "change":
        box("ChangingStationBack", (0.0, 0.02, 1.31), (0.92, 0.17, 0.58), mat,
            3, count, objects, bevel=0.009)
        box("ChangingTable", (0.0, -0.23, 1.04), (0.84, 0.54, 0.13), mat, 4,
            count, objects, bevel=0.009, rotation=(math.radians(-4), 0.0, 0.0))
        box("ChangingLip", (0.0, -0.50, 1.11), (0.84, 0.07, 0.18), mat, 5,
            count, objects, bevel=0.004)
        box("SafetyStrap", (0.0, -0.38, 1.11), (0.11, 0.28, 0.04), mat, 6,
            count, objects, bevel=0.002)
        eye, look = (1.75, -2.40, 1.80), (0.0, -0.10, 1.18)
    return objects, eye, look


def make_public_sanitary_bin():
    mat, count = bathroom_expansion_material("public_sanitary_bin")
    objects = []
    box("SanitaryBinBody", (0.0, 0.0, 0.31), (0.32, 0.30, 0.62), mat, 3,
        count, objects, bevel=0.008)
    box("SanitaryBinLid", (0.0, 0.0, 0.65), (0.35, 0.33, 0.09), mat, 4,
        count, objects, bevel=0.006)
    box("SanitaryBinPedal", (0.0, -0.18, 0.08), (0.17, 0.10, 0.07), mat, 7,
        count, objects, bevel=0.002)
    box("SanitaryMark", (0.0, -0.158, 0.40), (0.10, 0.025, 0.14), mat, 6,
        count, objects, bevel=0.002)
    return objects, (1.20, -1.65, 1.10), (0.0, 0.0, 0.32)


def make_restroom_sign(model_name, womens=False):
    mat, count = bathroom_expansion_material(model_name)
    objects = []
    accent = 6 if womens else 5
    box("RestroomSignBack", (0.0, 0.0, 1.63), (0.52, 0.10, 0.62), mat, 1,
        count, objects, bevel=0.007)
    box("SignHead", (0.0, -0.065, 1.78), (0.13, 0.04, 0.13), mat, accent,
        count, objects, bevel=0.005)
    if womens:
        box("SignTorso", (0.0, -0.065, 1.63), (0.13, 0.04, 0.17), mat,
            accent, count, objects, bevel=0.003)
        triangular_prism("SignTriangularSkirt", (0.0, -0.065, 1.44),
                         0.30, 0.25, 0.04, mat, accent, count, objects)
        leg_x = 0.075
        leg_z = 1.25
        leg_height = 0.18
    else:
        box("SignTorso", (0.0, -0.065, 1.57), (0.14, 0.04, 0.29), mat,
            accent, count, objects, bevel=0.003)
        leg_x = 0.065
        leg_z = 1.32
        leg_height = 0.24
    # Keep the arms as separate limbs rather than allowing the torso or skirt
    # silhouette to swallow them at the small in-game sign scale.
    for x in (-0.13, 0.13):
        angle = math.radians(12 if x < 0.0 else -12)
        box("SignArm%s" % str(x), (x, -0.066, 1.53),
            (0.055, 0.04, 0.27), mat, accent, count, objects, bevel=0.002,
            rotation=(0.0, angle, 0.0))
    for x in (-leg_x, leg_x):
        box("SignLeg%s" % str(x), (x, -0.065, leg_z),
            (0.06, 0.04, leg_height), mat, accent, count, objects,
            bevel=0.002)
    return objects, (1.30, -1.80, 2.00), (0.0, 0.0, 1.60)


def make_public_shower_stall(model_name, womens=False):
    mat, count = bathroom_expansion_material(model_name, metallic=0.08)
    objects = []
    accent = 6 if womens else 5
    box("ShowerPan", (0.0, 0.0, 0.07), (0.82, 0.82, 0.14), mat, 3,
        count, objects, bevel=0.006)
    box("ShowerDrain", (0.0, 0.0, 0.15), (0.18, 0.18, 0.025), mat, 1,
        count, objects, bevel=0.002)
    box("ShowerBack", (0.0, 0.37, 1.10), (0.82, 0.07, 2.06), mat, 2,
        count, objects, bevel=0.004)
    for x in (-0.39, 0.39):
        box("ShowerPost%s" % str(x), (x, 0.0, 1.10), (0.07, 0.82, 2.12),
            mat, 1, count, objects, bevel=0.002)
    box("ShowerGlassDoor", (0.0, -0.39, 1.12), (0.70, 0.04, 1.94), mat, 8,
        count, objects, bevel=0.004)
    box("ShowerDoorBand", (0.0, -0.418, 1.20), (0.70, 0.018, 0.14), mat,
        accent, count, objects, bevel=0.001)
    box("ShowerDoorHandle", (0.24, -0.445, 1.18), (0.07, 0.06, 0.32), mat,
        7, count, objects, bevel=0.002)
    box("ShowerRiser", (0.0, 0.31, 1.35), (0.06, 0.06, 1.20), mat, 7,
        count, objects, bevel=0.002)
    box("ShowerHeadArm", (0.0, 0.19, 1.91), (0.06, 0.28, 0.06), mat, 7,
        count, objects, bevel=0.002)
    box("ShowerHead", (0.0, 0.04, 1.87), (0.20, 0.10, 0.12), mat, 7,
        count, objects, bevel=0.004)
    box("ShowerControl", (0.0, 0.31, 1.02), (0.18, 0.08, 0.18), mat, 9,
        count, objects, bevel=0.004)
    return objects, (2.15, -2.95, 2.35), (0.0, 0.0, 1.08)


def make_public_shower_bench():
    mat, count = bathroom_expansion_material("public_shower_bench")
    objects = []
    for index, y in enumerate((-0.15, 0.0, 0.15)):
        box("ShowerBenchSlat_%d" % index, (0.0, y, 0.52),
            (1.22, 0.12, 0.12), mat, 2 + index % 2, count, objects,
            bevel=0.003)
    for x in (-0.48, 0.48):
        box("ShowerBenchLeg%s" % str(x), (x, 0.0, 0.25),
            (0.12, 0.34, 0.50), mat, 1, count, objects, bevel=0.002)
    box("ShowerBenchBrace", (0.0, 0.0, 0.24), (0.94, 0.10, 0.10), mat, 1,
        count, objects, bevel=0.002)
    return objects, (1.90, -2.55, 1.25), (0.0, 0.0, 0.28)


def make_house_bathtub():
    mat, count = bathroom_expansion_material("house_bathtub", True)
    objects = []
    box("BathtubBase", (0.0, 0.0, 0.18), (1.74, 0.78, 0.36), mat, 4,
        count, objects, bevel=0.015)
    for side, y in (("Front", -0.34), ("Back", 0.34)):
        box("BathtubRim%s" % side, (0.0, y, 0.57), (1.78, 0.12, 0.46), mat,
            4, count, objects, bevel=0.012)
    for side, x in (("Left", -0.81), ("Right", 0.81)):
        box("BathtubEnd%s" % side, (x, 0.0, 0.57), (0.16, 0.58, 0.46), mat,
            4, count, objects, bevel=0.012)
    box("BathtubInterior", (0.0, 0.0, 0.47), (1.44, 0.51, 0.05), mat, 8,
        count, objects, bevel=0.014)
    cylinder("TubFaucetBase", (0.58, 0.31, 0.88), 0.07, 0.22, 8, mat, 7,
             count, objects)
    box("TubFaucetSpout", (0.58, 0.17, 0.96), (0.07, 0.31, 0.07), mat, 7,
        count, objects, bevel=0.002)
    for x in (0.42, 0.74):
        cylinder("TubTap%s" % str(x), (x, 0.30, 0.82), 0.055, 0.13, 8, mat,
                 7, count, objects)
    return objects, (2.75, -3.65, 1.65), (0.0, 0.0, 0.42)


def make_house_shower_enclosure():
    mat, count = bathroom_expansion_material("house_shower_enclosure", True,
                                             metallic=0.08)
    objects = []
    box("HouseShowerPan", (0.0, 0.0, 0.07), (0.94, 0.94, 0.14), mat, 3,
        count, objects, bevel=0.008)
    box("HouseShowerBack", (0.0, 0.43, 1.10), (0.94, 0.07, 2.06), mat, 4,
        count, objects, bevel=0.004)
    box("HouseShowerSide", (-0.43, 0.0, 1.10), (0.07, 0.86, 2.06), mat, 8,
        count, objects, bevel=0.004)
    box("HouseShowerDoor", (0.18, -0.43, 1.11), (0.52, 0.04, 1.96), mat, 8,
        count, objects, bevel=0.004)
    for x in (-0.44, 0.44):
        box("HouseShowerPost%s" % str(x), (x, -0.42, 1.10),
            (0.06, 0.08, 2.12), mat, 7, count, objects, bevel=0.002)
    box("HouseShowerHandle", (0.35, -0.46, 1.18), (0.06, 0.06, 0.34), mat,
        7, count, objects, bevel=0.002)
    box("HouseShowerRiser", (0.13, 0.38, 1.34), (0.06, 0.06, 1.20), mat,
        7, count, objects, bevel=0.002)
    box("HouseShowerHead", (0.13, 0.18, 1.91), (0.20, 0.35, 0.09), mat,
        7, count, objects, bevel=0.003)
    box("HouseShowerControl", (0.13, 0.37, 1.02), (0.18, 0.08, 0.18), mat,
        9, count, objects, bevel=0.004)
    return objects, (2.25, -3.10, 2.40), (0.0, 0.0, 1.08)


def make_house_medicine_cabinet():
    mat, count = bathroom_expansion_material("house_medicine_cabinet", True)
    objects = []
    box("MedicineCabinetBody", (0.0, 0.0, 1.48), (0.70, 0.20, 0.80), mat,
        2, count, objects, bevel=0.006)
    box("MedicineMirror", (0.0, -0.112, 1.48), (0.60, 0.025, 0.68), mat,
        8, count, objects, bevel=0.004)
    for z in (1.24, 1.48, 1.72):
        box("MedicineShelf%s" % str(z), (0.0, 0.02, z),
            (0.58, 0.15, 0.04), mat, 3, count, objects, bevel=0.001)
    box("MedicineHandle", (0.27, -0.14, 1.47), (0.045, 0.035, 0.23), mat,
        7, count, objects, bevel=0.002)
    return objects, (1.50, -2.05, 2.00), (0.0, 0.0, 1.48)


def make_house_towel_rack():
    mat, count = bathroom_expansion_material("house_towel_rack", True)
    objects = []
    for x in (-0.37, 0.37):
        box("TowelBracket%s" % str(x), (x, 0.0, 1.34), (0.09, 0.16, 0.12),
            mat, 7, count, objects, bevel=0.003)
    box("TowelRail", (0.0, -0.08, 1.34), (0.78, 0.07, 0.07), mat, 7,
        count, objects, bevel=0.002)
    box("BathTowel", (0.0, -0.10, 1.06), (0.63, 0.06, 0.55), mat, 5,
        count, objects, bevel=0.005)
    for x in (-0.20, 0.0, 0.20):
        box("TowelStripe%s" % str(x), (x, -0.134, 0.90), (0.05, 0.018, 0.19),
            mat, 8, count, objects, bevel=0.001)
    return objects, (1.50, -2.05, 1.75), (0.0, 0.0, 1.18)


def make_house_bath_mat():
    mat, count = bathroom_expansion_material("house_bath_mat", True)
    objects = []
    box("BathMat", (0.0, 0.0, 0.035), (0.92, 0.58, 0.07), mat, 5,
        count, objects, bevel=0.012)
    for index, x in enumerate((-0.32, -0.16, 0.0, 0.16, 0.32)):
        box("BathMatStripe_%d" % index, (x, 0.0, 0.077),
            (0.07, 0.48, 0.018), mat, 8 if index % 2 else 6,
            count, objects, bevel=0.003)
    return objects, (1.45, -1.95, 0.95), (0.0, 0.0, 0.04)


def make_house_bathroom_shelf():
    mat, count = bathroom_expansion_material("house_bathroom_shelf", True)
    objects = []
    for index, z in enumerate((1.03, 1.42, 1.81)):
        box("BathroomShelf_%d" % index, (0.0, 0.0, z),
            (0.86, 0.26, 0.09), mat, 2, count, objects, bevel=0.003)
    for x in (-0.39, 0.39):
        box("BathroomShelfRail%s" % str(x), (x, 0.08, 1.42),
            (0.08, 0.12, 0.86), mat, 1, count, objects, bevel=0.002)
    for index, (x, z, region) in enumerate(((-0.24, 1.15, 5),
                                             (0.02, 1.15, 8),
                                             (0.26, 1.15, 4),
                                             (-0.20, 1.56, 6),
                                             (0.18, 1.56, 9))):
        box("BathroomBottle_%d" % index, (x, -0.02, z),
            (0.15, 0.15, 0.22), mat, region, count, objects, bevel=0.004)
    box("FoldedTowel", (0.0, -0.01, 1.91), (0.58, 0.20, 0.16), mat, 5,
        count, objects, bevel=0.005)
    return objects, (1.70, -2.30, 2.15), (0.0, 0.0, 1.42)


def make_grand_staircase():
    """Visible steps and landing matching FacilityView3D's smooth ramp."""
    colors = ["2a171d", "44252d", "6f3b43", "9a5960", "c28a78", "d8b99a"]
    mat = mansion_material("grand_staircase", colors, roughness=0.84,
                           metallic=0.03)
    count = len(colors)
    objects = []
    steps = 8
    tread_depth = 3.60 / steps
    for index in range(steps):
        top = (index + 1) / steps
        # Blender -Y exports as Godot +Z: rise from +Y toward -Y here.
        y = 1.80 - (index + 0.5) * tread_depth
        box("GrandStairStep_%02d" % index, (0.0, y, top * 0.5),
            (1.60, tread_depth + 0.015, top), mat,
            4 if index % 2 == 0 else 5, count, objects, bevel=0.006)

    box("GrandStairLanding", (0.0, -2.50, 0.95), (1.60, 1.40, 0.10),
        mat, 4, count, objects, bevel=0.008)
    slope_angle = math.atan(1.0 / 3.60)
    slope_length = math.sqrt(3.60 ** 2 + 1.0 ** 2)
    for side in (-0.84, 0.84):
        # Keep the rotated stringer just above the authored floor plane.  At
        # 0.52 its lower corner reached -0.047 m and failed source validation.
        box("GrandStairStringer_%s" % str(side), (side, 0.0, 0.57),
            (0.10, slope_length, 0.14), mat, 1, count, objects,
            bevel=0.004, rotation=(-slope_angle, 0.0, 0.0))
        for index, y in enumerate((1.65, 0.75, -0.15, -1.05, -1.70,
                                   -2.45, -3.12)):
            ramp_t = max(0.0, min(1.0, (1.80 - y) / 3.60))
            rail_base = 0.18 + ramp_t if y >= -1.80 else 1.0
            box("GrandStairPost_%s_%d" % (str(side), index),
                (side, y, rail_base + 0.44), (0.09, 0.09, 0.88), mat,
                2, count, objects, bevel=0.003)
        box("GrandStairHandrail_%s" % str(side),
            (side, 0.0, 1.18), (0.12, slope_length, 0.12), mat,
            3, count, objects, bevel=0.006,
            rotation=(-slope_angle, 0.0, 0.0))
        box("GrandLandingRail_%s" % str(side), (side, -2.50, 1.88),
            (0.12, 1.40, 0.12), mat, 3, count, objects, bevel=0.006)
    return objects, (4.80, 5.80, 3.70), (0.0, -0.55, 0.90)


def make_grand_foyer_staircase():
    """Twin walkable flights, raised gallery, columns and foyer lighting.

    The composition is inspired by monumental hotel/mansion foyers: two
    symmetrical shallow flights converge on a central balcony. Godot supplies
    two smooth diagonal ramps under these discrete visible treads.
    """
    colors = ["21151a", "43262d", "70414a", "a36a66", "d0a27f",
              "ead7b5", "7a6337", "d4b96a"]
    mat = mansion_material("grand_foyer_staircase", colors, roughness=0.78,
                           metallic=0.06)
    count = len(colors)
    objects = []
    steps = 10
    for side in (-1, 1):
        for index in range(steps):
            t = (index + 1) / steps
            top = 1.20 * t
            godot_z = -2.0 + (index + 0.5) * (4.0 / steps)
            x = side * (1.65 - t * 1.0)
            box("Foyer%sStep_%02d" % ("Left" if side < 0 else "Right", index),
                (x, -godot_z, top * 0.5), (1.25, 0.43, top), mat,
                4 if index % 2 == 0 else 5, count, objects, bevel=0.007)
        # Balusters follow both edges of each flight. Chunked rails retain the
        # block-art language while the shifted segments suggest a gentle curve.
        for index in range(6):
            t = index / 5.0
            godot_z = -2.0 + t * 4.0
            branch_x = side * (1.65 - t * 1.0)
            height = 0.12 + t * 1.20
            for edge in (-0.67, 0.67):
                x = branch_x + edge
                box("Foyer%sPost_%d_%s" % (
                    "L" if side < 0 else "R", index, str(edge)),
                    (x, -godot_z, height + 0.39), (0.075, 0.075, 0.78),
                    mat, 6, count, objects, bevel=0.003)
                if index < 5:
                    next_t = (index + 1) / 5.0
                    next_z = -2.0 + next_t * 4.0
                    next_x = side * (1.65 - next_t * 1.0) + edge
                    box("Foyer%sRail_%d_%s" % (
                        "L" if side < 0 else "R", index, str(edge)),
                        ((x + next_x) * 0.5, -(godot_z + next_z) * 0.5,
                         height + 0.80),
                        (abs(next_x - x) + 0.13, abs(next_z - godot_z) + 0.08,
                         0.10), mat, 7, count, objects, bevel=0.005)

    box("FoyerRaisedGallery", (0.0, -2.70, 1.15), (4.50, 1.40, 0.10),
        mat, 5, count, objects, bevel=0.009)
    # Balcony rail across the open centre, with gaps where both stairs arrive.
    for x in (-1.85, -1.45, -1.05, 1.05, 1.45, 1.85):
        box("GalleryBaluster_%s" % str(x), (x, -2.03, 1.61),
            (0.07, 0.07, 0.82), mat, 6, count, objects, bevel=0.003)
    for x in (-1.48, 1.48):
        box("GalleryRail_%s" % str(x), (x, -2.03, 2.02),
            (1.18, 0.10, 0.10), mat, 7, count, objects, bevel=0.005)

    # Tall paired columns and a shallow arch/header make the prop read as an
    # architectural foyer rather than two freestanding staircases.
    for x in (-2.12, 2.12):
        box("FoyerColumnBase_%s" % str(x), (x, -2.85, 0.16),
            (0.48, 0.48, 0.32), mat, 4, count, objects, bevel=0.006)
        box("FoyerColumn_%s" % str(x), (x, -2.85, 1.42),
            (0.30, 0.30, 2.36), mat, 5, count, objects, bevel=0.008)
        box("FoyerColumnCapital_%s" % str(x), (x, -2.85, 2.66),
            (0.56, 0.50, 0.18), mat, 7, count, objects, bevel=0.008)
    box("FoyerArchHeader", (0.0, -2.85, 2.72), (4.55, 0.38, 0.20),
        mat, 5, count, objects, bevel=0.010)

    # Block chandelier beneath the header, safely under the 3 m room ceiling.
    box("FoyerChandelierStem", (0.0, -1.45, 2.46), (0.08, 0.08, 0.50),
        mat, 6, count, objects, bevel=0.002)
    for x, y in ((-0.30, 0.0), (0.30, 0.0), (0.0, -0.30), (0.0, 0.30)):
        box("FoyerChandelierArm_%s_%s" % (x, y), (x, -1.45 + y, 2.20),
            (0.50 if x else 0.08, 0.50 if y else 0.08, 0.07),
            mat, 6, count, objects, bevel=0.003)
        box("FoyerChandelierLamp_%s_%s" % (x, y), (x, -1.45 + y, 2.10),
            (0.12, 0.12, 0.18), mat, 7, count, objects, bevel=0.006)
    return objects, (6.80, 7.40, 4.90), (0.0, -0.55, 1.25)


def make_mansion_couch_variant(model_name, colors, wide=False):
    mat = mansion_material(model_name, colors)
    count = len(colors)
    objects = []
    width = 1.82 if wide else 0.92
    arm_x = width * 0.5 - 0.08
    cushion_centres = (-0.55, 0.0, 0.55) if wide else (-0.22, 0.22)
    box("CouchBase", (0.0, 0.0, 0.24), (width, 0.60, 0.42), mat, 1,
        count, objects, bevel=0.006)
    box("CouchBack", (0.0, 0.23, 0.62), (width, 0.18, 0.58), mat, 2,
        count, objects, bevel=0.006)
    for side, x in (("L", -arm_x), ("R", arm_x)):
        box("CouchArm_%s" % side, (x, -0.01, 0.46), (0.16, 0.56, 0.46),
            mat, 3, count, objects, bevel=0.005)
    for index, x in enumerate(cushion_centres):
        box("SeatCushion_%d" % (index + 1), (x, -0.08, 0.49),
            (0.50 if wide else 0.40, 0.42, 0.16), mat, 4 if index == 0 else 3,
            count, objects, bevel=0.004)
        box("BackCushion_%d" % (index + 1), (x, 0.12, 0.70),
            (0.50 if wide else 0.40, 0.12, 0.34), mat, 3 if index == 0 else 4,
            count, objects, bevel=0.004)
    foot_x = width * 0.5 - 0.18
    for x in (-foot_x, foot_x):
        box("CouchFoot_%s" % ("L" if x < 0 else "R"), (x, -0.13, 0.045),
            (0.10, 0.10, 0.09), mat, 6, count, objects, bevel=0.001)
    eye = (2.45, -3.15, 1.70) if wide else (1.95, -2.75, 1.60)
    return objects, eye, (0.0, 0.0, 0.45)


def make_ornate_sideboard():
    colors = ["#120D0B", "#2B1913", "#4F2B1C", "#77492E", "#9B6840",
              "#C19459", "#D6B66B", "#EEE0BD"]
    mat = mansion_material("ornate_sideboard", colors, roughness=0.76, metallic=0.04)
    count = len(colors)
    objects = []
    box("SideboardBody", (0.0, 0.02, 0.57), (1.32, 0.58, 0.84), mat, 2,
        count, objects, bevel=0.006)
    box("SideboardTop", (0.0, 0.0, 1.04), (1.44, 0.66, 0.15), mat, 4,
        count, objects, bevel=0.008)
    box("SideboardPlinth", (0.0, 0.02, 0.12), (1.38, 0.62, 0.16), mat, 1,
        count, objects, bevel=0.004)
    for index, x in enumerate((-0.45, 0.0, 0.45)):
        box("TopDrawer_%d" % (index + 1), (x, -0.292, 0.81),
            (0.38, 0.025, 0.24), mat, 3, count, objects, bevel=0.002)
        box("DrawerHandle_%d" % (index + 1), (x, -0.314, 0.82),
            (0.12, 0.025, 0.045), mat, 6, count, objects, bevel=0.001)
    for index, x in enumerate((-0.43, 0.43)):
        box("CabinetDoor_%d" % (index + 1), (x, -0.294, 0.47),
            (0.55, 0.025, 0.42), mat, 2, count, objects, bevel=0.002)
        box("DoorInset_%d" % (index + 1), (x, -0.312, 0.47),
            (0.43, 0.012, 0.31), mat, 1, count, objects, bevel=0.001)
        box("DoorHandle_%d" % (index + 1), (x * 0.42, -0.326, 0.49),
            (0.045, 0.018, 0.10), mat, 6, count, objects, bevel=0.001)
    for x in (-0.63, 0.63):
        box("CarvedPost_%s" % ("L" if x < 0 else "R"), (x, -0.31, 0.58),
            (0.09, 0.08, 0.70), mat, 5, count, objects, bevel=0.002)
    return objects, (2.35, -3.10, 1.85), (0.0, 0.0, 0.58)


def make_table_candelabra():
    colors = ["#110E0A", "#342718", "#715226", "#B88635", "#D9B257",
              "#EFE0AC", "#9F382C", "#F0A738"]
    mat = mansion_material("table_candelabra", colors, roughness=0.52, metallic=0.32)
    count = len(colors)
    objects = []
    cylinder("CandelabraBase", (0.0, 0.0, 0.05), 0.16, 0.10, 8, mat, 2,
             count, objects)
    cylinder("CandelabraStem", (0.0, 0.0, 0.32), 0.055, 0.50, 8, mat, 3,
             count, objects)
    for index, x in enumerate((-0.24, 0.0, 0.24)):
        if x:
            box("CandleArm_%d" % (index + 1), (x * 0.5, 0.0, 0.44),
                (abs(x) + 0.06, 0.055, 0.055), mat, 3, count, objects,
                bevel=0.001, rotation=(0.0, math.radians(-10 if x < 0 else 10), 0.0))
        cylinder("CandleCup_%d" % (index + 1), (x, 0.0, 0.49), 0.075, 0.06, 8,
                 mat, 4, count, objects)
        box("Candle_%d" % (index + 1), (x, 0.0, 0.63), (0.075, 0.075, 0.25),
            mat, 5, count, objects, bevel=0.002)
        box("Flame_%d" % (index + 1), (x, 0.0, 0.79), (0.05, 0.05, 0.08),
            mat, 7, count, objects, bevel=0.001, rotation=(0.0, math.radians(45), 0.0))
    return objects, (1.35, -1.85, 1.20), (0.0, 0.0, 0.38)


def make_flower_centerpiece():
    colors = ["#15100F", "#4A2D24", "#7B4D38", "#C9B890", "#F0E5C7",
              "#345437", "#6A8A4D", "#B9C786", "#8D3240", "#D2C5AA"]
    mat = mansion_material("flower_centerpiece", colors, roughness=0.82)
    count = len(colors)
    objects = []
    cylinder("VaseBase", (0.0, 0.0, 0.09), 0.17, 0.18, 8, mat, 2,
             count, objects)
    cylinder("VaseBody", (0.0, 0.0, 0.27), 0.20, 0.34, 8, mat, 3,
             count, objects)
    cylinder("VaseNeck", (0.0, 0.0, 0.48), 0.11, 0.16, 8, mat, 1,
             count, objects)
    for index, (x, y, z, flower_region) in enumerate((
            (-0.16, 0.02, 0.78, 4), (0.0, -0.04, 0.88, 9),
            (0.16, 0.03, 0.76, 8), (-0.07, 0.07, 0.68, 4),
            (0.09, 0.08, 0.70, 9))):
        box("Stem_%d" % (index + 1), (x * 0.45, y * 0.45, 0.60),
            (0.028, 0.028, 0.34), mat, 5 + index % 2, count, objects,
            bevel=0.0, rotation=(0.0, math.radians(x * 35), math.radians(-x * 30)))
        box("Flower_%d" % (index + 1), (x, y, z), (0.18, 0.14, 0.15),
            mat, flower_region, count, objects, bevel=0.004,
            rotation=(0.0, 0.0, math.radians(45 if index % 2 else 0)))
        box("FlowerCenter_%d" % (index + 1), (x, y - 0.075, z),
            (0.055, 0.025, 0.055), mat, 7, count, objects, bevel=0.001)
    return objects, (1.45, -1.95, 1.30), (0.0, 0.0, 0.44)


def make_framed_wall_portrait():
    colors = ["#100C0A", "#2A1811", "#57301B", "#8A582C", "#B78848",
              "#324345", "#6C7E78", "#B8B394", "#702C31"]
    mat = mansion_material("framed_wall_portrait", colors, roughness=0.70, metallic=0.05)
    count = len(colors)
    objects = []
    box("PortraitBack", (0.0, 0.0, 1.28), (0.86, 0.12, 1.22), mat, 0,
        count, objects, bevel=0.004)
    box("PortraitCanvas", (0.0, -0.072, 1.28), (0.68, 0.025, 1.02), mat, 5,
        count, objects, bevel=0.001)
    for side, x in (("L", -0.39), ("R", 0.39)):
        box("Frame%s" % side, (x, -0.075, 1.28), (0.10, 0.08, 1.22),
            mat, 3, count, objects, bevel=0.003)
    for side, z in (("Top", 1.84), ("Bottom", 0.72)):
        box("Frame%s" % side, (0.0, -0.075, z), (0.86, 0.08, 0.10),
            mat, 4, count, objects, bevel=0.003)
    # Pixel-painted haunted landscape: sky, manor silhouette, moon and path.
    box("PortraitGround", (0.0, -0.089, 1.03), (0.65, 0.008, 0.45), mat, 1,
        count, objects, bevel=0.0)
    box("PortraitManor", (0.04, -0.095, 1.25), (0.30, 0.008, 0.30), mat, 0,
        count, objects, bevel=0.0)
    box("PortraitRoof", (0.04, -0.099, 1.43), (0.40, 0.008, 0.10), mat, 8,
        count, objects, bevel=0.0, rotation=(0.0, math.radians(9), 0.0))
    box("PortraitMoon", (-0.20, -0.101, 1.56), (0.13, 0.008, 0.13), mat, 7,
        count, objects, bevel=0.0)
    box("PortraitPath", (0.04, -0.102, 0.93), (0.16, 0.008, 0.28), mat, 6,
        count, objects, bevel=0.0)
    return objects, (1.65, -2.15, 2.15), (0.0, 0.0, 1.28)


def make_empty_wall_frame(model_name, style="normal", large=False):
    """An authored frame with a genuinely empty centre.

    These are intentionally not recolours of ``framed_wall_portrait``.  There
    is no canvas, backing quad, photograph or painted insert in the opening,
    so a room wall remains visible through it and future art can be supplied
    without deleting a baked placeholder picture first.
    """
    palettes = {
        "normal": ["#120D0A", "#332017", "#5A3825", "#82583A",
                   "#AD8052", "#D1A970", "#211714"],
        "luxury": ["#100B08", "#382216", "#6B4523", "#A8752F",
                   "#D7AD55", "#F0D690", "#541E24", "#27130E"],
        "gothic": ["#08080B", "#17141D", "#30283C", "#53385E",
                   "#7B4667", "#A48BAA", "#5A1826", "#C7B7C8"],
    }
    colors = palettes[style]
    mat = mansion_material(model_name, colors, roughness=0.76,
                           metallic=0.18 if style == "luxury" else 0.06)
    count = len(colors)
    objects = []
    width = 1.18 if large else 0.70
    height = 1.44 if large else 0.84
    centre_z = 1.42 if large else 1.38
    rail = 0.12 if large else 0.095
    depth = 0.11
    base_region = 2 if style == "normal" else (3 if style == "luxury" else 1)
    trim_region = 4 if style != "gothic" else 5

    for side, x in (("L", -width * .5), ("R", width * .5)):
        box("Frame%s" % side, (x, 0.0, centre_z),
            (rail, depth, height), mat, base_region, count, objects,
            bevel=0.003)
    for side, z in (("Top", centre_z + height * .5),
                    ("Bottom", centre_z - height * .5)):
        box("Frame%s" % side, (0.0, 0.0, z),
            (width + rail, depth, rail), mat, base_region, count, objects,
            bevel=0.003)

    # A second stepped rim makes the silhouette readable at gameplay distance
    # while still leaving the complete centre open.
    inner_w = width - rail * .95
    inner_h = height - rail * .95
    trim = rail * .28
    for side, x in (("L", -inner_w * .5), ("R", inner_w * .5)):
        box("InnerTrim%s" % side, (x, -depth * .55, centre_z),
            (trim, depth * .22, inner_h), mat, trim_region, count, objects,
            bevel=0.001)
    for side, z in (("Top", centre_z + inner_h * .5),
                    ("Bottom", centre_z - inner_h * .5)):
        box("InnerTrim%s" % side, (0.0, -depth * .55, z),
            (inner_w, depth * .22, trim), mat, trim_region, count, objects,
            bevel=0.001)

    if style == "luxury":
        for index, (x, z) in enumerate(((-width * .54, centre_z - height * .54),
                                        (width * .54, centre_z - height * .54),
                                        (-width * .54, centre_z + height * .54),
                                        (width * .54, centre_z + height * .54))):
            box("GoldCorner_%d" % (index + 1), (x, -0.015, z),
                (rail * 1.35, depth * 1.18, rail * 1.35), mat, 5,
                count, objects, bevel=0.002,
                rotation=(0.0, 0.0, math.radians(45)))
        box("Crown", (0.0, 0.0, centre_z + height * .5 + rail * .85),
            (width * .52, depth, rail * .55), mat, 4, count, objects,
            bevel=0.002)
    elif style == "gothic":
        # Dark stepped shoulders and a small pointed crown distinguish this
        # from the rectangular household frame without filling the opening.
        for side, x in (("L", -width * .28), ("R", width * .28)):
            box("GothicShoulder%s" % side,
                (x, 0.0, centre_z + height * .57),
                (width * .48, depth, rail), mat, 4, count, objects,
                bevel=0.001,
                rotation=(0.0, math.radians(-22 if x < 0 else 22), 0.0))
        box("GothicCrown", (0.0, 0.0, centre_z + height * .68),
            (rail * .72, depth, rail * 1.65), mat, 7, count, objects,
            bevel=0.001, rotation=(0.0, math.radians(45), 0.0))
    eye = (1.65 if large else 1.25, -2.3 if large else -1.9, 2.1)
    return objects, eye, (0.0, 0.0, centre_z)


def make_room_door(model_name, style="normal", double=False):
    """Open residential doorway dressing for streamed room thresholds.

    The leaf is authored partly open so it reads as a real door but cannot
    silently block the deterministic navigation grid.  Interaction/networked
    door state can later rotate this same leaf without replacing the model.
    """
    palettes = {
        "normal": ["#100C09", "#302017", "#563825", "#7C5538",
                   "#A67C50", "#C7A677", "#25272A", "#C6A04E"],
        "luxury": ["#100B08", "#342016", "#65401F", "#96672B",
                   "#C79B45", "#E3C671", "#5A1C24", "#22120D"],
        "gothic": ["#07070A", "#17131C", "#30263A", "#4E345A",
                   "#6F405D", "#98849E", "#641A2A", "#B5A6B8"],
    }
    colors = palettes[style]
    mat = mansion_material(model_name, colors, roughness=0.79,
                           metallic=0.20 if style != "normal" else 0.08)
    count = len(colors)
    objects = []
    # Single doors occupy one one-metre route cell.  Double doors span two
    # adjacent cells, so their opening and frame must genuinely be twice as
    # wide instead of squeezing two half-width leaves into the single-door
    # silhouette.
    opening_width = 1.92 if double else .92
    width = opening_width * .5 if double else .88
    height = 2.36
    depth = .10
    frame_rail = .14
    frame_x = opening_width * .5 + frame_rail * .5
    frame_width = opening_width + frame_rail * 2.0
    frame_region = 2 if style == "normal" else (3 if style == "luxury" else 1)
    accent_region = 4 if style != "gothic" else 5
    for side, x in (("L", -frame_x), ("R", frame_x)):
        box("DoorFrame%s" % side, (x, 0.0, 1.25),
            (frame_rail, .18, 2.50), mat, frame_region, count, objects, bevel=.003)
    box("DoorFrameTop", (0.0, 0.0, 2.47), (frame_width, .18, .16),
        mat, frame_region, count, objects, bevel=.003)
    box("Threshold", (0.0, 0.0, .035), (frame_width - .04, .19, .07),
        mat, accent_region, count, objects, bevel=.001)

    # Both double-door leaves are full single-door width and meet at the
    # centre of the two-cell threshold.  Stable hinge names let the Godot
    # interaction animate both halves independently.
    leaf_specs = [("", -opening_width * .5, 1.0)] if not double else [
        ("Left", -opening_width * .5, 1.0),
        ("Right", opening_width * .5, -1.0)]
    for suffix, hinge_x, direction in leaf_specs:
        angle = math.radians(68.0) * direction
        half = width * .5
        leaf_x = hinge_x + math.cos(angle) * half * direction
        leaf_y = math.sin(angle) * half * direction
        leaf_objects = []
        box("OpenDoorLeaf%s" % suffix, (leaf_x, leaf_y, 1.19),
            (width, depth, height), mat, 2 if style == "normal" else 1,
            count, leaf_objects, bevel=.004, rotation=(0.0, 0.0, angle))
        normal_x = -math.sin(angle)
        normal_y = math.cos(angle)
        for panel_index, panel_z in enumerate((.66, 1.62)):
            box("DoorPanel%s_%d" % (suffix, panel_index + 1),
                (leaf_x + normal_x * -.061, leaf_y + normal_y * -.061, panel_z),
                (width * .62, .025, .58), mat, accent_region, count, leaf_objects,
                bevel=.002, rotation=(0.0, 0.0, angle))
        handle_d = width - .10
        handle_x = hinge_x + math.cos(angle) * handle_d * direction + normal_x * -.078
        handle_y = math.sin(angle) * handle_d * direction + normal_y * -.078
        box("DoorHandle%s" % suffix, (handle_x, handle_y, 1.18),
            (.08, .055, .07), mat, 7, count, leaf_objects,
            bevel=.002, rotation=(0.0, 0.0, angle))
        bpy.ops.object.empty_add(type="PLAIN_AXES", location=(hinge_x, 0.0, 0.0))
        hinge = bpy.context.object
        hinge.name = "DoorHingeRight" if suffix == "Right" else "DoorHinge"
        for part in leaf_objects:
            world_matrix = part.matrix_world.copy()
            part.parent = hinge
            part.matrix_world = world_matrix
        objects.extend(leaf_objects)
        objects.append(hinge)
    if style == "luxury":
        box("DoorCrown", (0.0, 0.0, 2.61),
            (frame_width * .54, .18, .12),
            mat, 4, count, objects, bevel=.002)
    elif style == "gothic":
        box("DoorSpire", (0.0, 0.0, 2.62), (.15, .18, .28),
            mat, 7, count, objects, bevel=.001,
            rotation=(0.0, math.radians(45), 0.0))
    return objects, (2.45, -3.45, 2.62), (0.0, 0.15, 1.25)


def make_wall_sconce(model_name="wall_sconce", colors=None, style="classic"):
    colors = colors or ["#100D09", "#352817", "#745325", "#B88635", "#D9B257",
                        "#EFE0AC", "#9C372E", "#F0A73B"]
    mat = mansion_material(model_name, colors, roughness=0.50, metallic=0.30)
    count = len(colors)
    objects = []
    plate_width = .30 if style == "gothic" else .24
    box("SconcePlate", (0.0, 0.08, 1.45), (plate_width, 0.10, 0.54), mat, 2,
        count, objects, bevel=0.004)
    box("SconceArm", (0.0, -0.10, 1.35), (0.07, 0.36, 0.07), mat, 3,
        count, objects, bevel=0.002, rotation=(math.radians(-12), 0.0, 0.0))
    cylinder("SconceCup", (0.0, -0.27, 1.44), 0.11, 0.08, 8, mat, 4,
             count, objects)
    box("SconceCandle", (0.0, -0.27, 1.62), (0.10, 0.10, 0.30), mat, 5,
        count, objects, bevel=0.002)
    box("SconceFlame", (0.0, -0.27, 1.82), (0.06, 0.06, 0.10), mat, 7,
        count, objects, bevel=0.001, rotation=(0.0, math.radians(45), 0.0))
    if style == "gothic":
        for x in (-.12, .12):
            box("SconceSpike%s" % ("L" if x < 0 else "R"),
                (x, .075, 1.45), (.08, .08, .68), mat, 6, count, objects,
                bevel=.001, rotation=(0, 0, math.radians(45)))
    return objects, (1.25, -1.75, 2.10), (0.0, 0.0, 1.42)


def make_ceiling_light(model_name, colors, style="round"):
    mat = mansion_material(model_name, colors, roughness=.62, metallic=.18)
    count = len(colors)
    objects = []
    if style == "square":
        box("CeilingPlate", (0, 0, .25), (.74, .74, .10), mat, 1,
            count, objects, bevel=.006)
        box("LightPanel", (0, 0, .12), (.62, .62, .16), mat, 5,
            count, objects, bevel=.008)
    elif style == "cage":
        cylinder("CeilingPlate", (0, 0, .27), .30, .08, 8, mat, 1,
                 count, objects)
        cylinder("LightCore", (0, 0, .12), .16, .18, 8, mat, 5,
                 count, objects)
        for index, (x, y) in enumerate(((-.22, 0), (.22, 0), (0, -.22), (0, .22))):
            box("Cage_%d" % index, (x, y, .13), (.035, .035, .24),
                mat, 2, count, objects, bevel=.001)
    else:
        cylinder("CeilingPlate", (0, 0, .24), .34, .10, 12, mat, 1,
                 count, objects)
        cylinder("LightDiffuser", (0, 0, .11), .28, .16, 12, mat, 5,
                 count, objects)
    return objects, (1.4, -1.9, 1.2), (0, 0, .15)


def make_ceiling_fan(model_name, colors, blade_count=4):
    mat = mansion_material(model_name, colors, roughness=.76, metallic=.14)
    count = len(colors)
    objects = []
    cylinder("CeilingCanopy", (0, 0, .54), .20, .10, 10, mat, 1,
             count, objects)
    box("DownRod", (0, 0, .43), (.07, .07, .18), mat, 2,
        count, objects, bevel=.001)
    cylinder("FanMotor", (0, 0, .31), .25, .18, 10, mat, 2,
             count, objects)
    for index in range(blade_count):
        angle = math.tau * index / blade_count
        radius = .62
        x, y = math.cos(angle) * radius, math.sin(angle) * radius
        box("FanBlade_%d" % (index + 1), (x, y, .32), (.78, .20, .055),
            mat, 3 + index % 2, count, objects, bevel=.004,
            rotation=(0, 0, angle))
    cylinder("FanLight", (0, 0, .16), .22, .18, 10, mat, 5,
             count, objects)
    return objects, (2.1, -2.5, 1.7), (0, 0, .3)


def make_table_lamp(model_name, colors, style="shade"):
    mat = mansion_material(model_name, colors, roughness=.70, metallic=.14)
    count = len(colors)
    objects = []
    cylinder("TableLampBase", (0, 0, .055), .19, .11, 10, mat, 1,
             count, objects)
    box("TableLampStem", (0, 0, .27), (.055, .055, .38), mat, 2,
        count, objects, bevel=.001)
    if style == "banker":
        box("BankerShade", (0, 0, .56), (.48, .25, .20), mat, 5,
            count, objects, bevel=.008)
        box("ShadeTrim", (0, -.13, .55), (.50, .03, .08), mat, 4,
            count, objects, bevel=.002)
    elif style == "orb":
        cylinder("OrbLight", (0, 0, .53), .22, .30, 10, mat, 5,
                 count, objects)
    else:
        cone("TableShade", (0, 0, .53), .25, .17, .28, 8, mat, 5,
             count, objects)
    return objects, (1.2, -1.7, 1.05), (0, 0, .3)


def make_heavy_drapes():
    colors = ["#120D0D", "#2B1716", "#4A2922", "#6B4232", "#8C6148",
              "#B98961", "#C9A55C", "#E1C77E"]
    mat = mansion_material("heavy_mansion_drapes", colors)
    count = len(colors)
    objects = []
    box("DrapeRail", (0.0, 0.0, 2.14), (1.55, 0.10, 0.10), mat, 6,
        count, objects, bevel=0.002)
    for index, x in enumerate((-0.64, -0.50, -0.36, 0.36, 0.50, 0.64)):
        box("DrapeFold_%d" % (index + 1), (x, -0.01 if index % 2 else 0.02, 1.14),
            (0.22, 0.09, 2.00), mat, 2 + index % 4, count, objects,
            bevel=0.002)
    for side, x in (("L", -0.46), ("R", 0.46)):
        box("Tieback%s" % side, (x, -0.07, 1.08), (0.24, 0.07, 0.13), mat, 7,
            count, objects, bevel=0.002)
        box("DrapeTail%s" % side, (x + (-0.08 if x < 0 else 0.08), -0.02, 0.63),
            (0.25, 0.08, 0.78), mat, 3, count, objects, bevel=0.002,
            rotation=(0.0, math.radians(-5 if x < 0 else 5), 0.0))
    return objects, (2.20, -3.10, 2.55), (0.0, 0.0, 1.08)


def make_mansion_area_rug():
    colors = ["#171110", "#3A2220", "#6D3434", "#96504E", "#AA7B52",
              "#C3A879", "#D4C49D", "#344143"]
    mat = mansion_material("mansion_area_rug", colors)
    count = len(colors)
    objects = []
    box("RugField", (0.0, 0.0, 0.018), (2.60, 1.60, 0.036), mat, 2,
        count, objects, bevel=0.002)
    for y in (-0.72, 0.72):
        box("RugBorderY_%s" % str(y), (0.0, y, 0.039), (2.45, 0.12, 0.012),
            mat, 5, count, objects, bevel=0.0)
    for x in (-1.22, 1.22):
        box("RugBorderX_%s" % str(x), (x, 0.0, 0.039), (0.12, 1.35, 0.012),
            mat, 5, count, objects, bevel=0.0)
    for row, y in enumerate((-0.42, 0.0, 0.42)):
        for column, x in enumerate((-0.78, -0.26, 0.26, 0.78)):
            box("RugMotif_%d_%d" % (row, column), (x, y, 0.047),
                (0.22, 0.22, 0.012), mat, 4 if (row + column) % 2 else 6,
                count, objects, bevel=0.0, rotation=(0.0, 0.0, math.radians(45)))
    return objects, (2.90, -3.55, 2.70), (0.0, 0.0, 0.0)


def beach_material(model_name, colors, roughness=0.84, metallic=0.0):
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors, BEACH_TEXTURES)
    return make_material(model_name.replace("_", " ").title() + " pixel paint",
                         image, roughness=roughness, metallic=metallic)


def nether_material(model_name, colors, roughness=0.84, metallic=0.0):
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors, NETHER_TEXTURES)
    return make_material(model_name.replace("_", " ").title() + " pixel paint",
                         image, roughness=roughness, metallic=metallic)


def make_sand_castle():
    colors = ["#3B2B1B", "#79603B", "#A78955", "#C9AD70", "#E0C98E",
              "#8AC2C4", "#9A3944"]
    mat = beach_material("sand_castle", colors)
    count = len(colors)
    objects = []
    # Knee-high beach dressing, not a hunter-sized fortress. Four corner
    # towers and a stepped keep give it a stronger block-built silhouette.
    cylinder("SandMound", (0.0, 0.0, 0.05), 0.38, 0.10, 8, mat, 2,
             count, objects)
    box("CentralKeep", (0.0, 0.02, 0.27), (0.32, 0.30, 0.42), mat, 3,
        count, objects, bevel=0.003)
    for index, (x, y) in enumerate(((-0.22, -0.18), (0.22, -0.18),
                                     (-0.22, 0.18), (0.22, 0.18))):
        cylinder("CornerTower_%d" % (index + 1), (x, y, 0.25), 0.11, 0.38,
                 8, mat, 3 if index % 2 else 4, count, objects)
        for notch, (ox, oy) in enumerate(((-0.055, 0.0), (0.055, 0.0),
                                          (0.0, -0.055), (0.0, 0.055))):
            box("TowerCrenel_%d_%d" % (index + 1, notch + 1),
                (x + ox, y + oy, 0.48), (0.05, 0.05, 0.10), mat, 4,
                count, objects, bevel=0.001)
    for index, (x, y) in enumerate(((-0.11, -0.11), (0.0, -0.11),
                                     (0.11, -0.11), (-0.11, 0.11),
                                     (0.0, 0.11), (0.11, 0.11))):
        box("KeepCrenel_%d" % (index + 1), (x, y, 0.53),
            (0.055, 0.055, 0.10), mat, 4, count, objects, bevel=0.001)
    box("CastleArch", (0.0, -0.138, 0.23), (0.11, 0.018, 0.18), mat, 0,
        count, objects, bevel=0.003)
    box("FrontStep", (0.0, -0.25, 0.10), (0.26, 0.16, 0.10), mat, 2,
        count, objects, bevel=0.002)
    box("FlagPole", (0.0, 0.03, 0.67), (0.025, 0.025, 0.38), mat, 1,
        count, objects, bevel=0.0)
    box("Flag", (0.09, 0.03, 0.79), (0.18, 0.025, 0.12), mat, 6,
        count, objects, bevel=0.001)
    box("LostBucket", (0.33, -0.16, 0.10), (0.12, 0.12, 0.15), mat, 5,
        count, objects, bevel=0.002, rotation=(0.0, math.radians(18), 0.0))
    return objects, (1.35, -1.85, 1.20), (0.0, 0.0, 0.34)


def make_beach_umbrella():
    colors = ["#192327", "#3E666B", "#65A4A8", "#9CC8C8", "#C8C7B5",
              "#E7DDC7", "#76503A"]
    mat = beach_material("beach_umbrella", colors)
    count = len(colors)
    objects = []
    cylinder("UmbrellaBase", (0.0, 0.0, 0.07), 0.24, 0.14, 8, mat, 1,
             count, objects)
    cylinder("UmbrellaBaseInset", (0.0, 0.0, 0.15), 0.17, 0.06, 8, mat, 3,
             count, objects)
    # The complete umbrella is about one and a half 1.70 m hunter bodies tall.
    # This keeps the canopy comfortably overhead without turning the prop into
    # a pavilion.
    cylinder("UmbrellaPole", (0.0, 0.0, 1.28), 0.035, 2.40, 8, mat, 6,
             count, objects)
    # A 2.30 m canopy covers two roughly 0.65 m-wide hunters side by side with
    # room to spare instead of reading as a single-person parasol.
    cone("UmbrellaCanopy", (0.0, 0.0, 2.40), 1.15, 0.10, 0.24, 8, mat, 2,
         count, objects)
    for index, angle in enumerate((0, 45, 90, 135)):
        box("CreamCanopyStripe_%d" % (index + 1), (0.0, 0.0, 2.315),
            (2.12, 0.10, 0.035), mat, 5, count, objects, bevel=0.0,
            rotation=(0.0, 0.0, math.radians(angle)))
    cylinder("CanopyCap", (0.0, 0.0, 2.56), 0.075, 0.08, 8, mat, 4,
             count, objects)
    return objects, (3.10, -4.35, 2.95), (0.0, 0.0, 1.30)


def make_tiki_bar():
    colors = ["#171310", "#33241B", "#5A3B26", "#7E5735", "#A77A48",
              "#3F7779", "#7EBABC", "#D4DFD4", "#B83E3B", "#D3A14B"]
    mat = beach_material("tiki_bar", colors)
    count = len(colors)
    objects = []
    box("BarBody", (0.0, 0.0, 0.42), (1.34, 0.66, 0.76), mat, 2,
        count, objects, bevel=0.005)
    for index, x in enumerate((-0.52, -0.26, 0.0, 0.26, 0.52)):
        box("BarPlank_%d" % (index + 1), (x, -0.342, 0.42),
            (0.22, 0.025, 0.68), mat, 3 if index % 2 else 2,
            count, objects, bevel=0.001)
    box("BarCounter", (0.0, 0.0, 0.85), (1.48, 0.78, 0.14), mat, 4,
        count, objects, bevel=0.006)
    for side, x in (("L", -0.60), ("R", 0.60)):
        box("CanopyPost%s" % side, (x, 0.13, 1.58), (0.10, 0.10, 1.48),
            mat, 3, count, objects, bevel=0.003)
    box("CanopyRoof", (0.0, 0.10, 2.28), (1.54, 0.84, 0.16), mat, 2,
        count, objects, bevel=0.005)
    box("FrozenSign", (0.0, 0.14, 1.86), (0.92, 0.08, 0.30), mat, 5,
        count, objects, bevel=0.004)
    box("SignInset", (0.0, 0.09, 1.86), (0.76, 0.025, 0.18), mat, 6,
        count, objects, bevel=0.002)
    box("BottleShelf", (0.0, -0.36, 1.12), (0.80, 0.10, 0.08), mat, 1,
        count, objects, bevel=0.002)
    for index, x in enumerate((-0.30, -0.20, -0.10, 0.0, 0.10, 0.20, 0.30)):
        box("Bottle_%d" % (index + 1), (x, -0.38, 1.25),
            (0.055, 0.055, 0.22 + 0.03 * (index % 2)), mat,
            5 + index % 5, count, objects, bevel=0.002)
    for index, x in enumerate((-0.42, -0.14, 0.14, 0.42)):
        box("Icicle_%d" % (index + 1), (x, -0.34, 2.13),
            (0.07, 0.05, 0.22 + 0.05 * (index % 2)), mat, 7,
            count, objects, bevel=0.001)
    box("RopeDiagonalA", (0.0, -0.365, 0.35), (0.90, 0.025, 0.045), mat, 9,
        count, objects, bevel=0.0, rotation=(0.0, math.radians(26), 0.0))
    box("RopeDiagonalB", (0.0, -0.368, 0.35), (0.90, 0.025, 0.045), mat, 9,
        count, objects, bevel=0.0, rotation=(0.0, math.radians(-26), 0.0))
    return objects, (2.85, -3.75, 2.70), (0.0, 0.0, 1.16)


def make_beach_chair():
    colors = ["#131719", "#29383B", "#4A686B", "#69A6AA", "#8EC6C7",
              "#D7E3DC", "#704B34"]
    mat = beach_material("beach_chair", colors)
    count = len(colors)
    objects = []
    for side, x in (("L", -0.31), ("R", 0.31)):
        box("FrontLeg%s" % side, (x, -0.15, 0.30), (0.07, 0.07, 0.52),
            mat, 6, count, objects, bevel=0.002,
            rotation=(math.radians(-10), 0.0, 0.0))
        box("BackLeg%s" % side, (x, 0.15, 0.33), (0.07, 0.07, 0.58),
            mat, 6, count, objects, bevel=0.002,
            rotation=(math.radians(16), 0.0, 0.0))
        box("BackPost%s" % side, (x, 0.10, 0.88), (0.07, 0.07, 0.92),
            mat, 1, count, objects, bevel=0.002,
            rotation=(math.radians(-13), 0.0, 0.0))
    box("ChairSeatCanvas", (0.0, -0.04, 0.50), (0.58, 0.42, 0.08), mat, 3,
        count, objects, bevel=0.003)
    box("ChairBackCanvas", (0.0, 0.06, 0.91), (0.58, 0.08, 0.78), mat, 4,
        count, objects, bevel=0.003,
        rotation=(math.radians(-13), 0.0, 0.0))
    for index, z in enumerate((0.63, 0.83, 1.03, 1.23)):
        box("CanvasFrost_%d" % (index + 1), (0.0, -0.035, z),
            (0.48, 0.014, 0.045), mat, 5, count, objects, bevel=0.0,
            rotation=(math.radians(-13), 0.0, 0.0))
    return objects, (1.70, -2.35, 1.75), (0.0, 0.0, 0.66)


def make_surfboard_rack():
    colors = ["#121719", "#284A4D", "#4C8C8B", "#6EB8B3", "#D9C58D",
              "#E8DAB1", "#B74C3D", "#755237", "#D6E0D5"]
    mat = beach_material("surfboard_rack", colors)
    count = len(colors)
    objects = []
    box("RackBase", (0.0, 0.0, 0.09), (1.36, 0.60, 0.18), mat, 0,
        count, objects, bevel=0.004)
    for side, x in (("L", -0.62), ("R", 0.62)):
        box("RackPost%s" % side, (x, 0.0, 0.78), (0.09, 0.56, 1.48), mat, 1,
            count, objects, bevel=0.003)
    board_specs = ((-0.40, 3), (0.0, 5), (0.40, 6))
    for index, (x, region) in enumerate(board_specs):
        box("BoardBody_%d" % (index + 1), (x, 0.04, 0.88),
            (0.28, 0.11, 1.16), mat, region, count, objects, bevel=0.004)
        box("BoardNose_%d" % (index + 1), (x, 0.04, 1.49),
            (0.21, 0.11, 0.21), mat, region, count, objects, bevel=0.002,
            rotation=(0.0, math.radians(45), 0.0))
        box("BoardTail_%d" % (index + 1), (x, 0.04, 0.27),
            (0.18, 0.11, 0.18), mat, region, count, objects, bevel=0.002,
            rotation=(0.0, math.radians(45), 0.0))
        box("BoardStripe_%d" % (index + 1), (x, -0.022, 0.93),
            (0.06, 0.012, 0.84), mat, 8, count, objects, bevel=0.0)
    for z in (0.45, 1.08):
        box("RackRail_%s" % str(z), (0.0, -0.15, z), (1.26, 0.09, 0.10),
            mat, 7, count, objects, bevel=0.002)
    box("FrozenTidelineSign", (0.0, -0.18, 0.18), (1.18, 0.08, 0.26), mat, 2,
        count, objects, bevel=0.003)
    return objects, (2.35, -3.05, 2.15), (0.0, 0.0, 0.78)


def make_palm_tree():
    colors = ["#101719", "#293C3C", "#4F6E67", "#6F9690", "#9BC0B9",
              "#4B3022", "#765034", "#A07145", "#D9E4D9", "#A63D49"]
    mat = beach_material("palm_tree", colors)
    count = len(colors)
    objects = []
    cylinder("PalmPlanter", (0.0, 0.0, 0.12), 0.50, 0.24, 8, mat, 0,
             count, objects)
    cylinder("PlanterRim", (0.0, 0.0, 0.25), 0.52, 0.10, 8, mat, 3,
             count, objects)
    # Eleven stacked trunk sections make the tree a little over two complete
    # 1.70 m hunter bodies tall while preserving the connected leaf footprint.
    for index in range(11):
        z = 0.40 + index * 0.30
        cone("TrunkSegment_%d" % (index + 1), (0.0, 0.0, z),
             0.17 - index * 0.007, 0.15 - index * 0.007, 0.32, 8,
             mat, 5 + index % 3, count, objects)
    for index, angle in enumerate(range(0, 360, 45)):
        radians = math.radians(angle)
        inner_x, inner_y = math.cos(radians) * 0.25, math.sin(radians) * 0.25
        middle_x, middle_y = math.cos(radians) * 0.65, math.sin(radians) * 0.65
        tip_x, tip_y = math.cos(radians) * 0.98, math.sin(radians) * 0.98
        box("FrondInner_%d" % (index + 1), (inner_x, inner_y, 3.63),
            (0.60, 0.16, 0.11), mat, 2 + index % 3, count, objects,
            bevel=0.002, rotation=(0.0, 0.0, radians))
        box("FrondMiddle_%d" % (index + 1), (middle_x, middle_y, 3.58),
            (0.54, 0.15, 0.10), mat, 3 + index % 2, count, objects,
            bevel=0.002, rotation=(0.0, 0.0, radians))
        box("FrondTip_%d" % (index + 1), (tip_x, tip_y, 3.48),
            (0.38, 0.12, 0.10), mat, 4, count, objects,
            bevel=0.002, rotation=(0.0, 0.0, radians))
    # Small frozen bulbs sit against the front of the trunk rather than
    # hovering off its corners as the old diagonal offsets did.
    for index, (x, y, z) in enumerate(((-0.06, -0.13, 0.70), (0.06, -0.13, 1.00),
                                       (-0.06, -0.13, 1.30), (0.06, -0.13, 1.60),
                                       (-0.06, -0.13, 1.90), (0.06, -0.13, 2.20),
                                       (-0.06, -0.12, 2.50), (0.06, -0.11, 2.80),
                                       (-0.06, -0.10, 3.10))):
        box("PalmLight_%d" % (index + 1), (x, y, z), (0.08, 0.06, 0.08),
            mat, 9 if index % 2 else 8, count, objects, bevel=0.001)
    return objects, (4.40, -5.60, 4.10), (0.0, 0.0, 1.85)


def make_frozen_beach_hut():
    colors = ["#101719", "#293A3C", "#4E7375", "#7FA9A8", "#BED2CC",
              "#E4E4D6", "#36251D", "#65432D", "#91633E", "#B1433E"]
    mat = beach_material("frozen_beach_hut", colors)
    count = len(colors)
    objects = []
    box("HutDeck", (0.0, 0.0, 0.20), (2.10, 1.70, 0.22), mat, 7,
        count, objects, bevel=0.006)
    for index, (x, y) in enumerate(((-0.82, -0.62), (0.82, -0.62),
                                     (-0.82, 0.62), (0.82, 0.62))):
        box("HutStilt_%d" % (index + 1), (x, y, 0.10), (0.16, 0.16, 0.20),
            mat, 6, count, objects, bevel=0.002)
    box("HutBody", (0.0, 0.06, 1.30), (1.82, 1.38, 2.02), mat, 8,
        count, objects, bevel=0.005)
    for index, x in enumerate((-0.70, -0.42, -0.14, 0.14, 0.42, 0.70)):
        box("FrontPlank_%d" % (index + 1), (x, -0.642, 1.31),
            (0.22, 0.025, 1.85), mat, 7 if index % 2 else 8,
            count, objects, bevel=0.001)
    box("HutDoor", (0.43, -0.668, 1.22), (0.70, 0.04, 1.82), mat, 6,
        count, objects, bevel=0.004)
    box("DoorInset", (0.43, -0.695, 1.22), (0.57, 0.018, 1.65), mat, 1,
        count, objects, bevel=0.002)
    box("DoorHandle", (0.16, -0.715, 1.22), (0.06, 0.025, 0.10), mat, 9,
        count, objects, bevel=0.001)
    box("WindowFrame", (-0.47, -0.675, 1.55), (0.62, 0.05, 0.68), mat, 6,
        count, objects, bevel=0.003)
    box("FrozenWindow", (-0.47, -0.708, 1.55), (0.50, 0.018, 0.56), mat, 3,
        count, objects, bevel=0.002)
    box("WindowCrossV", (-0.47, -0.721, 1.55), (0.045, 0.014, 0.56), mat, 5,
        count, objects, bevel=0.0)
    box("WindowCrossH", (-0.47, -0.723, 1.55), (0.50, 0.014, 0.045), mat, 5,
        count, objects, bevel=0.0)
    box("RoofLeft", (-0.48, 0.02, 2.43), (1.25, 1.75, 0.18), mat, 6,
        count, objects, bevel=0.004, rotation=(0.0, math.radians(-24), 0.0))
    box("RoofRight", (0.48, 0.02, 2.43), (1.25, 1.75, 0.18), mat, 6,
        count, objects, bevel=0.004, rotation=(0.0, math.radians(24), 0.0))
    for side, x, angle in (("L", -0.50, -24), ("R", 0.50, 24)):
        box("RoofFrost%s" % side, (x, -0.02, 2.53), (1.18, 1.64, 0.08), mat, 5,
            count, objects, bevel=0.003, rotation=(0.0, math.radians(angle), 0.0))
    for index, x in enumerate((-0.68, -0.30, 0.10, 0.52)):
        box("HutIcicle_%d" % (index + 1), (x, -0.88, 2.19),
            (0.07, 0.06, 0.28 + 0.06 * (index % 2)), mat, 4,
            count, objects, bevel=0.001)
    box("HutSign", (0.0, -0.73, 2.27), (0.58, 0.05, 0.20), mat, 2,
        count, objects, bevel=0.003)
    return objects, (3.75, -4.75, 3.45), (0.0, 0.0, 1.40)


def make_frozen_tideline_pool():
    """Contained indoor-ocean dressing for a frozen tideline room.

    The route floor remains underneath this shallow model, so it reads as a
    dark ocean inlet without becoming a hole or an accidental route exit.
    Chunky ice banks keep the water edge legible in the game's block style.
    """
    water_colors = ["#07161B", "#0B2832", "#12414E", "#1B5D69",
                    "#2D7880", "#65A8AA", "#A4D2CF", "#DDEAE3"]
    ice_colors = ["#17262B", "#355158", "#58747A", "#82A2A4",
                  "#ACC5C2", "#D3E0DA", "#EDF1E8", "#6C888B"]
    water = beach_material("frozen_tideline_water", water_colors,
                           roughness=0.28, metallic=0.08)
    ice = beach_material("frozen_tideline_ice", ice_colors,
                         roughness=0.70)
    objects = []
    box("ContainedOceanSurface", (0.0, 0.0, 0.055), (6.20, 5.20, 0.07),
        water, 3, len(water_colors), objects, bevel=0.006)
    # Staggered pixel shelves avoid a perfect rectangular bathtub outline.
    edge_specs = (
        (-2.65, -2.35, 1.00, .42, .16), (-1.35, -2.48, 1.20, .30, .12),
        (0.15, -2.42, 1.35, .42, .18), (1.65, -2.48, .90, .32, .14),
        (2.72, -2.28, .70, .52, .20), (-2.78, 2.30, .75, .48, .18),
        (-1.70, 2.46, 1.05, .28, .12), (-.35, 2.38, 1.25, .44, .18),
        (1.15, 2.48, 1.05, .28, .13), (2.55, 2.34, 1.15, .46, .18),
    )
    for index, (x, y, width, depth, height) in enumerate(edge_specs):
        box("IceBankLong_%02d" % index, (x, y, .07 + height * .5),
            (width, depth, height), ice, 3 + index % 4, len(ice_colors),
            objects, bevel=.003)
    side_specs = (
        (-3.00, -1.55, .42, 1.10, .16), (-3.08, -.25, .30, 1.05, .13),
        (-3.00, 1.15, .46, 1.25, .19), (3.02, -1.55, .38, 1.05, .14),
        (3.08, -.20, .30, 1.20, .12), (3.00, 1.25, .44, 1.05, .18),
    )
    for index, (x, y, width, depth, height) in enumerate(side_specs):
        box("IceBankSide_%02d" % index, (x, y, .07 + height * .5),
            (width, depth, height), ice, 2 + index % 5, len(ice_colors),
            objects, bevel=.003)
    # Sparse floating plates add depth without blocking the playable floor.
    for index, (x, y, sx, sy) in enumerate(((-1.55, -.65, .78, .48),
                                             (.85, .65, .62, .42),
                                             (1.90, -1.15, .46, .34))):
        box("DriftIce_%02d" % index, (x, y, .115), (sx, sy, .08), ice,
            4 + index, len(ice_colors), objects, bevel=.003,
            rotation=(0.0, 0.0, math.radians((-12, 9, -7)[index])))
    return objects, (7.8, -9.2, 5.9), (0.0, 0.0, 0.0)


def make_lava_vent():
    colors = ["#0B0C0D", "#1C1E21", "#343338", "#553234", "#7D2925",
              "#C23A20", "#EF6B22", "#F5B33B"]
    mat = nether_material("lava_vent", colors, roughness=0.70, metallic=0.22)
    count = len(colors)
    objects = []
    cylinder("VentBase", (0.0, 0.0, 0.10), 0.34, 0.20, 8, mat, 1,
             count, objects)
    cylinder("VentBody", (0.0, 0.0, 0.31), 0.31, 0.32, 8, mat, 3,
             count, objects)
    cylinder("VentTopLip", (0.0, 0.0, 0.50), 0.34, 0.10, 8, mat, 4,
             count, objects)
    cylinder("LavaWell", (0.0, 0.0, 0.565), 0.25, 0.04, 8, mat, 6,
             count, objects)
    for index, y in enumerate((-0.20, -0.10, 0.0, 0.10, 0.20)):
        box("VentGrille_%d" % (index + 1), (0.0, y, 0.60),
            (0.50, 0.045, 0.055), mat, 0, count, objects, bevel=0.001)
    for index, x in enumerate((-0.18, 0.0, 0.18)):
        box("LavaGlow_%d" % (index + 1), (x, -0.315, 0.31),
            (0.08, 0.018, 0.20), mat, 6 + index % 2, count, objects,
            bevel=0.001)
    return objects, (1.55, -2.15, 1.25), (0.0, 0.0, 0.28)


def make_ember_brazier():
    colors = ["#090A0C", "#1B1D21", "#33343A", "#4D3A3A", "#782B25",
              "#BB3B22", "#EC6A20", "#F3AE35"]
    mat = nether_material("ember_brazier", colors, roughness=0.72, metallic=0.18)
    count = len(colors)
    objects = []
    for index, (x, y) in enumerate(((-0.20, -0.20), (0.20, -0.20),
                                     (-0.20, 0.20), (0.20, 0.20))):
        box("BrazierFoot_%d" % (index + 1), (x, y, 0.10),
            (0.12, 0.12, 0.20), mat, 1, count, objects, bevel=0.002)
    cone("BrazierBowl", (0.0, 0.0, 0.40), 0.22, 0.30, 0.34, 8, mat, 2,
         count, objects)
    cylinder("BrazierRim", (0.0, 0.0, 0.58), 0.31, 0.08, 8, mat, 3,
             count, objects)
    cylinder("CoalBed", (0.0, 0.0, 0.625), 0.24, 0.03, 8, mat, 0,
             count, objects)
    for index, (x, y, z, region) in enumerate(((-0.11, -0.05, 0.67, 5),
                                                (0.08, 0.04, 0.69, 6),
                                                (0.0, -0.07, 0.77, 7),
                                                (0.13, -0.02, 0.71, 5))):
        box("Ember_%d" % (index + 1), (x, y, z), (0.13, 0.10, 0.16),
            mat, region, count, objects, bevel=0.002,
            rotation=(0.0, math.radians(45 if index % 2 else 0), 0.0))
    return objects, (1.50, -2.05, 1.30), (0.0, 0.0, 0.40)


def make_basalt_pillar():
    colors = ["#08090B", "#15171B", "#282A30", "#3B3C43", "#55545A",
              "#762A22", "#C54424", "#EF7628"]
    mat = nether_material("basalt_pillar", colors, roughness=0.90)
    count = len(colors)
    objects = []
    cylinder("PillarBase", (0.0, 0.0, 0.10), 0.32, 0.20, 8, mat, 1,
             count, objects)
    cylinder("PillarBaseTrim", (0.0, 0.0, 0.23), 0.28, 0.10, 8, mat, 3,
             count, objects)
    for index, (z, radius, depth) in enumerate(((0.48, 0.23, 0.44),
                                                 (0.84, 0.22, 0.34),
                                                 (1.18, 0.23, 0.34),
                                                 (1.52, 0.21, 0.34))):
        cylinder("BasaltSegment_%d" % (index + 1), (0.0, 0.0, z), radius,
                 depth, 8, mat, 2 + index % 3, count, objects,
                 rotation=(0.0, 0.0, math.radians(11 * index)))
    cylinder("PillarCap", (0.0, 0.0, 1.73), 0.28, 0.16, 8, mat, 4,
             count, objects)
    cylinder("PillarCrown", (0.0, 0.0, 1.84), 0.23, 0.08, 8, mat, 2,
             count, objects)
    for index, (x, z, height, region) in enumerate(((-0.13, 0.55, 0.26, 6),
                                                     (0.12, 0.92, 0.34, 7),
                                                     (-0.10, 1.31, 0.28, 6))):
        box("MagmaCrack_%d" % (index + 1), (x, -0.225, z),
            (0.045, 0.012, height), mat, region, count, objects,
            bevel=0.0, rotation=(0.0, math.radians(-10 if index % 2 else 10), 0.0))
    return objects, (1.55, -2.25, 2.10), (0.0, 0.0, 0.90)


def make_magma_crystal_cluster():
    colors = ["#08090B", "#17161A", "#312126", "#632124", "#A52E24",
              "#DF4B22", "#F27928", "#F6B33D"]
    mat = nether_material("magma_crystal_cluster", colors, roughness=0.68)
    count = len(colors)
    objects = []
    cylinder("CrystalBed", (0.0, 0.0, 0.06), 0.34, 0.12, 8, mat, 1,
             count, objects)
    specs = ((-0.16, 0.02, 0.42, 0.62, -14, 5),
             (0.02, 0.04, 0.55, 0.88, 4, 7),
             (0.18, -0.02, 0.34, 0.50, 16, 6),
             (-0.02, -0.15, 0.26, 0.38, -8, 4))
    for index, (x, y, z, height, angle, region) in enumerate(specs):
        box("MagmaCrystal_%d" % (index + 1), (x, y, z),
            (0.16, 0.16, height), mat, region, count, objects, bevel=0.002,
            rotation=(0.0, math.radians(angle), math.radians(45)))
        box("CrystalTip_%d" % (index + 1), (x, y, z + height * 0.52),
            (0.12, 0.12, 0.12), mat, 7, count, objects, bevel=0.001,
            rotation=(0.0, math.radians(45), math.radians(45)))
    return objects, (1.45, -2.00, 1.35), (0.0, 0.0, 0.36)


def make_basalt_rubble():
    colors = ["#08090A", "#15171A", "#282A2F", "#3C3D43", "#56555B",
              "#872B22", "#D34A24"]
    mat = nether_material("basalt_rubble", colors)
    count = len(colors)
    objects = []
    specs = ((-0.28, -0.12, 0.14, 0.26), (-0.05, -0.15, 0.20, 0.34),
             (0.22, -0.10, 0.13, 0.22), (-0.20, 0.14, 0.18, 0.30),
             (0.08, 0.12, 0.15, 0.25), (0.30, 0.12, 0.10, 0.18))
    for index, (x, y, z, size) in enumerate(specs):
        cylinder("Rubble_%d" % (index + 1), (x, y, z + 0.06), size, size * 0.85, 6,
                 mat, 2 + index % 3, count, objects,
                 rotation=(math.radians(12 * (index % 2)),
                           math.radians(8 * (index % 3)),
                           math.radians(index * 17)))
    for index, x in enumerate((-0.18, 0.16)):
        box("RubbleGlow_%d" % (index + 1), (x, -0.30, 0.12),
            (0.08, 0.018, 0.18), mat, 5 + index, count, objects,
            bevel=0.001, rotation=(0.0, math.radians(20), 0.0))
    return objects, (1.55, -2.15, 1.05), (0.0, 0.0, 0.18)


def make_inferno_altar():
    colors = ["#08090B", "#17191D", "#2A2C32", "#44434A", "#6B2926",
              "#A93626", "#E15424", "#F19A31"]
    mat = nether_material("inferno_altar", colors, roughness=0.78, metallic=0.10)
    count = len(colors)
    objects = []
    box("AltarStepLower", (0.0, 0.0, 0.10), (1.20, 0.82, 0.20), mat, 1,
        count, objects, bevel=0.004)
    box("AltarStepUpper", (0.0, 0.0, 0.26), (0.98, 0.68, 0.16), mat, 2,
        count, objects, bevel=0.004)
    box("AltarBody", (0.0, 0.05, 0.58), (0.82, 0.56, 0.58), mat, 3,
        count, objects, bevel=0.005)
    box("AltarTop", (0.0, 0.0, 0.91), (1.02, 0.72, 0.16), mat, 4,
        count, objects, bevel=0.005)
    box("AltarInset", (0.0, -0.295, 0.60), (0.54, 0.025, 0.34), mat, 0,
        count, objects, bevel=0.002)
    box("RuneVertical", (0.0, -0.315, 0.60), (0.08, 0.014, 0.28), mat, 6,
        count, objects, bevel=0.001)
    box("RuneHorizontal", (0.0, -0.318, 0.60), (0.30, 0.014, 0.07), mat, 7,
        count, objects, bevel=0.001)
    for index, x in enumerate((-0.32, 0.32)):
        box("AltarCandle_%d" % (index + 1), (x, -0.08, 1.08),
            (0.10, 0.10, 0.28), mat, 5, count, objects, bevel=0.002)
        box("AltarFlame_%d" % (index + 1), (x, -0.08, 1.27),
            (0.06, 0.06, 0.10), mat, 7, count, objects, bevel=0.001,
            rotation=(0.0, math.radians(45), 0.0))
    return objects, (2.15, -2.85, 1.80), (0.0, 0.0, 0.55)


def make_inferno_chain_lantern():
    colors = ["#07080A", "#15171A", "#2A2D32", "#47474D", "#7A2924",
              "#B73B22", "#EC6221", "#F3A735"]
    mat = nether_material("inferno_chain_lantern", colors, roughness=0.66, metallic=0.22)
    count = len(colors)
    objects = []
    cylinder("LanternMount", (0.0, 0.0, 1.55), 0.16, 0.08, 8, mat, 2,
             count, objects)
    for index, z in enumerate((1.40, 1.26, 1.12, 0.98)):
        box("LanternChain_%d" % (index + 1), (0.0, 0.0, z),
            (0.07 if index % 2 else 0.12, 0.12 if index % 2 else 0.07, 0.10),
            mat, 3, count, objects, bevel=0.001)
    box("LanternCageTop", (0.0, 0.0, 0.87), (0.42, 0.42, 0.10), mat, 2,
        count, objects, bevel=0.003)
    box("LanternCageBottom", (0.0, 0.0, 0.28), (0.42, 0.42, 0.10), mat, 2,
        count, objects, bevel=0.003)
    for index, (x, y) in enumerate(((-0.18, -0.18), (0.18, -0.18),
                                     (-0.18, 0.18), (0.18, 0.18))):
        box("LanternBar_%d" % (index + 1), (x, y, 0.58),
            (0.055, 0.055, 0.62), mat, 1, count, objects, bevel=0.001)
    box("LanternEmber", (0.0, 0.0, 0.57), (0.24, 0.24, 0.42), mat, 6,
        count, objects, bevel=0.003)
    box("LanternHotCore", (0.0, -0.13, 0.57), (0.10, 0.04, 0.24), mat, 7,
        count, objects, bevel=0.001)
    return objects, (1.55, -2.15, 1.95), (0.0, 0.0, 0.82)


def make_lava_pipe_manifold():
    colors = ["#090A0B", "#191B1E", "#303237", "#4B4548", "#742C29",
              "#B23A24", "#E75A21", "#F19B31"]
    mat = nether_material("lava_pipe_manifold", colors, roughness=0.70, metallic=0.24)
    count = len(colors)
    objects = []
    box("PipeBase", (0.0, 0.0, 0.10), (1.20, 0.64, 0.20), mat, 1,
        count, objects, bevel=0.004)
    cylinder("MainPipe", (0.0, 0.0, 0.62), 0.16, 1.12, 8, mat, 2,
             count, objects, rotation=(0.0, math.radians(90), 0.0))
    for index, x in enumerate((-0.42, 0.0, 0.42)):
        cylinder("PipeRiser_%d" % (index + 1), (x, 0.0, 0.48), 0.11,
                 0.78 - 0.10 * (index % 2), 8, mat, 3, count, objects)
        cylinder("PipeCollar_%d" % (index + 1), (x, 0.0, 0.75), 0.15,
                 0.08, 8, mat, 4, count, objects)
        box("HeatWindow_%d" % (index + 1), (x, -0.12, 0.48),
            (0.08, 0.025, 0.24), mat, 6 + index % 2, count, objects,
            bevel=0.001)
    cylinder("ValveWheel", (0.0, -0.20, 0.94), 0.20, 0.07, 8, mat, 5,
             count, objects, rotation=(math.radians(90), 0.0, 0.0))
    box("ValveCrossH", (0.0, -0.245, 0.94), (0.34, 0.04, 0.055), mat, 1,
        count, objects, bevel=0.001)
    box("ValveCrossV", (0.0, -0.248, 0.94), (0.055, 0.04, 0.34), mat, 1,
        count, objects, bevel=0.001)
    return objects, (2.10, -2.80, 1.65), (0.0, 0.0, 0.50)


def make_charred_supply_crate():
    colors = ["#08090A", "#171719", "#2A2526", "#43302C", "#642B26",
              "#A73524", "#DD5222", "#ED8D2D"]
    mat = nether_material("charred_supply_crate", colors)
    count = len(colors)
    objects = []
    box("CharredCrate", (0.0, 0.0, 0.31), (0.74, 0.60, 0.62), mat, 2,
        count, objects, bevel=0.004)
    for index, x in enumerate((-0.32, 0.32)):
        box("CrateBand_%d" % (index + 1), (x, 0.0, 0.31),
            (0.08, 0.63, 0.62), mat, 1, count, objects, bevel=0.002)
    box("CrateTopBand", (0.0, 0.0, 0.57), (0.74, 0.63, 0.10), mat, 3,
        count, objects, bevel=0.002)
    box("CrateHandle", (0.0, -0.315, 0.35), (0.24, 0.025, 0.10), mat, 0,
        count, objects, bevel=0.002)
    for index, (x, z, height) in enumerate(((-0.16, 0.24, 0.26),
                                             (0.08, 0.38, 0.22),
                                             (0.23, 0.22, 0.18))):
        box("CrateMagmaCrack_%d" % (index + 1), (x, -0.329, z),
            (0.05, 0.012, height), mat, 6 + index % 2, count, objects,
            bevel=0.0, rotation=(0.0, math.radians(-14 + index * 14), 0.0))
    return objects, (1.55, -2.15, 1.25), (0.0, 0.0, 0.30)


NORMAL_BEDROOM_PALETTES = {
    "burgundy": ["#120E0E", "#392219", "#633A26", "#8A5738",
                 "#7B2734", "#B74858", "#D8CBB0", "#EEE5CE", "#B28A48"],
    "navy": ["#0C1015", "#202D3C", "#334A62", "#4C6A85",
             "#273B62", "#3F5F91", "#D5CCB5", "#EEE6D3", "#B18A4A"],
    "violet": ["#110C13", "#30203A", "#52315D", "#74467E",
               "#71304F", "#A74C76", "#D5C9B3", "#EEE4CF", "#B18A4A"],
    "olive": ["#0E100A", "#2D321D", "#4C5730", "#6E7943",
              "#445328", "#73814A", "#D5CCB5", "#EEE6D3", "#B18A4A"],
    "ivory": ["#1A1714", "#5D5245", "#867968", "#A99B85",
              "#B9A98D", "#D7C8A9", "#E5DCCB", "#F5EEDD", "#B18A4A"],
    "charcoal": ["#090A0B", "#1B1D20", "#30343A", "#4A5057",
                 "#2A2F36", "#59636D", "#CACBC7", "#ECEAE1", "#B18A4A"],
}

GOTHIC_BEDROOM_PALETTES = {
    # Indices stay structurally consistent: black iron, dark wood, carved wood,
    # bright trim, deep textile, bright textile, linen, metal and candlelight.
    "crimson": ["#080709", "#151117", "#29202B", "#54404D",
                "#5A101D", "#B2293D", "#D8CFBF", "#8E7448", "#F2B75B"],
    "violet": ["#080709", "#151117", "#29202B", "#54404D",
               "#3F174E", "#873AA1", "#D8CFBF", "#8E7448", "#F2B75B"],
    "midnight": ["#07080A", "#11151B", "#202935", "#455268",
                 "#101F43", "#294D8B", "#D5D0C3", "#86744E", "#EFB65A"],
    "forest": ["#070907", "#121813", "#233027", "#46584A",
               "#17351F", "#347046", "#D5D0C3", "#887448", "#EFB65A"],
    "ivory": ["#09090A", "#171719", "#2B292C", "#5D565A",
              "#958B7D", "#D7CDBA", "#F1EBDD", "#92784A", "#F3BA5D"],
}


def make_bedroom_bed(model_name, double=False, colors=None):
    colors = colors or NORMAL_BEDROOM_PALETTES["burgundy"]
    mat = mansion_material(model_name, colors)
    count = len(colors)
    objects = []
    # 2.42 m of mattress length comfortably contains the 1.70 m shared body
    # and the tallest 2.20 m hunter silhouettes without feet hanging over.
    width = 1.82 if double else 1.08
    mattress_width = width - 0.14
    pillow_centres = (-0.43, 0.43) if double else (0.0,)
    box("BedFrame", (0.0, 0.0, 0.28), (width, 2.62, 0.34), mat, 2,
        count, objects, bevel=0.005)
    box("Mattress", (0.0, -0.03, 0.51), (mattress_width, 2.42, 0.24), mat,
        6, count, objects, bevel=0.006)
    box("Blanket", (0.0, -0.42, 0.655), (mattress_width - 0.04, 1.48, 0.08),
        mat, 5, count, objects, bevel=0.004)
    for index, x in enumerate(pillow_centres):
        box("Pillow_%d" % (index + 1), (x, 0.88, 0.67),
            ((0.68 if double else 0.72), 0.46, 0.15), mat, 7,
            count, objects, bevel=0.008)
        box("PillowBand_%d" % (index + 1), (x, 0.665, 0.69),
            ((0.50 if double else 0.54), 0.035, 0.055), mat, 6,
            count, objects, bevel=0.001)
    box("HeadboardPanel", (0.0, 1.26, 0.86), (width, 0.14, 0.82), mat, 3,
        count, objects, bevel=0.005)
    box("HeadboardInset", (0.0, 1.18, 0.88), (width - 0.22, 0.035, 0.52),
        mat, 4, count, objects, bevel=0.003)
    for side, x in (("L", -width * 0.5 + 0.06),
                    ("R", width * 0.5 - 0.06)):
        box("HeadPost%s" % side, (x, 1.26, 0.67), (0.12, 0.16, 1.34),
            mat, 1, count, objects, bevel=0.003)
        box("Foot%s" % side, (x, -1.21, 0.12), (0.12, 0.12, 0.24),
            mat, 1, count, objects, bevel=0.002)
    box("Footboard", (0.0, -1.26, 0.40), (width, 0.13, 0.48), mat, 2,
        count, objects, bevel=0.004)
    eye = (2.75, -3.55, 2.20) if double else (2.25, -3.10, 2.05)
    return objects, eye, (0.0, 0.0, 0.56)


def make_bedroom_nightstand(model_name="bedroom_nightstand", colors=None):
    colors = colors or NORMAL_BEDROOM_PALETTES["burgundy"]
    mat = mansion_material(model_name, colors)
    count = len(colors)
    objects = []
    box("NightstandBody", (0.0, 0.0, 0.34), (0.52, 0.45, 0.58), mat, 2,
        count, objects, bevel=0.004)
    box("NightstandTop", (0.0, -0.01, 0.66), (0.58, 0.50, 0.10), mat, 4,
        count, objects, bevel=0.005)
    for index, z in enumerate((0.46, 0.24)):
        box("NightstandDrawer_%d" % (index + 1), (0.0, -0.231, z),
            (0.42, 0.025, 0.16), mat, 3, count, objects, bevel=0.002)
        box("NightstandHandle_%d" % (index + 1), (0.0, -0.251, z),
            (0.13, 0.024, 0.04), mat, 6, count, objects, bevel=0.001)
    for x in (-0.21, 0.21):
        box("NightstandFoot_%s" % ("L" if x < 0 else "R"),
            (x, 0.0, 0.055), (0.08, 0.35, 0.11), mat, 1,
            count, objects, bevel=0.002)
    return objects, (1.45, -2.05, 1.30), (0.0, 0.0, 0.34)


def make_bedroom_wardrobe(model_name="bedroom_wardrobe", colors=None):
    colors = colors or NORMAL_BEDROOM_PALETTES["burgundy"]
    mat = mansion_material(model_name, colors)
    count = len(colors)
    objects = []
    box("WardrobeBody", (0.0, 0.04, 1.02), (1.08, 0.54, 1.94), mat, 2,
        count, objects, bevel=0.006)
    box("WardrobeCrown", (0.0, 0.02, 2.04), (1.20, 0.62, 0.14), mat, 5,
        count, objects, bevel=0.006)
    box("WardrobePlinth", (0.0, 0.02, 0.09), (1.16, 0.60, 0.18), mat, 1,
        count, objects, bevel=0.004)
    for index, x in enumerate((-0.27, 0.27)):
        box("WardrobeDoor_%d" % (index + 1), (x, -0.244, 1.10),
            (0.48, 0.025, 1.62), mat, 3, count, objects, bevel=0.003)
        box("WardrobeInset_%d" % (index + 1), (x, -0.262, 1.13),
            (0.36, 0.014, 1.34), mat, 1, count, objects, bevel=0.002)
        box("WardrobeHandle_%d" % (index + 1),
            (-0.07 if x < 0 else 0.07, -0.282, 1.08),
            (0.045, 0.025, 0.22), mat, 6, count, objects, bevel=0.001)
    box("WardrobeCarvedBand", (0.0, -0.274, 1.86), (0.92, 0.014, 0.12),
        mat, 7, count, objects, bevel=0.001)
    return objects, (2.30, -3.10, 2.40), (0.0, 0.0, 1.02)


def make_bedroom_dresser(model_name="bedroom_dresser", colors=None):
    colors = colors or NORMAL_BEDROOM_PALETTES["burgundy"]
    mat = mansion_material(model_name, colors)
    count = len(colors)
    objects = []
    box("DresserBody", (0.0, 0.02, 0.50), (1.16, 0.50, 0.88), mat, 2,
        count, objects, bevel=0.005)
    box("DresserTop", (0.0, 0.0, 0.98), (1.24, 0.56, 0.12), mat, 4,
        count, objects, bevel=0.006)
    box("DresserPlinth", (0.0, 0.02, 0.08), (1.20, 0.54, 0.16), mat, 1,
        count, objects, bevel=0.003)
    for row, z in enumerate((0.78, 0.52, 0.26)):
        for column, x in enumerate((-0.28, 0.28)):
            box("DresserDrawer_%d_%d" % (row + 1, column + 1),
                (x, -0.244, z), (0.49, 0.025, 0.20), mat, 3,
                count, objects, bevel=0.002)
            box("DresserHandle_%d_%d" % (row + 1, column + 1),
                (x, -0.266, z), (0.15, 0.022, 0.04), mat, 6,
                count, objects, bevel=0.001)
    return objects, (2.05, -2.70, 1.70), (0.0, 0.0, 0.49)


def make_bedroom_vanity(model_name="bedroom_vanity", colors=None):
    colors = colors or NORMAL_BEDROOM_PALETTES["burgundy"]
    mat = mansion_material(model_name, colors, roughness=0.76)
    count = len(colors)
    objects = []
    box("VanityTop", (0.0, 0.0, 0.76), (1.02, 0.48, 0.12), mat, 4,
        count, objects, bevel=0.006)
    box("VanityDrawer", (0.0, -0.185, 0.64), (0.64, 0.10, 0.20), mat, 2,
        count, objects, bevel=0.003)
    box("VanityHandle", (0.0, -0.247, 0.64), (0.17, 0.025, 0.04), mat, 5,
        count, objects, bevel=0.001)
    for x in (-0.42, 0.42):
        box("VanityLeg_%s" % ("L" if x < 0 else "R"), (x, 0.0, 0.36),
            (0.10, 0.36, 0.72), mat, 1, count, objects, bevel=0.003)
    box("VanityMirrorBack", (0.0, 0.15, 1.37), (0.66, 0.10, 0.88), mat, 2,
        count, objects, bevel=0.006)
    box("VanityMirrorGlass", (0.0, 0.092, 1.37), (0.52, 0.025, 0.72), mat, 7,
        count, objects, bevel=0.004)
    for x in (-0.36, 0.36):
        box("MirrorPost_%s" % ("L" if x < 0 else "R"), (x, 0.15, 1.23),
            (0.07, 0.09, 1.08), mat, 3, count, objects, bevel=0.002)
    box("VanityAccent", (0.0, 0.08, 1.78), (0.36, 0.05, 0.07), mat, 8,
        count, objects, bevel=0.001)
    return objects, (2.05, -2.70, 2.05), (0.0, 0.0, 0.88)


def make_vanity_stool(model_name="vanity_stool", colors=None):
    colors = colors or NORMAL_BEDROOM_PALETTES["burgundy"]
    mat = mansion_material(model_name, colors)
    count = len(colors)
    objects = []
    for x in (-0.15, 0.15):
        for y in (-0.13, 0.13):
            box("StoolLeg_%s_%s" % ("L" if x < 0 else "R",
                                     "F" if y < 0 else "B"),
                (x, y, 0.22), (0.065, 0.065, 0.44), mat, 1,
                count, objects, bevel=0.002)
    box("StoolSeat", (0.0, 0.0, 0.47), (0.40, 0.36, 0.12), mat, 4,
        count, objects, bevel=0.006)
    box("StoolCushion", (0.0, -0.01, 0.55), (0.34, 0.30, 0.08), mat, 5,
        count, objects, bevel=0.005)
    return objects, (1.25, -1.75, 1.05), (0.0, 0.0, 0.28)


def make_bedside_lamp(model_name="bedside_lamp", colors=None):
    colors = colors or NORMAL_BEDROOM_PALETTES["burgundy"]
    mat = mansion_material(model_name, colors, roughness=0.62, metallic=0.18)
    count = len(colors)
    objects = []
    box("LampBase", (0.0, 0.0, 0.055), (0.28, 0.24, 0.11), mat, 2,
        count, objects, bevel=0.003)
    box("LampStem", (0.0, 0.0, 0.28), (0.07, 0.07, 0.36), mat, 3,
        count, objects, bevel=0.002)
    box("LampShade", (0.0, 0.0, 0.52), (0.34, 0.30, 0.26), mat, 5,
        count, objects, bevel=0.005)
    box("ShadeBandTop", (0.0, 0.0, 0.64), (0.27, 0.23, 0.04), mat, 6,
        count, objects, bevel=0.001)
    box("ShadeBandBottom", (0.0, 0.0, 0.39), (0.36, 0.32, 0.04), mat, 6,
        count, objects, bevel=0.001)
    return objects, (1.15, -1.65, 1.10), (0.0, 0.0, 0.30)


def make_toy_chest(model_name="toy_chest", colors=None):
    colors = colors or NORMAL_BEDROOM_PALETTES["burgundy"]
    mat = mansion_material(model_name, colors)
    count = len(colors)
    objects = []
    box("ChestBody", (0.0, 0.0, 0.28), (0.78, 0.48, 0.48), mat, 2,
        count, objects, bevel=0.004)
    box("ChestLid", (0.0, 0.02, 0.56), (0.82, 0.52, 0.16), mat, 4,
        count, objects, bevel=0.005)
    for x in (-0.34, 0.34):
        box("ChestBand_%s" % ("L" if x < 0 else "R"), (x, -0.255, 0.36),
            (0.08, 0.025, 0.52), mat, 1, count, objects, bevel=0.001)
    box("ChestLatch", (0.0, -0.274, 0.42), (0.18, 0.035, 0.20), mat, 6,
        count, objects, bevel=0.002)
    box("ChestHeart", (0.0, -0.296, 0.43), (0.09, 0.012, 0.08), mat, 7,
        count, objects, bevel=0.001, rotation=(0.0, math.radians(45), 0.0))
    return objects, (1.55, -2.10, 1.25), (0.0, 0.0, 0.30)


def make_laundry_hamper(model_name="laundry_hamper", colors=None):
    colors = colors or NORMAL_BEDROOM_PALETTES["burgundy"]
    mat = mansion_material(model_name, colors)
    count = len(colors)
    objects = []
    box("HamperBody", (0.0, 0.0, 0.34), (0.48, 0.44, 0.64), mat, 4,
        count, objects, bevel=0.004)
    box("HamperInset", (0.0, -0.226, 0.35), (0.36, 0.025, 0.48), mat, 2,
        count, objects, bevel=0.002)
    for x in (-0.13, 0.0, 0.13):
        box("HamperWeaveV_%s" % str(x), (x, -0.244, 0.35),
            (0.035, 0.018, 0.50), mat, 5, count, objects, bevel=0.0)
    for z in (0.20, 0.34, 0.48):
        box("HamperWeaveH_%s" % str(z), (0.0, -0.247, z),
            (0.38, 0.018, 0.035), mat, 3, count, objects, bevel=0.0)
    box("HamperRim", (0.0, 0.0, 0.69), (0.54, 0.50, 0.09), mat, 6,
        count, objects, bevel=0.004)
    box("FoldedCloth", (0.10, -0.04, 0.76), (0.25, 0.30, 0.09), mat, 7,
        count, objects, bevel=0.003)
    return objects, (1.35, -1.90, 1.30), (0.0, 0.0, 0.38)


def make_bedroom_rug(model_name="bedroom_rug", colors=None):
    colors = colors or NORMAL_BEDROOM_PALETTES["burgundy"]
    mat = mansion_material(model_name, colors, roughness=0.96)
    count = len(colors)
    objects = []
    box("RugBase", (0.0, 0.0, 0.025), (1.72, 1.18, 0.05), mat, 1,
        count, objects, bevel=0.003)
    box("RugBorderOuter", (0.0, -0.001, 0.052), (1.58, 1.04, 0.014), mat, 5,
        count, objects, bevel=0.001)
    box("RugField", (0.0, -0.002, 0.062), (1.38, 0.84, 0.014), mat, 3,
        count, objects, bevel=0.001)
    box("RugCenter", (0.0, -0.003, 0.072), (0.78, 0.40, 0.014), mat, 6,
        count, objects, bevel=0.001)
    for x, y in ((-0.52, -0.26), (0.52, -0.26), (-0.52, 0.26), (0.52, 0.26)):
        box("RugDiamond_%s_%s" % (str(x), str(y)), (x, y, 0.082),
            (0.20, 0.20, 0.014), mat, 7, count, objects, bevel=0.0,
            rotation=(0.0, 0.0, math.radians(45)))
    return objects, (2.25, -2.75, 2.10), (0.0, 0.0, 0.0)


REGIONAL_FLOOR_PALETTES = {
    "corridor_teal": ["#090D10", "#182329", "#2B3B42", "#42616A",
                      "#317A7D", "#62B3AE", "#B7D7CE", "#DCE7DE"],
    "corridor_burgundy": ["#0E0A0B", "#25171A", "#422329", "#66323D",
                          "#8B3E50", "#C06A77", "#C7AE92", "#E4D6BF"],
    "hotel_burgundy": ["#100B0D", "#2D171E", "#542331", "#81384B",
                       "#AF536A", "#D08491", "#C9A96F", "#F0DEC1"],
    "hotel_navy": ["#080D13", "#152638", "#243E59", "#365D7E",
                    "#4F82A3", "#85B4C6", "#B99855", "#E8DFC9"],
    "hotel_ivory": ["#171411", "#42382D", "#70604D", "#A08B70",
                     "#C5B496", "#E2D8C4", "#8F7250", "#F4EFE4"],
    "apartment_olive": ["#0C0F0A", "#27301D", "#445331", "#667849",
                        "#8A9B64", "#B1BE8A", "#85664A", "#D8D0B8"],
    "apartment_charcoal": ["#090A0C", "#20242A", "#373D45", "#555D66",
                           "#78828A", "#A9B0B2", "#5A7777", "#DADBD3"],
    "apartment_rust": ["#100C0A", "#342019", "#5C3324", "#884B32",
                       "#B56B49", "#D79B70", "#5D7370", "#E2D5BD"],
    "beach_teal": ["#081316", "#17404A", "#287383", "#3FA6AF",
                   "#78D2CC", "#D7EEE2", "#BC8A4D", "#F0D47A"],
    "beach_sun": ["#151008", "#4A2D18", "#82502A", "#C27B38",
                  "#E7AF50", "#F2DB8A", "#3E8988", "#A9DDD0"],
}


def make_region_floor_dressing(model_name, style, colors):
    """A dedicated thin regional textile, never a bedroom-rug alias."""
    mat = mansion_material(model_name, colors, roughness=.97)
    count = len(colors)
    o = []
    dims = {
        "corridor": (2.40, 3.40),
        "hotel": (2.20, 1.40),
        "apartment": (2.00, 1.35),
        "beach": (1.40, .85),
    }[style]
    width, depth = dims
    box("TextileBase", (0, 0, .018), (width, depth, .036), mat, 1,
        count, o, bevel=.010)

    if style == "corridor":
        box("RunnerField", (0, 0, .041), (width - .16, depth - .16, .018),
            mat, 3, count, o, bevel=.006)
        for x in (-width * .5 + .14, width * .5 - .14):
            box("LongBorder_%s" % x, (x, 0, .055), (.12, depth - .22, .012),
                mat, 5, count, o)
        for index, y in enumerate((-1.18, -.59, 0, .59, 1.18)):
            box("RunnerDiamond_%d" % index, (0, y, .059), (.42, .42, .014),
                mat, 6 if index % 2 else 4, count, o,
                rotation=(0, 0, math.radians(45)))
        for y in (-depth * .5 + .14, depth * .5 - .14):
            box("EndBand_%s" % y, (0, y, .057), (width - .24, .12, .012),
                mat, 7, count, o)
    elif style == "hotel":
        box("HotelField", (0, 0, .041), (width - .14, depth - .14, .018),
            mat, 4, count, o, bevel=.008)
        for axis, offset, size in (
                ("L", -width * .5 + .12, (.10, depth - .18, .012)),
                ("R", width * .5 - .12, (.10, depth - .18, .012)),
                ("F", -depth * .5 + .12, (width - .18, .10, .012)),
                ("B", depth * .5 - .12, (width - .18, .10, .012))):
            at = (offset, 0, .056) if axis in ("L", "R") else (0, offset, .056)
            box("HotelBorder%s" % axis, at, size, mat, 6, count, o)
        box("HotelMedallion", (0, 0, .061), (.58, .58, .014), mat, 2,
            count, o, rotation=(0, 0, math.radians(45)))
        for index, x in enumerate((-.68, .68)):
            box("HotelCornerMark_%d" % index, (x, 0, .061), (.22, .22, .014),
                mat, 7, count, o, rotation=(0, 0, math.radians(45)))
    elif style == "apartment":
        box("WovenField", (0, 0, .040), (width - .12, depth - .12, .016),
            mat, 2, count, o, bevel=.006)
        for index, y in enumerate((-.48, -.24, 0, .24, .48)):
            box("WovenBand_%d" % index, (0, y, .054),
                (width - .16, .13, .012), mat, 4 + index % 3, count, o)
        for side, y in (("F", -depth * .5 - .035), ("B", depth * .5 + .035)):
            for fringe in range(-5, 6):
                box("Fringe%s_%d" % (side, fringe),
                    (fringe * .15, y, .040), (.07, .12, .025), mat, 7,
                    count, o, bevel=.002)
    else:
        # Woven beach mats read as portable slatted textiles rather than a
        # resized bathroom mat. Alternating bands remain clear at mid-distance.
        for index in range(8):
            y = -depth * .5 + .075 + index * ((depth - .15) / 7.0)
            box("BeachSlat_%d" % index, (0, y, .044),
                (width - .08, .075, .018), mat, 3 + index % 3, count, o,
                bevel=.005)
        for x in (-width * .5 + .10, width * .5 - .10):
            box("BeachEdge_%s" % x, (x, 0, .058), (.08, depth - .08, .014),
                mat, 6, count, o, bevel=.003)
        for y in (-depth * .5 + .10, depth * .5 - .10):
            box("BeachTie_%s" % y, (0, y, .061), (width - .12, .055, .012),
                mat, 7, count, o)
    return o, (max(width, 2.0), -max(depth, 2.6), 2.0), (0, 0, 0)


def make_bedroom_wall_clock(model_name="bedroom_wall_clock", colors=None):
    colors = colors or NORMAL_BEDROOM_PALETTES["burgundy"]
    mat = mansion_material(model_name, colors, roughness=0.72,
                           metallic=0.10)
    count = len(colors)
    objects = []
    box("ClockBack", (0.0, 0.0, 1.40), (0.52, 0.12, 0.62), mat, 1,
        count, objects, bevel=0.006)
    box("ClockFace", (0.0, -0.071, 1.45), (0.40, 0.025, 0.40), mat, 5,
        count, objects, bevel=0.004)
    for x, z, width, height in ((0.0, 1.65, 0.04, 0.07),
                                (0.0, 1.25, 0.04, 0.07),
                                (-0.20, 1.45, 0.07, 0.04),
                                (0.20, 1.45, 0.07, 0.04)):
        box("ClockMarker_%s_%s" % (str(x), str(z)), (x, -0.088, z),
            (width, 0.012, height), mat, 7, count, objects, bevel=0.0)
    box("ClockHandHour", (-0.055, -0.096, 1.49), (0.13, 0.012, 0.025), mat, 6,
        count, objects, bevel=0.0, rotation=(0.0, math.radians(22), 0.0))
    box("ClockHandMinute", (0.035, -0.099, 1.54), (0.025, 0.012, 0.19), mat, 6,
        count, objects, bevel=0.0, rotation=(0.0, math.radians(-12), 0.0))
    box("ClockPendulumCase", (0.0, 0.0, 1.02), (0.34, 0.11, 0.34), mat, 2,
        count, objects, bevel=0.004)
    box("ClockPendulum", (0.0, -0.068, 1.04), (0.08, 0.025, 0.24), mat, 7,
        count, objects, bevel=0.002)
    return objects, (1.45, -2.05, 1.70), (0.0, 0.0, 1.35)


def make_bedroom_bench(model_name="bedroom_bench", colors=None):
    colors = colors or NORMAL_BEDROOM_PALETTES["burgundy"]
    mat = mansion_material(model_name, colors)
    count = len(colors)
    objects = []
    for x in (-0.42, 0.42):
        for y in (-0.14, 0.14):
            box("BenchLeg_%s_%s" % ("L" if x < 0 else "R",
                                     "F" if y < 0 else "B"),
                (x, y, 0.22), (0.08, 0.08, 0.44), mat, 1,
                count, objects, bevel=0.002)
    box("BenchFrame", (0.0, 0.0, 0.42), (1.02, 0.38, 0.18), mat, 2,
        count, objects, bevel=0.004)
    box("BenchCushion", (0.0, -0.01, 0.56), (0.94, 0.34, 0.18), mat, 5,
        count, objects, bevel=0.006)
    for x in (-0.30, 0.0, 0.30):
        box("BenchTuft_%s" % str(x), (x, -0.185, 0.57),
            (0.045, 0.018, 0.045), mat, 7, count, objects, bevel=0.001)
    return objects, (1.75, -2.35, 1.25), (0.0, 0.0, 0.30)


def gothic_arch(prefix, center, width, height, depth, thickness, mat, region,
                count, objects):
    """Two crisp diagonal beams form a low-poly pointed Gothic arch."""
    x, y, z = center
    half_width = width * 0.5
    half_height = height * 0.5
    length = math.sqrt(half_width * half_width + half_height * half_height)
    angle = math.degrees(math.atan2(half_height, half_width))
    box(prefix + "Left", (x - width * 0.25, y, z + height * 0.25),
        (length, depth, thickness), mat, region, count, objects, bevel=0.001,
        rotation=(0.0, math.radians(-angle), 0.0))
    box(prefix + "Right", (x + width * 0.25, y, z + height * 0.25),
        (length, depth, thickness), mat, region, count, objects, bevel=0.001,
        rotation=(0.0, math.radians(angle), 0.0))


def make_gothic_bed(model_name, colors):
    mat = mansion_material(model_name, colors, roughness=0.80, metallic=0.08)
    count = len(colors)
    objects = []
    width = 1.86
    box("GothicBedFrame", (0.0, 0.0, 0.31), (width, 2.64, 0.38), mat, 2,
        count, objects, bevel=0.003)
    box("GothicMattress", (0.0, -0.03, 0.55), (1.68, 2.42, 0.24), mat, 6,
        count, objects, bevel=0.004)
    box("GothicBlanket", (0.0, -0.42, 0.69), (1.64, 1.50, 0.08), mat, 5,
        count, objects, bevel=0.003)
    for index, x in enumerate((-0.43, 0.43)):
        box("GothicPillow_%d" % (index + 1), (x, 0.88, 0.71),
            (0.68, 0.46, 0.15), mat, 5 if index == 0 else 4,
            count, objects, bevel=0.005)
        box("PillowTrim_%d" % (index + 1), (x, 0.665, 0.73),
            (0.52, 0.026, 0.045), mat, 7, count, objects, bevel=0.0)
    box("TallHeadboard", (0.0, 1.27, 1.18), (1.76, 0.16, 1.50), mat, 1,
        count, objects, bevel=0.003)
    box("HeadboardVelvet", (0.0, 1.175, 1.14), (1.40, 0.025, 0.88), mat, 4,
        count, objects, bevel=0.002)
    gothic_arch("HeadboardArch", (0.0, 1.15, 1.55), 1.40, 0.72, 0.05,
                0.095, mat, 3, count, objects)
    box("HeadboardSpire", (0.0, 1.15, 2.02), (0.13, 0.05, 0.28), mat, 7,
        count, objects, bevel=0.001, rotation=(0.0, math.radians(45), 0.0))
    for side, x in (("L", -0.87), ("R", 0.87)):
        box("HeadPost%s" % side, (x, 1.26, 1.10), (0.13, 0.16, 2.20), mat, 0,
            count, objects, bevel=0.002)
        box("FootPost%s" % side, (x, -1.26, 1.10), (0.13, 0.16, 2.20), mat, 0,
            count, objects, bevel=0.002)
        for end, y in (("Head", 1.26), ("Foot", -1.26)):
            box("%s%sFinial" % (end, side), (x, y, 2.27),
                (0.18, 0.18, 0.18), mat, 7, count, objects, bevel=0.001,
                rotation=(0.0, math.radians(45), 0.0))
    box("CanopyHeadRail", (0.0, 1.26, 2.12), (1.86, 0.10, 0.10), mat, 1,
        count, objects, bevel=0.001)
    box("CanopyFootRail", (0.0, -1.26, 2.12), (1.86, 0.10, 0.10), mat, 1,
        count, objects, bevel=0.001)
    for side, x in (("L", -0.87), ("R", 0.87)):
        box("CanopySide%s" % side, (x, 0.0, 2.12), (0.10, 2.52, 0.10), mat, 1,
            count, objects, bevel=0.001)
    box("GothicFootboard", (0.0, -1.28, 0.52), (1.76, 0.14, 0.62), mat, 1,
        count, objects, bevel=0.003)
    gothic_arch("FootboardArch", (0.0, -1.365, 0.53), 1.24, 0.46, 0.035,
                0.075, mat, 3, count, objects)
    return objects, (3.15, -4.10, 2.65), (0.0, 0.0, 1.05)


def make_gothic_nightstand(model_name, colors):
    mat = mansion_material(model_name, colors, roughness=0.82, metallic=0.06)
    count = len(colors)
    objects = []
    box("NightstandBody", (0.0, 0.0, 0.37), (0.58, 0.47, 0.66), mat, 2,
        count, objects, bevel=0.003)
    box("NightstandTop", (0.0, -0.01, 0.74), (0.66, 0.54, 0.10), mat, 3,
        count, objects, bevel=0.003)
    box("PointedDoor", (0.0, -0.245, 0.37), (0.43, 0.025, 0.48), mat, 1,
        count, objects, bevel=0.001)
    gothic_arch("DoorArch", (0.0, -0.265, 0.47), 0.34, 0.25, 0.014,
                0.045, mat, 7, count, objects)
    box("DoorPull", (0.12, -0.28, 0.33), (0.045, 0.025, 0.08), mat, 7,
        count, objects, bevel=0.001)
    for x in (-0.24, 0.24):
        box("ClawFoot%s" % str(x), (x, -0.02, 0.055), (0.10, 0.35, 0.11),
            mat, 0, count, objects, bevel=0.001)
    return objects, (1.50, -2.10, 1.38), (0.0, 0.0, 0.38)


def make_gothic_wardrobe(model_name, colors):
    mat = mansion_material(model_name, colors, roughness=0.82, metallic=0.07)
    count = len(colors)
    objects = []
    box("WardrobeBody", (0.0, 0.04, 1.10), (1.18, 0.58, 2.10), mat, 2,
        count, objects, bevel=0.004)
    box("WardrobePlinth", (0.0, 0.02, 0.10), (1.28, 0.64, 0.20), mat, 0,
        count, objects, bevel=0.002)
    box("WardrobeCrown", (0.0, 0.02, 2.18), (1.32, 0.66, 0.16), mat, 3,
        count, objects, bevel=0.003)
    for index, x in enumerate((-0.30, 0.30)):
        box("WardrobeDoor_%d" % (index + 1), (x, -0.267, 1.14),
            (0.52, 0.025, 1.72), mat, 1, count, objects, bevel=0.002)
        gothic_arch("WardrobeArch_%d" % (index + 1),
                    (x, -0.286, 1.63), 0.39, 0.42, 0.012, 0.052,
                    mat, 3, count, objects)
        box("WardrobeHandle_%d" % (index + 1),
            (-0.07 if x < 0 else 0.07, -0.292, 1.12),
            (0.045, 0.025, 0.22), mat, 7, count, objects, bevel=0.001)
    for x in (-0.52, 0.0, 0.52):
        box("CrownSpire%s" % str(x), (x, 0.0, 2.36),
            (0.14, 0.14, 0.25), mat, 0 if x else 7, count, objects,
            bevel=0.001, rotation=(0.0, math.radians(45), 0.0))
    return objects, (2.55, -3.40, 2.65), (0.0, 0.0, 1.14)


def make_gothic_dresser(model_name, colors):
    mat = mansion_material(model_name, colors, roughness=0.82, metallic=0.06)
    count = len(colors)
    objects = []
    box("DresserBody", (0.0, 0.02, 0.52), (1.26, 0.54, 0.92), mat, 2,
        count, objects, bevel=0.003)
    box("DresserTop", (0.0, 0.0, 1.03), (1.36, 0.61, 0.13), mat, 3,
        count, objects, bevel=0.003)
    box("DresserPlinth", (0.0, 0.02, 0.09), (1.32, 0.58, 0.18), mat, 0,
        count, objects, bevel=0.002)
    for row, z in enumerate((0.80, 0.53, 0.26)):
        for column, x in enumerate((-0.31, 0.31)):
            box("Drawer_%d_%d" % (row, column), (x, -0.266, z),
                (0.53, 0.025, 0.21), mat, 1, count, objects, bevel=0.001)
            box("DrawerDiamond_%d_%d" % (row, column), (x, -0.285, z),
                (0.11, 0.016, 0.11), mat, 4, count, objects, bevel=0.0,
                rotation=(0.0, math.radians(45), 0.0))
            box("DrawerPull_%d_%d" % (row, column), (x, -0.299, z),
                (0.045, 0.018, 0.045), mat, 7, count, objects, bevel=0.001)
    return objects, (2.20, -2.95, 1.82), (0.0, 0.0, 0.52)


def make_gothic_vanity(model_name, colors):
    mat = mansion_material(model_name, colors, roughness=0.76, metallic=0.08)
    count = len(colors)
    objects = []
    box("VanityTop", (0.0, 0.0, 0.78), (1.10, 0.50, 0.13), mat, 3,
        count, objects, bevel=0.003)
    box("VanityDrawer", (0.0, -0.19, 0.65), (0.70, 0.10, 0.21), mat, 2,
        count, objects, bevel=0.002)
    box("VanityPull", (0.0, -0.252, 0.65), (0.18, 0.025, 0.045), mat, 7,
        count, objects, bevel=0.001)
    for x in (-0.46, 0.46):
        box("VanityLeg%s" % str(x), (x, 0.0, 0.37), (0.10, 0.38, 0.74),
            mat, 0, count, objects, bevel=0.002)
    box("MirrorBack", (0.0, 0.17, 1.43), (0.72, 0.11, 0.92), mat, 1,
        count, objects, bevel=0.003)
    box("MirrorGlass", (0.0, 0.105, 1.39), (0.55, 0.025, 0.64), mat, 6,
        count, objects, bevel=0.002)
    gothic_arch("MirrorArch", (0.0, 0.09, 1.69), 0.55, 0.48, 0.025,
                0.070, mat, 3, count, objects)
    box("MirrorSpire", (0.0, 0.09, 1.99), (0.11, 0.05, 0.21), mat, 7,
        count, objects, bevel=0.001, rotation=(0.0, math.radians(45), 0.0))
    return objects, (2.20, -2.90, 2.25), (0.0, 0.0, 0.96)


def make_gothic_stool(model_name, colors):
    mat = mansion_material(model_name, colors)
    count = len(colors)
    objects = []
    for x in (-0.16, 0.16):
        for y in (-0.14, 0.14):
            box("StoolLeg%s%s" % (str(x), str(y)), (x, y, 0.23),
                (0.07, 0.07, 0.46), mat, 0, count, objects, bevel=0.001)
    box("StoolFrame", (0.0, 0.0, 0.46), (0.44, 0.38, 0.10), mat, 2,
        count, objects, bevel=0.002)
    box("VelvetCushion", (0.0, -0.01, 0.55), (0.38, 0.32, 0.10), mat, 5,
        count, objects, bevel=0.004)
    box("CushionTuft", (0.0, -0.18, 0.56), (0.05, 0.015, 0.05), mat, 7,
        count, objects, bevel=0.001)
    return objects, (1.30, -1.80, 1.08), (0.0, 0.0, 0.28)


def make_gothic_bench(model_name, colors):
    mat = mansion_material(model_name, colors)
    count = len(colors)
    objects = []
    for x in (-0.45, 0.45):
        for y in (-0.15, 0.15):
            box("BenchLeg%s%s" % (str(x), str(y)), (x, y, 0.23),
                (0.08, 0.08, 0.46), mat, 0, count, objects, bevel=0.001)
    box("BenchFrame", (0.0, 0.0, 0.44), (1.10, 0.42, 0.18), mat, 2,
        count, objects, bevel=0.002)
    box("VelvetCushion", (0.0, -0.01, 0.58), (1.01, 0.37, 0.18), mat, 5,
        count, objects, bevel=0.004)
    for x in (-0.33, 0.0, 0.33):
        box("BenchTuft%s" % str(x), (x, -0.202, 0.59),
            (0.05, 0.016, 0.05), mat, 7, count, objects, bevel=0.001)
    for x in (-0.51, 0.51):
        box("BenchFinial%s" % str(x), (x, 0.0, 0.58),
            (0.12, 0.12, 0.12), mat, 3, count, objects, bevel=0.001,
            rotation=(0.0, math.radians(45), 0.0))
    return objects, (1.85, -2.45, 1.30), (0.0, 0.0, 0.31)


def make_gothic_rug(model_name, colors):
    mat = mansion_material(model_name, colors, roughness=0.97)
    count = len(colors)
    objects = []
    box("RugBase", (0.0, 0.0, 0.025), (2.20, 1.42, 0.05), mat, 0,
        count, objects, bevel=0.002)
    box("RugBorder", (0.0, -0.001, 0.052), (2.03, 1.25, 0.014), mat, 7,
        count, objects, bevel=0.001)
    box("RugField", (0.0, -0.002, 0.062), (1.82, 1.04, 0.014), mat, 4,
        count, objects, bevel=0.001)
    for x in (-0.65, 0.0, 0.65):
        box("GothicDiamond%s" % str(x), (x, 0.0, 0.078),
            (0.34, 0.34, 0.014), mat, 5 if x else 6, count, objects,
            bevel=0.0, rotation=(0.0, 0.0, math.radians(45)))
    for x in (-0.92, 0.92):
        box("RugCrossV%s" % str(x), (x, 0.0, 0.080),
            (0.07, 0.55, 0.014), mat, 3, count, objects, bevel=0.0)
        box("RugCrossH%s" % str(x), (x, 0.0, 0.081),
            (0.30, 0.07, 0.014), mat, 3, count, objects, bevel=0.0)
    return objects, (2.65, -3.25, 2.45), (0.0, 0.0, 0.0)


def make_gothic_bedside_candelabra(model_name, colors):
    mat = mansion_material(model_name, colors, roughness=0.50, metallic=0.32)
    count = len(colors)
    objects = []
    box("CandelabraBase", (0.0, 0.0, 0.045), (0.28, 0.22, 0.09), mat, 0,
        count, objects, bevel=0.002)
    box("CandelabraStem", (0.0, 0.0, 0.28), (0.06, 0.06, 0.42), mat, 7,
        count, objects, bevel=0.001)
    for index, x in enumerate((-0.18, 0.0, 0.18)):
        if x:
            box("CandleArm_%d" % index, (x * 0.5, 0.0, 0.41),
                (abs(x) + 0.04, 0.045, 0.045), mat, 7, count, objects,
                bevel=0.001, rotation=(0.0, math.radians(-12 if x < 0 else 12), 0.0))
        box("Candle_%d" % index, (x, 0.0, 0.57), (0.07, 0.07, 0.28), mat, 6,
            count, objects, bevel=0.001)
        box("Flame_%d" % index, (x, 0.0, 0.76), (0.055, 0.055, 0.09), mat, 8,
            count, objects, bevel=0.001, rotation=(0.0, math.radians(45), 0.0))
    return objects, (1.25, -1.75, 1.15), (0.0, 0.0, 0.36)


def make_mansion_console_table():
    colors = NORMAL_BEDROOM_PALETTES["burgundy"]
    mat = mansion_material("mansion_console_table", colors)
    count = len(colors)
    objects = []
    box("ConsoleTop", (0.0, 0.0, 0.84), (1.22, 0.42, 0.13), mat, 3,
        count, objects, bevel=0.004)
    box("ConsoleApron", (0.0, 0.02, 0.70), (1.04, 0.30, 0.18), mat, 2,
        count, objects, bevel=0.002)
    for x in (-0.49, 0.49):
        box("ConsoleLeg%s" % str(x), (x, 0.02, 0.38),
            (0.10, 0.24, 0.76), mat, 1, count, objects, bevel=0.002)
    box("ConsoleDrawer", (0.0, -0.202, 0.72), (0.48, 0.025, 0.13), mat, 4,
        count, objects, bevel=0.001)
    box("ConsolePull", (0.0, -0.222, 0.72), (0.14, 0.020, 0.04), mat, 8,
        count, objects, bevel=0.001)
    return objects, (2.05, -2.70, 1.55), (0.0, 0.0, 0.45)


def make_mansion_grandfather_clock():
    colors = NORMAL_BEDROOM_PALETTES["charcoal"]
    mat = mansion_material("mansion_grandfather_clock", colors, metallic=0.10)
    count = len(colors)
    objects = []
    box("ClockCase", (0.0, 0.02, 1.02), (0.58, 0.38, 1.92), mat, 2,
        count, objects, bevel=0.004)
    box("ClockCrown", (0.0, 0.0, 2.04), (0.70, 0.45, 0.18), mat, 3,
        count, objects, bevel=0.004)
    box("ClockFace", (0.0, -0.193, 1.65), (0.42, 0.025, 0.42), mat, 7,
        count, objects, bevel=0.003)
    box("HourHand", (-0.05, -0.213, 1.67), (0.14, 0.015, 0.025), mat, 0,
        count, objects, bevel=0.0, rotation=(0.0, math.radians(18), 0.0))
    box("MinuteHand", (0.03, -0.214, 1.72), (0.025, 0.015, 0.20), mat, 0,
        count, objects, bevel=0.0, rotation=(0.0, math.radians(-10), 0.0))
    box("PendulumWindow", (0.0, -0.194, 0.77), (0.34, 0.025, 0.66), mat, 6,
        count, objects, bevel=0.002)
    box("PendulumRod", (0.0, -0.213, 0.83), (0.04, 0.015, 0.43), mat, 8,
        count, objects, bevel=0.0)
    box("PendulumBob", (0.0, -0.216, 0.60), (0.16, 0.015, 0.16), mat, 8,
        count, objects, bevel=0.002, rotation=(0.0, math.radians(45), 0.0))
    return objects, (1.70, -2.35, 2.35), (0.0, 0.0, 1.08)


def make_mansion_coat_rack():
    colors = NORMAL_BEDROOM_PALETTES["burgundy"]
    mat = mansion_material("mansion_coat_rack", colors)
    count = len(colors)
    objects = []
    box("RackBase", (0.0, 0.0, 0.06), (0.52, 0.52, 0.12), mat, 1,
        count, objects, bevel=0.003)
    box("RackPost", (0.0, 0.0, 0.91), (0.12, 0.12, 1.70), mat, 2,
        count, objects, bevel=0.002)
    box("RackCrown", (0.0, 0.0, 1.82), (0.20, 0.20, 0.20), mat, 8,
        count, objects, bevel=0.001, rotation=(0.0, math.radians(45), 0.0))
    for index, angle in enumerate((0, 90, 180, 270)):
        radians = math.radians(angle)
        x, y = math.cos(radians) * 0.20, math.sin(radians) * 0.20
        box("CoatHook_%d" % index, (x * 0.5, y * 0.5, 1.60),
            (0.42 if angle % 180 == 0 else 0.08,
             0.42 if angle % 180 else 0.08, 0.07), mat, 3, count, objects,
            bevel=0.001)
    return objects, (1.45, -2.05, 2.05), (0.0, 0.0, 0.90)


def make_mansion_tea_cart():
    colors = NORMAL_BEDROOM_PALETTES["ivory"]
    mat = mansion_material("mansion_tea_cart", colors, metallic=0.08)
    count = len(colors)
    objects = []
    for z in (0.34, 0.76):
        box("CartShelf%s" % str(z), (0.0, 0.0, z), (1.05, 0.48, 0.10), mat, 3,
            count, objects, bevel=0.003)
    for x in (-0.46, 0.46):
        for y in (-0.19, 0.19):
            box("CartPost%s%s" % (str(x), str(y)), (x, y, 0.50),
                (0.07, 0.07, 0.86), mat, 1, count, objects, bevel=0.001)
    box("CartHandle", (0.0, 0.25, 0.92), (1.05, 0.07, 0.07), mat, 8,
        count, objects, bevel=0.001)
    for x in (-0.44, 0.44):
        box("CartWheel%s" % str(x), (x, 0.0, 0.13), (0.18, 0.10, 0.18), mat, 0,
            count, objects, bevel=0.002, rotation=(0.0, math.radians(45), 0.0))
    box("TeaPot", (0.15, -0.03, 0.89), (0.24, 0.20, 0.20), mat, 6,
        count, objects, bevel=0.004)
    box("TeaPotLid", (0.15, -0.03, 1.01), (0.12, 0.10, 0.05), mat, 8,
        count, objects, bevel=0.001)
    for x in (-0.22, -0.04):
        box("TeaCup%s" % str(x), (x, -0.05, 0.86), (0.12, 0.12, 0.13), mat, 7,
            count, objects, bevel=0.002)
    return objects, (1.90, -2.55, 1.45), (0.0, 0.0, 0.50)


def make_mansion_rocking_chair():
    colors = NORMAL_BEDROOM_PALETTES["olive"]
    mat = mansion_material("mansion_rocking_chair", colors)
    count = len(colors)
    objects = []
    box("Seat", (0.0, -0.02, 0.52), (0.62, 0.58, 0.14), mat, 3,
        count, objects, bevel=0.004)
    box("SeatCushion", (0.0, -0.04, 0.62), (0.54, 0.49, 0.12), mat, 5,
        count, objects, bevel=0.004)
    box("ChairBack", (0.0, 0.25, 1.08), (0.60, 0.13, 0.94), mat, 2,
        count, objects, bevel=0.003, rotation=(math.radians(-7), 0.0, 0.0))
    for x in (-0.25, 0.25):
        box("BackSlat%s" % str(x), (x, 0.17, 1.10), (0.07, 0.08, 0.78), mat, 6,
            count, objects, bevel=0.001)
        box("Arm%s" % str(x), (x, -0.03, 0.83), (0.09, 0.55, 0.09), mat, 3,
            count, objects, bevel=0.002)
        box("Leg%s" % str(x), (x, 0.0, 0.31), (0.08, 0.42, 0.55), mat, 1,
            count, objects, bevel=0.001)
        box("Rocker%s" % str(x), (x, 0.0, 0.07), (0.10, 0.94, 0.10), mat, 1,
            count, objects, bevel=0.004)
    return objects, (1.75, -2.35, 1.65), (0.0, 0.0, 0.72)


def make_mansion_room_divider():
    colors = NORMAL_BEDROOM_PALETTES["violet"]
    mat = mansion_material("mansion_room_divider", colors)
    count = len(colors)
    objects = []
    for index, x in enumerate((-0.72, -0.24, 0.24, 0.72)):
        angle = math.radians(8 if index % 2 else -8)
        box("DividerPanel_%d" % index, (x, 0.0, 1.02),
            (0.44, 0.10, 1.92), mat, 2, count, objects, bevel=0.003,
            rotation=(0.0, 0.0, angle))
        box("DividerInset_%d" % index, (x, -0.061, 1.08),
            (0.32, 0.025, 1.48), mat, 5, count, objects, bevel=0.002,
            rotation=(0.0, 0.0, angle))
        for z in (0.42, 1.72):
            box("DividerBand_%d_%s" % (index, str(z)), (x, -0.078, z),
                (0.34, 0.016, 0.07), mat, 7, count, objects, bevel=0.0,
                rotation=(0.0, 0.0, angle))
    return objects, (2.55, -3.35, 2.35), (0.0, 0.0, 1.04)


def make_gothic_highback_chair(model_name, colors):
    mat = mansion_material(model_name, colors)
    count = len(colors)
    objects = []
    box("ChairSeat", (0.0, 0.0, 0.56), (0.66, 0.60, 0.16), mat, 2,
        count, objects, bevel=0.003)
    box("VelvetSeat", (0.0, -0.04, 0.67), (0.55, 0.49, 0.13), mat, 5,
        count, objects, bevel=0.004)
    box("TallBack", (0.0, 0.27, 1.22), (0.68, 0.16, 1.20), mat, 1,
        count, objects, bevel=0.003)
    box("VelvetBack", (0.0, 0.175, 1.23), (0.52, 0.025, 0.82), mat, 4,
        count, objects, bevel=0.003)
    gothic_arch("ChairArch", (0.0, 0.15, 1.66), 0.52, 0.38, 0.025,
                0.065, mat, 3, count, objects)
    for x in (-0.30, 0.30):
        box("ChairArm%s" % str(x), (x, -0.02, 0.88),
            (0.10, 0.56, 0.10), mat, 3, count, objects, bevel=0.002)
        box("ChairLeg%s" % str(x), (x, 0.0, 0.29),
            (0.09, 0.46, 0.58), mat, 0, count, objects, bevel=0.001)
    box("ChairCrest", (0.0, 0.15, 1.98), (0.14, 0.08, 0.23), mat, 7,
        count, objects, bevel=0.001, rotation=(0.0, math.radians(45), 0.0))
    return objects, (1.85, -2.50, 2.05), (0.0, 0.0, 0.95)


def make_gothic_writing_desk():
    colors = GOTHIC_BEDROOM_PALETTES["crimson"]
    mat = mansion_material("gothic_writing_desk", colors)
    count = len(colors)
    objects = []
    box("DeskTop", (0.0, 0.0, 0.80), (1.38, 0.62, 0.14), mat, 3,
        count, objects, bevel=0.003)
    box("DeskApron", (0.0, 0.10, 0.66), (1.22, 0.30, 0.18), mat, 2,
        count, objects, bevel=0.002)
    for x in (-0.58, 0.58):
        box("DeskLeg%s" % str(x), (x, 0.10, 0.37),
            (0.11, 0.40, 0.74), mat, 0, count, objects, bevel=0.001)
    for x in (-0.38, 0.0, 0.38):
        box("DeskDrawer%s" % str(x), (x, -0.316, 0.69),
            (0.32, 0.025, 0.16), mat, 1, count, objects, bevel=0.001)
        box("DeskPull%s" % str(x), (x, -0.335, 0.69),
            (0.05, 0.016, 0.05), mat, 7, count, objects, bevel=0.001)
    gothic_arch("DeskApronArch", (0.0, -0.20, 0.49), 0.72, 0.34, 0.04,
                0.06, mat, 3, count, objects)
    return objects, (2.30, -3.05, 1.55), (0.0, 0.0, 0.45)


def make_gothic_bookcase():
    colors = GOTHIC_BEDROOM_PALETTES["violet"]
    mat = mansion_material("gothic_bookcase", colors)
    count = len(colors)
    objects = []
    box("BookcaseBack", (0.0, 0.16, 1.08), (1.14, 0.18, 2.08), mat, 1,
        count, objects, bevel=0.003)
    for x in (-0.54, 0.54):
        box("BookcasePost%s" % str(x), (x, 0.0, 1.10),
            (0.12, 0.46, 2.20), mat, 0, count, objects, bevel=0.002)
        box("BookcaseSpire%s" % str(x), (x, 0.0, 2.32),
            (0.16, 0.16, 0.24), mat, 7, count, objects, bevel=0.001,
            rotation=(0.0, math.radians(45), 0.0))
    for index, z in enumerate((0.22, 0.68, 1.14, 1.60, 2.06)):
        box("BookcaseShelf_%d" % index, (0.0, 0.0, z),
            (1.10, 0.46, 0.10), mat, 3, count, objects, bevel=0.002)
    book_colors = (4, 5, 6, 7)
    for row, z in enumerate((0.43, 0.89, 1.35, 1.81)):
        for column, x in enumerate((-0.38, -0.13, 0.12, 0.37)):
            box("Book_%d_%d" % (row, column), (x, -0.08, z),
                (0.18, 0.25, 0.32 + 0.03 * ((row + column) % 2)), mat,
                book_colors[(row + column) % len(book_colors)], count, objects,
                bevel=0.001)
    gothic_arch("BookcaseCrownArch", (0.0, -0.11, 2.05), 0.76, 0.42, 0.05,
                0.07, mat, 3, count, objects)
    return objects, (2.45, -3.30, 2.65), (0.0, 0.0, 1.12)


def make_gothic_pedestal_table():
    colors = GOTHIC_BEDROOM_PALETTES["forest"]
    mat = mansion_material("gothic_pedestal_table", colors)
    count = len(colors)
    objects = []
    box("PedestalBase", (0.0, 0.0, 0.07), (0.58, 0.58, 0.14), mat, 0,
        count, objects, bevel=0.002)
    box("PedestalStem", (0.0, 0.0, 0.43), (0.18, 0.18, 0.68), mat, 2,
        count, objects, bevel=0.002)
    box("PedestalCollar", (0.0, 0.0, 0.72), (0.34, 0.34, 0.12), mat, 3,
        count, objects, bevel=0.002, rotation=(0.0, 0.0, math.radians(45)))
    box("PedestalTop", (0.0, 0.0, 0.83), (0.76, 0.76, 0.14), mat, 1,
        count, objects, bevel=0.003)
    box("TopInlay", (0.0, 0.0, 0.91), (0.46, 0.46, 0.025), mat, 5,
        count, objects, bevel=0.001, rotation=(0.0, 0.0, math.radians(45)))
    return objects, (1.55, -2.10, 1.45), (0.0, 0.0, 0.45)


def make_gothic_floor_candelabra():
    colors = GOTHIC_BEDROOM_PALETTES["ivory"]
    mat = mansion_material("gothic_floor_candelabra", colors, metallic=0.34)
    count = len(colors)
    objects = []
    box("CandelabraBase", (0.0, 0.0, 0.07), (0.52, 0.44, 0.14), mat, 0,
        count, objects, bevel=0.002)
    box("CandelabraStem", (0.0, 0.0, 0.82), (0.09, 0.09, 1.46), mat, 7,
        count, objects, bevel=0.001)
    for index, x in enumerate((-0.34, -0.17, 0.0, 0.17, 0.34)):
        if x:
            box("CandelabraArm_%d" % index, (x * 0.5, 0.0, 1.35 - abs(x) * 0.25),
                (abs(x) + 0.05, 0.055, 0.055), mat, 7, count, objects,
                bevel=0.001, rotation=(0.0, math.radians(-12 if x < 0 else 12), 0.0))
        candle_z = 1.55 - abs(x) * 0.18
        box("FloorCandle_%d" % index, (x, 0.0, candle_z),
            (0.08, 0.08, 0.28), mat, 6, count, objects, bevel=0.001)
        box("FloorFlame_%d" % index, (x, 0.0, candle_z + 0.19),
            (0.055, 0.055, 0.09), mat, 8, count, objects, bevel=0.001,
            rotation=(0.0, math.radians(45), 0.0))
    return objects, (1.55, -2.15, 2.00), (0.0, 0.0, 0.86)


def make_gothic_coffin_chest():
    colors = GOTHIC_BEDROOM_PALETTES["crimson"]
    mat = mansion_material("gothic_coffin_chest", colors)
    count = len(colors)
    objects = []
    box("CoffinChestBody", (0.0, 0.0, 0.30), (0.98, 0.50, 0.52), mat, 2,
        count, objects, bevel=0.002)
    box("CoffinLid", (0.0, 0.0, 0.60), (1.03, 0.55, 0.14), mat, 1,
        count, objects, bevel=0.002)
    for x in (-0.39, 0.39):
        box("CoffinCorner%s" % str(x), (x, -0.275, 0.35),
            (0.10, 0.025, 0.52), mat, 0, count, objects, bevel=0.001)
    box("CoffinCrossV", (0.0, -0.296, 0.39), (0.09, 0.014, 0.34), mat, 7,
        count, objects, bevel=0.0)
    box("CoffinCrossH", (0.0, -0.297, 0.43), (0.30, 0.014, 0.08), mat, 7,
        count, objects, bevel=0.0)
    box("CoffinLatch", (0.0, -0.30, 0.59), (0.20, 0.022, 0.12), mat, 5,
        count, objects, bevel=0.001)
    return objects, (1.75, -2.35, 1.30), (0.0, 0.0, 0.33)


KITCHEN_PALETTES = {
    # dark outline, wood/body, panel, cabinet, worktop, metal, recess,
    # glass/accent, textile/accent, indicator/highlight
    "normal": ["#141517", "#5A402E", "#826044", "#C7B99A", "#6E7475",
               "#A9B0AE", "#242729", "#77A3A0", "#A95A43", "#E8C86B"],
    "luxury": ["#100E0D", "#3B241A", "#68422A", "#E0D2B5", "#D9D2C2",
               "#B88A43", "#252223", "#739195", "#7B2636", "#F0D083"],
    "gothic": ["#08080A", "#171319", "#30252F", "#4C454D", "#676169",
               "#93733F", "#121115", "#65415F", "#711A2A", "#E8AF59"],
}


def kitchen_material(model_name, style):
    metallic = 0.12 if style == "luxury" else (0.08 if style == "gothic" else 0.03)
    return mansion_material(model_name, KITCHEN_PALETTES[style],
                            roughness=0.78, metallic=metallic)


def add_kitchen_front_detail(objects, mat, count, style, width, center_z=0.45):
    panel_region = 3 if style == "normal" else 2
    for index, x in enumerate((-width * 0.24, width * 0.24)):
        box("CabinetDoor_%d" % (index + 1), (x, -0.316, center_z),
            (width * 0.43, 0.026, 0.53), mat, panel_region, count, objects,
            bevel=0.003)
        box("CabinetHandle_%d" % (index + 1),
            (x + (-0.08 if x > 0 else 0.08), -0.334, center_z + 0.02),
            (0.035, 0.025, 0.19), mat, 5, count, objects, bevel=0.001)
    if style == "luxury":
        box("GoldPlinthTrim", (0.0, -0.333, 0.13), (width - 0.12, 0.025, 0.045),
            mat, 5, count, objects, bevel=0.001)
    elif style == "gothic":
        gothic_arch("GothicCabinetArch", (0.0, -0.339, 0.56), width * 0.82,
                    0.28, 0.022, 0.045, mat, 5, count, objects)


def make_kitchen_counter(model_name, style):
    mat = kitchen_material(model_name, style)
    count = len(KITCHEN_PALETTES[style])
    objects = []
    box("CounterPlinth", (0.0, 0.0, 0.08), (1.28, 0.56, 0.16), mat, 0,
        count, objects, bevel=0.002)
    box("CounterBody", (0.0, 0.0, 0.46), (1.34, 0.60, 0.76), mat, 1,
        count, objects, bevel=0.004)
    box("Worktop", (0.0, -0.01, 0.89), (1.46, 0.66, 0.12), mat, 4,
        count, objects, bevel=0.005)
    box("TopBacksplash", (0.0, 0.30, 1.00), (1.42, 0.08, 0.20), mat,
        4 if style != "gothic" else 2, count, objects, bevel=0.003)
    add_kitchen_front_detail(objects, mat, count, style, 1.34)
    return objects, (2.20, -3.00, 1.65), (0.0, 0.0, 0.48)


def make_kitchen_sink(model_name, style):
    mat = kitchen_material(model_name, style)
    count = len(KITCHEN_PALETTES[style])
    objects = []
    box("SinkPlinth", (0.0, 0.0, 0.08), (1.06, 0.56, 0.16), mat, 0,
        count, objects, bevel=0.002)
    box("SinkCabinet", (0.0, 0.0, 0.46), (1.12, 0.60, 0.76), mat, 1,
        count, objects, bevel=0.004)
    box("SinkWorktop", (0.0, -0.01, 0.89), (1.22, 0.66, 0.12), mat, 4,
        count, objects, bevel=0.005)
    box("SinkBasin", (0.0, -0.06, 0.965), (0.58, 0.40, 0.055), mat, 6,
        count, objects, bevel=0.006)
    box("SinkRim", (0.0, -0.06, 1.00), (0.68, 0.50, 0.035), mat, 5,
        count, objects, bevel=0.004)
    box("BasinOpening", (0.0, -0.06, 1.022), (0.54, 0.36, 0.015), mat, 7,
        count, objects, bevel=0.003)
    box("FaucetPost", (0.0, 0.19, 1.18), (0.07, 0.07, 0.38), mat, 5,
        count, objects, bevel=0.002)
    box("FaucetSpout", (0.0, 0.07, 1.35), (0.07, 0.28, 0.07), mat, 5,
        count, objects, bevel=0.002)
    box("FaucetDrop", (0.0, -0.055, 1.29), (0.07, 0.07, 0.15), mat, 5,
        count, objects, bevel=0.002)
    add_kitchen_front_detail(objects, mat, count, style, 1.12)
    return objects, (2.10, -2.85, 1.80), (0.0, 0.0, 0.60)


def make_kitchen_stove(model_name, style):
    mat = kitchen_material(model_name, style)
    count = len(KITCHEN_PALETTES[style])
    objects = []
    box("RangeBody", (0.0, 0.0, 0.46), (0.78, 0.64, 0.92), mat,
        3 if style == "normal" else 2, count, objects, bevel=0.004)
    box("Cooktop", (0.0, -0.01, 0.94), (0.82, 0.66, 0.08), mat, 6,
        count, objects, bevel=0.003)
    for index, (x, y) in enumerate(((-0.22, -0.16), (0.22, -0.16),
                                     (-0.22, 0.16), (0.22, 0.16))):
        cylinder("Burner_%d" % (index + 1), (x, y, 0.995), 0.13, 0.035, 8,
                 mat, 5, count, objects)
    box("OvenDoor", (0.0, -0.326, 0.48), (0.63, 0.028, 0.50), mat, 6,
        count, objects, bevel=0.003)
    box("OvenWindow", (0.0, -0.345, 0.50), (0.48, 0.018, 0.31), mat, 7,
        count, objects, bevel=0.002)
    box("OvenHandle", (0.0, -0.37, 0.76), (0.54, 0.055, 0.055), mat, 5,
        count, objects, bevel=0.002)
    box("RangeControls", (0.0, -0.335, 0.86), (0.68, 0.035, 0.14), mat,
        1 if style == "normal" else 2, count, objects, bevel=0.002)
    for index, x in enumerate((-0.24, -0.08, 0.08, 0.24)):
        cylinder("RangeKnob_%d" % (index + 1), (x, -0.365, 0.87), 0.035,
                 0.035, 8, mat, 9 if index == 0 else 5, count, objects,
                 rotation=(math.radians(90), 0.0, 0.0))
    if style == "gothic":
        gothic_arch("OvenArch", (0.0, -0.363, 0.63), 0.58, 0.36, 0.02,
                    0.045, mat, 5, count, objects)
    return objects, (1.80, -2.45, 1.55), (0.0, 0.0, 0.48)


def make_kitchen_fridge(model_name, style):
    mat = kitchen_material(model_name, style)
    count = len(KITCHEN_PALETTES[style])
    objects = []
    box("FridgeBody", (0.0, 0.0, 0.96), (0.82, 0.70, 1.92), mat,
        3 if style == "normal" else 2, count, objects, bevel=0.006)
    box("UpperDoor", (0.0, -0.362, 1.39), (0.74, 0.028, 0.78), mat,
        4 if style == "normal" else 3, count, objects, bevel=0.003)
    box("LowerDoor", (0.0, -0.362, 0.56), (0.74, 0.028, 0.76), mat,
        4 if style == "normal" else 3, count, objects, bevel=0.003)
    for z in (0.58, 1.40):
        box("FridgeHandle_%s" % str(z), (0.29, -0.397, z),
            (0.055, 0.055, 0.48), mat, 5, count, objects, bevel=0.002)
    box("FridgeVent", (0.0, -0.386, 0.12), (0.46, 0.018, 0.09), mat, 6,
        count, objects, bevel=0.001)
    if style == "luxury":
        box("FridgeGoldBand", (0.0, -0.386, 0.98), (0.76, 0.018, 0.045),
            mat, 5, count, objects, bevel=0.001)
    elif style == "gothic":
        gothic_arch("FridgeCrown", (0.0, -0.37, 1.91), 0.76, 0.28, 0.025,
                    0.055, mat, 5, count, objects)
    return objects, (1.95, -2.70, 2.25), (0.0, 0.0, 0.95)


def make_kitchen_wall_cabinet(model_name, style):
    mat = kitchen_material(model_name, style)
    count = len(KITCHEN_PALETTES[style])
    objects = []
    # Geometry retains its authored wall height; its origin remains at floor
    # level so Godot mounts every style consistently.
    box("WallCabinetBody", (0.0, 0.0, 1.66), (1.12, 0.38, 0.82), mat, 1,
        count, objects, bevel=0.004)
    for index, x in enumerate((-0.28, 0.28)):
        box("WallCabinetDoor_%d" % (index + 1), (x, -0.201, 1.66),
            (0.50, 0.025, 0.68), mat, 3 if style == "normal" else 2,
            count, objects, bevel=0.003)
        box("WallCabinetKnob_%d" % (index + 1),
            (x + (-0.19 if x > 0 else 0.19), -0.222, 1.65),
            (0.045, 0.025, 0.07), mat, 5, count, objects, bevel=0.001)
    box("CabinetCrown", (0.0, 0.0, 2.10), (1.20, 0.42, 0.10), mat,
        5 if style == "luxury" else 2, count, objects, bevel=0.003)
    if style == "gothic":
        gothic_arch("WallCabinetArch", (0.0, -0.218, 1.92), 1.02, 0.34,
                    0.02, 0.05, mat, 5, count, objects)
    return objects, (2.10, -2.85, 2.45), (0.0, 0.0, 1.28)


def make_kitchen_island(model_name, style):
    mat = kitchen_material(model_name, style)
    count = len(KITCHEN_PALETTES[style])
    objects = []
    box("IslandPlinth", (0.0, 0.0, 0.08), (1.34, 0.68, 0.16), mat, 0,
        count, objects, bevel=0.002)
    box("IslandBody", (0.0, 0.0, 0.46), (1.44, 0.72, 0.76), mat, 1,
        count, objects, bevel=0.004)
    box("IslandWorktop", (0.0, 0.0, 0.89), (1.62, 0.88, 0.12), mat, 4,
        count, objects, bevel=0.005)
    for x in (-0.45, 0.0, 0.45):
        box("IslandPanel_%s" % str(x), (x, -0.372, 0.47),
            (0.37, 0.025, 0.56), mat, 3 if style == "normal" else 2,
            count, objects, bevel=0.003)
    if style == "luxury":
        box("MarbleIslandInlay", (0.0, -0.01, 0.962), (1.34, 0.62, 0.025),
            mat, 3, count, objects, bevel=0.003)
    elif style == "gothic":
        gothic_arch("IslandGothicArch", (0.0, -0.391, 0.60), 1.30, 0.34,
                    0.02, 0.05, mat, 5, count, objects)
    return objects, (2.35, -3.15, 1.70), (0.0, 0.0, 0.47)


def make_normal_bookcase():
    colors = KITCHEN_PALETTES["normal"]
    mat = mansion_material("normal_bookcase", colors)
    count = len(colors)
    objects = []
    box("BookcaseBack", (0.0, 0.12, 0.91), (0.96, 0.12, 1.82), mat, 1,
        count, objects, bevel=0.003)
    for x in (-0.46, 0.46):
        box("BookcaseSide%s" % str(x), (x, 0.0, 0.91), (0.10, 0.38, 1.82),
            mat, 2, count, objects, bevel=0.002)
    for index, z in enumerate((0.08, 0.50, 0.92, 1.34, 1.78)):
        box("BookcaseShelf_%d" % index, (0.0, 0.0, z), (0.92, 0.38, 0.10),
            mat, 2, count, objects, bevel=0.002)
    for shelf, z in enumerate((0.30, 0.72, 1.14, 1.56)):
        for index, x in enumerate((-0.32, -0.17, -0.01, 0.16, 0.32)):
            height = 0.25 + ((shelf + index) % 3) * 0.035
            box("Book_%d_%d" % (shelf, index), (x, -0.15, z),
                (0.12, 0.12, height), mat, 7 + (shelf + index) % 3,
                count, objects, bevel=0.001)
    return objects, (2.05, -2.80, 2.15), (0.0, 0.0, 0.92)


def make_normal_coffee_table():
    colors = KITCHEN_PALETTES["normal"]
    mat = mansion_material("normal_coffee_table", colors)
    count = len(colors)
    objects = []
    box("CoffeeTableTop", (0.0, 0.0, 0.46), (1.22, 0.70, 0.14), mat, 2,
        count, objects, bevel=0.006)
    box("CoffeeTableShelf", (0.0, 0.0, 0.20), (1.04, 0.56, 0.09), mat, 1,
        count, objects, bevel=0.003)
    for x in (-0.49, 0.49):
        for y in (-0.24, 0.24):
            box("CoffeeLeg%s%s" % (x, y), (x, y, 0.23), (0.10, 0.10, 0.46),
                mat, 1, count, objects, bevel=0.002)
    return objects, (1.90, -2.55, 1.25), (0.0, 0.0, 0.24)


def make_normal_tv_console():
    colors = KITCHEN_PALETTES["normal"]
    mat = mansion_material("normal_tv_console", colors)
    count = len(colors)
    objects = []
    box("TVConsoleBody", (0.0, 0.0, 0.34), (1.32, 0.44, 0.62), mat, 1,
        count, objects, bevel=0.004)
    box("TVConsoleTop", (0.0, 0.0, 0.69), (1.40, 0.48, 0.10), mat, 2,
        count, objects, bevel=0.004)
    for x in (-0.38, 0.38):
        box("ConsoleDoor%s" % str(x), (x, -0.228, 0.36), (0.50, 0.025, 0.43),
            mat, 3, count, objects, bevel=0.003)
        box("ConsoleKnob%s" % str(x), (x, -0.25, 0.38), (0.05, 0.025, 0.06),
            mat, 5, count, objects, bevel=0.001)
    box("TelevisionBody", (0.0, 0.02, 1.14), (0.92, 0.22, 0.72), mat, 6,
        count, objects, bevel=0.008)
    box("TelevisionScreen", (-0.07, -0.102, 1.17), (0.66, 0.025, 0.48), mat,
        7, count, objects, bevel=0.006)
    for z in (1.03, 1.17, 1.31):
        box("TVControl%s" % str(z), (0.38, -0.115, z), (0.07, 0.025, 0.07),
            mat, 9 if z == 1.31 else 5, count, objects, bevel=0.001)
    return objects, (2.20, -3.00, 1.95), (0.0, 0.0, 0.72)


def make_normal_entry_bench():
    colors = KITCHEN_PALETTES["normal"]
    mat = mansion_material("normal_entry_bench", colors)
    count = len(colors)
    objects = []
    box("EntryBenchSeat", (0.0, 0.0, 0.52), (1.20, 0.42, 0.16), mat, 2,
        count, objects, bevel=0.005)
    box("EntryBenchBack", (0.0, 0.17, 1.02), (1.20, 0.10, 0.86), mat, 1,
        count, objects, bevel=0.004)
    box("EntryCushion", (0.0, -0.02, 0.63), (1.08, 0.36, 0.12), mat, 8,
        count, objects, bevel=0.006)
    for x in (-0.48, 0.48):
        box("EntryBenchLeg%s" % str(x), (x, 0.0, 0.25), (0.10, 0.10, 0.50),
            mat, 1, count, objects, bevel=0.002)
    for x in (-0.36, 0.0, 0.36):
        box("CoatHook%s" % str(x), (x, 0.10, 1.25), (0.07, 0.12, 0.12),
            mat, 5, count, objects, bevel=0.002)
    return objects, (2.05, -2.75, 1.75), (0.0, 0.0, 0.68)


def make_mansion_display_cabinet():
    colors = KITCHEN_PALETTES["luxury"]
    mat = mansion_material("mansion_display_cabinet", colors, roughness=0.74,
                           metallic=0.08)
    count = len(colors)
    objects = []
    box("DisplayCabinetBody", (0.0, 0.08, 1.05), (1.10, 0.40, 2.10), mat, 1,
        count, objects, bevel=0.005)
    box("DisplayGlass", (0.0, -0.132, 1.28), (0.90, 0.025, 1.28), mat, 7,
        count, objects, bevel=0.003)
    for z in (0.68, 1.10, 1.52):
        box("DisplayShelf%s" % str(z), (0.0, -0.02, z), (0.90, 0.32, 0.07),
            mat, 5, count, objects, bevel=0.002)
    for x in (-0.49, 0.49):
        box("DisplayPillar%s" % str(x), (x, -0.13, 1.05), (0.10, 0.08, 2.02),
            mat, 2, count, objects, bevel=0.002)
    box("DisplayCrown", (0.0, 0.04, 2.14), (1.22, 0.46, 0.16), mat, 5,
        count, objects, bevel=0.004)
    for index, (x, z) in enumerate(((-0.28, 0.86), (0.25, 1.28), (-0.18, 1.70))):
        cylinder("DisplayVase_%d" % (index + 1), (x, -0.12, z), 0.09, 0.20,
                 8, mat, 8 + index % 2, count, objects)
    return objects, (2.25, -3.10, 2.40), (0.0, 0.0, 1.08)


def make_mansion_chaise_lounge():
    colors = KITCHEN_PALETTES["luxury"]
    mat = mansion_material("mansion_chaise_lounge", colors)
    count = len(colors)
    objects = []
    box("ChaiseFrame", (0.0, 0.0, 0.34), (1.76, 0.70, 0.30), mat, 1,
        count, objects, bevel=0.006)
    box("ChaiseCushion", (0.08, -0.02, 0.55), (1.52, 0.62, 0.24), mat, 8,
        count, objects, bevel=0.010)
    box("ChaiseBack", (-0.70, 0.08, 0.82), (0.30, 0.62, 0.72), mat, 8,
        count, objects, bevel=0.009, rotation=(0.0, math.radians(-9), 0.0))
    box("ChaiseRoll", (-0.78, -0.01, 1.08), (0.24, 0.72, 0.20), mat, 5,
        count, objects, bevel=0.008)
    for x in (-0.70, 0.70):
        for y in (-0.25, 0.25):
            box("ChaiseFoot%s%s" % (x, y), (x, y, 0.12), (0.10, 0.10, 0.24),
                mat, 5, count, objects, bevel=0.002)
    return objects, (2.70, -3.65, 1.85), (0.0, 0.0, 0.48)


def make_mansion_upright_piano():
    colors = KITCHEN_PALETTES["luxury"]
    mat = mansion_material("mansion_upright_piano", colors)
    count = len(colors)
    objects = []
    box("PianoBody", (0.0, 0.10, 0.83), (1.44, 0.48, 1.38), mat, 1,
        count, objects, bevel=0.005)
    box("PianoCrown", (0.0, 0.09, 1.56), (1.54, 0.52, 0.12), mat, 5,
        count, objects, bevel=0.004)
    box("KeyboardBed", (0.0, -0.26, 0.86), (1.34, 0.34, 0.16), mat, 2,
        count, objects, bevel=0.003)
    for index, x in enumerate([(-0.58 + i * 0.097) for i in range(13)]):
        box("IvoryKey_%02d" % index, (x, -0.445, 0.89),
            (0.082, 0.24, 0.055), mat, 3, count, objects, bevel=0.001)
    for index, x in enumerate((-0.52, -0.32, -0.13, 0.07, 0.26, 0.46)):
        box("BlackKey_%02d" % index, (x, -0.40, 0.93),
            (0.055, 0.14, 0.07), mat, 6, count, objects, bevel=0.001)
    for x in (-0.58, 0.58):
        box("PianoLeg%s" % str(x), (x, -0.08, 0.38), (0.14, 0.18, 0.76),
            mat, 2, count, objects, bevel=0.003)
    box("MusicRest", (0.0, -0.19, 1.25), (0.72, 0.08, 0.36), mat, 2,
        count, objects, bevel=0.003, rotation=(math.radians(-8), 0.0, 0.0))
    return objects, (2.45, -3.35, 2.20), (0.0, 0.0, 0.83)


def make_mansion_bust_pedestal():
    colors = KITCHEN_PALETTES["luxury"]
    mat = mansion_material("mansion_bust_pedestal", colors)
    count = len(colors)
    objects = []
    box("PedestalFoot", (0.0, 0.0, 0.08), (0.54, 0.54, 0.16), mat, 1,
        count, objects, bevel=0.003)
    box("PedestalColumn", (0.0, 0.0, 0.66), (0.34, 0.34, 1.02), mat, 3,
        count, objects, bevel=0.003)
    box("PedestalTop", (0.0, 0.0, 1.20), (0.50, 0.50, 0.14), mat, 5,
        count, objects, bevel=0.003)
    box("BustTorso", (0.0, 0.0, 1.40), (0.44, 0.26, 0.34), mat, 4,
        count, objects, bevel=0.010)
    box("BustNeck", (0.0, 0.0, 1.61), (0.15, 0.15, 0.18), mat, 4,
        count, objects, bevel=0.006)
    box("BustHead", (0.0, -0.01, 1.80), (0.29, 0.27, 0.32), mat, 4,
        count, objects, bevel=0.012)
    box("BustHair", (0.0, 0.03, 1.91), (0.31, 0.25, 0.14), mat, 1,
        count, objects, bevel=0.008)
    return objects, (1.55, -2.10, 2.20), (0.0, 0.0, 0.90)


def prison_materials(name):
    colors = ["#090B0D", "#171C20", "#293238", "#465057", "#6D5943",
              "#8B3B32", "#A77A49", "#B8B19D"]
    image = make_pixel_atlas(name + "_pixel_atlas", colors, PRISON_TEXTURES)
    iron = make_material(name + " iron", image, roughness=0.72, metallic=0.52)
    stone = make_material(name + " stone", image, roughness=0.96, metallic=0.0)
    cloth = make_material(name + " cloth", image, roughness=1.0, metallic=0.0)
    return iron, stone, cloth, len(colors)


def make_prison_cell_gate():
    iron, stone, _, count = prison_materials("prison_cell_gate")
    objects = []
    box("StoneJambL", (-1.42, 0.0, 1.40), (0.16, 0.34, 2.80), stone, 2,
        count, objects, bevel=0.018)
    box("StoneJambR", (1.42, 0.0, 1.40), (0.16, 0.34, 2.80), stone, 2,
        count, objects, bevel=0.018)
    box("StoneLintel", (0.0, 0.0, 2.72), (2.75, 0.34, 0.18), stone, 3,
        count, objects, bevel=0.018)
    box("IronThreshold", (0.0, -0.02, 0.07), (2.75, 0.24, 0.14), iron, 1,
        count, objects, bevel=0.008)
    for index, x in enumerate((-1.18, -0.88, -0.58, -0.28, 0.02, 0.32,
                               0.62, 0.92, 1.22)):
        cylinder("GateBar_%02d" % index, (x, -0.04, 1.39), 0.045, 2.58, 8,
                 iron, 3 if index % 2 else 2, count, objects, bevel=0.006)
    for index, z in enumerate((0.54, 1.36, 2.18)):
        box("CrossRail_%d" % index, (0.0, -0.04, z), (2.55, 0.10, 0.10),
            iron, 1, count, objects, bevel=0.008)
    box("LockHousing", (0.23, -0.12, 1.25), (0.25, 0.16, 0.34), iron, 6,
        count, objects, bevel=0.014)
    box("LockKeyway", (0.23, -0.215, 1.25), (0.045, 0.035, 0.11), iron, 0,
        count, objects, bevel=0.003)
    return objects, (4.2, -6.2, 3.4), (0.0, 0.0, 1.35)


def make_prison_bunk():
    iron, _, cloth, count = prison_materials("prison_bunk")
    objects = []
    for x in (-0.48, 0.48):
        for y in (-0.92, 0.92):
            cylinder("Post_%s_%s" % (x, y), (x, y, 0.73), 0.038, 1.46, 8,
                     iron, 2, count, objects, bevel=0.004)
    for level, z in enumerate((0.34, 1.10)):
        box("Frame_%d" % level, (0.0, 0.0, z), (1.04, 1.92, 0.10), iron, 2,
            count, objects, bevel=0.012)
        box("Mattress_%d" % level, (0.0, 0.0, z + 0.105),
            (0.92, 1.78, 0.11), cloth, 7 if level else 4, count, objects,
            bevel=0.018)
        box("Blanket_%d" % level, (0.0, 0.36, z + 0.17),
            (0.84, 0.75, 0.045), cloth, 5, count, objects, bevel=0.010)
    for rung, z in enumerate((0.32, 0.59, 0.86, 1.13)):
        box("LadderRung_%d" % rung, (0.54, -0.86, z), (0.08, 0.34, 0.055),
            iron, 3, count, objects, bevel=0.006)
    return objects, (3.4, -4.8, 2.75), (0.0, 0.0, 0.78)


def make_bunk_bed(model_name, style="metal"):
    palettes = {
        "metal": ["#111519", "#303940", "#5C686E", "#A1AAAB",
                  "#263D50", "#527A96", "#B8C9D1", "#E6E3D7"],
        "wood": ["#1A110C", "#49301F", "#765035", "#A8754B",
                 "#D2A26D", "#315069", "#7493A6", "#E8E0CF"],
        "loft": ["#15131A", "#3B3345", "#6D5B78", "#9A82A7",
                 "#D2B7D8", "#374E64", "#7896AA", "#ECE4D7"],
    }
    colors = palettes[style]
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors,
                             PRISON_TEXTURES)
    mat = make_material(model_name.replace("_", " ").title() + " pixel paint",
                        image, roughness=.88, metallic=.12 if style == "metal" else .02)
    count = len(colors)
    objects = []
    frame_index = 2 if style == "metal" else 3
    post_width = .09 if style == "metal" else .13
    for x in (-.52, .52):
        for y in (-1.03, 1.03):
            box("Post_%s_%s" % (x, y), (x, y, .88),
                (post_width, post_width, 1.76), mat, frame_index, count,
                objects, bevel=.006)
    for level, z in enumerate((.38, 1.22)):
        box("BedFrame_%d" % level, (0, 0, z), (1.12, 2.14, .13), mat,
            frame_index, count, objects, bevel=.010)
        box("Mattress_%d" % level, (0, 0, z + .13), (1.00, 1.96, .16), mat,
            7, count, objects, bevel=.025)
        box("Pillow_%d" % level, (0, -.70, z + .25), (.72, .42, .15), mat,
            6, count, objects, bevel=.035)
        box("Blanket_%d" % level, (0, .36, z + .23), (.92, 1.02, .08), mat,
            5, count, objects, bevel=.015)
        # Guard rails make the upper bed silhouette unmistakably different
        # from the old prison bunk alias.
        if level == 1:
            for x in (-.54, .54):
                box("GuardRail_%s" % x, (x, .28, z + .36),
                    (.07, 1.22, .09), mat, frame_index, count, objects,
                    bevel=.004)
    ladder_x = .60
    for side_y in (-.62, -.18):
        box("LadderRail_%s" % side_y, (ladder_x, side_y, .80),
            (.08, .08, 1.30), mat, frame_index, count, objects, bevel=.004)
    for rung, z in enumerate((.28, .52, .76, 1.0, 1.24)):
        box("LadderRung_%d" % rung, (ladder_x, -.40, z),
            (.08, .52, .06), mat, frame_index, count, objects, bevel=.004)
    if style == "loft":
        box("UnderBedDesk", (0, .20, .72), (.92, .75, .10), mat, 3,
            count, objects, bevel=.008)
        box("UnderBedShelf", (0, .74, .78), (.92, .14, .65), mat, 2,
            count, objects, bevel=.006)
    return objects, (3.7, -5.0, 3.0), (0.0, 0.0, .90)


def prison_cafeteria_material(model_name):
    colors = ["#0E1215", "#293136", "#4D595E", "#7B8587",
              "#AAB0AD", "#D4D5CF", "#315F64", "#6FA4A1"]
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors,
                             PRISON_TEXTURES)
    return (make_material(model_name.replace("_", " ").title() + " pixel paint",
                          image, roughness=.84, metallic=.18), len(colors))


def make_prison_cafeteria_table():
    mat, count = prison_cafeteria_material("prison_cafeteria_table")
    o = []
    box("TableTop", (0, 0, .78), (2.65, .82, .12), mat, 3, count, o,
        bevel=.008)
    for x in (-1.12, 1.12):
        box("TableLeg_%s" % x, (x, 0, .39), (.10, .58, .72), mat, 2,
            count, o, bevel=.004)
    for y in (-.72, .72):
        box("BenchSeat_%s" % y, (0, y, .48), (2.55, .34, .12), mat, 4,
            count, o, bevel=.008)
        for x in (-1.05, 1.05):
            box("BenchLeg_%s_%s" % (x, y), (x, y, .24), (.10, .22, .46),
                mat, 2, count, o, bevel=.004)
    for x in (-1.18, 1.18):
        box("FloorBolt_%s" % x, (x, 0, .035), (.18, .18, .07), mat, 1,
            count, o, bevel=.012)
    return o, (3.8, -5.2, 2.8), (0, 0, .45)


def make_prison_serving_counter():
    mat, count = prison_cafeteria_material("prison_serving_counter")
    o = []
    box("CounterBase", (0, 0, .48), (2.35, .78, .96), mat, 2, count, o,
        bevel=.008)
    box("CounterTop", (0, -.02, 1.01), (2.46, .88, .12), mat, 4, count, o,
        bevel=.008)
    for index, x in enumerate((-.72, 0, .72)):
        box("FoodWell_%d" % index, (x, -.03, 1.08), (.58, .52, .08), mat,
            1, count, o, bevel=.018)
    for x in (-1.03, 1.03):
        box("GuardPost_%s" % x, (x, .17, 1.55), (.06, .06, .92), mat, 3,
            count, o)
    box("SneezeGuard", (0, .17, 1.72), (2.08, .045, .62), mat, 7, count, o,
        bevel=.006)
    box("TrayRail", (0, -.51, .78), (2.32, .16, .10), mat, 3, count, o,
        bevel=.004)
    return o, (3.7, -5.2, 3.1), (0, 0, .95)


def make_prison_tray_return():
    mat, count = prison_cafeteria_material("prison_tray_return")
    o = []
    box("ReturnBody", (0, 0, .68), (.92, .66, 1.36), mat, 2, count, o,
        bevel=.008)
    box("ReturnOpening", (0, -.342, .93), (.68, .035, .46), mat, 0,
        count, o, bevel=.006)
    box("Top", (0, 0, 1.40), (1.0, .72, .10), mat, 4, count, o,
        bevel=.006)
    for index, z in enumerate((.18, .26, .34)):
        box("Tray_%d" % index, (0, -.40, z), (.70, .46, .035), mat,
            5 if index == 2 else 3, count, o, bevel=.004)
    box("WasteDoor", (.0, -.352, .50), (.58, .025, .26), mat, 1,
        count, o, bevel=.004)
    return o, (2.2, -3.2, 2.0), (0, 0, .72)


def make_prison_kitchen_rack():
    mat, count = prison_cafeteria_material("prison_kitchen_rack")
    o = []
    for x in (-.62, .62):
        for y in (-.25, .25):
            box("RackPost_%s_%s" % (x, y), (x, y, .90),
                (.07, .07, 1.80), mat, 2, count, o, bevel=.003)
    for index, z in enumerate((.20, .70, 1.20, 1.70)):
        box("RackShelf_%d" % index, (0, 0, z), (1.35, .62, .08), mat,
            3, count, o, bevel=.004)
    for index, (x, z) in enumerate(((-.35, .30), (.32, .30),
                                     (-.30, .80), (.28, .80))):
        cylinder("StockPot_%d" % index, (x, 0, z), .18, .22, 10, mat,
                 4 if index % 2 else 3, count, o, bevel=.005)
    return o, (2.7, -3.8, 2.4), (0, 0, .90)


def make_dungeon_cage():
    iron, stone, _, count = prison_materials("dungeon_cage")
    objects = []
    box("CagePlinth", (0.0, 0.0, 0.10), (2.45, 2.45, 0.20), stone, 2,
        count, objects, bevel=0.018)
    box("CageRoof", (0.0, 0.0, 2.45), (2.35, 2.35, 0.14), iron, 1,
        count, objects, bevel=0.012)
    positions = []
    for value in (-1.08, -0.72, -0.36, 0.0, 0.36, 0.72, 1.08):
        positions.extend([(value, -1.08), (value, 1.08),
                          (-1.08, value), (1.08, value)])
    seen = set()
    for index, (x, y) in enumerate(positions):
        key = (round(x, 2), round(y, 2))
        if key in seen:
            continue
        seen.add(key)
        cylinder("CageBar_%02d" % index, (x, y, 1.28), 0.04, 2.30, 8,
                 iron, 3 if index % 3 else 2, count, objects, bevel=0.005)
    box("CageDoorFrame", (0.0, -1.13, 1.28), (0.95, 0.11, 2.28), iron, 1,
        count, objects, bevel=0.010)
    box("CageLatch", (0.38, -1.22, 1.25), (0.18, 0.15, 0.30), iron, 6,
        count, objects, bevel=0.010)
    return objects, (4.4, -5.8, 3.6), (0.0, 0.0, 1.15)


def make_restraint_chair():
    iron, stone, cloth, count = prison_materials("restraint_chair")
    objects = []
    box("StoneBase", (0.0, 0.0, 0.08), (1.00, 1.00, 0.16), stone, 2,
        count, objects, bevel=0.018)
    box("Seat", (0.0, 0.0, 0.58), (0.68, 0.65, 0.15), cloth, 4,
        count, objects, bevel=0.020)
    box("Back", (0.0, 0.24, 1.28), (0.68, 0.14, 1.28), cloth, 4,
        count, objects, bevel=0.020, rotation=(math.radians(-7), 0, 0))
    for side, x in (("L", -0.43), ("R", 0.43)):
        box("Arm_%s" % side, (x, -0.03, 0.83), (0.16, 0.70, 0.13), iron,
            2, count, objects, bevel=0.012)
        box("Leg_%s" % side, (x, 0.08, 0.33), (0.12, 0.12, 0.62), iron,
            2, count, objects, bevel=0.008)
        box("WristCuff_%s" % side, (x, -0.20, 0.90), (0.20, 0.18, 0.12),
            iron, 5, count, objects, bevel=0.015)
    box("ChestRestraint", (0.0, 0.12, 1.40), (0.77, 0.18, 0.16), iron, 5,
        count, objects, bevel=0.012, rotation=(math.radians(-7), 0, 0))
    return objects, (3.0, -4.2, 2.7), (0.0, 0.0, 0.90)


def carnival_material(model_name, colors, roughness=0.88, metallic=0.0):
    image = make_pixel_atlas(model_name + "_pixel_atlas", colors,
                             CARNIVAL_TEXTURES)
    return make_material(model_name.replace("_", " ").title() + " pixel paint",
                         image, roughness=roughness, metallic=metallic)


def make_carnival_ticket_booth():
    colors = ["#17111D", "#5E1732", "#B82E4C", "#F1C24D", "#F4E4C1",
              "#2C6772", "#9D6732"]
    mat = carnival_material("carnival_ticket_booth", colors)
    count = len(colors)
    objects = []
    box("BoothBase", (0, 0, .12), (1.65, 1.15, .24), mat, 6, count, objects)
    box("BoothBack", (0, .48, 1.18), (1.65, .16, 2.12), mat, 1, count, objects)
    for x in (-.74, .74):
        box("FrontPost", (x, -.46, 1.2), (.17, .17, 2.15), mat, 2,
            count, objects)
    box("Counter", (0, -.48, .92), (1.55, .34, .18), mat, 6, count, objects)
    box("Header", (0, -.45, 2.12), (1.72, .28, .42), mat, 2, count, objects)
    for index, x in enumerate((-.55, -.33, -.11, .11, .33, .55)):
        box("HeaderStripe_%d" % index, (x, -.602, 2.12), (.12, .025, .34),
            mat, 3 if index % 2 == 0 else 4, count, objects)
    box("TicketSlot", (0, -.66, 1.20), (.52, .06, .36), mat, 0, count, objects)
    box("TicketLetter_T", (-.16, -.70, 2.13), (.08, .03, .20), mat, 4,
        count, objects)
    box("TicketLetter_I", (0, -.70, 2.13), (.06, .03, .20), mat, 4,
        count, objects)
    box("TicketLetter_X", (.16, -.70, 2.13), (.08, .03, .20), mat, 4,
        count, objects, rotation=(0, math.radians(45), 0))
    return objects, (3.2, -4.5, 3.0), (0, 0, 1.15)


def make_popcorn_cart():
    colors = ["#17131A", "#8A1E35", "#D73C4E", "#F2C84B", "#FFF0C7",
              "#67A7AE", "#8B592E"]
    mat = carnival_material("popcorn_cart", colors, roughness=.78, metallic=.08)
    count = len(colors)
    objects = []
    box("CartBody", (0, 0, .73), (1.25, .72, .78), mat, 1, count, objects)
    for x in (-.48, 0, .48):
        box("BodyStripe", (x, -.371, .73), (.16, .025, .68), mat,
            4 if x == 0 else 2, count, objects)
    box("GlassCase", (0, 0, 1.38), (1.05, .62, .55), mat, 5, count, objects)
    box("PopcornMass", (0, 0, 1.22), (.91, .51, .18), mat, 3, count, objects)
    box("Canopy", (0, 0, 1.76), (1.36, .82, .20), mat, 2, count, objects)
    for x in (-.42, .42):
        box("CanopyPanel", (x, -.421, 1.77), (.26, .025, .14), mat, 4,
            count, objects)
    for x in (-.46, .46):
        cylinder("Wheel", (x, .25, .34), .25, .12, 8, mat, 0, count,
                 objects, rotation=(math.radians(90), 0, 0))
    box("Handle", (.83, .18, .82), (.42, .08, .08), mat, 6, count, objects)
    return objects, (2.7, -3.8, 2.35), (0, 0, .9)


def make_ring_toss_stall():
    colors = ["#15121B", "#283C66", "#357FA0", "#B82D4B", "#F0C34C",
              "#F4E5C5", "#74411F"]
    mat = carnival_material("ring_toss_stall", colors)
    count = len(colors)
    objects = []
    box("StallDeck", (0, 0, .16), (2.45, 1.45, .32), mat, 6, count, objects)
    box("StallBack", (0, .64, 1.25), (2.45, .16, 2.2), mat, 1, count, objects)
    for x in (-1.1, 1.1):
        box("StallPost", (x, -.59, 1.35), (.16, .16, 2.5), mat, 3,
            count, objects)
    box("StallHeader", (0, -.58, 2.38), (2.5, .25, .42), mat, 3, count, objects)
    for index, x in enumerate((-1.0, -.6, -.2, .2, .6, 1.0)):
        box("Awning_%d" % index, (x, -.72, 2.07), (.30, .36, .32), mat,
            4 if index % 2 else 5, count, objects,
            rotation=(math.radians(-18), 0, 0))
    for row in range(2):
        for col in range(5):
            x = -.8 + col * .4
            y = -.28 + row * .42
            cylinder("Bottle_%d_%d" % (row, col), (x, y, .46), .07, .45,
                     8, mat, 2 if col % 2 else 4, count, objects)
            cylinder("Ring_%d_%d" % (row, col), (x, y, .72), .13, .035,
                     8, mat, 5, count, objects)
    return objects, (3.8, -5.2, 3.4), (0, 0, 1.2)


def make_strength_tester():
    colors = ["#141118", "#702039", "#C9364F", "#F0BF43", "#F5E6C5",
              "#456D81", "#825126"]
    mat = carnival_material("strength_tester", colors, roughness=.76,
                            metallic=.12)
    count = len(colors)
    objects = []
    box("TesterBase", (0, 0, .15), (.92, .72, .3), mat, 6, count, objects)
    box("TesterTower", (0, .1, 1.42), (.30, .26, 2.55), mat, 2, count, objects)
    for index in range(8):
        box("Gauge_%d" % index, (0, -.055, .45 + index * .26),
            (.16, .025, .11), mat, 3 if index > 5 else 4, count, objects)
    cylinder("Bell", (0, .08, 2.78), .34, .18, 8, mat, 3, count, objects)
    box("StrikePad", (0, -.18, .31), (.44, .38, .18), mat, 0, count, objects)
    box("MalletHandle", (.56, -.18, .65), (.10, .10, .82), mat, 6,
        count, objects, rotation=(0, math.radians(18), 0))
    box("MalletHead", (.66, -.18, 1.03), (.42, .20, .20), mat, 1,
        count, objects)
    return objects, (2.8, -4.1, 3.3), (0, 0, 1.4)


def make_circus_pedestal():
    colors = ["#17131A", "#731D39", "#C52D4A", "#F0C345", "#F5E6C8",
              "#2C6573"]
    mat = carnival_material("circus_pedestal", colors)
    count = len(colors)
    objects = []
    cylinder("PedestalBase", (0, 0, .12), .82, .24, 12, mat, 0, count,
             objects)
    cylinder("PedestalBody", (0, 0, .38), .70, .46, 12, mat, 2, count,
             objects)
    cylinder("PedestalTop", (0, 0, .66), .80, .16, 12, mat, 3, count,
             objects)
    for index in range(8):
        angle = index * math.tau / 8.0
        box("StarBlock_%d" % index,
            (math.cos(angle) * .58, math.sin(angle) * .58, .42),
            (.14, .08, .20), mat, 4, count, objects,
            rotation=(0, 0, angle))
    return objects, (2.4, -3.3, 1.8), (0, 0, .35)


def make_carousel_centerpiece():
    colors = ["#130F18", "#5A1838", "#B52A4C", "#E9B936", "#F4E4C0",
              "#2C6A75", "#4D3C72", "#8A572B"]
    mat = carnival_material("carousel_centerpiece", colors, roughness=.80,
                            metallic=.06)
    count = len(colors)
    objects = []
    cylinder("CarouselBase", (0, 0, .18), 2.65, .36, 16, mat, 1, count,
             objects)
    cylinder("CarouselDeck", (0, 0, .43), 2.50, .18, 16, mat, 3, count,
             objects)
    cylinder("CenterMast", (0, 0, 3.15), .24, 5.55, 12, mat, 3, count,
             objects)
    cylinder("CanopyBand", (0, 0, 5.18), 2.65, .28, 16, mat, 2, count,
             objects)
    cone("Canopy", (0, 0, 5.72), 2.72, .42, .92, 16, mat, 1, count,
         objects)
    cylinder("Crown", (0, 0, 6.28), .32, .32, 8, mat, 3, count, objects)
    for index in range(8):
        angle = index * math.tau / 8.0
        radius = 1.75
        x, y = math.cos(angle) * radius, math.sin(angle) * radius
        cylinder("RidePole_%d" % index, (x, y, 2.72), .055, 4.45, 8,
                 mat, 3 if index % 2 else 4, count, objects)
        # Block-built carousel animal: a compact horse silhouette rather than a
        # smooth sculpt, matching the existing hunters and room geometry.
        box("HorseBody_%d" % index, (x, y, 1.36), (.72, .26, .38), mat,
            4 if index % 2 else 5, count, objects,
            rotation=(0, 0, angle))
        box("HorseNeck_%d" % index,
            (x + math.cos(angle) * .30, y + math.sin(angle) * .30, 1.64),
            (.22, .22, .56), mat, 4 if index % 2 else 5, count, objects,
            rotation=(0, 0, angle))
        for leg in (-.22, .22):
            box("HorseLeg_%d_%s" % (index, "A" if leg < 0 else "B"),
                (x + math.cos(angle) * leg, y + math.sin(angle) * leg, 1.02),
                (.12, .12, .55), mat, 6, count, objects)
    return objects, (8.4, -10.5, 8.0), (0, 0, 3.0)


def save_and_export(name, objects, root=ROOT, source=SOURCE):
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    blend_path = os.path.join(source, name + ".blend")
    glb_path = os.path.join(root, name + ".glb")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path, check_existing=False)
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_cameras=False,
        export_lights=False,
    )


def point_camera(camera, target):
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render_inventory_icon(name, eye, look):
    """Render the actual authored tool against transparency for the HUD.

    The output is deliberately generated from the same clean Blender source
    as the world pickup and first-person view, so the hotbar cannot drift into
    a separate collection of hand-painted placeholder icons.
    """
    world = bpy.context.scene.world or bpy.data.worlds.new("World")
    bpy.context.scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#111823")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.18

    bpy.ops.object.light_add(type="AREA", location=(-2.2, -3.0, 3.8))
    key = bpy.context.object
    key.data.energy = 620.0
    key.data.size = 2.4
    point_camera(key, look)
    bpy.ops.object.light_add(type="AREA", location=(2.0, -0.8, 2.0))
    fill = bpy.context.object
    fill.data.energy = 280.0
    fill.data.color = (0.46, 0.62, 1.0)
    fill.data.size = 2.0
    point_camera(fill, look)

    bpy.ops.object.camera_add(location=eye)
    camera = bpy.context.object
    camera.data.lens = 62
    point_camera(camera, look)
    bpy.context.scene.camera = camera

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 96
    scene.render.resolution_y = 96
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.render.filepath = os.path.join(INVENTORY_ICONS, name + ".png")
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        pass
    bpy.ops.render.render(write_still=True)


def render_preview(name, objects, eye, look, previews=PREVIEWS):
    # Preview extras are created only after saving/exporting the clean model.
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, -0.008))
    floor = bpy.context.object
    floor.name = "PreviewFloor"
    floor_mat = bpy.data.materials.new("Preview floor")
    floor_mat.diffuse_color = rgba("#171D27")
    floor.data.materials.append(floor_mat)

    world = bpy.context.scene.world or bpy.data.worlds.new("World")
    bpy.context.scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = rgba("#0B1018")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.36

    bpy.ops.object.light_add(type="AREA", location=(-2.7, -3.2, 4.4))
    key = bpy.context.object
    key.data.energy = 720.0
    key.data.shape = "DISK"
    key.data.size = 3.2
    point_camera(key, look)
    bpy.ops.object.light_add(type="AREA", location=(2.7, -1.0, 2.4))
    fill = bpy.context.object
    fill.data.energy = 380.0
    fill.data.color = (0.45, 0.60, 1.0)
    fill.data.size = 2.3
    point_camera(fill, look)
    bpy.ops.object.light_add(type="AREA", location=(0.0, 2.4, 2.8))
    rim = bpy.context.object
    rim.data.energy = 520.0
    rim.data.color = (1.0, 0.36, 0.28)
    rim.data.size = 2.0
    point_camera(rim, look)

    bpy.ops.object.camera_add(location=eye)
    camera = bpy.context.object
    camera.data.lens = 58
    point_camera(camera, look)
    bpy.context.scene.camera = camera

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = os.path.join(previews, name + "_hytale_preview.png")
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        pass
    bpy.ops.render.render(write_still=True)


BUILDERS = {
    "coin": make_coin,
    "vent": make_vent,
    "music_box": make_music_box,
    "hiding_spot": make_locker,
    "battery": make_battery,
    "revive_kit": make_revive_kit,
    "stim_pack": make_stim_pack,
    "relay": make_relay,
    "safe_zone": make_safe_zone,
    "lift": make_lift,
    "heater_station": make_heater_station,
    "locked_relay_crate": make_locked_relay_crate,
    "locked_relay_barrel": make_locked_relay_barrel,
    "boarded_door": make_boarded_door,
    "lockpick_set": make_lockpick_set,
    "crowbar": make_crowbar,
    "rescue_axe": make_rescue_axe,
    "flashlight_item": make_flashlight_item,
    "taser_item": make_taser_item,
    "boarded_hallway": make_boarded_hallway,
    "service_ladder": make_service_ladder,
    "wall_light_switch": make_wall_light_switch,
    "backpack_small": make_backpack_small,
    "backpack_medium": make_backpack_medium,
    "backpack_large": make_backpack_large,
}

MAZE_BUILDERS = {
    "arcade_cabinet_default": lambda: make_arcade_variant(
        "arcade_cabinet_default",
        ["#090D13", "#202A33", "#364B5C", "#3E71B4", "#E05D70", "#101B26", "#B8A059"], 0),
    "arcade_cabinet_burgundy": lambda: make_arcade_variant(
        "arcade_cabinet_burgundy",
        ["#0D090D", "#2C171D", "#51212B", "#B43C55", "#D06A75", "#130D14", "#B28A4A"], 1),
    "arcade_cabinet_teal": lambda: make_arcade_variant(
        "arcade_cabinet_teal",
        ["#071011", "#123034", "#1F5558", "#32B8B3", "#78D3C8", "#071719", "#B79B51"], 2),
    "arcade_cabinet_amber": lambda: make_arcade_variant(
        "arcade_cabinet_amber",
        ["#110D06", "#34240E", "#634319", "#D28A16", "#F1B648", "#181207", "#8E6A37"], 3),
    "arcade_cabinet_ultraviolet": lambda: make_arcade_variant(
        "arcade_cabinet_ultraviolet",
        ["#0B0810", "#241333", "#492160", "#8C40C7", "#C16DE1", "#100B18", "#A77B45"], 0),
    "arcade_cabinet_cyan_magenta": lambda: make_arcade_variant(
        "arcade_cabinet_cyan_magenta",
        ["#080D11", "#21343D", "#3C555D", "#45C4BF", "#D955A0", "#0B171C", "#B7914B"], 1),
    "wooden_chair_oak": lambda: make_wooden_chair(
        "wooden_chair_oak", False, WOOD_PALETTES["oak"]),
    "wooden_chair_walnut": lambda: make_wooden_chair(
        "wooden_chair_walnut", False, WOOD_PALETTES["walnut"]),
    "wooden_chair_mahogany": lambda: make_wooden_chair(
        "wooden_chair_mahogany", False, WOOD_PALETTES["mahogany"]),
    "wooden_chair_ash": lambda: make_wooden_chair(
        "wooden_chair_ash", False, WOOD_PALETTES["ash"]),
    "wooden_chair_cushion": lambda: make_wooden_chair(
        "wooden_chair_cushion", True, WOOD_PALETTES["oak"]),
    "wooden_chair_cushion_walnut": lambda: make_wooden_chair(
        "wooden_chair_cushion_walnut", True, WOOD_PALETTES["walnut"]),
    "wooden_chair_cushion_mahogany": lambda: make_wooden_chair(
        "wooden_chair_cushion_mahogany", True, WOOD_PALETTES["mahogany"]),
    "wooden_chair_cushion_ash": lambda: make_wooden_chair(
        "wooden_chair_cushion_ash", True, WOOD_PALETTES["ash"]),
    "wooden_table": lambda: make_wooden_table(
        "wooden_table", WOOD_PALETTES["oak"]),
    "wooden_table_walnut": lambda: make_wooden_table(
        "wooden_table_walnut", WOOD_PALETTES["walnut"]),
    "wooden_table_mahogany": lambda: make_wooden_table(
        "wooden_table_mahogany", WOOD_PALETTES["mahogany"]),
    "wooden_table_ash": lambda: make_wooden_table(
        "wooden_table_ash", WOOD_PALETTES["ash"]),
    "restaurant_party_table": make_restaurant_party_table,
    "wooden_dresser_sideboard": lambda: make_wooden_dresser(
        "wooden_dresser_sideboard", WOOD_PALETTES["oak"]),
    "wooden_dresser_sideboard_walnut": lambda: make_wooden_dresser(
        "wooden_dresser_sideboard_walnut", WOOD_PALETTES["walnut"]),
    "wooden_dresser_sideboard_mahogany": lambda: make_wooden_dresser(
        "wooden_dresser_sideboard_mahogany", WOOD_PALETTES["mahogany"]),
    "wooden_dresser_sideboard_ash": lambda: make_wooden_dresser(
        "wooden_dresser_sideboard_ash", WOOD_PALETTES["ash"]),
    "filing_cabinet": make_filing_cabinet,
    "office_desk": make_office_desk,
    "office_task_chair": make_office_task_chair,
    "office_crt_security_console": make_office_security_console,
    "office_cubicle_partition": make_office_cubicle_partition,
    "office_printer": make_office_printer,
    "office_water_cooler": make_office_water_cooler,
    "office_photocopier": make_office_photocopier,
    "office_shredder": make_office_shredder,
    "office_file_boxes": make_office_file_boxes,
    "office_corner_workstation": make_office_corner_workstation,
    "supply_crates": make_supply_crates,
    "server_rack": make_server_rack,
    "vending_machine": make_vending_machine,
    "floor_lamp": make_floor_lamp,
    "trash_bin": make_trash_bin,
    "privacy_curtain": make_privacy_curtain,
    "lounge_couch_red": make_lounge_couch,
}

# Every generated office chooses one stable shell/partition finish. The
# historical unsuffixed exports remain the neutral option; charcoal and teal
# are additional authored variants with the same usable silhouettes.
OFFICE_VARIANT_BUILDERS = {
    "office_desk": make_office_desk,
    "office_task_chair": make_office_task_chair,
    "office_crt_security_console": make_office_security_console,
    "office_cubicle_partition": make_office_cubicle_partition,
    "office_printer": make_office_printer,
    "office_water_cooler": make_office_water_cooler,
    "office_photocopier": make_office_photocopier,
    "office_shredder": make_office_shredder,
    "office_file_boxes": make_office_file_boxes,
    "office_corner_workstation": make_office_corner_workstation,
}
for office_base_name, office_builder in OFFICE_VARIANT_BUILDERS.items():
    for office_theme, office_colors in OFFICE_PALETTES.items():
        office_variant_name = "%s_%s" % (office_base_name, office_theme)
        MAZE_BUILDERS[office_variant_name] = (
            lambda name=office_variant_name, colors=office_colors,
                   builder=office_builder: builder(name, colors)
        )

# Four distinct reference-led computer families, each exported in the same
# named shell themes.  Captured defaults in the lambdas are intentional: they
# keep every builder stable after the loop finishes.
for computer_style in ("compact", "tower", "desktop", "terminal"):
    for computer_theme, computer_colors in COMPUTER_PALETTES.items():
        computer_name = "retro_computer_%s_%s" % (computer_style, computer_theme)
        MAZE_BUILDERS[computer_name] = (
            lambda name=computer_name, style=computer_style, colors=computer_colors:
            make_retro_computer(name, style, colors)
        )

for catalog_name in (
        "arcade_basketball_hoop", "arcade_carpet_circle",
        "arcade_carpet_runner", "arcade_token_changer",
        "backstage_repair_stand", "breaker_cabinet", "broken_aquarium",
        "carnival_carousel", "flower_blue", "flower_rose", "flower_sun",
        "flower_violet", "garden_planter_bench", "giant_tree", "grass_fern",
        "locker", "maintenance_cleaning_cart", "maintenance_tool_cabinet",
        "mascot_statue", "prize_claw_machine", "prize_counter",
        "snack_kiosk", "stage_platform", "stage_speaker", "utility_cart"):
    MAZE_BUILDERS[catalog_name] = (
        lambda name=catalog_name: make_catalog_furnishing(name)
    )

MANSION_BUILDERS = {
    "grand_dining_table": make_grand_dining_table,
    "dining_chair_burgundy": lambda: make_dining_chair(
        "dining_chair_burgundy", False),
    "dining_chair_cushion_burgundy": lambda: make_dining_chair(
        "dining_chair_cushion_burgundy", True),
    "dining_chair_ivory": lambda: make_dining_chair(
        "dining_chair_ivory", True,
        ["#160F0D", "#352119", "#5B3826", "#835738", "#9A856A",
         "#C8B99A", "#E4D8BE", "#B88A45"]),
    "dining_chandelier": make_dining_chandelier,
    "dining_chandelier_crystal": lambda: make_dining_chandelier(
        "dining_chandelier_crystal",
        ["#101015", "#343947", "#68758A", "#A8B8C9", "#D7EAF3", "#F3FCFF", "#8ABED1"],
        "crystal"),
    "dining_chandelier_gothic": lambda: make_dining_chandelier(
        "dining_chandelier_gothic",
        ["#09080B", "#1D1722", "#37263E", "#5B385F", "#A14B62", "#E7C9A1", "#B72D3F"],
        "gothic"),
    "ceiling_light_warm": lambda: make_ceiling_light(
        "ceiling_light_warm", ["#17130F", "#4A3828", "#8F6940", "#C99A5B", "#E6C98E", "#FFF0BF"], "round"),
    "ceiling_light_cool": lambda: make_ceiling_light(
        "ceiling_light_cool", ["#10151A", "#2C3C49", "#527286", "#79A9BD", "#ADD5DF", "#E8FCFF"], "square"),
    "ceiling_light_teal": lambda: make_ceiling_light(
        "ceiling_light_teal", ["#071415", "#18383A", "#286268", "#3F9696", "#75CBC1", "#D6FFF4"], "cage"),
    "ceiling_fan_walnut": lambda: make_ceiling_fan(
        "ceiling_fan_walnut", ["#11100F", "#33261E", "#604331", "#8D6646", "#B08A5C", "#F3DCA1"], 5),
    "ceiling_fan_ivory": lambda: make_ceiling_fan(
        "ceiling_fan_ivory", ["#1A1917", "#5A554A", "#8D887B", "#BDB7A8", "#E2DDCF", "#FFF5D4"], 4),
    "ceiling_fan_charcoal": lambda: make_ceiling_fan(
        "ceiling_fan_charcoal", ["#080A0B", "#1A2023", "#313C41", "#4E5B60", "#78888D", "#D7EFF2"], 3),
    "table_lamp_burgundy": lambda: make_table_lamp(
        "table_lamp_burgundy", ["#130C0F", "#3D1720", "#742A39", "#A84255", "#D06D78", "#F4D8B0"], "shade"),
    "table_lamp_teal": lambda: make_table_lamp(
        "table_lamp_teal", ["#071315", "#17383A", "#286064", "#3D9392", "#78C9BE", "#E0FFF4"], "banker"),
    "table_lamp_ivory": lambda: make_table_lamp(
        "table_lamp_ivory", ["#191714", "#514B40", "#817969", "#B5A994", "#DFD4BB", "#FFF3CF"], "orb"),
    "floor_lamp_teal": lambda: make_floor_lamp(
        "floor_lamp_teal", ["#071214", "#173438", "#285B61", "#3D8E91", "#73C6BB", "#E1FFF4"], "modern"),
    "floor_lamp_ivory": lambda: make_floor_lamp(
        "floor_lamp_ivory", ["#171512", "#50493D", "#847B68", "#B7AA91", "#DED2B7", "#FFF0C9"], "tripod"),
    "mansion_bookshelf": make_mansion_bookshelf,
    "magazine_rack": make_magazine_rack,
    "mansion_fireplace": make_mansion_fireplace,
    "bathroom_stall": make_bathroom_stall,
    "bathroom_sink": make_bathroom_sink,
    "bathroom_mirror": make_bathroom_mirror,
    "bathroom_vanity": make_bathroom_vanity,
    "public_restroom_toilet": lambda: make_restroom_toilet(
        "public_restroom_toilet", False),
    "public_mens_urinal": make_public_mens_urinal,
    "public_sink_bank": make_public_sink_bank,
    "public_hand_dryer": lambda: make_public_wall_utility(
        "public_hand_dryer", "dryer"),
    "public_soap_dispenser": lambda: make_public_wall_utility(
        "public_soap_dispenser", "soap"),
    "public_paper_towel_dispenser": lambda: make_public_wall_utility(
        "public_paper_towel_dispenser", "paper"),
    "public_baby_change_station": lambda: make_public_wall_utility(
        "public_baby_change_station", "change"),
    "public_sanitary_bin": make_public_sanitary_bin,
    "public_mens_room_sign": lambda: make_restroom_sign(
        "public_mens_room_sign", False),
    "public_womens_room_sign": lambda: make_restroom_sign(
        "public_womens_room_sign", True),
    "public_mens_shower_stall": lambda: make_public_shower_stall(
        "public_mens_shower_stall", False),
    "public_womens_shower_stall": lambda: make_public_shower_stall(
        "public_womens_shower_stall", True),
    "public_shower_bench": make_public_shower_bench,
    "house_bathtub": make_house_bathtub,
    "house_toilet": lambda: make_restroom_toilet("house_toilet", True),
    "house_shower_enclosure": make_house_shower_enclosure,
    "house_medicine_cabinet": make_house_medicine_cabinet,
    "house_towel_rack": make_house_towel_rack,
    "house_bath_mat": make_house_bath_mat,
    "house_bathroom_shelf": make_house_bathroom_shelf,
    "grand_staircase": make_grand_staircase,
    "grand_foyer_staircase": make_grand_foyer_staircase,
    "ornate_sideboard": make_ornate_sideboard,
    "table_candelabra": make_table_candelabra,
    "flower_centerpiece": make_flower_centerpiece,
    "framed_wall_portrait": make_framed_wall_portrait,
    "normal_picture_frame_empty": lambda: make_empty_wall_frame(
        "normal_picture_frame_empty", "normal", False),
    "normal_painting_frame_empty": lambda: make_empty_wall_frame(
        "normal_painting_frame_empty", "normal", True),
    "luxury_picture_frame_empty": lambda: make_empty_wall_frame(
        "luxury_picture_frame_empty", "luxury", False),
    "luxury_painting_frame_empty": lambda: make_empty_wall_frame(
        "luxury_painting_frame_empty", "luxury", True),
    "gothic_picture_frame_empty": lambda: make_empty_wall_frame(
        "gothic_picture_frame_empty", "gothic", False),
    "gothic_painting_frame_empty": lambda: make_empty_wall_frame(
        "gothic_painting_frame_empty", "gothic", True),
    "normal_room_door": lambda: make_room_door("normal_room_door", "normal"),
    "luxury_room_door": lambda: make_room_door("luxury_room_door", "luxury"),
    "gothic_room_door": lambda: make_room_door("gothic_room_door", "gothic"),
    "normal_double_room_door": lambda: make_room_door(
        "normal_double_room_door", "normal", True),
    "luxury_double_room_door": lambda: make_room_door(
        "luxury_double_room_door", "luxury", True),
    "gothic_double_room_door": lambda: make_room_door(
        "gothic_double_room_door", "gothic", True),
    "wall_sconce": make_wall_sconce,
    "wall_sconce_cool": lambda: make_wall_sconce(
        "wall_sconce_cool", ["#0D1216", "#293844", "#506D80", "#79A4B7", "#A8D1DC", "#E5FAFF", "#487B8C", "#BDEEFF"], "classic"),
    "wall_sconce_gothic": lambda: make_wall_sconce(
        "wall_sconce_gothic", ["#08070A", "#1D1521", "#39243B", "#633B5F", "#A34A66", "#E9CCAD", "#B32A3E", "#F2A049"], "gothic"),
    "heavy_mansion_drapes": make_heavy_drapes,
    "mansion_area_rug": make_mansion_area_rug,
    "single_bed_burgundy": lambda: make_bedroom_bed(
        "single_bed_burgundy", False),
    "single_bed_navy": lambda: make_bedroom_bed(
        "single_bed_navy", False,
        ["#0C1015", "#202D3C", "#334A62", "#4C6A85", "#273B62",
         "#3F5F91", "#D5CCB5", "#EEE6D3", "#B18A4A"]),
    "double_bed_burgundy": lambda: make_bedroom_bed(
        "double_bed_burgundy", True),
    "double_bed_violet": lambda: make_bedroom_bed(
        "double_bed_violet", True,
        ["#110C13", "#30203A", "#52315D", "#74467E", "#71304F",
         "#A74C76", "#D5C9B3", "#EEE4CF", "#B18A4A"]),
    "bedroom_nightstand": make_bedroom_nightstand,
    "bedroom_wardrobe": make_bedroom_wardrobe,
    "bedroom_dresser": make_bedroom_dresser,
    "bedroom_vanity": make_bedroom_vanity,
    "vanity_stool": make_vanity_stool,
    "bedside_lamp": make_bedside_lamp,
    "toy_chest": make_toy_chest,
    "laundry_hamper": make_laundry_hamper,
    "bedroom_rug": make_bedroom_rug,
    "bedroom_wall_clock": make_bedroom_wall_clock,
    "bedroom_bench": make_bedroom_bench,
    "lounge_couch_brown": lambda: make_mansion_couch_variant(
        "lounge_couch_brown", ["#120E0D", "#38251E", "#5A3A2C", "#7C5138", "#9A6C4B", "#2C1C19", "#AD8348"]),
    "lounge_couch_black": lambda: make_mansion_couch_variant(
        "lounge_couch_black", ["#090A0B", "#17191B", "#292D30", "#40464A", "#62696B", "#111315", "#A78045"]),
    "lounge_couch_navy": lambda: make_mansion_couch_variant(
        "lounge_couch_navy", ["#090D12", "#172536", "#243D57", "#36597A", "#4E7695", "#111B29", "#B08A48"]),
    "lounge_couch_olive": lambda: make_mansion_couch_variant(
        "lounge_couch_olive", ["#0E100A", "#262D18", "#3F4B27", "#5E6A39", "#7C8753", "#1B2112", "#AD8847"]),
    "lounge_couch_violet": lambda: make_mansion_couch_variant(
        "lounge_couch_violet", ["#100B12", "#2A1932", "#48264F", "#67386C", "#87538B", "#211326", "#B08A48"]),
    "lounge_couch_ivory": lambda: make_mansion_couch_variant(
        "lounge_couch_ivory", ["#211B17", "#6F6453", "#9A8D74", "#BDB095", "#DED2B6", "#4C4035", "#B18445"]),
    "lounge_couch_red_wide": lambda: make_mansion_couch_variant(
        "lounge_couch_red_wide", ["#171014", "#4B2025", "#732D33", "#A04045", "#C45B5F", "#372126", "#B58A49"], True),
    "lounge_couch_brown_wide": lambda: make_mansion_couch_variant(
        "lounge_couch_brown_wide", ["#120E0D", "#38251E", "#5A3A2C", "#7C5138", "#9A6C4B", "#2C1C19", "#AD8348"], True),
    "lounge_couch_black_wide": lambda: make_mansion_couch_variant(
        "lounge_couch_black_wide", ["#090A0B", "#17191B", "#292D30", "#40464A", "#62696B", "#111315", "#A78045"], True),
    "lounge_couch_navy_wide": lambda: make_mansion_couch_variant(
        "lounge_couch_navy_wide", ["#090D12", "#172536", "#243D57", "#36597A", "#4E7695", "#111B29", "#B08A48"], True),
    "lounge_couch_olive_wide": lambda: make_mansion_couch_variant(
        "lounge_couch_olive_wide", ["#0E100A", "#262D18", "#3F4B27", "#5E6A39", "#7C8753", "#1B2112", "#AD8847"], True),
    "lounge_couch_violet_wide": lambda: make_mansion_couch_variant(
        "lounge_couch_violet_wide", ["#100B12", "#2A1932", "#48264F", "#67386C", "#87538B", "#211326", "#B08A48"], True),
    "lounge_couch_ivory_wide": lambda: make_mansion_couch_variant(
        "lounge_couch_ivory_wide", ["#211B17", "#6F6453", "#9A8D74", "#BDB095", "#DED2B6", "#4C4035", "#B18445"], True),
}

# Keep every bedroom colorway reproducible from this retained source script.
# The original unsuffixed household pieces are the burgundy colorway, which
# preserves all pre-existing paths while the remaining themes use suffixes.
NORMAL_BEDROOM_FACTORIES = {
    "bedroom_nightstand": make_bedroom_nightstand,
    "bedroom_wardrobe": make_bedroom_wardrobe,
    "bedroom_dresser": make_bedroom_dresser,
    "bedroom_vanity": make_bedroom_vanity,
    "vanity_stool": make_vanity_stool,
    "bedside_lamp": make_bedside_lamp,
    "toy_chest": make_toy_chest,
    "laundry_hamper": make_laundry_hamper,
    "bedroom_rug": make_bedroom_rug,
    "bedroom_wall_clock": make_bedroom_wall_clock,
    "bedroom_bench": make_bedroom_bench,
}
for theme_name, theme_colors in NORMAL_BEDROOM_PALETTES.items():
    for is_double in (False, True):
        bed_name = "%s_bed_%s" % ("double" if is_double else "single", theme_name)
        MANSION_BUILDERS[bed_name] = (
            lambda name=bed_name, double=is_double, colors=theme_colors:
                make_bedroom_bed(name, double, colors))
    for base_name, factory in NORMAL_BEDROOM_FACTORIES.items():
        variant_name = base_name if theme_name == "burgundy" \
            else "%s_%s" % (base_name, theme_name)
        MANSION_BUILDERS[variant_name] = (
            lambda name=variant_name, colors=theme_colors, build=factory:
                build(name, colors))

GOTHIC_BEDROOM_FACTORIES = {
    "gothic_double_bed": make_gothic_bed,
    "gothic_nightstand": make_gothic_nightstand,
    "gothic_wardrobe": make_gothic_wardrobe,
    "gothic_dresser": make_gothic_dresser,
    "gothic_vanity": make_gothic_vanity,
    "gothic_vanity_stool": make_gothic_stool,
    "gothic_bedroom_bench": make_gothic_bench,
    "gothic_bedroom_rug": make_gothic_rug,
    "gothic_bedside_candelabra": make_gothic_bedside_candelabra,
}
for theme_name, theme_colors in GOTHIC_BEDROOM_PALETTES.items():
    for base_name, factory in GOTHIC_BEDROOM_FACTORIES.items():
        variant_name = "%s_%s" % (base_name, theme_name)
        MANSION_BUILDERS[variant_name] = (
            lambda name=variant_name, colors=theme_colors, build=factory:
                build(name, colors))

MANSION_BUILDERS.update({
	"corridor_carpet_teal": lambda: make_region_floor_dressing(
		"corridor_carpet_teal", "corridor", REGIONAL_FLOOR_PALETTES["corridor_teal"]),
	"corridor_carpet_burgundy": lambda: make_region_floor_dressing(
		"corridor_carpet_burgundy", "corridor", REGIONAL_FLOOR_PALETTES["corridor_burgundy"]),
	"hotel_carpet_burgundy": lambda: make_region_floor_dressing(
		"hotel_carpet_burgundy", "hotel", REGIONAL_FLOOR_PALETTES["hotel_burgundy"]),
	"hotel_carpet_navy": lambda: make_region_floor_dressing(
		"hotel_carpet_navy", "hotel", REGIONAL_FLOOR_PALETTES["hotel_navy"]),
	"hotel_carpet_ivory": lambda: make_region_floor_dressing(
		"hotel_carpet_ivory", "hotel", REGIONAL_FLOOR_PALETTES["hotel_ivory"]),
	"apartment_carpet_olive": lambda: make_region_floor_dressing(
		"apartment_carpet_olive", "apartment", REGIONAL_FLOOR_PALETTES["apartment_olive"]),
	"apartment_carpet_charcoal": lambda: make_region_floor_dressing(
		"apartment_carpet_charcoal", "apartment", REGIONAL_FLOOR_PALETTES["apartment_charcoal"]),
	"apartment_carpet_rust": lambda: make_region_floor_dressing(
		"apartment_carpet_rust", "apartment", REGIONAL_FLOOR_PALETTES["apartment_rust"]),
	"beach_mat_teal": lambda: make_region_floor_dressing(
		"beach_mat_teal", "beach", REGIONAL_FLOOR_PALETTES["beach_teal"]),
	"beach_mat_sun": lambda: make_region_floor_dressing(
		"beach_mat_sun", "beach", REGIONAL_FLOOR_PALETTES["beach_sun"]),
	"mansion_console_table": make_mansion_console_table,
    "mansion_grandfather_clock": make_mansion_grandfather_clock,
    "mansion_coat_rack": make_mansion_coat_rack,
    "mansion_tea_cart": make_mansion_tea_cart,
    "mansion_rocking_chair": make_mansion_rocking_chair,
    "mansion_room_divider": make_mansion_room_divider,
    "gothic_writing_desk": make_gothic_writing_desk,
    "gothic_bookcase": make_gothic_bookcase,
    "gothic_pedestal_table": make_gothic_pedestal_table,
    "gothic_floor_candelabra": make_gothic_floor_candelabra,
    "gothic_coffin_chest": make_gothic_coffin_chest,
    "normal_bookcase": make_normal_bookcase,
    "normal_coffee_table": make_normal_coffee_table,
    "normal_tv_console": make_normal_tv_console,
    "normal_entry_bench": make_normal_entry_bench,
    "mansion_display_cabinet": make_mansion_display_cabinet,
    "mansion_chaise_lounge": make_mansion_chaise_lounge,
    "mansion_upright_piano": make_mansion_upright_piano,
    "mansion_bust_pedestal": make_mansion_bust_pedestal,
})

KITCHEN_FACTORIES = {
    "counter": make_kitchen_counter,
    "sink": make_kitchen_sink,
    "stove": make_kitchen_stove,
    "fridge": make_kitchen_fridge,
    "wall_cabinet": make_kitchen_wall_cabinet,
    "island": make_kitchen_island,
}
for kitchen_style in ("normal", "luxury", "gothic"):
    for piece_name, piece_factory in KITCHEN_FACTORIES.items():
        kitchen_name = "%s_kitchen_%s" % (kitchen_style, piece_name)
        MANSION_BUILDERS[kitchen_name] = (
            lambda name=kitchen_name, style=kitchen_style, build=piece_factory:
                build(name, style))

for theme_name, theme_colors in GOTHIC_BEDROOM_PALETTES.items():
    chair_name = "gothic_highback_chair_%s" % theme_name
    MANSION_BUILDERS[chair_name] = (
        lambda name=chair_name, colors=theme_colors:
            make_gothic_highback_chair(name, colors))

BEACH_BUILDERS = {
    "sand_castle": make_sand_castle,
    "beach_umbrella": make_beach_umbrella,
    "tiki_bar": make_tiki_bar,
    "beach_chair": make_beach_chair,
    "surfboard_rack": make_surfboard_rack,
    "palm_tree": make_palm_tree,
    "frozen_beach_hut": make_frozen_beach_hut,
    "frozen_tideline_pool": make_frozen_tideline_pool,
}

NETHER_BUILDERS = {
    "lava_vent": make_lava_vent,
    "ember_brazier": make_ember_brazier,
    "basalt_pillar": make_basalt_pillar,
    "magma_crystal_cluster": make_magma_crystal_cluster,
    "basalt_rubble": make_basalt_rubble,
    "inferno_altar": make_inferno_altar,
    "inferno_chain_lantern": make_inferno_chain_lantern,
    "lava_pipe_manifold": make_lava_pipe_manifold,
    "charred_supply_crate": make_charred_supply_crate,
}

PRISON_BUILDERS = {
    "prison_cell_gate": make_prison_cell_gate,
    "prison_bunk": make_prison_bunk,
    "bunk_bed_metal": lambda: make_bunk_bed("bunk_bed_metal", "metal"),
    "bunk_bed_wood": lambda: make_bunk_bed("bunk_bed_wood", "wood"),
    "bunk_bed_loft": lambda: make_bunk_bed("bunk_bed_loft", "loft"),
    "prison_cafeteria_table": make_prison_cafeteria_table,
    "prison_serving_counter": make_prison_serving_counter,
    "prison_tray_return": make_prison_tray_return,
    "prison_kitchen_rack": make_prison_kitchen_rack,
    "dungeon_cage": make_dungeon_cage,
    "restraint_chair": make_restraint_chair,
}

CARNIVAL_BUILDERS = {
    "carnival_ticket_booth": make_carnival_ticket_booth,
    "popcorn_cart": make_popcorn_cart,
    "ring_toss_stall": make_ring_toss_stall,
    "strength_tester": make_strength_tester,
    "circus_pedestal": make_circus_pedestal,
    "carousel_centerpiece": make_carousel_centerpiece,
}


def sewer_materials(name):
    colors = ["#0C0E0F", "#1E2326", "#353C3F", "#56605F", "#6E4B32",
              "#8E5B33", "#A9894E", "#FFB347"]
    image = make_pixel_atlas(name + "_pixel_atlas", colors, SEWER_TEXTURES)
    iron = make_material(name + " iron", image, roughness=0.74, metallic=0.45)
    rust = make_material(name + " rust", image, roughness=0.95, metallic=0.1)
    concrete = make_material(name + " concrete", image, roughness=0.97, metallic=0.0)
    return iron, rust, concrete, image, len(colors)


## Sewer ladders hang on the north wall of a 1 x 1 m shaft (Blender +Y, Godot -Z).
## Origin: the ladder cell's centre on the floor of the level it stands in.
## Person scale: 0.6 m between the rails, stout 7 cm rails and rungs a hand can close round, every 0.3 m.
LADDER_RAIL_Y = 0.38
LADDER_RAIL_X = 0.30


def _ladder_section(objects, iron, rust, count, z0, z1, rung_from, rung_step, prefix):
    for side, x in (("L", -LADDER_RAIL_X), ("R", LADDER_RAIL_X)):
        box("%sRail%s" % (prefix, side), (x, LADDER_RAIL_Y, (z0 + z1) * .5), (0.07, 0.07, z1 - z0),
            iron, 2, count, objects, bevel=0.006)
    z = rung_from
    index = 0
    while z < z1 - 0.05:
        cylinder("%sRung%02d" % (prefix, index), (0.0, LADDER_RAIL_Y, z), 0.026, LADDER_RAIL_X * 2.0, 8,
                 rust if index % 3 == 1 else iron, 3, count, objects, rotation=(0.0, math.pi / 2.0, 0.0))
        z += rung_step
        index += 1


def make_sewer_ladder():
    """Iron rungs from the sewer floor to the vault (3.2 m); the shaft above carries sewer_ladder_top."""
    iron, rust, _, _, count = sewer_materials("sewer_ladder")
    objects = []
    _ladder_section(objects, iron, rust, count, 0.0, 3.2, 0.28, 0.30, "")
    for index, z in enumerate((0.55, 1.65, 2.75)):
        for side, x in (("L", -LADDER_RAIL_X), ("R", LADDER_RAIL_X)):
            box("Bracket%d%s" % (index, side), (x, 0.455, z), (0.06, 0.09, 0.06), rust, 1, count, objects)
    return objects, (2.4, -3.0, 2.2), (0.0, 0.3, 1.5)


def make_sewer_ladder_top():
    """The ladder's last 0.8 m in the shaft under the maze floor, and grab hoops above the opening."""
    iron, rust, _, _, count = sewer_materials("sewer_ladder_top")
    objects = []
    _ladder_section(objects, iron, rust, count, -0.8, 0.0, -0.62, 0.30, "")
    # grab rails: the stiles carry on 1.15 m above the opening and bend back to the wall, a full
    # handhold for stepping on or off at person height
    for side, x in (("L", -LADDER_RAIL_X), ("R", LADDER_RAIL_X)):
        box("HoopUp%s" % side, (x, LADDER_RAIL_Y, 0.575), (0.07, 0.07, 1.15), iron, 2, count, objects, bevel=0.008)
        box("HoopTop%s" % side, (x, LADDER_RAIL_Y + 0.06, 1.15), (0.07, 0.19, 0.07), iron, 2, count, objects, bevel=0.008)
        box("HoopMid%s" % side, (x, LADDER_RAIL_Y + 0.06, 0.6), (0.06, 0.16, 0.06), rust, 1, count, objects)
        box("HoopFoot%s" % side, (x, 0.47, 0.04), (0.09, 0.06, 0.08), rust, 1, count, objects)
    return objects, (2.0, -2.6, 1.4), (0.0, 0.3, 0.1)


def _shaft_collar(objects, iron, count, prefix):
    # a cast iron frame flush on the floor around the 1 x 1 m opening
    for name, loc, dim in (("N", (0.0, 0.46, 0.012), (1.0, 0.08, 0.024)),
                           ("S", (0.0, -0.46, 0.012), (1.0, 0.08, 0.024)),
                           ("E", (0.46, 0.0, 0.012), (0.08, 0.84, 0.024)),
                           ("W", (-0.46, 0.0, 0.012), (0.08, 0.84, 0.024))):
        box(prefix + name, loc, dim, iron, 2, count, objects, bevel=0.004)


def make_manhole_frame():
    """Open manhole: frame round the shaft and the heavy round lid dragged aside onto the hall floor."""
    iron, rust, _, _, count = sewer_materials("manhole_frame")
    objects = []
    _shaft_collar(objects, iron, count, "Frame")
    cylinder("Lid", (0.0, -0.98, 0.022), 0.38, 0.044, 20, iron, 2, count, objects, bevel=0.006)
    for index, x in enumerate((-0.24, -0.12, 0.0, 0.12, 0.24)):
        box("LidRib%d" % index, (x, -0.98, 0.048), (0.03, 0.56 - abs(x) * 1.1, 0.008), rust, 3, count, objects)
    box("PryNotch", (0.30, -0.98, 0.046), (0.06, 0.03, 0.01), iron, 0, count, objects)
    return objects, (1.6, -2.8, 1.8), (0.0, -0.4, 0.0)


def make_sewer_floor_grate():
    """Open floor grate: the barred grate swung up on its hinge against the shaft's north side."""
    iron, rust, _, _, count = sewer_materials("sewer_floor_grate")
    objects = []
    _shaft_collar(objects, iron, count, "Frame")
    tilt = math.radians(-14.0)
    hinge_y = 0.46
    for index, x in enumerate((-0.36, -0.24, -0.12, 0.0, 0.12, 0.24, 0.36)):
        box("Bar%d" % index, (x, hinge_y + 0.10, 0.45), (0.035, 0.035, 0.86), iron, 2, count, objects,
            rotation=(tilt, 0.0, 0.0))
    for index, z in enumerate((0.08, 0.45, 0.82)):
        box("Cross%d" % index, (0.0, hinge_y + 0.03 + z * 0.24, z), (0.80, 0.04, 0.04), rust, 3, count, objects,
            rotation=(tilt, 0.0, 0.0))
    for side, x in (("L", -0.42), ("R", 0.42)):
        cylinder("Hinge%s" % side, (x, hinge_y, 0.04), 0.03, 0.08, 8, iron, 1, count, objects,
                 rotation=(0.0, math.pi / 2.0, 0.0))
    return objects, (1.8, -2.6, 1.6), (0.0, 0.2, 0.4)


def make_sewer_valve_wheel():
    """A gate valve on the wall: pipe stub out of the brick, bonnet, and the big hand wheel facing out."""
    iron, rust, _, _, count = sewer_materials("sewer_valve_wheel")
    objects = []
    cylinder("Stub", (0.0, 0.32, 0.0), 0.09, 0.36, 12, iron, 2, count, objects, rotation=(math.pi / 2.0, 0.0, 0.0))
    box("Flange", (0.0, 0.48, 0.0), (0.30, 0.04, 0.30), rust, 1, count, objects, bevel=0.006)
    box("Bonnet", (0.0, 0.12, 0.0), (0.16, 0.14, 0.16), iron, 2, count, objects, bevel=0.01)
    cylinder("Stem", (0.0, -0.02, 0.0), 0.02, 0.18, 8, iron, 3, count, objects, rotation=(math.pi / 2.0, 0.0, 0.0))
    radius = 0.21
    for index in range(10):
        a = index * math.tau / 10.0
        # each rim segment lies along the circle's tangent in the wheel's (x, z) plane
        box("Rim%d" % index, (math.cos(a) * radius, -0.11, math.sin(a) * radius), (0.14, 0.035, 0.035),
            rust if index % 2 else iron, 5, count, objects, rotation=(0.0, -(a + math.pi / 2.0), 0.0))
    for index in range(4):
        a = index * math.pi / 4.0 + math.pi / 8.0
        box("Spoke%d" % index, (0.0, -0.11, 0.0), (radius * 2.0, 0.025, 0.025), iron, 3, count, objects,
            rotation=(0.0, -a, 0.0))
    box("Hub", (0.0, -0.11, 0.0), (0.07, 0.05, 0.07), iron, 2, count, objects)
    return objects, (1.2, -1.6, 0.6), (0.0, 0.1, 0.0)


def make_sewer_pump():
    """A pump set on a concrete plinth: motor, volute casing, suction and discharge pipes into the wall."""
    iron, rust, concrete, _, count = sewer_materials("sewer_pump")
    objects = []
    box("Plinth", (0.0, 0.0, 0.08), (1.30, 0.90, 0.16), concrete, 4, count, objects, bevel=0.01)
    cylinder("Motor", (-0.28, 0.0, 0.46), 0.24, 0.62, 14, iron, 2, count, objects, rotation=(0.0, math.pi / 2.0, 0.0))
    for index, x in enumerate((-0.52, -0.40, -0.28, -0.16, -0.04)):
        box("Fin%d" % index, (x, 0.0, 0.72), (0.03, 0.40, 0.04), iron, 3, count, objects)
    box("MotorFoot", (-0.28, 0.0, 0.22), (0.56, 0.42, 0.10), rust, 1, count, objects)
    cylinder("Volute", (0.30, 0.0, 0.48), 0.30, 0.30, 16, rust, 5, count, objects, rotation=(0.0, math.pi / 2.0, 0.0))
    box("Coupling", (0.04, 0.0, 0.46), (0.14, 0.18, 0.18), iron, 6, count, objects)
    cylinder("Discharge", (0.30, 0.0, 1.02), 0.09, 0.80, 10, iron, 2, count, objects)
    cylinder("DischargeBend", (0.30, 0.22, 1.40), 0.09, 0.44, 10, iron, 2, count, objects,
             rotation=(math.pi / 2.0, 0.0, 0.0))
    cylinder("Suction", (0.30, 0.30, 0.40), 0.11, 0.30, 10, iron, 3, count, objects,
             rotation=(math.pi / 2.0, 0.0, 0.0))
    box("Gauge", (0.30, -0.16, 0.86), (0.10, 0.03, 0.10), iron, 7, count, objects)
    return objects, (2.4, -2.6, 1.8), (0.0, 0.0, 0.6)


def make_sewer_pipe_run():
    """Two cast iron mains along a wall with clamp brackets, 2 m long."""
    iron, rust, _, _, count = sewer_materials("sewer_pipe_run")
    objects = []
    for index, (z, r) in enumerate(((0.0, 0.11), (0.30, 0.07))):
        cylinder("Main%d" % index, (0.0, 0.30, z), r, 2.0, 12, rust if index else iron, 2 + index, count, objects,
                 rotation=(0.0, math.pi / 2.0, 0.0))
        for j, x in enumerate((-0.8, 0.0, 0.8)):
            box("Collar%d%d" % (index, j), (x, 0.30, z), (0.05, r * 2.3, r * 2.3), iron, 1, count, objects)
    for j, x in enumerate((-0.8, 0.8)):
        box("Bracket%d" % j, (x, 0.44, 0.15), (0.05, 0.12, 0.50), iron, 1, count, objects)
    return objects, (1.8, -2.4, 1.0), (0.0, 0.3, 0.1)


## The outflow main's underside sits at SewerRouteGenerator.CRAWL_CLEARANCE (the crouched capsule, 1.08 m x
## PlayerModels.SCALE, read from game/config/player_models.gd, + 5 cm): a crouched runner passes under it, nothing taller
## does. Rebuild sewer_outflow_pipe and sewer_outflow_pipe_broken whenever PlayerModels.SCALE changes (sewer_crawl checks).
def _player_scale():
    import re
    with open(os.path.join(PROJECT_ROOT, "src", "config", "player_models.gd")) as handle:
        return float(re.search(r"const SCALE := ([0-9.]+)", handle.read()).group(1))


OUTFLOW_CLEARANCE = 1.08 * _player_scale() + 0.05
OUTFLOW_VAULT = 3.2


def make_sewer_outflow_pipe():
    """A 1.5 m rusted outflow main: out of the tunnel wall (Blender +Y) through a riveted wall plate, straight across the
    3 m walkway on two vault straps, over the channel railing, then down a long-radius elbow into the channel, its foot
    under the water. Origin: the middle walkway cell on the floor (the wall face at y = 1.5, the channel edge at -1.5)."""
    iron, rust, concrete, _, count = sewer_materials("sewer_outflow_pipe")
    objects = []
    radius = 0.75
    flange = 0.82
    cz = OUTFLOW_CLEARANCE + flange
    axis = (math.pi / 2.0, 0.0, 0.0)
    # the run: buried 0.6 m in the brick, out to the bend over the channel edge
    for index, (y0, y1) in enumerate(((2.10, 0.60), (0.60, -0.50), (-0.50, -1.58))):
        cylinder("Barrel%d" % index, (0.0, (y0 + y1) * .5, cz), radius, y0 - y1, 20, rust if index != 1 else iron,
                 4 + index % 2, count, objects, rotation=axis)
    # the wall plate it comes through: square, riveted, never lower than the main's underside (the crawl clearance)
    box("WallPlate", (0.0, 1.47, cz), (1.90, 0.06, flange * 2.0), concrete, 3, count, objects, bevel=0.01)
    box("WallFlange", (0.0, 1.40, cz), (flange * 2.0, 0.08, flange * 2.0), iron, 2, count, objects, bevel=0.01)
    for bolt in range(8):
        a = bolt * math.tau / 8.0 + math.pi / 8.0
        box("PlateBolt%d" % bolt, (math.cos(a) * 0.86, 1.43, cz + math.sin(a) * (flange - 0.06)), (0.06, 0.06, 0.06),
            rust, 6, count, objects)
    for name, y in (("FlangeA", 0.60), ("FlangeB", -0.50)):
        cylinder(name, (0.0, y, cz), flange, 0.12, 20, iron, 2, count, objects, rotation=axis, bevel=0.01)
        for bolt in range(12):
            a = bolt * math.tau / 12.0
            box("%sBolt%02d" % (name, bolt), (math.cos(a) * (flange - 0.05), y, cz + math.sin(a) * (flange - 0.05)),
                (0.05, 0.16, 0.05), rust, 6, count, objects)
    # the elbow down into the channel: three mitred segments on a 0.95 m bend, then the drop to below the water
    bend = 0.95
    y_bend = -1.58
    for index, degrees in enumerate((15.0, 45.0, 75.0)):
        t = math.radians(degrees)
        cylinder("Elbow%d" % index, (0.0, y_bend - bend * math.sin(t), cz - bend * (1.0 - math.cos(t))), radius,
                 bend * math.pi / 6.0 + 0.06, 20, rust, 4 + index % 2, count, objects,
                 rotation=(math.pi / 2.0 + t, 0.0, 0.0))
    drop_top = cz - bend
    drop_foot = -0.75     # the bed lies 1.0 m down, the water surface 0.3 m: its foot stands in the flow
    drop_y = y_bend - bend
    cylinder("Drop", (0.0, drop_y, (drop_top + drop_foot) * .5), radius, drop_top - drop_foot, 20, iron, 5, count,
             objects)
    cylinder("DropFlange", (0.0, drop_y, drop_top - 0.05), flange, 0.12, 20, iron, 2, count, objects, bevel=0.01)
    for index, x in enumerate((-0.32, 0.10, 0.41)):
        box("RustStreak%d" % index, (x, -0.95 + index * 0.55, cz + radius - 0.01), (0.07, 0.42, 0.02), rust, 5,
            count, objects)
    top = cz + radius
    for index, y in enumerate((0.05, -1.10)):
        cylinder("Strap%d" % index, (0.0, y, cz), radius + 0.03, 0.07, 20, iron, 1, count, objects, rotation=axis)
        box("Hanger%d" % index, (0.0, y, (top + OUTFLOW_VAULT) * .5), (0.06, 0.06, OUTFLOW_VAULT - top), iron, 2,
            count, objects)
        box("HangerPlate%d" % index, (0.0, y, OUTFLOW_VAULT - 0.02), (0.22, 0.22, 0.04), rust, 1, count, objects)
    # a third strap round the drop, hung from the vault over the channel
    box("DropBand", (0.0, drop_y, drop_top - 0.35), (flange * 2.0, flange * 2.0, 0.07), iron, 1, count, objects)
    box("DropHanger", (0.0, drop_y - radius - 0.06, (drop_top - 0.35 + OUTFLOW_VAULT) * .5),
        (0.06, 0.06, OUTFLOW_VAULT - drop_top + 0.35), iron, 2, count, objects)
    return objects, (3.6, -3.4, 2.4), (0.0, -0.8, 1.2)


def make_sewer_outflow_pipe_broken():
    """The outflow main after the Axe: the riveted wall plate and a torn stub of barrel sticking 0.55 m out of it, its
    end a ring of jagged shell teeth round the dark bore, and the first vault hanger with its strap snapped. Same origin
    and frame as sewer_outflow_pipe (the wall face at y = 1.5); everything stays above the crawl clearance."""
    iron, rust, concrete, _, count = sewer_materials("sewer_outflow_pipe_broken")
    objects = []
    radius = 0.75
    flange = 0.82
    cz = OUTFLOW_CLEARANCE + flange
    axis = (math.pi / 2.0, 0.0, 0.0)
    stub_end = 0.95
    cylinder("Stub", (0.0, (2.10 + stub_end) * .5, cz), radius, 2.10 - stub_end, 20, rust, 4, count, objects,
             rotation=axis)
    box("WallPlate", (0.0, 1.47, cz), (1.90, 0.06, flange * 2.0), concrete, 3, count, objects, bevel=0.01)
    box("WallFlange", (0.0, 1.40, cz), (flange * 2.0, 0.08, flange * 2.0), iron, 2, count, objects, bevel=0.01)
    for bolt in range(8):
        a = bolt * math.tau / 8.0 + math.pi / 8.0
        box("PlateBolt%d" % bolt, (math.cos(a) * 0.86, 1.43, cz + math.sin(a) * (flange - 0.06)), (0.06, 0.06, 0.06),
            rust, 6, count, objects)
    # the torn end: shell teeth of uneven length round the rim, bent a little outward
    teeth = (0.34, 0.12, 0.42, 0.22, 0.08, 0.30, 0.18, 0.40, 0.10, 0.26, 0.36, 0.14)
    for index, length in enumerate(teeth):
        a = index * math.tau / len(teeth)
        flare = 0.05 if index % 3 == 0 else 0.0
        box("Tooth%02d" % index, (math.cos(a) * (radius + flare), stub_end - length * .5, cz + math.sin(a) * (radius + flare)),
            (0.30, length, 0.04), rust if index % 2 else iron, 4 + index % 2, count, objects,
            rotation=(0.0, -a + math.pi / 2.0, 0.0))
    # the dark bore over the stub's end face, leaving only a thin rim of shell, so the end reads open, not capped
    cylinder("Bore", (0.0, stub_end - 0.012, cz), radius - 0.05, 0.02, 20, iron, 0, count, objects, rotation=axis)
    top = cz + radius
    box("Hanger0", (0.0, 1.10, (top + OUTFLOW_VAULT) * .5), (0.06, 0.06, OUTFLOW_VAULT - top), iron, 2, count, objects)
    box("HangerPlate0", (0.0, 1.10, OUTFLOW_VAULT - 0.02), (0.22, 0.22, 0.04), rust, 1, count, objects)
    box("SnappedStrap", (0.30, 1.10, top - 0.02), (0.55, 0.07, 0.03), iron, 1, count, objects, rotation=(0.0, 0.35, 0.0))
    return objects, (2.2, -1.6, 2.6), (0.0, 1.0, 1.8)


def make_sewer_sluice_gate():
    """A lifting sluice leaf across the 3 m channel: two iron posts with a counterweight beam on the hinge side
    (Blender +Y, the walkway edge at y = 1.5), two seat bollards on the far side, and the riveted leaf "Leaf" authored
    LOWERED (flat, its walking surface at z = 0, spanning the channel). The view hinges it up to stand upright while the
    sluice is shut. Origin: the middle channel cell at walkway floor level."""
    iron, rust, concrete, _, count = sewer_materials("sewer_sluice_gate")
    objects = []
    half = 0.68
    # the leaf: one joined object so it hinges as a piece (frame, plate, cross ribs, kick plates)
    leaf_parts = []
    box("LeafPlate", (0.0, 0.0, -0.04), (half * 2.0, 3.0, 0.08), rust, 4, count, leaf_parts, bevel=0.006)
    for index, y in enumerate((-1.1, -0.35, 0.35, 1.1)):
        box("LeafRib%d" % index, (0.0, y, -0.12), (half * 2.0, 0.06, 0.08), iron, 2, count, leaf_parts)
    for side, x in (("L", -half), ("R", half)):
        box("LeafKick%s" % side, (x, 0.0, 0.06), (0.05, 3.0, 0.12), iron, 1, count, leaf_parts)
        for j, y in enumerate((-1.2, -0.4, 0.4, 1.2)):
            box("LeafRivet%s%d" % (side, j), (x * 0.9, y, 0.005), (0.04, 0.04, 0.02), rust, 6, count, leaf_parts)
    bpy.ops.object.select_all(action="DESELECT")
    for part in leaf_parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = leaf_parts[0]
    bpy.ops.object.join()
    leaf = bpy.context.view_layer.objects.active
    leaf.name = "Leaf"
    objects.append(leaf)
    # hinge side: posts, the hinge pin and a counterweight beam overhead
    for side, x in (("L", -half - 0.14), ("R", half + 0.14)):
        box("Post%s" % side, (x, 1.62, 1.3), (0.14, 0.14, 2.6), iron, 2, count, objects, bevel=0.008)
        box("PostFoot%s" % side, (x, 1.62, 0.03), (0.3, 0.3, 0.06), concrete, 3, count, objects)
    cylinder("HingePin", (0.0, 1.5, 0.0), 0.06, half * 2.0 + 0.4, 10, iron, 1, count, objects,
             rotation=(0.0, math.pi / 2.0, 0.0))
    box("Header", (0.0, 1.62, 2.66), (half * 2.0 + 0.5, 0.18, 0.14), iron, 2, count, objects, bevel=0.008)
    box("Counterweight", (0.0, 1.62, 2.4), (0.7, 0.3, 0.38), concrete, 4, count, objects, bevel=0.01)
    # far side: the leaf's seat
    for side, x in (("L", -half + 0.1), ("R", half - 0.1)):
        box("Seat%s" % side, (x, -1.58, -0.1), (0.16, 0.16, 0.2), iron, 2, count, objects)
    return objects, (3.6, -2.6, 2.6), (0.0, 0.0, 0.8)


def make_sewer_overflow_grate():
    """Barred weir across the overflow chamber's basin: a low iron screen standing in the water."""
    iron, rust, concrete, _, count = sewer_materials("sewer_overflow_grate")
    objects = []
    box("Sill", (0.0, 0.0, 0.06), (3.0, 0.22, 0.12), concrete, 4, count, objects, bevel=0.01)
    for index in range(15):
        x = -1.40 + index * 0.20
        box("Bar%02d" % index, (x, 0.0, 0.44), (0.04, 0.04, 0.68), rust if index % 4 == 0 else iron, 2, count, objects)
    box("TopRail", (0.0, 0.0, 0.80), (3.0, 0.07, 0.06), iron, 3, count, objects, bevel=0.006)
    for side, x in (("L", -1.52), ("R", 1.52)):
        box("Post%s" % side, (x, 0.0, 0.45), (0.10, 0.12, 0.90), iron, 1, count, objects)
    return objects, (3.6, -3.4, 2.0), (0.0, 0.0, 0.4)


def make_sewer_lamp():
    """Caged bulkhead lamp on the brick: back plate, amber glass, iron cage."""
    iron, rust, _, image, count = sewer_materials("sewer_lamp")
    objects = []
    glow = make_material("sewer_lamp glow", image, roughness=0.4, metallic=0.0)
    bsdf = glow.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None and "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = rgba("#FFB347")
        bsdf.inputs["Emission Strength"].default_value = 2.2
    box("BackPlate", (0.0, 0.46, 0.0), (0.24, 0.06, 0.30), rust, 1, count, objects, bevel=0.008)
    cylinder("Glass", (0.0, 0.36, 0.0), 0.075, 0.16, 12, glow, 7, count, objects, rotation=(math.pi / 2.0, 0.0, 0.0))
    for index, x in enumerate((-0.09, 0.0, 0.09)):
        box("CageV%d" % index, (x, 0.27, 0.0), (0.016, 0.016, 0.22), iron, 2, count, objects)
    for index, z in enumerate((-0.10, 0.10)):
        box("CageH%d" % index, (0.0, 0.27, z), (0.20, 0.016, 0.016), iron, 2, count, objects)
        for side, x in (("L", -0.10), ("R", 0.10)):
            box("CageArm%d%s" % (index, side), (x, 0.36, z), (0.016, 0.18, 0.016), iron, 2, count, objects)
    return objects, (0.9, -1.3, 0.5), (0.0, 0.3, 0.0)


def _grate_deck(objects, iron, rust, count, prefix, half=1.5, slat=0.15):
    """A 3 x 3 m grated deck whose walking surface is z = 0: a frame and open slats you can see the water through."""
    t = 0.10
    for name, loc, dim in (("FrameN", (0.0, half - 0.05, -t * .5), (half * 2, 0.10, t)),
                           ("FrameS", (0.0, -half + 0.05, -t * .5), (half * 2, 0.10, t)),
                           ("FrameE", (half - 0.05, 0.0, -t * .5), (0.10, half * 2, t)),
                           ("FrameW", (-half + 0.05, 0.0, -t * .5), (0.10, half * 2, t))):
        box(prefix + name, loc, dim, iron, 2, count, objects, bevel=0.006)
    index = 0
    x = -half + 0.10 + slat * .5
    while x < half - 0.10:
        box("%sSlat%02d" % (prefix, index), (x, 0.0, -0.035), (0.035, half * 2 - 0.2, 0.07),
            rust if index % 5 == 2 else iron, 3, count, objects)
        x += slat
        index += 1
    for j, y in enumerate((-0.75, 0.0, 0.75)):
        box("%sCrossbar%d" % (prefix, j), (0.0, y, -0.06), (half * 2 - 0.2, 0.05, 0.04), iron, 1, count, objects)


def make_sewer_bridge():
    """Tunnel crossing: a 3 x 3 m riveted grate deck spanning the channel (span along local z) on two deep girders
    that bear on the walkway edges, with kick plates along its open sides. Railings are added by the level."""
    iron, rust, concrete, _, count = sewer_materials("sewer_bridge")
    objects = []
    _grate_deck(objects, iron, rust, count, "Deck")
    for side, x in (("L", -1.15), ("R", 1.15)):
        box("Girder%s" % side, (x, 0.0, -0.32), (0.10, 3.8, 0.36), iron, 2, count, objects, bevel=0.008)
        box("Flange%s" % side, (x, 0.0, -0.13), (0.24, 3.8, 0.04), rust, 5, count, objects)
        box("FlangeLow%s" % side, (x, 0.0, -0.49), (0.24, 3.8, 0.04), iron, 1, count, objects)
        for j, y in enumerate((-1.6, -0.8, 0.0, 0.8, 1.6)):
            box("Rivet%s%d" % (side, j), (x + (0.06 if x > 0 else -0.06), y, -0.32), (0.02, 0.05, 0.05), rust, 6,
                count, objects)
        box("Kick%s" % side, (x * 1.27, 0.0, 0.06), (0.04, 3.0, 0.12), rust, 5, count, objects)
    for side, y in (("N", 1.75), ("S", -1.75)):
        box("Bearing%s" % side, (0.0, y, -0.55), (2.6, 0.3, 0.12), concrete, 4, count, objects, bevel=0.01)
    for j, y in enumerate((-1.0, 1.0)):
        box("Brace%d" % j, (0.0, y, -0.44), (2.2, 0.06, 0.06), iron, 1, count, objects)
    return objects, (3.6, -4.2, 2.6), (0.0, 0.0, -0.2)


def make_sewer_grate_deck():
    """Junction plaza tile: a 3 x 3 m grate panel over the confluence on a beam grid; neighbouring tiles butt up."""
    iron, rust, _, _, count = sewer_materials("sewer_grate_deck")
    objects = []
    _grate_deck(objects, iron, rust, count, "Deck")
    for j, x in enumerate((-1.45, 0.0, 1.45)):
        box("BeamX%d" % j, (x, 0.0, -0.24), (0.08, 3.0, 0.28), iron, 2, count, objects)
    for j, y in enumerate((-1.45, 1.45)):
        box("BeamY%d" % j, (0.0, y, -0.24), (3.0, 0.08, 0.28), iron, 2, count, objects)
    return objects, (3.4, -4.0, 2.4), (0.0, 0.0, -0.2)


SEWER_BUILDERS = {
    "sewer_bridge": make_sewer_bridge,
    "sewer_grate_deck": make_sewer_grate_deck,
    "sewer_ladder": make_sewer_ladder,
    "sewer_ladder_top": make_sewer_ladder_top,
    "manhole_frame": make_manhole_frame,
    "sewer_floor_grate": make_sewer_floor_grate,
    "sewer_valve_wheel": make_sewer_valve_wheel,
    "sewer_pump": make_sewer_pump,
    "sewer_pipe_run": make_sewer_pipe_run,
    "sewer_outflow_pipe": make_sewer_outflow_pipe,
    "sewer_outflow_pipe_broken": make_sewer_outflow_pipe_broken,
    "sewer_sluice_gate": make_sewer_sluice_gate,
    "sewer_overflow_grate": make_sewer_overflow_grate,
    "sewer_lamp": make_sewer_lamp,
}


requested = set(sys.argv[sys.argv.index("--") + 1:]) if "--" in sys.argv else set(BUILDERS)
for model_name, builder in BUILDERS.items():
    if model_name not in requested:
        continue
    clear_scene()
    export_objects, eye, look = builder()
    save_and_export(model_name, export_objects)
    if model_name in {"battery", "flashlight_item", "taser_item", "lockpick_set",
                      "crowbar", "rescue_axe", "revive_kit", "stim_pack", "backpack_small",
                      "backpack_medium", "backpack_large"}:
        render_inventory_icon(model_name, eye, look)
    render_preview(model_name, export_objects, eye, look)
    print("BUILT", model_name, len(export_objects))

for model_name, builder in MAZE_BUILDERS.items():
    if "maze" not in requested and model_name not in requested:
        continue
    clear_scene()
    export_objects, eye, look = builder()
    save_and_export(model_name, export_objects, MAZE_ROOT, MAZE_SOURCE)
    render_preview(model_name, export_objects, eye, look, MAZE_PREVIEWS)
    print("BUILT", model_name, len(export_objects))

for model_name, builder in MANSION_BUILDERS.items():
    if "mansion" not in requested and model_name not in requested:
        continue
    clear_scene()
    export_objects, eye, look = builder()
    save_and_export(model_name, export_objects, MANSION_ROOT, MANSION_SOURCE)
    render_preview(model_name, export_objects, eye, look, MANSION_PREVIEWS)
    print("BUILT", model_name, len(export_objects))

for model_name, builder in BEACH_BUILDERS.items():
    if "beach" not in requested and model_name not in requested:
        continue
    clear_scene()
    export_objects, eye, look = builder()
    save_and_export(model_name, export_objects, BEACH_ROOT, BEACH_SOURCE)
    render_preview(model_name, export_objects, eye, look, BEACH_PREVIEWS)
    print("BUILT", model_name, len(export_objects))

for model_name, builder in NETHER_BUILDERS.items():
    if "nether" not in requested and model_name not in requested:
        continue
    clear_scene()
    export_objects, eye, look = builder()
    save_and_export(model_name, export_objects, NETHER_ROOT, NETHER_SOURCE)
    render_preview(model_name, export_objects, eye, look, NETHER_PREVIEWS)
    print("BUILT", model_name, len(export_objects))

for model_name, builder in PRISON_BUILDERS.items():
    if "prison" not in requested and model_name not in requested:
        continue
    clear_scene()
    export_objects, eye, look = builder()
    save_and_export(model_name, export_objects, PRISON_ROOT, PRISON_SOURCE)
    render_preview(model_name, export_objects, eye, look, PRISON_PREVIEWS)
    print("BUILT", model_name, len(export_objects))

for model_name, builder in CARNIVAL_BUILDERS.items():
    if "carnival" not in requested and model_name not in requested:
        continue
    clear_scene()
    export_objects, eye, look = builder()
    save_and_export(model_name, export_objects, CARNIVAL_ROOT, CARNIVAL_SOURCE)
    render_preview(model_name, export_objects, eye, look, CARNIVAL_PREVIEWS)
    print("BUILT", model_name, len(export_objects))

for model_name, builder in SEWER_BUILDERS.items():
    if "sewer" not in requested and model_name not in requested:
        continue
    clear_scene()
    export_objects, eye, look = builder()
    save_and_export(model_name, export_objects, SEWER_ROOT, SEWER_SOURCE)
    render_preview(model_name, export_objects, eye, look, SEWER_PREVIEWS)
    print("BUILT", model_name, len(export_objects))
