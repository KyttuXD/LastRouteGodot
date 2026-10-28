class_name SewerRouteGenerator
extends RefCounted

## Deterministic sewer/waterworks layer streamed one level below the Last Route
## maze (level -1). Like StreamedRouteGenerator it owns topology only; the view
## consumes chunk dictionaries of the same CHUNK_SIZE so both layers stream on
## the same coordinates.
##
## Every chunk carries the same main cross so seams always meet: a nine-wide
## brick tunnel along x = 22 and z = 22, made of a three-wide central channel
## of deep flowing water sunk below two railed three-wide walkways. Bridge decks
## cross the channel at regular spacing so nobody is trapped on one bank, and
## the tunnels meet in a junction chamber whose confluence is decked over with
## a cross-shaped grate plaza. Up to two quadrants hold a utility room (pump, valve or overflow) on
## a three-wide dry branch; the others may hold an access shaft that climbs to
## an open maze hallway cell above: every entrance is a climbable ladder
## (LevelLink kind "ladder") under a manhole lid or a floor grate ("cover").

const CHUNK_SIZE := StreamedRouteGenerator.CHUNK_SIZE
const LEVEL := -1
const SURFACE_LEVEL := 0

## Grid codes. Water is open channel nobody walks in; bridge cells are walkable
## decks with the channel running underneath.
const SOLID := 1
const DRY := 0
const WATER := 2
const BRIDGE := 3

const CENTER := CHUNK_SIZE / 2
const TUNNEL_HALF := 4           # 22 - 4 .. 22 + 4: walkway 18-20, water 21-23, walkway 24-26
const CHANNEL_HALF := 1
const JUNCTION_HALF := 6         # 13 x 13 chamber
## One bridge on each tunnel arm either side of the junction (plus the junction's
## grate plaza): a crossing about every 24 m along the channel.
const BRIDGE_OFFSETS := [10, 34]
## Centres (along each arm, from the junction centre) of the 3 x 3 grate tiles
## that deck the confluence: cells -4..+4 of both arms are walkable grating.
const PLAZA_TILES := [-3, 0, 3]
const QUADRANT_CENTERS := [Vector2i(9, 9), Vector2i(35, 9), Vector2i(9, 35), Vector2i(35, 35)]
const ROOM_HALF := 3             # 7 x 7 utility rooms
const SHAFT_HALF := 1            # 3 x 3 dry shaft chamber under a manhole
const ROOM_KINDS := ["pump_room", "valve_room", "overflow_chamber"]
const LINK_CHANCE := 0.55
## Every sewer space has the same low brick ceiling, so a ladder shaft always
## spans exactly LEVEL_HEIGHT - CEILING_HEIGHT between it and the maze floor.
const CEILING_HEIGHT := 3.2
## Deep channels: the bed lies CHANNEL_DEPTH below the walkways and the water
## surface WATER_SURFACE below them (negative = down). Nobody wades: railings
## line every walkway edge and the channel cells block movement, so the water
## is crossed only on the bridges and the junction's grate plaza.
const CHANNEL_DEPTH := 1.0
const WATER_SURFACE := -0.3

var world_seed: String
var surface: StreamedRouteGenerator
var _cache := {}


func _init(p_surface: StreamedRouteGenerator) -> void:
	surface = p_surface
	world_seed = p_surface.world_seed


func is_chunk_allowed(coord: Vector3i) -> bool:
	return coord.y == LEVEL


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
		return _streamed_schema(coord, grid, [], [], [])
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
			# The ladder hangs on the brick on the far side from the tunnel: the 3x3
			# shaft chamber opens away from that wall and its branch leaves from the
			# chamber's middle, so the wall behind the rungs stays solid.
			var wall := _ladder_wall(up)
			var chamber_center := up - wall
			_carve_rect(grid, Rect2i(chamber_center - Vector2i(SHAFT_HALF, SHAFT_HALF), Vector2i(3, 3)), DRY)
			_carve_branch(grid, chamber_center, SHAFT_HALF)
			var link := LevelLink.make("ladder", coord, SURFACE_LEVEL, up, LEVEL, up)
			link["cover"] = cover
			link["wall"] = wall
			links.append(link)
			features.append({"type": "sewerLadder", "cell": up, "link": links.back()["id"], "wall": wall})
	features.append_array(_tunnel_features())
	features.append_array(_crossing_features())
	features = _mount_on_walls(grid, features)
	return _streamed_schema(coord, grid, rooms, links, features)


## The chunk in StreamedRouteGenerator's schema so the streamed view, minimap and
## audits read it like any maze chunk: "grid" is 0 for every walkable cell
## (water included) and 1 for brick; "sewer_grid" keeps the dry/water/bridge codes.
func _streamed_schema(coord: Vector3i, sewer_grid: Array, rooms: Array, links: Array, features: Array) -> Dictionary:
	var grid := []
	for row_value in sewer_grid:
		var row := []
		for code in row_value:
			row.append(0 if is_walkable(int(code)) else 1)
		grid.append(row)
	var room_entries := []
	for index in rooms.size():
		var room: Dictionary = rooms[index]
		room_entries.append({"id": "%s:ROOM:%d" % [chunk_id(coord), index], "room_type": room["kind"],
			"rect": room["rect"], "center": room["center"]})
	var seam := range(CENTER - TUNNEL_HALF, CENTER + TUNNEL_HALF + 1)
	return {"schema": 2, "coord": coord, "chunk_id": chunk_id(coord), "level": coord.y,
		"biome": "sewer", "region": "sewer", "grid": grid, "sewer_grid": sewer_grid,
		"rooms": room_entries, "corridors": [], "suites": [],
		"edges": {"west": seam, "east": seam, "north": seam, "south": seam},
		"stairs": [], "safe_room": false, "safe_room_data": {}, "region_props": _feature_props(coord, features),
		"fixtures": _fixtures(coord, grid, room_entries, features),
		"pickups": _pickups(coord, sewer_grid, grid, features, links),
		"hunter_spawns": [], "dual_level_room": {},
		"floor_voids": [], "ceiling_voids": [], "structural_voids": [],
		"difficulty": surface.difficulty_for_level(coord.y),
		"links": links, "features": features}


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
	# Three-cell bridge decks over each channel along the tunnels, and a
	# cross-shaped grated plaza over the junction's confluence: the water keeps
	# flowing under every deck.
	for offset in BRIDGE_OFFSETS:
		_carve_rect(grid, Rect2i(offset - 1, c_lo, 3, c_w), BRIDGE)
		_carve_rect(grid, Rect2i(c_lo, offset - 1, c_w, 3), BRIDGE)
	for k in PLAZA_TILES:
		_carve_rect(grid, Rect2i(CENTER + k - 1, c_lo, 3, c_w), BRIDGE)
		_carve_rect(grid, Rect2i(c_lo, CENTER + k - 1, c_w, 3), BRIDGE)


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


## Hiding spots in the utility rooms: a cabinet or locker backed against a room
## wall, one per room, kept off the dressing. Same fixture records as the maze.
func _fixtures(coord: Vector3i, grid: Array, rooms: Array, features: Array) -> Array:
	var used := {}
	for feature in features:
		StreamedRouteGenerator._exclude_neighbourhood(used, feature["cell"], 1)
	var rng := SeededRandom.new("%s:SEWER-FIXTURES:%d:%d" % [world_seed, coord.x, coord.z])
	var result := []
	for room in rooms:
		var rect: Rect2i = room["rect"]
		var candidates := []
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var cell := Vector2i(x, z)
				if not used.has(cell) and int(grid[z][x]) == 0 and StreamedRouteGenerator._wall_count(grid, cell) == 1:
					candidates.append(cell)
		if candidates.is_empty():
			continue
		var cell: Vector2i = candidates[rng.next_index(candidates.size())]
		var backing := StreamedRouteGenerator._backing_wall_direction(grid, cell)
		result.append({"id": "%s:FIXTURE:HIDING_SPOT:%d" % [chunk_id(coord), result.size()], "kind": "hiding_spot",
			"cell": cell, "yaw": StreamedRouteGenerator._room_facing_yaw(cell, cell - backing),
			"backing_wall": backing, "open_direction": -backing})
	return result


## Relays and batteries on dry walkways (never in the water, on a bridge or by
## a ladder), at a little under the maze's density, sometimes a tool.
func _pickups(coord: Vector3i, sewer_grid: Array, grid: Array, features: Array, links: Array) -> Array:
	var excluded := {}
	for feature in features:
		StreamedRouteGenerator._exclude_neighbourhood(excluded, feature["cell"], 1)
	for link in links:
		StreamedRouteGenerator._exclude_neighbourhood(excluded, link["to_cell"], 2)
	var candidates := []
	for z in range(1, CHUNK_SIZE - 1):
		for x in range(1, CHUNK_SIZE - 1):
			var cell := Vector2i(x, z)
			if int(sewer_grid[z][x]) == DRY and not excluded.has(cell) \
					and StreamedRouteGenerator._open_spawn_neighbourhood(grid, cell):
				candidates.append(cell)
	var rng := SeededRandom.new("%s:SEWER-PICKUPS:%d:%d" % [world_seed, coord.x, coord.z])
	var plans := ["relay", "battery"]
	if rng.next_float() < 0.55:
		plans.append("relay")
	if rng.next_float() < 0.45:
		plans.append("tool")
	var result := []
	var kind_indices := {}
	for kind_value in plans:
		if candidates.is_empty():
			break
		var kind := String(kind_value)
		var cell: Vector2i = candidates.pop_at(rng.next_index(candidates.size()))
		var index := int(kind_indices.get(kind, 0))
		kind_indices[kind] = index + 1
		var item := ""
		if kind == "tool":
			item = StreamedRouteGenerator.PICKUP_TYPES[rng.next_index(StreamedRouteGenerator.PICKUP_TYPES.size())]
		result.append({"id": surface.pickup_id(coord, index, kind), "cell": cell, "kind": kind, "item": item})
	return result


## Unit step from a ladder cell to the wall its rungs are fixed to: away from
## the tunnel the shaft's branch runs to (the same axis _carve_branch picks).
static func _ladder_wall(cell: Vector2i) -> Vector2i:
	if absi(cell.x - CENTER) <= absi(cell.y - CENTER):
		return Vector2i(-1, 0) if cell.x < CENTER else Vector2i(1, 0)
	return Vector2i(0, -1) if cell.y < CENTER else Vector2i(0, 1)


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
			if x < 4 or z < 4 or x > CHUNK_SIZE - 5 or z > CHUNK_SIZE - 5:
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


## Room dressing. "wall" is the unit step from the cell to the brick the piece
## is fixed to (Vector2i.ZERO for free-standing pieces).
static func _room_features(kind: String, rect: Rect2i, center: Vector2i) -> Array:
	var north := Vector2i(center.x, rect.position.y)
	var west := Vector2i(rect.position.x, center.y)
	var east := Vector2i(rect.end.x - 1, center.y)
	match kind:
		"pump_room":
			return [{"type": "sewerPump", "cell": north, "wall": Vector2i(0, -1)},
				{"type": "sewerPipeRun", "cell": west, "wall": Vector2i(-1, 0)},
				{"type": "sewerLamp", "cell": east, "wall": Vector2i(1, 0)}]
		"valve_room":
			return [{"type": "sewerValveWheel", "cell": north, "wall": Vector2i(0, -1)},
				{"type": "sewerValveWheel", "cell": east, "wall": Vector2i(1, 0)},
				{"type": "sewerPipeRun", "cell": west, "wall": Vector2i(-1, 0)}]
		_:
			return [{"type": "sewerOverflowGrate", "cell": center, "wall": Vector2i.ZERO},
				{"type": "sewerLamp", "cell": north, "wall": Vector2i(0, -1)}]


## Caged lamps far apart on the tunnels' outer walls, and pipe runs between them.
static func _tunnel_features() -> Array:
	var out := []
	for offset in [7, 37]:
		out.append({"type": "sewerLamp", "cell": Vector2i(offset, CENTER - TUNNEL_HALF), "wall": Vector2i(0, -1)})
		out.append({"type": "sewerLamp", "cell": Vector2i(CENTER + TUNNEL_HALF, offset), "wall": Vector2i(1, 0)})
	for offset in [14, 30]:
		out.append({"type": "sewerPipeRun", "cell": Vector2i(offset, CENTER + TUNNEL_HALF), "wall": Vector2i(0, 1)})
		out.append({"type": "sewerPipeRun", "cell": Vector2i(CENTER - TUNNEL_HALF, offset), "wall": Vector2i(-1, 0)})
	return out


## Every wall-mounted piece (valves, lamps, pipe runs, pumps) must have brick
## behind it. Rooms, branches and shaft chambers carved after the dressing was
## planned can open a doorway exactly where a piece wanted its wall (playtest:
## a valve wheel hanging in mid-air in a pump-room doorway): such a piece slides
## along its wall to the nearest walkable cell that is backed by brick, or is
## left out when there is none within reach.
const MOUNT_SLIDE := 3


static func _mount_on_walls(grid: Array, features: Array) -> Array:
	var out := []
	for feature_value in features:
		var feature: Dictionary = feature_value
		var wall: Vector2i = feature.get("wall", Vector2i.ZERO)
		# free-standing pieces stay put, and so do ladders (their cell is the link)
		if wall == Vector2i.ZERO or feature.has("link"):
			out.append(feature)
			continue
		var cell: Vector2i = feature["cell"]
		var along := Vector2i(absi(wall.y), absi(wall.x))
		for k in [0, 1, -1, 2, -2, 3, -3]:
			if absi(k) > MOUNT_SLIDE:
				continue
			var spot: Vector2i = cell + along * k
			if wall_backed(grid, spot, wall):
				var moved := feature.duplicate()
				moved["cell"] = spot
				out.append(moved)
				break
	return out


## True when `cell` is walkable floor and the cell beyond it toward `wall` is brick.
static func wall_backed(grid: Array, cell: Vector2i, wall: Vector2i) -> bool:
	var back := cell + wall
	for c in [cell, back]:
		if c.x < 0 or c.y < 0 or c.x >= CHUNK_SIZE or c.y >= CHUNK_SIZE:
			return false
	return int(grid[cell.y][cell.x]) == DRY and int(grid[back.y][back.x]) == SOLID


## The decks: an authored bridge over the channel at each tunnel crossing and
## grate tiles over the confluence. "yaw" turns the span across the water
## (authored spanning local z, i.e. across an east-west channel).
static func _crossing_features() -> Array:
	var out := []
	for offset in BRIDGE_OFFSETS:
		out.append({"type": "sewerBridge", "cell": Vector2i(offset, CENTER), "yaw": 0.0})
		out.append({"type": "sewerBridge", "cell": Vector2i(CENTER, offset), "yaw": PI / 2.0})
	for k in PLAZA_TILES:
		out.append({"type": "sewerGrateDeck", "cell": Vector2i(CENTER + k, CENTER), "yaw": 0.0})
		if k != 0:
			out.append({"type": "sewerGrateDeck", "cell": Vector2i(CENTER, CENTER + k), "yaw": PI / 2.0})
	return out


## Wall-mounted height and whether a piece blocks movement; everything but the
## pump stands aside of the walkway or in the water.
const FEATURE_MOUNT_Y := {"sewerLamp": 2.35, "sewerValveWheel": 1.15, "sewerPipeRun": 2.55}
const SOLID_FEATURES := {"sewerPump": Vector3(1.3, 1.5, 0.9)}


## Yaw that turns an authored piece's back toward `wall` (PropModelCatalog adds
## the half turn authored models need).
static func wall_yaw(wall: Vector2i) -> float:
	if wall == Vector2i.ZERO:
		return 0.0
	return atan2(float(wall.x), float(wall.y))


func _feature_props(coord: Vector3i, features: Array) -> Array:
	var props := []
	for index in features.size():
		var feature: Dictionary = features[index]
		var type := String(feature["type"])
		var wall: Vector2i = feature.get("wall", Vector2i.ZERO)
		var prop := {"id": "%s:PROP:%d" % [chunk_id(coord), index], "type": type, "cell": feature["cell"],
			"yaw": float(feature.get("yaw", wall_yaw(wall))), "solid": SOLID_FEATURES.has(type), "sewer_feature": true}
		if FEATURE_MOUNT_Y.has(type):
			prop["mount_y"] = FEATURE_MOUNT_Y[type]
			prop["mount_offset"] = Vector2(wall) * .5
		elif type == "sewerPump":
			prop["mount_offset"] = Vector2(wall) * .05
		if SOLID_FEATURES.has(type):
			prop["collider_size"] = SOLID_FEATURES[type]
		if feature.has("link"):
			prop["link"] = feature["link"]
		props.append(prop)
	return props


static func is_walkable(code: int) -> bool:
	return code == DRY or code == BRIDGE


static func is_dry(code: int) -> bool:
	return code == DRY or code == BRIDGE
