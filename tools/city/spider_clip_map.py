#!/usr/bin/env python3
"""Retarget the white wolf spider's six clips onto the black wolf spider's rig (which has none).

The two models are two builds of the same species with different rigging:

    white                                   black
    root > thorax > abdomen > abdomenRear   root > body            (thorax + abdomen merged)
                    > tail1..4                    > tail1..5       (tail5 is extra; hangs off body, not the abdomen)
                  > neck > head > jaw/ears        > neck > head > jaw/ears
                  > legLn > shinLn > footLn       > legXn_upper > legXn_lower > legXn_foot

Both are modelled head toward -Z, Y up, every bone at rest rotation 0, so a bone's keyframe (euler degrees, Blockbench ZYX order)
means the same thing in either rig: the clips transfer bone by bone with these rules (BONE_MAP below):

* thorax -> body (rotation + position).
* abdomen and abdomenRear have no black bone: their motion is composed into tail1 (which in the white rig hangs below both), so the
  tail still whips with the body.
* tail1..4 -> tail1..4, tail5 = tail4 delayed by TAIL5_LAG seconds at TAIL5_GAIN of its amplitude (a whip travelling down the tail).
* neck, head, jaw -> the same names; ears by SIDE (see below).
* legs: SIDE-FLIPPED. The white model calls the +X side "L"; the black one calls the -X side "L". A bone must keep the side of the
  body it is on, so white legLn/shinLn/footLn drive black legRn_upper/_lower/_foot (and R drives L); same for the ears.

The clips are sampled at 24 fps from the white keyframes (linear, like the source), mapped, and written to
tools/city/black_wolf_spider.clips.json (bone NAME -> rotation/position keys) for bbmodel_creature.py --clips. A forward-kinematics check
(FK below) then measures the lowest point of the feet in every frame; for the ground clips (idle, walk, sprint, bark) the body is lifted
when a foot would sink below the floor, so the feet stay on it (a lift is recorded as a position key on `body`).

    python3 tools/city/spider_clip_map.py            # writes the clips json and prints the foot/ground report
"""
import json, math, sys, os
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
WHITE = os.path.join(HERE, "white_wolf_spider.bbmodel")
BLACK = os.path.join(HERE, "black_wolf_spider.bbmodel")
OUT = os.path.join(HERE, "black_wolf_spider.clips.json")
FPS = 24.0
TAIL5_LAG = 0.07
TAIL5_GAIN = 1.15
GROUND_CLIPS = ("idle", "walk", "sprint", "bark")

# black bone <- list of white bones it is driven by (composed parent -> child in that order for rotation)
def side_flip(name):
    return name.replace("L", "R") if "L" in name else name.replace("R", "L")


def build_map(black_names):
    m = {"body": ["thorax"], "neck": ["neck"], "head": ["head"], "jaw": ["jaw"],
         "earL": ["earR"], "earR": ["earL"],       # side flip
         "tail1": ["abdomen", "abdomenRear", "tail1"], "tail2": ["tail2"], "tail3": ["tail3"], "tail4": ["tail4"]}
    for side in ("L", "R"):
        for n in range(1, 5):
            other = "R" if side == "L" else "L"
            m["leg%s%d_upper" % (side, n)] = ["leg%s%d" % (other, n)]
            m["leg%s%d_lower" % (side, n)] = ["shin%s%d" % (other, n)]
            m["leg%s%d_foot" % (side, n)] = ["foot%s%d" % (other, n)]
    m["tail5"] = ["tail4"]                         # lagged copy, see TAIL5_*
    missing = [b for b in black_names if b not in m and b not in ("root", "hitbox")]
    return m, missing


# ------------------------------------------------------------------ math (Blockbench euler ZYX, degrees)
def rot(rx, ry, rz):
    cx, sx, cy, sy, cz, sz = (math.cos(math.radians(rx)), math.sin(math.radians(rx)), math.cos(math.radians(ry)),
                              math.sin(math.radians(ry)), math.cos(math.radians(rz)), math.sin(math.radians(rz)))
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Rz @ Ry @ Rx


def euler_from(R, prev=None):
    y = math.asin(max(-1.0, min(1.0, -R[2][0])))
    if abs(math.cos(y)) > 1e-6:
        x = math.atan2(R[2][1], R[2][2])
        z = math.atan2(R[1][0], R[0][0])
    else:                                          # gimbal: fold z into x
        x = math.atan2(-R[1][2], R[1][1])
        z = 0.0
    e = [math.degrees(x), math.degrees(y), math.degrees(z)]
    if prev is not None:                           # unwrap to stay continuous
        for i in range(3):
            while e[i] - prev[i] > 180:
                e[i] -= 360
            while e[i] - prev[i] < -180:
                e[i] += 360
    return e


# ------------------------------------------------------------------ models
def load(path):
    bb = json.load(open(path))
    groups, uuid_name, parent = {}, {}, {}
    cubes = {e["uuid"]: e for e in bb["elements"] if e.get("type", "cube") == "cube"}

    def walk(g, par):
        groups[g["name"]] = {"origin": np.array(g.get("origin", [0, 0, 0]), float), "parent": par, "cubes": []}
        uuid_name[g["uuid"]] = g["name"]
        for c in g.get("children", []):
            if isinstance(c, str):
                if c in cubes and cubes[c].get("visibility") is not False:
                    groups[g["name"]]["cubes"].append(cubes[c])
            else:
                walk(c, g["name"])
    for g in bb["outliner"]:
        if isinstance(g, dict):
            walk(g, None)
    return bb, groups, uuid_name


def keys_of(animator, channel):
    ks = sorted(((k["time"], k["data_points"][0]) for k in animator.get("keyframes", []) if k["channel"] == channel and k.get("data_points")), key=lambda k: k[0])
    return [(t, np.array([float(p.get("x", 0) or 0), float(p.get("y", 0) or 0), float(p.get("z", 0) or 0)])) for t, p in ks]


def sample(ks, t, default=0.0):
    if not ks:
        return np.zeros(3) + default
    if t <= ks[0][0]:
        return ks[0][1].copy()
    if t >= ks[-1][0]:
        return ks[-1][1].copy()
    for (t0, v0), (t1, v1) in zip(ks, ks[1:]):
        if t0 <= t <= t1:
            return v0 + (v1 - v0) * ((t - t0) / (t1 - t0) if t1 > t0 else 0.0)
    return ks[-1][1].copy()


def white_tracks(white_bb, uuid_name):
    clips = {}
    for a in white_bb["animations"]:
        clips[a["name"]] = {"length": float(a["length"]), "loop": a.get("loop") == "loop",
                            "bones": {uuid_name[u]: {"rotation": keys_of(an, "rotation"), "position": keys_of(an, "position")}
                                      for u, an in a["animators"].items() if u in uuid_name}}
    return clips


# ------------------------------------------------------------------ forward kinematics for the ground check
def foot_min_y(groups, pose):
    """pose: bone -> (euler, position offset). Returns the lowest world Y of any foot cube corner (model units)."""
    cache = {}

    def world(name):
        if name in cache:
            return cache[name]
        g = groups[name]
        par = g["parent"]
        eul, pos = pose.get(name, (np.zeros(3), np.zeros(3)))
        local_t = g["origin"] - (groups[par]["origin"] if par else g["origin"]) + pos
        R = rot(*eul)
        if par is None:
            M = (np.eye(3), local_t * 0)
            M = (R, g["origin"] * 0 + pos + g["origin"] * 0)
            res = (R, g["origin"] + pos)
        else:
            Rp, tp = world(par)
            res = (Rp @ R, tp + Rp @ local_t)
        cache[name] = res
        return res

    lowest = 1e9
    for name, g in groups.items():
        if not name.endswith("foot") and not name.startswith("foot"):
            continue
        R, t = world(name)
        for c in g["cubes"]:
            f, to = np.array(c["from"], float), np.array(c["to"], float)
            co = np.array(c.get("origin", [0, 0, 0]), float)
            Rc = rot(*c.get("rotation", [0, 0, 0]))
            for x in (f[0], to[0]):
                for y in (f[1], to[1]):
                    for z in (f[2], to[2]):
                        p = co + Rc @ (np.array([x, y, z]) - co)
                        w = t + R @ (p - g["origin"])
                        lowest = min(lowest, w[1])
    return lowest


def simplify(keys, tol):
    """Drop keys that linear interpolation between their neighbours reproduces within tol (degrees / units): the file stays small."""
    if len(keys) <= 2:
        return keys
    keep = [0, len(keys) - 1]
    stack = [(0, len(keys) - 1)]
    while stack:
        a, b = stack.pop()
        ta, tb = keys[a][0], keys[b][0]
        worst, at = 0.0, None
        for i in range(a + 1, b):
            f = (keys[i][0] - ta) / (tb - ta) if tb > ta else 0.0
            err = max(abs(keys[i][j] - (keys[a][j] + (keys[b][j] - keys[a][j]) * f)) for j in (1, 2, 3))
            if err > worst:
                worst, at = err, i
        if at is not None and worst > tol:
            keep.append(at)
            stack += [(a, at), (at, b)]
    return [keys[i] for i in sorted(set(keep))]


def main():
    wbb, wg, wu = load(WHITE)
    bbb, bg, bu = load(BLACK)
    bmap, missing = build_map(list(bg))
    if missing:
        sys.exit("black bones without a mapping: %s" % missing)
    wclips = white_tracks(wbb, wu)
    out, report = {}, {}
    rest_low = foot_min_y(bg, {})
    for cname, clip in wclips.items():
        length = clip["length"]
        n = max(2, int(round(length * FPS)) + 1)
        times = [min(length, i / FPS) for i in range(n)]
        if times[-1] < length - 1e-6:
            times.append(length)
        bones = {}
        lows = []
        # per frame euler/position for every black bone
        frames = []
        for t in times:
            frame = {}
            for bname, srcs in bmap.items():
                if bname == "tail5":
                    src = clip["bones"].get("tail4")
                    tt = max(0.0, t - TAIL5_LAG)
                    if clip["loop"]:
                        tt = (t - TAIL5_LAG) % length
                    e = sample(src["rotation"], tt) * TAIL5_GAIN if src else np.zeros(3)
                    p = np.zeros(3)
                else:
                    R = np.eye(3)
                    p = np.zeros(3)
                    for s in srcs:
                        tr = clip["bones"].get(s)
                        if tr is None:
                            continue
                        R = R @ rot(*sample(tr["rotation"], t))
                        p = p + sample(tr["position"], t)
                    e = np.array(euler_from(R))
                frame[bname] = (e, p)
            frames.append(frame)
        # continuity of euler angles along time
        for bname in bmap:
            prev = None
            for fr in frames:
                e = fr[bname][0]
                if prev is not None:
                    e = np.array(euler_from(rot(*e), prev))
                    fr[bname] = (e, fr[bname][1])
                prev = fr[bname][0]
        # keep the feet on the ground for the ground clips: lift the body when a foot would sink
        lift_total = 0.0
        for fr in frames:
            low = foot_min_y(bg, fr)
            if cname in GROUND_CLIPS and low < rest_low - 0.15:
                lift = rest_low - low
                e, p = fr["body"]
                fr["body"] = (e, p + np.array([0.0, lift, 0.0]))
                lift_total = max(lift_total, lift)
                low = foot_min_y(bg, fr)
            lows.append(low)
        for bname in bmap:
            bones[bname] = {"rotation": [[round(float(t), 5)] + [round(float(v), 4) for v in fr[bname][0]] for t, fr in zip(times, frames)],
                            "position": [[round(float(t), 5)] + [round(float(v), 4) for v in fr[bname][1]] for t, fr in zip(times, frames)]}
        # a bone that never moves needs no track; the rest are simplified (the report's loop and foot numbers are taken before this)
        for bname in list(bones):
            for ch in ("rotation", "position"):
                vals = np.array([k[1:] for k in bones[bname][ch]])
                if np.abs(vals).max() < 1e-3:
                    bones[bname][ch] = []
                else:
                    bones[bname][ch] = simplify(bones[bname][ch], 0.08 if ch == "rotation" else 0.04)
        out[cname] = {"length": length, "loop": clip["loop"], "bones": bones}
        loop_err = max(float(np.abs(np.array(bones[b][ch][0][1:]) - np.array(bones[b][ch][-1][1:])).max()) for b in bones for ch in ("rotation", "position") if bones[b][ch]) if clip["loop"] else None
        report[cname] = {"frames": len(times), "lowest_foot_min": round(min(lows), 2), "highest_lowest_foot": round(max(lows), 2),
                         "max_body_lift": round(lift_total, 2), "loop_closure_error": None if loop_err is None else round(loop_err, 5)}
    json.dump({"source": "retargeted from white_wolf_spider.bbmodel by tools/city/spider_clip_map.py", "fps": FPS, "clips": out}, open(OUT, "w"))
    print("rest foot level %.2f" % rest_low)
    for k, v in report.items():
        print(k, v)
    return report


if __name__ == "__main__":
    main()
