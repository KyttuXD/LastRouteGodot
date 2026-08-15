#!/usr/bin/env python3
"""
Ports Hytale `.blockyanim` animations onto the converted hunter models.

The conversion is not guessed -- it mirrors `parseAnimationFile` in the
official Hytale Blockbench plugin
(config/Blockbench/plugins/hytale_plugin.js), so the results match what that
plugin produces when it imports the same file:

  * length      = duration / FPS,  FPS = 60 (the plugin's constant)
  * loop        = "hold" if holdLastKeyframe else "loop"
  * snapping    = 60
  * channels    orientation -> rotation, position -> position,
                shapeStretch -> scale, shapeVisible -> visibility,
                shapeUvOffset -> uv_offset (with Y negated)
  * rotation    quaternion -> THREE.Euler with order "ZYX" -> degrees
  * time        keyframe time / FPS
  * interpolation "smooth" -> catmullrom, otherwise linear

This works at all because our rig IS the Hytale player rig: the bone names
line up 1:1 once the template's corrupted "Fofrontm" is spelled "Forearm".
"""
import json, math, os, glob, hashlib

FPS = 60.0

def _quat_to_euler_zyx(x, y, z, w):
    """Quaternion -> Euler XYZ radians in THREE.js's "ZYX" order.

    Replicates THREE.Quaternion -> Matrix4 -> Euler.setFromRotationMatrix
    element for element, so the numbers match the plugin's own import."""
    n = math.sqrt(x * x + y * y + z * z + w * w)
    if n == 0:
        return 0.0, 0.0, 0.0
    x, y, z, w = x / n, y / n, z / n, w / n
    x2, y2, z2 = x + x, y + y, z + z
    xx, xy, xz = x * x2, x * y2, x * z2
    yy, yz, zz = y * y2, y * z2, z * z2
    wx, wy, wz = w * x2, w * y2, w * z2
    m11 = 1 - (yy + zz); m12 = xy - wz;        m21 = xy + wz
    m22 = 1 - (xx + zz); m31 = xz - wy
    m32 = yz + wx;       m33 = 1 - (xx + yy)
    m31c = max(-1.0, min(1.0, m31))
    ey = math.asin(-m31c)
    if abs(m31) < 0.9999999:
        ex = math.atan2(m32, m33)
        ez = math.atan2(m21, m11)
    else:
        ex = 0.0
        ez = math.atan2(-m12, m22)
    return ex, ey, ez

def _uuid_from(*parts):
    h = hashlib.md5("|".join(str(p) for p in parts).encode()).hexdigest()
    return f"{h[0:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"

CHANNELS = [
    ("rotation",   "orientation"),
    ("position",   "position"),
    ("scale",      "shapeStretch"),
    ("visibility", "shapeVisible"),
    ("uv_offset",  "shapeUvOffset"),
]

def convert_animation(anim_json, name, bone_uuids):
    """Build one Blockbench animation dict. `bone_uuids` maps bone name ->
    group uuid in the target model; bones the model doesn't have are skipped
    so we don't emit animators bound to nothing."""
    animators = {}
    for bone, data in anim_json.get("nodeAnimations", {}).items():
        uuid = bone_uuids.get(bone)
        if uuid is None:
            continue                      # bone not on this rig (armour, cloth, jaws...)
        keyframes = []
        for channel, src_key in CHANNELS:
            for kf in data.get(src_key) or []:
                delta = kf.get("delta")
                if channel == "visibility":
                    dp = {"visibility": delta}
                elif channel == "uv_offset":
                    dp = {"x": delta["x"], "y": -delta["y"]}
                elif channel == "rotation":
                    ex, ey, ez = _quat_to_euler_zyx(delta["x"], delta["y"], delta["z"], delta["w"])
                    dp = {"x": math.degrees(ex), "y": math.degrees(ey), "z": math.degrees(ez)}
                else:
                    dp = {"x": delta["x"], "y": delta["y"], "z": delta["z"]}
                keyframes.append({
                    "channel": channel,
                    "data_points": [dp],
                    "uuid": _uuid_from(name, bone, channel, kf.get("time")),
                    "time": kf.get("time", 0) / FPS,
                    "color": -1,
                    "interpolation": "catmullrom" if kf.get("interpolationType") == "smooth" else "linear",
                })
        if not keyframes:
            continue
        animators[uuid] = {"name": bone, "type": "bone", "keyframes": keyframes}
    if not animators:
        return None
    return {
        "uuid": _uuid_from("anim", name),
        "name": name,
        "loop": "hold" if anim_json.get("holdLastKeyframe") else "loop",
        "override": False,
        "length": anim_json.get("duration", FPS) / FPS,
        "snapping": int(FPS),
        "selected": False,
        "saved": True,
        "path": "",
        "anim_time_update": "",
        "blend_weight": "",
        "start_delay": "",
        "loop_delay": "",
        "animators": animators,
    }

def bone_uuid_map(model):
    return {g["name"]: g["uuid"] for g in model.get("groups", [])}

def attach_animations(model, anim_files, rename=None):
    """Attach every animation that binds to at least one of the model's bones.
    Returns (attached, skipped) name lists."""
    uuids = bone_uuid_map(model)
    out, attached, skipped = [], [], []
    for path in anim_files:
        try:
            data = json.load(open(path))
        except Exception:
            skipped.append((os.path.basename(path), "unreadable"))
            continue
        name = os.path.splitext(os.path.basename(path))[0]
        if rename:
            name = rename(name, path)
        anim = convert_animation(data, name, uuids)
        if anim is None:
            skipped.append((name, "no bones in common"))
            continue
        out.append(anim)
        attached.append(name)
    model["animations"] = out
    return attached, skipped
