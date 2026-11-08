class_name AtticRouteGenerator
extends RefCounted

## Level +4, the Attic: a low level of rafters, insulation, ducts and storage boxes over the Archive. A standing spine
## (the shared three-wide cross, so seams meet) carries the ladder hatches up from the Archive; off it,
## the eaves are crouch-only crawlspace under the roof pitch, where a full-height hunter cannot follow. Quiet and good
## for hiding: storage boxes and insulation rolls in the eaves are hide spots for the hiding-props system.
##
## Topology only; reads ArchiveRouteGenerator for the hatch cells so both ends of every ladder agree.

const CHUNK_SIZE := StreamedRouteGenerator.CHUNK_SIZE
const LEVEL := 4

## Grid codes. STAND has room to walk upright under the ridge; CRAWL is crouch-only under the eaves.
const SOLID := 1
const STAND := 0
const CRAWL := 2

const CENTER := CHUNK_SIZE / 2
const SPINE_HALF := 1
const QUADRANT_CENTERS := [Vector2i(9, 9), Vector2i(35, 9), Vector2i(9, 35), Vector2i(35, 35)]
const ROOM_HALF := 3
const EAVES_HALF := 4
## Clear heights (m). The player's crouched capsule fits under CRAWL_CEILING; a standing body does not.
const STAND_CEILING := 2.4
## Crawl clearance follows the player: crouched capsule + 0.05 (world rule), never a hard-coded number.
const CRAWL_CEILING := PlayerController3D.CROUCH_COLLISION_HEIGHT + 0.05
const ROOM_KINDS := ["box_storage", "rafter_loft", "water_tank_loft"]
const HIDE_TYPES := ["atticStorageBox", "insulationRoll"]

var world_seed: String
var below: ArchiveRouteGenerator
var _cache := {}


func _init(p_below: ArchiveRouteGenerator) -> void:
	below = p_below
	world_seed = p_below.world_seed


static func is_walkable(code: int) -> bool:
	return code == STAND or code == CRAWL


static func clear_height(code: int) -> float:
	return STAND_CEILING if code == STAND else (CRAWL_CEILING if code == CRAWL else 0.0)


## Whether a body of `height` (m) can pass this cell. Crouching runners pass CRAWL; hunters use their own height
## (HunterRoster.MODEL_SCALE x the rig), so every full-size humanoid hunter is held at the eaves.
static func passable(code: int, height: float) -> bool:
	return is_walkable(code) and height <= clear_height(code)


func is_chunk_allowed(coord: Vector3i) -> bool:
	return coord.y == LEVEL


func chunk_id(coord: Vector3i) -> String:
	return "ATTIC:%d:%d:%d" % [coord.x, coord.y, coord.z]


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
		row.fill(SOLID)
		grid.append(row)
	if not is_chunk_allowed(coord):
		return _schema(coord, grid, [], [], [])
	_carve(grid, Rect2i(0, CENTER - SPINE_HALF, CHUNK_SIZE, SPINE_HALF * 2 + 1), STAND)
	_carve(grid, Rect2i(CENTER - SPINE_HALF, 0, SPINE_HALF * 2 + 1, CHUNK_SIZE), STAND)
	var rng := SeededRandom.new("%s:ATTIC:%d:%d" % [world_seed, coord.x, coord.z])
	var rooms := []
	var features := []
	var hatch_quadrants := {}
	var links := []
	for link in below.links_for(Vector3i(coord.x, below.LEVEL, coord.z)):
		if int(link["from_level"]) != LEVEL:
			continue
		links.append(link)
		var cell: Vector2i = link["from_cell"]
		_carve(grid, Rect2i(cell - Vector2i.ONE, Vector2i(3, 3)), STAND)
		_connect(grid, cell, STAND)
		hatch_quadrants[_quadrant(cell)] = true
		features.append({"type": "atticHatch", "cell": cell, "link": link["id"]})
	for q in QUADRANT_CENTERS.size():
		var qc: Vector2i = QUADRANT_CENTERS[q]
		if hatch_quadrants.has(q) or rng.next_float() < 0.4:
			var rect := Rect2i(qc - Vector2i(ROOM_HALF, ROOM_HALF), Vector2i.ONE * (ROOM_HALF * 2 + 1))
			_carve_keep(grid, rect, STAND)
			_connect(grid, qc, STAND)
			rooms.append({"kind": ROOM_KINDS[rng.next_index(ROOM_KINDS.size())], "rect": rect, "center": qc})
		else:
			# Eaves: crouch-only from the spine in; the hide spots sit at the far end, out of a standing hunter's reach.
			var rect := Rect2i(qc - Vector2i(EAVES_HALF, EAVES_HALF), Vector2i.ONE * (EAVES_HALF * 2 + 1))
			_carve_keep(grid, rect, CRAWL)
			_connect(grid, qc, CRAWL)
			rooms.append({"kind": "eaves", "rect": rect, "center": qc})
			var far := qc + Vector2i(signi(qc.x - CENTER), signi(qc.y - CENTER)) * (EAVES_HALF - 1)
			features.append({"type": HIDE_TYPES[rng.next_index(HIDE_TYPES.size())], "cell": far, "hide": true})
	return _schema(coord, grid, rooms, links, features)


static func _quadrant(cell: Vector2i) -> int:
	return (1 if cell.x > CENTER else 0) + (2 if cell.y > CENTER else 0)


## A three-wide passage of `code` from `from` straight to the nearer spine arm (never lowering STAND to CRAWL).
static func _connect(grid: Array, from: Vector2i, code: int) -> void:
	if absi(from.x - CENTER) <= absi(from.y - CENTER):
		_carve_keep(grid, Rect2i(mini(from.x, CENTER), from.y - 1, absi(from.x - CENTER) + 1, 3), code)
	else:
		_carve_keep(grid, Rect2i(from.x - 1, mini(from.y, CENTER), 3, absi(from.y - CENTER) + 1), code)


static func _carve(grid: Array, rect: Rect2i, code: int) -> void:
	for z in range(maxi(rect.position.y, 0), mini(rect.end.y, CHUNK_SIZE)):
		for x in range(maxi(rect.position.x, 0), mini(rect.end.x, CHUNK_SIZE)):
			grid[z][x] = code


static func _carve_keep(grid: Array, rect: Rect2i, code: int) -> void:
	for z in range(maxi(rect.position.y, 0), mini(rect.end.y, CHUNK_SIZE)):
		for x in range(maxi(rect.position.x, 0), mini(rect.end.x, CHUNK_SIZE)):
			if int(grid[z][x]) != STAND:
				grid[z][x] = code


func _schema(coord: Vector3i, attic_grid: Array, rooms: Array, links: Array, features: Array) -> Dictionary:
	var grid := []
	for row_value in attic_grid:
		var row := []
		for code in row_value:
			row.append(0 if is_walkable(int(code)) else 1)
		grid.append(row)
	var room_entries := []
	for index in rooms.size():
		var room: Dictionary = rooms[index]
		room_entries.append({"id": "%s:ROOM:%d" % [chunk_id(coord), index], "room_type": room["kind"],
			"rect": room["rect"], "center": room["center"]})
	var seam := range(CENTER - SPINE_HALF, CENTER + SPINE_HALF + 1)
	return {"schema": 2, "coord": coord, "chunk_id": chunk_id(coord), "level": coord.y,
		"biome": "attic", "region": "attic", "grid": grid, "attic_grid": attic_grid,
		"rooms": room_entries, "edges": {"west": seam, "east": seam, "north": seam, "south": seam},
		"links": links, "features": features, "ceiling_height": STAND_CEILING}
