#!/usr/bin/env python3
"""Night Watch pose set for the shared blocky hunter rig, authored as DATA.

    python3 tools/blocky_hunters/nw_poses.py        # -> assets/hunters_blocky/night_watch_poses.json

No hunter model is touched: game/night_watch/night_watch_poses.gd compiles this JSON into an AnimationLibrary at load and adds
it to every hunter's AnimationPlayer (clips are named "nw/<pose>"). All keys are DELTAS from the model's rest pose:
rotations are euler degrees applied in the parent's space, translations are metres scaled by the hunter's leg length.

Axis cheat sheet (front is -Z, left is -X, a hanging limb points -Y):
  rot x  +  swings a hanging limb FORWARD / tips the torso BACK      (forward lean is negative x)
  rot y  +  turns a part to the LEFT
  rot z  +  tips a torso/head to the LEFT; for arms L raises with negative z, R with positive z
"""
import json
import math
import pathlib
import random

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent.parent / "assets" / "hunters_blocky" / "night_watch_poses.json"

# degrees (min, max) per axis: a pose key outside these is a validator failure (limb through the body, bent backwards ...)
LIMITS = {
    "Pelvis": {"x": (-85, 30), "y": (-60, 60), "z": (-25, 25)},
    "Belly": {"x": (-50, 25), "y": (-40, 40), "z": (-25, 25)},
    "Chest": {"x": (-50, 25), "y": (-45, 45), "z": (-25, 25)},
    "Head": {"x": (-40, 50), "y": (-70, 70), "z": (-35, 35)},
    "L-Arm": {"x": (-60, 175), "y": (-60, 60), "z": (-170, 8)},
    "R-Arm": {"x": (-60, 175), "y": (-60, 60), "z": (-8, 170)},
    "L-Forearm": {"x": (-10, 150), "y": (-30, 30), "z": (-30, 30)},
    "R-Forearm": {"x": (-10, 150), "y": (-30, 30), "z": (-30, 30)},
    "L-Hand": {"x": (-50, 50), "y": (-40, 40), "z": (-40, 40)},
    "R-Hand": {"x": (-50, 50), "y": (-40, 40), "z": (-40, 40)},
    "L-Thigh": {"x": (-50, 100), "y": (-35, 35), "z": (-40, 20)},
    "R-Thigh": {"x": (-50, 100), "y": (-35, 35), "z": (-20, 40)},
    "L-Calf": {"x": (-150, 5), "y": (-10, 10), "z": (-10, 10)},
    "R-Calf": {"x": (-150, 5), "y": (-10, 10), "z": (-10, 10)},
    "L-Foot": {"x": (-60, 70), "y": (-25, 25), "z": (-20, 20)},
    "R-Foot": {"x": (-60, 70), "y": (-25, 25), "z": (-20, 20)},
}
BONES = list(LIMITS)

POSES = {}


def mirror_bone(name):
    if name.startswith("L-"):
        return "R-" + name[2:]
    if name.startswith("R-"):
        return "L-" + name[2:]
    return name


def sample(length, fn, n=8, loop=True):
    """fn(phase 0..1) -> value; n+1 keys when looping so the last equals the first."""
    return [(length * i / n, fn(i / n)) for i in range(n + 1)]


def rot(keys):
    return {"rot": [[round(t, 4), *[round(v, 3) for v in e]] for t, e in keys]}


def hold(e, length=1.0):
    return [(0.0, e), (length, e)]


def wave_keys(length, base, amp, phase=0.0, n=8, axis=None, ease=None):
    """base: (x,y,z); amp: (ax,ay,az) sine amplitudes (one cycle per loop)."""
    def f(p):
        s = math.sin((p + phase) * math.tau)
        return tuple(base[i] + amp[i] * s for i in range(3))
    return sample(length, f, n)


def add(tracks, bone, keys):
    tracks.setdefault(bone, {"rot": [], "pos": []})
    tracks[bone]["rot"] = [[round(t, 4), *[round(v, 3) for v in e]] for t, e in keys]


def add_pos(tracks, bone, keys):
    tracks.setdefault(bone, {"rot": [], "pos": []})
    tracks[bone]["pos"] = [[round(t, 4), *[round(v, 4) for v in e]] for t, e in keys]


def pose(pid, length, loop, blend, tracks, grounded=True, hands_on_body=False, note="", layers=True, ease=1.0):
    POSES[pid] = {"length": length, "loop": loop, "blend": blend, "grounded": grounded, "layers": layers, "ease": ease,
                  "hands_on_body": hands_on_body, "note": note, "tracks": tracks}


def mirrored(pid, source, note=""):
    src = POSES[source]
    tracks = {}
    for bone, tr in src["tracks"].items():
        tracks[mirror_bone(bone)] = {
            "rot": [[t, x, -y, -z] for t, x, y, z in tr["rot"]],
            "pos": [[t, -x, y, z] for t, x, y, z in tr["pos"]],
        }
    POSES[pid] = dict(src, tracks=tracks, note=note or "mirror of " + source)


# --------------------------------------------------------------------------------------------------------- poses

# door lurk: standing in a lit doorway, shoulders slightly hunched, head forward, slow breathing sway
L = 3.2
t = {}
add(t, "Chest", wave_keys(L, (-5, 0, 0), (2.0, 0, 0)))
add(t, "Belly", wave_keys(L, (-4, 0, 0), (1.5, 0, 1.0)))
add(t, "Head", wave_keys(L, (-10, 0, 0), (2.5, 5, 2.0), phase=.25))
add(t, "L-Arm", wave_keys(L, (4, 0, -9), (1.5, 0, 1.5), phase=.1))
add(t, "R-Arm", wave_keys(L, (4, 0, 9), (1.5, 0, -1.5), phase=.1))
add(t, "L-Forearm", hold((12, 0, 0), L) if False else wave_keys(L, (14, 0, 0), (2, 0, 0)))
add(t, "R-Forearm", wave_keys(L, (14, 0, 0), (2, 0, 0)))
pose("door_lurk", L, True, .45, t, note="lit doorway, hunched, breathing sway")

# peek around a corner: lean and look sideways, one shoulder forward, head only reaches out
L = 2.4
t = {}
add(t, "Pelvis", wave_keys(L, (0, 0, 0), (0, 0, 0)))
add_pos(t, "Pelvis", sample(L, lambda p: (0.07, -0.01 + .004 * math.sin(p * math.tau), 0)))
add(t, "Belly", wave_keys(L, (-3, 0, 12), (1, 0, 1)))
add(t, "Chest", wave_keys(L, (-5, 8, 10), (1.5, 0, 1)))
add(t, "Head", wave_keys(L, (-4, 28, -16), (1.5, 4, 1), phase=.3))
add(t, "L-Arm", hold((10, 0, -4), L))
add(t, "R-Arm", hold((-8, 0, 14), L))
add(t, "L-Forearm", hold((30, 0, 0), L))
add(t, "L-Hand", hold((0, 0, 0), L))
add(t, "L-Thigh", hold((6, 0, -8), L))
add(t, "R-Thigh", hold((-4, 0, 6), L))
pose("peek_left", L, True, .35, t, note="lean left, head only past the corner")
mirrored("peek_right", "peek_left")

# route locker inspection (HunterInspect): the trailer's "locker breath" bow (its waist [-40, -22]) -- feet planted, she
# folds forward from the waist until her eyes are level with the locker's vent band and tips her chin up (positive Head
# x) to look straight in; seen from inside with dev/look/locker_inspect_capture.tscn her face fills the slats.
L = 3.0
t = {}
add_pos(t, "Pelvis", sample(L, lambda p: (0, -0.02 + .005 * math.sin(p * math.tau), 0)))
add(t, "Belly", wave_keys(L, (-40, 0, 0), (1.5, 0, 0)))
add(t, "Chest", wave_keys(L, (-22, 0, 0), (2.0, 0, 0), phase=.15))
add(t, "Head", wave_keys(L, (46, 0, 0), (1.5, 3, 0), phase=.3))
add(t, "L-Arm", hold((24, 0, -4), L))
add(t, "R-Arm", hold((24, 0, 4), L))
pose("locker_lean", L, True, .6, t, note="route locker inspection: bent in at the slats from the waist, face looking straight in")

# route corner peek (HunterPeek): the deep version. Feet planted behind the corner, the torso bends sideways from the
# belly so the head and most of the chest clear the edge, head turned down the hall. Body/legs stay put.
L = 2.0
t = {}
add_pos(t, "Pelvis", sample(L, lambda p: (0.12, -0.03 + .004 * math.sin(p * math.tau), 0)))
add(t, "Belly", wave_keys(L, (-4, 6, 20), (1, 0, 1.2)))
add(t, "Chest", wave_keys(L, (-6, 10, 18), (1.2, 0, 1.2)))
add(t, "Head", wave_keys(L, (-6, 20, -22), (1.5, 5, 1), phase=.3))
add(t, "L-Arm", hold((14, 0, -10), L))
add(t, "L-Forearm", hold((34, 0, 0), L))
add(t, "R-Arm", hold((-10, 0, 22), L))
add(t, "R-Forearm", hold((20, 0, 0), L))
add(t, "L-Thigh", hold((4, 0, -10), L))
add(t, "R-Thigh", hold((-4, 0, 8), L))
pose("corner_peek_left", L, True, .25, t, note="route corner peek: head and most of the chest past the edge, feet behind it")
mirrored("corner_peek_right", "corner_peek_left")

# stare at the camera: head locked square on the lens, slow tilt, arms limp
L = 5.0
t = {}
add(t, "Head", wave_keys(L, (-3, 0, 0), (1.5, 0, 12), n=10))
add(t, "Chest", wave_keys(L, (-2, 0, 0), (1.0, 0, 0)))
add(t, "L-Arm", hold((2, 0, -5), L))
add(t, "R-Arm", hold((2, 0, 5), L))
add(t, "L-Forearm", hold((6, 0, 0), L))
add(t, "R-Forearm", hold((6, 0, 0), L))
pose("stare_camera", L, True, .6, t, note="head locked front, slow tilt")

# pound on the door: both fists forward at shoulder height, alternating
L = .8
t = {}
add(t, "Chest", wave_keys(L, (-6, 0, 0), (3, 0, 0), phase=.25, n=8))
add(t, "L-Arm", wave_keys(L, (82, 0, -6), (14, 0, 0), n=8))
add(t, "R-Arm", wave_keys(L, (82, 0, 6), (-14, 0, 0), n=8))
add(t, "L-Forearm", wave_keys(L, (35, 0, 0), (25, 0, 0), n=8))
add(t, "R-Forearm", wave_keys(L, (35, 0, 0), (-25, 0, 0), n=8))
add(t, "Head", wave_keys(L, (14, 0, 0), (2, 0, 0), phase=.5))
pose("door_pound", L, True, .25, t, note="arms swing like hammering")

# hands flat on the door/glass: palms forward at head height, body leaning in
L = 3.0
t = {}
add(t, "Pelvis", hold((-4, 0, 0), L))
add(t, "Chest", wave_keys(L, (-12, 0, 0), (1.5, 0, 0)))
add(t, "Head", wave_keys(L, (-6, 0, 0), (1, 3, 0), phase=.2))
add(t, "L-Arm", hold((100, 0, -12), L))
add(t, "R-Arm", hold((100, 0, 12), L))
add(t, "L-Forearm", hold((5, 0, 0), L))
add(t, "R-Forearm", hold((5, 0, 0), L))
add(t, "L-Hand", hold((-40, 0, 0), L))
add(t, "R-Hand", hold((-40, 0, 0), L))
add(t, "L-Thigh", hold((10, 0, 0), L))
add(t, "R-Thigh", hold((10, 0, 0), L))
pose("press_glass", L, True, .5, t, hands_on_body=False, note="palms on the glass, leaning in")

# creeping walk: low, slow, knees bent, arms in front, head down
L = 1.6
KNEE = 38.0
DROP = -0.0  # solved per-hunter by the leg length scale (see pose limits); pelvis offset below keeps the feet down


def leg_phase(p, sign):
    return math.sin((p + (0 if sign > 0 else .5)) * math.tau)


LEG = 0.39      # thigh and calf length of the standard rig (metres); positions scale with each hunter's leg length


def ext(thigh_deg, calf_deg):
    """Hip height needed for a foot on the floor with the given thigh/calf rotations."""
    return LEG * (math.cos(math.radians(thigh_deg)) + math.cos(math.radians(thigh_deg + calf_deg)))


def creep_leg(p, sign):
    ph = leg_phase(p, sign)
    thigh = KNEE + 22 * ph
    calf = -(KNEE * 1.7 + 14 * max(0, -ph))
    return thigh, calf


t = {}
add_pos(t, "Pelvis", sample(L, lambda p: (0, max(ext(*creep_leg(p, 1)), ext(*creep_leg(p, -1))) - 2 * LEG, -0.03), 16))
add(t, "Pelvis", wave_keys(L, (-6, 0, 0), (0, 4, 0), n=16))
add(t, "Belly", wave_keys(L, (-12, 0, 0), (0, 3, 0), n=16))
add(t, "Chest", hold((-6, 0, 0), L))
add(t, "Head", wave_keys(L, (-18, 0, 0), (2, 8, 0), phase=.1, n=16))
for side, s_ in (("L", 1), ("R", -1)):
    add(t, f"{side}-Thigh", sample(L, lambda p, s_=s_: (creep_leg(p, s_)[0], 0, 0), 16))
    add(t, f"{side}-Calf", sample(L, lambda p, s_=s_: (creep_leg(p, s_)[1], 0, 0), 16))
    add(t, f"{side}-Foot", sample(L, lambda p, s_=s_: (-(sum(creep_leg(p, s_))), 0, 0), 16))
add(t, "L-Arm", wave_keys(L, (35, 0, -8), (-12, 0, 0), n=16))
add(t, "R-Arm", wave_keys(L, (35, 0, 8), (12, 0, 0), n=16))
add(t, "L-Forearm", hold((55, 0, 0), L))
add(t, "R-Forearm", hold((55, 0, 0), L))
pose("creep_walk", L, True, .4, t, note="low slow walk, knees bent")

# sprint lunge: a committed leap at the player, arms reaching
L = .9
t = {}
add_pos(t, "Pelvis", sample(L, lambda p: (0, -0.12 + .05 * math.sin(p * math.tau), -0.12), 8))
add(t, "Pelvis", hold((-22, 0, 0), L))
add(t, "Belly", hold((-16, 0, 0), L))
add(t, "Chest", wave_keys(L, (-14, 0, 0), (2, 0, 0)))
add(t, "Head", hold((26, 0, 0), L))
add(t, "L-Arm", wave_keys(L, (150, 0, -14), (6, 0, 0)))
add(t, "R-Arm", wave_keys(L, (150, 0, 14), (-6, 0, 0)))
add(t, "L-Forearm", hold((12, 0, 0), L))
add(t, "R-Forearm", hold((12, 0, 0), L))
add(t, "L-Hand", hold((20, 0, 0), L))
add(t, "R-Hand", hold((20, 0, 0), L))
add(t, "L-Thigh", hold((62, 0, 0), L))
add(t, "L-Calf", hold((-20, 0, 0), L))
add(t, "L-Foot", hold((-10, 0, 0), L))
add(t, "R-Thigh", hold((-40, 0, 0), L))
add(t, "R-Calf", hold((-75, 0, 0), L))
add(t, "R-Foot", hold((30, 0, 0), L))
pose("sprint_lunge", L, True, .12, t, grounded=False, layers=False, note="leaping lunge, arms reaching")

# retreat: walking backwards, arms raised slightly, head still facing front
L = 1.0
t = {}
add(t, "Chest", wave_keys(L, (4, 0, 0), (0, 3, 0), n=8))
add(t, "Head", hold((-4, 0, 0), L))
for side, s in (("L", 1), ("R", -1)):
    add(t, f"{side}-Thigh", sample(L, lambda p, s=s: (-22 * leg_phase(p, s) * -1, 0, 0), 8))
    add(t, f"{side}-Calf", sample(L, lambda p, s=s: (-16 + -16 * leg_phase(p, s) * -1 * .5 - 8, 0, 0), 8))
    add(t, f"{side}-Foot", sample(L, lambda p, s=s: (10 * leg_phase(p, s), 0, 0), 8))
add(t, "L-Arm", wave_keys(L, (30, 0, -22), (10, 0, 0), n=8))
add(t, "R-Arm", wave_keys(L, (30, 0, 22), (-10, 0, 0), n=8))
add(t, "L-Forearm", hold((40, 0, 0), L))
add(t, "R-Forearm", hold((40, 0, 0), L))
pose("retreat", L, True, .3, t, note="backing away, hands up")

# flinch: recoil from the door light, a one-shot
L = 1.1
t = {}
add_pos(t, "Pelvis", [(0, (0, 0, 0)), (.12, (0, -.03, .08)), (.5, (0, -.025, .06)), (1.1, (0, 0, 0))])
add(t, "Pelvis", [(0, (0, 0, 0)), (.12, (10, 0, 0)), (.5, (8, 0, 0)), (1.1, (0, 0, 0))])
add(t, "Chest", [(0, (0, 0, 0)), (.12, (14, 0, 0)), (.5, (10, 0, 0)), (1.1, (0, 0, 0))])
add(t, "Head", [(0, (0, 0, 0)), (.12, (-18, 14, 10)), (.5, (-12, 18, 8)), (1.1, (0, 0, 0))])
add(t, "L-Arm", [(0, (0, 0, 0)), (.12, (110, 0, -35)), (.5, (100, 0, -30)), (1.1, (0, 0, 0))])
add(t, "R-Arm", [(0, (0, 0, 0)), (.12, (110, 0, 35)), (.5, (100, 0, 30)), (1.1, (0, 0, 0))])
add(t, "L-Forearm", [(0, (0, 0, 0)), (.12, (95, 0, 0)), (.5, (85, 0, 0)), (1.1, (0, 0, 0))])
add(t, "R-Forearm", [(0, (0, 0, 0)), (.12, (95, 0, 0)), (.5, (85, 0, 0)), (1.1, (0, 0, 0))])
pose("flinch", L, False, .08, t, layers=False, ease=.5, note="hands up against the light, one-shot")

# twitch / glitch: seeded jitter bursts on the head and arms
L = 2.0
rng = random.Random(1307)
t = {}
times = [0, .15, .22, .3, .9, 1.0, 1.06, 1.12, 1.6, 1.68, 1.8, 2.0]
burst = {0: 0, .15: 1, .22: 1, .3: 0, .9: 0, 1.0: 1, 1.06: 1, 1.12: 0, 1.6: 0, 1.68: 1, 1.8: 1, 2.0: 0}


def jitter(scale):
    return [(tt, tuple(rng.uniform(-1, 1) * scale * burst[tt] for _ in range(3))) for tt in times]


add(t, "Head", jitter(24))
add(t, "Chest", jitter(6))
add(t, "L-Arm", [(tt, (e[0], e[1], min(e[2], 0) - 6)) for tt, e in jitter(18)])
add(t, "R-Arm", [(tt, (e[0], e[1], max(e[2], 0) + 6)) for tt, e in jitter(18)])
add(t, "L-Forearm", [(tt, (abs(e[0]) + 8, 0, 0)) for tt, e in jitter(20)])
add(t, "R-Forearm", [(tt, (abs(e[0]) + 8, 0, 0)) for tt, e in jitter(20)])
pose("twitch", L, True, .1, t, layers=False, note="jitter bursts, deterministic seed")

# kneel: down on one knee, head bowed
L = 3.0
t = {}
add_pos(t, "Pelvis", hold((0, -0.36, -0.04), L))
add(t, "Pelvis", hold((-4, 0, 0), L))
add(t, "Belly", wave_keys(L, (-8, 0, 0), (1.5, 0, 0)))
add(t, "Head", wave_keys(L, (-24, 0, 0), (2, 3, 0), phase=.2))
add(t, "L-Thigh", hold((88, 0, -4), L))
add(t, "L-Calf", hold((-92, 0, 0), L))
add(t, "L-Foot", hold((10, 0, 0), L))
add(t, "R-Thigh", hold((-8, 0, 2), L))
add(t, "R-Calf", hold((-98, 0, 0), L))
add(t, "R-Foot", hold((55, 0, 0), L))
add(t, "L-Arm", hold((25, 0, -4), L))
add(t, "R-Arm", hold((30, 0, 4), L))
add(t, "L-Forearm", hold((40, 0, 0), L))
add(t, "R-Forearm", hold((40, 0, 0), L))
pose("kneel", L, True, .55, t, grounded=False, note="one knee down, head bowed")

# slump: tired idle, rounded back, arms heavy, slow sway
L = 4.0
t = {}
add_pos(t, "Pelvis", hold((0, -.03, 0), L))
add(t, "Belly", wave_keys(L, (-14, 0, 0), (1.5, 0, 1.5)))
add(t, "Chest", wave_keys(L, (-12, 0, 0), (1.5, 0, 1)))
add(t, "Head", wave_keys(L, (-26, 0, 0), (2, 6, 3), phase=.3))
add(t, "L-Arm", wave_keys(L, (8, 0, -3), (2, 0, 0)))
add(t, "R-Arm", wave_keys(L, (8, 0, 3), (-2, 0, 0), phase=.15))
add(t, "L-Forearm", hold((10, 0, 0), L))
add(t, "R-Forearm", hold((10, 0, 0), L))
add(t, "L-Thigh", hold((4, 0, -3), L))
add(t, "R-Thigh", hold((4, 0, 3), L))
pose("slump", L, True, .7, t, note="tired idle")

# sit: on a hunter-scale seat (HunterSeats): pelvis down by a thigh, thighs level, calves hanging,
# hands resting on the knees, slow breathing
L = 4.0
t = {}
add_pos(t, "Pelvis", hold((0, -0.4, 0.06), L))
add(t, "Belly", wave_keys(L, (-4, 0, 0), (1.2, 0, 0)))
add(t, "Chest", wave_keys(L, (-3, 0, 0), (1, 0, 0), phase=.1))
add(t, "Head", wave_keys(L, (-6, 0, 0), (1.5, 8, 0), phase=.3))
add(t, "L-Thigh", hold((90, 0, -4), L))
add(t, "R-Thigh", hold((90, 0, 4), L))
add(t, "L-Calf", hold((-90, 0, 0), L))
add(t, "R-Calf", hold((-90, 0, 0), L))
add(t, "L-Arm", hold((32, 0, -4), L))
add(t, "R-Arm", hold((32, 0, 4), L))
add(t, "L-Forearm", hold((48, 0, 0), L))
add(t, "R-Forearm", hold((48, 0, 0), L))
pose("sit", L, True, .5, t, grounded=False, note="seated on a chair or bench")

# point at the office: right arm straight out, head turned to it
L = 2.0
t = {}
add(t, "Chest", wave_keys(L, (-3, -10, 0), (1, 0, 0)))
add(t, "Head", wave_keys(L, (-4, -18, 0), (1, 2, 0)))
add(t, "R-Arm", wave_keys(L, (88, 0, 10), (1.5, 0, 0)))
add(t, "R-Forearm", hold((2, 0, 0), L))
add(t, "R-Hand", hold((-8, 0, 0), L))
add(t, "L-Arm", hold((5, 0, -6), L))
add(t, "L-Forearm", hold((20, 0, 0), L))
pose("point_office", L, True, .3, t, note="pointing straight ahead")

# wave
L = 1.2
t = {}
add(t, "R-Arm", wave_keys(L, (0, 0, 150), (0, 0, 0)))
add(t, "R-Forearm", wave_keys(L, (35, 0, 0), (0, 0, 0)))
add(t, "R-Hand", wave_keys(L, (0, 0, 0), (0, 0, 30), n=8))
add(t, "R-Forearm", wave_keys(L, (25, 0, 0), (20, 0, 0), n=8))
add(t, "Head", wave_keys(L, (-4, 0, 6), (0, 0, 3)))
add(t, "L-Arm", hold((4, 0, -5), L))
pose("wave", L, True, .3, t, note="right hand wave")

# listen: head cocked, one hand to the ear
L = 3.0
t = {}
add(t, "Head", wave_keys(L, (-2, 12, 16), (1, 6, 2), phase=.2))
add(t, "Chest", hold((-3, 4, 4), L))
add(t, "R-Arm", hold((55, 0, 28), L))
add(t, "R-Forearm", hold((118, 0, 0), L))
add(t, "R-Hand", hold((10, 0, 0), L))
add(t, "L-Arm", hold((4, 0, -6), L))
pose("listen", L, True, .45, t, note="head cocked, hand to the ear")

# hands up (reach out): both arms forward and wide, as if begging or grabbing
L = 2.2
t = {}
add(t, "Chest", wave_keys(L, (-8, 0, 0), (1.5, 0, 0)))
add(t, "Head", hold((8, 0, 0), L))
add(t, "L-Arm", wave_keys(L, (115, 0, -22), (4, 0, -3)))
add(t, "R-Arm", wave_keys(L, (115, 0, 22), (4, 0, 3)))
add(t, "L-Forearm", hold((25, 0, 0), L))
add(t, "R-Forearm", hold((25, 0, 0), L))
add(t, "L-Hand", hold((-20, 0, 0), L))
add(t, "R-Hand", hold((-20, 0, 0), L))
pose("reach_out", L, True, .4, t, note="both arms reaching forward")

# crawl in a vent shaft: all fours, torso level, arms and knees alternate
L = 1.4
t = {}
add_pos(t, "Pelvis", sample(L, lambda p: (0, -0.38 + .02 * abs(math.sin(p * math.tau)), -.1), 8))
add(t, "Pelvis", hold((-78, 0, 0), L))
add(t, "Belly", hold((4, 0, 0), L))
add(t, "Chest", hold((6, 0, 0), L))
add(t, "Head", hold((48, 0, 0), L))
for side, s in (("L", 1), ("R", -1)):
    add(t, f"{side}-Arm", sample(L, lambda p, s=s: (74 + 24 * leg_phase(p, s), 0, 0), 8))
    add(t, f"{side}-Forearm", sample(L, lambda p, s=s: (8 + 18 * max(0, -leg_phase(p, s)), 0, 0), 8))
    add(t, f"{side}-Thigh", sample(L, lambda p, s=s: (68 - 26 * leg_phase(p, s), 0, 0), 8))
    add(t, f"{side}-Calf", sample(L, lambda p, s=s: (-100 + 18 * leg_phase(p, s), 0, 0), 8))
    add(t, f"{side}-Foot", hold((30, 0, 0), L))
pose("vent_crawl", L, True, .35, t, grounded=False, layers=False, note="all fours, hips low")

# ------------------------------------------------------------------------------------ Verrine's vent crawl
# Low belly crawl on hands and knees for Night Watch vent shafts (about 0.8 m of headroom): hips dropped to knee height,
# torso pitched far forward, head low and cocked, elbows bent, arms and knees alternating in a shuffle. "travel" lists the
# nodes whose backward travel sets the clip's reference speed (dev/look/stride_table.tscn): the clip then plays at
# real ground speed / that, so hands and knees do not slide. vent_drop / vent_rise are the one-shot transitions.
CRAWL_TRAVEL = ["L-Hand", "R-Hand", "L-Calf", "R-Calf"]
CRAWL_PELVIS = (-78.0, 0.0, 0.0)
CRAWL_Y = -0.36


def crawl_frame(p, ph):
    """One frame of the crawl at phase p (0..1); ph = +1/-1 selects which side leads."""
    a = math.sin(p * math.tau)
    b = math.sin(p * math.tau + math.pi)
    return a, b


L = 1.2
t = {}
add_pos(t, "Pelvis", sample(L, lambda p: (0.012 * math.sin(p * math.tau * 2), CRAWL_Y + 0.012 * abs(math.sin(p * math.tau)), -0.10), 16))
add(t, "Pelvis", sample(L, lambda p: (CRAWL_PELVIS[0] + 2 * math.sin(p * math.tau * 2), 4 * math.sin(p * math.tau), 3 * math.sin(p * math.tau)), 16))
add(t, "Belly", sample(L, lambda p: (4, 3 * math.sin(p * math.tau), -3 * math.sin(p * math.tau)), 16))
add(t, "Chest", sample(L, lambda p: (6 + 2 * math.sin(p * math.tau * 2), -4 * math.sin(p * math.tau), 3 * math.sin(p * math.tau)), 16))
add(t, "Head", sample(L, lambda p: (-16, 6 * math.sin(p * math.tau + 1.0), 16 + 3 * math.sin(p * math.tau)), 16))
for side, s_ in (("L", 1), ("R", -1)):
    ph = 0 if s_ > 0 else .5
    add(t, f"{side}-Arm", sample(L, lambda p, ph=ph: (56 + 24 * math.sin((p + ph) * math.tau), 0, -4), 16))
    add(t, f"{side}-Forearm", sample(L, lambda p, ph=ph: (24 + 18 * max(0, math.sin((p + ph) * math.tau)) + 10 * max(0, -math.sin((p + ph) * math.tau)), 0, 0), 16))
    add(t, f"{side}-Hand", sample(L, lambda p, ph=ph: (-14, 0, 0), 16))
    add(t, f"{side}-Thigh", sample(L, lambda p, ph=ph: (60 - 24 * math.sin((p + ph + .25) * math.tau), 0, 0), 16))
    add(t, f"{side}-Calf", sample(L, lambda p, ph=ph: (-72 + 16 * math.sin((p + ph + .25) * math.tau), 0, 0), 16))
    add(t, f"{side}-Foot", hold((20, 0, 0), L))
pose("vent_crawl_verrine", L, True, .4, t, grounded=False, layers=False, note="belly-low hands-and-knees shuffle for vent shafts")
POSES["vent_crawl_verrine"]["travel"] = CRAWL_TRAVEL

L = .8
t = {}
frame = POSES["vent_crawl_verrine"]["tracks"]


def at(bone, p):
    """Rotation of a crawl track at phase p (interpolated from the 16-step keys)."""
    keys = frame[bone]["rot"]
    i = min(int(p * 16), 15)
    k0, k1 = keys[i], keys[i + 1]
    f = p * 16 - i
    return tuple(k0[j] * (1 - f) + k1[j] * f for j in (1, 2, 3))


def lerp3(a, b, f):
    return tuple(a[i] * (1 - f) + b[i] * f for i in range(3))


def ease(f):
    return f * f * (3 - 2 * f)


# drop: knees buckle first (legs lead), then the hips sink and the torso tips forward, the hands reach the floor last
LEG_BONES = ("L-Thigh", "R-Thigh", "L-Calf", "R-Calf", "L-Foot", "R-Foot")
LAGS = {"leg": (0.0, .5, .92, 1.0), "body": (0.0, .2, .6, 1.0), "pelvis": (0.0, .3, .7, 1.0)}
TIMES = (0.0, .25, .5, .8)
for bone in frame:
    if bone == "Pelvis":
        continue
    end = at(bone, 0.0)
    kind = "leg" if bone in LEG_BONES else "body"
    add(t, bone, [(tt, lerp3((0, 0, 0), end, ease(lag))) for tt, lag in zip(TIMES, LAGS[kind])])
end_p = frame["Pelvis"]["rot"][0]
end_rot = (end_p[1], end_p[2], end_p[3])
end_pos = (frame["Pelvis"]["pos"][0][1], frame["Pelvis"]["pos"][0][2], frame["Pelvis"]["pos"][0][3])
add(t, "Pelvis", [(tt, lerp3((0, 0, 0), end_rot, ease(lag))) for tt, lag in zip(TIMES, LAGS["pelvis"])])
add_pos(t, "Pelvis", [(tt, lerp3((0, 0, 0), end_pos, ease(lag))) for tt, lag in zip(TIMES, LAGS["pelvis"])])
pose("vent_drop_verrine", L, False, .12, t, grounded=False, layers=False, note="drop from standing to the crawl (one-shot)")

t = {}
for bone, tr in POSES["vent_drop_verrine"]["tracks"].items():
    rev = [[round(L - k[0], 4)] + k[1:] for k in reversed(tr["rot"])]
    pos = [[round(L - k[0], 4)] + k[1:] for k in reversed(tr["pos"])]
    t[bone] = {"rot": rev, "pos": pos}
POSES["vent_rise_verrine"] = dict(POSES["vent_drop_verrine"], tracks=t, note="rise from the crawl to standing (one-shot)")

# lean on the wall: arms folded, one shoulder to the wall, one foot crossed (a waiting pose for rooms)
L = 4.0
t = {}
add(t, "Pelvis", hold((0, 0, -4), L))
add(t, "Belly", wave_keys(L, (-3, 0, -8), (1, 0, 1)))
add(t, "Chest", wave_keys(L, (-4, 0, -6), (1.2, 0, 0)))
add(t, "Head", wave_keys(L, (6, -16, 4), (1, 4, 1), phase=.3))
add(t, "L-Arm", hold((35, 0, 8), L))
add(t, "R-Arm", hold((35, 0, -8), L))
add(t, "L-Forearm", hold((105, -20, 0), L))
add(t, "R-Forearm", hold((105, 20, 0), L))
add(t, "R-Thigh", hold((6, 0, 6), L))
add(t, "L-Thigh", hold((0, 0, -4), L))
pose("lean_wall", L, True, .5, t, hands_on_body=True, note="arms folded, waiting")


# ----------------------------------------------------------------------------------------------- state mapping
# NW hunter states -> poses (documented in docs/NIGHT_WATCH_POSES.md and used by NightWatchPoses.pose_for_state)
STATES = {
    "idle": "door_lurk", "doorway": "door_lurk", "at_door": "door_pound", "door_grace": "door_lurk",
    "peek_left": "peek_left", "peek_right": "peek_right", "camera": "stare_camera", "monitor": "stare_camera",
    "glass": "press_glass", "vent": "vent_crawl", "approach": "creep_walk", "attack": "sprint_lunge",
    "retreat": "retreat", "light_flinch": "flinch", "glitch": "twitch", "kneel": "kneel", "tired": "slump",
    "point_office": "point_office", "greet": "wave", "listening": "listen", "reaching": "reach_out",
    "waiting": "lean_wall",
}

# per-hunter tweaks that do not need a model edit: {hunter_id: {"scale_pos": 1.1, "bone_rot": {"Head": [x, y, z]}}}
HUNTER_OFFSETS = {}

# hunter-specific poses for a state ("" = the generic one): play_state(view, "vent") picks vent_crawl_verrine for Verrine
HUNTER_STATES = {"verrine": {"vent": "vent_crawl_verrine", "vent_enter": "vent_drop_verrine", "vent_exit": "vent_rise_verrine"}}

DATA = {"version": 1, "limits": {b: {a: list(r) for a, r in v.items()} for b, v in LIMITS.items()},
        "states": STATES, "hunter_states": HUNTER_STATES, "hunter_offsets": HUNTER_OFFSETS, "poses": POSES}

if __name__ == "__main__":
    OUT.write_text(json.dumps(DATA, indent=1))
    print("wrote", OUT, len(POSES), "poses")
