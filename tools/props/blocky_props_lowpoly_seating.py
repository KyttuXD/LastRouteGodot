"""Beds/seating group: the 45 bed, chair, stool, bench and sofa types redone low-poly. exec'd by build_blocky_props.py after SIZE_SCALE and before the mansion finishes,
so the "<type>Mansion" sets are derived from these shapes. PROPS, VARIANTS, Part, VOX, _reg, TARGET_SIZE, CLOTH and WOODS are in scope.

What changes, and what does not:
  - Fewer, chunkier boxes: rear legs run up as the back posts, arms are one block per side, seat slats and seam strips are one slab,
    stretchers, trims, cup holders and hand rims are gone, rockers are five pieces, canopy drapes are four straight panels.
  - Every type in LOWPOLY is built with hidden_faces(): faces on the floor, buried in another box or covered by a box sitting on them are
    not emitted (same look, fewer triangles). Undersides above the floor are kept for the seat-pan probe.
  - Locked to staging: type ids, the number of models per type (so a seed picks the same variant slot), every model's bounds (so the
    generated colliders, footprints and placement stay put), the front (+z), seat tops, the 0.40 m clearance under beds (hiding), and
    the colour options. Same atlas, no new tiles.
Types whose staging design was already a handful of boxes (barberChair, dinerStool, waitingChairs, officeChair, normalEntryBench,
mansionChaiseLounge, publicShowerBench, gardenPlanterBench, prisonBunk, vanityStool, gothicVanityStool) keep their shapes and only get
the hidden-face pass.
"""

_SEATING_078 = ["barberChair", "beachChair", "bedroomBench", "bunkBed", "cinemaSeats", "dinerBooth", "dinerStool", "diningChair",
                "diningChairCushion", "doubleBed", "gardenPlanterBench", "gothicBedroomBench", "gothicDoubleBed", "gothicHighbackChair",
                "gothicVanityStool", "greenhouseBench", "hospitalBed", "labStool", "loungeCouch", "loungeCouchWide", "mallBench",
                "mansionChaiseLounge", "mansionRockingChair", "normalEntryBench", "officeChair", "prisonBunk", "publicShowerBench",
                "restraintChair", "singleBed", "vanityStool", "waitingChairs", "wheelchair", "woodenChair", "woodenChairCushion"]


def _keep_variants(name, shapes):
    """Replace a type's shapes one for one: shapes[0] is the base, the rest the variants, each keeping its staging colour options."""
    old = [PROPS[name]] + list(VARIANTS.get(name, []))
    assert len(old) == len(shapes), (name, len(old), len(shapes))
    PROPS[name] = (shapes[0], old[0][1])
    VARIANTS[name] = [(s, o[1]) for s, o in zip(shapes[1:], old[1:])]


# ---- chairs (woodenChair, woodenChairCushion, diningChair, diningChairCushion) ------------------------------------------------
def lp_chair(back="splat", cushion=False, arms=False, seat_kind="@wood", frame="@wood", cloth="@cloth"):
    """Rear legs run straight up into the back posts; one top rail and one back piece; arms are a solid side block."""
    c = Part(0.5, 0.94, 0.5)
    seat_top, seat_bot, top = 0.4375, 0.375, 0.9375
    ins, leg = 0.03, VOX
    for x in (ins, 0.5 - ins - leg):
        c.add(x, 0, 0.5 - ins - leg, x + leg, seat_bot, 0.5 - ins, frame)               # front legs
        c.add(x, 0, ins, x + leg, top, ins + leg, frame)                                 # rear legs = back posts
    c.add(ins, seat_bot, ins, 0.5 - ins, seat_top, 0.5 - ins, cloth if arms else seat_kind)
    if cushion:
        c.add(0.07, seat_top, 0.07, 0.43, seat_top + 0.05, 0.43, cloth)
    c.add(ins + leg, 0.8125, ins, 0.5 - ins - leg, top, ins + leg, frame)                # top rail
    if back == "splat":
        c.add(0.19, seat_top, ins + 0.005, 0.31, 0.8125, ins + 0.05, frame)             # one wide centre splat (staging's slat depth)
    elif back == "panel":
        c.add(ins + leg, 0.5, ins + 0.005, 0.5 - ins - leg, 0.8125, ins + leg, cloth)
    elif back == "ladder":
        c.add(ins + leg, 0.5625, ins + 0.005, 0.5 - ins - leg, 0.625, ins + leg, frame)  # two broad rungs
        c.add(ins + leg, 0.6875, ins + 0.005, 0.5 - ins - leg, 0.75, ins + leg, frame)
    if arms:
        for x in (ins, 0.5 - ins - leg):
            c.add(x, seat_top, ins + leg, x + leg, 0.6 + VOX, 0.5 - ins, frame)          # arm block
    return c.boxes


def lp_stool():
    c = Part(0.5, 0.94, 0.5)
    for x in (0.06, 0.5 - 0.06 - VOX):
        for z in (0.06, 0.5 - 0.06 - VOX):
            c.add(x, 0, z, x + VOX, 0.4375, z + VOX, "dark")
    c.add(0.03, 0.4375, 0.03, 0.47, 0.5, 0.47, "@wood")
    return c.boxes


for _n in ("woodenChair", "woodenChairCushion", "diningChair", "diningChairCushion"):
    _cush = _n.endswith("Cushion")
    _keep_variants(_n, [lp_chair("splat", cushion=_cush), lp_chair("ladder"), lp_chair("panel", cushion=_cush),
                        lp_chair("panel", arms=True), lp_stool()])


# ---- single and double beds (fractions of the footprint, 0.40 m clear underneath) ---------------------------------------------
def lp_bed(head_h=.62, foot_h=.5, pillows=2, canopy=False, frame="dark"):
    b = [(0, .30, 0, 1, .42, 1, frame),                                    # deck: 0.40 m under the bed for hiding
         (0, 0, 0, 1, head_h, .05, frame),                                 # headboard, down to the floor (it is the head legs)
         (0, .30, .95, 1, max(foot_h, .38), 1, frame),                     # footboard, above the gap so you slide in from the foot
         (.03, .42, .05, .97, .62, .36, "paper"),                          # sheet at the head end
         (.03, .42, .36, .97, .70, .95, "@cloth")]                         # blanket over the rest
    if pillows == 2:
        b += [(.06, .62, .08, .46, .72, .3, "white"), (.54, .62, .08, .94, .72, .3, "white")]
    else:
        b += [(.06, .62, .08, .94, .72, .3, "white")]
    if canopy:
        for x0 in (0, .94):
            for z0 in (0, .94):
                b.append((x0, 0, z0, x0 + .06, 1.0, z0 + .06, frame))       # posts are the legs too
            b.append((x0, .94, .06, x0 + .06, 1.0, .94, frame))              # two side rails carry the canopy
    else:
        b += [(0, 0, .9, .06, .30, .95, frame), (.94, 0, .9, 1, .30, .95, frame)]   # foot legs
    return b


def lp_platform_bed():
    """Staging's platform bed, already seven boxes; the lie-down probe reads its folded sheet, so it stays as it was."""
    return [(0, .28, 0, 1, .36, 1, "oak"), (.03, .36, .04, .97, .52, .96, "@cloth"), (.04, .52, .06, .96, .62, .3, "white"),
            (0, 0, 0, 1, .9, .05, "oak"), (.04, .52, .5, .96, .58, .96, "paper"), (.9, 0, .9, 1, .46, 1, "oak"),
            (0, 0, .9, .1, .46, 1, "oak")]


def lp_staging_bed_base():
    """Staging's base bed reached z = 1 only with its footboard and kept the pillow at .78; same bounds, fewer parts."""
    return [(0, .30, 0, 1, .42, 1, "dark"), (0, 0, 0, 1, .62, .05, "dark"), (0, .30, .95, 1, .5, 1, "dark"),
            (.03, .42, .05, .97, .66, .40, "paper"), (.03, .42, .40, .97, .70, .95, "@cloth"), (.05, .66, .07, .95, .78, .3, "paper"),
            (0, 0, .9, .08, .30, .95, "dark"), (.92, 0, .9, 1, .30, .95, "dark")]


for _n in ("singleBed", "doubleBed"):
    _keep_variants(_n, [lp_staging_bed_base(), lp_bed(.95, .24, 2), lp_bed(.72, .5, 1), lp_bed(.8, .3, 2, canopy=True),
                        lp_platform_bed()])


# ---- bunks ------------------------------------------------------------------------------------------------------------------
def lp_bunk_bed():
    w, h, d = 1.0, 1.85, 2.05
    c = Part(w, h, d)
    p = 0.09
    _posts(c, (0.0, w - p), (0.0, d - p), 0, h, p, "dark")
    for y, top in ((0.28, 0.44), (1.06, 1.22)):
        c.add(p, y, p, w - p, y + 0.06, d - p, "dark")                                    # deck
        c.add(0.12, y + 0.06, 0.12, w - 0.12, top + 0.08, 0.62, "paper")                 # sheet at the head
        c.add(0.12, y + 0.06, 0.62, w - 0.12, top + 0.12, d - 0.12, "@cloth")            # blanket
        c.add(0.16, top + 0.08, 0.16, w - 0.16, top + 0.14, 0.5, "white")                # pillow
    c.add(p, 0.5, 0, w - p, 0.62, 0.06, "dark")                                         # head board between the posts
    c.add(0, 1.5, p, 0.06, 1.62, d - p, "dark")                                         # upper guard rails
    c.add(w - 0.06, 1.5, p, w, 1.62, d - p, "dark")
    for y in (0.34, 0.66, 0.98):                                                         # three ladder rungs at the foot end
        c.add(w - p, y, d - p - 0.4, w, y + 0.06, d - p, "oak")
    return c.boxes


_reg("bunkBed", lp_bunk_bed(), (1.0, 1.85, 2.05), {"@cloth": CLOTH})


# ---- gothic canopy bed ------------------------------------------------------------------------------------------------------------
def lp_gothic_canopy_bed():
    w, h, d = 2.0, 2.38, 2.31
    c = Part(w, h, d)
    p = 0.14
    _posts(c, (0.0, w - p), (0.0, d - p), 0, 2.2, p, "dark")
    for x in (0.0, w - p):
        c.add(x, 2.2, 0, x + p, 2.38, p, "brass")                                          # finials on the head posts
        c.add(x, 2.2, 0, x + p, 2.3, d, "dark")                                             # canopy side rails
    c.add(p, 2.2, d - p, w - p, 2.3, d, "dark")                                             # canopy foot rail
    c.add(p, 0.3, 0.0, w - p, 1.55, 0.12, "dark")                                           # tall headboard
    c.add(0.3, 1.55, 0.0, w - 0.3, 1.7, 0.12, "dark")                                       # crest
    c.add(p, 0.42, d - 0.12, w - p, 0.85, d, "dark")                                        # footboard
    c.add(p, 0.42, p, w - p, 0.58, d - p, "dark")                                           # frame: 0.42 m clear underneath
    c.add(0.18, 0.58, 0.2, w - 0.18, 0.8, 0.9, "paper")                                     # sheet
    c.add(0.18, 0.58, 0.9, w - 0.18, 0.84, d - 0.2, "@cloth")                               # coverlet
    c.add(0.3, 0.8, 0.2, w - 0.3, 0.92, 0.6, "white")                                       # one long bolster
    for x0, x1 in ((0.1, 0.16), (w - 0.16, w - 0.1)):                                       # drapes tied back at head and foot
        c.add(x0, 1.0, 0.2, x1, 2.2, 0.7, "@cloth")
        c.add(x0, 1.0, d - 0.7, x1, 2.2, d - 0.2, "@cloth")
    return c.boxes


_reg("gothicDoubleBed", lp_gothic_canopy_bed(), (2.0, 2.38, 2.31), {"@cloth": ["plum", "red"]})


# ---- hospital bed -----------------------------------------------------------------------------------------------------------------
def lp_hospital_bed():
    w, h, d = 0.95, 1.05, 2.10
    c = Part(w, h, d)
    _wheels(c, w, d)
    c.add(0.06, 0.08, 0.06, w - 0.06, 0.16, d - 0.06, "steel")                 # chassis
    c.add(0.40, 0.16, 0.5, w - 0.40, 0.42, d - 0.5, "grey")                     # lift column
    c.add(0.04, 0.42, 0.04, w - 0.04, 0.5, d - 0.04, "steel")                   # deck
    c.add(0.06, 0.5, 0.06, w - 0.06, 0.64, 0.75, "@sheet")                      # mattress under its sheet
    c.add(0.06, 0.5, 0.75, w - 0.06, 0.72, d - 0.06, "@blanket")                # blanket over the foot
    c.add(0.18, 0.64, 0.12, w - 0.18, 0.76, 0.42, "white", (-12, 0, 0), (w / 2, 0.64, 0.12))  # raised pillow
    c.add(0.02, 0.42, 0.0, w - 0.02, 1.05, 0.06, "grey")                        # headboard
    c.add(0.02, 0.42, d - 0.06, w - 0.02, 0.86, d, "grey")                      # footboard
    for x in (0.0, w - 0.03):
        c.add(x, 0.6, 0.30, x + 0.03, 0.82, 0.95, "steel")                       # one side rail each side
    return c.boxes


_reg("hospitalBed", lp_hospital_bed(), (0.95, 1.05, 2.10), {"@sheet": ["white", "porcelain", "linen"],
                                                           "@blanket": ["teal", "blue", "linen"]})


# ---- thrones and special chairs ------------------------------------------------------------------------------------------------
def lp_gothic_highback():
    w, h, d = 0.56, 1.30, 0.56
    c = Part(w, h, d)
    leg, ins = VOX, 0.03
    seat_bot, seat_top = 0.375, 0.4375
    for x in (ins, w - ins - leg):
        c.add(x, 0, d - ins - leg, x + leg, seat_bot, d - ins, "dark")
        c.add(x, 0, ins, x + leg, seat_bot, ins + leg, "dark")
    c.add(ins, seat_bot, ins, w - ins, seat_top, d - ins, "dark")             # seat frame
    c.add(0.09, seat_top, 0.1, w - 0.09, seat_top + 0.04, d - 0.06, "@cloth")   # cushion
    pivot = (w / 2, seat_top, ins + leg / 2)
    lean = (-8, 0, 0)
    for x in (ins, w - ins - leg):
        c.add(x, seat_top, ins, x + leg, 1.18, ins + leg, "dark", lean, pivot)       # rear posts
        c.add(x, 1.18, ins, x + leg, 1.30, ins + leg, "brass", lean, pivot)           # finials
    c.add(ins + leg, 0.56, ins + 0.005, w - ins - leg, 1.12, ins + leg - 0.005, "@cloth", lean, pivot)  # tall padded panel
    c.add(ins + leg, 1.12, ins, w - ins - leg, 1.24, ins + leg, "dark", lean, pivot)   # one crest rail
    for x in (ins, w - ins - leg):
        c.add(x, seat_top, 0.16, x + leg, 0.68, d - ins, "dark")                 # solid arm blocks
    return c.boxes


def lp_restraint_chair():
    w, h, d = 0.8, 1.35, 0.8
    c = Part(w, h, d)
    leg = 0.1
    for x in (0.05, w - 0.05 - leg):
        for z in (0.05, d - 0.05 - leg):
            c.add(x, 0, z, x + leg, 0.4375, z + leg, "steel")
    c.add(0.0, 0.4375, 0.0, w, 0.5, d, "dark")                                       # seat
    pivot = (w / 2, 0.5, 0.1)
    lean = (-6, 0, 0)
    c.add(0.05, 0.5, 0.0, w - 0.05, 1.2, 0.12, "dark", lean, pivot)                  # back
    c.add(0.2, 1.2, 0.0, w - 0.2, 1.35, 0.12, "steel", lean, pivot)                   # head rest
    for x in (0.0, w - 0.0625):
        c.add(x, 0.5, 0.14, x + 0.0625, 0.76, d - 0.1, "steel")                     # solid arm blocks
        c.add(x, 0.76, 0.4, x + 0.0625, 0.82, 0.5, "brass")                          # one wrist cuff each
    for x in (0.05, w - 0.05 - leg):                                                  # ankle cuffs
        c.add(x, 0.2, d - 0.05 - leg, x + leg, 0.27, d - 0.05, "brass")
    c.add(0.0, 0.52, 0.3, w, 0.56, 0.36, "black")                                     # lap strap
    return c.boxes


def lp_rocking_chair():
    w, h, d = 0.6, 1.05, 0.9
    c = Part(w, h, d)
    segs = 7
    for x in (0.04, w - 0.04 - VOX):
        # rockers: four of staging's seven arc pieces (they set the bounds) over one flat bar that closes the gaps
        for i in (0, 2, 4, segs - 1):
            t = (i + 0.5) / segs
            z = 0.04 + t * (d - 0.08)
            u = (t - 0.5) * 2
            y = 0.10 * u * u
            slope = _math.degrees(_math.atan(0.2 * u))
            c.add(x, y, z - 0.07, x + VOX, y + 0.05, z + 0.07, "dark", (-slope, 0, 0))
        c.add(x, 0.0, 0.18, x + VOX, 0.0625, d - 0.18, "dark")
    seat_top = 0.40
    for x in (0.08, w - 0.08 - VOX):
        for z in (0.2, d - 0.3):
            c.add(x, 0.0625, z, x + VOX, seat_top, z + VOX, "@wood")
    c.add(0.06, seat_top - 0.06, 0.18, w - 0.06, seat_top, d - 0.22, "@wood")         # seat
    c.add(0.1, seat_top, 0.22, w - 0.1, seat_top + 0.04, d - 0.28, "@cloth")
    pivot = (w / 2, seat_top, 0.22)
    lean = (-12, 0, 0)
    for x in (0.08, w - 0.08 - VOX):
        c.add(x, seat_top, 0.18, x + VOX, 1.0, 0.18 + VOX, "@wood", lean, pivot)
    for y0 in (0.52, 0.72):                                                            # two broad slats
        c.add(0.14, y0, 0.18, w - 0.14, y0 + 0.12, 0.18 + 0.03, "@wood", lean, pivot)
    c.add(0.06, 0.94, 0.17, w - 0.06, 1.0, 0.18 + VOX, "@wood", lean, pivot)
    for x in (0.08, w - 0.08 - VOX):
        c.add(x, seat_top, d - 0.36, x + VOX, 0.68, d - 0.36 + VOX, "@wood")           # arm post
        c.add(x, 0.62, 0.3, x + VOX, 0.68, d - 0.36, "@wood")                          # arm
    return c.boxes


def lp_beach_chair():
    w, h, d = 0.6, 0.85, 1.0
    c = Part(w, h, d)
    frame = "steel"
    hinge = 0.45
    c.add(0.0, 0.2, hinge, w, 0.26, d, "@cloth")                       # seat deck
    for x in (0.0, w - VOX):
        c.add(x, 0.0, d - 0.1, x + VOX, 0.2, d - 0.1 + VOX, frame)      # front legs
        c.add(x, 0.0, hinge, x + VOX, 0.2, hinge + VOX, frame)           # middle legs
        c.add(x, 0.2, hinge, x + VOX, 0.26, d, frame)                    # side rails (they set the deck back 6 mm: the seat pan)
    pivot = (w / 2, 0.26, hinge)
    for x in (0.0, w - VOX):
        c.add(x, 0.26, hinge, x + VOX, 0.86, hinge + VOX, frame, (-45, 0, 0), pivot)     # back rails, reclined
    for i, kind in enumerate(("@cloth", "white", "@cloth")):                               # three broad stripes
        c.add(VOX, 0.3 + i * 0.1833, hinge - 0.01, w - VOX, 0.3 + (i + 1) * 0.1833, hinge + VOX, kind, (-45, 0, 0), pivot)
    for x in (0.0, w - VOX):
        c.add(x, 0.0, 0.1, x + VOX, 0.4, 0.1 + VOX, frame, (30, 0, 0), (x, 0.0, 0.1))
    return c.boxes


_reg("gothicHighbackChair", lp_gothic_highback(), (0.56, 1.30, 0.56), {"@cloth": ["plum", "red", "green"]})
_keep_variants("restraintChair", [lp_restraint_chair()] + [
    [b[:6] + (m.get(b[6], b[6]),) + tuple(b[7:]) for b in lp_restraint_chair()] for m in (FINISH_A, FINISH_B)])
_reg("mansionRockingChair", lp_rocking_chair(), (0.6, 1.05, 0.9), {"@wood": WOODS, "@cloth": CLOTH})
_reg("beachChair", lp_beach_chair(), (0.6, 0.85, 1.0), {"@cloth": ["blue", "red", "yellow"]})


# ---- sofas ------------------------------------------------------------------------------------------------------------------------
def lp_couch(seats, back=0.88):
    """Chunky arms and base on four short feet (gilt in the mansion finish), one seat cushion per seat (the sittable seats) and one
    long tilted back cushion instead of one per seat."""
    w = 0.7 * seats + 0.3
    h, d = 0.9, 0.95
    c = Part(w, h, d)
    arm = 0.15
    for x in (0.0, w - arm):
        c.add(x, 0.12, 0.0, x + arm, 0.62, d, "@cloth")                                       # arm block
        c.add(x - 0.02 if x else x, 0.62, 0.02, x + arm + (0.02 if x else 0), 0.68, d - 0.02, "@cloth")   # rolled top
    c.add(arm, 0.12, 0.0, w - arm, back + 0.02, 0.24, "@cloth")                               # back frame
    c.add(arm, 0.12, 0.24, w - arm, 0.3, d, "@cloth")                                         # seat base
    sw = (w - 2 * arm) / seats
    for i in range(seats):
        x0 = arm + i * sw
        c.add(x0 + 0.01, 0.3, 0.26, x0 + sw - 0.01, 0.44, d - 0.02, "@cloth")                  # seat cushion
    c.add(arm + 0.02, 0.44, 0.1, w - arm - 0.02, back, 0.3, "@cloth", (-9, 0, 0), (w / 2, 0.42, 0.2))   # back cushion
    for x in (0.04, w - 0.04 - VOX):
        for z in (0.06, d - 0.12):
            c.add(x, 0.0, z, x + VOX, 0.12, z + VOX, "dark")
    return c.boxes


_reg("loungeCouch", lp_couch(2), (1.7, 0.9, 0.95), {"@cloth": CLOTH},
     [(lp_couch(2), {"@cloth": ["blue", "green", "plum"]}), (lp_couch(2, 0.78), {"@cloth": CLOTH}),
      (lp_couch(2, 0.66), {"@cloth": ["blue", "green", "plum"]})])
_reg("loungeCouchWide", lp_couch(3), (2.4, 0.9, 0.98), {"@cloth": CLOTH},
     [(lp_couch(3), {"@cloth": ["blue", "green", "plum"]}), (lp_couch(3, 0.78), {"@cloth": CLOTH}),
      (lp_couch(3, 0.66), {"@cloth": ["blue", "green", "plum"]})])


# ---- benches ------------------------------------------------------------------------------------------------------------------
def lp_bedroom_bench(w=1.0):
    c = Part(w, 0.46, 0.4)
    for x in (0.04, w - 0.04 - VOX):
        c.add(x, 0, 0.04, x + VOX, 0.36, 0.4 - 0.04, "dark")                     # solid end panels instead of four legs and a rail
    c.add(0.0, 0.36, 0.0, w, 0.42, 0.4, "dark")
    c.add(0.04, 0.42, 0.04, w - 0.04, 0.46, 0.36, "@cloth")
    return c.boxes


def lp_greenhouse_bench():
    w, h, d = 1.6, 0.85, 0.6
    c = Part(w, h, d)
    for x in (0.05, w - 0.12):
        c.add(x, 0, 0.08, x + 0.07, 0.42, 0.52, "steel")                        # cast frames
        c.add(x, 0.42, 0.04, x + 0.07, 0.85, 0.11, "steel", (-10, 0, 0), (x, 0.42, 0.08))
    c.add(0.0, 0.4, 0.1, w, 0.44, 0.52, "@wood")                                # one seat slab
    for y in (0.5, 0.72):
        c.add(0.0, y, 0.05, w, y + 0.07, 0.09, "@wood", (-10, 0, 0), (w / 2, 0.42, 0.08))   # two back boards
    return c.boxes


def lp_mall_bench():
    w, h, d = 1.8, 0.5, 0.6
    c = Part(w, h, d)
    for x in (0.1, w - 0.2):
        c.add(x, 0, 0.05, x + 0.1, 0.4, d - 0.05, "steel")
    c.add(0.0, 0.4, 0.0, w, 0.5625, d, "@wood")                                # staging's seam strips stood 6 cm proud; the slab keeps that top
    return c.boxes


_reg("bedroomBench", lp_bedroom_bench(1.0), (1.0, 0.46, 0.4), {"@cloth": ["red", "plum", "green"]})
_reg("gothicBedroomBench", lp_bedroom_bench(1.1), (1.1, 0.46, 0.4), {"@cloth": ["plum", "red"]})
_reg("greenhouseBench", lp_greenhouse_bench(), (1.6, 0.85, 0.6), {"@wood": ["oak", "pine", "teal"]})
_reg("mallBench", lp_mall_bench(), (1.8, 0.5, 0.6), {"@wood": ["oak", "walnut"]})


# ---- cinema, diner, clinic -------------------------------------------------------------------------------------------------------
def lp_cinema_seats():
    w, h, d = 2.4, 1.0, 0.8
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.1, d, "black")                                      # riser plinth
    for i in range(4):
        x0 = 0.05 + i * 0.6
        c.add(x0 - 0.05, 0.1, 0.1, x0, 0.62, 0.7, "black")                      # armrests
        c.add(x0, 0.32, 0.25, x0 + 0.5, 0.45, 0.72, "@seat")                    # seat
        c.add(x0, 0.4, 0.1, x0 + 0.5, 1.0, 0.25, "@seat", (-10, 0, 0), (x0 + 0.25, 0.4, 0.17))   # back
    c.add(w - 0.05, 0.1, 0.1, w, 0.62, 0.7, "black")
    return c.boxes


def lp_diner_booth():
    w, h, d = 1.6, 1.15, 1.5
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.44, 0.5, "@seat")                                   # benches
    c.add(0.0, 0, d - 0.5, w, 0.44, d, "@seat")
    c.add(0.0, 0.44, 0.0, w, 1.15, 0.14, "@seat")                               # backs
    c.add(0.0, 0.44, d - 0.14, w, 1.15, d, "@seat")
    c.add(0.0, 0.44, 0.14, w, 0.48, 0.5, "red")                                 # seat pads (the seat pan is measured on them)
    c.add(0.0, 0.44, d - 0.5, w, 0.48, d - 0.14, "red")
    c.add(0.7, 0, 0.66, 0.9, 0.72, 0.84, "steel")                               # table post
    c.add(0.1, 0.72, 0.52, w - 0.1, 0.76, 0.98, "@wood")                        # table top
    c.add(0.25, 0.76, 0.6, 0.35, 0.86, 0.7, "white")                            # napkins
    c.add(1.1, 0.76, 0.65, 1.3, 0.78, 0.85, "white")                            # plate
    return c.boxes


def lp_wheelchair():
    w, h, d = 0.65, 0.95, 0.95
    c = Part(w, h, d)
    for x in (0.0, w - 0.05):
        c.add(x, 0, 0.12, x + 0.05, 0.6, 0.72, "black")                         # big wheels
        c.add(x + 0.01, 0.05, 0.17, x + 0.04, 0.55, 0.67, "steel")              # hand rims (they set the bounds)
    for x in (0.1, w - 0.15):
        c.add(x, 0, d - 0.12, x + 0.05, 0.48, d - 0.07, "steel")                # caster fork, one piece
    c.add(0.06, 0.42, 0.2, w - 0.06, 0.5, 0.7, "@seat")                         # seat
    c.add(0.06, 0.5, 0.12, w - 0.06, 0.92, 0.2, "@seat", (-8, 0, 0), (w / 2, 0.5, 0.16))   # back
    for x in (0.06, w - 0.1):
        c.add(x, 0.5, 0.1, x + 0.04, 0.95, 0.14, "steel")                       # push handles
        c.add(x, 0.66, 0.22, x + 0.04, 0.7, 0.62, "black")                      # arms
    c.add(0.12, 0.08, d - 0.06, w - 0.12, 0.12, d, "steel")                     # foot plates
    return c.boxes


def lp_lab_stool():
    w, h, d = 0.42, 0.75, 0.42
    c = Part(w, h, d)
    c.add(0.0, 0, 0.18, w, 0.07, 0.24, "steel")                                 # cross feet on the floor
    c.add(0.18, 0, 0.0, 0.24, 0.07, d, "steel")
    c.add(0.18, 0.07, 0.18, 0.24, 0.66, 0.24, "steel")                          # gas lift
    c.add(0.06, 0.3, 0.06, 0.36, 0.33, 0.36, "steel")                           # foot ring
    c.add(0.02, 0.66, 0.02, 0.4, 0.75, 0.4, "@seat")
    return c.boxes


_reg("cinemaSeats", lp_cinema_seats(), (2.4, 1.0, 0.8), {"@seat": ["red", "plum"]})
_reg("dinerBooth", lp_diner_booth(), (1.6, 1.15, 1.5), {"@seat": ["red", "teal", "plum"], "@wood": ["white", "oak"]})
_reg("wheelchair", lp_wheelchair(), (0.65, 0.95, 0.95), {"@seat": ["blue", "black", "teal"]})
_reg("labStool", lp_lab_stool(), (0.42, 0.75, 0.42), {"@seat": ["black", "blue", "grey"]})


# ---- hidden-face pass for the whole group (the mansion finishes are derived after this file) ------------------------------------
LOWPOLY.update(_SEATING_078)
LOWPOLY.update(n + "Mansion" for n in _SEATING_078)
