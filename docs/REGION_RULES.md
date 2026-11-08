# Region rules: making, texturing and tuning a region

The durable reference for adding a region (district) or re-texturing one. Written from the code on `staging` at
`df2ca2d3` (2026-10-29). Anchors are `file:line` at that commit and drift; search for the symbol name. Nothing here
was run: Godot was not available, so "what a validator locks" comes from reading the scripts. Section 8 lists what
could not be verified.

Companion docs: [DATA_DRIVEN_CONTENT.md](DATA_DRIVEN_CONTENT.md) (registry, packs), [modding/content-types.md](modding/content-types.md)
(player-facing schemas), [WALL_THEMES.md](WALL_THEMES.md), [MATERIAL_LOOK.md](MATERIAL_LOOK.md),
[ROOM_SIZES.md](ROOM_SIZES.md), [VENTS.md](VENTS.md).

## 0. The rules on one screen

1. Built-in surfaces are painted in code (`RefTextures`), 32 texels per metre, nearest-filtered, seeded per kind. No imported textures.
2. A prop, room type or region dressing item needs a real authored asset. No aliases, no catalog-only placeholders.
3. Same seed, same world, on every peer: draw only from `SeededRandom("<seed>:TAG:<id>")` or `RefLook.pick(x, z, salt, n)`; no global RNG, time or frame state in generation.
4. Region data is JSON (`lr.region/1`); algorithms stay code and are selected by name. Packs never carry code. Unknown keys are errors.
5. Append new entries at the END of every ordered table (see 3.5 for what that does and does not protect).
6. Surfaces stay matte: roughness >= 0.55, metallic <= 0.4, specular <= 0.35, light specular <= 0.3; take values from `MaterialLook`, never literals.
7. One floor kind per room, one hall floor per chunk (never per cell). Walls take the theme of the space they FACE.
8. A coordinated colour set must not mix palettes inside one room (office neutral/charcoal/teal, same `VARIANT_THEMES` order).
9. Ceilings: ordinary rooms and corridors stay <= 4.6 m (`TALL_ROOM`); only named `HALL_ROOMS` (4.8-6.0) and glasshouses (6.4-7.5) go taller; nothing exceeds `RefLook.MAX_HEIGHT` 7.5 m.
10. Every new floor kind needs a footstep surface; every new region needs an ambience bed, map colour, swatch PNG pair and a place in the validators.
11. Region names are admin-only UI text (`RegionNames.visible()`); players see `LEVEL n`.
12. Do not change version names or convert debug builds.

## 1. Where a region lives today

A region id is a string key in about twenty tables. Only the Mall's slice of them is data so far.

| Concern | Anchor | Data or code |
|---|---|---|
| Region list (also `ContentRegistry._CODE_IDS["regions"]`) | `streamed_route_generator.gd:29` `REGIONS` | code |
| Placement per 4x4-chunk block | `streamed_route_generator.gd:1195` `region_for`, `choices` at `:1217` (weights = repeats) | code |
| Top-level-only regions | `TOP_LEVEL_ONLY_REGIONS` (`greenhouse`), `_pick_region` / `region_allowed_at` / `highest_level_at` next to `region_for`: never on level 0 or below, only on the highest level `is_chunk_allowed` admits in that column (+1 over a deck/void). A disallowed first draw is redrawn on the same stream, so other regions keep their places. Since the void/mezzanine was removed (`VoidRegion.ENABLED`, `StreamedRouteGenerator.MEZZANINE_ENABLED` both false) no column has a level above 0, so `highest_level_at` is 0 everywhere and **no greenhouse is generated anywhere** until a placement is decided | code |
| Void / Mezzanine (removed) | `VoidRegion.ENABLED := false` (no void column, chunk, tower or `"mezzanine"` region), `MEZZANINE_ENABLED := false` (no +1 chunk, deck patch or stairwell up; `top_level()` is 0, the view clamps there). Generators and view code stay in the tree, dead; `void`, `mezzanine_view`, `deck_patches`, `upper_levels` suites now guard the removal. Void hunters/powers are separate and unchanged | code |
| Layout class | `:63` `DENSE_DISTRICTS`, `:60` `LINEAR_REGIONS`, `:67/:69` `BANK_BIG_CHANCE/TYPES`, `:99/:101` `LARGE_ROOM_CHANCE/TYPES`, `:1775` `WARREN_REGIONS`; `_dense_linear_layout` `:1982` (mall/maze special cases `:1999`, `:2090`) | code |
| Room roles | `:80-84` `HOSPITAL_ROOMS/LAB_ROOMS/GREENHOUSE_ROOMS`; `:89-90` `MALL_ROOMS/SHOP_NAMES` (from JSON); `_room_type_choices` `:2155`; `_room_type_for` `:2691` | code (mall roles: JSON) |
| Furnished-room dispatch and recipes | `_furnished_room_props` `:2998` (region list `:3068`), `_room_template_specs` `:3570`, `_region_room_specs` `:4279`, `REGION_REPEAT_TEMPLATES` `:93`, `RoomRecipes` (`game/world/generation/room_recipes.gd`, `data/rooms/`), `MusicWing` hook `:3071` | code, or `lr.room/1` for types with no code recipe |
| Loose dressing | `_CODE_REGION_PROP_SETS` `:124` -> `REGION_PROP_SETS` `:263`; scatter in `_region_props` `:2764` (skips templated rooms, `stairwell`, `prison_cell`) | code (mall: JSON `prop_set`) |
| Room doors | `_CODE_REGION_ROOM_DOORS` `:247`, `..._DOUBLE_...` `:255`; `_room_door_props` `:4987` (no entry = no door props) | code (mall: JSON) |
| Floors (live) | `floor_sets.gd:11` `_CODE_HALLS`, `:29` `_CODE_ROOM_DEFAULT`, `:63` `ROOMS` (per room purpose), `room_kind` `:131` | code (mall halls/default: JSON) |
| Walls and ceiling kind (live) | `data/themes/regions/<id>.json` (`wall`, `ceiling`), `data/themes/rooms/<purpose>.json` (`wall`), built into `RefLook.REGION_STYLE` / `ROOM_STYLE`; `wall_kind` | data (`lr.region_theme/1`, `lr.room_theme/1`) |
| Arch/pilaster trim | `accent` in `data/themes/regions/<id>.json` -> `RefLook.ARCH_ACCENT` (falls back to maze) | data |
| Painters | `ref_textures.gd:937/:960/:978` `FLOOR_/WALL_/CEILING_PAINTERS` | code |
| Heights | `ref_look.gd:293-307` ranges and room lists, `room_range` `:324` | code |
| Lamps, tint, wall extras | `ref_decor.gd:596` `STYLE` (falls back to maze) | code |
| Prop finish per region | `finish` in `data/themes/regions/<id>.json` -> `PropModelCatalog.REGION_FINISHES` (mansion only) | data |
| Ambience | `ambience_table.gd:12` `_beds`, `ambience_synth.gd:34` `SPACE_OF`, `surface_sounds.gd:10` `FLOOR_KINDS` | code |
| Map / catalog | `facility_map.gd:29` `REGION_COLORS`, `room_catalog.gd:300` `REGION_DEFAULT_TYPE`, `:624` `color_for_region`, `room_size_profiles.gd:12` `PROFILES` | code |
| View block colours + swatch PNGs | `streamed_facility_view_3d.gd:89/:104` `REGION_COLORS/REGION_WALL_COLORS`; PNGs `assets/environment/floor_<id>.png`, `wall_<id>.png` baked by `tools/environment/bake_block_textures.gd:17` | code + baked PNG |
| Region JSON | `data/regions/<id>.json`, schema `content_registry.gd:48` `REGION_FIELDS` | data |

Not regions, do not add to `REGIONS`: `sewer`, `mezzanine`/void, `inferno` caves (level-driven in `region_for`), though
`REGION_STYLE`, `ARCH_ACCENT` and `STYLE` carry `sewer` and `inferno` entries.

**Stale floor lists.** `REGION_STYLE[...]["corridor"/"room"/"runner"]` and `ROOM_STYLE[...]["floor"]` have no reader (grep:
only `wall_kind`, the view's `ceiling` lookups, `geometry_audit.gd:317` for `runner`, and `validate_wall_themes` read these
tables). Floors come from `FloorSets`. Edit `FloorSets` to change a floor; fill the legacy keys only to keep the table's shape.

## 2. Checklist: a new region, end to end

Order matters: assets and painters first, tables second, generator third, tests last. `<id>` = the region id.

**A. Assets (no region without them)**
1. Each new prop type: builder in `tools/props/` (shop/room props live in `blocky_props_<region>.py`, emitted by `emit_models.py`;
   `rebuild_hytale_props.py` builds the game objects), source `.blend`, exported `.glb`, Godot import
   (`godot --headless --path . --import`), `game/config/blocky_prop_models.gd`, a `data/props/<family>.json` entry (`lr.prop/1`:
   `models`, optional `themes`/`coordinated`/`batchable`/`size`), footprint `room_catalog.gd:403` `FOOTPRINTS`, collider
   `prop_collider_sizes.gd:95` (`tools/props/emit_collider_sizes.tscn`), wall-mounted/floor-dressing lists in `prop_model_catalog.gd` if thin.
2. Check sizes against `data/scale/prop_size_ranges.json` (hunter factor 1.5; `scale_fit`, `data_props`).

**B. Surfaces**
3. New kinds (only if the existing ones do not fit): painter `_paint_*` + entries appended to `FLOOR_PAINTERS` / `WALL_PAINTERS` /
   `CEILING_PAINTERS` (`ref_textures.gd`). Rules in section 4.
4. Footstep surface for every new floor kind: `surface_sounds.gd:10` `FLOOR_KINDS` (unmapped kinds step as concrete silently;
   the `ambience` suite fails them). Soft/metal response only if needed: `material_look.gd:64` `floor_response`.
5. `FloorSets`: `_CODE_HALLS[<id>]` (floor kinds, runner bool), `_CODE_ROOM_DEFAULT[<id>]`, and a `ROOMS[<purpose>]` entry for **every**
   room purpose the region generates (`wall_themes` fails purposes without one; `FloorSets.has_room`).
6. `data/themes/regions/<id>.json` (`wall` list, `ceiling` kind, `accent`, optional `finish`), `RefLook._CODE_REGION_STYLE[<id>]` legacy
   floor keys, optional `data/themes/rooms/<purpose>.json` wall overrides (docs/WALL_THEMES.md, "Themes as data").
7. Swatch pair: add `<id>` to `bake_block_textures.gd` `palettes`, run it, commit `floor_<id>.png`, `wall_<id>.png` and their `.import`
   (`validate_streamed_world` requires the pair). Add `REGION_COLORS[<id>]` and `REGION_WALL_COLORS[<id>]` in the view.

**C. Generator**
8. Append `<id>` to `REGIONS` (and to `choices` in `region_for`, with the weight you want; mind 3.5). Add to `DENSE_DISTRICTS` unless it
   is deliberately sparse (seams and great halls test `DENSE_DISTRICTS.has(neighbour)` at `:1281`, `:1308`, `:1327-1343`), and to `WARREN_REGIONS` if warrens suit it.
9. Room roles: a `<ID>_ROOMS` list (code const) or `room_roles` in JSON read through `ContentRegistry.get_def` (mall pattern `:89`,
   rebuilt in `rebuild_from_registry` `:274`); register in `_room_type_choices` `:2155` and `_room_type_for` `:2691`; bank
   specials in `BANK_BIG_*` / `LARGE_ROOM_*`; add the region to the `region in [...]` dispatch `:3068` or give the types data recipes.
10. Recipes: a `match` arm per role in `_region_room_specs` (11-wide bank frame, 1.4 m aisles, `_keep_entrance_clear`; list in
    `REGION_REPEAT_TEMPLATES` if it is laid twice across a 21-wide hall) or a `data/rooms/<role>.json` (`lr.room/1`, plain props only).
11. `REGION_PROP_SETS[<id>]` (only dresses rooms without a recipe), `REGION_ROOM_DOORS` / `..._DOUBLE_...` if it wants real doors.
12. `RoomSizeProfiles.PROFILES[<role>]` for every generated role (`room_sizes` fails rooms outside their profile);
    `RoomCatalog` entries / `REGION_DEFAULT_TYPE` / `color_for_region` for the streamed catalog.

**D. Look, sound, map**
13. `RefDecor.STYLE[<id>]` (lamp family, spacing, tint, `lit_rooms`), `AmbienceTable._beds[<id>]` (seamless loop; `ambience` renders it),
    `AmbienceSynth.SPACE_OF[<id>]`, `FacilityMap.REGION_COLORS[<id>]` (must be unique among regions).
14. Heights: add hall-type roles to `RefLook.HALL_ROOMS`, glass-roofed roles to `GLASSHOUSE_ROOMS`; check `room_range` special cases.
15. Optional: flythrough sets `playtest_flythrough.gd:19/:42` and `tools/playtest/flythrough.py:31`.

**E. Tests (section 6)**
16. Facility-style region: `validate_regions.gd` `FACILITY_REGIONS`, `KEY_PROPS` (defining props per role), `REGION_ROOM_TYPES`,
    `_expected_room_types` lists; a shard `validate_regions_<id>.gd` (copy `validate_regions_mall.gd`), the name in `validate_runner.gd`
    `SUITES` and in both `SUITE_ALIASES` (`validate_runner.gd:22`, `tools/build/run_suites.py:47`).
17. If any table moved to JSON: update the frozen copies and parity in `validate_data_regions.gd`; compare `Parity.region_hash("<id>")`
    before and after; say in the commit when a hash changes on purpose (`3acf8be2` did).

## 3. Data-driven rules

### 3.1 What goes in `data/regions/<id>.json` (`lr.region/1`)

Exactly the fields in `REGION_FIELDS` (`content_registry.gd:48`); anything else is an error naming file and key:

`hall_floor` (strings), `hall_runner` (bool), `room_default_floor` (strings), `room_roles` (strings), `shop_names` (dict, optional),
`room_door`, `double_room_door` (optional prop ids), `prop_set` (`[{type, size:[x,y,z], solid?}]`; item keys are only those three).

Wall themes are not region fields: they are the `region_themes` / `room_themes` kinds (docs/WALL_THEMES.md).
`DATA_DRIVEN_CONTENT.md` also lists `wall_theme`, `color`, `default_room_type`, `room_templates`, `finish`, `budgets` for the region
schema. **None of those exist in the loader**; writing one makes the file fail. Only `mall` is migrated; the other twelve regions are
still `_CODE_*` constants. The loader does not check floor-kind names inside `hall_floor`/`room_default_floor` (only `wall_themes`
does, for built-in tables) or that `room_roles` have recipes.

### 3.2 What stays code (selected by name, never by script)

Layout (banks, halls, great halls, warrens), room recipes with computed loops, stairs/arches/dressers (`prison_cell_block`), placement
clearance, region selection, heights, painters, decor styles, ambience. A data region may only name them; a pack cannot add them.

### 3.3 Migrating a table entry to data (the mall pattern)

Old `const NAME` -> `const _CODE_NAME`; migrated entries get the value `ContentRegistry.DATA` (`"@data"`); `static var NAME = ContentRegistry.resolve(_CODE_NAME, "regions", "<field>")`
(or `resolve_with` for tables built from several fields, `floor_sets.gd:50`); readers keep using `NAME`; key order is preserved;
register `static var _watching: bool = ContentRegistry.watch(rebuild_from_registry)` and re-resolve in `rebuild_from_registry()` so
pack load/unload rebuilds the table (`floor_sets.gd:58`, `streamed_route_generator.gd:274`). A `DATA` key with no JSON is a logged error and the key is dropped.
Resolved tables are read-only (`data_regions` asserts it). Delete `_CODE_*` only when every entry is data. One claim per commit,
equal parity hashes, or a stated intentional change.

### 3.4 Packs

Allowed files: `pack.json`, JSON in the kind folders, `.glb`/`.png`/`.ogg` under `assets/`; any script, scene or resource refuses the
whole pack (`modding/rules.md`). New ids start `<pack>_`; built-in ids change only via `overrides`. Today a pack can override a built-in
region (e.g. `regions/mall`), replace floor/wall/ceiling kinds with PNGs (`lr.surface/1`, scaled nearest to 32x32 / 32x128; roughness,
metal and the glass/vault glow stay with the kind via `RefTextures.params`; `safe*` and `runner_*` slices are locked) and add room
recipes. A pack region with a NEW id loads and validates but no level places it. The built-in hash covers every file the registry
loads from `res://data` (props, regions, hunters and declared extension kinds), so editing a region JSON changes the multiplayer
fingerprint: both peers need the same build.

### 3.5 Determinism and "append at the end"

- Chunk generation seeds from strings: `"%s:BIOME:..."` (region choice; the literal `BIOME` is part of the seed, never rename it),
  `:BANKS:`, `:ROOMS:`, `:DRESSING:`, `:TEMPLATE:`, `:VARIETY:`, `:LARGE:`, `:WARREN:`, data recipes `:ROOMDATA:` (own stream, fixed draw
  count per `chance`/`choose`). New randomness gets a NEW tag; never reuse a stream another system consumes, or later draws shift.
- View-side picks use `RefLook.pick(x, z, salt, n)`; salts in use: 1 hall floor per chunk, 2 wall kind, 7 room floor / inferno rock. Use a new salt.
- Appending protects the prefix order (`REGIONS`, `room_roles`, painter layers, `FloorSets` lists), **not the draws**: anything indexed
  `% size` or `next_index(size)` re-rolls when the length changes (`region_for` choices, mall `type_offset`/shop cycle, `FloorSets.room_kind`,
  `wall_kind`). Adding a region therefore moves existing seeds' region map, and a longer `room_roles` re-cycles shops (`3acf8be2`: parity hash changed on purpose).
  Treat that as a deliberate, announced change, never a side effect.
- Painter layers: `texture arrays = painters' key order` (`ref_textures.gd:1043`); floors and ceilings share one array
  (`FLOOR_PAINTERS.keys() + CEILING_PAINTERS.keys()`). Insert in the middle and every later layer index shifts. Lookups are by name, so a
  consistent build is safe, but append anyway and never reorder.

## 4. Texturing rules

- **Scale.** `PX = 32` texels per metre (`ref_textures.gd:13`). Floors 32x32 = one cell. Walls 32x128 (`WALL_H`) = one 4 m storey
  (`WALL_TEXTURE_SPAN` 4.0). The mesh stretches the image over each repeat of the room's height (`ref_surface_mesh.gd:96`) with
  `wall_tiers(h) = max(1, round(h / 4))`: a 4.4 m room stretches ~10%, a 6 m hall is two 3 m tiers. Design bands for 4 m.
- **Wall bands** (y from the TOP): `CORNICE_H` 10, `RAIL_Y` 70, `SKIRT_H` 8 at the bottom. Use `_wall_base`, `_rail`, `_skirt`, `_cornice`, `_grime`
  so cornice meets ceiling and skirting meets floor. Floors repeat per cell: give seams/dividers at the 32 px edge deliberately (terrazzo's brass strips).
- **Painters are pure.** Signature `_paint_x(variant: int) -> Image`; randomness only from `_rng("<unique key>%d")` (`RandomNumberGenerator`
  seeded by `hash(key)`); a reused key gives identical noise. No time, no global RNG, no loading images. Register as `"kind": [&"_paint_x", variant]`.
- **Filtering.** Textures are nearest with mipmaps (`TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC`). Painted values are deliberately
  dark: `material()` lifts floors/walls by `Color(1.4, 1.4, 1.45)`, ceilings by `(.8, .78, .85)`, the array shader tints `(1.25, 1.22, 1.3)`. Judge by an in-engine look, do not pre-brighten.
- **Which table.** Floor kind -> `FLOOR_PAINTERS` (also paving, carpets, rock). Wall kind -> `WALL_PAINTERS` (32x128). Ceiling kind ->
  `CEILING_PAINTERS` (32x32, drawn through the "floor" array; kind is per region via `REGION_STYLE.ceiling`, no per-room override found).
  A kind name may exist in two tables (`stone0` floor and wall); the group says which.
- **Unknown kinds fail quietly.** `texture()` falls back to the first painter, `layer()` to layer 0: a typo renders as `metal0` / `panel0` with no error.
  `wall_themes` checks floor kinds in `FloorSets`; nothing found checks wall/ceiling kind names, so re-read them by hand.
- **Matte.** Surfaces use `MaterialLook` only: `ROUGHNESS_MATTE` .92, `ROUGHNESS_SOFT_FLOOR` .82 (stone/parquet/check), `ROUGHNESS_METAL` .62 with
  `METALLIC_METAL` .18 (metal/hazard/grate/safe), specular .18 / .32, light specular .22. Limits enforced by `material_look`:
  roughness >= .55, metallic <= .4, specular <= .35, light specular <= .3, unless emissive, transparent glass, or named in `ALLOWED_GLOSS`.
  "Polished" terrazzo and epoxy are still matte (`floor_response` defaults); glass and vault ceilings glow via `params()`, not gloss.
- **One floor per room.** `FloorSets.room_kind` picks one kind per room keyed on its origin; `ref_floor_kind` picks one hall floor per chunk
  (`RefLook.pick(coord.x, coord.z, 1, n)`). Doorway and junction cells take the hall floor. A floor list may hold several kinds; they vary room to room.
- **Walls follow what they face** (`wall_kind`, 4-cell patches; inferno every cell). A cell belongs to a room only inside its door line.
  Arches/jambs/lintels call the same function and `RefDecor.arch_wall_material`; trim uses `ARCH_ACCENT` (brass only where the district uses it).
- **Coordinated sets.** Furniture families that share a finish hash the ROOM id, not the prop (`prop_model_catalog.gd:407-419`
  `COORDINATED_SET_TYPES`, `VARIANT_THEMES`): keep every member in the set, keep theme arrays the same length and order, add any new finish to every silhouette.
  Regional finishes (`REGION_FINISHES`, mansion) swap models by region but keep type names, footprints and colliders.
- **No imported textures for built-in surfaces** and none for props beyond their authored GLB atlas. Only packs ship PNG surfaces.
  The `floor_<id>.png` / `wall_<id>.png` swatches are baked procedurally by a tool, not hand-painted art.
- **Dressing needs real assets.** Empty frame GLBs get a runtime white canvas (`_add_blank_frame_canvas`). Thin floor dressing
  (`FLOOR_DRESSING_TYPES`) sits at `FLOOR_DRESSING_Y` .012 with a flush bottom pivot; never thicken it or scatter it in random corridors.
- **Z-fighting.** Coplanar pairs (>= 5 dm2) fail `coplanar`; keep wall-mounted pieces 6 cm off the wall face (`mount_offset`), no two surfaces on one plane.

## 5. Heights and ceilings

| Range | Value | Anchor |
|---|---|---|
| `CORRIDOR_RANGE` | 4.0-4.6 (beach/greenhouse hallways use `ROOM_RANGE`) | `ref_look.gd:294`, `room_range` `:332` |
| `ROOM_RANGE` | 3.7-4.4 (low end clears raised door frames, `DoorwayFrames.FRAME_TOP_CAP` 3.65) | `:296` |
| gothic non-hall rooms | 4.1-4.6 (crest cap 4.02) | `:328` |
| `HALL_RANGE` | 4.8-6.0 for `HALL_ROOMS` | `:297`, `:307` |
| `GREENHOUSE_RANGE` | 6.4-7.5 for `is_glasshouse` rooms | `:298`, `:314` |
| `TALL_ROOM` | 4.6: above it pendants on chains, roof ribs, tiered wall lamps | `:293`, `ref_decor.gd:355` |
| `MAX_HEIGHT` | 7.5: the wall collider height; no range may exceed it | `:299`, view `:4397` |
| `sewer` | one fixed `SewerRouteGenerator.CEILING_HEIGHT` | `:325` |

- Height is a hash of the room id (corridors: chunk coord) snapped to 0.1 m (`_ranged`): same on every peer. Changing a range moves every ceiling of that kind.
- Glasshouse rule: `is_glasshouse(region, room_type)` is true for beach cove/tide pool/hut/boardwalk and, in the greenhouse region, for
  `GLASSHOUSE_ROOMS`. Those get the tall range, greenery instead of roof ribs and the glass roof. Potting sheds and plant rooms keep an ordinary height. Do not add a role there without checking its recipe's hanging fixtures at 6.4-7.5 m.
- Vents plenum (owner's rule): storey-0 ducts run at `VentNetwork.DUCT_FLOOR` 2.7 m with their roof at the slab (3.9 m), on the lines x/z = 6 and 38 of every
  level-0 chunk (`streamed_facility_view_3d.gd:1426`, `_spawn_ducts` `:1937`; walls under a duct line are capped at 2.7 m `:1827`). Keep ordinary
  ceilings <= 4.6 m so the duct reads as hung under the ceiling; taller halls (4.8-6.0) and glasshouses will show the ducts and the gap above them. Raising
  `CORRIDOR_RANGE`/`ROOM_RANGE` maxima past 4.6 needs a look at `vents_view` and a visual pass. Upper levels are capped at `LEVEL_HEIGHT - SLAB` 3.9 (`upper_levels`).
- Hunter scale: the world is built for a 2.67 m hunter; doors need 40 cm over her head, aisles and strips beside furniture >= 1.4 m
  Rooms are never below 9x9 (`ROOM_SIZES`).
- `REF_LOOK.md` still quotes old heights (3.7 / 4.6 / 9.2 / 13.8 m and 3.0-3.6): the code constants above are the authority.

## 6. Validators for region work

Run as `godot --headless --path . res://tests/scenes/validate.tscn -- <suite> ...`; shards `name#i/n`; parallel `python3 tools/build/run_suites.py [--affected ...]`.
Never with `--script` (no autoloads). Baseline failures: `TESTING.md`.

| Suite | Locks |
|---|---|
| `data_regions` | every `data/regions` file passes the schema; `id` is in `REGIONS`; prop_set/door models exist; 4 chunks per data region are one connected open space, deterministic, props have models; mall frozen copies equal the JSON; resolved tables are read-only; bad files are rejected clearly; prints `parity regions` |
| `data_props`, `data_rooms` | prop families (models exist, finishes line up, coordinated-set order) and data recipes (placed, no overlap, entrance clear, reachable, hash-equal) |
| `data_packs`, `data_hotswap` | pack load/unload gives back the exact built-in tables and parity hashes; surface overrides; no leaked objects; guest handshake |
| `data_themes` | district/room themes equal the old constants (frozen hashes); theme pack overrides, pack themes, pack coordinated sets; exact restore; refusals |
| `regions_hospital/_lab/_greenhouse/_mall` (`regions`) | 7 seeds x radius 7: >= 6 chunks, every role generated and furnished, `KEY_PROPS` present, no solid overlaps, doorway clear, at most 2 stranded cells |
| `wall_themes` | each wall face/floor cell themed by the space it faces; doorways on the hall theme; every generated purpose has `FloorSets.ROOMS`; every district has hall+room sets; floor kinds painted; arches in wall theme with `ARCH_ACCENT` trim |
| `material_look` | all painters and the three array materials, decor, scene materials and lights stay inside the matte limits |
| `ambience` | every region has a bed, beds loop seamlessly, every floor kind has a footstep surface |
| `streamed_world` | swatch PNG pair per region, `FacilityMap.REGION_COLORS` present and unique, seams agree, determinism, ceiling-range checks for office rooms |
| `room_sizes` | each generated room inside its `RoomSizeProfiles` entry; great halls table grids |
| `hallways`, `connectivity`, `density`, `humps` | 3-wide halls never pinch, floor reachable across seams, dense districts stay dense, no wall humps (sample every `REGIONS` entry) |
| `door_clearance`, `ceiling_gaps` | hunters clear every door; no air gap over doors/walls up to the ceiling (every region) |
| `collision`, `colliders`, `geometry_overlap`, `coplanar`, `prop_coplanar` | props reachable/fitted, interpenetration ratchet, z-fighting ratchet (KNOWN = 0) |
| `ceiling_fixtures`, `light_switches` | one ceiling-fixture family per room, symmetric fixtures, switches beside doors |
| `scale_fit`, `furniture`, `bedrooms`, `hiding_props`, `prop_perf`, `stream_perf` | prop sizes at hunter scale, recipes, a bed in every bedroom, hiding spots, perf ratchets |
| `vents`, `vents_view`, `upper_levels`, `level_links` | duct geometry/headroom, upper ceilings <= 3.9, slab/seam leaks between storeys |
| `region_names` | region names shown to admins only |
| `hunter_real` | hunters do not stick on real geometry in every district |

Smallest sensible set for a texture-only change: `material_look wall_themes ambience data_packs streamed_world coplanar`.
For a new region add `regions_<id> data_regions room_sizes hallways connectivity density door_clearance ceiling_gaps geometry_overlap collision colliders ceiling_fixtures`.
Visual check (Godot windowed): `dev/look/capture.tscn`, `dev/look/chunk_map.gd`, and single-player plus co-op host/client runs.

## 7. Gotchas

- **Two `GREENHOUSE_ROOMS`.** `RefLook.GREENHOUSE_ROOMS` (beach conservatories: cove, tide_pool, ...) is not `StreamedRouteGenerator.GREENHOUSE_ROOMS` (the greenhouse region's roles). Easy to edit the wrong one.
- **Dead floor lists.** Editing `REGION_STYLE.corridor/room` or `ROOM_STYLE.floor` changes nothing; floors are `FloorSets`.
- **Per-room, not per-cell, floors.** Picking per cell checkerboarded two floors in a lab room; `room_kind` keys on the room origin.
- **Room bleed.** A room's rect includes its wall ring and door cells; ownership is the interior inside the door line (`f6e36aa3`). Do not theme halls from room data.
- **Mall roles are JSON but mall branches are code.** `MALL_ROOMS`/`SHOP_NAMES` read `get_def("regions", "mall")` by name; a second data region needs its own reader and rebuild hook. Adding a role to `room_roles` also needs a recipe, a `PROFILES` entry, `FloorSets.ROOMS`, `KEY_PROPS` and the frozen copy in `validate_data_regions` or the `regions_mall` shards fail (`3acf8be2`).
- **Frozen copies.** `validate_data_regions.gd` keeps the mall constants on purpose; update them in the same commit as the JSON.
- **New floor kind, silent concrete steps.** Unmapped kinds step as concrete until the `ambience` suite complains (inferno rock needed a follow-up, `b9a924a1`; terrazzo had its own, `e86ab5f4`).
- **One broken painter breaks every surface.** `ref_textures.gd` is one class; a parse/type error anywhere in it takes all floors, walls and ceilings
  down (the terrazzo painter once failed to compile over a chip colour's type, `b80ba595`). Type locals explicitly (`var chip: Color = ...`).
- **Wall colliders are 7.5 m.** Ceilings above `MAX_HEIGHT` leave gaps above the colliders.
- **Banks are 8 deep in the maze** (5-wide centre hall): recipes tuned to 9-deep banks (restaurant rows) do not fit; `WARREN_ROOM_EXCLUDE` keeps `ward`/`pod_room` in banks.
- **Hunter-scale furniture.** Beds, benches and counters need >= 1.4 m strips to a wall or the room counts stranded floor (ICU beds and night-diner counters: `97e2ced5`, `dccae4f3`; ward bedside kit a row out: `7368e3cc`).
- **Seat reservations.** Seats moved in front of screens carry their occupied cell (`c24a81a5`: 772 lab rooms had stale reservations).
- **Beds.** Every bedroom-purpose room must end up with a bed (`4a25c281`, `bedrooms` suite).
- **Dangling doc references.** Generator comments cite `docs/REGIONS.md` and `docs/BIOMES.md`; neither exists. `biomes` is only a legacy suite alias for the four region shards.
- **Region names are admin-only** (`073aca05`): route any new UI string through `RegionNames`.
- **Music wing / office suite / carousel** live inside bank chunks of their regions (`MUSIC_WING_REGIONS` hotel, maze office quarter, carnival big top). A new great-hall type in those regions must leave them alone.
- **Stale numbers in older docs** (`REF_LOOK.md` heights, `WALL_THEMES.md` district table lacks the newer regions). Trust code.
- **Regenerate imports.** After adding GLBs, PNGs or a `class_name` script run `godot --headless --path . --import` or scripts fail with `Identifier "X" not declared`.

## 8. Not verified from code

- The `<= 4.6 m` plenum limit is the owner's rule; the code only shows `TALL_ROOM` 4.6, the range maxima, and ducts at 2.7-3.9 m. No validator asserts it.
- `DATA_DRIVEN_CONTENT.md` region fields beyond `REGION_FIELDS` and "room_templates"/"finish"/"budgets" are design text; not built.
- Whether wall/ceiling kind typos in `REGION_STYLE`/`ROOM_STYLE` are caught by any suite (none found).
- Whether `REGIONS` additions are safe for saved worlds: generation is seed-derived, so existing seeds re-roll their region map (3.5); persistence of that was not checked.
- `rebuild_hytale_props.py` builds game objects (coin, vent, locker, relay); region room props were built by `blocky_props_<region>.py`.
