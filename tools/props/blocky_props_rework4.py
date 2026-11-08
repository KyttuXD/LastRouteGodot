"""Props rework 4: room-purpose catalog widening (docs/HIDING_PROPS.md). Infirmary (hospital bed, IV stand, medical cart),
library (reading table, globe), storage (barrel, steel shelving), lobby (reception desk, potted plant) and a standing mirror
for bedrooms. exec'd by build_blocky_props.py after rework3 (Part, VOX, PROPS, VARIANTS, v, TARGET_SIZE, _reg in scope).

Our own designs in metres on the 6.25 cm grid. The thuing/ library was only looked at for proportions; nothing was copied.
Same layering rule as rework 3: bodies stop short of the front, fronts and handles are the next layers.
"""


def hospital_bed():
    w, h, d = 1.0, 1.0, 2.12
    c = Part(w, h, d)
    for x in (0.06, w - 0.125):
        for z in (0.06, d - 0.125):
            c.add(x, 0, z, x + VOX, 0.12, z + VOX, "black")                       # casters
            c.add(x, 0.12, z, x + VOX, 0.44, z + VOX, "steel")                    # legs
    c.add(0.06, 0.44, 0.06, w - 0.06, 0.5, d - 0.06, "steel")                     # frame
    c.add(0.0625, 0.5, 0.125, w - 0.0625, 0.62, d - 0.125, "white")                # mattress
    c.add(0.125, 0.62, 0.125, w - 0.125, 0.69, 0.5, "linen")                     # pillow
    c.add(0.0625, 0.62, 0.625, w - 0.0625, 0.66, d - 0.125, "teal")               # blanket
    c.add(0.06, 0.5, 0, w - 0.06, h, 0.0625, "steel")                             # head board (against the wall)
    c.add(0.06, 0.5, d - 0.0625, w - 0.06, 0.875, d, "steel")                     # foot board
    for x in (0, w - 0.0625):
        c.add(x, 0.62, 0.5, x + 0.0625, 0.75, 1.5, "grey")                        # side rails
    c.add(0.375, 0.75, d - 0.0625, 0.625, 0.8125, d, "screen")                    # chart clip
    return c.boxes


def iv_stand():
    w, h, d = 0.5, 1.9, 0.5
    c = Part(w, h, d)
    c.add(0.0, 0, 0.1875, w, 0.0625, 0.3125, "black")
    c.add(0.1875, 0, 0.0, 0.3125, 0.0625, w, "black")
    c.add(0.21875, 0.0625, 0.21875, 0.28125, 1.75, 0.28125, "steel")             # pole
    c.add(0.0625, 1.75, 0.21875, 0.4375, 1.8125, 0.28125, "steel")               # hook bar
    c.add(0.0625, 1.375, 0.1875, 0.1875, 1.6875, 0.3125, "glass")                # drip bag
    c.add(0.3125, 1.4375, 0.1875, 0.4375, 1.6875, 0.3125, "water")
    return c.boxes


def medical_cart():
    w, h, d = 0.75, 1.0, 0.5
    c = Part(w, h, d)
    for x in (0.03, w - 0.0925):
        for z in (0.03, d - 0.0925):
            c.add(x, 0, z, x + VOX, 0.0625, z + VOX, "black")
    c.add(0.03, 0.0625, 0.03, w - 0.03, h - VOX, d - 0.125, "white")              # body
    c.add(0, h - VOX, 0, w, h, d, "steel")                                        # top
    for r in range(3):                                                            # drawers
        y0 = 0.125 + r * 0.25
        c.add(0.0625, y0, d - 0.125, w - 0.0625, y0 + 0.1875, d - 0.0625, ["red", "blue", "yellow"][r])
        c.add(w / 2 - 0.0625, y0 + 0.0625, d - 0.0625, w / 2 + 0.0625, y0 + 0.125, d, "steel")
    return c.boxes


def reading_table():
    w, h, d = 1.5, 0.75, 0.88
    c = Part(w, h, d)
    for x in (0.06, w - 0.125):
        for z in (0.06, d - 0.125):
            c.add(x, 0, z, x + VOX, h - 0.0625, z + VOX, "@wood")
    c.add(0.06, 0.5, 0.06, w - 0.06, h - 0.0625, 0.125, "@wood")                 # apron
    c.add(0, h - 0.0625, 0, w, h, d, "@wood")                                     # top
    return c.boxes


def library_globe():
    w, h, d = 0.62, 1.06, 0.62
    c = Part(w, h, d)
    c.add(0.0625, 0, 0.0625, w - 0.0625, 0.0625, d - 0.0625, "@wood")             # foot
    c.add(0.25, 0.0625, 0.25, 0.375, 0.5, 0.375, "@wood")                         # stem
    c.add(0.0, 0.5, 0.25, w, 0.5625, 0.375, "brass")                              # meridian ring base
    c.add(0.125, 0.5625, 0.125, w - 0.125, 0.9375, d - 0.125, "blue")             # globe
    c.add(0.1875, 0.6875, 0.1875, 0.3125, 0.8125, d - 0.125, "green")             # continents (proud of the sphere front)
    c.add(0.3125, 0.625, 0.1875, 0.4375, 0.75, d - 0.125, "sand")
    c.add(0.25, 0.9375, 0.25, 0.375, 1.0, 0.375, "brass")                         # axis cap
    return c.boxes


def storage_barrel():
    w, h, d = 0.62, 0.94, 0.62
    c = Part(w, h, d)
    c.add(0.0625, 0, 0.0625, w - 0.0625, h, d - 0.0625, "@wood")                  # staves
    c.add(0.0, 0.0625, 0.125, 0.0625, h - 0.0625, d - 0.125, "@wood")             # belly
    c.add(w - 0.0625, 0.0625, 0.125, w, h - 0.0625, d - 0.125, "@wood")
    c.add(0.125, 0.0625, 0.0, w - 0.125, h - 0.0625, 0.0625, "@wood")
    c.add(0.125, 0.0625, d - 0.0625, w - 0.125, h - 0.0625, d, "@wood")
    for y in (0.1875, h - 0.25):                                                  # hoops sit proud of the belly
        c.add(0.0, y, 0.0625, w, y + 0.0625, 0.125, "black")
        c.add(0.0, y, d - 0.125, w, y + 0.0625, d - 0.0625, "black")
    return c.boxes


def storage_shelving():
    w, h, d = 1.25, 1.94, 0.5
    c = Part(w, h, d)
    for x in (0.0, w - VOX):
        for z in (0.0, d - VOX):
            c.add(x, 0, z, x + VOX, h, z + VOX, "steel")
    for i, y in enumerate((0.0625, 0.5625, 1.0625, 1.5625)):
        c.add(VOX, y, 0.0, w - VOX, y + 0.0625, d, "grey")
        # stock on each shelf: boxes and tins in different spots
        x0 = 0.125 + (i % 2) * 0.375
        c.add(x0, y + 0.0625, 0.0625, x0 + 0.375, y + 0.375, 0.375, ["paper", "oak", "rust", "paper"][i])
        c.add(x0 + 0.5, y + 0.0625, 0.125, x0 + 0.6875, y + 0.25, 0.3125, ["red", "blue", "steel", "green"][i])
    return c.boxes


def reception_desk():
    w, h, d = 2.0, 1.12, 0.88
    c = Part(w, h, d)
    c.add(0.0625, 0, 0.0625, w - 0.0625, 0.75, 0.6875, "@wood")                   # work surface body
    c.add(0, 0.75, 0, w, 0.8125, 0.6875, "dark")                                  # work top
    c.add(0, 0, 0.6875, w, 1.0625, d - 0.0625, "@wood")                           # front counter wall
    c.add(0, 1.0625, 0.625, w, h, d, "dark")                                      # transaction ledge
    c.add(0.25, 0.25, d - 0.0625, w - 0.25, 0.8125, d, "brass")                   # name plaque band
    c.add(0.375, 0.8125, 0.125, 0.875, 1.0, 0.1875, "black")                      # monitor
    c.add(0.4375, 0.8125, 0.1875, 0.8125, 0.875, 0.5, "black")                    # keyboard
    c.add(1.375, 0.8125, 0.1875, 1.5625, 0.9375, 0.375, "red")                    # phone
    return c.boxes


def potted_plant():
    w, h, d = 0.5, 1.25, 0.5
    c = Part(w, h, d)
    c.add(0.0625, 0, 0.0625, w - 0.0625, 0.375, d - 0.0625, "@pot")
    c.add(0.0, 0.3125, 0.0, w, 0.4375, d, "@pot")                                 # rim
    c.add(0.0625, 0.4375, 0.0625, w - 0.0625, 0.5, d - 0.0625, "bark")            # soil
    c.add(0.1875, 0.5, 0.1875, 0.3125, 0.75, 0.3125, "bark")                      # trunk
    c.add(0.0625, 0.75, 0.0625, w - 0.0625, 1.0625, d - 0.0625, "leaf")
    c.add(0.125, 1.0625, 0.125, w - 0.125, h, d - 0.125, "leaf")
    c.add(0.0, 0.8125, 0.1875, 0.0625, 1.0, 0.3125, "green")                      # stray leaves
    c.add(w - 0.0625, 0.875, 0.1875, w, 1.0625, 0.3125, "green")
    return c.boxes


def standing_mirror():
    w, h, d = 0.62, 1.75, 0.44
    c = Part(w, h, d)
    c.add(0.0, 0, 0.0625, 0.0625, 0.0625, d - 0.0625, "@wood")                    # splayed feet
    c.add(w - 0.0625, 0, 0.0625, w, 0.0625, d - 0.0625, "@wood")
    c.add(0.0, 0.0625, 0.1875, 0.0625, 1.5, 0.25, "@wood")                        # posts
    c.add(w - 0.0625, 0.0625, 0.1875, w, 1.5, 0.25, "@wood")
    c.add(0.0625, 0.25, 0.1875, w - 0.0625, h, 0.25, "@wood")                     # frame back
    c.add(0.125, 0.3125, 0.25, w - 0.125, h - 0.0625, 0.3125, "mirror")           # glass, proud of the frame
    return c.boxes


# hospitalBed comes from blocky_props_regions.py; the infirmary uses that one.
_reg("ivStand", iv_stand(), (0.5, 1.9, 0.5))
_reg("medicalCart", medical_cart(), (0.75, 1.0, 0.5))
_reg("readingTable", reading_table(), (1.5, 0.75, 0.88), {"@wood": ["walnut", "oak", "mahogany"]})
_reg("libraryGlobe", library_globe(), (0.62, 1.06, 0.62), {"@wood": ["walnut", "mahogany"]})
_reg("storageBarrel", storage_barrel(), (0.62, 0.94, 0.62), {"@wood": ["oak", "dark", "pine"]})
_reg("storageShelving", storage_shelving(), (1.25, 1.94, 0.5))
_reg("receptionDesk", reception_desk(), (2.0, 1.12, 0.88), {"@wood": ["oak", "walnut", "ash"]})
_reg("pottedPlant", potted_plant(), (0.5, 1.25, 0.5), {"@pot": ["rust", "white", "black"]})
_reg("standingMirror", standing_mirror(), (0.62, 1.75, 0.44), {"@wood": ["oak", "walnut", "mahogany"]})

NEW_ROOM_PROPS = ["ivStand", "medicalCart", "readingTable", "libraryGlobe", "storageBarrel",
                  "storageShelving", "receptionDesk", "pottedPlant", "standingMirror"]
