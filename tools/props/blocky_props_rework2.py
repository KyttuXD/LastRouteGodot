"""Props rework 2 (DONE13): the weak seating, beds, storage and kitchen props, authored in metres on the 6 cm grid with the
new rotation field. exec'd by build_blocky_props.py after the doors, so PROPS, VARIANTS, Part, VOX, CLOTH and WOODS are in scope.

Every shape is our own design. The thuing/ library was looked at (read only) for proportions, part breakdowns and how
rotations are used (backrest tilt 5-15 degrees, splayed legs, rocker arcs, angled lids); nothing was copied.

TARGET_SIZE[name] = (w, h, d) in metres overrides the footprint the builder takes from the old model, so a design here is built
at exactly this size (seat heights 0.44 m, tables 0.75 m, counters 0.92 m).
Rotation: Part.add(..., rot=(rx, ry, rz) degrees, pivot=(x, y, z) metres). A positive rx tips the top toward the front (+z),
so a backrest that leans back uses a negative rx.
"""
import math as _math
import random as _random

TARGET_SIZE = {}


def _reg(name, boxes, size, subs=None, variants=()):
    PROPS[name] = (boxes, subs or {})
    TARGET_SIZE[name] = size
    VARIANTS.pop(name, None)
    for vb, vs in variants:
        v(name, vb, vs)


def _posts(c, xs, zs, y0, y1, w, kind):
    for x in xs:
        for z in zs:
            c.add(x, y0, z, x + w, y1, z + w, kind)


# ---- seating ---------------------------------------------------------------------------------------------------------
def gothic_highback():
    w, h, d = 0.56, 1.30, 0.56
    c = Part(w, h, d)
    leg, ins = VOX, 0.03
    seat_bot, seat_top = 0.375, 0.4375
    # front legs stop at the seat, rear posts run up into the back
    for x in (ins, w - ins - leg):
        c.add(x, 0, d - ins - leg, x + leg, seat_bot, d - ins, "dark")
        c.add(x, 0, ins, x + leg, seat_bot, ins + leg, "dark")
        c.add(x, 0.12, ins + leg, x + leg, 0.2, d - ins - leg, "dark")      # side stretchers
    c.add(ins + leg, 0.12, d - ins - leg, w - ins - leg, 0.2, d - ins, "dark")  # front stretcher
    c.add(ins, seat_bot, ins, w - ins, seat_top, d - ins, "dark")             # seat frame
    c.add(0.09, seat_top, 0.1, w - 0.09, seat_top + 0.04, d - 0.06, "@cloth")   # cushion
    pivot = (w / 2, seat_top, ins + leg / 2)
    lean = (-8, 0, 0)
    for x in (ins, w - ins - leg):
        c.add(x, seat_top, ins, x + leg, 1.18, ins + leg, "dark", lean, pivot)       # rear posts
        c.add(x, 1.18, ins, x + leg, 1.30, ins + leg, "brass", lean, pivot)           # finials
    c.add(ins + leg, 0.56, ins + 0.005, w - ins - leg, 1.12, ins + leg - 0.005, "@cloth", lean, pivot)  # tall padded panel
    c.add(ins, 1.12, ins, w - ins, 1.18, ins + leg, "dark", lean, pivot)           # top rail
    c.add(0.2, 1.18, ins, w - 0.2, 1.24, ins + leg, "dark", lean, pivot)           # pointed crest
    # arms on posts
    for x in (ins, w - ins - leg):
        c.add(x, 0.62, 0.16, x + leg, 0.68, d - ins, "dark")
        c.add(x, seat_top, d - ins - leg, x + leg, 0.62, d - ins, "dark")
    return c.boxes


def restraint_chair():
    w, h, d = 0.8, 1.35, 0.8
    c = Part(w, h, d)
    leg = 0.1
    for x in (0.05, w - 0.05 - leg):
        for z in (0.05, d - 0.05 - leg):
            c.add(x, 0, z, x + leg, 0.4375, z + leg, "steel")
    c.add(0.05, 0.14, 0.05, w - 0.05, 0.2, 0.05 + leg, "steel")
    c.add(0.05, 0.14, d - 0.05 - leg, w - 0.05, 0.2, d - 0.05, "steel")
    c.add(0.0, 0.4375, 0.0, w, 0.5, d, "dark")                                       # seat
    pivot = (w / 2, 0.5, 0.1)
    lean = (-6, 0, 0)
    c.add(0.05, 0.5, 0.0, w - 0.05, 1.2, 0.12, "dark", lean, pivot)                  # back
    c.add(0.2, 1.2, 0.0, w - 0.2, 1.35, 0.12, "steel", lean, pivot)                   # head rest
    c.add(0.0, 0.6, 0.0, 0.07, 1.05, 0.12, "steel", lean, pivot)
    c.add(w - 0.07, 0.6, 0.0, w, 1.05, 0.12, "steel", lean, pivot)
    for x in (0.0, w - 0.0625):                                                       # arms with wrist cuffs
        c.add(x, 0.7, 0.14, x + 0.0625, 0.76, d - 0.1, "steel")
        c.add(x, 0.5, d - 0.16, x + 0.0625, 0.7, d - 0.1, "steel")
        c.add(x, 0.76, 0.3, x + 0.0625, 0.82, 0.4, "brass")
        c.add(x, 0.76, 0.5, x + 0.0625, 0.82, 0.58, "brass")
    for x in (0.05, w - 0.05 - leg):                                                  # ankle cuffs
        c.add(x, 0.2, d - 0.05 - leg, x + leg, 0.27, d - 0.05, "brass")
    c.add(0.0, 0.52, 0.3, w, 0.56, 0.36, "black", None)                               # lap strap
    return c.boxes


def rocking_chair():
    w, h, d = 0.6, 1.05, 0.9
    c = Part(w, h, d)
    # two curved rockers built from short boxes turned to follow an arc
    segs = 7
    for x in (0.04, w - 0.04 - VOX):
        for i in range(segs):
            t = (i + 0.5) / segs
            z = 0.04 + t * (d - 0.08)
            u = (t - 0.5) * 2
            y = 0.10 * u * u
            slope = _math.degrees(_math.atan(0.2 * u))
            c.add(x, y, z - 0.07, x + VOX, y + 0.05, z + 0.07, "dark", (-slope, 0, 0))
    seat_top = 0.40
    for x in (0.08, w - 0.08 - VOX):
        for z in (0.2, d - 0.3):
            c.add(x, 0.1, z, x + VOX, seat_top, z + VOX, "@wood")
    c.add(0.06, seat_top - 0.06, 0.18, w - 0.06, seat_top, d - 0.22, "@wood")         # seat
    c.add(0.1, seat_top, 0.22, w - 0.1, seat_top + 0.04, d - 0.28, "@cloth")
    pivot = (w / 2, seat_top, 0.22)
    lean = (-12, 0, 0)
    for x in (0.08, w - 0.08 - VOX):
        c.add(x, seat_top, 0.18, x + VOX, 1.0, 0.18 + VOX, "@wood", lean, pivot)
    for i in range(4):
        y0 = 0.52 + i * 0.12
        c.add(0.14, y0, 0.18, w - 0.14, y0 + 0.07, 0.18 + 0.03, "@wood", lean, pivot)
    c.add(0.06, 0.94, 0.17, w - 0.06, 1.0, 0.18 + VOX, "@wood", lean, pivot)
    for x in (0.08, w - 0.08 - VOX):                                                    # arms
        c.add(x, 0.62, 0.3, x + VOX, 0.68, d - 0.3, "@wood")
        c.add(x, seat_top, d - 0.36, x + VOX, 0.62, d - 0.36 + VOX, "@wood")
    return c.boxes


def beach_chair():
    w, h, d = 0.6, 0.85, 1.0
    c = Part(w, h, d)
    frame = "steel"
    hinge = 0.45                      # the reclined back pivots here: its top ends up at z = 0.45 - 0.6 * sin(45) = 0.03, inside the footprint
    c.add(0.0, 0.2, hinge, w, 0.26, d, "@cloth")                       # seat deck
    for x in (0.0, w - VOX):
        c.add(x, 0.0, d - 0.1, x + VOX, 0.2, d - 0.1 + VOX, frame)      # front legs
        c.add(x, 0.0, hinge, x + VOX, 0.2, hinge + VOX, frame)           # middle legs
        c.add(x, 0.2, hinge, x + VOX, 0.26, d, frame)                    # side rails
    pivot = (w / 2, 0.26, hinge)
    for x in (0.0, w - VOX):
        c.add(x, 0.26, hinge, x + VOX, 0.86, hinge + VOX, frame, (-45, 0, 0), pivot)     # back rails, reclined
    for i, kind in enumerate(("@cloth", "white", "@cloth", "white", "@cloth")):
        c.add(VOX, 0.3 + i * 0.11, hinge - 0.01, w - VOX, 0.3 + i * 0.11 + 0.1, hinge + VOX, kind, (-45, 0, 0), pivot)
    for x in (0.0, w - VOX):                                           # props holding the back up
        c.add(x, 0.0, 0.1, x + VOX, 0.4, 0.1 + VOX, frame, (30, 0, 0), (x, 0.0, 0.1))
    return c.boxes


# ---- beds ------------------------------------------------------------------------------------------------------------
def bunk_bed():
    w, h, d = 1.0, 1.85, 2.05
    c = Part(w, h, d)
    p = 0.09
    _posts(c, (0.0, w - p), (0.0, d - p), 0, h, p, "dark")
    for y, top in ((0.28, 0.44), (1.06, 1.22)):
        c.add(p, y, p, w - p, y + 0.06, d - p, "dark")                                    # deck
        c.add(0.12, y + 0.06, 0.12, w - 0.12, top + 0.08, d - 0.12, "@cloth")              # mattress with sheet
        c.add(0.16, top + 0.08, 0.16, w - 0.16, top + 0.14, 0.5, "paper")                  # pillow
        c.add(0.12, y + 0.06 + 0.1, 0.62, w - 0.12, top + 0.12, d - 0.12, "@cloth")
    for y in (0.5, 0.56):
        c.add(0, y, 0, w, y + 0.06, 0.06, "dark")
    c.add(0, 1.5, p, 0.06, 1.62, d - p, "dark")                                           # upper guard rails
    c.add(w - 0.06, 1.5, p, w, 1.62, d - p, "dark")
    c.add(0, 1.5, 0, w, 1.56, p, "dark")
    c.add(0, 1.5, d - p, w, 1.56, d, "dark")
    for y in (0.34, 0.62, 0.9, 1.18):                                                      # ladder at the foot end
        c.add(w - p, y, d - p - 0.4, w, y + 0.05, d - p, "oak")
    return c.boxes


def prison_bunk():
    w, h, d = 0.9, 1.7, 1.9
    c = Part(w, h, d)
    p = 0.08
    _posts(c, (0.0, w - p), (0.0, d - p), 0, h, p, "steel")
    for y in (0.4, 1.12):
        c.add(0, y, 0, w, y + 0.06, d, "steel")
        c.add(0.1, y + 0.06, 0.1, w - 0.1, y + 0.14, d - 0.1, "stone")                      # thin grey mattress
        c.add(0.12, y + 0.14, 0.12, w - 0.12, y + 0.2, 0.46, "paper")
    c.add(0, 1.42, 0, 0.06, 1.54, d, "steel")
    c.add(w - 0.06, 1.42, 0, w, 1.54, d, "steel")
    for y in (0.3, 0.6, 0.9):                                                              # ladder rungs at the foot
        c.add(0, y, d - 0.5, 0.06, y + 0.05, d - 0.06, "steel")
    return c.boxes


def gothic_canopy_bed():
    w, h, d = 2.0, 2.38, 2.31
    c = Part(w, h, d)
    p = 0.14
    # posts: low at the foot, tall carved posts at the head and canopy posts at the foot
    _posts(c, (0.0, w - p), (0.0, d - p), 0, 2.2, p, "dark")
    for x in (0.0, w - p):
        c.add(x, 2.2, 0, x + p, 2.38, p, "brass")
        c.add(x, 2.2, d - p, x + p, 2.38, d, "brass")
    c.add(0, 2.2, 0, w, 2.3, p, "dark")                                                    # canopy frame
    c.add(0, 2.2, d - p, w, 2.3, d, "dark")
    c.add(0, 2.2, p, p, 2.3, d - p, "dark")
    c.add(w - p, 2.2, p, w, 2.3, d - p, "dark")
    c.add(p, 0.3, 0.0, w - p, 1.55, 0.12, "dark")                                           # tall headboard
    c.add(0.3, 1.2, 0.0, w - 0.3, 1.7, 0.12, "dark")
    c.add(p, 0.42, d - 0.12, w - p, 0.85, d, "dark")                                          # footboard
    c.add(p, 0.42, p, w - p, 0.58, d - p, "dark")                                            # frame: 0.42 m clear underneath
    c.add(0.18, 0.58, 0.2, w - 0.18, 0.8, d - 0.2, "paper")                                 # mattress
    c.add(0.18, 0.68, 0.9, w - 0.18, 0.84, d - 0.2, "@cloth")                                # coverlet
    for x in (0.3, 1.1):
        c.add(x, 0.8, 0.2, x + 0.6, 0.92, 0.6, "white")                                    # pillows
    # hanging drapes: panels slightly out of line and turned a little so they read as cloth, not a wall
    for x0, x1, side in ((0.1, 0.16, 0), (w - 0.16, w - 0.1, 1)):
        for i in range(5):
            z = 0.2 + i * 0.38                                                                  # five panels along the 2.31 m bed
            c.add(x0, 1.0, z, x1, 2.2, z + 0.38, "@cloth", (0, 0, (-3 if (i % 2) else 3) * (1 if side == 0 else -1)),
                  (x0 + 0.03, 2.2, z + 0.19))
    return c.boxes


# ---- sofas -----------------------------------------------------------------------------------------------------------
def couch(seats, back=0.88):
    w = 0.7 * seats + 0.3                      # 1.7 m for two seats (the catalogue footprint), 2.4 m for three
    h, d = 0.9, 0.95
    c = Part(w, h, d)
    arm = 0.15
    for x in (0.0, w - arm):
        c.add(x, 0.12, 0.0, x + arm, 0.62, d, "@cloth")                                      # rolled arms
        c.add(x - 0.02 if x else x, 0.62, 0.02, x + arm + (0.02 if x else 0), 0.68, d - 0.02, "@cloth")
    c.add(arm, 0.12, 0.0, w - arm, back + 0.02, 0.24, "@cloth")                                       # back frame
    c.add(arm, 0.12, 0.24, w - arm, 0.3, d, "@cloth")                                         # seat base
    sw = (w - 2 * arm) / seats
    pivot_y = 0.42
    for i in range(seats):
        x0 = arm + i * sw
        c.add(x0 + 0.01, 0.3, 0.26, x0 + sw - 0.01, 0.44, d - 0.02, "@cloth")                  # seat cushion
        c.add(x0 + 0.02, 0.44, 0.1, x0 + sw - 0.02, back, 0.3, "@cloth", (-9, 0, 0), (x0 + sw / 2, pivot_y, 0.2))  # back cushion
    for x in (0.04, w - 0.04 - VOX):
        for z in (0.06, d - 0.12):
            c.add(x, 0.0, z, x + VOX, 0.12, z + VOX, "dark")
    return c.boxes


# ---- storage ---------------------------------------------------------------------------------------------------------
def bookcase(w, h, d, shelves, seed, wood="dark", crown=True):
    """w x h x d is the finished footprint: with a crown the carcass is 6 cm narrower on each side so the overhang stays inside it."""
    rng = _random.Random(seed)
    c = Part(w, h, d)
    ox = 0.03 if crown else 0.0
    bw = w - 2 * ox
    bd = d - (0.03 if crown else 0.0)
    t = VOX
    kick = 0.12
    c.add(ox, 0, 0, ox + t, h - 0.1, bd, wood)
    c.add(ox + bw - t, 0, 0, ox + bw, h - 0.1, bd, wood)
    c.add(ox + t, kick, 0, ox + bw - t, h - 0.1, 0.06, "black")                                  # back panel
    c.add(ox + t, 0, 0.02, ox + bw - t, kick, bd - 0.02, wood)                                     # kick plate
    c.add(0, h - 0.1, 0, w, h, d, wood)                                                            # top, overhanging the carcass
    inner = h - kick - 0.1 - t
    gap = (inner - shelves * t) / (shelves + 1)
    palette = ["red", "plum", "green", "brass", "blue", "paper", "rust", "oak"]
    y = kick
    for s_ in range(shelves + 1):
        if s_ > 0:
            c.add(ox + t, y - t, 0.06, ox + bw - t, y, bd, wood)                                 # shelf board
        x = ox + t + 0.03
        while x < ox + bw - t - 0.08:
            bwid = rng.choice((0.05, 0.06, 0.08, 0.1))
            bh = gap * rng.uniform(0.62, 0.95)
            if x + bwid > ox + bw - t - 0.16:
                break
            if rng.random() < 0.1:                                                               # an empty gap in the row
                x += 0.12
                continue
            c.add(x, y, 0.1, x + bwid, y + bh, bd - 0.06, rng.choice(palette))
            x += bwid + 0.005
        if s_ and rng.random() < 0.6:                                                            # a leaning book at the end of a row
            lx = ox + bw - t - 0.14
            c.add(lx, y, 0.1, lx + 0.06, y + gap * 0.7, bd - 0.06, rng.choice(palette), (0, 0, -12), (lx + 0.03, y, 0.2))
        y += gap + t
    return c.boxes


def wardrobe(w, h, d, ajar=False, kind="dark", panel="oak"):
    c = Part(w, h, d)
    foot = 0.1
    c.add(0.02, 0, 0.02, 0.02 + 0.08, foot, 0.02 + 0.08, kind)
    c.add(w - 0.1, 0, 0.02, w - 0.02, foot, 0.1, kind)
    c.add(0.02, 0, d - 0.1, 0.1, foot, d - 0.02, kind)
    c.add(w - 0.1, 0, d - 0.1, w - 0.02, foot, d - 0.02, kind)
    c.add(0, foot, 0, w, h - 0.12, d - 0.06, kind)                                              # carcass
    c.add(-0.0, h - 0.12, -0.0, w, h, d, kind)                                                  # cornice
    dw = (w - 0.12) / 2
    for i, x0 in enumerate((0.06, 0.06 + dw)):
        x1 = x0 + dw - 0.0
        rot, piv = None, None
        if ajar and i == 1:
            rot, piv = (0, 38, 0), (x1, foot, d - 0.06)
        c.add(x0, foot + 0.02, d - 0.06, x1, h - 0.14, d - 0.02, panel, rot, piv)               # door slab
        c.add(x0 + 0.1, foot + 0.14, d - 0.02, x1 - 0.1, h - 0.28, d, kind, rot, piv)           # raised panel
        hx = x1 - 0.09 if i == 0 else x0 + 0.05
        c.add(hx, 0.95, d - 0.0, hx + 0.04, 1.2, d + 0.03, "brass", rot, piv)                  # handle
    return c.boxes


def locker():
    w, h, d = 0.62, 2.0, 0.69
    c = Part(w, h, d)
    c.add(0, 0, 0, w, h, d - 0.06, "steel")
    c.add(0, 0.0, 0, w, 0.1, d, "black")                                                       # base
    c.add(0.02, 0.12, d - 0.06, w - 0.02, h - 0.04, d - 0.02, "concrete")                      # door
    for i in range(5):                                                                          # louvre slats top and bottom
        c.add(0.1, 1.55 + i * 0.07, d - 0.02, w - 0.1, 1.55 + i * 0.07 + 0.03, d, "black")
        c.add(0.1, 0.22 + i * 0.07, d - 0.02, w - 0.1, 0.22 + i * 0.07 + 0.03, d, "black")
    c.add(0.1, 1.1, d - 0.02, 0.18, 1.34, d + 0.02, "black")                                    # handle recess
    c.add(0.38, 1.28, d - 0.02, 0.5, 1.38, d, "brass")                                          # number plate
    return c.boxes


# ---- tables and small seats ------------------------------------------------------------------------------------------
def prison_cafeteria_table():
    w, h, d = 2.62, 0.75, 1.75
    c = Part(w, h, d)
    top = 0.75
    # bolted steel table with a bench on each long side: seat 0.44 m, table top 0.75 m
    c.add(0.0, top - 0.06, 0.45, w, top, d - 0.45, "steel")
    c.add(0.06, top - 0.07, 0.5, w - 0.06, top - 0.06, d - 0.5, "concrete")
    for x in (0.2, w - 0.2 - 0.12):
        c.add(x, 0.0, 0.6, x + 0.12, top - 0.06, d - 0.6, "steel")                                # slab supports
        c.add(x - 0.04, 0.0, 0.5, x + 0.16, 0.06, d - 0.5, "black")                                  # floor plates
        c.add(x, 0.38, 0.0, x + 0.12, 0.44, 0.5, "steel")                                            # bench arms
        c.add(x, 0.38, d - 0.5, x + 0.12, 0.44, d, "steel")
        c.add(x, 0.2, 0.0, x + 0.12, 0.38, 0.12, "steel")
        c.add(x, 0.2, d - 0.12, x + 0.12, 0.38, d, "steel")
    for z0, z1 in ((0.0, 0.4), (d - 0.4, d)):
        c.add(0.1, 0.38, z0, w - 0.1, 0.44, z1, "concrete")                                       # benches
    return c.boxes


def bedroom_bench(w=1.0):
    c = Part(w, 0.46, 0.4)
    for x in (0.04, w - 0.04 - VOX):
        for z in (0.04, 0.4 - 0.04 - VOX):
            c.add(x, 0, z, x + VOX, 0.36, z + VOX, "dark")
    c.add(0.04, 0.12, 0.04, w - 0.04, 0.18, 0.1, "dark")
    c.add(0.0, 0.36, 0.0, w, 0.42, 0.4, "dark")
    c.add(0.04, 0.42, 0.04, w - 0.04, 0.46, 0.36, "@cloth")
    return c.boxes


def vanity_stool():
    c = Part(0.4, 0.46, 0.4)
    for sx, sz in ((0.07, 0.07), (0.33 - VOX, 0.07), (0.07, 0.33 - VOX), (0.33 - VOX, 0.33 - VOX)):
        dx = -9 if sx < 0.2 else 9
        dz = 9 if sz < 0.2 else -9
        c.add(sx, 0, sz, sx + VOX, 0.32, sz + VOX, "dark", (dz * -1, 0, dx), (sx + VOX / 2, 0.32, sz + VOX / 2))
    c.add(0.02, 0.32, 0.02, 0.38, 0.38, 0.38, "dark")
    c.add(0.0, 0.38, 0.0, 0.4, 0.46, 0.4, "@cloth")
    return c.boxes


# ---- register ----------------------------------------------------------------------------------------------------------
_reg("gothicHighbackChair", gothic_highback(), (0.56, 1.30, 0.56), {"@cloth": ["plum", "red", "green"]})
_reg("restraintChair", restraint_chair(), (0.8, 1.35, 0.8))
_reg("mansionRockingChair", rocking_chair(), (0.6, 1.05, 0.9), {"@wood": WOODS, "@cloth": CLOTH})
_reg("beachChair", beach_chair(), (0.6, 0.85, 1.0), {"@cloth": ["blue", "red", "yellow"]})
_reg("bunkBed", bunk_bed(), (1.0, 1.85, 2.05), {"@cloth": CLOTH})
_reg("prisonBunk", prison_bunk(), (0.9, 1.7, 1.9))
_reg("gothicDoubleBed", gothic_canopy_bed(), (2.0, 2.38, 2.31), {"@cloth": ["plum", "red"]})
_reg("loungeCouch", couch(2), (1.7, 0.9, 0.95), {"@cloth": CLOTH}, [(couch(2), {"@cloth": ["blue", "green", "plum"]}), (couch(2, 0.78), {"@cloth": CLOTH}), (couch(2, 0.66), {"@cloth": ["blue", "green", "plum"]})])
_reg("loungeCouchWide", couch(3), (2.4, 0.9, 0.98), {"@cloth": CLOTH}, [(couch(3), {"@cloth": ["blue", "green", "plum"]}), (couch(3, 0.78), {"@cloth": CLOTH}), (couch(3, 0.66), {"@cloth": ["blue", "green", "plum"]})])
_reg("normalBookcase", bookcase(1.0, 1.81, 0.42, 4, 11, "dark", False), (1.0, 1.81, 0.42), {},
     [(bookcase(1.0, 1.81, 0.42, 4, 111, "oak", False), {}), (bookcase(1.0, 1.81, 0.42, 3, 211, "dark", True), {})])
_reg("mansionBookshelf", bookcase(0.88, 2.06, 0.62, 5, 12, "dark", True), (0.88, 2.06, 0.62), {},
     [(bookcase(0.88, 2.06, 0.62, 5, 112, "oak", True), {}), (bookcase(0.88, 2.06, 0.62, 4, 212, "dark", True), {})])
_reg("gothicBookcase", bookcase(1.38, 2.44, 0.5, 6, 13, "black", True), (1.38, 2.44, 0.5), {},
     [(bookcase(1.38, 2.44, 0.5, 6, 113, "dark", True), {}), (bookcase(1.38, 2.44, 0.5, 5, 213, "black", True), {})])
_reg("bedroomWardrobe", wardrobe(1.25, 2.12, 0.62), (1.25, 2.12, 0.62), {},
     [(wardrobe(1.25, 2.12, 0.62, False, "oak", "dark"), {}), (wardrobe(1.25, 2.12, 0.62, False, "dark", "dark"), {})])
_reg("gothicWardrobe", wardrobe(1.38, 2.5, 0.69, False, "black", "dark"), (1.38, 2.5, 0.69), {},
     [(wardrobe(1.38, 2.5, 0.69, False, "dark", "oak"), {}), (wardrobe(1.38, 2.5, 0.69, False, "black", "oak"), {})])
_reg("locker", locker(), (0.62, 2.0, 0.69))
_reg("prisonCafeteriaTable", prison_cafeteria_table(), (2.62, 0.75, 1.75))
_reg("bedroomBench", bedroom_bench(1.0), (1.0, 0.46, 0.4), {"@cloth": ["red", "plum", "green"]})
_reg("gothicBedroomBench", bedroom_bench(1.1), (1.1, 0.46, 0.4), {"@cloth": ["plum", "red"]})
_reg("vanityStool", vanity_stool(), (0.4, 0.46, 0.4), {"@cloth": ["red", "plum", "green"]})
_reg("gothicVanityStool", vanity_stool(), (0.4, 0.46, 0.4), {"@cloth": ["plum", "red"]})

# ---- sizes only: surfaces that were the wrong height for the player and for what stands on them ---------------------------
TARGET_SIZE["officeDesk"] = (1.62, 0.75, 0.75)                      # top at 0.75 m (it was 0.88 m)
for _kit in ("normal", "luxury", "gothic"):
    TARGET_SIZE[_kit + "KitchenCounter"] = (1.5, 0.92, 0.69)        # counter top 0.92 m (1.12 m), matches the stove and sink
    TARGET_SIZE[_kit + "KitchenSink"] = (1.25, 1.12, 0.69)         # basin at counter height, the tap rises above it
    TARGET_SIZE[_kit + "KitchenStove"] = (0.88, 0.92, 0.69)
