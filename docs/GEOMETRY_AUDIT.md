# Geometry overlap audit

`GeometryAudit` (`src/game/geometry_audit.gd`) collects every placed solid of the generated content as an oriented
footprint plus a height span and reports interpenetration, floating pieces, slivers and ceiling pokes. It works on
generator data (no nodes) for Last Route and the City, and per cube on the built Night Watch offices.

* Suite: `geometry_overlap` (`scripts/validate_geometry_overlap.gd`, ratchet table empty = zero findings allowed).
* Full ranked report with seed, coordinates and node paths:
  `godot --headless --path . res://tools/look/geometry_audit.tscn -- OUTDIR 6 6 TAG` writes `geometry_audit_TAG.json`.
* Multi-angle capture (8 headings x street/14 m up around chosen cells, plus a block sweep):
  `CAP_SPOTS=135:91,183:44 CAP_SWEEP=1 godot --path . res://tools/look/geometry_capture.tscn -- OUTDIR TAG CITY-LOOK`.

## Rules

| Rule | Meaning |
|---|---|
| prop_in_wall / prop_in_prop / prop_in_hall | solid prop footprint penetrates a wall cell, another solid prop, or a hall cell by more than 10 cm |
| door_zone / door_frame | prop in a door keep-clear zone; doorway cell closed or the jamb standing in open floor |
| building_overlap | two City building rectangles share cells |
| orphan_mass | City wall cells owned by no building (drawn as a default 6 m stub beside 12-28 m towers) |
| sliver | 1-2 cell gap between two building masses |
| decor_in_wall / decor_overlap | street furniture part (tree canopy, lamp head) through a facade or another piece, height-aware |
| floating / prop_over_void | surface prop with no parent, wall mount with open wall behind, prop on a void cell |
| poke_ceiling | collider taller than the 4 m ceiling |
| cube_overlap / slab_coplanar / cube_floating | Night Watch cubes of different groups overlapping, coplanar slabs, groups with nothing within 6 cm |

Allow-list (explicit, in `pair_allowance` and `audit_office`): chairs tucked under tables/desks (55 cm), seat rows (20 cm),
tree/cypress canopies blending (30 cm), door/vent/window frames set into a wall aperture, wall-corner joints, tall pieces
ending inside a floor/ceiling slab, cable ends (6 cm), wall-mounted pieces touching their wall.

## Results (6 seeds + ENDLESS-ROUTE/CITY-LOOK, 432 Last Route chunks / 46k props, 8 cities, 9 offices)

| Game | Rule | Before | After |
|---|---|---|---|
| Last Route | prop_in_wall (carnival strengthTester 20 cm into side walls) | 196 | 0 |
| City | orphan_mass (6 m stubs between towers, thin-alley and sealed-pocket fills) | 208 | 0 |
| City | decor_in_wall (tree canopies through facades) | 50 | 0 |
| City | decor_overlap (lamp head inside canopy) | 38 | 0 |
| City | prop_in_wall (interior furniture in cells sealed to wall) | 62 | 0 |
| Night Watch | cube_overlap / slab_coplanar (yard, hall, catwalk, sill slabs over the shell; curtains behind shelves; sill rail) | 17 | 0 |
| Last Route | junction_floor (junction cells on stone tiles instead of the hall carpet, runner biomes) | 9792 | 0 |
| Last Route | prop_in_wall at 2 cm strict tolerance | 1865 | 0 |
| **Total (10 cm rules, excl. junction_floor)** | | **571** | **0** |

Before = `main` at the start of this audit, measured with the same final rules. `docs/geometry_audit_before_after.png`:
top row before, bottom row after (City, CITY-LOOK; the stub brick wall closing alley cell (170,44) is gone).

## Fixes (all generic)

* `CityLayout._absorb_orphan_walls` – leftover wall cells join the building they touch (flood), unreachable ones become hedge.
* `CityLayout._fill_slivers` – 1-2 cell strips between masses are closed unless a doorway opens on them.
* `CityLayout._decor_clips_solid/_decor_clips_decor/_prune_clipping_decor` – furniture keeps its visible footprint (canopy, lamp head) clear of masses and other pieces; no furniture on alley cells.
* `CityLayout.building_props` – no interior furniture on cells that were sealed to wall.
* `GeometryResolve.push_out` (run in `_build_chunk` before PlacementClearance) – solid props slide clear of walls; the carnival strength testers now back onto the side walls.
* Night Watch offices: slab overlaps trimmed (cargo yard, bedroom hall, open-air catwalk, descent sill), bedroom shelves moved clear of the curtains.

## Hall junctions

`StreamedFacilityView3D._runner_kind` only gave the carpet runner to cells exactly one hall wide across one axis. A T, cross
or corner cell is crossed by a hall in both directions, matched neither test and fell through to the random stone corridor
tiles: the grey tile patch in the middle of the carpet at every junction. Junction cells next to a one-hall-wide cell now take
the hall's centre strip (`runner_c`). Audit rules: `junction_floor` (that fallback), `hall_nub` (single wall cell jutting into a
hall; 0 found, so the wall mass in KT's screenshot is not a grid stub and still needs a repro with its seed/position).
`docs/junction_before_after.png` (gothic, `CAP_JUNCTION=gothic` in tools/look/capture.gd): top before shows the grey stone tile patch cut into the red carpet at a hall junction, bottom after shows the carpet running through. The jutting wall mass is still not reproduced.

## City see-through facades (KT: "smaller blocks can be seen through")

Root cause: `_build_facade_cell` drew a facade face only toward OUTDOOR neighbours. A facade cell beside a lamp/tree/bollard
(POST), hedge, bed or water cell had no face, a taller building beside a lower one had no face above its neighbour's roof,
and towers had no roof: the tower was open there and its inside showed through (about 100 undrawn edges per seed). Fix:
`CityFacilityView3D.facade_span` (draw from the neighbouring mass's top to this building's top for every non-interior
neighbour) plus a roof quad. Audit rule `facade_hole` (0 now; was 67-132 per city, old OUTDOOR-only rule on the same layouts).
`docs/city_facade_holes_before_after.png`: top before, bottom after (centre column: the lamp-side seam in the tower is gone).
Dome ribs/rings still exist on main (the City lane removes them in 43f09e20); not touched here.

## Not covered / left

* Prop hitbox vs mesh AABB comparison, walk-test through visible space and the minimap box check are not built yet (the
  collider-level audit finds no prop_in_prop even at 2 cm in Last Route, so any visible clipping there is collider-vs-mesh).
* Room capacity (`room_capacity`, solids over 45% of open floor) finds no squeezed rooms in the sampled chunks.

* Fixtures, pickups and hunter props are not audited. Doors are checked only at the grid level (frame vs wall cells), not mesh vs mesh.
* The City lane (`claude/city-lane`) rewrites facades/props/sky; its facade boxes, awnings, signs and windows need re-auditing once it lands (`geometry_overlap` runs on whatever `CityLayout` produces). Window quads glowing through overlapping masses came from the stub masses fixed here.
* Z-fight of coplanar faces between different materials is only checked for Night Watch slabs; Last Route keeps using the `coplanar` suite.
