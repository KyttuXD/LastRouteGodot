"""Music wing props (Rehearsal Hall): mics, instruments, amps, stage and studio gear. Original designs
authored here in metres at real-world size (HUNTER_SCALE 1.5 makes them hunter scale in game, like the seats and counters).
exec'd after blocky_props_mall.py, so Part, _reg and VOX are in scope. Front is +z, back (z = 0) faces the wall.
"""


def _tripod(c, cx, cz, r, h, kind="black"):
    """Three splayed legs meeting under (cx, cz) at height h."""
    for dx, dz in ((-r, -r * 0.6), (r, -r * 0.6), (0.0, r)):
        x0, z0 = cx + dx, cz + dz
        c.add(min(x0, cx) - 0.015, 0, min(z0, cz) - 0.015, max(x0, cx) + 0.015, 0.03, max(z0, cz) + 0.015, kind)
    c.add(cx - 0.02, 0.0, cz - 0.02, cx + 0.02, h, cz + 0.02, kind)


def mic_stand():
    w, h, d = 0.5, 1.6, 0.5
    c = Part(w, h, d)
    _tripod(c, 0.25, 0.22, 0.2, 1.25)
    c.add(0.23, 1.25, 0.2, 0.27, 1.29, 0.24, "steel")                                        # clutch
    c.add(0.245, 1.27, 0.22, 0.255, 1.30, 0.5, "black", rot=(-20, 0, 0), pivot=(0.25, 1.28, 0.22))   # boom arm
    c.add(0.23, 1.38, 0.43, 0.27, 1.52, 0.48, "black", rot=(-20, 0, 0), pivot=(0.25, 1.28, 0.22))    # mic body
    c.add(0.225, 1.52, 0.425, 0.275, 1.6, 0.485, "steel", rot=(-20, 0, 0), pivot=(0.25, 1.28, 0.22)) # grille
    return c.boxes


def podium_mic():
    w, h, d = 0.6, 1.15, 0.5
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, 0.06, d, "@wood")
    c.add(0.06, 0.06, 0.06, w - 0.06, 0.95, d - 0.06, "@wood")
    c.add(0.1, 0.25, d - 0.07, w - 0.1, 0.75, d - 0.05, "@panel")                             # front panel
    c.add(0.02, 0.95, 0.0, w - 0.02, 1.0, d, "@wood", rot=(12, 0, 0))                          # sloped top
    c.add(0.28, 1.0, 0.1, 0.32, 1.1, 0.14, "black")                                             # gooseneck base
    c.add(0.29, 1.08, 0.12, 0.31, 1.1, 0.3, "steel", rot=(30, 0, 0), pivot=(0.3, 1.09, 0.12))   # gooseneck
    c.add(0.28, 1.1, 0.28, 0.32, 1.15, 0.34, "black")                                           # capsule
    return c.boxes


def desk_mic():
    w, h, d = 0.15, 0.25, 0.15
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, 0.03, d, "black")
    c.add(0.065, 0.03, 0.065, 0.085, 0.18, 0.085, "steel")
    c.add(0.05, 0.16, 0.05, 0.1, 0.25, 0.1, "black")
    return c.boxes


def drum_kit():
    w, h, d = 1.8, 1.2, 1.5
    c = Part(w, h, d)
    c.add(0.65, 0.0, 0.85, 1.15, 0.55, 1.25, "@shell")                                         # kick drum
    c.add(0.7, 0.05, 1.25, 1.1, 0.5, 1.27, "white")                                             # kick head
    c.add(0.86, 0.22, 1.27, 0.94, 0.3, 1.28, "black")                                           # logo port
    c.add(0.35, 0.5, 0.5, 0.65, 0.65, 0.8, "@shell")                                            # snare
    c.add(0.36, 0.65, 0.51, 0.64, 0.66, 0.79, "white")
    c.add(0.48, 0.0, 0.63, 0.52, 0.5, 0.67, "steel")                                            # snare stand
    for x0 in (0.65, 0.92):                                                                     # rack toms on the kick
        c.add(x0, 0.62, 0.95, x0 + 0.24, 0.82, 1.15, "@shell")
        c.add(x0 + 0.01, 0.82, 0.96, x0 + 0.23, 0.83, 1.14, "white")
    c.add(1.25, 0.0, 0.5, 1.6, 0.55, 0.85, "@shell")                                            # floor tom
    c.add(1.26, 0.55, 0.51, 1.59, 0.56, 0.84, "white")
    c.add(0.12, 0.0, 0.85, 0.16, 0.95, 0.89, "steel")                                           # hi-hat stand
    c.add(0.0, 0.93, 0.72, 0.3, 0.95, 1.02, "brass")
    c.add(0.0, 0.97, 0.72, 0.3, 0.99, 1.02, "brass")
    for x, y in ((0.4, 1.15), (1.5, 1.1)):                                                      # crash, ride
        c.add(x - 0.02, 0.0, 1.3, x + 0.02, y, 1.34, "steel")
        c.add(x - 0.2, y, 1.12, x + 0.2, y + 0.02, 1.52, "brass", rot=(-10, 0, 0))
    c.add(0.75, 0.0, 0.15, 1.05, 0.45, 0.45, "black")                                           # throne
    c.add(0.72, 0.45, 0.12, 1.08, 0.52, 0.48, "@seat")
    return c.boxes


def _guitar(c, cx, body_w, body_h, neck_h, body, neck="dark", hollow=False, strings=6):
    """A guitar leaning back on a small A-frame stand: lower bout, waist and upper bout, neck, headstock."""
    c.add(cx - 0.18, 0.0, 0.04, cx + 0.18, 0.04, 0.3, "black")                                 # stand feet
    c.add(cx - 0.02, 0.04, 0.04, cx + 0.02, 0.45, 0.08, "black")                                # stand back post
    c.add(cx - 0.12, 0.04, 0.2, cx + 0.12, 0.1, 0.28, "black")                                  # cradle
    tilt = (-12, 0, 0)
    piv = (cx, 0.1, 0.2)
    t0, t1 = 0.14, 0.24 if hollow else 0.21                                                      # body depth (hollow is thicker)
    y = 0.1
    lower, waist, upper = body_h * 0.5, body_h * 0.14, body_h * 0.36
    c.add(cx - body_w / 2, y, t0, cx + body_w / 2, y + lower, t1, body, rot=tilt, pivot=piv)
    c.add(cx - body_w * 0.36, y + lower, t0, cx + body_w * 0.36, y + lower + waist, t1, body, rot=tilt, pivot=piv)
    c.add(cx - body_w * 0.43, y + lower + waist, t0, cx + body_w * 0.43, y + body_h, t1, body, rot=tilt, pivot=piv)
    if hollow:
        c.add(cx - 0.05, y + lower + waist * 0.2, t1, cx + 0.05, y + lower + waist + 0.04, t1 + 0.005, "black", rot=tilt, pivot=piv)   # sound hole
        c.add(cx - 0.07, y + 0.07, t1, cx + 0.07, y + 0.1, t1 + 0.01, "dark", rot=tilt, pivot=piv)                                     # bridge
    else:
        c.add(cx - body_w * 0.3, y + 0.05, t1, cx + body_w * 0.05, y + lower + waist, t1 + 0.005, "white", rot=tilt, pivot=piv)       # pickguard
        for k in range(2):
            c.add(cx - 0.05, y + 0.12 + k * 0.1, t1, cx + 0.05, y + 0.15 + k * 0.1, t1 + 0.01, "black", rot=tilt, pivot=piv)          # pickups
        c.add(cx + body_w * 0.15, y + 0.04, t1, cx + body_w * 0.3, y + 0.08, t1 + 0.01, "steel", rot=tilt, pivot=piv)                  # knobs
    c.add(cx - 0.025, y + body_h, 0.17, cx + 0.025, y + body_h + neck_h, 0.21, neck, rot=tilt, pivot=piv)
    c.add(cx - 0.045, y + body_h + neck_h, 0.165, cx + 0.045, y + body_h + neck_h + 0.15, 0.205, neck, rot=tilt, pivot=piv)
    for k in range(3 if strings == 6 else 2):                                                    # tuning pegs
        yy = y + body_h + neck_h + 0.03 + k * 0.04
        c.add(cx - 0.06, yy, 0.18, cx + 0.06, yy + 0.015, 0.19, "steel", rot=tilt, pivot=piv)
    c.add(cx - 0.012 * strings / 6, y + 0.06, t1 + 0.005, cx + 0.012 * strings / 6, y + body_h + neck_h, t1 + 0.012,
          "steel", rot=tilt, pivot=piv)                                                          # strings


def electric_guitar_stand():
    c = Part(0.4, 1.0, 0.35)
    _guitar(c, 0.2, 0.34, 0.42, 0.3, "@body")
    return c.boxes


def acoustic_guitar_stand():
    c = Part(0.45, 1.05, 0.35)
    _guitar(c, 0.225, 0.4, 0.48, 0.3, "@body", hollow=True)
    return c.boxes


def bass_guitar_stand():
    c = Part(0.4, 1.15, 0.35)
    _guitar(c, 0.2, 0.34, 0.42, 0.42, "@body", strings=4)
    return c.boxes


def keyboard_stand():
    w, h, d = 1.3, 0.95, 0.4
    c = Part(w, h, d)
    for x in (0.2, 1.0):                                                                         # X-stand pairs
        c.add(x, 0.0, 0.18, x + 0.04, 0.85, 0.22, "black", rot=(0, 0, 28), pivot=(x + 0.02, 0.42, 0.2))
        c.add(x + 0.06, 0.0, 0.18, x + 0.1, 0.85, 0.22, "black", rot=(0, 0, -28), pivot=(x + 0.08, 0.42, 0.2))
    c.add(0.0, 0.82, 0.0, w, 0.92, d, "@body")                                                   # synth case
    c.add(0.06, 0.88, 0.16, w - 0.06, 0.93, d - 0.03, "white")                                   # white keys
    for i in range(18):                                                                          # black keys
        if i % 7 in (2, 6):
            continue
        x = 0.1 + i * 0.062
        c.add(x, 0.93, 0.26, x + 0.03, 0.95, d - 0.03, "black")
    c.add(0.06, 0.92, 0.03, 0.5, 0.95, 0.14, "black")                                            # knobs panel
    c.add(0.55, 0.92, 0.04, 0.8, 0.95, 0.12, "screen")                                           # display
    return c.boxes


def upright_piano():
    w, h, d = 1.5, 1.25, 0.95
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, 1.25, 0.5, "@wood")                                                  # case
    c.add(0.05, 0.62, 0.5, w - 0.05, 0.72, 0.62, "@wood")                                        # key bed
    c.add(0.08, 0.72, 0.5, w - 0.08, 0.75, 0.62, "white")                                        # keys
    for i in range(26):
        if i % 7 in (2, 6):
            continue
        x = 0.12 + i * 0.05
        c.add(x, 0.75, 0.5, x + 0.025, 0.77, 0.56, "black")
    c.add(0.1, 0.85, 0.5, w - 0.1, 1.1, 0.52, "@panel")                                          # front panel
    c.add(0.5, 0.88, 0.52, 1.0, 1.0, 0.54, "paper")                                              # sheet music
    for x in (0.05, w - 0.1):                                                                    # toe blocks
        c.add(x, 0.0, 0.5, x + 0.05, 0.62, 0.62, "@wood")
    c.add(0.6, 0.06, 0.48, 0.9, 0.1, 0.56, "brass")                                              # pedals
    c.add(0.35, 0.0, 0.7, 1.15, 0.48, 0.95, "@wood")                                             # bench
    c.add(0.33, 0.48, 0.68, 1.17, 0.52, 0.95, "black")
    return c.boxes


def amp_stack():
    w, h, d = 0.75, 1.3, 0.4
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, 0.75, d, "black")                                                    # 4x12 cab
    c.add(0.04, 0.04, d - 0.01, w - 0.04, 0.71, d, "@grille")
    for x, y in ((0.2, 0.2), (0.55, 0.2), (0.2, 0.55), (0.55, 0.55)):
        c.add(x - 0.1, y - 0.1, d, x + 0.1, y + 0.1, d + 0.005, "black")                          # speaker cones
    c.add(0.0, 0.75, 0.02, w, 1.0, d - 0.02, "black")                                             # head
    c.add(0.04, 0.82, d - 0.03, w - 0.04, 0.95, d - 0.02, "brass")                                # control panel
    c.add(0.62, 0.85, d - 0.02, 0.67, 0.9, d - 0.015, "red")                                      # standby LED
    c.add(0.2, 1.0, 0.15, 0.55, 1.03, 0.25, "black")                                              # handle
    return c.boxes


def combo_amp():
    w, h, d = 0.6, 0.5, 0.3
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, 0.42, d, "@tolex")
    c.add(0.04, 0.04, d - 0.01, w - 0.04, 0.32, d, "@grille")
    c.add(0.04, 0.34, d - 0.02, w - 0.04, 0.4, d - 0.01, "brass")
    c.add(0.2, 0.42, 0.12, 0.4, 0.45, 0.18, "black")
    return c.boxes


def stage_monitor():
    w, h, d = 0.55, 0.35, 0.4
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, 0.12, d, "black")
    c.add(0.0, 0.12, 0.0, w, 0.35, 0.18, "black")
    c.add(0.02, 0.06, 0.18, w - 0.02, 0.32, 0.36, "@grille", rot=(-40, 0, 0), pivot=(w / 2, 0.12, 0.27))   # sloped face
    return c.boxes


def pa_speaker_pole():
    w, h, d = 0.5, 2.0, 0.5
    c = Part(w, h, d)
    _tripod(c, 0.25, 0.25, 0.22, 1.35)
    c.add(0.07, 1.35, 0.12, 0.43, 2.0, 0.42, "black")
    c.add(0.1, 1.4, 0.42, 0.4, 1.82, 0.43, "@grille")
    c.add(0.18, 1.86, 0.42, 0.32, 1.95, 0.43, "steel")                                            # horn
    return c.boxes


def mixing_desk():
    w, h, d = 1.5, 0.95, 0.8
    c = Part(w, h, d)
    for x in (0.05, w - 0.1):                                                                     # stand legs
        c.add(x, 0.0, 0.1, x + 0.05, 0.72, 0.15, "black")
        c.add(x, 0.0, 0.6, x + 0.05, 0.72, 0.65, "black")
    c.add(0.0, 0.72, 0.0, w, 0.82, d, "grey")                                                     # console body
    c.add(0.0, 0.82, 0.0, w, 0.95, 0.2, "grey")                                                   # meter bridge
    c.add(0.05, 0.84, 0.2, w - 0.05, 0.92, 0.21, "screen")                                        # level meters
    for i in range(16):                                                                           # channel strips
        x = 0.08 + i * 0.085
        c.add(x, 0.82, 0.25, x + 0.05, 0.84, 0.7, "black")
        c.add(x + 0.01, 0.84, 0.5 + (i * 7 % 5) * 0.03, x + 0.04, 0.86, 0.53 + (i * 7 % 5) * 0.03, "white")   # fader caps
        c.add(x + 0.015, 0.84, 0.3, x + 0.035, 0.86, 0.32, ["red", "yellow", "blue", "green"][i % 4])          # knobs
    return c.boxes


def studio_monitors():
    w, h, d = 0.8, 0.35, 0.25
    c = Part(w, h, d)
    for x in (0.0, 0.58):
        c.add(x, 0.0, 0.0, x + 0.22, 0.35, d, "black")
        c.add(x + 0.04, 0.05, d, x + 0.18, 0.19, d + 0.005, "@grille")
        c.add(x + 0.07, 0.23, d, x + 0.15, 0.31, d + 0.005, "steel")
        c.add(x + 0.1, 0.02, d, x + 0.12, 0.04, d + 0.005, "screen")
    return c.boxes


def rack_gear():
    w, h, d = 0.6, 1.2, 0.6
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, h, d - 0.02, "black")
    for i in range(7):
        y = 0.1 + i * 0.15
        c.add(0.04, y, d - 0.02, w - 0.04, y + 0.12, d, "steel" if i % 2 else "grey")
        c.add(0.08, y + 0.04, d, 0.14, y + 0.08, d + 0.005, ["screen", "amber", "red"][i % 3])     # LEDs
        c.add(0.3, y + 0.04, d, 0.52, y + 0.08, d + 0.005, "black")
    return c.boxes


def music_stand():
    w, h, d = 0.45, 1.2, 0.4
    c = Part(w, h, d)
    _tripod(c, 0.225, 0.2, 0.18, 0.95)
    c.add(0.0, 0.92, 0.12, w, 1.2, 0.16, "black", rot=(-15, 0, 0), pivot=(0.225, 0.95, 0.2))       # desk
    c.add(0.03, 0.97, 0.16, w - 0.03, 1.18, 0.17, "paper", rot=(-15, 0, 0), pivot=(0.225, 0.95, 0.2))
    c.add(0.0, 0.92, 0.16, w, 0.95, 0.22, "black")                                                  # lip
    return c.boxes


def cable_coil():
    w, h, d = 0.4, 0.06, 0.4
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.05, 0.05, 0.03, 0.35, "black")
    c.add(0.35, 0.0, 0.05, 0.4, 0.03, 0.35, "black")
    c.add(0.05, 0.0, 0.0, 0.35, 0.03, 0.05, "black")
    c.add(0.05, 0.0, 0.35, 0.35, 0.03, 0.4, "black")
    c.add(0.08, 0.03, 0.08, 0.32, 0.06, 0.12, "black")
    c.add(0.08, 0.03, 0.28, 0.32, 0.06, 0.32, "black")
    c.add(0.15, 0.0, 0.18, 0.25, 0.04, 0.22, "steel")                                               # jack
    return c.boxes


def cable_run():
    w, h, d = 1.4, 0.03, 0.15
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.03, w, 0.03, 0.12, "yellow")                                                  # gaffer tape
    c.add(0.0, 0.0, 0.06, w, 0.02, 0.09, "black")
    return c.boxes


def stage_light_rig():
    w, h, d = 3.0, 2.4, 0.4
    c = Part(w, h, d)
    for x in (0.0, w - 0.12):                                                                       # uprights on bases
        c.add(x - 0.1, 0.0, 0.05, x + 0.22, 0.05, 0.35, "black")
        c.add(x, 0.05, 0.14, x + 0.12, 2.3, 0.26, "steel")
    c.add(0.0, 2.25, 0.12, w, 2.4, 0.28, "steel")                                                   # truss
    for i in range(10):
        x = 0.15 + i * 0.28
        c.add(x, 2.27, 0.12, x + 0.03, 2.38, 0.28, "grey")                                          # truss lacing
    for i, col in enumerate(["red", "blue", "amber", "plum"]):                                      # PAR cans
        x = 0.45 + i * 0.6
        c.add(x + 0.07, 2.12, 0.18, x + 0.13, 2.25, 0.22, "black")
        c.add(x, 1.85, 0.1, x + 0.2, 2.12, 0.32, "black", rot=(-25, 0, 0), pivot=(x + 0.1, 2.12, 0.2))
        c.add(x + 0.03, 1.86, 0.32, x + 0.17, 1.98, 0.33, col, rot=(-25, 0, 0), pivot=(x + 0.1, 2.12, 0.2))
    return c.boxes


def acoustic_panel():
    w, h, d = 1.0, 1.0, 0.08
    c = Part(w, h, d)
    for i in range(4):
        for j in range(4):
            kind = "@foam" if (i + j) % 2 == 0 else "@foam2"
            depth = 0.08 if (i + j) % 2 == 0 else 0.05
            c.add(i * 0.25, j * 0.25, 0.0, (i + 1) * 0.25, (j + 1) * 0.25, depth, kind)
    return c.boxes


def guitar_wall_hanger():
    w, h, d = 1.0, 0.8, 0.2
    c = Part(w, h, d)
    c.add(0.0, 0.6, 0.0, w, 0.68, 0.04, "@wood")                                                    # rail
    for i, body in enumerate(["red", "yellow", "teal"]):
        x = 0.17 + i * 0.33
        c.add(x - 0.02, 0.6, 0.04, x + 0.02, 0.66, 0.1, "black")                                    # hook
        c.add(x - 0.03, 0.66, 0.06, x + 0.03, 0.78, 0.1, "dark")                                    # headstock
        c.add(x - 0.02, 0.3, 0.06, x + 0.02, 0.66, 0.1, "dark")                                     # neck
        c.add(x - 0.13, 0.0, 0.05, x + 0.13, 0.16, 0.12, body)                                      # lower bout
        c.add(x - 0.09, 0.16, 0.05, x + 0.09, 0.2, 0.12, body)                                      # waist
        c.add(x - 0.11, 0.2, 0.05, x + 0.11, 0.32, 0.12, body)                                      # upper bout
        c.add(x - 0.06, 0.04, 0.12, x + 0.02, 0.18, 0.125, "white")                                 # pickguard
    return c.boxes


def instrument_cases():
    w, h, d = 1.0, 0.8, 0.6
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, 1.0, 0.18, 0.4, "black")                                                   # keyboard case
    c.add(0.0, 0.18, 0.05, 0.95, 0.32, 0.4, "@case")                                                # guitar case
    c.add(0.9, 0.12, 0.15, 0.95, 0.2, 0.25, "steel")                                                # latch
    c.add(0.55, 0.0, 0.4, 0.95, 0.4, 0.6, "@case")                                                  # snare case
    c.add(0.05, 0.32, 0.1, 0.45, 0.8, 0.35, "black")                                                # upright bass case
    c.add(0.2, 0.55, 0.35, 0.3, 0.6, 0.36, "steel")
    return c.boxes


def on_air_sign():
    w, h, d = 0.6, 0.25, 0.1
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, h, 0.07, "black")
    c.add(0.03, 0.03, 0.07, w - 0.03, h - 0.03, 0.1, "red")
    c.add(0.1, 0.09, 0.1, 0.5, 0.16, 0.105, "white")                                                # "REC" bar
    return c.boxes


SHELLS = ["red", "blue", "black", "white"]
_reg("micStand", mic_stand(), (0.5, 1.6, 0.5))
_reg("podiumMic", podium_mic(), (0.6, 1.15, 0.5), {"@wood": ["walnut", "oak"], "@panel": ["plum", "teal"]})
_reg("deskMic", desk_mic(), (0.15, 0.25, 0.15))
_reg("drumKit", drum_kit(), (1.8, 1.2, 1.5), {"@shell": ["red", "blue", "black"], "@seat": ["black", "red"]})
_reg("electricGuitarStand", electric_guitar_stand(), (0.4, 1.0, 0.35), {"@body": ["red", "black", "yellow", "teal"]})
_reg("acousticGuitarStand", acoustic_guitar_stand(), (0.45, 1.05, 0.35), {"@body": ["pine", "mahogany", "oak"]})
_reg("bassGuitarStand", bass_guitar_stand(), (0.4, 1.15, 0.35), {"@body": ["white", "blue", "walnut"]})
_reg("keyboardStand", keyboard_stand(), (1.3, 0.95, 0.4), {"@body": ["black", "red", "grey"]})
_reg("uprightPianoMusic", upright_piano(), (1.5, 1.25, 0.95), {"@wood": ["black", "walnut", "mahogany"],
                                                              "@panel": ["black", "dark"]})
_reg("ampStack", amp_stack(), (0.75, 1.3, 0.4), {"@grille": ["grey", "linen"]})
_reg("comboAmp", combo_amp(), (0.6, 0.5, 0.3), {"@tolex": ["black", "linen", "teal"], "@grille": ["linen", "grey"]})
_reg("stageMonitor", stage_monitor(), (0.55, 0.35, 0.4), {"@grille": ["grey"]})
_reg("paSpeakerPole", pa_speaker_pole(), (0.5, 2.0, 0.5), {"@grille": ["grey"]})
_reg("mixingDesk", mixing_desk(), (1.5, 0.95, 0.8))
_reg("studioMonitors", studio_monitors(), (0.8, 0.35, 0.25), {"@grille": ["black", "amber"]})
_reg("rackGear", rack_gear(), (0.6, 1.2, 0.6))
_reg("musicStand", music_stand(), (0.45, 1.2, 0.4))
_reg("cableCoil", cable_coil(), (0.4, 0.06, 0.4))
_reg("cableRun", cable_run(), (1.4, 0.03, 0.15))
_reg("stageLightRig", stage_light_rig(), (3.0, 2.4, 0.4))
_reg("acousticPanel", acoustic_panel(), (1.0, 1.0, 0.08), {"@foam": ["grey", "teal", "plum"], "@foam2": ["black", "dark"]})
_reg("guitarWallHanger", guitar_wall_hanger(), (1.0, 0.8, 0.2), {"@wood": ["walnut", "oak"]})
_reg("instrumentCases", instrument_cases(), (1.0, 0.8, 0.6), {"@case": ["black", "dark", "grey"]})
_reg("onAirSign", on_air_sign(), (0.6, 0.25, 0.1))
