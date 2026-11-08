"""Tables/desks group: 17 base types (+ mansion finishes) redone low-poly.
Exec'd by build_blocky_props.py after SIZE_SCALE and before mansion finishes.
Keep type ids, variant slot counts, TARGET_SIZE / SIZE_SCALE bounds, front, colliders, atlas tiles.
Fewer boxes, no fancy bevels, share materials; hidden_faces() via LOWPOLY.
"""

_TABLES_078 = [
    "woodenTable", "diningTable", "restaurantPartyTable", "officeDesk", "normalCoffeeTable",
    "mansionConsoleTable", "gothicPedestalTable", "gothicWritingDesk", "foodCourtTable",
    "prisonCafeteriaTable", "readingTable", "receptionDesk", "checkoutCounter", "operatingTable",
    "autopsyTable", "mixingDesk", "officeCornerWorkstation",
]


def _keep_variants(name, shapes):
    old = [PROPS[name]] + list(VARIANTS.get(name, []))
    assert len(old) == len(shapes), (name, len(old), len(shapes))
    PROPS[name] = (shapes[0], old[0][1])
    VARIANTS[name] = [(s, o[1]) for s, o in zip(shapes[1:], old[1:])]


def lp_table(w, d, top=0.75, drawer=False, kind="@wood", leg="dark", style="legs"):
    """Chunky table: thick legs or trestle/pedestal, one slab top; apron is one frame box max."""
    t = Part(w, top, d)
    slab = VOX
    lw = 0.14
    if style == "legs":
        for x in (0.04, w - 0.04 - lw):
            for z in (0.04, d - 0.04 - lw):
                t.add(x, 0, z, x + lw, top - slab, z + lw, leg)
        # single apron ring (four thin sides collapsed to one under-top skirt box on each long/short - 2 boxes)
        t.add(0.04, top - slab - 0.14, 0.04, w - 0.04, top - slab, d - 0.04, leg)
        if drawer:
            t.add(w * 0.32, top - slab - 0.12, d - 0.05, w * 0.68, top - slab - 0.02, d - 0.005, "oak")
    elif style == "trestle":
        for x in (0.12, w - 0.12 - lw):
            t.add(x, 0, 0.1, x + lw, top - slab, d - 0.1, leg)
        t.add(0.12 + lw, 0.18, d / 2 - 0.05, w - 0.12 - lw, 0.28, d / 2 + 0.05, leg)
    elif style == "pedestal":
        t.add(w / 2 - 0.28, 0, d / 2 - 0.28, w / 2 + 0.28, 0.1, d / 2 + 0.28, leg)
        t.add(w / 2 - 0.12, 0.1, d / 2 - 0.12, w / 2 + 0.12, top - slab, d / 2 + 0.12, leg)
    t.add(0, top - slab, 0, w, top, d, kind)
    return t.boxes


def lp_restaurant():
    """Party table + cloth + fewer place settings + 2 balloons (was denser cluster). Bounds stay 2.62 x 2.23 x 1.0."""
    w, h, d = 2.62, 2.23, 1.0
    t = Part(w, h, d)
    for x in (0.12, w - 0.24):
        for z in (0.12, d - 0.24):
            t.add(x, 0, z, x + 0.12, 0.56, z + 0.12, "dark")
    t.add(0.04, 0.56, 0.04, w - 0.04, 0.69, d - 0.04, "dark")
    t.add(0, 0.69, 0, w, 0.75, d, "plum")
    # cloth skirt: one box per side (4)
    t.add(0, 0.5, 0, w, 0.69, 0.06, "plum")
    t.add(0, 0.5, d - 0.06, w, 0.69, d, "plum")
    t.add(0, 0.5, 0.06, 0.06, 0.69, d - 0.06, "plum")
    t.add(w - 0.06, 0.5, 0.06, w, 0.69, d - 0.06, "plum")
    for i in range(2):  # was 4 place settings
        x = 0.7 + i * 1.0
        t.add(x, 0.75, 0.22, x + 0.18, 0.78, 0.4, "paper")
        t.add(x, 0.75, d - 0.4, x + 0.18, 0.78, d - 0.22, "paper")
        t.add(x + 0.22, 0.75, 0.26, x + 0.3, 0.86, 0.34, "blue")
    t.add(w / 2 - 0.02, 0.75, d / 2 - 0.02, w / 2 + 0.02, 1.75, d / 2 + 0.02, "steel")
    t.add(w / 2 - 0.22, 1.7, d / 2 - 0.14, w / 2 + 0.02, 2.05, d / 2 + 0.12, "plum")
    t.add(w / 2 - 0.05, 1.9, d / 2 - 0.05, w / 2 + 0.22, 2.23, d / 2 + 0.14, "red")
    return t.boxes


def lp_office_desk(kind="oak", pedestals=True, hutch=False):
    """Unit-space desk; top at y=1 → TARGET 0.75 m. Hutch = front drawers only (no tall riser)."""
    c = Part(1.0, 1.0, 1.0)
    c.add(0, 0.86, 0, 1, 1, 1, kind)
    if pedestals:
        c.add(0.02, 0, 0.04, 0.28, 0.86, 0.96, "steel" if kind == "oak" else kind)
        c.add(0.72, 0, 0.04, 0.98, 0.86, 0.96, "steel" if kind == "oak" else kind)
    else:
        c.add(0.02, 0, 0.04, 0.12, 0.86, 0.96, "steel")
        c.add(0.88, 0, 0.04, 0.98, 0.86, 0.96, "steel")
        c.add(0.12, 0.5, 0.1, 0.88, 0.56, 0.16, "steel")
    if hutch:
        # drawers on the left pedestal face (staging variant 1 look), stay under the top
        c.add(0.04, 0.55, 0.96, 0.26, 0.78, 1.0, "steel")
        c.add(0.04, 0.28, 0.96, 0.26, 0.48, 1.0, "steel")
        c.add(0.04, 0.06, 0.96, 0.26, 0.22, 1.0, "steel")
        c.add(0.9, 0, 0.04, 0.98, 0.86, 0.2, "steel")
        c.add(0.9, 0, 0.8, 0.98, 0.86, 0.96, "steel")
    return c.boxes


def lp_coffee():
    return [(0, .8, 0, 1, 1, 1, "@wood"),
            (.06, 0, .1, .2, .8, .28, "dark"), (.8, 0, .1, .94, .8, .28, "dark"),
            (.06, 0, .72, .2, .8, .9, "dark"), (.8, 0, .72, .94, .8, .9, "dark")]


def lp_console(i=0):
    """mansionConsoleTable: fill TARGET/bounds height (top at y=1)."""
    if i == 0:
        return [(0, 0, 0, 1, 0.86, 1, "@wood"), (0.04, 0.86, 0.05, 0.96, 1.0, 0.95, "@wood"),
                (0.08, 0.4, 0.85, 0.45, 0.72, 0.98, "oak"), (0.55, 0.4, 0.85, 0.92, 0.72, 0.98, "oak")]
    if i == 1:
        return [(0, 0, 0, 1, 0.92, 1, "@wood"), (0, 0.92, 0, 1, 1.0, 1, "@wood"),
                (0.05, 0.5, 0.08, 0.95, 0.56, 0.92, "dark")]
    return [(0.05, 0, 0.1, 0.95, 0.82, 0.9, "@wood"), (0, 0.82, 0, 1, 1.0, 1, "@wood"),
            (0.1, 0.35, 0.82, 0.9, 0.62, 0.95, "oak")]


def lp_gothic_pedestal():
    return [(.1, 0, .1, .9, .12, .9, "dark"), (.38, .12, .38, .62, .8, .62, "dark"), (0, .8, 0, 1, 1, 1, "@wood")]


def lp_gothic_desk(i=0):
    if i == 0:
        return [(0, .8, 0, 1, 1, 1, "dark"),
                (.05, 0, .05, .15, .8, .95, "dark"), (.85, 0, .05, .95, .8, .95, "dark"),
                (.1, .5, .1, .5, .8, .9, "oak"), (.54, .84, .3, .9, .88, .7, "paper")]
    if i == 1:
        return [(0, .82, 0, 1, 1, 1, "dark"), (.08, 0, .08, .2, .82, .92, "dark"),
                (.8, 0, .08, .92, .82, .92, "dark"), (.2, .4, .15, .8, .5, .85, "oak")]
    return [(0, .78, 0, 1, 1, 1, "oak"), (.1, 0, .1, .9, .78, .2, "dark"),
            (.1, 0, .8, .9, .78, .9, "dark"), (.15, .78, .2, .85, .82, .75, "paper")]


def lp_food_court():
    # metres on TARGET (1.7, 0.78, 1.7); seats stay under top so height stays 0.78 (~staging 0.81)
    w, h, d = 1.7, 0.78, 1.7
    c = Part(w, h, d)
    c.add(0.25, 0, 0.25, w - 0.25, 0.08, d - 0.25, "steel")
    c.add(w * 0.42, 0.08, d * 0.42, w * 0.58, 0.7, d * 0.58, "steel")
    c.add(0.08, 0.7, 0.08, w - 0.08, 0.76, d - 0.08, "@top")
    c.add(w * 0.45, 0.76, d * 0.45, w * 0.55, 0.81, d * 0.55, "white")  # napkin / tip like staging
    for x, z in ((0.08, 0.08), (w - 0.28, 0.08), (0.08, d - 0.28), (w - 0.28, d - 0.28)):
        c.add(x, 0, z, x + 0.2, 0.45, z + 0.2, "@seat")
    return c.boxes


def lp_prison_cafe(i=0):
    if i == 0:
        return [(0, .86, 0, 1, 1, 1, "concrete"),
                (.04, 0, .1, .12, .86, .9, "steel"), (.88, 0, .1, .96, .86, .9, "steel"),
                (0, .3, 0, 1, .4, .08, "steel"), (0, .3, .92, 1, .4, 1, "steel")]
    if i == 1:
        return [(0, .86, 0, 1, 1, 1, "concrete"),
                (.2, 0, .2, .8, .86, .8, "steel")]
    return [(0, .86, 0, 1, 1, 1, "steel"),
            (.05, 0, .05, .15, .86, .95, "steel"), (.85, 0, .05, .95, .86, .95, "steel")]


def lp_reading():
    # metres on TARGET (1.5, 0.75, 0.88) — top flush at design height
    w, h, d = 1.5, 0.75, 0.88
    c = Part(w, h, d)
    for x in (0.06, w - 0.14):
        for z in (0.06, d - 0.14):
            c.add(x, 0, z, x + 0.08, h - 0.06, z + 0.08, "@wood")
    c.add(0.1, 0.35, 0.1, w - 0.1, 0.42, d - 0.1, "dark")
    c.add(0, h - 0.06, 0, w, h, d, "@wood")
    return c.boxes


def lp_reception():
    return [(0, 0.55, 0, 1, 1.0, 0.55, "@wood"), (0, 0.0, 0, 1, 0.55, 0.5, "@wood"),
            (0.05, 0.7, 0.55, 0.95, 0.95, 0.95, "@wood"), (0.1, 0.55, 0.6, 0.9, 0.62, 0.9, "oak")]


def lp_checkout():
    # metres on TARGET (1.8, 1.32, 0.75); register stays under 1.32
    w, h, d = 1.8, 1.32, 0.75
    c = Part(w, h, d)
    c.add(0, 0, 0, w, 0.92, d, "@wood")
    c.add(0, 0.92, 0, w, 0.96, d, "black")
    c.add(0.15, 0.96, 0.15, 0.55, 1.08, 0.55, "grey")
    c.add(0.2, 1.08, 0.2, 0.5, 1.1, 0.5, "black")
    c.add(0.25, 1.1, 0.2, 0.48, h, 0.26, "black")  # display tip = design height
    c.add(1.2, 0.96, 0.1, 1.7, 1.2, 0.25, "oak")
    return c.boxes


def lp_operating():
    w, h, d = 0.75, 1.00, 2.00
    c = Part(w, h, d)
    c.add(0.08, 0.7, 0.1, w - 0.08, 0.85, d - 0.1, "white")
    for x, z in ((0.12, 0.15), (w - 0.28, 0.15), (0.12, d - 0.35), (w - 0.28, d - 0.35)):
        c.add(x, 0, z, x + 0.16, 0.7, z + 0.2, "steel")
    c.add(0.1, 0.85, 0.12, w - 0.1, h, d - 0.12, "white")
    return c.boxes


def lp_autopsy():
    w, h, d = 0.85, 0.95, 2.00
    c = Part(w, h, d)
    c.add(0.05, 0.65, 0.05, w - 0.05, 0.8, d - 0.05, "steel")
    for x, z in ((0.1, 0.1), (w - 0.3, 0.1), (0.1, d - 0.3), (w - 0.3, d - 0.3)):
        c.add(x, 0, z, x + 0.2, 0.65, z + 0.2, "steel")
    c.add(0.1, 0.8, 0.1, w - 0.1, h, d - 0.1, "steel")
    return c.boxes


def lp_mixing():
    w, h, d = 1.5, 0.95, 0.8
    c = Part(w, h, d)
    c.add(0, 0.55, 0, w, 0.75, d, "black")
    c.add(0.05, 0, 0.08, 0.2, 0.55, d - 0.08, "dark")
    c.add(w - 0.2, 0, 0.08, w - 0.05, 0.55, d - 0.08, "dark")
    c.add(0.1, 0.75, 0.08, w - 0.1, 0.88, d - 0.08, "steel")
    c.add(0.15, 0.88, 0.15, w - 0.15, h, d - 0.2, "black")
    return c.boxes


def lp_corner(i=0):
    # fill bounds height (top at y=1)
    if i == 0:
        return [(0, .86, 0, 1, 1, .5, "oak"), (0, .86, .5, .5, 1, 1, "oak"),
                (.02, 0, .04, .12, .86, .46, "steel"), (.9, 0, .04, .98, .86, .46, "steel"),
                (.02, 0, .54, .12, .86, .96, "steel")]
    if i == 1:
        return [(0, .86, 0, 1, 1, .55, "dark"), (0, .86, .55, .55, 1, 1, "dark"),
                (.05, 0, .05, .15, .86, .95, "dark"), (.85, 0, .05, .95, .86, .5, "dark")]
    return [(0, .86, 0, .7, 1, 1, "oak"), (.7, .86, 0, 1, 1, .5, "oak"),
            (.05, 0, .05, .15, .86, .95, "steel"), (.85, 0, .05, .95, .86, .45, "steel")]


# ---- apply --------------------------------------------------------------------------------------
_keep_variants("woodenTable", [
    lp_table(1.2, 0.78),
    lp_table(1.2, 0.78, drawer=True),
    lp_table(1.2, 0.78, style="trestle"),
    lp_table(1.2, 0.78, style="pedestal"),
])
_keep_variants("diningTable", [
    lp_table(2.2, 0.84),
    lp_table(2.2, 0.84, style="trestle"),
    lp_table(2.2, 0.84, style="pedestal"),
])
PROPS["restaurantPartyTable"] = (lp_restaurant(), PROPS["restaurantPartyTable"][1])
_keep_variants("officeDesk", [
    lp_office_desk("oak", True, False),
    lp_office_desk("dark", True, True),
    lp_office_desk("oak", False, False),
])
# normalCoffeeTable: 1 shape slot
PROPS["normalCoffeeTable"] = (lp_coffee(), PROPS["normalCoffeeTable"][1])
_keep_variants("mansionConsoleTable", [lp_console(0), lp_console(1), lp_console(2)])
PROPS["gothicPedestalTable"] = (lp_gothic_pedestal(), PROPS["gothicPedestalTable"][1])
_keep_variants("gothicWritingDesk", [lp_gothic_desk(0), lp_gothic_desk(1), lp_gothic_desk(2)])
_reg("foodCourtTable", lp_food_court(), TARGET_SIZE["foodCourtTable"],
     {"@seat": ["red", "teal", "yellow"], "@top": ["white", "oak"]})
_keep_variants("prisonCafeteriaTable", [lp_prison_cafe(0), lp_prison_cafe(1), lp_prison_cafe(2)])
_reg("readingTable", lp_reading(), TARGET_SIZE["readingTable"], {"@wood": ["walnut", "oak", "mahogany"]})
_reg("receptionDesk", lp_reception(), TARGET_SIZE["receptionDesk"], {"@wood": ["oak", "walnut", "ash"]})
_reg("checkoutCounter", lp_checkout(), TARGET_SIZE["checkoutCounter"],
     {"@wood": ["oak", "white", "walnut"]})
_reg("operatingTable", lp_operating(), TARGET_SIZE["operatingTable"])
_reg("autopsyTable", lp_autopsy(), TARGET_SIZE["autopsyTable"])
_reg("mixingDesk", lp_mixing(), TARGET_SIZE["mixingDesk"])
_keep_variants("officeCornerWorkstation", [lp_corner(0), lp_corner(1), lp_corner(2)])

# lock footprints to staging blocky heights (measure can undershoot after prior rebuilds)
TARGET_SIZE["officeCornerWorkstation"] = (1.90, 0.875, 1.42)
TARGET_SIZE["mansionConsoleTable"] = (1.22, 0.905, 0.442)
# desk hutch variant: surface check uses mesh AABB vs SURFACE 0.75 — keep all desks <= 0.83
TARGET_SIZE["officeDesk"] = (1.62, 0.75, 0.75)

LOWPOLY.update(_TABLES_078)
LOWPOLY.update(n + "Mansion" for n in _TABLES_078)
