class_name CustomMapParser
extends RefCounted

## Developer custom maps: a single colour-coded PNG stands in for procedural
## generation. One pixel = one grid cell, matched exactly against PALETTE
## below (no blending/anti-aliasing — that's what the original enforces too).
## Ported from the original's src/game/custom-map.js, same palette, same
## bounds, same flood-fill-by-colour room detection.
##
## Required:
##   #000000 black  — wall
##   #ffffff white  — floor / corridor (no room)
##   #00ff00 green  — start point (exactly one pixel)
## Optional:
##   #ff0000 red    — exit point (one pixel). The original leaves a map with
##     none entirely without a service lift; this port has nowhere for a
##     no-exit floor to go (every floor descends through one), so absence
##     here falls back to FacilityGenerator's own pick_service_lift() instead
##     of leaving exit_cell unset. A real gap from the original, and the
##     honest way to note it is in code, not a silent behaviour change.
## Region colours (flood-filled into rooms; any shape/count) — recorded on
## the room so a per-region floor material can read it (see
## FacilityView3D.REGION_FLOOR_TINTS), and for anything later that wants to
## know what a room is themed as. No per-region PROP placement yet — this
## port has no prop system to place one into.
const PALETTE := {
	0x000000: {"kind": "wall"},
	0xffffff: {"kind": "floor"},
	0x00ff00: {"kind": "start"},
	0xff0000: {"kind": "exit"},
	0x4a90d9: {"kind": "region", "region": "office"},
	0xc97a3d: {"kind": "region", "region": "maintenance"},
	0xd9b94a: {"kind": "region", "region": "arcade"},
	0xd94aa0: {"kind": "region", "region": "circus"},
	0xb94a4a: {"kind": "region", "region": "nether"},
	0xe8cba0: {"kind": "region", "region": "beach"},
	0x8e5fd9: {"kind": "region", "region": "mansion"},
	0x6fbf73: {"kind": "region", "region": "garden"},
}

## Custom layouts do not inherit the procedural generator's 35..121 authoring
## bounds. Their PNG dimensions become the grid dimensions directly. In other
## words, there is no Last Route pixel-width, pixel-height, or total-cell cap;
## practical memory/rendering cost is determined by the machine loading it.

const FLOOD_NEIGHBORS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## Returns {"ok": bool, "error": String} on failure, or on success:
## {"ok": true, "cols", "rows", "grid", "rooms", "start", "exit_cell"
##  (Vector2i(-1,-1) if none painted), "warnings": Array[String]}.
##
## `grid` matches FacilityGenerator's own convention: 0 = open, 1 = wall.
## `rooms` matches its room dict shape closely enough to feed straight into
## the same downstream code (id/x/y/width/height/center/type), with "region"
## added when the room came from a region colour rather than being carved.
static func parse(image: Image) -> Dictionary:
	if image == null:
		return {"ok": false, "error": "no image data"}
	var width := image.get_width()
	var height := image.get_height()

	if image.is_compressed():
		image = image.duplicate()
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image = image.duplicate()
		image.convert(Image.FORMAT_RGBA8)

	var warnings: Array[String] = []
	var grid: Array = []
	for _y in height:
		var row: Array = []
		row.resize(width)
		row.fill(1)
		grid.append(row)
	var cell_region := {}  # Vector2i -> String region, only for painted region cells
	var start := Vector2i(-1, -1)
	var exits: Array[Vector2i] = []

	for y in height:
		for x in width:
			var pixel := image.get_pixel(x, y)
			if pixel.a < 0.999:
				warnings.append("unrecognized colour at (%d, %d) — treated as wall" % [x, y])
				continue
			var hex := (int(round(pixel.r * 255.0)) << 16) \
				| (int(round(pixel.g * 255.0)) << 8) | int(round(pixel.b * 255.0))
			var entry: Dictionary = PALETTE.get(hex, {})
			if entry.is_empty():
				warnings.append("unrecognized colour #%06x at (%d, %d) — treated as wall"
					% [hex, x, y])
				continue
			match String(entry["kind"]):
				"wall":
					continue
				"floor":
					grid[y][x] = 0
				"start":
					grid[y][x] = 0
					if start.x >= 0:
						warnings.append("extra start marker at (%d, %d) ignored — using %s"
							% [x, y, start])
					else:
						start = Vector2i(x, y)
				"exit":
					grid[y][x] = 0
					exits.append(Vector2i(x, y))
				"region":
					grid[y][x] = 0
					cell_region[Vector2i(x, y)] = String(entry["region"])

	if start.x < 0:
		return {"ok": false, "error": "custom map has no start marker — paint one pure green (#00ff00) pixel"}
	if exits.size() > 1:
		warnings.append("%d exit markers found — using %s, ignoring the rest" % [exits.size(), exits[0]])

	var rooms := _flood_fill_regions(cell_region, width, height)

	return {
		"ok": true, "cols": width, "rows": height, "grid": grid, "rooms": rooms,
		"start": start, "exit_cell": exits[0] if not exits.is_empty() else Vector2i(-1, -1),
		"warnings": warnings,
	}


static func _flood_fill_regions(cell_region: Dictionary, width: int, height: int) -> Array:
	var rooms: Array = []
	var visited := {}
	for key in cell_region:
		var cell: Vector2i = key
		if visited.has(cell):
			continue
		var region: String = cell_region[cell]
		var stack: Array = [cell]
		visited[cell] = true
		var min_x: int = cell.x
		var max_x: int = cell.x
		var min_y: int = cell.y
		var max_y: int = cell.y
		while not stack.is_empty():
			var at: Vector2i = stack.pop_back()
			min_x = mini(min_x, at.x)
			max_x = maxi(max_x, at.x)
			min_y = mini(min_y, at.y)
			max_y = maxi(max_y, at.y)
			for step in FLOOD_NEIGHBORS:
				var next: Vector2i = at + step
				if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
					continue
				if visited.has(next) or cell_region.get(next, "") != region:
					continue
				visited[next] = true
				stack.append(next)
		var w: int = max_x - min_x + 1
		var h: int = max_y - min_y + 1
		rooms.append({
			"id": "custom-room-%d" % rooms.size(),
			"x": min_x, "y": min_y, "width": w, "height": h,
			"center": Vector2i(min_x + w / 2, min_y + h / 2),
			"type": region, "region": region,
		})
	return rooms
