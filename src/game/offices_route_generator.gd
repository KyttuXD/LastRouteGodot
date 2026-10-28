class_name OfficesRouteGenerator
extends RefCounted

## Level +2, the Offices / Upper Floors: abandoned office and hotel floors. A three-wide corridor cross (UpperLevelTools,
## so seams meet) serves one walled suite per quadrant: cubicle farms, conference rooms, elevator lobbies and break
## rooms. The stairwells up from the mezzanine land in a suite; one suite may hold the stairwell on up to the Archive
## (+3). Windows stay dark and empty (lore): suites are lit from the ceiling, never from outside.
## Topology only, like the other upper levels.

const CHUNK_SIZE := StreamedRouteGenerator.CHUNK_SIZE
const LEVEL := 2

const FLOOR := 0
const WALL := 1

const SUITE_HALF := 4            # 9 x 9 suites
const SUITE_KINDS := ["cubicle_farm", "conference_room", "elevator_lobby", "break_room", "hotel_corridor_rooms"]
const CEILING := 2.8

var world_seed: String
var below: MezzanineRouteGenerator
var _cache := {}


func _init(p_below: MezzanineRouteGenerator) -> void:
	below = p_below
	world_seed = p_below.world_seed


static func is_walkable(code: int) -> bool:
	return code == FLOOR


func is_chunk_allowed(coord: Vector3i) -> bool:
	return coord.y == LEVEL


func chunk_id(coord: Vector3i) -> String:
	return "OFFICES:%d:%d:%d" % [coord.x, coord.y, coord.z]


func chunk(coord: Vector3i) -> Dictionary:
	var key := chunk_id(coord)
	if not _cache.has(key):
		_cache[key] = _build_chunk(coord)
	return _cache[key]


func links_for(coord: Vector3i) -> Array:
	return chunk(Vector3i(coord.x, LEVEL, coord.z))["links"]


func _build_chunk(coord: Vector3i) -> Dictionary:
	var grid := UpperLevelTools.filled(WALL)
	if not is_chunk_allowed(coord):
		return _schema(coord, grid, [], [], [])
	UpperLevelTools.carve_cross(grid, FLOOR)
	var rng := SeededRandom.new("%s:OFFICES:%d:%d" % [world_seed, coord.x, coord.z])
	var rooms := []
	var features := []
	var links := []
	var taken := {}
	for link in UpperLevelTools.links_up_to(below, Vector3i(coord.x, below.LEVEL, coord.z), LEVEL):
		links.append(link)
		taken[UpperLevelTools.quadrant_of(link["from_cell"])] = true
		features.append({"type": "stairHead", "cell": link["from_cell"], "link": link["id"]})
	var order := UpperLevelTools.shuffled_quadrants(rng)
	var wants_up := UpperLevelTools.wants_up(LEVEL, coord, rng)
	for quadrant in order:
		var qc: Vector2i = UpperLevelTools.QUADRANT_CENTERS[quadrant]
		var rect := Rect2i(qc - Vector2i(SUITE_HALF, SUITE_HALF), Vector2i.ONE * (SUITE_HALF * 2 + 1))
		UpperLevelTools.carve(grid, rect, FLOOR)
		UpperLevelTools.connect_to_cross(grid, qc, FLOOR, [])
		rooms.append({"kind": SUITE_KINDS[rng.next_index(SUITE_KINDS.size())], "rect": rect, "center": qc})
		if wants_up and not taken.has(quadrant):
			wants_up = false
			var foot := UpperLevelTools.up_cell(quadrant)
			var up := LevelLink.make("stairs", coord, LEVEL + 1, foot, LEVEL, foot)
			up["provisional"] = true
			links.append(up)
			features.append({"type": "stairFoot", "cell": foot, "link": up["id"]})
	return _schema(coord, grid, rooms, links, features)


func _schema(coord: Vector3i, own: Array, rooms: Array, links: Array, features: Array) -> Dictionary:
	return UpperLevelTools.schema("offices", chunk_id(coord), coord, own, is_walkable, "offices_grid", rooms, links, features, CEILING)
