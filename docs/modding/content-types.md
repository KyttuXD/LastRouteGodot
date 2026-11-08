# Content types

Every file starts with `"schema"`. Unknown fields are errors. Numbers below give the range the built-in content uses
as a guide; they are not hard limits unless stated.

## Props

A prop file holds one family of props:

```json
{"schema": "lr.prop/1", "family": "lamps", "props": [
	{"id": "mypack_lamp", "models": ["assets/lamp.glb"]}
]}
```

| field | required | meaning |
|---|---|---|
| `id` | yes | `<pack id>_<name>` for a new prop, or a built-in id listed in `overrides` |
| `models` | yes | one or more `.glb` files under `assets/`. Each placement picks one of them, the same one for everyone in the room. |
| `themes` | no | one label per model, same order (finish sets such as `neutral`/`charcoal`/`teal`). Give it when overriding a themed built-in prop. |
| `coordinated` | no | built-in finish sets only; pack props never join a built-in coordinated set |
| `batchable` | no | `false` for anything animated or interactive; the default draws repeated plain props together |
| `size` | for room recipes | `[x, y, z]` metres at game scale: the footprint a room recipe places your prop with |
| `light` | no | the light the prop gives off, for lamps and glowing signs. See below. Leave it out for no light. |

Where props show up:
- An **override** replaces the model of a built-in prop everywhere the game already places it. This is the reliable
  way to change what players see (the Ember pack recolours every office printer).
- A **new prop** appears through a [room recipe](#rooms) (give it a `size`), or a region's `prop_set`, which only
  dresses rooms that have no recipe.

A prop `light` is plain data, no scripts:

```json
"light": {"color": "ffd99a", "energy": 0.38, "range": 3.0, "offset": [0, 0.54, 0], "shadows": false, "type": "omni"}
```

| key | required | meaning |
|---|---|---|
| `color` | yes | hex colour, `rrggbb` (a leading `#` is fine) |
| `energy` | yes | brightness, 0 to 2. Built-in lamps sit between 0.18 and 0.85. |
| `range` | yes | metres the light reaches, 0.1 to 8 |
| `offset` | no | `[x, y, z]` metres from the model's origin, y up, at most 4 m each way. x and z turn with the prop. Default `[0, 0.5, 0]`. |
| `shadows` | no | `true` casts shadows. Default `false`. Only the small finite maps honour it: the streamed world lends a few shared shadowless lights to the lamps nearest you. |
| `type` | no | `"omni"`, the only kind so far |

Overriding a built-in lamp and leaving `light` out keeps its built-in light. Lights stay inside each map's lamp budget,
so a pack cannot add more lights than the game already allows.

Models are built for the game's scale: the world is laid out for a 2.67 m hunter, about 1.5x a person. A chair seat
sits where a hunter sits. `modpack.sh validate` checks every prop against its size category (person-scale range
x 1.5) once the size table ships, and refuses a model with no mesh.

## Hunters

```json
{"schema": "lr.hunter/1", "id": "mypack_runner", "name": "Runner", "tier": "easy",
 "speed": 0.82, "chase": 3.6, "prog": 0.18, "sight": 8.0, "hearing": 1.0, "spawn": 12,
 "model": "res://assets/hunters_blocky/glyra/glyra.glb", "chase_style": "lope"}
```

| field | required | meaning (built-in range) |
|---|---|---|
| `name` | yes | display name |
| `tier` | yes | `easy`, `intermediate` or `difficult` for pack hunters. The route draws a tier by difficulty weights, then a hunter from that tier, from the seed. |
| `speed` | yes | walking speed multiplier (built-in files: 0.77–1.02) |
| `chase` | yes | chase speed (built-in files: 2.75–4.9) |
| `prog` | yes | how fast the chase builds up (built-in files: 0.12–0.30) |
| `sight` | yes | sight range (built-in files: 6.72–10.0) |
| `hearing` | yes | hearing scale; 1.0 is normal, 0 is deaf (built-in files: 0–1.38) |
| `spawn` | yes | whole number: spawn distance from the runner (built-in files: 10–17) |
| `model` | no | a `.glb` in the pack, or a shipped body: `res://assets/hunters_blocky/<hunter>/<hunter>.glb` (the old `res://assets/characters/` bodies are retired) |
| `portrait` | no | a `.png` in the pack, or a shipped `res://assets/ui/hunter_portraits/<hunter>.png` |
| `chase_style` | no | how the body moves when chasing: `reach2`, `reach1`, `pump`, `lope`, `glide`, `skitter`, `stalk`, `stopstart`, optionally `:<variant>`. Unknown values fall back to `pump`. |
| `taser_immune` | no | `true` or `false`: a taser beam slows her instead of stunning her (movement speed x the difficulty's `taser_slow_factor`, 0.5, for `taser_slow_seconds`, 3.0). Absent means `true`. Every built-in file states it. |
| `melee_immune` | no | `true` or `false`: a crowbar or axe hit does nothing to her. Absent means `false`. Every built-in file states it. |
| `taser_slow_factor` | no | a number: her own taser slowdown factor (movement speed multiplier), in place of the difficulty's `taser_slow_factor`. Absent means the difficulty's value. Only used while she is taser immune. |
| `taser_slow_seconds` | no | a number: her own taser slowdown length in seconds, in place of the difficulty's `taser_slow_seconds`. Absent means the difficulty's value. |
| `category` | no | built-in use (`void`); leave it out |

New hunters run the default chase behaviour on their own numbers. Built-in hunters' special abilities belong to
their ids, so a variant of Aki is a new hunter wearing Aki's body, not Aki. Overriding a built-in id (listed in
`overrides`) retunes that hunter and keeps its abilities.

## Regions

Overrides of built-in regions work now (for example `mall`). Copy the built-in file from the game's `data/regions/`
as a starting point.

| field | required | meaning |
|---|---|---|
| `hall_floor` | yes | floor kinds for halls, e.g. `["terrazzo0", "terrazzo1"]` |
| `hall_runner` | yes | `true` to lay a carpet runner down halls |
| `room_default_floor` | yes | floor kinds for rooms without their own |
| `room_roles` | yes | room types the region cycles through. Only room types the game knows (they need a furniture recipe). |
| `shop_names` | no | sign text per role, e.g. `{"donut_shop": "DONUT COUNTER"}` |
| `room_door`, `double_room_door` | no | door prop ids |
| `prop_set` | yes | `[{"type": <prop id>, "size": [x, y, z], "solid": true}]` loose dressing for rooms without a recipe; sizes in metres |

Floor kinds: `metal0-3 grate hazard floral0-1 star0-1 carpet_red carpet_teal carpet_green carpet_plum carpet_tile0-1
runner parquet0-1 check0-1 vinyl0-1 stone0-2 rock0-2 concrete0-1 epoxy0-1 terracotta0-1 terrazzo0-1`.

A region with a new id loads and validates, but no level places it until levels become a pack type.

## Grabs

How a hunter takes hold of a runner it has caught: a weighted pool of grab styles, one file per hunter. On a catch the
game drops the styles the surroundings rule out (a lift under a low ceiling, a wall pin with no wall) and picks one of
the rest, the same one for everyone in the room. The animations themselves are built in; a pack chooses which ones a
hunter uses and how often.

```json
{"schema": "lr.grab/1", "id": "mypack_runner", "pool": {"shoulder_grab": 3, "tackle": 1}, "look": {"delay": 0.5}}
```

| field | required | meaning |
|---|---|---|
| `id` | yes | the hunter: one of your pack's hunters, or a built-in hunter listed in `overrides` as `"grabs/<id>"` |
| `pool` | yes | style: weight (positive numbers). Styles: `neck_lift`, `shoulder_grab`, `tackle`, `wrist_yank`, `wrap`, `leg_grab`, `upside_down`, `shoulder_carry`, `collar_drag`, `wall_pin`, `pounce_pin` (creature rigs only). New styles are added from time to time; an unknown style is refused with its name. |
| `look` | no | how the head follows the runner: `yaw`, `up`, `down` (degrees), `chest` (0-1 share), `delay` (seconds before looking), `forward` ([x, y, z]) |

A hunter without a pool uses the shoulder grab. The built-in pools are in the game's `data/grabs/`.

## Sounds and ambience

The game makes its sounds itself (synthesized cues and looping background beds). A pack can replace any of them with
its own `.ogg` recordings. Both folders use the same file shape:

```json
{"schema": "lr.sound/1", "sounds": [
	{"id": "alert", "files": ["assets/alert_a.ogg", "assets/alert_b.ogg"], "gain_db": -3}
]}
```

| field | required | meaning |
|---|---|---|
| `id` | yes | the built-in sound, listed in `overrides`: `"sounds/<cue>"` or `"ambience/<bed>"` |
| `files` | yes | one or more `.ogg` (Ogg Vorbis) files under `assets/`; each play picks one. A bed uses the first and loops it. |
| `gain_db` | no | volume offset in decibels |

- `sounds/` replaces **cues**: `alert`, `chase_start`, `door_open`, `door_close`, `taser`, `music_box`, `axe_chop`,
  the Night Watch cues (`nw_ring`, `nw_door`, ...) and the rest of the game's named sounds. An unknown name is refused.
  A cue's in-game loudness still scales your file; left/right placement is not applied to recordings. Footsteps and a
  few queued office cues are not replaceable yet.
- `ambience/` replaces **beds**: the region beds (`maze`, `mansion`, `hotel`, `mall`, `sewer`, `inferno`, ...) and the
  room beds, whose ids carry a colon: `room:chapel`, `room:kitchen`, `room:big_top`, ... (list them in `overrides` the
  same way: `"ambience/room:chapel"`). Ambience ids are the only ids that may contain `:`. Make the recording loop
  seamlessly.

## Surfaces (floors, walls and ceilings)

The game paints its floor and wall patterns itself at a deliberately low resolution. A pack can replace any of them
with an image:

```json
{"schema": "lr.surface/1", "surfaces": [{"id": "terrazzo0", "image": "assets/my_terrazzo.png"}]}
```

| field | required | meaning |
|---|---|---|
| `id` | yes | the kind, listed in `overrides` as `"floors/<kind>"`, `"walls/<kind>"` or `"ceilings/<kind>"` |
| `image` | yes | a `.png` under `assets/`. Floors are shown at 32x32 pixels and walls at 32x128 (one wall tile, floor to ceiling); other sizes are scaled to that with no smoothing, so draw at that size or an exact multiple. |

- Floor kinds are the list under [Regions](#regions) (`terrazzo0`, `parquet1`, `stone2`, `metal0`, `grate`, `hazard`,
  `runner`, ...). Wall kinds include `panel0-2`, `paper0-1`, `brick0-1`, `stone0-1`, `hedge0-1`, `office0-1`,
  `corridor0-1`, `inferno0`, `rockwall0-7` and the rest the game paints. A floor and a wall kind may share a name
  (`stone0`); the folder says which one you mean.
- Not replaceable: the safe-room floors (`safe`, `safe_plain`, `safe_mark`), which tell players where the safe zone
  is, and the pieces of the hall runner (`runner_l`, `runner_c`, ...); replace `runner` / `runnerz` as a whole.
  Ceiling kinds: `ceil0`, `ceil1`, `glass`, `rockceil`, `vault` (32x32 like floors, `ceilings/` folder).
- Only the picture changes. How shiny a floor looks, and the glow of the `glass` and `vault` ceilings (the sewer relies
  on it), come from the kind, so they stay whatever image you supply.

## Themes (which wall, ceiling and trim a place uses)

Surfaces change a pattern's *picture*; themes change *which* patterns a district or a room uses. One file per id:

```json
{"schema": "lr.region_theme/1", "id": "mansion", "wall": ["brick0", "brick1"], "finish": ""}
{"schema": "lr.room_theme/1", "id": "bedroom", "wall": ["stone0"]}
```

| field | kind | meaning |
|---|---|---|
| `id` | both | the district (`maze`, `mansion`, `hotel`, ... `sewer`, `inferno`) or room purpose (`bedroom`, `kitchen`, ...). Override built-in ones as `"region_themes/<id>"` / `"room_themes/<id>"`; new ones start with `<pack id>_` |
| `wall` | both | wall kinds, picked per four-cell patch in this order (room themes need it) |
| `ceiling` | district | a ceiling kind (`ceil0`, `ceil1`, `glass`, `rockceil`, `vault`) |
| `accent` | district | arch and pilaster trim: `{"texture": "floor"\|"wall", "kind", "tint": "#rrggbb", "metal": true\|false}` |
| `finish` | district | the furniture finish: `"Mansion"` (lacquer, marble, velvet, gilt) or `""` for the ordinary furniture |

- An override only needs the fields it changes; the rest stay the game's.
- Kinds are the ones the game paints (see Surfaces); a theme cannot add a pattern, only pick existing ones.
- Floors are not themes: they follow the region's `hall_floor` / `room_default_floor` and the room purpose.
- Furniture colour sets (all the office furniture in one room teal, all the bedroom set navy) come from each prop's
  `themes` and `coordinated` (see Props). A pack's own furniture family with `"coordinated": true` gets one finish
  per room the same way; keep `themes` the same length and order across the set.

## Rooms

A room recipe furnishes one **room type**. A pack adds a new type (id `<pack id>_<name>`) and puts it where a region
lists it in `room_roles` -- for example a new shop in the mall's cycle (override `regions/mall`, append your type to
`room_roles`, and give it a sign in `shop_names`). The game's own rooms keep their built-in recipes; packs cannot
replace those.

```json
{"schema": "lr.room/1", "id": "record_shop_store", "items": [
	{"type": "checkoutCounter", "side": -2, "depth": "front-1", "facing": "open"},
	{"type": ["shopShelf", "displayCase"], "side": ["-half+1", "half", 3], "depth": "back", "wall_backed": true},
	{"type": "@rug", "side": 0, "depth": "mid", "solid": false, "when": {"min_side": 9}},
	{"choose": [{"type": "@painting", "weight": 2}, {"type": "@frame", "weight": 1}],
	 "side": 0, "depth": "back", "wall_mount": true, "solid": false, "when": {"chance": 0.6}}
]}
```

**Where things go** (in cells, seen from the entrance):
- `depth`: `0` / `"back"` is the row along the back wall; `"front"` is the row with the entrance in its middle (kept
  clear automatically); `"mid"` is halfway. Offsets work: `"front-1"`, `"back+1"`.
- `side`: `0` is the centre column; `"half"` is the distance to the side wall (`"-half+1"`, `"half-1"`). Rooms are
  mirrored at random (the same way for everyone); set `"mirror": false` to pin an item's side.
- `side` may be a range `[from, to, step]` (to excluded) to line items up along a wall.

| item field | meaning |
|---|---|
| `type` | a prop id, or a list cycled along a range, or `@frame` / `@painting` / `@rug` (the region's own; skipped where it has none) |
| `choose` | instead of `type`: `[{type, weight}]`, one picked per placement |
| `side`, `depth` | positions as above (required) |
| `facing` | `open` (towards the entrance, default), `back`, `left`, `right`, `center` |
| `wall_backed` | back flush against the wall behind it |
| `wall_mount` | hung on the wall (frames, shelves); not solid by default |
| `solid` | `false` for things you walk over or that hang (rugs, lamps) |
| `mount_y` | height above the floor in metres (a lamp on a table) |
| `when` | `min_side`, `max_side`, `min_depth`, `max_depth` (room size in cells), `chance` (0-1) |

Rules: recipes place plain props only -- no hiding spots, lockers, booths or other things you use (the game places
those). Every prop must be known (built-in or from your pack) and pack props need a `size`. Items that don't fit are
skipped; the game checks every generated room keeps its entrance clear, all its floor reachable and room for pickups.
See `examples/mods/record_shop` for a complete pack.

## Death lines

The line on the death screen comes from the hunter that caught you, picked from its lines by the route seed, so
everyone in the room sees the same one.

```json
{"schema": "lr.deaths/1", "id": "mypack_runner", "lines": ["Caught you on depth {depth}.", "Run, {name}."],
 "lore_line": "One for the archive.", "mode": "replace"}
```

| field | required | meaning |
|---|---|---|
| `id` | yes | the hunter: one of your pack's, or a built-in one listed in `overrides` as `"deaths/<id>"` |
| `lines` | yes | text lines (`{depth}` and `{name}` are filled in), or `{"text": ..., "style": "caption"}` for a quiet caption |
| `lore_line` | no | one more line in the pool |
| `mode` | no | `replace` (default) swaps the hunter's lines; `add` keeps the built-in ones and adds yours |

## Emotes (`emotes/`, `lr.emote/1`)

One file per hunter: your pack's own hunter, or a built-in one listed in `overrides` as `"emotes/<hunter id>"`.

```json
{"schema": "lr.emote/1", "id": "aki",
 "weights": {"taunt": 0, "dance": 3},
 "clips": {"stretch": "emote_shy"},
 "voice": {"laugh": ["assets/aki_laugh1.ogg", "assets/aki_laugh2.ogg"]}}
```

- `weights`: how often the hunter picks each emote (1 = normal, 0 = never).
- `clips`: play another animation clip for an emote.
- `voice`: recordings played (one at random, heard by distance) when the hunter does that emote.

Emote names must be in `HunterEmoteCatalog`; anything left out keeps the built-in behaviour. Hot-swapped like every kind.

## Loot (`loot/`, `lr.loot/1`)

What a chunk's pickups are, besides its relays. The game ships two tables: `route` (every region without a table of
its own) and `sewer` (the sewer levels). Where pickups lie, the relays, and the sealed wings' bonus relay and guaranteed
tool stay the game's.

```json
{"schema": "lr.loot/1", "id": "mypack_hotel", "regions": ["hotel"],
 "base": ["battery", "coin"],
 "rolls": [{"kind": "tool", "chance": 0.9}, {"kind": "backpack", "chance": 0.25}],
 "tools": [{"item": "crowbar", "weight": 3}, {"item": "rescue_axe", "weight": 1}],
 "backpacks": ["backpack_small", "backpack_medium", "backpack_large"],
 "aid": [{"item": "stim_pack", "chance": 0.2}, {"item": "revive_kit", "chance": 0.03, "chance_coop": 0.08}]}
```

| field | required | meaning |
|---|---|---|
| `id` | yes | `route` / `sewer` listed in `overrides` (`"loot/route"`), or `<pack id>_<name>` for a new table |
| `regions` | new tables | region ids this table loots instead of `route`/`sewer` (`hotel`, `mall`, `sewer`...). If two packs claim a region, the first table by id wins. Ignored on overrides. |
| `base` | yes | kinds every chunk (not safe rooms) gets: `battery`, `coin`, `tool`, `backpack`; at most 4 |
| `rolls` | yes | `{kind, chance}`: one roll each, in order, chance 0 to 1; at most 8 |
| `tools` | yes | `{item, weight}`: which tool a `tool` pickup holds. Items: `taser`, `lockpick`, `crowbar`, `rescue_axe`, `stim_pack`, `revive_kit`. Weights need not add up to 1. |
| `backpacks` | when a backpack can drop | small to large; deeper levels allow the bigger ones |
| `aid` | no | `{item, chance, chance_coop?}`: Stim Packs and Revive Kits, rolled after everything else; `chance_coop` in co-op rooms |

Only the kinds and items above exist: a pack cannot add a new item or relays, and a table carries no code. Every chance is
one draw of the chunk's seeded stream, so everyone in the room gets the same loot.

## Skins (`skins/`, `lr.skin/1`)

Player skins for the **FROM CATALOG** list in Settings -> SKIN. One file per skin; the picture is a PNG in the pack,
nothing else.

```json
{"schema": "lr.skin/1", "id": "mypack_ember", "name": "Ember", "image": "assets/ember_skin.png", "arms": "auto",
 "author": "Your name"}
```

| field | required | meaning |
|---|---|---|
| `id` | yes | `<pack id>_<name>` for a new skin, or a shipped one (`ref_classic`, `ref_slim`) listed in `overrides` as `"skins/<id>"` |
| `name` | yes | shown in the list, 1-32 characters |
| `image` | yes | a `.png` under `assets/`: a standard 64x64 skin (or the old 64x32), at most 64 KB -- the same rules as a picked file ([PLAYER_SKINS.md](../PLAYER_SKINS.md)) |
| `arms` | no | `auto` (default: read from the picture), `classic` or `slim` |
| `author` | no | up to 64 characters |

- The picture is checked when the pack loads; one bad skin refuses the pack like any other error.
- Pack skins are listed while the pack is loaded (your private rooms). Picking one only previews it; **APPLY** makes it
  your own skin, so from then on it is yours like a picked file: kept on your device, put on your account when signed
  in, and shown to co-op players by its hash. It stays on after the pack is unloaded.
- The base layer is made opaque as for every skin, so a pack cannot make anyone invisible.
- The shipped catalog is in the game's `data/skins/` (pictures in `assets/skins/`).
