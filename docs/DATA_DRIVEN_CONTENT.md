# Data-driven content (props, regions, hunters)

Status: Phase 1 design note (DATA lane). Nothing here changes runtime yet.

## Goal

Move prop, region (biome/level) and hunter definitions out of GDScript
constants into data files with one registry per kind. Behaviour must stay
identical: same seed, same chunk, same output. Later, the same path loads
player content packs from `user://mods/` in private rooms only. Packs carry
data and assets. They never carry scripts.

## Format: JSON, not `.tres`

Recommendation: **JSON files**, parsed into plain typed definition objects
(`RefCounted` classes) by our own loader.

- A `.tres`/`.res` file can embed or reference a `Script` and runs it on
  load. Loading one from `user://mods` means running mod code. Scrubbing
  that is fragile. JSON cannot carry code.
- Using one format for built-in and mod content keeps one code path, and the
  validators then test exactly what mods will hit.
- JSON diffs and union-merges cleanly, which matters with six lanes editing
  world generation.
- Encrypted Player Release builds: `res://data/**/*.json` sits inside the
  PCK like everything else. `export_presets.cfg` currently has empty
  `encryption_include_filters`. When encryption is turned on, the filter must
  include `data/*` (or `*`). The loader reads through `FileAccess`, which
  decrypts transparently. That export change is release work, so it needs
  KT's sign-off and is not part of this lane.
- Editor ergonomics: an optional `@tool` inspector can come later. Data stays
  JSON.

Types that JSON cannot express are encoded explicitly and validated:
`Vector3` → `[x, y, z]`, `Vector2i` → `[x, y]`, `Color` → `"#rrggbb"`.

## Layout

```
res://data/
  props/<family>.json        # one file per prop family (office, mall, sewer…)
  regions/<region>.json      # one file per region
  hunters/<id>.json          # one file per hunter
user://mods/<pack_id>/
  pack.json                  # manifest
  props/ regions/ hunters/   # same schemas as built-in content
  assets/                    # .glb, .png, .ogg only
```

## Schemas (v1)

Each file begins with `"schema": "lr.prop/1"` (or `lr.region/1`,
`lr.hunter/1`). Unknown keys are an error, not a silent skip, so typos fail
loudly. Any field that is missing takes the value it has today in GDScript.

### Prop (`lr.prop/1`). A file holds a family: `{"schema", "family", "props": [...]}`

| field | today's source | notes |
|---|---|---|
| `id` | catalog key (`officeDesk`) | unique across all packs, `[A-Za-z0-9_]` |
| `models` | `PropModelCatalog.MODEL_PATHS` | list of paths; picked by `_stable_index` |
| `footprint` `[w,d]` | `RoomCatalog.FOOTPRINTS` | cells |
| `size` `[x,y,z]` | `REGION_PROP_SETS` / `PropColliderSizes` | metres, hunter scale |
| `solid` | `RoomCatalog.is_solid` | bool |
| `mount` | wall/ceiling/floor_dressing/surface/floor | replaces the five type lists |
| `surface_height` | `SURFACE_HEIGHTS` | only when it acts as a surface parent |
| `surface_parents` | `SURFACE_PARENT_TYPES` | for surface props |
| `variant_set` / `themes` | `COORDINATED_SET_TYPES`, `VARIANT_THEMES` | themes stay in the same order across a set |
| `interaction` | `interaction_for()` | enum string |
| `light` | `LIGHT_PROFILES` | optional |
| `keeps_authored_pivot` | `keeps_authored_pivot()` | bool |

### Region (`lr.region/1`)

`id`, `display_name` (`region_names.gd`), `floor` and `runner`
(`floor_sets.gd`), `wall_theme`, `color`, `default_room_type`
(`REGION_DEFAULT_TYPE`), `room_door` / `double_door` (the generator's door
maps), `room_roles` (for example `MALL_ROOMS`), `room_templates` (the
template specs used by this region, by id), `prop_set` (the
`REGION_PROP_SETS` entry: `[{type, size, solid}]`), `finish`
(`REGION_FINISHES`), `budgets` (overrides for per-chunk prop and light counts).

Generator *algorithms* (stairs, arches, cell-block dresser, placement
clearance) stay in code. Regions select and parametrise them by name, for
example `"dresser": "prison_cell_block"`. This keeps sewer, inferno and prison
logic with their lanes.

### Hunter (`lr.hunter/1`)

`id`, `name`, `tier`, `speed`, `chase`, `prog`, `sight`, `hearing`, `spawn`
(`HunterRoster.PROFILES`), `eye_glow` (a `Color`), `aliases`
(`hunter_id_aliases.gd`), `pools` (`a_z`, `void`, `office_void`, `special`),
`vision` (`hunter_vision.gd`), `emote_personality`, `dossier` (text),
`model` (body GLB or blocky rig id), `scale` (default 2.67 m), `behaviour`.

`behaviour` names an ability script that ships with the game, for example
`"ravelle_traps"`. Mod hunters may only reuse built-in behaviours with tuned
numbers. That is how "hunter variants" work without script mods.

## Registry and loader API

```gdscript
# src/data/content_registry.gd (autoload: Content)
Content.props   : PropRegistry
Content.regions : RegionRegistry
Content.hunters : HunterRegistry

registry.get_def(id) -> Def        # null + push_error on miss
registry.has(id) -> bool
registry.ids() -> PackedStringArray  # sorted, stable across peers
registry.source_of(id) -> String    # "builtin" or pack_id

Content.load_builtin()                    # at boot: res://data
Content.load_packs(pack_ids: Array) -> LoadReport   # private rooms only
Content.unload_packs()                    # back to the built-in-only state
Content.pack_hash() -> String
```

Existing APIs stay as thin wrappers during the migration.
`HunterRoster.PROFILES[id]` becomes `HunterRoster.profile(id)`, which reads
from `Content.hunters`. `RoomCatalog.footprint()`,
`PropModelCatalog.model_path()` and the others keep their signatures, so call
sites in other lanes do not change. The `const` dictionaries are deleted only
once nothing reads them.

Load order: built-in content, then packs sorted by `pack_id`. A pack may
**add** ids. It may **override** a built-in id only if its manifest lists the
id under `"overrides"`. Two packs that override the same id is an error.

## Validation

There are two layers. Both run in the loader (which produces the
`LoadReport`) and in the new suites `data_props`, `data_regions` and
`data_hunters`.

1. **Schema.** Required fields, types, enums, id uniqueness, unknown keys,
   and cross-references: every `prop_set.type`, `room_templates` entry,
   `surface_parents` entry and `behaviour` must resolve. Each error names the
   file, the JSON path and the problem, for example
   `mall.json: prop_set[3].type "kioskCart" is not a known prop`.
2. **Generate-and-check.** For each region, generate N fixed seeds × K chunks
   headless and assert:
   - **Reachability:** every room and stair is flood-fill reachable from the
     entry at hunter clearance.
   - **Door clearance at hunter scale:** a 2.67 m hunter capsule fits through
     every door. Reuse the `PlacementClearance` keep-clear zones and the
     `DOORWAY_CLEARANCE.md` rules.
   - **Budgets:** props, lights and colliders per chunk stay within the
     STREAM/PERF limits. Read those limits from PERF's constants rather than
     copying them.
   - **Surface props** share a cell with a legal parent, and `mount_y`
     matches `surface_height`.
   - **Determinism:** two runs with the same seed hash identically. During
     migration, the data path must also hash identically to the old
     GDScript path. That parity check is what proves "no visible change".
3. **Bad assets.** A missing or unloadable GLB is a hard error in
   `res://` content (so the suite fails). In a mod pack it disables only that
   prop and logs it in `LoadReport`. The room falls back to "no prop" and
   never substitutes an unrelated mesh, which follows the AGENTS.md rule.
   Mod GLBs load through `GLTFDocument` at runtime. The loader keeps
   meshes, materials and textures and drops any scripts or extensions. Size
   caps apply per file and per pack.

## Built-in content and mod packs share one path

Built-in data is simply the pack `builtin` with root `res://data`. The
loader, the validators and the registries all treat it the same way. Mod
packs add three things on top: a manifest (`pack.json`: `id`, `name`,
`version`, `schema`, `overrides`), assets rooted in `user://`, and the
error-isolation rule above. The game only offers mods in private rooms, and
the hub never applies them to public or ranked play.

## Multiplayer pack hash

Each peer computes `pack_hash` from the sorted list of `(pack_id, version,
sha256 of every file)`, built-in content included, so that a client with
mismatched data also shows up. The host sends its hash and pack list in the
join handshake. A client with a different hash is refused before it
generates anything, and is told which packs differ. Generation is seeded, so
an identical hash plus an identical seed gives an identical world. Mod
downloads from the host are out of scope for v1, and players install packs
themselves. The anti-cheat work in the WORLD lane can reuse the built-in
hash.

## Migration order (avoiding other lanes)

Each step is one small commit with a parity test. The old constants stay
until all readers have moved.

1. **Loader, registries, schema validators and empty `res://data`.** These
   are new files only. The one touch to a shared file is a union-merged
   suite-list entry in `scripts/validate_runner.gd`.
2. **Pilot hunter: Dovelle** (the `DEFAULT_ID`). Its profile moves to JSON,
   and `HunterRoster` reads the registry for that id. No lane is editing
   hunter tuning right now.
3. **Pilot prop family: office.** It is stable, fully specified in
   AGENTS.md, and outside the PROPS lane's seats/rescale work. Footprint,
   model, surface and variant data move to JSON.
4. **Pilot region: Mall.** Its floor set, doors, `MALL_ROOMS`, prop set and
   templates move to JSON. The generator reads `Content.regions.get_def("mall")`
   only at the places where it reads mall constants today. The parity hash
   must match the old path.
5. **Remaining hunters**, in batches (the A–Z roster, then the void and
   special pools).
6. **Remaining regions.** Do the quiet ones first: hospital, lab,
   greenhouse, hotel, apartment and office. Leave **sewer, inferno, the new
   biomes and mansion/carnival until those lanes land** and have been
   merged to main. Then coordinate with each lane to get a frozen window.
7. **Remaining prop families**, leaving **seats and anything being
   rescaled until PROPS lands**.
8. **Delete the old constants** once nothing reads them.
9. **Mod packs.** Add `user://mods` discovery, the manifest, the pack hash
   handshake, and the private-room UI.

Steps 1–4 are Phase 2 of this lane. Steps 5–8 are Phase 3. Step 9 comes
later and is not started without KT's go-ahead.

## Open questions for KT and the coordinator

- Should packs be allowed to override built-in ids, or only add new ones?
  The proposal is overrides only when the manifest declares them.
- Should the world-generation budgets live in PERF's code or in region data?
  The proposal is that PERF owns the defaults and regions may only lower them.
