class_name MezzanineRouteGenerator
extends RefCounted

## Level +1, the Mezzanine: grated catwalks and solid-decked balconies hung over the Last Route maze. It is exposed but
## quick: a runner crosses a chunk in a straight line on the catwalk cross, and hunters on level 0 see up through the
## grating (and runners see down). Like SewerRouteGenerator it owns topology only and reads the level-0 chunk below
## read-only; the view, links and streaming integration come once the stairwell work lands.
##
## Every chunk carries the shared three-wide cross (UpperLevelTools) as grated catwalk. Two or three quadrants hang a
## balcony (a solid deck) off it on a grated spur; one may carry the landing of the stairwell up from level 0, another
## the stairwell on up to the Offices (+2). There are no windows to look out of: the mezzanine only overlooks the maze
## (lore: glass stays dark).

const CHUNK_SIZE := StreamedRouteGenerator.CHUNK_SIZE
const LEVEL := 1
const SURFACE_LEVEL := 0

## Grid codes. OPEN is air over level 0 (nobody walks there; it is the double-height void the maze looks up into).
## GRATE is see-through catwalk, DECK a solid balcony floor; both are walkable.
const GRATE := 0
const OPEN := 1
const DECK := 2

const BALCONY_HALF := 3          # 7 x 7 balcony decks
const BALCONY_KINDS := ["overlook", "gantry_office", "storage_platform"]
## Railings line every edge that drops to OPEN.
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
	var grid := UpperLevelTools.filled(OPEN)
	if not is_chunk_allowed(coord):
		return _schema(coord, grid, [], [], [])
	UpperLevelTools.carve_cross(grid, GRATE)
	var rng := SeededRandom.new("%s:MEZZANINE:%d:%d" % [world_seed, coord.x, coord.z])
	var order := UpperLevelTools.shuffled_quadrants(rng)
	var balcony_count := 2 + rng.next_index(2)
	var wants_up := UpperLevelTools.wants_up(LEVEL, coord, rng)
	var rooms := []
	var links := []
	var features := []
	var below: Array = surface.chunk(Vector3i(coord.x, SURFACE_LEVEL, coord.z))["grid"]
	for slot in balcony_count:
		var quadrant: int = order[slot]
		var qc: Vector2i = UpperLevelTools.QUADRANT_CENTERS[quadrant]
		var rect := Rect2i(qc - Vector2i(BALCONY_HALF, BALCONY_HALF), Vector2i.ONE * (BALCONY_HALF * 2 + 1))
		UpperLevelTools.carve(grid, rect, DECK)
		UpperLevelTools.connect_to_cross(grid, qc, GRATE, [DECK])
		var kind: String = BALCONY_KINDS[rng.next_index(BALCONY_KINDS.size())]
		rooms.append({"kind": kind, "rect": rect, "center": qc})
		if slot == 0 and wants_up:
			# Provisional: the stairwell planner (StreamedRouteGenerator.stairwell_between) will own this footprint.
			var foot := UpperLevelTools.up_cell(quadrant)
			var up := LevelLink.make("stairs", coord, LEVEL + 1, foot, LEVEL, foot)
			up["provisional"] = true
			links.append(up)
			features.append({"type": "stairFoot", "cell": foot, "link": up["id"]})
		elif slot == 1:
			# Provisional landing of the stairwell up from level 0: only a cell over open level-0 floor qualifies.
			var landing := _landing_cell(rect, below)
			if landing != Vector2i(-1, -1):
				var stairs := LevelLink.make("stairs", coord, LEVEL, landing, SURFACE_LEVEL, landing)
				stairs["provisional"] = true
				links.append(stairs)
				features.append({"type": "stairLanding", "cell": landing, "link": stairs["id"]})
	features.append_array(_rails(grid))
	return _schema(coord, grid, rooms, links, features)


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


func _schema(coord: Vector3i, own: Array, rooms: Array, links: Array, features: Array) -> Dictionary:
	return UpperLevelTools.schema("mezzanine", chunk_id(coord), coord, own, is_walkable, "mezzanine_grid", rooms, links, features, 0.0)
