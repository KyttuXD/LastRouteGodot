"""Outdoor/beach/garden group: the beach, frozen-beach, maze garden, nether rock, greenhouse and potted-plant types redone
low-poly. exec'd by build_blocky_props.py after
SIZE_SCALE and before the mansion finishes, so PROPS, VARIANTS, FINISH_B and LOWPOLY are in scope.

What changes, and what does not:
  - Fewer, chunkier boxes: rows of seedlings, pots, bottles and flowers become a few strips or clumps; buried parts (water inside a
    stone basin, a kick plate inside a cabinet, soil under a trunk) and tiny trims that never read at play distance are gone.
  - Every type in LOWPOLY is built with hidden_faces(): faces on the floor, buried in another box or covered by a box sitting on them
    are not emitted. Big floor props (tideline pool, dome fountain, raised planter, giant tree) gain the most, since every 0.5 m face
    cell is two triangles.
  - Locked to staging 29b79686: type ids, the number of models per type (so a seed picks the same variant slot), every model's
    bounds (so prop_collider_sizes.gd regenerates unchanged and footprints/placement stay put), the front (+z) and the colour
    options. The boxes that set each model's extent (canopy edges, frond tips, vine tufts, the seedling-rack light, the fountain
    rim) are kept as they were. Same atlas, no new tiles. Boxes are fractions of the staging footprint (TARGET_SIZE types too).
"""

_OUTDOOR_078 = ["beachUmbrella", "beachMat", "surfboardRack", "sandCastle", "tikiBar", "frozenBeachHut", "frozenTidelinePool",
                "giantTree", "palmTree", "grassFern", "flowerBlue", "flowerRose", "flowerSun", "flowerViolet", "flowerCenterpiece",
                "basaltPillar", "basaltRubble", "brokenAquarium", "infernoAltar", "magmaCrystalCluster",
                "pottedPlant", "pottedPalm", "bananaPlant", "saguaroCactus", "cactusCluster", "raisedPlanter", "pottingBench",
                "seedlingRack", "irrigationManifold", "mistingPost", "overgrowthPatch", "hangingVines", "domeFountain",
                "wateringCart", "compostBins", "labBench"]


def _od_keep(name, boxes):
    """New boxes, staging colour options, no shape variants."""
    assert name in PROPS and not VARIANTS.get(name), (name, VARIANTS.get(name))
    PROPS[name] = (boxes, PROPS[name][1])


def _od_recolour(boxes, mapping):
    return [b[:6] + (mapping.get(b[6], b[6]),) + tuple(b[7:]) for b in boxes]


# ---- beach ---------------------------------------------------------------------------------------------------------------------
_od_keep("beachUmbrella", [(.47, 0, .47, .53, .8, .53, "paper"),             # pole stops under the canopy
                           (.1, .8, .1, .9, .9, .9, "@cloth"),                # canopy, one slab (the white ring is gone)
                           (.42, .9, .42, .58, 1, .58, "@cloth")])
_od_keep("beachMat", [(0, 0, 0, 1, 1, .34, "yellow"), (0, 0, .34, 1, 1, .66, "white"), (0, 0, .66, 1, 1, 1, "yellow")])   # 3 bands (was 5)
_od_keep("surfboardRack", [(0, 0, 0, .08, 1, 1, "dark"), (.92, 0, 0, 1, 1, 1, "dark"),
                           (.08, .1, .3, .92, .14, .7, "dark"),
                           (.1, 0, .35, .22, .9, .65, "@cloth"), (.4, 0, .35, .52, .8, .65, "white"), (.7, 0, .35, .82, .86, .65, "yellow")])
_od_keep("sandCastle", [(0, 0, 0, 1, .3, 1, "sand"), (.1, .3, .1, .9, .6, .9, "sand"),
                        (0, .3, 0, .2, .7, .2, "sand"), (.8, .3, 0, 1, .7, .2, "sand"), (0, .3, .8, .2, .7, 1, "sand"), (.8, .3, .8, 1, .7, 1, "sand"),
                        (.4, .6, .4, .6, .8, .6, "sand"),                     # keep
                        (.44, .8, .44, .5, 1, .5, "red")])                    # flag
_od_keep("tikiBar", [(0, 0, 0, 1, .5, 1, "bark"), (0, .5, 0, 1, .56, 1, "oak"),
                     (0, .56, 0, .05, .9, .1, "bark"), (.95, .56, 0, 1, .9, .1, "bark"),   # posts stop under the thatch
                     (0, .9, 0, 1, 1, 1, "sand"),
                     (.1, .56, .2, .6, .74, .5, "amber")])                    # bottles as one row
_od_keep("frozenBeachHut", [(0, 0, 0, 1, .66, 1, "white"),                   # walls and the icy band as one block
                            (.1, .66, .1, .9, .8, .9, "water"), (.2, .8, .2, .8, .92, .8, "white"), (.4, .92, .4, .6, 1, .6, "water"),
                            (.4, .08, .98, .6, .55, 1, "dark"), (.1, .3, .98, .3, .5, 1, "glass")])
_od_keep("frozenTidelinePool", [(0, 0, 0, 1, 1, .08, "white"), (0, 0, .92, 1, 1, 1, "white"),
                                (0, 0, .08, .08, 1, .92, "white"), (.92, 0, .08, 1, 1, .92, "white"),
                                (.08, 0, .08, .92, .6, .92, "water")])      # shape kept; floor and wall-backed faces removed

# ---- maze garden -------------------------------------------------------------------------------------------------------------
_od_keep("giantTree", [(.4, 0, .4, .6, .45, .6, "bark"),                      # trunk stops under the canopy
                       (.3, 0, .3, .4, .15, .4, "bark"), (.6, 0, .6, .7, .15, .7, "bark"),
                       (.1, .45, .1, .9, .75, .9, "leaf"), (.2, .75, .2, .8, .92, .8, "leaf"), (.35, .92, .35, .65, 1, .65, "leaf")])
_od_keep("palmTree", [(.44, 0, .44, .56, .78, .56, "bark"),                   # no bark collar
                      (0, .78, .44, 1, .84, .56, "leaf"), (.44, .78, 0, .56, .84, 1, "leaf"),
                      (.2, .84, .2, .8, .9, .8, "leaf"), (.4, .9, .4, .6, 1, .6, "leaf")])
_od_keep("grassFern", [(.4, 0, .4, .6, .5, .6, "leaf"),
                       (.1, .1, .4, .9, .4, .6, "leaf"), (.4, .1, .1, .6, .4, .9, "leaf"),   # four fronds as two crossing bars
                       (0, 0, .4, 1, .2, .6, "leaf")])                       # low fronds as one bar
for _n, _c in (("flowerBlue", "blue"), ("flowerRose", "red"), ("flowerSun", "yellow"), ("flowerViolet", "plum")):
    _od_keep(_n, [(.1, 0, .1, .9, .1, .9, "dark"),                           # soil
                  (.45, .1, .45, .55, .6, .55, "leaf"),                       # one stem (the bark stub is gone)
                  (.3, .6, .3, .7, .7, .7, _c), (.4, .7, .4, .6, .85, .6, "yellow")])
_od_keep("flowerCenterpiece", [(.2, 0, .2, .8, .4, .8, "glass"), (.3, .4, .3, .7, .6, .7, "leaf"),
                               (.1, .6, .3, .4, .8, .6, "red"), (.6, .6, .4, .9, .85, .7, "yellow"), (.35, .7, .35, .65, 1, .65, "plum")])

# ---- nether rock / ruins -----------------------------------------------------------------------------------------------------
_od_keep("basaltPillar", [(.1, 0, .1, .9, 1, .9, "black"), (.2, .3, .2, .8, .34, .8, "stone"), (.2, .7, .2, .8, .74, .8, "stone")])
_od_keep("basaltRubble", [(0, 0, 0, .6, .4, .5, "black"), (.4, 0, .4, 1, .6, 1, "stone"), (.1, 0, .6, .4, .3, 1, "black"),
                          (.6, 0, 0, 1, .25, .35, "concrete"), (.2, .4, .1, .5, .7, .4, "black")])
_od_keep("infernoAltar", [(0, 0, 0, 1, .5, 1, "black"), (.1, .5, .1, .9, .78, .9, "stone"),   # plinth and rust slab as one step
                          (.1, .78, .3, .2, 1, .5, "amber"), (.8, .78, .3, .9, 1, .5, "amber"), (.4, .78, .4, .6, .9, .6, "red")])
_od_keep("magmaCrystalCluster", [(.1, 0, .1, .9, .2, .9, "black"), (.3, .2, .3, .6, .75, .6, "amber"), (.1, .2, .5, .35, .5, .8, "red"),
                                 (.6, .2, .2, .9, .6, .5, "amber"), (.4, .75, .4, .5, 1, .5, "yellow")])
# brokenAquarium: staging has the base plus one automatic finish (rework3 COMMON_SINGLES, FINISH_B: black -> grey); rebuild it from
# the new boxes with the same swap so slot 1 is still the grey finish.
_aq = [(0, 0, 0, 1, .2, 1, "black"), (.02, .2, .02, .98, .9, .98, "water"),
       (0, .2, 0, .06, 1, 1, "glass"), (.94, .2, 0, 1, .6, 1, "glass"),       # one whole pane, one broken
       (.3, .2, .4, .5, .5, .6, "leaf"),                                      # weed (the sand floor under the water is gone)
       (0, .9, 0, 1, 1, 1, "black")]
assert len(VARIANTS.get("brokenAquarium", [])) == 1, VARIANTS.get("brokenAquarium")
_aq_kinds = {b[6] for b in _aq}
PROPS["brokenAquarium"] = (_aq, PROPS["brokenAquarium"][1])
VARIANTS["brokenAquarium"] = [(_od_recolour(_aq, {k: v for k, v in FINISH_B.items() if k in _aq_kinds}), dict(VARIANTS["brokenAquarium"][0][1]))]

# ---- potted plants and cacti -------------------------------------------------------------------------------------------------
_od_keep("pottedPlant", [(.125, 0, .125, .875, .25, .875, "@pot"), (0, .25, 0, 1, .35, 1, "@pot"),
                         (.375, .35, .375, .625, .6, .625, "bark"),            # trunk straight from the rim (no soil layer)
                         (.125, .6, .125, .875, .85, .875, "leaf"), (.25, .85, .25, .75, 1, .75, "leaf"),
                         (0, .65, .375, 1, .8, .625, "green")])               # side leaves as one bar through the crown
_pp = [(.3, 0, .3, .7, .185, .7, "@pot"), (.28, .167, .28, .72, .193, .72, "@pot"),
       (.42, .185, .42, .58, .533, .58, "bark"), (.436, .533, .436, .564, .867, .564, "dark")]   # trunk in two pieces (was six)
for _a in range(0, 360, 60):
    _pp.append((.467, .867, .5, .533, .889, 1.0, "leaf", (-28, _a, 0), (.5, .867, .5)))
    _pp.append((.413, .874, .667, .587, .885, .947, "green", (-28, _a, 0), (.5, .867, .5)))
_pp.append((.433, .848, .433, .567, .941, .567, "leaf"))                      # crown (the coconut is gone)
_od_keep("pottedPalm", _pp)
_bp = [(.273, 0, .273, .727, .239, .727, "@pot"),                              # pot with the soil as one block
       (.455, .239, .455, .545, .611, .545, "green")]
for _a in (20, 110, 200, 290):
    _bp.append((.427, .556, .5, .573, .578, 1.0, "leaf", (-35, _a, 0), (.5, .556, .5)))
    _bp.append((.482, .578, .527, .518, .583, .955, "green", (-35, _a, 0), (.5, .556, .5)))
_bp += [(.445, .722, .5, .555, .744, .909, "leaf", (-15, 65, 0), (.5, .722, .5)),
        (.445, .722, .5, .555, .744, .909, "leaf", (-15, 245, 0), (.5, .722, .5)),
        (.455, .611, .455, .545, 1.0, .545, "leaf")]
_od_keep("bananaPlant", _bp)
_od_keep("saguaroCactus", [(.062, 0, 0, .938, .056, 1, "sand"),
                           (.375, .056, .333, .625, .977, .667, "green"), (.4, .977, .367, .6, 1, .633, "leaf"),
                           (.125, .419, .367, .375, .465, .633, "green"), (.1, .465, .367, .275, .744, .633, "green"),
                           (.625, .558, .367, .875, .605, .633, "green"), (.725, .605, .367, .9, .86, .633, "green"),
                           (.475, .186, .667, .525, .828, .683, "leaf")])     # one rib (was four), no flower or pebble
_od_keep("cactusCluster", [(0, 0, 0, 1, .12, 1, "sand"),
                           (.105, .12, .105, .474, .5, .474, "green"),        # barrel and its cap as one block
                           (.253, .5, .253, .326, .55, .326, "red"),
                           (.579, .12, .526, .842, .65, .789, "leaf"), (.632, .65, .579, .789, 1, .737, "leaf"),
                           (.158, .12, .632, .474, .4, .716, "green", (0, 0, 15), (.316, .12, .674)),
                           (.232, .38, .632, .505, .62, .716, "green", (0, 0, -18), (.368, .38, .674)),
                           (.379, .6, .632, .442, .66, .716, "plum")])        # no loose stones

# ---- greenhouse ----------------------------------------------------------------------------------------------------------------
_od_keep("raisedPlanter", [(0, 0, 0, 1, .524, 1, "@wood"),
                           (0, 0, 0, .04, .571, 1, "dark"), (.96, 0, 0, 1, .571, 1, "dark"),
                           (.04, .476, 0, .96, .571, .067, "dark"), (.04, .476, .933, .96, .571, 1, "dark"),
                           (.04, .524, .067, .96, .533, .933, "bark"),        # soil
                           (.06, .533, .133, .35, .75, .833, "leaf"), (.13, .75, .301, .28, .952, .665, "green"),   # plants in two
                           (.4, .533, .167, .65, .72, .778, "green"),                                             # tiers (was three)
                           (.7, .533, .111, .95, .75, .867, "leaf"), (.76, .75, .292, .89, 1, .685, "green"),
                           (.15, .819, .389, .19, .895, .478, "red"), (.475, .72, .389, .515, .79, .478, "yellow"),
                           (.825, .819, .389, .865, .895, .478, "white")])     # three flowers (was four), no label
_od_keep("pottingBench", [(.019, 0, .043, .056, .586, .129, "@wood"), (.019, 0, .871, .056, .586, .957, "@wood"),
                          (.944, 0, .043, .981, .586, .129, "@wood"), (.944, 0, .871, .981, .586, .957, "@wood"),   # legs stop under the top
                          (0, .586, 0, 1, .621, 1, "@wood"), (.019, .138, .043, .981, .166, .957, "@wood"),
                          (.019, .621, 0, .056, 1, .086, "@wood"), (.944, .621, 0, .981, 1, .086, "@wood"),
                          (0, .828, 0, 1, .855, .314, "@wood"),
                          (.062, .855, .057, .163, .952, .286, "rust"), (.081, .952, .1, .144, 1, .243, "leaf"),
                          (.437, .855, .057, .537, .952, .286, "rust"), (.456, .952, .1, .519, 1, .243, "leaf"),
                          (.812, .855, .057, .912, .952, .286, "rust"), (.831, .952, .1, .894, 1, .243, "leaf"),   # three pots (was five)
                          (.062, .166, .143, .375, .359, .786, "sand"),       # sack (the tray beside it is gone)
                          (.094, .621, .286, .469, .676, .857, "bark"),
                          (.562, .621, .429, .688, .724, .714, "rust"), (.581, .724, .471, .669, .793, .671, "green")])
_sr = [(0, 0, 0, .033, 1, .08, "steel"), (0, 0, .92, .033, 1, 1, "steel"), (.967, 0, 0, 1, 1, .08, "steel"), (.967, 0, .92, 1, 1, 1, "steel")]
for _y, _h in ((.065, (.168, .184)), (.308, (.427, .411)), (.551, (.67, .654)), (.795, (.897, .914))):
    _t = _y + .043
    _sr += [(.033, _y, 0, .967, _y + .016, 1, "steel"), (.042, _y + .016, .1, .958, _t, .9, "black"),
            (.083, _t, .2, .85, _h[1] - .016, .36, "green"),                  # back row of seedlings as one strip (was five)
            (.083, _t, .56, .85, _h[0], .72, "leaf")]                         # front row as one strip
for _y in (.27, .514, .757):
    _sr.append((.042, _y, .2, .958, _y + .016, .8, "white"))                  # grow lights under the shelves
_sr.append((.042, 1.0, .2, .958, 1.016, .8, "white"))                         # top light (sets the height)
_od_keep("seedlingRack", _sr)
_od_keep("irrigationManifold", [(.033, 0, .083, .4, .735, .917, "@tank"),    # tank and lid as one block
                                (.4, .135, .417, 1, .178, .55, "steel"),
                                (.5, .178, .417, .553, .946, .55, "steel"), (.8, .178, .417, .853, .946, .55, "steel"),
                                (.5, .919, 0, .853, .962, .55, "steel"),
                                (.48, .486, .367, .573, .541, .6, "red"),     # one valve (was two), no gauge
                                (.6, .324, .333, .733, .459, .667, "blue"),
                                (.88, 0, .167, 1, .065, .833, "black")])
_od_keep("mistingPost", [(.125, 0, .125, .875, .024, .875, "steel"), (.425, .024, .425, .575, .98, .575, "steel"),
                         (.425, .48, .5, .575, .496, 1.0, "steel"), (.4, .472, .85, .6, .504, 1.0, "blue"),
                         (.425, .68, .5, .575, .696, 1.0, "steel", (0, 90, 0), (.5, .68, .5)),
                         (.4, .672, .85, .6, .704, 1.0, "blue", (0, 90, 0), (.5, .68, .5)),
                         (.425, .88, .5, .575, .896, 1.0, "steel", (0, 180, 0), (.5, .88, .5)),
                         (.4, .872, .85, .6, .904, 1.0, "blue", (0, 180, 0), (.5, .88, .5)),
                         (.3, .968, .3, .7, 1, .7, "steel")])                 # no valve
_od_keep("overgrowthPatch", [(0, 0, .077, .75, .143, .846, "leaf"), (.187, 0, 0, 1, .114, .615, "green"), (.125, 0, .692, .625, .171, 1, "green"),
                             (.062, .114, .154, .281, .943, .423, "leaf"),
                             (.25, .114, .538, .5, 1.029, .846, "green"),
                             (.688, .114, .385, .906, .943, .654, "leaf"),    # three stalks (was five), no creeping vine
                             (.344, .343, .423, .387, .514, .477, "yellow")])
_od_keep("hangingVines", [(.483, .84, .483, .517, 1, .517, "steel"), (.292, .64, .292, .708, .84, .708, "@pot"),
                          (.25, .84, .25, .75, .867, .75, "leaf"), (.31, .867, .31, .69, .92, .69, "green"),   # two tiers (was three)
                          (.25, 0, .267, .3, .68, .317, "leaf"), (.225, .12, .25, .325, .2, .333, "green"),
                          (.683, .16, .333, .733, .68, .383, "leaf"),
                          (.417, .08, .708, .467, .68, .758, "leaf"), (.392, .2, .692, .492, .28, .775, "green"),
                          (.292, .28, .625, .342, .68, .675, "leaf"),
                          (.708, .04, .683, .758, .68, .733, "leaf"), (.683, .16, .667, .783, .24, .75, "green")])
_od_keep("domeFountain", [(.038, 0, .154, .962, .281, .846, "stone"), (.154, 0, .038, .846, .281, .962, "stone"),   # basin (the
                          (.019, .281, .135, .981, .344, .865, "concrete"), (.135, .281, .019, .865, .344, .981, "concrete"),  # water
                          (.058, .281, .173, .942, .344, .827, "water"), (.173, .281, .058, .827, .344, .942, "water"),  # buried in
                          (.442, .344, .442, .558, .688, .558, "stone"),                                            # it is gone)
                          (.327, .688, .327, .673, .75, .673, "concrete"), (.365, .737, .365, .635, .756, .635, "water"),
                          (.481, .75, .481, .519, 1, .519, "water"),
                          (.154, .344, .212, .231, .36, .288, "leaf"), (.769, .344, .712, .846, .36, .788, "leaf")])   # two pads
_od_keep("wateringCart", [(.05, 0, .083, .1, .126, .167, "black"), (.05, 0, .833, .1, .126, .917, "black"),
                          (.9, 0, .083, .95, .126, .167, "black"), (.9, 0, .833, .95, .126, .917, "black"),
                          (.03, .126, .05, .97, .442, .95, "green"), 
                          (.06, .442, .1, .94, .463, .9, "water"),
                          (.94, .442, .167, .98, 1, .233, "steel"), (.94, .442, .767, .98, 1, .833, "steel"), (.94, .947, .233, .98, 1, .767, "steel"),
                          (.1, .463, .25, .35, .758, .667, "steel"),
                          (.35, .632, .417, .5, .674, .5, "steel", (0, 0, 25), (.35, .632, .45)),
                          (.5, .463, .333, .72, .716, .7, "green"),
                          (.05, .158, .95, .35, .4, 1, "yellow")])            # label without its black badge
_od_keep("compostBins", [(0, 0, 0, .486, .9, 1, "@wood"), (.514, 0, 0, 1, .9, 1, "@wood"),
                         (0, .15, .987, .486, .2, 1, "dark"), (0, .65, .987, .486, .7, 1, "dark"),
                         (.514, .15, .987, 1, .2, 1, "dark"), (.514, .65, .987, 1, .7, 1, "dark"),   # two slats per bin (was three)
                         (.036, .9, .067, .45, .95, .933, "bark"), (.55, .9, .067, .964, .95, .933, "bark"),
                         (.071, .95, .2, .214, 1, .4, "leaf"), (.643, .95, .533, .786, .98, .8, "yellow")])
_od_keep("labBench", [(0, 0, .062, 1, .593, .975, "white"),                   # cabinet (the kick plate inside it is gone)
                      (.015, .069, .975, .49, .566, 1, "porcelain"), (.505, .069, .975, .98, .566, 1, "porcelain"),   # two doors
                      (.42, .483, .963, .47, .51, 1, "steel"), (.525, .483, .963, .575, .51, 1, "steel"),       # (was four)
                      (0, .593, 0, 1, .634, 1, "black"), (0, .634, 0, 1, 1, .1, "grey"),
                      (0, .828, .1, 1, .848, .375, "steel"),
                      (.75, .621, .375, .925, .634, .812, "steel"),           # sink
                      (.82, .634, .125, .84, .772, .175, "steel"), (.82, .745, .175, .84, .772, .375, "steel"),
                      (.04, .848, .15, .31, .986, .275, "glass"), (.385, .848, .15, .655, .959, .275, "amber"),
                      (.73, .848, .15, .885, .959, .275, "blue"),             # bottles as three blocks (was eight)
                      (.075, .634, .375, .225, .731, .75, "steel"),           # tube rack and tubes as one block
                      (.3, .634, .312, .475, .724, .75, "grey"),
                      (.525, .634, .25, .675, .772, .562, "white"), (.54, .69, .562, .66, .745, .575, "screen")])

# ---- hidden-face pass for the whole group ---------------------------------------------------------------------------------------
LOWPOLY.update(_OUTDOOR_078)
