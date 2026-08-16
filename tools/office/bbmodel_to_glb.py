#!/usr/bin/env python3
"""
Exports a .bbmodel straight to binary glTF (.glb), with animation.

Blockbench's own exporter is driven through its UI, which has not been reliable
in this environment, and these models are only axis-aligned boxes with per-face
UV rects -- so writing the .glb directly is both simpler and verifiable.
`art/props-3d/README.md` accepts glTF on the same terms as FBX:

  "glTF 2.0 (.glb) still works exactly the same way ... Godot expects +Y up,
   -Z forward, which matches Blender's and Blockbench's own default export
   orientation."

Blockbench and glTF already agree on handedness (+Y up, -Z away from the
viewer) and on UV origin (upper-left), so no axis or V flip is applied. The
only conversion is scale: 64 Blockbench units = 1 metre = 1 Godot unit.

The outliner is walked RECURSIVELY. Rooms are flat, but the hunter rig nests
bones (Chest > Belly > ...), and a top-level-only walk silently dropped every
nested bone -- along with all the geometry under it.

Animation is exported as glTF node TRS channels. These models are not skinned:
each Blockbench animator targets a GROUP, and every group is already a glTF
node, so bone motion is node motion. Blockbench keyframes are DELTAS from the
rest pose while glTF channels REPLACE the node transform, so rest is folded in
here -- rotation as rest*delta, position as origin+delta.
"""
import json, struct, base64, io, os, sys, math

M = 64.0        # Blockbench units per metre
# The shared source crouch lowers Pelvis by 25 Blockbench units. Its bent
# calves/feet recover part of that distance, leaving the rendered sole 13.7
# units below the model origin. Blockbench previews without a world floor, but
# Godot places this origin exactly on y=0; carry a root lift in that clip so a
# crouching character stays planted instead of disappearing into the slab.
CROUCH_GROUND_LIFT = 13.7 / M

# Vertex order per face is (bottom-left, bottom-right, top-right, top-left) as
# seen from OUTSIDE the box, so one UV order serves every face. Winding is
# counter-clockwise from outside, which is glTF's front-face convention.
def _face_verts(x0, y0, z0, x1, y1, z1, face):
    return {
        "north": [(x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0)],
        "south": [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)],
        "east":  [(x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1)],
        "west":  [(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)],
        "up":    [(x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)],
        "down":  [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)],
    }[face]

_NORMALS = {"north": (0, 0, -1), "south": (0, 0, 1), "east": (1, 0, 0),
            "west": (-1, 0, 0), "up": (0, 1, 0), "down": (0, -1, 0)}


def _pad(b, n=4, fill=b"\0"):
    return b + fill * ((n - len(b) % n) % n)


def _quat_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)


def _quat_rotate(q, vector):
    """Rotate a 3-vector by quaternion ``q`` without allocating matrices."""
    x, y, z, w = q
    vx, vy, vz = vector
    # q * (v, 0) * conjugate(q), simplified.
    tx = 2.0 * (y * vz - z * vy)
    ty = 2.0 * (z * vx - x * vz)
    tz = 2.0 * (x * vy - y * vx)
    return (vx + w * tx + y * tz - z * ty,
            vy + w * ty + z * tx - x * tz,
            vz + w * tz + x * ty - y * tx)


def _euler_zyx_to_quat(dx, dy, dz):
    """Degrees -> (x,y,z,w), composing Rz*Ry*Rx.

    That order is not a guess: hytale_anim.py extracts these Eulers from the
    source quaternions with THREE's "ZYX" convention (ey=asin(-m31),
    ex=atan2(m32,m33), ez=atan2(m21,m11)), which is exactly the decomposition
    of Rz*Ry*Rx. Composing in any other order would invert the ports."""
    hx, hy, hz = [math.radians(v) / 2.0 for v in (dx, dy, dz)]
    qx = (math.sin(hx), 0.0, 0.0, math.cos(hx))
    qy = (0.0, math.sin(hy), 0.0, math.cos(hy))
    qz = (0.0, 0.0, math.sin(hz), math.cos(hz))
    return _quat_mul(_quat_mul(qz, qy), qx)


def convert(bb_path, glb_path, collision=True, animations=True, keep=None):
    model = json.load(open(bb_path))
    tex = (model.get("textures") or [None])[0]
    if tex is None or not str(tex.get("source", "")).startswith("data:"):
        raise SystemExit(f"{bb_path}: no embedded texture to export")
    png = base64.b64decode(tex["source"].split(",", 1)[1])
    # Blockbench's model resolution can remain 64x64 while a texture atlas
    # grows vertically as extracted hair/accessory swatches are appended.
    # UVs address the texture atlas, not that stale project-grid resolution.
    # Reading the embedded PNG is authoritative and fixes the previous V
    # scaling that sampled shirt rows onto faces and empty padding onto bodies.
    if png[:8] != b"\x89PNG\r\n\x1a\n" or len(png) < 24:
        raise SystemExit(f"{bb_path}: embedded texture is not a valid PNG")
    tw, th = struct.unpack(">II", png[16:24])

    by_uuid = {e["uuid"]: e for e in model["elements"]}
    groups = {g["uuid"]: g for g in model.get("groups", [])}

    bin_parts, accessors, buffer_views, meshes, nodes = [], [], [], [], []
    offset = 0
    node_for_group = {}          # group uuid -> glTF node index, for animation
    parent_origin_for_group = {} # group uuid -> parent's absolute BB origin

    def add_view(data, target=None):
        nonlocal offset
        data = _pad(data)
        bin_parts.append(data)
        bv = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target:
            bv["target"] = target
        buffer_views.append(bv)
        offset += len(data)
        return len(buffer_views) - 1

    def acc(data, fmt, count, ctype, atype, target=None, minmax=None):
        n = {"VEC4": 4, "VEC3": 3, "VEC2": 2, "SCALAR": 1}[atype]
        bv = add_view(struct.pack(f"<{count * n}{fmt}", *data), target)
        a = {"bufferView": bv, "componentType": ctype, "count": count, "type": atype}
        if minmax:
            a["min"], a["max"] = minmax
        accessors.append(a)
        return len(accessors) - 1

    def build(entry, parent_origin):
        """Emit one group as a node, recursing into child groups.

        `keep`, if given, selects which top-level groups are emitted -- that is
        what lets one .bbmodel export as a shell file and a props file, so the
        two can be edited and replaced independently."""
        g = groups.get(entry.get("uuid"))
        if g is None:
            return None
        if keep is not None and not keep(g["name"]):
            return None
        gx, gy, gz = [c / M for c in g.get("origin", [0, 0, 0])]
        parent_origin_for_group[g["uuid"]] = parent_origin
        pos, nrm, uvs, idx = [], [], [], []
        children = []

        for child in entry.get("children", []):
            if isinstance(child, dict):                 # a nested bone
                sub = build(child, (gx, gy, gz))
                if sub is not None:
                    children.append(sub)
                continue
            el = by_uuid.get(child)
            if el is None or el.get("type") != "cube":
                continue
            inflate = float(el.get("inflate", 0.0) or 0.0) / M
            x0, y0, z0 = [c / M - inflate for c in el["from"]]
            x1, y1, z1 = [c / M + inflate for c in el["to"]]
            element_rotation = el.get("rotation") or [0, 0, 0]
            element_quat = _euler_zyx_to_quat(*element_rotation)
            ex, ey, ez = [c / M for c in el.get("origin", [0, 0, 0])]
            for face, fd in el["faces"].items():
                if fd.get("texture") is None or not fd.get("uv"):
                    continue
                u0, v0, u1, v1 = fd["uv"]
                u0, u1 = min(u0, u1) / tw, max(u0, u1) / tw
                v0, v1 = min(v0, v1) / th, max(v0, v1) / th
                base = len(pos) // 3
                # Vertices are relative to this group's origin, so the node
                # transform carries the pivot and animation rotates about it.
                for (vx, vy, vz) in _face_verts(x0, y0, z0, x1, y1, z1, face):
                    rx, ry, rz = _quat_rotate(
                        element_quat, (vx - ex, vy - ey, vz - ez))
                    pos += [rx + ex - gx, ry + ey - gy, rz + ez - gz]
                rotated_normal = _quat_rotate(element_quat, _NORMALS[face])
                nrm += list(rotated_normal) * 4
                face_uvs = [(u0, v1), (u1, v1), (u1, v0), (u0, v0)]
                # Blockbench stores per-face texture rotation in clockwise
                # quarter turns. The old exporter ignored it, leaving feet,
                # sleeves and neck texels sideways even when geometry looked
                # plausible from a distance.
                quarter_turns = int(fd.get("rotation", 0) or 0) // 90
                if quarter_turns:
                    face_uvs = face_uvs[-quarter_turns:] + face_uvs[:-quarter_turns]
                for uv in face_uvs:
                    uvs += uv
                idx += [base, base + 1, base + 2, base, base + 2, base + 3]

        # Child node translations are relative to their parent.
        node = {"name": g["name"],
                "translation": [gx - parent_origin[0], gy - parent_origin[1],
                                gz - parent_origin[2]]}
        rot = g.get("rotation") or [0, 0, 0]
        if any(rot):
            node["rotation"] = list(_euler_zyx_to_quat(*rot))

        if idx:
            n = len(pos) // 3
            mn = [min(pos[i::3]) for i in range(3)]
            mx = [max(pos[i::3]) for i in range(3)]
            a_pos = acc(pos, "f", n, 5126, "VEC3", 34962, (mn, mx))
            a_nrm = acc(nrm, "f", n, 5126, "VEC3", 34962)
            a_uv = acc(uvs, "f", n, 5126, "VEC2", 34962)
            a_idx = acc(idx, "I", len(idx), 5125, "SCALAR", 34963)
            meshes.append({"name": g["name"], "primitives": [{
                "attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "TEXCOORD_0": a_uv},
                "indices": a_idx, "material": 0}]})
            node["mesh"] = len(meshes) - 1
            if collision:
                # "-colonly", not "-col": the plain suffix keeps the mesh
                # VISIBLE beside the collider and draws everything twice.
                # A SIBLING, not a child: nested, Godot builds two
                # StaticBody3D per mesh instead of one.
                nodes.append({"name": g["name"] + "-colonly",
                              "mesh": len(meshes) - 1})
                children.append(len(nodes) - 1)

        if children:
            node["children"] = children
        nodes.append(node)
        node_for_group[g["uuid"]] = len(nodes) - 1
        return len(nodes) - 1

    top_level = []
    for entry in model.get("outliner", []):
        if isinstance(entry, dict):
            n = build(entry, (0.0, 0.0, 0.0))
            if n is not None:
                top_level.append(n)

    img_view = add_view(png)
    root = {"name": model.get("name", "model"), "children": top_level}
    nodes.append(root)
    root_idx = len(nodes) - 1

    # --- animation ---------------------------------------------------------
    gltf_anims = []
    if animations:
        for anim in model.get("animations", []):
            channels, samplers = [], []
            for bone_uuid, animator in (anim.get("animators") or {}).items():
                node_idx = node_for_group.get(bone_uuid)
                if node_idx is None:
                    continue                       # animator for a bone we did not emit
                g = groups[bone_uuid]
                ox, oy, oz = [c / M for c in g.get("origin", [0, 0, 0])]
                px, py, pz = parent_origin_for_group.get(bone_uuid, (0.0, 0.0, 0.0))
                rest = g.get("rotation") or [0, 0, 0]
                by_channel = {}
                for kf in animator.get("keyframes", []):
                    by_channel.setdefault(kf.get("channel"), []).append(kf)
                for ch, kfs in by_channel.items():
                    if ch not in ("rotation", "position", "scale"):
                        continue                   # visibility/uv_offset have no glTF path
                    kfs.sort(key=lambda k: k.get("time", 0.0))
                    times, values = [], []
                    for kf in kfs:
                        dp = (kf.get("data_points") or [{}])[0]
                        def num(key, default=0.0):
                            try:
                                return float(dp.get(key, default))
                            except (TypeError, ValueError):
                                return default
                        times.append(float(kf.get("time", 0.0)))
                        if ch == "rotation":
                            # Blockbench keys are deltas from rest; glTF replaces.
                            values += list(_euler_zyx_to_quat(
                                rest[0] + num("x"), rest[1] + num("y"),
                                rest[2] + num("z")))
                        elif ch == "position":
                            # A glTF child translation is local to its parent.
                            # The old exporter wrote the group's absolute BB
                            # origin here, so the first position key moved
                            # feet to the knees and nested props away from the
                            # body. Fold the animation delta into the same
                            # parent-relative rest translation build() emits.
                            values += [ox - px + num("x") / M,
                                       oy - py + num("y") / M,
                                       oz - pz + num("z") / M]
                        else:
                            values += [num("x", 1.0), num("y", 1.0), num("z", 1.0)]
                    if not times:
                        continue
                    a_in = acc(times, "f", len(times), 5126, "SCALAR",
                               None, ([min(times)], [max(times)]))
                    atype = "VEC4" if ch == "rotation" else "VEC3"
                    a_out = acc(values, "f", len(times), 5126, atype)
                    samplers.append({"input": a_in, "output": a_out,
                                     # glTF has no catmullrom; LINEAR is the
                                     # honest fallback rather than CUBICSPLINE,
                                     # which needs tangents we do not have.
                                     "interpolation": "LINEAR"})
                    path = {"rotation": "rotation", "position": "translation",
                            "scale": "scale"}[ch]
                    channels.append({"sampler": len(samplers) - 1,
                                     "target": {"node": node_idx, "path": path}})
            source_animation_name = str(anim.get("name", "anim"))
            if source_animation_name.lower() == "crouch" and channels:
                duration = max(float(anim.get("length", 0.0) or 0.0), 0.001)
                a_in = acc([0.0, duration], "f", 2, 5126, "SCALAR",
                           None, ([0.0], [duration]))
                a_out = acc([0.0, CROUCH_GROUND_LIFT, 0.0,
                             0.0, CROUCH_GROUND_LIFT, 0.0],
                            "f", 2, 5126, "VEC3")
                samplers.append({"input": a_in, "output": a_out,
                                 "interpolation": "LINEAR"})
                channels.append({"sampler": len(samplers) - 1,
                                 "target": {"node": root_idx,
                                            "path": "translation"}})
            if channels:
                # glTF itself has no standard loop flag. Godot's importer
                # recognizes the documented ``-loop`` suffix and strips it
                # from the imported Animation name while setting loop_mode.
                # Preserve Blockbench's loop setting through a clean import
                # instead of relying on hand-edited .import metadata.
                animation_name = source_animation_name
                if anim.get("loop") == "loop":
                    animation_name += "-loop"
                gltf_anims.append({"name": animation_name,
                                   "channels": channels, "samplers": samplers})

    gltf = {
        "asset": {"version": "2.0", "generator": "bbmodel_to_glb"},
        "scene": 0,
        "scenes": [{"nodes": [root_idx]}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": [{
            "name": "model",
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": 0},
                "metallicFactor": 0.0, "roughnessFactor": 1.0},
            # Blockbench renders its pixel-art planes from either side. Wings,
            # gills and hair cards commonly author only one textured face;
            # single-sided glTF made Xivvy's wings disappear from the front.
            "alphaMode": "MASK", "alphaCutoff": 0.5, "doubleSided": True,
        }],
        "textures": [{"sampler": 0, "source": 0}],
        # NEAREST both ways -- these are pixel-art atlases; linear filtering
        # would blur every texel and bleed neighbouring materials together.
        "samplers": [{"magFilter": 9728, "minFilter": 9728,
                      "wrapS": 33071, "wrapT": 33071}],
        "images": [{"bufferView": img_view, "mimeType": "image/png"}],
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": offset}],
    }
    if gltf_anims:
        gltf["animations"] = gltf_anims

    bin_blob = _pad(b"".join(bin_parts))
    json_blob = _pad(json.dumps(gltf, separators=(",", ":")).encode(), 4, b" ")
    glb = b"glTF" + struct.pack("<II", 2, 12 + 8 + len(json_blob) + 8 + len(bin_blob))
    glb += struct.pack("<I", len(json_blob)) + b"JSON" + json_blob
    glb += struct.pack("<I", len(bin_blob)) + b"BIN\0" + bin_blob

    os.makedirs(os.path.dirname(glb_path) or ".", exist_ok=True)
    open(glb_path, "wb").write(glb)
    tris = sum(a["count"] for a in accessors if a["type"] == "SCALAR"
               and a["componentType"] == 5125) // 3
    return {"path": glb_path, "bytes": len(glb), "nodes": len(nodes) - 1,
            "meshes": len(meshes), "tris": tris, "animations": len(gltf_anims)}


if __name__ == "__main__":
    for src in sys.argv[1:-1] if len(sys.argv) > 2 else []:
        dst = os.path.join(sys.argv[-1],
                           os.path.splitext(os.path.basename(src))[0] + ".glb")
        i = convert(src, dst)
        print(f"{os.path.basename(dst):22s} {i['bytes']:8d} B  {i['meshes']:3d} meshes  "
              f"{i['tris']:5d} tris  {i['animations']:2d} anims")
