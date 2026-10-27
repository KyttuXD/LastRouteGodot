# Z-fighting

## What was done
- **Depth precision:** the first-person cameras had Godot's default near 0.05 / far 4000 (a ratio of 80000), which makes every nearly-coplanar face flicker. They now use **near 0.06, far 160** (`scenes/infinite_route_test.tscn`, `scenes/main_3d.tscn`); the streamed window is 3x3 chunks (135 m), so 160 m is enough.
- **Detector:** `CoplanarScan` (`src/look/coplanar_scan.gd`) walks every `MeshInstance3D` and visible `MultiMesh` instance below the streamed facility, keeps the axis-aligned triangles, buckets them by plane (2 mm tolerance, same facing) and reports overlapping faces of *different* meshes. It skips faces buried in the floor slab, a locker's hidden seal, additive decals (pools, streaks, halos, petals, which draw without depth writes) and, optionally, parts of one prop overlapping each other.
- **Tool:** `Godot --headless --path . res://tools/look/coplanar_scan.tscn -- SEED` prints a summary by mesh-kind pair and the worst pairs with world positions (`SIBLINGS=1` also lists overlaps inside one prop).
- **Validator:** `-- coplanar` (scripts/validate_coplanar.gd) fails if any prop/door/surface pair overlapping by 5 dm2 or more is coplanar (ratchet `KNOWN = 0`).

## Findings and fixes
- Prison cafeteria furniture (serving counter, tables, tray return, kitchen rack) butted flush in the old 5-wide wings (13 pairs, about 0.09 m2 each) and the tray return sat flush against a wall. Prison cells and cafeterias are now 9x9 rooms, so none remain at the sample seed.
- Wall-mounted decor and hidden seam geometry at chunk corners: lantern/teal/sconce faces coplanar with the border walls over 2-4 cm2 patches (about 140 pairs). Tiny and at wall bases.
- Doors: `DoorFrame` vs `OpenDoorLeaf` share the plane y = 2.375 over about 2 cm2 (56 pairs). The door leaf is 2.36 m tall against a 2.39 m lintel; lowering the leaf (tools/props/blocky_props_doors.py `height`) and regenerating the blocky props would remove it. Not regenerated here because that rebuilds the whole blocky prop set.
- Decor vs decor (arch caps/headers, pipes, petals) are adjacent modules of the same kind and additive decals, not placement errors.

## Counts (seed COPLANAR-SCAN, chunks -1..1)
Before: prop/door/surface pairs (any size) 20 kinds, 12+ prison pairs; after: validator count 0 at >= 5 dm2.
