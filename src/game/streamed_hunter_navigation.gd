class_name StreamedHunterNavigation
extends RefCounted

## Duck-typed navigation surface consumed by HunterBrain. The finite route
## uses FacilityGenerator directly; the endless route resolves global cells
## into deterministic chunks and keeps path searches bounded around their two
## endpoints. No mesh has to remain loaded for a hunter decision to be stable.

const DIRECTIONS4 := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
const MAX_PATH_SPAN := StreamedRouteGenerator.CHUNK_SIZE * 3
const MAX_NEAREST_VISITS := 4096
const SAFE_ZONE_BLOCK_RADIUS := 3.15

var generator: StreamedRouteGenerator
var world_state: StreamedWorldState
var level := 0
var rooms: Array = []
var safe_zones: Array = []
var relays: Array = []
var batteries: Array = []
var vents: Array = []
var hiding_spots: Array = []
var start := Vector2i.ZERO
var exit_cell := Vector2i.ZERO

var _chunk_cache := {}
## Static authored furniture is not part of the structural wall GridMap, but it
## owns real player collision. Mirror that footprint into the A* surface so a
## hunter cannot take a visual shortcut through a couch, bed or cabinet.
var _solid_prop_cells := {}
var _active_coords: Array[Vector3i] = []
var _refresh_revision := -1
var _refresh_generation := 0
var _path_grid := AStarGrid2D.new()
var _path_grid_coords: Array[Vector3i] = []
var _path_grid_level := 0x7fffffff


const INVALID_CELL := -2147483648


func _init(route_generator: StreamedRouteGenerator, route_level: int = 0,
		mutation_state: StreamedWorldState = null) -> void:
	generator = route_generator
	level = route_level
	world_state = mutation_state


func refresh(route_level: int, coords: Array) -> void:
	var canonical: Array[Vector3i] = []
	for value in coords:
		var coord: Vector3i = value
		if coord.y == route_level and not canonical.has(coord):
			canonical.append(coord)
	canonical.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return a.x < b.x or (a.x == b.x and (a.z < b.z \
			or (a.z == b.z and a.y < b.y))))
	var revision := world_state.navigation_revision if world_state != null else 0
	if level == route_level and _active_coords == canonical \
			and _refresh_revision == revision:
		return
	level = route_level
	# Decisions may query one margin chunk beyond the visible 3x3 window. Drop
	# that cache whenever the window advances so navigation memory cannot grow
	# with total distance travelled.
	_chunk_cache.clear()
	_solid_prop_cells.clear()
	rooms.clear()
	safe_zones.clear()
	relays.clear()
	batteries.clear()
	vents.clear()
	hiding_spots.clear()
	_active_coords = canonical
	_refresh_revision = revision
	_refresh_generation += 1
	for coord in _active_coords:
		var data := _chunk(coord)
		if bool(data.get("safe_room", false)):
			var safe_data: Dictionary = data.get("safe_room_data", {})
			safe_zones.append({
				"room_id": String(safe_data.get("id", "")),
				"x": coord.x * StreamedRouteGenerator.CHUNK_SIZE \
					+ StreamedRouteGenerator.CHUNK_SIZE / 2,
				"y": coord.z * StreamedRouteGenerator.CHUNK_SIZE \
					+ StreamedRouteGenerator.CHUNK_SIZE / 2,
			})
			continue
		for room_value in data.get("rooms", []):
			var room: Dictionary = (room_value as Dictionary).duplicate(true)
			var local_center: Vector2i = room.get("center", Vector2i.ZERO)
			room["center"] = local_center + Vector2i(
				coord.x * StreamedRouteGenerator.CHUNK_SIZE,
				coord.z * StreamedRouteGenerator.CHUNK_SIZE)
			rooms.append(room)
		for pickup_value in data.get("pickups", []):
			var pickup: Dictionary = pickup_value
			var kind := String(pickup.get("kind", ""))
			if kind not in ["relay", "battery", "coin"]:
				continue
			var cell: Vector2i = pickup.get("cell", Vector2i.ZERO)
			var pickup_entry := {"id": String(pickup.get("id", "")),
				"x": coord.x * StreamedRouteGenerator.CHUNK_SIZE + cell.x,
				"y": coord.z * StreamedRouteGenerator.CHUNK_SIZE + cell.y,
				"collected": world_state != null and not world_state.pickup_available(
					String(pickup.get("id", ""))),
				"sabotaged": world_state != null and world_state.relay_sabotaged(
					String(pickup.get("id", ""))),
				"source_chunk": coord}
			if kind == "relay":
				relays.append(pickup_entry)
			elif kind == "battery":
				batteries.append(pickup_entry)
		for fixture_value in data.get("fixtures", []):
			var fixture: Dictionary = fixture_value
			var cell: Vector2i = fixture.get("cell", Vector2i.ZERO)
			var open_direction: Vector2i = fixture.get("open_direction", Vector2i.ZERO)
			var fixture_entry := {"id": String(fixture.get("id", "")),
				"x": coord.x * StreamedRouteGenerator.CHUNK_SIZE + cell.x,
				"y": coord.z * StreamedRouteGenerator.CHUNK_SIZE + cell.y,
				# Vent travel must emerge on the clear room-facing side. Keeping
				# this authored direction in the navigation snapshot prevents the
				# gimmick from placing a player inside the destination grate/wall.
				"open_direction": open_direction,
				"source_chunk": coord}
			if String(fixture.get("kind", "")) == "vent":
				vents.append(fixture_entry)
			else:
				hiding_spots.append(fixture_entry)
	vents.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("id", "")) < String(b.get("id", "")))
	for index in vents.size():
		vents[index]["index"] = index
	if not _active_coords.is_empty():
		var center: Vector3i = _active_coords[_active_coords.size() / 2]
		start = Vector2i(
			center.x * StreamedRouteGenerator.CHUNK_SIZE \
				+ StreamedRouteGenerator.CHUNK_SIZE / 2,
			center.z * StreamedRouteGenerator.CHUNK_SIZE \
				+ StreamedRouteGenerator.CHUNK_SIZE / 2)
		exit_cell = start
	# Build A* lazily on the first path request. Adjacent vertical navigation
	# surfaces are kept ready for floor transfers, but paying to bake all of them
	# whenever a region boundary is crossed caused a visible frame spike.


func cached_chunk_count() -> int:
	return _chunk_cache.size()


func refresh_generation() -> int:
	return _refresh_generation


func active_coordinates() -> Array[Vector3i]:
	return _active_coords.duplicate()


func uncollected(entries: Array) -> Array:
	return entries.filter(func(entry: Dictionary) -> bool:
		return not bool(entry.get("collected", false)))


func is_floor(x: float, y: float) -> bool:
	var cell := Vector2i(floori(x), floori(y))
	var coord := cell_chunk(cell, level)
	var local := local_cell(cell)
	var data := _chunk(coord)
	var grid: Array = data.get("grid", [])
	return local.y >= 0 and local.y < grid.size() \
		and local.x >= 0 and local.x < (grid[local.y] as Array).size() \
		and int(grid[local.y][local.x]) == 0 \
		and not _solid_prop_cells.has(cell)


func can_occupy(x: float, y: float, radius: float = 0.23,
		blocked_cells = null) -> bool:
	for sample in [Vector2(x, y), Vector2(x - radius, y - radius),
			Vector2(x + radius, y - radius), Vector2(x - radius, y + radius),
			Vector2(x + radius, y + radius)]:
		if not is_floor(sample.x, sample.y):
			return false
		if blocked_cells != null and blocked_cells.has(Vector2i(
				floori(sample.x), floori(sample.y))):
			return false
	return true


func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array:
	if from_cell == to_cell:
		return [from_cell] if can_occupy(from_cell.x + .5, from_cell.y + .5) else []
	if absi(to_cell.x - from_cell.x) > MAX_PATH_SPAN \
			or absi(to_cell.y - from_cell.y) > MAX_PATH_SPAN:
		return []
	# A hunter pressed against a prop or wall (or a goal on a prop's edge) stands in a cell whose capsule samples
	# fail can_occupy although it is open floor: path from the nearest roomy neighbour instead of giving up.
	from_cell = _roomy_cell(from_cell)
	to_cell = _roomy_cell(to_cell)
	if from_cell.x == INVALID_CELL or to_cell.x == INVALID_CELL:
		return []
	if from_cell == to_cell:
		return [from_cell]
	# AStarGrid2D executes the hot search in engine code. The solid-cell grid is
	# rebuilt only when the streamed 3x3 authority window moves; relay claims
	# can refresh fixture lists without paying for another navigation bake.
	_rebuild_path_grid_if_needed()
	if not _path_grid.is_in_boundsv(from_cell) \
			or not _path_grid.is_in_boundsv(to_cell):
		return []
	var packed := _path_grid.get_id_path(from_cell, to_cell)
	var result := []
	for cell in packed:
		result.append(cell)
	return result


## The cell itself when a hunter capsule fits, else the nearest of its 8 neighbours (then ring two) that does.
func _roomy_cell(cell: Vector2i) -> Vector2i:
	if can_occupy(cell.x + .5, cell.y + .5):
		return cell
	for ring in [1, 2]:
		var best := Vector2i(INVALID_CELL, 0)
		var best_distance := 1.0e9
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var candidate := cell + Vector2i(dx, dz)
				var distance := float(dx * dx + dz * dz)
				if distance < best_distance and can_occupy(candidate.x + .5, candidate.y + .5):
					best = candidate
					best_distance = distance
		if best.x != INVALID_CELL:
			return best
	return Vector2i(INVALID_CELL, 0)


func _rebuild_path_grid_if_needed() -> void:
	if _path_grid_level == level and _path_grid_coords == _active_coords:
		return
	_path_grid_level = level
	_path_grid_coords = _active_coords.duplicate()
	if _active_coords.is_empty():
		_path_grid.region = Rect2i()
		_path_grid.update()
		return
	var min_chunk := Vector2i(_active_coords[0].x, _active_coords[0].z)
	var max_chunk := min_chunk
	for coord in _active_coords:
		min_chunk.x = mini(min_chunk.x, coord.x)
		min_chunk.y = mini(min_chunk.y, coord.z)
		max_chunk.x = maxi(max_chunk.x, coord.x)
		max_chunk.y = maxi(max_chunk.y, coord.z)
	var origin := min_chunk * StreamedRouteGenerator.CHUNK_SIZE
	var size := (max_chunk - min_chunk + Vector2i.ONE) \
		* StreamedRouteGenerator.CHUNK_SIZE
	_path_grid.region = Rect2i(origin, size)
	_path_grid.cell_size = Vector2.ONE
	# Match the finite/original pathfinder: open floor supports natural 8-way
	# movement, but a diagonal is legal only when both orthogonal flank cells are
	# clear. This keeps hunters fluid without letting their capsule cut wall or
	# furniture corners.
	_path_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_path_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_path_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_path_grid.update()
	for z in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			var cell := Vector2i(x, z)
			if not can_occupy(x + .5, z + .5):
				_path_grid.set_point_solid(cell, true)



func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var distance := from.distance_to(to)
	var steps := maxi(1, ceili(distance * 6.0))
	for index in range(steps + 1):
		var point := from.lerp(to, float(index) / float(steps))
		if not is_floor(point.x, point.y):
			return false
	return true


func floor_cells() -> Array:
	var result := []
	for coord in _active_coords:
		var grid: Array = _chunk(coord).get("grid", [])
		for z in grid.size():
			for x in (grid[z] as Array).size():
				var cell := Vector2i(
					coord.x * StreamedRouteGenerator.CHUNK_SIZE + x,
					coord.z * StreamedRouteGenerator.CHUNK_SIZE + z)
				if int(grid[z][x]) == 0 and not _solid_prop_cells.has(cell):
					result.append(cell)
	return result


func nearest_open_position(origin_x: float, origin_y: float, radius: float,
		blocked_cells = null) -> Dictionary:
	var origin := Vector2i(floori(origin_x), floori(origin_y))
	var frontier: Array[Vector2i] = [origin]
	var visited := {origin: true}
	var cursor := 0
	while cursor < frontier.size() and visited.size() < MAX_NEAREST_VISITS:
		var current: Vector2i = frontier[cursor]
		cursor += 1
		var world := Vector2(current) + Vector2(.5, .5)
		if can_occupy(world.x, world.y, radius, blocked_cells):
			return {"x": world.x, "y": world.y, "cell": current}
		for direction_value in DIRECTIONS4:
			var direction: Vector2i = direction_value
			var next: Vector2i = current + direction
			if visited.has(next):
				continue
			visited[next] = true
			frontier.append(next)
	return {}


func room_at(x: float, y: float) -> Dictionary:
	var point := Vector2i(floori(x), floori(y))
	for room_value in rooms:
		var room: Dictionary = room_value
		var center: Vector2i = room.get("center", Vector2i.ZERO)
		var size: Vector2i = room.get("size", Vector2i.ONE)
		if Rect2i(center - size / 2, size).has_point(point):
			return room
	return {}


func get_safe_zone_blocked_cells() -> Dictionary:
	var blocked := {}
	for zone_value in safe_zones:
		var zone: Dictionary = zone_value
		var center_x := float(zone.get("x", 0.0)) + 0.5
		var center_y := float(zone.get("y", 0.0)) + 0.5
		var extent := int(ceil(SAFE_ZONE_BLOCK_RADIUS))
		var zone_x := int(floor(center_x))
		var zone_y := int(floor(center_y))
		for y in range(zone_y - extent, zone_y + extent + 1):
			for x in range(zone_x - extent, zone_x + extent + 1):
				if not is_floor(x + 0.5, y + 0.5):
					continue
				if Vector2(x + 0.5 - center_x, y + 0.5 - center_y).length() \
						< SAFE_ZONE_BLOCK_RADIUS:
					blocked[Vector2i(x, y)] = true
	return blocked


func hiding_exit_position(spot: Dictionary) -> Vector2:
	var open := nearest_open_position(float(spot.get("x", 0)) + 0.5,
		float(spot.get("y", 0)) + 0.5, GameConfig.PLAYER_RADIUS)
	if open.is_empty():
		return Vector2(float(spot.get("x", 0)) + 0.5, float(spot.get("y", 0)) + 0.5)
	return Vector2(float(open.get("x", 0.0)), float(open.get("y", 0.0)))


func cell_chunk(cell: Vector2i, route_level: int = level) -> Vector3i:
	return Vector3i(
		floori(float(cell.x) / StreamedRouteGenerator.CHUNK_SIZE),
		route_level,
		floori(float(cell.y) / StreamedRouteGenerator.CHUNK_SIZE))


static func local_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(posmod(cell.x, StreamedRouteGenerator.CHUNK_SIZE),
		posmod(cell.y, StreamedRouteGenerator.CHUNK_SIZE))


func _chunk(coord: Vector3i) -> Dictionary:
	if not _chunk_cache.has(coord):
		var data := generator.chunk(coord)
		_chunk_cache[coord] = data
		_cache_solid_prop_cells(coord, data)
	return _chunk_cache[coord]


func _cache_solid_prop_cells(coord: Vector3i, data: Dictionary) -> void:
	var base := Vector2i(coord.x, coord.z) * StreamedRouteGenerator.CHUNK_SIZE
	for prop_value in data.get("region_props", []):
		var prop: Dictionary = prop_value
		if not bool(prop.get("solid", true)) \
				or bool(prop.get("room_door", false)):
			continue
		var occupied: Array = prop.get("occupied_cells", [])
		if occupied.is_empty():
			occupied = [prop.get("cell", Vector2i.ZERO)]
		for local_value in occupied:
			_solid_prop_cells[base + (local_value as Vector2i)] = true
