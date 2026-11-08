"""Mansion finishes: luxurious looks of the ordinary furniture, built as "<type>Mansion" model sets
with exactly the base type's shape and footprint, so the game keeps one type name (sizes, colliders, surfaces, hiding spots
and room rules unchanged) and only the mansion region picks these models (PropModelCatalog.REGION_FINISHES).
exec'd by build_blocky_props.py after SIZE_SCALE (PROPS, VARIANTS, BOUNDS, TARGET_SIZE, SIZE_SCALE, Part, VOX, _reg in scope).

The look: lacquered or painted bodies (white, black, cream) instead of brown wood, marble tops (porcelain/tile tiles),
velvet upholstery (deep red, emerald, navy), gilt trims and pulls (brass), crystal chandeliers (mirror + glass), ornate
rugs. Matte like everything else; no new atlas tiles. Two new mansion pieces: a marble column and a porcelain vase.
"""

WOODS = ("oak", "dark", "walnut", "pine", "ash", "mahogany", "bark")
FABRICS = ("red", "plum", "green", "teal", "linen", "grey", "paper")

# three finishes per piece: (lacquer, velvet, marble)
FINISHES = [("white", "red", "porcelain"), ("black", "green", "tile"), ("linen", "blue", "porcelain")]

# pieces whose topmost full-footprint slab becomes marble
TOPPED = {"woodenTable", "diningTable", "normalCoffeeTable", "diningSideboard", "woodenDresserSideboard", "bedroomDresser",
          "bedroomNightstand", "mansionConsoleTable", "normalTvConsole", "bedroomVanity", "bathroomVanity",
          "gothicPedestalTable", "mansionTeaCart"}
# upholstered pieces: wood frames go gilt/lacquer, every fabric goes velvet
UPHOLSTERED = {"loungeCouch", "loungeCouchWide", "woodenChairCushion", "diningChairCushion", "diningChair", "woodenChair",
               "vanityStool", "bedroomBench", "mansionChaiseLounge"}
BEDS = {"singleBed", "doubleBed"}
CABINETS = {"bedroomWardrobe", "mansionBookshelf", "normalBookcase", "mansionDisplayCabinet"}
RUGS = {"mansionAreaRug", "bedroomRug"}

MANSION_TYPES = sorted(TOPPED | UPHOLSTERED | BEDS | CABINETS | RUGS | {"diningChandelier", "floorLamp", "tableLamp"})


def _resolve(kind, subs):
    if isinstance(kind, str) and kind.startswith("@"):
        options = subs.get(kind)
        if options:
            return options[0]
    return kind


def _mansion_boxes(name, boxes, subs, finish):
    lacquer, velvet, marble = finish
    out = []
    top_y = max(b[4] for b in boxes)
    for b in boxes:
        kind = _resolve(b[6], subs)
        area = (b[3] - b[0]) * (b[5] - b[2])
        new = kind
        if name in RUGS:
            new = {"dark": "red" if velvet != "red" else "plum", "brass": "brass"}.get(kind, velvet)
        elif name == "diningChandelier":
            new = {"amber": "mirror", "glass": "mirror"}.get(kind, "brass")
        elif name in ("floorLamp", "tableLamp"):
            new = "brass" if kind in WOODS or kind in ("steel", "black", "dark") else kind
        elif name in BEDS:
            tall_board = (b[5] <= .06 or b[2] >= .94) and (b[4] - b[1]) >= .2
            if tall_board:
                new = velvet                          # upholstered head and foot boards
            elif kind in WOODS:
                new = lacquer
            elif kind == "paper":
                new = "white"                         # linen sheets
            elif kind in FABRICS or b[6] == "@cloth":
                new = velvet
        elif name in UPHOLSTERED:
            if kind in FABRICS or str(b[6]).startswith("@cloth"):
                new = velvet
            elif kind in WOODS:
                new = "brass" if (b[4] - b[1]) < .35 and area < .05 else lacquer   # gilt legs, lacquer frames
        else:
            if name in TOPPED and b[4] >= top_y - 1e-6 and area >= .6:
                new = marble
            elif name in TOPPED and kind in WOODS and area < .05 and (b[4] - b[1]) > .2:
                new = "brass"                         # gilt legs under the marble
            elif kind in WOODS:
                new = lacquer
            elif kind in ("steel",):
                new = "brass"
            elif kind in FABRICS and name in CABINETS:
                new = kind                            # book spines stay
        out.append(tuple([b[0], b[1], b[2], b[3], b[4], b[5], new] + list(b[7:])))
    return out


for _base in MANSION_TYPES:
    if _base not in PROPS:
        continue
    _boxes, _subs = PROPS[_base]
    _key = _base + "Mansion"
    _shapes = [_mansion_boxes(_base, _boxes, _subs, f) for f in FINISHES]
    PROPS[_key] = (_shapes[0], {})
    VARIANTS[_key] = [(s, {}) for s in _shapes[1:]]
    if _base in BOUNDS:
        BOUNDS[_key] = BOUNDS[_base]
    if _base in SIZE_SCALE:
        SIZE_SCALE[_key] = SIZE_SCALE[_base]
    if _base in TARGET_SIZE:
        TARGET_SIZE[_key] = TARGET_SIZE[_base]


def marble_column():
    w, h, d = 0.5, 2.25, 0.5
    c = Part(w, h, d)
    c.add(0, 0, 0, w, 0.125, d, "tile")                                          # plinth
    c.add(0.0625, 0.125, 0.0625, w - 0.0625, 0.1875, d - 0.0625, "brass")         # gilt ring
    c.add(0.125, 0.1875, 0.125, w - 0.125, h - 0.1875, d - 0.125, "porcelain")    # shaft
    for x in (0.0625, w - 0.125):                                                 # flutes, proud of the shaft
        c.add(x, 0.25, 0.1875, x + 0.0625, h - 0.25, d - 0.1875, "tile")
    c.add(0.0625, h - 0.1875, 0.0625, w - 0.0625, h - 0.125, d - 0.0625, "brass")
    c.add(0, h - 0.125, 0, w, h, d, "tile")                                      # capital
    return c.boxes


def porcelain_vase():
    w, h, d = 0.44, 0.94, 0.44
    c = Part(w, h, d)
    c.add(0.125, 0, 0.125, w - 0.125, 0.0625, d - 0.125, "brass")                 # gilt foot
    c.add(0.0625, 0.0625, 0.0625, w - 0.0625, 0.5625, d - 0.0625, "@body")
    c.add(0.0625, 0.25, 0.0, w - 0.0625, 0.375, 0.0625, "blue")                   # painted band, proud of the belly
    c.add(0.0625, 0.25, d - 0.0625, w - 0.0625, 0.375, d, "blue")
    c.add(0.125, 0.5625, 0.125, w - 0.125, 0.8125, d - 0.125, "@body")            # neck
    c.add(0.0625, 0.8125, 0.0625, w - 0.0625, 0.875, d - 0.0625, "brass")         # lip
    c.add(0.1875, 0.875, 0.1875, w - 0.1875, h, d - 0.1875, "green")              # stems
    return c.boxes


_reg("mansionMarbleColumn", marble_column(), (0.5, 2.25, 0.5))
_reg("mansionPorcelainVase", porcelain_vase(), (0.44, 0.94, 0.44), {"@body": ["white", "porcelain", "black"]})
