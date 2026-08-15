"""
Maps a standard 64x64 Minecraft skin onto the Hytale 'Player' rig template.
Rig convention (verified empirically against the live Player.bbmodel):
  - north (-Z) = character's own FRONT   (confirmed: eyelids sit at z=-14.9, head's min-Z)
  - south (+Z) = character's own BACK
  - east  (+X) = character's own RIGHT   (confirmed: R- cubes now sit at +X after rename fix)
  - west  (-X) = character's own LEFT
Minecraft skin format defines front/back/right/left/top/bottom in the character's
OWN frame (not viewer-relative), so this mapping needs no further mirroring.
"""

# Standard Minecraft 64x64 skin UV regions: (x, y, w, h) per face, in texture-pixel space.
REGIONS = {
    "head_base": {
        "top": (8,0,8,8), "bottom": (16,0,8,8),
        "right": (0,8,8,8), "front": (8,8,8,8),
        "left": (16,8,8,8), "back": (24,8,8,8),
    },
    "head_overlay": {
        "top": (40,0,8,8), "bottom": (48,0,8,8),
        "right": (32,8,8,8), "front": (40,8,8,8),
        "left": (48,8,8,8), "back": (56,8,8,8),
    },
    "body_base": {
        "top": (20,16,8,4), "bottom": (28,16,8,4),
        "right": (16,20,4,12), "front": (20,20,8,12),
        "left": (28,20,4,12), "back": (32,20,8,12),
    },
    "body_overlay": {
        "top": (20,32,8,4), "bottom": (28,32,8,4),
        "right": (16,36,4,12), "front": (20,36,8,12),
        "left": (28,36,4,12), "back": (32,36,8,12),
    },
    "r_arm_base": {
        "top": (44,16,4,4), "bottom": (48,16,4,4),
        "right": (40,20,4,12), "front": (44,20,4,12),
        "left": (48,20,4,12), "back": (52,20,4,12),
    },
    "r_arm_overlay": {
        "top": (44,32,4,4), "bottom": (48,32,4,4),
        "right": (40,36,4,12), "front": (44,36,4,12),
        "left": (48,36,4,12), "back": (52,36,4,12),
    },
    "l_arm_base": {
        "top": (36,48,4,4), "bottom": (40,48,4,4),
        "right": (32,52,4,12), "front": (36,52,4,12),
        "left": (40,52,4,12), "back": (44,52,4,12),
    },
    "l_arm_overlay": {
        "top": (52,48,4,4), "bottom": (56,48,4,4),
        "right": (48,52,4,12), "front": (52,52,4,12),
        "left": (56,52,4,12), "back": (60,52,4,12),
    },
    "r_leg_base": {
        "top": (4,16,4,4), "bottom": (8,16,4,4),
        "right": (0,20,4,12), "front": (4,20,4,12),
        "left": (8,20,4,12), "back": (12,20,4,12),
    },
    "r_leg_overlay": {
        "top": (4,32,4,4), "bottom": (8,32,4,4),
        "right": (0,36,4,12), "front": (4,36,4,12),
        "left": (8,36,4,12), "back": (12,36,4,12),
    },
    "l_leg_base": {
        "top": (20,48,4,4), "bottom": (24,48,4,4),
        "right": (16,52,4,12), "front": (20,52,4,12),
        "left": (24,52,4,12), "back": (28,52,4,12),
    },
    "l_leg_overlay": {
        "top": (4,48,4,4), "bottom": (8,48,4,4),
        "right": (0,52,4,12), "front": (4,52,4,12),
        "left": (8,52,4,12), "back": (12,52,4,12),
    },
}

FACE_TO_MC = {"north": "front", "south": "back", "east": "right", "west": "left", "up": "top", "down": "bottom"}

def rect_to_uv(x0, y0, x1, y1, face):
    """Convert a desired image-space rect (x0<x1, y0<y1) to Blockbench's stored
    per-face uv array, matching the flip convention already used by this rig
    (empirically verified against the existing Player.bbmodel Head/Arm cubes)."""
    if face in ("north", "south", "east", "west"):
        return [x1, y0, x0, y1]
    else:  # up, down
        return [x0, y1, x1, y0]

def region_face_rect(region_name, face):
    mc_face = FACE_TO_MC[face]
    x, y, w, h = REGIONS[region_name][mc_face]
    return (x, y, x + w, y + h)

def slice_rect(rect, axis_h_total, part_start, part_len, from_bottom_of_part_list=False):
    """Slice a rect's height (assumed vertical axis) into a sub-band.
    rect: (x0,y0,x1,y1). Returns the sub-rect for a part occupying
    [part_start, part_start+part_len) out of axis_h_total, counted from the top (y0)."""
    x0, y0, x1, y1 = rect
    full_h = y1 - y0
    scale = full_h / axis_h_total
    ny0 = y0 + part_start * scale
    ny1 = y0 + (part_start + part_len) * scale
    return (x0, ny0, x1, ny1)
