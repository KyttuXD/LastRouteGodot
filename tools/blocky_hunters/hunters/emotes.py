"""Per-hunter emotes: short one-shot body clips (`emote_<name>`, same rig, no loop) each paired with a face.

Every hunter gets the SHARED set plus a few personal ones that fit her persona (LORE-CANON section 5; Kathy, Aki,
Loxelle and Nyxie are confirmed, the rest soft canon). A pose is {bone: euler degrees} on top of the rest pose;
`dy` is a pelvis bob in skin px. Conventions: arm X + swings forward, arm Z +/- raises the R / L arm sideways,
forearm X + bends the elbow forward, head X - looks down, Belly/Chest X - bows forward."""
import json, math, pathlib

BONES = {"LArm": "L-Arm", "RArm": "R-Arm", "LFore": "L-Forearm", "RFore": "R-Forearm", "LHand": "L-Hand",
         "RHand": "R-Hand", "LThigh": "L-Thigh", "RThigh": "R-Thigh", "LCalf": "L-Calf", "RCalf": "R-Calf",
         "LFoot": "L-Foot", "RFoot": "R-Foot", "Belly": "Belly", "Chest": "Chest", "Head": "Head", "Pelvis": "Pelvis"}


def K(t, dy=0.0, **pose):
    return (t, dy, {BONES[k]: v for k, v in pose.items()})


def _rest(t):
    return K(t)


def _osc(t0, step, n, a, b, **fixed):
    """n keys from t0 alternating pose a / pose b (dicts of one bone each) on top of fixed bones."""
    out = []
    for i in range(n):
        out.append(K(t0 + i * step, **{**fixed, **(a if i % 2 == 0 else b)}))
    return out


TEMPLATES = {
    # ---------------- shared
    "wave": ("Wave", "happy", [_rest(0), K(.35, RArm=(0, 0, 150), Head=(0, 0, -6))]
             + _osc(.6, .25, 7, dict(RFore=(0, 0, 22)), dict(RFore=(0, 0, -22)), RArm=(0, 0, 150), Head=(0, 0, -6))
             + [_rest(2.5)]),
    "cheer": ("Cheer", "happy", [_rest(0), K(.25, LArm=(0, 0, -160), RArm=(0, 0, 160)),
                                  K(.5, -.9, LArm=(0, 0, -150), RArm=(0, 0, 150), LThigh=(14, 0, 0), RThigh=(14, 0, 0), LCalf=(-26, 0, 0), RCalf=(-26, 0, 0)),
                                  K(.75, .9, LArm=(0, 0, -165), RArm=(0, 0, 165)),
                                  K(1.0, -.9, LArm=(0, 0, -150), RArm=(0, 0, 150), LThigh=(14, 0, 0), RThigh=(14, 0, 0), LCalf=(-26, 0, 0), RCalf=(-26, 0, 0)),
                                  K(1.25, .9, LArm=(0, 0, -165), RArm=(0, 0, 165)), _rest(2.0)]),
    "bow": ("Bow", "blink", [_rest(0), K(.6, Belly=(-17, 0, 0), Chest=(-20, 0, 0), Head=(10, 0, 0), LArm=(14, 0, 0), RArm=(14, 0, 0)),
                             K(1.5, Belly=(-17, 0, 0), Chest=(-20, 0, 0), Head=(10, 0, 0), LArm=(14, 0, 0), RArm=(14, 0, 0)), _rest(2.2)]),
    "shrug": ("Shrug", "neutral", [_rest(0), K(.3, LArm=(0, 0, -22), RArm=(0, 0, 22), LFore=(50, 0, 0), RFore=(50, 0, 0), Head=(0, 0, 9)),
                                   K(1.3, LArm=(0, 0, -22), RArm=(0, 0, 22), LFore=(50, 0, 0), RFore=(50, 0, 0), Head=(0, 0, 9)), _rest(1.8)]),
    # ---------------- personal
    "hug": ("Hug", "happy", [_rest(0), K(.5, LArm=(62, 0, 20), RArm=(62, 0, -20), LFore=(62, 0, 36), RFore=(62, 0, -36), Chest=(-6, 0, 0), Head=(0, 0, 6)),
                             K(2.0, LArm=(62, 0, 20), RArm=(62, 0, -20), LFore=(62, 0, 36), RFore=(62, 0, -36), Chest=(-6, 0, 0), Head=(0, 0, 6)), _rest(2.6)]),
    "pat": ("Head pat", "happy", [_rest(0), K(.4, RArm=(98, 0, 0), RFore=(40, 0, 0), Chest=(-6, 0, 0))]
            + _osc(.7, .25, 6, dict(RFore=(66, 0, 0)), dict(RFore=(40, 0, 0)), RArm=(98, 0, 0), Chest=(-6, 0, 0)) + [_rest(2.4)]),
    "read": ("Read", "neutral", [_rest(0), K(.6, LArm=(56, 0, 10), RArm=(56, 0, -10), LFore=(88, 0, 0), RFore=(88, 0, 0), Head=(-15, 0, 0), Belly=(-6, 0, 0)),
                                 K(1.8, LArm=(56, 0, 10), RArm=(56, 0, -10), LFore=(88, 0, 0), RFore=(88, 0, 0), Head=(-15, 0, 0), Belly=(-6, 0, 0)),
                                 K(2.1, LArm=(56, 0, 10), RArm=(56, 0, -10), LFore=(88, 0, 0), RFore=(96, 0, 0), RHand=(0, 0, -35), Head=(-15, 0, 0), Belly=(-6, 0, 0)),
                                 K(2.4, LArm=(56, 0, 10), RArm=(56, 0, -10), LFore=(88, 0, 0), RFore=(88, 0, 0), Head=(-15, 0, 0), Belly=(-6, 0, 0)), _rest(3.2)]),
    "shy": ("Shy fidget", "blink", [_rest(0), K(.5, LArm=(32, 0, 12), RArm=(32, 0, -12), LFore=(66, 0, 28), RFore=(66, 0, -28), Head=(-10, 0, 7), Belly=(-5, 0, 0))]
            + _osc(1.0, .6, 3, dict(Head=(-10, 0, -5), Chest=(0, 0, -3)), dict(Head=(-10, 0, 7), Chest=(0, 0, 3)),
                   LArm=(32, 0, 12), RArm=(32, 0, -12), LFore=(66, 0, 28), RFore=(66, 0, -28), Belly=(-5, 0, 0)) + [_rest(3.0)]),
    "peek": ("Peek", "blink", [_rest(0), K(.5, Chest=(0, 0, 10), Belly=(0, 0, 6), Head=(-4, 0, -12), LThigh=(12, 0, 0)),
                               K(1.5, Chest=(0, 0, 10), Belly=(0, 0, 6), Head=(-4, 0, -12), LThigh=(12, 0, 0)), _rest(2.2)]),
    "spin": ("Spin", "happy", [_rest(0), K(.2, LArm=(0, 0, -45), RArm=(0, 0, 45), Pelvis=(0, 90, 0)), K(.5, .5, LArm=(0, 0, -45), RArm=(0, 0, 45), Pelvis=(0, 180, 0)),
                               K(.8, LArm=(0, 0, -45), RArm=(0, 0, 45), Pelvis=(0, 270, 0)), K(1.1, .5, LArm=(0, 0, -45), RArm=(0, 0, 45), Pelvis=(0, 360, 0)),
                               K(1.4, LArm=(0, 0, -20), RArm=(0, 0, 20)), _rest(1.7)]),
    "dance_a": ("Dance", "happy", [_rest(0)] + [K(.3 * (i + 1), -.5 if i % 2 else .3,
                                              Pelvis=(0, 18 if i % 2 else -18, 0), Head=(0, 0, 8 if i % 2 else -8),
                                              LArm=(0, 0, -110 if i % 2 else -30), RArm=(0, 0, 30 if i % 2 else 110),
                                              LThigh=(8 if i % 2 else 0, 0, 0), RThigh=(0 if i % 2 else 8, 0, 0)) for i in range(7)] + [_rest(2.6)]),
    "sway": ("Sway", "happy", [_rest(0)] + [K(.5 * (i + 1), 0, Chest=(0, 0, 8 if i % 2 else -8), Belly=(0, 0, -4 if i % 2 else 4),
                                           Pelvis=(0, 9 if i % 2 else -9, 0), Head=(0, 0, 5 if i % 2 else -5),
                                           LArm=(0, 0, -26 if i % 2 else -10), RArm=(0, 0, 10 if i % 2 else 26)) for i in range(6)] + [_rest(3.4)]),
    "panic": ("Panic", "scream", [_rest(0)] + [K(.1 + .12 * i, -.4 if i % 2 else 0, LArm=(150, 0, -20 + 12 * (i % 2)), RArm=(150, 0, 20 - 12 * (i % 2)),
                                              LFore=(20, 0, 0), RFore=(20, 0, 0), Head=(0, 0, 12 if i % 2 else -12),
                                              LThigh=(10, 0, 0), RThigh=(10, 0, 0), LCalf=(-20, 0, 0), RCalf=(-20, 0, 0)) for i in range(10)] + [_rest(1.7)]),
    "tantrum": ("Tantrum", "chase", [_rest(0)] + [K(.2 * (i + 1), -.3, LFore=(40, 0, 0), RFore=(40, 0, 0), Chest=(-8, 0, 0), Head=(0, 0, -8),
                                                  LThigh=(46 if i % 2 == 0 else 0, 0, 0), RThigh=(46 if i % 2 else 0, 0, 0),
                                                  LCalf=(-30 if i % 2 == 0 else 0, 0, 0), RCalf=(-30 if i % 2 else 0, 0, 0)) for i in range(7)] + [_rest(1.9)]),
    "facepalm": ("Facepalm", "blank", [_rest(0), K(.6, RArm=(125, 0, 0), RFore=(100, 0, 0), Head=(-12, 0, 0), Belly=(-6, 0, 0)),
                                       K(1.7, RArm=(125, 0, 0), RFore=(100, 0, 0), Head=(-12, 0, 0), Belly=(-6, 0, 0)), _rest(2.3)]),
    "salute": ("Salute", "neutral", [_rest(0), K(.4, RArm=(10, 0, 95), RFore=(0, 0, 115), Head=(4, 0, 0)),
                                     K(1.6, RArm=(10, 0, 95), RFore=(0, 0, 115), Head=(4, 0, 0)), _rest(2.1)]),
    "point_old": ("Point", "neutral", [_rest(0), K(.4, RArm=(85, 0, 0), Chest=(-5, 0, 0)), K(.8, RArm=(95, 0, 0), Chest=(-5, 0, 0)),
                                   K(1.1, RArm=(85, 0, 0), Chest=(-5, 0, 0)), K(1.4, RArm=(95, 0, 0), Chest=(-5, 0, 0)), _rest(2.1)]),
    "chin": ("Think", "neutral", [_rest(0), K(.5, RArm=(70, 0, 0), RFore=(122, 0, 0), Head=(-3, 0, 6))]
            + _osc(1.0, .25, 5, dict(RFore=(130, 0, 0)), dict(RFore=(120, 0, 0)), RArm=(70, 0, 0), Head=(-3, 0, 6)) + [_rest(2.6)]),
    "stretch_a": ("Stretch", "blink", [_rest(0), K(.8, LArm=(0, 0, -170), RArm=(0, 0, 170), Chest=(10, 0, 0), Belly=(6, 0, 0), Head=(8, 0, 0)),
                                     K(1.8, LArm=(0, 0, -170), RArm=(0, 0, 170), Chest=(10, 0, 0), Belly=(6, 0, 0), Head=(8, 0, 0)), _rest(2.6)]),
    "flex": ("Flex", "happy", [_rest(0), K(.4, LArm=(0, 0, -90), LFore=(0, 0, -105), RArm=(0, 0, 90), RFore=(0, 0, 105), Chest=(6, 0, 0)),
                               K(.8, .5, LArm=(0, 0, -90), LFore=(0, 0, -105), RArm=(0, 0, 90), RFore=(0, 0, 105), Chest=(6, 0, 0)),
                               K(1.2, 0, LArm=(0, 0, -90), LFore=(0, 0, -105), RArm=(0, 0, 90), RFore=(0, 0, 105), Chest=(6, 0, 0)), _rest(2.0)]),
    "akimbo": ("Hands on hips", "chase", [_rest(0), K(.4, LArm=(0, 0, -28), RArm=(0, 0, 28), LFore=(0, 0, 120), RFore=(0, 0, -120), Head=(4, 0, 0), Chest=(3, 0, 0)),
                                          K(1.6, LArm=(0, 0, -28), RArm=(0, 0, 28), LFore=(0, 0, 120), RFore=(0, 0, -120), Head=(4, 0, 0), Chest=(3, 0, 0)), _rest(2.1)]),
    "laugh_a": ("Laugh", "happy", [_rest(0), K(.3, Belly=(-12, 0, 0), Chest=(-14, 0, 0), LArm=(45, 0, 10), RArm=(45, 0, -10), LFore=(90, 0, 0), RFore=(90, 0, 0))]
              + [K(.5 + .12 * i, -.3 if i % 2 else 0, Belly=(-12, 0, 0), Chest=(-14, 0, 3 if i % 2 else -3), LArm=(45, 0, 10), RArm=(45, 0, -10),
                   LFore=(90, 0, 0), RFore=(90, 0, 0)) for i in range(10)] + [_rest(2.2)]),
    "sulk": ("Sulk", "blank", [_rest(0), K(.6, LArm=(40, 0, 35), RArm=(40, 0, -35), LFore=(100, 0, 50), RFore=(100, 0, -50), Head=(-10, 0, -7), Belly=(-6, 0, 0)),
                               K(2.0, LArm=(40, 0, 35), RArm=(40, 0, -35), LFore=(100, 0, 50), RFore=(100, 0, -50), Head=(-10, 0, -7), Belly=(-6, 0, 0)), _rest(2.6)]),
    "hold": ("Hold out", "neutral", [_rest(0), K(.6, LArm=(50, 0, 15), RArm=(50, 0, -15), LFore=(80, 0, 25), RFore=(80, 0, -25), Head=(-8, 0, 0)),
                                     K(2.0, LArm=(50, 0, 15), RArm=(50, 0, -15), LFore=(80, 0, 25), RFore=(80, 0, -25), Head=(-8, 0, 0)), _rest(2.6)]),
    "tease": ("Tease", "wink_left", [_rest(0), K(.4, RArm=(82, 0, 0), RFore=(20, 0, 0), Head=(0, 0, 8), Pelvis=(0, 0, 6)),
                                     K(1.6, RArm=(82, 0, 0), RFore=(20, 0, 0), Head=(0, 0, 8), Pelvis=(0, 0, 6)), _rest(2.2)]),
    "fetch": ("Fetch!", "happy", [_rest(0), K(.3, RArm=(82, 0, 0))] + [K(.5 + .3 * i, -.5 if i % 2 else .4, RArm=(82, 0, 0)) for i in range(4)] + [_rest(2.2)]),
}

def _hold(t0, t1, **pose):
    return [K(t0, **pose), K(t1, **pose)]


# ---------------- Void: no waving or cheering; unsettling, still, predatory. Shared set + one per colour.
TEMPLATES.update({
    "stare": ("Stare", "neutral", [_rest(0), K(.8, Head=(-7, 0, 0), Chest=(-3, 0, 0))] + _hold(2.4, 2.4, Head=(-7, 0, 0), Chest=(-3, 0, 0)) + [_rest(3.2)]),
    "tilt": ("Head tilt", "neutral", [_rest(0), K(1.0, Head=(2, 0, 24)), K(2.6, Head=(2, 0, 24)), _rest(3.4)]),
    "twitch": ("Twitch", "neutral", [_rest(0)] + [K(.12 * (i + 1), 0, Head=(0, 0, 16 if i % 2 else -12), LArm=(0, 0, -8 * (i % 2)), RArm=(0, 0, 8 * (i % 2)),
                                           Chest=(0, 0, 3 if i % 2 else -3)) for i in range(8)] + [_rest(1.6)]),
    "loom": ("Loom", "neutral", [_rest(0), K(.7, Chest=(-12, 0, 0), Belly=(-8, 0, 0), Head=(14, 0, 0), LArm=(0, 0, -38), RArm=(0, 0, 38)),
                              K(2.0, Chest=(-12, 0, 0), Belly=(-8, 0, 0), Head=(14, 0, 0), LArm=(0, 0, -38), RArm=(0, 0, 38)), _rest(2.8)]),
    "devour": ("Devour", "neutral", [_rest(0), K(.4, LArm=(0, 0, -60), RArm=(0, 0, 60), Chest=(6, 0, 0)),
                                    K(.9, LArm=(80, 0, 22), RArm=(80, 0, -22), LFore=(40, 0, 0), RFore=(40, 0, 0), Chest=(-14, 0, 0), Head=(8, 0, 0)),
                                    K(1.8, LArm=(80, 0, 22), RArm=(80, 0, -22), LFore=(40, 0, 0), RFore=(40, 0, 0), Chest=(-14, 0, 0), Head=(8, 0, 0)), _rest(2.5)]),
    "shiver": ("Shiver", "neutral", [_rest(0)] + [K(.09 * (i + 1), -.1 * (i % 2), Chest=(0, 0, 3 if i % 2 else -3), LArm=(18, 0, 8), RArm=(18, 0, -8),
                                                LFore=(60, 0, 0), RFore=(60, 0, 0), Head=(-6, 0, 3 if i % 2 else -3)) for i in range(14)] + [_rest(2.0)]),
    "smash": ("Smash", "neutral", [_rest(0), K(.5, LArm=(165, 0, 0), RArm=(165, 0, 0), Chest=(8, 0, 0)),
                                 K(.62, -.8, LArm=(35, 0, 0), RArm=(35, 0, 0), Chest=(-20, 0, 0), Belly=(-12, 0, 0), Head=(-6, 0, 0)),
                                 K(1.8, -.8, LArm=(35, 0, 0), RArm=(35, 0, 0), Chest=(-20, 0, 0), Belly=(-12, 0, 0), Head=(-6, 0, 0)), _rest(2.6)]),
    "zap": ("Zap", "neutral", [_rest(0), K(.25, LArm=(0, 0, -75), RArm=(0, 0, 75))] + [K(.25 + .08 * (i + 1), 0, LArm=(0, 0, -75 + 14 * (i % 2)), RArm=(0, 0, 75 - 14 * (i % 2)),
                                           Head=(0, 0, 10 if i % 2 else -10), Chest=(0, 0, 4 if i % 2 else -4)) for i in range(12)] + [_rest(1.9)]),
    "freeze": ("Freeze", "neutral", [_rest(0), K(.12, LArm=(0, 0, -4), RArm=(0, 0, 4), Head=(2, 0, 0)), K(2.6, LArm=(0, 0, -4), RArm=(0, 0, 4), Head=(2, 0, 0)), _rest(2.8)]),
    "exhale": ("Exhale", "neutral", [_rest(0), K(.7, Chest=(10, 0, 0), Belly=(6, 0, 0), Head=(16, 0, 0), LArm=(0, 0, -14), RArm=(0, 0, 14)),
                                   K(1.6, Chest=(10, 0, 0), Belly=(6, 0, 0), Head=(16, 0, 0), LArm=(0, 0, -14), RArm=(0, 0, 14)),
                                   K(2.3, Chest=(-8, 0, 0), Head=(-8, 0, 0)), _rest(3.0)]),
    "rev": ("Rev up", "neutral", [_rest(0), K(.4, -1.2, Chest=(-20, 0, 0), Belly=(-10, 0, 0), LArm=(-40, 0, -6), RArm=(-40, 0, 6),
                                          LThigh=(34, 0, 0), RThigh=(-8, 0, 0), LCalf=(-52, 0, 0), RCalf=(-20, 0, 0), Head=(14, 0, 0))]
            + _osc(.7, .16, 7, dict(RThigh=(-14, 0, 0)), dict(RThigh=(-4, 0, 0)), Chest=(-20, 0, 0), Belly=(-10, 0, 0), LArm=(-40, 0, -6), RArm=(-40, 0, 6),
                   LThigh=(34, 0, 0), LCalf=(-52, 0, 0), RCalf=(-20, 0, 0), Head=(14, 0, 0)) + [_rest(2.4)]),
    "flicker": ("Flicker", "neutral", [_rest(0)] + [K(.14 * (i + 1), -.5 if i % 2 else 0, Pelvis=(0, (-1) ** i * (20 + 10 * (i % 3)), 0),
                                                 Head=(0, 0, 8 if i % 2 else -8)) for i in range(10)] + [_rest(1.9)]),
    "rage": ("Rage", "neutral", [_rest(0), K(.3, LArm=(30, 0, -10), RArm=(30, 0, 10), LFore=(95, 0, 0), RFore=(95, 0, 0), Chest=(-14, 0, 0), Head=(4, 0, 0))]
            + _osc(.5, .08, 14, dict(Chest=(-16, 0, 4)), dict(Chest=(-12, 0, -4)), LArm=(30, 0, -10), RArm=(30, 0, 10), LFore=(95, 0, 0), RFore=(95, 0, 0), Head=(4, 0, 0)) + [_rest(2.3)]),
    "listen": ("Listen", "neutral", [_rest(0), K(.8, Head=(8, 0, 18), Chest=(0, 0, 3)), K(1.8, Head=(8, 0, -18), Chest=(0, 0, -3)),
                                   K(2.8, Head=(10, 0, 14), Chest=(0, 0, 2)), _rest(3.6)]),
    "flick": ("Flick", "neutral", [_rest(0), K(.3, RArm=(60, 0, -4), RFore=(110, 0, 0)), K(.45, RArm=(88, 0, -4), RFore=(10, 0, 0), Head=(0, 0, 6)),
                                   K(1.4, RArm=(88, 0, -4), RFore=(10, 0, 0), Head=(0, 0, 6)), _rest(2.0)]),
})
VOID_SHARED = ["stare", "tilt", "twitch", "loom"]
PERSONAL_VOID = {"black": "devour", "blue": "shiver", "brown": "smash", "cyan": "zap", "gray": "freeze", "green": "exhale",
                 "orange": "rev", "pink": "beckon", "purple": "flicker", "red": "rage", "white": "listen", "yellow": "flick"}

SHARED = ["wave", "cheer", "bow", "shrug"]
PERSONAL = {
    "aki": ["shy", "read", "peek"], "briselle": ["hold", "chin"], "ceryth": ["chin", "salute"],
    "dovelle": ["akimbo"], "eirys": ["flex", "spin"], "ferryn": ["panic", "shy", "peek"],
    "glyra": ["sway", "tantrum"], "haelith": ["fetch"], "ilyra": ["chin", "sulk"],
    "jyvra": ["akimbo", "tantrum"], "kathy": ["hug", "pat"], "loxelle": ["sway", "hold"],
    "mavrine": ["salute", "chin"], "nyxie": ["tease", "sway", "spin"], "opalie": ["spin"],
    "porcelle": ["shy", "hold", "peek"], "quirith": ["sulk", "hug", "shy"], "ravelle": ["tease"],
    "solyth": ["flex", "tantrum"], "thessine": ["facepalm", "chin"], "umbriel": ["peek", "shy", "sulk"],
    "verrine": ["sulk", "facepalm", "peek"], "wynelle": ["sway", "hold", "spin"], "xivvy": ["spin"],
    "ysolde": ["hold", "hug", "pat"], "zephyra": ["spin", "hold"],
}


def names_for(hunter):
    base = hunter.replace("_tall", "")
    if base.startswith("void_"):
        own = PERSONAL_VOID[base[5:]]
        return VOID_SHARED + ([] if own == "beckon" else [own])      # void_pink's beckon is built moving (compile_moving)
    out = list(SHARED)
    out += [n for n in PERSONAL.get(base, []) if n not in out]
    return out


def compile_emotes(hunter, restq, pel, U, k, core_bones):
    """Return {clip_name: clip} for the hunter, plus the metadata list for emotes.json."""
    from bb_core import quat_from_euler, quat_mul
    clips, meta = {}, []
    for key in names_for(hunter):
        label, face, keys = TEMPLATES[key]
        times = [t for t, _, _ in keys]
        tracks = {}
        for bone in core_bones:
            vals = []
            for t, dy, pose in keys:
                e = pose.get(bone, (0, 0, 0))
                vals.append(quat_mul(quat_from_euler(*e), restq[bone]))
            tracks[bone] = {"rotation": (times, vals)}
        tracks["Pelvis"]["translation"] = (times, [(pel[0], pel[1] + dy * U * k, pel[2]) for _, dy, _ in keys])
        clips["emote_" + key] = {"length": times[-1], "tracks": tracks, "loop": False}
        meta.append({"clip": "emote_" + key, "label": label, "face": face, "shared": key in SHARED or key in VOID_SHARED})
    return clips, meta


# ======================================================================================================================
# The hunter emote catalog (docs/HUNTER_EMOTES.md): 12 clips every non-Void hunter carries, named exactly emote_<id>.
# Static ones are one-shots from and to the idle pose. taunt / point / beckon are MOVING emotes: they play while the
# hunter runs, so they are built on the hunter's own sprint clip (legs, pelvis, extras keep the stride; only the upper
# body is overridden, blended in and out so they start and end on the run). Void hunters keep their shared set; void_pink's
# own beckon is the moving one too.
NEW_STATIC = ["laugh", "look_around", "smug", "dance", "flinch", "stretch", "yawn", "hum", "victory"]
NEW_MOVING = ["taunt", "point", "beckon"]
CATALOG_FACE = {"taunt": "scream", "laugh": "happy", "point": "chase", "beckon": "happy", "look_around": "derp", "smug": "happy",
                "dance": "happy", "flinch": "stun", "stretch": "blink", "yawn": "blink", "hum": "happy", "victory": "happy",
                "shrug": "blank"}
LABEL = {"taunt": "Taunt", "laugh": "Laugh", "point": "Point", "beckon": "Beckon", "look_around": "Look around", "smug": "Smug",
         "dance": "Dance", "flinch": "Flinch", "stretch": "Stretch", "yawn": "Yawn", "hum": "Hum", "victory": "Victory"}

# how big her gestures are (persona): 1 = as authored
ENERGY = {"aki": .65, "ferryn": .8, "mavrine": .6, "ceryth": .6, "ilyra": .7, "quirith": .7, "porcelle": .8, "verrine": .7,
          "xivvy": 1.4, "opalie": 1.3, "zephyra": 1.25, "ravelle": 1.3, "nyxie": 1.2, "glyra": 1.1, "eirys": 1.2, "haelith": 1.2,
          "solyth": 1.2, "jyvra": 1.1, "loxelle": .9, "wynelle": .8, "thessine": .6, "umbriel": .7, "ysolde": .9}
EMOTE_ENERGY = {("glyra", "hum"): 1.6, ("kathy", "taunt"): 1.3, ("kathy", "smug"): 1.1, ("aki", "stretch"): 1.2}
LEFTY = {"kathy"}              # the scythe is in her right hand: her pointing / beckoning / taunting hand is the left
CROSSED_ARMS = {"kathy", "mavrine", "ceryth", "thessine", "jyvra", "briselle", "ilyra", "verrine"}   # smug: arms crossed
VARIANT = {("glyra", "dance"): "dance_waltz", ("xivvy", "dance"): "dance_hop", ("haelith", "dance"): "dance_a",
           ("opalie", "dance"): "dance_a", ("ravelle", "dance"): "dance_a",
           ("opalie", "laugh"): "laugh_a", ("ravelle", "laugh"): "laugh_a", ("xivvy", "laugh"): "laugh_a", ("zephyra", "laugh"): "laugh_a"}

_ARMS_UP = dict(LArm=(0, 0, -170), RArm=(0, 0, 170))
NEW_TEMPLATES = {
    # head back, chest shakes, a hand on the belly
    "laugh": [_rest(0), K(.2, Belly=(-9, 0, 0), Chest=(-2, 0, 0), Head=(14, 0, 0), RArm=(34, 0, -10), RFore=(98, 0, 0), LArm=(14, 0, -16))]
             + [K(.3 + .1 * i, -.35 if i % 2 else 0, Belly=(-9, 0, 0), Chest=(-2 + (4 if i % 2 else -4), 0, 3 if i % 2 else -3), Head=(14, 0, 0),
                  RArm=(34, 0, -10), RFore=(98, 0, 0), LArm=(14, 0, -16)) for i in range(11)] + [_rest(1.6)],
    # slow body-twist left, pause, right, a hand shading the eyes
    "look_around": [_rest(0), K(.4, Chest=(0, 22, 0), Belly=(0, 12, 0), Head=(2, 28, 0), RArm=(78, 0, -4), RFore=(118, 0, 0)),
                    K(.95, Chest=(0, 22, 0), Belly=(0, 12, 0), Head=(2, 28, 0), RArm=(78, 0, -4), RFore=(118, 0, 0)),
                    K(1.3, Chest=(0, -22, 0), Belly=(0, -12, 0), Head=(2, -28, 0), RArm=(78, 0, -4), RFore=(118, 0, 0)),
                    K(1.8, Chest=(0, -22, 0), Belly=(0, -12, 0), Head=(2, -28, 0), RArm=(78, 0, -4), RFore=(118, 0, 0)), _rest(2.2)],
    # hands behind the back, chin up, a slow nod
    "smug": [_rest(0), K(.5, Head=(11, 0, 0), Chest=(4, 0, 0), LArm=(-28, 0, 12), RArm=(-28, 0, -12), LFore=(34, 0, 0), RFore=(34, 0, 0)),
             K(1.0, Head=(2, 0, 0), Chest=(4, 0, 0), LArm=(-28, 0, 12), RArm=(-28, 0, -12), LFore=(34, 0, 0), RFore=(34, 0, 0)),
             K(1.5, Head=(12, 0, 0), Chest=(4, 0, 0), LArm=(-28, 0, 12), RArm=(-28, 0, -12), LFore=(34, 0, 0), RFore=(34, 0, 0)), _rest(2.2)],
    "smug_cross": [_rest(0), K(.5, Head=(10, 0, 0), Chest=(3, 0, 0), LArm=(45, 0, 22), RArm=(45, 0, -22), LFore=(105, 0, 38), RFore=(105, 0, -38)),
                   K(1.0, Head=(2, 0, 0), Chest=(3, 0, 0), LArm=(45, 0, 22), RArm=(45, 0, -22), LFore=(105, 0, 38), RFore=(105, 0, -38)),
                   K(1.5, Head=(11, 0, 0), Chest=(3, 0, 0), LArm=(45, 0, 22), RArm=(45, 0, -22), LFore=(105, 0, 38), RFore=(105, 0, -38)), _rest(2.2)],
    # quick side-step sway, arms alternating up, a small bounce
    "dance": [_rest(0)] + [K(.33 * (i + 1), -.45 if i % 2 else .25, Pelvis=(0, 15 if i % 2 else -15, 0), Chest=(0, 0, 8 if i % 2 else -8),
                             Head=(0, 0, -7 if i % 2 else 7), LArm=(0, 0, -140 if i % 2 else -24), RArm=(0, 0, 24 if i % 2 else 140),
                             LThigh=(10 if i % 2 else 0, 0, 0), RThigh=(0 if i % 2 else 10, 0, 0), LCalf=(-14 if i % 2 else 0, 0, 0),
                             RCalf=(0 if i % 2 else -14, 0, 0)) for i in range(8)] + [_rest(3.0)],
    "dance_waltz": [_rest(0)] + [K(.4 * (i + 1), 0, Pelvis=(0, 38 if i % 2 else -38, 0), Chest=(0, 0, 6 if i % 2 else -6), Head=(2, 0, -8 if i % 2 else 8),
                                   LArm=(0, 0, -78 if i % 2 else -52), RArm=(0, 0, 52 if i % 2 else 78), LFore=(14, 0, 0), RFore=(14, 0, 0),
                                   LThigh=(6 if i % 2 else 0, 0, 0), RThigh=(0 if i % 2 else 6, 0, 0)) for i in range(6)] + [_rest(3.0)],
    "dance_hop": [_rest(0)] + [K(.25 * (i + 1), -.5 if i % 2 else 1.2, LArm=(0, 0, -150 if i % 2 else -100), RArm=(0, 0, 100 if i % 2 else 150),
                                 Chest=(0, 0, 5 if i % 2 else -5), Head=(0, 0, -6 if i % 2 else 6),
                                 LThigh=(16, 0, 0), RThigh=(16, 0, 0), LCalf=(-30 if i % 2 else -8, 0, 0), RCalf=(-30 if i % 2 else -8, 0, 0))
                              for i in range(10)] + [_rest(3.0)],
    # a short recoil: arms snatched in, head ducks
    "flinch": [_rest(0), K(.09, -.55, Chest=(-9, 0, 0), Belly=(-6, 0, 0), Head=(-13, 0, 0), LArm=(28, 0, -6), RArm=(28, 0, 6), LFore=(66, 0, 0), RFore=(66, 0, 0),
                            LThigh=(8, 0, 0), RThigh=(8, 0, 0), LCalf=(-14, 0, 0), RCalf=(-14, 0, 0)),
               K(.3, -.35, Chest=(-7, 0, 0), Belly=(-4, 0, 0), Head=(-11, 0, 0), LArm=(24, 0, -5), RArm=(24, 0, 5), LFore=(56, 0, 0), RFore=(56, 0, 0)), _rest(.7)],
    # arms overhead, back arch, relax
    "stretch": [_rest(0), K(.7, Chest=(11, 0, 0), Belly=(6, 0, 0), Head=(9, 0, 0), **_ARMS_UP), K(1.35, Chest=(11, 0, 0), Belly=(6, 0, 0), Head=(9, 0, 0), **_ARMS_UP),
                _rest(2.0)],
    # a fist to the mouth, head tips back, shoulders drop
    "yawn": [_rest(0), K(.5, Head=(15, 0, 0), Chest=(-5, 0, 0), Belly=(-3, 0, 0), RArm=(92, 0, -14), RFore=(112, 0, 0), LArm=(0, 0, -4)),
             K(1.3, Head=(13, 0, 0), Chest=(-5, 0, 0), Belly=(-3, 0, 0), RArm=(92, 0, -14), RFore=(112, 0, 0), LArm=(0, 0, -4)), _rest(1.8)],
    # a gentle sway, fingers tapping at the hip
    "hum": [_rest(0)] + [K(.3 * (i + 1), 0, Chest=(0, 0, 5 if i % 2 else -5), Belly=(0, 0, -3 if i % 2 else 3), Pelvis=(0, 6 if i % 2 else -6, 0),
                           Head=(0, 0, 5 if i % 2 else -5), RArm=(0, 0, 14), RFore=(24 if (i // 1) % 2 else 10, 0, 0), RHand=(0, 0, -10 if i % 2 else 8),
                           LArm=(0, 0, -10 if i % 2 else -16)) for i in range(7)] + [_rest(2.4)],
    # fist pump, arms raised, a small hop, hold
    "victory": [_rest(0), K(.3, -.8, Chest=(-8, 0, 0), LThigh=(34, 0, 0), RThigh=(34, 0, 0), LCalf=(-58, 0, 0), RCalf=(-58, 0, 0), LFoot=(24, 0, 0), RFoot=(24, 0, 0),
                            LArm=(-30, 0, -8), RArm=(-30, 0, 8)),
                K(.55, 1.4, Chest=(6, 0, 0), Head=(8, 0, 0), LThigh=(10, 0, 0), RThigh=(10, 0, 0), LCalf=(-14, 0, 0), RCalf=(-14, 0, 0), **dict(LArm=(0, 0, -158), RArm=(0, 0, 158))),
                K(.85, -.5, LThigh=(18, 0, 0), RThigh=(18, 0, 0), LCalf=(-30, 0, 0), RCalf=(-30, 0, 0), Chest=(0, 0, 0), LArm=(0, 0, -150), RArm=(0, 0, 150)),
                K(1.1, 0, Head=(8, 0, 0), LArm=(0, 0, -150), RArm=(0, 0, 150)),
                K(1.4, 0, Head=(8, 0, 0), LArm=(0, 0, -150), RArm=(0, 0, 150), RFore=(0, 0, 40)),
                K(1.7, 0, Head=(8, 0, 0), LArm=(0, 0, -150), RArm=(0, 0, 150), RFore=(0, 0, -10)),
                K(2.0, 0, Head=(8, 0, 0), LArm=(0, 0, -150), RArm=(0, 0, 150), RFore=(0, 0, 40)),
                K(3.0, 0, Head=(8, 0, 0), Chest=(5, 0, 0), LArm=(0, 0, -150), RArm=(0, 0, 150)), _rest(3.5)],
}
# Moving emotes: (t, blend weight, pose) over the sprint clip. Bones in ADDITIVE ride on top of the run; arms replace it.
ADDITIVE = ("Pelvis", "Belly", "Chest", "Head")
MOVING_TEMPLATES = {
    "taunt": [(0, 0, {}), (.16, 1, dict(Head=(1, 0, 0), Chest=(4, 0, 0), RArm=(108, 0, -6), RFore=(40, 0, 0))),
              (.34, 1, dict(Head=(2, 0, 1), Chest=(4, 0, 0), RArm=(108, 0, -6), RFore=(112, 0, 0))),
              (.52, 1, dict(Head=(2, 0, -1), Chest=(4, 0, 0), RArm=(108, 0, -6), RFore=(40, 0, 0))),
              (.7, 1, dict(Head=(2, 0, 1), Chest=(4, 0, 0), RArm=(108, 0, -6), RFore=(112, 0, 0))), (1.0, 0, {})],
    "point": [(0, 0, {}), (.2, 1, dict(RArm=(90, 0, -3), RFore=(0, 0, 0), RHand=(0, 0, 0), Head=(3, -14, 0), Chest=(-3, -10, 0))),
              (1.0, 1, dict(RArm=(90, 0, -3), RFore=(0, 0, 0), RHand=(0, 0, 0), Head=(3, -14, 0), Chest=(-3, -10, 0))), (1.2, 0, {})],
    "beckon": [(0, 0, {}), (.22, 1, dict(RArm=(100, 0, -8), RFore=(34, 0, 0), Head=(0, 0, 8))),
               (.5, 1, dict(RArm=(100, 0, -8), RFore=(108, 0, 0), Head=(0, 0, 8))),
               (.78, 1, dict(RArm=(100, 0, -8), RFore=(34, 0, 0), Head=(0, 0, 8))),
               (1.06, 1, dict(RArm=(100, 0, -8), RFore=(108, 0, 0), Head=(0, 0, 8))), (1.4, 0, {})],
}
_SWAP = {"L-": "R-", "R-": "L-"}


def mirrored(pose):
    """Left-hand version of a right-hand pose: swap sides, flip yaw and roll."""
    out = {}
    for bone, e in pose.items():
        nb = _SWAP[bone[:2]] + bone[2:] if bone[:2] in _SWAP else bone
        out[nb] = (e[0], -e[1], -e[2])
    return out


def _energy(hunter, emote):
    base = hunter.replace("_tall", "")
    return EMOTE_ENERGY.get((base, emote), ENERGY.get(base, 1.0))


def _scaled(pose, f):
    return {b: tuple(v * f for v in e) for b, e in pose.items()} if f != 1.0 else pose


def compile_new(hunter, restq, pel, U, k, core_bones):
    """The 9 static catalog emotes for a non-Void hunter (energy-scaled, persona variants, catalog faces)."""
    from bb_core import quat_from_euler, quat_mul
    base = hunter.replace("_tall", "")
    clips, meta = {}, []
    if base.startswith("void_"):
        return clips, meta
    for emote in NEW_STATIC:
        key = VARIANT.get((base, emote), emote)
        if emote == "smug" and base in CROSSED_ARMS:
            key = "smug_cross"
        keys = NEW_TEMPLATES.get(key) or TEMPLATES[key][2]
        f = _energy(base, emote)
        times = [t for t, _, _ in keys]
        tracks = {}
        for bone in core_bones:
            vals = [quat_mul(quat_from_euler(*_scaled(pose, f).get(bone, (0, 0, 0))), restq[bone]) for _, _, pose in keys]
            tracks[bone] = {"rotation": (times, vals)}
        tracks["Pelvis"]["translation"] = (times, [(pel[0], pel[1] + dy * f * U * k, pel[2]) for _, dy, _ in keys])
        clips["emote_" + emote] = {"length": times[-1], "tracks": tracks, "loop": False}
        meta.append({"clip": "emote_" + emote, "label": LABEL[emote], "face": CATALOG_FACE[emote], "shared": True})
    return clips, meta


def compile_moving(hunter, clips, restq):
    """taunt / point / beckon on top of the hunter's own sprint clip (call after build_clips). Void: only void_pink's beckon."""
    from bb_core import quat_from_euler, quat_mul
    from bb_rig import _sample_q
    base = hunter.replace("_tall", "")
    wanted = ["beckon"] if base == "void_pink" else ([] if base.startswith("void_") else NEW_MOVING)
    src = clips["sprint"]
    L = src["length"]
    meta = []
    for emote in wanted:
        keys = MOVING_TEMPLATES[emote]
        f = _energy(base, emote)
        T = keys[-1][0]
        n = max(2, round(T * 20))
        times = [T * i / n for i in range(n + 1)]
        mirror = base in LEFTY

        def at(t):
            for (t0, w0, p0), (t1, w1, p1) in zip(keys, keys[1:]):
                if t0 <= t <= t1:
                    u = (t - t0) / max(t1 - t0, 1e-9)
                    bones = set(p0) | set(p1)
                    pose = {}
                    for b in bones:
                        a = p0.get(b, p1.get(b)) if b in p0 else tuple(0 for _ in range(3))
                        c = p1.get(b, p0.get(b)) if b in p1 else tuple(0 for _ in range(3))
                        pose[b] = tuple(a[i] + (c[i] - a[i]) * u for i in range(3))
                    return w0 + (w1 - w0) * u, pose
            return 0.0, {}
        tracks = {}
        for bone, tr in src["tracks"].items():
            new = {}
            if "translation" in tr:
                tt, vv = tr["translation"]
                new["translation"] = (times, [vv[min(range(len(tt)), key=lambda j: abs(tt[j] - (t % L)))] for t in times])
            if "rotation" in tr:
                tt, vv = tr["rotation"]
                vals = []
                for t in times:
                    q = _sample_q(tt, vv, t % L)
                    w, pose = at(t)
                    pose = _scaled(mirrored(pose) if mirror else pose, f)
                    if w > 0 and bone in pose:
                        tgt = quat_mul(quat_from_euler(*pose[bone]), q if bone in ADDITIVE else restq[bone])
                        r = tuple(q[i] + (tgt[i] - q[i]) * w for i in range(4)) if sum(a * b for a, b in zip(q, tgt)) >= 0 else \
                            tuple(q[i] + (-tgt[i] - q[i]) * w for i in range(4))
                        nrm = sum(c * c for c in r) ** .5 or 1.0
                        q = tuple(c / nrm for c in r)
                    vals.append(q)
                new["rotation"] = (times, vals)
            tracks[bone] = new
        clips["emote_" + emote] = {"length": T, "tracks": tracks, "loop": False}
        meta.append({"clip": "emote_" + emote, "label": LABEL[emote], "face": CATALOG_FACE[emote], "shared": base != "void_pink"})
    return meta
