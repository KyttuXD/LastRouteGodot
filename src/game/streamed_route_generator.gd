class_name StreamedRouteGenerator
extends RefCounted

## Deterministic foundation for the endless route. This class intentionally
## owns topology/data only; StreamedFacilityView3D consumes it for the solo
## debug playtest while FacilityView3D remains the shipping fixed-floor view.
## Keeping the seam contract pure makes host authority and persistence testable.

## One streamed chunk is deliberately the same footprint as the original
## Standard finite floor. That gives each newly generated piece enough room
## for the familiar central lobby, bounded rooms and three-wide halls instead
## of stretching a tiny maze cell pattern into an open parking structure.
const CHUNK_SIZE := 45
## Level zero is a compact, finite 3x3 arrival floor. Each piece retains the
## finite route's room-and-corridor grammar; stairs lead into the genuinely
## unbounded upper and lower levels.
const ARRIVAL_FLOOR_RADIUS := 1
const BIOME_REGION_SIZE := 4
const CHUNK_CACHE_LIMIT := 192
const BIOMES := ["maze", "mansion", "hotel", "apartment", "beach", "gothic",
	"prison", "inferno"]
const EDGE_OFFSETS := [5, 11, 17, 22, 27, 33, 39]
## Keep vertical links far enough from the chunk centre to fit the physical
## eight-metre flight used by StreamedFacilityView3D. Ordinary door seams may
## still use every odd offset above.
## Stair anchors sit inside one of four reserved room sectors. Keeping them
## away from the outer edge lane and central hall leaves enough wall shoulder
## for a real stairwell instead of dropping a flight into an ordinary room.
## Stair links are shared by the two chunks on either side of a vertical
## boundary, so their placement must depend only on that canonical boundary.
## Even and odd boundaries use opposite diagonal bay pairs. A chunk can
## therefore contain both an up and a down link without ever stacking two
## flights, landings, or slab openings inside the same stairwell room.
const STAIR_BAY_ANCHORS := {
	0: [Vector2i(8, 8), Vector2i(12, 8), Vector2i(8, 12), Vector2i(12, 12)],
	1: [Vector2i(32, 8), Vector2i(36, 8), Vector2i(32, 12), Vector2i(36, 12)],
	2: [Vector2i(8, 32), Vector2i(12, 32), Vector2i(8, 36), Vector2i(12, 36)],
	3: [Vector2i(32, 32), Vector2i(36, 32), Vector2i(32, 36), Vector2i(36, 36)],
}
const STAIR_BAYS_BY_BOUNDARY_PARITY := {
	0: [0, 3],
	1: [1, 2],
}
const STAIR_RUN_CELLS := 8
const CORRIDOR_WIDTH := 3
const STAIR_ACCESS_WIDTH := 5
const ROOM_SIZES := [Vector2i(3, 3), Vector2i(3, 5), Vector2i(5, 5),
	Vector2i(5, 7), Vector2i(7, 5), Vector2i(9, 9), Vector2i(11, 13),
	Vector2i(13, 11), Vector2i(15, 15)]
const PICKUP_TYPES := ["flashlight", "taser", "lockpick", "crowbar", "rescue_axe"]
const BACKPACK_TYPES := ["backpack_small", "backpack_medium", "backpack_large"]
const REGION_PROP_SETS := {
	"maze": [
		{"type": "serverRack", "size": Vector3(.8, 2.0, .55)},
		{"type": "supplyCrates", "size": Vector3(1.4, 1.0, .8)},
		{"type": "vendingMachine", "size": Vector3(.85, 1.9, .6)},
		{"type": "woodenChair", "size": Vector3(.65, 1.1, .65)},
		{"type": "loungeCouchWide", "size": Vector3(1.8, 1.0, .8)},
		{"type": "normalPictureFrameEmpty", "size": Vector3(.7, .9, .12), "solid": false},
	],
	"mansion": [
		{"type": "mansionBookshelf", "size": Vector3(1.5, 2.1, .45)},
		{"type": "loungeCouchWide", "size": Vector3(1.8, 1.0, .8)},
		{"type": "diningSideboard", "size": Vector3(1.4, 1.1, .5)},
		{"type": "diningChair", "size": Vector3(.65, 1.2, .65)},
		{"type": "singleBed", "size": Vector3(1.0, .75, 2.0)},
		{"type": "mansionAreaRug", "size": Vector3(2.6, .03, 1.6), "solid": false},
		{"type": "bathroomMirror", "size": Vector3(.85, 1.4, .14), "solid": false},
		{"type": "luxuryPictureFrameEmpty", "size": Vector3(.75, 1.0, .12), "solid": false},
		{"type": "luxuryPaintingFrameEmpty", "size": Vector3(1.2, 1.55, .12), "solid": false},
	],
	"hotel": [
		{"type": "singleBed", "size": Vector3(1.0, .75, 2.0)},
		{"type": "bedroomWardrobe", "size": Vector3(1.2, 2.1, .55)},
		{"type": "bedroomNightstand", "size": Vector3(.65, .8, .55)},
		{"type": "loungeCouchWide", "size": Vector3(1.8, 1.0, .8)},
		{"type": "woodenChairCushion", "size": Vector3(.65, 1.1, .65)},
		{"type": "hotelCarpet", "size": Vector3(2.2, .03, 1.4), "solid": false},
		{"type": "bathroomMirror", "size": Vector3(.85, 1.4, .14), "solid": false},
		{"type": "luxuryPictureFrameEmpty", "size": Vector3(.75, 1.0, .12), "solid": false},
		{"type": "luxuryPaintingFrameEmpty", "size": Vector3(1.2, 1.55, .12), "solid": false},
	],
	"apartment": [
		{"type": "normalKitchenFridge", "size": Vector3(.85, 2.0, .75)},
		{"type": "normalBookcase", "size": Vector3(1.25, 1.9, .45)},
		{"type": "loungeCouchWide", "size": Vector3(1.8, 1.0, .8)},
		{"type": "singleBed", "size": Vector3(1.0, .75, 2.0)},
		{"type": "woodenChair", "size": Vector3(.65, 1.1, .65)},
		{"type": "apartmentCarpet", "size": Vector3(2.0, .03, 1.35), "solid": false},
		{"type": "bathroomMirror", "size": Vector3(.85, 1.4, .14), "solid": false},
		{"type": "normalPictureFrameEmpty", "size": Vector3(.7, .9, .12), "solid": false},
		{"type": "normalPaintingFrameEmpty", "size": Vector3(1.2, 1.5, .12), "solid": false},
	],
	"beach": [
		{"type": "beachUmbrella", "size": Vector3(.45, 2.35, .45)},
		{"type": "beachChair", "size": Vector3(.75, 1.0, 1.2)},
		{"type": "surfboardRack", "size": Vector3(1.4, 1.7, .55)},
		{"type": "beachMat", "size": Vector3(1.4, .03, .85), "solid": false},
	],
	"gothic": [
		{"type": "gothicBookcase", "size": Vector3(1.4, 2.1, .5)},
		{"type": "gothicHighbackChair", "size": Vector3(.75, 1.6, .75)},
		{"type": "gothicCoffinChest", "size": Vector3(.85, .65, 1.9)},
		{"type": "gothicDoubleBed", "size": Vector3(1.8, .9, 2.2)},
		{"type": "gothicBedroomBench", "size": Vector3(1.4, .7, .55)},
		{"type": "gothicBedroomRug", "size": Vector3(2.2, .03, 1.4), "solid": false},
		{"type": "gothicPictureFrameEmpty", "size": Vector3(.75, 1.0, .12), "solid": false},
		{"type": "gothicPaintingFrameEmpty", "size": Vector3(1.2, 1.55, .12), "solid": false},
	],
	"inferno": [
		{"type": "basaltPillar", "size": Vector3(.8, 2.4, .8)},
		{"type": "emberBrazier", "size": Vector3(.8, 1.0, .8)},
		{"type": "magmaCrystalCluster", "size": Vector3(1.0, 1.1, 1.0)},
	],
	"prison": [],
}
const REGION_ROOM_DOORS := {
	"apartment": "normalRoomDoor",
	"hotel": "luxuryRoomDoor",
	"mansion": "luxuryRoomDoor",
	"gothic": "gothicRoomDoor",
}
## Only hunters whose gimmicks depend on the shared navigation contract (or no
## gimmick at all) enter the streamed route today. Finite-floor objective and
## hiding-place hunters stay in the standard mode until those world entities
## have streamed equivalents.
const STREAMED_HUNTER_IDS := [
	"dovelle", "quirith", "eirys", "xivvy", "thessine", "umbriel",
	"aki", "porcelle", "glyra", "haelith", "opalie", "ysolde",
	"briselle", "verrine",
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
	if not is_chunk_allowed(coord):
		return {"schema": 2, "coord": coord, "chunk_id": chunk_id(coord),
			"biome": "sealed", "region": "sealed", "rooms": [], "corridors": [],
			"grid": _solid_grid(), "edges": {"west": [], "east": [],
				"north": [], "south": []}, "stairs": [], "safe_room": false,
			"safe_room_data": {}, "region_props": [], "fixtures": [],
			"pickups": [], "hunter_spawns": [],
			"difficulty": difficulty_for_level(coord.y)}
	var grid := _solid_grid()
	var region := biome_for(coord)
	# Vertical links participate in room planning. When layout ran first, its
	# rooms could be carved directly through the later stair footprint.
	var stairs := stair_links(coord)
	var layout := _region_layout(coord, region, grid, stairs)
	# This mask is presentation-independent circulation space: central halls,
	# room connectors, chunk seams and stair approaches. Solid dressing must
	# never consume it, even though all of those cells are ordinary floor in the
	# structural GridMap.
	var circulation: Dictionary = layout.get("circulation", {})
	var edges := {
		"west": edge_openings(coord, Vector2i(-1, 0)),
		"east": edge_openings(coord, Vector2i(1, 0)),
		"north": edge_openings(coord, Vector2i(0, -1)),
		"south": edge_openings(coord, Vector2i(0, 1)),
	}
	var edge_corridors := _carve_edges(grid, edges, layout["rooms"], circulation)
	(layout["corridors"] as Array).append_array(edge_corridors)
	for stair in stairs:
		_carve_stair_access(grid, stair, layout["rooms"], circulation)
	# Perimeter seams and stair approaches are carved after the room banks. They
	# must never punch a second opening through a room which already owns one
	# canonical branch doorway. Rebuild each ordinary room's boundary now that
	# all shared circulation is known; stairwell rooms retain their wide flights.
	_restore_single_room_thresholds(grid, layout["rooms"])
	var safe := is_safe_room(coord)
	if safe:
		_carve_safe_room(grid)
	var region_props := _region_props(coord, region, layout["rooms"], grid, safe,
		stairs, circulation)
	var fixtures := _fixtures(coord, grid, layout["rooms"], stairs,
		region_props, safe)
	var pickups := _pickups(coord, grid, stairs, safe, region_props, fixtures)
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
		"fixtures": fixtures,
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
	var neighbour := coord + Vector3i(direction.x, 0, direction.y)
	if not is_chunk_allowed(coord) or not is_chunk_allowed(neighbour):
		return []
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
		# Consecutive boundaries meet inside this chunk. Put them in disjoint
		# stairwell sectors while retaining canonical agreement with the chunk
		# above/below that describes the same physical flight.
		var boundary_parity := posmod(int(lower_level), 2)
		var allowed_bays: Array = STAIR_BAYS_BY_BOUNDARY_PARITY[boundary_parity]
		var bay_index: int = allowed_bays[rng.next_index(allowed_bays.size())]
		var bay_anchors: Array = STAIR_BAY_ANCHORS[bay_index]
		var cell: Vector2i = bay_anchors[rng.next_index(bay_anchors.size())]
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


func is_chunk_allowed(coord: Vector3i) -> bool:
	return coord.y != 0 or (absi(coord.x) <= ARRIVAL_FLOOR_RADIUS \
		and absi(coord.z) <= ARRIVAL_FLOOR_RADIUS)


func coordinates_around(world_xz: Vector2, level: int, radius: int = 2) -> Array:
	var center := Vector2i(floori(world_xz.x / CHUNK_SIZE),
		floori(world_xz.y / CHUNK_SIZE))
	var result := []
	for z in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var coord := Vector3i(x, level, z)
			if is_chunk_allowed(coord):
				result.append(coord)
	return result


func chunk_id(coord: Vector3i) -> String:
	return "%d:%d:%d" % [coord.x, coord.y, coord.z]


func pickup_id(coord: Vector3i, index: int, kind: String = "tool") -> String:
	# Stable entity ids are the authority key for "one pickup, one winner".
	# The future host mutation store records these ids after collection; clients
	# never infer ownership from whether a mesh is currently loaded.
	return "%s:PICKUP:%s:%d" % [chunk_id(coord), kind.to_upper(), index]


func hunter_id(coord: Vector3i, index: int) -> String:
	return "%s:HUNTER:%d" % [chunk_id(coord), index]


func _solid_grid() -> Array:
	var grid := []
	for z in CHUNK_SIZE:
		var row := []
		row.resize(CHUNK_SIZE)
		row.fill(1)
		grid.append(row)
	return grid


func _carve_edges(grid: Array, edges: Dictionary, rooms: Array,
		circulation: Dictionary = {}) -> Array:
	var corridors := []
	var center := CHUNK_SIZE / 2
	for side in ["west", "east", "north", "south"]:
		for offset_value in edges[side]:
			var offset := int(offset_value)
			var start := Vector2i(1, offset)
			match side:
				"east":
					start = Vector2i(CHUNK_SIZE - 2, offset)
				"north":
					start = Vector2i(offset, 1)
				"south":
					start = Vector2i(offset, CHUNK_SIZE - 2)
			for spread in range(-1, 2):
				if side == "west":
					grid[offset + spread][0] = 0
				elif side == "east":
					grid[offset + spread][CHUNK_SIZE - 1] = 0
				elif side == "north":
					grid[0][offset + spread] = 0
				else:
					grid[CHUNK_SIZE - 1][offset + spread] = 0
			# Enter an outer three-wide lane first, then join the canonical central
			# cross. Routing a seam straight to a room centre used to cut across
			# unrelated rooms and merge most of a chunk into one irregular blob.
			var lane := start
			var junction := Vector2i(center, center)
			if side == "west" or side == "east":
				lane.x = 2 if side == "west" else CHUNK_SIZE - 3
				var hall_entry := Vector2i(lane.x, center)
				_carve_corridor_segment(grid, circulation, start, lane)
				_carve_corridor_segment(grid, circulation, lane, hall_entry)
				_carve_corridor_segment(grid, circulation, hall_entry, junction)
			else:
				lane.y = 2 if side == "north" else CHUNK_SIZE - 3
				var hall_entry := Vector2i(center, lane.y)
				_carve_corridor_segment(grid, circulation, start, lane)
				_carve_corridor_segment(grid, circulation, lane, hall_entry)
				_carve_corridor_segment(grid, circulation, hall_entry, junction)
			corridors.append({
				"id": "EDGE:%s:%d" % [side, offset],
				"axis": side,
				"from_perimeter": true,
				"room_id": "",
				"width": CORRIDOR_WIDTH,
				"length": absi(start.x - junction.x) + absi(start.y - junction.y),
			})
	return corridors


static func _carve_corridor_segment(grid: Array, circulation: Dictionary,
		from: Vector2i, to: Vector2i) -> void:
	_carve_corridor(grid, from, to, CORRIDOR_WIDTH)
	_mark_corridor_cells(circulation, from, to, CORRIDOR_WIDTH)


func _nearest_perimeter_room(rooms: Array, side: String,
		offset: int) -> Dictionary:
	var chosen := {}
	var best_score := INF
	for room_value in rooms:
		var room: Dictionary = room_value
		if String(room.get("room_type", "")) == "lobby":
			continue
		var rect: Rect2i = room.get("rect", Rect2i())
		if rect.size.x <= 0 or rect.size.y <= 0:
			continue
		var anchor := rect.position + rect.size / 2
		var edge_distance := 0
		var cross_distance := 0
		match side:
			"west":
				anchor = Vector2i(rect.position.x,
					clampi(offset, rect.position.y + 1, rect.end.y - 2))
				edge_distance = rect.position.x
				cross_distance = absi(offset - anchor.y)
			"east":
				anchor = Vector2i(rect.end.x - 1,
					clampi(offset, rect.position.y + 1, rect.end.y - 2))
				edge_distance = CHUNK_SIZE - rect.end.x
				cross_distance = absi(offset - anchor.y)
			"north":
				anchor = Vector2i(clampi(offset, rect.position.x + 1,
					rect.end.x - 2), rect.position.y)
				edge_distance = rect.position.y
				cross_distance = absi(offset - anchor.x)
			"south":
				anchor = Vector2i(clampi(offset, rect.position.x + 1,
					rect.end.x - 2), rect.end.y - 1)
				edge_distance = CHUNK_SIZE - rect.end.y
				cross_distance = absi(offset - anchor.x)
		var score := edge_distance * 4 + cross_distance
		if score < best_score:
			best_score = score
			chosen = {"anchor": anchor, "room_id": String(room.get("id", ""))}
	return chosen


static func stair_path_cells(cell: Vector2i) -> Array[Vector2i]:
	var center := Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)
	var delta := center - cell
	var direction := Vector2i(signi(delta.x), 0) \
		if abs(delta.x) >= abs(delta.y) else Vector2i(0, signi(delta.y))
	var result: Array[Vector2i] = []
	for index in range(STAIR_RUN_CELLS + 1):
		result.append(cell + direction * index)
	return result


static func stair_bay_index(cell: Vector2i) -> int:
	return (1 if cell.x > CHUNK_SIZE / 2 else 0) \
		+ (2 if cell.y > CHUNK_SIZE / 2 else 0)


static func stair_access_cells(cell: Vector2i) -> Array[Vector2i]:
	var path := stair_path_cells(cell)
	var result: Array[Vector2i] = []
	var occupied := {}
	var travel := path[1] - path[0] if path.size() > 1 else Vector2i.RIGHT
	var across := Vector2i(-travel.y, travel.x)
	for path_cell in path:
		for offset in range(-STAIR_ACCESS_WIDTH / 2, STAIR_ACCESS_WIDTH / 2 + 1):
			var cell_at: Vector2i = path_cell + across * offset
			if occupied.has(cell_at):
				continue
			occupied[cell_at] = true
			result.append(cell_at)
	return result


func _carve_stair_access(grid: Array, stair: Dictionary, rooms: Array,
		circulation: Dictionary = {}) -> void:
	var cell: Vector2i = stair.get("cell", Vector2i.ZERO)
	var path := stair_path_cells(cell)
	# The visible flight and its smooth collision ramp occupy the full path at
	# almost two cells wide. Carve that footprint explicitly before connecting
	# it to the room network; a generic cell-to-room corridor can turn away from
	# the flight and leave a solid wall halfway up it.
	for path_cell in path:
		_carve_corridor_cell(grid, path_cell, STAIR_ACCESS_WIDTH)
		_mark_corridor_cell(circulation, path_cell, STAIR_ACCESS_WIDTH)
	var connector: Vector2i = path[0] if String(stair.get("direction", "")) == "up" \
		else path[-1]
	var center := CHUNK_SIZE / 2
	# Join the nearest arm of the same three-wide hall cross as rooms and chunk
	# seams. A stair-to-room-centre path could bisect several rooms and was a
	# major source of the malformed map silhouettes seen in fullscreen view.
	var horizontal_target := Vector2i(connector.x, center)
	var vertical_target := Vector2i(center, connector.y)
	var target := horizontal_target if absi(connector.y - center) \
		<= absi(connector.x - center) else vertical_target
	_carve_corridor(grid, connector, target, CORRIDOR_WIDTH)
	_mark_corridor_cells(circulation, connector, target, CORRIDOR_WIDTH)


func _carve_safe_room(grid: Array) -> void:
	var center := CHUNK_SIZE / 2
	# The central halls already provide a generous safe lobby. Limit the extra
	# opening to five cells so it cannot punch diagonal entrances through the
	# inner corners of neighbouring rooms.
	for z in range(center - 2, center + 3):
		for x in range(center - 2, center + 3):
			grid[z][x] = 0


func _region_layout(coord: Vector3i, region: String, grid: Array,
		stairs: Array = []) -> Dictionary:
	# A region is the multi-chunk visual/gameplay identity. Rooms are the small
	# bounded spaces inside one chunk; corridors serve many rooms and stairs
	# bridge the same circulation network vertically.
	if region in ["hotel", "prison"]:
		return _linear_room_layout(coord, region, grid, stairs)
	return _mixed_room_layout(coord, region, grid, stairs)


func _linear_room_layout(coord: Vector3i, region: String, grid: Array,
		stairs: Array = []) -> Dictionary:
	var rooms := []
	var corridors := []
	var circulation := {}
	var center := CHUNK_SIZE / 2
	var horizontal_hall := Rect2i(1, center - 1, CHUNK_SIZE - 2, 3)
	var vertical_hall := Rect2i(center - 1, 1, 3, CHUNK_SIZE - 2)
	for hall in [horizontal_hall, vertical_hall]:
		_carve_rect(grid, hall)
		_mark_rect_cells(circulation, hall)
	corridors.append({"id": "%s:HALL:0" % chunk_id(coord),
		"rect": horizontal_hall, "width": CORRIDOR_WIDTH,
		"axis": "east_west", "serves_many_rooms": true})
	corridors.append({"id": "%s:HALL:1" % chunk_id(coord),
		"rect": vertical_hall, "width": CORRIDOR_WIDTH,
		"axis": "north_south", "serves_many_rooms": true})
	# Two room banks on either side of the north/south hall. Keeping the
	# three-wide centre reservation out of every room prevents a vertical seam
	# or stair connector from slicing a guest room in half.
	var room_columns := [Vector2i(5, 5), Vector2i(11, 7),
		Vector2i(25, 7), Vector2i(33, 5)]
	var stair_bays := _stairwell_bays(stairs)
	var room_index := 0
	for side in [-1, 1]:
		for column in room_columns:
			var cursor: int = column.x
			var width: int = column.y
			var depth := 7 if region == "hotel" else 5
			var z := center - 2 - depth if side < 0 else center + 3
			var rect := Rect2i(cursor, z, width, depth)
			if stair_bays.values().any(func(stair_rect: Rect2i) -> bool:
				return stair_rect.intersects(rect)):
				continue
			_carve_rect(grid, rect)
			var room_rng := SeededRandom.new("%s:ROOM-BRANCH:%d:%d" % [
				chunk_id(coord), side, room_index])
			var connection := _connect_room_to_main_hall(grid, circulation,
				rect, 0 if side < 0 else 2, room_rng, "north_south")
			corridors.append({
				"id": "%s:ROOM-BRANCH:%d" % [chunk_id(coord), room_index],
				"axis": String(connection["axis"]),
				"width": CORRIDOR_WIDTH,
				"length": int(connection["length"]),
				"branch": true,
				"from_main_hall": true,
				"serves_many_rooms": false,
				"doorway": connection["doorway"],
			})
			var room_entry := _room_entry(coord, room_index, region, rect,
				"guest_room" if region == "hotel" else "prison_cell")
			room_entry["doorway"] = connection["doorway"]
			rooms.append(room_entry)
			room_index += 1
	for bay_index_value in stair_bays:
		var bay_index := int(bay_index_value)
		var stair_rect: Rect2i = stair_bays[bay_index]
		_carve_rect(grid, stair_rect)
		var stair_rng := SeededRandom.new("%s:STAIRWELL:%d" % [chunk_id(coord), bay_index])
		var connection := _connect_room_to_main_hall(grid, circulation,
			stair_rect, bay_index, stair_rng)
		corridors.append({"id": "%s:STAIR-HALL:%d" % [chunk_id(coord), bay_index],
			"axis": String(connection["axis"]), "width": CORRIDOR_WIDTH,
			"length": int(connection["length"]), "branch": true,
			"from_main_hall": true, "serves_many_rooms": false,
			"doorway": connection["doorway"]})
		var stair_room := _room_entry(coord, room_index, region, stair_rect, "stairwell")
		stair_room["stair_ids"] = _stair_ids_in_bay(stairs, bay_index)
		rooms.append(stair_room)
		room_index += 1
	return {"rooms": rooms, "corridors": corridors,
		"circulation": circulation}


func _mixed_room_layout(coord: Vector3i, region: String, grid: Array,
		stairs: Array = []) -> Dictionary:
	var rng := SeededRandom.new("%s:ROOMS:%s" % [world_seed, chunk_id(coord)])
	var rooms := []
	var corridors := []
	var circulation := {}
	var center := CHUNK_SIZE / 2
	# A canonical three-wide cross divides four bounded room sectors. Earlier
	# centre-to-centre connectors travelled through neighbouring sectors and
	# dissolved their walls into huge irregular open shapes on the map.
	var horizontal_hall := Rect2i(1, center - 1, CHUNK_SIZE - 2, 3)
	var vertical_hall := Rect2i(center - 1, 1, 3, CHUNK_SIZE - 2)
	for hall in [horizontal_hall, vertical_hall]:
		_carve_rect(grid, hall)
		_mark_rect_cells(circulation, hall)
	corridors.append({"id": "%s:HALL:MAIN-X" % chunk_id(coord),
		"rect": horizontal_hall, "width": CORRIDOR_WIDTH,
		"axis": "east_west", "serves_many_rooms": true})
	corridors.append({"id": "%s:HALL:MAIN-Z" % chunk_id(coord),
		"rect": vertical_hall, "width": CORRIDOR_WIDTH,
		"axis": "north_south", "serves_many_rooms": true})
	var sectors := [
		Rect2i(4, 4, 17, 17), Rect2i(24, 4, 17, 17),
		Rect2i(4, 24, 17, 17), Rect2i(24, 24, 17, 17),
	]
	var stair_bays := _stairwell_bays(stairs)
	var size_pool := ROOM_SIZES
	if region == "mansion":
		size_pool = [Vector2i(9, 9), Vector2i(11, 13), Vector2i(13, 11), Vector2i(15, 15)]
	elif region == "beach":
		size_pool = [Vector2i(9, 9), Vector2i(11, 13), Vector2i(15, 15)]
	elif region in ["gothic", "inferno"]:
		size_pool = [Vector2i(7, 5), Vector2i(9, 9), Vector2i(11, 13)]
	for sector_index in sectors.size():
		var sector: Rect2i = sectors[sector_index]
		if stair_bays.has(sector_index):
			var stair_rect: Rect2i = stair_bays[sector_index]
			_carve_rect(grid, stair_rect)
			var stair_connection := _connect_room_to_main_hall(grid,
				circulation, stair_rect, sector_index, rng)
			corridors.append({
				"id": "%s:STAIR-HALL:%d" % [chunk_id(coord), sector_index],
				"axis": String(stair_connection["axis"]),
				"width": CORRIDOR_WIDTH,
				"length": int(stair_connection["length"]),
				"branch": true,
				"from_main_hall": true,
				"serves_many_rooms": false,
				"doorway": stair_connection["doorway"],
			})
			var stair_room := _room_entry(coord, sector_index, region,
				stair_rect, "stairwell")
			stair_room["stair_ids"] = _stair_ids_in_bay(stairs, sector_index)
			rooms.append(stair_room)
			continue
		if sector_index == 0 and region in ["mansion", "beach"]:
			# Pull the landmark away from the central cross so its connector reads
			# as a real secondary hall instead of dissolving into the room edge.
			var landmark_rect := Rect2i(4, 4, 15, 15)
			_carve_rect(grid, landmark_rect)
			var landmark_connection := _connect_room_to_main_hall(grid,
				circulation, landmark_rect, sector_index, rng)
			corridors.append({
				"id": "%s:HALL:%d" % [chunk_id(coord), sector_index],
				"axis": String(landmark_connection["axis"]),
				"width": CORRIDOR_WIDTH,
				"length": int(landmark_connection["length"]),
				"branch": true,
				"from_main_hall": true,
				"serves_many_rooms": false,
				"doorway": landmark_connection["doorway"],
			})
			var landmark_room := _room_entry(coord, sector_index, region,
				landmark_rect, _room_type_for(region, sector_index))
			landmark_room["doorway"] = landmark_connection["doorway"]
			rooms.append(landmark_room)
			continue
		var fitting := size_pool.filter(func(candidate: Vector2i) -> bool:
			return candidate.x <= sector.size.x - 2 \
				and candidate.y <= sector.size.y - 2)
		if fitting.is_empty():
			fitting = [Vector2i(9, 9)]
		var wanted: Vector2i = fitting[rng.next_index(fitting.size())]
		var room_size := Vector2i(mini(wanted.x, sector.size.x - 2),
			mini(wanted.y, sector.size.y - 2))
		# Anchor rooms toward the outer corner of their sector. This guarantees
		# visible secondary branches between the room and the central three-wide
		# cross instead of letting a large room swallow its own connector.
		var at := Vector2i(
			sector.position.x + 1 if sector_index % 2 == 0 \
				else sector.end.x - room_size.x - 1,
			sector.position.y + 1 if sector_index < 2 \
				else sector.end.y - room_size.y - 1)
		var rect := Rect2i(at, room_size)
		_carve_rect(grid, rect)
		var connection := _connect_room_to_main_hall(grid, circulation,
			rect, sector_index, rng)
		corridors.append({
			"id": "%s:HALL:%d" % [chunk_id(coord), sector_index],
			"axis": String(connection["axis"]),
			"width": CORRIDOR_WIDTH,
			"length": int(connection["length"]),
			"branch": true,
			"from_main_hall": true,
			"serves_many_rooms": false,
			"doorway": connection["doorway"],
		})
		var room_entry := _room_entry(coord, sector_index, region, rect,
			_room_type_for(region, sector_index))
		room_entry["doorway"] = connection["doorway"]
		rooms.append(room_entry)
	return {"rooms": rooms, "corridors": corridors,
		"circulation": circulation}


static func _stairwell_bays(stairs: Array) -> Dictionary:
	var result := {}
	for stair_value in stairs:
		var stair: Dictionary = stair_value
		var cell: Vector2i = stair.get("cell", Vector2i.ZERO)
		var index := stair_bay_index(cell)
		# The 17x17 sector retains a one-cell structural wall on all sides;
		# the resulting 15x15 room comfortably encloses the five-wide flight.
		var sector_position := Vector2i(24 if index % 2 == 1 else 4,
			24 if index >= 2 else 4)
		result[index] = Rect2i(sector_position + Vector2i.ONE,
			Vector2i(15, 15))
	return result


static func _stair_ids_in_bay(stairs: Array, bay_index: int) -> Array:
	var result := []
	for stair_value in stairs:
		var stair: Dictionary = stair_value
		var cell: Vector2i = stair.get("cell", Vector2i.ZERO)
		var index := stair_bay_index(cell)
		if index == bay_index:
			result.append(String(stair.get("id", "")))
	return result


static func _connect_room_to_main_hall(grid: Array, circulation: Dictionary,
		rect: Rect2i, sector_index: int, rng: SeededRandom,
		axis_hint: String = "") -> Dictionary:
	var center := CHUNK_SIZE / 2
	var room_center := rect.position + rect.size / 2
	var horizontal_door := Vector2i(
		rect.end.x - 1 if sector_index in [0, 2] else rect.position.x,
		_safe_room_door_coordinate(rect.position.y, rect.end.y, room_center.y))
	var vertical_door := Vector2i(
		_safe_room_door_coordinate(rect.position.x, rect.end.x, room_center.x),
		rect.end.y - 1 if sector_index in [0, 1] else rect.position.y)
	var horizontal_length := absi(horizontal_door.x - center)
	var vertical_length := absi(vertical_door.y - center)
	var connect_horizontally := false
	if axis_hint == "east_west":
		connect_horizontally = true
	elif axis_hint == "north_south":
		connect_horizontally = false
	elif horizontal_length == vertical_length:
		connect_horizontally = rng.next_float() < .5
	else:
		# Prefer the longer route so ordinary rooms have an unmistakable branch
		# off the central hall. The boundary is rebuilt below, so this cannot cut
		# an alternate entrance through a room corner.
		connect_horizontally = horizontal_length > vertical_length
	var start := room_center
	var target := room_center
	if connect_horizontally:
		start = horizontal_door
		target = Vector2i(center, start.y)
	else:
		start = vertical_door
		target = Vector2i(start.x, center)
	_carve_corridor_segment(grid, circulation, start, target)
	_seal_room_perimeter_except(grid, rect, start)
	return {"axis": "east_west" if connect_horizontally else "north_south",
		"length": absi(start.x - target.x) + absi(start.y - target.y),
		"doorway": start, "junction": target}


static func _safe_room_door_coordinate(start: int, finish: int,
		preferred: int) -> int:
	# Three-wide corridors may approach the room, but their final threshold is
	# one centered cell. Preserve at least one wall shoulder on compact rooms
	# and two on rooms wide enough to support a full authored door frame.
	var shoulder := 2 if finish - start >= 5 else 1
	return clampi(preferred, start + shoulder, finish - shoulder - 1)


static func _seal_room_perimeter_except(grid: Array, rect: Rect2i,
		doorway: Vector2i) -> void:
	for x in range(rect.position.x, rect.end.x):
		grid[rect.position.y][x] = 1
		grid[rect.end.y - 1][x] = 1
	for z in range(rect.position.y, rect.end.y):
		grid[z][rect.position.x] = 1
		grid[z][rect.end.x - 1] = 1
	grid[doorway.y][doorway.x] = 0


static func _restore_single_room_thresholds(grid: Array, rooms: Array) -> void:
	for room_value in rooms:
		var room: Dictionary = room_value
		if String(room.get("room_type", "")) == "stairwell":
			continue
		var rect: Rect2i = room.get("rect", Rect2i())
		var doorway = room.get("doorway")
		if rect.size.x <= 0 or rect.size.y <= 0 or not doorway is Vector2i:
			continue
		_seal_room_perimeter_except(grid, rect, doorway)


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


static func _mark_corridor_cells(marked: Dictionary, from: Vector2i,
		to: Vector2i, width: int) -> void:
	var cursor := from
	while cursor.x != to.x:
		_mark_corridor_cell(marked, cursor, width)
		cursor.x += -1 if cursor.x > to.x else 1
	while cursor.y != to.y:
		_mark_corridor_cell(marked, cursor, width)
		cursor.y += -1 if cursor.y > to.y else 1
	_mark_corridor_cell(marked, to, width)


static func _mark_corridor_cell(marked: Dictionary, cell: Vector2i,
		width: int) -> void:
	var half := floori(float(width) / 2.0)
	for dz in range(-half, half + 1):
		for dx in range(-half, half + 1):
			var at := cell + Vector2i(dx, dz)
			if at.x >= 0 and at.y >= 0 and at.x < CHUNK_SIZE \
					and at.y < CHUNK_SIZE:
				marked[at] = true


static func _mark_rect_cells(marked: Dictionary, rect: Rect2i) -> void:
	for z in range(maxi(0, rect.position.y), mini(CHUNK_SIZE, rect.end.y)):
		for x in range(maxi(0, rect.position.x), mini(CHUNK_SIZE, rect.end.x)):
			marked[Vector2i(x, z)] = true


func _region_props(coord: Vector3i, region: String, rooms: Array, grid: Array,
		safe: bool, stairs: Array = [], circulation: Dictionary = {}) -> Array:
	if region == "prison" or rooms.is_empty():
		return []
	var choices: Array = (REGION_PROP_SETS.get(region,
		REGION_PROP_SETS["maze"]) as Array).duplicate()
	if choices.is_empty():
		return []
	var rng := SeededRandom.new("%s:DRESSING:%s" % [world_seed, chunk_id(coord)])
	# Residential doors own true room thresholds, not random room corners. Door
	# candidates must have navigable room and corridor cells on opposite sides,
	# and stair footprints are excluded so access carving cannot leave a door
	# floating beside a stairwell.
	var result := _room_door_props(coord, region, rooms, grid, stairs)
	var reserved := {}
	for door in result:
		reserved[door.get("cell", Vector2i.ZERO)] = true
		for threshold_cell in door.get("threshold_wall_cells", []):
			reserved[threshold_cell] = true
	var wall_mount_exclusion := _stair_door_exclusion(stairs)
	var solid_exclusion := circulation.duplicate()
	# Leave a one-cell shoulder around the authored three-wide route. Wide
	# couches, beds and cabinets can then keep their real collision without
	# pinching the shared hallway down to a player-sized slit.
	for traffic_cell_value in circulation:
		_exclude_neighbourhood(solid_exclusion,
			traffic_cell_value as Vector2i, 1)
	for reserved_cell_value in reserved:
		_exclude_neighbourhood(solid_exclusion,
			reserved_cell_value as Vector2i, 1)
	for stair_cell_value in wall_mount_exclusion:
		solid_exclusion[stair_cell_value] = true
	var prop_count := mini(5 if safe else 8, rooms.size())
	for index in prop_count:
		var room: Dictionary = rooms[index]
		if String(room.get("room_type", "")) == "stairwell":
			continue
		var rect: Rect2i = room.get("rect", Rect2i())
		if rect.size.x < 3 or rect.size.y < 3:
			continue
		var choice: Dictionary = choices[rng.next_index(choices.size())]
		var prop_type := String(choice.get("type", "supplyCrates"))
		if PropModelCatalog.is_wall_mounted(prop_type):
			var mount := _wall_mount_for_room(rect, grid, reserved,
				wall_mount_exclusion, rng)
			if mount.is_empty():
				continue
			var mount_cell: Vector2i = mount["cell"]
			var backing_wall: Vector2i = mount["backing_wall"]
			var open_direction := -backing_wall
			result.append({"id": "%s:PROP:%d" % [chunk_id(coord), index],
				"type": prop_type, "cell": mount_cell,
				"yaw": _room_facing_yaw(mount_cell,
					mount_cell + open_direction),
				"facing_target": mount_cell + open_direction,
				# Move the thin model from the open cell centre to just in front of
				# the wall face. The remaining 6 cm avoids coplanar wall z-fighting.
				"mount_offset": Vector2(backing_wall) * .44,
				"backing_wall": backing_wall,
				"open_direction": open_direction,
				"wall_mounted": true,
				"blocker_size": choice.get("size", Vector3.ONE),
				"solid": false})
			reserved[mount_cell] = true
			continue
		var blocker_size: Vector3 = choice.get("size", Vector3.ONE)
		var solid := bool(choice.get("solid", true))
		var room_center: Vector2i = room.get("center", rect.position + rect.size / 2)
		if not solid:
			# Rugs are intentional room-centred dressing. Wall-mounted art takes the
			# dedicated branch above; neither kind can obstruct circulation.
			result.append({"id": "%s:PROP:%d" % [chunk_id(coord), index],
				"type": prop_type, "cell": room_center, "yaw": 0.0,
				"facing_target": room_center,
				"blocker_size": blocker_size, "solid": false,
				"occupied_cells": []})
			reserved[room_center] = true
			continue
		var placement := _solid_prop_placement(rect, grid, solid_exclusion,
			reserved, blocker_size, rng)
		if placement.is_empty():
			continue
		var cell: Vector2i = placement["cell"]
		var open_direction: Vector2i = placement["open_direction"]
		result.append({"id": "%s:PROP:%d" % [chunk_id(coord), index],
			"type": prop_type, "cell": cell,
			"yaw": _room_facing_yaw(cell, cell + open_direction),
			"facing_target": cell + open_direction,
			"placement_offset": placement["placement_offset"],
			"backing_wall": -open_direction,
			"open_direction": open_direction,
			"blocker_size": blocker_size, "solid": true,
			"occupied_cells": placement["occupied_cells"],
			"corridor_clear": true})
		for occupied_value in placement["occupied_cells"]:
			var occupied: Vector2i = occupied_value
			reserved[occupied] = true
			_exclude_neighbourhood(solid_exclusion, occupied, 1)
	return result


static func _solid_prop_placement(rect: Rect2i, grid: Array,
		excluded: Dictionary, reserved: Dictionary, blocker_size: Vector3,
		rng: SeededRandom) -> Dictionary:
	var candidates := []
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, z)
			if excluded.has(cell) or reserved.has(cell) \
					or not _grid_cell_open(grid, cell) or _wall_count(grid, cell) != 1:
				continue
			var backing_wall := _backing_wall_direction(grid, cell)
			var open_direction := -backing_wall
			if not _grid_cell_open(grid, cell + open_direction):
				continue
			# Authored prop depth is local Z. Keep its rear face five centimetres
			# clear of the wall and move any excess depth into the room.
			var depth_shift := maxf(0.0, blocker_size.z * .5 - .45)
			var placement_offset := Vector2(open_direction) * depth_shift
			var occupied := _prop_occupied_cells(cell, open_direction,
				blocker_size, placement_offset)
			var valid := not occupied.is_empty()
			for occupied_value in occupied:
				var at: Vector2i = occupied_value
				if not rect.has_point(at) or excluded.has(at) or reserved.has(at) \
						or not _grid_cell_open(grid, at):
					valid = false
					break
			if valid:
				candidates.append({"cell": cell,
					"open_direction": open_direction,
					"placement_offset": placement_offset,
					"occupied_cells": occupied})
	if candidates.is_empty():
		return {}
	return candidates[rng.next_index(candidates.size())]


static func _prop_occupied_cells(cell: Vector2i, open_direction: Vector2i,
		blocker_size: Vector3, placement_offset: Vector2) -> Array:
	var center := Vector2(cell) + Vector2(.5, .5) + placement_offset
	var extent := Vector2(blocker_size.x, blocker_size.z) * .5
	if open_direction.x != 0:
		extent = Vector2(blocker_size.z, blocker_size.x) * .5
	var min_cell := Vector2i(floori(center.x - extent.x + .001),
		floori(center.y - extent.y + .001))
	var max_cell := Vector2i(floori(center.x + extent.x - .001),
		floori(center.y + extent.y - .001))
	var result := []
	for z in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			result.append(Vector2i(x, z))
	return result


static func _wall_mount_for_room(rect: Rect2i, grid: Array,
		reserved: Dictionary, excluded: Dictionary, rng: SeededRandom) -> Dictionary:
	var candidates := []
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, z)
			if reserved.has(cell) or excluded.has(cell) \
					or not _grid_cell_open(grid, cell) or _wall_count(grid, cell) != 1:
				continue
			var backing_wall := _backing_wall_direction(grid, cell)
			var open_direction := -backing_wall
			if not _grid_cell_open(grid, cell + open_direction):
				continue
			candidates.append({"cell": cell, "backing_wall": backing_wall})
	if candidates.is_empty():
		return {}
	return candidates[rng.next_index(candidates.size())]


func _room_door_props(coord: Vector3i, region: String, rooms: Array,
		grid: Array, stairs: Array = []) -> Array:
	var door_type := String(REGION_ROOM_DOORS.get(region, ""))
	if door_type.is_empty():
		return []
	var result := []
	var stair_exclusion := _stair_door_exclusion(stairs)
	for room_index in rooms.size():
		if result.size() >= 6:
			break
		var room: Dictionary = rooms[room_index]
		if String(room.get("room_type", "")) in ["lobby", "stairwell"]:
			continue
		var rect: Rect2i = room.get("rect", Rect2i())
		var room_center: Vector2i = room.get("center", rect.position + rect.size / 2)
		var threshold := _find_room_door_threshold(rect, room_center, grid,
			stair_exclusion)
		if threshold.is_empty():
			continue
		var cell: Vector2i = threshold["cell"]
		var wall_cells: Array = threshold["wall_cells"]
		for shoulder_value in wall_cells:
			var shoulder: Vector2i = shoulder_value
			grid[shoulder.y][shoulder.x] = 1
		result.append({
			# Tie persistence to the room index rather than the number of earlier
			# successful candidates. Omitting an invalid door no longer renumbers
			# every later authoritative door in the chunk.
			"id": "%s:DOOR:%d" % [chunk_id(coord), room_index],
			"type": door_type, "cell": cell,
			"yaw": _room_facing_yaw(cell, room_center),
			"facing_target": room_center,
			"blocker_size": Vector3(1.15, 2.3, .2), "solid": false,
			"room_id": String(room.get("id", "")), "room_door": true,
			"inward": threshold["inward"],
			"outward": threshold["outward"],
			"across": threshold["across"],
			"threshold_wall_cells": wall_cells,
		})
	return result


static func _stair_door_exclusion(stairs: Array) -> Dictionary:
	var excluded := {}
	for stair_value in stairs:
		var stair: Dictionary = stair_value
		var path := stair_path_cells(stair.get("cell", Vector2i.ZERO))
		for path_cell in path:
			# The generated approach is five cells wide. One additional cell of
			# clearance keeps the authored frame and its wall shoulders away from
			# both the visible flight and the open slab edge.
			_exclude_neighbourhood(excluded, path_cell, 3)
	return excluded


static func _find_room_door_threshold(rect: Rect2i, room_center: Vector2i,
		grid: Array, excluded: Dictionary) -> Dictionary:
	var candidates := []
	# A threshold cell belongs to the room boundary. Inward remains in the room;
	# outward must leave it and continue through at least two open corridor cells.
	var sides := [
		{"outward": Vector2i.UP, "across": Vector2i.RIGHT},
		{"outward": Vector2i.DOWN, "across": Vector2i.RIGHT},
		{"outward": Vector2i.LEFT, "across": Vector2i.DOWN},
		{"outward": Vector2i.RIGHT, "across": Vector2i.DOWN},
	]
	for side_value in sides:
		var side: Dictionary = side_value
		var outward: Vector2i = side["outward"]
		var inward := -outward
		var across: Vector2i = side["across"]
		var start := rect.position + Vector2i.ONE
		var finish := rect.end - Vector2i.ONE
		var cells := []
		if outward == Vector2i.UP:
			for x in range(start.x, finish.x):
				cells.append(Vector2i(x, rect.position.y))
		elif outward == Vector2i.DOWN:
			for x in range(start.x, finish.x):
				cells.append(Vector2i(x, rect.end.y - 1))
		elif outward == Vector2i.LEFT:
			for z in range(start.y, finish.y):
				cells.append(Vector2i(rect.position.x, z))
		else:
			for z in range(start.y, finish.y):
				cells.append(Vector2i(rect.end.x - 1, z))
		for cell_value in cells:
			var cell: Vector2i = cell_value
			var inward_cell := cell + inward
			var outside_cell := cell + outward
			var corridor_cell := cell + outward * 2
			if not rect.has_point(inward_cell) or rect.has_point(outside_cell):
				continue
			if not _grid_cell_open(grid, cell) \
					or not _grid_cell_open(grid, inward_cell) \
					or not _grid_cell_open(grid, outside_cell) \
					or not _grid_cell_open(grid, corridor_cell):
				continue
			var footprint := [cell, inward_cell, outside_cell, corridor_cell]
			var wall_cells := []
			for offset in range(1, 3):
				for sign_value in [-1, 1]:
					var shoulder := cell + across * offset * int(sign_value)
					if rect.has_point(shoulder):
						wall_cells.append(shoulder)
						footprint.append(shoulder)
			# A real doorway needs a frame on both sides. Five-cell-wide rooms get
			# two wall cells per side; compact three-cell rooms retain one.
			if not wall_cells.has(cell - across) or not wall_cells.has(cell + across):
				continue
			var blocked_by_stair := footprint.any(func(at): return excluded.has(at))
			if blocked_by_stair:
				continue
			candidates.append({
				"cell": cell, "inward": inward, "outward": outward,
				"across": across, "wall_cells": wall_cells,
				"score": cell.distance_squared_to(room_center),
			})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["score"]) != float(b["score"]):
			return float(a["score"]) < float(b["score"])
		var a_cell: Vector2i = a["cell"]
		var b_cell: Vector2i = b["cell"]
		return a_cell.y < b_cell.y or (a_cell.y == b_cell.y and a_cell.x < b_cell.x))
	return candidates[0]


static func _grid_cell_open(grid: Array, cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < CHUNK_SIZE \
		and cell.y < CHUNK_SIZE and int(grid[cell.y][cell.x]) == 0


static func _room_facing_yaw(cell: Vector2i, target: Vector2i) -> float:
	var direction := Vector2(target - cell)
	if direction.length_squared() < .01:
		return 0.0
	# Godot's visual forward is -Z; atan2(-x, -z) turns that axis toward target.
	return snappedf(atan2(-direction.x, -direction.y), PI * .25)


func _fixtures(coord: Vector3i, grid: Array, rooms: Array, stairs: Array,
		region_props: Array, safe: bool) -> Array:
	var excluded := {}
	for stair in stairs:
		_exclude_neighbourhood(excluded, stair.get("cell", Vector2i.ZERO), 2)
	for prop in region_props:
		_exclude_neighbourhood(excluded, prop.get("cell", Vector2i.ZERO), 1)
	if safe:
		_exclude_neighbourhood(excluded,
			Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2), 4)
	var candidates := []
	var seen := {}
	for room_value in rooms:
		var room: Dictionary = room_value
		var rect: Rect2i = room.get("rect", Rect2i())
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var cell := Vector2i(x, z)
				if seen.has(cell) or excluded.has(cell) or grid[z][x] != 0 \
						or _wall_count(grid, cell) != 1:
					continue
				seen[cell] = true
				candidates.append(cell)
	var rng := SeededRandom.new("%s:FIXTURES:%s" % [world_seed, chunk_id(coord)])
	var result := []
	var target_count := 3 if safe else 6
	while result.size() < target_count and not candidates.is_empty():
		var cell: Vector2i = candidates.pop_at(rng.next_index(candidates.size()))
		var separated := true
		for existing in result:
			if cell.distance_to(existing["cell"]) < 5.0:
				separated = false
				break
		if not separated:
			continue
		var fixture_kind := "vent" if result.size() % 3 == 2 else "hiding_spot"
		var backing_wall := _backing_wall_direction(grid, cell)
		var open_direction := -backing_wall
		result.append({
			"id": "%s:FIXTURE:%s:%d" % [chunk_id(coord),
				fixture_kind.to_upper(), result.size()],
			"kind": fixture_kind,
			"cell": cell,
			# Authored interactables face local -Z. Point that front toward open
			# floor while the opposite side remains backed against the wall.
			"yaw": _room_facing_yaw(cell, cell + open_direction),
			"backing_wall": backing_wall,
			"open_direction": open_direction,
		})
	return result


func _pickups(coord: Vector3i, grid: Array, stairs: Array, safe: bool,
		region_props: Array = [], fixtures: Array = []) -> Array:
	if safe:
		return []
	var excluded := {}
	for stair in stairs:
		_exclude_neighbourhood(excluded, stair["cell"], 2)
	for prop in region_props:
		_exclude_neighbourhood(excluded, prop.get("cell", Vector2i.ZERO), 1)
	for fixture in fixtures:
		_exclude_neighbourhood(excluded, fixture.get("cell", Vector2i.ZERO), 1)
	var candidates := []
	for z in range(1, CHUNK_SIZE - 1):
		for x in range(1, CHUNK_SIZE - 1):
			var cell := Vector2i(x, z)
			if grid[z][x] == 0 and not excluded.has(cell) \
					and _open_spawn_neighbourhood(grid, cell):
				candidates.append(cell)
	var rng := SeededRandom.new("%s:PICKUPS:%s" % [world_seed, chunk_id(coord)])
	var result := []
	var plans := ["relay", "relay", "battery"]
	if rng.next_float() < 0.72:
		plans.append("tool")
	if rng.next_float() < 0.38:
		plans.append("battery")
	if rng.next_float() < 0.30:
		plans.append("coin")
	if rng.next_float() < 0.16:
		plans.append("backpack")
	var kind_indices := {}
	for kind_value in plans:
		if candidates.is_empty():
			break
		var kind := String(kind_value)
		var pick_index := rng.next_index(candidates.size())
		var cell: Vector2i = candidates[pick_index]
		candidates.remove_at(pick_index)
		var index := int(kind_indices.get(kind, 0))
		kind_indices[kind] = index + 1
		var item := ""
		if kind == "tool":
			item = PICKUP_TYPES[rng.next_index(PICKUP_TYPES.size())]
		elif kind == "backpack":
			var depth_rank := clampi(1 + floori(maxf(0.0, -float(coord.y)) / 4.0), 1, 3)
			var rolled_rank := clampi(1 + rng.next_index(depth_rank), 1, 3)
			item = BACKPACK_TYPES[rolled_rank - 1]
		result.append({
			"id": pickup_id(coord, index, kind),
			"cell": cell,
			"kind": kind,
			"item": item,
		})
	return result


static func _exclude_neighbourhood(excluded: Dictionary, cell: Vector2i,
		radius: int) -> void:
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			excluded[cell + Vector2i(dx, dz)] = true


static func _wall_count(grid: Array, cell: Vector2i) -> int:
	var result := 0
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP,
			Vector2i.DOWN]:
		var at: Vector2i = cell + direction
		if at.x < 0 or at.y < 0 or at.x >= CHUNK_SIZE \
				or at.y >= CHUNK_SIZE or int(grid[at.y][at.x]) != 0:
			result += 1
	return result


static func _backing_wall_direction(grid: Array, cell: Vector2i) -> Vector2i:
	if int(grid[cell.y - 1][cell.x]) != 0:
		return Vector2i.UP
	if int(grid[cell.y][cell.x + 1]) != 0:
		return Vector2i.RIGHT
	if int(grid[cell.y + 1][cell.x]) != 0:
		return Vector2i.DOWN
	return Vector2i.LEFT


static func _wall_backed_yaw(grid: Array, cell: Vector2i) -> float:
	# Compatibility helper for callers/tests that used the old name. The return
	# value now consistently describes the usable FRONT, not the backing wall.
	var open_direction := -_backing_wall_direction(grid, cell)
	return _room_facing_yaw(cell, cell + open_direction)


func _hunter_spawns(coord: Vector3i, grid: Array, stairs: Array,
		safe: bool, region_props: Array = []) -> Array:
	# Safe rooms themselves never spawn a hunter. The east neighbour of the
	# origin owns a guaranteed primary hunter so difficulty activation rules are
	# observable immediately: Hard wakes her at run start, Standard on relay one
	# and Relaxed on relay three. Distance plus the intact origin checkpoint is
	# the arrival grace instead of deleting every hunter from the loaded window.
	if safe:
		return []
	var profile := difficulty_for_level(coord.y)
	var danger := float(profile["danger"])
	var rng := SeededRandom.new("%s:HUNTERS:%s" % [world_seed, chunk_id(coord)])
	# These are dormant deterministic candidates. Runtime admits only the
	# relay-scaled population budget, so a denser pool lets new hunters join an
	# already explored area without making every candidate active at once.
	var spawn_chance := lerpf(0.16, 0.42, danger)
	var guaranteed_primary := coord == Vector3i(1, 0, 0)
	if not guaranteed_primary and rng.next_float() >= spawn_chance:
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
	var count := 2 if guaranteed_primary else 1
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
		# Office Void signals are genuinely rare before the full A-Z admission
		# milestone. Runtime raises this chance after 26 durable hunters have
		# entered the world; this tiny deterministic deep-floor roll is the early
		# surprise path requested for long survival runs.
		if coord.y <= -2 and rng.next_float() < .015:
			identity = HunterRoster.office_void_for("%s:%s:%d" % [
				world_seed, chunk_id(coord), index])
		result.append({
			"id": hunter_id(coord, index),
			"hunter_id": identity,
			"cell": cell,
			"level": coord.y,
			"origin_chunk": coord,
		})
		# Multiple candidates in one chunk must not materialize shoulder-to-
		# shoulder when a later relay expands the live population.
		candidates = candidates.filter(func(other: Vector2i) -> bool:
			return other.distance_to(cell) >= 6.0)
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
