"""Second batch of blocky props (rugs, frames, bathroom, office, mansion, gothic, prison,
carnival, beach, plants...). exec'd by build_blocky_props.py, so PROPS, CLOTH, WOODS and
legs() are in scope. Boxes are (x0, y0, z0, x1, y1, z1, kind) as fractions of the old
footprint: x left..right, y bottom..top, z back..front (front = +z)."""


def ring(x0, z0, x1, z1, t, kind, y0=0, y1=1):
    """Four non-overlapping strips (no coplanar faces, so no z-fighting on flat props)."""
    return [(x0, y0, z0, x1, y1, z0 + t, kind), (x0, y0, z1 - t, x1, y1, z1, kind),
            (x0, y0, z0 + t, x0 + t, y1, z1 - t, kind), (x1 - t, y0, z0 + t, x1, y1, z1 - t, kind)]


def rug(border="dark", trim="brass", inner=.1):
    boxes = ring(0, 0, 1, 1, .07, border) + ring(.07, .07, .93, .93, .07, trim)
    boxes.append((.14, 0, .14, .86, 1, .86, "@cloth"))
    return boxes


def frame(canvas, rim="brass", back="dark"):
    return [(0, 0, 0, 1, 1, .5, back), (0, 0, .5, 1, .1, 1, rim), (0, .9, .5, 1, 1, 1, rim),
            (0, .1, .5, .1, .9, 1, rim), (.9, .1, .5, 1, .9, 1, rim), (.1, .1, .5, .9, .9, .8, canvas)]


def box_on(parts, base):
    return base + parts


# ---- floor coverings ---------------------------------------------------------------------------
for t in ("apartmentCarpet", "bedroomRug", "gothicBedroomRug", "hotelCarpet", "mansionAreaRug", "corridorCarpet",
          "arcadeCarpetRunner", "arcadeCarpetCircle"):
    PROPS[t] = (rug(), {"@cloth": CLOTH})
PROPS["houseBathMat"] = (ring(0, 0, 1, 1, .1, "white") + [(.1, 0, .1, .9, 1, .9, "@cloth")], {"@cloth": ["blue", "green"]})
PROPS["beachMat"] = ([(0, 0, i / 5, 1, 1, (i + 1) / 5, ["yellow", "white"][i % 2]) for i in range(5)], {})

# ---- frames, clocks, mirrors, drapes ------------------------------------------------------------
for t in ("normalPaintingFrameEmpty", "normalPictureFrameEmpty"):
    PROPS[t] = (frame("@canvas", "oak"), {"@canvas": ["paper", "green", "glass"]})
for t in ("luxuryPaintingFrameEmpty", "luxuryPictureFrameEmpty", "gothicPaintingFrameEmpty", "gothicPictureFrameEmpty"):
    PROPS[t] = (frame("@canvas", "brass"), {"@canvas": ["plum", "black", "stone"]})
PROPS["framedWallPortrait"] = (frame("@canvas", "brass") + [(.3, .52, .8, .7, .84, .86, "paper"), (.2, .12, .8, .8, .5, .86, "dark")],
                               {"@canvas": ["plum", "green"]})
PROPS["bathroomMirror"] = (frame("mirror", "steel"), {})
PROPS["bedroomWallClock"] = ([(.1, 0, 0, .9, 1, .5, "dark"), (.18, .08, .5, .82, .92, .7, "paper"), (.46, .5, .7, .54, .85, .8, "black"),
                              (.46, .46, .7, .72, .54, .8, "black")], {})
PROPS["heavyMansionDrapes"] = ([(0, .96, 0, 1, 1, .5, "brass")] + [(i / 6, 0, .1 + .25 * (i % 2), (i + 1) / 6, .96, .55 + .25 * (i % 2), "@cloth") for i in range(6)],
                               {"@cloth": ["red", "plum"]})
PROPS["privacyCurtain"] = ([(0, .9, .3, 1, 1, .7, "steel")] + [(i / 5, 0, .3 + .12 * (i % 2), (i + 1) / 5, .9, .6 + .12 * (i % 2), "paper") for i in range(5)], {})
PROPS["publicMensRoomSign"] = ([(0, 0, 0, 1, 1, .5, "steel"), (.1, .1, .5, .9, .9, 1, "blue"), (.4, .6, 1, .6, .8, 1, "white"), (.35, .2, 1, .65, .6, 1, "white")], {})
PROPS["publicWomensRoomSign"] = ([(0, 0, 0, 1, 1, .5, "steel"), (.1, .1, .5, .9, .9, 1, "red"), (.4, .6, 1, .6, .8, 1, "white"), (.3, .2, 1, .7, .6, 1, "white")], {})

# ---- bathrooms ----------------------------------------------------------------------------------
PROPS["bathroomStall"] = ([(0, .1, 0, .08, 1, 1, "steel"), (.92, .1, 0, 1, 1, 1, "steel"), (0, .1, 0, 1, 1, .06, "steel"),
                           (.08, .1, .92, .92, .9, 1, "concrete"), (.38, .5, .98, .46, .56, 1, "black")], {})
PROPS["bathroomVanity"] = ([(0, 0, 0, 1, .5, 1, "dark"), (0, .5, 0, 1, .56, 1, "porcelain"), (.2, .56, .2, .8, .62, .8, "white"),
                            (.44, .62, .2, .56, .7, .3, "steel"), (.05, .55, 0, .95, 1, .1, "mirror"), (.08, .08, .98, .48, .46, 1, "oak"), (.52, .08, .98, .92, .46, 1, "oak")], {})
PROPS["houseBathroomShelf"] = ([(0, 0, 0, 1, 1, .4, "oak"), (.04, .1, .4, .96, .4, 1, "paper"), (.04, .6, .4, .96, .9, 1, "porcelain")], {})
PROPS["houseMedicineCabinet"] = ([(0, 0, 0, 1, 1, .8, "porcelain"), (.1, .1, .8, .9, .9, 1, "mirror"), (.4, .4, 1, .46, .6, 1, "steel")], {})
PROPS["houseTowelRack"] = ([(0, .7, 0, .1, 1, .3, "steel"), (.9, .7, 0, 1, 1, .3, "steel"), (0, .8, .3, 1, .9, .5, "steel"),
                            (.1, .1, .3, .9, .8, .8, "@cloth")], {"@cloth": ["blue", "red", "white"]})
PROPS["houseShowerEnclosure"] = ([(0, 0, 0, 1, .06, 1, "porcelain"), (0, .06, 0, .06, 1, 1, "porcelain"), (0, .06, 0, 1, 1, .06, "porcelain"),
                                  (.94, .06, 0, 1, 1, 1, "glass"), (0, .06, .94, 1, 1, 1, "glass"), (.4, .8, .08, .6, .9, .3, "steel")], {})
for t in ("publicMensShowerStall", "publicWomensShowerStall"):
    PROPS[t] = PROPS["houseShowerEnclosure"]
PROPS["publicMensUrinal"] = ([(.1, .1, 0, .9, .9, .5, "porcelain"), (.25, .3, .5, .75, .8, .8, "porcelain"), (.4, .9, .2, .6, 1, .4, "steel")], {})
PROPS["publicSinkBank"] = ([(0, .5, .1, 1, .6, 1, "porcelain")] + [(.1 + .3 * i, .4, .3, .3 + .3 * i, .5, .9, "white") for i in range(3)] +
                           [(0, .6, 0, 1, 1, .08, "mirror"), (.1, 0, .3, .9, .5, .8, "steel")], {})
PROPS["publicBabyChangeStation"] = ([(0, .4, 0, 1, 1, 1, "porcelain"), (.1, .5, .1, .9, .6, .9, "@cloth"), (.1, 0, .0, .9, .4, .3, "steel")], {"@cloth": ["blue", "red"]})
PROPS["publicHandDryer"] = ([(0, 0, 0, 1, 1, .7, "steel"), (.2, .1, .7, .8, .5, 1, "black")], {})
PROPS["publicPaperTowelDispenser"] = ([(0, 0, 0, 1, 1, .8, "steel"), (.2, .0, .8, .8, .2, 1, "black"), (.2, .5, .8, .8, .9, 1, "white")], {})
PROPS["publicSanitaryBin"] = ([(0, 0, 0, 1, 1, 1, "white"), (.15, .75, .98, .85, .9, 1, "black")], {})
PROPS["publicSoapDispenser"] = ([(0, 0, 0, 1, .7, .6, "white"), (.3, .7, 0, .7, 1, .9, "steel"), (.4, .4, .6, .6, .6, 1, "steel")], {})
PROPS["publicShowerBench"] = ([(0, .5, 0, 1, .7, 1, "oak"), (.04, 0, .1, .14, .5, .9, "steel"), (.86, 0, .1, .96, .5, .9, "steel")], {})
PROPS["laundryHamper"] = ([(.05, 0, .05, .95, .85, .95, "oak"), (0, .85, 0, 1, 1, 1, "oak"), (.15, .9, .15, .85, 1, .85, "@cloth")],
                          {"@cloth": ["paper", "blue", "red"]})

# ---- bedroom / living / mansion --------------------------------------------------------------
PROPS["bedroomBench"] = ([(0, .5, 0, 1, .7, 1, "@cloth"), (.04, 0, .1, .14, .5, .9, "dark"), (.86, 0, .1, .96, .5, .9, "dark")], {"@cloth": CLOTH})
PROPS["gothicBedroomBench"] = PROPS["bedroomBench"]
PROPS["bedroomVanity"] = ([(0, 0, 0, 1, .42, 1, "dark"), (0, .42, 0, 1, .48, 1, "oak"), (.08, .48, 0, .92, 1, .08, "mirror"), (.02, .48, 0, .08, 1, .1, "dark"),
                           (.92, .48, 0, .98, 1, .1, "dark"), (.1, .08, .98, .48, .4, 1, "oak"), (.52, .08, .98, .9, .4, 1, "oak")], {})
PROPS["gothicVanity"] = PROPS["bedroomVanity"]
PROPS["vanityStool"] = ([(.1, 0, .1, .9, .5, .9, "dark"), (0, .5, 0, 1, 1, 1, "@cloth")], {"@cloth": CLOTH})
PROPS["gothicVanityStool"] = PROPS["vanityStool"]
PROPS["bunkBed"] = ([(0, 0, 0, .08, 1, .08, "dark"), (.92, 0, 0, 1, 1, .08, "dark"), (0, 0, .92, .08, 1, 1, "dark"), (.92, 0, .92, 1, 1, 1, "dark"),
                     (.04, .2, .04, .96, .3, .96, "paper"), (.04, .6, .04, .96, .7, .96, "paper"), (.04, .3, .3, .96, .38, .96, "@cloth"),
                     (.04, .7, .3, .96, .78, .96, "@cloth"), (.0, .85, 0, 1, .9, .06, "dark")], {"@cloth": CLOTH})
PROPS["prisonBunk"] = ([(0, 0, 0, .06, 1, .06, "steel"), (.94, 0, 0, 1, 1, .06, "steel"), (0, 0, .94, .06, 1, 1, "steel"), (.94, 0, .94, 1, 1, 1, "steel"),
                        (.06, .25, .02, .94, .35, .98, "concrete"), (.06, .7, .02, .94, .8, .98, "concrete"), (.1, .35, .5, .9, .4, .95, "green")], {})
PROPS["gothicDoubleBed"] = ([(0, 0, 0, 1, .3, 1, "dark"), (0, .3, 0, 1, 1, .06, "dark"), (0, .3, .94, 1, .6, 1, "dark"), (.04, .3, .08, .96, .46, .94, "paper"),
                             (.04, .46, .4, .96, .56, .94, "@cloth"), (.1, .46, .1, .46, .58, .3, "white"), (.54, .46, .1, .9, .58, .3, "white")], {"@cloth": ["red", "plum"]})
PROPS["gothicCoffinChest"] = ([(0, 0, 0, 1, .7, 1, "dark"), (.04, .7, .04, .96, 1, .96, "oak"), (.4, .4, .98, .6, .5, 1, "brass")], {})
PROPS["toyChest"] = ([(0, 0, 0, 1, .7, 1, "@wood"), (0, .7, 0, 1, 1, 1, "red"), (.4, .55, .98, .6, .65, 1, "brass")], {"@wood": WOODS})
PROPS["normalCoffeeTable"] = ([(0, .8, 0, 1, 1, 1, "@wood"), (.04, 0, .08, .16, .8, .24, "dark"), (.84, 0, .08, .96, .8, .24, "dark"),
                               (.04, 0, .76, .16, .8, .92, "dark"), (.84, 0, .76, .96, .8, .92, "dark"), (.1, .3, .1, .9, .36, .9, "dark")], {"@wood": WOODS})
PROPS["normalEntryBench"] = ([(0, .3, 0, 1, .36, 1, "oak"), (.04, 0, .1, .12, .3, .9, "dark"), (.88, 0, .1, .96, .3, .9, "dark"),
                              (0, .36, 0, 1, .46, .9, "@cloth"), (0, .46, 0, 1, 1, .1, "oak")], {"@cloth": CLOTH})
PROPS["magazineRack"] = ([(0, 0, 0, 1, .15, 1, "dark"), (0, 0, 0, .08, 1, 1, "dark"), (.92, 0, 0, 1, 1, 1, "dark"), (.08, .1, .6, .92, .3, 1, "red"),
                          (.08, .4, .6, .92, .62, 1, "paper"), (.08, .7, .6, .92, .9, 1, "blue")], {})
PROPS["mansionChaiseLounge"] = ([(0, .2, 0, 1, .5, 1, "@cloth"), (0, .5, 0, .24, .9, 1, "@cloth"), (0, 0, 0, .08, .2, .12, "dark"), (.92, 0, 0, 1, .2, .12, "dark"),
                                 (0, 0, .88, .08, .2, 1, "dark"), (.92, 0, .88, 1, .2, 1, "dark")], {"@cloth": CLOTH})
PROPS["mansionRockingChair"] = ([(0, 0, 0, .1, .06, 1, "dark"), (.9, 0, 0, 1, .06, 1, "dark"), (.1, .06, .1, .9, .36, .4, "@wood"), (.1, .36, .1, .9, .46, .9, "@wood"),
                                 (.1, .46, .1, .9, 1, .24, "@wood")], {"@wood": WOODS})
PROPS["mansionTeaCart"] = ([(0, .1, 0, 1, .16, 1, "brass"), (0, .66, 0, 1, .72, 1, "brass"), (.02, 0, .1, .08, .8, .9, "brass"), (.92, 0, .1, .98, .8, .9, "brass"),
                            (.5, .72, .3, .85, .9, .7, "porcelain"), (.1, .72, .3, .3, .8, .7, "white"), (.8, .8, 0, 1, 1, 1, "brass")], {})
PROPS["mansionUprightPiano"] = ([(0, 0, 0, 1, 1, .8, "black"), (.04, .38, .8, .96, .46, 1, "white"), (.04, .3, .8, .96, .38, 1, "black"), (.1, .6, .8, .9, .9, 1, "dark"),
                                 (0, 0, .8, .06, .38, 1, "black"), (.94, 0, .8, 1, .38, 1, "black")], {})
PROPS["mansionGrandfatherClock"] = ([(0, 0, 0, 1, .12, 1, "dark"), (.1, .12, .1, .9, .62, .9, "dark"), (.25, .2, .9, .75, .56, 1, "glass"),
                                     (.46, .26, .97, .54, .52, 1, "brass"), (0, .62, 0, 1, .9, 1, "dark"), (.2, .68, .98, .8, .86, 1, "paper"), (.1, .9, .1, .9, 1, .9, "dark")], {})
PROPS["mansionFireplace"] = ([(0, 0, 0, 1, 1, .55, "stone"), (.2, 0, .55, .8, .6, 1, "black"), (.2, 0, .55, .8, .2, .95, "rust"), (.3, .1, .6, .7, .3, .9, "amber"),
                              (0, .8, .55, 1, 1, 1, "oak"), (0, 0, .55, .2, .8, 1, "stone"), (.8, 0, .55, 1, .8, 1, "stone")], {})
PROPS["mansionDisplayCabinet"] = ([(0, 0, 0, 1, 1, .9, "dark"), (.06, .06, .9, .94, .94, 1, "glass"), (.1, .3, .3, .9, .34, .86, "oak"), (.1, .6, .3, .9, .64, .86, "oak"),
                                   (.2, .34, .4, .4, .5, .6, "brass"), (.6, .64, .4, .8, .8, .6, "porcelain")], {})
PROPS["mansionCoatRack"] = ([(.2, 0, .2, .8, .06, .8, "dark"), (.42, .06, .42, .58, .94, .58, "dark"), (.1, .76, .42, .9, .84, .58, "dark"), (.42, .76, .1, .58, .84, .9, "dark"),
                             (.42, .4, .1, .58, .88, .26, "@cloth")], {"@cloth": CLOTH})
PROPS["mansionBustPedestal"] = ([(0, 0, 0, 1, .55, 1, "porcelain"), (.1, .55, .1, .9, .6, .9, "stone"), (.3, .6, .3, .7, .78, .7, "stone"), (.3, .78, .26, .7, 1, .7, "stone")], {})
PROPS["mansionRoomDivider"] = ([(0, 0, 0, 1, .06, 1, "dark")] + [(i / 3 + .01, .06, .1, (i + 1) / 3 - .01, .94, .9, "@cloth") for i in range(3)] +
                               [(i / 3 + .01, .94, .1, (i + 1) / 3 - .01, 1, .9, "dark") for i in range(3)], {"@cloth": ["red", "plum"]})
PROPS["gothicHighbackChair"] = (legs(.2, .14, "dark", .06) + [(.04, .2, .04, .96, .3, .96, "dark"), (.1, .3, .1, .9, .36, .9, "@cloth"), (.04, .3, .04, .96, 1, .16, "dark"),
                                (.14, .4, .1, .86, .9, .14, "@cloth")], {"@cloth": ["red", "plum"]})
PROPS["gothicPedestalTable"] = ([(.1, 0, .1, .9, .12, .9, "dark"), (.38, .12, .38, .62, .8, .62, "dark"), (0, .8, 0, 1, 1, 1, "@wood")], {"@wood": ["dark", "oak"]})
PROPS["gothicWritingDesk"] = ([(0, .8, 0, 1, 1, 1, "dark")] + legs(.8, .1, "dark", .02) + [(.1, .5, .1, .5, .8, .9, "oak"), (.54, .84, .3, .9, .88, .7, "paper")], {})
PROPS["gothicBedsideCandelabra"] = ([(.1, 0, .1, .9, .1, .9, "brass"), (.44, .1, .44, .56, .6, .56, "brass"), (.1, .6, .4, .9, .66, .6, "brass"),
                                     (.1, .66, .44, .22, .9, .56, "amber"), (.78, .66, .44, .9, .9, .56, "amber"), (.44, .66, .44, .56, 1, .56, "amber")], {})
PROPS["gothicFloorCandelabra"] = ([(.1, 0, .1, .9, .05, .9, "brass"), (.46, .05, .4, .54, .8, .6, "brass"), (0, .8, .4, 1, .84, .6, "brass"),
                                   (0, .84, .44, .1, .94, .56, "amber"), (.9, .84, .44, 1, .94, .56, "amber"), (.46, .84, .44, .54, 1, .56, "amber")], {})
PROPS["diningChandelier"] = ([(.44, .7, .44, .56, 1, .56, "brass"), (.1, .5, .1, .9, .6, .9, "brass"), (.1, .6, .1, .2, .7, .2, "amber"), (.8, .6, .1, .9, .7, .2, "amber"),
                              (.1, .6, .8, .2, .7, .9, "amber"), (.8, .6, .8, .9, .7, .9, "amber"), (.4, .2, .4, .6, .5, .6, "amber")], {})
PROPS["ceilingFan"] = ([(.44, .6, .44, .56, 1, .56, "steel"), (.4, .3, .4, .6, .6, .6, "black"), (.0, .3, .44, 1, .4, .56, "oak"), (.44, .3, 0, .56, .4, 1, "oak")], {})
PROPS["backstageRepairStand"] = ([(0, .6, 0, 1, .7, 1, "steel"), (.04, 0, .1, .12, .6, .9, "steel"), (.88, 0, .1, .96, .6, .9, "steel"),
                                  (.1, .7, .2, .5, .9, .6, "black"), (.6, .7, .3, .9, .76, .8, "amber")], {})
PROPS["utilityCart"] = PROPS["backstageRepairStand"]
PROPS["maintenanceCleaningCart"] = ([(0, .2, 0, 1, .26, 1, "steel"), (.02, 0, .1, .1, .2, .9, "black"), (.9, 0, .1, .98, .2, .9, "black"), (.05, .26, .1, .55, .8, .9, "blue"),
                                     (.6, .26, .1, .95, .6, .9, "yellow"), (.9, .3, 0, 1, 1, 1, "steel")], {})
PROPS["maintenanceToolCabinet"] = ([(0, 0, 0, 1, 1, .9, "red"), (.06, .06, .9, .94, .5, 1, "steel"), (.06, .55, .9, .94, .94, 1, "steel"), (.4, .22, 1, .6, .28, 1, "black"),
                                    (.4, .7, 1, .6, .76, 1, "black")], {})

# ---- office -----------------------------------------------------------------------------------
PROPS["officeCornerWorkstation"] = ([(0, .86, 0, 1, 1, .5, "oak"), (0, .86, .5, .5, 1, 1, "oak"), (.02, 0, .04, .12, .86, .46, "steel"), (.9, 0, .04, .98, .86, .46, "steel"),
                                     (.02, 0, .6, .12, .86, .96, "steel"), (.3, 1, .1, .5, 1, .3, "black")], {})
PROPS["officeCubiclePartition"] = ([(0, 0, 0, 1, .06, 1, "black"), (.02, .06, .2, .98, 1, .8, "@cloth")], {"@cloth": ["steel", "blue", "green"]})
PROPS["officeFileBoxes"] = ([(0, 0, 0, .5, .5, .6, "paper"), (.5, 0, 0, 1, .5, .6, "paper"), (.1, .5, .05, .6, 1, .6, "paper"), (.04, .3, .6, .46, .4, .64, "black"),
                             (.54, .3, .6, .96, .4, .64, "black")], {})
PROPS["officePhotocopier"] = ([(0, 0, 0, 1, .6, 1, "concrete"), (0, .6, 0, 1, .8, 1, "steel"), (.05, .8, .1, .95, .9, .9, "glass"), (.6, .6, .8, .9, .66, 1, "screen"), (.1, .3, .98, .5, .4, 1, "black")], {})
PROPS["officePrinter"] = ([(0, 0, 0, 1, .7, 1, "concrete"), (.1, .7, .2, .9, .9, .7, "white"), (.1, .05, .96, .9, .15, 1, "black"), (.7, .55, .98, .85, .62, 1, "screen")], {})
PROPS["officeShredder"] = ([(.05, 0, .05, .95, .7, .95, "black"), (0, .7, 0, 1, .9, 1, "steel"), (.1, .9, .3, .9, 1, .7, "black")], {})
PROPS["officeWaterCooler"] = ([(.05, 0, .05, .95, .55, .95, "white"), (.2, .55, .2, .8, .95, .8, "water"), (.35, .3, .95, .65, .4, 1, "blue"), (.35, .2, .95, .65, .28, 1, "red")], {})

# ---- kitchens ---------------------------------------------------------------------------------
for t in ("normalKitchenSink", "luxuryKitchenSink", "gothicKitchenSink"):
    PROPS[t] = ([(0, 0, 0, 1, .9, 1, "oak"), (0, .9, 0, 1, 1, 1, "stone"), (.2, .88, .2, .8, .9, .8, "steel"), (.44, .9, .05, .56, 1, .3, "steel"), (.06, .08, .98, .48, .8, 1, "dark"),
                 (.52, .08, .98, .94, .8, 1, "dark")], {})
for t in ("normalKitchenWallCabinet", "luxuryKitchenWallCabinet", "gothicKitchenWallCabinet"):
    PROPS[t] = ([(0, 0, 0, 1, 1, .9, "dark"), (.04, .06, .9, .48, .94, 1, "oak"), (.52, .06, .9, .96, .94, 1, "oak"), (.4, .4, 1, .44, .6, 1, "brass"), (.56, .4, 1, .6, .6, 1, "brass")], {})
PROPS["prisonKitchenRack"] = ([(0, 0, 0, .06, 1, .06, "steel"), (.94, 0, 0, 1, 1, .06, "steel"), (0, 0, .94, .06, 1, 1, "steel"), (.94, 0, .94, 1, 1, 1, "steel")] +
                              [(.04, y, .04, .96, y + .05, .96, "steel") for y in (.2, .5, .8)] + [(.2, .25, .3, .5, .4, .7, "concrete"), (.6, .55, .3, .9, .7, .7, "concrete")], {})
PROPS["prisonServingCounter"] = ([(0, 0, 0, 1, .45, 1, "concrete"), (0, .45, 0, 1, .5, 1, "steel"), (0, .5, .5, 1, .56, 1, "steel"), (.1, .56, .2, .9, .7, .6, "porcelain"),
                                  (0, .8, 0, 1, .86, .3, "steel"), (.04, .5, 0, .1, .8, .1, "steel"), (.9, .5, 0, .96, .8, .1, "steel")], {})
PROPS["prisonCafeteriaTable"] = ([(0, .86, 0, 1, 1, 1, "concrete"), (.04, 0, .1, .1, .86, .9, "steel"), (.9, 0, .1, .96, .86, .9, "steel"), (0, .3, .0, 1, .4, .1, "steel"),
                                  (0, .3, .9, 1, .4, 1, "steel")], {})
PROPS["prisonTrayReturn"] = ([(0, 0, 0, 1, .6, 1, "steel"), (.05, .6, .1, .95, .66, .9, "concrete"), (.1, .66, .2, .9, .9, .5, "concrete"), (0, .6, 0, 1, 1, .1, "steel")], {})
PROPS["prisonCellGate"] = ([(0, 0, 0, 1, .06, 1, "black"), (0, .94, 0, 1, 1, 1, "black")] + [(i / 12 + .01, .06, .2, i / 12 + .05, .94, .8, "steel") for i in range(12)] +
                           [(0, .45, .2, 1, .5, .8, "steel")], {})
PROPS["dungeonCage"] = ([(0, 0, 0, 1, .06, 1, "black"), (0, .94, 0, 1, 1, 1, "black")] + [(i / 8, .06, 0, i / 8 + .04, .94, .04, "steel") for i in range(8)] +
                        [(i / 8, .06, .96, i / 8 + .04, .94, 1, "steel") for i in range(8)] + [(0, .06, i / 8, .04, .94, i / 8 + .04, "steel") for i in range(1, 8)] +
                        [(.96, .06, i / 8, 1, .94, i / 8 + .04, "steel") for i in range(1, 8)], {})
PROPS["restraintChair"] = ([(.1, 0, .1, .9, .45, .9, "steel"), (.1, .45, .1, .9, .55, .9, "dark"), (.1, .55, .1, .9, 1, .24, "steel"), (0, .55, .1, .1, .65, .9, "black"),
                            (.9, .55, .1, 1, .65, .9, "black")], {})

# ---- arcade / carnival ------------------------------------------------------------------------
PROPS["arcadeBasketballHoop"] = ([(0, 0, 0, 1, .5, .3, "@cloth"), (.1, .5, 0, .9, 1, .1, "white"), (.3, .62, .1, .7, .7, .4, "red"), (.3, .5, .4, .7, .62, .45, "paper"),
                                  (0, 0, .3, 1, .14, 1, "black")], {"@cloth": ["blue", "red"]})
PROPS["arcadeTokenChanger"] = ([(0, 0, 0, 1, .9, 1, "@cloth"), (.1, .5, .9, .9, .85, 1, "glass"), (.3, .2, .9, .7, .3, 1, "black"), (.2, .9, .1, .8, 1, .9, "yellow")], {"@cloth": ["blue", "red"]})
PROPS["prizeClawMachine"] = ([(0, 0, 0, 1, .3, 1, "@cloth"), (0, .3, 0, .06, 1, 1, "steel"), (.94, .3, 0, 1, 1, 1, "steel"), (0, .3, 0, 1, 1, .06, "steel"),
                              (0, .94, 0, 1, 1, 1, "amber"), (.06, .3, .94, .94, .94, 1, "glass"), (.4, .6, .4, .6, .94, .6, "steel"), (.1, .3, .1, .9, .5, .9, "plum")], {"@cloth": ["red", "blue"]})
PROPS["prizeCounter"] = ([(0, 0, 0, 1, .55, 1, "@wood"), (0, .55, 0, 1, .6, 1, "stone"), (.05, .6, .1, .95, 1, .5, "glass"), (.1, .62, .15, .3, .8, .45, "red"),
                          (.7, .62, .15, .9, .85, .45, "blue")], {"@wood": WOODS})
PROPS["snackKiosk"] = ([(0, 0, 0, 1, .5, 1, "@cloth"), (0, .5, 0, 1, .55, 1, "paper"), (0, .55, 0, .06, 1, 1, "@cloth"), (.94, .55, 0, 1, 1, 1, "@cloth"),
                        (0, .9, 0, 1, 1, 1, "@cloth"), (.1, .55, .1, .9, .9, .2, "glass")], {"@cloth": ["red", "blue"]})
PROPS["carnivalTicketBooth"] = ([(0, 0, 0, 1, .45, 1, "red"), (0, .45, 0, .08, .85, 1, "red"), (.92, .45, 0, 1, .85, 1, "red"), (0, .45, 0, 1, .85, .08, "red"),
                                 (.08, .5, .94, .92, .78, 1, "glass"), (0, .85, 0, 1, .95, 1, "white"), (.1, .95, .1, .9, 1, .9, "yellow")], {})
PROPS["ringTossStall"] = ([(0, 0, 0, .05, 1, .05, "dark"), (.95, 0, 0, 1, 1, .05, "dark"), (0, .8, 0, 1, 1, 1, "@cloth"), (0, 0, .5, 1, .5, .9, "dark"),
                           (.1, .5, .55, .9, .56, .85, "paper"), (.2, .56, .6, .3, .9, .7, "amber"), (.5, .56, .6, .6, .9, .7, "blue"), (.8, .56, .6, .9, .9, .7, "red")], {"@cloth": ["red", "blue"]})
PROPS["popcornCart"] = ([(0, .2, .1, 1, .5, .9, "red"), (0, 0, .1, .1, .2, .9, "black"), (.9, 0, .1, 1, .2, .9, "black"), (.05, .5, .12, .95, .8, .88, "glass"),
                         (.05, .8, .1, .95, .9, .9, "paper"), (.1, .9, .1, .9, 1, .9, "yellow")], {})
PROPS["strengthTester"] = ([(0, 0, 0, 1, .2, 1, "dark"), (.4, .2, .3, .6, .9, .7, "paper"), (.36, .9, .26, .64, 1, .74, "brass"), (.1, .2, .3, .3, .5, .7, "red")], {})
PROPS["circusPedestal"] = ([(0, 0, 0, 1, .6, 1, "red"), (.1, .6, .1, .9, .8, .9, "white"), (.2, .8, .2, .8, 1, .8, "yellow")], {})
PROPS["stagePlatform"] = ([(0, 0, 0, 1, .8, 1, "dark"), (0, .8, 0, 1, 1, 1, "oak"), (.04, .8, .04, .96, 1, .96, "oak")], {})
PROPS["stageSpeaker"] = ([(0, 0, 0, 1, 1, .9, "black"), (.1, .5, .9, .9, .95, 1, "steel"), (.3, .6, 1, .7, .85, 1, "black"), (.1, .06, .9, .9, .4, 1, "steel"), (.3, .12, 1, .7, .34, 1, "black")], {})
PROPS["mascotStatue"] = ([(0, 0, 0, 1, .2, 1, "stone"), (.2, .2, .3, .8, .62, .7, "@cloth"), (.1, .3, .4, .2, .56, .6, "@cloth"), (.8, .3, .4, .9, .56, .6, "@cloth"),
                          (.26, .62, .26, .74, 1, .74, "@cloth"), (.3, .8, .74, .7, .9, .8, "white")], {"@cloth": ["yellow", "blue", "red"]})
PROPS["carnivalCarousel"] = ([(0, 0, 0, 1, .1, 1, "dark"), (.05, .1, .05, .95, .15, .95, "red"), (.47, .15, .47, .53, .75, .53, "brass"), (.15, .75, .15, .85, .8, .85, "white"),
                              (.05, .8, .05, .95, .95, .95, "red"), (.25, .95, .25, .75, 1, .75, "yellow"), (.2, .15, .2, .26, .6, .26, "brass"), (.74, .15, .2, .8, .6, .26, "brass"),
                              (.2, .15, .74, .26, .6, .8, "brass"), (.74, .15, .74, .8, .6, .8, "brass")], {})
PROPS["carouselCenterpiece"] = ([(0, 0, 0, 1, .06, 1, "dark"), (.04, .06, .04, .96, .12, .96, "red"), (.45, .12, .45, .55, .7, .55, "brass"), (.1, .7, .1, .9, .74, .9, "white"),
                                 (.04, .74, .04, .96, .86, .96, "red"), (.2, .86, .2, .8, .94, .8, "yellow"), (.4, .94, .4, .6, 1, .6, "brass")], {})

# ---- beach / outdoors / plants ---------------------------------------------------------------
PROPS["beachChair"] = ([(.1, 0, .1, .9, .2, .9, "@cloth"), (.1, .2, .1, .9, .9, .25, "@cloth"), (.04, 0, .1, .1, .5, .9, "steel"), (.9, 0, .1, .96, .5, .9, "steel")], {"@cloth": ["blue", "red", "yellow"]})
PROPS["beachUmbrella"] = ([(.47, 0, .47, .53, .8, .53, "paper"), (.1, .8, .1, .9, .86, .9, "@cloth"), (.25, .86, .25, .75, .92, .75, "white"), (.42, .92, .42, .58, 1, .58, "@cloth")],
                          {"@cloth": ["red", "blue", "yellow"]})
PROPS["surfboardRack"] = ([(0, 0, 0, .08, 1, 1, "dark"), (.92, 0, 0, 1, 1, 1, "dark"), (.08, .1, .3, .92, .14, .7, "dark"), (.1, 0, .35, .22, .9, .65, "@cloth"),
                           (.4, 0, .35, .52, .8, .65, "white"), (.7, 0, .35, .82, .86, .65, "yellow")], {"@cloth": ["blue", "red"]})
PROPS["sandCastle"] = ([(0, 0, 0, 1, .3, 1, "sand"), (.1, .3, .1, .9, .6, .9, "sand"), (0, .3, 0, .2, .7, .2, "sand"), (.8, .3, 0, 1, .7, .2, "sand"), (0, .3, .8, .2, .7, 1, "sand"),
                        (.8, .3, .8, 1, .7, 1, "sand"), (.4, .6, .4, .6, 1, .6, "sand"), (.44, .8, .44, .5, 1, .5, "red")], {})
PROPS["tikiBar"] = ([(0, 0, 0, 1, .5, 1, "bark"), (0, .5, 0, 1, .56, 1, "oak"), (0, .56, 0, .05, 1, .1, "bark"), (.95, .56, 0, 1, 1, .1, "bark"), (0, .9, 0, 1, 1, 1, "sand"),
                     (.1, .56, .2, .3, .8, .5, "amber"), (.5, .56, .3, .6, .7, .5, "water")], {})
PROPS["frozenBeachHut"] = ([(0, 0, 0, 1, .6, 1, "white"), (0, .6, 0, 1, .66, 1, "water"), (.1, .66, .1, .9, .8, .9, "white"), (.2, .8, .2, .8, .92, .8, "water"), (.4, .92, .4, .6, 1, .6, "white"),
                            (.4, .08, .98, .6, .55, 1, "dark"), (.1, .3, .98, .3, .5, 1, "glass")], {})
PROPS["frozenTidelinePool"] = (ring(0, 0, 1, 1, .08, "white", 0, 1) + [(.08, 0, .08, .92, .6, .92, "water")], {})
PROPS["gardenPlanterBench"] = ([(0, .4, 0, 1, .46, .5, "oak"), (.04, 0, .05, .12, .4, .45, "dark"), (.88, 0, .05, .96, .4, .45, "dark"), (0, .46, 0, 1, 1, .1, "oak"),
                                (0, 0, .5, 1, .5, 1, "dark"), (.04, .5, .54, .96, .66, .96, "bark"), (.1, .66, .6, .9, .9, .9, "leaf")], {})
PROPS["giantTree"] = ([(.4, 0, .4, .6, .55, .6, "bark"), (.3, 0, .3, .4, .15, .4, "bark"), (.6, 0, .6, .7, .15, .7, "bark"), (.1, .45, .1, .9, .75, .9, "leaf"),
                       (.2, .75, .2, .8, .92, .8, "leaf"), (.35, .92, .35, .65, 1, .65, "leaf")], {})
PROPS["palmTree"] = ([(.44, 0, .44, .56, .78, .56, "bark"), (.0, .78, .44, 1, .84, .56, "leaf"), (.44, .78, 0, .56, .84, 1, "leaf"), (.2, .84, .2, .8, .9, .8, "leaf"),
                      (.4, .9, .4, .6, 1, .6, "leaf"), (.4, .72, .4, .6, .78, .6, "bark")], {})
PROPS["grassFern"] = ([(.4, 0, .4, .6, .5, .6, "leaf"), (.1, .1, .4, .4, .4, .6, "leaf"), (.6, .1, .4, .9, .4, .6, "leaf"), (.4, .1, .1, .6, .4, .4, "leaf"), (.4, .1, .6, .6, .4, .9, "leaf"),
                       (0, 0, .4, .1, .2, .6, "leaf"), (.9, 0, .4, 1, .2, .6, "leaf")], {})
flower = lambda petal: ([(.4, 0, .4, .6, .3, .6, "bark"), (.45, .3, .45, .55, .6, .55, "leaf"), (.3, .6, .3, .7, .7, .7, petal), (.4, .7, .4, .6, .85, .6, "yellow"),
                         (.1, 0, .1, .9, .1, .9, "dark")], {})
PROPS["flowerBlue"] = flower("blue")
PROPS["flowerRose"] = flower("red")
PROPS["flowerSun"] = flower("yellow")
PROPS["flowerViolet"] = flower("plum")
PROPS["flowerCenterpiece"] = ([(.2, 0, .2, .8, .4, .8, "glass"), (.3, .4, .3, .7, .6, .7, "leaf"), (.1, .6, .3, .4, .8, .6, "red"), (.6, .6, .4, .9, .85, .7, "yellow"),
                               (.35, .7, .35, .65, 1, .65, "plum")], {})

# ---- inferno / basalt / misc ----------------------------------------------------------------------
PROPS["basaltPillar"] = ([(.1, 0, .1, .9, 1, .9, "black"), (.2, .3, .2, .8, .34, .8, "stone"), (.2, .7, .2, .8, .74, .8, "stone")], {})
PROPS["basaltRubble"] = ([(0, 0, 0, .6, .4, .5, "black"), (.4, 0, .4, 1, .6, 1, "stone"), (.1, 0, .6, .4, .3, 1, "black"), (.6, 0, 0, 1, .25, .35, "concrete"), (.2, .4, .1, .5, .7, .4, "black")], {})
PROPS["brokenAquarium"] = ([(0, 0, 0, 1, .2, 1, "black"), (.02, .2, .02, .98, .9, .98, "water"), (0, .2, 0, .06, 1, 1, "glass"), (.94, .2, 0, 1, .6, 1, "glass"),
                            (.1, .2, .2, .9, .3, .8, "sand"), (.3, .3, .4, .5, .5, .6, "leaf"), (0, .9, 0, 1, 1, 1, "black")], {})
PROPS["emberBrazier"] = ([(.2, 0, .2, .8, .1, .8, "black"), (.4, .1, .4, .6, .5, .6, "black"), (.05, .5, .05, .95, .62, .95, "black"), (.15, .62, .15, .85, .8, .85, "rust"),
                          (.25, .8, .25, .75, 1, .75, "amber")], {})
PROPS["infernoAltar"] = ([(0, 0, 0, 1, .5, 1, "black"), (.1, .5, .1, .9, .7, .9, "stone"), (.2, .7, .2, .8, .78, .8, "rust"), (.1, .78, .3, .2, 1, .5, "amber"), (.8, .78, .3, .9, 1, .5, "amber"),
                          (.4, .78, .4, .6, .9, .6, "red")], {})
PROPS["infernoChainLantern"] = ([(.44, .7, .44, .56, 1, .56, "steel"), (.2, .5, .2, .8, .7, .8, "black"), (.28, .1, .28, .72, .5, .72, "amber"), (.2, 0, .2, .8, .1, .8, "black")], {})
PROPS["lavaPipeManifold"] = ([(0, .3, .2, 1, .6, .8, "rust"), (.1, 0, .3, .26, .3, .7, "rust"), (.74, 0, .3, .9, .3, .7, "rust"), (.4, .6, .3, .6, 1, .7, "rust"), (0, .35, .1, .1, .55, .9, "steel"),
                             (.9, .35, .1, 1, .55, .9, "steel"), (.44, .4, .8, .56, .5, 1, "amber")], {})
PROPS["lavaVent"] = ([(.05, 0, .05, .95, .3, .95, "black"), (.2, .3, .2, .8, .5, .8, "black"), (.3, .5, .3, .7, .6, .7, "amber")], {})
PROPS["magmaCrystalCluster"] = ([(.1, 0, .1, .9, .2, .9, "black"), (.3, .2, .3, .6, .75, .6, "amber"), (.1, .2, .5, .35, .5, .8, "red"), (.6, .2, .2, .9, .6, .5, "amber"), (.4, .75, .4, .5, 1, .5, "yellow")], {})
