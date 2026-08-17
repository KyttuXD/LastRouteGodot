class_name FacilityGenerator
extends RefCounted

## Deterministic seeded facility generation, ported from LastRoute's
## src/game/maze.js (the `Maze` class).
##
## Scope: this covers the STRUCTURAL algorithm faithfully — the odd sector
## grid, the central lobby, authored-sized rooms dropped into sectors, the
## Kruskal-connected 3-wide corridor graph with a few short service loops,
## and seed-deterministic relay/battery/safe-zone/service-lift placement.
##
## Out of scope (a later content milestone, not a structural one): themed
## room types and their furniture (maze.js's ROOM_TYPES/populateRooms),
## hiding spots, hunter spawns, coins, the heater station, and custom/
## authored map layouts. Because those steps consume random draws in the
## original before objective placement runs, a given seed will NOT produce
## a pixel-identical layout to the JS game — only the same *kind* of layout,
## deterministically, seed to seed, within this port.

const MIN_ROUTE_SIZE := 35
const MAX_ROUTE_SIZE := 121
const MAX_SAFE_ZONE_COUNT := 4
const HALL_WIDTH := 3
const LOBBY_SIZE := 11
const SECTOR_GAP := 2
const SECTOR_MARGIN := 2
const MIN_AUTHORED_ROOM_SIZE := 10
const MAX_AUTHORED_ROOM_SIZE := 26
const ROOM_SECTOR_FILL := 0.86
const DEFAULT_AGENT_RADIUS := 0.23
# TUNING.safeRadius (2.5) + 0.65, from maze.js's getSafeZoneBlockedCells default.
const SAFE_ZONE_BLOCK_RADIUS := 3.15
const CARDINAL_IDS := ["north", "south", "west", "east"]
const DIRECTIONS4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const ROOM_SIZE_CLASS_RATIOS := {
	"compact": [0.5, 0.64],
	"medium": [0.64, 0.8],
	"large": [0.78, 0.92],
}

var seed_text: String
var cols: int
var rows: int
var relay_count: int
var battery_count: int
var room_count: int
var safe_zone_count: int
var safe_zone_at_spawn: bool

## grid[y][x]: 1 = wall, 0 = floor.
var grid: Array = []
var rooms: Array = []
var hallways: Array = []
var sectors: Array = []
var relays: Array = []
var batteries: Array = []
var safe_zones: Array = []
var start: Vector2i
## Every authored green cell on a custom map. `start` remains the primary
## anchor used for distances/objective placement; multiplayer consumes this
## whole ordered list before falling back to nearby open cells.
var spawn_points: Array[Vector2i] = []
var exit_cell: Vector2i

var random: SeededRandom

var _astar: AStarGrid2D


## `custom_layout`, when given, skips procedural carving entirely and loads a
## pre-parsed grid/rooms/start/exit instead (see CustomMapParser) — the same
## shape `_init` builds internally, just handed in rather than carved.
## Objective placement (relays/batteries/safe zones/service lift) still runs
## either way: those algorithms only ever read `self.grid`/`self.rooms`, so a
## hand-painted floor gets the same seeded, deterministic placement a
## procedural one does.
func _init(p_seed_text: String, options: Dictionary = {}, custom_layout: Dictionary = {}) -> void:
	seed_text = p_seed_text
	relay_count = maxi(1, options.get("relay_count", GameConfig.FACILITY_RELAY_COUNT))
	battery_count = maxi(1, options.get("battery_count", GameConfig.FACILITY_BATTERY_COUNT))
	room_count = maxi(5, options.get("room_count", GameConfig.FACILITY_ROOM_COUNT))
	safe_zone_count = clampi(options.get("safe_zone_count", GameConfig.FACILITY_SAFE_ZONE_COUNT), 0, MAX_SAFE_ZONE_COUNT)
	safe_zone_at_spawn = options.get("safe_zone_at_spawn", GameConfig.FACILITY_SAFE_ZONE_AT_SPAWN)
	random = SeededRandom.new(seed_text)

	if custom_layout.is_empty():
		cols = clampi(options.get("cols", GameConfig.FACILITY_COLS), MIN_ROUTE_SIZE, MAX_ROUTE_SIZE)
		rows = clampi(options.get("rows", GameConfig.FACILITY_ROWS), MIN_ROUTE_SIZE, MAX_ROUTE_SIZE)
		grid = []
		for _y in rows:
			var row_data: Array = []
			row_data.resize(cols)
			row_data.fill(1)
			grid.append(row_data)
		start = Vector2i(cols / 2, rows / 2)
		exit_cell = start
		generate()
	else:
		cols = custom_layout["cols"]
		rows = custom_layout["rows"]
		grid = custom_layout["grid"]
		rooms = custom_layout["rooms"]
		_load_custom_spawn_points(custom_layout)
		var from_start := distance_map(start.x, start.y)
		var custom_exit: Vector2i = custom_layout.get("exit_cell", Vector2i(-1, -1))
		# A painted exit is used as-is; an unpainted one falls back to the same
		# auto-pick a procedural floor gets rather than leaving the floor with
		# no way down -- see CustomMapParser's note on why.
		exit_cell = custom_exit if custom_exit.x >= 0 else pick_service_lift(from_start)
		place_safe_zones(from_start)
		place_relays(from_start)
		place_batteries(from_start)


func _load_custom_spawn_points(custom_layout: Dictionary) -> void:
	spawn_points.clear()
	for value in custom_layout.get("spawn_points", []):
		var cell: Vector2i = value
		if _valid_open_cell(cell) and not spawn_points.has(cell):
			spawn_points.append(cell)

	# Backward compatibility for layouts produced before `spawn_points` was
	# part of the parser result.
	if spawn_points.is_empty():
		var legacy_start: Vector2i = custom_layout.get("start", Vector2i(-1, -1))
		if _valid_open_cell(legacy_start):
			spawn_points.append(legacy_start)

	if spawn_points.is_empty():
		var candidates: Array = floor_cells()
		if candidates.is_empty():
			# Border cells are normally walls and floor_cells() intentionally omits
			# them, but an unbounded custom format may author a tiny/border-only map.
			for y in rows:
				for x in cols:
					if grid[y][x] == 0:
						candidates.append(Vector2i(x, y))
		if candidates.is_empty():
			# CustomMapParser rejects this case; retain a total fallback for direct
			# callers so construction cannot index an empty array.
			spawn_points.append(Vector2i.ZERO)
		else:
			spawn_points.append(candidates[random.next_index(candidates.size())])
	start = spawn_points[0]


func _valid_open_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < cols and cell.y < rows \
		and grid[cell.y][cell.x] == 0


func generate() -> void:
	var lobby := carve_facility_rooms()
	start = lobby["center"]
	spawn_points.clear()
	spawn_points.append(start)
	connect_facility_rooms(lobby)

	var from_start := distance_map(start.x, start.y)
	exit_cell = pick_service_lift(from_start)
	place_safe_zones(from_start)
	place_relays(from_start)
	place_batteries(from_start)


# ---------------------------------------------------------------------------
# Sector grid + room carving
# ---------------------------------------------------------------------------

func carve_facility_rooms() -> Dictionary:
	sectors = _create_facility_sectors(cols, rows)

	var center_x: int = cols / 2
	var center_y: int = rows / 2
	var lobby_offset: int = LOBBY_SIZE / 2
	var lobby := {
		"id": "room-lobby",
		"sector": "lobby",
		"x": center_x - lobby_offset,
		"y": center_y - lobby_offset,
		"width": LOBBY_SIZE,
		"height": LOBBY_SIZE,
		"center": Vector2i(center_x, center_y),
		"type": "lobby",
	}
	rooms.append(lobby)
	carve_rect(lobby["x"], lobby["y"], LOBBY_SIZE, LOBBY_SIZE)

	var cardinal_sectors: Array = sectors.filter(func(s): return CARDINAL_IDS.has(s["id"]))
	var other_sectors: Array = sectors.filter(func(s): return not CARDINAL_IDS.has(s["id"]))
	_shuffle_array(other_sectors)
	sectors = cardinal_sectors + other_sectors

	var outer_room_count: int = mini(sectors.size(), maxi(0, room_count - 1))
	for index in outer_room_count:
		var sector: Dictionary = sectors[index]
		var dimensions := _authored_room_dimensions(sector)
		var width_ceiling: int = maxi(mini(MIN_AUTHORED_ROOM_SIZE, sector["width"]), int(floor(sector["width"] * ROOM_SECTOR_FILL)))
		var height_ceiling: int = maxi(mini(MIN_AUTHORED_ROOM_SIZE, sector["height"]), int(floor(sector["height"] * ROOM_SECTOR_FILL)))
		var width: int = mini(width_ceiling, dimensions["width"])
		var height: int = mini(height_ceiling, dimensions["height"])
		var x_range: int = maxi(0, sector["width"] - width)
		var y_range: int = maxi(0, sector["height"] - height)
		var x: int = sector["x"] + random.next_index(x_range + 1)
		var y: int = sector["y"] + random.next_index(y_range + 1)
		var center := Vector2i(int(x + width / 2.0), int(y + height / 2.0))
		var room := {
			"id": "room-%d" % index,
			"sector": sector["id"],
			"sector_col": sector["grid_col"],
			"sector_row": sector["grid_row"],
			"x": x,
			"y": y,
			"width": width,
			"height": height,
			"size_class": dimensions["size_class"],
			"center": center,
			"type": "generic",
		}
		rooms.append(room)
		carve_rect(x, y, width, height)
	return lobby


func _authored_room_dimensions(sector: Dictionary) -> Dictionary:
	var smallest_side: int = mini(sector["width"], sector["height"])
	var size_class := "medium"
	if smallest_side >= 16:
		var roll := random.next_float()
		size_class = "compact" if roll < 0.32 else ("medium" if roll < 0.82 else "large")
	elif random.next_float() < 0.38:
		size_class = "compact"
	var width_range := _room_size_range(sector["width"], size_class)
	var height_range := _room_size_range(sector["height"], size_class)
	var width: int = width_range["minimum"] + random.next_index(width_range["maximum"] - width_range["minimum"] + 1)
	var height: int = height_range["minimum"] + random.next_index(height_range["maximum"] - height_range["minimum"] + 1)
	return {"size_class": size_class, "width": width, "height": height}


func _room_size_range(sector_dimension: int, size_class: String) -> Dictionary:
	var ratios: Array = ROOM_SIZE_CLASS_RATIOS[size_class]
	var minimum: int = _clamp_authored_room_dimension(int(floor(sector_dimension * ratios[0])), sector_dimension)
	var maximum: int = maxi(minimum, _clamp_authored_room_dimension(int(floor(sector_dimension * ratios[1])), sector_dimension))
	return {"minimum": minimum, "maximum": maximum}


func _clamp_authored_room_dimension(value: int, sector_dimension: int, minimum: int = MIN_AUTHORED_ROOM_SIZE) -> int:
	var maximum: int = mini(MAX_AUTHORED_ROOM_SIZE, sector_dimension)
	return maxi(mini(minimum, maximum), mini(maximum, value))


func carve_rect(x: int, y: int, width: int, height: int) -> void:
	for row in range(maxi(1, y), mini(rows - 1, y + height)):
		for col in range(maxi(1, x), mini(cols - 1, x + width)):
			grid[row][col] = 0


static func _facility_sector_divisions(size: int) -> int:
	if size >= 110:
		return 7
	if size >= 66:
		return 5
	return 3


static func _facility_bands(size: int, n: int) -> Array:
	var gap := SECTOR_GAP
	var margin := SECTOR_MARGIN
	var usable: int = size - margin * 2 - gap * (n - 1)
	var band: int = usable / n
	var remainder: int = usable - band * n
	var centre: int = n / 2
	var bands: Array = []
	var pos := margin
	for index in n:
		var band_size: int = band + (remainder if index == centre else 0)
		bands.append({"pos": pos, "size": band_size})
		pos += band_size + gap
	return bands


static func _create_facility_sectors(p_cols: int, p_rows: int) -> Array:
	var nx := _facility_sector_divisions(p_cols)
	var ny := _facility_sector_divisions(p_rows)
	var horizontal := _facility_bands(p_cols, nx)
	var vertical := _facility_bands(p_rows, ny)
	var cx: int = nx / 2
	var cy: int = ny / 2
	var cardinal_order: Array = []
	var other_order: Array = []
	for row in ny:
		for col in nx:
			if col == cx and row == cy:
				continue
			var id := "sector-%d-%d" % [col, row]
			if col == cx and row == cy - 1:
				id = "north"
			elif col == cx and row == cy + 1:
				id = "south"
			elif col == cx - 1 and row == cy:
				id = "west"
			elif col == cx + 1 and row == cy:
				id = "east"
			var sector := {
				"id": id,
				"grid_col": col,
				"grid_row": row,
				"x": horizontal[col]["pos"],
				"y": vertical[row]["pos"],
				"width": horizontal[col]["size"],
				"height": vertical[row]["size"],
			}
			if CARDINAL_IDS.has(id):
				cardinal_order.append(sector)
			else:
				other_order.append(sector)
	return cardinal_order + other_order


# ---------------------------------------------------------------------------
# Corridor graph (Kruskal MST around the four lobby arteries + short loops)
# ---------------------------------------------------------------------------

func connect_facility_rooms(lobby: Dictionary) -> void:
	var room_by_sector := {}
	for room in rooms:
		room_by_sector[room["sector"]] = room

	var parent := {}
	for room in rooms:
		parent[room["id"]] = room["id"]

	var selected: Array = []
	var selected_keys := {}

	for sector_id in CARDINAL_IDS:
		if room_by_sector.has(sector_id):
			_select_edge({"from": lobby, "to": room_by_sector[sector_id], "kind": "main"}, selected, selected_keys, parent)

	var candidates: Array = []
	for first in range(rooms.size()):
		for second in range(first + 1, rooms.size()):
			var from_room = rooms[first]
			var to_room = rooms[second]
			var from_center: Vector2i = from_room["center"]
			var to_center: Vector2i = to_room["center"]
			var distance: float = absi(from_center.x - to_center.x) + absi(from_center.y - to_center.y)
			candidates.append({"from": from_room, "to": to_room, "distance": distance, "score": distance + random.next_float() * 3.5})
	candidates.sort_custom(func(a, b): return a["score"] < b["score"])

	for candidate in candidates:
		if _uf_find(parent, candidate["from"]["id"]) == _uf_find(parent, candidate["to"]["id"]):
			continue
		_select_edge({"from": candidate["from"], "to": candidate["to"], "kind": "connector"}, selected, selected_keys, parent)

	var loop_candidates: Array = []
	for candidate in candidates:
		if not selected_keys.has(_edge_key(candidate["from"]["id"], candidate["to"]["id"])) and candidate["distance"] <= 24:
			loop_candidates.append(candidate)
	_shuffle_array(loop_candidates)
	loop_candidates.sort_custom(func(a, b):
		if a["distance"] != b["distance"]:
			return a["distance"] < b["distance"]
		return a["score"] < b["score"]
	)
	var loop_count: int = mini(4, loop_candidates.size())
	for i in loop_count:
		var candidate = loop_candidates[i]
		_select_edge({"from": candidate["from"], "to": candidate["to"], "kind": "service"}, selected, selected_keys, parent)

	for edge in selected:
		var horizontal_first: bool = choose_hall_orientation(edge)
		carve_orthogonal_hall(edge["from"]["center"], edge["to"]["center"], horizontal_first, edge["kind"])


static func _edge_key(from_id: String, to_id: String) -> String:
	var ids := [from_id, to_id]
	ids.sort()
	return "%s|%s" % [ids[0], ids[1]]


func _select_edge(edge: Dictionary, selected: Array, selected_keys: Dictionary, parent: Dictionary) -> bool:
	var edge_key := _edge_key(edge["from"]["id"], edge["to"]["id"])
	if selected_keys.has(edge_key):
		return false
	selected_keys[edge_key] = true
	var full_edge := edge.duplicate()
	full_edge["width"] = HALL_WIDTH
	selected.append(full_edge)
	_uf_union(parent, edge["from"]["id"], edge["to"]["id"])
	return true


static func _uf_find(parent: Dictionary, id: String) -> String:
	var cursor: String = id
	while parent[cursor] != cursor:
		cursor = parent[cursor]
	var compression: String = id
	while parent[compression] != compression:
		var next_id: String = parent[compression]
		parent[compression] = cursor
		compression = next_id
	return cursor


static func _uf_union(parent: Dictionary, a: String, b: String) -> bool:
	var root_a := _uf_find(parent, a)
	var root_b := _uf_find(parent, b)
	if root_a == root_b:
		return false
	parent[root_b] = root_a
	return true


func choose_hall_orientation(edge: Dictionary) -> bool:
	var from_center: Vector2i = edge["from"]["center"]
	var to_center: Vector2i = edge["to"]["center"]
	var delta_x: int = absi(from_center.x - to_center.x)
	var delta_y: int = absi(from_center.y - to_center.y)
	if edge["kind"] == "main":
		var from_sector: String = edge["from"].get("sector", "")
		var to_sector: String = edge["to"].get("sector", "")
		var cardinal := ""
		if CARDINAL_IDS.has(from_sector):
			cardinal = from_sector
		elif CARDINAL_IDS.has(to_sector):
			cardinal = to_sector
		if cardinal == "north" or cardinal == "south":
			return false
		if cardinal == "west" or cardinal == "east":
			return true
	if delta_x > delta_y * 1.5:
		return true
	if delta_y > delta_x * 1.5:
		return false
	return random.next_float() < 0.5


func carve_orthogonal_hall(from_center: Vector2i, to_center: Vector2i, horizontal_first: bool, kind: String) -> void:
	var bend: Vector2i = Vector2i(to_center.x, from_center.y) if horizontal_first else Vector2i(from_center.x, to_center.y)
	if horizontal_first:
		carve_hall_segment(from_center, bend, "horizontal", kind)
		carve_hall_segment(bend, to_center, "vertical", kind)
	else:
		carve_hall_segment(from_center, bend, "vertical", kind)
		carve_hall_segment(bend, to_center, "horizontal", kind)


func carve_hall_segment(from_pos: Vector2i, to_pos: Vector2i, orientation: String, kind: String) -> void:
	var width := HALL_WIDTH
	var offset: int = (width - 1) / 2
	if orientation == "horizontal":
		var x: int = mini(from_pos.x, to_pos.x)
		carve_rect(x, from_pos.y - offset, absi(to_pos.x - from_pos.x) + 1, width)
		hallways.append({"x": x, "y": from_pos.y - offset, "width": absi(to_pos.x - from_pos.x) + 1, "height": width, "orientation": orientation, "kind": kind})
	else:
		var y: int = mini(from_pos.y, to_pos.y)
		carve_rect(from_pos.x - offset, y, width, absi(to_pos.y - from_pos.y) + 1)
		hallways.append({"x": from_pos.x - offset, "y": y, "width": width, "height": absi(to_pos.y - from_pos.y) + 1, "orientation": orientation, "kind": kind})


# ---------------------------------------------------------------------------
# Grid queries
# ---------------------------------------------------------------------------

func is_floor(x: float, y: float) -> bool:
	var cell_x := int(floor(x))
	var cell_y := int(floor(y))
	if cell_x < 0 or cell_y < 0 or cell_x >= cols or cell_y >= rows:
		return false
	return grid[cell_y][cell_x] == 0


func can_occupy(x: float, y: float, radius: float = DEFAULT_AGENT_RADIUS, blocked_cells = null) -> bool:
	var samples := [
		Vector2(x, y),
		Vector2(x - radius, y - radius),
		Vector2(x + radius, y - radius),
		Vector2(x - radius, y + radius),
		Vector2(x + radius, y + radius),
	]
	for sample in samples:
		if not is_floor(sample.x, sample.y):
			return false
		if blocked_cells != null and blocked_cells.has(Vector2i(int(floor(sample.x)), int(floor(sample.y)))):
			return false
	return true


## Grid-space A* over the facility, matching maze.js's pathfind(): 8-way,
## octile heuristic, and diagonal steps rejected unless both flanking
## orthogonal cells are also open (no corner-cutting through wall corners).
## Built lazily and cached — safe because a generator's grid never changes
## after generate() completes.
func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array:
	var astar := _get_astar()
	if not astar.is_in_boundsv(from_cell) or not astar.is_in_boundsv(to_cell):
		return []
	if astar.is_point_solid(from_cell) or astar.is_point_solid(to_cell):
		return []
	var path: PackedVector2Array = astar.get_id_path(from_cell, to_cell)
	var result: Array = []
	for point in path:
		result.append(Vector2i(point))
	return result


func _get_astar() -> AStarGrid2D:
	if _astar == null:
		_astar = AStarGrid2D.new()
		_astar.region = Rect2i(0, 0, cols, rows)
		_astar.cell_size = Vector2(1, 1)
		_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		_astar.update()
		for y in rows:
			for x in cols:
				_astar.set_point_solid(Vector2i(x, y), grid[y][x] != 0)
	return _astar


## Grid-raymarch line of sight, matching maze.js's hasLineOfSight(): samples
## the straight segment at ceil(distance*6) points and rejects on the first
## sampled point that isn't floor. Walls only — no prop occlusion (matches
## the original; props aren't ported yet, see MIGRATION.md).
func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var distance := from.distance_to(to)
	var steps: int = maxi(1, int(ceil(distance * 6.0)))
	for i in range(steps + 1):
		var point := from.lerp(to, float(i) / float(steps))
		if not is_floor(point.x, point.y):
			return false
	return true


func floor_cells() -> Array:
	var cells: Array = []
	for y in range(1, rows - 1):
		for x in range(1, cols - 1):
			if grid[y][x] == 0:
				cells.append(Vector2i(x, y))
	return cells


func distance_map(start_x: int, start_y: int) -> Dictionary:
	var distances := {}
	var start_cell := Vector2i(start_x, start_y)
	distances[start_cell] = 0
	var queue: Array = [start_cell]
	var qi := 0
	while qi < queue.size():
		var current: Vector2i = queue[qi]
		qi += 1
		var distance: int = distances[current]
		for dir in DIRECTIONS4:
			var next_cell: Vector2i = current + dir
			if distances.has(next_cell) or not is_floor(next_cell.x + 0.5, next_cell.y + 0.5):
				continue
			distances[next_cell] = distance + 1
			queue.append(next_cell)
	return distances


func nearest_open_position(origin_x: float, origin_y: float, radius: float, blocked_cells = null) -> Dictionary:
	var start_cell := Vector2i(int(floor(origin_x)), int(floor(origin_y)))
	var visited := {start_cell: true}
	var queue: Array = [start_cell]
	var qi := 0
	while qi < queue.size():
		var current: Vector2i = queue[qi]
		qi += 1
		var world_x: float = current.x + 0.5
		var world_y: float = current.y + 0.5
		if can_occupy(world_x, world_y, radius, blocked_cells):
			return {"x": world_x, "y": world_y, "cell": current}
		for dir in DIRECTIONS4:
			var next_cell: Vector2i = current + dir
			if visited.has(next_cell) or not is_floor(next_cell.x + 0.5, next_cell.y + 0.5):
				continue
			visited[next_cell] = true
			queue.append(next_cell)
	return {}


func occupiable_component(origin_cell: Vector2i, radius: float, blocked_cells = null) -> Dictionary:
	var start_pos := nearest_open_position(origin_cell.x + 0.5, origin_cell.y + 0.5, radius, blocked_cells)
	var visited := {}
	if start_pos.is_empty():
		return visited
	var start_cell: Vector2i = start_pos["cell"]
	visited[start_cell] = true
	var queue: Array = [start_cell]
	var qi := 0
	while qi < queue.size():
		var current: Vector2i = queue[qi]
		qi += 1
		for dir in DIRECTIONS4:
			var next_cell: Vector2i = current + dir
			if visited.has(next_cell) or not can_occupy(next_cell.x + 0.5, next_cell.y + 0.5, radius, blocked_cells):
				continue
			visited[next_cell] = true
			queue.append(next_cell)
	return visited


# ---------------------------------------------------------------------------
# Objective placement: safe zones, relays, batteries, service lift
# ---------------------------------------------------------------------------

func place_safe_zones(from_start: Dictionary) -> void:
	safe_zones = []
	if safe_zone_count <= 0:
		return
	if safe_zone_at_spawn:
		safe_zones = [{"id": "safe-0", "x": start.x, "y": start.y, "room_id": "room-lobby", "spawn": true}]
		return

	var room_candidates: Array = rooms.duplicate()
	room_candidates.sort_custom(func(a, b):
		var ad: int = from_start.get(a["center"], 0)
		var bd: int = from_start.get(b["center"], 0)
		return ad > bd
	)
	var alternatives: Array = room_candidates.filter(func(r): return r["id"] != "room-lobby")
	var wanted: int = mini(safe_zone_count, alternatives.size())
	if wanted <= 0:
		return

	var stride: int = maxi(1, alternatives.size() / wanted)
	var preferred: Array = []
	var preferred_ids := {}
	var idx := 0
	while preferred.size() < wanted and idx < alternatives.size():
		var room = alternatives[idx]
		preferred.append(room)
		preferred_ids[room["id"]] = true
		idx += stride
	while preferred.size() < wanted:
		var found = null
		for r in alternatives:
			if not preferred_ids.has(r["id"]):
				found = r
				break
		if found == null:
			break
		preferred.append(found)
		preferred_ids[found["id"]] = true

	safe_zones = _make_safe_zones(preferred)
	if safe_zones.size() == wanted and _keeps_hunter_routes_connected():
		return

	var fallback_pool: Array = alternatives.slice(0, mini(alternatives.size(), 12))
	var count := wanted
	while count >= 1:
		for combo in _room_combinations(fallback_pool, count):
			safe_zones = _make_safe_zones(combo)
			if _keeps_hunter_routes_connected():
				return
		count -= 1
	safe_zones = []


static func _make_safe_zones(rooms_subset: Array) -> Array:
	var zones: Array = []
	for i in rooms_subset.size():
		var room = rooms_subset[i]
		zones.append({"id": "safe-%d" % i, "x": room["center"].x, "y": room["center"].y, "room_id": room["id"]})
	return zones


## Marks a generated relay/battery as collected. The `collected` field has
## existed on these dictionaries since generation, but nothing wrote to it —
## so any hunter reading generator.relays/batteries saw a floor where nothing
## had ever been picked up. Opalie guards collected relays, Haelith hunts
## uncollected ones, Ysolde steals uncollected batteries and Solyth burns
## them, so the write side has to exist for those to mean anything.
## `entries` is the generator array to search; returns true if it found one.
func mark_collected(entries: Array, cell: Vector2i) -> bool:
	for entry in entries:
		if entry["x"] == cell.x and entry["y"] == cell.y:
			entry["collected"] = true
			return true
	return false


## Convenience for the two callers that always want "every uncollected one".
func uncollected(entries: Array) -> Array:
	var remaining: Array = []
	for entry in entries:
		if not entry.get("collected", false):
			remaining.append(entry)
	return remaining


func get_safe_zone_blocked_cells() -> Dictionary:
	var blocked := {}
	for zone in safe_zones:
		if zone.get("spawn", false):
			continue
		var center_x: float = zone["x"] + 0.5
		var center_y: float = zone["y"] + 0.5
		var extent := int(ceil(SAFE_ZONE_BLOCK_RADIUS))
		for y in range(zone["y"] - extent, zone["y"] + extent + 1):
			for x in range(zone["x"] - extent, zone["x"] + extent + 1):
				if not is_floor(x + 0.5, y + 0.5):
					continue
				if Vector2(x + 0.5 - center_x, y + 0.5 - center_y).length() < SAFE_ZONE_BLOCK_RADIUS:
					blocked[Vector2i(x, y)] = true
	return blocked


func _keeps_hunter_routes_connected() -> bool:
	var blocked := get_safe_zone_blocked_cells()
	var component := occupiable_component(start, 0.25, blocked)
	for cell in floor_cells():
		if can_occupy(cell.x + 0.5, cell.y + 0.5, 0.25, blocked) and not component.has(cell):
			return false
	return true


func _room_combinations(source_rooms: Array, size: int) -> Array:
	var result: Array = []
	if size <= 0 or size > source_rooms.size():
		return result
	_walk_combinations(source_rooms, size, 0, [], result)
	return result


func _walk_combinations(source_rooms: Array, size: int, start_index: int, current: Array, result: Array) -> void:
	if current.size() == size:
		result.append(current.duplicate())
		return
	for index in range(start_index, source_rooms.size()):
		current.append(source_rooms[index])
		_walk_combinations(source_rooms, size, index + 1, current, result)
		current.pop_back()


func place_relays(from_start: Dictionary) -> void:
	var candidates: Array = []
	for cell in floor_cells():
		if spawn_points.has(cell):
			continue
		var start_distance: int = from_start.get(cell, 0)
		if start_distance <= 14:
			continue
		if not can_occupy(cell.x + 0.5, cell.y + 0.5):
			continue
		if Vector2(cell.x - exit_cell.x, cell.y - exit_cell.y).length() <= 4:
			continue
		if not _far_from_all(cell, safe_zones, 5.0):
			continue
		candidates.append(cell)
	_shuffle_array(candidates)
	var chosen: Array = []
	for cell in candidates:
		if _pairwise_far(cell, chosen, 7.0):
			chosen.append({"id": "relay-%d" % chosen.size(), "x": cell.x, "y": cell.y, "collected": false})
			if chosen.size() == relay_count:
				break
	relays = chosen


func place_batteries(from_start: Dictionary) -> void:
	var candidates: Array = []
	for cell in floor_cells():
		if spawn_points.has(cell):
			continue
		var distance: int = from_start.get(cell, -1)
		if distance <= 5:
			continue
		if not can_occupy(cell.x + 0.5, cell.y + 0.5):
			continue
		if Vector2(cell.x - exit_cell.x, cell.y - exit_cell.y).length() <= 2:
			continue
		if not _far_from_all(cell, relays, 2.5):
			continue
		if not _far_from_all(cell, safe_zones, 2.5):
			continue
		candidates.append(cell)
	_shuffle_array(candidates)
	var chosen: Array = []
	for cell in candidates:
		if _pairwise_far(cell, chosen, 4.5):
			# Fixed 15% — matches maze.js's placeBatteries (one battery powers a
			# heater/fan appliance for exactly 30s at its 0.5%/s drain rate).
			chosen.append({"id": "battery-%d" % chosen.size(), "x": cell.x, "y": cell.y, "charge": 15.0, "collected": false})
			if chosen.size() == battery_count:
				break
	batteries = chosen


## Not part of generate() — called on demand once a hunter milestone actually
## needs it (see MIGRATION.md), simplified to ONE spawn from maze.js's
## placeHunterSpawns (which picks two, for a roster this port doesn't have
## yet). Reuses the same random stream as relay/battery placement.
func place_hunter_spawn(from_start: Dictionary) -> Vector2i:
	var hunter_component := occupiable_component(start, 0.25, get_safe_zone_blocked_cells())
	var candidates: Array = []
	for cell in floor_cells():
		if spawn_points.has(cell):
			continue
		var distance: int = from_start.get(cell, 0)
		if distance <= 20:
			continue
		if not hunter_component.has(cell):
			continue
		if not can_occupy(cell.x + 0.5, cell.y + 0.5, 0.25):
			continue
		if not _far_from_all(cell, safe_zones, 7.0):
			continue
		if Vector2(cell.x - exit_cell.x, cell.y - exit_cell.y).length() <= 4:
			continue
		candidates.append(cell)
	if candidates.is_empty():
		return exit_cell
	return candidates[random.next_index(candidates.size())]


static func _far_from_all(cell: Vector2i, zones: Array, min_dist: float) -> bool:
	for zone in zones:
		if Vector2(cell.x - zone["x"], cell.y - zone["y"]).length() <= min_dist:
			return false
	return true


static func _pairwise_far(cell: Vector2i, chosen: Array, min_dist: float) -> bool:
	for other in chosen:
		if Vector2(cell.x - other["x"], cell.y - other["y"]).length() < min_dist:
			return false
	return true


func pick_service_lift(from_start: Dictionary) -> Vector2i:
	var lift_rng := SeededRandom.new("%s:SERVICE-LIFT" % seed_text)
	var reachable: Array = []
	for cell in floor_cells():
		if spawn_points.has(cell):
			continue
		if from_start.has(cell) and can_occupy(cell.x + 0.5, cell.y + 0.5):
			reachable.append(cell)
	if reachable.is_empty():
		return start

	var min_steps: float = (cols + rows) * 0.35
	var room_corner_choices: Array = []
	for room in rooms:
		if room["id"] == "room-lobby":
			continue
		var w: int = room["width"]
		var h: int = room["height"]
		var corner_cells: Array = []
		for cell in reachable:
			if cell.x >= room["x"] + int(floor(w * 0.62)) \
				and cell.x < room["x"] + w - 1 \
				and cell.y > room["y"] \
				and cell.y <= room["y"] + maxi(1, int(floor(h * 0.38))) \
				and cell.x >= cols / 2.0 \
				and cell.y <= rows / 2.0 \
				and float(from_start.get(cell, 0)) >= min_steps:
				corner_cells.append(cell)
		if not corner_cells.is_empty():
			room_corner_choices.append(corner_cells)
	if not room_corner_choices.is_empty():
		var selected: Array = room_corner_choices[lift_rng.next_index(room_corner_choices.size())]
		return selected[lift_rng.next_index(selected.size())]

	var top_right: Array = reachable.filter(func(c): return c.x >= cols / 2.0 and c.y <= rows / 2.0)
	var top_right_far: Array = top_right.filter(func(c): return float(from_start.get(c, 0)) >= min_steps)
	var far: Array = reachable.filter(func(c): return float(from_start.get(c, 0)) >= min_steps)
	var pool: Array = top_right_far if not top_right_far.is_empty() else (top_right if not top_right.is_empty() else (far if not far.is_empty() else reachable))
	pool.sort_custom(func(a, b): return (a.x - a.y) > (b.x - b.y))
	var band_size: int = maxi(1, int(ceil(pool.size() * 0.12)))
	var band: Array = pool.slice(0, band_size)
	if band.is_empty():
		return pool[0]
	return band[lift_rng.next_index(band.size())]


func _shuffle_array(items: Array) -> void:
	for index in range(items.size() - 1, 0, -1):
		var swap_index: int = random.next_index(index + 1)
		var tmp = items[index]
		items[index] = items[swap_index]
		items[swap_index] = tmp


## Where the player can get out of sight.
##
## In the original these are derived from PROPS -- lockers, privacy curtains,
## supply crates -- placed by populateRooms(), which is the deferred
## room-content milestone and is enormous. Rather than block three hunters on
## that whole catalogue, spots are placed directly here on open cells that back
## onto a wall, which is where a locker would stand anyway. The same
## simplification place_hunter_spawn() already makes: real placement, honest
## about being a simpler rule than the original's.
##
## Called on demand rather than from generate(), so the validator's contract is
## unaffected.
var hiding_spots: Array = []


## HUNTER_ROSTER.md's "trivial gap": a point -> room query nothing needed
## until Loxelle, whose passive only ever destroys spots in her OWN room.
func room_at(x: float, y: float) -> Dictionary:
	for room in rooms:
		if x >= room["x"] and x < room["x"] + room["width"] \
				and y >= room["y"] and y < room["y"] + room["height"]:
			return room
	return {}


func place_hiding_spots(count: int = 6) -> Array:
	hiding_spots = []
	var rng := SeededRandom.new("%s:HIDING-SPOTS" % seed_text)
	var taken := {exit_cell: true}
	for spawn_cell in spawn_points:
		taken[spawn_cell] = true
	for group in [relays, batteries, safe_zones]:
		for entry in group:
			taken[Vector2i(entry["x"], entry["y"])] = true

	# Room cells preferred over corridor ones: a locker in a room is furniture,
	# a locker wedged in a corridor wall is not somewhere real. It also gives
	# every spot a real room_id, which Loxelle's passive depends on -- she only
	# ever burns a spot in her OWN room, and a spot with no room could never be
	# hers or anyone else's. Corridor cells are the fallback for a layout with
	# too little room floor to seat every spot, not the first choice.
	var in_room: Array = []
	var in_corridor: Array = []
	for y in range(1, rows - 1):
		for x in range(1, cols - 1):
			var cell := Vector2i(x, y)
			if grid[y][x] != 0 or taken.has(cell):
				continue
			# Backed onto a wall, and not in a doorway: a spot in the middle of a
			# corridor is not somewhere you could hide, and a spot in a doorway
			# blocks the way through.
			if _walls_around(cell) != 1:
				continue
			if room_at(cell.x, cell.y).is_empty():
				in_corridor.append(cell)
			else:
				in_room.append(cell)
	if in_room.is_empty() and in_corridor.is_empty():
		return hiding_spots

	# Spread them out. Six lockers clustered in one room is one hiding place
	# with six doors, not six hiding places.
	var spacing := maxf(4.0, float(mini(cols, rows)) / float(maxi(1, count)))
	# Room candidates exhausted first, corridor cells only to fill what is left.
	for candidates in [in_room, in_corridor]:
		while hiding_spots.size() < count and not candidates.is_empty():
			var pick: Vector2i = candidates[rng.next_index(candidates.size())]
			var clear := true
			for spot in hiding_spots:
				if Vector2(pick).distance_to(Vector2(spot["x"], spot["y"])) < spacing:
					clear = false
					break
			candidates.erase(pick)
			if not clear:
				continue
			var room := room_at(pick.x, pick.y)
			hiding_spots.append({"id": "hide-%d" % hiding_spots.size(),
				"x": pick.x, "y": pick.y,
				"room_id": String(room.get("id", ""))})
	return hiding_spots


func _walls_around(cell: Vector2i) -> int:
	var walls := 0
	for step in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var at: Vector2i = cell + step
		if at.x < 0 or at.y < 0 or at.x >= cols or at.y >= rows or grid[at.y][at.x] != 0:
			walls += 1
	return walls


## An open cell beside a spot, for stepping out of it.
func hiding_exit_position(spot: Dictionary) -> Vector2:
	var open := nearest_open_position(spot["x"] + 0.5, spot["y"] + 0.5, GameConfig.PLAYER_RADIUS)
	if open.is_empty():
		return Vector2(spot["x"] + 0.5, spot["y"] + 0.5)
	return Vector2(open["x"], open["y"])


## Verrine's vent network: a fixed set of stops at real room centers, shared
## between the physical interactable a player steps into (see
## FacilityView3D._spawn_interactables) and her own gimmick, which reads this
## SAME list rather than picking its own -- the two have to agree on where
## every vent is, or the props on the floor and what she thinks the network
## looks like would disagree.
var vents: Array = []


## Zephyra's economy. A generator-owned scatter, same reasoning as
## place_vents(): the physical pickups (FacilityView3D._spawn_interactables)
## and anything reading `generator.coins` (nothing does yet, but Ysolde's
## `generator.batteries` precedent is the shape a future coin-aware gimmick
## would want) have to agree on where every coin actually is.
var coins: Array = []


func place_coins(count: int = 5) -> Array:
	coins = []
	if rooms.is_empty():
		return coins
	var rng := SeededRandom.new("%s:COINS" % seed_text)
	var taken := {exit_cell: true}
	for spawn_cell in spawn_points:
		taken[spawn_cell] = true
	for group in [relays, batteries, safe_zones, hiding_spots, vents]:
		for entry in group:
			taken[Vector2i(entry["x"], entry["y"])] = true

	var pool := rooms.duplicate()
	while coins.size() < count and not pool.is_empty():
		var index := rng.next_index(pool.size())
		var room: Dictionary = pool[index]
		pool.remove_at(index)
		var center: Vector2i = room["center"]
		var open := nearest_open_position(center.x + 0.5, center.y + 0.5, DEFAULT_AGENT_RADIUS, taken)
		if open.is_empty():
			continue
		var cell := Vector2i(int(open["x"]), int(open["y"]))
		taken[cell] = true
		coins.append({"id": "coin-%d" % coins.size(), "x": cell.x, "y": cell.y})
	return coins


func place_vents(count: int = 4) -> Array:
	vents = []
	if rooms.is_empty():
		return vents
	var rng := SeededRandom.new("%s:VENT-NETWORK" % seed_text)
	var pool := rooms.duplicate()
	while vents.size() < count and not pool.is_empty():
		var index := rng.next_index(pool.size())
		var room: Dictionary = pool[index]
		pool.remove_at(index)
		var center: Vector2i = room["center"]
		var open := nearest_open_position(center.x + 0.5, center.y + 0.5, DEFAULT_AGENT_RADIUS)
		var at := Vector2i(int(open["x"]), int(open["y"])) if not open.is_empty() else center
		vents.append({"id": "vent-%d" % (vents.size() + 1), "x": at.x, "y": at.y,
			"room_id": String(room.get("id", "")), "index": vents.size()})
	return vents
