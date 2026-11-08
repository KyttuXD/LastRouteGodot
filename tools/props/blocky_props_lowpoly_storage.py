"""Storage/lockers/wardrobes: 36 types redone low-poly.
exec'd by build_blocky_props.py after SIZE_SCALE and before mansion finishes, so *Mansion sets derive from these shapes.
PROPS, VARIANTS, Part, VOX, _reg, TARGET_SIZE, CLOTH, WOODS are in scope.

What changes:
  - Bookcases / shop / pharmacy / bakery shelves: empty shelves (no per-book / per-bottle boxes).
  - Storage shelving: empty steel shelves (no stock boxes).
  - Crates: two solid boxes (no plank crate detail).
  - Locker: two louvre bands instead of five each.
  - Wardrobes: door slab + handle only (no raised panel).
  - Chests / nightstands: same layout, one pull per drawer (already lean); hidden_faces culls buried faces.
  - Other already-lean types keep shapes and only join LOWPOLY for face culling.
Locked: type ids, model counts per type, TARGET_SIZE / footprints / colliders / front / hide / mount, same atlas.
"""

_STORAGE_078 = [
    "locker", "bedroomWardrobe", "gothicWardrobe", "bedroomDresser", "gothicDresser", "woodenDresserSideboard",
    "bedroomNightstand", "gothicNightstand", "filingCabinet", "storageShelving", "storageBarrel", "supplyCrates",
    "charredSupplyCrate", "normalBookcase", "mansionBookshelf", "gothicBookcase", "mansionDisplayCabinet",
    "gothicCoffinChest", "toyChest", "magazineRack", "officeFileBoxes", "maintenanceToolCabinet", "morgueCabinet",
    "pharmacyShelf", "shopShelf", "bakeryRack", "clothesRack", "instrumentCases", "coldStorageUnit",
]


def _keep_variants(name, shapes):
    """Replace a type's shapes one for one: shapes[0] is the base, the rest the variants, each keeping its colour options."""
    old = [PROPS[name]] + list(VARIANTS.get(name, []))
    assert len(old) == len(shapes), (name, len(old), len(shapes))
    PROPS[name] = (shapes[0], old[0][1])
    VARIANTS[name] = [(s, o[1]) for s, o in zip(shapes[1:], old[1:])]


def _n(name):
    return 1 + len(VARIANTS.get(name, []))


def _repeat(name, makers):
    """Fill exactly _n(name) shapes by cycling makers."""
    n = _n(name)
    shapes = [makers[i % len(makers)]() for i in range(n)]
    _keep_variants(name, shapes)


# ---- bookcases: carcass + empty shelves (no book boxes) --------------------------------------------------------------
def lp_bookcase(w, h, d, shelves, wood="dark", crown=True):
    c = Part(w, h, d)
    ox = 0.03 if crown else 0.0
    bw = w - 2 * ox
    bd = d - (0.03 if crown else 0.0)
    t = VOX
    kick = 0.12
    c.add(ox, 0, 0, ox + t, h - 0.1, bd, wood)
    c.add(ox + bw - t, 0, 0, ox + bw, h - 0.1, bd, wood)
    c.add(ox + t, kick, 0, ox + bw - t, h - 0.1, 0.06, "black")
    c.add(ox + t, 0, 0.02, ox + bw - t, kick, bd - 0.02, wood)
    c.add(0, h - 0.1, 0, w, h, d, wood)
    inner = h - kick - 0.1 - t
    gap = (inner - shelves * t) / (shelves + 1)
    y = kick
    for s_ in range(shelves + 1):
        if s_ > 0:
            c.add(ox + t, y - t, 0.06, ox + bw - t, y, bd, wood)
        y += gap + t
    return c.boxes


_repeat("normalBookcase", [
    lambda: lp_bookcase(1.0, 1.81, 0.42, 4, "dark", False),
    lambda: lp_bookcase(1.0, 1.81, 0.42, 4, "oak", False),
    lambda: lp_bookcase(1.0, 1.81, 0.42, 3, "dark", True),
])
_repeat("mansionBookshelf", [
    lambda: lp_bookcase(0.88, 2.06, 0.62, 5, "dark", True),
    lambda: lp_bookcase(0.88, 2.06, 0.62, 5, "oak", True),
    lambda: lp_bookcase(0.88, 2.06, 0.62, 4, "dark", True),
])
_repeat("gothicBookcase", [
    lambda: lp_bookcase(1.38, 2.44, 0.5, 6, "black", True),
    lambda: lp_bookcase(1.38, 2.44, 0.5, 6, "dark", True),
    lambda: lp_bookcase(1.38, 2.44, 0.5, 5, "black", True),
])


# ---- wardrobes -------------------------------------------------------------------------------------------------------
def lp_wardrobe(w, h, d, kind="dark", panel="oak"):
    c = Part(w, h, d)
    foot = 0.1
    for x, z in ((0.02, 0.02), (w - 0.1, 0.02), (0.02, d - 0.1), (w - 0.1, d - 0.1)):
        c.add(x, 0, z, x + 0.08, foot, z + 0.08, kind)
    c.add(0, foot, 0, w, h - 0.12, d - 0.06, kind)
    c.add(0, h - 0.12, 0, w, h, d, kind)
    dw = (w - 0.12) / 2
    for i, x0 in enumerate((0.06, 0.06 + dw)):
        x1 = x0 + dw
        c.add(x0, foot + 0.02, d - 0.06, x1, h - 0.14, d - 0.02, panel)
        hx = x1 - 0.09 if i == 0 else x0 + 0.05
        c.add(hx, 0.95, d - 0.0, hx + 0.04, 1.2, d + 0.03, "brass")
    return c.boxes


_repeat("bedroomWardrobe", [
    lambda: lp_wardrobe(1.25, 2.12, 0.62, "dark", "oak"),
    lambda: lp_wardrobe(1.25, 2.12, 0.62, "oak", "dark"),
    lambda: lp_wardrobe(1.25, 2.12, 0.62, "dark", "dark"),
])
_repeat("gothicWardrobe", [
    lambda: lp_wardrobe(1.38, 2.5, 0.69, "black", "dark"),
    lambda: lp_wardrobe(1.38, 2.5, 0.69, "dark", "oak"),
    lambda: lp_wardrobe(1.38, 2.5, 0.69, "black", "oak"),
])


# ---- locker ----------------------------------------------------------------------------------------------------------
def lp_locker():
    w, h, d = 0.62, 2.0, 0.69
    c = Part(w, h, d)
    c.add(0, 0, 0, w, h, d - 0.06, "steel")
    c.add(0, 0.0, 0, w, 0.1, d, "black")
    c.add(0.02, 0.12, d - 0.06, w - 0.02, h - 0.04, d - 0.02, "concrete")
    for y0 in (0.22, 1.55):
        for i in range(2):
            c.add(0.1, y0 + i * 0.1, d - 0.02, w - 0.1, y0 + i * 0.1 + 0.04, d, "black")
    c.add(0.1, 1.1, d - 0.02, 0.18, 1.34, d + 0.02, "black")
    c.add(0.38, 1.28, d - 0.02, 0.5, 1.38, d, "brass")
    return c.boxes


_repeat("locker", [lp_locker])


# ---- chests / dressers / nightstands (lean drawer fronts) ------------------------------------------------------------
def lp_chest(w, h, d, rows, cols, leg_h=0.12, doors=False, top="@top", wood="@wood", body="dark", pull="brass"):
    c = Part(w, h, d)
    leg = VOX
    if leg_h > 0:
        for x in (0.03, w - 0.03 - leg):
            for z in (0.03, d - 0.03 - leg):
                c.add(x, 0, z, x + leg, leg_h, z + leg, body)
    c.add(0.03, leg_h, 0, w - 0.03, h - VOX, d - 0.125, body)
    c.add(0, h - VOX, 0, w, h, d, top)
    c.add(0.03, leg_h, d - 0.125, w - 0.03, h - VOX, d - 0.0625, body)
    inner_x0, inner_x1 = 0.09, w - 0.09
    inner_y0, inner_y1 = leg_h + 0.06, h - VOX
    if doors:
        n = max(2, cols)
        cw = (inner_x1 - inner_x0 - (n - 1) * VOX) / n
        for i in range(n):
            x0 = inner_x0 + i * (cw + VOX)
            c.add(x0, inner_y0, d - 0.0625, x0 + cw, inner_y1 - 0.06, d, wood)
            hx = x0 + cw - 0.12 if i % 2 == 0 else x0 + 0.06
            c.add(hx, (inner_y0 + inner_y1) / 2 - 0.1, d - 0.0625, hx + VOX, (inner_y0 + inner_y1) / 2 + 0.06, d, pull)
        return c.boxes
    rh = (inner_y1 - inner_y0 - 0.06 - (rows - 1) * VOX) / rows
    cw = (inner_x1 - inner_x0 - (cols - 1) * VOX) / cols
    for r in range(rows):
        y0 = inner_y0 + r * (rh + VOX)
        for k in range(cols):
            x0 = inner_x0 + k * (cw + VOX)
            c.add(x0, y0, d - 0.0625, x0 + cw, y0 + rh, d, wood)
            hx = x0 + cw / 2 - 0.0625
            c.add(hx, y0 + rh / 2 - 0.03, d - 0.0625, hx + 0.125, y0 + rh / 2 + 0.03, d, pull)
    return c.boxes


_CHESTS = {
    "bedroomNightstand": (0.62, 0.69, 0.5, 2, 1, 0.12),
    "bedroomDresser": (1.25, 1.06, 0.56, 3, 2, 0.12),
    "gothicNightstand": (0.62, 0.81, 0.56, 2, 1, 0.18),
    "gothicDresser": (1.38, 1.12, 0.62, 3, 3, 0.18),
    "woodenDresserSideboard": (1.25, 0.94, 0.62, 2, 3, 0.12),
}
for _name, (_w, _h, _d, _rows, _cols, _legs) in _CHESTS.items():
    _repeat(_name, [
        lambda w=_w, h=_h, d=_d, r=_rows, c=_cols, l=_legs: lp_chest(w, h, d, r, c, l),
        lambda w=_w, h=_h, d=_d, r=_rows, c=_cols, l=_legs: lp_chest(w, h, d, r, c, l, doors=True),
        lambda w=_w, h=_h, d=_d, r=_rows, c=_cols, l=_legs: lp_chest(w, h, d, max(1, r - 1), c, l),
    ])


# ---- shelving / crates / barrel --------------------------------------------------------------------------------------
def lp_storage_shelving():
    w, h, d = 1.25, 1.94, 0.5
    c = Part(w, h, d)
    for x in (0.0, w - VOX):
        for z in (0.0, d - VOX):
            c.add(x, 0, z, x + VOX, h, z + VOX, "steel")
    for y in (0.0625, 0.5625, 1.0625, 1.5625):
        c.add(VOX, y, 0.0, w - VOX, y + 0.0625, d, "grey")
    return c.boxes


_repeat("storageShelving", [lp_storage_shelving])


def lp_storage_barrel(wood="@wood"):
    # Footprint locked to staging blocky size 0.625 x 0.9375 x 0.625
    w, h, d = 0.625, 0.9375, 0.625
    c = Part(w, h, d)
    c.add(0, 0, 0, w, h, d, wood)
    for y in (0.1875, h - 0.25):
        c.add(0, y, 0, w, y + 0.0625, d, "black")
    return c.boxes


_repeat("storageBarrel", [lp_storage_barrel])


def lp_crates():
    """Two solid crates; no plank/lid detail. Envelope = rework3 TARGET_SIZE / props_rework (0.75, 0.94, 0.62)."""
    w, h, d = 0.75, 0.94, 0.62
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, 0.5, 0.44, 0.5, "@wood")
    c.add(0.25, 0.44, 0.12, w, h, d, "pine")
    return c.boxes


_repeat("supplyCrates", [lp_crates])
# charredSupplyCrate: keep staging shape + colour (often a recolor of supply crates); only LOWPOLY cull


# ---- shop / pharmacy / bakery shelves: empty boards ------------------------------------------------------------------
def lp_shop_shelf():
    w, h, d = 1.2, 1.9, 0.5
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, h, 0.04, "@frame")
    for x in (0.0, w - 0.04):
        c.add(x, 0, 0.0, x + 0.04, h, d, "@frame")
    c.add(0.04, 0, 0.04, w - 0.04, 0.1, d, "black")
    for s in range(4):
        y = 0.1 + s * 0.44
        c.add(0.04, y, 0.04, w - 0.04, y + 0.03, d, "steel")
        c.add(0.04, y, d - 0.01, w - 0.04, y + 0.06, d, "white")
    c.add(0.1, h - 0.18, d - 0.02, w - 0.1, h - 0.05, d, "@sign")
    return c.boxes


_repeat("shopShelf", [lp_shop_shelf])


def lp_pharmacy_shelf():
    w, h, d = 1.6, 2.0, 0.45
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, h, 0.03, "white")
    for x in (0.0, w - 0.04):
        c.add(x, 0, 0.0, x + 0.04, h, d, "white")
    for s in range(5):
        y = 0.05 + s * 0.39
        c.add(0.04, y, 0.03, w - 0.04, y + 0.03, d, "grey")
    return c.boxes


_repeat("pharmacyShelf", [lp_pharmacy_shelf])


def lp_bakery_rack():
    # Footprint locked to staging 1.0 x 1.875 x 0.5625
    w, h, d = 1.0, 1.875, 0.5625
    c = Part(w, h, d)
    for x in (0.0, w - 0.04):
        c.add(x, 0.0, 0.0, x + 0.04, h, d, "steel")
    for y in (0.0, 0.45, 0.9, 1.35, 1.8):
        c.add(0.04, y, 0.0, w - 0.04, y + 0.03, d, "steel")
    return c.boxes


_repeat("bakeryRack", [lp_bakery_rack])


def lp_clothes_rack():
    # Footprint locked to staging 1.5 x 1.625 x 0.375
    w, h, d = 1.5, 1.625, 0.375
    c = Part(w, h, d)
    for x in (0.0, w - 0.04):
        c.add(x, 0, d * 0.45, x + 0.04, h - 0.05, d * 0.55, "steel")
    c.add(0.0, h - 0.05, d * 0.45, w, h, d * 0.55, "steel")
    # three garment slabs instead of nine — span full depth/height envelope
    for i, col in enumerate(("red", "blue", "black")):
        x0 = 0.1 + i * 0.45
        c.add(x0, 0.55, 0.0, x0 + 0.35, h - 0.08, d, col)
    return c.boxes


_repeat("clothesRack", [lp_clothes_rack])


# ---- already-lean types: keep geometry, opt into face culling only ---------------------------------------------------
_KEEP = [
    "filingCabinet", "mansionDisplayCabinet", "gothicCoffinChest", "toyChest", "magazineRack",
    "officeFileBoxes", "maintenanceToolCabinet", "morgueCabinet", "instrumentCases", "coldStorageUnit",
]
# (no shape replace — staging meshes stay; LOWPOLY still culls buried faces)


# Pin rebuilt types to staging blocky mesh sizes (prop_bounds) so colliders/footprints do not move.
TARGET_SIZE["storageBarrel"] = (0.625, 0.9375, 0.625)
TARGET_SIZE["supplyCrates"] = (0.75, 0.94, 0.62)
TARGET_SIZE["bakeryRack"] = (1.0, 1.875, 0.5625)
TARGET_SIZE["clothesRack"] = (1.5, 1.625, 0.375)

LOWPOLY.update(_STORAGE_078)
LOWPOLY.update(n + "Mansion" for n in _STORAGE_078 if n + "Mansion" in PROPS or True)
