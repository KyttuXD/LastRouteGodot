"""Numeric clip audit straight from the .glb (no renderer): forward kinematics of every clip on every hunter.

  python3 tools/blocky_hunters/fk_audit.py [hunter ...]

Per clip it reports (and flags with !!):
  feet     lowest foot-sole height over the clip: standing/walking clips should keep one foot on the floor (~0);
           flags floating (> 6 cm) or sinking (< -6 cm)
  torso    arm/hand centres entering the torso box while the arm is below the shoulder (arm clipping the body)
  range    summed rotation range of the core bones (a tiny range = clip looks like standing still / like idle)
  twin     another clip with the same pose track (identical clips)"""
import glob, json, os, struct, sys
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def load(path):
    with open(path, "rb") as f:
        f.read(12)
        n, _ = struct.unpack("<II", f.read(8))
        g = json.loads(f.read(n))
        f.read(4)
        f.read(4)
        blob = f.read()
    return g, blob


def acc(g, blob, i):
    a = g["accessors"][i]
    v = g["bufferViews"][a["bufferView"]]
    nc = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[a["type"]]
    return np.frombuffer(blob, dtype="<f4", count=a["count"] * nc, offset=v["byteOffset"]).reshape(a["count"], nc)


def qmat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def sample(times, vals, t, quat):
    t = min(max(t, times[0]), times[-1])
    i = int(np.searchsorted(times, t, side="right") - 1)
    i = min(i, len(times) - 2)
    u = (t - times[i]) / max(times[i + 1] - times[i], 1e-9)
    a, b = vals[i], vals[i + 1]
    if quat and np.dot(a, b) < 0:
        b = -b
    r = a + (b - a) * u
    return r / np.linalg.norm(r) if quat else r


def audit(h):
    g, blob = load(f"{ROOT}/assets/hunters_blocky/{h}/{h}.glb")
    nodes = g["nodes"]
    name_of = {i: n["name"] for i, n in enumerate(nodes)}
    idx = {n["name"]: i for i, n in enumerate(nodes)}
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    rest_t = {i: np.array(n.get("translation", [0, 0, 0])) for i, n in enumerate(nodes)}
    rest_r = {i: np.array(n.get("rotation", [0, 0, 0, 1])) for i, n in enumerate(nodes)}

    def world(pose_r, pose_t):
        W = {}

        def rec(i):
            if i in W:
                return W[i]
            M = np.eye(4)
            M[:3, :3] = qmat(pose_r.get(i, rest_r[i]))
            M[:3, 3] = pose_t.get(i, rest_t[i])
            W[i] = (rec(parent[i]) @ M) if i in parent else M
            return W[i]
        for i in range(len(nodes)):
            rec(i)
        return W
    W0 = world({}, {})
    foot_bottom = {s: np.array([0, -W0[idx[f"{s}-Foot"]][1, 3], 0, 1.0]) for s in "LR"}   # sole point in foot space
    torso_c = W0[idx["Chest"]][:3, 3]
    out = {}
    anims = {a["name"].replace("-loop", ""): a for a in g["animations"]}
    twins = {}
    for cname, a in anims.items():
        ch = {}
        for c in a["channels"]:
            s = a["samplers"][c["sampler"]]
            ch[(c["target"]["node"], c["target"]["path"])] = (acc(g, blob, s["input"])[:, 0], acc(g, blob, s["output"]))
        length = max(t[-1] for t, _ in ch.values())
        lows, hits, rng = [], 0, 0.0
        for k in range(24):
            t = length * k / 24
            pr, pt = {}, {}
            for (n, path), (ts, vs) in ch.items():
                if path == "rotation":
                    pr[n] = sample(ts, vs, t, True)
                elif path == "translation":
                    pt[n] = sample(ts, vs, t, False)
            W = world(pr, pt)
            soles = [(W[idx[f"{s}-Foot"]] @ foot_bottom[s])[1] for s in "LR"]
            lows.append(min(soles))
            for s in "LR":                       # arm centres vs the torso box
                for part, tol in (("Forearm", 0), ("Hand", 0)):
                    p = W[idx[f"{s}-{part}"]][:3, 3] - np.array([0, 0, 0])
                    mid = p + W[idx[f"{s}-{part}"]][:3, :3] @ np.array([0, -0.12, 0])
                    sh = W[idx[f"{s}-Arm"]][:3, 3]
                    if abs(mid[0]) < 0.165 and abs(mid[2] - torso_c[2]) < 0.075 and mid[1] < sh[1] - 0.05 and mid[1] > W[idx["Pelvis"]][1, 3]:
                        hits += 1
        for (n, path), (ts, vs) in ch.items():
            if path == "rotation" and name_of[n] in ("Pelvis", "Belly", "Chest", "Head", "L-Arm", "R-Arm", "L-Forearm", "R-Forearm",
                                                      "L-Thigh", "R-Thigh", "L-Calf", "R-Calf"):
                rest = rest_r[n]
                rng += float(np.max([2 * np.degrees(np.arccos(min(1, abs(np.dot(v, rest))))) for v in vs]))
        key = tuple(np.round(np.concatenate([ch[k][1].ravel() for k in sorted(ch) if k[1] == "rotation"])[:400], 2))
        twins.setdefault(key, []).append(cname)
        out[cname] = dict(low=min(lows), top=max(lows), hits=hits, rng=rng)
    return out, [v for v in twins.values() if len(v) > 1]


def main():
    hunters = sys.argv[1:] or sorted(os.path.basename(p[:-1]) for p in glob.glob(f"{ROOT}/assets/hunters_blocky/*/")
                                      if not p[:-1].endswith("_tall"))
    for h in hunters:
        res, twins = audit(h)
        flags = []
        for c, r in res.items():
            if c.startswith("emote") or c in ("flight", "jumpscare"):
                continue
            ground = c not in ("stun", "stun_recover", "scythe_stun", "scythe_stun_recover", "crouch")
            if ground and r["top"] > (0.08 if c in ("sprint", "charge") else 0.06):
                flags.append(f"{c}: feet float (+{r['top']*100:.0f} cm)")
            if r["low"] < -0.06:
                flags.append(f"{c}: feet sink ({r['low']*100:.0f} cm)")
            if r["hits"] > 2 and not c.startswith("scythe") and c != "stun" and "stun" not in c:
                flags.append(f"{c}: arm in torso ({r['hits']} samples)")
        rngs = {c: round(r["rng"]) for c, r in res.items() if c in ("idle", "walk", "chase", "sprint")}
        print(f"{h:12s} range {rngs}  {'; '.join(flags) if flags else 'ok'}{'  TWINS ' + str(twins) if twins else ''}")


main()
