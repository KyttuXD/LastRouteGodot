"""Region props (hospital, research lab, greenhouse), authored in metres like blocky_props_rework2.py. exec'd by
build_blocky_props.py after rework3, so PROPS, VARIANTS, Part, VOX, TARGET_SIZE and _reg are in scope.

Every shape is our own design. Front is +z (the side facing into the room), back (z = 0) sits against the wall.
These types have no older model, so the builder takes their footprint from TARGET_SIZE (centred, standing on the floor).
"""


def _bx(c, x0, y0, z0, x1, y1, z1, kind, rot=None, pivot=None):
    c.add(x0, y0, z0, x1, y1, z1, kind, rot, pivot)


def _wheels(c, w, d, inset=0.05, r=0.08, kind="black"):
    for x in (inset, w - inset - 0.05):
        for z in (inset, d - inset - 0.05):
            c.add(x, 0, z, x + 0.05, r, z + 0.05, kind)


# ---- hospital ---------------------------------------------------------------------------------------------------------
def hospital_bed():
    w, h, d = 0.95, 1.05, 2.10
    c = Part(w, h, d)
    _wheels(c, w, d)
    c.add(0.06, 0.08, 0.06, w - 0.06, 0.16, d - 0.06, "steel")                 # chassis
    c.add(0.40, 0.16, 0.5, w - 0.40, 0.42, d - 0.5, "grey")                     # lift column
    c.add(0.04, 0.42, 0.04, w - 0.04, 0.5, d - 0.04, "steel")                   # deck
    c.add(0.06, 0.5, 0.06, w - 0.06, 0.64, d - 0.06, "white")                   # mattress
    c.add(0.08, 0.64, 0.10, w - 0.08, 0.66, d - 0.10, "@sheet")                 # fitted sheet
    c.add(0.06, 0.64, 0.75, w - 0.06, 0.72, d - 0.12, "@blanket")               # folded blanket
    c.add(0.18, 0.64, 0.12, w - 0.18, 0.76, 0.42, "white", (-12, 0, 0), (w / 2, 0.64, 0.12))  # raised pillow
    c.add(0.02, 0.42, 0.0, w - 0.02, 1.05, 0.06, "grey")                        # headboard
    c.add(0.08, 0.9, 0.0, w - 0.08, 0.98, 0.065, "teal")                        # headboard trim
    c.add(0.02, 0.42, d - 0.06, w - 0.02, 0.86, d, "grey")                      # footboard
    c.add(0.25, 0.7, d - 0.065, w - 0.25, 0.8, d - 0.055, "paper")              # chart clip
    for x in (0.0, w - 0.03):                                                    # side rails
        c.add(x, 0.6, 0.30, x + 0.03, 0.82, 0.95, "steel")
        c.add(x, 0.6, 1.15, x + 0.03, 0.62, 1.7, "steel")
    return c.boxes


def hospital_curtain():
    w, h, d = 1.90, 2.40, 0.16
    c = Part(w, h, d)
    c.add(0.0, 2.32, 0.03, w, 2.40, 0.13, "steel")                              # ceiling track
    for x in (0.02, w - 0.07):
        c.add(x, 0, 0.04, x + 0.05, 2.32, 0.12, "steel")                         # end poles
        c.add(x - 0.08, 0, 0.0, x + 0.13, 0.05, 0.16, "black")                   # feet
    folds = 9
    step = (w - 0.14) / folds
    for i in range(folds):
        x0 = 0.07 + i * step
        z0 = 0.05 if i % 2 == 0 else 0.08
        c.add(x0, 0.24, z0, x0 + step, 2.26, z0 + 0.04, "@curtain")            # pleats
    c.add(0.07, 2.18, 0.045, w - 0.07, 2.22, 0.13, "white")                     # mesh band
    return c.boxes


def iv_stand():
    w, h, d = 0.45, 1.95, 0.45
    c = Part(w, h, d)
    c.add(0.02, 0.04, 0.2, w - 0.02, 0.08, 0.25, "steel")
    c.add(0.2, 0.04, 0.02, 0.25, 0.08, d - 0.02, "steel")
    for x, z in ((0.02, 0.2), (w - 0.07, 0.2), (0.2, 0.02), (0.2, d - 0.07)):
        c.add(x, 0, z, x + 0.05, 0.04, z + 0.05, "black")
    c.add(0.2, 0.08, 0.2, 0.25, 1.86, 0.25, "steel")                            # pole
    c.add(0.06, 1.82, 0.2, w - 0.06, 1.86, 0.25, "steel")                       # hook bar
    c.add(0.05, 1.5, 0.17, 0.17, 1.8, 0.28, "glass")                            # saline bag
    c.add(0.28, 1.56, 0.18, 0.39, 1.8, 0.27, "amber")                           # second bag
    c.add(0.1, 1.0, 0.21, 0.12, 1.5, 0.23, "white")                             # line
    c.add(0.2, 1.1, 0.25, 0.3, 1.22, 0.32, "grey")                              # pump
    c.add(0.21, 1.14, 0.32, 0.29, 1.2, 0.33, "screen")
    return c.boxes


def vitals_monitor():
    w, h, d = 0.6, 1.62, 0.55
    c = Part(w, h, d)
    _wheels(c, w, d)
    c.add(0.05, 0.08, 0.05, w - 0.05, 0.14, d - 0.05, "grey")
    c.add(0.1, 0.14, 0.1, w - 0.1, 0.62, d - 0.1, "white")                      # ventilator box
    c.add(0.14, 0.4, d - 0.1, w - 0.14, 0.56, d - 0.09, "screen")
    c.add(0.15, 0.2, d - 0.1, 0.25, 0.3, d - 0.08, "blue")                      # hose ports
    c.add(0.35, 0.2, d - 0.1, 0.45, 0.3, d - 0.08, "blue")
    c.add(0.27, 0.62, 0.25, 0.33, 1.2, 0.31, "steel")                           # pole
    c.add(0.04, 1.2, 0.12, w - 0.04, 1.58, 0.44, "grey")                        # monitor shell
    c.add(0.07, 1.24, 0.44, w - 0.07, 1.54, 0.45, "black")
    c.add(0.09, 1.44, 0.445, w - 0.09, 1.46, 0.455, "green")                    # ECG trace
    c.add(0.09, 1.36, 0.445, 0.3, 1.38, 0.455, "yellow")
    c.add(0.33, 1.28, 0.445, 0.5, 1.34, 0.455, "red")
    c.add(0.24, 1.58, 0.2, 0.36, 1.62, 0.36, "red")                             # alarm light
    return c.boxes


def nurses_station():
    w, h, d = 2.4, 1.18, 0.95
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.74, 0.62, "white")                                  # back desk
    c.add(0.0, 0.74, 0.0, w, 0.78, 0.66, "grey")                                # work top
    c.add(0.0, 0, 0.66, w, 1.1, d, "teal")                                      # front counter wall
    c.add(-0.0, 1.1, 0.6, w, 1.18, d, "white")                                  # raised ledge
    c.add(0.1, 0.12, d - 0.005, w - 0.1, 0.18, d, "white")                      # kick stripe
    for x in (0.3, 1.25):                                                        # two screens
        c.add(x, 0.78, 0.12, x + 0.5, 0.8, 0.3, "black")
        c.add(x + 0.22, 0.8, 0.14, x + 0.28, 0.9, 0.2, "black")
        c.add(x, 0.9, 0.1, x + 0.5, 1.2, 0.14, "black")
        c.add(x + 0.03, 0.93, 0.14, x + 0.47, 1.17, 0.145, "screen")
    c.add(1.95, 0.78, 0.08, 2.3, 1.0, 0.4, "@sheet")                           # chart rack
    for i in range(4):
        c.add(1.97, 0.8 + i * 0.05, 0.1, 2.28, 0.83 + i * 0.05, 0.38, ["blue", "red", "yellow", "green"][i])
    c.add(0.85, 0.78, 0.4, 1.1, 0.84, 0.55, "black")                            # phone
    c.add(0.05, 1.18, 0.7, 0.18, 1.3, 0.85, "red")                              # call light
    return c.boxes


def waiting_chairs():
    w, h, d = 2.0, 0.86, 0.62
    c = Part(w, h, d)
    for x in (0.1, w - 0.16):
        c.add(x, 0, 0.1, x + 0.06, 0.38, 0.5, "steel")                          # legs
    c.add(0.0, 0.34, 0.25, w, 0.38, 0.33, "steel")                              # beam
    for i in range(3):
        x0 = 0.04 + i * 0.66
        c.add(x0, 0.38, 0.08, x0 + 0.58, 0.45, 0.56, "@seat")                   # seat
        c.add(x0, 0.45, 0.04, x0 + 0.58, 0.86, 0.1, "@seat", (-10, 0, 0), (x0 + 0.29, 0.45, 0.07))
        if i < 2:
            c.add(x0 + 0.6, 0.38, 0.12, x0 + 0.64, 0.62, 0.5, "black")          # armrests
    return c.boxes


def operating_table():
    w, h, d = 0.75, 1.0, 2.0
    c = Part(w, h, d)
    c.add(0.1, 0, 0.55, w - 0.1, 0.1, 1.45, "steel")                            # base plate
    c.add(0.25, 0.1, 0.8, w - 0.25, 0.72, 1.2, "white")                         # column
    c.add(0.05, 0.72, 0.05, w - 0.05, 0.8, d - 0.05, "steel")                   # frame
    c.add(0.07, 0.8, 0.1, w - 0.07, 0.9, d - 0.1, "teal")                       # pad
    c.add(0.22, 0.8, 0.0, w - 0.22, 0.88, 0.12, "teal")                         # headrest
    for x in (-0.0, w - 0.05):
        c.add(x, 0.78, 0.6, x + 0.05, 0.84, 1.4, "steel")                       # side rails
    c.add(-0.0, 0.8, 0.75, 0.08, 0.86, 1.1, "teal")                             # arm board
    c.add(0.05, 0.9, 0.5, w - 0.05, 0.92, 1.6, "linen")                         # drape
    c.add(w - 0.12, 0.84, d - 0.2, w - 0.02, 1.0, d - 0.1, "black")             # foot control
    return c.boxes


def surgical_light():
    w, h, d = 1.5, 0.9, 1.5
    c = Part(w, h, d)
    c.add(0.7, 0.82, 0.7, 0.8, 0.9, 0.8, "steel")                               # ceiling mount
    c.add(0.72, 0.6, 0.72, 0.78, 0.82, 0.78, "steel")
    c.add(0.15, 0.56, 0.72, 1.35, 0.62, 0.78, "steel")                          # boom arms
    for x0 in (0.0, 0.85):
        c.add(x0 + 0.24, 0.36, 0.57, x0 + 0.41, 0.56, 0.93, "steel")            # yokes
        c.add(x0 + 0.04, 0.24, 0.45, x0 + 0.61, 0.38, 1.05, "white")            # dome
        c.add(x0 + 0.1, 0.2, 0.51, x0 + 0.55, 0.24, 0.99, "amber")              # lamp face
        c.add(x0 + 0.27, 0.16, 0.7, x0 + 0.38, 0.2, 0.8, "steel")               # handle
    return c.boxes


def instrument_trolley():
    w, h, d = 0.9, 0.95, 0.55
    c = Part(w, h, d)
    _wheels(c, w, d)
    for x in (0.04, w - 0.08):
        for z in (0.04, d - 0.08):
            c.add(x, 0.08, z, x + 0.04, 0.9, z + 0.04, "steel")
    c.add(0.03, 0.3, 0.03, w - 0.03, 0.33, d - 0.03, "steel")
    c.add(0.03, 0.86, 0.03, w - 0.03, 0.9, d - 0.03, "steel")
    c.add(0.06, 0.9, 0.06, w - 0.06, 0.92, d - 0.06, "teal")                    # sterile drape
    for i, x in enumerate((0.12, 0.22, 0.32, 0.42, 0.52)):
        c.add(x, 0.92, 0.15, x + 0.03, 0.93, 0.4, "mirror")                     # instruments
    c.add(0.62, 0.92, 0.12, 0.82, 0.98, 0.42, "steel")                          # kidney tray
    c.add(0.1, 0.33, 0.1, 0.45, 0.45, 0.45, "white")                            # boxed supplies
    c.add(0.5, 0.33, 0.12, 0.8, 0.41, 0.42, "blue")
    return c.boxes


def morgue_cabinet():
    w, h, d = 2.0, 2.1, 0.95
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, 2.1, 0.8, "steel")                                 # body
    c.add(0.0, 0.0, 0.8, w, 0.12, 0.84, "black")                                # plinth
    for row in range(3):
        for col in range(2):
            x0 = 0.06 + col * 0.98
            y0 = 0.16 + row * 0.64
            c.add(x0, y0, 0.8, x0 + 0.9, y0 + 0.58, 0.84, "grey")               # drawer door
            c.add(x0 + 0.35, y0 + 0.24, 0.84, x0 + 0.55, y0 + 0.3, 0.9, "mirror")   # latch
            c.add(x0 + 0.06, y0 + 0.44, 0.84, x0 + 0.26, y0 + 0.52, 0.845, "paper")  # name card
    c.add(0.06, 0.16, 0.84, 0.96, 0.24, d, "steel")                             # one tray pulled out
    c.add(0.1, 0.24, 0.84, 0.92, 0.3, d, "white")                               # sheet
    c.add(0.0, 2.0, 0.0, w, 2.1, 0.86, "grey")                                  # cornice
    c.add(0.85, 1.98, 0.86, 1.15, 2.06, 0.87, "screen")                         # temperature readout
    return c.boxes


def autopsy_table():
    w, h, d = 0.85, 0.95, 2.0
    c = Part(w, h, d)
    c.add(0.25, 0, 0.75, w - 0.25, 0.7, 1.25, "steel")                          # pedestal
    c.add(0.15, 0, 0.65, w - 0.15, 0.06, 1.35, "grey")
    c.add(0.0, 0.7, 0.0, w, 0.8, d, "steel")                                    # slab
    for x in (0.0, w - 0.04):
        c.add(x, 0.8, 0.0, x + 0.04, 0.86, d, "mirror")                         # lips
    c.add(0.0, 0.8, d - 0.04, w, 0.86, d, "mirror")
    c.add(0.35, 0.8, d - 0.2, 0.5, 0.81, d - 0.05, "black")                     # drain
    c.add(0.1, 0.8, 0.12, w - 0.1, 0.9, 1.6, "white")                           # sheet over the slab
    c.add(0.25, 0.9, 0.18, w - 0.25, 0.95, 0.45, "white")
    c.add(0.0, 0.86, 0.0, 0.12, 0.95, 0.1, "steel")                             # tap
    return c.boxes


def pharmacy_shelf():
    w, h, d = 1.6, 2.0, 0.45
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, h, 0.03, "white")                                     # back panel
    for x in (0.0, w - 0.04):
        c.add(x, 0, 0.0, x + 0.04, h, d, "white")
    colours = ["blue", "red", "white", "yellow", "green", "teal", "paper", "amber"]
    for s in range(5):
        y = 0.05 + s * 0.39
        c.add(0.04, y, 0.03, w - 0.04, y + 0.03, d, "grey")
        x = 0.07
        i = s * 3
        while x < w - 0.18:
            bw = 0.1 + (i % 3) * 0.04
            c.add(x, y + 0.03, 0.08, x + bw, y + 0.17 + (i % 2) * 0.08, d - 0.05, colours[i % len(colours)])
            x += bw + 0.03
            i += 1
    return c.boxes


def xray_machine():
    w, h, d = 1.6, 2.2, 1.5
    c = Part(w, h, d)
    c.add(0.2, 0, 0.75, 1.4, 0.65, 1.2, "white")                               # table base
    c.add(0.0, 0.65, 0.65, w, 0.75, 1.3, "grey")                                # table top
    c.add(0.05, 0.75, 0.7, w - 0.05, 0.8, 1.25, "black")                        # detector tray
    c.add(0.1, 0, 0.05, 0.35, 2.2, 0.3, "white")                                # column
    c.add(0.35, 1.7, 0.1, 1.05, 1.82, 0.25, "grey")                             # arm
    c.add(0.8, 1.35, 0.85, 1.25, 1.7, 0.6, "white", None, None)
    c.add(0.8, 1.35, 0.6, 1.25, 1.7, 0.95, "white")                             # tube head
    c.add(0.85, 1.25, 0.65, 1.2, 1.35, 0.9, "black")                            # collimator
    c.add(0.95, 1.255, 0.7, 1.1, 1.26, 0.85, "amber")                           # light field
    c.add(0.9, 1.7, 0.25, 1.05, 1.82, 0.6, "grey")                              # arm to head
    c.add(0.12, 1.1, 0.3, 0.33, 1.3, 0.32, "yellow")                            # radiation label
    return c.boxes


def xray_lightbox():
    w, h, d = 1.3, 0.85, 0.08
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, h, 0.05, "grey")
    for i in range(3):
        x0 = 0.05 + i * 0.41
        c.add(x0, 0.06, 0.05, x0 + 0.38, 0.79, 0.06, "white")                   # lit panel
        c.add(x0 + 0.05, 0.12, 0.06, x0 + 0.33, 0.73, 0.065, "black")           # film
        c.add(x0 + 0.12, 0.22, 0.065, x0 + 0.26, 0.64, 0.07, "glass")           # bones
        for y in (0.3, 0.4, 0.5):
            c.add(x0 + 0.08, y, 0.065, x0 + 0.3, y + 0.025, 0.07, "glass")       # ribs
    return c.boxes


def supply_rack():
    w, h, d = 1.2, 1.9, 0.5
    c = Part(w, h, d)
    for x in (0.0, w - 0.03):
        for z in (0.0, d - 0.03):
            c.add(x, 0, z, x + 0.03, h, z + 0.03, "steel")
    stock = [("white", "blue"), ("teal", "white"), ("paper", "yellow"), ("blue", "white")]
    for s in range(4):
        y = 0.1 + s * 0.48
        c.add(0.0, y, 0.0, w, y + 0.03, d, "steel")
        a, b = stock[s]
        c.add(0.06, y + 0.03, 0.05, 0.5, y + 0.25, d - 0.05, a)                 # linen stack / boxes
        c.add(0.58, y + 0.03, 0.05, 0.9, y + 0.18, d - 0.08, b)
        c.add(0.95, y + 0.03, 0.1, 1.14, y + 0.3, d - 0.1, "porcelain")
    return c.boxes


def wheelchair():
    w, h, d = 0.65, 0.95, 0.95
    c = Part(w, h, d)
    for x in (0.0, w - 0.05):
        c.add(x, 0, 0.12, x + 0.05, 0.6, 0.72, "black")                         # big wheels
        c.add(x + 0.01, 0.05, 0.17, x + 0.04, 0.55, 0.67, "steel")              # hand rims
    for x in (0.1, w - 0.15):
        c.add(x, 0, d - 0.12, x + 0.05, 0.12, d - 0.07, "black")                # casters
        c.add(x, 0.12, d - 0.12, x + 0.05, 0.48, d - 0.07, "steel")
    c.add(0.06, 0.42, 0.2, w - 0.06, 0.5, 0.7, "@seat")                         # seat
    c.add(0.06, 0.5, 0.12, w - 0.06, 0.92, 0.2, "@seat", (-8, 0, 0), (w / 2, 0.5, 0.16))   # back
    for x in (0.06, w - 0.1):
        c.add(x, 0.5, 0.1, x + 0.04, 0.95, 0.14, "steel")                       # push handles
        c.add(x, 0.66, 0.22, x + 0.04, 0.7, 0.62, "black")                      # arms
    c.add(0.12, 0.08, d - 0.06, w - 0.12, 0.12, d, "steel")                     # foot plates
    return c.boxes


def medical_sign():
    w, h, d = 0.95, 0.36, 0.06
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, h, 0.04, "@sign")
    c.add(0.06, 0.08, 0.04, 0.28, 0.28, 0.05, "white")                          # cross plate
    c.add(0.14, 0.11, 0.05, 0.2, 0.25, 0.055, "red")
    c.add(0.1, 0.15, 0.05, 0.24, 0.21, 0.055, "red")
    for i in range(4):
        c.add(0.34 + i * 0.14, 0.14, 0.04, 0.44 + i * 0.14, 0.22, 0.05, "white")   # lettering
    return c.boxes


_reg("hospitalBed", hospital_bed(), (0.95, 1.05, 2.10), {"@sheet": ["white", "porcelain", "linen"],
                                                        "@blanket": ["teal", "blue", "linen"]})
_reg("hospitalCurtain", hospital_curtain(), (1.90, 2.40, 0.16), {"@curtain": ["teal", "linen", "blue"]})
_reg("ivDripStand", iv_stand(), (0.45, 1.95, 0.45))
_reg("vitalsMonitor", vitals_monitor(), (0.60, 1.62, 0.55))
_reg("nursesStation", nurses_station(), (2.40, 1.18, 0.95), {"@sheet": ["white", "porcelain"]})
_reg("waitingChairs", waiting_chairs(), (2.00, 0.86, 0.62), {"@seat": ["teal", "blue", "grey"]})
_reg("operatingTable", operating_table(), (0.75, 1.00, 2.00))
_reg("surgicalLight", surgical_light(), (1.50, 0.90, 1.50))
_reg("instrumentTrolley", instrument_trolley(), (0.90, 0.95, 0.55))
_reg("morgueCabinet", morgue_cabinet(), (2.00, 2.10, 0.95))
_reg("autopsyTable", autopsy_table(), (0.85, 0.95, 2.00))
_reg("pharmacyShelf", pharmacy_shelf(), (1.60, 2.00, 0.45))
_reg("xrayMachine", xray_machine(), (1.60, 2.20, 1.50))
_reg("xrayLightbox", xray_lightbox(), (1.30, 0.85, 0.08))
_reg("medicalSupplyRack", supply_rack(), (1.20, 1.90, 0.50))
_reg("wheelchair", wheelchair(), (0.65, 0.95, 0.95), {"@seat": ["blue", "black", "teal"]})
_reg("hospitalWardSign", medical_sign(), (0.95, 0.36, 0.06), {"@sign": ["blue", "teal", "green"]})


# ---- research lab -----------------------------------------------------------------------------------------------------
def lab_bench():
    w, h, d = 2.0, 1.45, 0.8
    c = Part(w, h, d)
    c.add(0.0, 0, 0.05, w, 0.86, d - 0.02, "white")                             # cabinets
    for i in range(4):
        x0 = 0.03 + i * 0.49
        c.add(x0, 0.1, d - 0.02, x0 + 0.46, 0.82, d, "porcelain")               # doors
        c.add(x0 + 0.18, 0.7, d - 0.03, x0 + 0.28, 0.74, d - 0.0, "steel")      # pulls
    c.add(0.0, 0, 0.05, w, 0.08, d - 0.04, "black")                             # kick
    c.add(-0.0, 0.86, 0.0, w, 0.92, d, "black")                                 # epoxy top
    c.add(0.0, 0.92, 0.0, w, 1.45, 0.08, "grey")                                # riser
    c.add(0.0, 1.2, 0.08, w, 1.23, 0.3, "steel")                                # reagent shelf
    c.add(1.5, 0.9, 0.3, 1.85, 0.92, 0.65, "steel")                             # sink
    c.add(1.64, 0.92, 0.1, 1.68, 1.12, 0.14, "steel")
    c.add(1.64, 1.08, 0.14, 1.68, 1.12, 0.3, "steel")                           # gooseneck
    bottles = ["amber", "glass", "green", "glass", "blue", "amber", "glass", "red"]
    for i, k in enumerate(bottles):
        x0 = 0.08 + i * 0.23
        c.add(x0, 1.23, 0.12, x0 + 0.08, 1.23 + 0.12 + (i % 3) * 0.04, 0.22, k)
    c.add(0.15, 0.92, 0.3, 0.45, 0.94, 0.6, "steel")                            # tray
    for x0, k in ((0.18, "green"), (0.26, "glass"), (0.34, "teal")):
        c.add(x0, 0.94, 0.38, x0 + 0.06, 1.06, 0.44, k)                         # flasks
    c.add(0.6, 0.92, 0.25, 0.95, 1.05, 0.6, "grey")                             # balance
    c.add(0.65, 1.05, 0.3, 0.9, 1.06, 0.55, "steel")
    c.add(1.05, 0.92, 0.2, 1.35, 1.12, 0.45, "white")                           # analyser
    c.add(1.08, 1.0, 0.45, 1.32, 1.08, 0.46, "screen")
    return c.boxes


def fume_hood():
    w, h, d = 1.5, 2.35, 0.9
    c = Part(w, h, d)
    c.add(0.0, 0, 0.05, w, 0.86, d, "white")                                    # base cabinet
    c.add(0.0, 0.86, 0.0, w, 0.9, d, "black")                                   # work surface
    for x in (0.0, w - 0.08):
        c.add(x, 0.9, 0.0, x + 0.08, 2.05, d, "white")                          # side walls
    c.add(0.0, 0.9, 0.0, w, 2.05, 0.06, "grey")                                 # back baffle
    c.add(0.0, 1.85, 0.0, w, 2.05, d, "white")                                  # header
    c.add(0.08, 1.2, d - 0.05, w - 0.08, 1.85, d - 0.02, "glass")               # sash
    c.add(0.08, 1.16, d - 0.06, w - 0.08, 1.2, d, "steel")                      # sash handle
    c.add(0.15, 1.88, d - 0.01, 0.45, 1.98, d, "screen")
    c.add(1.05, 1.9, d - 0.01, 1.15, 1.96, d, "green")
    c.add(0.45, 2.05, 0.2, 1.05, 2.35, 0.7, "steel")                            # duct
    c.add(0.3, 0.9, 0.3, 0.42, 1.1, 0.42, "amber")                              # glassware inside
    c.add(0.6, 0.9, 0.25, 0.9, 1.0, 0.5, "steel")
    c.add(1.0, 0.9, 0.3, 1.1, 1.18, 0.4, "glass")
    return c.boxes


def specimen_tank():
    w, h, d = 0.95, 2.3, 0.95
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.32, d, "steel")                                     # base
    c.add(0.04, 0.12, d - 0.01, w - 0.04, 0.2, d, "yellow")
    c.add(0.1, 0.2, d - 0.01, 0.4, 0.28, d, "screen")
    c.add(0.1, 0.32, 0.1, w - 0.1, 1.95, 0.16, "@fluid")                        # fluid column: back and sides
    for x in (0.1, w - 0.16):
        c.add(x, 0.32, 0.16, x + 0.06, 1.95, d - 0.1, "@fluid")
    c.add(0.16, 0.32, 0.16, w - 0.16, 0.5, d - 0.1, "@fluid")                   # settled fluid at the base
    c.add(0.1, 0.32, d - 0.16, w - 0.1, 0.6, d - 0.1, "@fluid")                 # front glass bands
    c.add(0.1, 1.75, d - 0.16, w - 0.1, 1.95, d - 0.1, "@fluid")
    c.add(0.45, 0.6, d - 0.14, 0.5, 1.75, d - 0.11, "steel")                    # front glass mullion
    for x in (0.06, w - 0.12):
        for z in (0.06, d - 0.12):
            c.add(x, 0.32, z, x + 0.06, 1.95, z + 0.06, "steel")               # frame posts
    c.add(0.36, 0.7, 0.36, 0.59, 1.5, 0.59, "plum")                             # specimen
    c.add(0.3, 1.25, 0.32, 0.65, 1.45, 0.63, "plum")
    c.add(0.4, 1.5, 0.4, 0.55, 1.68, 0.55, "plum")
    for y in (0.5, 0.9, 1.3, 1.7):
        c.add(0.42, y, 0.42, 0.47, y + 0.04, 0.47, "white")                     # bubbles
    c.add(0.0, 1.95, 0.0, w, 2.15, d, "steel")                                  # cap
    c.add(0.3, 2.15, 0.3, 0.42, 2.3, 0.42, "grey")                              # feed pipes
    c.add(0.55, 2.15, 0.5, 0.67, 2.3, 0.62, "grey")
    c.add(0.15, 2.0, d - 0.01, 0.8, 2.08, d, "yellow")
    return c.boxes


def containment_cell():
    w, h, d = 2.2, 2.6, 1.7
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.12, d, "steel")                                     # floor plate
    for i in range(11):                                                          # hazard stripes on the sill
        x0 = i * 0.2
        c.add(x0, 0.12, d - 0.06, x0 + 0.1, 0.2, d, "yellow")
        c.add(x0 + 0.1, 0.12, d - 0.06, x0 + 0.2, 0.2, d, "black")
    for x in (0.0, w - 0.1):
        for z in (0.0, d - 0.1):
            c.add(x, 0.12, z, x + 0.1, 2.5, z + 0.1, "grey")                    # corner posts
    c.add(0.1, 0.2, d - 0.08, 1.05, 2.4, d - 0.04, "glass")                     # front glass
    c.add(1.15, 0.2, d - 0.08, w - 0.1, 2.4, d - 0.04, "glass")                 # door glass
    c.add(1.05, 0.12, d - 0.1, 1.15, 2.5, d, "grey")                            # door jamb
    c.add(1.2, 1.1, d - 0.03, 1.3, 1.4, d, "red")                               # lock panel
    for x in (0.0, w - 0.06):
        c.add(x, 0.2, 0.1, x + 0.06, 2.4, d - 0.1, "glass")                     # side glass
    c.add(0.1, 0.12, 0.0, w - 0.1, 2.5, 0.08, "grey")                           # back wall
    c.add(0.0, 2.4, 0.0, w, 2.6, d, "grey")                                     # roof
    c.add(0.4, 2.42, d - 0.01, 1.8, 2.54, d, "amber")                           # status strip
    c.add(0.2, 0.12, 0.2, 0.9, 0.5, 0.8, "white")                               # cot inside
    c.add(1.4, 0.12, 0.2, 1.9, 0.9, 0.5, "steel")
    return c.boxes


def cooling_unit():
    w, h, d = 1.0, 2.1, 0.85
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 2.1, d, "white")
    for i in range(8):
        c.add(0.08, 0.15 + i * 0.1, d - 0.01, w - 0.08, 0.2 + i * 0.1, d, "grey")   # intake louvres
    c.add(0.25, 1.4, d - 0.01, 0.75, 1.7, d, "black")
    c.add(0.28, 1.45, d - 0.012, 0.72, 1.65, d - 0.0, "screen")
    c.add(0.1, 1.9, d - 0.01, 0.9, 2.0, d, "blue")
    c.add(0.0, 0, d - 0.02, w, 0.1, d, "black")
    return c.boxes


def control_console():
    w, h, d = 2.4, 1.4, 1.0
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.72, 0.7, "grey")                                    # desk body
    c.add(0.0, 0.72, 0.0, w, 0.78, d, "black")                                  # desk top
    c.add(0.1, 0.78, 0.55, w - 0.1, 0.84, 0.9, "steel", (12, 0, 0), (w / 2, 0.78, 0.72))   # sloped control deck
    for i in range(10):
        c.add(0.2 + i * 0.2, 0.84, 0.62, 0.28 + i * 0.2, 0.87, 0.7, ["red", "green", "amber", "blue"][i % 4])
    c.add(1.0, 0.79, 0.78, 1.4, 0.82, 0.92, "black")                            # keyboard
    for i, ang in enumerate((25, 0, -25)):                                       # three angled screens
        x0 = 0.1 + i * 0.75
        pv = (x0 + 0.35, 0.8, 0.3)
        c.add(x0 + 0.3, 0.78, 0.25, x0 + 0.4, 0.92, 0.33, "black")
        c.add(x0, 0.92, 0.22, x0 + 0.7, 1.38, 0.27, "black", (0, ang, 0), pv)
        c.add(x0 + 0.03, 0.95, 0.27, x0 + 0.67, 1.35, 0.275, "screen", (0, ang, 0), pv)
    c.add(2.15, 0.78, 0.1, 2.3, 0.98, 0.25, "red")                              # alarm button housing
    return c.boxes


def monitor_wall():
    w, h, d = 2.4, 1.4, 0.1
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, h, 0.05, "black")
    for row in range(3):
        for col in range(4):
            x0 = 0.04 + col * 0.59
            y0 = 0.04 + row * 0.45
            c.add(x0, y0, 0.05, x0 + 0.55, y0 + 0.41, 0.06, "screen" if (row + col) % 3 else "green")
            c.add(x0 + 0.05, y0 + 0.05, 0.06, x0 + 0.3, y0 + 0.08, 0.065, "white")   # readouts
    c.add(0.9, 1.3, 0.06, 1.5, 1.38, 0.07, "red")
    return c.boxes


def decon_shower():
    w, h, d = 1.3, 2.5, 1.3
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.1, d, "steel")                                      # grate tray
    for i in range(6):
        c.add(0.1 + i * 0.19, 0.1, 0.1, 0.16 + i * 0.19, 0.11, d - 0.1, "black")
    for x in (0.0, w - 0.08):
        for z in (0.0, d - 0.08):
            c.add(x, 0.1, z, x + 0.08, 2.4, z + 0.08, "yellow")                 # posts
    c.add(0.0, 2.4, 0.0, w, 2.5, d, "yellow")                                   # roof frame
    c.add(0.08, 2.38, 0.08, w - 0.08, 2.4, d - 0.08, "steel")
    c.add(0.08, 0.1, 0.0, w - 0.08, 2.4, 0.05, "glass")                         # back pane
    for x in (0.0, w - 0.05):
        c.add(x, 0.1, 0.08, x + 0.05, 2.4, d - 0.08, "glass")                   # side panes
    for x0 in (0.25, 0.85):                                                      # shower heads
        c.add(x0, 2.2, 0.55, x0 + 0.2, 2.26, 0.75, "steel")
        c.add(x0 + 0.08, 2.26, 0.62, x0 + 0.12, 2.38, 0.68, "steel")
    c.add(0.5, 1.2, 0.05, 0.8, 1.4, 0.08, "red")                                # pull handle
    c.add(0.0, 2.32, d - 0.01, w, 2.4, d, "black")
    return c.boxes


def cold_storage():
    w, h, d = 1.4, 2.1, 0.85
    c = Part(w, h, d)
    c.add(0.0, 0.1, 0.0, w, 2.1, d - 0.04, "white")
    c.add(0.0, 0, 0.05, w, 0.1, d - 0.08, "black")
    for x0 in (0.03, 0.71):
        c.add(x0, 0.14, d - 0.04, x0 + 0.66, 1.78, d, "porcelain")              # doors
        c.add(x0 + 0.1, 0.9, d - 0.01, x0 + 0.5, 1.5, d + 0.004, "glass")       # frosted window
    c.add(0.1, 1.84, d - 0.03, 0.7, 2.02, d, "black")
    c.add(0.13, 1.87, d - 0.031, 0.5, 1.99, d - 0.0, "blue")                    # -80 readout
    c.add(0.9, 1.86, d - 0.03, 1.3, 2.0, d, "steel")                            # vent
    c.add(0.0, 0.14, d - 0.04, 0.03, 1.78, d, "teal")
    return c.boxes


def whiteboard():
    w, h, d = 1.8, 1.15, 0.08
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, h, 0.03, "steel")
    c.add(0.04, 0.04, 0.03, w - 0.04, h - 0.04, 0.04, "white")
    for x0, y0, x1, y1, k in ((0.15, 0.85, 0.9, 0.88, "blue"), (0.15, 0.75, 0.6, 0.78, "blue"),
                              (0.2, 0.3, 0.24, 0.65, "red"), (0.2, 0.3, 0.7, 0.34, "red"),
                              (0.3, 0.45, 0.4, 0.5, "red"), (0.45, 0.52, 0.55, 0.57, "red"),
                              (0.6, 0.6, 0.68, 0.64, "red"), (1.0, 0.4, 1.6, 0.9, "blue"),
                              (1.05, 0.45, 1.55, 0.85, "white"), (1.2, 0.55, 1.4, 0.75, "green")):
        c.add(x0, y0, 0.04, x1, y1, 0.045, k)                                    # notes and a chart
    c.add(0.1, 0.0, 0.03, w - 0.1, 0.03, 0.08, "steel")                         # marker tray
    c.add(0.3, 0.03, 0.04, 0.42, 0.05, 0.07, "red")
    c.add(0.5, 0.03, 0.04, 0.62, 0.05, 0.07, "blue")
    return c.boxes


def hazard_sign():
    w, h, d = 0.6, 0.62, 0.05
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, 0.04, 0.03, "black")
    for i in range(7):                                                           # stepped triangle
        inset = i * 0.04
        c.add(0.02 + inset, 0.04 + i * 0.08, 0.0, w - 0.02 - inset, 0.12 + i * 0.08, 0.03, "@hazard")
    c.add(0.27, 0.16, 0.03, 0.33, 0.36, 0.04, "black")                          # exclamation
    c.add(0.27, 0.08, 0.03, 0.33, 0.13, 0.04, "black")
    return c.boxes


def glass_partition():
    w, h, d = 1.95, 2.5, 0.14
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.22, d, "grey")                                      # base rail
    for i in range(10):
        c.add(i * 0.195, 0.08, d - 0.005, i * 0.195 + 0.0975, 0.16, d, "yellow")   # hazard stripes
    for x in (0.0, w - 0.06):
        c.add(x, 0.22, 0.0, x + 0.06, h, d, "steel")                            # mullions
    c.add(0.9, 0.22, 0.0, 0.96, h, d, "steel")
    c.add(0.0, h - 0.08, 0.0, w, h, d, "steel")                                 # head rail
    c.add(0.06, 0.22, 0.05, 0.9, h - 0.08, 0.09, "glass")
    c.add(0.96, 0.22, 0.05, w - 0.06, h - 0.08, 0.09, "glass")
    c.add(0.06, 1.3, 0.04, 0.9, 1.36, 0.1, "white")                             # manifestation band
    c.add(0.96, 1.3, 0.04, w - 0.06, 1.36, 0.1, "white")
    return c.boxes


def lab_stool():
    w, h, d = 0.42, 0.75, 0.42
    c = Part(w, h, d)
    for x, z in ((0.0, 0.18), (0.36, 0.18), (0.18, 0.0), (0.18, 0.36)):
        c.add(x, 0, z, x + 0.06, 0.04, z + 0.06, "black")
    c.add(0.0, 0.04, 0.18, w, 0.07, 0.24, "steel")
    c.add(0.18, 0.04, 0.0, 0.24, 0.07, d, "steel")
    c.add(0.18, 0.07, 0.18, 0.24, 0.66, 0.24, "steel")                          # gas lift
    c.add(0.06, 0.3, 0.06, 0.36, 0.33, 0.36, "steel")                           # foot ring
    c.add(0.02, 0.66, 0.02, 0.4, 0.75, 0.4, "@seat")
    return c.boxes


def microscope():
    w, h, d = 0.34, 0.46, 0.36
    c = Part(w, h, d)
    c.add(0.04, 0, 0.0, 0.3, 0.05, 0.3, "white")                                # foot
    c.add(0.12, 0.05, 0.0, 0.22, 0.38, 0.1, "white")                            # arm
    c.add(0.06, 0.15, 0.1, 0.28, 0.18, 0.3, "black")                            # stage
    c.add(0.13, 0.18, 0.15, 0.21, 0.19, 0.25, "glass")                          # slide
    c.add(0.13, 0.22, 0.12, 0.21, 0.4, 0.2, "black", (20, 0, 0), (0.17, 0.3, 0.16))   # tube
    c.add(0.14, 0.38, 0.06, 0.2, 0.46, 0.12, "black", (-30, 0, 0), (0.17, 0.42, 0.09))  # eyepiece
    c.add(0.13, 0.18, 0.05, 0.21, 0.24, 0.1, "steel")                           # nosepiece
    return c.boxes


def gas_cylinders():
    w, h, d = 0.95, 1.65, 0.45
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.06, d, "steel")
    c.add(0.0, 0.06, 0.0, w, 1.3, 0.04, "steel")                                # back frame
    for x0, k in ((0.05, "green"), (0.35, "grey"), (0.65, "blue")):
        c.add(x0, 0.06, 0.08, x0 + 0.25, 1.4, 0.33, k)                          # cylinder
        c.add(x0 + 0.06, 1.4, 0.14, x0 + 0.19, 1.5, 0.27, k)                    # shoulder
        c.add(x0 + 0.09, 1.5, 0.17, x0 + 0.16, 1.62, 0.24, "brass")             # valve
        c.add(x0 + 0.02, 1.0, 0.33, x0 + 0.23, 1.06, 0.34, "white")             # label
    c.add(0.0, 0.95, 0.04, w, 0.99, 0.38, "black")                              # restraint chain
    return c.boxes


def biohazard_bin():
    w, h, d = 0.5, 0.82, 0.5
    c = Part(w, h, d)
    c.add(0.04, 0, 0.04, w - 0.04, 0.72, d - 0.04, "red")
    c.add(0.02, 0.72, 0.02, w - 0.02, 0.8, d - 0.02, "red")                     # lid
    c.add(0.12, 0.8, 0.2, 0.38, 0.82, 0.3, "black")
    c.add(0.12, 0.3, d - 0.04, 0.38, 0.56, d - 0.03, "yellow")                  # symbol plate
    c.add(0.21, 0.38, d - 0.03, 0.29, 0.48, d - 0.02, "black")
    c.add(0.15, 0.0, d - 0.06, 0.35, 0.05, d, "black")                          # pedal
    return c.boxes


_reg("labBench", lab_bench(), (2.0, 1.45, 0.8))
_reg("fumeHood", fume_hood(), (1.5, 2.35, 0.9))
_reg("specimenTank", specimen_tank(), (0.95, 2.3, 0.95), {"@fluid": ["teal", "green", "water"]})
_reg("containmentCell", containment_cell(), (2.2, 2.6, 1.7))
_reg("labCoolingUnit", cooling_unit(), (1.0, 2.1, 0.85))
_reg("controlConsole", control_console(), (2.4, 1.4, 1.0))
_reg("monitorWall", monitor_wall(), (2.4, 1.4, 0.1))
_reg("deconShower", decon_shower(), (1.3, 2.5, 1.3))
_reg("coldStorageUnit", cold_storage(), (1.4, 2.1, 0.85))
_reg("labWhiteboard", whiteboard(), (1.8, 1.15, 0.08))
_reg("hazardSign", hazard_sign(), (0.6, 0.62, 0.05), {"@hazard": ["yellow", "amber"]})
_reg("labGlassPartition", glass_partition(), (1.95, 2.5, 0.14))
_reg("labStool", lab_stool(), (0.42, 0.75, 0.42), {"@seat": ["black", "blue", "grey"]})
_reg("labMicroscope", microscope(), (0.34, 0.46, 0.36))
_reg("gasCylinderRack", gas_cylinders(), (0.95, 1.65, 0.45))
_reg("biohazardBin", biohazard_bin(), (0.5, 0.82, 0.5))


# ---- greenhouse -------------------------------------------------------------------------------------------------------
def _foliage(c, x0, z0, x1, z1, y0, y1, kinds=("leaf", "green")):
    """A stepped leafy mound (three shrinking layers) over the given rectangle."""
    for i in range(3):
        ix = (x1 - x0) * 0.12 * i
        iz = (z1 - z0) * 0.12 * i
        lo = y0 + (y1 - y0) * i / 3
        hi = y0 + (y1 - y0) * (i + 1) / 3
        c.add(x0 + ix, lo, z0 + iz, x1 - ix, hi, z1 - iz, kinds[i % len(kinds)])


def raised_planter():
    w, h, d = 2.0, 1.05, 0.9
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.55, d, "@wood")                                     # box
    for x in (0.0, w - 0.08):
        c.add(x, 0, 0.0, x + 0.08, 0.6, d, "dark")                              # corner boards
    c.add(0.0, 0.5, 0.0, w, 0.6, 0.06, "dark")
    c.add(0.0, 0.5, d - 0.06, w, 0.6, d, "dark")
    c.add(0.08, 0.5, 0.06, w - 0.08, 0.56, d - 0.06, "bark")                    # soil
    _foliage(c, 0.12, 0.12, 0.7, 0.75, 0.56, 1.0)
    _foliage(c, 0.8, 0.15, 1.3, 0.7, 0.56, 0.85, ("green", "leaf"))
    _foliage(c, 1.4, 0.1, 1.9, 0.78, 0.56, 1.05)
    for x0, k in ((0.3, "red"), (0.95, "yellow"), (1.1, "plum"), (1.65, "white")):
        c.add(x0, 0.86, 0.35, x0 + 0.08, 0.94, 0.43, k)                          # blooms
    c.add(0.85, 0.56, d - 0.12, 0.9, 0.7, d - 0.07, "paper")                    # plant label
    return c.boxes


def potting_bench():
    w, h, d = 1.6, 1.45, 0.7
    c = Part(w, h, d)
    for x in (0.03, w - 0.09):
        for z in (0.03, d - 0.09):
            c.add(x, 0, z, x + 0.06, 0.88, z + 0.06, "@wood")
    c.add(0.0, 0.85, 0.0, w, 0.9, d, "@wood")                                   # top
    c.add(0.03, 0.2, 0.03, w - 0.03, 0.24, d - 0.03, "@wood")                   # low shelf
    for x in (0.03, w - 0.09):
        c.add(x, 0.9, 0.0, x + 0.06, 1.45, 0.06, "@wood")                       # rear uprights
    c.add(0.0, 1.2, 0.0, w, 1.24, 0.22, "@wood")                                # pot shelf
    for i in range(5):
        x0 = 0.1 + i * 0.3
        c.add(x0, 1.24, 0.04, x0 + 0.16, 1.38, 0.2, "rust")                     # terracotta pots
        c.add(x0 + 0.03, 1.38, 0.07, x0 + 0.13, 1.45, 0.17, "leaf")
    c.add(0.1, 0.24, 0.1, 0.6, 0.52, 0.55, "sand")                              # soil bag
    c.add(0.7, 0.24, 0.12, 1.2, 0.4, 0.6, "rust")                               # stacked pots
    c.add(0.15, 0.9, 0.2, 0.75, 0.98, 0.6, "bark")                              # potting soil heap
    c.add(0.9, 0.9, 0.3, 1.1, 1.05, 0.5, "rust")
    c.add(0.93, 1.05, 0.33, 1.07, 1.15, 0.47, "green")                          # seedling
    c.add(1.25, 0.9, 0.35, 1.45, 0.92, 0.42, "steel")                           # trowel
    return c.boxes


def potted_palm():
    w, h, d = 1.5, 2.7, 1.5
    c = Part(w, h, d)
    c.add(0.45, 0, 0.45, 1.05, 0.5, 1.05, "@pot")                               # planter
    c.add(0.42, 0.45, 0.42, 1.08, 0.52, 1.08, "@pot")
    c.add(0.5, 0.5, 0.5, 1.0, 0.54, 1.0, "bark")
    for i in range(6):                                                           # ringed trunk
        y0 = 0.54 + i * 0.3
        k = "bark" if i % 2 == 0 else "dark"
        s = 0.12 - i * 0.008
        c.add(0.75 - s, y0, 0.75 - s, 0.75 + s, y0 + 0.3, 0.75 + s, k)
    top = 2.34
    for ang in (0, 60, 120, 180, 240, 300):                                      # fronds radiating and drooping
        c.add(0.7, top, 0.75, 0.8, top + 0.06, 1.5, "leaf", (-28, ang, 0), (0.75, top, 0.75))
        c.add(0.62, top + 0.02, 1.0, 0.88, top + 0.05, 1.42, "green", (-28, ang, 0), (0.75, top, 0.75))
    c.add(0.65, top - 0.05, 0.65, 0.85, top + 0.2, 0.85, "leaf")                 # crown
    c.add(0.68, top - 0.12, 0.8, 0.76, top - 0.02, 0.88, "brass")               # coconuts
    return c.boxes


def banana_plant():
    w, h, d = 1.1, 1.8, 1.1
    c = Part(w, h, d)
    c.add(0.3, 0, 0.3, 0.8, 0.4, 0.8, "@pot")
    c.add(0.35, 0.4, 0.35, 0.75, 0.43, 0.75, "bark")
    c.add(0.5, 0.43, 0.5, 0.6, 1.1, 0.6, "green")                               # pseudostem
    for ang in (20, 110, 200, 290):
        c.add(0.47, 1.0, 0.55, 0.63, 1.04, 1.1, "leaf", (-35, ang, 0), (0.55, 1.0, 0.55))   # broad leaves
        c.add(0.53, 1.04, 0.58, 0.57, 1.05, 1.05, "green", (-35, ang, 0), (0.55, 1.0, 0.55))
    for ang in (65, 245):
        c.add(0.49, 1.3, 0.55, 0.61, 1.34, 1.0, "leaf", (-15, ang, 0), (0.55, 1.3, 0.55))
    c.add(0.5, 1.1, 0.5, 0.6, 1.8, 0.6, "leaf")                                 # unfurling leaf
    return c.boxes


def saguaro():
    w, h, d = 0.8, 2.15, 0.6
    c = Part(w, h, d)
    c.add(0.05, 0, 0.0, 0.75, 0.12, 0.6, "sand")                                # sand mound
    c.add(0.3, 0.12, 0.2, 0.5, 2.1, 0.4, "green")                               # trunk
    c.add(0.32, 2.1, 0.22, 0.48, 2.15, 0.38, "leaf")
    c.add(0.1, 0.9, 0.22, 0.3, 1.0, 0.38, "green")                              # left arm
    c.add(0.08, 1.0, 0.22, 0.22, 1.6, 0.38, "green")
    c.add(0.5, 1.2, 0.22, 0.7, 1.3, 0.38, "green")                              # right arm
    c.add(0.58, 1.3, 0.22, 0.72, 1.85, 0.38, "green")
    for y in (0.4, 0.8, 1.2, 1.6):
        c.add(0.38, y, 0.4, 0.42, y + 0.18, 0.41, "leaf")                       # ribs
    c.add(0.36, 2.12, 0.27, 0.44, 2.15, 0.33, "white")                          # bloom
    c.add(0.55, 0.12, 0.05, 0.7, 0.2, 0.18, "stone")
    return c.boxes


def cactus_cluster():
    w, h, d = 0.95, 1.0, 0.95
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.12, d, "sand")
    c.add(0.1, 0.12, 0.1, 0.45, 0.45, 0.45, "green")                            # barrel cactus
    c.add(0.15, 0.45, 0.15, 0.4, 0.5, 0.4, "leaf")
    c.add(0.24, 0.5, 0.24, 0.31, 0.55, 0.31, "red")                             # flower
    c.add(0.55, 0.12, 0.5, 0.8, 0.65, 0.75, "leaf")                             # column
    c.add(0.6, 0.65, 0.55, 0.75, 1.0, 0.7, "leaf")
    c.add(0.15, 0.12, 0.6, 0.45, 0.4, 0.68, "green", (0, 0, 15), (0.3, 0.12, 0.64))     # prickly pear pads
    c.add(0.22, 0.38, 0.6, 0.48, 0.62, 0.68, "green", (0, 0, -18), (0.35, 0.38, 0.64))
    c.add(0.36, 0.6, 0.6, 0.42, 0.66, 0.68, "plum")
    c.add(0.6, 0.12, 0.1, 0.85, 0.22, 0.35, "stone")                            # rocks
    c.add(0.05, 0.12, 0.8, 0.2, 0.18, 0.92, "stone")
    return c.boxes


def seedling_rack():
    w, h, d = 1.2, 1.85, 0.5
    c = Part(w, h, d)
    for x in (0.0, w - 0.04):
        for z in (0.0, d - 0.04):
            c.add(x, 0, z, x + 0.04, h, z + 0.04, "steel")
    for s in range(4):
        y = 0.12 + s * 0.45
        c.add(0.0, y, 0.0, w, y + 0.03, d, "steel")
        c.add(0.05, y + 0.03, 0.05, w - 0.05, y + 0.08, d - 0.05, "black")      # tray
        for i in range(5):
            for j in range(2):
                c.add(0.1 + i * 0.21, y + 0.08, 0.1 + j * 0.18, 0.18 + i * 0.21, y + 0.16 + ((i + j + s) % 3) * 0.03,
                      0.18 + j * 0.18, "leaf" if (i + j) % 2 else "green")       # seedlings
        c.add(0.05, y + 0.38, 0.1, w - 0.05, y + 0.41, d - 0.1, "white")        # grow light
    return c.boxes


def irrigation_manifold():
    w, h, d = 1.5, 1.85, 0.6
    c = Part(w, h, d)
    c.add(0.05, 0, 0.05, 0.6, 1.3, 0.55, "@tank")                               # water tank
    c.add(0.1, 1.3, 0.1, 0.55, 1.36, 0.5, "black")
    c.add(0.6, 0.25, 0.25, w, 0.33, 0.33, "steel")                              # outlet pipe
    c.add(0.75, 0.33, 0.25, 0.83, 1.75, 0.33, "steel")                          # risers
    c.add(1.2, 0.33, 0.25, 1.28, 1.75, 0.33, "steel")
    c.add(0.75, 1.7, 0.0, 1.28, 1.78, 0.33, "steel")                            # header to wall
    for x0 in (0.72, 1.17):
        c.add(x0, 0.9, 0.22, x0 + 0.14, 1.0, 0.36, "red")                       # valve wheels
    c.add(0.9, 0.6, 0.2, 1.1, 0.85, 0.4, "blue")                                # pump
    c.add(0.95, 1.1, 0.33, 1.1, 1.25, 0.36, "screen")                           # timer
    c.add(1.32, 0.0, 0.1, 1.5, 0.12, 0.5, "black")
    return c.boxes


def misting_post():
    w, h, d = 0.4, 2.5, 0.4
    c = Part(w, h, d)
    c.add(0.05, 0, 0.05, 0.35, 0.06, 0.35, "steel")
    c.add(0.17, 0.06, 0.17, 0.23, 2.45, 0.23, "steel")                          # pipe
    for y, ang in ((1.2, 0), (1.7, 90), (2.2, 180)):
        c.add(0.17, y, 0.2, 0.23, y + 0.04, 0.4, "steel", (0, ang, 0), (0.2, y, 0.2))
        c.add(0.16, y - 0.02, 0.34, 0.24, y + 0.06, 0.4, "blue", (0, ang, 0), (0.2, y, 0.2))   # nozzle
    c.add(0.12, 2.42, 0.12, 0.28, 2.5, 0.28, "steel")
    c.add(0.15, 0.4, 0.23, 0.25, 0.55, 0.3, "red")                              # shut-off valve
    return c.boxes


def overgrowth():
    w, h, d = 1.6, 0.35, 1.3
    c = Part(w, h, d)
    c.add(0.0, 0, 0.1, 1.2, 0.05, 1.1, "leaf")
    c.add(0.3, 0, 0.0, 1.6, 0.04, 0.8, "green")
    c.add(0.2, 0, 0.9, 1.0, 0.06, 1.3, "green")
    for x0, z0, s, k in ((0.1, 0.2, 0.35, "leaf"), (0.7, 0.1, 0.3, "green"), (1.1, 0.5, 0.35, "leaf"),
                         (0.4, 0.7, 0.4, "green"), (0.15, 0.95, 0.25, "leaf")):
        c.add(x0, 0.04, z0, x0 + s, 0.12 + s * 0.6, z0 + s, k)                   # tufts
    c.add(0.0, 0.03, 0.55, 1.5, 0.06, 0.6, "bark", (0, 20, 0), (0.75, 0.04, 0.58))   # creeping root
    c.add(0.55, 0.12, 0.55, 0.62, 0.18, 0.62, "yellow")
    c.add(1.25, 0.12, 0.6, 1.32, 0.17, 0.67, "white")
    return c.boxes


def hanging_vines():
    w, h, d = 1.2, 1.25, 1.2
    c = Part(w, h, d)
    c.add(0.58, 1.05, 0.58, 0.62, 1.25, 0.62, "steel")                          # hanger
    c.add(0.35, 0.8, 0.35, 0.85, 1.05, 0.85, "@pot")                            # basket
    _foliage(c, 0.3, 0.3, 0.9, 0.9, 1.05, 1.15)
    for x0, z0, y0 in ((0.3, 0.32, 0.0), (0.82, 0.4, 0.2), (0.5, 0.85, 0.1), (0.35, 0.75, 0.35), (0.85, 0.82, 0.05)):
        c.add(x0, y0, z0, x0 + 0.06, 0.85, z0 + 0.06, "leaf")                    # trailing vines
        c.add(x0 - 0.03, y0 + 0.15, z0 - 0.02, x0 + 0.09, y0 + 0.25, z0 + 0.08, "green")
    return c.boxes


def dome_fountain():
    w, h, d = 2.6, 1.6, 2.6
    c = Part(w, h, d)
    c.add(0.1, 0, 0.4, 2.5, 0.5, 2.2, "stone")                                  # octagon-ish basin
    c.add(0.4, 0, 0.1, 2.2, 0.5, 2.5, "stone")
    c.add(0.25, 0.4, 0.55, 2.35, 0.45, 2.05, "water")
    c.add(0.55, 0.4, 0.25, 2.05, 0.45, 2.35, "water")
    c.add(0.05, 0.45, 0.35, 2.55, 0.55, 2.25, "concrete")                       # rim
    c.add(0.35, 0.45, 0.05, 2.25, 0.55, 2.55, "concrete")
    c.add(0.15, 0.45, 0.45, 2.45, 0.55, 2.15, "water")
    c.add(0.45, 0.45, 0.15, 2.15, 0.55, 2.45, "water")
    c.add(1.15, 0.45, 1.15, 1.45, 1.1, 1.45, "stone")                           # column
    c.add(0.85, 1.1, 0.85, 1.75, 1.2, 1.75, "concrete")                         # upper bowl
    c.add(0.95, 1.18, 0.95, 1.65, 1.21, 1.65, "water")
    c.add(1.25, 1.2, 1.25, 1.35, 1.6, 1.35, "water")                            # jet
    for x0, z0 in ((0.4, 0.55), (2.0, 0.55), (0.4, 1.85), (2.0, 1.85)):
        c.add(x0, 0.45, z0, x0 + 0.2, 0.48, z0 + 0.2, "leaf")                   # lily pads
    return c.boxes


def watering_cart():
    w, h, d = 1.0, 0.95, 0.6
    c = Part(w, h, d)
    _wheels(c, w, d, r=0.12)
    c.add(0.03, 0.12, 0.03, w - 0.03, 0.42, d - 0.03, "green")                  # tub
    c.add(0.06, 0.42, 0.06, w - 0.06, 0.44, d - 0.06, "water")
    c.add(w - 0.06, 0.42, 0.1, w - 0.02, 0.95, 0.14, "steel")                   # handle
    c.add(w - 0.06, 0.42, d - 0.14, w - 0.02, 0.95, d - 0.1, "steel")
    c.add(w - 0.06, 0.9, 0.1, w - 0.02, 0.95, d - 0.1, "steel")
    c.add(0.1, 0.44, 0.15, 0.35, 0.72, 0.4, "steel")                            # watering cans
    c.add(0.35, 0.6, 0.25, 0.5, 0.64, 0.3, "steel", (0, 0, 25), (0.35, 0.6, 0.27))
    c.add(0.5, 0.44, 0.2, 0.72, 0.68, 0.42, "green")
    c.add(0.05, 0.15, d - 0.03, 0.35, 0.38, d, "yellow")                        # hose reel
    c.add(0.15, 0.24, d - 0.04, 0.25, 0.3, d - 0.02, "black")
    return c.boxes


def greenhouse_bench():
    w, h, d = 1.6, 0.85, 0.6
    c = Part(w, h, d)
    for x in (0.05, w - 0.12):
        c.add(x, 0, 0.08, x + 0.07, 0.42, 0.52, "steel")                        # cast frames
        c.add(x, 0.42, 0.04, x + 0.07, 0.85, 0.11, "steel", (-10, 0, 0), (x, 0.42, 0.08))
    for i in range(5):
        c.add(0.0, 0.4, 0.1 + i * 0.09, w, 0.44, 0.16 + i * 0.09, "@wood")      # seat slats
    for i in range(3):
        y = 0.5 + i * 0.11
        c.add(0.0, y, 0.05, w, y + 0.07, 0.09, "@wood", (-10, 0, 0), (w / 2, 0.42, 0.08))   # back slats
    return c.boxes


def compost_bins():
    w, h, d = 1.4, 1.0, 0.75
    c = Part(w, h, d)
    for x0 in (0.0, 0.72):
        c.add(x0, 0, 0.0, x0 + 0.68, 0.9, d, "@wood")
        for y in (0.15, 0.4, 0.65):
            c.add(x0, y, d - 0.01, x0 + 0.68, y + 0.05, d, "dark")              # slat gaps
        c.add(x0 + 0.05, 0.9, 0.05, x0 + 0.63, 0.95, d - 0.05, "bark")          # compost top
    c.add(0.1, 0.95, 0.15, 0.3, 1.0, 0.3, "leaf")
    c.add(0.9, 0.95, 0.4, 1.1, 0.98, 0.6, "yellow")
    return c.boxes


_reg("raisedPlanter", raised_planter(), (2.0, 1.05, 0.9), {"@wood": ["oak", "pine", "walnut"]})
_reg("pottingBench", potting_bench(), (1.6, 1.45, 0.7), {"@wood": ["pine", "oak", "ash"]})
_reg("pottedPalm", potted_palm(), (1.5, 2.7, 1.5), {"@pot": ["rust", "stone", "concrete"]})
_reg("bananaPlant", banana_plant(), (1.1, 1.8, 1.1), {"@pot": ["rust", "concrete"]})
_reg("saguaroCactus", saguaro(), (0.8, 2.15, 0.6))
_reg("cactusCluster", cactus_cluster(), (0.95, 1.0, 0.95))
_reg("seedlingRack", seedling_rack(), (1.2, 1.85, 0.5))
_reg("irrigationManifold", irrigation_manifold(), (1.5, 1.85, 0.6), {"@tank": ["blue", "green", "black"]})
_reg("mistingPost", misting_post(), (0.4, 2.5, 0.4))
_reg("overgrowthPatch", overgrowth(), (1.6, 0.35, 1.3))
_reg("hangingVines", hanging_vines(), (1.2, 1.25, 1.2), {"@pot": ["rust", "bark"]})
_reg("domeFountain", dome_fountain(), (2.6, 1.6, 2.6))
_reg("wateringCart", watering_cart(), (1.0, 0.95, 0.6))
_reg("greenhouseBench", greenhouse_bench(), (1.6, 0.85, 0.6), {"@wood": ["oak", "pine", "teal"]})
_reg("compostBins", compost_bins(), (1.4, 1.0, 0.75), {"@wood": ["dark", "oak"]})

REGION_PROP_NAMES = ["hospitalBed", "hospitalCurtain", "ivDripStand", "vitalsMonitor", "nursesStation", "waitingChairs",
                    "operatingTable", "surgicalLight", "instrumentTrolley", "morgueCabinet", "autopsyTable",
                    "pharmacyShelf", "xrayMachine", "xrayLightbox", "medicalSupplyRack", "wheelchair",
                    "hospitalWardSign", "labBench", "fumeHood", "specimenTank", "containmentCell", "labCoolingUnit",
                    "controlConsole", "monitorWall", "deconShower", "coldStorageUnit", "labWhiteboard", "hazardSign",
                    "labGlassPartition", "labStool", "labMicroscope", "gasCylinderRack", "biohazardBin",
                    "raisedPlanter", "pottingBench", "pottedPalm", "bananaPlant", "saguaroCactus", "cactusCluster",
                    "seedlingRack", "irrigationManifold", "mistingPost", "overgrowthPatch", "hangingVines",
                    "domeFountain", "wateringCart", "greenhouseBench", "compostBins"]
