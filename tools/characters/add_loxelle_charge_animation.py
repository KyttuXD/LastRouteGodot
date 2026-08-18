#!/usr/bin/env python3
"""Add Loxelle's locker-impact charge loop to her reviewed BBModel."""
from __future__ import annotations

import json
import math
import sys

from refine_hunter_animations import _animation, _animators, _set_curves


def add_charge(model: dict) -> None:
    clip = "charge"
    duration = 0.7
    samples = 8
    animation = _animation(model, clip, duration, create=True)
    bones = _animators(model, animation)
    curves = {
        "Pelvis": lambda p: (-13.0 + 2.0 * math.cos(p), 0.0, 0.0),
        "Belly": lambda p: (-10.0, 0.0, 0.0),
        "Chest": lambda p: (-18.0 + 2.0 * math.sin(p), 0.0, 0.0),
        "Head": lambda p: (12.0, 0.0, 0.0),
        "L-Arm": lambda p: (-48.0, -8.0, 20.0),
        "R-Arm": lambda p: (-48.0, 8.0, -20.0),
        "L-Forearm": lambda p: (-34.0 + 5.0 * math.sin(p), 0.0, 0.0),
        "R-Forearm": lambda p: (-34.0 - 5.0 * math.sin(p), 0.0, 0.0),
        "L-Thigh": lambda p: (-26.0 * math.cos(p), 0.0, 2.0),
        "R-Thigh": lambda p: (26.0 * math.cos(p), 0.0, -2.0),
        "L-Calf": lambda p: (max(0.0, 32.0 * math.sin(p)), 0.0, 0.0),
        "R-Calf": lambda p: (max(0.0, -32.0 * math.sin(p)), 0.0, 0.0),
        "L-Foot": lambda p: (8.0 * math.sin(p), 0.0, 0.0),
        "R-Foot": lambda p: (-8.0 * math.sin(p), 0.0, 0.0),
    }
    for bone, sampler in curves.items():
        _set_curves(clip, bones, bone,
                    {"rotation": (duration, samples, sampler)})


def main() -> int:
    source, output = sys.argv[1:3]
    with open(source, encoding="utf8") as handle:
        model = json.load(handle)
    add_charge(model)
    with open(output, "w", encoding="utf8") as handle:
        json.dump(model, handle, separators=(",", ":"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
