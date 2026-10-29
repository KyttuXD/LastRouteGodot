# Last Route agent notes

## Publishing to GitHub

- Never stage, commit, push, tag, or create a release unless the user has
  explicitly authorized that action in the current conversation.
- When a commit and push are authorized, use `scripts/push_to_github.sh` from
  the repository instead of assembling an ad-hoc Git command sequence.
- Read `scripts/PUSHING.md` before using the helper. In particular, its default
  staging mode includes every tracked and untracked path shown by
  `git status`; this repository may contain unrelated user work.
- Keep the full test run enabled unless the same working-tree revision was
  already validated and the user accepts `--skip-tests`.
- Do not force-push. If the helper reports that the remote branch diverged,
  stop and resolve it without discarding either the local or remote history.
- The helper only commits and pushes. Version bumps, tags, GitHub releases,
  and release artifacts are separate operations requiring separate user
  authorization.

## Owner standing rules

- Never change version names and never convert debug branch/builds to release
  unless KT XD explicitly says so in the current conversation.
- Whenever LastRouteGodot changes on GitHub, also update the local checkout at
  `C:\Users\Kyttu\Documents\Game Stuff\LastRouteGodot` so it stays current.
  Pull or fetch from GitHub into that tree. Do not invent a local-edit
  workflow that bypasses GitHub.

## Ongoing handoff notes

These notes reflect current `main` after
https://github.com/KyttuXD/LastRouteGodot/pull/1 (merged 2026-08-21, merge
commit `9603a42`). Prefer extending existing deterministic templates and
catalog entries so multiplayer peers stay in sync from the same seed.

### Office suites

Anchors:

- `src/game/streamed_route_generator.gd` (`office_roles` and
  `_room_template_specs` for `office_reception`, `office_cubicles`,
  `office_job`, `office_meeting`, `private_office`)
- `src/config/room_catalog.gd` (`office` room type props, surface parents,
  `officePrinter` not solid)

Default four-room office suites assign `office_reception`, `cubicle_room`,
`office_job`, and `private_office`. The `office_meeting` recipe and
`meeting_room` → `office_meeting` mapping still exist in the generator, but
meeting rooms are not a default suite amenity. Do not silently put
`meeting_room` back into `office_roles`.

`office_job` must keep a real center desk, a filing cabinet, and computers
seated on desks/workstations. Surface `mount_y` matches catalog desk height
`0.78` (`RoomCatalog.SURFACE_HEIGHTS` for `officeDesk` and
`officeCornerWorkstation`). Surface computers and printers must share a cell
with a legal parent from `SURFACE_PARENT_TYPES`. `officePrinter` is a surface
prop (`RoomCatalog.is_solid` returns false), not a solid collider.

Photocopier, shredder, file boxes, and the L-shaped corner workstation already
have authored GLBs, `PropModelCatalog` variants, footprints, and template use
(`officePhotocopier`, `officeShredder`, `officeFileBoxes`,
`officeCornerWorkstation`). Do not stub or alias them.

### Prison chunks

Prison chunks spawn generated `region_props` first, then the cell-block
dresser (`StreamedFacilityView3D` chunk build phase 4). The dresser is extra
presentation for `prison_cell` rooms and must not replace cafeteria furniture
or other authored dressing.

`prison_cafeteria` templates must keep dedicated bolted table/bench units
(`prisonCafeteriaTable`), a guarded serving counter, tray return, and kitchen
rack. Do not restore restaurant/kitchen silhouettes in
`REGION_PROP_SETS["prison"]`. Skip `prison_cell` rooms in fallback scatter so
the view dresser owns those interiors.

Residential `bunkBed` selects distinct metal, wood, and loft-bed GLBs;
`prisonBunk` remains only the institutional prison-cell model.

### Still-valid contracts

- Empty picture/painting frame GLBs get a deterministic white canvas at
  runtime via `StreamedFacilityView3D._add_blank_frame_canvas()`. Keep the
  authored frame mesh and canvas separate so future artwork can replace only
  the child surface without re-exporting every frame model.
- The office family has coordinated neutral, charcoal, and teal GLB variants.
  Keep every office type in `COORDINATED_SET_TYPES`, keep the three
  `VARIANT_THEMES` arrays in identical order, and add any future office finish
  to every silhouette so one generated room cannot mix unrelated palettes.
- Stair flights occupy the full `stair_path_cells()` span. `_fixtures()` and
  `_pickups()` use `_stair_door_exclusion(stairs)` rather than excluding only
  each stair anchor, preventing props, relays, batteries, and tools from
  spawning on treads or the upper landing.
- Never add a room/custom-map prop type without a real authored asset. The
  required chain is builder in `tools/props/rebuild_hytale_props.py`, source
  `.blend`, exported `.glb`, Godot import, `PropModelCatalog` entry, footprint,
  and deterministic runtime placement. Do not substitute an unrelated GLB or
  leave a catalog-only placeholder.
- Regional floor dressing no longer aliases bedroom/bathroom meshes. Corridor,
  hotel, apartment, and beach types own dedicated thin GLBs. Keep their bottom
  pivots flush and rely on `FLOOR_DRESSING_Y` for the small runtime lift; do
  not thicken them into collision or return them to random maze corridors.

When Godot is available, verify office suites and prison cafeterias visually
in single-player and co-op host/client runs. Streamed/prop validators already
lock `office_job` generation, surface-parent sharing, and the prison dressing
set; do not weaken those contracts.

### Region rules

Full reference with file anchors, checklist and validators: `docs/REGION_RULES.md`.
Read it before adding a region or touching region floors, walls, ceilings or heights.

- A region id lives in about twenty tables (`REGIONS`, `region_for`, `FloorSets`,
  `RefLook.REGION_STYLE`/`ARCH_ACCENT`, `RefDecor.STYLE`, ambience, map colours,
  swatch PNGs, validators). Follow the numbered checklist; do not add a region
  half-wired.
- Data vs code: `data/regions/<id>.json` (`lr.region/1`) holds only `hall_floor`,
  `hall_runner`, `room_default_floor`, `room_roles`, `shop_names`, `room_door`,
  `double_room_door`, `prop_set`. Algorithms stay code and are named, never
  scripted. Unknown keys are errors; packs never carry code. Only `mall` is
  migrated (`_CODE_*` + `ContentRegistry.DATA` + `resolve()` + `watch()`).
- Same seed, same world on every peer: only `SeededRandom` with a new tag or
  `RefLook.pick` with a new salt. Append new entries at the END of ordered
  tables. A longer table still re-rolls `% size` draws, so a hash change must be
  deliberate and stated.
- Surfaces are procedural: 32 texels/m, nearest-filtered, `_rng("<unique key>")`
  per painter; floors 32x32, walls 32x128 (one 4 m storey with cornice 10 / rail
  70 / skirt 8 px bands), ceilings 32x32. Append to `FLOOR_/WALL_/CEILING_PAINTERS`
  (layer = key order). No imported textures for built-in surfaces; unknown kinds
  fall back silently to layer 0.
- Matte only: values from `MaterialLook` (roughness >= .55, metallic <= .4,
  specular <= .35). Each new floor kind needs a `SurfaceSounds.FLOOR_KINDS` entry.
- Floors: one kind per room, one per hall chunk (`FloorSets`); `REGION_STYLE`
  floor lists are unread. Walls follow the space they face. Coordinated colour
  sets never mix palettes in one room.
- Heights: `ROOM_RANGE` 3.7-4.4, `CORRIDOR_RANGE` 4.0-4.6, `HALL_ROOMS` 4.8-6.0,
  glasshouses 6.4-7.5, `MAX_HEIGHT` 7.5. Keep ordinary ceilings <= 4.6 m
  (`TALL_ROOM`): vent ducts hang at `VentNetwork.DUCT_FLOOR` 2.7 m, and taller
  halls show them.
- Props and dressing need real authored assets (chain above). Hunter-scale aisles
  >= 1.4 m. Region names stay admin-only (`RegionNames`).
- Validators: texture change `material_look wall_themes ambience data_packs
  streamed_world coplanar`; new region add `regions_<id> data_regions room_sizes
  hallways connectivity density door_clearance ceiling_gaps`.
