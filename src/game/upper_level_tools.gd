class_name UpperLevelTools
extends RefCounted

## Shared grid helpers for the upper-level generators (MezzanineRouteGenerator +1, OfficesRouteGenerator +2,
## ArchiveRouteGenerator +3, AtticRouteGenerator +4). Every upper level carries the same three-wide cross along
## x = 22 and z = 22 so seams always meet, and every way up is a LevelLink whose upper end the level above carves
## a landing around. Access thins going up (UP_CHANCE), with one guaranteed at chunk (0, 0) so each level is
## reachable from spawn.

const CHUNK_SIZE := StreamedRouteGenerator.CHUNK_SIZE
const CENTER := CHUNK_SIZE / 2
const CROSS_HALF := 1
const QUADRANT_CENTERS := [Vector2i(9, 9), Vector2i(35, 9), Vector2i(9, 35), Vector2i(35, 35)]
## Chance a chunk on level L has a way up to L + 1.
const UP_CHANCE := {0: 0.55, 1: 0.45, 2: 0.35, 3: 0.25, 4: 0.08}
## Storey height (both up and down) and the slab: nothing on level L may rise above (L + 1) * LEVEL_HEIGHT - SLAB.
const LEVEL_HEIGHT := 4.0
const SLAB := 0.1


static func filled(code: int) -> Array:
	var grid := []
	for z in CHUNK_SIZE:
		var row := []
		row.resize(CHUNK_SIZE)
		row.fill(code)
		grid.append(row)
	return grid


static func carve(grid: Array, rect: Rect2i, code: int) -> void:
	for z in range(maxi(rect.position.y, 0), mini(rect.end.y, CHUNK_SIZE)):
		for x in range(maxi(rect.position.x, 0), mini(rect.end.x, CHUNK_SIZE)):
			grid[z][x] = code


## Carve `code` except over cells already holding one of `keep`.
static func carve_keep(grid: Array, rect: Rect2i, code: int, keep: Array) -> void:
	for z in range(maxi(rect.position.y, 0), mini(rect.end.y, CHUNK_SIZE)):
		for x in range(maxi(rect.position.x, 0), mini(rect.end.x, CHUNK_SIZE)):
			if not keep.has(int(grid[z][x])):
				grid[z][x] = code


static func carve_cross(grid: Array, code: int) -> void:
	carve(grid, Rect2i(0, CENTER - CROSS_HALF, CHUNK_SIZE, CROSS_HALF * 2 + 1), code)
	carve(grid, Rect2i(CENTER - CROSS_HALF, 0, CROSS_HALF * 2 + 1, CHUNK_SIZE), code)


## A three-wide passage from `from` straight to the nearer arm of the cross.
static func connect_to_cross(grid: Array, from: Vector2i, code: int, keep: Array) -> void:
	if absi(from.x - CENTER) <= absi(from.y - CENTER):
		carve_keep(grid, Rect2i(mini(from.x, CENTER), from.y - 1, absi(from.x - CENTER) + 1, 3), code, keep)
	else:
		carve_keep(grid, Rect2i(from.x - 1, mini(from.y, CENTER), 3, absi(from.y - CENTER) + 1), code, keep)


static func quadrant_of(cell: Vector2i) -> int:
	return (1 if cell.x > CENTER else 0) + (2 if cell.y > CENTER else 0)


static func shuffled_quadrants(rng: SeededRandom) -> Array:
	var order := [0, 1, 2, 3]
	for i in range(order.size() - 1, 0, -1):
		var j := rng.next_index(i + 1)
		var t: int = order[i]
		order[i] = order[j]
		order[j] = t
	return order


static func wants_up(level: int, coord: Vector3i, rng: SeededRandom) -> bool:
	return (coord.x == 0 and coord.z == 0) or rng.next_float() < float(UP_CHANCE.get(level, 0.0))


## The cell in `quadrant` where a way up from this level rises: the quadrant's outer corner area, inside 2..41 and off
## the vent lines, so the level above can build its landing there.
static func up_cell(quadrant: int) -> Vector2i:
	var qc: Vector2i = QUADRANT_CENTERS[quadrant]
	return qc + Vector2i(signi(qc.x - CENTER), signi(qc.y - CENTER)) * 2


## Links from `below` whose upper end is on `level`.
static func links_up_to(below: Object, coord: Vector3i, level: int) -> Array:
	var result := []
	for link in below.links_for(coord):
		if int(link["from_level"]) == level:
			result.append(link)
	return result


## The chunk dictionary in StreamedRouteGenerator's schema: "grid" is 0 walkable / 1 blocked; the level's own codes
## stay under `own_key`.
static func schema(level_name: String, chunk_id: String, coord: Vector3i, own_grid: Array, walkable: Callable,
		own_key: String, rooms: Array, links: Array, features: Array, ceiling: float) -> Dictionary:
	var grid := []
	for row_value in own_grid:
		var row := []
		for code in row_value:
			row.append(0 if walkable.call(int(code)) else 1)
		grid.append(row)
	var room_entries := []
	for index in rooms.size():
		var room: Dictionary = rooms[index]
		room_entries.append({"id": "%s:ROOM:%d" % [chunk_id, index], "room_type": room["kind"],
			"rect": room["rect"], "center": room["center"]})
	var seam := range(CENTER - CROSS_HALF, CENTER + CROSS_HALF + 1)
	var data := {"schema": 2, "coord": coord, "chunk_id": chunk_id, "level": coord.y,
		"biome": level_name, "region": level_name, "grid": grid,
		"rooms": room_entries, "edges": {"west": seam, "east": seam, "north": seam, "south": seam},
		"links": links, "features": features, "ceiling_height": ceiling}
	data[own_key] = own_grid
	return data
