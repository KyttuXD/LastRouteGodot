"""Kathy-only scythe clips, added to her normal clip set (shared clip names untouched):

  scythe_idle-loop  idle, but the right arm holds the shaft close in front of her side (forearm bent, hand keeps the
                    shaft upright)
  scythe_walk-loop  walk, right arm held to the shaft instead of swinging
  scythe_swing      one-shot sweep: wind up back-right, whip across, recover

They are complete clips (every bone keyed), so they can simply be played instead of idle/walk while the prop is in
her hand (BoneAttach: add the prop under `R-HandProp`)."""
import copy
from bb_core import quat_from_euler, quat_mul

HOLD = {"R-Arm": (24, 0, -6), "R-Forearm": (42, 0, 0), "R-Hand": (-66, 0, 6)}   # the hand cancels arm + forearm: the shaft stays upright


def _hold_tracks(clip, restq):
    for bone, e in HOLD.items():
        t = clip["tracks"][bone]["rotation"][0]
        clip["tracks"][bone]["rotation"] = (t, [quat_mul(quat_from_euler(*e), restq[bone]) for _ in t])


def hook(clips, restq, pel, U):
    for src, dst in (("idle", "scythe_idle"), ("walk", "scythe_walk")):
        c = copy.deepcopy(clips[src])
        _hold_tracks(c, restq)
        c["loop"] = True
        clips[dst] = c
    # swing: windup (0.35) -> slash (0.6) -> follow-through (0.8) -> recover (1.3)
    times = [0, .35, .6, .8, 1.3]
    pose = [
        {},
        {"R-Arm": (-55, 0, 42), "R-Forearm": (35, 0, 0), "Chest": (0, 32, 0), "Belly": (0, 12, 0), "Head": (0, 10, 0),
         "L-Arm": (10, 0, -20), "L-Thigh": (-10, 0, 0), "R-Thigh": (12, 0, 0)},
        {"R-Arm": (72, 0, -12), "R-Forearm": (30, 0, 0), "Chest": (-10, -38, 0), "Belly": (-4, -14, 0), "Head": (0, -16, 0),
         "L-Arm": (-20, 0, -25), "L-Thigh": (14, 0, 0), "R-Thigh": (-10, 0, 0), "L-Calf": (-12, 0, 0)},
        {"R-Arm": (84, 0, -20), "R-Forearm": (20, 0, 0), "Chest": (-8, -28, 0), "Belly": (-3, -10, 0), "Head": (0, -12, 0),
         "L-Arm": (-12, 0, -20), "L-Thigh": (12, 0, 0), "R-Thigh": (-8, 0, 0)},
        {},
    ]
    tracks = {}
    for bone in restq:
        if bone not in clips["idle"]["tracks"]:
            continue
        tracks[bone] = {"rotation": (times, [quat_mul(quat_from_euler(*p.get(bone, (0, 0, 0))), restq[bone]) for p in pose])}
    dy = [0, -.3, -.6, -.3, 0]
    tracks["Pelvis"]["translation"] = (times, [(pel[0], pel[1] + d * U, pel[2]) for d in dy])
    clips["scythe_swing"] = {"length": times[-1], "tracks": tracks, "loop": False}
