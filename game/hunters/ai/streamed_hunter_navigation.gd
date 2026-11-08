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
## Music boxes on this level: {"id", "x", "y", "source_chunk"} (Glyra reads her nearest).
var music_boxes: Array = []
var hiding_spots: Array = []
## Free seats a patrolling hunter may sit on (HunterSeats): one per sit point of every sit prop.
var seat_spots: Array = []
var start := Vector2i.ZERO
var exit_cell := Vector2i.ZERO

var _chunk_cache := {}
## Static authored furniture is not part of the structural wall GridMap, but it
## owns real player collision. Mirror that footprint into the A* surface so a
## hunter cannot take a visual shortcut through a couch, bed or cabinet.
var _solid_prop_cells := {}
## Channel cells under an open sewer sluice gate (its valve turned an odd number of times): floor for hunters too.
var _open_gate_cells := {}
var _solid_by_coord := {}   # coord -> that chunk's solid cells, kept while the chunk stays in the window
## The solid cells sight stops at: every solid prop cell except the ones only a see-through barrier blocks
## (SEE_THROUGH_PROPS / SEE_THROUGH_BREAKABLES). Those still block movement (_solid_prop_cells) but not hunter sight.
var _opaque_prop_cells := {}
var _opaque_by_coord := {}  # coord -> that chunk's opaque cells, kept like _solid_by_coord
var _gates_by_coord := {}   # coord -> that chunk's open gate cells, kept like _solid_by_coord
var _seats_by_coord := {}   # coord -> that chunk's seat spots (static), kept like _solid_by_coord
var _active_coords: Array[Vector3i] = []
var _refresh_revision := -1
var _refresh_generation := 0
var _path_grid_walls := Vector2i(-1, -1)
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
	var perf_t := HunterPerf.begin()
	_refresh_window(route_level, coords)
	HunterPerf.end("nav.refresh", perf_t)


func _refresh_window(route_level: int, coords: Array) -> void:
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
	# Decisions may query one margin chunk beyond the visible 3x3 window. Drop the
	# chunks that left the window so navigation memory cannot grow with total
	# distance travelled; the ones that stayed keep their data and solid cells
	# (rebuilding every chunk's prop footprint on each window step cost ~10 ms per
	# teammate crossing on an M4, 25-100 ms on the Windows test PCs). A new level
	# or world-state revision (a breach opened) recomputes everything.
	_probe_chunk_x = 0x7fffffff   # the probe cache points into _chunk_cache: forget it whenever that may change
	_open_cache.clear()
	if level != route_level or _refresh_revision != revision:
		_chunk_cache.clear()
		_solid_by_coord.clear()
		_opaque_by_coord.clear()
		_gates_by_coord.clear()
		_seats_by_coord.clear()
	else:
		for coord_value in _chunk_cache.keys():
			if not canonical.has(coord_value):
				_chunk_cache.erase(coord_value)
				_solid_by_coord.erase(coord_value)
				_opaque_by_coord.erase(coord_value)
				_gates_by_coord.erase(coord_value)
				_seats_by_coord.erase(coord_value)
	level = route_level
	_solid_prop_cells.clear()
	_opaque_prop_cells.clear()
	_open_gate_cells.clear()
	for coord_value in _solid_by_coord:
		for cell_value in _solid_by_coord[coord_value]:
			_solid_prop_cells[cell_value] = true
	for coord_value in _opaque_by_coord:
		for cell_value in _opaque_by_coord[coord_value]:
			_opaque_prop_cells[cell_value] = true
	for coord_value in _gates_by_coord:
		for cell_value in _gates_by_coord[coord_value]:
			_open_gate_cells[cell_value] = true
	rooms.clear()
	safe_zones.clear()
	relays.clear()
	batteries.clear()
	vents.clear()
	music_boxes.clear()
	hiding_spots.clear()
	seat_spots.clear()
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
		for box_value in data.get("music_boxes", []):
			var box: Dictionary = box_value
			var box_cell: Vector2i = box.get("cell", Vector2i.ZERO)
			music_boxes.append({"id": String(box.get("id", "")),
				"x": coord.x * StreamedRouteGenerator.CHUNK_SIZE + box_cell.x,
				"y": coord.z * StreamedRouteGenerator.CHUNK_SIZE + box_cell.y, "source_chunk": coord})
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
				"source_chunk": coord,
				# furniture hiding spots: the bed or wardrobe itself (hunter naps use the beds, docs/REST_AND_SLEEP.md)
				"style": String(fixture.get("style", "")),
				"prop_at": Vector2(coord.x * StreamedRouteGenerator.CHUNK_SIZE, coord.z * StreamedRouteGenerator.CHUNK_SIZE) \
					+ (fixture.get("local_position", Vector2(cell) + Vector2(.5, .5)) as Vector2),
				"yaw": float(fixture.get("yaw", 0.0)),
				"capacity": int(fixture.get("capacity", 1)),
				"prop_size": fixture.get("blocker_size", Vector3.ONE)}
			if String(fixture.get("kind", "")) == "vent":
				vents.append(fixture_entry)
			else:
				hiding_spots.append(fixture_entry)
		# a chunk's seats are static while it stays in the window (see refresh): computed once, copied per refresh
		var seats: Array = _seats_by_coord.get(coord, [])
		if not _seats_by_coord.has(coord):
			var origin := Vector2(coord.x * StreamedRouteGenerator.CHUNK_SIZE, coord.z * StreamedRouteGenerator.CHUNK_SIZE)
			for prop_value in data.get("region_props", []):
				var prop: Dictionary = prop_value
				var type := String(prop.get("type", ""))
				if PropModelCatalog.interaction_for(type) != "sit":
					continue
				# the same size and position the view spawns the sit interactables at (StreamedFacilityView3D._spawn_region_prop)
				var size: Vector3 = prop.get("collider_size", prop.get("blocker_size", Vector3.ONE))
				var yaw := float(prop.get("yaw", 0.0))
				var centre := origin + Vector2(prop.get("cell", Vector2i.ZERO)) + Vector2(.5, .5) \
					+ (prop.get("placement_offset", Vector2.ZERO) as Vector2) + (prop.get("mount_offset", Vector2.ZERO) as Vector2)
				var points: Array = PropModelCatalog.seat_points(type, size)
				for index in points.size():
					var point: Dictionary = points[index]
					# gameplay-local (x, z) turned by yaw into the plan, as the view places the sit interactables
					var local := Vector3(float(point["x"]), 0.0, float(point["z"])).rotated(Vector3.UP, yaw)
					var at := centre + Vector2(local.x, local.z)
					var exit_local := Vector3((point["exit"] as Vector2).x, 0.0, (point["exit"] as Vector2).y).rotated(Vector3.UP, yaw)
					var exit_dir := Vector2(exit_local.x, exit_local.z)
					var exit_reach := (size.x * .5 - absf(float(point["x"])) if absf(exit_dir.dot(Vector2(cos(yaw), -sin(yaw)))) > .5 \
						else size.z * .5 + absf(float(point["z"]))) + .6
					seats.append({"id": "%s#%d" % [String(prop.get("id", "%s@%s" % [type, at])), index], "type": type,
						"seat_at": at, "stand_at": at + exit_dir * exit_reach, "yaw": yaw + float(point["turn"])})
			_seats_by_coord[coord] = seats
		for seat_value in seats:
			seat_spots.append((seat_value as Dictionary).duplicate())
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
	return _cell_open(floori(x), floori(y))


func can_occupy(x: float, y: float, radius: float = 0.23,
		blocked_cells = null) -> bool:
	# Perf pass (docs/PERF_PASS.md): the same five samples in the same order as before (centre, then the four corners, each
	# rounded to float32 like the Vector2 it used to be), but a cell an earlier sample already passed is not asked again and
	# nothing is allocated. Identical answers, about 4x cheaper, and it is the hottest call of the hunter brain.
	var s0 := Vector2(x, y)
	var x0 := floori(s0.x)
	var y0 := floori(s0.y)
	# In the open (all nine cells around this one are floor) a capsule of up to 0.9 cells stands anywhere in the cell: its five
	# samples can only land in those nine, so the answer is yes without asking each one. Walls, props and gates take the exact path.
	if blocked_cells == null and radius <= 0.9 and _interior_open(x0, y0):
		return true
	if not _cell_open(x0, y0) or (blocked_cells != null and blocked_cells.has(Vector2i(x0, y0))):
		return false
	var s1 := Vector2(x - radius, y - radius)
	var x1 := floori(s1.x)
	var y1 := floori(s1.y)
	if (x1 != x0 or y1 != y0) and (not _cell_open(x1, y1) \
			or (blocked_cells != null and blocked_cells.has(Vector2i(x1, y1)))):
		return false
	var s2 := Vector2(x + radius, y - radius)
	var x2 := floori(s2.x)
	var y2 := floori(s2.y)
	if (x2 != x0 or y2 != y0) and (x2 != x1 or y2 != y1) and (not _cell_open(x2, y2) \
			or (blocked_cells != null and blocked_cells.has(Vector2i(x2, y2)))):
		return false
	var s3 := Vector2(x - radius, y + radius)
	var x3 := floori(s3.x)
	var y3 := floori(s3.y)
	if (x3 != x0 or y3 != y0) and (x3 != x1 or y3 != y1) and (x3 != x2 or y3 != y2) and (not _cell_open(x3, y3) \
			or (blocked_cells != null and blocked_cells.has(Vector2i(x3, y3)))):
		return false
	var s4 := Vector2(x + radius, y + radius)
	var x4 := floori(s4.x)
	var y4 := floori(s4.y)
	if (x4 != x0 or y4 != y0) and (x4 != x1 or y4 != y1) and (x4 != x2 or y4 != y2) and (x4 != x3 or y4 != y3) \
			and (not _cell_open(x4, y4) or (blocked_cells != null and blocked_cells.has(Vector2i(x4, y4)))):
		return false
	return true


## Cells whose whole 3x3 neighbourhood is walkable, remembered until the window or its walls change.
var _interior_memo := {}
var _interior_walls := Vector2i(-1, -1)
var _interior_level := 0x7fffffff


func _interior_open(cx: int, cy: int) -> bool:
	var walls := Vector2i(_solid_prop_cells.size(), _open_gate_cells.size())
	if walls != _interior_walls or _interior_level != level:
		_interior_memo.clear()
		_interior_walls = walls
		_interior_level = level
	var key := Vector2i(cx, cy)
	var known = _interior_memo.get(key)
	if known != null:
		return known
	var open := true
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if not _cell_open(cx + dx, cy + dz):
				open = false
				break
		if not open:
			break
	if walls == Vector2i(_solid_prop_cells.size(), _open_gate_cells.size()):   # a probe may have generated a chunk: then not yet
		_interior_memo[key] = open
	return open


## HunterBrain._clear_sweep for the real navigation: can a capsule of `radius` stand at every sample from `from` to `to`, one
## sample each `step` metres (the last one at `to`)? Same samples, same answer as asking can_occupy at each; the open-floor test
## is kept across consecutive samples (they mostly share a cell) instead of being looked up again.
func sweep_clear(from: Vector2, to: Vector2, step: float, radius: float) -> bool:
	var distance := from.distance_to(to)
	var steps := maxi(1, ceili(distance / step))
	var last_x := 0x7fffffff
	var last_y := 0
	var last_open := false
	for index in range(1, steps + 1):
		var point := from.lerp(to, float(index) / float(steps))
		var cx := floori(point.x)
		var cy := floori(point.y)
		if radius <= 0.9:
			if cx != last_x or cy != last_y:
				last_x = cx
				last_y = cy
				last_open = _interior_open(cx, cy)
			if last_open:
				continue
		if not can_occupy(point.x, point.y, radius):
			return false
	return true


## The chunk the last probe landed in (grid rows + typed grids): the probes of one hunter step run in a handful of chunks, so
## the cache dictionary and its Vector3i key are only touched when a probe crosses a chunk edge. Forgotten whenever the chunk
## cache changes (refresh), so it never outlives the data it points at.
var _probe_chunk_x := 0x7fffffff
var _probe_chunk_z := 0
var _probe_level := 0
var _probe_data: Dictionary = {}
var _probe_grid: Array = []


func _probe_chunk(chunk_x: int, chunk_z: int) -> void:
	_probe_data = _chunk(Vector3i(chunk_x, level, chunk_z))
	_probe_grid = _probe_data.get("grid", [])
	_probe_chunk_x = chunk_x
	_probe_chunk_z = chunk_z
	_probe_level = level


## True when the plan cell can be walked on: open grid code (or an opened sluice gate) and no solid prop on it.
func _cell_open(cx: int, cy: int) -> bool:
	var lx := cx % StreamedRouteGenerator.CHUNK_SIZE
	if lx < 0:
		lx += StreamedRouteGenerator.CHUNK_SIZE
	var lz := cy % StreamedRouteGenerator.CHUNK_SIZE
	if lz < 0:
		lz += StreamedRouteGenerator.CHUNK_SIZE
	var chunk_x := (cx - lx) / StreamedRouteGenerator.CHUNK_SIZE
	var chunk_z := (cy - lz) / StreamedRouteGenerator.CHUNK_SIZE
	if chunk_x != _probe_chunk_x or chunk_z != _probe_chunk_z or _probe_level != level:
		_probe_chunk(chunk_x, chunk_z)
	if lz >= _probe_grid.size():
		return false
	var row = _probe_grid[lz]
	if lx >= row.size():
		return false
	if int(row[lx]) != 0 and (_open_gate_cells.is_empty() or not _open_gate_cells.has(Vector2i(cx, cy))):
		return false
	return _solid_prop_cells.is_empty() or not _solid_prop_cells.has(Vector2i(cx, cy))


func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array:
	var perf_t := HunterPerf.begin()
	var found := _find_path(from_cell, to_cell)
	HunterPerf.end("nav.find_path" if not found.is_empty() else "nav.find_path_empty", perf_t)
	return found


func _find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array:
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
	# a world-state change that moves a wall (a seal or pipe broken, a sluice gate opened) rebuilds it too, not only a new
	# window; a relay claim or pickup (same walls) does not
	var walls := Vector2i(_solid_prop_cells.size(), _open_gate_cells.size())
	if _path_grid_level == level and _path_grid_coords == _active_coords and _path_grid_walls == walls:
		return
	_path_grid_level = level
	_path_grid_coords = _active_coords.duplicate()
	_path_grid_walls = walls
	if _active_coords.is_empty():
		_path_grid.region = Rect2i()
		_path_grid.update()
		return
	var perf_t := HunterPerf.begin()
	_bake_path_grid()
	HunterPerf.end("nav.path_grid_bake", perf_t)


## Perf pass: the path grid used to be filled by asking can_occupy about every cell of the window's bounding box (227 ms for 20k
## cells, 0.7-0.9 s for 40-60k, a visible stall each time a hunter crossed a chunk). A can_occupy at a cell centre only ever
## samples that one cell (the capsule corners stay inside it), so the answer per cell is just "is it walkable": this fills the
## same solid map from the chunk grids a row at a time, in runs. It also generates every chunk of the box FIRST, so the wall
## signature taken afterwards already contains the props that spill in from them (the old bake took it before, then
## generated chunks mid-bake and was found stale on the next path request: a second full re-bake per window move).
func _bake_path_grid() -> void:
	var size_chunk := StreamedRouteGenerator.CHUNK_SIZE
	var min_chunk := Vector2i(_active_coords[0].x, _active_coords[0].z)
	var max_chunk := min_chunk
	for coord in _active_coords:
		min_chunk.x = mini(min_chunk.x, coord.x)
		min_chunk.y = mini(min_chunk.y, coord.z)
		max_chunk.x = maxi(max_chunk.x, coord.x)
		max_chunk.y = maxi(max_chunk.y, coord.z)
	for chunk_z in range(min_chunk.y, max_chunk.y + 1):
		for chunk_x in range(min_chunk.x, max_chunk.x + 1):
			_chunk(Vector3i(chunk_x, level, chunk_z))
	_path_grid_walls = Vector2i(_solid_prop_cells.size(), _open_gate_cells.size())
	var origin := min_chunk * size_chunk
	var size := (max_chunk - min_chunk + Vector2i.ONE) * size_chunk
	var region := Rect2i(origin, size)
	_path_grid.region = region
	_path_grid.cell_size = Vector2.ONE
	# Match the finite/original pathfinder: open floor supports natural 8-way movement, but a diagonal is legal only when
	# both orthogonal flank cells are clear. This keeps hunters fluid without letting their capsule cut wall or furniture
	# corners.
	_path_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_path_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_path_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_path_grid.update()
	# update() keeps the solid flags when the region is unchanged: clear them, or a rebuild for an opened gate or a broken
	# seal would keep the old walls
	_path_grid.fill_solid_region(region, false)
	for chunk_z in range(min_chunk.y, max_chunk.y + 1):
		for chunk_x in range(min_chunk.x, max_chunk.x + 1):
			var grid: Array = _chunk(Vector3i(chunk_x, level, chunk_z)).get("grid", [])
			var base_x := chunk_x * size_chunk
			var base_z := chunk_z * size_chunk
			for lz in size_chunk:
				if lz >= grid.size():
					_path_grid.fill_solid_region(Rect2i(base_x, base_z + lz, size_chunk, 1), true)
					continue
				var row = grid[lz]
				var row_size: int = row.size()
				var run_start := -1
				for lx in size_chunk:
					var wall := lx >= row_size or int(row[lx]) != 0
					if wall:
						if run_start < 0:
							run_start = lx
					elif run_start >= 0:
						_path_grid.fill_solid_region(Rect2i(base_x + run_start, base_z + lz, lx - run_start, 1), true)
						run_start = -1
				if run_start >= 0:
					_path_grid.fill_solid_region(Rect2i(base_x + run_start, base_z + lz, size_chunk - run_start, 1), true)
	# an opened sluice gate is floor again, unless a solid prop stands on it (is_floor's rule), then the props are walls
	for cell_value in _open_gate_cells:
		if region.has_point(cell_value) and not _solid_prop_cells.has(cell_value):
			_path_grid.set_point_solid(cell_value, false)
	for cell_value in _solid_prop_cells:
		if region.has_point(cell_value):
			_path_grid.set_point_solid(cell_value, true)


func path_grid_is_solid(cell: Vector2i) -> bool:
	_rebuild_path_grid_if_needed()
	return _path_grid.is_in_boundsv(cell) and _path_grid.is_point_solid(cell)


## The path grid's region after a (re)bake, for the validator that compares the fast bake with the old per-cell can_occupy one.
func path_grid_region() -> Rect2i:
	_rebuild_path_grid_if_needed()
	return _path_grid.region


## Grid-raymarch line of sight. Sight stops at walls and opaque solid props, not at what the runner can see through
## ("hunters can see beyond the fence grate"): a railed sewer channel, falls or stairwell well, the
## mezzanine's open air past its catwalk rails, and fence / grate / cell-gate props. Those keep blocking movement.
func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var distance := from.distance_to(to)
	var steps := maxi(1, ceili(distance * 6.0))
	# a sample in the cell the previous one already cleared is not asked again (same answer, about a third of the calls)
	var last_x := 0x7fffffff
	var last_y := 0
	for index in range(steps + 1):
		var point := from.lerp(to, float(index) / float(steps))
		var cx := floori(point.x)
		var cy := floori(point.y)
		if cx == last_x and cy == last_y:
			continue
		last_x = cx
		last_y = cy
		if _cell_blocks_sight(cx, cy):
			return false
	return true


## Grid codes of the typed level grids that are open air at eye height behind a railing: blocked to walk, not to see.
const SEE_THROUGH_CODES := {
	"sewer_grid": [SewerRouteGenerator.WATER, SewerRouteGenerator.FALL, SewerRouteGenerator.SHAFT],
	"mezzanine_grid": [MezzanineRouteGenerator.OPEN, MezzanineRouteGenerator.PIT],
}
## Solid props you can see through (bars, mesh, grating): they block movement and paths, never sight.
const SEE_THROUGH_PROPS := ["prisonCellGate", "dungeonCage", "sewerSluiceGate", "sewerOverflowGrate"]
## Breakable seal variants built as a see-through gate or fence (Breach "variant").
const SEE_THROUGH_BREAKABLES := ["chainedGate", "lockedCatwalkGate", "sluiceGate"]


## True where hunter sight stops: a wall, or a cell an opaque solid prop covers. See-through barriers (railed drops and
## channels, grates, fences, cell gates) do not stop it. HunterPeek also reads this: a corner she leans round must be
## one that hides the hall, never a railing or grate.
func blocks_sight(x: float, y: float) -> bool:
	return _cell_blocks_sight(floori(x), floori(y))


func _cell_blocks_sight(cx: int, cy: int) -> bool:
	var lx := cx % StreamedRouteGenerator.CHUNK_SIZE
	if lx < 0:
		lx += StreamedRouteGenerator.CHUNK_SIZE
	var lz := cy % StreamedRouteGenerator.CHUNK_SIZE
	if lz < 0:
		lz += StreamedRouteGenerator.CHUNK_SIZE
	var chunk_x := (cx - lx) / StreamedRouteGenerator.CHUNK_SIZE
	var chunk_z := (cy - lz) / StreamedRouteGenerator.CHUNK_SIZE
	if chunk_x != _probe_chunk_x or chunk_z != _probe_chunk_z or _probe_level != level:
		_probe_chunk(chunk_x, chunk_z)
	if lz >= _probe_grid.size():
		return true
	var row = _probe_grid[lz]
	if lx >= row.size():
		return true
	var cell := Vector2i(cx, cy)
	if not _opaque_prop_cells.is_empty() and _opaque_prop_cells.has(cell):
		return true
	if int(row[lx]) == 0 or (not _open_gate_cells.is_empty() and _open_gate_cells.has(cell)):
		return false
	for key in SEE_THROUGH_CODES:
		var typed: Array = _probe_data.get(key, [])
		if lz < typed.size() and lx < (typed[lz] as Array).size() \
				and (SEE_THROUGH_CODES[key] as Array).has(int(typed[lz][lx])):
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
				if (int(grid[z][x]) == 0 or _open_gate_cells.has(cell)) and not _solid_prop_cells.has(cell):
					result.append(cell)
	return result


## Perf pass: the answer depends only on the origin cell, the radius and the walls, and a hunter that goes idle -> wander asks it
## for the centre of every room in the window (a breadth-first spiral each when a table stands in the middle). Kept until the
## window or its walls change, so a crowd of idlers asks once.
var _open_cache := {}
var _open_cache_walls := Vector2i(-1, -1)


func nearest_open_position(origin_x: float, origin_y: float, radius: float,
		blocked_cells = null) -> Dictionary:
	var origin := Vector2i(floori(origin_x), floori(origin_y))
	if blocked_cells != null:
		return _nearest_open_search(origin, radius, blocked_cells)
	var walls := Vector2i(_solid_prop_cells.size(), _open_gate_cells.size())
	if walls != _open_cache_walls:
		_open_cache.clear()
		_open_cache_walls = walls
	var key := Vector3(origin.x, origin.y, radius)
	if _open_cache.has(key):
		return (_open_cache[key] as Dictionary).duplicate()
	var found := _nearest_open_search(origin, radius, null)
	if walls == Vector2i(_solid_prop_cells.size(), _open_gate_cells.size()):   # the search itself may have generated chunks
		_open_cache[key] = found
	return found.duplicate()


func _nearest_open_search(origin: Vector2i, radius: float, blocked_cells) -> Dictionary:
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


## A capsule rides up a ledge this low (the player has no step-up; its rounded bottom climbs it): a solid prop whose
## collider is no taller is floor to the runner, so it is floor to the hunters too.
const WALK_ON_HEIGHT := 0.25
## can_occupy's default capsule radius: a cell whose centre is this far clear of every collider can be stood on.
const NAV_RADIUS := 0.23


static func blocks_nothing(prop: Dictionary) -> bool:
	var size: Vector3 = prop.get("collider_size", prop.get("blocker_size", Vector3.ONE))
	return size.y <= WALK_ON_HEIGHT and float(prop.get("collider_y0", 0.0)) <= 0.0


## The prop's collider boxes on the chunk plan (chunk-local metres), each the axis-aligned bounds of its turned box grown
## by `grow`: the same boxes the view builds (StreamedFacilityView3D._spawn_authored_prop).
static func collider_plan_rects(prop: Dictionary, grow: float = 0.0) -> Array:
	var type := String(prop.get("type", ""))
	var size: Vector3 = prop.get("collider_size", prop.get("blocker_size", Vector3.ONE))
	var yaw := float(prop.get("yaw", 0.0))
	var centre := Vector2(prop.get("cell", Vector2i.ZERO)) + Vector2(.5, .5) \
		+ (prop.get("placement_offset", Vector2.ZERO) as Vector2) + (prop.get("mount_offset", Vector2.ZERO) as Vector2)
	var out := []
	for box in PropColliderBoxes.boxes(type, size):
		var c: Vector2 = box["c"]
		var h: Vector2 = box["h"]
		var rect := Rect2()
		var first := true
		for corner in [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(-h.x, h.y), Vector2(h.x, h.y)]:
			var turned := Vector3(c.x + corner.x, 0.0, c.y + corner.y).rotated(Vector3.UP, yaw)
			var at := centre + Vector2(turned.x, turned.z)
			rect = Rect2(at, Vector2.ZERO) if first else rect.expand(at)
			first = false
		out.append(rect.grow(grow))
	return out


func _cache_solid_prop_cells(coord: Vector3i, data: Dictionary) -> void:
	var cells := {}
	var gates := {}
	var opaque := {}
	_collect_solid_prop_cells(coord, data, cells, gates, opaque)
	_solid_by_coord[coord] = cells.keys()
	_opaque_by_coord[coord] = opaque.keys()
	_gates_by_coord[coord] = gates.keys()
	_solid_prop_cells.merge(cells)
	_opaque_prop_cells.merge(opaque)
	_open_gate_cells.merge(gates)


## `opaque` (optional) gets the subset of `out` that also stops sight: every cell but the see-through barriers' (113).
func _collect_solid_prop_cells(coord: Vector3i, data: Dictionary, out: Dictionary, gates: Dictionary,
		opaque = null) -> void:
	var sight: Dictionary = {} if opaque == null else opaque
	var base := Vector2i(coord.x, coord.z) * StreamedRouteGenerator.CHUNK_SIZE
	for gate_value in data.get("gates", []):
		var gate: Dictionary = gate_value
		if world_state != null and world_state.valve_count(String(gate["valve"])) % 2 == 1:
			for local_value in gate["cells"]:
				gates[base + (local_value as Vector2i)] = true
	# a closed seal (or any breakable that blocks) is a wall to the hunters until somebody breaks it open
	for spec_value in data.get("breakables", []):
		var spec: Dictionary = spec_value
		if String((spec.get("extras", {}) as Dictionary).get("blocks", "")) == "" and String(spec.get("kind", "")) != Breach.KIND_SEAL:
			continue
		if world_state != null and world_state.breach_open(String(spec["id"])):
			continue
		var see_through := SEE_THROUGH_BREAKABLES.has(String(spec.get("variant", "")))
		for local_value in (spec["extras"] as Dictionary).get("cells", []):
			out[base + (local_value as Vector2i)] = true
			if not see_through:
				sight[base + (local_value as Vector2i)] = true
	for prop_value in data.get("region_props", []):
		var prop: Dictionary = prop_value
		if not bool(prop.get("solid", true)) \
				or bool(prop.get("room_door", false)):
			continue
		# a sewer pipe somebody broke with the Axe is gone (Breach, "breakable_id")
		if prop.has("breakable_id") and world_state != null and world_state.breach_open(String(prop["breakable_id"])):
			continue
		var occupied: Array = prop.get("occupied_cells", [])
		if occupied.is_empty():
			occupied = [prop.get("cell", Vector2i.ZERO)]
		# walkability and navigation agree: a prop low enough to walk onto is floor, and a reserved
		# cell is blocked only where the collider (grown by the navigation's capsule radius) covers its centre: the open
		# corner of an L desk, the gap between two potted palms, the free end of a cart's cell all stay open
		if blocks_nothing(prop):
			continue
		var rects := collider_plan_rects(prop, NAV_RADIUS)
		var prop_sight := not SEE_THROUGH_PROPS.has(String(prop.get("type", "")))
		for local_value in occupied:
			var centre := Vector2(local_value as Vector2i) + Vector2(.5, .5)
			if rects.is_empty() or rects.any(func(r: Rect2) -> bool: return r.has_point(centre)):
				out[base + (local_value as Vector2i)] = true
				if prop_sight:
					sight[base + (local_value as Vector2i)] = true
		# the other way round: a collider can reach past the cells its prop reserves (the reservation is sized from the
		# authored blocker, the collider from the model: a cafeteria table 3.98 x 2.67 m on 3 cells, a kitchen rack 2.1 m on
		# 1). Those cells follow the same rule: blocked where the collider grown by NAV_RADIUS covers the centre. BETA's
		# prison cafeteria lined a tray return, a table and a rack wall to wall with 0.45-0.49 m slots between them (the
		# capsule is 0.5 m wide) over cells the navigation called open, and the bots walked into a slot for good 4 m
		# short of a relay. A raised collider (crawl-under pipe) leaves the floor under it open.
		if float(prop.get("collider_y0", 0.0)) > 0.0:
			continue
		for rect_value in rects:
			for local_value in cells_inside(rect_value as Rect2):
				out[base + (local_value as Vector2i)] = true
				if prop_sight:
					sight[base + (local_value as Vector2i)] = true


## Plan cells (chunk-local, may lie past the chunk's edge) whose centre lies inside `rect`.
static func cells_inside(rect: Rect2) -> Array:
	var out := []
	for z in range(ceili(rect.position.y - .5), floori(rect.end.y - .5) + 1):
		for x in range(ceili(rect.position.x - .5), floori(rect.end.x - .5) + 1):
			var centre := Vector2(x + .5, z + .5)
			if rect.has_point(centre):
				out.append(Vector2i(x, z))
	return out
