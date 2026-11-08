"""Kitchen/bath group: 48 base types (+ mansion vanity finishes) redone low-poly.
Exec'd by build_blocky_props.py after SIZE_SCALE and before mansion finishes.
Keep type ids, variant slot counts, TARGET_SIZE / SIZE_SCALE bounds, fronts, colliders, atlas tiles.
Fewer boxes, no fancy bevels, share materials; hidden_faces() via LOWPOLY.
"""

_KITCHEN_078 = [
    "normalKitchenCounter", "luxuryKitchenCounter", "gothicKitchenCounter",
    "normalKitchenIsland", "luxuryKitchenIsland", "gothicKitchenIsland",
    "normalKitchenFridge", "luxuryKitchenFridge", "gothicKitchenFridge",
    "normalKitchenStove", "luxuryKitchenStove", "gothicKitchenStove",
    "normalKitchenSink", "luxuryKitchenSink", "gothicKitchenSink",
    "normalKitchenWallCabinet", "luxuryKitchenWallCabinet", "gothicKitchenWallCabinet",
    "prisonKitchenRack", "prisonServingCounter", "prisonTrayReturn",
    "houseToilet", "publicRestroomToilet", "bathroomSink", "houseBathtub",
    "bathroomStall", "bathroomVanity", "houseBathroomShelf", "houseMedicineCabinet",
    "houseTowelRack", "houseShowerEnclosure", "publicMensShowerStall", "publicWomensShowerStall",
    "publicMensUrinal", "publicSinkBank", "publicBabyChangeStation", "publicHandDryer",
    "publicPaperTowelDispenser", "publicSanitaryBin", "publicSoapDispenser",
    "laundryHamper", "washingMachine", "dryerStack",
    "bedroomVanity", "gothicVanity",
    "coffeeStation", "donutFryer", "shopFridge",
]


def _keep_variants(name, shapes):
    old = [PROPS[name]] + list(VARIANTS.get(name, []))
    assert len(old) == len(shapes), (name, len(old), len(shapes))
    PROPS[name] = (shapes[0], old[0][1])
    VARIANTS[name] = [(s, o[1]) for s, o in zip(shapes[1:], old[1:])]


def _keep_one(name, shapes):
    """Single-variant types (PROPS only, no VARIANTS entries)."""
    assert name in PROPS and not VARIANTS.get(name), (name, VARIANTS.get(name))
    assert len(shapes) == 1, (name, len(shapes))
    PROPS[name] = (shapes[0], PROPS[name][1])


# ---- kitchen counters / islands / cabinets ---------------------------------------------------

def lp_counter(i=0, body="oak", top="stone", accent="dark"):
    """Base + toe-kick + countertop; variant 1 adds sink cut hint / drawers; 2 adds tall backsplash strip."""
    if i == 0:
        return [
            (0.0, 0.06, 0.0, 1.0, 0.82, 1.0, body),
            (0.0, 0.0, 0.0, 1.0, 0.06, 0.92, accent),
            (0.0, 0.82, 0.0, 1.0, 0.92, 1.0, top),
            (0.04, 0.4, 0.88, 0.96, 0.72, 0.98, accent),
        ]
    if i == 1:
        return [
            (0.0, 0.06, 0.0, 1.0, 0.82, 1.0, body),
            (0.0, 0.0, 0.0, 1.0, 0.06, 0.92, accent),
            (0.0, 0.82, 0.0, 1.0, 0.92, 1.0, top),
            (0.08, 0.35, 0.86, 0.45, 0.7, 0.98, accent),
            (0.55, 0.35, 0.86, 0.92, 0.7, 0.98, accent),
            (0.12, 0.84, 0.15, 0.88, 0.86, 0.55, "steel"),
            (0.02, 0.92, 0.0, 0.98, 1.0, 0.12, body),
        ]
    return [
        (0.0, 0.06, 0.0, 1.0, 0.82, 1.0, body),
        (0.0, 0.0, 0.0, 1.0, 0.06, 0.92, accent),
        (0.0, 0.82, 0.0, 1.0, 0.92, 1.0, top),
        (0.0, 0.92, 0.0, 1.0, 1.0, 0.1, body),
        (0.1, 0.45, 0.88, 0.9, 0.7, 0.98, accent),
        (0.35, 0.84, 0.7, 0.65, 0.9, 0.95, "steel"),
    ]


def lp_island(i=0, body="oak", top="stone", accent="dark"):
    return [
        (0.05, 0.0, 0.05, 0.95, 0.78, 0.95, body),
        (0.0, 0.78, 0.0, 1.0, 0.9, 1.0, top),
        (0.12, 0.3, 0.88, 0.88, 0.65, 0.98, accent),
        (0.2, 0.9, 0.2, 0.8, 1.0, 0.8, top if i else body),
    ]


def lp_wall_cab(i=0, body="oak", door="dark"):
    return [
        (0.0, 0.0, 0.0, 1.0, 1.0, 0.85, body),
        (0.04, 0.08, 0.85, 0.48, 0.92, 0.98, door),
        (0.52, 0.08, 0.85, 0.96, 0.92, 0.98, door),
        (0.4, 0.42, 0.98, 0.46, 0.58, 1.0, "brass"),
        (0.54, 0.42, 0.98, 0.6, 0.58, 1.0, "brass"),
    ]


# ---- appliances ------------------------------------------------------------------------------

def lp_fridge(body="porcelain", door="steel", accent="black"):
    return [
        (0.0, 0.04, 0.0, 1.0, 1.0, 0.84, body),
        (0.0, 0.0, 0.06, 1.0, 0.04, 0.92, accent),
        (0.06, 0.08, 0.84, 0.94, 0.4, 0.94, door),
        (0.06, 0.42, 0.84, 0.94, 0.96, 0.94, door),
        (0.06, 0.4, 0.84, 0.94, 0.42, 0.94, accent),
        (0.78, 0.16, 0.94, 0.86, 0.34, 1.0, accent),
        (0.78, 0.5, 0.94, 0.86, 0.74, 1.0, accent),
    ]


def lp_stove(body="porcelain", face="steel"):
    """Body + cooktop + one oven door + 4 burner pads (was denser knobs/legs)."""
    return [
        (0.0, 0.0, 0.0, 1.0, 0.78, 0.92, body),
        (0.0, 0.78, 0.0, 1.0, 0.88, 1.0, face),
        (0.08, 0.12, 0.88, 0.92, 0.62, 0.98, "black"),
        (0.08, 0.64, 0.88, 0.92, 0.72, 0.96, "glass"),
        (0.12, 0.88, 0.12, 0.4, 0.92, 0.4, "rust"),
        (0.6, 0.88, 0.12, 0.88, 0.92, 0.4, "rust"),
        (0.12, 0.88, 0.55, 0.4, 0.92, 0.85, "rust"),
        (0.6, 0.88, 0.55, 0.88, 0.92, 0.85, "rust"),
        (0.05, 0.88, 0.05, 0.95, 1.0, 0.18, face),
    ]


def lp_sink(body="porcelain", top="stone", basin="steel", door="oak", tap="steel"):
    """Unit 0..1 matching staging silhouette (faucet tip at y=1); merged cabinet doors."""
    return [
        (0.0, 0.054, 0.0, 1.0, 0.714, 0.819, body),          # merged cabinet body
        (0.0, 0.0, 0.087, 1.0, 0.054, 0.913, "black"),
        (0.0, 0.714, 0.0, 1.0, 0.821, 0.174, top),            # top front strip
        (0.0, 0.714, 0.739, 1.0, 0.821, 1.0, top),            # top back
        (0.0, 0.714, 0.174, 0.28, 0.821, 0.739, top),
        (0.72, 0.714, 0.174, 1.0, 0.821, 0.739, top),
        (0.28, 0.714, 0.174, 0.72, 0.77, 0.739, basin),       # basin
        (0.475, 0.821, 0.087, 0.525, 1.0, 0.435, tap),        # faucet stem+spout merged
        (0.048, 0.089, 0.819, 0.952, 0.679, 0.909, door),     # merged front doors
        (0.34, 0.491, 0.909, 0.388, 0.598, 1.0, tap),
        (0.605, 0.491, 0.909, 0.653, 0.598, 1.0, tap),
    ]


def lp_prison_rack(frame="steel", bin_m="concrete"):
    return [
        (0, 0, 0, 0.06, 1, 0.06, frame),
        (0.94, 0, 0, 1, 1, 0.06, frame),
        (0, 0, 0.94, 0.06, 1, 1, frame),
        (0.94, 0, 0.94, 1, 1, 1, frame),
        (0.04, 0.2, 0.04, 0.96, 0.25, 0.96, frame),
        (0.04, 0.5, 0.04, 0.96, 0.55, 0.96, frame),
        (0.04, 0.8, 0.04, 0.96, 0.85, 0.96, frame),
        (0.2, 0.25, 0.3, 0.9, 0.4, 0.7, bin_m),             # merged bins row lower
    ]


def lp_prison_serve(body="concrete", top="steel", tray="porcelain"):
    """Keep max y=0.86 like staging (scale_fit counter_with_top)."""
    return [
        (0, 0, 0, 1, 0.45, 1, body),
        (0, 0.45, 0, 1, 0.56, 1, top),                       # merged steel shelves
        (0.1, 0.56, 0.2, 0.9, 0.7, 0.6, tray),
        (0, 0.8, 0, 1, 0.86, 0.3, top),
        (0.04, 0.5, 0, 0.1, 0.8, 0.1, top),
        (0.9, 0.5, 0, 0.96, 0.8, 0.1, top),
    ]


def lp_prison_tray(frame="steel", shelf="concrete"):
    return [
        (0.0, 0.0, 0.0, 1.0, 0.9, 0.2, frame),
        (0.0, 0.0, 0.8, 1.0, 0.9, 1.0, frame),
        (0.05, 0.35, 0.2, 0.95, 0.42, 0.8, frame),
        (0.1, 0.42, 0.25, 0.9, 0.55, 0.75, shelf),
    ]


def lp_toilet(i=0):
    return [
        (0.1, 0.0, 0.15, 0.9, 0.42, 0.95, "porcelain"),
        (0.05, 0.42, 0.05, 0.95, 0.55, 0.85, "porcelain"),
        (0.15, 0.55, 0.0, 0.85, 0.92, 0.35, "porcelain"),
        (0.2, 0.55, 0.35, 0.8, 0.62, 0.75, "white"),
        (0.4, 0.92, 0.08, 0.6, 0.98, 0.22, "steel"),
        (0.35, 0.35, 0.9, 0.65, 0.45, 1.0, "steel" if i != 2 else "porcelain"),
    ]


def lp_bath_sink(body="porcelain", rim="white"):
    """Full unit width/depth like staging (pedestal + basin rim)."""
    return [
        (0.323, 0.0, 0.263, 0.677, 0.7, 0.737, body),
        (0.161, 0.0, 0.158, 0.839, 0.06, 0.842, body),
        (0.0, 0.7, 0.0, 1.0, 0.76, 1.0, body),
        (0.0, 0.76, 0.0, 1.0, 0.88, 0.164, rim),
        (0.0, 0.76, 0.836, 1.0, 0.88, 1.0, rim),
        (0.0, 0.76, 0.164, 0.101, 0.88, 0.836, rim),
        (0.899, 0.76, 0.164, 1.0, 0.88, 0.836, rim),
        (0.101, 0.76, 0.164, 0.899, 0.82, 0.836, "water"),
        (0.45, 0.88, 0.0, 0.55, 1.0, 0.474, "steel"),       # faucet merged
    ]


def lp_bathtub(i=0):
    return [
        (0.0, 0.0, 0.0, 1.0, 0.55, 1.0, "porcelain"),
        (0.06, 0.08, 0.08, 0.94, 0.48, 0.92, "water"),
        (0.0, 0.55, 0.0, 1.0, 0.7, 0.12, "porcelain"),
        (0.0, 0.55, 0.88, 1.0, 0.7, 1.0, "porcelain"),
        (0.0, 0.55, 0.12, 0.08, 0.7, 0.88, "porcelain"),
        (0.92, 0.55, 0.12, 1.0, 0.7, 0.88, "porcelain"),
        (0.75, 0.7, 0.35, 0.9, 0.95, 0.55, "steel"),
        (0.7, 0.95, 0.3, 0.95, 1.0, 0.6, "brass" if i else "steel"),
    ]


def lp_stall(i=0):
    return [
        (0.0, 0.0, 0.0, 0.08, 1.0, 1.0, "concrete"),
        (0.92, 0.0, 0.0, 1.0, 1.0, 1.0, "concrete"),
        (0.08, 0.0, 0.0, 0.92, 1.0, 0.08, "concrete"),
        (0.08, 0.85, 0.08, 0.92, 1.0, 0.2, "steel"),
        (0.4, 0.35, 0.9, 0.6, 0.7, 1.0, "black" if i else "steel"),
    ]


def lp_bath_vanity(i=0):
    return [
        (0.0, 0.0, 0.1, 1.0, 0.72, 1.0, "oak"),
        (0.0, 0.72, 0.05, 1.0, 0.82, 1.0, "porcelain"),
        (0.15, 0.65, 0.25, 0.85, 0.75, 0.85, "white"),
        (0.2, 0.58, 0.3, 0.8, 0.68, 0.8, "porcelain"),
        (0.1, 0.25, 0.92, 0.9, 0.6, 1.0, "dark"),
        (0.15, 0.82, 0.7, 0.85, 1.0, 0.95, "mirror"),
        (0.4, 0.82, 0.45, 0.6, 0.95, 0.55, "steel"),
    ]


def lp_bath_shelf(i=0):
    return [
        (0.0, 0.0, 0.6, 1.0, 0.08, 1.0, "oak"),
        (0.0, 0.45, 0.6, 1.0, 0.53, 1.0, "oak"),
        (0.0, 0.9, 0.6, 1.0, 0.98, 1.0, "oak"),
    ]


def lp_med_cab(i=0):
    return [
        (0.05, 0.05, 0.0, 0.95, 0.95, 0.7, "porcelain"),
        (0.1, 0.1, 0.7, 0.9, 0.9, 0.95, "mirror"),
        (0.4, 0.4, 0.95, 0.6, 0.55, 1.0, "steel"),
    ]


def lp_towel_rack():
    """Staging wall rack: cloth hangs low so overall height ~0.5 m in bounds."""
    return [
        (0, 0.7, 0, 0.1, 1, 0.3, "steel"),
        (0.9, 0.7, 0, 1, 1, 0.3, "steel"),
        (0, 0.8, 0.3, 1, 0.9, 0.5, "steel"),
        (0.1, 0.1, 0.3, 0.9, 0.8, 0.8, "@cloth"),
    ]


def lp_shower():
    return [
        (0.0, 0.0, 0.0, 1.0, 0.08, 1.0, "porcelain"),
        (0.0, 0.08, 0.0, 0.08, 1.0, 1.0, "steel"),
        (0.92, 0.08, 0.0, 1.0, 1.0, 1.0, "steel"),
        (0.08, 0.08, 0.0, 0.92, 1.0, 0.08, "steel"),
        (0.08, 0.15, 0.08, 0.92, 0.95, 0.12, "glass"),
        (0.7, 0.7, 0.85, 0.9, 0.95, 1.0, "steel"),
    ]


def lp_urinal():
    return [
        (0.15, 0.2, 0.2, 0.85, 0.85, 0.8, "porcelain"),
        (0.25, 0.25, 0.0, 0.75, 0.7, 0.35, "porcelain"),
        (0.4, 0.85, 0.35, 0.6, 1.0, 0.55, "steel"),
    ]


def lp_sink_bank(body="porcelain", stand="steel"):
    """Three basins + mirror; full footprint like staging."""
    return [
        (0, 0.5, 0.1, 1, 0.6, 1, body),
        (0.1, 0.4, 0.3, 0.3, 0.5, 0.9, "white"),
        (0.4, 0.4, 0.3, 0.6, 0.5, 0.9, "white"),
        (0.7, 0.4, 0.3, 0.9, 0.5, 0.9, "white"),
        (0, 0.6, 0, 1, 1, 0.08, "mirror"),
        (0.1, 0, 0.3, 0.9, 0.5, 0.8, stand),
    ]


def lp_baby_change():
    return [
        (0.0, 0.55, 0.0, 1.0, 0.7, 1.0, "porcelain"),
        (0.05, 0.7, 0.05, 0.95, 0.85, 0.95, "@cloth"),
        (0.1, 0.3, 0.85, 0.9, 0.55, 1.0, "steel"),
    ]


def lp_hand_dryer():
    return [(0.1, 0.2, 0.0, 0.9, 0.9, 0.7, "steel"), (0.25, 0.0, 0.2, 0.75, 0.25, 0.8, "black")]


def lp_paper_towel():
    return [
        (0.1, 0.1, 0.0, 0.9, 0.9, 0.75, "steel"),
        (0.2, 0.2, 0.75, 0.8, 0.8, 0.95, "white"),
        (0.35, 0.0, 0.3, 0.65, 0.15, 0.7, "black"),
    ]


def lp_sanitary_bin():
    return [(0.15, 0.0, 0.15, 0.85, 0.85, 0.85, "black"), (0.2, 0.85, 0.2, 0.8, 1.0, 0.8, "white")]


def lp_soap():
    return [
        (0.2, 0.2, 0.0, 0.8, 0.85, 0.7, "white"),
        (0.3, 0.85, 0.15, 0.7, 1.0, 0.55, "steel"),
        (0.35, 0.0, 0.25, 0.65, 0.2, 0.55, "steel"),
    ]


def lp_hamper():
    return [
        (0.05, 0.0, 0.05, 0.95, 0.08, 0.95, "oak"),
        (0.08, 0.08, 0.08, 0.92, 0.85, 0.92, "oak"),
        (0.15, 0.15, 0.15, 0.85, 0.8, 0.85, "@cloth"),
    ]


def lp_washer():
    return [
        (0.0, 0.0, 0.0, 1.0, 0.92, 0.95, "white"),
        (0.15, 0.25, 0.85, 0.85, 0.8, 1.0, "@drum"),
        (0.2, 0.3, 0.9, 0.8, 0.75, 0.98, "grey"),
        (0.1, 0.92, 0.1, 0.9, 1.0, 0.9, "steel"),
        (0.65, 0.94, 0.3, 0.85, 0.98, 0.55, "screen"),
        (0.15, 0.94, 0.3, 0.4, 0.98, 0.55, "steel"),
    ]


def lp_dryer_stack():
    return [
        (0.0, 0.0, 0.0, 1.0, 0.48, 0.95, "white"),
        (0.0, 0.5, 0.0, 1.0, 0.98, 0.95, "white"),
        (0.15, 0.12, 0.85, 0.85, 0.4, 1.0, "@drum"),
        (0.15, 0.6, 0.85, 0.85, 0.88, 1.0, "@drum"),
        (0.1, 0.48, 0.1, 0.9, 0.52, 0.9, "steel"),
        (0.65, 0.42, 0.3, 0.85, 0.46, 0.55, "screen"),
        (0.65, 0.9, 0.3, 0.85, 0.94, 0.55, "screen"),
    ]


def lp_bed_vanity(i=0, body="oak"):
    return [
        (0.0, 0.0, 0.15, 1.0, 0.7, 1.0, body),
        (0.0, 0.7, 0.1, 1.0, 0.8, 1.0, body),
        (0.1, 0.25, 0.92, 0.9, 0.6, 1.0, "dark"),
        (0.15, 0.8, 0.65, 0.85, 1.0, 0.95, "mirror"),
        (0.05, 0.8, 0.7, 0.12, 1.0, 0.9, "dark"),
        (0.88, 0.8, 0.7, 0.95, 1.0, 0.9, "dark"),
        (0.2, 0.45, 0.95, 0.8, 0.55, 1.0, "dark"),
    ]


def lp_coffee():
    return [
        (0.0, 0.0, 0.0, 1.0, 0.75, 0.9, "@wood"),
        (0.0, 0.75, 0.0, 1.0, 0.85, 1.0, "steel"),
        (0.1, 0.85, 0.2, 0.45, 1.0, 0.7, "black"),
        (0.15, 0.9, 0.25, 0.4, 0.98, 0.55, "glass"),
        (0.55, 0.85, 0.25, 0.9, 1.0, 0.65, "white"),
        (0.6, 0.92, 0.35, 0.85, 0.98, 0.55, "screen"),
        (0.1, 0.3, 0.88, 0.9, 0.65, 0.98, "@wood"),
    ]


def lp_donut():
    return [
        (0.0, 0.0, 0.0, 1.0, 0.7, 0.95, "steel"),
        (0.05, 0.7, 0.05, 0.95, 0.85, 0.95, "black"),
        (0.15, 0.5, 0.15, 0.85, 0.72, 0.85, "amber"),
        (0.2, 0.85, 0.2, 0.8, 0.95, 0.75, "steel"),
        (0.1, 0.95, 0.3, 0.9, 1.0, 0.7, "red"),
        (0.25, 0.72, 0.25, 0.4, 0.8, 0.45, "sand"),
        (0.6, 0.72, 0.25, 0.75, 0.8, 0.45, "sand"),
    ]


def lp_shop_fridge():
    """Was 49 boxes of product rows — one case body, glass door, 3 shelf slabs, sign strip."""
    return [
        (0.0, 0.0, 0.0, 1.0, 1.0, 0.85, "steel"),
        (0.05, 0.05, 0.85, 0.95, 0.95, 0.98, "glass"),
        (0.08, 0.25, 0.1, 0.92, 0.32, 0.8, "white"),
        (0.08, 0.5, 0.1, 0.92, 0.57, 0.8, "white"),
        (0.08, 0.75, 0.1, 0.92, 0.82, 0.8, "white"),
        (0.1, 0.32, 0.2, 0.35, 0.48, 0.55, "red"),
        (0.4, 0.32, 0.2, 0.65, 0.48, 0.55, "blue"),
        (0.7, 0.32, 0.2, 0.9, 0.48, 0.55, "green"),
        (0.1, 0.57, 0.2, 0.45, 0.72, 0.55, "amber"),
        (0.55, 0.57, 0.2, 0.9, 0.72, 0.55, "black"),
        (0.05, 0.95, 0.05, 0.95, 1.0, 0.9, "@sign"),
        (0.85, 0.35, 0.98, 0.95, 0.7, 1.0, "black"),
    ]


# ---- apply -----------------------------------------------------------------------------------

_keep_variants("normalKitchenCounter", [lp_counter(0), lp_counter(1), lp_counter(2)])
_keep_variants("luxuryKitchenCounter", [lp_counter(0, "oak", "stone", "dark"), lp_counter(1, "oak", "stone", "dark"), lp_counter(2, "oak", "stone", "dark")])
_keep_variants("gothicKitchenCounter", [lp_counter(0, "dark", "stone", "dark"), lp_counter(1, "dark", "stone", "dark"), lp_counter(2, "dark", "stone", "dark")])

_keep_variants("normalKitchenIsland", [lp_island(0), lp_island(1), lp_island(2)])
_keep_variants("luxuryKitchenIsland", [lp_island(0), lp_island(1), lp_island(2)])
_keep_variants("gothicKitchenIsland", [lp_island(0, "dark", "stone", "dark"), lp_island(1, "dark", "stone", "dark"), lp_island(2, "dark", "stone", "dark")])

_keep_variants("normalKitchenFridge", [lp_fridge(), lp_fridge("linen", "black", "black"), lp_fridge("grey", "steel", "black")])
_keep_variants("luxuryKitchenFridge", [lp_fridge("steel", "black", "black"), lp_fridge("steel", "steel", "black"), lp_fridge("grey", "black", "black")])
_keep_variants("gothicKitchenFridge", [lp_fridge("dark", "brass", "black"), lp_fridge("dark", "dark", "black"), lp_fridge("dark", "brass", "black")])

_keep_variants("normalKitchenStove", [lp_stove(), lp_stove("porcelain", "black"), lp_stove("steel", "steel")])
_keep_variants("luxuryKitchenStove", [lp_stove("steel", "steel"), lp_stove("steel", "black"), lp_stove("black", "steel")])
_keep_variants("gothicKitchenStove", [lp_stove("dark", "brass"), lp_stove("dark", "black"), lp_stove("dark", "brass")])

_keep_variants("normalKitchenSink", [lp_sink("porcelain","stone","steel","oak","steel"), lp_sink("linen","stone","black","oak","black"), lp_sink("grey","stone","steel","walnut","steel")])
_keep_variants("luxuryKitchenSink", [lp_sink("black","stone","steel","stone","steel"), lp_sink("grey","ash","steel","ash","steel"), lp_sink("teal","stone","brass","stone","brass")])
_keep_variants("gothicKitchenSink", [lp_sink("dark","stone","steel","dark","brass"), lp_sink("mahogany","stone","steel","mahogany","brass"), lp_sink("walnut","stone","steel","walnut","steel")])

_keep_variants("normalKitchenWallCabinet", [lp_wall_cab(), lp_wall_cab(1), lp_wall_cab(2)])
_keep_variants("luxuryKitchenWallCabinet", [lp_wall_cab(0, "oak", "dark"), lp_wall_cab(1, "oak", "dark"), lp_wall_cab(2, "oak", "dark")])
_keep_variants("gothicKitchenWallCabinet", [lp_wall_cab(0, "dark", "dark"), lp_wall_cab(1, "dark", "dark"), lp_wall_cab(2, "dark", "dark")])

_keep_variants("prisonKitchenRack", [lp_prison_rack("steel","concrete"), lp_prison_rack("grey","stone"), lp_prison_rack("black","grey")])
_keep_variants("prisonServingCounter", [lp_prison_serve("concrete","steel","porcelain"), lp_prison_serve("stone","grey","tile"), lp_prison_serve("grey","black","linen")])
_keep_variants("prisonTrayReturn", [lp_prison_tray(), lp_prison_tray("steel","steel"), lp_prison_tray("steel","concrete")])

_keep_variants("houseToilet", [lp_toilet(0), lp_toilet(1), lp_toilet(2)])
_keep_variants("publicRestroomToilet", [lp_toilet(0), lp_toilet(1), lp_toilet(2)])
_keep_variants("bathroomSink", [lp_bath_sink("porcelain","white"), lp_bath_sink("tile","white"), lp_bath_sink("linen","paper")])
_keep_variants("houseBathtub", [lp_bathtub(0), lp_bathtub(1), lp_bathtub(2)])
_keep_variants("bathroomStall", [lp_stall(0), lp_stall(1), lp_stall(2)])
_keep_variants("bathroomVanity", [lp_bath_vanity(0), lp_bath_vanity(1), lp_bath_vanity(2)])
_keep_variants("houseBathroomShelf", [lp_bath_shelf(0), lp_bath_shelf(1), lp_bath_shelf(2)])
_keep_variants("houseMedicineCabinet", [lp_med_cab(0), lp_med_cab(1), lp_med_cab(2)])
_keep_one("houseTowelRack", [lp_towel_rack()])
_keep_one("houseShowerEnclosure", [lp_shower()])
_keep_one("publicMensShowerStall", [lp_shower()])
_keep_one("publicWomensShowerStall", [lp_shower()])
_keep_one("publicMensUrinal", [lp_urinal()])
_keep_variants("publicSinkBank", [lp_sink_bank("porcelain","steel"), lp_sink_bank("tile","grey"), lp_sink_bank("linen","black")])
_keep_one("publicBabyChangeStation", [lp_baby_change()])
_keep_one("publicHandDryer", [lp_hand_dryer()])
_keep_one("publicPaperTowelDispenser", [lp_paper_towel()])
_keep_one("publicSanitaryBin", [lp_sanitary_bin()])
_keep_one("publicSoapDispenser", [lp_soap()])
_keep_one("laundryHamper", [lp_hamper()])
_keep_one("washingMachine", [lp_washer()])
_keep_one("dryerStack", [lp_dryer_stack()])
_keep_variants("bedroomVanity", [lp_bed_vanity(0), lp_bed_vanity(1), lp_bed_vanity(2)])
_keep_variants("gothicVanity", [lp_bed_vanity(0, "dark"), lp_bed_vanity(1, "dark"), lp_bed_vanity(2, "dark")])
_keep_one("coffeeStation", [lp_coffee()])
_keep_one("donutFryer", [lp_donut()])
_keep_one("shopFridge", [lp_shop_fridge()])

LOWPOLY.update(_KITCHEN_078)
LOWPOLY.update(n + "Mansion" for n in _KITCHEN_078)
