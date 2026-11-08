# Data-driven content (props, regions, hunters)

Status: Phase 1 design note. Nothing here changes runtime yet.

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
- JSON diffs and union-merges cleanly, which matters with several contributors editing
  world generation.
- Encrypted Player Release builds: `res://data/**/*.json` sits inside the
  PCK like everything else. `export_presets.cfg` currently has empty
  `encryption_include_filters`. When encryption is turned on, the filter must
  include `data/*` (or `*`). The loader reads through `FileAccess`, which
  decrypts transparently. That export change is release work and needs
  the maintainer's sign-off.
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
user://mods/<pack_id>/       # hand-installed packs
  pack.json                  # manifest
  props/ regions/ hunters/   # same schemas as built-in content
  assets/                    # .glb, .png, .ogg only
user://mods/.cache/<sha256>/ # downloaded packs (step 10), same layout
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
| `light` | `LIGHT_PROFILES` (now `_CODE_LIGHT_PROFILES` -> data, 094) | optional `{color: "rrggbb", energy 0-2, range 0.1-8, offset? [x,y,z] (default [0,.5,0]; y = the old `height`), shadows? (false), type? ("omni")}`. Absent = no light. `ContentRegistry._convert_light` checks it; `PropModelCatalog.light_profile()` reads it; `data_props` pins the 14 built-in lights to the old constant |
| `keeps_authored_pivot` | `keeps_authored_pivot()` | bool |
| `batchable` | (new) | optional bool; absent = `PropModelCatalog.is_batchable()` default: pure dressing true, interactive (`interaction_for` non-empty) false. Animated props set it false. Batching goes into MultiMesh keyed by prop id + mesh, after the registry lookup, with placements unchanged |
| `hide_capacity` | (new) | optional int 1–2; runners a hiding prop holds at once (`HideOccupancy`, docs/HIDING_PROPS.md). Absent = 1; the wardrobes set 2 |

### Region (`lr.region/1`)

`id`, `display_name` (`region_names.gd`), `floor` and `runner`
(`floor_sets.gd`), `wall_theme` (built as its own kinds instead: `region_themes` / `room_themes`, docs/WALL_THEMES.md), `color`, `default_room_type`
(`REGION_DEFAULT_TYPE`), `room_door` / `double_door` (the generator's door
maps), `room_roles` (for example `MALL_ROOMS`), `room_templates` (the
template specs used by this region, by id), `prop_set` (the
`REGION_PROP_SETS` entry: `[{type, size, solid}]`), `finish`
(`REGION_FINISHES`), `budgets` (overrides for per-chunk prop and light counts).

Generator *algorithms* (stairs, arches, cell-block dresser, placement
clearance) stay in code. Regions select and parametrise them by name, for
example `"dresser": "prison_cell_block"`. This keeps sewer, inferno and prison
logic with their own systems.

### Hunter (`lr.hunter/1`)

`id`, `name`, `tier`, `speed`, `chase`, `prog`, `sight`, `hearing`, `spawn`
(`HunterRoster.PROFILES`), `eye_glow` (a `Color`), `aliases`
(`hunter_id_aliases.gd`), `pools` (`a_z`, `void`, `office_void`, `special`),
`vision` (`hunter_vision.gd`), `emote_personality`, `dossier` (text),
`model` (body GLB or blocky rig id), `scale` (default 2.67 m), `behaviour`,
`chase_style` (optional; how she runs in a chase, one of `HunterChaseStyle.STYLES`
with an optional `:variant`, for example `"reach2"` or `"pump:fast"`; absent or
unknown means `"pump"`).

Hit immunity (both optional booleans; `HunterRoster.taser_immune` and `HunterRoster.melee_immune` read them):
`taser_immune` (default `true`) means a taser beam does not stun her: it slows her instead. Her movement speed is
multiplied by `taser_slow_factor` (0.5) for `taser_slow_seconds` (3.0), the difficulty profile values in
`game/config/game_config.gd` (the same in every mode). She keeps hunting, searching and wandering, with no stun and no
change to her hide checks or perception. The host sends no message for a slowed hit (the stun message is still sent
for a non-immune hit). A running slow keeps the stronger factor and the longer time. `melee_immune` (default `false`)
means a crowbar or axe hit does nothing to her, and the host says `<CROWBAR|AXE> // NO EFFECT ON <NAME>`. Every built-in
hunter file states both (`true` and `false`). A pack hunter that leaves them out takes the defaults, so an older pack
behaves as before. A hunter with no profile (a secret creature) has no immunity. Her own slowdown is optional:
`taser_slow_factor` and `taser_slow_seconds` (floats) replace the profile values for her alone
(`HunterRoster.taser_slow_factor` / `taser_slow_seconds`); a pack that leaves them out gets the profile values. The host decides the hit. A stun
replicates as `stun` and `stun_kind`; a slowdown replicates as `slow_timer` and `slow_factor` (the hunter state and
the hunter report), so guests see the same slowed hunter.

`behaviour` names an ability script that ships with the game, for example
`"ravelle_traps"`. Mod hunters may only reuse built-in behaviours with tuned
numbers. That is how "hunter variants" work without script mods.

## Registry and loader API

As built in Phase 2, this is a static class, `ContentRegistry`
(`game/config/content_registry.gd`), rather than an autoload. The config
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
# mod packs (step 9, built):
ContentRegistry.load_packs(dirs) -> {ok, packs, errors, hash}  # all or nothing, replaces the loaded set
ContentRegistry.unload_packs()                               # back to exactly the built-in game
ContentRegistry.pack_hash() / builtin_pack_hash() -> String
ContentRegistry.loaded_packs() -> [{id, name, version, author, sha256, dir}]
ContentRegistry.pack_of(kind, id) / added_ids(kind)
ContentRegistry.pack_scene(path) / pack_texture(path)        # runtime glTF / PNG, only inside a loaded pack
ContentRegistry.watch(rebuild) -> true                       # readers register their rebuild
ContentPacks.discover() / read(dir)                          # game/config/content_packs.gd
```

### Mod packs as built (step 9, loader)

- **Ids.** A pack's new ids must start with `<pack_id>_`, so they can never
  collide with the game or with another pack. A pack replaces a built-in id
  only when `pack.json` lists it under `"overrides"` as `"<kind>/<id>"`, and
  only one loaded pack may override a given id. Prop families are namespaced
  internally as `<pack_id>:<family>`, so a pack prop never joins a built-in
  coordinated set.
- **Tables.** `resolve()` gives an overridden key the pack's definition (an
  optional field the override leaves out falls back to the built-in value)
  and appends ids that packs added after the code keys, sorted. With no pack
  loaded the tables are the code tables exactly; `data_packs` compares every
  table and the three parity hashes before loading and after unloading.
- **Readers rebuild themselves.** `HunterRoster`, `PropModelCatalog`,
  `FloorSets` and `StreamedRouteGenerator` register `rebuild_from_registry()`
  with `ContentRegistry.watch()`, and `ModelSlot` registers
  `clear_material_caches()`. The registry never names its readers, so there
  is no class-loading cycle, and a reader loaded after packs builds from them.
- **Hunters.** Pack hunters join the seeded draw (`HunterRoster.DRAW_IDS` =
  `IMPLEMENTED_IDS` + pack hunters, so vanilla draws are unchanged), run the
  default chase behaviour on their own tuning, and must be in a drawn tier.
  `model` is a pack `.glb` or a shipped hunter body under
  `res://assets/hunters_blocky/`;
  `portrait` is a pack `.png` or a shipped portrait.
- **Models.** `ModelSlot.instantiate()` sends every `user://` path to
  `ContentRegistry.pack_scene()`: `GLTFDocument` at runtime, then every node
  that is not a mesh, skeleton, bone attachment or animation player is
  dropped and every script cleared. A model outside a loaded pack is refused.
  `PropModelCatalog.model_path()` lets a prop override win over the blocky
  substitutes.
- **Regions.** Overrides of built-in regions (for example `mall`) work now.
  A pack region with a new id registers and validates, but no level draws it
  until levels are data (`lr.level/1`). A region's `prop_set` only dresses
  rooms without a furniture template, and every mall role has one, so a pack
  prop shows up in the world through a prop override (it replaces the model
  wherever the game places that prop) until room templates are data too.

### Rooms (step 9, hot-swap)

- `RoomPacks` (`game/network/room_packs.gd`) holds the room rules;
  `RoomState` only calls it. `Settings.mods_enabled` lists the pack ids a
  player's private rooms use (`[mods] enabled` in settings.cfg).
- **Host.** `host_room()` and `enter()` call `RoomPacks.host_load()`: a public
  route unloads every pack; a private room loads the enabled packs, and a run
  does not start while they fail to load (the reason is the room status).
- **Guests.** `broadcast()` sends `_receive_packs(announce())` ahead of
  `_receive_room`. The guest finds each pack locally by id and sha256
  (`user://mods/<id>` or `user://mods/.cache/<sha256>`), loads them, and checks
  that its `pack_hash()` now equals the host's. Otherwise it leaves before
  generating anything, with `MODS DIFFER // MISSING <name> <version>` (or the
  load error) as the status; a public route whose host hash is not the
  built-in one is refused outright.
- **Leaving.** `leave_network()` (which every new, joined or hosted room goes
  through first) and a dropped connection unload every pack. A reconnect
  grace period keeps them.
- `data_hotswap` runs vanilla -> modded -> vanilla -> another modded room ->
  vanilla in one process through these calls, checks tables and parity hashes
  after each return, generate-and-checks each modded mall, counts objects and
  resources across repeated modded rooms, and drives the guest handshake
  (adopt, refuse a modded public route, name a missing pack).

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
     doorway clearance rules.
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
   never substitutes an unrelated mesh.
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
packs" below. The anti-cheat work in the world code can reuse the built-in
hash.

## Auto-download of packs (at the player's own risk)

Goal: players can download mods automatically, at their own risk.

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

### Transfer source: the file host serves the files, the backend holds the index

Pack files are hosted on a separate **file host**. The game backend does not serve pack files. Host over
ENet is not used either, because all co-op traffic already runs through the
backend relay (UDP 1105).

- **File host.** Every pack archive is stored on and downloaded from
  the file host. Anything over 1 MB must be there, and tiny packs live there too so
  there is one rule. Storage is content-addressed (`<sha256>.zip`) and
  immutable, so it can be cached publicly behind a CDN.
- **Backend (index and moderation).** The backend keeps only the pack index (id,
  version, sha256, size, author account, upload time), the moderation state
  and blocks, and per-account quotas. When a room is joined, the backend returns
  the room's pack list with a **download URL on the file host** for each pack.
- **Upload.** The host asks the backend for an upload slot (an authenticated
  account, quota checked). The backend issues a short-lived signed upload URL on
  the file host. After the upload, the file host (or a backend job) recomputes the sha256 and
  runs the validator rules. Only then does the backend publish the index entry.
- **Download check.** Clients verify the sha256 **from the backend's index**
  before opening anything they downloaded from the file host. A mismatch throws the
  file away and cancels the join. The file host is never trusted on its own.
- **No hardcoded hosts.** The file host and the backend API base URLs come
  from config: the backend endpoint config the client already reads, and
  the download URLs the backend hands out. Source code never names a host.
  The signing secrets live only on the servers, never in the repo or the
  client.

Limits for v1. These are proposals.

| limit | value |
|---|---|
| per file | 16 MB |
| per pack (zip, compressed) | 64 MB; uncompressed ≤ 128 MB |
| packs per room | 8, total ≤ 192 MB |
| uploads per account | 10 per day, 512 MB stored per account |
| file host storage quota | set to fit the file host's disk, with LRU eviction of packs no room has used in 30 days |
| download rate | 4 MB/s per client, 20 concurrent downloads per server |

Bandwidth: the backend now carries only small index and moderation JSON
responses, so mod downloads add next to nothing to the game backend. Pack
bytes leave from the file host, with the CDN in front of it. In the worst case, a
room of 4 guests pulling a 64 MB pack costs about 256 MB of file-host egress
with no cache hit.

### Safety rules (the loader enforces them, and the server does too on upload)

- **Data plus assets only.** Allowed extensions are `.json`, `.glb`, `.png`,
  and `.ogg` (`ContentPacks.ASSET_EXTENSIONS`). Any other file, including `.gd`, `.tres`, `.res`,
  `.wav`, `.tscn`, `.gdextension`, `.so`, `.dll` and `.pck`, causes the **whole
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

### Downloads as built (step 10, client side)

- `PackDownloads` (`game/network/pack_downloads.gd`) is the mod UI's provider
  (`ModPackApi.provider`): `installed_packs()`, `remove_downloaded()`
  and `download_packs()`. `RoomState` installs it, and hands a private room's
  missing packs to the lobby's `ModJoinDialog` (confirm or auto-download,
  progress, cancel); the guest stays in staging until `RoomPacks.adopt()`
  succeeds, and a cancel leaves the room.
- For each missing pack it asks the backend index
  (`<backend>/api/mods/packs/<id>?version=<v>`) and refuses a blocked pack, a
  file list whose paths or sizes this loader would refuse, and a list whose
  identity sha (the same formula as `ContentPacks.read()`) is not the host's.
  Files are fetched one by one from the index's `downloadBase`
  (`<base>/<id>/<version>/<path>`, file host) -- packs are plain file trees, not
  archives -- each checked against the index's size and sha256, into
  `user://mods/.cache/.download-<sha>`, read back as a pack, and only then
  renamed to `.cache/<sha>`. Any failure deletes the staging folder.
- `data_downloads` runs this against a local stand-in for the index and file
  host (download, reuse, remove, tampered file, blocked, wrong version, path
  escape). `tools/build/pack_smoke.sh` runs the room handshake between two real
  processes.

### Cache

- `user://mods/.cache/` holds downloaded packs keyed by sha256. `index.json`
  records `last_used`, size and source.
- LRU cleanup removes the least recently used packs once the cache goes
  over 1 GB, which players can change. Packs the current room needs are
  never evicted.
- Settings → Online has a **REMOVE DOWNLOADED MODS** button with a confirm
  step. It deletes `user://mods/.cache/`; hand-installed packs in
  `user://mods/<pack_id>/` stay.

### Owner moderation

- Blocking works like skin removal. Owners block a pack sha256 (and, if
  they choose, every pack from an author account) from the hub ADMIN
  panel. the backend stops handing out its URL (451), the file host deletes the stored
  copy.
- Clients fetch the blocklist with the update manifest. A blocked hash is
  never loaded, even from the local cache, and the guest sees the reason
  "Removed by moderators". A host whose room uses a blocked pack cannot
  open the room until the pack is removed.
- Uploads record the account id, so a block can trace back to the
  uploader. No credentials or tokens are stored in packs or in the cache.

## Migration order

Each step is one small commit with a parity test. The old constants stay
until all readers have moved.

1. **Loader, registries, schema validators and empty `res://data`.** These
   are new files only. The one touch to a shared file is a union-merged
   suite-list entry in `tests/validate_runner.gd`.
2. **Pilot hunter: Dovelle** (the `DEFAULT_ID`). Its profile moves to JSON,
   and `HunterRoster` reads the registry for that id. Nothing else is editing
   hunter tuning right now.
3. **Pilot prop family: office.** It is stable, fully specified
   and outside the seats/rescale work. Footprint,
   model, surface and variant data move to JSON.
4. **Pilot region: Mall.** Its floor set, doors, `MALL_ROOMS`, prop set and
   templates move to JSON. The generator reads `Content.regions.get_def("mall")`
   only at the places where it reads mall constants today. The parity hash
   must match the old path.
5. **Remaining hunters**, in batches (the A–Z roster, then the void and
   special pools).
6. **Remaining regions.** Do the quiet ones first: hospital, lab,
   greenhouse, hotel, apartment and office. Leave **sewer, inferno, the new
   regions and mansion/carnival until those systems land** and have been
   merged to main. Then pick a frozen window for each.
7. **Remaining prop families**, leaving **seats and anything being
   rescaled until that work lands**.
8. **Delete the old constants** once nothing reads them.
9. **Mod packs.** Add `user://mods` discovery, the manifest, the pack hash
   handshake, and the private-room UI.
10. **Auto-download.** Add the backend index and file-host endpoints, the client downloader and
    cache, the setting and confirm screen, and the owner blocklist.

Steps 1–4 are Phase 2 of this work. Steps 5–8 are Phase 3. Steps 9–10 come
later and is not started without the maintainer's go-ahead.

## Open questions

- Should packs be allowed to override built-in ids, or only add new ones?
  The proposal is overrides only when the manifest declares them.
- Should the world-generation budgets live in code or in region data?
  The proposal is that code owns the defaults and regions may only lower them.

## Room recipes (`lr.room/1`): design, not built yet

A room recipe furnishes one room type (a ward, a bedroom, the mall's music_store). Today every recipe is a
branch of `StreamedRouteGenerator._room_template_specs()` (about 1,200 lines shared by several systems). Data
recipes let packs add shop and room roles and place new props, which nothing else can do.

### Axes and units

Recipes use the generator's own spec frame, in **cells**:
- `depth` runs from the **back wall** (`0`, the first interior row) to the **front** row, `front = depth_span - 3`,
  whose middle cell is the entrance (it is always kept clear, `_keep_entrance_clear`). The entrance wall is the one
  the room's door (the corridor connection the layout gives it) sits in; a room with a second door or an archway still
  has one entrance for the recipe frame, and other openings are kept clear by the same placement code.
- `side` runs across the room; `0` is the centre column (for an even width, the column left of centre, as the code
  rounds), `half = side_span / 2`. The room's seeded `mirror` (+1/-1) multiplies `side` unless `"mirror": false`.
- `facing`: `open` (towards the entrance), `back`, `left`, `right`, `center` (towards the room centre).
- Size-relative positions are strings: `back`, `front`, `mid` (= `depth_span / 2`), `half`, and offsets on them:
  `"front-1"`, `"half-1"`, `"-half+1"`.
- A range `"side": [from, to, step]` places one item per value from `from` up to and excluding `to` (like `range()`),
  bounds may be size-relative (`["-half+1", "half", 3]`); mirroring applies to each placed value after the step.

### What a recipe is

The generator already reduces every recipe to a list of specs `{type, side, depth, facing, wall_backed?, wall_mount?,
solid?, mount_y?}`; a data recipe is that list plus the few conditions the code uses:

```json
{"schema": "lr.room/1", "id": "mypack_record_shop",
 "items": [
	{"type": "checkoutCounter", "side": -2, "depth": "front-1", "wall_backed": false, "facing": "open"},
	{"type": ["mypack_rack_a", "mypack_rack_b"], "side": ["-half+1", "half", 3], "depth": "back", "wall_backed": true},
	{"type": "@rug", "side": 0, "depth": "mid", "solid": false, "when": {"min_side": 9}},
	{"choose": [{"type": "guitarWallHanger", "weight": 3}, {"type": "@painting", "weight": 1}],
	 "side": 0, "depth": "back", "wall_mount": true, "solid": false, "when": {"chance": 0.5}}
 ]}
```

- `type`: a prop id; a **list** on a range item cycles by index (`types[i % n]`, no draw).
- `@frame`, `@painting`, `@rug`: the region's own frame/painting/rug type; the item is skipped where the region has none.
- `when`: `min_side`, `max_side`, `min_depth`, `max_depth`, `chance`; all must hold.
- `choose`: a weighted pick.
- `mount_y` is in metres (world scale); surface parents (a mic on a desk) are not in v1 -- recipes that need them stay
  code until the field is designed.
- Placement (clearance, door keep-clear, wall snapping, colliders) is the generator's existing code, unchanged.

### Determinism

- Data recipes draw from **their own** stream, `SeededRandom("%s:ROOMDATA:%s" % [seed, room_id])`, never the room's
  rng, so editing a data recipe can never shift a later code draw (pickups, hiding spots, dressing).
- Every `chance` and every `choose` consumes **exactly one** draw in item order, **even when** its size condition fails
  or placement refuses the item. Range items with a `chance` draw once per placed value. Host and guest therefore get
  the same room whatever their room sizes or clearance results.

### What recipes may place

- Only plain props: no interactables. Hiding spots and lockers, music boxes, relays, pickups, ladders and vents stay
  placed by the game (lockers carry inspect and vent logic; pickup and relay plans take free floor cells).
- Every prop needs a footprint the generator knows (a collider size or a declared size), so clearance never works on
  an unknown footprint.
- Recipes never apply to safe rooms, sealed-wing seal cells, or stairwell and ladder footprints.

### Ids, roles and the code hand-off

- Built-in data recipes keep their plain id (`music_store`); the `<pack>_` prefix is only for pack recipes.
- Where a room appears is decided by the region's `room_roles` alone (mall.json stays the single source); a recipe has
  no region list.
- A data recipe is used only where no code branch exists, so moving a built-in recipe to data removes its code branch
  (e.g. `MusicWing.TEMPLATES` and its match arm for music_store) **in the same commit** that adds the JSON.
- Pack recipes override built-in data recipes through `overrides` (`rooms/<type>`); code recipes cannot be overridden.

### Validation (`data_rooms`)

For every data recipe, over N seeds and every room size its roles get: all items placed or deliberately skipped, no
overlaps, entrance clear, every floor cell reachable for players **and** for hunter navigation
(StreamedHunterNavigation), at least 4 free reachable floor cells left (relay chunks need 2-3) for pickups and relays,
sizes per the size table, and the defining props of the room type (the KEY_PROPS of validate_regions and the owning
room's recipe checks) present. Determinism: two generations hash equal. Hot-swap: recipes rebuild through
`ContentRegistry.watch()`, and a world is generated after its packs load, so no chunk mixes recipe sets.

### Order and coordination

1. Interpreter plus the `rooms/` pack kind, used only for room types with no code branch. No built-in change; parity
   identical. Suite data_rooms.
2. **Done:** music_store as the first data recipe (`data/rooms/music_store.json`), as one joint commit with MUSIC (JSON in, code branch out); its key props and
   MUSIC's recipe checks keep passing.
3. Optional migration of simple built-in recipes, one region at a time, in frozen windows with BIOMES (layouts),
   WORLD (doors, archways, sizes; a window for any region with hiding spots near doors) and MUSIC, parity hash per
   region. Recipes with computed loops or derived edges (music_stage, dining rows) keep a named code `"layout"`.
4. Levels (`lr.level/1`, the level-0 pilot already approved) come after, so pack regions can be placed.

## Loot tables (`lr.loot/1`): built (loot slice)

What a chunk's pickups are moved out of `StreamedRouteGenerator._pickups` / `pick_tool`, `SewerRouteGenerator._pickups`
and `GameConfig.STIM_PACK_CHANCE` / `REVIVE_KIT_CHANCE_*` into `res://data/loot/{route,sewer}.json`, an extension kind
(`res://data/kinds/loot.json`) whose reader and validator is `LootTables` (`game/world/interactables/loot_tables.gd`).

- **Split.** The generators keep where pickups lie (free cells, stair and seal exclusions) and the objective: the
  relays, the sealed wing's bonus relay and guaranteed tool (`SealRules`), the sewer's second relay
  (`SEWER_EXTRA_RELAY_CHANCE`). A table gives `base` kinds, `rolls` (`{kind, chance}`), `tools` (`{item, weight}`),
  `backpacks` (by depth rank) and `aid` (`{item, chance, chance_coop?}`, on the chunk's own aid stream).
- **Determinism.** Every roll is one draw of the chunk's stream in file order, the tool pick one draw, the backpack
  rank one draw, exactly as the code was; weights are only scaled when they do not sum to 1, so the shipped weights
  run the old arithmetic. `data_loot` replays the old code against the table for 3000 seeds and prints
  `Parity.loot_hash()` (staging 29b79686 and after the move: `ff29abcc6793cf9e`).
- **Packs.** `"overrides": ["loot/route"]` (or `loot/sewer`) replaces a built-in table; a new `<pack>_<name>` table with
  `"regions": [...]` loots those regions instead (first by id wins). Only the built-in kinds (`battery`, `coin`,
  `tool`, `backpack`) and items (`LootTables.TOOL_ITEMS`, `BACKPACK_ITEMS`) are allowed; relays and new items are
  refused. `StreamedRouteGenerator.PICKUP_TYPES` / `PICKUP_WEIGHTS` mirror the `route` table and rebuild on load and
  unload.

## Extension kinds (other systems' data)

A system owner that owns a system can make it data-driven and moddable without editing the registry:

1. Declare the kinds in `res://data/kinds/<owner>.json`:
   `{"nw_offices": {"schema": "nw.office/1", "root": "res://data/night_watch/offices", "validator": "res://game/night_watch/data/nw_schemas.gd"}}`.
   The registry reads every file there before anything else, so the kinds exist before any pack is read.
2. Write the validator: `static func validate(kind: String, entry: Dictionary, where: String) -> PackedStringArray`
   (errors naming `where` and the field; empty = valid). `entry` is the file minus `schema`, `id` included.
3. Put built-in files under `root`, one definition per file: `{"schema", "id", ...}`.
4. Read with `ContentRegistry.get_def(kind, id)` / `ids(kind)`, and register a rebuild with `ContentRegistry.watch()`.

The registry does the rest the same way as for its own kinds: ids, `<pack>_` prefixes for new pack content,
`overrides` for built-in ids, all-or-nothing loading, the pack hash, hot-swap. An optional `"assets": {"<field>": "<extension>"}` in the declaration names fields that hold a pack file
(`"assets/..."`); the pack loader checks the file is in the pack and makes the path absolute, while shipped `res://`
values are left to the validator. The player skins kind (`data/kinds/player_skins.json`, `SkinCatalog`) uses it for its
`image`. Packs ship the kind as a folder of
the same name; `ContentRegistry.pack_kinds()` lists every kind a pack may contain (the starter kit and the index use it).
