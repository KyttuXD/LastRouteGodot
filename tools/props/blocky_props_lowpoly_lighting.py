"""Lighting/fixtures group: 17 types redone low-poly.
Exec'd by build_blocky_props.py after SIZE_SCALE and before mansion finishes.
Keep type ids, variant slot counts, TARGET_SIZE / SIZE_SCALE bounds, fronts, colliders, atlas tiles.
Fewer boxes, no fancy bevels, share materials; hidden_faces() via LOWPOLY.
"""

_LIGHTS_078 = [
    "tableLamp", "bedsideLamp", "floorLamp", "ceilingLight", "wallSconce",
    "tableCandelabra", "gothicBedsideCandelabra", "gothicFloorCandelabra",
    "diningChandelier", "ceilingFan", "surgicalLight", "emberBrazier",
    "infernoChainLantern", "stageLightRig",
]


def _keep_variants(name, shapes):
    old = [PROPS[name]] + list(VARIANTS.get(name, []))
    assert len(old) == len(shapes), (name, len(old), len(shapes))
    PROPS[name] = (shapes[0], old[0][1])
    VARIANTS[name] = [(s, o[1]) for s, o in zip(shapes[1:], old[1:])]


def _keep_one(name, shapes):
    assert name in PROPS and not VARIANTS.get(name), (name, VARIANTS.get(name))
    assert len(shapes) == 1, (name, len(shapes))
    PROPS[name] = (shapes[0], PROPS[name][1])


def lp_lamp(layers=1):
    """Base + pole + one shade slab (was many shade layers). Fill footprint for scale_fit short."""
    shade_bot = 0.72
    return [
        (0.18, 0, 0.18, 0.82, 0.08, 0.82, "dark"),
        (0.44, 0.08, 0.44, 0.56, shade_bot, 0.56, "brass"),
        (0.02, shade_bot, 0.02, 0.98, 1.0, 0.98, "@shade"),
    ]


def lp_floor_lamp(tall=True):
    """Fill TARGET width (~0.38 m) so hunter-scale short stays in lamp range."""
    shade_bot = 0.78 if tall else 0.82
    return [
        (0.05, 0, 0.05, 0.95, 0.04, 0.95, "dark"),
        (0.44, 0.04, 0.44, 0.56, shade_bot, 0.56, "brass"),
        (0.02, shade_bot, 0.02, 0.98, 1.0, 0.98, "@shade"),
    ]


def lp_ceiling():
    return [
        (0.05, 0.75, 0.05, 0.95, 1.0, 0.95, "steel"),
        (0.18, 0.25, 0.18, 0.82, 0.75, 0.82, "amber"),
        (0.05, 0.0, 0.05, 0.95, 0.25, 0.95, "steel"),
    ]


def lp_sconce():
    return [
        (0.2, 0.0, 0.0, 0.8, 1.0, 0.18, "brass"),
        (0.3, 0.2, 0.18, 0.7, 0.8, 0.55, "amber"),
        (0.28, 0.08, 0.18, 0.72, 0.18, 0.6, "brass"),
    ]


def lp_table_candelabra():
    return [
        (0.2, 0, 0.3, 0.8, 0.1, 0.7, "brass"),
        (0.46, 0.1, 0.44, 0.54, 0.55, 0.56, "brass"),
        (0.1, 0.55, 0.4, 0.9, 0.62, 0.6, "brass"),
        (0.12, 0.62, 0.42, 0.28, 0.9, 0.58, "amber"),
        (0.72, 0.62, 0.42, 0.88, 0.9, 0.58, "amber"),
        (0.42, 0.62, 0.42, 0.58, 1.0, 0.58, "amber"),
    ]


def lp_gothic_bedside_candelabra():
    return [
        (0.1, 0, 0.1, 0.9, 0.1, 0.9, "brass"),
        (0.44, 0.1, 0.44, 0.56, 0.6, 0.56, "brass"),
        (0.1, 0.6, 0.4, 0.9, 0.66, 0.6, "brass"),
        (0.15, 0.66, 0.42, 0.35, 0.95, 0.58, "amber"),
        (0.65, 0.66, 0.42, 0.85, 0.95, 0.58, "amber"),
        (0.42, 0.66, 0.42, 0.58, 1.0, 0.58, "amber"),
    ]


def lp_gothic_floor_candelabra():
    return [
        (0.1, 0, 0.1, 0.9, 0.05, 0.9, "brass"),
        (0.46, 0.05, 0.4, 0.54, 0.8, 0.6, "brass"),
        (0.0, 0.8, 0.4, 1.0, 0.84, 0.6, "brass"),
        (0.08, 0.84, 0.42, 0.22, 1.0, 0.58, "amber"),
        (0.78, 0.84, 0.42, 0.92, 1.0, 0.58, "amber"),
        (0.42, 0.84, 0.42, 0.58, 1.0, 0.58, "amber"),
    ]


def lp_chandelier():
    # keep original vertical span (pendant down to ~0.2) so height matches staging
    return [
        (0.44, 0.7, 0.44, 0.56, 1.0, 0.56, "brass"),
        (0.15, 0.5, 0.15, 0.85, 0.6, 0.85, "brass"),
        (0.12, 0.6, 0.12, 0.28, 0.75, 0.28, "amber"),
        (0.72, 0.6, 0.12, 0.88, 0.75, 0.28, "amber"),
        (0.12, 0.6, 0.72, 0.28, 0.75, 0.88, "amber"),
        (0.72, 0.6, 0.72, 0.88, 0.75, 0.88, "amber"),
        (0.4, 0.2, 0.4, 0.6, 0.5, 0.6, "amber"),
    ]


def lp_ceiling_fan():
    return [
        (0.44, 0.6, 0.44, 0.56, 1.0, 0.56, "steel"),
        (0.38, 0.35, 0.38, 0.62, 0.6, 0.62, "black"),
        (0.0, 0.38, 0.44, 1.0, 0.48, 0.56, "oak"),
        (0.44, 0.38, 0.0, 0.56, 0.48, 1.0, "oak"),
    ]


def lp_surgical():
    w, h, d = 1.5, 0.9, 1.5
    c = Part(w, h, d)
    c.add(0.7, 0.82, 0.7, 0.8, h, 0.8, "steel")
    c.add(0.72, 0.55, 0.72, 0.78, 0.82, 0.78, "steel")
    c.add(0.2, 0.55, 0.72, 1.3, 0.62, 0.78, "steel")
    c.add(0.15, 0.3, 0.55, 0.55, 0.55, 0.95, "white")
    c.add(0.95, 0.3, 0.55, 1.35, 0.55, 0.95, "white")
    c.add(0.2, 0.26, 0.6, 0.5, 0.3, 0.9, "amber")
    c.add(1.0, 0.26, 0.6, 1.3, 0.3, 0.9, "amber")
    return c.boxes


def lp_brazier():
    return [
        (0.2, 0, 0.2, 0.8, 0.1, 0.8, "black"),
        (0.4, 0.1, 0.4, 0.6, 0.5, 0.6, "black"),
        (0.08, 0.5, 0.08, 0.92, 0.62, 0.92, "black"),
        (0.18, 0.62, 0.18, 0.82, 0.85, 0.82, "rust"),
        (0.3, 0.85, 0.3, 0.7, 1.0, 0.7, "amber"),
    ]


def lp_chain_lantern():
    return [
        (0.44, 0.7, 0.44, 0.56, 1.0, 0.56, "steel"),
        (0.22, 0.5, 0.22, 0.78, 0.7, 0.78, "black"),
        (0.28, 0.12, 0.28, 0.72, 0.5, 0.72, "amber"),
        (0.22, 0, 0.22, 0.78, 0.12, 0.78, "black"),
    ]


def lp_stage_rig():
    w, h, d = 3.0, 2.4, 0.4
    c = Part(w, h, d)
    for x in (0.0, w - 0.12):
        c.add(x - 0.08, 0.0, 0.08, x + 0.2, 0.05, 0.32, "black")
        c.add(x, 0.05, 0.14, x + 0.12, 2.25, 0.26, "steel")
    c.add(0.0, 2.2, 0.12, w, h, 0.28, "steel")
    for i, col in enumerate(["red", "blue", "amber", "plum"]):
        x = 0.45 + i * 0.6
        c.add(x, 1.9, 0.1, x + 0.2, 2.2, 0.32, "black")
        c.add(x + 0.03, 1.92, 0.3, x + 0.17, 2.05, 0.33, col)
    return c.boxes


# ---- apply --------------------------------------------------------------------------------------
_keep_variants("tableLamp", [lp_lamp(), lp_lamp()])
_keep_variants("bedsideLamp", [lp_lamp(), lp_lamp()])
_keep_variants("floorLamp", [lp_floor_lamp(True), lp_floor_lamp(False)])
_keep_one("ceilingLight", [lp_ceiling()])
_keep_one("wallSconce", [lp_sconce()])
_keep_one("tableCandelabra", [lp_table_candelabra()])
_keep_one("gothicBedsideCandelabra", [lp_gothic_bedside_candelabra()])
_keep_one("gothicFloorCandelabra", [lp_gothic_floor_candelabra()])
_keep_one("diningChandelier", [lp_chandelier()])
_keep_one("ceilingFan", [lp_ceiling_fan()])
_keep_one("surgicalLight", [lp_surgical()])
_keep_one("emberBrazier", [lp_brazier()])
_keep_one("infernoChainLantern", [lp_chain_lantern()])
_keep_one("stageLightRig", [lp_stage_rig()])

LOWPOLY.update(_LIGHTS_078)
LOWPOLY.update(n + "Mansion" for n in _LIGHTS_078)
