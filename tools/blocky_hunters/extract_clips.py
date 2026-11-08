"""One-off: copy the Hytale-rig gameplay clips out of a Godot1 hunter GLB into clips.json.

The Hytale clips are rotation tracks on named bones (plus a Pelvis/Origin
translation), so they are independent of a hunter's proportions. clips.json is
committed; this script only documents where the data came from.

  python3 extract_clips.py <godot1>/art/props-3d/characters/kathy.glb
"""
import json, struct, sys, pathlib
KEEP = ["idle", "walk", "chase", "sprint", "crouch", "stun"]

def main(path):
    b = pathlib.Path(path).read_bytes()
    jl = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    off = 20 + jl + 8
    binb = b[off:]
    def acc(i):
        a = j["accessors"][i]; bv = j["bufferViews"][a["bufferView"]]
        n = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[a["type"]]
        o = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        return list(struct.unpack("<%df" % (a["count"] * n), binb[o:o + 4 * n * a["count"]])), n
    nodes = j["nodes"]
    rest = {n["name"]: {"t": n.get("translation", [0, 0, 0]), "r": n.get("rotation", [0, 0, 0, 1])} for n in nodes}
    out = {"rest": {k: rest[k] for k in rest if k in (
        "L-Arm", "R-Arm", "L-Thigh", "R-Thigh", "Pelvis")}, "clips": {}}
    for a in j["animations"]:
        name = a["name"].replace("-loop", "")
        if name not in KEEP:
            continue
        tr = {}
        for c in a["channels"]:
            node = nodes[c["target"]["node"]]["name"]
            if node in ("Origin",) or node == "Kathy":
                continue
            s = a["samplers"][c["sampler"]]
            t, _ = acc(s["input"]); v, n = acc(s["output"])
            tr.setdefault(node, {})[c["target"]["path"]] = {
                "t": [round(x, 5) for x in t],
                "v": [[round(x, 6) for x in v[i * n:(i + 1) * n]] for i in range(len(t))]}
        out["clips"][name] = {"length": max(max(p["t"]) for d in tr.values() for p in d.values()), "tracks": tr}
    pathlib.Path(__file__).with_name("clips.json").write_text(json.dumps(out, separators=(",", ":")))
    for k, v in out["clips"].items():
        print(k, v["length"], len(v["tracks"]))
    print(out["rest"])

main(sys.argv[1])
