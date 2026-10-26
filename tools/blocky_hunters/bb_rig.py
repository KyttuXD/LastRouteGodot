"""The shared hunter rig and clip set.

Bone NAMES, HIERARCHY and rest-pose rotations are fixed for every hunter (they
are the Hytale-rig names the Godot1 clips already use); only the pivot positions
follow each hunter's proportions. Extra bones (ponytail, wings ...) hang off a
core bone and get procedural sway in every clip; the core clips never mention
them, so one clip set plays on all hunters.
"""
import json, math, pathlib
from bb_core import quat_from_euler, quat_mul

HERE = pathlib.Path(__file__).resolve().parent
CLIPS = json.loads((HERE / "clips.json").read_text())
HYTALE_PELVIS_Y = 0.796875

# (bone, parent) in tree order. L = -X, R = +X (same as the Godot1 models).
CORE = [
    ("Pelvis", None),
    ("Belly", "Pelvis"), ("Chest", "Belly"), ("Head", "Chest"),
    ("L-Arm", "Chest"), ("L-Forearm", "L-Arm"), ("L-Hand", "L-Forearm"),
    ("R-Arm", "Chest"), ("R-Forearm", "R-Arm"), ("R-Hand", "R-Forearm"),
    ("L-Thigh", "Pelvis"), ("L-Calf", "L-Thigh"), ("L-Foot", "L-Calf"),
    ("R-Thigh", "Pelvis"), ("R-Calf", "R-Thigh"), ("R-Foot", "R-Calf"),
]
CORE_NAMES = [b for b, _ in CORE]
REQUIRED_CLIPS = ["idle", "walk", "chase", "sprint", "crouch", "stun", "charge", "flight", "jumpscare"]
# the gameplay clips the roster/jumpscare code asks for by name (blink etc. are faces)


def skeleton(sk, extras=()):
    """sk: proportion dict -> list of dict(name,parent,pivot,rot) in tree order.
    sk keys: hip_y hip_x thigh_y knee_y ankle_y belly_y chest_y neck_y sh_x sh_y elbow_y wrist_y
    extras: iterable of (name, parent, pivot (x,y,z), sway) where sway=(ax,az,cycles,phase) deg."""
    rest = CLIPS["rest"]
    piv = {
        "Pelvis": (0, sk["hip_y"], 0),
        "Belly": (0, sk["belly_y"], 0), "Chest": (0, sk["chest_y"], 0), "Head": (0, sk["neck_y"], 0),
    }
    for side, s in (("L", -1), ("R", 1)):
        piv[f"{side}-Arm"] = (s * sk["sh_x"], sk["sh_y"], 0)
        piv[f"{side}-Forearm"] = (s * sk["sh_x"], sk["elbow_y"], 0)
        piv[f"{side}-Hand"] = (s * sk["sh_x"], sk["wrist_y"], 0)
        piv[f"{side}-Thigh"] = (s * sk["hip_x"], sk["thigh_y"], 0)
        piv[f"{side}-Calf"] = (s * sk["hip_x"], sk["knee_y"], 0)
        piv[f"{side}-Foot"] = (s * sk["hip_x"], sk["ankle_y"], 0)
    out = []
    for name, parent in CORE:
        r = rest.get(name, {}).get("r", [0, 0, 0, 1]) if name.endswith(("Arm", "Thigh")) else [0, 0, 0, 1]
        out.append(dict(name=name, parent=parent, pivot=piv[name], rot=tuple(r), sway=None))
    for name, parent, pv, sway in extras:
        out.append(dict(name=name, parent=parent, pivot=pv, rot=(0, 0, 0, 1), sway=sway))
    return out


def q_euler_on(base, e):
    return quat_mul(quat_from_euler(*e), base)


def _lerp_key_times(length, n):
    return [length * i / n for i in range(n + 1)]


def build_clips(bones, hip_y, hunter_extras=None):
    """Return {clip: {"length": s, "tracks": {bone: {"rotation": (t, v), "translation": (t, v)}}}}.
    Core tracks come from the Hytale clips; charge/flight/jumpscare are authored here."""
    names = {b["name"] for b in bones}
    restq = {b["name"]: b["rot"] for b in bones}
    pel = next(b for b in bones if b["name"] == "Pelvis")["pivot"]
    k = hip_y / HYTALE_PELVIS_Y
    clips = {}

    def from_hytale(name):
        src = CLIPS["clips"][name]
        tr = {}
        for bone, d in src["tracks"].items():
            if bone not in names:
                continue
            tr[bone] = {}
            if "rotation" in d:
                tr[bone]["rotation"] = (list(d["rotation"]["t"]), [tuple(v) for v in d["rotation"]["v"]])
            if "translation" in d and bone == "Pelvis":
                tt = d["translation"]
                tr[bone]["translation"] = (list(tt["t"]), [
                    (pel[0] + v[0] * k, pel[1] + (v[1] - HYTALE_PELVIS_Y) * k, pel[2] + v[2] * k) for v in tt["v"]])
        return {"length": src["length"], "tracks": tr}

    for n in ("idle", "walk", "chase", "sprint", "crouch", "stun"):
        clips[n] = from_hytale(n)

    # charge: sprint with the whole torso leaned into it, head kept up
    ch = from_hytale("sprint")
    for bone, lean in (("Belly", -10), ("Chest", -12), ("Head", 18)):
        t, v = ch["tracks"][bone]["rotation"]
        ch["tracks"][bone]["rotation"] = (t, [quat_mul(quat_from_euler(lean, 0, 0), q) for q in v])
    clips["charge"] = ch

    def authored(length, n, pose, pelvis_dy=lambda i: 0.0):
        """pose(bone, i) -> euler degrees (or None for rest) at key i of n."""
        times = _lerp_key_times(length, n)
        tr = {}
        for b in CORE_NAMES:
            vals = []
            for i in range(n + 1):
                ii = i % n
                e = pose(b, ii) or (0, 0, 0)
                vals.append(quat_mul(quat_from_euler(*e), restq[b]))
            tr[b] = {"rotation": (times, vals)}
        tr["Pelvis"]["translation"] = (times, [(pel[0], pel[1] + pelvis_dy(i % n) * k, pel[2]) for i in range(n + 1)])
        return {"length": length, "tracks": tr}

    # flight: arms thrown out, legs trailing, body leaned forward, bobbing
    def fly(b, i):
        s = math.sin(2 * math.pi * i / 8)
        c = math.cos(2 * math.pi * i / 8)
        return {
            "Belly": (-8, 0, 0), "Chest": (-10, 0, 3 * s), "Head": (14, 0, 0),
            "L-Arm": (-10, 0, -62 + 8 * s), "R-Arm": (-10, 0, 62 - 8 * s),
            "L-Forearm": (14, 0, -10), "R-Forearm": (14, 0, 10),      # elbows flex forward (+X), never back
            "L-Thigh": (-14 + 4 * s, 0, 0), "R-Thigh": (-8 - 4 * s, 0, 0),
            "L-Calf": (-30, 0, 0), "R-Calf": (-36, 0, 0), "L-Foot": (-22, 0, 0), "R-Foot": (-22, 0, 0),   # knees fold the foot BACK (-X)
        }.get(b)
    clips["flight"] = authored(1.2, 8, fly, lambda i: 0.10 + 0.05 * math.sin(2 * math.pi * i / 8))

    # jumpscare: lunge with both arms clawed forward, head thrust, trembling
    def scare(b, i):
        s = 1 if i % 2 == 0 else -1
        return {
            "Belly": (-8, 0, 2 * s), "Chest": (-14, 3 * s, 0), "Head": (10, 0, 7 * s),
            "L-Arm": (100, 0, -14), "R-Arm": (100, 0, 14),
            "L-Forearm": (30, 0, 0), "R-Forearm": (30, 0, 0),
            "L-Hand": (35, 0, 0), "R-Hand": (35, 0, 0),
            "L-Thigh": (18, 0, 0), "R-Thigh": (-12, 0, 0),
            "L-Calf": (-8, 0, 0), "R-Calf": (-22, 0, 0),
        }.get(b)
    clips["jumpscare"] = authored(0.8, 6, scare, lambda i: -0.05 + 0.012 * (1 if i % 2 else -1))

    # procedural sway for extra bones (ponytail, hair, wings, ribbons ...)
    for clip_name, clip in clips.items():
        length = clip["length"]
        cyc = {"idle": 1, "walk": 2, "chase": 2, "sprint": 2, "charge": 2, "crouch": 1,
               "stun": 2, "flight": 3, "jumpscare": 4}[clip_name]
        for b in bones:
            if not b["sway"]:
                continue
            ax, az, mult, phase = b["sway"]
            amp = {"idle": .5, "walk": 1.0, "chase": 1.5, "sprint": 1.8, "charge": 1.8, "crouch": .4,
                   "stun": 1.4, "flight": b.get("flight_amp", 1.0) if isinstance(b, dict) else 1.0,
                   "jumpscare": 1.6}[clip_name]
            if b["name"].endswith("Wing"):
                amp = {"idle": .5, "walk": .8, "chase": 1.2, "sprint": 1.4, "charge": 1.4, "crouch": .35,
                       "stun": 1.0, "flight": 3.2, "jumpscare": 2.0}[clip_name]
                cyc2 = {"idle": 2, "walk": 3, "chase": 5, "sprint": 6, "charge": 6, "crouch": 1,
                        "stun": 4, "flight": 10, "jumpscare": 8}[clip_name]
            else:
                cyc2 = cyc * mult
            n = 12 if cyc2 <= 3 else max(12, int(cyc2 * 4))
            times = [length * i / n for i in range(n + 1)]
            vals = []
            for i in range(n + 1):
                ph = 2 * math.pi * cyc2 * i / n + phase
                e = (ax * amp * math.sin(ph), 0, az * amp * math.sin(ph + 1.1))
                if b["name"].endswith("Wing"):
                    e = (0, ax * amp * math.sin(ph), 0)
                vals.append(quat_euler(e, b["rot"]))
            clip["tracks"][b["name"]] = {"rotation": (times, vals)}
    return clips


def quat_euler(e, base):
    return quat_mul(quat_from_euler(*e), base)
