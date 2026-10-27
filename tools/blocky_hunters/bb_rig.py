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
REQUIRED_CLIPS = ["idle", "walk", "chase", "sprint", "crouch", "stun", "stun_recover", "charge", "flight", "jumpscare", "climb"]
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


def build_clips(bones, hip_y, profile=None, emotes=None):
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

    for n in ("idle", "walk", "chase", "sprint", "crouch"):
        clips[n] = from_hytale(n)

    # charge: a bull-rush, the sprint with the whole body thrown forward, head up and eyes on the target, arms swept
    # back and fists clenched (Loxelle's charge ability)
    ch = from_hytale("sprint")
    for bone, off in (("Belly", (-4, 0, 0)), ("Chest", (-3, 0, 0)), ("Head", (6, 0, 0)),
                      ("L-Arm", (-38, 0, 8)), ("R-Arm", (-38, 0, -8)), ("L-Forearm", (24, 0, 0)), ("R-Forearm", (24, 0, 0))):
        t, v = ch["tracks"][bone]["rotation"]
        ch["tracks"][bone]["rotation"] = (t, [quat_mul(quat_from_euler(*off), q) for q in v])
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

    # climb: on a sewer ladder facing the rungs, one hand reaching overhead while the opposite knee lifts to the next
    # rung (contralateral, like a real ladder climb), torso tucked in to the ladder, a small lift each hand-over-hand
    def climb(b, i):
        s = math.sin(2 * math.pi * i / 8)
        return {
            "Belly": (5, 0, 0), "Chest": (6, 0, 2 * s), "Head": (-6, 0, 0),
            "L-Arm": (150 + 22 * s, 0, -6), "R-Arm": (150 - 22 * s, 0, 6),
            "L-Forearm": (28 - 18 * s, 0, 0), "R-Forearm": (28 + 18 * s, 0, 0),
            "L-Hand": (10, 0, 0), "R-Hand": (10, 0, 0),
            "L-Thigh": (48 - 26 * s, 0, 0), "R-Thigh": (48 + 26 * s, 0, 0),
            "L-Calf": (-58 + 22 * s, 0, 0), "R-Calf": (-58 - 22 * s, 0, 0),
            "L-Foot": (10, 0, 0), "R-Foot": (10, 0, 0),
        }.get(b)
    clips["climb"] = authored(1.0, 8, climb, lambda i: 0.04 * math.sin(4 * math.pi * i / 8))

    # stun: a per-hunter style (stun.py) of staggering / toppling / curling ..., and the wake-up that follows it
    import stun as stun_mod
    st = stun_mod.style((profile or {}).get("stun_style", "base"), (profile or {}).get("stun_over"))
    stun_pose, stun_dy = stun_mod.pose_fn(st), stun_mod.dy_fn(st)

    def sampled(length, n, pose, dy, loop=True):
        times = [length * i / n for i in range(n + 1)]
        tr = {}
        for b in CORE_NAMES:
            vals = [quat_mul(quat_from_euler(*(pose(b, i) or (0, 0, 0))), restq[b]) for i in range(n + 1)]
            tr[b] = {"rotation": (times, vals)}
        tr["Pelvis"]["translation"] = (times, [(pel[0], pel[1] + dy(i) * k, pel[2]) for i in range(n + 1)])
        return {"length": length, "tracks": tr, "loop": loop}
    N = 24 if st["harm"] > 2 else 16
    clips["stun"] = sampled(st["length"], N, lambda b, i: stun_pose(b, 2 * math.pi * (i % N) / N), lambda i: stun_dy(2 * math.pi * (i % N) / N))

    def ease(u):
        u = max(0.0, min(1.0, u))
        return u * u * (3 - 2 * u)

    def recover_pose(b, i, n=10, length=1.0):
        t = i / n
        u = ease(t / .7)
        a = stun_pose(b, 0.0) or (0, 0, 0)
        e = [v * (1 - u) for v in a]
        if b in ("Head", "Chest"):             # wake-up jolt: head snaps up past level, then settles
            e[0] += 12 * math.sin(math.pi * min(1, t / .8)) * (1 if b == "Head" else .5)
        if b == "Head":
            e[1] += 14 * math.sin(t * 2 * math.pi * 2.5) * (1 - t)       # shakes the dizziness off
        return tuple(e)
    clips["stun_recover"] = sampled(1.0 if st["length"] < 2 else 1.3, 10, recover_pose, lambda i: stun_dy(0.0) * (1 - ease(i / 10 / .7)), loop=False)

    # run polish: the Hytale gaits are small shuffles, so chase / sprint / charge get a much longer stride, deeper knees,
    # harder arm pumping, bent elbows and a lean into the run (head kept level); walk gets a little more stride
    for name, lean, elbow, arms, stride, knee in (("walk", 0, 0, 1.3, 1.25, 1.2), ("chase", 11, 30, 1.9, 1.7, 1.5),
                                                  ("sprint", 17, 55, 2.3, 2.0, 1.8), ("charge", 12, 40, 1.0, 2.0, 1.8)):
        for bone, tr in clips[name]["tracks"].items():
            if "rotation" not in tr:
                continue
            t, v = tr["rotation"]
            if bone in ARM:
                v = [_scale_about(restq[bone], q, arms) for q in v]
            if bone in LEG:
                v = [_scale_about(restq[bone], q, stride) for q in v]
            if bone in KNEE:
                v = [_scale_about(restq[bone], q, knee) for q in v]
            off = {"Belly": (-lean * .55, 0, 0), "Chest": (-lean * .45, 0, 0), "Head": (lean * .85, 0, 0),
                   "L-Forearm": (elbow, 0, 0), "R-Forearm": (elbow, 0, 0)}.get(bone)
            if off and any(off):
                v = [quat_mul(quat_from_euler(*off), q) for q in v]
            tr["rotation"] = (t, v)

    # life overlays: the Hytale idle / walk are very small motions; add breathing and weight shift to idle, and the
    # torso counter-rotation + hip sway + head bob a real gait has to walk / chase / sprint / charge
    for name, specs in OVERLAYS.items():
        if name in clips:
            overlay(clips[name], restq, specs)
    _apply_profile(clips, restq, pel, profile or {})
    ground_fit(clips, bones, restq, st["buckle"] <= .2)
    clips.update(emotes or {})            # one-shot emotes are added after the profile: they keep their own timing

    # procedural sway for extra bones (ponytail, hair, wings, ribbons ...)
    for clip_name, clip in clips.items():
        length = clip["length"]
        cyc = {"idle": 1, "walk": 2, "chase": 2, "sprint": 2, "charge": 2, "crouch": 1,
               "stun": 2, "stun_recover": 1, "flight": 3, "jumpscare": 4}.get(clip_name, max(1, round(length / 1.2)))   # emotes: one swing per ~1.2 s
        for b in bones:
            if not b["sway"]:
                continue
            ax, az, mult, phase = b["sway"][:4]
            ay = b["sway"][4] if len(b["sway"]) > 4 else 0     # optional yaw (side-to-side wag)
            amp = {"idle": .5, "walk": 1.0, "chase": 1.5, "sprint": 1.8, "charge": 1.8, "crouch": .4,
                   "stun": .7, "flight": b.get("flight_amp", 1.0) if isinstance(b, dict) else 1.0,
                   "jumpscare": 1.6}.get(clip_name, 1.0)
            if b["name"].endswith("Wing"):
                amp = {"idle": .5, "walk": .8, "chase": 1.2, "sprint": 1.4, "charge": 1.4, "crouch": .35,
                       "stun": 1.0, "flight": 3.2, "jumpscare": 2.0}.get(clip_name, 1.2)
                cyc2 = {"idle": 2, "walk": 3, "chase": 5, "sprint": 6, "charge": 6, "crouch": 1,
                        "stun": 4, "flight": 10, "jumpscare": 8}.get(clip_name, max(2, round(length * 3)))
            else:
                cyc2 = cyc * mult
            rule = stun_mod.extra_rule(st, b["name"]) if clip_name in ("stun", "stun_recover") else None
            off = (0.0, 0.0, 0.0)
            if rule:
                amp *= rule[0]
                if rule[1]:
                    cyc2 = cyc * rule[1] if clip_name == "stun" else cyc2
                sgn = -1 if b["name"].startswith("L-") else 1
                off = (rule[2][0], rule[2][1], rule[2][2] * sgn)
            n = 12 if cyc2 <= 3 else max(12, int(cyc2 * 4))
            times = [length * i / n for i in range(n + 1)]
            vals = []
            for i in range(n + 1):
                ph = 2 * math.pi * cyc2 * i / n + phase
                e = (ax * amp * math.sin(ph), ay * amp * math.sin(ph + .6), az * amp * math.sin(ph + 1.1))
                if b["name"].endswith("Wing"):
                    e = (0, ax * amp * math.sin(ph), 0)
                e = (e[0] + off[0], e[1] + off[1], e[2] + off[2])
                vals.append(quat_euler(e, b["rot"]))
            clip["tracks"][b["name"]] = {"rotation": (times, vals)}
    return clips


def quat_euler(e, base):
    return quat_mul(quat_from_euler(*e), base)


LOCOMOTION = ("walk", "chase", "sprint", "charge", "crouch")
LEG = ("L-Thigh", "R-Thigh", "L-Foot", "R-Foot")
KNEE = ("L-Calf", "R-Calf")
ARM = ("L-Arm", "R-Arm", "L-Forearm", "R-Forearm", "L-Hand", "R-Hand")
DEFAULT_PROFILE = dict(tempo=1.0, stride=1.0, knee=1.0, arm_swing=1.0, bounce=1.0, lean=0.0, head_pitch=0.0,
                       head_roll=0.0, shoulder_in=0.0, idle_amp=1.0, idle_tempo=1.0)


def _scale_about(rest, q, k):
    """Scale the rotation q away from `rest` by k (small-angle nlerp), keeping it a unit quaternion."""
    d = sum(a * b for a, b in zip(rest, q))
    q = tuple(-v for v in q) if d < 0 else q
    r = tuple(rest[i] + (q[i] - rest[i]) * k for i in range(4))
    n = math.sqrt(sum(v * v for v in r)) or 1.0
    return tuple(v / n for v in r)


def _apply_profile(clips, restq, pel, prof):
    """Per-hunter motion: reshape the shared clips (tempo, stride, bounce, posture ...) without changing the
    rig, so every hunter still plays the same clip names."""
    p = dict(DEFAULT_PROFILE)
    p.update(prof)
    for name, clip in clips.items():
        tempo = p["tempo"] if name in LOCOMOTION else p["idle_tempo"] if name == "idle" else 1.0
        if tempo != 1.0:
            clip["length"] = clip["length"] / tempo
            for tr in clip["tracks"].values():
                for chan, (t, v) in list(tr.items()):
                    tr[chan] = ([x / tempo for x in t], v)
        for bone, tr in clip["tracks"].items():
            if "rotation" not in tr:
                continue
            t, v = tr["rotation"]
            rest = restq[bone]
            k = 1.0
            if name in LOCOMOTION:
                k = p["stride"] if bone in LEG else p["knee"] * p["stride"] if bone in KNEE else p["arm_swing"] if bone in ARM else 1.0
            elif name == "idle":
                k = p["idle_amp"]
            if k != 1.0:
                v = [_scale_about(rest, q, k) for q in v]
            if name != "jumpscare":
                off = (0.0, 0.0, 0.0)
                if bone in ("Belly", "Chest"):
                    off = (-p["lean"] / 2, 0.0, 0.0)
                elif bone == "Head":
                    off = (-p["head_pitch"] + p["lean"], 0.0, p["head_roll"])   # lean is cancelled so the head stays level
                elif bone == "L-Arm":
                    off = (0.0, 0.0, p["shoulder_in"])
                elif bone == "R-Arm":
                    off = (0.0, 0.0, -p["shoulder_in"])
                if any(off):
                    v = [quat_mul(quat_from_euler(*off), q) for q in v]
            tr["rotation"] = (t, v)
        pt = clip["tracks"].get("Pelvis", {}).get("translation")
        if pt and p["bounce"] != 1.0 and name in LOCOMOTION + ("idle",):
            t, v = pt
            clip["tracks"]["Pelvis"]["translation"] = (t, [(pel[0] + (x - pel[0]) * p["bounce"], pel[1] + (y - pel[1]) * p["bounce"],
                                                            pel[2] + (z - pel[2]) * p["bounce"]) for x, y, z in v])


# How far the lowest sole may rise above the floor per clip (airborne phase of a run); everything else is fitted so
# the lowest foot touches the floor (a pelvis bob that is bigger than the legs can follow makes feet float or sink).
GROUND_SLACK = {"idle": 0.0, "walk": 0.015, "chase": 0.03, "sprint": 0.05, "charge": 0.04, "crouch": 0.0, "stun": 0.0,
                "stun_recover": 0.0}


def ground_fit(clips, bones, restq, hovering=False):
    """Forward-kinematics pass: raise / lower the Pelvis per key so the lowest sole is on the floor (within the slack above)."""
    import numpy as np

    def qm(q):
        x, y, z, w = q
        return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    par = {b["name"]: b["parent"] for b in bones}
    piv = {b["name"]: np.array(b["pivot"], float) for b in bones}
    chain = {}
    for f in ("L-Foot", "R-Foot"):
        c, n = [], f
        while n:
            c.append(n)
            n = par[n]
        chain[f] = c[::-1]
    sole = {f: np.array([0.0, -piv[f][1], 0.0]) for f in chain}      # sole point in foot space (pivot height above floor)

    def interp(t, v, x):
        i = max(0, min(len(t) - 2, int(np.searchsorted(t, x, side="right") - 1)))
        u = (x - t[i]) / max(t[i + 1] - t[i], 1e-9)
        a, b = np.array(v[i]), np.array(v[i + 1])
        if a @ b < 0:
            b = -b
        r = a + (b - a) * u
        return r / np.linalg.norm(r)
    for name, slack in GROUND_SLACK.items():
        clip = clips.get(name)
        if clip is None or (hovering and name.startswith("stun")):
            continue
        pt = clip["tracks"]["Pelvis"].get("translation")
        if pt is None:
            continue
        times, trans = pt
        new = []
        for i, x in enumerate(times):
            low = 1e9
            for f, ch in chain.items():
                M = np.eye(4)
                for n in ch:
                    tr = piv[n] - (piv[par[n]] if par[n] else 0 * piv[n])
                    if n == "Pelvis":
                        tr = np.array(trans[i], float)
                    rot = clip["tracks"].get(n, {}).get("rotation")
                    L = np.eye(4)
                    L[:3, :3] = qm(interp(rot[0], rot[1], x) if rot else restq[n])
                    L[:3, 3] = tr
                    M = M @ L
                low = min(low, (M @ np.append(sole[f], 1.0))[1])
            shift = -low if low < 0 else (-(low - slack) if low > slack else 0.0)
            new.append((trans[i][0], trans[i][1] + shift, trans[i][2]))
        clip["tracks"]["Pelvis"]["translation"] = (times, new)


# (bone, euler amplitude deg, cycles per clip, phase) added on top of the clip; walk = 1 gait cycle per clip
OVERLAYS = {
    "idle": [("Chest", (2.2, 0, 0), 1, 0.0), ("Belly", (0, 0, 2.0), 1, 1.6), ("Pelvis", (0, 0, 1.6), 1, 1.6),
             ("Head", (-1.6, 5.0, 0), 1, 0.4), ("L-Arm", (0, 0, 2.5), 1, 0.0), ("R-Arm", (0, 0, -2.5), 1, 0.0)],
    "walk": [("Chest", (0, 6.0, 0), 1, 0.0), ("Pelvis", (0, -5.0, 3.0), 1, 0.0), ("Belly", (0, 0, 2.5), 1, 1.0),
             ("Head", (2.0, 0, 0), 2, 0.5)],
    "chase": [("Chest", (0, 8.0, 0), 1, 0.0), ("Pelvis", (0, -6.0, 3.5), 1, 0.0), ("Belly", (0, 0, 3.0), 1, 1.0),
              ("Head", (2.5, 0, 0), 2, 0.5)],
    "sprint": [("Chest", (0, 11.0, 0), 1, 0.0), ("Pelvis", (0, -8.0, 4.0), 1, 0.0), ("Belly", (0, 0, 4.0), 1, 1.0),
               ("Head", (3.0, 0, 0), 2, 0.5)],
    "charge": [("Chest", (0, 7.0, 0), 1, 0.0), ("Pelvis", (0, -5.0, 3.0), 1, 0.0), ("Head", (2.0, 0, 0), 2, 0.5)],
}


def overlay(clip, restq, specs, n=24):
    """Add sinusoidal rotation offsets to bones of a looping clip (the bone's track is resampled to n+1 keys)."""
    length = clip["length"]
    times = [length * i / n for i in range(n + 1)]
    for bone, amp, cyc, phase in specs:
        tr = clip["tracks"].setdefault(bone, {})
        old = tr.get("rotation")
        vals = []
        for i, x in enumerate(times):
            q = restq[bone] if old is None else _sample_q(old[0], old[1], x)
            ph = 2 * math.pi * cyc * (i % n) / n + phase
            e = tuple(a * math.sin(ph) for a in amp)
            vals.append(quat_mul(quat_from_euler(*e), q))
        tr["rotation"] = (times, vals)


def _sample_q(t, v, x):
    i = max(0, min(len(t) - 2, next((k for k in range(len(t) - 1) if t[k + 1] >= x), len(t) - 2)))
    u = (x - t[i]) / max(t[i + 1] - t[i], 1e-9)
    a, b = v[i], v[i + 1]
    if sum(p * q for p, q in zip(a, b)) < 0:
        b = tuple(-c for c in b)
    r = tuple(a[k] + (b[k] - a[k]) * u for k in range(4))
    nrm = math.sqrt(sum(c * c for c in r)) or 1.0
    return tuple(c / nrm for c in r)
