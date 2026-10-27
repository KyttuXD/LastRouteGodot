class_name SewerRouteGenerator
extends RefCounted

## Deterministic sewer/waterworks layer streamed one level below the Last Route
## maze (level -1). Like StreamedRouteGenerator it owns topology only; the view
## consumes chunk dictionaries of the same CHUNK_SIZE so both layers stream on
## the same coordinates.
##
## Every chunk carries the same main cross so seams always meet: a nine-wide
## brick tunnel along x = 22 and z = 22, made of a three-wide central channel
## of shallow flowing water (wading only: slow and loud, never deep) between two
## three-wide dry walkways. Footbridges cross the channel at regular spacing so
## a dry walker is never trapped on one bank. The tunnels meet in a junction
## chamber. Up to two quadrants hold a utility room (pump, valve or overflow) on
## a three-wide dry branch; the others may hold an access shaft that climbs to
## an open maze hallway cell above: every entrance is a climbable ladder
## (LevelLink kind "ladder") under a manhole lid or a floor grate ("cover").

const CHUNK_SIZE := StreamedRouteGenerator.CHUNK_SIZE
const LEVEL := -1
const SURFACE_LEVEL := 0

## Grid codes. Water is walkable (wading) but never dry; bridge cells are dry
## decks over the channel.
const SOLID := 1
const DRY := 0
const WATER := 2
const BRIDGE := 3

const CENTER := CHUNK_SIZE / 2
const TUNNEL_HALF := 4           # 22 - 4 .. 22 + 4: walkway 18-20, water 21-23, walkway 24-26
const CHANNEL_HALF := 1
const JUNCTION_HALF := 6         # 13 x 13 chamber
const BRIDGE_OFFSETS := [3, 10, 34, 41]   # along each tunnel, clear of the junction
const QUADRANT_CENTERS := [Vector2i(9, 9), Vector2i(35, 9), Vector2i(9, 35), Vector2i(35, 35)]
const ROOM_HALF := 3             # 7 x 7 utility rooms
const SHAFT_HALF := 1            # 3 x 3 dry shaft chamber under a manhole
const ROOM_KINDS := ["pump_room", "valve_room", "overflow_chamber"]
const LINK_CHANCE := 0.55

var world_seed: String
var surface: StreamedRouteGenerator
var _cache := {}


func _init(p_surface: StreamedRouteGenerator) -> void:
	surface = p_surface
	world_seed = p_surface.world_seed


func is_chunk_allowed(coord: Vector3i) -> bool:
	return coord.y == LEVEL and surface.is_chunk_allowed(Vector3i(coord.x, SURFACE_LEVEL, coord.z))


func chunk_id(coord: Vector3i) -> String:
	return "SEWER:%d:%d:%d" % [coord.x, coord.y, coord.z]


func chunk(coord: Vector3i) -> Dictionary:
	var key := chunk_id(coord)
	if not _cache.has(key):
		_cache[key] = _build_chunk(coord)
	return _cache[key]


## The links touching the surface chunk above `coord` (any y). Surface code asks
## this to place manholes/grates; the sewer view uses it for ladders.
func links_for(coord: Vector3i) -> Array:
	return chunk(Vector3i(coord.x, LEVEL, coord.z))["links"]


func _build_chunk(coord: Vector3i) -> Dictionary:
	var grid := []
	for z in CHUNK_SIZE:
		var row := []
		row.resize(CHUNK_SIZE)
		row.fill(SOLID)
		grid.append(row)
	if not is_chunk_allowed(coord):
		return {"coord": coord, "chunk_id": chunk_id(coord), "grid": grid, "rooms": [],
			"links": [], "features": [], "level": coord.y}
	_carve_main_cross(grid)
	var rng := SeededRandom.new("%s:SEWER:%d:%d" % [world_seed, coord.x, coord.z])
	var rooms := []
	var links := []
	var features := []
	var order := [0, 1, 2, 3]
	# Deterministic shuffle so rooms and shafts land in different quadrants per chunk.
	for i in range(order.size() - 1, 0, -1):
		var j := rng.next_index(i + 1)
		var t: int = order[i]
		order[i] = order[j]
		order[j] = t
	var room_count := 1 + rng.next_index(2)
	var wants_link := coord.x == 0 and coord.z == 0 or rng.next_float() < LINK_CHANCE
	var surface_data: Dictionary = surface.chunk(Vector3i(coord.x, SURFACE_LEVEL, coord.z))
	var blocked := _surface_blocked_cells(surface_data)
	var covers := ["manhole", "grate"]
	for slot in order.size():
		var quadrant: int = order[slot]
		var qc: Vector2i = QUADRANT_CENTERS[quadrant]
		if slot < room_count:
			var kind: String = ROOM_KINDS[rng.next_index(ROOM_KINDS.size())]
			# The overflow chamber is two cells wider so a three-wide dry ring
			# survives around its central basin.
			var half := ROOM_HALF + 1 if kind == "overflow_chamber" else ROOM_HALF
			var rect := Rect2i(qc - Vector2i(half, half), Vector2i.ONE * (half * 2 + 1))
			_carve_rect(grid, rect, DRY)
			_carve_branch(grid, qc, half)
			if kind == "overflow_chamber":
				_carve_rect(grid, Rect2i(qc - Vector2i.ONE, Vector2i(3, 3)), WATER)
			rooms.append({"kind": kind, "rect": rect, "center": qc})
			features.append_array(_room_features(kind, rect, qc))
		elif wants_link and links.size() < 2:
			var up := _shaft_cell(qc, surface_data["grid"], blocked)
			if up.x < 0:
				continue
			var cover: String = covers[rng.next_index(covers.size())]
			_carve_rect(grid, Rect2i(up - Vector2i(SHAFT_HALF, SHAFT_HALF), Vector2i(3, 3)), DRY)
			_carve_branch(grid, up, SHAFT_HALF)
			var link := LevelLink.make("ladder", coord, SURFACE_LEVEL, up, LEVEL, up)
			link["cover"] = cover
			links.append(link)
			features.append({"type": "sewerLadder", "cell": up, "link": links.back()["id"]})
	features.append_array(_tunnel_features())
	return {"coord": coord, "chunk_id": chunk_id(coord), "level": coord.y, "grid": grid,
		"rooms": rooms, "links": links, "features": features, "biome": "sewer", "region": "sewer"}


static func _carve_rect(grid: Array, rect: Rect2i, code: int) -> void:
	for z in range(maxi(rect.position.y, 0), mini(rect.end.y, CHUNK_SIZE)):
		for x in range(maxi(rect.position.x, 0), mini(rect.end.x, CHUNK_SIZE)):
			grid[z][x] = code


func _carve_main_cross(grid: Array) -> void:
	var lo := CENTER - TUNNEL_HALF
	var width := TUNNEL_HALF * 2 + 1
	_carve_rect(grid, Rect2i(0, lo, CHUNK_SIZE, width), DRY)
	_carve_rect(grid, Rect2i(lo, 0, width, CHUNK_SIZE), DRY)
	_carve_rect(grid, Rect2i(CENTER - JUNCTION_HALF, CENTER - JUNCTION_HALF,
		JUNCTION_HALF * 2 + 1, JUNCTION_HALF * 2 + 1), DRY)
	var c_lo := CENTER - CHANNEL_HALF
	var c_w := CHANNEL_HALF * 2 + 1
	_carve_rect(grid, Rect2i(0, c_lo, CHUNK_SIZE, c_w), WATER)
	_carve_rect(grid, Rect2i(c_lo, 0, c_w, CHUNK_SIZE), WATER)
	# Bridges three cells wide over each channel, plus the four decks around the
	# junction's central confluence.
	for offset in BRIDGE_OFFSETS:
		_carve_rect(grid, Rect2i(offset - 1, c_lo, 3, c_w), BRIDGE)
		_carve_rect(grid, Rect2i(c_lo, offset - 1, c_w, 3), BRIDGE)
	for d in [-JUNCTION_HALF + 2, JUNCTION_HALF - 2]:
		_carve_rect(grid, Rect2i(CENTER + d - 1, c_lo, 3, c_w), BRIDGE)
		_carve_rect(grid, Rect2i(c_lo, CENTER + d - 1, c_w, 3), BRIDGE)


## A three-wide dry branch from a room/shaft centre straight to the nearer
## tunnel's outer walkway.
static func _carve_branch(grid: Array, from: Vector2i, half: int) -> void:
	var walk_lo := CENTER - TUNNEL_HALF
	var walk_hi := CENTER + TUNNEL_HALF
	var dx := absi(from.x - CENTER)
	var dz := absi(from.y - CENTER)
	if dx <= dz:
		# Toward the north-south tunnel along x.
		var start := from.x + half + 1 if from.x < CENTER else walk_hi + 1
		var finish := walk_lo if from.x < CENTER else from.x - half
		_carve_rect(grid, Rect2i(start, from.y - 1, finish - start, 3), DRY)
	else:
		var start := from.y + half + 1 if from.y < CENTER else walk_hi + 1
		var finish := walk_lo if from.y < CENTER else from.y - half
		_carve_rect(grid, Rect2i(from.x - 1, start, 3, finish - start), DRY)


## Maze cells the manhole must keep clear of: anything a prop, fixture, pickup
## or hunter spawn claims (with a one-cell ring), so no lid sits under furniture.
static func _surface_blocked_cells(data: Dictionary) -> Dictionary:
	var blocked := {}
	for key in ["region_props", "fixtures", "pickups", "hunter_spawns"]:
		for entry in data.get(key, []):
			var cells: Array = [entry.get("cell", Vector2i(-99, -99))]
			cells.append_array(entry.get("occupied_cells", []))
			cells.append_array(entry.get("doorway_cells", []))
			for cell in cells:
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						blocked[Vector2i(cell) + Vector2i(dx, dz)] = true
	for room in data.get("rooms", []):
		# Hallway cells only: rooms keep their own floor plans.
		var rect: Rect2i = room.get("rect", Rect2i())
		for z in range(rect.position.y - 1, rect.end.y + 1):
			for x in range(rect.position.x - 1, rect.end.x + 1):
				blocked[Vector2i(x, z)] = true
	return blocked


## The open maze hallway cell nearest the quadrant centre with a full 3x3 of
## open floor around it (the lid plus clearance), or (-1, -1).
static func _shaft_cell(quadrant_center: Vector2i, surface_grid: Array, blocked: Dictionary) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for z in range(quadrant_center.y - 7, quadrant_center.y + 8):
		for x in range(quadrant_center.x - 7, quadrant_center.x + 8):
			var cell := Vector2i(x, z)
			# Stay out of the tunnel band and two cells off the chunk edge.
			if absi(x - CENTER) <= TUNNEL_HALF + SHAFT_HALF + 1 or absi(z - CENTER) <= TUNNEL_HALF + SHAFT_HALF + 1:
				continue
			if x < 3 or z < 3 or x > CHUNK_SIZE - 4 or z > CHUNK_SIZE - 4:
				continue
			if blocked.has(cell):
				continue
			var clear := true
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					if int(surface_grid[z + dz][x + dx]) != 0:
						clear = false
			if not clear:
				continue
			var d := (cell - quadrant_center).length_squared()
			if d < best_d:
				best_d = d
				best = cell
	return best


static func _room_features(kind: String, rect: Rect2i, center: Vector2i) -> Array:
	var wall_n := Vector2i(center.x, rect.position.y)
	match kind:
		"pump_room":
			return [{"type": "sewerPump", "cell": wall_n, "yaw": 0.0},
				{"type": "sewerPipeRun", "cell": Vector2i(rect.position.x, center.y), "yaw": PI / 2.0}]
		"valve_room":
			return [{"type": "sewerValveWheel", "cell": wall_n, "yaw": 0.0},
				{"type": "sewerValveWheel", "cell": Vector2i(rect.end.x - 1, center.y), "yaw": -PI / 2.0}]
		_:
			return [{"type": "sewerOverflowGrate", "cell": center, "yaw": 0.0}]


static func _tunnel_features() -> Array:
	var out := []
	for offset in [7, 37]:
		out.append({"type": "sewerLamp", "cell": Vector2i(offset, CENTER - TUNNEL_HALF), "yaw": 0.0})
		out.append({"type": "sewerLamp", "cell": Vector2i(CENTER + TUNNEL_HALF, offset), "yaw": -PI / 2.0})
	return out


static func is_walkable(code: int) -> bool:
	return code != SOLID


static func is_dry(code: int) -> bool:
	return code == DRY or code == BRIDGE
