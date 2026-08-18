#!/usr/bin/env python3
"""Replace the shared hunter locomotion clips with purpose-built loops.

The reviewed Blockbench hunters all use the same animation data.  This tool
keeps their geometry, textures, extra clips, and character-specific bones
untouched while replacing idle, walk, sprint, chase, and the shared dizzy
stun reaction. It is intended
for hunter sources; the player mannequin deliberately does not use it.

    python3 tools/characters/refine_hunter_animations.py aki.bbmodel output.bbmodel
"""
from __future__ import annotations

import argparse
import json
import math
import uuid
from collections.abc import Callable


Point = tuple[float, float, float]
Sampler = Callable[[float], Point]
LOCOMOTION_BONES = {
    "Origin", "Pelvis", "Belly", "Chest", "Head",
    "L-Arm", "R-Arm", "L-Forearm", "R-Forearm", "L-Hand", "R-Hand",
    "L-Thigh", "R-Thigh", "L-Calf", "R-Calf", "L-Foot", "R-Foot",
}


def _key(clip: str, bone: str, channel: str, time: float, point: Point) -> dict:
    identity = f"lastroute:hunter-{clip}:{bone}:{channel}:{time:.6f}"
    return {
        "channel": channel,
        "data_points": [{axis: round(value, 6)
                         for axis, value in zip(("x", "y", "z"), point)}],
        "uuid": str(uuid.uuid5(uuid.NAMESPACE_URL, identity)),
        "time": round(time, 6),
        "color": -1,
        "interpolation": "catmullrom",
    }


def _animation(model: dict, name: str, duration: float,
               create: bool = False) -> dict:
    animation = next((item for item in model.get("animations", [])
                      if str(item.get("name", "")).lower() == name), None)
    if animation is None and create:
        animation = {
            "uuid": str(uuid.uuid5(uuid.NAMESPACE_URL,
                                   f"lastroute:hunter-animation:{name}")),
            "name": name, "loop": "loop", "override": False,
            "length": duration, "snapping": 30, "selected": False,
            "saved": True, "path": "", "anim_time_update": "",
            "blend_weight": "", "start_delay": "", "loop_delay": "",
            "animators": {},
        }
        model.setdefault("animations", []).append(animation)
    if animation is None:
        raise ValueError(f"hunter is missing the {name!r} animation")
    animation["length"] = duration
    animation["loop"] = "loop"
    animation["snapping"] = 30
    return animation


def _animators(model: dict, animation: dict) -> dict[str, dict]:
    """Return locomotion animators, creating absent standard bone entries."""
    by_name = {str(animator.get("name", "")): animator
               for animator in animation.get("animators", {}).values()}
    group_ids = {str(group.get("name", "")): str(group.get("uuid", ""))
                 for group in model.get("groups", [])}
    stored = animation.setdefault("animators", {})
    for name in LOCOMOTION_BONES:
        if name in by_name:
            continue
        group_uuid = group_ids.get(name)
        if not group_uuid:
            raise ValueError(f"hunter is missing the standard {name!r} bone")
        animator = {"name": name, "type": "bone", "keyframes": []}
        stored[group_uuid] = animator
        by_name[name] = animator
    return by_name


def _curve(clip: str, animators: dict[str, dict], bone: str, channel: str,
           duration: float, samples: int, sampler: Sampler) -> list[dict]:
    if bone not in animators:
        raise ValueError(f"{clip!r} animation is missing the {bone!r} animator")
    return [_key(clip, bone, channel, duration * index / samples,
                 sampler(math.tau * index / samples))
            for index in range(samples)]


def _set_curves(clip: str, animators: dict[str, dict], bone: str,
                curves: dict[str, tuple[float, int, Sampler]]) -> None:
    keys = []
    for channel, (duration, samples, sampler) in curves.items():
        keys.extend(_curve(clip, animators, bone, channel,
                           duration, samples, sampler))
    animators[bone]["keyframes"] = sorted(
        keys, key=lambda item: (item["time"], item["channel"]))


def _idle(model: dict) -> None:
    clip = "idle"
    duration = 2.4
    samples = 12
    animation = _animation(model, clip, duration)
    bones = _animators(model, animation)

    # A relaxed contrapposto: weight lives mostly over the left leg while the
    # right knee and arms stay loose.  The periodic terms are intentionally
    # small so the character breathes instead of bobbing in place.
    rotation = {
        "Pelvis": lambda p: (-0.8 + 0.3 * math.cos(p),
                              1.0 + 0.4 * math.sin(p),
                              3.2 + 0.45 * math.sin(p)),
        "Belly": lambda p: (-1.4 - 0.5 * math.cos(p),
                             -0.5 * math.sin(p), -1.1),
        "Chest": lambda p: (2.7 + 0.75 * math.cos(p),
                             0.7 * math.sin(p), -1.4),
        "Head": lambda p: (1.2 - 0.25 * math.cos(p),
                            -0.35 * math.sin(p), 0.35),
        "L-Thigh": lambda p: (-1.0 + 0.2 * math.cos(p), -0.6, 2.1),
        "R-Thigh": lambda p: (-3.8 - 0.35 * math.cos(p), 1.2, -4.2),
        "L-Calf": lambda p: (2.0 + 0.25 * math.cos(p), 0.0, 0.0),
        "R-Calf": lambda p: (11.0 + 0.6 * math.cos(p), 0.0, 0.0),
        "L-Foot": lambda p: (-1.0, 0.0, -1.2),
        "R-Foot": lambda p: (-4.0 - 0.4 * math.cos(p), 0.0, 2.2),
        "L-Arm": lambda p: (2.5 + 0.5 * math.cos(p), -5.5, 5.2),
        "R-Arm": lambda p: (1.5 + 0.45 * math.cos(p), 4.5, -3.8),
        "L-Forearm": lambda p: (-9.0 - 0.8 * math.cos(p), 0.0, 0.0),
        "R-Forearm": lambda p: (-13.0 - 0.9 * math.cos(p), 0.0, 0.0),
        "L-Hand": lambda p: (-4.0 - 0.5 * math.cos(p), -3.5, -2.5),
        "R-Hand": lambda p: (-6.0 - 0.5 * math.cos(p), 3.0, 3.5),
        "Origin": lambda p: (0.0, 0.0, 0.2 * math.sin(p)),
    }
    for bone, sampler in rotation.items():
        if bone == "Origin" and bone not in bones:
            continue
        _set_curves(clip, bones, bone,
                    {"rotation": (duration, samples, sampler)})
    _set_curves(clip, bones, "Pelvis", {
        "rotation": (duration, samples, rotation["Pelvis"]),
        "position": (duration, samples,
                     lambda p: (0.65 + 0.12 * math.sin(p),
                                -0.45 + 0.12 * math.cos(p), 0.0)),
    })


def _walk(model: dict, clip: str = "walk", duration: float = 1.0) -> None:
    """Author the same gait at any gameplay clip duration."""
    samples = 8
    animation = _animation(model, clip, duration)
    bones = _animators(model, animation)

    def knee(phase: float, airborne_center: float) -> float:
        amount = math.cos(phase - airborne_center)
        return max(0.0, 42.0 * amount)

    rotation = {
        "L-Thigh": lambda p: (-27.0 * math.cos(p), -1.8 * math.cos(p),
                               2.3 + 0.8 * math.sin(p)),
        "R-Thigh": lambda p: (27.0 * math.cos(p), 1.8 * math.cos(p),
                               -2.3 - 0.8 * math.sin(p)),
        "L-Calf": lambda p: (knee(p, 7.0 * math.pi / 4.0), 0.0, 0.0),
        "R-Calf": lambda p: (knee(p, 3.0 * math.pi / 4.0), 0.0, 0.0),
        "L-Arm": lambda p: (12.0 * math.sin(p), -8.0 + 1.5 * math.cos(p),
                             6.0 + 1.2 * math.sin(p)),
        "R-Arm": lambda p: (-12.0 * math.sin(p), 8.0 - 1.5 * math.cos(p),
                             -6.0 - 1.2 * math.sin(p)),
        "L-Forearm": lambda p: (-14.0 - 4.0 * math.cos(p), 0.0, 0.0),
        "R-Forearm": lambda p: (-14.0 + 4.0 * math.cos(p), 0.0, 0.0),
        "L-Hand": lambda p: (-3.0 * math.sin(p), 0.0, 2.0 * math.cos(p)),
        "R-Hand": lambda p: (3.0 * math.sin(p), 0.0, -2.0 * math.cos(p)),
        "Belly": lambda p: (0.5 * math.cos(2.0 * p), 1.5 * math.cos(p),
                             2.0 * math.sin(p)),
        "Chest": lambda p: (-1.0, -2.5 * math.cos(p), -2.0 * math.sin(p)),
        "Head": lambda p: (0.5, math.cos(p), 0.7 * math.sin(p)),
        "Origin": lambda p: (0.0, 0.0, 0.35 * math.sin(p)),
    }
    for bone, sampler in rotation.items():
        if bone == "Origin" and bone not in bones:
            continue
        _set_curves(clip, bones, bone,
                    {"rotation": (duration, samples, sampler)})
    left_foot = (20.0, 2.0, -8.0, 4.0, 8.0, 2.0, -10.0, 6.0)
    right_foot = left_foot[4:] + left_foot[:4]
    for bone, values in (("L-Foot", left_foot), ("R-Foot", right_foot)):
        _set_curves(clip, bones, bone, {
            "rotation": (duration, samples,
                         lambda p, points=values: (points[round(p / math.tau * samples) % samples],
                                                   0.0, 0.0)),
        })
    _set_curves(clip, bones, "Pelvis", {
        "rotation": (duration, samples,
                     lambda p: (-1.0 + math.cos(2.0 * p), 3.0 * math.cos(p),
                                4.5 * math.sin(p))),
        "position": (duration, samples,
                     lambda p: (1.15 * math.sin(p),
                                -0.75 + 0.75 * math.cos(2.0 * p), 0.0)),
    })


def _stun(model: dict) -> None:
    """Loose head-roll/body-sway loop for a failed hunter attack.

    The reference reads as dizziness through a circular head path and delayed
    torso counter-sway. Keeping the planted legs nearly neutral prevents the
    reaction from turning into another locomotion clip or sinking through the
    floor on hunters with different skirts, wings, and shoes.
    """
    clip = "stun"
    duration = 1.2
    samples = 12
    animation = _animation(model, clip, duration, create=True)
    bones = _animators(model, animation)
    rotation = {
        "Pelvis": lambda p: (-1.5, 2.5 * math.cos(p), 4.5 * math.sin(p)),
        "Belly": lambda p: (2.0 * math.sin(p), -4.0 * math.cos(p),
                              -5.5 * math.sin(p)),
        "Chest": lambda p: (-4.5 * math.sin(p), 7.0 * math.cos(p),
                              7.5 * math.sin(p)),
        "Head": lambda p: (13.0 * math.sin(p), 19.0 * math.cos(p),
                             12.0 * math.sin(p - math.pi * .35)),
        "L-Arm": lambda p: (-5.0 + 3.0 * math.sin(p), -7.0,
                              8.0 + 3.0 * math.cos(p)),
        "R-Arm": lambda p: (-5.0 - 3.0 * math.sin(p), 7.0,
                              -8.0 - 3.0 * math.cos(p)),
        "L-Forearm": lambda p: (-12.0 + 2.0 * math.cos(p), 0.0, 0.0),
        "R-Forearm": lambda p: (-12.0 - 2.0 * math.cos(p), 0.0, 0.0),
        "L-Hand": lambda p: (2.0 * math.sin(p), -2.0, 2.0),
        "R-Hand": lambda p: (-2.0 * math.sin(p), 2.0, -2.0),
        "L-Thigh": lambda p: (-2.0, 0.0, 1.5),
        "R-Thigh": lambda p: (-2.0, 0.0, -1.5),
        "L-Calf": lambda p: (4.0, 0.0, 0.0),
        "R-Calf": lambda p: (4.0, 0.0, 0.0),
        "L-Foot": lambda p: (-1.0, 0.0, 0.0),
        "R-Foot": lambda p: (-1.0, 0.0, 0.0),
    }
    for bone, sampler in rotation.items():
        _set_curves(clip, bones, bone,
                    {"rotation": (duration, samples, sampler)})


def _flight(model: dict) -> None:
    """Xivvy-only wing flap with tucked legs and a forward chase posture."""
    group_ids = {str(group.get("name", "")): str(group.get("uuid", ""))
                 for group in model.get("groups", [])}
    wing_names = ("L-Wing-Bone", "R-Wing-Bone")
    if not all(group_ids.get(name) for name in wing_names):
        return
    clip = "flight"
    duration = 0.8
    samples = 8
    animation = _animation(model, clip, duration, create=True)
    bones = _animators(model, animation)
    stored = animation.setdefault("animators", {})
    for name in wing_names:
        if name not in bones:
            animator = {"name": name, "type": "bone", "keyframes": []}
            stored[group_ids[name]] = animator
            bones[name] = animator
    curves = {
        "L-Wing-Bone": lambda p: (5.0 * math.sin(p),
                                    -14.0 - 24.0 * math.sin(p),
                                    12.0 + 8.0 * math.cos(p)),
        "R-Wing-Bone": lambda p: (-5.0 * math.sin(p),
                                    14.0 + 24.0 * math.sin(p),
                                    -12.0 - 8.0 * math.cos(p)),
        "Chest": lambda p: (-10.0 + 2.0 * math.cos(p), 0.0, 0.0),
        "Head": lambda p: (7.0 - 1.5 * math.cos(p), 0.0, 0.0),
        "L-Arm": lambda p: (-18.0, -12.0, 16.0),
        "R-Arm": lambda p: (-18.0, 12.0, -16.0),
        "L-Forearm": lambda p: (-22.0, 0.0, 0.0),
        "R-Forearm": lambda p: (-22.0, 0.0, 0.0),
        "L-Thigh": lambda p: (23.0 + 2.0 * math.sin(p), 0.0, 3.0),
        "R-Thigh": lambda p: (23.0 - 2.0 * math.sin(p), 0.0, -3.0),
        "L-Calf": lambda p: (-38.0, 0.0, 0.0),
        "R-Calf": lambda p: (-38.0, 0.0, 0.0),
        "L-Foot": lambda p: (18.0, 0.0, 0.0),
        "R-Foot": lambda p: (18.0, 0.0, 0.0),
    }
    for bone, sampler in curves.items():
        _set_curves(clip, bones, bone,
                    {"rotation": (duration, samples, sampler)})


def refine_hunter_animations(model: dict) -> dict:
    """Mutate and return one hunter bbmodel dictionary."""
    _idle(model)
    _walk(model, "walk", 1.0)
    _walk(model, "sprint", 2.0 / 3.0)
    _walk(model, "chase", 0.5)
    _stun(model)
    _flight(model)
    return model


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("output")
    args = parser.parse_args()
    with open(args.source, encoding="utf8") as source:
        model = json.load(source)
    refine_hunter_animations(model)
    with open(args.output, "w", encoding="utf8") as destination:
        json.dump(model, destination, separators=(",", ":"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
