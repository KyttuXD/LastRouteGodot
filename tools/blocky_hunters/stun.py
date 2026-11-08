"""Per-hunter stun / wake animation styles on the shared rig (same bones, same clip names `stun` / `stun_recover`;
every model is its own .glb, so each hunter simply carries her own version of the two clips).

A style is a dict of knobs on one base stagger (knees buckled, head lolling, arms limp):
  length (s)   harm (cycles per clip, 1 or 2; 3 for trembling)   slump (forward droop, <0 = bent back)
  roll (head/torso side roll)   yaw (twisting)   side (whole-body sideways lean)   buckle (knee collapse)
  dy (pelvis height, design m)   dyamp (bounce)   arms: limp | up | cover | flail | straight
  extras: [(name part, amp x, cycles x or None, (ox, oy, oz) constant offset deg)] for extra bones
  (wings flap, tails tuck/curl, ears droop, halos wobble ...) matched on the lower-cased bone name.
Which hunter uses which style is STYLE_OF in hunters/motion.py."""
import math

BASE = dict(length=1.6, harm=1, slump=1.0, roll=1.0, yaw=1.0, side=0.0, buckle=1.0, dy=-0.11, dyamp=0.025,
            arms="limp", extras=[])

TUCK = [("tail", 1.6, None, (28, 0, 0)), ("ear", 1.0, None, (0, 0, 0))]
STYLES = {
    "base": {},
    # heavy / tall: slow, big sideways topple, knees only half buckle
    "topple": dict(length=2.4, slump=.5, roll=1.1, yaw=.4, side=6, buckle=.65, dy=-.07, dyamp=.02,
                   extras=[("pony", 1.8, None, (0, 0, 0)), ("halo", 2.5, None, (0, 0, 0)), ("pig", 1.8, None, (0, 0, 0)),
                           ("horn", 1.0, None, (0, 0, 0))]),
    # small / hyper: quick tumbling wobble, big twist, bounces
    "tumble": dict(length=1.1, slump=.7, roll=1.2, yaw=1.3, side=4, buckle=1.0, dy=-.09, dyamp=.05, arms="flail",
                   extras=[("pony", 2.4, 2, (0, 0, 0)), ("tail", 2.5, 2, (0, 0, 0)), ("pig", 2.4, 2, (0, 0, 0)),
                           ("ear", 2.0, 2, (0, 0, 0)), ("gill", 2.5, 2, (0, 0, 0))]),
    # floaty / ghostly: lifts off the ground, arms drift up, head tipped back, slow wobble
    "float": dict(length=2.4, slump=-.65, roll=.8, yaw=.6, side=4, buckle=.15, dy=.05, dyamp=.07, arms="up",
                  extras=[("pony", 2.0, None, (0, 0, 0)), ("halo", 3.0, None, (0, 0, 0)), ("tail", 1.6, None, (0, 0, 0)),
                          ("pig", 2.0, None, (0, 0, 0)), ("cue", 2.0, None, (0, 0, 0)), ("gill", 2.0, None, (0, 0, 0))]),
    # rigid: stands straight, bent slightly back, small jerks
    "stiff": dict(length=1.4, slump=-.6, roll=.35, yaw=.4, side=0, buckle=.35, dy=-.04, dyamp=.01, arms="straight"),
    # shy: curls forward, hands up at the face, knees in
    "cover": dict(length=1.8, slump=1.0, roll=.45, yaw=.5, buckle=1.25, dy=-.13, dyamp=.015, arms="cover",
                  extras=[("tail", 1.6, None, (30, 0, 0)), ("ear", 1.0, None, (0, 0, 28)), ("pony", 1.5, None, (0, 0, 0))]),
    # all-out curl (cats / sulkers): crouched very low, tail wrapped round
    "curl": dict(length=2.0, slump=1.0, roll=.3, yaw=.4, buckle=1.45, dy=-.17, dyamp=.012, arms="cover",
                 extras=[("tail", 1.4, None, (0, 38, 0)), ("ear", 1.0, None, (0, 0, 40)), ("pony", 1.4, None, (0, 0, 0))]),
    # arms and wings flail, body flops
    "flop": dict(length=1.2, slump=.8, roll=1.1, yaw=1.0, side=4, buckle=.7, dy=-.06, dyamp=.06, arms="flail",
                 extras=[("wing", 3.2, 5, (0, 0, 0)), ("pony", 2.2, 2, (0, 0, 0))]),
    # trembling: fast small shudder, crouched a little
    "shake": dict(length=1.0, harm=3, slump=.7, roll=.6, yaw=.5, buckle=.8, dy=-.08, dyamp=.012, arms="limp",
                  extras=[("pony", 2.0, 3, (0, 0, 0)), ("tail", 2.0, 3, (0, 0, 0)), ("cue", 2.5, 3, (0, 0, 0)),
                          ("ear", 2.0, 3, (0, 0, 0))]),
}
# ears droop and tails tuck in the shy / canine / feline styles regardless of the knobs above
DROOP = {"curl": (0, 0, 32), "cover": (0, 0, 22), "stiff": (0, 0, 0), "base": (0, 0, 8)}


def style(name, over=None):
    s = dict(BASE)
    s.update(STYLES.get(name, {}))
    s.update(over or {})
    return s


def pose_fn(st):
    """(bone, phase) -> euler degrees for the looping stun pose."""
    h = st["harm"]
    side, sl, ro, ya, bu = st["side"], st["slump"], st["roll"], st["yaw"], st["buckle"]

    def pose(b, p):
        P = p * h
        s1, c1, s2, c2 = math.sin(P), math.cos(P), math.sin(2 * P), math.cos(2 * P)
        arms = st["arms"]
        if arms == "up":
            al, ar = (-8 + 10 * s1, 0, -62 - 8 * c1), (-8 - 10 * s1, 0, 62 + 8 * c1)
            fl, fr = (22 + 8 * c1, 0, 0), (22 - 8 * c1, 0, 0)
        elif arms == "cover":
            al, ar = (55 + 6 * s1, 0, -14), (55 - 6 * s1, 0, 14)
            fl, fr = (100 + 6 * c1, 0, 0), (100 - 6 * c1, 0, 0)
        elif arms == "flail":
            al, ar = (60 * s1, 0, -34 - 10 * c1), (-60 * s1, 0, 34 + 10 * c1)
            fl, fr = (30 + 25 * c1, 0, 0), (30 - 25 * c1, 0, 0)
        elif arms == "straight":
            al, ar = (6, 0, -4), (6, 0, 4)
            fl = fr = (4, 0, 0)
        else:
            al, ar = (16 + 12 * s1, 0, -9 - 6 * c1), (16 - 12 * s1, 0, 9 + 6 * c1)
            fl, fr = (14 + 8 * c1, 0, 0), (14 - 8 * c1, 0, 0)
        legs = bu
        return {
            "Pelvis": (0, 10 * ya * s1, side * .7 * s1 + 3 * ro * c1),
            "Belly": (-9 * sl + 3 * c2, 9 * ya * s1, side * .6 * s1 + 3 * ro * s1),
            "Chest": (-8 * sl + 3 * s2, 8 * ya * math.sin(P + .8), side * .5 * s1 + 4 * ro * c1),
            "Head": (-15 * sl + 6 * c1, 12 * ya * s1, (9 * s1 + 5 * c1) * ro + side * .4 * s1),
            "L-Arm": al, "R-Arm": ar, "L-Forearm": fl, "R-Forearm": fr,
            "L-Hand": (12 if arms in ("limp", "flail") else 0, 0, 0), "R-Hand": (12 if arms in ("limp", "flail") else 0, 0, 0),
            "L-Thigh": ((38 + 9 * s1) * legs, 0, -6), "R-Thigh": ((30 - 9 * s1) * legs, 0, 6),
            "L-Calf": ((-66 - 10 * s1) * legs, 0, 0), "R-Calf": ((-55 + 10 * s1) * legs, 0, 0),
            "L-Foot": ((28 + 1 * s1) * legs, 0, 0), "R-Foot": ((25 - 1 * s1) * legs, 0, 0),
        }.get(b)
    return pose


def dy_fn(st):
    h = st["harm"]
    return lambda p: st["dy"] + st["dyamp"] * math.cos(2 * p * h)


def extra_rule(st, bone_name):
    """(amp x, cycles x or None, offset) for an extra bone during stun, or None."""
    n = bone_name.lower()
    for part, amp, cyc, off in st["extras"]:
        if part in n:
            return amp, cyc, off
    return None
