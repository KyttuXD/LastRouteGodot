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
`city_facade_holes_before_after.png` (on branch archive/city-20261027): top before, bottom after (centre column: the lamp-side seam in the tower is gone).
Dome ribs/rings still exist on main (the City lane removes them in 43f09e20); not touched here.

## Not covered / left

* Prop hitbox vs mesh AABB comparison, walk-test through visible space and the minimap box check are not built yet (the
  collider-level audit finds no prop_in_prop even at 2 cm in Last Route, so any visible clipping there is collider-vs-mesh).
* Room capacity (`room_capacity`, solids over 45% of open floor) finds no squeezed rooms in the sampled chunks.

* Fixtures, pickups and hunter props are not audited. Doors are checked only at the grid level (frame vs wall cells), not mesh vs mesh.
* The City lane (`claude/city-lane`) rewrites facades/props/sky; its facade boxes, awnings, signs and windows need re-auditing once it lands (`geometry_overlap` runs on whatever `CityLayout` produces). Window quads glowing through overlapping masses came from the stub masses fixed here.
* Z-fight of coplanar faces between different materials is only checked for Night Watch slabs; Last Route keeps using the `coplanar` suite.

## City: looking up from the Ring Road

`city_ring_road_up_before_after.png` (on branch archive/city-20261027) (top before, bottom after; cell 200:67, pitch 55, four headings;
`tools/look/geometry_capture.tscn`, now with `CAP_PITCH` and `CAP_HIDE=NodeName,...` to isolate layers).

- Thin dark arcs across the sky: the dome shell (ribs, rings, pylons, viaducts) in `CityDomeFrame`. Removed, matching
  `claude/city-lane` 43f09e20.
- Maroon slabs floating overhead: tree canopies (and other raised `CitySurface.box`es) had no underside, so from below
  only the near side faces showed. Raised boxes now close their bottom.
- Glowing window squares with no wall: skyline windows were offset along the radial direction from axis-aligned tower
  boxes, so diagonal towers' windows hung beside or inside the box. They now sit on the box face that looks at the city.
- Big flat purple polygons behind towers: the sky shader's cloud pixels were ~10 degrees wide near the zenith. Same
  cloud shapes, three times finer cells.
- Camera far (420) covers the sky sphere (380) and the skyline; no visibility_range is set on City geometry.

`geometry_overlap` now checks: the dome frame builds only towers + windows, every skyline window is on a tower face,
and a raised `CitySurface` box has an underside.

Straight up from Central Avenue (`city_central_avenue_zenith_before_after.png` (on branch archive/city-20261027), left before bb183674, right after):
the ring, spokes and cyan bracket markers were the dome ribs, rings and beacons of `CityDomeFrame._build_frame`. Render
check: `tools/look/zenith_check.tscn` (not headless) looks straight up from Central Avenue, Main Street and the Ring Road
and fails if the dome frame darkens more than 0.2% of the zenith disc (old frame: 0.9 to 3.7%, now 0%).

## Hunter model clipping (swaying parts)

`hunter_clipping` (scripts/validate_hunter_clipping.gd, src/game/hunter_clip_audit.gd) loads every blocky hunter, plays every clip at 16
timesteps and fails when a swaying/attached part (hair chain, braid, tail, ear, wing, horn, halo) cuts deeper into the body than it does at
rest (oriented-box SAT per bone mesh), when a part's pivot drifts from its parent, or when feet sink/float. Tiers: idle/walk/chase/sprint/
crouch/charge are strict (torso 5.5 cm, limbs 17 cm); emotes, climb, stun, jumpscare and flight only fail beyond 30 cm. Void `Cue-*`
clouds are exempt by design.

Fix: `tools/blocky_hunters/clearance.py` runs at build time (build.py) after the clips exist. For every extra bone and clip frame it does
forward kinematics, and where the sway would clip it picks the cheapest smaller sway and/or pitch/yaw/roll offset that clears the body,
so a part only deviates in the frames that would have clipped. Before: 9225 findings over 38 hunters (a ponytail through the belly in most
chase frames, Porcelle's braids across torso and legs); after: 0 on the validator. Capture: docs/hunter_clipping_before_after.png.

Sway amplitude: `SWAY_SCALE` (0.5) and `SWAY_FREQUENCY` (0.6) at the top of tools/blocky_hunters/bb_rig.py scale idle breathing, gait torso/head
counter-motion, arm drift and every hanging part, for hunters and the player mannequins; `sway` in hunters/motion.py PROFILES multiplies
it per hunter. Deliberate poses (head_roll, lean, stride, emotes) are untouched.

Known: the mermaid tails (Opalie, Loxelle) still pass ~16 cm through the sprinting legs, and the extreme emote/climb/stun poses roll the
head or lift the arms into hair/wing pivots rotation cannot clear; both need the part's root moved, not just rotated.
