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
    "bow": ("Bow", "blink", [_rest(0), K(.6, Belly=(-24, 0, 0), Chest=(-20, 0, 0), Head=(10, 0, 0), LArm=(14, 0, 0), RArm=(14, 0, 0)),
                             K(1.5, Belly=(-24, 0, 0), Chest=(-20, 0, 0), Head=(10, 0, 0), LArm=(14, 0, 0), RArm=(14, 0, 0)), _rest(2.2)]),
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
    "dance": ("Dance", "happy", [_rest(0)] + [K(.3 * (i + 1), -.5 if i % 2 else .3,
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
    "point": ("Point", "neutral", [_rest(0), K(.4, RArm=(85, 0, 0), Chest=(-5, 0, 0)), K(.8, RArm=(95, 0, 0), Chest=(-5, 0, 0)),
                                   K(1.1, RArm=(85, 0, 0), Chest=(-5, 0, 0)), K(1.4, RArm=(95, 0, 0), Chest=(-5, 0, 0)), _rest(2.1)]),
    "chin": ("Think", "neutral", [_rest(0), K(.5, RArm=(70, 0, 0), RFore=(122, 0, 0), Head=(-3, 0, 6))]
            + _osc(1.0, .25, 5, dict(RFore=(130, 0, 0)), dict(RFore=(120, 0, 0)), RArm=(70, 0, 0), Head=(-3, 0, 6)) + [_rest(2.6)]),
    "stretch": ("Stretch", "blink", [_rest(0), K(.8, LArm=(0, 0, -170), RArm=(0, 0, 170), Chest=(10, 0, 0), Belly=(6, 0, 0), Head=(8, 0, 0)),
                                     K(1.8, LArm=(0, 0, -170), RArm=(0, 0, 170), Chest=(10, 0, 0), Belly=(6, 0, 0), Head=(8, 0, 0)), _rest(2.6)]),
    "flex": ("Flex", "happy", [_rest(0), K(.4, LArm=(0, 0, -90), LFore=(0, 0, -105), RArm=(0, 0, 90), RFore=(0, 0, 105), Chest=(6, 0, 0)),
                               K(.8, .5, LArm=(0, 0, -90), LFore=(0, 0, -105), RArm=(0, 0, 90), RFore=(0, 0, 105), Chest=(6, 0, 0)),
                               K(1.2, 0, LArm=(0, 0, -90), LFore=(0, 0, -105), RArm=(0, 0, 90), RFore=(0, 0, 105), Chest=(6, 0, 0)), _rest(2.0)]),
    "akimbo": ("Hands on hips", "chase", [_rest(0), K(.4, LArm=(0, 0, -28), RArm=(0, 0, 28), LFore=(0, 0, 120), RFore=(0, 0, -120), Head=(4, 0, 0), Chest=(3, 0, 0)),
                                          K(1.6, LArm=(0, 0, -28), RArm=(0, 0, 28), LFore=(0, 0, 120), RFore=(0, 0, -120), Head=(4, 0, 0), Chest=(3, 0, 0)), _rest(2.1)]),
    "laugh": ("Laugh", "happy", [_rest(0), K(.3, Belly=(-18, 0, 0), Chest=(-14, 0, 0), LArm=(45, 0, 10), RArm=(45, 0, -10), LFore=(90, 0, 0), RFore=(90, 0, 0))]
              + [K(.5 + .12 * i, -.3 if i % 2 else 0, Belly=(-18, 0, 0), Chest=(-14, 0, 3 if i % 2 else -3), LArm=(45, 0, 10), RArm=(45, 0, -10),
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
    "tilt": ("Head tilt", "neutral", [_rest(0), K(1.0, Head=(2, 0, 30)), K(2.6, Head=(2, 0, 30)), _rest(3.4)]),
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
                                 K(.62, -.8, LArm=(35, 0, 0), RArm=(35, 0, 0), Chest=(-26, 0, 0), Belly=(-12, 0, 0), Head=(-6, 0, 0)),
                                 K(1.8, -.8, LArm=(35, 0, 0), RArm=(35, 0, 0), Chest=(-26, 0, 0), Belly=(-12, 0, 0), Head=(-6, 0, 0)), _rest(2.6)]),
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
    "beckon": ("Beckon", "neutral", [_rest(0), K(.4, RArm=(88, 0, -8), RFore=(30, 0, 0), Head=(0, 0, 10))]
              + _osc(.7, .3, 6, dict(RFore=(100, 0, 0)), dict(RFore=(30, 0, 0)), RArm=(88, 0, -8), Head=(0, 0, 10)) + [_rest(2.8)]),
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
    "aki": ["shy", "read", "peek"], "briselle": ["hold", "chin"], "ceryth": ["chin", "point", "salute"],
    "dovelle": ["stretch", "akimbo"], "eirys": ["flex", "point", "spin"], "ferryn": ["panic", "shy", "peek"],
    "glyra": ["dance", "sway", "tantrum"], "haelith": ["fetch", "dance"], "ilyra": ["stretch", "chin", "sulk"],
    "jyvra": ["akimbo", "point", "tantrum"], "kathy": ["hug", "pat"], "loxelle": ["sway", "stretch", "hold"],
    "mavrine": ["salute", "point", "chin"], "nyxie": ["tease", "sway", "spin"], "opalie": ["spin", "dance", "laugh"],
    "porcelle": ["shy", "hold", "peek"], "quirith": ["sulk", "hug", "shy"], "ravelle": ["laugh", "dance", "tease"],
    "solyth": ["flex", "tantrum", "stretch"], "thessine": ["facepalm", "chin", "point"], "umbriel": ["peek", "shy", "sulk"],
    "verrine": ["sulk", "facepalm", "peek"], "wynelle": ["sway", "hold", "spin"], "xivvy": ["spin", "dance", "laugh"],
    "ysolde": ["hold", "hug", "pat"], "zephyra": ["spin", "hold", "laugh"],
}


def names_for(hunter):
    base = hunter.replace("_tall", "")
    if base.startswith("void_"):
        return VOID_SHARED + [PERSONAL_VOID[base[5:]]]
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
