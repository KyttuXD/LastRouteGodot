"""Shopping arcade (mall) props, authored in metres like blocky_props_regions.py: the City's shop fixtures (shelf, fridge,
register, display, donut tray, coffee, fryer, rack, stool, clothes, screen, washer, flowers, barber chair, seats, menu
board, booth) rebuilt as proper Last Route props, plus the cinema and food court pieces. exec'd after
blocky_props_regions.py, so Part, _reg, _wheels and _foliage are in scope. Front is +z, back (z = 0) is the wall.
"""


def shop_shelf():
    w, h, d = 1.2, 1.9, 0.5
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, h, 0.04, "@frame")
    for x in (0.0, w - 0.04):
        c.add(x, 0, 0.0, x + 0.04, h, d, "@frame")
    c.add(0.04, 0, 0.04, w - 0.04, 0.1, d, "black")
    goods = ["red", "yellow", "blue", "green", "white", "amber", "plum", "teal"]
    for s in range(4):
        y = 0.1 + s * 0.44
        c.add(0.04, y, 0.04, w - 0.04, y + 0.03, d, "steel")
        c.add(0.04, y, d - 0.01, w - 0.04, y + 0.06, d, "white")                # price strip
        x = 0.07
        i = s * 5
        while x < w - 0.16:
            bw = 0.09 + (i % 3) * 0.04
            c.add(x, y + 0.03, 0.08, x + bw, y + 0.16 + ((i * 7) % 4) * 0.05, d - 0.05, goods[i % len(goods)])
            x += bw + 0.025
            i += 1
    c.add(0.1, h - 0.18, d - 0.02, w - 0.1, h - 0.05, d, "@sign")               # aisle header
    return c.boxes


def shop_fridge():
    w, h, d = 1.0, 2.1, 0.75
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, h, d - 0.04, "white")
    c.add(0.0, 1.9, d - 0.04, w, h, d, "@sign")                                 # lit header
    for x0 in (0.04, 0.51):
        c.add(x0, 0.12, d - 0.05, x0 + 0.45, 1.86, d - 0.04, "black")
        for s in range(5):
            y = 0.18 + s * 0.34
            for k in range(4):
                c.add(x0 + 0.04 + k * 0.1, y, d - 0.25, x0 + 0.1 + k * 0.1, y + 0.22, d - 0.1,
                      ["red", "green", "blue", "amber", "white"][(s + k) % 5])     # bottles
        c.add(x0 + 0.02, 0.12, d - 0.03, x0 + 0.43, 1.86, d - 0.02, "glass")     # glass door
        c.add(x0 + (0.38 if x0 < 0.5 else 0.03), 0.8, d - 0.02, x0 + (0.42 if x0 < 0.5 else 0.07), 1.3, d, "steel")
    c.add(0.0, 0, d - 0.04, w, 0.12, d, "black")
    return c.boxes


def checkout_counter():
    w, h, d = 1.8, 1.32, 0.75
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.92, d, "@wood")
    c.add(0.0, 0.92, 0.0, w, 0.96, d, "black")
    c.add(0.05, 0.1, d - 0.01, w - 0.05, 0.86, d, "@panel")                     # front panel
    c.add(0.15, 0.96, 0.15, 0.6, 1.08, 0.55, "grey")                            # register base
    c.add(0.2, 1.08, 0.2, 0.55, 1.1, 0.5, "black")                              # keys
    c.add(0.25, 1.1, 0.2, 0.5, 1.32, 0.26, "black")                             # customer display
    c.add(0.27, 1.13, 0.26, 0.48, 1.29, 0.27, "screen")
    c.add(0.7, 0.96, 0.25, 1.0, 0.98, 0.55, "glass")                            # scanner plate
    c.add(1.2, 0.96, 0.1, 1.7, 1.25, 0.25, "@goods")                            # impulse rack
    for i in range(4):
        c.add(1.24 + i * 0.11, 0.98, 0.25, 1.32 + i * 0.11, 1.18, 0.3, ["red", "yellow", "blue", "green"][i])
    return c.boxes


def display_case():
    w, h, d = 1.4, 1.25, 0.75
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.7, d, "@wood")
    c.add(0.0, 0.7, 0.0, w, 0.74, d, "steel")
    for t in range(2):
        y = 0.74 + t * 0.24
        c.add(0.05, y, 0.06, w - 0.05, y + 0.02, d - 0.06, "steel")             # trays
        for i in range(6):
            x0 = 0.1 + i * 0.205
            c.add(x0, y + 0.02, 0.18, x0 + 0.15, y + 0.08, 0.36, "@food")        # pastries / donuts / rings
            c.add(x0 + 0.05, y + 0.08, 0.24, x0 + 0.1, y + 0.09, 0.3, "@topping")
    c.add(0.02, 0.74, d - 0.04, w - 0.02, 1.2, d - 0.02, "glass")               # sloped glass front
    c.add(0.02, 1.2, 0.0, w - 0.02, 1.25, d - 0.02, "glass")
    for x in (0.0, w - 0.03):
        c.add(x, 0.74, 0.0, x + 0.03, 1.25, d, "steel")
    c.add(0.1, 0.2, d - 0.01, w - 0.1, 0.3, d, "@topping")                      # trim stripe
    return c.boxes


def coffee_station():
    w, h, d = 1.3, 1.55, 0.65
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.9, d, "@wood")
    c.add(0.0, 0.9, 0.0, w, 0.94, d, "black")
    c.add(0.1, 0.94, 0.08, 0.7, 1.4, 0.5, "steel")                              # espresso machine
    c.add(0.12, 1.4, 0.1, 0.68, 1.46, 0.48, "black")
    for x0 in (0.18, 0.46):
        c.add(x0, 1.1, 0.5, x0 + 0.08, 1.2, 0.56, "black")                      # group heads
        c.add(x0 + 0.01, 0.94, 0.48, x0 + 0.07, 1.02, 0.54, "white")            # cups
    c.add(0.3, 1.3, 0.5, 0.5, 1.36, 0.51, "screen")
    c.add(0.8, 0.94, 0.1, 1.0, 1.3, 0.3, "black")                               # grinder
    c.add(0.83, 1.3, 0.13, 0.97, 1.55, 0.27, "glass")
    for i in range(3):
        c.add(1.05, 0.94 + i * 0.06, 0.15, 1.23, 1.0 + i * 0.06, 0.45, "white")  # cup stack
    return c.boxes


def donut_fryer():
    w, h, d = 1.3, 1.25, 0.8
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.85, d, "steel")
    c.add(0.05, 0.85, 0.05, w - 0.05, 0.9, d - 0.05, "black")
    c.add(0.1, 0.88, 0.1, w - 0.1, 0.9, d - 0.1, "amber")                       # hot oil
    for i in range(5):
        c.add(0.15 + i * 0.2, 0.9, 0.3, 0.27 + i * 0.2, 0.94, 0.5, "sand")      # donuts frying
    c.add(0.0, 0.9, 0.0, w, 1.25, 0.08, "steel")                                # splash back
    c.add(0.1, 0.4, d - 0.01, 0.4, 0.55, d, "black")                            # controls
    c.add(0.15, 0.45, d - 0.012, 0.22, 0.5, d - 0.0, "red")
    return c.boxes


def bakery_rack():
    w, h, d = 1.0, 1.9, 0.6
    c = Part(w, h, d)
    _wheels(c, w, d)
    for x in (0.02, w - 0.06):
        for z in (0.02, d - 0.06):
            c.add(x, 0.08, z, x + 0.04, h, z + 0.04, "steel")
    for s in range(7):
        y = 0.2 + s * 0.24
        c.add(0.04, y, 0.04, w - 0.04, y + 0.02, d - 0.04, "steel")
        for i in range(4):
            c.add(0.08 + i * 0.22, y + 0.02, 0.12, 0.24 + i * 0.22, y + 0.1, d - 0.12, "@food")
    return c.boxes


def diner_stool():
    w, h, d = 0.42, 0.78, 0.42
    c = Part(w, h, d)
    c.add(0.06, 0, 0.06, 0.36, 0.04, 0.36, "steel")
    c.add(0.18, 0.04, 0.18, 0.24, 0.7, 0.24, "steel")
    c.add(0.08, 0.28, 0.08, 0.34, 0.3, 0.34, "steel")
    c.add(0.01, 0.68, 0.01, 0.41, 0.72, 0.41, "steel")
    c.add(0.02, 0.72, 0.02, 0.4, 0.78, 0.4, "@seat")
    return c.boxes


def diner_booth():
    w, h, d = 1.6, 1.15, 1.5
    c = Part(w, h, d)
    for z0, back_at_wall in ((0.0, True), (d - 0.5, False)):                     # two facing benches
        c.add(0.0, 0, z0, w, 0.44, z0 + 0.5, "@seat")
        if back_at_wall:
            c.add(0.0, 0.44, 0.0, w, 1.15, 0.14, "@seat")
        else:
            c.add(0.0, 0.44, d - 0.14, w, 1.15, d, "@seat")
    c.add(0.0, 0.44, 0.14, w, 0.48, 0.5, "red")
    c.add(0.0, 0.44, d - 0.5, w, 0.48, d - 0.14, "red")
    c.add(0.7, 0, 0.66, 0.9, 0.72, 0.84, "steel")                               # table post
    c.add(0.1, 0.72, 0.52, w - 0.1, 0.76, 0.98, "@wood")                        # table top
    c.add(0.25, 0.76, 0.6, 0.35, 0.86, 0.7, "white")                            # napkins, ketchup
    c.add(0.4, 0.76, 0.62, 0.45, 0.9, 0.67, "red")
    c.add(1.1, 0.76, 0.65, 1.3, 0.78, 0.85, "white")                            # plate
    return c.boxes


def menu_board():
    w, h, d = 1.5, 0.9, 0.08
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, h, 0.04, "black")
    c.add(0.03, 0.03, 0.04, w - 0.03, h - 0.03, 0.045, "@board")
    for col in range(3):
        x0 = 0.1 + col * 0.47
        c.add(x0, 0.7, 0.045, x0 + 0.3, 0.76, 0.05, "@title")                   # headings
        for r in range(4):
            c.add(x0, 0.52 - r * 0.12, 0.045, x0 + 0.24, 0.55 - r * 0.12, 0.05, "white")
            c.add(x0 + 0.3, 0.52 - r * 0.12, 0.045, x0 + 0.36, 0.55 - r * 0.12, 0.05, "yellow")
    return c.boxes


def donut_sign():
    w, h, d = 1.3, 1.3, 0.3
    c = Part(w, h, d)
    c.add(0.6, 0.0, 0.0, 0.7, 0.2, 0.1, "steel")                                # wall bracket
    ring = [(0.2, 0.2), (0.45, 0.1), (0.75, 0.1), (1.0, 0.2), (1.1, 0.45), (1.1, 0.75), (1.0, 1.0), (0.75, 1.1),
            (0.45, 1.1), (0.2, 1.0), (0.1, 0.75), (0.1, 0.45)]
    for i, (x, y) in enumerate(ring):
        c.add(x - 0.12, y - 0.12, 0.05, x + 0.12, y + 0.12, 0.25, "sand")       # dough ring
        c.add(x - 0.11, y - 0.06, 0.2, x + 0.11, y + 0.13, 0.3, "@icing")       # icing on the face
        if i % 3 == 0:
            c.add(x - 0.03, y + 0.02, 0.29, x + 0.02, y + 0.05, 0.31, ["yellow", "blue", "green", "white"][i // 3])
    return c.boxes


def washing_machine():
    w, h, d = 0.75, 1.15, 0.72
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 1.1, d, "white")
    c.add(0.0, 1.0, 0.0, w, 1.15, 0.2, "white")                                 # control panel
    c.add(0.05, 1.02, 0.18, 0.4, 1.12, 0.2, "screen")
    c.add(0.5, 1.03, 0.18, 0.6, 1.11, 0.21, "grey")                             # dial
    c.add(0.1, 0.25, d - 0.01, 0.65, 0.85, d, "steel")                          # porthole ring
    c.add(0.17, 0.32, d - 0.0, 0.58, 0.78, d + 0.01, "@drum")                   # glass with laundry
    c.add(0.05, 0.05, d - 0.01, 0.7, 0.15, d, "grey")
    c.add(0.55, 0.6, d, 0.62, 0.66, d + 0.02, "steel")                          # coin slot
    return c.boxes


def dryer_stack():
    w, h, d = 0.75, 2.05, 0.72
    c = Part(w, h, d)
    for y0 in (0.0, 1.0):
        c.add(0.0, y0, 0.0, w, y0 + 0.98, d, "white")
        c.add(0.12, y0 + 0.2, d - 0.01, 0.63, y0 + 0.75, d, "steel")
        c.add(0.18, y0 + 0.26, d, 0.57, y0 + 0.69, d + 0.01, "@drum")
        c.add(0.05, y0 + 0.85, d - 0.01, 0.4, y0 + 0.93, d, "screen")
    c.add(0.0, 1.98, 0.0, w, 2.05, d, "grey")
    return c.boxes


def flower_stand():
    w, h, d = 1.3, 1.2, 0.65
    c = Part(w, h, d)
    for tier in range(3):                                                        # stepped wooden tiers
        z0 = tier * 0.2
        y1 = 0.7 - tier * 0.25
        c.add(0.0, 0, z0, w, y1, z0 + 0.22, "@wood")
        for i in range(4):
            x0 = 0.08 + i * 0.3
            c.add(x0, y1, z0 + 0.03, x0 + 0.18, y1 + 0.18, z0 + 0.19, "steel")   # buckets
            c.add(x0 - 0.02, y1 + 0.18, z0 + 0.01, x0 + 0.2, y1 + 0.42, z0 + 0.21, "leaf")
            c.add(x0 + 0.02, y1 + 0.42, z0 + 0.04, x0 + 0.16, y1 + 0.5, z0 + 0.18,
                  ["red", "yellow", "white", "plum", "blue"][(i + tier) % 5])      # blooms
    return c.boxes


def barber_chair():
    w, h, d = 0.7, 1.25, 0.95
    c = Part(w, h, d)
    c.add(0.15, 0, 0.25, 0.55, 0.06, 0.75, "steel")                             # base
    c.add(0.28, 0.06, 0.38, 0.42, 0.42, 0.52, "steel")                          # hydraulic post
    c.add(0.05, 0.42, 0.2, w - 0.05, 0.56, 0.75, "@seat")                       # seat
    c.add(0.05, 0.56, 0.1, w - 0.05, 1.1, 0.22, "@seat", (-12, 0, 0), (w / 2, 0.56, 0.16))   # back
    c.add(0.2, 1.08, 0.08, 0.5, 1.25, 0.18, "@seat", (-12, 0, 0), (w / 2, 0.56, 0.16))      # headrest
    for x in (0.0, w - 0.07):
        c.add(x, 0.6, 0.25, x + 0.07, 0.68, 0.72, "steel")                      # chrome arms
    c.add(0.15, 0.16, 0.8, 0.55, 0.22, 0.95, "steel")                           # footrest
    return c.boxes


def barber_station():
    w, h, d = 1.2, 1.9, 0.45
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.85, d, "@wood")
    c.add(0.0, 0.85, 0.0, w, 0.89, d, "black")
    c.add(0.1, 0.95, 0.0, w - 0.1, 1.85, 0.04, "mirror")                        # mirror
    c.add(0.05, 0.92, 0.0, w - 0.05, 1.9, 0.02, "steel")
    for i, k in enumerate(("blue", "green", "amber", "white")):
        c.add(0.12 + i * 0.12, 0.89, 0.25, 0.2 + i * 0.12, 1.05 + (i % 2) * 0.06, 0.33, k)   # tonics, barbicide
    c.add(0.7, 0.89, 0.2, 1.05, 0.93, 0.38, "black")                            # clippers tray
    return c.boxes


def clothes_rack():
    w, h, d = 1.4, 1.65, 0.55
    c = Part(w, h, d)
    for x in (0.02, w - 0.06):
        c.add(x - 0.04, 0, 0.1, x + 0.08, 0.04, d - 0.1, "steel")
        c.add(x, 0.04, 0.25, x + 0.04, 1.6, 0.3, "steel")
    c.add(0.0, 1.58, 0.25, w, 1.62, 0.3, "steel")                               # rail
    for i in range(9):
        x0 = 0.1 + i * 0.135
        c.add(x0, 0.75, 0.08, x0 + 0.1, 1.55, d - 0.08,
              ["@cloth", "blue", "@cloth", "black", "white", "@cloth", "plum", "grey", "@cloth"][i])   # garments
    return c.boxes


def tv_wall():
    w, h, d = 1.6, 1.9, 0.5
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.7, d, "black")                                      # base unit
    c.add(0.0, 0.7, 0.0, w, 1.9, 0.06, "grey")
    for row in range(2):
        for col in range(2):
            x0 = 0.06 + col * 0.76
            y0 = 0.78 + row * 0.56
            c.add(x0, y0, 0.06, x0 + 0.72, y0 + 0.5, 0.1, "black")
            c.add(x0 + 0.03, y0 + 0.03, 0.1, x0 + 0.69, y0 + 0.47, 0.105, "screen" if (row + col) % 2 else "@screen")
    for i in range(3):
        c.add(0.15 + i * 0.5, 0.7, 0.2, 0.45 + i * 0.5, 0.78, 0.45, ["grey", "black", "white"][i])   # boxed consoles
    return c.boxes


def cinema_seats():
    w, h, d = 2.4, 1.0, 0.8
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.1, d, "black")                                      # riser plinth
    for i in range(4):
        x0 = 0.05 + i * 0.6
        c.add(x0 - 0.05, 0.1, 0.1, x0, 0.62, 0.7, "black")                      # armrests
        c.add(x0, 0.32, 0.25, x0 + 0.5, 0.45, 0.72, "@seat")                    # seat
        c.add(x0, 0.4, 0.1, x0 + 0.5, 1.0, 0.25, "@seat", (-10, 0, 0), (x0 + 0.25, 0.4, 0.17))   # back
        c.add(x0 + 0.05, 0.62, 0.0, x0 + 0.45, 0.7, 0.1, "black")
    c.add(w - 0.05, 0.1, 0.1, w, 0.62, 0.7, "black")
    c.add(0.0, 0.62, 0.3, 0.04, 0.68, 0.36, "brass")                            # cup holder
    return c.boxes


def cinema_screen():
    w, h, d = 4.2, 2.2, 0.12
    c = Part(w, h, d)
    c.add(0.0, 0.0, 0.0, w, h, 0.05, "black")
    c.add(0.1, 0.1, 0.05, w - 0.1, h - 0.1, 0.06, "white")                      # screen
    c.add(0.1, 0.1, 0.06, 1.0, h - 0.1, 0.07, "@curtain")                       # curtains drawn back
    c.add(w - 1.0, 0.1, 0.06, w - 0.1, h - 0.1, 0.07, "@curtain")
    c.add(0.0, h - 0.2, 0.05, w, h, 0.12, "@curtain")                           # valance
    return c.boxes


def ticket_booth():
    w, h, d = 1.7, 2.35, 1.2
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 1.0, d, "@panel")
    c.add(0.0, 1.0, 0.0, 0.1, 2.1, d, "@panel")
    c.add(w - 0.1, 1.0, 0.0, w, 2.1, d, "@panel")
    c.add(0.0, 1.0, 0.0, w, 2.1, 0.1, "@panel")
    c.add(0.1, 1.0, d - 0.08, w - 0.1, 1.95, d - 0.04, "glass")                 # window
    c.add(0.55, 1.0, d - 0.1, 1.15, 1.06, d, "brass")                           # ticket slot
    c.add(0.0, 2.1, 0.0, w, 2.35, d + 0.0, "red")                               # marquee roof
    for i in range(7):
        c.add(0.08 + i * 0.23, 2.15, d - 0.01, 0.14 + i * 0.23, 2.3, d, "amber")   # bulbs
    c.add(0.3, 0.3, d - 0.01, w - 0.3, 0.7, d, "brass")
    c.add(0.5, 1.0, 0.3, 1.2, 1.12, 0.6, "grey")                                # register inside
    return c.boxes


def concession_counter():
    w, h, d = 2.2, 1.7, 0.8
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.95, d, "red")
    c.add(0.0, 0.95, 0.0, w, 0.99, d, "black")
    c.add(0.05, 0.15, d - 0.01, w - 0.05, 0.8, d, "@panel")
    c.add(0.1, 0.99, 0.1, 0.8, 1.7, 0.6, "red")                                 # popcorn machine
    c.add(0.15, 1.05, 0.58, 0.75, 1.6, 0.61, "glass")
    c.add(0.18, 1.05, 0.15, 0.72, 1.35, 0.55, "yellow")                         # popcorn
    c.add(0.95, 0.99, 0.15, 1.45, 1.45, 0.55, "black")                          # soda fountain
    for i in range(3):
        c.add(1.0 + i * 0.15, 1.15, 0.55, 1.08 + i * 0.15, 1.3, 0.58, ["red", "amber", "green"][i])
    for i in range(4):
        c.add(1.6 + (i % 2) * 0.2, 0.99, 0.2 + (i // 2) * 0.2, 1.75 + (i % 2) * 0.2, 1.2, 0.35 + (i // 2) * 0.2,
              "red" if i % 2 else "white")                                       # popcorn tubs
    return c.boxes


def food_court_table():
    w, h, d = 1.7, 0.78, 1.7
    c = Part(w, h, d)
    c.add(0.75, 0, 0.75, 0.95, 0.72, 0.95, "steel")                             # pedestal
    c.add(0.55, 0, 0.55, 1.15, 0.04, 1.15, "steel")
    c.add(0.45, 0.72, 0.45, 1.25, 0.76, 1.25, "@top")                           # square top
    for x0, z0 in ((0.0, 0.65), (1.3, 0.65), (0.65, 0.0), (0.65, 1.3)):          # four bolted swivel seats
        c.add(x0 + 0.17, 0, z0 + 0.17, x0 + 0.23, 0.44, z0 + 0.23, "steel")
        c.add(x0, 0.44, z0, x0 + 0.4, 0.5, z0 + 0.4, "@seat")
    c.add(0.75, 0.76, 0.75, 0.95, 0.8, 0.95, "white")                           # napkin box
    return c.boxes


def mall_planter():
    w, h, d = 1.3, 2.4, 1.3
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0, w, 0.55, d, "@stone")                                    # tiled box with a ledge seat
    c.add(-0.0, 0.5, -0.0, w, 0.58, d, "concrete")
    c.add(0.08, 0.5, 0.08, w - 0.08, 0.6, d - 0.08, "bark")
    c.add(0.58, 0.6, 0.58, 0.72, 1.6, 0.72, "bark")                             # ficus trunk
    _foliage(c, 0.2, 0.2, 1.1, 1.1, 1.3, 2.4)
    for x0, z0 in ((0.15, 0.15), (0.95, 0.9), (0.2, 1.0)):
        c.add(x0, 0.6, z0, x0 + 0.2, 0.75, z0 + 0.2, "leaf")                    # ground cover
    return c.boxes


def mall_bench():
    w, h, d = 1.8, 0.5, 0.6
    c = Part(w, h, d)
    for x in (0.1, w - 0.2):
        c.add(x, 0, 0.05, x + 0.1, 0.4, d - 0.05, "steel")
    c.add(0.0, 0.4, 0.0, w, 0.5, d, "@wood")
    for i in range(5):
        c.add(0.05 + i * 0.36, 0.495, 0.0, 0.08 + i * 0.36, 0.5, d, "black")   # slat seams
    return c.boxes


_reg("shopShelf", shop_shelf(), (1.2, 1.9, 0.5), {"@frame": ["white", "grey", "steel"], "@sign": ["red", "blue", "green"]})
_reg("shopFridge", shop_fridge(), (1.0, 2.1, 0.75), {"@sign": ["blue", "red"]})
_reg("checkoutCounter", checkout_counter(), (1.8, 1.32, 0.75), {"@wood": ["oak", "white", "walnut"],
                                                              "@panel": ["red", "teal", "grey"],
                                                              "@goods": ["black", "steel"]})
_reg("displayCase", display_case(), (1.4, 1.25, 0.75), {"@wood": ["oak", "white", "black"],
                                                      "@food": ["sand", "pine", "brass"],
                                                      "@topping": ["plum", "dark", "white"]})
_reg("coffeeStation", coffee_station(), (1.3, 1.55, 0.65), {"@wood": ["walnut", "oak"]})
_reg("donutFryer", donut_fryer(), (1.3, 1.25, 0.8))
_reg("bakeryRack", bakery_rack(), (1.0, 1.9, 0.6), {"@food": ["sand", "pine", "plum"]})
_reg("dinerStool", diner_stool(), (0.42, 0.78, 0.42), {"@seat": ["red", "teal", "black"]})
_reg("dinerBooth", diner_booth(), (1.6, 1.15, 1.5), {"@seat": ["red", "teal", "plum"], "@wood": ["white", "oak"]})
_reg("menuBoard", menu_board(), (1.5, 0.9, 0.08), {"@board": ["black", "dark"], "@title": ["plum", "amber", "teal"]})
_reg("donutSign", donut_sign(), (1.3, 1.3, 0.3), {"@icing": ["plum", "red"]})
_reg("washingMachine", washing_machine(), (0.75, 1.15, 0.72), {"@drum": ["glass", "blue", "linen"]})
_reg("dryerStack", dryer_stack(), (0.75, 2.05, 0.72), {"@drum": ["glass", "linen"]})
_reg("flowerStand", flower_stand(), (1.3, 1.2, 0.65), {"@wood": ["pine", "green"]})
_reg("barberChair", barber_chair(), (0.7, 1.25, 0.95), {"@seat": ["red", "black", "teal"]})
_reg("barberStation", barber_station(), (1.2, 1.9, 0.45), {"@wood": ["white", "walnut"]})
_reg("clothesRack", clothes_rack(), (1.4, 1.65, 0.55), {"@cloth": ["red", "teal", "yellow"]})
_reg("tvWall", tv_wall(), (1.6, 1.9, 0.5), {"@screen": ["blue", "green", "plum"]})
_reg("cinemaSeats", cinema_seats(), (2.4, 1.0, 0.8), {"@seat": ["red", "plum"]})
_reg("cinemaScreen", cinema_screen(), (4.2, 2.2, 0.12), {"@curtain": ["red", "plum"]})
_reg("ticketBooth", ticket_booth(), (1.7, 2.35, 1.2), {"@panel": ["plum", "red", "teal"]})
_reg("concessionCounter", concession_counter(), (2.2, 1.7, 0.8), {"@panel": ["yellow", "white"]})
_reg("foodCourtTable", food_court_table(), (1.7, 0.78, 1.7), {"@seat": ["red", "teal", "yellow"], "@top": ["white", "oak"]})
_reg("mallPlanter", mall_planter(), (1.3, 2.4, 1.3), {"@stone": ["concrete", "tile", "stone"]})
_reg("mallBench", mall_bench(), (1.8, 0.5, 0.6), {"@wood": ["oak", "walnut"]})
