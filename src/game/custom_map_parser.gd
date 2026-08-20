class_name CustomMapParser
extends RefCounted

## Developer custom maps: a single colour-coded PNG stands in for procedural
## generation. One pixel = one grid cell, matched exactly against PALETTE
## below (no blending/anti-aliasing — that's what the original enforces too).
## Ported from the original's src/game/custom-map.js, with the same palette
## and flood-fill-by-colour room detection.
##
## Geometry:
##   #000000 black  — wall
##   #ffffff white  — floor / corridor (no room)
##   #00ff00 green  — authored player spawn point (zero or more). Every green
##     cell is retained. With none, FacilityGenerator deterministically picks
##     a random open floor cell from the route seed.
## Optional:
##   #ff0000 red    — exit point (one pixel). The original leaves a map with
##     none entirely without a service lift; this port has nowhere for a
##     no-exit floor to go (every floor descends through one), so absence
##     here falls back to FacilityGenerator's own pick_service_lift() instead
##     of leaving exit_cell unset. A real gap from the original, and the
##     honest way to note it is in code, not a silent behaviour change.
## Region colours (flood-filled into rooms; any shape/count) — recorded on
## the room so its floor material and RoomCatalog roster can both read it.
## FacilityGenerator turns each flood-filled region into deterministic themed
## prop placement, and FacilityView3D instances the authored GLB models.
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
	0xb07cc6: {"kind": "region", "region": "bedroom"},
	0x6fbf73: {"kind": "region", "region": "garden"},
	# Exact authored props from the original PNG tool. The map remains an
	# admin-only developer surface; these colors do not become procedural
	# Infinite Route inputs.
	0x00e5ff: {"kind": "prop", "prop_type": "locker"},
	0xe91e63: {"kind": "prop", "prop_type": "privacyCurtain"},
	0x8d6e63: {"kind": "prop", "prop_type": "supplyCrates"},
	0x3f51b5: {"kind": "prop", "prop_type": "officeDesk"},
	0x009688: {"kind": "prop", "prop_type": "officeChair"},
	0x9e9e9e: {"kind": "prop", "prop_type": "filingCabinet"},
	0xffc107: {"kind": "prop", "prop_type": "trashBin"},
	0x795548: {"kind": "prop", "prop_type": "woodenChair"},
	0x607d8b: {"kind": "prop", "prop_type": "woodenTable"},
	0xff5722: {"kind": "prop", "prop_type": "vendingMachine"},
	0x673ab7: {"kind": "prop", "prop_type": "magazineRack"},
	0x03a9f4: {"kind": "prop", "prop_type": "floorLamp"},
}

## Custom layouts do not inherit the procedural generator's 35..121 authoring
## bounds, but a downloaded PNG still needs a shipping-safe ceiling. The byte
## limit in Main3D only caps the compressed file; without these decoded limits
## a tiny PNG can expand into an enormous grid and exhaust a client's memory.
const MAX_DIMENSION := 512
const MAX_CELLS := 65_536

const FLOOD_NEIGHBORS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## Returns {"ok": bool, "error": String} on failure, or on success:
## {"ok": true, "cols", "rows", "grid", "rooms", "start", "spawn_points", "exit_cell"
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
	var size_error := dimension_error(width, height)
	if not size_error.is_empty():
		return {"ok": false, "error": size_error}

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
	var spawn_points: Array[Vector2i] = []
	var exits: Array[Vector2i] = []
	var authored_props: Array = []
	var open_cell_count := 0

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
					open_cell_count += 1
				"start":
					grid[y][x] = 0
					open_cell_count += 1
					spawn_points.append(Vector2i(x, y))
				"exit":
					grid[y][x] = 0
					open_cell_count += 1
					exits.append(Vector2i(x, y))
				"region":
					grid[y][x] = 0
					open_cell_count += 1
					cell_region[Vector2i(x, y)] = String(entry["region"])
				"prop":
					grid[y][x] = 0
					open_cell_count += 1
					authored_props.append({"x": x, "y": y,
						"type": String(entry["prop_type"])})

	if open_cell_count <= 0:
		return {"ok": false, "error": "custom map has no walkable floor or spawn cells"}
	var connectivity_start: Vector2i = spawn_points[0] if not spawn_points.is_empty() \
		else _first_open_cell(grid, width, height)
	var reachable_count := _connected_open_count(grid, connectivity_start, width, height)
	if reachable_count != open_cell_count:
		return {"ok": false, "error":
			"custom map has %d unreachable walkable cells" % (open_cell_count - reachable_count)}
	if spawn_points.is_empty():
		warnings.append("no green spawn markers — a seeded random open cell will be used")
	if exits.size() > 1:
		warnings.append("%d exit markers found — using %s, ignoring the rest" % [exits.size(), exits[0]])

	var rooms := _flood_fill_regions(cell_region, width, height)

	return {
		"ok": true, "cols": width, "rows": height, "grid": grid, "rooms": rooms,
		"start": spawn_points[0] if not spawn_points.is_empty() else Vector2i(-1, -1),
		"spawn_points": spawn_points,
		"exit_cell": exits[0] if not exits.is_empty() else Vector2i(-1, -1),
		"authored_props": authored_props,
		"warnings": warnings,
	}


static func dimension_error(width: int, height: int) -> String:
	if width <= 0 or height <= 0:
		return "custom map dimensions are invalid"
	if width > MAX_DIMENSION or height > MAX_DIMENSION:
		return "custom map dimensions exceed %dx%d" % [MAX_DIMENSION, MAX_DIMENSION]
	if width * height > MAX_CELLS:
		return "custom map exceeds %d walkable-grid cells" % MAX_CELLS
	return ""


static func _first_open_cell(grid: Array, width: int, height: int) -> Vector2i:
	for y in height:
		for x in width:
			if grid[y][x] == 0:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


static func _connected_open_count(grid: Array, start: Vector2i,
		width: int, height: int) -> int:
	if start.x < 0:
		return 0
	var visited := {start: true}
	var queue: Array[Vector2i] = [start]
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		for step in FLOOD_NEIGHBORS:
			var next: Vector2i = cell + step
			if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
				continue
			if visited.has(next) or grid[next.y][next.x] != 0:
				continue
			visited[next] = true
			queue.append(next)
	return visited.size()


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
		var member_cells: Array[Vector2i] = []
		var member_lookup := {}
		while not stack.is_empty():
			var at: Vector2i = stack.pop_back()
			member_cells.append(at)
			member_lookup[at] = true
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
		var box_center := Vector2(min_x + (w - 1) * 0.5, min_y + (h - 1) * 0.5)
		var room_center: Vector2i = member_cells[0]
		var closest_distance := Vector2(room_center).distance_squared_to(box_center)
		for candidate in member_cells:
			var distance := Vector2(candidate).distance_squared_to(box_center)
			if distance < closest_distance:
				closest_distance = distance
				room_center = candidate
		rooms.append({
			"id": "custom-room-%d" % rooms.size(),
			"x": min_x, "y": min_y, "width": w, "height": h,
			# A region can be L-shaped or ring-shaped. Keep exact membership so
			# room queries do not turn the empty part of its bounding box into a
			# themed room, and anchor its center on a real painted cell.
			"center": room_center, "cells": member_lookup,
			"type": region, "region": region,
		})
	return rooms
