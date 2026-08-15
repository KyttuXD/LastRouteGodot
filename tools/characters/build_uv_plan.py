import json, sys
import os as _os, sys as _sys
# The toolchain used to live in a scratch directory that was deleted.
# It lives here now; resolve siblings relative to this file, never a path.
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
_sys.path.insert(0, _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), _os.pardir, "office"))
from mc_hytale_map import REGIONS, rect_to_uv, region_face_rect, slice_rect

FACES = ["north","south","east","west","up","down"]

def whole_region_faces(region_name):
    return {f: rect_to_uv(*region_region_wrapper(region_name, f), f) for f in FACES}

def region_region_wrapper(region_name, face):
    return region_face_rect(region_name, face)

def uv_for(region_name, face):
    return rect_to_uv(*region_face_rect(region_name, face), face)

def sliced_uv(region_name, face, axis_total, part_start, part_len):
    rect = region_face_rect(region_name, face)
    sub = slice_rect(rect, axis_total, part_start, part_len)
    return rect_to_uv(*sub, face)

plan = {}

# HEAD: whole head_base region, 1:1
plan["Head"] = {f: uv_for("head_base", f) for f in FACES}

# HAIR overlay cube (new geometry), whole head_overlay region, 1:1 (same box shape as Head)
plan["Hair-Fringe"] = {f: uv_for("head_overlay", f) for f in FACES}

# BODY split: Chest (top 7px of 12) / Belly (bottom 5px of 12), rig ratio 22:16 -> chest_px=7, belly_px=5
# side faces (front/back/right/left) sliced; top/bottom special-cased
for part, (start, length) in [("Chest", (0, 7)), ("Belly", (7, 5))]:
    plan[part] = {}
    for f in ["north","south","east","west"]:
        plan[part][f] = sliced_uv("body_base", f, 12, start, length)
plan["Chest"]["up"] = uv_for("body_base", "up")
plan["Chest"]["down"] = sliced_uv("body_base", "north", 12, 6, 1)  # low-impact internal seam, reuse a mid slice
plan["Belly"]["up"] = sliced_uv("body_base", "north", 12, 6, 1)    # low-impact internal seam
plan["Belly"]["down"] = uv_for("body_base", "down")

# ARMS split: Arm(top 5px) / Fofrontm(mid 4px) / Hand(bottom 3px) of 12, ratio 20:16:12
for side, region in [("R", "r_arm_base"), ("L", "l_arm_base")]:
    for part, (start, length) in [(f"{side}-Arm", (0,5)), (f"{side}-Fofrontm", (5,4)), (f"{side}-Hand", (9,3))]:
        plan[part] = {}
        for f in ["north","south","east","west"]:
            plan[part][f] = sliced_uv(region, f, 12, start, length)
    plan[f"{side}-Arm"]["up"] = uv_for(region, "up")
    plan[f"{side}-Arm"]["down"] = sliced_uv(region, "north", 12, 4, 1)
    plan[f"{side}-Fofrontm"]["up"] = sliced_uv(region, "north", 12, 4, 1)
    plan[f"{side}-Fofrontm"]["down"] = sliced_uv(region, "north", 12, 8, 1)
    plan[f"{side}-Hand"]["up"] = sliced_uv(region, "north", 12, 8, 1)
    plan[f"{side}-Hand"]["down"] = uv_for(region, "down")

# LEGS split: Thigh(top 5px) / Calf(bottom 7px) of 12, ratio 20:24
for side, region in [("R", "r_leg_base"), ("L", "l_leg_base")]:
    for part, (start, length) in [(f"{side}-Thigh", (0,5)), (f"{side}-Calf", (5,7))]:
        plan[part] = {}
        for f in ["north","south","east","west"]:
            plan[part][f] = sliced_uv(region, f, 12, start, length)
    plan[f"{side}-Thigh"]["up"] = uv_for(region, "up")
    plan[f"{side}-Thigh"]["down"] = sliced_uv(region, "north", 12, 4, 1)
    plan[f"{side}-Calf"]["up"] = sliced_uv(region, "north", 12, 4, 1)
    plan[f"{side}-Calf"]["down"] = uv_for(region, "down")  # sole peeks through here too (low-impact internal)
    # FOOT: reuse bottom 2px of calf region for sides (shoe color), and leg "bottom" for the actual sole
    plan[f"{side}-Foot"] = {}
    for f in ["north","south","east","west"]:
        plan[f"{side}-Foot"][f] = sliced_uv(region, f, 12, 10, 2)
    plan[f"{side}-Foot"]["down"] = uv_for(region, "down")
    plan[f"{side}-Foot"]["up"] = sliced_uv(region, "north", 12, 10, 1)

# NECK: reuse collar-row (topmost 1px) of body front/back/right/left, stretched
plan["Neck"] = {}
for f in ["north","south","east","west"]:
    plan["Neck"][f] = sliced_uv("body_base", f, 12, 0, 1)
plan["Neck"]["up"] = None
plan["Neck"]["down"] = sliced_uv("body_base", "north", 12, 0, 1)

# EYELIDS: small skin-tone patch from r_arm_base front (2x2 corner), only 'north' face is visible
eyelid_patch = (44, 20, 46, 22)
for name in ["L-Eyelid","R-Eyelid","L-Eyelid-Bot","R-Eyelid-Bot"]:
    plan[name] = {"north": rect_to_uv(*eyelid_patch, "north")}

print(json.dumps(plan, indent=1))
