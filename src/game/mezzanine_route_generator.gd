class_name MezzanineRouteGenerator
extends RefCounted

## Level +1, the Mezzanine: grated catwalks and solid-decked balconies hung over the Last Route maze. It is exposed but
## quick: a runner crosses a chunk in a straight line on the catwalk cross, and hunters on level 0 see up through the
## grating (and runners see down). Like SewerRouteGenerator it owns topology only and reads the level-0 chunk below
## read-only; the view, links and streaming integration come once the stairwell work lands (docs: notes hand-over).
##
## Every chunk carries the same catwalk cross along x = 22 and z = 22 (three wide) so seams always meet. Up to three
## quadrants hang a balcony (a solid deck) off the cross on a three-wide grated spur; one balcony may carry the attic
## ladder, one the landing of the stairwell up from level 0. There are no windows to look out of: the mezzanine only
## overlooks the maze (lore: glass stays dark).

const CHUNK_SIZE := StreamedRouteGenerator.CHUNK_SIZE
const LEVEL := 1
const SURFACE_LEVEL := 0
const ATTIC_LEVEL := 2

## Grid codes. OPEN is air over level 0 (nobody walks there; it is the double-height void the maze looks up into).
## GRATE is see-through catwalk, DECK a solid balcony floor; both are walkable.
const OPEN := 1
const GRATE := 0
const DECK := 2

const CENTER := CHUNK_SIZE / 2
const WALK_HALF := 1             # catwalk cross: 21..23
const QUADRANT_CENTERS := [Vector2i(9, 9), Vector2i(35, 9), Vector2i(9, 35), Vector2i(35, 35)]
const BALCONY_HALF := 3          # 7 x 7 balcony decks
const BALCONY_KINDS := ["overlook", "gantry_office", "storage_platform"]
## The catwalks hang this far above level 0's floor; railings line every edge that drops to OPEN.
const FLOOR_HEIGHT := 4.0
const RAIL_HEIGHT := 1.1

var world_seed: String
var surface: StreamedRouteGenerator
var _cache := {}


func _init(p_surface: StreamedRouteGenerator) -> void:
	surface = p_surface
	world_seed = p_surface.world_seed


static func is_walkable(code: int) -> bool:
	return code == GRATE or code == DECK


func is_chunk_allowed(coord: Vector3i) -> bool:
	return coord.y == LEVEL


func chunk_id(coord: Vector3i) -> String:
	return "MEZZANINE:%d:%d:%d" % [coord.x, coord.y, coord.z]


func chunk(coord: Vector3i) -> Dictionary:
	var key := chunk_id(coord)
	if not _cache.has(key):
		_cache[key] = _build_chunk(coord)
	return _cache[key]


func links_for(coord: Vector3i) -> Array:
	return chunk(Vector3i(coord.x, LEVEL, coord.z))["links"]


func _build_chunk(coord: Vector3i) -> Dictionary:
	var grid := []
	for z in CHUNK_SIZE:
		var row := []
		row.resize(CHUNK_SIZE)
		row.fill(OPEN)
		grid.append(row)
	if not is_chunk_allowed(coord):
		return _schema(coord, grid, [], [], [])
	_carve(grid, Rect2i(0, CENTER - WALK_HALF, CHUNK_SIZE, WALK_HALF * 2 + 1), GRATE)
	_carve(grid, Rect2i(CENTER - WALK_HALF, 0, WALK_HALF * 2 + 1, CHUNK_SIZE), GRATE)
	var rng := SeededRandom.new("%s:MEZZANINE:%d:%d" % [world_seed, coord.x, coord.z])
	var order := [0, 1, 2, 3]
	for i in range(order.size() - 1, 0, -1):
		var j := rng.next_index(i + 1)
		var t: int = order[i]
		order[i] = order[j]
		order[j] = t
	var balcony_count := 2 + rng.next_index(2)
	var rooms := []
	var links := []
	var features := []
	var below: Array = surface.chunk(Vector3i(coord.x, SURFACE_LEVEL, coord.z))["grid"]
	for slot in balcony_count:
		var qc: Vector2i = QUADRANT_CENTERS[order[slot]]
		var rect := Rect2i(qc - Vector2i(BALCONY_HALF, BALCONY_HALF), Vector2i.ONE * (BALCONY_HALF * 2 + 1))
		_carve(grid, rect, DECK)
		_carve_spur(grid, qc)
		var kind: String = BALCONY_KINDS[rng.next_index(BALCONY_KINDS.size())]
		rooms.append({"kind": kind, "rect": rect, "center": qc})
		if slot == 0:
			# The attic ladder rises from the balcony's far corner, away from its spur.
			var foot := qc + Vector2i(signi(qc.x - CENTER), signi(qc.y - CENTER)) * (BALCONY_HALF - 1)
			var link := LevelLink.make("ladder", coord, ATTIC_LEVEL, foot, LEVEL, foot)
			link["cover"] = "hatch"
			links.append(link)
			features.append({"type": "atticLadder", "cell": foot, "link": link["id"]})
		elif slot == 1:
			# Provisional stairwell landing: the head of the level-0 stairwell will claim this deck once the sewer lane's
			# switchback stairwells (LevelLink "stairs") are on main. Only a cell over open level-0 floor qualifies.
			var landing := _landing_cell(rect, below)
			if landing != Vector2i(-1, -1):
				var stairs := LevelLink.make("stairs", coord, LEVEL, landing, SURFACE_LEVEL, landing)
				stairs["provisional"] = true
				links.append(stairs)
				features.append({"type": "stairLanding", "cell": landing, "link": stairs["id"]})
	features.append_array(_rails(grid))
	return _schema(coord, grid, rooms, links, features)


## Three-wide grated spur from a balcony to the nearer arm of the catwalk cross.
static func _carve_spur(grid: Array, from: Vector2i) -> void:
	if absi(from.x - CENTER) <= absi(from.y - CENTER):
		var x0 := mini(from.x, CENTER)
		_carve(grid, Rect2i(x0, from.y - 1, absi(from.x - CENTER) + 1, 3), GRATE)
	else:
		var z0 := mini(from.y, CENTER)
		_carve(grid, Rect2i(from.x - 1, z0, 3, absi(from.y - CENTER) + 1), GRATE)


static func _landing_cell(rect: Rect2i, below: Array) -> Vector2i:
	for z in range(rect.position.y + 1, rect.end.y - 1):
		for x in range(rect.position.x + 1, rect.end.x - 1):
			if int(below[z][x]) == 0:
				return Vector2i(x, z)
	return Vector2i(-1, -1)


## A railing on every walkable edge that drops to OPEN (chunk seams stay open: the cross continues next door).
static func _rails(grid: Array) -> Array:
	var rails := []
	for z in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			if not is_walkable(int(grid[z][x])):
				continue
			for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = Vector2i(x, z) + dir
				if n.x < 0 or n.y < 0 or n.x >= CHUNK_SIZE or n.y >= CHUNK_SIZE:
					continue
				if int(grid[n.y][n.x]) == OPEN:
					rails.append({"type": "catwalkRail", "cell": Vector2i(x, z), "side": dir})
	return rails


## Level-0 cells under see-through grating: where a hunter below can spot a runner above (and the reverse).
func sight_cells(coord: Vector3i) -> Array:
	var data := chunk(Vector3i(coord.x, LEVEL, coord.z))
	var below: Array = surface.chunk(Vector3i(coord.x, SURFACE_LEVEL, coord.z))["grid"]
	var cells := []
	for z in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			if int(data["mezzanine_grid"][z][x]) == GRATE and int(below[z][x]) == 0:
				cells.append(Vector2i(x, z))
	return cells


static func _carve(grid: Array, rect: Rect2i, code: int) -> void:
	for z in range(maxi(rect.position.y, 0), mini(rect.end.y, CHUNK_SIZE)):
		for x in range(maxi(rect.position.x, 0), mini(rect.end.x, CHUNK_SIZE)):
			grid[z][x] = code


func _schema(coord: Vector3i, mezz_grid: Array, rooms: Array, links: Array, features: Array) -> Dictionary:
	var grid := []
	for row_value in mezz_grid:
		var row := []
		for code in row_value:
			row.append(0 if is_walkable(int(code)) else 1)
		grid.append(row)
	var room_entries := []
	for index in rooms.size():
		var room: Dictionary = rooms[index]
		room_entries.append({"id": "%s:ROOM:%d" % [chunk_id(coord), index], "room_type": room["kind"],
			"rect": room["rect"], "center": room["center"]})
	var seam := range(CENTER - WALK_HALF, CENTER + WALK_HALF + 1)
	return {"schema": 2, "coord": coord, "chunk_id": chunk_id(coord), "level": coord.y,
		"biome": "mezzanine", "region": "mezzanine", "grid": grid, "mezzanine_grid": mezz_grid,
		"rooms": room_entries, "edges": {"west": seam, "east": seam, "north": seam, "south": seam},
		"links": links, "features": features, "ceiling_height": 0.0}
