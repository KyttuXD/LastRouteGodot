# Walkthrough: the Poster Shop pack

Poster Shop is the small example in `examples/mods/poster_shop`. It does two things, and only those two: a new mall
shop furnished by a room recipe, and one replacement floor image. It is the short version of what `library_rooms`
(recipes and region roles) and `neon_arcade` (surface images) show separately.

## 1. The manifest

```json
{
	"schema": "lr.pack/1",
	"id": "poster_shop",
	"name": "Poster Shop",
	"version": "1.0.0",
	"author": "Kyttu's Lab (example)",
	"description": "Example pack: a poster stall joins the mall's shop cycle, and the mall's terrazzo0 floor becomes a cream-and-teal checker.",
	"overrides": ["regions/mall", "floors/terrazzo0"]
}
```

`regions/mall` replaces the whole mall region. `floors/terrazzo0` replaces one built-in floor. Surfaces can only
replace a kind the game already paints, so the floor id stays `terrazzo0` and the folder says it is a floor.

## 2. The room recipe (`rooms/stall.json`)

```json
{"schema": "lr.room/1", "id": "poster_shop_stall", "items": [
	{"type": "checkoutCounter", "side": -2, "depth": "front-1", "facing": "open"},
	{"type": "shopShelf", "side": ["-half+1", -1, 2], "depth": "back", "wall_backed": true, "facing": "open"},
	{"type": "shopShelf", "side": [1, "half", 2], "depth": "back", "wall_backed": true, "facing": "open"},
	{"type": "menuBoard", "side": 0, "depth": "back", "wall_mount": true, "solid": false, "facing": "open"},
	{"type": "displayCase", "side": 2, "depth": "mid", "facing": "center", "when": {"min_depth": 9}},
	{"type": "floorLamp", "side": "half-1", "depth": "front-2", "wall_backed": true, "solid": false},
	{"type": "@rug", "side": 0, "depth": "mid", "solid": false, "when": {"min_side": 9}}
]}
```

The id starts with the pack id. A counter sits by the door. Shelves line the back wall and leave the centre cell for
a wall-hung menu board (the stall's poster). Deeper rooms add a display case; wider rooms add the region's rug. Every
prop is one the room generator already has a footprint for.

## 3. Hook it into the mall (`regions/mall.json`)

Copy the built-in mall region and append the new role after the existing shops, including `music_store`:

```json
"room_roles": [ "...", "music_store", "poster_shop_stall" ],
"shop_names": { "...": "...", "music_store": "MUSIC & SOUND", "poster_shop_stall": "POSTERS" }
```

A region override replaces the whole role list. Leaving `music_store` in that list keeps the music wing's mall shop.
The sign on the door is `POSTERS`.

This pack overrides `regions/mall`, so it cannot load together with another pack that overrides the same region
(`neon_arcade`, `library_rooms`, `record_shop`).

## 4. One surface (`floors/floors.json`)

```json
{"schema": "lr.surface/1", "surfaces": [
	{"id": "terrazzo0", "image": "assets/poster_floor.png"}
]}
```

`assets/poster_floor.png` is an original 32x32 image: a cream and teal checker with a dark grout line and a small pin
in each cell. The mall's room floors use `terrazzo0`, and the hall alternates `terrazzo0` with `terrazzo1`, so rooms
and every other hall tile show the checker. `terrazzo1` stays the built-in terrazzo. Only the picture changes; the
floor's shine stays whatever `terrazzo0` already uses.

## 5. Check it and play it

```
tools/modpack/modpack.sh validate examples/mods/poster_shop
cp -R examples/mods/poster_shop "$HOME/Library/Application Support/Godot/app_userdata/KYTTU- The Last Route/mods/"
```

Then open **Settings -> MODS**, switch on **USE IN MY ROOMS** for Poster Shop, and start a private room. On Linux the
mods folder is under the Godot user data directory for this project (`user://mods/poster_shop/`).
