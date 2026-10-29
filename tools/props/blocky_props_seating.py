"""Chairs, stools and tables authored in metres (DONE11 rework), exec'd by build_blocky_props.py after the variants.

Why a separate file: the older definitions were fractions of the old model's bounding box, so a chair's seat landed at
0.56 m, a dining table's top at 1.0 m and the restaurant party table (sized to include its balloons) had its top slab at
2.2 m. Here every part is placed in metres on the 6 cm voxel grid and the overall height is pinned by SIZE_SCALE in
build_blocky_props.py (chairs 0.94 m, tables 0.75 m top surface, restaurant table 0.9 m with its place settings).

Rules the parts follow (all own designs; proportions are the usual ones for a believable chair/table):
  seat top 0.44 m, table top 0.75 m, so a chair seat (0.44) clears the apron underside (0.56) by 12 cm and tucks under;
  legs 6 cm on chairs, 12 cm on tables; backs are posts + rails + slats, never a solid slab;
  the chair front is +Z (blocks are fractions: x left..right, y up, z back..front).
"""

VOX = 0.0625


def _frac(box_m, w, h, d, kind, rot=None, pivot_m=None):
    x0, y0, z0, x1, y1, z1 = box_m
    out = (x0 / w, y0 / h, z0 / d, x1 / w, y1 / h, z1 / d, kind)
    if rot is not None:
        px, py, pz = pivot_m if pivot_m is not None else ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
        out += (tuple(rot), (px / w, py / h, pz / d))
    return out


class Part:
    """Collects boxes in metres for a prop of footprint w x d and total height h."""

    def __init__(self, w, h, d):
        self.w, self.h, self.d = w, h, d
        self.boxes = []

    def add(self, x0, y0, z0, x1, y1, z1, kind, rot=None, pivot=None):
        """rot = (rx, ry, rz) degrees about the prop axes, pivot in metres (default the box centre); see build_blocky_props.py."""
        self.boxes.append(_frac((x0, y0, z0, x1, y1, z1), self.w, self.h, self.d, kind, rot, pivot))
        return self


def chair(back="slats", cushion=False, arms=False, seat_kind="@wood", frame="@wood", cloth="@cloth"):
    c = Part(0.5, 0.94, 0.5)
    seat_top, seat_bot = 0.4375, 0.375
    inset, leg = 0.03, VOX
    for x in (inset, 0.5 - inset - leg):
        for z in (inset, 0.5 - inset - leg):
            c.add(x, 0, z, x + leg, seat_bot, z + leg, frame)
    # low rails join the legs so the chair reads as one frame
    c.add(inset, 0.14, inset + leg, inset + leg, 0.2, 0.5 - inset - leg, frame)
    c.add(0.5 - inset - leg, 0.14, inset + leg, 0.5 - inset, 0.2, 0.5 - inset - leg, frame)
    c.add(inset, seat_bot, inset, 0.5 - inset, seat_top, 0.5 - inset, cloth if arms else seat_kind)
    if cushion:
        c.add(0.07, seat_top, 0.07, 0.43, seat_top + 0.05, 0.43, cloth)
    # back: posts, top rail and either slats or a padded panel; the back stands on the rear edge (z small)
    top = 0.9375
    for x in (inset, 0.5 - inset - leg):
        c.add(x, seat_top, inset, x + leg, top, inset + leg, frame)
    c.add(inset, 0.8125, inset, 0.5 - inset, top, inset + leg, frame)
    if back == "slats":
        for x0 in (0.15, 0.22, 0.29):
            c.add(x0, 0.5, inset + 0.005, x0 + 0.04, 0.8125, inset + 0.05, frame)
    elif back == "panel":
        c.add(inset + leg, 0.5, inset + 0.005, 0.5 - inset - leg, 0.8125, inset + leg, cloth)
    elif back == "ladder":
        for y0 in (0.5, 0.62, 0.74):
            c.add(inset + leg, y0, inset + 0.005, 0.5 - inset - leg, y0 + 0.05, inset + leg, frame)
    if arms:
        for x in (inset - 0.0, 0.5 - inset - leg):
            c.add(x, 0.6, inset + leg, x + leg, 0.6 + VOX, 0.5 - inset, frame)
            c.add(x, seat_top, 0.5 - inset - leg, x + leg, 0.6, 0.5 - inset, frame)
    return c.boxes


def stool(kind="@wood"):
    c = Part(0.5, 0.94, 0.5)
    for x in (0.06, 0.5 - 0.06 - VOX):
        for z in (0.06, 0.5 - 0.06 - VOX):
            c.add(x, 0, z, x + VOX, 0.4375, z + VOX, "dark")
    c.add(0.06, 0.18, 0.06, 0.44, 0.23, 0.115, "dark")
    c.add(0.06, 0.18, 0.385, 0.44, 0.23, 0.44, "dark")
    c.add(0.03, 0.4375, 0.03, 0.47, 0.5, 0.47, kind)
    return c.boxes


def table(w, d, top=0.75, drawer=False, kind="@wood", leg="dark", style="legs"):
    t = Part(w, top, d)
    slab = VOX
    lw = 0.125
    if style == "legs":
        for x in (0.04, w - 0.04 - lw):
            for z in (0.04, d - 0.04 - lw):
                t.add(x, 0, z, x + lw, top - slab - 0.19, z + lw, leg)
        # apron: 19 cm deep frame under the top, so seats (0.44) clear it by 12 cm
        t.add(0.04, top - slab - 0.19, 0.04 + lw * 0.5, w - 0.04, top - slab, 0.04 + lw * 0.5 + 0.05, leg)
        t.add(0.04, top - slab - 0.19, d - 0.04 - lw * 0.5 - 0.05, w - 0.04, top - slab, d - 0.04 - lw * 0.5, leg)
        t.add(0.04 + lw * 0.5, top - slab - 0.19, 0.04, 0.04 + lw * 0.5 + 0.05, top - slab, d - 0.04, leg)
        t.add(w - 0.04 - lw * 0.5 - 0.05, top - slab - 0.19, 0.04, w - 0.04 - lw * 0.5, top - slab, d - 0.04, leg)
        # legs rise to the apron so nothing floats
        for x in (0.04, w - 0.04 - lw):
            for z in (0.04, d - 0.04 - lw):
                t.add(x, top - slab - 0.19, z, x + lw, top - slab, z + lw, leg)
        if drawer:
            t.add(w * 0.35, top - slab - 0.16, d - 0.04, w * 0.65, top - slab - 0.03, d - 0.005, "oak")
            t.add(w * 0.47, top - slab - 0.11, d - 0.012, w * 0.53, top - slab - 0.08, d, "brass")
    elif style == "trestle":
        for x in (0.1, w - 0.1 - lw):
            t.add(x, 0, 0.08, x + lw, top - slab, d - 0.08, leg)
        t.add(0.1 + lw, 0.2, d / 2 - 0.04, w - 0.1 - lw, 0.26, d / 2 + 0.04, leg)
    elif style == "pedestal":
        t.add(w / 2 - 0.1, 0.1, d / 2 - 0.1, w / 2 + 0.1, top - slab, d / 2 + 0.1, leg)
        t.add(w / 2 - 0.3, 0, d / 2 - 0.3, w / 2 + 0.3, 0.1, d / 2 + 0.3, leg)
    t.add(0, top - slab, 0, w, top, d, kind)
    return t.boxes


def restaurant_table():
    """Long party table under a cloth, with plates, cups, hats and a balloon cluster on a pole (h 2.23 m; the table
    top is 0.75 m, the rest is the cluster). The old shape put the table top at the top of the balloons, 2.2 m up."""
    w, h, d = 2.62, 2.23, 1.0
    t = Part(w, h, d)
    for x in (0.12, w - 0.12 - 0.12):
        for z in (0.12, d - 0.12 - 0.12):
            t.add(x, 0, z, x + 0.12, 0.56, z + 0.12, "dark")
    t.add(0.04, 0.56, 0.04, w - 0.04, 0.69, d - 0.04, "dark")
    t.add(0, 0.69, 0, w, 0.75, d, "plum")
    t.add(0, 0.5, 0, w, 0.69, 0.06, "plum")
    t.add(0, 0.5, d - 0.06, w, 0.69, d, "plum")
    t.add(0, 0.5, 0.06, 0.06, 0.69, d - 0.06, "plum")
    t.add(w - 0.06, 0.5, 0.06, w, 0.69, d - 0.06, "plum")
    for i in range(4):
        x = 0.45 + i * 0.5
        t.add(x, 0.75, 0.2, x + 0.16, 0.78, 0.36, "paper")
        t.add(x, 0.75, d - 0.36, x + 0.16, 0.78, d - 0.2, "paper")
        t.add(x + 0.2, 0.75, 0.24, x + 0.28, 0.85, 0.32, "blue")
        t.add(x + 0.2, 0.75, d - 0.32, x + 0.28, 0.85, d - 0.24, "yellow")
        t.add(x + 0.04, 0.78, 0.24, x + 0.12, 0.9, 0.32, "red" if i % 2 else "yellow")
    t.add(w / 2 - 0.1, 0.75, d / 2 - 0.1, w / 2 + 0.1, 0.9, d / 2 + 0.1, "red")
    # balloon cluster: a thin pole from the table to just under the top balloons
    t.add(w / 2 - 0.02, 0.9, d / 2 - 0.02, w / 2 + 0.02, 1.8, d / 2 + 0.02, "steel")
    t.add(w / 2 - 0.28, 1.74, d / 2 - 0.14, w / 2 - 0.02, 2.06, d / 2 + 0.12, "plum")
    t.add(w / 2 + 0.02, 1.72, d / 2 - 0.12, w / 2 + 0.28, 2.04, d / 2 + 0.14, "red")
    t.add(w / 2 - 0.13, 1.92, d / 2 - 0.13, w / 2 + 0.13, 2.23, d / 2 + 0.13, "blue")
    return t.boxes


# ---- chairs -------------------------------------------------------------------------------------
for name in ("woodenChair", "woodenChairCushion", "diningChair", "diningChairCushion"):
    cushion = name.endswith("Cushion") or name == "woodenChairCushion"
    PROPS[name] = (chair("slats", cushion=cushion), {"@wood": WOODS, "@cloth": CLOTH})
    VARIANTS[name] = []
    v(name, chair("ladder", cushion=False), {"@wood": WOODS})
    v(name, chair("panel", arms=False, cushion=cushion), {"@wood": WOODS, "@cloth": CLOTH})
    v(name, chair("panel", arms=True), {"@wood": WOODS, "@cloth": CLOTH})
    v(name, stool(), {"@wood": WOODS})

# ---- tables -------------------------------------------------------------------------------------
PROPS["woodenTable"] = (table(1.2, 0.78), {"@wood": WOODS})
VARIANTS["woodenTable"] = []
v("woodenTable", table(1.2, 0.78, drawer=True), {"@wood": WOODS})
v("woodenTable", table(1.2, 0.78, style="trestle"), {"@wood": WOODS})
v("woodenTable", table(1.2, 0.78, style="pedestal"), {"@wood": WOODS})
PROPS["diningTable"] = (table(2.2, 0.84), {"@wood": WOODS})
VARIANTS["diningTable"] = []
v("diningTable", table(2.2, 0.84, style="trestle"), {"@wood": WOODS})
v("diningTable", table(2.2, 0.84, style="pedestal"), {"@wood": WOODS})
PROPS["restaurantPartyTable"] = (restaurant_table(), {})
