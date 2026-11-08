# Pack format

## Layout

```
mypack/
  pack.json                 the manifest (required)
  props/<anything>.json     prop files      (lr.prop/1)
  hunters/<anything>.json   hunter files    (lr.hunter/1)
  regions/<anything>.json   region files    (lr.region/1)
  grabs/<anything>.json     grab pools      (lr.grab/1)
  sounds/<anything>.json    sound effects   (lr.sound/1)
  ambience/<anything>.json  ambience beds   (lr.sound/1)
  floors/<anything>.json    floor textures  (lr.surface/1)
  walls/<anything>.json     wall textures   (lr.surface/1)
  ceilings/<anything>.json  ceiling textures (lr.surface/1)
  rooms/<anything>.json     room recipes    (lr.room/1)
  region_themes/<id>.json   district themes (lr.region_theme/1): wall set, ceiling, arch trim, furniture finish
  room_themes/<id>.json     room wall sets  (lr.room_theme/1)
  deaths/<anything>.json    death lines     (lr.deaths/1)
  loot/<anything>.json      loot tables     (lr.loot/1)
  skins/<anything>.json     player skins    (lr.skin/1)
  assets/...                .glb models, .png images, .ogg sounds (any sub-folders, lower-case extensions)
```

Nothing else may be in the folder: no scripts, scenes, resources, READMEs, hidden files or links. The data folders
are one level deep. macOS `.DS_Store` files are ignored.

Installed packs live in the game's user folder under `mods/<pack id>/` (on macOS
`~/Library/Application Support/Godot/app_userdata/KYTTU- The Last Route/mods/`). Packs downloaded from other players
are kept separately in `mods/.cache/<hash>/`.

## pack.json (`lr.pack/1`)

```json
{
	"schema": "lr.pack/1",
	"id": "mypack",
	"name": "My Pack",
	"version": "1.0.0",
	"author": "Your name",
	"description": "What it changes.",
	"overrides": ["props/officePrinter", "hunters/kathy"]
}
```

| field | required | rule |
|---|---|---|
| `schema` | yes | `"lr.pack/1"` |
| `id` | yes | 3-32 characters: `a-z`, `0-9`, `_`, starting with a letter or digit. No capitals, no `-`. Must equal the folder name. |
| `name` | yes | shown in menus and the join dialog |
| `version` | yes | 1-32 characters of `A-Z a-z 0-9 . + -`, starting with a letter or digit. Publish a new version for any change. |
| `author` | no | shown in the join dialog |
| `description` | no | |
| `game_version` | no | informational |
| `overrides` | no | built-in content this pack replaces, as `"<kind>/<id>"` |
| `files` | no | `[{path, sha256, size}]` for every file except `pack.json`; if present it must match exactly |

Unknown keys are an error, so typos fail loudly instead of being ignored.

## Ids

- **New content** must use ids that start with `<pack id>_`, e.g. `mypack_lamp`, `mypack_runner`. Content ids use
  `A-Z a-z 0-9 _`. This keeps packs from ever colliding with the game or each other.
- **Changing built-in content** uses the built-in id (e.g. `officePrinter`) and must list it under `overrides`.
  Only one loaded pack may override a given id.

## The pack hash

A pack's identity is a SHA-256 over its files: for every file, including `pack.json`, the line
`<sha256 of the file> <path>`, sorted by path and joined with newlines. `modpack.sh pack` prints it. A room's host
sends each pack's hash; guests load exactly those packs or refuse to join, so everyone in a room plays the same world.
Any change to any file gives a new hash, which is why a changed pack needs a new version.
