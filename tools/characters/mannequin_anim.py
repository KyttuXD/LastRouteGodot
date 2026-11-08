"""The five clips `ModelSlot.play_if_available` asks a body for, by name.

Hand-authored rather than retargeted. The clips that used to be on this model
came from Hytale `.blockyanim` files and were bound to a Hytale skeleton --
Neck, Forearm, Calf, Eyelid -- so none of them address a bone a six-box
Minecraft figure has. Six bones only need six curves, and swinging limbs in
opposition is the whole of a walk cycle at this fidelity.

Angles are degrees about X (pitch), which is the axis every one of these
rotates about. Blockbench keyframes are deltas from the bone's rest pose, and
every bone here rests at zero, so they read as absolute.
"""

# name -> (length in seconds, {bone: [(time, pitch), ...]})
# A cycle repeats its first key at the end, so the loop has no seam.
def _swing(period, amount, lean=0.0, head=0.0):
    """One limb-opposition cycle: arms and legs cross, at `amount` degrees."""
    q = period / 4.0
    phase = [(0.0, amount), (q, 0.0), (2 * q, -amount), (3 * q, 0.0),
             (period, amount)]
    anti = [(t, -a) for t, a in phase]
    bones = {
        "RightArm": phase, "LeftLeg": phase,
        "LeftArm": anti, "RightLeg": anti,
    }
    if lean:
        bones["Body"] = [(0.0, lean), (period, lean)]
    if head:
        bones["Head"] = [(0.0, head), (period, head)]
    return period, bones


CLIPS = {
    # Not still: a figure frozen mid-scene reads as a broken import, and the
    # remote-player sync sends "idle" far more often than anything else.
    "idle": (2.4, {
        "RightArm": [(0.0, 0.0), (1.2, 3.5), (2.4, 0.0)],
        "LeftArm": [(0.0, 0.0), (1.2, -3.5), (2.4, 0.0)],
        "Head": [(0.0, 0.0), (0.8, 2.0), (1.6, -2.0), (2.4, 0.0)],
    }),
    "walk": _swing(1.0, 34.0),
    "sprint": _swing(0.66, 56.0, lean=12.0, head=-10.0),
    # Hunters play this one. Faster and further than a sprint on purpose --
    # something running you down should not read as the same gait you use.
    "chase": _swing(0.58, 62.0, lean=16.0, head=-14.0),
    "crouch": (1.6, {
        "Body": [(0.0, 26.0), (1.6, 26.0)],
        # Counter-pitched so a crouching figure still looks where it is going
        # rather than at the floor.
        "Head": [(0.0, -22.0), (1.6, -22.0)],
        "RightArm": [(0.0, 12.0), (0.8, -12.0), (1.6, 12.0)],
        "LeftArm": [(0.0, -12.0), (0.8, 12.0), (1.6, -12.0)],
        "RightLeg": [(0.0, -14.0), (0.8, 14.0), (1.6, -14.0)],
        "LeftLeg": [(0.0, 14.0), (0.8, -14.0), (1.6, 14.0)],
    }),
}


def attach(model):
    """Add every clip to a model built by mc_skin.build(). Returns the names."""
    have = {g["uuid"] for g in model["groups"]}
    model["animations"] = []
    for name, (length, bones) in CLIPS.items():
        animators = {}
        for bone, keys in bones.items():
            if bone not in have:
                continue
            animators[bone] = {
                "name": bone, "type": "bone",
                "keyframes": [{"channel": "rotation", "time": t,
                               "data_points": [{"x": pitch, "y": 0, "z": 0}]}
                              for t, pitch in keys],
            }
        model["animations"].append({"name": name, "loop": "loop",
                                    "length": length, "animators": animators})
    return [a["name"] for a in model["animations"]]
