"""Build-time hair / tail physics, baked into the clips.

Hunters with long hair or tails have a chain of bones (Pony-1..3, L/R-Pig-1..n, Tail-1..4): a few segments per strand group. Rather than
sine sway (which knows nothing about the body), each chain is simulated once per clip, offline and deterministically:

  * the chain root rides the head / pelvis from forward kinematics of the clip's core bones;
  * each segment tip is a Verlet particle: gravity pulls it down, damping settles it, and a soft spring pulls it back toward where a
    rigid strand would be (the hair follows head and body motion with inertia and a little lag, then settles);
  * each segment's swing is limited (SWING_FIRST from the rest direction, SWING_NEXT from the segment above);
  * particles (and segment midpoints) are pushed out of the head, shoulders, arms, torso and legs, so the hair drapes over the shoulders or
    down the back and never passes through the body.

The result is written back as ordinary rotation keys on the chain bones, so there is nothing to run in the game: no cost, identical on every
peer, not synced. The shared sway scale (bb_rig.SWAY_SCALE, times the hunter's `sway` profile value) sets how loose the strand is:
lower scale = stiffer spring and more damping = calmer hair. clearance.py still runs afterwards as a safety net."""
import math, re
import numpy as np
from bb_core import quat_mul
from clearance import Rig, qmat, sample_q, sample_v, nlerp, CORE

CHAIN = re.compile(r"^(?:[LR]-)?(Pony|Pig|Tail)-\d+$")
DT = 1.0 / 60.0
GRAVITY = 9.8
SWING_FIRST = math.radians(70)     # first segment, from the rigid (follows the head) direction
SWING_NEXT = math.radians(40)      # each further segment, from the segment above it
HAIR_RADIUS = 0.025                # metres of clearance kept between a strand and the body
KEYS_PER_SECOND = 24


def _is_chain(name):
    return bool(CHAIN.match(name)) or name.startswith("Tail-Fin")


def chains_of(rig):
    """Bone chains [[b1, b2, ...], ...] in order, root first (a chain root is a hair/tail bone whose parent is not one)."""
    kids = {}
    for n in rig.bones:
        kids.setdefault(rig.parent[n], []).append(n)
    out = []
    for n in rig.bones:
        if not CHAIN.match(n) or (rig.parent[n] and _is_chain(rig.parent[n])):
            continue
        chain = [n]
        while True:
            nxt = [k for k in kids.get(chain[-1], []) if _is_chain(k)]
            if not nxt:
                break
            chain.append(nxt[0])
        out.append(chain)
    return out


def _unit(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else v


def _swing(a, b):
    """Quaternion (x, y, z, w) rotating unit vector a onto unit vector b by the shortest arc."""
    d = float(np.dot(a, b))
    if d < -0.999999:
        ax = _unit(np.cross(a, np.array([1.0, 0, 0])) if abs(a[0]) < 0.9 else np.cross(a, np.array([0, 1.0, 0])))
        return (ax[0], ax[1], ax[2], 0.0)
    c = np.cross(a, b)
    q = np.array([c[0], c[1], c[2], 1.0 + d])
    return tuple(q / np.linalg.norm(q))


def _limit(d, ref, max_angle):
    """Clamp unit vector d to within max_angle of unit vector ref."""
    cosang = float(np.clip(np.dot(d, ref), -1, 1))
    if math.acos(cosang) <= max_angle:
        return d
    perp = _unit(d - ref * cosang)
    return _unit(ref * math.cos(max_angle) + perp * math.sin(max_angle))


def _push_out(p, boxes, r):
    for cb, Rb, hb in boxes:
        loc = Rb.T @ (p - cb)
        pen = hb + r - np.abs(loc)
        if np.all(pen > 0):
            i = int(np.argmin(pen))
            loc[i] += math.copysign(pen[i], loc[i] if loc[i] != 0 else 1.0)
            p = cb + Rb @ loc
    return p


def simulate(model, bones, clips, scale, sway=1.0, verbose=False):
    """Replace the sway tracks of every hair/tail chain with simulated ones. `sway` = shared scale (SWAY_SCALE * hunter multiplier)."""
    rig = Rig(model, bones, scale)
    chains = chains_of(rig)
    if not chains:
        return 0
    body = [n for n in rig.bones if n in CORE and n in rig.box]
    # looser at higher sway: the spring that pulls a strand back to its rigid pose, and the damping that calms it
    stiff = 0.16 - 0.1 * min(sway, 1.0)
    damp = 0.20 - 0.10 * min(sway, 1.0)
    written = 0
    for cname, clip in clips.items():
        tracks = clip["tracks"]
        length = clip["length"]
        looping = clip.get("loop", True)
        n_keys = max(12, int(round(length * KEYS_PER_SECOND)))
        key_times = [length * i / n_keys for i in range(n_keys + 1)]
        steps_per_cycle = max(1, int(round(length / DT)))
        cycles = 3 if looping else 1

        def core_world(t):
            rot = {n: sample_q(tracks[n]["rotation"], t) for n in rig.bones
                   if n in tracks and "rotation" in tracks[n] and n in CORE}
            trans = {}
            if "Pelvis" in tracks and "translation" in tracks["Pelvis"]:
                trans["Pelvis"] = sample_v(tracks["Pelvis"]["translation"], t) * scale
            return rot, trans

        for chain in chains:
            seg_len, seg_rest = [], []
            for k, b in enumerate(chain):
                if k + 1 < len(chain):
                    v = rig.local_t[chain[k + 1]]
                else:
                    c, h = rig.box[b]
                    v = np.array([0.0, c[1] - h[1] if h[1] > 0 else -0.1, 0.0])      # to the bottom of the last segment
                    v = np.array([0.0, min(v[1], -0.05), 0.0])
                seg_len.append(float(np.linalg.norm(v)))
                seg_rest.append(v)
            out_rot = {b: [] for b in chain}
            # state: world tip position per segment
            rest_world = rig.world({}, {})
            tips = [rest_world[b][1] + rest_world[b][0] @ seg_rest[k] for k, b in enumerate(chain)]
            prev = [t.copy() for t in tips]
            total_steps = steps_per_cycle * cycles
            record_from = steps_per_cycle * (cycles - 1)
            key_step = {int(round(kt / DT)) + record_from: i for i, kt in enumerate(key_times)}
            captured = {}
            for step in range(total_steps + 1):
                t = (step % steps_per_cycle) * DT if looping else min(step * DT, length)
                rot, trans = core_world(t)
                W = rig.world(rot, trans)
                root_parent = W[rig.parent[chain[0]]]
                root = root_parent[1] + root_parent[0] @ rig.local_t[chain[0]]
                boxes = [(W[b][1] + W[b][0] @ rig.box[b][0], W[b][0], rig.box[b][1]) for b in body]
                # rigid target: where each tip would be if the strand were stiff on the head
                tgt, anchor, pR = [], root, root_parent[0]
                Rk = root_parent[0] @ qmat(rig.rest_q[chain[0]])
                pos = root
                for k, b in enumerate(chain):
                    pos = pos + Rk @ seg_rest[k]
                    tgt.append(pos.copy())
                    if k + 1 < len(chain):
                        Rk = Rk @ qmat(rig.rest_q[chain[k + 1]])
                # verlet
                for k in range(len(chain)):
                    vel = (tips[k] - prev[k]) * (1.0 - damp)
                    prev[k] = tips[k].copy()
                    tips[k] = tips[k] + vel + np.array([0, -GRAVITY, 0]) * DT * DT * 0.35 + (tgt[k] - tips[k]) * stiff
                for _ in range(3):
                    above = root
                    ref_dir = _unit(tgt[0] - root)
                    for k in range(len(chain)):
                        d = tips[k] - above
                        d = _unit(d) if np.linalg.norm(d) > 1e-9 else ref_dir
                        d = _limit(d, ref_dir, SWING_FIRST if k == 0 else SWING_NEXT)
                        tip = above + d * seg_len[k]
                        tip = _push_out(tip, boxes, HAIR_RADIUS)
                        mid = _push_out((above + tip) / 2, boxes, HAIR_RADIUS)
                        if np.linalg.norm(mid - (above + tip) / 2) > 1e-9:
                            tip = tip + (mid - (above + tip) / 2) * 1.5
                        d = _unit(tip - above)
                        tips[k] = above + d * seg_len[k]
                        above = tips[k]
                        ref_dir = d
                if step in key_step:
                    # bone rotations from the segment directions, parents first
                    Rparent, origin = root_parent[0], root
                    above = root
                    for k, b in enumerate(chain):
                        d = _unit(tips[k] - above)
                        local_dir = Rparent.T @ d
                        base = qmat(rig.rest_q[b])
                        q = _swing(_unit(seg_rest[k]), _unit(local_dir))
                        full = quat_mul(q, rig.rest_q[b])
                        captured.setdefault(key_step[step], {})[b] = full
                        Rparent = Rparent @ qmat(full)
                        above = tips[k]
            for b in chain:
                vals = [captured[i][b] for i in range(n_keys + 1) if i in captured]
                if len(vals) == n_keys + 1:
                    if looping:                       # close the loop: ease the last quarter of the clip back onto the first key
                        for i in range(n_keys + 1):
                            u = (i - 0.75 * n_keys) / (0.25 * n_keys)
                            if u > 0:
                                vals[i] = nlerp(vals[i], vals[0], u * u * (3 - 2 * u))
                    tracks.setdefault(b, {})["rotation"] = (key_times, vals)
                    written += 1
    if verbose:
        print(f"  hairsim: {len(chains)} chains, {written} tracks simulated")
    return written
