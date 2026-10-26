"""Shape variants: extra, genuinely different silhouettes for the common furniture, so two chairs,
tables, beds or couches in the same house are not just recolours of one model.
exec'd by build_blocky_props.py after the base PROPS; VARIANTS[name] is a list of (boxes, subs) like PROPS[name].
The catalogue picks among all models of a type per room/instance, so more shapes = more variety.
Boxes: (x0, y0, z0, x1, y1, z1, kind) as fractions of the old footprint (x left..right, y up, z back..front)."""

VARIANTS = {}
CL = CLOTH
WD = WOODS


def v(name, boxes, subs=None):
    VARIANTS.setdefault(name, []).append((boxes, subs or {}))


# ---- chairs ------------------------------------------------------------------------------
chair_hi = (legs(.44, .12, "dark", .08) + [(.06, .44, .06, .94, .52, .94, "@wood"), (.1, .52, .06, .9, 1.0, .14, "@wood"),
            (.14, .62, .14, .86, .66, .2, "dark"), (.14, .74, .14, .86, .78, .2, "dark"), (.14, .86, .14, .86, .9, .2, "dark"),
            (.06, .96, .04, .94, 1.0, .16, "dark")])
chair_arm = (legs(.4, .14, "dark", .06) + [(.04, .4, .06, .96, .52, .96, "@cloth"), (.1, .52, .06, .9, 1.0, .22, "@cloth"),
             (.04, .52, .1, .16, .7, .94, "@wood"), (.84, .52, .1, .96, .7, .94, "@wood"), (.04, .66, .1, .16, .72, .94, "oak"), (.84, .66, .1, .96, .72, .94, "oak")])
chair_stool = ([(.1, .5, .1, .9, .6, .9, "@wood"), (.12, 0, .12, .24, .5, .24, "dark"), (.76, 0, .12, .88, .5, .24, "dark"),
                (.12, 0, .76, .24, .5, .88, "dark"), (.76, 0, .76, .88, .5, .88, "dark"), (.12, .2, .12, .88, .26, .24, "dark"), (.12, .2, .76, .88, .26, .88, "dark")])
chair_ladder = (legs(.46, .1, "dark", .08) + [(.06, .46, .08, .94, .54, .92, "@wood")] +
                [(.1 + .24 * i, .54, .06, .18 + .24 * i, 1.0, .12, "@wood") for i in range(4)] + [(.08, .92, .04, .92, 1.0, .14, "dark")])
for n in ("woodenChair", "woodenChairCushion", "diningChair", "diningChairCushion"):
    v(n, chair_hi, {"@wood": WD})
    v(n, chair_arm, {"@cloth": CL, "@wood": WD})
    v(n, chair_stool, {"@wood": WD})
    v(n, chair_ladder, {"@wood": WD})

# ---- tables ------------------------------------------------------------------------------
table_ped = [(.04, .84, .04, .96, .94, .96, "@wood"), (.4, .12, .4, .6, .84, .6, "dark"), (.2, 0, .2, .8, .12, .8, "dark"), (.1, .12, .44, .9, .2, .56, "dark")]
table_trestle = [(0, .86, 0, 1, 1, 1, "@wood"), (.08, 0, .1, .18, .86, .9, "dark"), (.82, 0, .1, .92, .86, .9, "dark"), (.18, .3, .46, .82, .38, .54, "dark")]
table_drawer = [(0, .84, 0, 1, 1, 1, "@wood"), (.04, .66, .04, .96, .84, .96, "dark"), (.4, .72, .96, .6, .78, 1, "brass")] + legs(.66, .1, "dark", .03)
table_slab = [(.02, .8, .02, .98, .92, .98, "@wood"), (.02, 0, .2, .14, .8, .8, "dark"), (.86, 0, .2, .98, .8, .8, "dark"), (.14, .5, .46, .86, .56, .54, "dark")]
for n in ("woodenTable",):
    for shape in (table_ped, table_trestle, table_drawer):
        v(n, shape, {"@wood": WD})
for shape in (table_ped, table_trestle, table_slab):
    v("diningTable", shape, {"@wood": WD})

# ---- beds ----------------------------------------------------------------------------------
def bed(head_h, foot_h, posts, frame="dark", sheets="@cloth"):
    b = [(0, .12, 0, 1, .42, 1, frame), (.03, .42, .05, .97, .62, .95, "paper"), (.03, .42, .36, .97, .7, .95, sheets),
         (.06, .62, .08, .46, .72, .3, "white"), (.54, .62, .08, .94, .72, .3, "white") if posts != "single" else (.5, .62, .08, .5, .62, .08, "white"),
         (0, .12, 0, 1, head_h, .05, frame), (0, .12, .95, 1, foot_h, 1, frame)]
    if posts == "canopy":
        for x0 in (0, .94):
            for z0 in (0, .94):
                b.append((x0, .12, z0, x0 + .06, 1.0, z0 + .06, frame))
        b.append((0, .94, 0, 1, 1.0, .06, frame))
        b.append((0, .94, .94, 1, 1.0, 1, frame))
        b.append((0, .94, 0, .06, 1.0, 1, frame))
        b.append((.94, .94, 0, 1, 1.0, 1, frame))
    return b


for n in ("singleBed", "doubleBed"):
    v(n, bed(.95, .24, "none"), {"@cloth": CL})
    v(n, bed(.72, .5, "single"), {"@cloth": CL})
    v(n, bed(.8, .3, "canopy"), {"@cloth": CL})
    v(n, [(0, 0, 0, 1, .32, 1, "oak"), (.03, .32, .04, .97, .5, .96, "@cloth"), (.04, .5, .06, .96, .6, .3, "white"),
          (0, .32, 0, 1, .9, .05, "oak"), (.04, .5, .5, .96, .56, .96, "paper"), (.9, .32, .9, 1, .42, 1, "oak"), (0, .32, .9, .1, .42, 1, "oak")], {"@cloth": CL})

# ---- couches --------------------------------------------------------------------------------
couch_rolled = [(0, .08, 0, 1, .4, 1, "@cloth"), (0, .4, 0, 1, 1, .24, "@cloth"), (0, .4, .0, .1, .62, 1, "@cloth"), (.9, .4, 0, 1, .62, 1, "@cloth"),
                (-0.0, .62, .02, .1, .72, .98, "@cloth"), (.9, .62, .02, 1, .72, .98, "@cloth"), (.1, .4, .24, .9, .52, .98, "@cloth"),
                (.1, .52, .3, .5, .56, .96, "brass"), (.5, .52, .3, .9, .56, .96, "brass")]
couch_low = [(0, .1, 0, 1, .34, 1, "@cloth"), (0, .34, 0, 1, .74, .2, "@cloth"), (.08, .34, .2, .46, .48, .96, "@cloth"), (.54, .34, .2, .92, .48, .96, "@cloth"),
             (0, 0, .08, .08, .1, .16, "dark"), (.92, 0, .08, 1, .1, .16, "dark"), (0, 0, .84, .08, .1, .92, "dark"), (.92, 0, .84, 1, .1, .92, "dark")]
couch_chaise = [(0, .08, 0, 1, .4, .52, "@cloth"), (0, .08, .52, .5, .4, 1, "@cloth"), (0, .4, 0, 1, .96, .2, "@cloth"), (0, .4, 0, .12, .66, .7, "@cloth"),
                (.88, .4, 0, 1, .66, .52, "@cloth"), (.12, .4, .2, .88, .5, .5, "@cloth"), (.04, .4, .54, .46, .5, .96, "@cloth")]
for n in ("loungeCouch", "loungeCouchWide"):
    for shape in (couch_rolled, couch_low, couch_chaise):
        v(n, shape, {"@cloth": CL})

# ---- storage --------------------------------------------------------------------------------
v("bedroomNightstand", [(0, 0, 0, 1, .12, 1, "dark"), (0, .12, 0, 1, .5, .94, "oak"), (.08, .16, .94, .92, .46, 1, "dark"), (0, .5, 0, 1, .56, 1, "dark"),
                        (0, .56, 0, 1, 1, .94, "oak"), (.08, .6, .94, .92, .96, 1, "dark"), (.42, .72, .99, .58, .8, 1, "brass")])
v("bedroomNightstand", [(0, .7, 0, 1, 1, 1, "@wood"), (.04, 0, .04, .16, .7, .16, "dark"), (.84, 0, .04, .96, .7, .16, "dark"),
                        (.04, 0, .84, .16, .7, .96, "dark"), (.84, 0, .84, .96, .7, .96, "dark"), (.1, .3, .1, .9, .36, .9, "oak")], {"@wood": WD})
for n in ("bedroomDresser", "woodenDresserSideboard", "normalTvConsole", "diningSideboard"):
    v(n, [(0, 0, 0, 1, .12, 1, "dark"), (0, .12, 0, 1, .88, .94, "oak")] + [(.04 + .32 * i, .18, .94, .32 + .32 * i, .46, 1, "dark") for i in range(3)] +
      [(.04 + .32 * i, .52, .94, .32 + .32 * i, .8, 1, "dark") for i in range(3)] + [(0, .88, 0, 1, 1, 1, "dark")])
    v(n, [(.04, 0, .04, .14, .5, .14, "dark"), (.86, 0, .04, .96, .5, .14, "dark"), (.04, 0, .86, .14, .5, .96, "dark"), (.86, 0, .86, .96, .5, .96, "dark"),
          (0, .5, 0, 1, .9, 1, "oak"), (.06, .56, .96, .48, .84, 1, "dark"), (.52, .56, .96, .94, .84, 1, "dark"), (0, .9, 0, 1, 1, 1, "dark"), (.46, .66, .99, .54, .74, 1, "brass")])
v("bedroomWardrobe", [(0, 0, 0, 1, 1, .92, "dark"), (.04, .04, .92, .33, .96, 1, "oak"), (.36, .04, .92, .64, .96, 1, "oak"), (.67, .04, .92, .96, .96, 1, "oak"),
                      (.3, .5, .99, .33, .6, 1, "brass"), (.64, .5, .99, .67, .6, 1, "brass"), (.1, .96, .0, .9, 1, .92, "oak")])
v("bedroomWardrobe", [(0, 0, 0, 1, .12, 1, "dark"), (0, .12, 0, 1, .86, .92, "oak"), (.06, .2, .92, .94, .8, 1, "dark"), (.46, .44, .99, .54, .56, 1, "brass"),
                      (-.0, .86, 0, 1, .94, 1, "dark"), (.1, .94, .1, .9, 1, .9, "oak")])
for n in ("normalBookcase", "mansionBookshelf", "gothicBookcase"):
    open_shelf = [(0, 0, 0, .06, 1, 1, "dark"), (.94, 0, 0, 1, 1, 1, "dark"), (0, 0, 0, 1, 1, .08, "dark")] + [(0, y, .0, 1, y + .04, 1, "oak") for y in (.0, .28, .52, .76, .96)]
    x = .1
    for k, kind in enumerate(["red", "green", "blue", "paper", "plum", "brass", "red", "green"]):
        w = .08 + .02 * (k % 3)
        open_shelf.append((x, .04, .2, x + w, .26 - .02 * (k % 2), .84, kind))
        x += w + .01
    open_shelf.append((.1, .56, .3, .5, .72, .8, "porcelain"))
    open_shelf.append((.6, .8, .3, .82, .96, .76, "brass"))
    v(n, open_shelf)
    cabinet = [(0, 0, 0, 1, .4, 1, "dark"), (.04, .04, .96, .48, .36, 1, "oak"), (.52, .04, .96, .96, .36, 1, "oak"), (0, .4, 0, 1, .44, 1, "oak"),
               (0, .44, 0, .06, 1, .9, "dark"), (.94, .44, 0, 1, 1, .9, "dark"), (0, .44, 0, 1, 1, .08, "dark"), (0, .7, .06, 1, .74, .9, "oak"),
               (.1, .74, .3, .22, .98, .8, "red"), (.24, .74, .3, .34, .96, .8, "green"), (.36, .74, .3, .46, .98, .8, "plum"), (.58, .44, .3, .9, .68, .8, "paper")]
    v(n, cabinet)

# ---- desks, lamps, kitchen, bath -------------------------------------------------------------
v("officeDesk", [(0, .86, 0, 1, 1, 1, "oak"), (.02, 0, .04, .12, .86, .96, "steel"), (.88, 0, .04, .98, .86, .96, "steel"), (.12, .5, .1, .88, .56, .16, "steel"),
                 (.3, .9, .1, .6, 1.0, .24, "black"), (.36, 1, .4, .56, 1.04, .7, "paper")])
v("officeDesk", [(0, .86, 0, 1, 1, 1, "dark"), (.02, 0, .04, .4, .86, .96, "dark"), (.04, .6, .96, .38, .8, 1, "steel"), (.04, .3, .96, .38, .5, 1, "steel"),
                 (.04, .06, .96, .38, .26, 1, "steel"), (.9, 0, .04, .98, .86, .2, "steel"), (.9, 0, .8, .98, .86, .96, "steel")])
v("officeChair", [(.44, 0, .44, .56, .3, .56, "steel"), (.08, 0, .08, .92, .05, .92, "steel"), (.06, .3, .06, .94, .4, .94, "@cloth"), (.1, .4, .06, .9, .95, .14, "@cloth"),
                  (.0, .4, .2, .08, .6, .8, "steel"), (.92, .4, .2, 1, .6, .8, "steel")], {"@cloth": ["plum", "red", "blue"]})
for n in ("tableLamp", "bedsideLamp"):
    v(n, [(.25, 0, .25, .75, .1, .75, "brass"), (.42, .1, .42, .58, .6, .58, "dark"), (.3, .6, .3, .7, .95, .7, "amber"), (.2, .95, .2, .8, 1, .8, "brass")])
    v(n, [(.3, 0, .3, .7, .06, .7, "dark"), (.44, .06, .44, .56, .45, .56, "brass"), (.2, .45, .2, .8, .62, .8, "amber"), (.3, .62, .3, .7, .8, .7, "amber"),
          (.4, .8, .4, .6, 1, .6, "brass")])
v("floorLamp", [(.25, 0, .25, .75, .04, .75, "dark"), (.46, .04, .46, .54, .75, .54, "brass"), (.2, .74, .2, .8, .9, .8, "amber"), (.3, .9, .3, .7, 1, .7, "amber")])
v("floorLamp", [(.1, 0, .1, .9, .05, .9, "iron" if False else "dark"), (.4, .05, .4, .6, .6, .6, "dark"), (.16, .6, .16, .84, .98, .84, "paper"),
                (.2, .6, .2, .8, .62, .8, "brass")])
for n in ("normalKitchenCounter", "luxuryKitchenCounter", "gothicKitchenCounter"):
    v(n, [(0, 0, 0, 1, .9, 1, "dark"), (0, .9, 0, 1, 1, 1, "stone")] + [(.04 + .32 * i, .08, .98, .32 + .32 * i, .8, 1, "oak") for i in range(3)] + [(.1 + .3 * i, .9, .2, .2 + .3 * i, 1.06, .3, "steel") for i in range(2)])
    v(n, [(0, 0, 0, 1, .12, 1, "dark"), (0, .12, 0, 1, .9, 1, "oak"), (0, .9, 0, 1, 1, 1, "porcelain"), (.04, .16, .98, .96, .42, 1, "dark"), (.04, .48, .98, .96, .86, 1, "dark"), (.46, .24, 1, .54, .3, 1, "brass")])
v("houseToilet", [(.2, 0, .3, .8, .42, 1, "porcelain"), (.14, .42, .06, .86, .98, .3, "porcelain"), (.18, .42, .3, .82, .5, .94, "paper"), (.4, .86, .0, .6, .94, .06, "steel")])
v("bathroomSink", [(.34, 0, .34, .66, .62, .66, "porcelain"), (.1, .62, .1, .9, .74, .9, "porcelain"), (.46, .74, .12, .54, .96, .18, "steel"), (.3, .96, .1, .7, 1, .22, "steel")])
v("bathroomSink", [(.04, 0, .06, .96, .6, .94, "@wood"), (0, .6, 0, 1, .68, 1, "porcelain"), (.3, .68, .3, .7, .74, .7, "white"), (.46, .74, .12, .54, .96, .18, "steel"), (.1, .1, .98, .46, .5, 1, "dark"), (.54, .1, .98, .9, .5, 1, "dark")], {"@wood": WD})
v("houseBathtub", [(0, 0, 0, 1, .1, 1, "dark"), (0, .1, 0, 1, .62, .12, "porcelain"), (0, .1, .88, 1, .62, 1, "porcelain"), (0, .1, 0, .12, .62, 1, "porcelain"), (.88, .1, 0, 1, .62, 1, "porcelain"),
                   (.12, .1, .12, .88, .4, .88, "water"), (.4, .62, .02, .6, .74, .1, "steel")])
v("trashBin", [(.1, 0, .1, .9, .8, .9, "steel"), (.04, .8, .04, .96, .9, .96, "concrete"), (.3, .9, .46, .7, .96, .54, "black")])
v("supplyCrates", [(0, 0, 0, .5, .5, .5, "oak"), (.5, 0, 0, 1, .5, .5, "dark"), (0, 0, .5, .5, .5, 1, "dark"), (.5, 0, .5, 1, .5, 1, "oak"), (.2, .5, .2, .8, 1, .8, "oak"), (.2, .62, .2, .8, .68, .8, "dark")])
