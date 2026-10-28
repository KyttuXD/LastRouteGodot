# Data-driven content (props, regions, hunters)

Status: Phase 1 design note (DATA lane). Nothing here changes runtime yet.

## Goal

Move prop, region (region/level) and hunter definitions out of GDScript
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
| `batchable` | (new) | optional bool; absent = `PropModelCatalog.is_batchable()` default: pure dressing true, interactive (`interaction_for` non-empty) false. Animated props set it false. PERF batches into MultiMesh keyed by prop id + mesh, after the registry lookup, with placements unchanged |

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

As built in Phase 2, this is a static class, `ContentRegistry`
(`src/config/content_registry.gd`), rather than an autoload. The config
classes that read it (`HunterRoster`, `PropModelCatalog`, `FloorSets`,
`StreamedRouteGenerator`) are static, and leaving it out of autoloads also
keeps `project.godot` untouched.

```gdscript
ContentRegistry.get_def(kind, id) -> Dictionary   # {} when missing
ContentRegistry.has(kind, id) -> bool
ContentRegistry.ids(kind) -> PackedStringArray    # sorted, stable across peers
ContentRegistry.family(name) -> Array             # prop ids of one family, file order
ContentRegistry.errors() -> PackedStringArray
ContentRegistry.parse_file(path, kind) -> {defs, errors}
ContentRegistry.resolve(code_table, kind, field)  # fill ContentRegistry.DATA entries
ContentRegistry.splice(code_array, flag)          # "@data:<family>" -> that family's ids
# later, for mod packs (step 9):
ContentRegistry.load_packs(pack_ids) -> LoadReport
ContentRegistry.unload_packs()
ContentRegistry.pack_hash() -> String
```

Migrating a table works like this. The old `const NAME` becomes
`const _CODE_NAME`, and each migrated entry's value becomes
`ContentRegistry.DATA`. A `static var NAME` holds the resolved table.
Readers keep using `NAME`, and key order is preserved. The `_CODE_`
tables are deleted once every entry in them is data.

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
an identical hash plus an identical seed gives an identical world. Packs a guest is missing are fetched as described in "Auto-download of
packs" below. The anti-cheat work in the WORLD lane can reuse the built-in
hash.

## Auto-download of packs (at the player's own risk)

KT's request: players can download mods automatically, at their own risk.

### Flow

1. The host's join handshake sends a pack list
   `[{pack_id, version, name, author, size, sha256}]` plus `pack_hash`.
2. The guest compares that list with its local cache. Packs it already has
   (matched by sha256) are used as they are.
3. **The setting "Auto-download mods — at your own risk"** is in
   Settings → Online and is **off by default**:
   - **Off:** the guest sees a confirm screen listing each missing pack's
     name, author, size and short hash, with the warning "Mods are made by
     other players. They contain data and assets only, but Kyttu's Lab does
     not review them. Download at your own risk." The guest chooses
     DOWNLOAD & JOIN or CANCEL. A "don't ask again" tick on that screen turns
     the setting on.
   - **On:** missing packs download without asking. A HUD line names each
     pack, and the own-risk notice shows once per session.
4. The guest downloads, verifies and loads the packs. The client checks that
   `pack_hash` now equals the host's, then generation starts. If anything
   fails, the join is cancelled with the reason. The guest never joins with
   a partial pack set.
5. This only applies in private rooms. Public and ranked rooms refuse any
   pack hash other than the built-in one.

### Transfer source: VPS 2 hosts the files, VPS 3 holds the index

KT ruled that pack files are hosted primarily on **VPS 2**, which is the
file host. VPS 3, the game backend, does not serve pack files. Host over
ENet is not used either, because all co-op traffic already runs through the
VPS 3 relay (UDP 1105).

- **VPS 2 (files).** Every pack archive is stored on and downloaded from
  VPS 2. Anything over 1 MB must be there, and tiny packs live there too so
  there is one rule. Storage is content-addressed (`<sha256>.zip`) and
  immutable, so it can be cached publicly behind a CDN.
- **VPS 3 (index and moderation).** VPS 3 keeps only the pack index (id,
  version, sha256, size, author account, upload time), the moderation state
  and blocks, and per-account quotas. When a room is joined, VPS 3 returns
  the room's pack list with a **download URL on VPS 2** for each pack.
- **Upload.** The host asks VPS 3 for an upload slot (an authenticated
  account, quota checked). VPS 3 issues a short-lived signed upload URL on
  VPS 2. After the upload, VPS 2 (or a VPS 3 job) recomputes the sha256 and
  runs the validator rules. Only then does VPS 3 publish the index entry.
- **Download check.** Clients verify the sha256 **from VPS 3's index**
  before opening anything they downloaded from VPS 2. A mismatch throws the
  file away and cancels the join. VPS 2 is never trusted on its own.
- **No hardcoded hosts.** The VPS 2 file host and VPS 3 API base URLs come
  from config: the backend endpoint config the client already reads, and
  the download URLs VPS 3 hands out. Source code never names a host.
  The signing secrets live only on the servers, never in the repo or the
  client.

Limits for v1. These are proposals for KT to confirm.

| limit | value |
|---|---|
| per file | 16 MB |
| per pack (zip, compressed) | 64 MB; uncompressed ≤ 128 MB |
| packs per room | 8, total ≤ 192 MB |
| uploads per account | 10 per day, 512 MB stored per account |
| VPS 2 storage quota | set to fit VPS 2's disk, with LRU eviction of packs no room has used in 30 days |
| download rate | 4 MB/s per client, 20 concurrent downloads per server |

Bandwidth: VPS 3 now carries only small index and moderation JSON
responses, so mod downloads add next to nothing to the game backend. Pack
bytes leave from VPS 2, with the CDN in front of it. In the worst case, a
room of 4 guests pulling a 64 MB pack costs about 256 MB of VPS 2 egress
with no cache hit.

### Safety rules (the loader enforces them, and the server does too on upload)

- **Data plus assets only.** Allowed extensions are `.json`, `.glb`, `.png`,
  `.ogg` and `.wav`. Any other file, including `.gd`, `.tres`, `.res`,
  `.tscn`, `.gdextension`, `.so`, `.dll` and `.pck`, causes the **whole
  pack to be rejected**. GLBs load through `GLTFDocument`, and any scripts or
  extensions inside them are dropped.
- **Hash first.** The archive's sha256 must match the handshake hash
  before the archive is opened at all.
- **Extraction.** Files are extracted only under
  `user://mods/<sha256>/`. Each entry path is normalised, and the pack is
  rejected if a path is absolute, contains `..`, is a symlink, has a drive
  letter or backslash, or has a duplicate name after case folding. The
  per-file and total uncompressed caps are checked during extraction, which
  also guards against zip bombs. Extraction first goes to a temp directory,
  which is renamed into place only once everything has passed.
- **Malformed files.** Bad JSON, a broken GLB or a bad image rejects that
  pack with a `LoadReport` entry. It never crashes the game and never
  partially loads the pack. The guest's join fails cleanly with the reason.

### No restart, ever (hard requirement)

Joining or leaving a modded room never needs a game restart.

- Packs load when a room is joined and unload when it is left, through
  `ContentRegistry.load_packs()` / `unload_packs()`. Every resolved table
  (`HunterRoster.PROFILES`, `PropModelCatalog.MODEL_PATHS`,
  `StreamedRouteGenerator.REGION_PROP_SETS` and the others) is rebuilt from
  the registry at load and at unload. Because these are `static var`s
  rather than consts, they can be reassigned.
- `ProjectSettings.load_resource_pack()` is **never** used for mods, because
  a resource pack cannot be unloaded. Mods are JSON plus runtime loads from
  `user://`: `GLTFDocument` for models, `Image.load_from_file` for textures
  and `AudioStreamOggVorbis.load_from_file` for audio. None of these go
  through `ResourceLoader`, so nothing is cached under `res://` paths.
- Unload frees every mesh, texture and audio stream a pack created. It also
  clears every cache keyed by mod ids: the prop model cache, materials,
  hunter rigs and collider boxes.
- Pack downloads happen inside the join flow and show a progress bar. A
  failed or cancelled download leaves the game in the vanilla state.
- **`data_hotswap` suite**, all in one process:
  1. Boot vanilla.
  2. Join a modded room. The pack loads and its region generates and
     passes the generate-and-check rules.
  3. Leave, then join a vanilla room. The vanilla parity hashes must equal
     a fresh boot's, with no leaked mod ids in any table and no leaked
     resources (object and resource counts are back to their earlier
     values).
  4. Join a different modded room and check it the same way.

  This suite ships with step 9, together with `load_packs`/`unload_packs`.

### Cache

- `user://mods/` holds packs keyed by sha256. `index.json` records
  `last_used`, size and source.
- LRU cleanup removes the least recently used packs once the cache goes
  over 1 GB, which players can change. Packs the current room needs are
  never evicted.
- Settings → Online has a **REMOVE DOWNLOADED MODS** button with a confirm
  step. It deletes everything under `user://mods/` that the player did not
  install by hand. Hand-installed packs live in `user://mods/local/`.

### Owner moderation

- Blocking works like skin removal. Owners block a pack sha256 (and, if
  they choose, every pack from an author account) from the hub ADMIN
  panel. VPS 3 stops handing out its URL (451), VPS 2 deletes the stored
  copy.
- Clients fetch the blocklist with the update manifest. A blocked hash is
  never loaded, even from the local cache, and the guest sees the reason
  "Removed by moderators". A host whose room uses a blocked pack cannot
  open the room until the pack is removed.
- Uploads record the account id, so a block can trace back to the
  uploader. No credentials or tokens are stored in packs or in the cache.

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
   regions and mansion/carnival until those lanes land** and have been
   merged to main. Then coordinate with each lane to get a frozen window.
7. **Remaining prop families**, leaving **seats and anything being
   rescaled until PROPS lands**.
8. **Delete the old constants** once nothing reads them.
9. **Mod packs.** Add `user://mods` discovery, the manifest, the pack hash
   handshake, and the private-room UI.
10. **Auto-download.** Add the VPS 3 index and VPS 2 file endpoints, the client downloader and
    cache, the setting and confirm screen, and the owner blocklist.

Steps 1–4 are Phase 2 of this lane. Steps 5–8 are Phase 3. Steps 9–10 come
later and is not started without KT's go-ahead.

## Open questions for KT and the coordinator

- Should packs be allowed to override built-in ids, or only add new ones?
  The proposal is overrides only when the manifest declares them.
- Should the world-generation budgets live in PERF's code or in region data?
  The proposal is that PERF owns the defaults and regions may only lower them.
