"""Mall/shop group: the arcade, carnival and shopping-arcade types redone low-poly. exec'd by build_blocky_props.py after SIZE_SCALE and before the mansion finishes, so
PROPS, VARIANTS, Part, VOX, _reg, TARGET_SIZE, FINISH_A and FINISH_B are in scope.

What changes, and what does not:
  - Fewer, chunkier boxes: rows of goods, bulbs, bottles, buckets, menu lines and donut rings become a few long strips; layered
    trims (bezels behind screens, white rings under canopies, inner glass layers) are gone; flat panels sit flush instead of on top.
  - Every type in LOWPOLY is built with hidden_faces(): faces on the floor, buried in another box or covered by a box sitting on them
    are not emitted. Big floor props (carousel, centrepiece, ring toss, cinema screen) gain the most, since every 0.5 m face cell
    is two triangles.
  - Locked to staging 29b79686: type ids, the number of models per type (so a seed picks the same variant slot), every model's
    bounds (so prop_collider_sizes.gd regenerates unchanged and footprints/placement stay put), the front (+z), the back at the wall
    (z = 0) for wall-mounted signs and boards, and the colour options. Same atlas, no new tiles.
shootingGallery, whackAMole and duckPond have no models of their own (blocky_prop_models.gd points them at ringTossStall_1,
ringTossStall_0 and circusPedestal), so they follow those two types.
"""

_MALL_078 = ["vendingMachine", "arcadeCabinet", "arcadeCabinetCyanMagenta", "arcadeBasketballHoop", "arcadeTokenChanger",
             "prizeClawMachine", "prizeCounter", "snackKiosk", "carnivalTicketBooth", "ringTossStall", "popcornCart", "strengthTester",
             "circusPedestal", "carnivalCarousel", "carouselCenterpiece", "mascotStatue",
             "displayCase", "menuBoard", "donutSign", "flowerStand", "barberStation", "tvWall", "cinemaScreen", "ticketBooth",
             "concessionCounter", "mallPlanter"]


def _keep_one(name, boxes):
    """Single-shape fraction types (extra.py): new boxes, staging colour options, no shape variants."""
    assert name in PROPS and not VARIANTS.get(name), (name, VARIANTS.get(name))
    PROPS[name] = (boxes, PROPS[name][1])


def _recolour(boxes, mapping):
    return [b[:6] + (mapping.get(b[6], b[6]),) + tuple(b[7:]) for b in boxes]


# ---- arcade (fractions of the staging footprint; front = +z) ----------------------------------------------------------------
def lp_vending():
    return [(0, 0, 0, 1, 1, .9, "red"),
            (.08, .3, .9, .92, .92, 1, "glass"),                     # one window (the paper layer behind the glass is gone)
            (.08, .08, .9, .92, .2, 1, "black"),                     # pickup flap
            (.7, .22, .9, .9, .28, .98, "brass")]                    # coin panel


def lp_arcade():
    return [(0, 0, 0, 1, .9, .9, "@cloth"),
            (.04, .9, 0, .96, 1, .7, "black"),                       # marquee
            (.12, .52, .9, .88, .86, .97, "screen"),                 # screen, no bezel layer
            (.06, .36, .5, .94, .5, 1, "dark"),                      # control deck
            (.2, .5, .74, .8, .53, .86, "amber")]                    # one button strip


def lp_hoop():
    return [(0, 0, 0, 1, .5, .3, "@cloth"),                          # cabinet
            (.1, .5, 0, .9, 1, .1, "white"),                         # backboard
            (.3, .62, .1, .7, .7, .4, "red"),                        # rim
            (0, 0, .3, 1, .14, 1, "black")]                          # ramp


def lp_token():
    return [(0, 0, 0, 1, .9, 1, "@cloth"),
            (.1, .5, .9, .9, .85, 1, "glass"),
            (.3, .2, .9, .7, .3, 1, "black"),
            (.2, .9, .1, .8, 1, .9, "yellow")]


def lp_claw():
    return [(0, 0, 0, 1, .3, 1, "@cloth"),                           # base
            (0, .3, 0, 1, .94, .06, "steel"),                        # back panel
            (0, .3, .06, .06, .94, 1, "steel"), (.94, .3, .06, 1, .94, 1, "steel"),
            (.06, .3, .94, .94, .94, 1, "glass"),                    # front glass
            (0, .94, 0, 1, 1, 1, "amber"),                           # lit lid
            (.1, .3, .1, .9, .45, .9, "plum"),                       # prize pile
            (.45, .6, .45, .55, .94, .55, "steel")]                  # claw drop


def lp_prize_counter():
    return [(0, 0, 0, 1, .6, 1, "@wood"),
            (.05, .6, .1, .95, 1, .5, "glass"),                      # prize case
            (.1, .6, .15, .9, .82, .45, "red")]                      # prizes as one row


def lp_snack_kiosk():
    return [(0, 0, 0, 1, .55, 1, "@cloth"),
            (0, .55, 0, .06, .9, 1, "@cloth"), (.94, .55, 0, 1, .9, 1, "@cloth"),
            (0, .9, 0, 1, 1, 1, "@cloth"),                           # roof
            (.06, .55, .1, .94, .9, .2, "glass")]                    # back shelf glass


def lp_carnival_ticket_booth():
    return [(0, 0, 0, 1, .45, 1, "red"),
            (0, .45, 0, .08, .85, 1, "red"), (.92, .45, 0, 1, .85, 1, "red"), (.08, .45, 0, .92, .85, .08, "red"),
            (.08, .5, .94, .92, .78, 1, "glass"),
            (0, .85, 0, 1, 1, 1, "white")]                           # roof, one block (the yellow cap is gone)


def lp_ring_toss():
    return [(0, 0, 0, .05, .8, .05, "dark"), (.95, 0, 0, 1, .8, .05, "dark"),     # posts stop under the awning
            (0, .8, 0, 1, 1, 1, "@cloth"),                           # awning
            (0, 0, .5, 1, .5, .9, "dark"),                           # counter
            (.15, .5, .6, .85, .82, .7, "amber")]                    # one rack of bottles


def lp_popcorn_cart():
    return [(0, .2, .1, 1, .5, .9, "red"),
            (0, 0, .1, .1, .2, .9, "black"), (.9, 0, .1, 1, .2, .9, "black"),   # wheels
            (.05, .5, .12, .95, .8, .88, "glass"),
            (.05, .8, .1, .95, .9, .9, "paper"),
            (.1, .9, .1, .9, 1, .9, "yellow")]


def lp_strength():
    return [(0, 0, 0, 1, .2, 1, "dark"),
            (.4, .2, .3, .6, .9, .7, "paper"),
            (.36, .9, .26, .64, 1, .74, "brass"),
            (.1, .2, .3, .3, .5, .7, "red")]


def lp_circus_pedestal():
    return [(0, 0, 0, 1, .6, 1, "red"), (.1, .6, .1, .9, .8, .9, "white"), (.2, .8, .2, .8, 1, .8, "yellow")]


def lp_carousel():
    b = [(0, 0, 0, 1, .12, 1, "red"),                                # one deck (dark plinth and red deck were two full-size slabs)
         (.47, .12, .47, .53, .8, .53, "brass"),                     # centre pole
         (.05, .8, .05, .95, .9, .95, "red"),                        # canopy, one slab (white ring under it is gone)
         (.25, .9, .25, .75, 1, .75, "yellow")]
    for x, z in ((.2, .2), (.74, .2), (.2, .74), (.74, .74)):
        b.append((x, .12, z, x + .06, .8, z + .06, "brass"))         # horse poles run up into the canopy
    return b


def lp_centrepiece():
    return [(0, 0, 0, 1, .1, 1, "red"),
            (.45, .1, .45, .55, .74, .55, "brass"),
            (.04, .74, .04, .96, .84, .96, "red"),
            (.2, .84, .2, .8, .94, .8, "yellow"),
            (.4, .94, .4, .6, 1, .6, "brass")]


def lp_mascot():
    return [(0, 0, 0, 1, .2, 1, "stone"),
            (.2, .2, .3, .8, .62, .7, "@cloth"),                     # body
            (.1, .3, .4, .9, .56, .6, "@cloth"),                     # arms as one bar through the body
            (.26, .62, .26, .74, 1, .74, "@cloth"),                  # head
            (.3, .8, .74, .7, .9, .8, "white")]                      # face


_keep_one("arcadeCabinet", lp_arcade())
_keep_one("arcadeCabinetCyanMagenta", lp_arcade())
_keep_one("arcadeBasketballHoop", lp_hoop())
_keep_one("arcadeTokenChanger", lp_token())
_keep_one("prizeClawMachine", lp_claw())
_keep_one("prizeCounter", lp_prize_counter())
_keep_one("snackKiosk", lp_snack_kiosk())
_keep_one("carnivalTicketBooth", lp_carnival_ticket_booth())
_keep_one("ringTossStall", lp_ring_toss())
_keep_one("popcornCart", lp_popcorn_cart())
_keep_one("strengthTester", lp_strength())
_keep_one("circusPedestal", lp_circus_pedestal())
_keep_one("carnivalCarousel", lp_carousel())
_keep_one("carouselCenterpiece", lp_centrepiece())
_keep_one("mascotStatue", lp_mascot())

# vendingMachine: staging has the base plus two automatic finishes (rework3 COMMON_SINGLES); rebuild them from the new boxes with the
# same swaps, so slot 1 is still the teal finish and slot 2 the plum one.
_vm = lp_vending()
_vm_kinds = {b[6] for b in _vm}
assert len(VARIANTS.get("vendingMachine", [])) == 2, VARIANTS.get("vendingMachine")
PROPS["vendingMachine"] = (_vm, PROPS["vendingMachine"][1])
VARIANTS["vendingMachine"] = [(_recolour(_vm, {k: v for k, v in m.items() if k in _vm_kinds}), dict(s))
                              for m, (_b, s) in zip((FINISH_A, FINISH_B), VARIANTS["vendingMachine"])]


# ---- shopping arcade (metres, like blocky_props_mall.py; front = +z, back z = 0 at the wall) --------------------------------------
def lp_display_case():
    w, h, d = 1.4, 1.25, 0.75
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.74, d, "@wood")                                     # cabinet and steel deck as one block
    c.add(0.1, 0.2, d - 0.01, w - 0.1, 0.3, d, "@topping")                      # trim stripe
    c.add(0.1, 0.74, 0.18, w - 0.1, 0.82, 0.36, "@food")                        # bottom tray of pastries, one row
    c.add(0.05, 0.98, 0.06, w - 0.05, 1.0, d - 0.06, "steel")                   # upper tray
    c.add(0.1, 1.0, 0.18, w - 0.1, 1.08, 0.36, "@topping")                      # upper row
    c.add(0.03, 0.74, d - 0.04, w - 0.03, 1.2, d, "glass")                      # front glass
    c.add(0.03, 1.2, 0.0, w - 0.03, 1.25, d, "glass")                           # glass lid
    for x in (0.0, w - 0.03):
        c.add(x, 0.74, 0.0, x + 0.03, 1.25, d, "steel")                         # end posts
    return c.boxes


def lp_menu_board():
    w, h, d = 1.5, 0.9, 0.08
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, h, 0.045, "@board")                                 # one board, no separate frame layer
    for col in range(3):
        x0 = 0.1 + col * 0.47
        c.add(x0, 0.7, 0.045, x0 + 0.3, 0.76, 0.05, "@title")                   # headings
        c.add(x0, 0.2, 0.045, x0 + 0.36, 0.55, 0.05, "white")                   # the price list as one block per column
    return c.boxes


def lp_donut_sign():
    w, h, d = 1.3, 1.3, 0.3
    c = Part(w, h, d)
    c.add(0.6, 0.0, 0.0, 0.7, 0.2, 0.1, "steel")                                # wall bracket
    c.add(-0.02, 0.22, 0.05, 0.22, 0.98, 0.25, "sand")                          # dough ring as four bars (was twelve blocks)
    c.add(0.98, 0.22, 0.05, 1.22, 0.98, 0.25, "sand")
    c.add(0.22, -0.02, 0.05, 0.98, 0.22, 0.25, "sand")                          # corners left open: reads round, not square
    c.add(0.22, 0.98, 0.05, 0.98, 1.22, 0.25, "sand")
    c.add(0.0, 0.25, 0.25, 0.2, 0.95, 0.3, "@icing")                            # icing on the face
    c.add(1.0, 0.25, 0.25, 1.2, 0.95, 0.3, "@icing")
    c.add(0.25, 0.0, 0.25, 0.95, 0.2, 0.3, "@icing")
    c.add(0.25, 1.0, 0.25, 0.95, 1.2, 0.3, "@icing")
    c.add(0.55, 1.05, 0.29, 0.6, 1.08, 0.31, "yellow")                          # sprinkles
    c.add(0.05, 0.6, 0.29, 0.1, 0.63, 0.31, "blue")
    return c.boxes


def lp_flower_stand():
    w, h, d = 1.3, 1.2, 0.65
    c = Part(w, h, d)
    for tier in range(3):                                                        # stepped wooden tiers
        z0 = tier * 0.2
        y1 = 0.7 - tier * 0.25
        c.add(0.0, 0, z0, w, y1, z0 + 0.22 if tier < 2 else d, "@wood")
        c.add(0.06, y1, z0 + 0.02, w - 0.06, y1 + 0.42, z0 + 0.2, "leaf")       # one hedge of stems per tier
        c.add(0.1, y1 + 0.42, z0 + 0.04, w - 0.1, y1 + 0.5, z0 + 0.18,
              ["red", "yellow", "plum"][tier])                                   # one band of blooms per tier
    return c.boxes


def lp_barber_station():
    w, h, d = 1.2, 1.9, 0.45
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.89, d, "@wood")                                     # cabinet and top as one block
    c.add(0.05, 0.92, 0.0, w - 0.05, 1.9, 0.04, "mirror")                       # mirror, no steel frame layer behind it
    c.add(0.12, 0.89, 0.25, 0.56, 1.05, 0.33, "blue")                           # tonics as one row
    c.add(0.7, 0.89, 0.2, 1.05, 0.93, 0.38, "black")                            # clippers tray
    return c.boxes


def lp_tv_wall():
    w, h, d = 1.6, 1.9, 0.5
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.7, d, "black")                                      # base unit
    c.add(0.0, 0.7, 0.0, w, 1.9, 0.06, "grey")
    for row in range(2):
        for col in range(2):
            x0 = 0.06 + col * 0.76
            y0 = 0.78 + row * 0.56
            c.add(x0, y0, 0.06, x0 + 0.72, y0 + 0.5, 0.1, "screen" if (row + col) % 2 else "@screen")   # screens, no bezel layer
    c.add(0.15, 0.7, 0.2, 1.45, 0.78, 0.45, "grey")                             # one row of boxed consoles
    return c.boxes


def lp_cinema_screen():
    w, h, d = 4.2, 2.2, 0.12
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, h - 0.2, 0.05, "black")
    c.add(1.0, 0.1, 0.05, w - 1.0, h - 0.2, 0.06, "white")                      # screen between the curtains (not under them)
    c.add(0.1, 0.1, 0.05, 1.0, h - 0.2, 0.07, "@curtain")                       # curtains drawn back
    c.add(w - 1.0, 0.1, 0.05, w - 0.1, h - 0.2, 0.07, "@curtain")
    c.add(0.0, h - 0.2, 0.0, w, h, 0.12, "@curtain")                            # valance, down to the wall
    return c.boxes


def lp_ticket_booth():
    w, h, d = 1.7, 2.35, 1.2
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 1.0, d, "@panel")
    c.add(0.0, 1.0, 0.0, 0.1, 2.1, d, "@panel")
    c.add(w - 0.1, 1.0, 0.0, w, 2.1, d, "@panel")
    c.add(0.1, 1.0, 0.0, w - 0.1, 2.1, 0.1, "@panel")
    c.add(0.1, 1.0, d - 0.08, w - 0.1, 1.95, d - 0.04, "glass")                 # window
    c.add(0.55, 1.0, d - 0.04, 1.15, 1.06, d, "brass")                          # ticket slot
    c.add(0.0, 2.1, 0.0, w, 2.35, d, "red")                                     # marquee roof
    c.add(0.08, 2.15, d - 0.01, w - 0.08, 2.3, d, "amber")                       # bulbs as one lit strip
    c.add(0.3, 0.3, d - 0.01, w - 0.3, 0.7, d, "brass")
    return c.boxes


def lp_concession():
    w, h, d = 2.2, 1.7, 0.8
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.99, d, "red")                                       # counter and top as one block
    c.add(0.05, 0.15, d - 0.01, w - 0.05, 0.8, d, "@panel")
    c.add(0.1, 0.99, 0.1, 0.8, 1.7, 0.58, "red")                                # popcorn machine
    c.add(0.15, 1.05, 0.58, 0.75, 1.6, 0.61, "glass")
    c.add(0.95, 0.99, 0.15, 1.45, 1.45, 0.55, "black")                          # soda fountain
    c.add(1.0, 1.15, 0.55, 1.4, 1.3, 0.58, "amber")                             # taps as one strip
    c.add(1.6, 0.99, 0.2, 1.95, 1.2, 0.55, "white")                             # stacked popcorn tubs
    return c.boxes


def lp_mall_planter():
    w, h, d = 1.3, 2.4, 1.3
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.58, d, "@stone")                                    # tiled box with its ledge, one block
    c.add(0.08, 0.58, 0.08, w - 0.08, 0.6, d - 0.08, "bark")
    c.add(0.58, 0.6, 0.58, 0.72, 1.3, 0.72, "bark")                             # ficus trunk, up into the crown
    c.add(0.2, 1.3, 0.2, 1.1, 1.9, 1.1, "leaf")                                 # crown in two steps (was three plus ground cover)
    c.add(0.35, 1.9, 0.35, 0.95, 2.4, 0.95, "green")
    return c.boxes


def _reg_keep(name, boxes):
    """Shopping-arcade types: same TARGET_SIZE and colour options as staging, new boxes."""
    _reg(name, boxes, TARGET_SIZE[name], PROPS[name][1])


_reg_keep("displayCase", lp_display_case())
_reg_keep("menuBoard", lp_menu_board())
_reg_keep("donutSign", lp_donut_sign())
_reg_keep("flowerStand", lp_flower_stand())
_reg_keep("barberStation", lp_barber_station())
_reg_keep("tvWall", lp_tv_wall())
_reg_keep("cinemaScreen", lp_cinema_screen())
_reg_keep("ticketBooth", lp_ticket_booth())
_reg_keep("concessionCounter", lp_concession())
_reg_keep("mallPlanter", lp_mall_planter())


# ---- hidden-face pass for the whole group ---------------------------------------------------------------------------------------
LOWPOLY.update(_MALL_078)
