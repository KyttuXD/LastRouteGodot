"""Music/stage group: 18 types redone low-poly (fewer boxes, no tiny trim, shared atlas tiles, hidden faces culled via LOWPOLY).
Exec'd by build_blocky_props.py after SIZE_SCALE and before mansion finishes (Part, VOX, PROPS, TARGET_SIZE in scope).
Keeps type ids, colour-option keys (so the model counts stay), TARGET_SIZE bounds, outer extents (colliders), front +z, atlas tiles.
"""

_MUSIC_078 = [
    "micStand", "podiumMic", "deskMic", "drumKit", "electricGuitarStand", "acousticGuitarStand", "bassGuitarStand",
    "keyboardStand", "uprightPianoMusic", "ampStack", "comboAmp", "stageMonitor", "paSpeakerPole", "studioMonitors",
    "musicStand", "guitarWallHanger", "stagePlatform", "stageSpeaker",
]


def _lp_set(name, boxes):
    """Swap the shapes, keep the colour options (model count) and the size."""
    assert name in PROPS and not VARIANTS.get(name), (name, VARIANTS.get(name))
    PROPS[name] = (boxes, PROPS[name][1])


def _lp_base(c, cx, cz, r, h, kind="black"):
    """Tripod footprint as two flat bars (rear cross bar + front spine) and a pole: same reach as the three splayed legs."""
    c.add(cx - r - 0.015, 0.0, cz - r * 0.6 - 0.015, cx + r + 0.015, 0.03, cz - r * 0.6 + 0.07, kind)
    c.add(cx - 0.015, 0.0, cz - r * 0.6 - 0.015, cx + 0.015, 0.03, cz + r + 0.015, kind)
    c.add(cx - 0.02, 0.0, cz - 0.02, cx + 0.02, h, cz + 0.02, kind)


def lp_mic_stand():
    c = Part(0.5, 1.6, 0.5)
    _lp_base(c, 0.25, 0.22, 0.2, 1.25)
    piv = (0.25, 1.28, 0.22)
    c.add(0.245, 1.27, 0.22, 0.255, 1.30, 0.5, "black", rot=(-20, 0, 0), pivot=piv)          # boom arm
    c.add(0.225, 1.38, 0.425, 0.275, 1.6, 0.485, "black", rot=(-20, 0, 0), pivot=piv)        # mic (body + grille in one)
    return c.boxes


def lp_podium_mic():
    w, h, d = 0.6, 1.15, 0.5
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, 0.06, d, "@wood")                                                 # plinth
    c.add(0.06, 0.06, 0.06, w - 0.06, 0.95, d - 0.06, "@wood")
    c.add(0.1, 0.25, d - 0.07, w - 0.1, 0.75, d - 0.05, "@panel")
    c.add(0.02, 0.95, 0.0, w - 0.02, 1.0, d, "@wood", rot=(12, 0, 0))                          # sloped top
    c.add(0.28, 1.0, 0.1, 0.32, 1.15, 0.14, "black")                                          # gooseneck as a straight stem
    c.add(0.28, 1.1, 0.14, 0.32, 1.15, 0.34, "black")                                         # capsule arm
    return c.boxes


def lp_desk_mic():
    w, h, d = 0.15, 0.25, 0.15
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, 0.03, d, "black")
    c.add(0.065, 0.03, 0.065, 0.085, 0.18, 0.085, "steel")
    c.add(0.05, 0.16, 0.05, 0.1, 0.25, 0.1, "black")
    return c.boxes


def lp_drum_kit():
    c = Part(1.8, 1.2, 1.5)
    c.add(0.65, 0.0, 0.85, 1.15, 0.55, 1.25, "@shell")                                        # kick drum
    c.add(0.7, 0.05, 1.25, 1.1, 0.5, 1.27, "white")                                           # kick head
    c.add(0.35, 0.5, 0.5, 0.65, 0.66, 0.8, "@shell")                                          # snare
    c.add(0.48, 0.0, 0.63, 0.52, 0.5, 0.67, "steel")                                          # snare stand
    c.add(0.65, 0.62, 0.95, 1.16, 0.83, 1.15, "@shell")                                       # rack toms as one block on the kick
    c.add(1.25, 0.0, 0.5, 1.6, 0.56, 0.85, "@shell")                                          # floor tom
    c.add(0.12, 0.0, 0.85, 0.16, 0.95, 0.89, "steel")                                         # hi-hat stand
    c.add(0.0, 0.93, 0.72, 0.3, 0.99, 1.02, "brass")                                          # hi-hat pair
    for x, y in ((0.4, 1.15), (1.5, 1.1)):                                                    # crash, ride
        c.add(x - 0.02, 0.0, 1.3, x + 0.02, y, 1.34, "steel")
        c.add(x - 0.2, y, 1.12, x + 0.2, y + 0.02, 1.52, "brass", rot=(-10, 0, 0))
    c.add(0.85, 0.0, 0.25, 0.95, 0.45, 0.35, "black")                                         # throne post
    c.add(0.72, 0.45, 0.12, 1.08, 0.52, 0.48, "@seat")
    return c.boxes


def _lp_guitar(c, cx, body_w, body_h, neck_h, body, neck="dark", hollow=False, strings=6):
    """Guitar leaning on an A-frame: feet + cradle, two-box body, sound hole or pickup, neck, headstock."""
    c.add(cx - 0.18, 0.0, 0.04, cx + 0.18, 0.04, 0.3, "black")                               # stand feet
    c.add(cx - 0.02, 0.04, 0.04, cx + 0.02, 0.45, 0.08, "black")                              # back post
    tilt, piv = (-12, 0, 0), (cx, 0.1, 0.2)
    t0, t1 = 0.14, 0.24 if hollow else 0.21
    y = 0.1
    lower, waist = body_h * 0.5, body_h * 0.14
    c.add(cx - body_w / 2, y, t0, cx + body_w / 2, y + lower + waist * 0.5, t1, body, rot=tilt, pivot=piv)
    c.add(cx - body_w * 0.43, y + lower + waist * 0.5, t0, cx + body_w * 0.43, y + body_h, t1, body, rot=tilt, pivot=piv)
    if hollow:
        c.add(cx - 0.05, y + lower + waist * 0.2, t1, cx + 0.05, y + lower + waist + 0.04, t1 + 0.005, "black", rot=tilt, pivot=piv)
        c.add(cx - 0.07, y + 0.07, t1, cx + 0.07, y + 0.1, t1 + 0.01, "dark", rot=tilt, pivot=piv)        # bridge
    else:
        c.add(cx - 0.05, y + 0.12, t1, cx + 0.05, y + 0.25, t1 + 0.01, "black", rot=tilt, pivot=piv)     # pickups
    c.add(cx - 0.025, y + body_h, 0.17, cx + 0.025, y + body_h + neck_h, 0.21, neck, rot=tilt, pivot=piv)
    c.add(cx - 0.045, y + body_h + neck_h, 0.165, cx + 0.045, y + body_h + neck_h + 0.15, 0.205, neck, rot=tilt, pivot=piv)
    yy = y + body_h + neck_h + 0.03 + (2 if strings == 6 else 1) * 0.04                                               # one tuner bar (the top peg row)
    c.add(cx - 0.06, yy, 0.18, cx + 0.06, yy + 0.015, 0.19, "steel", rot=tilt, pivot=piv)
    c.add(cx - 0.012, y + 0.06, t1 + 0.005, cx + 0.012, y + body_h + neck_h, t1 + 0.012, "steel", rot=tilt, pivot=piv)   # strings


def lp_electric():
    c = Part(0.4, 1.0, 0.35)
    _lp_guitar(c, 0.2, 0.34, 0.42, 0.3, "@body")
    return c.boxes


def lp_acoustic():
    c = Part(0.45, 1.05, 0.35)
    _lp_guitar(c, 0.225, 0.4, 0.48, 0.3, "@body", hollow=True)
    return c.boxes


def lp_bass():
    c = Part(0.4, 1.15, 0.35)
    _lp_guitar(c, 0.2, 0.34, 0.42, 0.42, "@body", strings=4)
    return c.boxes


def _lp_black_key_groups(c, x_start, step, count, y0, y1, z0, z1):
    """Black keys as one block per 2- or 3-key group (the old i % 7 in (2, 6) gaps)."""
    i = 0
    while i < count:
        if i % 7 in (2, 6):
            i += 1
            continue
        j = i
        while j + 1 < count and (j + 1) % 7 not in (2, 6):
            j += 1
        c.add(x_start + i * step, y0, z0, x_start + j * step + step * 0.5, y1, z1, "black")
        i = j + 1


def lp_keyboard_stand():
    w, h, d = 1.3, 0.95, 0.4
    c = Part(w, h, d)
    for x in (0.2, 1.0):                                                                       # X-stand pairs
        c.add(x, 0.0, 0.18, x + 0.04, 0.85, 0.22, "black", rot=(0, 0, 28), pivot=(x + 0.02, 0.42, 0.2))
        c.add(x + 0.06, 0.0, 0.18, x + 0.1, 0.85, 0.22, "black", rot=(0, 0, -28), pivot=(x + 0.08, 0.42, 0.2))
    c.add(0.0, 0.82, 0.0, w, 0.92, d, "@body")
    c.add(0.06, 0.88, 0.16, w - 0.06, 0.93, d - 0.03, "white")
    _lp_black_key_groups(c, 0.1, 0.062, 18, 0.93, 0.95, 0.26, d - 0.03)
    c.add(0.06, 0.92, 0.03, 0.5, 0.95, 0.14, "black")                                          # knobs panel
    c.add(0.55, 0.92, 0.04, 0.8, 0.95, 0.12, "screen")
    return c.boxes


def lp_upright_piano():
    w, h, d = 1.5, 1.25, 0.95
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, 1.25, 0.5, "@wood")                                                # case
    c.add(0.05, 0.0, 0.5, w - 0.05, 0.72, 0.62, "@wood")                                       # key bed down to the floor (toe blocks folded in)
    c.add(0.08, 0.72, 0.5, w - 0.08, 0.75, 0.62, "white")
    _lp_black_key_groups(c, 0.12, 0.05, 26, 0.75, 0.77, 0.5, 0.56)
    c.add(0.1, 0.85, 0.5, w - 0.1, 1.1, 0.52, "@panel")
    c.add(0.5, 0.88, 0.52, 1.0, 1.0, 0.54, "paper")
    c.add(0.6, 0.06, 0.62, 0.9, 0.1, 0.66, "brass")                                            # pedals
    c.add(0.35, 0.0, 0.7, 1.15, 0.48, 0.95, "@wood")                                           # bench
    c.add(0.33, 0.48, 0.68, 1.17, 0.52, 0.95, "black")
    return c.boxes


def lp_amp_stack():
    w, h, d = 0.75, 1.3, 0.4
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, 0.75, d, "black")                                                  # 4x12 cab
    c.add(0.04, 0.04, d - 0.01, w - 0.04, 0.71, d, "@grille")
    for y in (0.2, 0.55):                                                                      # speaker pairs as two bands
        c.add(0.1, y - 0.1, d, 0.65, y + 0.1, d + 0.005, "black")
    c.add(0.0, 0.75, 0.02, w, 1.0, d - 0.02, "black")                                          # head
    c.add(0.04, 0.82, d - 0.03, w - 0.04, 0.95, d - 0.02, "brass")                             # control panel
    c.add(0.2, 1.0, 0.15, 0.55, 1.03, 0.25, "black")                                           # handle
    return c.boxes


def lp_combo_amp():
    w, h, d = 0.6, 0.5, 0.3
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, 0.42, d, "@tolex")
    c.add(0.04, 0.04, d - 0.01, w - 0.04, 0.32, d, "@grille")
    c.add(0.04, 0.34, d - 0.02, w - 0.04, 0.4, d - 0.01, "brass")
    c.add(0.2, 0.42, 0.12, 0.4, 0.45, 0.18, "black")
    return c.boxes


def lp_stage_monitor():
    w, h, d = 0.55, 0.35, 0.4
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, 0.12, d, "black")
    c.add(0.0, 0.12, 0.0, w, 0.35, 0.18, "black")
    c.add(0.02, 0.06, 0.18, w - 0.02, 0.32, 0.36, "@grille", rot=(-40, 0, 0), pivot=(w / 2, 0.12, 0.27))
    return c.boxes


def lp_pa_speaker_pole():
    w, h, d = 0.5, 2.0, 0.5
    c = Part(w, h, d)
    _lp_base(c, 0.25, 0.25, 0.22, 1.35)
    c.add(0.07, 1.35, 0.12, 0.43, 2.0, 0.42, "black")
    c.add(0.1, 1.4, 0.42, 0.4, 1.82, 0.43, "@grille")
    c.add(0.18, 1.86, 0.42, 0.32, 1.95, 0.43, "steel")
    return c.boxes


def lp_studio_monitors():
    w, h, d = 0.8, 0.35, 0.25
    c = Part(w, h, d)
    for x in (0.0, 0.58):
        c.add(x, 0.0, 0.0, x + 0.22, 0.35, d, "black")
        c.add(x + 0.04, 0.05, d, x + 0.18, 0.19, d + 0.005, "@grille")
        c.add(x + 0.07, 0.23, d, x + 0.15, 0.31, d + 0.005, "steel")
    return c.boxes


def lp_music_stand():
    w, h, d = 0.45, 1.2, 0.4
    c = Part(w, h, d)
    _lp_base(c, 0.225, 0.2, 0.18, 0.95)
    piv = (0.225, 0.95, 0.2)
    c.add(0.0, 0.92, 0.12, w, 1.2, 0.16, "black", rot=(-15, 0, 0), pivot=piv)                  # desk
    c.add(0.03, 0.97, 0.16, w - 0.03, 1.18, 0.17, "paper", rot=(-15, 0, 0), pivot=piv)
    c.add(0.0, 0.92, 0.16, w, 0.95, 0.22, "black")                                              # lip
    return c.boxes


def lp_guitar_wall_hanger():
    w, h, d = 1.0, 0.8, 0.2
    c = Part(w, h, d)
    c.add(0.0, 0.6, 0.0, w, 0.68, 0.04, "@wood")                                                # rail
    for i, body in enumerate(["red", "yellow", "teal"]):
        x = 0.17 + i * 0.33
        c.add(x - 0.02, 0.6, 0.04, x + 0.02, 0.66, 0.1, "black")                                # hook
        c.add(x - 0.03, 0.3, 0.06, x + 0.03, 0.78, 0.1, "dark")                                 # neck + headstock
        c.add(x - 0.13, 0.0, 0.05, x + 0.13, 0.18, 0.12, body)                                  # lower bout
        c.add(x - 0.11, 0.18, 0.05, x + 0.11, 0.32, 0.12, body)                                 # upper bout
    c.add(0.11, 0.04, 0.12, 0.15, 0.18, 0.125, "white")                                         # one pickguard keeps the front depth
    return c.boxes


_lp_set("micStand", lp_mic_stand())
_lp_set("podiumMic", lp_podium_mic())
_lp_set("deskMic", lp_desk_mic())
_lp_set("drumKit", lp_drum_kit())
_lp_set("electricGuitarStand", lp_electric())
_lp_set("acousticGuitarStand", lp_acoustic())
_lp_set("bassGuitarStand", lp_bass())
_lp_set("keyboardStand", lp_keyboard_stand())
_lp_set("uprightPianoMusic", lp_upright_piano())
_lp_set("ampStack", lp_amp_stack())
_lp_set("comboAmp", lp_combo_amp())
_lp_set("stageMonitor", lp_stage_monitor())
_lp_set("paSpeakerPole", lp_pa_speaker_pole())
_lp_set("studioMonitors", lp_studio_monitors())
_lp_set("musicStand", lp_music_stand())
_lp_set("guitarWallHanger", lp_guitar_wall_hanger())
# fraction-of-footprint types (blocky_props_extra.py): platform drops the buried inner top; speaker shares one grille panel
_lp_set("stagePlatform", [(0, 0, 0, 1, .8, 1, "dark"), (0, .8, 0, 1, 1, 1, "oak")])
_lp_set("stageSpeaker", [(0, 0, 0, 1, 1, .9, "black"), (.1, .06, .9, .9, .95, 1, "steel"),
                         (.3, .6, 1, .7, .85, 1, "black"), (.3, .12, 1, .7, .34, 1, "black")])

LOWPOLY.update(_MUSIC_078)
