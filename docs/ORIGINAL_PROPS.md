# Original prop models over the blocky ones (PREFER_ORIGINAL_PROPS)

The blocky Minecraft-style props (`assets/props/blocky`, `game/config/blocky_prop_models.gd`) are cheap but plain. The
original models (`assets/props/{maze,mansion,beach,nether,prison,carnival,sewer}`) carry more detail. This switch draws the
original wherever a type has one and it passes a fit and cost screen, and keeps the blocky model everywhere else.

```gdscript
PropModelCatalog.PREFER_ORIGINAL_PROPS := true   # false = the old all-blocky look, byte for byte
PropModelCatalog.MAX_ORIGINAL_TRIS     := 520    # triangle cap for an original that is heavier than its blocky twin
PropModelCatalog.ORIGINAL_DENY                   # type -> reason, the types that stay blocky although an original exists
PropModelCatalog.prefer_original_props           # the same switch as a run-time static var (tests and benchmarks flip it)
```

The measured premise first: **the originals are not lower poly.** The median original has about 430 triangles against about 140
blocky; per type the drawn originals average 325 against 110. The cost on a 2015 MacBook Air is therefore not lower
by itself. It is kept down by (1) the screen below and (2) `PropMeshMerge` (one mesh per material per prop, so draws stay equal). The real Air
numbers need a windowed run (end of this file).

## What is presentation and what is gameplay

| | Follows the switch | Fixed to the blocky models |
| --- | --- | --- |
| What the player sees (`PropModelCatalog.model_path`, the 3D view, prefetch) | yes | |
| Which model gameplay is derived from (`PropModelCatalog.collider_model_path`) | | yes: exactly the pick `model_path` made before the switch existed |
| Collider boxes (`PropColliderBoxes.for_prop`, `variant_of`, `variant_paths`) | | yes: the variant index comes from `collider_model_path`, the list is the blocky one |
| Generated tables (`PropColliderSizes`, `TEMPLATE_PROP_SIZES`, footprints, hunter scale, placement) | | yes: nothing in generation loads a model; `tools/props/emit_collider_sizes` still reads the blocky models |
| Saves, sync, seeds, `has_model()` | | yes |

`tests/validate_original_props.gd` proves the second column for every one of the 337 prop types and for generated worlds (42
chunks over every region, two seeds): the whole chunk dictionaries, `PropColliderBoxes.for_prop`, `variant_of`, and the 3D
view's own lookup (`variant_paths(type).find(drawn path)`, `streamed_facility_view_3d.gd`) are identical with the switch on and
off. Why the view lookup is safe: the only per-variant boxes are `PropColliderSizes.VARIANT_BOXES` (`diningChair`,
`diningChairCushion`, `officeChair`), and those three types are on the deny list. Every other type ignores the variant index, so the
view's `-1` for an original path gives the same boxes.

The visual still has to sit in the collider. Of the 93 solid types with an original, 81 have a footprint within 0.10 m of the collider on
every side and 83 within 0.12 m. The screen keeps the other solid types blocky. The worst drawn mismatch is 0.19 m (a decor type, against
its blocky twin, no collider).

## The screen (tools/props/original_fit_report.gd)

`godot --headless --path . res://tools/props/original_fit_report.tscn` prints one `FIT|` line per type that has both models
(footprint per side in the collider frame, height, triangles, mesh nodes, verdict, deny row). `row()` and `verdict()` are what
the test enforces: a type draws its original only if

* footprint within `ORIGINAL_FIT_SOLID` 0.12 m per side of the gameplay collider (solid types), or `ORIGINAL_FIT_DECOR` 0.20 m of the blocky model;
* top within -0.30 / +0.60 m of the blocky model (solid: not more than 0.30 m below the collider); wall-mounted types within 0.15 m top
  and bottom; ceiling types within 0.10 m of the top (they are hung by it);
* at most `MAX_ORIGINAL_TRIS` triangles in the heaviest variant, unless the original is lighter than the blocky model;
* it merges to at most 3 draws.

and is not in a category the deny list holds back for gameplay reasons. A deny row that says `fit` or `heavy` fails the test
the day it stops being true, so the list cannot rot.

## Deny list (80 of the 204 types that have both models)

| Reason | Types | Why |
| --- | --- | --- |
| `hiding` (5) | singleBed, doubleBed, gothicDoubleBed, bedroomWardrobe, gothicWardrobe | `validate_hiding_props` measures the blocky model: 0.36 m under the bed and an open foot (the original beds have 0.11-0.12 m and a blocked foot), the wardrobe interior |
| `collider_variants` (3) | diningChair, diningChairCushion, officeChair | `VARIANT_BOXES` is indexed by the blocky variant. Lift this by passing `PropColliderBoxes.variant_of(prop)` instead of `variant_paths(type).find(path)` at `streamed_facility_view_3d.gd:4402` |
| `seats` (4) | loungeCouch, loungeCouchWide, gothicBedroomBench, publicShowerBench | multi-seat sit points follow the blocky width: the original couches are 1.5 m in a 2.7 m collider |
| `door_frames` (6) | the six room doors | the header wall (`DoorwayFrames.header_y`), the widened double door and the clearance read the blocky frame. With originals `ceiling_gaps` reports open air over gothic doors, and `door_clearance` hit negative leaf boxes |
| `interaction` (8) | carouselCenterpiece, prizeClawMachine, ringTossStall, strengthTester, retroComputer x4 | booth, ride and computer anchors and cameras are tuned to the blocky model |
| `facing` (10) | bedroomVanity, gothicVanity, mansionUprightPiano, officeCornerWorkstation, officeCrtSecurityConsole, prizeCounter, publicBabyChangeStation, snackKiosk, stageSpeaker, tikiBar | the mesh centroid sits on the other side of the pivot from the blocky model; front/back is not confirmed. Look at them windowed before removing a row |
| `fit` (10) | see below | outside the tolerance |
| `heavy` (40) | see below | over 520 triangles and heavier than the blocky twin |

`fit` (original against collider for solid types, against the blocky model otherwise):

| Type | Against | Worst |
| --- | --- | --- |
| beachChair | collider | side 0.39 m, top +0.90 m |
| giantTree | blocky | side 0.32 m |
| floorLamp | collider | side 0.27 m |
| officeFileBoxes | collider | side 0.23 m |
| beachUmbrella | blocky | side 0.21 m |
| bunkBed | collider | side 0.20 m |
| gothicHighbackChair | collider | side 0.13 m, top +1.20 m |
| mansionRockingChair | blocky | top +0.84 m |
| normalEntryBench | blocky | top +0.77 m |
| prisonBunk | collider | top -0.34 m (collider taller than the mesh) |

`heavy` (heaviest original / mean blocky triangles): dungeonCage 2384/1024, palmTree 1816/208, restaurantPartyTable 1372/412,
sandCastle 1340/128, carnivalCarousel 1292/904, mansionBookshelf 1276/236, gothicBookcase 1232/294, normalBookcase 1232/176,
prisonCellGate 1224/480, frozenBeachHut 1168/370, apartmentCarpet 1116/104, diningChandelier 1032/100, frozenTidelinePool 880/506,
prisonKitchenRack 816/288, diningSideboard 748/224, gothicDresser 732/270, gothicFloorCandelabra 704/98, surfboardRack 696/202,
bedroomDresser 660/244, gothicKitchenSink 660/236, mansionFireplace 660/140, maintenanceCleaningCart 652/184, luxuryKitchenSink and
publicSinkBank 616, flowerCenterpiece 584, gothicKitchenStove 576, mansionTeaCart, normalKitchenSink, backstageRepairStand,
serverRack, utilityCart, luxuryPaintingFrameEmpty and luxuryPictureFrameEmpty 572-568, woodenDresserSideboard 564, infernoChainLantern 556,
and at 528 gothicWritingDesk, privacyCurtain, the two public shower stalls, supplyCrates.

Not on the list because there is nothing to prefer: the 115 blocky-only types (hospital, lab, greenhouse, mall and music wing
families and the like) and the 32 `<type>Mansion` finish sets stay blocky; the 18 original-only types (the staircases, the
carnival games, the duck pond and the sewer set) always draw their original.

## Finishes, variants, coordinated sets

* A region finish (`PropModelCatalog.region_finish`, today only the mansion's `"Mansion"`) keeps its blocky finished set. In a finished region the coordinated
  families (`COORDINATED_SET_TYPES`) and every type that has a finished set stay blocky, so a mansion room keeps one palette. This is why the mansion
  window gains only 17% triangles: most of its furniture is finished blocky.
* Elsewhere the original lists of a coordinated family have the same length in the same order as `VARIANT_THEMES`, so one room id picks one finish for all
  original members (the test checks 640 rooms). A family member that is denied (the beds, `officeChair`) stays blocky as before; the blocky
  lists were never coordinated across types, so a room can still mix a blocky bed with original bedside furniture.
* The pick is a hash of the room id (or the prop id) over the list the type draws from, as before; original lists are shorter than the blocky
  ones (`woodenChair` 4 against 13), so a drawn room has fewer distinct looks.

## Measured cost (headless, CPU side)

Sampled with the real pipeline (`ModelSlot.instantiate_prop` -> `RefLook.grade_prop` -> `PropMeshMerge.merge`) over 3x3-chunk windows of
every region (the streaming radius), seed `STREAM-BENCH`, level 0 (the sewer level -1): `blocky` is what shipped before, `preferred` is this change.
Triangles are summed over every prop in the window after the merge; `near 30 m` is the triangles of props within 30 m of the middle chunk (about what
the 28/48/72 m visibility ranges draw). Draw calls (merged surfaces) are the same in both modes in every region. Build is the cold instantiate + merge time
of the window on a noisy desktop, so read the ratio only.

| Region | props/window | tris blocky -> preferred (all-original) | near 30 m | materials blocky -> preferred (all-orig.) | build ms blocky -> preferred (all-orig.) |
| --- | --- | --- | --- | --- | --- |
| hotel | 618 | 134k -> 247k (1.84x; 2.05x) | 18.0k -> 34.7k | 6 -> 38 (57) | 1030 -> 1265 (1646) |
| maze | 761 | 123k -> 227k (1.86x; 2.33x) | 19.4k -> 38.5k | 11 -> 38 (53) | 1291 -> 1584 (1928) |
| apartment | 1256 | 231k -> 414k (1.80x; 2.14x) | 29.7k -> 56.4k | 15 -> 38 (65) | 2055 -> 2806 (2763) |
| prison | 480 | 87k -> 132k (1.52x; 1.94x) | 7.1k -> 10.5k | 3 -> 10 (13) | 696 -> 737 (876) |
| carnival | 425 | 55k -> 84k (1.53x; 1.69x) | 4.9k -> 8.4k | 26 -> 33 (35) | 611 -> 695 (836) |
| beach | 271 | 42k -> 62k (1.47x; 2.50x) | 7.5k -> 9.8k | 4 -> 8 (11) | 462 -> 515 (773) |
| gothic | 678 | 183k -> 220k (1.20x; 1.71x) | 24.1k -> 29.9k | 11 -> 23 (44) | 1057 -> 1088 (1743) |
| hospital | 978 | 172k -> 204k (1.18x; 1.59x) | 31.5k -> 35.3k | 9 -> 19 (22) | 1651 -> 1938 (2125) |
| lab | 761 | 152k -> 180k (1.18x; 1.78x) | 22.7k -> 26.2k | 8 -> 17 (23) | 1284 -> 1269 (1684) |
| mansion | 683 | 124k -> 145k (1.17x; 2.32x) | 17.1k -> 19.5k | 8 -> 13 (61) | 1135 -> 1160 (1824) |
| mall | 368 | 79k -> 86k (1.09x; 1.08x) | 28.2k -> 30.7k | 23 -> 26 (27) | 672 -> 586 (590) |
| sewer | 182 | 70k -> 70k (1.00x) | 7.2k -> 7.2k | 21 -> 21 | 772 -> 849 |

Reading it: triangles go up 1.1x to 1.9x (the all-original look would have been 1.6x to 2.5x), draw calls do not move, materials go up
because every original model has its own 128-192 x 16 palette strip and its own material names. Sharing them was tried and dropped: keying the
palette by its imported file hash does not merge anything (the 408 strips are 138 different images but named per model), and ignoring the name merges
the locker's trim/hardware/inset materials that `validate_props` keeps apart. Baking the palettes into one atlas (the way the blocky models share one) is
the next step if the Air shows material or texture binds as the cost.
The mansion barely changes because of the finish rule, and the sewer has no blocky models at all.

The benchmark was a scratch harness (not committed); `tests/validate_prop_perf.gd` (`prop_perf`) still ratchets the materials and mesh instances of the streamed route, and
`original_props` ratchets the triangle ratio of the drawn set.

## What must be verified windowed, on the Air (and one other Mac)

Nothing here was run on a GPU. Please check, with `PREFER_ORIGINAL_PROPS` true and then false for the same seed:

1. **Frame time and draws**: `dev/look/prop_perf.tscn` and `dev/look/stream_bench` in a hotel, a maze and the apartment (the three biggest rises, +1.8x triangles,
   +27 to +32 materials). Watch fps, `draw_calls_mean` against the Air budget of 400 (`tools/build/perf_budgets.json`), frame-time spikes when a chunk streams in
   (the build time is about +10 to +35%, noisy), and VRAM. If the Air hitches, lower `MAX_ORIGINAL_TRIS` first (400 keeps roughly 90 of the 118 types), then atlas the palettes.
2. **Fit**: walk against the drawn originals that overhang or fall short of their (unchanged) collider by the most: woodenTable, woodenChair, woodenChairCushion, bedroomNightstand,
   officeDesk, filing cabinets and kitchen counters (up to 0.12 m per side), bathroomSink, houseToilet and the public restroom fixtures (taller than the collider by up to 0.6 m),
   wall frames and sconces (flush against the wall), ceiling lights and the fan (hung by their top).
3. **Sitting**: woodenChair, woodenChairCushion, bedroomBench, vanityStool, gardenPlanterBench, gothicVanityStool (the seat height is scanned from the original's top face; the
   camera must not clip the backrest).
4. **Facing** of the drawn wall-backed pieces (kitchen counters, cabinets, wardrobes) and, if you want them, the 10 `facing` rows.
5. **Mixed rooms**: a bedroom (blocky bed, original nightstand and dresser), an office (blocky chair, original desk), and the mansion (finished blocky next to an original frame or rug).
6. **Doors** are all blocky; nothing to check there.

## Known, not caused by this change

* `streamed_facility_view_3d.gd` looks the collider variant up with the drawn path. In a finished region it draws `diningChairMansion_n`, which is not in
  `variant_paths("diningChair")`, so the view builds the union box where `CollisionWorld` uses the variant's own box (48 props in the sampled chunks). Same with the switch off.
* Failing before the change and with the switch off: `prop_orientation` (34 props not facing their anchor), `data_themes` (frozen hashes from an old commit, including the
  mall/maze/mansion chunk hashes), `geometry_overlap` (hall nubs).
