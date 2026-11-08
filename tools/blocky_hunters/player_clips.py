"""Clip set of the player mannequin (same rig, same bone names as the hunters).

From the shared gait set (idle walk chase sprint crouch stun stun_recover) plus what the player controller and the
old wooden mannequin use: sit, lay (both loops, played on furniture), tpose (reference pose), and the movement extras
jump (one-shot), fall (loop) and climb (loop, ladders). No charge / flight / jumpscare / emotes (hunters only).

lay is face-up with the head toward +Z and the feet toward -Z (the way the player faces is -Z), pelvis resting on the
floor: the Godot side rotates the model on the furniture if the bed points the other way."""
import math
import bb_rig
from bb_core import quat_from_euler, quat_mul

KEEP = ("idle", "walk", "chase", "sprint", "crouch", "stun", "stun_recover")


def build(bones, hip_y, profile):
    restq = {b["name"]: b["rot"] for b in bones}
    pel = next(b for b in bones if b["name"] == "Pelvis")["pivot"]
    U = hip_y / 12.0                                 # one skin pixel in design metres
    clips = bb_rig.build_clips(bones, hip_y, profile, None)
    clips = {n: clips[n] for n in KEEP}

    def sampled(length, n, pose, dy=lambda i: 0.0, loop=True, dz=lambda i: 0.0):
        times = [length * i / n for i in range(n + 1)]
        tr = {}
        for b in bb_rig.CORE_NAMES:
            vals = []
            for i in range(n + 1):
                ii = i % n if loop else i
                e = pose(b, ii) or (0, 0, 0)
                vals.append(quat_mul(quat_from_euler(*e), restq[b]))
            tr[b] = {"rotation": (times, vals)}
        tr["Pelvis"]["translation"] = (times, [(pel[0], pel[1] + dy(i % n if loop else i), pel[2] + dz(i % n if loop else i))
                                                for i in range(n + 1)])
        return {"length": length, "tracks": tr, "loop": loop}

    # tpose: arms straight out, the reference pose
    clips["tpose"] = sampled(1.0, 2, lambda b, i: {"L-Arm": (0, 0, -90), "R-Arm": (0, 0, 90)}.get(b))

    # sit: thighs level, shins vertical, hands resting on the thighs, a slow breath
    def sit(b, i, n=12):
        br = math.sin(2 * math.pi * i / n)
        return {"Chest": (-3 + 1.5 * br, 0, 0), "Belly": (-3, 0, 0), "Head": (4 - 1.2 * br, 0, 0),
                "L-Thigh": (88, 0, -3), "R-Thigh": (88, 0, 3), "L-Calf": (-88, 0, 0), "R-Calf": (-88, 0, 0),
                "L-Arm": (24, 0, -5), "R-Arm": (24, 0, 5), "L-Forearm": (40, 0, 0), "R-Forearm": (40, 0, 0)}.get(b)
    clips["sit"] = sampled(2.4, 12, sit, lambda i: -6 * U)

    # lay: on the back, head toward +Z, legs straight, arms by the sides, a slow breath
    def lay(b, i, n=12):
        br = math.sin(2 * math.pi * i / n)
        return {"Pelvis": (90, 0, 0), "Chest": (1.2 * br, 0, 0), "L-Arm": (0, 0, -4), "R-Arm": (0, 0, 4)}.get(b)
    clips["lay"] = sampled(2.4, 12, lay, lambda i: -(12 - 2.1) * U)

    # jump (one-shot, 0.8 s): crouch, launch with the arms up, tuck in the air, land
    def jump(b, i):
        phase = ["stand", "load", "launch", "air", "air2", "land", "stand"][i]
        P = {
            "stand": {},
            "load": {"Belly": (-8, 0, 0), "Chest": (-6, 0, 0), "L-Thigh": (38, 0, 0), "R-Thigh": (38, 0, 0), "L-Calf": (-70, 0, 0), "R-Calf": (-70, 0, 0),
                     "L-Foot": (32, 0, 0), "R-Foot": (32, 0, 0), "L-Arm": (-40, 0, -6), "R-Arm": (-40, 0, 6)},
            "launch": {"Chest": (4, 0, 0), "Head": (6, 0, 0), "L-Arm": (150, 0, -12), "R-Arm": (150, 0, 12), "L-Calf": (-6, 0, 0), "R-Calf": (-6, 0, 0)},
            "air": {"L-Arm": (120, 0, -26), "R-Arm": (120, 0, 26), "L-Thigh": (28, 0, 0), "R-Thigh": (10, 0, 0), "L-Calf": (-50, 0, 0), "R-Calf": (-22, 0, 0)},
            "air2": {"L-Arm": (60, 0, -34), "R-Arm": (60, 0, 34), "L-Thigh": (16, 0, 0), "R-Thigh": (24, 0, 0), "L-Calf": (-30, 0, 0), "R-Calf": (-40, 0, 0)},
            "land": {"Belly": (-10, 0, 0), "Chest": (-6, 0, 0), "L-Thigh": (42, 0, 0), "R-Thigh": (42, 0, 0), "L-Calf": (-76, 0, 0), "R-Calf": (-76, 0, 0),
                     "L-Foot": (34, 0, 0), "R-Foot": (34, 0, 0), "L-Arm": (20, 0, -20), "R-Arm": (20, 0, 20)},
        }[phase]
        return P.get(b)
    jump_dy = [0, -.10, .02, .14, .10, -.11, 0]                       # pelvis height per key (design m)
    clips["jump"] = sampled(0.8, 6, jump, lambda i: jump_dy[i], loop=False)

    # fall: arms out and up, legs loose, a little flap (loop)
    def fall(b, i, n=8):
        s = math.sin(2 * math.pi * i / n)
        return {"Belly": (-4, 0, 0), "Head": (8, 0, 0), "L-Arm": (60 + 12 * s, 0, -42), "R-Arm": (60 - 12 * s, 0, 42),
                "L-Forearm": (20, 0, 0), "R-Forearm": (20, 0, 0),
                "L-Thigh": (18 + 6 * s, 0, -6), "R-Thigh": (12 - 6 * s, 0, 6), "L-Calf": (-30, 0, 0), "R-Calf": (-24, 0, 0)}.get(b)
    clips["fall"] = sampled(0.8, 8, fall, lambda i: 0.0)

    # climb: facing the ladder, hands reach up alternately, knees come up alternately (loop)
    def climb(b, i, n=8):
        p = 2 * math.pi * i / n
        s, c = math.sin(p), math.cos(p)
        return {"Chest": (-4, 6 * s, 0), "Belly": (-3, 0, 0), "Head": (-10, 0, 0),
                "L-Arm": (140 + 22 * s, 0, -10), "R-Arm": (140 - 22 * s, 0, 10), "L-Forearm": (30 - 20 * s, 0, 0), "R-Forearm": (30 + 20 * s, 0, 0),
                "L-Thigh": (30 + 28 * s, 0, -3), "R-Thigh": (30 - 28 * s, 0, 3),
                "L-Calf": (-50 - 30 * s, 0, 0), "R-Calf": (-50 + 30 * s, 0, 0)}.get(b)
    clips["climb"] = sampled(1.0, 8, climb, lambda i: .01 * math.cos(4 * math.pi * i / 8))
    bb_rig.ground_fit(clips, bones, restq)
    return clips
