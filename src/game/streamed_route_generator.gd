class_name StreamedRouteGenerator
extends RefCounted

## Deterministic foundation for the endless route. This class intentionally
## owns topology/data only; StreamedFacilityView3D consumes it for the solo
## debug playtest while FacilityView3D remains the shipping fixed-floor view.
## Keeping the seam contract pure makes host authority and persistence testable.

const CHUNK_SIZE := 32
const BIOME_REGION_SIZE := 4
const CHUNK_CACHE_LIMIT := 192
const BIOMES := ["maze", "mansion", "hotel", "apartment", "beach", "gothic",
	"prison", "inferno"]
const EDGE_OFFSETS := [3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29]
## Keep vertical links far enough from the chunk centre to fit the physical
## eight-metre flight used by StreamedFacilityView3D. Ordinary door seams may
## still use every odd offset above.
const STAIR_OFFSETS := [3, 5, 7, 25, 27, 29]
const ROOM_SIZES := [Vector2i(3, 3), Vector2i(3, 5), Vector2i(5, 5),
	Vector2i(5, 7), Vector2i(7, 5), Vector2i(9, 9), Vector2i(11, 13),
	Vector2i(13, 11), Vector2i(15, 15)]
const PICKUP_TYPES := ["flashlight", "taser", "lockpick", "crowbar", "rescue_axe"]
const REGION_PROP_SETS := {
	"maze": [
		{"type": "serverRack", "size": Vector3(.8, 2.0, .55)},
		{"type": "supplyCrates", "size": Vector3(1.4, 1.0, .8)},
		{"type": "vendingMachine", "size": Vector3(.85, 1.9, .6)},
	],
	"mansion": [
		{"type": "mansionBookshelf", "size": Vector3(1.5, 2.1, .45)},
		{"type": "loungeCouch", "size": Vector3(1.8, 1.0, .8)},
		{"type": "diningSideboard", "size": Vector3(1.4, 1.1, .5)},
	],
	"hotel": [
		{"type": "singleBed", "size": Vector3(1.0, .75, 2.0)},
		{"type": "bedroomWardrobe", "size": Vector3(1.2, 2.1, .55)},
		{"type": "bedroomNightstand", "size": Vector3(.65, .8, .55)},
	],
	"apartment": [
		{"type": "normalKitchenFridge", "size": Vector3(.85, 2.0, .75)},
		{"type": "normalBookcase", "size": Vector3(1.25, 1.9, .45)},
		{"type": "loungeCouch", "size": Vector3(1.8, 1.0, .8)},
	],
	"beach": [
		{"type": "beachUmbrella", "size": Vector3(.45, 2.35, .45)},
		{"type": "beachChair", "size": Vector3(.75, 1.0, 1.2)},
		{"type": "surfboardRack", "size": Vector3(1.4, 1.7, .55)},
	],
	"gothic": [
		{"type": "gothicBookcase", "size": Vector3(1.4, 2.1, .5)},
		{"type": "gothicHighbackChair", "size": Vector3(.75, 1.6, .75)},
		{"type": "gothicCoffinChest", "size": Vector3(.85, .65, 1.9)},
	],
	"inferno": [
		{"type": "basaltPillar", "size": Vector3(.8, 2.4, .8)},
		{"type": "emberBrazier", "size": Vector3(.8, 1.0, .8)},
		{"type": "magmaCrystalCluster", "size": Vector3(1.0, 1.1, 1.0)},
	],
	"prison": [],
}
## Only hunters whose gimmicks depend on the shared navigation contract (or no
## gimmick at all) enter the streamed route today. Finite-floor objective and
## hiding-place hunters stay in the standard mode until those world entities
## have streamed equivalents.
const STREAMED_HUNTER_IDS := [
	"dovelle", "quirith", "eirys", "xivvy", "thessine", "umbriel",
	"aki", "porcelle", "glyra",
]

var world_seed := "ENDLESS-ROUTE"
var _chunk_cache := {}
var _chunk_cache_order: Array[Vector3i] = []


func _init(seed_text: String = "ENDLESS-ROUTE") -> void:
	world_seed = seed_text if not seed_text.is_empty() else "ENDLESS-ROUTE"


func chunk(coord: Vector3i) -> Dictionary:
	if _chunk_cache.has(coord):
		_chunk_cache_order.erase(coord)
		_chunk_cache_order.append(coord)
		return _chunk_cache[coord]
	var data := _build_chunk(coord)
	_chunk_cache[coord] = data
	_chunk_cache_order.append(coord)
	while _chunk_cache_order.size() > CHUNK_CACHE_LIMIT:
		_chunk_cache.erase(_chunk_cache_order.pop_front())
	return data


func cached_chunk_count() -> int:
	return _chunk_cache.size()


func _build_chunk(coord: Vector3i) -> Dictionary:
	var grid := _maze_grid(coord)
	var region := biome_for(coord)
	var layout := _region_layout(coord, region, grid)
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
	var region_props := _region_props(coord, region, layout["rooms"], safe)
	var pickups := _pickups(coord, grid, stairs, safe, region_props)
	var hunters := _hunter_spawns(coord, grid, stairs, safe, region_props)
	return {
		"schema": 2,
		"coord": coord,
		"chunk_id": chunk_id(coord),
		"biome": region,
		"region": region,
		"rooms": layout["rooms"],
		"corridors": layout["corridors"],
		"difficulty": difficulty_for_level(coord.y),
		"grid": grid,
		"edges": edges,
		"stairs": stairs,
		"safe_room": safe,
		"safe_room_data": safe_room_data(coord) if safe else {},
		"region_props": region_props,
		"pickups": pickups,
		"hunter_spawns": hunters,
	}


func biome_for(coord: Vector3i) -> String:
	# Four-by-four regions read as facility biomes rather than every doorway
	# changing material language. Level participates so a stair can lead into a
	# visibly different wing without destabilising horizontal neighbours.
	var region_x := floori(float(coord.x) / BIOME_REGION_SIZE)
	var region_z := floori(float(coord.z) / BIOME_REGION_SIZE)
	var rng := SeededRandom.new("%s:BIOME:%d:%d:%d" % [
		world_seed, region_x, coord.y, region_z])
	var choices := ["maze", "mansion", "hotel", "apartment"]
	# Upper levels remain recognizable and forgiving. Gothic wings begin below
	# the central floor; Inferno is a deep-only biome and can never leak upward.
	if coord.y <= -1:
		choices.append("gothic")
		choices.append("gothic")
	if coord.y <= -2:
		choices.append("prison")
		choices.append("prison")
	if coord.y <= -3:
		choices.append("inferno")
		choices.append("inferno")
		if coord.y <= -6:
			choices.append("inferno")
	if coord.y >= 2:
		choices.append("hotel")
		choices.append("apartment")
		choices.append("beach")
	elif coord.y >= 0:
		choices.append("beach")
	return choices[rng.next_index(choices.size())]


func difficulty_for_level(level: int) -> Dictionary:
	# Zero is the central arrival floor. Positive levels relax toward a floor,
	# while every step downward adds pursuit pressure without a hard depth cap.
	var danger := clampf(0.48 - float(level) * 0.075, 0.12, 1.0)
	return {
		"level": level,
		"danger": danger,
		"hunter_speed_scale": lerpf(0.86, 1.28, danger),
		"hunter_count_bias": floori(maxf(0.0, -float(level)) / 3.0),
		"safe_room_bias": lerpf(1.45, 0.55, danger),
	}


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
			and int(lower_level) in [-1, 0]
		var rng := SeededRandom.new("%s:STAIR:%d:%d:%d" % [
			world_seed, coord.x, lower_level, coord.z])
		if not forced_origin and rng.next_float() >= 0.24:
			continue
		var cell := Vector2i(
			STAIR_OFFSETS[rng.next_index(STAIR_OFFSETS.size())],
			STAIR_OFFSETS[rng.next_index(STAIR_OFFSETS.size())])
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
	var profile := difficulty_for_level(coord.y)
	return rng.next_float() < 0.055 * float(profile["safe_room_bias"])


func safe_room_data(coord: Vector3i) -> Dictionary:
	var danger := float(difficulty_for_level(coord.y)["danger"])
	return {
		"id": "%s:SAFE" % chunk_id(coord),
		"checkpoint_id": "%s:CHECKPOINT" % chunk_id(coord),
		"max_integrity": 100,
		"breachable": true,
		"repairable": true,
		"breach_pressure": snappedf(lerpf(0.55, 1.65, danger), 0.01),
	}


func spawn_chunk() -> Vector3i:
	return Vector3i.ZERO


func spawn_cell() -> Vector2i:
	return Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)


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


func hunter_id(coord: Vector3i, index: int) -> String:
	return "%s:HUNTER:%d" % [chunk_id(coord), index]


func _maze_grid(coord: Vector3i) -> Array:
	var grid := []
	for z in CHUNK_SIZE:
		var row := []
		row.resize(CHUNK_SIZE)
		row.fill(1)
		grid.append(row)
	var rng := SeededRandom.new("%s:MAZE:%s" % [world_seed, chunk_id(coord)])
	var center := CHUNK_SIZE / 2 - 1
	if center % 2 == 0:
		center -= 1
	var start := Vector2i(center, center)
	var stack := [start]
	var visited := {start: true}
	grid[start.y][start.x] = 0
	while not stack.is_empty():
		var current: Vector2i = stack[-1]
		var options := []
		for direction in [Vector2i(2, 0), Vector2i(-2, 0),
				Vector2i(0, 2), Vector2i(0, -2)]:
			var next: Vector2i = current + direction
			if next.x >= 1 and next.y >= 1 and next.x <= CHUNK_SIZE - 3 \
					and next.y <= CHUNK_SIZE - 3 \
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
		for x in range(CHUNK_SIZE - 3, CHUNK_SIZE):
			grid[offset][x] = 0
	for offset in edges["north"]:
		for z in range(0, 2):
			grid[z][offset] = 0
	for offset in edges["south"]:
		for z in range(CHUNK_SIZE - 3, CHUNK_SIZE):
			grid[z][offset] = 0


func _carve_to_center(grid: Array, cell: Vector2i) -> void:
	var cursor := cell
	var center := CHUNK_SIZE / 2
	while cursor.x != center:
		grid[cursor.y][cursor.x] = 0
		cursor.x += -1 if cursor.x > center else 1
	while cursor.y != center:
		grid[cursor.y][cursor.x] = 0
		cursor.y += -1 if cursor.y > center else 1
	grid[center][center] = 0


func _carve_safe_room(grid: Array) -> void:
	var center := CHUNK_SIZE / 2
	for z in range(center - 3, center + 4):
		for x in range(center - 3, center + 4):
			grid[z][x] = 0


func _region_layout(coord: Vector3i, region: String, grid: Array) -> Dictionary:
	# A region is the multi-chunk visual/gameplay identity. Rooms are the small
	# bounded spaces inside one chunk; corridors serve many rooms and stairs
	# bridge the same circulation network vertically.
	if region in ["hotel", "prison"]:
		return _linear_room_layout(coord, region, grid)
	return _mixed_room_layout(coord, region, grid)


func _linear_room_layout(coord: Vector3i, region: String, grid: Array) -> Dictionary:
	var rooms := []
	var corridors := []
	var center := CHUNK_SIZE / 2
	var hall := Rect2i(1, center - 1, CHUNK_SIZE - 2, 3)
	_carve_rect(grid, hall)
	corridors.append({"id": "%s:HALL:0" % chunk_id(coord), "rect": hall,
		"axis": "east_west", "serves_many_rooms": true})
	var widths := [5, 7, 5, 7] if region == "hotel" else [3, 5, 3, 5, 3]
	var cursor := 2
	var room_index := 0
	for side in [-1, 1]:
		cursor = 2
		for width in widths:
			if cursor + width >= CHUNK_SIZE - 1:
				break
			var depth := 7 if region == "hotel" else 5
			var z := center - 2 - depth if side < 0 else center + 2
			var rect := Rect2i(cursor, z, width, depth)
			_carve_rect(grid, rect)
			var door_x: int = cursor + width / 2
			_carve_corridor(grid, Vector2i(door_x,
				z + depth - 1 if side < 0 else z), Vector2i(door_x, center), 1)
			rooms.append(_room_entry(coord, room_index, region, rect,
				"guest_room" if region == "hotel" else "prison_cell"))
			room_index += 1
			cursor += width + 1
	return {"rooms": rooms, "corridors": corridors}


func _mixed_room_layout(coord: Vector3i, region: String, grid: Array) -> Dictionary:
	var rng := SeededRandom.new("%s:ROOMS:%s" % [world_seed, chunk_id(coord)])
	var rooms := []
	var corridors := []
	var center := CHUNK_SIZE / 2
	var horizontal := Rect2i(1, center, CHUNK_SIZE - 2, 1)
	var vertical := Rect2i(center, 1, 1, CHUNK_SIZE - 2)
	_carve_rect(grid, horizontal)
	_carve_rect(grid, vertical)
	corridors.append({"id": "%s:HALL:0" % chunk_id(coord), "rect": horizontal,
		"axis": "east_west", "serves_many_rooms": true})
	corridors.append({"id": "%s:HALL:1" % chunk_id(coord), "rect": vertical,
		"axis": "north_south", "serves_many_rooms": true})
	var size_pool := ROOM_SIZES
	if region == "mansion":
		size_pool = [Vector2i(9, 9), Vector2i(11, 13), Vector2i(13, 11), Vector2i(15, 15)]
	elif region == "beach":
		size_pool = [Vector2i(9, 9), Vector2i(11, 13), Vector2i(15, 15)]
	elif region in ["gothic", "inferno"]:
		size_pool = [Vector2i(7, 5), Vector2i(9, 9), Vector2i(11, 13)]
	# Each quadrant stops immediately before the crossing hall. The north-west
	# quadrant is a full 15x15 cells, so landmark rooms are not merely catalogued
	# and then silently clipped to the old small-map dimensions.
	var anchors := [Vector2i(1, 1), Vector2i(center + 1, 1),
		Vector2i(1, center + 1), Vector2i(center + 1, center + 1)]
	for room_index in range(2 + rng.next_index(3)):
		var wanted: Vector2i = size_pool[rng.next_index(size_pool.size())]
		var at: Vector2i = anchors[room_index]
		var available := Vector2i(
			center - at.x if at.x < center else CHUNK_SIZE - 1 - at.x,
			center - at.y if at.y < center else CHUNK_SIZE - 1 - at.y)
		var size := Vector2i(mini(wanted.x, available.x),
			mini(wanted.y, available.y))
		var rect := Rect2i(at, size)
		_carve_rect(grid, rect)
		_carve_corridor(grid, Vector2i(at.x + size.x / 2, at.y + size.y / 2),
			Vector2i(center, center), 1)
		rooms.append(_room_entry(coord, room_index, region, rect,
			_room_type_for(region, room_index)))
	return {"rooms": rooms, "corridors": corridors}


func _room_entry(coord: Vector3i, index: int, region: String, rect: Rect2i,
		room_type: String) -> Dictionary:
	return {"id": "%s:ROOM:%d" % [chunk_id(coord), index], "region": region,
		"room_type": room_type, "rect": rect, "size": rect.size,
		"center": rect.position + rect.size / 2}


static func _room_type_for(region: String, index: int) -> String:
	var types := {
		"mansion": ["drawing_room", "bedroom", "dining_room", "gallery"],
		"beach": ["cove", "beach_hut", "tide_pool", "boardwalk_room"],
		"inferno": ["thermal_chamber", "forge", "altar_room", "lava_gallery"],
		"gothic": ["crypt", "chapel", "mourning_room", "archive"],
		"apartment": ["apartment", "laundry", "lounge", "utility_room"],
		"maze": ["maze_room", "relay_room", "storage", "junction"],
	}
	var choices: Array = types.get(region, ["room"])
	return String(choices[index % choices.size()])


static func _carve_rect(grid: Array, rect: Rect2i) -> void:
	for z in range(maxi(1, rect.position.y), mini(CHUNK_SIZE - 1, rect.end.y)):
		for x in range(maxi(1, rect.position.x), mini(CHUNK_SIZE - 1, rect.end.x)):
			grid[z][x] = 0


static func _carve_corridor(grid: Array, from: Vector2i, to: Vector2i,
		width: int) -> void:
	var cursor := from
	while cursor.x != to.x:
		_carve_corridor_cell(grid, cursor, width)
		cursor.x += -1 if cursor.x > to.x else 1
	while cursor.y != to.y:
		_carve_corridor_cell(grid, cursor, width)
		cursor.y += -1 if cursor.y > to.y else 1
	_carve_corridor_cell(grid, to, width)


static func _carve_corridor_cell(grid: Array, cell: Vector2i, width: int) -> void:
	var half := floori(float(width) / 2.0)
	for dz in range(-half, half + 1):
		for dx in range(-half, half + 1):
			var at := cell + Vector2i(dx, dz)
			if at.x > 0 and at.y > 0 and at.x < CHUNK_SIZE - 1 \
					and at.y < CHUNK_SIZE - 1:
				grid[at.y][at.x] = 0


func _region_props(coord: Vector3i, region: String, rooms: Array,
		safe: bool) -> Array:
	if safe or region == "prison" or rooms.is_empty():
		return []
	var choices: Array = REGION_PROP_SETS.get(region, REGION_PROP_SETS["maze"])
	if choices.is_empty():
		return []
	var rng := SeededRandom.new("%s:DRESSING:%s" % [world_seed, chunk_id(coord)])
	var result := []
	for index in mini(2, rooms.size()):
		var room: Dictionary = rooms[index]
		var rect: Rect2i = room.get("rect", Rect2i())
		if rect.size.x < 3 or rect.size.y < 3:
			continue
		var choice: Dictionary = choices[rng.next_index(choices.size())]
		var cell := rect.position + Vector2i(1, 1)
		# Alternate corners so a long hotel hall reads as occupied rooms without
		# filling the room centre or its door approach.
		if index % 2 == 1:
			cell = rect.end - Vector2i(2, 2)
		result.append({"id": "%s:PROP:%d" % [chunk_id(coord), index],
			"type": String(choice.get("type", "supplyCrates")), "cell": cell,
			"yaw": float(rng.next_index(4)) * PI * .5,
			"blocker_size": choice.get("size", Vector3.ONE)})
	return result


func _pickups(coord: Vector3i, grid: Array, stairs: Array, safe: bool,
		region_props: Array = []) -> Array:
	if safe:
		return []
	var excluded := {}
	for stair in stairs:
		excluded[stair["cell"]] = true
	for prop in region_props:
		excluded[prop.get("cell", Vector2i.ZERO)] = true
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


func _hunter_spawns(coord: Vector3i, grid: Array, stairs: Array,
		safe: bool, region_props: Array = []) -> Array:
	# The arrival floor gets a three-by-three grace region so a new run cannot
	# load into a capture. Beyond it, pressure is sparse but unbounded: explored
	# chunks deterministically own their hunter entity just like their pickups.
	if safe or (coord.y == 0 and absi(coord.x) <= 1 and absi(coord.z) <= 1):
		return []
	var profile := difficulty_for_level(coord.y)
	var danger := float(profile["danger"])
	var rng := SeededRandom.new("%s:HUNTERS:%s" % [world_seed, chunk_id(coord)])
	var spawn_chance := lerpf(0.08, 0.24, danger)
	if rng.next_float() >= spawn_chance:
		return []
	var excluded := {}
	for stair in stairs:
		var stair_cell: Vector2i = stair["cell"]
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				excluded[stair_cell + Vector2i(dx, dz)] = true
	for prop in region_props:
		var prop_cell: Vector2i = prop.get("cell", Vector2i.ZERO)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				excluded[prop_cell + Vector2i(dx, dz)] = true
	var candidates: Array[Vector2i] = []
	for z in range(3, CHUNK_SIZE - 3):
		for x in range(3, CHUNK_SIZE - 3):
			var cell := Vector2i(x, z)
			if grid[z][x] == 0 and not excluded.has(cell) \
					and _open_spawn_neighbourhood(grid, cell):
				candidates.append(cell)
	if candidates.is_empty():
		return []
	var count := 1
	if coord.y <= -6 and rng.next_float() < minf(0.22, danger * 0.18):
		count = 2
	var result := []
	for index in count:
		if candidates.is_empty():
			break
		var picked := rng.next_index(candidates.size())
		var cell: Vector2i = candidates.pop_at(picked)
		var identity: String = STREAMED_HUNTER_IDS[rng.next_index(
			STREAMED_HUNTER_IDS.size())]
		# Deep floors can gain an additional aggressive Void identity, but the
		# arrival and upper route never roll one.
		if coord.y <= -2 and rng.next_float() < lerpf(0.04, 0.30, danger):
			identity = HunterRoster.VOID_IDS[rng.next_index(HunterRoster.VOID_IDS.size())]
		result.append({
			"id": hunter_id(coord, index),
			"hunter_id": identity,
			"cell": cell,
			"level": coord.y,
			"origin_chunk": coord,
		})
	return result


static func _open_spawn_neighbourhood(grid: Array, cell: Vector2i) -> bool:
	for offset in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT,
			Vector2i.UP, Vector2i.DOWN]:
		var at: Vector2i = cell + (offset as Vector2i)
		if at.x < 0 or at.y < 0 or at.x >= CHUNK_SIZE or at.y >= CHUNK_SIZE \
				or int(grid[at.y][at.x]) != 0:
			return false
	return true


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
