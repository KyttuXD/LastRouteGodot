#!/usr/bin/env python3
"""Blockbench 'free' model (groups, cubes with per-face UVs, keyframed animations) -> Godot-ready .glb.

For creature rigs that are NOT the shared humanoid rig (first user: the City's secret White Wolf Spider).
Pure stdlib: node hierarchy from the outliner, one mesh per group, nearest-filtered embedded texture, rotation + translation clips
(quaternions, LINEAR). Loop clips get a '-loop' suffix (Godot imports those as looping), one-shot clips keep their name.

    python3 tools/city/bbmodel_creature.py tools/city/white_wolf_spider.bbmodel assets/city/white_wolf_spider/white_wolf_spider.glb --scale 0.035

Writes <out>.report.json next to the glb (clips, lengths, loop closure error, triangle count, size). The .bbmodel stays the source of truth.
"""
import argparse, base64, json, math, struct, sys

TARGET_ARRAY, TARGET_ELEMENT = 34962, 34963


def q_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz)


def q_axis(axis, deg):
    h = math.radians(deg) / 2
    s, c = math.sin(h), math.cos(h)
    v = [0.0, 0.0, 0.0]
    v[axis] = s
    return (v[0], v[1], v[2], c)


def q_euler_zyx(rx, ry, rz):
    """Blockbench bone/cube rotation order: ZYX (apply X, then Y, then Z), degrees."""
    return q_mul(q_axis(2, rz), q_mul(q_axis(1, ry), q_axis(0, rx)))


def rotate_vec(q, v):
    x, y, z, w = q
    tx, ty, tz = 2 * (y * v[2] - z * v[1]), 2 * (z * v[0] - x * v[2]), 2 * (x * v[1] - y * v[0])
    return (v[0] + w * tx + (y * tz - z * ty), v[1] + w * ty + (z * tx - x * tz), v[2] + w * tz + (x * ty - y * tx))


def sub(a, b):
    return [a[i] - b[i] for i in range(3)]


# corners as seen from OUTSIDE the face: top-left, top-right, bottom-right, bottom-left
def face_corners(face, f, t):
    x1, y1, z1 = f
    x2, y2, z2 = t
    return {
        "north": [(x2, y2, z1), (x1, y2, z1), (x1, y1, z1), (x2, y1, z1)], "south": [(x1, y2, z2), (x2, y2, z2), (x2, y1, z2), (x1, y1, z2)],
        "east": [(x2, y2, z2), (x2, y2, z1), (x2, y1, z1), (x2, y1, z2)], "west": [(x1, y2, z1), (x1, y2, z2), (x1, y1, z2), (x1, y1, z1)],
        "up": [(x1, y2, z1), (x2, y2, z1), (x2, y2, z2), (x1, y2, z2)], "down": [(x1, y1, z2), (x2, y1, z2), (x2, y1, z1), (x1, y1, z1)],
    }[face]


NORMALS = {"north": (0, 0, -1), "south": (0, 0, 1), "east": (1, 0, 0), "west": (-1, 0, 0), "up": (0, 1, 0), "down": (0, -1, 0)}


class Buf:
    def __init__(self):
        self.data, self.views, self.accs = bytearray(), [], []

    def view(self, raw, target=None):
        while len(self.data) % 4:
            self.data.append(0)
        v = {"buffer": 0, "byteOffset": len(self.data), "byteLength": len(raw)}
        if target:
            v["target"] = target
        self.data += raw
        self.views.append(v)
        return len(self.views) - 1

    def floats(self, vals, atype, target=None, minmax=False):
        n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[atype]
        a = {"bufferView": self.view(struct.pack("<%df" % len(vals), *vals), target), "componentType": 5126, "count": len(vals) // n, "type": atype}
        if minmax:
            a["min"] = [min(vals[i::n]) for i in range(n)]
            a["max"] = [max(vals[i::n]) for i in range(n)]
        self.accs.append(a)
        return len(self.accs) - 1

    def indices(self, vals):
        big = max(vals) > 65535
        raw = struct.pack("<%d%s" % (len(vals), "I" if big else "H"), *vals)
        self.accs.append({"bufferView": self.view(raw, TARGET_ELEMENT), "componentType": 5125 if big else 5123, "count": len(vals), "type": "SCALAR"})
        return len(self.accs) - 1


def shrink_png(png, bb, tw, th):
    """Lossless: crop the unused rows below the last UV and store as an indexed PNG when it has <= 256 colours (nearest-filtered palette art)."""
    try:
        from PIL import Image
        import io
    except ImportError:
        return png, tw, th
    im = Image.open(io.BytesIO(png)).convert("RGBA")
    v_max = max(f["uv"][3] for e in bb["elements"] for f in e["faces"].values() if f.get("texture") is not None)
    v_max = max(f["uv"][1] for e in bb["elements"] for f in e["faces"].values() if f.get("texture") is not None) if False else max(
        v_max, max(f["uv"][1] for e in bb["elements"] for f in e["faces"].values() if f.get("texture") is not None))
    h = min(im.size[1], int(math.ceil(v_max / 8.0) * 8))
    im = im.crop((0, 0, im.size[0], h))
    colors = sorted(set(im.getdata()))
    if len(colors) <= 256:
        index = {c: i for i, c in enumerate(colors)}
        p = Image.new("P", im.size)
        p.putdata([index[c] for c in im.getdata()])
        p.putpalette([ch for c in colors for ch in c[:3]])
        p.info["transparency"] = bytes(c[3] for c in colors)
        im = p
    bio = io.BytesIO()
    im.save(bio, "PNG", optimize=True, transparency=im.info.get("transparency"))
    return bio.getvalue(), tw, h


def build(src, out, scale, clips_json=None):
    bb = json.load(open(src))
    tex = bb["textures"][0]
    tw, th = tex.get("uv_width", tex["width"]), tex.get("uv_height", tex["height"])
    png = base64.b64decode(tex["source"].split(",", 1)[1])
    png, tw, th = shrink_png(png, bb, tw, th)
    cubes = {e["uuid"]: e for e in bb["elements"] if e.get("type", "cube") == "cube"}
    S = scale
    buf = Buf()
    nodes, meshes, node_of_uuid, group_by_uuid = [], [], {}, {}
    tris = 0
    skipped = []

    def add_group(g, parent_origin, parent_idx):
        nonlocal tris
        origin = g.get("origin", [0, 0, 0])
        idx = len(nodes)
        node = {"name": g["name"], "translation": [(origin[i] - parent_origin[i]) * S for i in range(3)], "children": []}
        rot = g.get("rotation", [0, 0, 0])
        if any(abs(v) > 1e-9 for v in rot):
            node["rotation"] = list(q_euler_zyx(*rot))
        nodes.append(node)
        node_of_uuid[g["uuid"]] = idx
        group_by_uuid[g["uuid"]] = g
        if parent_idx is not None:
            nodes[parent_idx]["children"].append(idx)
        pos, nor, uv, ind = [], [], [], []
        for c in g.get("children", []):
            if isinstance(c, str):
                e = cubes.get(c)
                if e is None:
                    continue
                if e.get("visibility") is False:
                    skipped.append(e["name"])
                    continue
                co = e.get("origin", [0, 0, 0])
                q = q_euler_zyx(*e.get("rotation", [0, 0, 0]))
                has_rot = any(abs(v) > 1e-9 for v in e.get("rotation", [0, 0, 0]))
                for fname, face in e["faces"].items():
                    if face.get("texture") is None:
                        continue
                    corners = []
                    for p in face_corners(fname, e["from"], e["to"]):
                        v = sub(p, co)
                        if has_rot:
                            v = rotate_vec(q, v)
                        corners.append([(co[i] + v[i] - origin[i]) * S for i in range(3)])
                    n = NORMALS[fname]
                    if has_rot:
                        n = rotate_vec(q, n)
                    u1, v1, u2, v2 = face["uv"]
                    uvs = [(u1, v1), (u2, v1), (u2, v2), (u1, v2)]
                    base = len(pos) // 3
                    for p, (u, v) in zip(corners, uvs):
                        pos += p
                        nor += list(n)
                        uv += [u / tw, v / th]
                    ind += [base, base + 3, base + 2, base, base + 2, base + 1]
                    tris += 2
            else:
                add_group(c, origin, idx)
        if pos:
            prim = {"attributes": {"POSITION": buf.floats(pos, "VEC3", TARGET_ARRAY, True), "NORMAL": buf.floats(nor, "VEC3", TARGET_ARRAY),
                                   "TEXCOORD_0": buf.floats(uv, "VEC2", TARGET_ARRAY)}, "indices": buf.indices(ind), "material": 0}
            meshes.append({"name": g["name"], "primitives": [prim]})
            node["mesh"] = len(meshes) - 1

    roots = [g for g in bb["outliner"] if isinstance(g, dict)]
    scene_nodes = []
    for g in roots:
        scene_nodes.append(len(nodes))
        add_group(g, g.get("origin", [0, 0, 0]), None)   # root sits at its own origin: feet centre of the model

    animations, report_clips = [], {}
    node_of_name = {n["name"]: i for i, n in enumerate(nodes)}

    def clip_sources():
        """Yield {name, length, loop, tracks: {node index: {"rotation": {t: xyz}, "position": {t: xyz}}}} from the bbmodel's own
        animations, or from a retargeted clips json (bone NAME keyed; see tools/city/spider_clip_map.py)."""
        if clips_json:
            for cname, c in json.load(open(clips_json))["clips"].items():
                tracks = {}
                for bname, chans_by_name in c["bones"].items():
                    if bname not in node_of_name:
                        raise SystemExit("clips json drives a bone the model does not have: %s" % bname)
                    tr = {"rotation": {}, "position": {}}
                    for chan in ("rotation", "position"):
                        for key in chans_by_name.get(chan, []):
                            tr[chan][round(key[0], 6)] = (key[1], key[2], key[3])
                    tracks[node_of_name[bname]] = tr
                yield {"name": cname, "length": c["length"], "loop": bool(c["loop"]), "tracks": tracks}
        else:
            for a in bb.get("animations", []):
                tracks = {}
                for auuid, an in a["animators"].items():
                    if auuid not in node_of_uuid:
                        continue
                    tr = {"rotation": {}, "position": {}}
                    for k in an.get("keyframes", []):
                        if k["channel"] in tr and k.get("data_points"):
                            dp = k["data_points"][0]
                            tr[k["channel"]][round(k["time"], 6)] = (float(dp.get("x", 0) or 0), float(dp.get("y", 0) or 0), float(dp.get("z", 0) or 0))
                    tracks[node_of_uuid[auuid]] = tr
                yield {"name": a["name"], "length": a["length"], "loop": a.get("loop") == "loop", "tracks": tracks}

    for a in clip_sources():
        chans, samps, closure = [], [], 0.0
        for ni, by_chan in a["tracks"].items():
            base_t = nodes[ni]["translation"]
            base_q = tuple(nodes[ni].get("rotation", [0, 0, 0, 1]))
            for chan, keys in by_chan.items():
                if not keys:
                    continue
                times = sorted(keys)
                if a["loop"] and times[-1] < a["length"] - 1e-6:    # close the loop on the first key
                    keys[round(a["length"], 6)] = keys[times[0]]
                    times = sorted(keys)
                if times[0] > 1e-6:
                    keys[0.0] = keys[times[0]]
                    times = sorted(keys)
                vals = [keys[t] for t in times]
                if a["loop"]:
                    closure = max(closure, max(abs(vals[0][i] - vals[-1][i]) for i in range(3)))
                if chan == "rotation":
                    qs, prev = [], None
                    for v in vals:
                        q = q_mul(base_q, q_euler_zyx(*v)) if False else q_euler_zyx(*v)
                        if prev is not None and sum(q[i] * prev[i] for i in range(4)) < 0:
                            q = tuple(-c for c in q)          # shortest path, so slerp never takes the long way round
                        qs.append(q)
                        prev = q
                    outv = [c for q in qs for c in q]
                    path, atype = "rotation", "VEC4"
                else:
                    outv = [c for v in vals for c in [base_t[0] + v[0] * S, base_t[1] + v[1] * S, base_t[2] + v[2] * S]]
                    path, atype = "translation", "VEC3"
                samps.append({"input": buf.floats(times, "SCALAR", None, True), "output": buf.floats(outv, atype), "interpolation": "LINEAR"})
                chans.append({"sampler": len(samps) - 1, "target": {"node": ni, "path": path}})
        looped = a["loop"]
        name = a["name"] + ("-loop" if looped else "")
        animations.append({"name": name, "channels": chans, "samplers": samps})
        report_clips[a["name"]] = {"length": a["length"], "loop": looped, "tracks": len(chans), "loop_closure_error_deg_or_units": round(closure, 6)}

    img = buf.view(png)
    gltf = {"asset": {"version": "2.0", "generator": "LastRoute tools/city/bbmodel_creature.py", "extras": {"source": src.split("/")[-1], "scale": S}},
            "scene": 0, "scenes": [{"nodes": scene_nodes}], "nodes": nodes, "meshes": meshes,
            "materials": [{"name": "palette", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0, "roughnessFactor": 1},
                           "alphaMode": "MASK", "alphaCutoff": 0.5, "doubleSided": True}],
            "textures": [{"sampler": 0, "source": 0}],
            "samplers": [{"magFilter": 9728, "minFilter": 9728, "wrapS": 33071, "wrapT": 33071}],
            "images": [{"bufferView": img, "mimeType": "image/png", "name": "palette"}],
            "animations": animations, "accessors": buf.accs, "bufferViews": buf.views, "buffers": [{"byteLength": len(buf.data)}]}
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    binb = bytes(buf.data) + b"\0" * (-len(buf.data) % 4)
    blob = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binb)) + struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(binb), 0x004E4942) + binb
    open(out, "wb").write(blob)
    hb = next((e for e in bb["elements"] if e.get("name") == "hitbox"), None)
    hitbox = None
    if hb:
        ro = roots[0].get("origin", [0, 0, 0])
        hitbox = {"min_m": [round((hb["from"][i] - ro[i]) * S, 3) for i in range(3)], "max_m": [round((hb["to"][i] - ro[i]) * S, 3) for i in range(3)]}
    report = {"hitbox": hitbox, "source": src, "scale": S, "bytes": len(blob), "triangles": tris, "nodes": len(nodes), "meshes": len(meshes), "skipped_hidden_cubes": skipped, "clips": report_clips}
    json.dump(report, open(out + ".report.json", "w"), indent=1)
    return report


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--clips", help="retargeted clips json (bone name keyed) used instead of the bbmodel's own animations")
    ap.add_argument("--scale", type=float, default=0.035, help="metres per Blockbench unit (default 0.035: head about 2 m)")
    a = ap.parse_args()
    r = build(a.src, a.out, a.scale, a.clips)
    print(json.dumps({k: r[k] for k in ("bytes", "triangles", "nodes", "skipped_hidden_cubes")}), {k: (v["length"], v["loop"], v["tracks"]) for k, v in r["clips"].items()})
