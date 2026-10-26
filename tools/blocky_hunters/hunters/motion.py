"""Per-hunter motion profiles: the same nine clip names on the same rig, shaped per personality.

Keys (all optional, see bb_rig.DEFAULT_PROFILE): tempo (locomotion speed), stride / knee (leg swing), arm_swing,
bounce (pelvis bob), lean (deg forward), head_pitch (deg down), head_roll (deg tilt), shoulder_in (arms
pulled in), idle_amp / idle_tempo (idle fidgeting). Personalities: LORE-CANON section 5 (Kathy, Aki, Loxelle and
Nyxie confirmed; the rest are soft canon) - a first pass to tune by eye."""
PROFILES = {
    # confirmed
    "kathy":    dict(tempo=1.0, stride=1.0, bounce=1.15, head_roll=4, idle_amp=1.0),                       # warm, protective: steady, upright
    "aki":      dict(tempo=0.9, stride=0.8, arm_swing=0.6, lean=7, head_pitch=9, shoulder_in=5, idle_amp=0.6),  # shy bookworm: hunched, small
    "loxelle":  dict(tempo=0.95, stride=0.9, bounce=1.1, idle_amp=1.2, head_roll=2),                      # calm, swishy
    "nyxie":    dict(tempo=1.0, stride=1.15, bounce=0.9, head_roll=5, idle_amp=1.3),                      # bold, unpredictable
    # soft canon
    "briselle": dict(tempo=0.9, stride=0.9, arm_swing=0.8),
    "ceryth":   dict(tempo=1.0, stride=0.95, arm_swing=0.5, bounce=0.7, idle_amp=0.5),                    # blunt, analytical: stiff
    "dovelle":  dict(),                                                                                    # the steady normal one
    "eirys":    dict(tempo=1.2, stride=1.1, lean=5, bounce=1.2),                                           # competitive: always racing
    "ferryn":   dict(tempo=1.1, stride=0.8, arm_swing=0.7, lean=5, head_pitch=6, shoulder_in=6, idle_amp=1.6, idle_tempo=1.4),  # shy, jumpy
    "glyra":    dict(tempo=0.85, stride=0.9, head_roll=7, idle_amp=1.4, idle_tempo=0.8),                   # dreamy, music-obsessed
    "haelith":  dict(tempo=1.1, stride=1.1, bounce=1.3, idle_amp=1.3, idle_tempo=1.2),                    # loyal, eager
    "ilyra":    dict(tempo=0.9, stride=0.9, arm_swing=0.6, bounce=0.7, head_roll=-4, idle_amp=0.5),       # aloof, catlike
    "jyvra":    dict(tempo=1.1, stride=1.1, lean=5, arm_swing=1.2),                                        # pushy but means well
    "mavrine":  dict(tempo=1.0, stride=0.95, arm_swing=0.3, bounce=0.5, idle_amp=0.3),                    # formal rule-keeper: rigid
    "opalie":   dict(tempo=1.1, stride=1.0, bounce=1.5, arm_swing=1.3, idle_amp=1.3, idle_tempo=1.2),     # cheerful mascot
    "porcelle": dict(tempo=0.85, stride=0.8, arm_swing=0.7, shoulder_in=4, head_pitch=4, idle_amp=0.7),   # soft-spoken
    "quirith":  dict(tempo=0.9, stride=0.9, arm_swing=0.5, bounce=0.7, idle_amp=0.5, head_roll=-3),       # cold, then clingy
    "ravelle":  dict(tempo=1.1, stride=1.05, bounce=1.4, head_roll=-6, idle_amp=1.4),                     # prankster
    "solyth":   dict(tempo=1.1, stride=1.2, arm_swing=1.3, lean=4),                                        # hot-tempered, sunny
    "thessine": dict(tempo=1.0, stride=0.9, arm_swing=0.5, head_roll=6, idle_amp=0.7),                    # nitpicky auditor
    "umbriel":  dict(tempo=0.85, stride=0.85, arm_swing=0.7, lean=5, head_pitch=7, shoulder_in=4, idle_amp=0.7),  # introvert
    "verrine":  dict(tempo=0.9, stride=0.9, arm_swing=0.4, lean=6, head_pitch=5, shoulder_in=7, idle_amp=0.6),     # sulky vent loner
    "wynelle":  dict(tempo=0.9, stride=0.95, arm_swing=0.8, bounce=0.8, idle_amp=0.8, idle_tempo=0.8),    # icy and gentle: smooth, slow
    "xivvy":    dict(tempo=1.25, stride=1.2, arm_swing=1.4, bounce=1.7, lean=-3, head_roll=6, idle_amp=1.8, idle_tempo=1.5),  # hyper, airy
    "ysolde":   dict(tempo=0.85, stride=0.85, head_roll=6, head_pitch=3, idle_amp=0.9),                   # sentimental
    "zephyra":  dict(tempo=1.05, stride=1.0, bounce=1.35, arm_swing=1.1, idle_amp=1.2),                   # cheerful merchant
}


# Void: the roster's "more aggressive" baseline (shared), plus a nudge per colour toward its gimmick. First pass.
_VOID = dict(tempo=1.15, stride=1.1, arm_swing=0.8, lean=5, head_pitch=3, idle_amp=0.5)
PROFILES.update({f"void_{c}": dict(_VOID, **o) for c, o in {
    "black": dict(idle_amp=0.7), "blue": dict(tempo=1.0, stride=0.95, arm_swing=0.5, bounce=0.7),
    "brown": dict(tempo=1.05, stride=1.2, arm_swing=1.2, lean=8), "cyan": dict(head_roll=5, idle_amp=1.2, idle_tempo=1.4),
    "gray": dict(tempo=0.95, arm_swing=0.2, bounce=0.4, idle_amp=0.2, lean=2), "green": dict(arm_swing=0.9, bounce=1.1, head_roll=-4),
    "orange": dict(tempo=1.3, stride=1.25, lean=10, arm_swing=1.3), "pink": dict(tempo=0.95, head_roll=6, bounce=1.2, idle_amp=1.0),
    "purple": dict(tempo=1.2, bounce=0.6, idle_amp=1.0, idle_tempo=1.6), "red": dict(tempo=1.3, stride=1.25, arm_swing=1.4, lean=9, head_pitch=6),
    "white": dict(tempo=0.95, head_roll=8, head_pitch=-2, idle_amp=1.3), "yellow": dict(tempo=1.2, stride=1.15, arm_swing=1.1, bounce=1.2),
}.items()})


def profile(name):
    return PROFILES.get(name.replace("_tall", ""), {})
