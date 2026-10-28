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

Where props show up:
- An **override** replaces the model of a built-in prop everywhere the game already places it. This is the reliable
  way to change what players see (the Ember pack recolours every office printer).
- A **new prop** is placed only by a region's `prop_set`, which dresses rooms that have no furniture recipe. Every
  room type in the current regions has a recipe, so a new prop needs a region override and a room without a recipe
  to appear. Room recipes are planned as a pack type.

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
| `speed` | yes | walking speed multiplier (0.77-0.97) |
| `chase` | yes | chase speed (2.75-4.35) |
| `prog` | yes | how fast the chase builds up (0.12-0.20) |
| `sight` | yes | sight range (6.7-8.7) |
| `hearing` | yes | hearing scale; 1.0 is normal, 0 is deaf (0-1.18) |
| `spawn` | yes | whole number: spawn distance from the runner (10-16) |
| `model` | no | a `.glb` in the pack, or a shipped body: `res://assets/hunters_blocky/<hunter>/<hunter>.glb` or `res://art/props-3d/characters/...` |
| `portrait` | no | a `.png` in the pack, or a shipped `res://assets/ui/hunter_portraits/<hunter>.png` |
| `chase_style` | no | how the body moves when chasing: `reach2`, `reach1`, `pump`, `lope`, `glide`, `skitter`, `stalk`, `stopstart`, optionally `:<variant>`. Unknown values fall back to `pump`. |
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
- `ambience/` replaces **beds**: the region beds (`maze`, `mansion`, `hotel`, `mall`, `sewer`, `inferno`, ...) and room
  beds. Make the recording loop seamlessly.
