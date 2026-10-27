"""Props rework 3 (DONE14): chests of drawers, lamps, kitchen appliances, bathroom fixtures, bins and crates, plus the finish
variants that give every common family 2-3 looks. exec'd by build_blocky_props.py after rework2 (Part, VOX, PROPS, VARIANTS, v,
TARGET_SIZE, CLOTH, WOODS in scope).

Everything is our own design in metres on the 6 cm grid. The thuing/ library was only looked at (proportions, how drawers, shades and
bins are broken into parts); nothing was copied.

Layering rule for fronts: carcass ends 12.5 cm short of the front, the door/drawer layer is the next 6 cm, handles are the last 6 cm, so
nothing sits coplanar and nothing leaves the footprint.
"""

# ---- chests of drawers, sideboards, nightstands, consoles -----------------------------------------------------------------
def chest(w, h, d, rows, cols, leg_h=0.12, doors=False, top="@top", wood="@wood", body="dark", pull="brass"):
    c = Part(w, h, d)
    leg = VOX
    if leg_h > 0:
        for x in (0.03, w - 0.03 - leg):
            for z in (0.03, d - 0.03 - leg):
                c.add(x, 0, z, x + leg, leg_h, z + leg, body)
    c.add(0.03, leg_h, 0, w - 0.03, h - VOX, d - 0.125, body)                    # carcass
    c.add(0, h - VOX, 0, w, h, d, top)                                              # top slab, full footprint
    c.add(0.03, leg_h, d - 0.125, w - 0.03, h - VOX, d - 0.0625, body)             # dark front layer: the gaps between fronts show it
    inner_x0, inner_x1 = 0.09, w - 0.09
    inner_y0, inner_y1 = leg_h + 0.06, h - VOX - 0.0
    if doors:
        n = max(2, cols)
        cw = (inner_x1 - inner_x0 - (n - 1) * VOX) / n
        for i in range(n):
            x0 = inner_x0 + i * (cw + VOX)
            c.add(x0, inner_y0, d - 0.0625, x0 + cw, inner_y1 - 0.06, d, wood)
        for i in range(n):                                                      # pulls are small blocks set into the door faces
            x0 = inner_x0 + i * (cw + VOX)
            hx = x0 + cw - 0.12 if i % 2 == 0 else x0 + 0.06
            c.add(hx, (inner_y0 + inner_y1) / 2 - 0.1, d - 0.0625, hx + VOX, (inner_y0 + inner_y1) / 2 + 0.06, d, pull)
        return c.boxes
    rh = (inner_y1 - inner_y0 - 0.06 - (rows - 1) * VOX) / rows
    cw = (inner_x1 - inner_x0 - (cols - 1) * VOX) / cols
    for r in range(rows):
        y0 = inner_y0 + r * (rh + VOX)
        for k in range(cols):
            x0 = inner_x0 + k * (cw + VOX)
            c.add(x0, y0, d - 0.0625, x0 + cw, y0 + rh, d, wood)                  # drawer front (outer layer)
            hx = x0 + cw / 2 - 0.0625
            c.add(hx, y0 + rh / 2 - 0.03, d - 0.0625, hx + 0.125, y0 + rh / 2 + 0.03, d, pull)   # pull set into the front
    return c.boxes


def _wood_subs():
    return {"@wood": ["oak", "walnut", "pine", "mahogany"], "@top": ["dark", "dark", "ash", "dark"]}


def register_chests():
    table = {
        "bedroomNightstand": (0.62, 0.69, 0.5, 2, 1, 0.12),
        "bedroomDresser": (1.25, 1.06, 0.56, 3, 2, 0.12),
        "gothicNightstand": (0.62, 0.81, 0.56, 2, 1, 0.18),
        "gothicDresser": (1.38, 1.12, 0.62, 3, 3, 0.18),
        "woodenDresserSideboard": (1.25, 0.94, 0.62, 2, 3, 0.12),
        "diningSideboard": (1.5, 1.06, 0.69, 2, 3, 0.12),
        "mansionConsoleTable": (1.25, 0.88, 0.44, 1, 3, 0.2),
    }
    for name, (w, h, d, rows, cols, legs) in table.items():
        base = chest(w, h, d, rows, cols, legs)
        door = chest(w, h, d, rows, cols, legs, doors=True)
        low = chest(w, h, d, max(1, rows - 1), cols, legs)
        _reg(name, base, (w, h, d), _wood_subs(), [(door, _wood_subs()), (low, {"@wood": ["walnut", "pine"], "@top": ["ash", "dark"]})])


register_chests()


# ---- lamps -------------------------------------------------------------------------------------------------------------------
def lamp(w, h, base_w, shade_layers, pole=VOX):
    c = Part(w, h, w)
    cx = w / 2
    c.add(cx - base_w / 2, 0, cx - base_w / 2, cx + base_w / 2, VOX, cx + base_w / 2, "dark")
    shade_h = VOX * shade_layers
    top = h - shade_h
    c.add(cx - pole / 2, VOX, cx - pole / 2, cx + pole / 2, top, cx + pole / 2, "brass")
    for i in range(shade_layers):
        inset = 0.0 if i < shade_layers - 1 else VOX
        wide = w - 2 * (VOX * 0.5 * (i // 2))
        x0 = cx - wide / 2 + inset / 2
        c.add(x0, top + i * VOX, x0, x0 + wide - inset, top + (i + 1) * VOX, x0 + wide - inset, "@shade")
    return c.boxes


for _name, _w, _h, _base, _layers in (("tableLamp", 0.38, 0.69, 0.25, 5), ("bedsideLamp", 0.25, 0.69, 0.19, 4)):
    _reg(_name, lamp(_w, _h, _base, _layers), (_w, _h, _w), {"@shade": ["amber", "paper", "white"]},
         [(lamp(_w, _h, _base, _layers - 1), {"@shade": ["amber", "red", "paper"]})])
_reg("floorLamp", lamp(0.38, 1.75, 0.38, 6), (0.38, 1.75, 0.38), {"@shade": ["amber", "paper", "white"]},
     [(lamp(0.38, 1.62, 0.31, 5), {"@shade": ["amber", "plum", "paper"]})])


# ---- kitchen --------------------------------------------------------------------------------------------------------------------
KITCHEN_STYLES = {"normal": ("porcelain", "steel", "oak", "black"), "luxury": ("black", "steel", "stone", "steel"),
                  "gothic": ("dark", "brass", "dark", "black")}


def stove(style, door_kind=None):
    body, trim, front, hob = KITCHEN_STYLES[style]
    w, h, d = 0.88, 0.92, 0.69
    c = Part(w, h, d)
    c.add(0, 0.06, 0, w, 0.79, d - 0.125, body)
    c.add(0, 0, 0.06, w, 0.06, d - 0.06, "black")                                    # plinth
    c.add(0, 0.79, 0, w, 0.855, d, hob)                                              # hob
    for x, z in ((0.15, 0.12), (w - 0.15 - 0.2, 0.12), (0.15, 0.37), (w - 0.15 - 0.2, 0.37)):
        c.add(x, 0.855, z, x + 0.2, h, z + 0.2, "rust")                               # burners
    c.add(0.0625, 0.1, d - 0.125, w - 0.0625, 0.7, d - 0.0625, trim)                # oven door layer
    c.add(0.2, 0.2, d - 0.0625, w - 0.2, 0.52, d, "glass")                           # window
    c.add(0.15, 0.6, d - 0.0625, w - 0.15, 0.66, d, "black")                         # handle bar
    for i in range(4):
        c.add(0.12 + i * 0.2, 0.7, d - 0.125, 0.12 + i * 0.2 + VOX, 0.79, d - 0.0625, "black")   # knobs row
    return c.boxes


def fridge(style):
    body, trim, front, hob = KITCHEN_STYLES[style]
    w, h, d = 0.88, 1.94, 0.81
    c = Part(w, h, d)
    c.add(0, 0.06, 0, w, h, d - 0.125, body)
    c.add(0, 0, 0.06, w, 0.06, d - 0.06, "black")
    c.add(0.0625, 0.12, d - 0.125, w - 0.0625, 0.74, d - 0.0625, trim)               # lower door
    c.add(0.0625, 0.8, d - 0.125, w - 0.0625, h - 0.06, d - 0.0625, trim)            # upper door
    c.add(0.0625, 0.74, d - 0.125, w - 0.0625, 0.8, d - 0.0625, "black")             # seam
    c.add(w - 0.2, 0.3, d - 0.0625, w - 0.2 + VOX, 0.62, d, "black")                 # handles
    c.add(w - 0.2, 0.9, d - 0.0625, w - 0.2 + VOX, 1.4, d, "black")
    return c.boxes


def sink(style):
    body, trim, front, hob = KITCHEN_STYLES[style]
    w, h, d = 1.25, 1.12, 0.69
    c = Part(w, h, d)
    c.add(0, 0.06, 0, w, 0.5, d - 0.125, body)
    c.add(0, 0, 0.06, w, 0.06, d - 0.06, "black")
    top_y0, top_y1 = 0.80, 0.92
    c.add(0, 0.5, 0, w, top_y0, d - 0.125, body)
    # worktop with a basin: four slabs around a hole, basin walls and floor below
    c.add(0, top_y0, 0, w, top_y1, 0.12, "stone")
    c.add(0, top_y0, d - 0.18, w, top_y1, d, "stone")
    c.add(0, top_y0, 0.12, 0.35, top_y1, d - 0.18, "stone")
    c.add(w - 0.35, top_y0, 0.12, w, top_y1, d - 0.18, "stone")
    c.add(0.35, top_y0 - 0.0, 0.12, w - 0.35, top_y0 + VOX, d - 0.18, "steel")      # basin floor
    # tap
    c.add(w / 2 - VOX / 2, top_y1, 0.06, w / 2 + VOX / 2, 1.06, 0.06 + VOX, "steel")
    c.add(w / 2 - VOX / 2, 1.06, 0.06, w / 2 + VOX / 2, 1.12, 0.3, "steel")
    for i, x0 in enumerate((0.06, 0.06 + (w - 0.12) / 2 + VOX / 2)):
        c.add(x0, 0.1, d - 0.125, x0 + (w - 0.12) / 2 - VOX / 2, 0.76, d - 0.0625, front)
        c.add(x0 + (w - 0.12) / 2 - 0.2 if i == 0 else x0 + 0.1, 0.55, d - 0.0625, x0 + (w - 0.12) / 2 - 0.14 if i == 0 else x0 + 0.16, 0.67, d, trim)
    return c.boxes


for _style in ("normal", "luxury", "gothic"):
    _reg(_style + "KitchenStove", stove(_style), (0.88, 0.92, 0.69), {})
    _reg(_style + "KitchenFridge", fridge(_style), (0.88, 1.94, 0.81), {})
    _reg(_style + "KitchenSink", sink(_style), (1.25, 1.12, 0.69), {})


# ---- bathroom -------------------------------------------------------------------------------------------------------------------
def toilet():
    w, h, d = 0.38, 0.8, 0.69
    c = Part(w, h, d)
    c.add(0.06, 0, 0.3, w - 0.06, 0.3, d - 0.06, "porcelain")                       # bowl pedestal
    c.add(0.0, 0.3, 0.26, w, 0.38, d, "porcelain")                                  # bowl rim
    c.add(0.0, 0.38, 0.3, w, 0.44, d - 0.02, "white")                               # seat and closed lid
    c.add(0.02, 0.0, 0.02, w - 0.02, 0.62, 0.26, "porcelain")                       # cistern
    c.add(0.0, 0.62, 0.0, w, 0.68, 0.28, "white")                                   # cistern lid
    c.add(w / 2 - 0.03, 0.68, 0.08, w / 2 + 0.03, 0.74, 0.14, "steel")             # flush button
    return c.boxes


def bathtub():
    w, h, d = 1.75, 0.8, 0.75
    c = Part(w, h, d)
    for x in (0.1, w - 0.1 - 0.125):
        for z in (0.08, d - 0.08 - 0.125):
            c.add(x, 0, z, x + 0.125, 0.12, z + 0.125, "brass")                       # feet
    c.add(0, 0.12, 0, w, 0.18, d, "porcelain")                                      # floor of the tub
    c.add(0, 0.18, 0, w, 0.56, 0.0625, "porcelain")
    c.add(0, 0.18, d - 0.0625, w, 0.56, d, "porcelain")
    c.add(0, 0.18, 0.0625, 0.0625, 0.56, d - 0.0625, "porcelain")
    c.add(w - 0.0625, 0.18, 0.0625, w, 0.56, d - 0.0625, "porcelain")
    c.add(0, 0.56, 0, w, 0.62, 0.125, "white")                                      # rim
    c.add(0, 0.56, d - 0.125, w, 0.62, d, "white")
    c.add(0, 0.56, 0.125, 0.125, 0.62, d - 0.125, "white")
    c.add(w - 0.125, 0.56, 0.125, w, 0.62, d - 0.125, "white")
    c.add(0.125, 0.18 + VOX, 0.0625, w - 0.125, 0.3, d - 0.0625, "water")           # water
    c.add(w - 0.3, 0.62, 0.0, w - 0.3 + VOX, 0.74, VOX, "steel")                      # tap
    c.add(w - 0.3, 0.74, 0.0, w - 0.3 + VOX, 0.8, 0.25, "steel")
    return c.boxes


def pedestal_sink():
    w, h, d = 0.62, 1.0, 0.38
    c = Part(w, h, d)
    c.add(0.2, 0, 0.1, 0.42, 0.7, 0.28, "porcelain")                                # pedestal
    c.add(0.1, 0, 0.06, 0.52, 0.06, 0.32, "porcelain")                              # foot
    c.add(0, 0.7, 0, w, 0.76, d, "porcelain")                                       # basin underside
    c.add(0, 0.76, 0, w, 0.88, 0.0625, "white")
    c.add(0, 0.76, d - 0.0625, w, 0.88, d, "white")
    c.add(0, 0.76, 0.0625, 0.0625, 0.88, d - 0.0625, "white")
    c.add(w - 0.0625, 0.76, 0.0625, w, 0.88, d - 0.0625, "white")
    c.add(0.0625, 0.76, 0.0625, w - 0.0625, 0.82, d - 0.0625, "water")
    c.add(w / 2 - VOX / 2, 0.88, 0.0, w / 2 + VOX / 2, 1.0, VOX, "steel")           # tap on the back rim
    c.add(w / 2 - VOX / 2, 0.94, 0.0, w / 2 + VOX / 2, 1.0, 0.18, "steel")
    return c.boxes


_reg("houseToilet", toilet(), (0.38, 0.8, 0.69))
_reg("publicRestroomToilet", toilet(), (0.38, 0.8, 0.69))
_reg("houseBathtub", bathtub(), (1.75, 0.8, 0.75))
_reg("bathroomSink", pedestal_sink(), (0.62, 1.0, 0.38))


# ---- bins and crates ----------------------------------------------------------------------------------------------------------
def pedal_bin():
    w, h, d = 0.5, 0.75, 0.56
    c = Part(w, h, d)
    c.add(0.06, 0, 0.06, w - 0.06, 0.6, d - 0.06, "steel")
    c.add(0.0, 0.0, 0.0, w, 0.06, d, "black")
    c.add(0.0, 0.54, 0.0, w, 0.6, d, "black")                                        # rim
    c.add(0.0, 0.6, 0.0, w, 0.66, d - 0.12, "steel", (-10, 0, 0), (w / 2, 0.6, 0.0))  # lid, hinged at the back, a little open
    c.add(w / 2 - 0.1, 0.0, d - 0.12, w / 2 + 0.1, 0.06, d, "black")                 # pedal
    return c.boxes


def crate(w, h, d, planks="@wood", post="dark"):
    c = Part(w, h, d)
    for x in (0, w - VOX):
        for z in (0, d - VOX):
            c.add(x, 0, z, x + VOX, h, z + VOX, post)
    n = max(2, int(h / 0.125))
    gap = (h - 0.0625) / n
    for i in range(n):
        y0 = i * gap + 0.0625 / 2
        c.add(VOX, y0, 0, w - VOX, y0 + gap * 0.8, VOX, planks)
        c.add(VOX, y0, d - VOX, w - VOX, y0 + gap * 0.8, d, planks)
        c.add(0, y0, VOX, VOX, y0 + gap * 0.8, d - VOX, planks)
        c.add(w - VOX, y0, VOX, w, y0 + gap * 0.8, d - VOX, planks)
    c.add(VOX, 0, VOX, w - VOX, 0.0625, d - VOX, planks)
    c.add(0, h - VOX, 0, w, h, d, planks)
    return c


def crates():
    w, h, d = 0.75, 0.94, 0.62
    c = Part(w, h, d)
    # lower crate on the floor, upper crate turned a few degrees on top
    for part, (ox, oy, oz), rot in ((crate(0.5, 0.44, 0.5), (0.0, 0.0, 0.0), None), (crate(0.44, 0.44, 0.44, "pine"), (0.28, 0.5, 0.16), (0, 8, 0))):
        for bx in part.boxes:
            fx0, fy0, fz0, fx1, fy1, fz1, kind = bx[:7]
            x0, y0, z0 = fx0 * part.w + ox, fy0 * part.h + oy, fz0 * part.d + oz
            x1, y1, z1 = fx1 * part.w + ox, fy1 * part.h + oy, fz1 * part.d + oz
            if rot:
                c.add(x0, y0, z0, x1, y1, z1, kind, rot, (ox + part.w / 2, oy, oz + part.d / 2))
            else:
                c.add(x0, y0, z0, x1, y1, z1, kind)
    return c.boxes


_reg("trashBin", pedal_bin(), (0.5, 0.75, 0.56), {}, [(pedal_bin(), {})])
_reg("supplyCrates", crates(), (0.75, 0.94, 0.62), {"@wood": ["oak", "pine", "ash"]})


# ---- finish variants: a second and third look for families that had a single model ---------------------------------------------
def recolor(name, *mappings):
    """Adds one variant per mapping ({old kind: new kind}) of the first model of `name`."""
    boxes, subs = PROPS[name]
    for mapping in mappings:
        recoloured = [b[:6] + (mapping.get(b[6], b[6]),) + tuple(b[7:]) for b in boxes]
        v(name, recoloured, dict(subs))


for _style, _maps in (("normal", [{"porcelain": "linen", "steel": "black"}, {"porcelain": "grey", "oak": "walnut"}]),
                      ("luxury", [{"black": "grey", "stone": "ash"}, {"black": "teal", "steel": "brass"}]),
                      ("gothic", [{"dark": "mahogany"}, {"dark": "walnut", "brass": "steel"}])):
    for _kit in ("Stove", "Fridge", "Sink"):
        recolor(_style + "Kitchen" + _kit, *_maps)
for _n in ("houseToilet", "publicRestroomToilet", "houseBathtub", "bathroomSink"):
    recolor(_n, {"porcelain": "tile"}, {"porcelain": "linen", "white": "paper"})


# Common single-model furniture and fixtures get two automatic finishes (wood/metal/cloth swaps), only where the swap changes something.
COMMON_SINGLES = [
    "retroComputerDesktop", "retroComputerCompact", "retroComputerTower", "retroComputerTerminal", "officeCrtSecurityConsole",
    "filingCabinet", "locker", "vendingMachine", "serverRack", "breakerCabinet", "normalKitchenIsland", "luxuryKitchenIsland",
    "gothicKitchenIsland", "normalKitchenWallCabinet", "luxuryKitchenWallCabinet", "gothicKitchenWallCabinet", "bathroomVanity",
    "bedroomVanity", "gothicVanity", "bathroomStall", "houseBathroomShelf", "houseMedicineCabinet", "gothicCoffinChest",
    "magazineRack", "mansionTeaCart", "mansionUprightPiano", "mansionGrandfatherClock", "mansionDisplayCabinet",
    "gothicWritingDesk", "utilityCart", "maintenanceCleaningCart", "maintenanceToolCabinet", "officeCornerWorkstation",
    "officeFileBoxes", "officePhotocopier", "officePrinter", "officeShredder", "officeWaterCooler", "prisonKitchenRack",
    "prisonServingCounter", "prisonTrayReturn", "prisonCafeteriaTable", "prisonBunk", "restraintChair", "gardenPlanterBench",
    "brokenAquarium", "publicSinkBank", "publicShowerBench",
]
FINISH_A = {"oak": "pine", "dark": "walnut", "steel": "grey", "red": "teal", "plum": "linen", "paper": "linen", "concrete": "stone",
            "porcelain": "tile", "stone": "ash"}
FINISH_B = {"oak": "ash", "dark": "mahogany", "steel": "black", "red": "plum", "green": "teal", "paper": "white", "black": "grey",
            "concrete": "grey", "porcelain": "linen", "stone": "concrete"}
for _n in COMMON_SINGLES:
    if _n not in PROPS:
        continue
    _kinds = {b[6] for b in PROPS[_n][0]}
    _have = len(VARIANTS.get(_n, []))
    for _m in (FINISH_A, FINISH_B):
        if _have >= 2:
            break
        _use = {k: val for k, val in _m.items() if k in _kinds}
        if _use:
            recolor(_n, _use)
            _have += 1
