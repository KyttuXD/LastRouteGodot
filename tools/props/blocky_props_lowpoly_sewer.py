"""Sewer/utility group: 25 types redone low-poly (server racks, carts, cables, lava pipes, gas rack, control
console, monitor wall, hazard sign, bin, office machines, retro computers, rack gear).
Exec'd by build_blocky_props.py after SIZE_SCALE and before mansion finishes.
Keep type ids, variant slot counts, colour options, TARGET_SIZE / bounds (outer extents unchanged), fronts, colliders, atlas tiles.
Fewer boxes (repeated rows merged, labels and trim dropped), no bevels, shared tiles; hidden_faces() culling via LOWPOLY.
"""

_SEWER_078 = [
    "serverRack", "breakerCabinet", "utilityCart", "maintenanceCleaningCart", "backstageRepairStand",
    "cableCoil", "cableRun", "lavaPipeManifold", "lavaVent", "gasCylinderRack", "controlConsole", "monitorWall",
    "hazardSign", "trashBin", "officePhotocopier", "officePrinter", "officeShredder", "officeWaterCooler",
    "officeCubiclePartition", "officeCrtSecurityConsole", "retroComputerDesktop", "retroComputerCompact",
    "retroComputerTower", "retroComputerTerminal", "rackGear",
]


def _sw_keep_variants(name, shapes):
    old = [PROPS[name]] + list(VARIANTS.get(name, []))
    assert len(old) == len(shapes), (name, len(old), len(shapes))
    PROPS[name] = (shapes[0], old[0][1])
    VARIANTS[name] = [(s, o[1]) for s, o in zip(shapes[1:], old[1:])]


def _sw_keep_one(name, shape):
    assert name in PROPS and not VARIANTS.get(name), (name, VARIANTS.get(name))
    PROPS[name] = (shape, PROPS[name][1])


# ---- racks / cabinets -------------------------------------------------------------------------

def lp_rack(body="black", panel="steel"):
    """Cabinet body + three front door panels (was six) + three status LEDs."""
    return [
        (0, 0, 0, 1, 1, .92, body),
        (.08, .06, .92, .92, .3, 1, panel),
        (.08, .34, .92, .92, .58, 1, panel),
        (.08, .62, .92, .92, .86, 1, panel),
        (.7, .1, .98, .78, .14, 1.0, "screen"),
        (.7, .38, .98, .78, .42, 1.0, "screen"),
        (.7, .66, .98, .78, .7, 1.0, "screen"),
    ]


def lp_rack_gear():
    """Rack case + four faceplates (was seven) with one LED each and two display strips (TARGET 0.6 x 1.2 x 0.6)."""
    z0, z1, zl = .9666666666666667, 1.0, 1.0083333333333333
    rows = [(.0833, .2917, "grey", "screen"), (.3333, .5417, "steel", "amber"),
            (.5833, .7917, "grey", "red"), (.8333, .9333, "steel", "screen")]
    out = [(0.0, 0.0, 0.0, 1.0, 1.0, z0, "black")]
    for k, (y0, y1, plate, led) in enumerate(rows):
        out.append((.0667, y0, z0, .9333, y1, z1, plate))
        out.append((.1333, y0 + .03, z1, .2333, y0 + .07, zl, led))
        if k % 2 == 0:
            out.append((.5, y0 + .03, z1, .8667, y0 + .07, zl, "black"))
    return out


# ---- carts / stands ---------------------------------------------------------------------------

def lp_cart(frame="steel", tub="black"):
    return [
        (0, .6, 0, 1, .7, 1, frame),
        (.04, 0, .1, .12, .6, .9, frame),
        (.88, 0, .1, .96, .6, .9, frame),
        (.1, .7, .2, .5, .9, .6, tub),
        (.6, .7, .3, .9, .76, .8, "amber"),
    ]


def lp_clean_cart(frame="steel", wheel="black"):
    return [
        (0, .2, 0, 1, .26, 1, frame),
        (.02, 0, .1, .1, .2, .9, wheel),
        (.9, 0, .1, .98, .2, .9, wheel),
        (.05, .26, .1, .55, .8, .9, "blue"),
        (.6, .26, .1, .9, .6, .9, "yellow"),
        (.9, .26, 0, 1, 1, 1, frame),
    ]


# ---- cables -----------------------------------------------------------------------------------

def lp_cable_coil():
    """Square coil ring of four runs + steel plug (was ring + two cross loops + plug)."""
    a, b = .125, .875
    return [
        (0.0, 0.0, a, a, 1.0, b, "black"),
        (b, 0.0, a, 1.0, 1.0, b, "black"),
        (a, 0.0, 0.0, b, 1.0, a, "black"),
        (a, 0.0, b, b, 1.0, 1.0, "black"),
        (.375, 0.0, .45, .625, .6666666666666667, .55, "steel"),
    ]


def lp_cable_run():
    """Yellow cover strips either side of the black cable (no buried box)."""
    return [
        (0.0, 0.0, 0.2, 1.0, 1.0, 0.4, "yellow"),
        (0.0, 0.0, 0.4, 1.0, 1.0, 0.6, "black"),
        (0.0, 0.0, 0.6, 1.0, 1.0, 0.8, "yellow"),
    ]


# ---- lava pipes -------------------------------------------------------------------------------

def lp_lava_manifold():
    return [
        (0, .3, .2, 1, .6, .8, "rust"),
        (.1, 0, .3, .26, .3, .7, "rust"),
        (.74, 0, .3, .9, .3, .7, "rust"),
        (.4, .6, .3, .6, 1, .7, "rust"),
        (0, .35, .1, .1, .55, .9, "steel"),
        (.9, .35, .1, 1, .55, .9, "steel"),
        (.44, .4, .8, .56, .5, 1, "amber"),
    ]


def lp_lava_vent():
    return [
        (.05, 0, .05, .95, .3, .95, "black"),
        (.2, .3, .2, .8, .5, .8, "black"),
        (.3, .5, .3, .7, .6, .7, "amber"),
    ]


# ---- gas cylinders ----------------------------------------------------------------------------

def lp_gas_rack():
    """Base, back plate, retaining strap and three cylinders as body + valve (shoulders and labels dropped)."""
    y_base, y_body, y_valve = 0.03636363636363636, 0.8484848484848485, 0.9818181818181819
    out = [
        (0.0, 0.0, 0.0, 1.0, y_base, 1.0, "steel"),
        (0.0, y_base, 0.0, 1.0, 0.787878787878788, 0.08888888888888889, "steel"),
        (0.0, 0.5757575757575758, 0.08888888888888889, 1.0, 0.6, 0.8444444444444444, "black"),
    ]
    for x0, x1, kind in ((0.0526, 0.3158, "green"), (0.3684, 0.6316, "grey"), (0.6842, 0.9474, "blue")):
        out.append((x0, y_base, 0.17777777777777778, x1, y_body, 0.7333333333333334, kind))
        cx = (x0 + x1) / 2
        out.append((cx - .045, y_body, 0.37777777777777777, cx + .045, y_valve, 0.5333333333333333, "brass"))
    return out


# ---- control console / monitor wall -----------------------------------------------------------

def lp_control_console():
    """Desk, top, tilted button panel with four button blocks (was eleven), keyboard, three angled monitors, e-stop."""
    y_top = 0.5571428571428572
    p = lambda x: [0.0, 25.0, 0.0] if x < .3 else ([0.0, -25.0, 0.0] if x > .7 else None)
    out = [
        (0.0, 0.0, 0.0, 1.0, 0.5142857142857143, 0.7, "grey"),
        (0.0, 0.5142857142857143, 0.0, 1.0, y_top, 1.0, "black"),
        (0.041666666666666664, y_top, 0.55, 0.9583333333333334, 0.6, 0.9, "steel", (12, 0, 0), (0.5, y_top, 0.72)),
        (0.083, 0.6, 0.62, 0.283, 0.6214285714285714, 0.7, "red"),
        (0.292, 0.6, 0.62, 0.45, 0.6214285714285714, 0.7, "green"),
        (0.5, 0.6, 0.62, 0.7, 0.6214285714285714, 0.7, "amber"),
        (0.708, 0.6, 0.62, 0.867, 0.6214285714285714, 0.7, "blue"),
        (0.4166666666666667, 0.5642857142857144, 0.78, 0.5833333333333334, 0.5857142857142857, 0.92, "black"),
    ]
    for sx0, sx1, bx0, bx1, rot, piv in (
            (0.16666666666666669, 0.20833333333333334, 0.041666666666666664, 0.3333333333333333, (0, 25, 0), 0.1875),
            (0.47916666666666663, 0.5208333333333334, 0.3541666666666667, 0.6458333333333334, None, 0.5),
            (0.7916666666666667, 0.8333333333333334, 0.6666666666666666, 0.9583333333333334, (0, -25, 0), 0.8125)):
        out.append((sx0, y_top, 0.25, sx1, 0.6571428571428573, 0.33, "black"))
        if rot:
            pv = (piv, 0.5714285714285715, 0.3)
            out.append((bx0, 0.6571428571428573, 0.22, bx1, 0.9857142857142857, 0.27, "black", rot, pv))
            out.append((bx0 + .0125, 0.6785714285714286, 0.27, bx1 - .0125, 0.9642857142857144, 0.275, "screen", rot, pv))
        else:
            out.append((bx0, 0.6571428571428573, 0.22, bx1, 0.9857142857142857, 0.27, "black"))
            out.append((bx0 + .0125, 0.6785714285714286, 0.27, bx1 - .0125, 0.9642857142857144, 0.275, "screen"))
    out.append((0.8958333333333334, y_top, 0.1, 0.9583333333333334, 0.7, 0.25, "red"))
    return out


def lp_monitor_wall():
    """Backboard + 4x3 screens (label strips dropped) + red alarm light."""
    cols = (0.017, 0.263, 0.508, 0.754)
    rows = ((0.029, 0.321), (0.35, 0.643), (0.671, 0.964))
    green = {(0, 0), (3, 0), (2, 1), (1, 2)}
    out = [(0.0, 0.0, 0.0, 1.0, 1.0, 0.5, "black")]
    for r, (y0, y1) in enumerate(rows):
        for c, x0 in enumerate(cols):
            out.append((x0, y0, 0.5, x0 + 0.229, y1, 0.6, "green" if (c, r) in green else "screen"))
    out.append((0.375, 0.929, 0.6, 0.625, 0.986, 0.7, "red"))
    return out


def lp_hazard_sign():
    """Black base + four-step warning triangle (was seven) + exclamation mark."""
    return [
        (0.0, 0.0, 0.0, 1.0, 0.065, 0.6, "black"),
        (0.033, 0.065, 0.0, 0.967, 0.29, 0.6, "@hazard"),
        (0.15, 0.29, 0.0, 0.85, 0.516, 0.6, "@hazard"),
        (0.267, 0.516, 0.0, 0.733, 0.742, 0.6, "@hazard"),
        (0.383, 0.742, 0.0, 0.617, 0.968, 0.6, "@hazard"),
        (0.45, 0.258, 0.6, 0.55, 0.581, 0.8, "black"),
        (0.45, 0.129, 0.6, 0.55, 0.21, 0.8, "black"),
    ]


# ---- bin / office machines --------------------------------------------------------------------

def lp_trash_bin():
    """Pedal bin: body, black foot ring, tilted lid, pedal (rim band dropped)."""
    return [
        (0.12, 0.0, 0.10714285714285712, 0.88, 0.8, 0.8928571428571428, "steel"),
        (0.0, 0.0, 0.0, 1.0, 0.08, 1.0, "black"),
        (0.0, 0.8, 0.0, 1.0, 0.88, 0.7857142857142857, "steel", (-10, 0, 0), (0.5, 0.8, 0.0)),
        (0.3, 0.0, 0.7857142857142857, 0.7, 0.08, 1.0, "black"),
    ]


def lp_copier(body="concrete", top="steel", tray="black"):
    return [
        (0, 0, 0, 1, .6, 1, body),
        (0, .6, 0, 1, .8, 1, top),
        (.05, .8, .1, .95, .9, .9, "glass"),
        (.6, .6, .8, .9, .66, 1, "screen"),
        (.1, .3, .98, .5, .4, 1, tray),
    ]


def lp_printer(body="concrete", tray="black"):
    return [
        (0, 0, 0, 1, .7, 1, body),
        (.1, .7, .2, .9, .9, .7, "white"),
        (.1, .05, .96, .9, .15, 1, tray),
        (.7, .55, .98, .85, .62, 1, "screen"),
    ]


def lp_shredder(bin_="black", head="steel"):
    return [
        (.05, 0, .05, .95, .7, .95, bin_),
        (0, .7, 0, 1, .9, 1, head),
        (.1, .9, .3, .9, 1, .7, bin_),
    ]


def lp_cooler(tap="red"):
    """Cabinet, bottle, one tap pair merged into a single strip with a coloured hot tap."""
    return [
        (.05, 0, .05, .95, .55, .95, "white"),
        (.2, .55, .2, .8, .95, .8, "water"),
        (.35, .3, .95, .65, .4, 1, "blue"),
        (.35, .2, .95, .65, .28, 1, tap),
    ]


def lp_partition():
    return [
        (0, 0, 0, 1, .06, 1, "black"),
        (.02, .06, .2, .98, 1, .8, "@cloth"),
    ]


def lp_retro(case="paper", bezel="black"):
    """Base plate, CRT case, bezel, screen, keyboard."""
    return [
        (0, 0, .1, 1, .12, .9, case),
        (.1, .12, .15, .9, .9, .85, case),
        (.18, .24, .85, .82, .82, .92, bezel),
        (.22, .3, .92, .78, .76, 1, "screen"),
        (.1, 0.0, .86, .9, .06, 1, case),
    ]


for _n in ("serverRack", "breakerCabinet"):
    _sw_keep_variants(_n, [lp_rack("black", "steel"), lp_rack("black", "grey"), lp_rack("grey", "black")])
_sw_keep_variants("utilityCart", [lp_cart("steel", "black"), lp_cart("grey", "black"), lp_cart("black", "grey")])
_sw_keep_one("backstageRepairStand", lp_cart("steel", "black"))
_sw_keep_variants("maintenanceCleaningCart", [lp_clean_cart("steel", "black"), lp_clean_cart("grey", "black"), lp_clean_cart("black", "grey")])
_sw_keep_one("cableCoil", lp_cable_coil())
_sw_keep_one("cableRun", lp_cable_run())
_sw_keep_one("lavaPipeManifold", lp_lava_manifold())
_sw_keep_one("lavaVent", lp_lava_vent())
_sw_keep_one("gasCylinderRack", lp_gas_rack())
_sw_keep_one("controlConsole", lp_control_console())
_sw_keep_one("monitorWall", lp_monitor_wall())
_sw_keep_one("hazardSign", lp_hazard_sign())
_sw_keep_variants("trashBin", [lp_trash_bin(), lp_trash_bin()])
_sw_keep_variants("officePhotocopier", [lp_copier("concrete", "steel", "black"), lp_copier("stone", "grey", "black"), lp_copier("grey", "black", "grey")])
_sw_keep_variants("officePrinter", [lp_printer("concrete", "black"), lp_printer("stone", "black"), lp_printer("grey", "grey")])
_sw_keep_variants("officeShredder", [lp_shredder("black", "steel"), lp_shredder("black", "grey"), lp_shredder("grey", "black")])
_sw_keep_variants("officeWaterCooler", [lp_cooler("red"), lp_cooler("teal"), lp_cooler("plum")])
_sw_keep_one("officeCubiclePartition", lp_partition())
for _n in ("officeCrtSecurityConsole", "retroComputerDesktop", "retroComputerCompact", "retroComputerTower", "retroComputerTerminal"):
    _sw_keep_variants(_n, [lp_retro("paper", "black"), lp_retro("linen", "black"), lp_retro("white", "grey")])
_sw_keep_one("rackGear", lp_rack_gear())

LOWPOLY.update(_SEWER_078)
