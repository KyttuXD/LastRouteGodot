"""Medical/lab/dive: 25 types redone low-poly.
exec'd by build_blocky_props.py after SIZE_SCALE and before mansion finishes (none of these types has a mansion finish).
PROPS, VARIANTS, Part, VOX, _reg, _wheels, TARGET_SIZE are in scope; the region / pod builders (blocky_props_regions.py,
blocky_props_pods.py, blocky_props_rework4.py) ran first, so _reg() here replaces their shapes one for one.

What changes (outer boxes stay where they were, so every mesh keeps its staging bounds):
  - hospitalCurtain: five wide pleats (was nine).
  - ivDripStand: crossed base bars + pole + hook bar + two bags (no casters, line or pump).
  - vitalsMonitor: one ECG trace (was three), no hose ports.
  - nursesStation: two screens without stand plates, empty chart rack (no file boxes), no kick stripe.
  - instrumentTrolley: two instruments (was five), one supply box.
  - xrayMachine / xrayLightbox: no buried duplicate head, no light-field / label plates; films without ribs.
  - medicalSupplyRack: one stock block per shelf (was three).
  - fumeHood: one flask inside (was three), no status light.
  - specimenTank: one specimen block, no bubbles / mullion, one feed pipe and one label strip.
  - containmentCell: five sill stripes (was twenty-two).
  - labCoolingUnit: three louvres (was eight), screen without bezel.
  - deconShower: three grate bars (was six), one-box shower heads, no inner roof plate.
  - labWhiteboard: four notes (was ten), one marker.
  - labGlassPartition: four sill stripes (was ten).
  - divePod / Film / Lit: one release clamp per side (was two), no sensor pads.
  - diveHeadsetShelf: six headsets kept as is (shell, stand, visor, tape); only hidden-face culling saves triangles.
  - diveConsole: three list bars (was six), three sensor pads (was five).
  - ivStand, medicalCart, labMicroscope, biohazardBin, diveHeadsetStand: already lean; shapes kept, only hidden-face culling.
Every type joins LOWPOLY, so faces buried in or against another box (and floor-contact undersides) are dropped.
Locked: type ids, model counts per type (same colour slots), TARGET_SIZE / footprints / colliders / front / hide / mount,
same atlas (no new tiles).
"""

_MEDICAL_078 = [
    "hospitalCurtain", "ivStand", "ivDripStand", "medicalCart", "vitalsMonitor", "nursesStation", "instrumentTrolley",
    "xrayMachine", "xrayLightbox", "medicalSupplyRack", "fumeHood", "specimenTank", "containmentCell", "labCoolingUnit",
    "deconShower", "labWhiteboard", "labGlassPartition", "labMicroscope", "biohazardBin", "divePod", "divePodFilm",
    "divePodLit", "diveHeadsetStand", "diveHeadsetShelf", "diveConsole",
]


def _lp_replace(name, boxes):
    """Swap the base shape, keeping the type's colour slots (model count) and its TARGET_SIZE."""
    subs = PROPS[name][1]
    assert not VARIANTS.get(name), name
    _reg(name, boxes, TARGET_SIZE[name], subs)


# ---- hospital ---------------------------------------------------------------------------------------------------------
def lp_hospital_curtain():
    w, h, d = 1.90, 2.40, 0.16
    c = Part(w, h, d)
    c.add(0.0, 2.32, 0.03, w, 2.40, 0.13, "steel")                              # ceiling track
    for x in (0.02, w - 0.07):
        c.add(x, 0, 0.04, x + 0.05, 2.32, 0.12, "steel")                         # end poles
        c.add(x - 0.08, 0, 0.0, x + 0.13, 0.05, 0.16, "black")                   # feet
    folds = 5
    step = (w - 0.14) / folds
    for i in range(folds):
        x0 = 0.07 + i * step
        z0 = 0.05 if i % 2 == 0 else 0.08
        c.add(x0, 0.24, z0, x0 + step, 2.26, z0 + 0.04, "@curtain")            # pleats
    c.add(0.07, 2.18, 0.045, w - 0.07, 2.22, 0.13, "white")                     # mesh band
    return c.boxes


def lp_iv_drip_stand():
    w, h, d = 0.45, 1.95, 0.45
    c = Part(w, h, d)
    c.add(0.02, 0.0, 0.2, w - 0.02, 0.08, 0.25, "steel")                        # crossed base bars (were on casters)
    c.add(0.2, 0.0, 0.02, 0.25, 0.08, d - 0.02, "steel")
    c.add(0.2, 0.08, 0.2, 0.25, 1.86, 0.25, "steel")                            # pole
    c.add(0.06, 1.82, 0.2, w - 0.06, 1.86, 0.25, "steel")                       # hook bar
    c.add(0.05, 1.5, 0.17, 0.17, 1.8, 0.28, "glass")                            # saline bag
    c.add(0.28, 1.56, 0.18, 0.39, 1.8, 0.27, "amber")                           # second bag
    c.add(0.2, 1.1, 0.25, 0.3, 1.22, 0.33, "grey")                              # pump (keeps the front bound)
    return c.boxes


def lp_vitals_monitor():
    w, h, d = 0.6, 1.62, 0.55
    c = Part(w, h, d)
    _wheels(c, w, d)
    c.add(0.05, 0.08, 0.05, w - 0.05, 0.14, d - 0.05, "grey")
    c.add(0.1, 0.14, 0.1, w - 0.1, 0.62, d - 0.1, "white")                      # ventilator box
    c.add(0.14, 0.4, d - 0.1, w - 0.14, 0.56, d - 0.09, "screen")
    c.add(0.27, 0.62, 0.25, 0.33, 1.2, 0.31, "steel")                           # pole
    c.add(0.04, 1.2, 0.12, w - 0.04, 1.58, 0.44, "grey")                        # monitor shell
    c.add(0.07, 1.24, 0.44, w - 0.07, 1.54, 0.45, "black")
    c.add(0.09, 1.44, 0.445, w - 0.09, 1.46, 0.455, "green")                    # ECG trace
    c.add(0.24, 1.58, 0.2, 0.36, 1.62, 0.36, "red")                             # alarm light
    return c.boxes


def lp_nurses_station():
    w, h, d = 2.4, 1.18, 0.95
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.74, 0.62, "white")                                  # back desk
    c.add(0.0, 0.74, 0.0, w, 0.78, 0.66, "grey")                                # work top
    c.add(0.0, 0, 0.66, w, 1.1, d, "teal")                                      # front counter wall
    c.add(0.0, 1.1, 0.6, w, 1.18, d, "white")                                   # raised ledge
    for x in (0.3, 1.25):                                                        # two screens
        c.add(x + 0.22, 0.78, 0.14, x + 0.28, 0.9, 0.2, "black")
        c.add(x, 0.9, 0.1, x + 0.5, 1.2, 0.14, "black")
        c.add(x + 0.03, 0.93, 0.14, x + 0.47, 1.17, 0.145, "screen")
    c.add(1.95, 0.78, 0.08, 2.3, 1.0, 0.4, "@sheet")                           # chart rack
    c.add(0.85, 0.78, 0.4, 1.1, 0.84, 0.55, "black")                            # phone
    c.add(0.05, 1.18, 0.7, 0.18, 1.3, 0.85, "red")                              # call light
    return c.boxes


def lp_instrument_trolley():
    w, h, d = 0.9, 0.95, 0.55
    c = Part(w, h, d)
    _wheels(c, w, d)
    for x in (0.04, w - 0.08):
        for z in (0.04, d - 0.08):
            c.add(x, 0.08, z, x + 0.04, 0.9, z + 0.04, "steel")
    c.add(0.03, 0.3, 0.03, w - 0.03, 0.33, d - 0.03, "steel")
    c.add(0.03, 0.86, 0.03, w - 0.03, 0.9, d - 0.03, "steel")
    c.add(0.06, 0.9, 0.06, w - 0.06, 0.92, d - 0.06, "teal")                    # sterile drape
    for x in (0.16, 0.36):
        c.add(x, 0.92, 0.15, x + 0.06, 0.93, 0.4, "mirror")                     # instruments
    c.add(0.62, 0.92, 0.12, 0.82, 0.98, 0.42, "steel")                          # kidney tray
    c.add(0.1, 0.33, 0.1, 0.8, 0.45, 0.45, "white")                             # boxed supplies
    return c.boxes


def lp_xray_machine():
    w, h, d = 1.6, 2.2, 1.5
    c = Part(w, h, d)
    c.add(0.2, 0, 0.75, 1.4, 0.65, 1.2, "white")                               # table base
    c.add(0.0, 0.65, 0.65, w, 0.75, 1.3, "grey")                                # table top
    c.add(0.05, 0.75, 0.7, w - 0.05, 0.8, 1.25, "black")                        # detector tray
    c.add(0.1, 0, 0.05, 0.35, 2.2, 0.3, "white")                                # column
    c.add(0.35, 1.7, 0.1, 1.05, 1.82, 0.25, "grey")                             # arm
    c.add(0.8, 1.35, 0.6, 1.25, 1.7, 0.95, "white")                             # tube head
    c.add(0.85, 1.25, 0.65, 1.2, 1.35, 0.9, "black")                            # collimator
    c.add(0.9, 1.7, 0.25, 1.05, 1.82, 0.6, "grey")                              # arm to head
    return c.boxes


def lp_xray_lightbox():
    w, h, d = 1.3, 0.85, 0.08
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, h, 0.05, "grey")
    for i in range(3):
        x0 = 0.05 + i * 0.41
        c.add(x0, 0.06, 0.05, x0 + 0.38, 0.79, 0.06, "white")                   # lit panel
        c.add(x0 + 0.05, 0.12, 0.06, x0 + 0.33, 0.73, 0.065, "black")           # film
        c.add(x0 + 0.12, 0.22, 0.065, x0 + 0.26, 0.64, 0.07, "glass")           # bones
    return c.boxes


def lp_supply_rack():
    w, h, d = 1.2, 1.9, 0.5
    c = Part(w, h, d)
    for x in (0.0, w - 0.03):
        for z in (0.0, d - 0.03):
            c.add(x, 0, z, x + 0.03, h, z + 0.03, "steel")
    stock = ["white", "teal", "paper", "blue"]
    for s in range(4):
        y = 0.1 + s * 0.48
        c.add(0.0, y, 0.0, w, y + 0.03, d, "steel")
        c.add(0.06, y + 0.03, 0.05, 0.9 if s % 2 else 1.14, y + 0.25, d - 0.05, stock[s])   # one stock block per shelf
    return c.boxes


# ---- lab --------------------------------------------------------------------------------------------------------------
def lp_fume_hood():
    w, h, d = 1.5, 2.35, 0.9
    c = Part(w, h, d)
    c.add(0.0, 0, 0.05, w, 0.86, d, "white")                                    # base cabinet
    c.add(0.0, 0.86, 0.0, w, 0.9, d, "black")                                   # work surface
    for x in (0.0, w - 0.08):
        c.add(x, 0.9, 0.0, x + 0.08, 2.05, d, "white")                          # side walls
    c.add(0.08, 0.9, 0.0, w - 0.08, 1.85, 0.06, "grey")                         # back baffle (between the walls)
    c.add(0.0, 1.85, 0.0, w, 2.05, d, "white")                                  # header
    c.add(0.08, 1.2, d - 0.05, w - 0.08, 1.85, d - 0.02, "glass")               # sash
    c.add(0.08, 1.16, d - 0.06, w - 0.08, 1.2, d, "steel")                      # sash handle
    c.add(0.15, 1.88, d - 0.01, 0.45, 1.98, d, "screen")
    c.add(0.45, 2.05, 0.2, 1.05, 2.35, 0.7, "steel")                            # duct
    c.add(0.3, 0.9, 0.3, 0.42, 1.1, 0.42, "amber")                              # flask inside
    return c.boxes


def lp_specimen_tank():
    w, h, d = 0.95, 2.3, 0.95
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.32, d, "steel")                                     # base
    c.add(0.1, 0.2, d - 0.01, 0.4, 0.28, d, "screen")
    c.add(0.1, 0.32, 0.1, w - 0.1, 1.95, 0.16, "@fluid")                        # fluid column: back and sides
    for x in (0.1, w - 0.16):
        c.add(x, 0.32, 0.16, x + 0.06, 1.95, d - 0.1, "@fluid")
    c.add(0.1, 0.32, d - 0.16, w - 0.1, 0.6, d - 0.1, "@fluid")                 # front glass bands
    c.add(0.1, 1.75, d - 0.16, w - 0.1, 1.95, d - 0.1, "@fluid")
    for x in (0.06, w - 0.12):
        for z in (0.06, d - 0.12):
            c.add(x, 0.32, z, x + 0.06, 1.95, z + 0.06, "steel")               # frame posts
    c.add(0.32, 0.6, 0.32, 0.63, 1.5, 0.63, "plum")                             # specimen
    c.add(0.0, 1.95, 0.0, w, 2.15, d, "steel")                                  # cap
    c.add(0.3, 2.15, 0.3, 0.67, 2.3, 0.62, "grey")                              # feed pipe
    c.add(0.15, 2.0, d - 0.01, 0.8, 2.08, d, "yellow")
    return c.boxes


def lp_containment_cell():
    w, h, d = 2.2, 2.6, 1.7
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.12, d, "steel")                                     # floor plate
    sw = w / 5
    for i in range(5):                                                           # hazard stripes on the sill
        c.add(i * sw, 0.12, d - 0.06, (i + 1) * sw, 0.2, d, "yellow" if i % 2 == 0 else "black")
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


def lp_cooling_unit():
    w, h, d = 1.0, 2.1, 0.85
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 2.1, d, "white")
    for i in range(3):
        c.add(0.08, 0.2 + i * 0.25, d - 0.01, w - 0.08, 0.32 + i * 0.25, d, "grey")   # intake louvres
    c.add(0.25, 1.4, d - 0.01, 0.75, 1.7, d, "screen")
    c.add(0.1, 1.9, d - 0.01, 0.9, 2.0, d, "blue")
    c.add(0.0, 0, d - 0.02, w, 0.1, d, "black")
    return c.boxes


def lp_decon_shower():
    w, h, d = 1.3, 2.5, 1.3
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.1, d, "steel")                                      # grate tray
    for i in range(3):
        c.add(0.2 + i * 0.4, 0.1, 0.1, 0.3 + i * 0.4, 0.11, d - 0.1, "black")
    for x in (0.0, w - 0.08):
        for z in (0.0, d - 0.08):
            c.add(x, 0.1, z, x + 0.08, 2.4, z + 0.08, "yellow")                 # posts
    c.add(0.0, 2.4, 0.0, w, 2.5, d, "yellow")                                   # roof frame
    c.add(0.08, 0.1, 0.0, w - 0.08, 2.4, 0.05, "glass")                         # back pane
    for x in (0.0, w - 0.05):
        c.add(x, 0.1, 0.08, x + 0.05, 2.4, d - 0.08, "glass")                   # side panes
    for x0 in (0.25, 0.85):                                                      # shower heads
        c.add(x0, 2.2, 0.55, x0 + 0.2, 2.4, 0.75, "steel")
    c.add(0.5, 1.2, 0.05, 0.8, 1.4, 0.08, "red")                                # pull handle
    c.add(0.0, 2.32, d - 0.01, w, 2.4, d, "black")
    return c.boxes


def lp_whiteboard():
    w, h, d = 1.8, 1.15, 0.08
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, h, 0.03, "steel")
    c.add(0.04, 0.04, 0.03, w - 0.04, h - 0.04, 0.04, "white")
    for x0, y0, x1, y1, k in ((0.15, 0.85, 0.9, 0.88, "blue"), (0.15, 0.75, 0.6, 0.78, "blue"),
                              (0.2, 0.3, 0.7, 0.34, "red"), (1.0, 0.4, 1.6, 0.9, "green")):
        c.add(x0, y0, 0.04, x1, y1, 0.045, k)                                    # notes and a chart
    c.add(0.1, 0.0, 0.03, w - 0.1, 0.03, 0.08, "steel")                         # marker tray
    c.add(0.3, 0.03, 0.04, 0.42, 0.05, 0.07, "red")
    return c.boxes


def lp_glass_partition():
    w, h, d = 1.95, 2.5, 0.14
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.22, d, "grey")                                      # base rail
    for i in range(4):
        x0 = 0.12 + i * 0.48
        c.add(x0, 0.08, d - 0.005, x0 + 0.24, 0.16, d, "yellow")                # hazard stripes
    for x in (0.0, w - 0.06):
        c.add(x, 0.22, 0.0, x + 0.06, h, d, "steel")                            # mullions
    c.add(0.9, 0.22, 0.0, 0.96, h, d, "steel")
    c.add(0.0, h - 0.08, 0.0, w, h, d, "steel")                                 # head rail
    c.add(0.06, 0.22, 0.05, 0.9, h - 0.08, 0.09, "glass")
    c.add(0.96, 0.22, 0.05, w - 0.06, h - 0.08, 0.09, "glass")
    c.add(0.06, 1.3, 0.04, 0.9, 1.36, 0.1, "white")                             # manifestation band
    c.add(0.96, 1.3, 0.04, w - 0.06, 1.36, 0.1, "white")
    return c.boxes


# ---- dive lab ---------------------------------------------------------------------------------------------------------
def lp_pod(film=False, lit=False):
    w, h, d = 1.0, 1.35, 2.2
    c = Part(w, h, d)
    c.add(0.15, 0.0, 0.25, w - 0.15, 0.12, d - 0.25, "grey")                    # plinth
    c.add(0.05, 0.12, 0.2, w - 0.05, 0.55, d - 0.2, "white")                    # shell
    c.add(0.1, 0.12, 0.08, w - 0.1, 0.5, 0.2, "white")
    c.add(0.1, 0.12, d - 0.2, w - 0.1, 0.5, d - 0.08, "white")
    c.add(0.16, 0.42, 0.24, w - 0.16, 0.56, d - 0.24, "linen")                  # padded bed inside the rim
    c.add(0.3, 0.56, 0.28, w - 0.3, 0.64, 0.5, "linen")                         # head cushion
    c.add(0.05, 0.55, 0.2, 0.12, 0.6, d - 0.2, "porcelain")                     # rim
    c.add(w - 0.12, 0.55, 0.2, w - 0.05, 0.6, d - 0.2, "porcelain")
    lid_kind = "mirror" if film else "white"
    c.add(0.08, 0.6, 0.05, w - 0.08, 0.68, 1.4, "white", (-62, 0, 0), (w / 2, 0.6, 0.12))
    c.add(0.12, 0.68, 0.1, w - 0.12, 0.7, 1.32, lid_kind, (-62, 0, 0), (w / 2, 0.6, 0.12))
    if film:
        c.add(w - 0.32, 0.7, 1.12, w - 0.12, 0.72, 1.32, "mirror", (-62, 0, 35), (w - 0.22, 0.7, 1.22))
    for x in (0.04, w - 0.1):                                                   # one release clamp per side
        c.add(x, 0.5, 1.6, x + 0.06, 0.62, 1.75, "steel")
    c.add(w / 2 - 0.05, 0.0, 0.0, w / 2 + 0.05, 0.1, 0.25, "black")             # cable run to the console
    c.add(0.1, 0.13, d - 0.1, w - 0.1, 0.2, d - 0.06, "screen" if lit else "grey")   # status strip at the foot
    return c.boxes


def lp_headset_shelf():
    w, h, d = 1.9, 0.45, 0.32
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, 0.04, d, "white")                                   # shelf board
    for x in (0.05, w - 0.09):
        c.add(x, -0.0, 0.0, x + 0.04, 0.12, 0.2, "steel")                       # brackets
    for i in range(6):
        x0 = 0.08 + i * 0.3
        c.add(x0, 0.18, 0.06, x0 + 0.24, 0.38, d - 0.04, "white")               # headset shell
        c.add(x0 + 0.1, 0.04, 0.12, x0 + 0.14, 0.18, 0.16, "steel")             # stand
        c.add(x0, 0.22, d - 0.05, x0 + 0.24, 0.32, d - 0.03, "black")           # visor
        c.add(x0 + 0.2, 0.24, 0.08, x0 + 0.24, 0.32, d - 0.06, "grey")          # tape
    return c.boxes


def lp_dive_console():
    w, h, d = 2.0, 1.3, 0.8
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, 0.72, 0.6, "grey")                                  # desk body
    c.add(0.0, 0.72, 0.0, w, 0.77, d, "white")                                  # desk top
    c.add(0.55, 0.77, 0.12, 0.65, 0.9, 0.2, "black")                            # monitor stem
    c.add(0.2, 0.9, 0.1, 1.0, 1.28, 0.16, "black")                              # monitor
    c.add(0.24, 0.94, 0.16, 0.96, 1.24, 0.165, "dark")
    for i in range(3):                                                          # the list: bars, no text
        y = 0.99 + i * 0.08
        c.add(0.28, y, 0.165, 0.28 + (0.3 + 0.08 * i), y + 0.03, 0.17, "screen")
    c.add(1.2, 0.77, 0.15, 1.28, 0.85, 0.23, "green")                           # uplink bulb
    c.add(0.45, 0.77, 0.4, 0.95, 0.79, 0.62, "black")                           # keyboard
    c.add(1.2, 0.77, 0.4, 1.5, 0.79, 0.62, "paper")                             # intake forms
    for i in range(3):                                                          # sensor pads on the edge
        c.add(1.55 + i * 0.14, 0.77, 0.66, 1.65 + i * 0.14, 0.785, 0.76, "black")
    return c.boxes


_lp_replace("hospitalCurtain", lp_hospital_curtain())
_lp_replace("ivDripStand", lp_iv_drip_stand())
_lp_replace("vitalsMonitor", lp_vitals_monitor())
_lp_replace("nursesStation", lp_nurses_station())
_lp_replace("instrumentTrolley", lp_instrument_trolley())
_lp_replace("xrayMachine", lp_xray_machine())
_lp_replace("xrayLightbox", lp_xray_lightbox())
_lp_replace("medicalSupplyRack", lp_supply_rack())
_lp_replace("fumeHood", lp_fume_hood())
_lp_replace("specimenTank", lp_specimen_tank())
_lp_replace("containmentCell", lp_containment_cell())
_lp_replace("labCoolingUnit", lp_cooling_unit())
_lp_replace("deconShower", lp_decon_shower())
_lp_replace("labWhiteboard", lp_whiteboard())
_lp_replace("labGlassPartition", lp_glass_partition())
_lp_replace("divePod", lp_pod())
_lp_replace("divePodFilm", lp_pod(film=True))
_lp_replace("divePodLit", lp_pod(lit=True))
_lp_replace("diveHeadsetShelf", lp_headset_shelf())
_lp_replace("diveConsole", lp_dive_console())
# ivStand, medicalCart, labMicroscope, biohazardBin, diveHeadsetStand: shapes kept (already lean), culling only.

LOWPOLY.update(_MEDICAL_078)
