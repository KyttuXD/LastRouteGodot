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
