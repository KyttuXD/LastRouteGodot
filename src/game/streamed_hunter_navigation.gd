class_name StreamedHunterNavigation
extends RefCounted

## Duck-typed navigation surface consumed by HunterBrain. The finite route
## uses FacilityGenerator directly; the endless route resolves global cells
## into deterministic chunks and keeps path searches bounded around their two
## endpoints. No mesh has to remain loaded for a hunter decision to be stable.

const DIRECTIONS4 := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
const MAX_PATH_SPAN := StreamedRouteGenerator.CHUNK_SIZE * 3
const MAX_PATH_VISITS := 14000
const MAX_NEAREST_VISITS := 4096

var generator: StreamedRouteGenerator
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
var _active_coords: Array[Vector3i] = []


func _init(route_generator: StreamedRouteGenerator, route_level: int = 0) -> void:
	generator = route_generator
	level = route_level


func refresh(route_level: int, coords: Array) -> void:
	level = route_level
	# Decisions may query one margin chunk beyond the visible 3x3 window. Drop
	# that cache whenever the window advances so navigation memory cannot grow
	# with total distance travelled.
	_chunk_cache.clear()
	rooms.clear()
	safe_zones.clear()
	_active_coords.clear()
	for value in coords:
		var coord: Vector3i = value
		if coord.y != level:
			continue
		_active_coords.append(coord)
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
	if not _active_coords.is_empty():
		var center: Vector3i = _active_coords[_active_coords.size() / 2]
		start = Vector2i(
			center.x * StreamedRouteGenerator.CHUNK_SIZE \
				+ StreamedRouteGenerator.CHUNK_SIZE / 2,
			center.z * StreamedRouteGenerator.CHUNK_SIZE \
				+ StreamedRouteGenerator.CHUNK_SIZE / 2)
		exit_cell = start


func cached_chunk_count() -> int:
	return _chunk_cache.size()


func is_floor(x: float, y: float) -> bool:
	var cell := Vector2i(floori(x), floori(y))
	var coord := cell_chunk(cell, level)
	var local := local_cell(cell)
	var data := _chunk(coord)
	var grid: Array = data.get("grid", [])
	return local.y >= 0 and local.y < grid.size() \
		and local.x >= 0 and local.x < (grid[local.y] as Array).size() \
		and int(grid[local.y][local.x]) == 0


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
			or absi(to_cell.y - from_cell.y) > MAX_PATH_SPAN \
			or not can_occupy(from_cell.x + .5, from_cell.y + .5) \
			or not can_occupy(to_cell.x + .5, to_cell.y + .5):
		return []
	var margin := 8
	var min_cell := Vector2i(mini(from_cell.x, to_cell.x) - margin,
		mini(from_cell.y, to_cell.y) - margin)
	var max_cell := Vector2i(maxi(from_cell.x, to_cell.x) + margin,
		maxi(from_cell.y, to_cell.y) + margin)
	var frontier: Array[Vector2i] = [from_cell]
	var came_from := {from_cell: from_cell}
	var cursor := 0
	while cursor < frontier.size() and came_from.size() < MAX_PATH_VISITS:
		var current: Vector2i = frontier[cursor]
		cursor += 1
		for direction_value in DIRECTIONS4:
			var direction: Vector2i = direction_value
			var next: Vector2i = current + direction
			if next.x < min_cell.x or next.y < min_cell.y \
					or next.x > max_cell.x or next.y > max_cell.y \
					or came_from.has(next) \
					or not can_occupy(next.x + .5, next.y + .5):
				continue
			came_from[next] = current
			if next == to_cell:
				return _reconstruct_path(came_from, from_cell, to_cell)
			frontier.append(next)
	return []


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
				if int(grid[z][x]) == 0:
					result.append(Vector2i(
						coord.x * StreamedRouteGenerator.CHUNK_SIZE + x,
						coord.z * StreamedRouteGenerator.CHUNK_SIZE + z))
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
		_chunk_cache[coord] = generator.chunk(coord)
	return _chunk_cache[coord]


static func _reconstruct_path(came_from: Dictionary, from_cell: Vector2i,
		to_cell: Vector2i) -> Array:
	var result := [to_cell]
	var cursor := to_cell
	while cursor != from_cell:
		cursor = came_from[cursor]
		result.push_front(cursor)
	return result
