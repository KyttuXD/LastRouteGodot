"""Write a Model + rig + clips as a .glb (node hierarchy, rotation tracks, no skin) and a .bbmodel."""
import json, struct, uuid, base64, io
from bb_core import FACES, ATLAS_W, ATLAS_H, FACE_CELL


def _pad(b, ch=b"\0"):
    return b + ch * (-len(b) % 4)


class _Buf:
    def __init__(self):
        self.data = bytearray()
        self.views, self.accs = [], []

    def view(self, raw, target=None):
        while len(self.data) % 4:
            self.data.append(0)
        off = len(self.data)
        self.data += raw
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(raw)}
        if target:
            v["target"] = target
        self.views.append(v)
        return len(self.views) - 1

    def acc(self, floats=None, ints=None, ctype=5126, atype="SCALAR", count=None, minmax=False, target=None):
        if floats is not None:
            raw = struct.pack("<%df" % len(floats), *floats)
        else:
            fmt = "H" if ctype == 5123 else "I"
            raw = struct.pack("<%d%s" % (len(ints), fmt), *ints)
        n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[atype]
        a = {"bufferView": self.view(raw, target), "componentType": ctype, "count": len(raw) // 4 // n if ctype != 5123 else len(ints) // n, "type": atype}
        if floats is not None:
            a["count"] = len(floats) // n
            if minmax:
                cols = [floats[i::n] for i in range(n)]
                a["min"] = [min(c) for c in cols]
                a["max"] = [max(c) for c in cols]
        self.accs.append(a)
        return len(self.accs) - 1


def write_glb(model, bones, clips, path, scale=1.0, loop_suffix=True):
    S = scale
    buf = _Buf()
    nodes, meshes = [], []
    index = {}
    mat_main, mat_face = 0, 1
    by_bone = {}
    for ci, c in enumerate(model.cubes):
        by_bone.setdefault(c.bone, []).append(ci)
    pivots = {b["name"]: b["pivot"] for b in bones}

    root_name = model.name.capitalize()
    nodes.append({"name": root_name, "children": []})
    for b in bones:
        n = {"name": b["name"], "children": []}
        par = b["parent"]
        pp = pivots[par] if par else (0, 0, 0)
        n["translation"] = [(b["pivot"][i] - pp[i]) * S for i in range(3)]
        if any(abs(v) > 1e-9 for v in b["rot"][:3]):
            n["rotation"] = list(b["rot"])
        index[b["name"]] = len(nodes)
        nodes.append(n)
        nodes[index[par] if par else 0]["children"].append(index[b["name"]])

    def mesh_for(cube_ids, bone, material, name):
        pos, nor, uv, idx = [], [], [], []
        pv = pivots[bone]
        for ci in cube_ids:
            c = model.cubes[ci]
            for f, corners, normal in model.cube_faces(ci):
                x, y, w, h = model.uv[(ci, f)]
                base = len(pos) // 3
                uvs = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
                for p, (u, v) in zip(corners, uvs):
                    pos += [(p[i] - pv[i]) * S for i in range(3)]
                    nor += list(normal)
                    uv += [u / model.atlas.w, v / model.atlas.h]
                # winding: make the geometric normal agree with the face normal
                p0, p1, p2 = corners[0], corners[2], corners[1]
                e1 = [p1[i] - p0[i] for i in range(3)]
                e2 = [p2[i] - p0[i] for i in range(3)]
                cr = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]]
                if sum(cr[i] * normal[i] for i in range(3)) >= 0:
                    idx += [base, base + 2, base + 1, base, base + 3, base + 2]
                else:
                    idx += [base, base + 1, base + 2, base, base + 2, base + 3]
        prim = {
            "attributes": {
                "POSITION": buf.acc(floats=pos, atype="VEC3", minmax=True, target=34962),
                "NORMAL": buf.acc(floats=nor, atype="VEC3", target=34962),
                "TEXCOORD_0": buf.acc(floats=uv, atype="VEC2", target=34962)},
            "indices": buf.acc(ints=idx, ctype=5123 if len(pos) // 3 < 65535 else 5125, target=34963),
            "material": material}
        meshes.append({"name": name, "primitives": [prim]})
        return len(meshes) - 1

    for bone, ids in by_bone.items():
        body = [i for i in ids if model.cubes[i].group != "face"]
        face = [i for i in ids if model.cubes[i].group == "face"]
        if body:
            nodes[index[bone]]["mesh"] = mesh_for(body, bone, mat_main, bone)
        for i in face:
            fn = {"name": "Face", "mesh": mesh_for([i], bone, mat_face, "Face"),
                  "extras": {"cell_w": model.face_cell[0], "cell_h": model.face_cell[1], "cols": 3, "rows": 5}}
            nodes.append(fn)
            nodes[index[bone]]["children"].append(len(nodes) - 1)

    # eye locators (HunterView3D hangs the eye glow and Kathy's beam off these)
    for side, s in (("L", -1), ("R", 1)):
        if "eyes" not in model.extras:
            break
        e = model.extras["eyes"][side]
        head = pivots["Head"]
        nodes.append({"name": f"{side}-Eye-Attachment", "translation": [(e[i] - head[i]) * S for i in range(3)]})
        nodes[index["Head"]]["children"].append(len(nodes) - 1)

    # HandProp: an empty at the centre of each palm (child of the hand bone) where a held prop is attached,
    # e.g. get_node("R-HandProp").add_child(scythe). It follows every clip and has no mesh.
    if "R-Hand" in index and "L-Hand" in index:
        from bb_skin import U as SKIN_U
        from bb_core import quat_from_euler
        for side, out in (("L", 1), ("R", -1)):
            # tilted 25 degrees forward and 8 outward: a held shaft leans away from the hanging arm instead of
            # lying along it (a shaft collinear with the arm looks like it is inside it)
            nodes.append({"name": f"{side}-HandProp", "translation": [0.0, -1.0 * SKIN_U * S, 0.0],
                          "rotation": list(quat_from_euler(-25.0, 0.0, 8.0 * out))})
            nodes[index[f"{side}-Hand"]]["children"].append(len(nodes) - 1)

    # animations
    animations = []
    for cname, clip in clips.items():
        chans, samps = [], []
        for bone, tr in clip["tracks"].items():
            for chan, (times, vals) in tr.items():
                tacc = buf.acc(floats=times, minmax=True)
                flat = [c for v in vals for c in (v if chan == "rotation" else tuple(x for x in v))]
                if chan == "translation":
                    flat = [c * S if False else c for c in flat]
                    p0 = pivots[bones_parent(bones, bone)] if bones_parent(bones, bone) else (0, 0, 0)
                    flat = []
                    for v in vals:
                        flat += [(v[i] - p0[i]) * S for i in range(3)]
                oacc = buf.acc(floats=flat, atype="VEC4" if chan == "rotation" else "VEC3")
                samps.append({"input": tacc, "output": oacc, "interpolation": "LINEAR"})
                chans.append({"sampler": len(samps) - 1, "target": {"node": index[bone], "path": chan}})
        animations.append({"name": cname + ("-loop" if loop_suffix and clip.get("loop", True) else ""), "channels": chans, "samplers": samps})

    png = model.texture_png()
    img_view = buf.view(png)
    gltf = {
        "asset": {"version": "2.0", "generator": "LastRoute blocky_hunters",
                  "extras": {"hunter": model.name, "style": "cube-blocky", "triangles": model.triangle_count()}},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": nodes, "meshes": meshes,
        "materials": [
            {"name": "model", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0, "roughnessFactor": 1},
             "alphaMode": "MASK", "alphaCutoff": 0.5, "doubleSided": True},
            {"name": "face", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0, "roughnessFactor": 1},
             "alphaMode": "MASK", "alphaCutoff": 0.5, "doubleSided": True}],
        "textures": [{"sampler": 0, "source": 0}],
        "samplers": [{"magFilter": 9728, "minFilter": 9728, "wrapS": 33071, "wrapT": 33071}],
        "images": [{"bufferView": img_view, "mimeType": "image/png", "name": model.name + "_atlas"}],
        "animations": animations, "accessors": buf.accs, "bufferViews": buf.views,
        "buffers": [{"byteLength": len(buf.data)}],
    }
    js = _pad(json.dumps(gltf, separators=(",", ":")).encode(), b" ")
    binb = _pad(bytes(buf.data))
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binb))
    out += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(binb), 0x004E4942) + binb
    with open(path, "wb") as fh:
        fh.write(out)
    return len(out)


def bones_parent(bones, name):
    for b in bones:
        if b["name"] == name:
            return b["parent"]
    return None


def write_bbmodel(model, bones, path):
    """Editable Blockbench project (free format, per-face UV) of the rest pose."""
    uuids = {}
    elements, outliner_nodes = [], {}
    pivots = {b["name"]: b["pivot"] for b in bones}
    U = 16.0  # blockbench units per design metre
    names = {"N": "north", "S": "south", "E": "east", "W": "west", "U": "up", "D": "down"}
    for ci, c in enumerate(model.cubes):
        u = str(uuid.uuid4())
        piv = c.pivot or c.center()
        faces = {}
        for f in "NSEWUD":
            if f in c.faces:
                x, y, w, h = model.uv[(ci, f)]
                faces[names[f]] = {"uv": [x, y, x + w, y + h], "texture": 0}
            else:
                faces[names[f]] = {"uv": [0, 0, 0, 0], "texture": None}
        elements.append({"name": c.name, "type": "cube", "uuid": u, "box_uv": False, "rescale": False,
                         "locked": False, "from": [v * 64 for v in c.lo], "to": [v * 64 for v in c.hi],
                         "autouv": 0, "color": 0, "origin": [v * 64 for v in piv],
                         "rotation": list(c.rot), "faces": faces})
        outliner_nodes.setdefault(c.bone, []).append(u)
    groups = {}
    for b in bones:
        groups[b["name"]] = {"name": b["name"], "origin": [v * 64 for v in b["pivot"]], "rotation": [0, 0, 0],
                             "uuid": str(uuid.uuid4()), "export": True, "isOpen": True, "visibility": True,
                             "children": list(outliner_nodes.get(b["name"], []))}
    for b in bones:
        if b["parent"]:
            groups[b["parent"]]["children"].append(groups[b["name"]])
    root = [groups[b["name"]] for b in bones if b["parent"] is None]
    png = model.texture_png()
    doc = {"meta": {"format_version": "4.10", "model_format": "free", "box_uv": False},
           "name": model.name, "resolution": {"width": model.atlas.w, "height": model.atlas.h},
           "elements": elements, "outliner": root,
           "textures": [{"name": model.name + "_atlas.png", "uuid": str(uuid.uuid4()), "id": "0",
                         "source": "data:image/png;base64," + base64.b64encode(png).decode(),
                         "render_mode": "default", "particle": False}]}
    with open(path, "w") as fh:
        json.dump(doc, fh)
