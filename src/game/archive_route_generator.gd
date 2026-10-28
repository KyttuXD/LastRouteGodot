class_name ArchiveRouteGenerator
extends RefCounted

## Level +3, the Archive: endless stacks of filing cabinets and record boxes, a quiet maze made of shelving. Each
## quadrant is filled with shelving rows two aisles apart; every row has gaps where the cross-aisles run, so every aisle
## connects. Relay and collectible spots hide at the ends of the stacks; rolling library ladders run on rails along the
## tallest rows. One stack may hold the ladder and hatch up into the Attic (+4). Records and files only.
## Topology only, like the other upper levels.

const CHUNK_SIZE := StreamedRouteGenerator.CHUNK_SIZE
const LEVEL := 3

const FLOOR := 0
const SHELF := 1

## Shelving rows run along x on every third z; a cross-aisle gap opens every GAP_EVERY cells.
const ROW_EVERY := 3
const GAP_EVERY := 6
const STACK_KINDS := ["filing_stacks", "record_boxes", "card_index_hall"]
const SPOTS_PER_CHUNK := 3
const CEILING := 3.4

var world_seed: String
var below: OfficesRouteGenerator
var _cache := {}


func _init(p_below: OfficesRouteGenerator) -> void:
	below = p_below
	world_seed = p_below.world_seed


static func is_walkable(code: int) -> bool:
	return code == FLOOR


func is_chunk_allowed(coord: Vector3i) -> bool:
	return coord.y == LEVEL


func chunk_id(coord: Vector3i) -> String:
	return "ARCHIVE:%d:%d:%d" % [coord.x, coord.y, coord.z]


func chunk(coord: Vector3i) -> Dictionary:
	var key := chunk_id(coord)
	if not _cache.has(key):
		_cache[key] = _build_chunk(coord)
	return _cache[key]


func links_for(coord: Vector3i) -> Array:
	return chunk(Vector3i(coord.x, LEVEL, coord.z))["links"]


func _build_chunk(coord: Vector3i) -> Dictionary:
	var grid := UpperLevelTools.filled(FLOOR)
	if not is_chunk_allowed(coord):
		return _schema(coord, grid, [], [], [])
	var rng := SeededRandom.new("%s:ARCHIVE:%d:%d" % [world_seed, coord.x, coord.z])
	var lo := UpperLevelTools.CENTER - UpperLevelTools.CROSS_HALF
	var hi := UpperLevelTools.CENTER + UpperLevelTools.CROSS_HALF
	var offset := rng.next_index(GAP_EVERY)
	# Shelving rows inside 2..41, off the cross; the outer two cells stay a perimeter aisle so seams meet everywhere.
	for z in range(2, CHUNK_SIZE - 2):
		if z >= lo - 1 and z <= hi + 1 or z % ROW_EVERY != 0:
			continue
		for x in range(2, CHUNK_SIZE - 2):
			if x >= lo - 1 and x <= hi + 1 or (x + offset) % GAP_EVERY == 0:
				continue
			grid[z][x] = SHELF
	var rooms := []
	for quadrant in 4:
		var qc: Vector2i = UpperLevelTools.QUADRANT_CENTERS[quadrant]
		rooms.append({"kind": STACK_KINDS[rng.next_index(STACK_KINDS.size())],
			"rect": Rect2i(qc - Vector2i(8, 8), Vector2i(17, 17)), "center": qc})
	var links := []
	var features := []
	var taken := {}
	for link in UpperLevelTools.links_up_to(below, Vector3i(coord.x, below.LEVEL, coord.z), LEVEL):
		links.append(link)
		var head: Vector2i = link["from_cell"]
		taken[UpperLevelTools.quadrant_of(head)] = true
		UpperLevelTools.carve(grid, Rect2i(head - Vector2i.ONE, Vector2i(3, 3)), FLOOR)
		features.append({"type": "stairHead", "cell": head, "link": link["id"]})
	if UpperLevelTools.wants_up(LEVEL, coord, rng):
		for quadrant in UpperLevelTools.shuffled_quadrants(rng):
			if taken.has(quadrant):
				continue
			var foot := UpperLevelTools.up_cell(quadrant)
			UpperLevelTools.carve(grid, Rect2i(foot - Vector2i.ONE, Vector2i(3, 3)), FLOOR)
			var up := LevelLink.make("ladder", coord, LEVEL + 1, foot, LEVEL, foot)
			up["cover"] = "hatch"
			links.append(up)
			features.append({"type": "atticLadder", "cell": foot, "link": up["id"]})
			break
	features.append_array(_stack_spots(grid, rng))
	return _schema(coord, grid, rooms, links, features)


## Dead-quiet spots at the ends of shelving rows where relays and collectibles hide in the stacks.
static func _stack_spots(grid: Array, rng: SeededRandom) -> Array:
	var candidates := []
	for z in range(2, CHUNK_SIZE - 2):
		for x in range(2, CHUNK_SIZE - 2):
			if int(grid[z][x]) != FLOOR:
				continue
			var shelves := 0
			for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = Vector2i(x, z) + dir
				if int(grid[n.y][n.x]) == SHELF:
					shelves += 1
			if shelves >= 2:
				candidates.append(Vector2i(x, z))
	var spots := []
	for i in mini(SPOTS_PER_CHUNK, candidates.size()):
		spots.append({"type": "stackSpot", "cell": candidates[rng.next_index(candidates.size())], "hide": false})
	return spots


func _schema(coord: Vector3i, own: Array, rooms: Array, links: Array, features: Array) -> Dictionary:
	return UpperLevelTools.schema("archive", chunk_id(coord), coord, own, is_walkable, "archive_grid", rooms, links, features, CEILING)
