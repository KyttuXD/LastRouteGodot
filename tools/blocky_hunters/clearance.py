"""Build-time clearance for swaying parts (hair chains, braids, tails, ears, wings, horns, cues ...).

The extra bones get procedural sway in every clip (bb_rig.build_clips) that knows nothing about the body: a ponytail
hanging off a head that leans into a chase swings through the belly, wings flap through the forearms. This pass walks
every clip frame, does forward kinematics for the core rig, and for each extra bone (parents first) keeps the sway that
was asked for unless that pushes the part's box deeper into a body box than it sits at rest (plus TOL). When it does it
searches, cheapest first, for a smaller sway and/or a pitch/yaw/roll offset that clears the body. The look is kept: a
part only deviates in the frames where it would have clipped, by as little as possible.

The depth test is the same oriented-box SAT as game/world/collision/hunter_clip_audit.gd (the Godot validator that guards it)."""
import itertools, math
import numpy as np
from bb_core import quat_from_euler, quat_mul

import os
DEBUG = bool(os.environ.get("CLEARANCE_DEBUG"))
TOL = 0.006            # metres of extra penetration over the rest pose we accept on the torso/head (the validator's tolerance is 0.012)
TOL_LIMB = 0.035       # limbs swing through a hanging braid on their own (a wave, a stumble): accepted up to this (validator: 0.06)
TORSO = {"Pelvis", "Belly", "Chest", "Head"}
CORE = {"Pelvis", "Belly", "Chest", "Head", "L-Arm", "L-Forearm", "L-Hand", "R-Arm", "R-Forearm", "R-Hand",
        "L-Thigh", "L-Calf", "L-Foot", "R-Thigh", "R-Calf", "R-Foot"}
SCALES = (1.0, 0.75, 0.5, 0.3, 0.15, 0.0)
# (pitch, yaw, roll) offsets in degrees tried on top of the sway, small first
OFFSETS = sorted({(a, b, c) for a in (0, 6, -6, 12, -12, 20, -20, 32, -32, 48, -48, 70, -70, 90, -90) for b in (0, 8, -8, 18, -18, 32, -32, 60, -60)
                  for c in (0, 8, -8, 18, -18, 32, -32, 60, -60, 90, -90) if (a != 0) + (b != 0) + (c != 0) <= 2},
                 key=lambda o: abs(o[0]) + abs(o[1]) + abs(o[2]))

CANDIDATES = sorted(((1 - s) * 40 + abs(o[0]) + abs(o[1]) + abs(o[2]), s, o) for s in SCALES for o in OFFSETS)

# wings only calm down (a smaller flap): any pitch/yaw/roll offset swings them out wider than a one-cell door (validate_door_clearance)
WING_CANDIDATES = [c for c in CANDIDATES if not any(c[2])]


def qmat(q):
    x, y, z, w = q
    n = math.sqrt(x * x + y * y + z * z + w * w) or 1.0
    x, y, z, w = x / n, y / n, z / n, w / n
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def nlerp(a, b, u):
    if sum(p * q for p, q in zip(a, b)) < 0:
        b = tuple(-v for v in b)
    r = tuple(a[i] + (b[i] - a[i]) * u for i in range(4))
    n = math.sqrt(sum(v * v for v in r)) or 1.0
    return tuple(v / n for v in r)


def sample_q(track, t):
    times, vals = track
    if t <= times[0]:
        return vals[0]
    if t >= times[-1]:
        return vals[-1]
    i = int(np.searchsorted(times, t, side="right") - 1)
    return nlerp(vals[i], vals[i + 1], (t - times[i]) / max(times[i + 1] - times[i], 1e-9))


def sample_v(track, t):
    times, vals = track
    if t <= times[0]:
        return np.array(vals[0], float)
    if t >= times[-1]:
        return np.array(vals[-1], float)
    i = int(np.searchsorted(times, t, side="right") - 1)
    u = (t - times[i]) / max(times[i + 1] - times[i], 1e-9)
    return np.array(vals[i], float) * (1 - u) + np.array(vals[i + 1], float) * u


def obb_depth(ca, Ra, ha, cb, Rb, hb):
    """Penetration depth of two oriented boxes (centre, rotation columns = axes, half extents); 0 when apart."""
    d = cb - ca
    if d @ d > (ha @ ha) ** 0.5 + (hb @ hb) ** 0.5 and d @ d > ((ha @ ha) ** 0.5 + (hb @ hb) ** 0.5) ** 2:
        return 0.0
    A, B = Ra.T, Rb.T
    cr = np.cross(A[:, None, :], B[None, :, :]).reshape(9, 3)
    n = np.linalg.norm(cr, axis=1)
    cr = cr[n > 1e-4] / n[n > 1e-4, None]
    axes = np.vstack([A, B, cr])
    ra = np.abs(axes @ Ra) @ ha
    rb = np.abs(axes @ Rb) @ hb
    o = ra + rb - np.abs(axes @ d)
    m = float(o.min())
    return m if m > 0 else 0.0


class Rig:
    def __init__(self, model, bones, scale):
        self.bones = [b["name"] for b in bones]
        self.parent = {b["name"]: b["parent"] for b in bones}
        self.rest_q = {b["name"]: tuple(b["rot"]) for b in bones}
        pv = {b["name"]: b["pivot"] for b in bones}
        self.local_t = {n: np.array([(pv[n][i] - (pv[self.parent[n]][i] if self.parent[n] else 0)) * scale for i in range(3)])
                        for n in self.bones}
        # per-bone AABB in bone space (what the Godot mesh reports), from the exact cube corners
        lo, hi = {}, {}
        for ci, c in enumerate(model.cubes):
            if c.group == "face" or c.bone not in pv:
                continue
            for f, corners, _ in model.cube_faces(ci):
                for p in corners:
                    q = np.array([(p[i] - pv[c.bone][i]) * scale for i in range(3)])
                    lo[c.bone] = np.minimum(lo.get(c.bone, q), q)
                    hi[c.bone] = np.maximum(hi.get(c.bone, q), q)
        self.box = {n: ((lo[n] + hi[n]) / 2, (hi[n] - lo[n]) / 2) for n in lo}

    def world(self, rot, trans):
        """rot: bone -> quat, trans: bone -> local translation override. Returns bone -> (R, origin)."""
        out = {}
        for n in self.bones:
            R = qmat(rot.get(n, self.rest_q[n]))
            t = trans.get(n, self.local_t[n])
            p = self.parent[n]
            if p:
                PR, PO = out[p]
                out[n] = (PR @ R, PO + PR @ t)
            else:
                out[n] = (R, t.copy())
        return out

    def depths(self, W, parts, body):
        res = {}
        for p in parts:
            if p not in self.box:
                continue
            c, h = self.box[p]
            Rp, Op = W[p]
            cp = Op + Rp @ c
            for b in body:
                if b not in self.box:
                    continue
                cb_, hb = self.box[b]
                Rb, Ob = W[b]
                d = obb_depth(cp, Rp, h, Ob + Rb @ cb_, Rb, hb)
                if d > 0:
                    res[(p, b)] = d
        return res


def solve(model, bones, clips, scale, verbose=False):
    rig = Rig(model, bones, scale)
    extras = [n for n in rig.bones if n not in CORE and n in rig.box]
    if not extras:
        return 0
    body = [n for n in rig.bones if n in CORE and n in rig.box]
    rest_world = rig.world({}, {})
    rest_depth = rig.depths(rest_world, extras, body)
    changed = 0
    for cname, clip in clips.items():
        tracks = clip["tracks"]
        for bone in extras:          # tree order: parents before children
            tr = tracks.get(bone, {}).get("rotation")
            if tr is None:
                continue
            times, vals = tr
            new_vals = []
            for i, t in enumerate(times):
                rot = {n: sample_q(tracks[n]["rotation"], t) for n in rig.bones
                       if n in tracks and "rotation" in tracks[n] and n != bone}
                trans = {}
                if "Pelvis" in tracks and "translation" in tracks["Pelvis"]:
                    trans["Pelvis"] = sample_v(tracks["Pelvis"]["translation"], t) * scale
                best = _pick(rig, rot, trans, bone, vals[i], body, rest_depth, rest_world)
                if best != vals[i]:
                    changed += 1
                new_vals.append(best)
            tracks[bone]["rotation"] = (times, new_vals)
    if verbose:
        print(f"  clearance: {changed} sway keys adjusted")
    return changed


def _pick(rig, rot, trans, bone, desired, body, rest_depth, rest_world):
    rest = rig.rest_q[bone]
    W = rig.world(rot, trans)
    PR, PO = W[rig.parent[bone]]
    lt = rig.local_t[bone]
    c, h = rig.box[bone]
    wing = bone.endswith("Wing")
    bodies = [(W[b][1] + W[b][0] @ rig.box[b][0], W[b][0], rig.box[b][1], rest_depth.get((bone, b), 0.0) + (0.0 if b in TORSO else TOL_LIMB - TOL)) for b in body]

    def excess(q):
        R = PR @ qmat(q)
        O = PO + PR @ lt
        cp = O + R @ c
        worst = 0.0
        for cb, Rb, hb, base in bodies:
            d = obb_depth(cp, R, h, cb, Rb, hb)
            if d - base > worst:
                worst = d - base
        return worst

    ex0 = excess(desired)
    if ex0 <= TOL:
        return desired
    least, least_ex = desired, 1e9
    for cost, s, off in (WING_CANDIDATES if wing else CANDIDATES):
        q = nlerp(rest, desired, s)
        if any(off):
            q = quat_mul(quat_from_euler(*off), q)
        ex = excess(q)
        if ex <= TOL:
            return q                       # candidates are in ascending cost order: the first clear one is the cheapest
        if ex < least_ex:
            least, least_ex = q, ex
    if DEBUG:
        print(f"    unsolved {bone}: {ex0*100:.1f} cm -> {least_ex*100:.1f} cm")
    return least
