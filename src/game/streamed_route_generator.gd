class_name StreamedRouteGenerator
extends RefCounted

## Deterministic foundation for the endless route. This class intentionally
## owns topology/data only; FacilityView3D remains the shipping fixed-floor
## renderer until chunk unload/reload and host-authoritative mutation storage
## are ready. Keeping the seam contract pure makes that next step testable.

const CHUNK_SIZE := 16
const BIOME_REGION_SIZE := 4
const BIOMES := ["maze", "mansion", "hotel", "apartment"]
const EDGE_OFFSETS := [3, 5, 7, 9, 11, 13]
const PICKUP_TYPES := ["flashlight", "taser", "lockpick", "crowbar", "rescue_axe"]

var world_seed := "ENDLESS-ROUTE"


func _init(seed_text: String = "ENDLESS-ROUTE") -> void:
	world_seed = seed_text if not seed_text.is_empty() else "ENDLESS-ROUTE"


func chunk(coord: Vector3i) -> Dictionary:
	var grid := _maze_grid(coord)
	var edges := {
		"west": edge_openings(coord, Vector2i(-1, 0)),
		"east": edge_openings(coord, Vector2i(1, 0)),
		"north": edge_openings(coord, Vector2i(0, -1)),
		"south": edge_openings(coord, Vector2i(0, 1)),
	}
	_carve_edges(grid, edges)
	var stairs := stair_links(coord)
	for stair in stairs:
		_carve_to_center(grid, stair["cell"])
	var safe := is_safe_room(coord)
	if safe:
		_carve_safe_room(grid)
	var pickups := _pickups(coord, grid, stairs, safe)
	return {
		"schema": 1,
		"coord": coord,
		"chunk_id": chunk_id(coord),
		"biome": biome_for(coord),
		"grid": grid,
		"edges": edges,
		"stairs": stairs,
		"safe_room": safe,
		"pickups": pickups,
	}


func biome_for(coord: Vector3i) -> String:
	# Four-by-four regions read as facility biomes rather than every doorway
	# changing material language. Level participates so a stair can lead into a
	# visibly different wing without destabilising horizontal neighbours.
	var region_x := floori(float(coord.x) / BIOME_REGION_SIZE)
	var region_z := floori(float(coord.z) / BIOME_REGION_SIZE)
	var rng := SeededRandom.new("%s:BIOME:%d:%d:%d" % [
		world_seed, region_x, coord.y, region_z])
	return BIOMES[rng.next_index(BIOMES.size())]


func edge_openings(coord: Vector3i, direction: Vector2i) -> Array:
	var key := ""
	if direction.x != 0:
		var boundary_x := coord.x + (1 if direction.x > 0 else 0)
		key = "X:%d:%d:%d" % [boundary_x, coord.y, coord.z]
	else:
		var boundary_z := coord.z + (1 if direction.y > 0 else 0)
		key = "Z:%d:%d:%d" % [coord.x, coord.y, boundary_z]
	var rng := SeededRandom.new("%s:SEAM:%s" % [world_seed, key])
	var first: int = EDGE_OFFSETS[rng.next_index(EDGE_OFFSETS.size())]
	var result := [first]
	# Occasional double connections create loops across chunks while the
	# canonical boundary key guarantees both neighbours make the same choice.
	if rng.next_float() < 0.22:
		var second: int = EDGE_OFFSETS[rng.next_index(EDGE_OFFSETS.size())]
		if second != first:
			result.append(second)
	result.sort()
	return result


func stair_links(coord: Vector3i) -> Array:
	var links := []
	for lower_level in [coord.y - 1, coord.y]:
		var forced_origin: bool = coord.x == 0 and coord.z == 0 \
			and int(lower_level) == 0
		var rng := SeededRandom.new("%s:STAIR:%d:%d:%d" % [
			world_seed, coord.x, lower_level, coord.z])
		if not forced_origin and rng.next_float() >= 0.24:
			continue
		var cell := Vector2i(
			EDGE_OFFSETS[rng.next_index(EDGE_OFFSETS.size())],
			EDGE_OFFSETS[rng.next_index(EDGE_OFFSETS.size())])
		var lower := Vector3i(coord.x, lower_level, coord.z)
		var upper := Vector3i(coord.x, lower_level + 1, coord.z)
		links.append({
			"id": "STAIR:%d:%d:%d" % [coord.x, lower_level, coord.z],
			"cell": cell,
			"lower": lower,
			"upper": upper,
			"direction": "up" if coord.y == lower_level else "down",
			# Resolve style from the shared lower chunk so both vertical sides
			# describe the same physical staircase even across a biome boundary.
			"style": _stair_style(biome_for(lower)),
		})
	return links


func is_safe_room(coord: Vector3i) -> bool:
	if coord == Vector3i.ZERO:
		return true
	var rng := SeededRandom.new("%s:SAFE:%d:%d:%d" % [
		world_seed, coord.x, coord.y, coord.z])
	return rng.next_float() < 0.055


func coordinates_around(world_xz: Vector2, level: int, radius: int = 2) -> Array:
	var center := Vector2i(floori(world_xz.x / CHUNK_SIZE),
		floori(world_xz.y / CHUNK_SIZE))
	var result := []
	for z in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			result.append(Vector3i(x, level, z))
	return result


func chunk_id(coord: Vector3i) -> String:
	return "%d:%d:%d" % [coord.x, coord.y, coord.z]


func pickup_id(coord: Vector3i, index: int) -> String:
	# Stable entity ids are the authority key for "one pickup, one winner".
	# The future host mutation store records these ids after collection; clients
	# never infer ownership from whether a mesh is currently loaded.
	return "%s:PICKUP:%d" % [chunk_id(coord), index]


func _maze_grid(coord: Vector3i) -> Array:
	var grid := []
	for z in CHUNK_SIZE:
		var row := []
		row.resize(CHUNK_SIZE)
		row.fill(1)
		grid.append(row)
	var rng := SeededRandom.new("%s:MAZE:%s" % [world_seed, chunk_id(coord)])
	var start := Vector2i(7, 7)
	var stack := [start]
	var visited := {start: true}
	grid[start.y][start.x] = 0
	while not stack.is_empty():
		var current: Vector2i = stack[-1]
		var options := []
		for direction in [Vector2i(2, 0), Vector2i(-2, 0),
				Vector2i(0, 2), Vector2i(0, -2)]:
			var next: Vector2i = current + direction
			if next.x >= 1 and next.y >= 1 and next.x <= 13 and next.y <= 13 \
					and not visited.has(next):
				options.append(next)
		if options.is_empty():
			stack.pop_back()
			continue
		var next: Vector2i = options[rng.next_index(options.size())]
		visited[next] = true
		var between: Vector2i = (current + next) / 2
		grid[between.y][between.x] = 0
		grid[next.y][next.x] = 0
		stack.append(next)
	return grid


func _carve_edges(grid: Array, edges: Dictionary) -> void:
	for offset in edges["west"]:
		for x in range(0, 2):
			grid[offset][x] = 0
	for offset in edges["east"]:
		for x in range(13, CHUNK_SIZE):
			grid[offset][x] = 0
	for offset in edges["north"]:
		for z in range(0, 2):
			grid[z][offset] = 0
	for offset in edges["south"]:
		for z in range(13, CHUNK_SIZE):
			grid[z][offset] = 0


func _carve_to_center(grid: Array, cell: Vector2i) -> void:
	var cursor := cell
	while cursor.x != 7:
		grid[cursor.y][cursor.x] = 0
		cursor.x += -1 if cursor.x > 7 else 1
	while cursor.y != 7:
		grid[cursor.y][cursor.x] = 0
		cursor.y += -1 if cursor.y > 7 else 1
	grid[7][7] = 0


func _carve_safe_room(grid: Array) -> void:
	for z in range(5, 10):
		for x in range(5, 10):
			grid[z][x] = 0


func _pickups(coord: Vector3i, grid: Array, stairs: Array, safe: bool) -> Array:
	if safe:
		return []
	var excluded := {}
	for stair in stairs:
		excluded[stair["cell"]] = true
	var candidates := []
	for z in range(1, CHUNK_SIZE - 1):
		for x in range(1, CHUNK_SIZE - 1):
			var cell := Vector2i(x, z)
			if grid[z][x] == 0 and not excluded.has(cell):
				candidates.append(cell)
	var rng := SeededRandom.new("%s:PICKUPS:%s" % [world_seed, chunk_id(coord)])
	var count := 1 if rng.next_float() < 0.34 else 0
	var result := []
	for index in count:
		if candidates.is_empty():
			break
		var pick_index := rng.next_index(candidates.size())
		var cell: Vector2i = candidates[pick_index]
		candidates.remove_at(pick_index)
		result.append({
			"id": pickup_id(coord, index),
			"cell": cell,
			"item": PICKUP_TYPES[rng.next_index(PICKUP_TYPES.size())],
		})
	return result


static func _stair_style(biome: String) -> String:
	match biome:
		"mansion":
			return "grand_foyer"
		"hotel":
			return "hotel_stairwell"
		"apartment":
			return "apartment_stairwell"
		_:
			return "service_stairs"
