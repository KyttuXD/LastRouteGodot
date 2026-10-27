# Props audit: chairs and tables (DONE11)

Measured with `tools/look/prop_dims.gd` (bounding boxes of every blocky variant), `tools/look/prop_lineup.tscn` (renders)
and `tools/look/furniture_audit.gd` (placement over real generated chunks, every district, three seeds). The prop shapes
are built by `tools/props/build_blocky_props.py`; the chair and table definitions now live in
`tools/props/blocky_props_seating.py`. Before/after: `docs/props_chairs_tables_before_after.png`.

References: the thuing library was looked at for proportions, part breakdowns and how many cubes a believable chair or
table needs, and for how rotations are used (backrest tilts, angled legs). Nothing was copied or converted; every shape
here is our own, built from axis-aligned boxes. Rotated parts are not supported by the box builder yet, so tilted backs
and splayed legs are noted below as a follow-up rather than faked.

## What was wrong and what changed

| Prop | Problem (measured) | Fix |
| --- | --- | --- |
| restaurantPartyTable | the table top sat at the top of the balloon cluster, 2.2 m up: a gateway, not a table | table top 0.75 m with cloth, skirts, place settings; the balloon cluster stands on a pole in the middle |
| diningTable | top at 1.0 m (the old model's height with goblets) | 0.75 m, apron under the top, trestle and pedestal variants rebuilt |
| woodenTable | top 0.81 m, slab 11 cm thick, no apron | 0.75 m, 6 cm top, 19 cm apron, 12 cm legs; drawer, trestle and pedestal variants |
| woodenChair / diningChair (+cushion) | seat top 0.56 m (11 cm too high), back a solid slab, legs 14 cm blobs | seat 0.44 m, 6 cm legs with low rails, back = posts + rail + slats (or ladder or padded panel); armchair and stool variants; 0.94 m tall |
| normalEntryBench | seat at 0.67 m, whole prop 1.45 m | scaled to 0.94 m so the seat is 0.44 m |
| gothicPedestalTable | 0.94 m | 0.75 m |
| colliders | chair 1.1-1.2 m, dining table 1.05 m, restaurant table 2.2 m boxes, dressing surface heights 0.79/0.86 | blocker heights match the new models; table surface heights 0.75 so centrepieces and lamps sit on the top |

Every chair and table variant is on the 6 cm voxel grid, floors at y = 0, no floating parts. A chair seat (0.44 m) clears the
apron underside (0.56 m) by 12 cm, so a chair can be tucked in.

## Placement audit (before the rework, unchanged by it)

855 chairs, 636 tables, 5973 solid props over 126 chunks: **0 solid footprint overlaps**. 319 chairs stand more than three
cells from any table (wall-scatter singles, by design); 84 "faces away" reports come from a chair near the wrong table in
an apartment suite, not from the template conventions (`left`/`right`/`back` all face the table, checked in
`_template_prop_entry`). Door-crowding and cut-off-pocket counts from this tool are over-reported for suite rooms (the room
rect is the whole suite), so the proper walk-through test belongs to the collision pass (DONE12).

## Validator

`furniture` (`scripts/validate_furniture.gd`): every chair variant 0.45-1.0 m tall and no wider than a chair, standing on the
floor; every table variant 0.75 m; the restaurant table keeps its balloon cluster; pedestal table 0.75 m; entry bench at most
1.0 m; the collider footprint covers each model (not smaller, not a giant box) and blocker heights cover the model.

## Follow-ups and props that look off (for KT)

- Rotated parts: tilted chair backs (5-15 degrees), splayed stool legs, angled lamp shades. Needs a rotation field in the
  box builder.
- Candidates noticed during the audit: gothicHighbackChair (2.1 m tall), restraintChair, mansionRockingChair, beachChair
  (1.3 m), officeChair (1.3 m, fine for a task chair), beds (bunk/canopy proportions), lounge couches (very wide),
  bookcases and wardrobes (flat fronts), lockers, the old non-blocky tables (prisonCafeteriaTable is a grey slab with
  attached benches), bedroomBench and vanityStool.

## Mesh LODs

Every model import now has `meshes/generate_lods=false` (about 3,400 import files) and `project.godot` sets it as the
importer default, so new models follow. Godot's generated LODs decimate the few-hundred-triangle cube models once a
viewport's LOD threshold is high (low-resolution or scaled 3D): hunter hands and forearms vanish. The `lods` validator
checks every `.glb/.gltf` import. A chair, a table and a nightstand rendered at 3 m and 10 m with a threshold of 8, LODs on
vs off (`tools/look/lod_check.tscn`), came out pixel-identical: props this small never get LODs generated, so the visible
artifact was a hunter problem; the change is the safe default for everything.

# Props rework 2 (DONE13)

Every blocky prop family was measured again (`tools/look/prop_dims.gd` over all 204 types) and the weak ones were rebuilt in
`tools/props/blocky_props_rework2.py`, authored in metres on the 6 cm grid. Before/after: `docs/props_rework2_before_after.png`
(rendered headless with `tools/props/render_sheet.py`).

References: the thuing library was looked at read-only for proportions, part counts and rotation conventions (backrest tilt of
5-15 degrees, splayed legs, rocker arcs, how drapes hang off a canopy). Nothing was copied, converted or committed; every shape is our
own design with our own numbers.

## Rotation field in the box builder

A box can now carry two optional trailing items: `(x0, y0, z0, x1, y1, z1, kind, (rx, ry, rz), (px, py, pz))` - degrees about the
prop axes (x right, y up, z front, applied z, then y, then x) and a pivot in the same fractions. In `blocky_props_*.py` the `Part.add`
helper takes `rot=(rx, ry, rz)` and `pivot=(x, y, z)` in metres (default: the box centre). A positive `rx` tips the top toward the front,
so a backrest that leans back uses a negative `rx`. Rotated boxes keep the voxel-sized thickness and the constant texel density.
`TARGET_SIZE[name] = (w, h, d)` builds a design at exactly that size (floor props are pinned to y = 0 - the old beach chair model floated 4 cm).

## What was wrong and what changed

| Prop | Problem (measured) | Fix |
| --- | --- | --- |
| gothicHighbackChair | 2.12 m tall (a throne taller than a person) | 1.30 m: padded panel and crest leaning back 8 degrees, finials, arms on posts, stretchers |
| restraintChair | 1.94 m, 1.0 m wide, a solid block | 1.35 m: slab back leaning 6 degrees with head rest, arms with wrist cuffs, ankle cuffs, lap strap |
| mansionRockingChair | 1.56 m tall, 1.0 m deep slab | 1.05 m: two curved rockers made of short boxes turned along the arc, slat back leaning 12 degrees, arms |
| beachChair | 0.38 m deep stub, floated 4 cm | 0.6 x 1.0 m lounger: level seat, striped back reclined 45 degrees, props holding the back up |
| bunkBed | 1.75 m, no guard or ladder | 1.85 m: posts, two decks with mattresses and pillows, upper guard rails, ladder at the foot |
| prisonBunk | 1.44 m (an upper bunk you could not sit under) | 1.7 m steel frame, thin grey mattresses, ladder rungs |
| gothicDoubleBed | canopy without hangings | posts, canopy frame, tall headboard, coverlet, drapes slightly out of line and turned a few degrees |
| loungeCouch / loungeCouchWide | very wide (1.62 / 2.75 m), one slab | 1.7 m two-seat / 2.4 m three-seat: rolled arms, split seat cushions, back cushions leaning 9 degrees, feet; three back heights |
| normalBookcase / mansionBookshelf / gothicBookcase | flat front, books as a pattern | carcass with kick plate, shelf boards, crown that stays inside the footprint, varied books, leaning books; 3 variants each |
| bedroomWardrobe / gothicWardrobe | flat slab front | feet, cornice, two doors with raised panels and handles; 3 finishes each |
| locker | flat front | door with louvre slats, handle recess, number plate, base |
| prisonCafeteriaTable | grey slab 0.81 m | bolted steel table 0.75 m with two benches at 0.44 m |
| bedroomBench / gothicBedroomBench / vanityStool | 0.44-0.56 m, solid | 0.46 m with legs, rails, cushion; stools with splayed legs |
| officeDesk | top at 0.88 m | 0.75 m (surface height 0.75, blocker 0.78) |
| kitchen counters / sinks / stoves | counter top 1.12 m next to a 1.0 m stove and a 1.38 m sink | counters 0.92 m, sink 1.12 m with tap, stove 0.92 m so the run lines up |

Colliders, footprints and surface heights followed: `streamed_route_generator.gd` (gothicHighbackChair, bunkBed, prisonCafeteriaTable,
officeDesk), `room_catalog.gd` (beachChair footprint, officeDesk surface 0.75). Rooms are not re-laid out: footprints only shrank,
except the beach chair (0.34 x 0.54 half-size).

Validator `props_rework` (scripts/validate_props_rework.gd): each reworked type is built at its designed size, stands on the floor,
keeps rotated parts inside the footprint, colliders cover it without being giant boxes, desk and kitchen heights line up, and a
sweep over all 438 blocky models catches floating, sunken or collapsed shapes. The sweep and the per-design checks found five real
issues in the first draft of this pass (crown overhangs, drapes and cuffs poking outside the footprint, an ajar wardrobe door that
left its footprint, rocker feet above the floor); all are fixed.

Workflow: `render_sheet.py` (headless contact sheets), `emit_models.py` (regenerates `blocky_prop_models.gd` from the build's
`manifest.json`; the committed manifest had been stale), `clean_orphans.py` (removes GLBs a rebuild no longer lists; keeps the locked
relay barrel). The build is deterministic: rebuilding the previous commit reproduced all 437 committed GLBs byte for byte.

## Families that still look weak (candidates for DONE14)

Measured but not reworked yet: nightstands/dressers (flat fronts, 6 cm drawer lines only), kitchen wall cabinets and islands,
sinks/vanities/mirrors (bathroom), shower enclosures and tubs, floor and table lamps (blocky stacks), TV consoles, desks with computers
(screen/keyboard parts), display cabinets and the piano, arcade and carnival cabinets, supply crates and shelves, the old non-blocky
families (maze, mansion, beach, carnival, nether, prison original models are only fallbacks), plants and flowers (no variants), and
texture density/palette consistency across districts. Collision pass and set dressing belong to the world lane.

# Props rework 3 (DONE14): materials, finishes and the remaining weak families

Contact sheet: `docs/props_rework3_after.png` (rendered headless with `tools/props/render_sheet.py`). Designs live in
`tools/props/blocky_props_rework3.py`; thuing/ was used read-only for proportions and part breakdowns, nothing copied.

## Materials: eight new finishes in the shared atlas

The shared 128x64 atlas had eight free tiles. They are now `walnut`, `pine` (with knots), `ash`, `mahogany`, `linen`, `teal`, `tile`
(8 px grout lines) and `grey`, appended after the old 24 so no existing UV moved (every model is rebuilt because the atlas image is
embedded in each GLB). The wood-style plank lines and the cloth dither apply to the new tiles too, so a pine dresser and an oak one
share the same texel density. The validator now requires every builder model to sample that one 128x64 atlas (612 surfaces checked).

## Rebuilt families

| Family | Problem | Fix |
| --- | --- | --- |
| nightstands, dressers, sideboards, console (7 types) | flat slab with two brass dots | carcass with legs, full-footprint top slab, drawer or door fronts as a raised layer, pulls set into the fronts; per type three layouts (drawers, doors, one row fewer) in four wood finishes |
| table, bedside and floor lamps | stacked boxes with a flat shade | base, pole, tapered shade of 4-6 layers in amber, paper, white, red or plum; a shorter second shape |
| stoves, fridges, sinks (normal, luxury, gothic) | slabs; counter, stove and sink tops at 1.12 / 1.0 / 1.38 m | stove with hob, four burners, oven window, handle bar and knob row; two-door fridge with seam and handles; sink with a real basin hole, tap and two cabinet doors; styles differ in body, trim and top; two extra finishes each |
| toilet, bathtub, pedestal sink | blocks | bowl, seat and lid, cistern with button; tub on brass feet with walls, rim, water and tap; pedestal sink with basin, water and tap; tile and linen finishes |
| bins, crates | solid cubes | pedal bin with a lid hinged at the back (opened 10 degrees); two stacked plank crates with corner posts, the upper one turned 8 degrees, in oak, pine or ash |

Layering rule for fronts: carcass ends 12.5 cm short of the front, the door or drawer layer is the next 6 cm, handles the last 6 cm,
so nothing is coplanar and nothing leaves the footprint (the `coplanar` suite still reports no z-fighting).

## Variety: 2-3 looks for every common family

`recolor()` adds finish variants (wood, metal and cloth swaps that only apply where the model has those kinds) to 48 common
single-model furniture and fixture types (office machines, cabinets, vanities, carts, prison furniture, ...), skipping doors, signs,
lights, trees and set pieces. 43 common families are checked for at least two looks and seating, chests and lamps for at least four
(`COMMON_FAMILIES` / `RICH_FAMILIES` in `scripts/validate_props_rework.gd`). Total: 618 models in 204 types (was 438); 62 types
still have a single model on purpose (doors, signs, trees, flowers, carnival, beach and inferno set pieces).

## Still weak

Doors (six tall regional doors, one look each), flowers and plants (single cube bouquets), arcade and carnival cabinets, sconces and
chandeliers, the piano, tea cart and display cabinet (finish variants only, shapes unchanged), curtains and drapes, signs. These are
candidates for a later pass.
