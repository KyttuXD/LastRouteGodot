import glob
import json
import os
import struct
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))

# Scale contracts are measured against the imported hunter roster: a 1.70 m
# body with character-specific silhouettes reaching as high as 2.20 m.  These
# broad families protect the props whose usability depends on human scale;
# decorative tabletop and ground dressing intentionally varies more widely.
HUNTER_SCALE_HEIGHTS = {
    "hiding_spot": (1.80, 2.10),
    "arcade_cabinet_": (1.75, 2.00),
    "filing_cabinet": (1.10, 1.50),
    "floor_lamp": (1.55, 2.00),
    "lounge_couch_": (0.80, 1.10),
    "privacy_curtain": (2.30, 2.55),
    "server_rack": (1.80, 2.20),
    "supply_crates": (0.75, 1.15),
    "trash_bin": (0.55, 0.85),
    "vending_machine": (1.70, 2.10),
    "wooden_chair_": (0.90, 1.25),
    "wooden_dresser_sideboard": (0.80, 1.15),
    "wooden_table": (0.72, 0.90),
    "bathroom_mirror": (1.10, 1.35),
    "bathroom_sink": (1.10, 1.45),
    "bathroom_stall": (1.80, 2.10),
    "bathroom_vanity": (1.55, 1.90),
    "public_restroom_toilet": (1.10, 1.35),
    "public_mens_urinal": (1.00, 1.25),
    "public_sink_bank": (1.20, 1.40),
    "public_hand_dryer": (0.35, 0.55),
    "public_soap_dispenser": (0.35, 0.50),
    "public_paper_towel_dispenser": (0.60, 0.80),
    "public_baby_change_station": (0.60, 1.00),
    "public_sanitary_bin": (0.60, 0.80),
    "public_mens_room_sign": (0.65, 0.85),
    "public_womens_room_sign": (0.65, 0.85),
    "public_mens_shower_stall": (2.00, 2.30),
    "public_womens_shower_stall": (2.00, 2.30),
    "public_shower_bench": (0.50, 0.70),
    "house_bathtub": (0.85, 1.10),
    "house_toilet": (1.10, 1.35),
    "house_shower_enclosure": (2.00, 2.30),
    "house_medicine_cabinet": (0.70, 0.90),
    "house_towel_rack": (0.50, 0.75),
    "house_bath_mat": (0.05, 0.12),
    "house_bathroom_shelf": (0.90, 1.15),
	"grand_staircase": (1.75, 2.05),
	"grand_foyer_staircase": (2.65, 3.05),
    "bedroom_bench": (0.50, 0.80),
    "bedroom_dresser": (0.90, 1.20),
    "bedroom_nightstand": (0.60, 0.85),
    "bedroom_vanity": (1.65, 2.00),
    "dining_chair_": (1.05, 1.35),
    "grand_dining_table": (0.95, 1.15),
    "bedroom_wardrobe": (1.95, 2.30),
    "gothic_highback_chair_": (1.90, 2.30),
    "gothic_nightstand_": (0.65, 0.95),
    "gothic_vanity_stool_": (0.50, 0.75),
    "gothic_vanity_": (1.90, 2.30),
    "gothic_wardrobe_": (2.30, 2.75),
    "mansion_coat_rack": (1.80, 2.20),
    "mansion_console_table": (0.75, 1.05),
    "mansion_grandfather_clock": (1.95, 2.35),
    "mansion_rocking_chair": (1.35, 1.75),
    "mansion_tea_cart": (0.85, 1.20),
    "beach_chair": (1.15, 1.55),
    "beach_umbrella": (2.55, 2.75),
    "surfboard_rack": (1.45, 1.90),
    "tiki_bar": (2.20, 2.60),
    "palm_tree": (3.40, 4.10),
    "frozen_beach_hut": (2.60, 2.95),
    "sand_castle": (0.65, 0.95),
    "normal_bookcase": (1.70, 2.00),
    "normal_coffee_table": (0.40, 0.60),
    "normal_tv_console": (1.35, 1.65),
    "normal_entry_bench": (1.20, 1.50),
    "mansion_display_cabinet": (2.05, 2.35),
    "mansion_chaise_lounge": (0.95, 1.30),
    "mansion_upright_piano": (1.45, 1.75),
    "mansion_bust_pedestal": (1.85, 2.15),
}
for kitchen_style in ("normal", "luxury", "gothic"):
    HUNTER_SCALE_HEIGHTS.update({
        "%s_kitchen_counter" % kitchen_style: (0.95, 1.20),
        "%s_kitchen_sink" % kitchen_style: (1.25, 1.50),
        "%s_kitchen_stove" % kitchen_style: (0.90, 1.10),
        "%s_kitchen_fridge" % kitchen_style: (1.85, 2.20),
        "%s_kitchen_wall_cabinet" % kitchen_style: (0.80, 1.05),
        "%s_kitchen_island" % kitchen_style: (0.90, 1.10),
    })


def validate_hunter_scale(name, low, high):
    height = high[2] - low[2]
    for prefix, limits in HUNTER_SCALE_HEIGHTS.items():
        if name == prefix or name.startswith(prefix):
            if not limits[0] <= height <= limits[1]:
                raise RuntimeError(
                    f"{name}: {height:.3f} m high, expected {limits[0]:.2f}-"
                    f"{limits[1]:.2f} m beside 1.70-2.20 m hunters"
                )
            break

    size = tuple(high[index] - low[index] for index in range(3))
    if name == "beach_umbrella" and min(size[0], size[1]) < 2.20:
        raise RuntimeError(
            f"{name}: {size[0]:.3f}x{size[1]:.3f} m canopy cannot "
            "shelter two hunters side by side"
        )
    if name.startswith("single_bed_"):
        if size[0] < 1.05 or size[1] < 2.40:
            raise RuntimeError(
                f"{name}: {size[0]:.3f}x{size[1]:.3f} m bed cannot "
                "comfortably contain the 0.65x2.20 m hunter silhouette"
            )
    elif name.startswith("double_bed_") or name.startswith("gothic_double_bed_"):
        if size[0] < 1.75 or size[1] < 2.40:
            raise RuntimeError(
                f"{name}: {size[0]:.3f}x{size[1]:.3f} m bed cannot "
                "comfortably contain the 0.65x2.20 m hunter silhouette"
            )
    elif name.startswith("lounge_couch_") and name.endswith("_wide"):
        if size[0] < 1.75:
            raise RuntimeError(
                f"{name}: {size[0]:.3f} m is too narrow for two 0.65 m "
                "hunter silhouettes plus arm clearance"
            )

    if name == "wall_sconce" and not (low[2] >= 1.10 and high[2] >= 1.80):
        raise RuntimeError(
            f"wall_sconce: mounted bounds {low[2]:.3f}-{high[2]:.3f} m "
            "sit below hunter chest/eye height"
        )
    if name.endswith("_kitchen_wall_cabinet") \
            and not (low[2] >= 1.20 and 2.00 <= high[2] <= 2.30):
        raise RuntimeError(
            f"{name}: mounted bounds {low[2]:.3f}-{high[2]:.3f} m are not "
            "comfortable above a hunter-scale worktop"
        )

    mounted_bathroom_ranges = {
        "public_hand_dryer": (1.10, 1.50, 1.70),
        "public_soap_dispenser": (0.95, 1.30, 1.50),
        "public_paper_towel_dispenser": (0.90, 1.55, 1.80),
        "public_mens_room_sign": (1.15, 1.85, 2.05),
        "public_womens_room_sign": (1.15, 1.85, 2.05),
        "house_medicine_cabinet": (1.00, 1.75, 2.00),
        "house_towel_rack": (0.75, 1.30, 1.55),
        "house_bathroom_shelf": (0.95, 1.85, 2.10),
    }
    if name in mounted_bathroom_ranges:
        minimum_low, minimum_high, maximum_high = mounted_bathroom_ranges[name]
        if low[2] < minimum_low or not minimum_high <= high[2] <= maximum_high:
            raise RuntimeError(
                f"{name}: mounted bounds {low[2]:.3f}-{high[2]:.3f} m "
                "do not match hunter reach/eye height"
            )


def validate_blend(path):
    bpy.ops.wm.open_mainfile(filepath=path)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    extras = [obj.name for obj in bpy.context.scene.objects if obj.type in {"CAMERA", "LIGHT"}]
    corners = []
    for obj in meshes:
        corners.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    low = tuple(round(min(v[i] for v in corners), 3) for i in range(3))
    high = tuple(round(max(v[i] for v in corners), 3) for i in range(3))
    if low[2] < -0.001:
        raise RuntimeError(f"{path}: geometry below floor: {low[2]}")
    if extras:
        raise RuntimeError(f"{path}: stray render objects: {extras}")
    name = os.path.splitext(os.path.basename(path))[0]
    if name.startswith(("single_bed_", "double_bed_", "gothic_double_bed_")):
        mattresses = [obj for obj in meshes if "mattress" in obj.name.lower()]
        mattress_length = max((obj.dimensions.y for obj in mattresses), default=0.0)
        if mattress_length < 2.40:
            raise RuntimeError(
                f"{path}: sleeping surface is only {mattress_length:.3f} m long; "
                "hunters require at least 2.40 m"
            )
    return len(meshes), low, high


def validate_glb(path):
    with open(path, "rb") as stream:
        magic, version, _ = struct.unpack("<4sII", stream.read(12))
        if magic != b"glTF" or version != 2:
            raise RuntimeError(f"{path}: invalid GLB header")
        json_length, json_type = struct.unpack("<II", stream.read(8))
        if json_type != 0x4E4F534A:
            raise RuntimeError(f"{path}: missing JSON chunk")
        data = json.loads(stream.read(json_length).decode("utf-8"))
    if data.get("cameras") or "KHR_lights_punctual" in data.get("extensions", {}):
        raise RuntimeError(f"{path}: camera or light exported")
    images = data.get("images", [])
    if len(images) != 1 or "bufferView" not in images[0]:
        raise RuntimeError(f"{path}: expected one embedded pixel atlas")
    samplers = data.get("samplers", [])
    if not samplers or any(s.get("magFilter") != 9728 for s in samplers):
        raise RuntimeError(f"{path}: texture sampling is not nearest-neighbor")
    triangles = 0
    accessors = data.get("accessors", [])
    for mesh in data.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            if "indices" in primitive:
                triangles += accessors[primitive["indices"]]["count"] // 3
    return len(data.get("meshes", [])), len(data.get("materials", [])), triangles


roots = [
    os.path.join(PROJECT_ROOT, "art", "props-3d", "interactables"),
    os.path.join(PROJECT_ROOT, "art", "props-3d", "props", "maze"),
    os.path.join(PROJECT_ROOT, "art", "props-3d", "props", "mansion"),
    os.path.join(PROJECT_ROOT, "art", "props-3d", "props", "beach"),
    os.path.join(PROJECT_ROOT, "art", "props-3d", "props", "nether"),
]
for root in roots:
    for blend_path in sorted(glob.glob(os.path.join(root, "source", "*.blend"))):
        name = os.path.splitext(os.path.basename(blend_path))[0]
        glb_path = os.path.join(root, f"{name}.glb")
        if not os.path.isfile(glb_path):
            continue
        mesh_count, low, high = validate_blend(blend_path)
        validate_hunter_scale(name, low, high)
        glb_meshes, materials, triangles = validate_glb(glb_path)
        if mesh_count != glb_meshes:
            raise RuntimeError(f"{name}: source/export mesh mismatch {mesh_count} != {glb_meshes}")
        print(
            f"PASS {name}: meshes={mesh_count} materials={materials} triangles={triangles} "
            f"bounds={low}..{high}"
        )
