extends RefCounted

## Nothing is below the Inferno (level -3 is the lowest storey and the player has no kill plane), so a cell a runner can step into
## that has no ground is a fall with no end. This builds every Inferno chunk of a window through the real StreamedFacilityView3D
## (the level -2 chunk above it too where a ramp comes down: the slope's collider lives there), and in the physics world those
## builds made probes every cell the way a runner meets it: a capsule at the feet (blocked?) and rays down at the centre and four
## quarter points (ground within 0.6 m?). A cell that is not blocked and has no ground is a hole. A hole next to a cell with ground
## that the runner's capsule slides into without touching anything is an open way in.
##
## What it finds: the lower end of an Inferno ramp tunnel. The grid keeps the slope rect solid, so the view builds no floor and no
## collider on the Inferno storey there (StreamedFacilityView3D._build_structure_cell returns early for ramp cells, and
## _close_ramp_sides only draws wall faces). The slab on level -2 is the only collider; under it is a 3 x 12 cell pocket, 0 to 4 m
## high, with no floor. Cave tunnels run along its sides and head, so a runner walks through the drawn wall and falls for good.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- res://tests/validate_inferno_floor.gd
##
## Not in the runner's SUITES list. Register it as "inferno_floor" once the ramp pocket is closed.

const SEEDS := ["STREAM-BENCH", "REFLOOK", "INF-SCAN-A", "INFERNO-CAV-A", "SOAKTEST"]
const RADIUS := 4
## Storeys above the Inferno are scanned too (smaller window, two seeds): their ramp slopes and the falls' jump cell are open by design.
const UPPER_RADIUS := 2
const FLOOR_TOLERANCE := .2
## Ray length below the feet that counts as "ground under the feet" (the floor slab is 0.1 m).
const GROUND_REACH := .6
## A body dropped into a hole must fall less than this in 12 m of travel to count as caught by something.
const FELL := 3.0

var _failures := 0
var _space: PhysicsDirectSpaceState3D
var _shape: Shape3D
var _shape_offset := Vector3.ZERO
var _player_rid: RID


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	for seed_text in SEEDS:
		await _scan_seed(host, seed_text, StreamedRouteGenerator.INFERNO_LEVEL, RADIUS)
	for level in [StreamedRouteGenerator.LOWER_SEWER_LEVEL, StreamedRouteGenerator.SEWER_LEVEL]:
		for seed_text in SEEDS.slice(0, 2):
			await _scan_seed(host, seed_text, level, UPPER_RADIUS)
	await _dormant_check(host, SEEDS[0])
	return _failures


## A parked (dormant) chunk is hidden with process_mode DISABLED, and a StaticBody3D's default disable_mode REMOVE takes it out of
## the physics world. The ramp slab is a StaticBody3D child of the level -2 chunk (the Inferno's way down); the floor is a GridMap,
## which stays. Probes both before and after parking the pair.
func _dormant_check(host: Node, seed_text: String) -> void:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var level := StreamedRouteGenerator.INFERNO_LEVEL
	var gen := StreamedRouteGenerator.new(seed_text)
	var view := StreamedFacilityView3D.new()
	host.add_child(view)
	var player := (load("res://game/night_watch/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	host.add_child(player)
	player.global_position = Vector3(4000, 4000, 4000)
	view.begin(seed_text, player)
	view.set_process(false)
	player.set_physics_process(false)
	_space = host.get_viewport().find_world_3d().direct_space_state
	var found := Vector3i.ZERO
	var ramp := {}
	for cz in range(-RADIUS, RADIUS + 1):
		for cx in range(-RADIUS, RADIUS + 1):
			var data := gen.chunk(Vector3i(cx, level, cz))
			if ramp.is_empty() and not (data.get("ramps", []) as Array).is_empty():
				found = Vector3i(cx, level, cz)
				ramp = (data["ramps"] as Array)[0]
	if ramp.is_empty():
		_expect(false, "dormant check: no ramp chunk found for %s" % seed_text)
		return
	var upper := Vector3i(found.x, level + 1, found.z)
	for coord in [found, upper]:
		if not view._loaded.has(coord):
			view._load_chunk(coord)
	for _i in 3:
		await host.get_tree().physics_frame
	var rect: Rect2i = ramp["ramp"]
	var mid_cell := Vector2(rect.position.x + rect.size.x * .5, rect.position.y + rect.size.y * .5)
	var slope_y := float(upper.y) * StreamedFacilityView3D.LEVEL_HEIGHT + StreamedFacilityView3D._ramp_surface_y(ramp, mid_cell.x)
	var slope_at := Vector3(found.x * size + mid_cell.x, slope_y, found.z * size + mid_cell.y)
	var bottom: Rect2i = ramp["bottom"]
	var floor_at := Vector3(found.x * size + bottom.position.x + 1.5, float(level) * StreamedFacilityView3D.LEVEL_HEIGHT, found.z * size + bottom.position.y + 1.5)
	var before := [_ray_hit(slope_at), _ray_hit(floor_at)]
	view._make_dormant(upper)
	view._make_dormant(found)
	for _i in 3:
		await host.get_tree().physics_frame
	var parked := [_ray_hit(slope_at), _ray_hit(floor_at)]
	print("  inferno_floor dormant %s ramp chunk %s: slab %s -> parked %s, Inferno landing floor %s -> parked %s" % [
		seed_text, found, before[0], parked[0], before[1], parked[1]])
	_expect(before[0] and before[1], "dormant check: the slab (%s) or the landing floor (%s) was not there to begin with" % [before[0], before[1]])
	_expect(parked[0] == before[0], "parking the level -2 chunk takes its ramp slab out of the physics world (a runner on the slope falls)")
	_expect(parked[1] == before[1], "parking the Inferno chunk takes its floor out of the physics world")
	view.clear()
	view.queue_free()
	player.queue_free()
	await host.get_tree().process_frame


## True when a ray down through (x, y + 0.5 .. y - 0.6, z) meets something.
func _ray_hit(at: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * .5, at + Vector3.DOWN * .6, 1)
	return not _space.intersect_ray(ray).is_empty()


func _scan_seed(host: Node, seed_text: String, level: int, radius: int) -> void:
	var t0 := Time.get_ticks_msec()
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var inferno := level == StreamedRouteGenerator.INFERNO_LEVEL
	var gen := StreamedRouteGenerator.new(seed_text)
	var view := StreamedFacilityView3D.new()
	host.add_child(view)
	var player := (load("res://game/night_watch/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	host.add_child(player)
	var start := Vector3i(0, level, 0)
	var spot := InfernoCaverns.landing(gen.chunk(start)) if inferno else Vector2i(size / 2, size / 2)
	player.global_position = Vector3(start.x * size + spot.x + .5, float(level) * StreamedFacilityView3D.LEVEL_HEIGHT + .1, start.z * size + spot.y + .5)
	view.begin(seed_text, player)
	for _i in 600:
		await host.get_tree().physics_frame
		if not view.is_streaming() and not view.is_preloading():
			break
	view.set_process(false)
	player.set_physics_process(false)
	_player_rid = player.get_rid()
	_shape = player.player_collision.shape
	_shape_offset = player.player_collision.global_position - player.global_position
	_space = host.get_viewport().find_world_3d().direct_space_state
	var totals := {"cells": 0, "floor": 0, "solid": 0, "hole": 0, "enter": 0, "walk": 0, "ramps": 0, "ramps_open": 0, "unplanned": 0}
	var ways := {}
	var open_lines: Array[String] = []
	var drops: Array[Vector3] = []
	var chunks := 0
	for cz in range(-radius, radius + 1):
		var batch: Array[Vector3i] = []
		var made: Array[Vector3i] = []
		for cx in range(-radius, radius + 1):
			var coord := Vector3i(cx, level, cz)
			batch.append(coord)
			var data := gen.chunk(coord)
			if not view._loaded.has(coord):
				view._load_chunk(coord)
				made.append(coord)
			if not (data.get("ramps", []) as Array).is_empty():
				var above := Vector3i(cx, level + 1, cz)
				if not view._loaded.has(above):
					view._load_chunk(above)
					made.append(above)
		for _i in 3:
			await host.get_tree().physics_frame
		for coord in batch:
			chunks += 1
			var res := _probe_chunk(view, coord)
			for key in totals:
				totals[key] = int(totals[key]) + int((res["totals"] as Dictionary).get(key, 0))
			for way in res["ways"]:
				ways[way] = int(ways.get(way, 0)) + int(res["ways"][way])
			for line in res["open"]:
				if open_lines.size() < 4:
					open_lines.append(line)
			for hole_at in res["enter_cells"]:
				if drops.size() < 1:
					drops.append(hole_at)
		for coord in made:
			view._unload_chunk(coord)
		await host.get_tree().process_frame
	print("  inferno_floor %s level %d: %d chunks, %d cells: %d ground, %d blocked, %d no ground; %d of them the runner can slide into %s; %d of %d ramps have a way in; %d no-ground cells on the walk grid (%.1f s)" % [
		seed_text, level, chunks, totals["cells"], totals["floor"], totals["solid"], totals["hole"], totals["enter"], ways,
		totals["ramps_open"], totals["ramps"], totals["walk"], (Time.get_ticks_msec() - t0) / 1000.0])
	_expect(int(totals["walk"]) == 0, "%s level %d: %d cells of the walk grid have no ground" % [seed_text, level, totals["walk"]])
	_expect(int(totals["unplanned"]) == 0,
		"%s level %d: %d cells beside a floor cell have no ground and no wall and are not a ramp slope or the plunge: e.g. %s" % [seed_text, level, totals["unplanned"], open_lines])
	if inferno:
		_expect(int(totals["ramps_open"]) == 0,
			"%s: %d of %d Inferno ramps can be walked into from the cave floor (no floor or wall under the slope): e.g. %s" % [seed_text, totals["ramps_open"], totals["ramps"], open_lines.slice(0, 2)])
		for drop in drops:
			var y0: float = drop.y + .05
			player.global_position = Vector3(drop.x, y0, drop.z)
			for _i in 60:
				player.move_and_collide(Vector3(0, -.2, 0))
			_expect(y0 - player.global_position.y < FELL, "%s: a runner in the open ramp pocket at %s falls from y %.2f to %.2f and finds no ground (floor is %.2f)" % [
				seed_text, Vector2(drop.x, drop.z), y0, player.global_position.y, drop.y])
	view.clear()
	view.queue_free()
	player.queue_free()
	await host.get_tree().process_frame


## 0 = ground under the feet, 1 = blocked, 2 = no ground
func _probe_cell(world_x: float, floor_y: float, world_z: float) -> int:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.transform = Transform3D(Basis.IDENTITY, Vector3(world_x, floor_y + .03, world_z) + _shape_offset)
	query.exclude = [_player_rid]
	query.collision_mask = 1
	if not _space.intersect_shape(query, 1).is_empty():
		return 1
	for offset in [Vector2(0, 0), Vector2(-.3, -.3), Vector2(.3, -.3), Vector2(-.3, .3), Vector2(.3, .3)]:
		var ray := PhysicsRayQueryParameters3D.create(Vector3(world_x + offset.x, floor_y + .5, world_z + offset.y),
			Vector3(world_x + offset.x, floor_y - GROUND_REACH, world_z + offset.y), 1, [_player_rid])
		var hit := _space.intersect_ray(ray)
		if hit.is_empty() or float((hit["position"] as Vector3).y) < floor_y - FLOOR_TOLERANCE:
			return 2
	return 0


func _probe_chunk(view: StreamedFacilityView3D, coord: Vector3i) -> Dictionary:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var data: Dictionary = view.generator.chunk(coord)
	var grid: Array = data["grid"]
	var floor_y := float(coord.y) * StreamedFacilityView3D.LEVEL_HEIGHT
	var origin := Vector2(coord.x * size, coord.z * size)
	var inferno := coord.y == StreamedRouteGenerator.INFERNO_LEVEL
	var status := {}
	var ramp_cells: Dictionary = data.get("ramp_cells", {}) if inferno else _ramp_rect_cells(data)
	var jump: Vector2i = StreamedFacilityView3D._jump_cell(data)
	var totals := {"cells": 0, "floor": 0, "solid": 0, "hole": 0, "enter": 0, "walk": 0, "ramps": (data.get("ramps", []) as Array).size(),
		"ramps_open": 0, "unplanned": 0}
	for z in size:
		for x in size:
			var s := _probe_cell(origin.x + x + .5, floor_y, origin.y + z + .5)
			status[Vector2i(x, z)] = s
			totals["cells"] += 1
			totals["floor" if s == 0 else "solid" if s == 1 else "hole"] += 1
	var ways := {}
	var open_lines: Array[String] = []
	var enter_cells: Array[Vector3] = []
	var ramps_hit := {}
	for cell in status:
		if int(status[cell]) != 2:
			continue
		if inferno and int(grid[cell.y][cell.x]) == 0:
			totals["walk"] += 1
		var enter_from := Vector2i(-1, -1)
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cell + step
			if enter_from.x < 0 and status.has(n) and int(status[n]) == 0 and _free_move(origin, floor_y, n, cell):
				enter_from = n     # the capsule slides from that cell with ground into this one without touching anything
		if enter_from.x < 0:
			continue
		totals["enter"] += 1
		var way := "%s via %s" % ["side" if enter_from.x == cell.x else "end", _carve_role(data, enter_from)]
		ways[way] = int(ways.get(way, 0)) + 1
		var is_ramp := ramp_cells.has(cell)
		if is_ramp and inferno:
			# an Inferno ramp cell has neither floor nor wall: the pocket under the slope
			enter_cells.append(Vector3(origin.x + cell.x + .5, floor_y, origin.y + cell.y + .5))
			for ramp_value in data.get("ramps", []):
				if ((ramp_value as Dictionary)["ramp"] as Rect2i).has_point(cell):
					ramps_hit[(ramp_value as Dictionary)["ramp"]] = true
		elif not is_ramp and cell != jump:
			totals["unplanned"] += 1       # above the Inferno a slope's cells and the plunge cell are open on purpose
		else:
			continue
		if open_lines.size() < 4:
			open_lines.append(_describe(data, coord, cell, enter_from))
	totals["ramps_open"] = ramps_hit.size()
	return {"totals": totals, "ways": ways, "open": open_lines, "enter_cells": enter_cells}


## Every cell of the ramp rects of a sewer chunk's data (the slopes there are open by design).
static func _ramp_rect_cells(data: Dictionary) -> Dictionary:
	var cells := {}
	for ramp in data.get("ramps", []):
		var rect: Rect2i = ramp["ramp"]
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				cells[Vector2i(x, z)] = true
	return cells


## The runner's capsule slides from cell `a` to cell `b` (both chunk-local) at floor height without touching anything.
func _free_move(origin: Vector2, floor_y: float, a: Vector2i, b: Vector2i) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.transform = Transform3D(Basis.IDENTITY, Vector3(origin.x + a.x + .5, floor_y + .03, origin.y + a.y + .5) + _shape_offset)
	query.motion = Vector3(b.x - a.x, 0, b.y - a.y)
	query.exclude = [_player_rid]
	query.collision_mask = 1
	var fractions := _space.cast_motion(query)
	return fractions.size() == 2 and float(fractions[0]) >= .999


## Which Inferno carve owns a floor cell: a cavern, a cavern's hall, a crevice, or neither (a cave tunnel, seam or stray).
static func _carve_role(data: Dictionary, cell: Vector2i) -> String:
	for cavern in data.get("inferno_caverns", []):
		if (cavern["cells"] as Array).has(cell):
			return "cavern"
		for hall in cavern["halls"]:
			if (hall as Rect2i).has_point(cell):
				return "hall"
		for slit in cavern["crevices"]:
			if (slit["cells"] as Array).has(cell):
				return "crevice"
	return "tunnel/seam/other"


## Where a hole sits against its ramp: how far along the slope (0 = foot, 1 = head) and the slab's height above the floor there.
static func _describe(data: Dictionary, coord: Vector3i, cell: Vector2i, from: Vector2i) -> String:
	for ramp_value in data.get("ramps", []):
		var ramp: Dictionary = ramp_value
		var rect: Rect2i = ramp["ramp"]
		if not rect.has_point(cell):
			continue
		var along := clampf((cell.x + .5 - float(ramp["bottom_x"])) / (float(ramp["top_x"]) - float(ramp["bottom_x"])), 0.0, 1.0)
		return "%s cell %s in ramp %s (%.0f%% up the slope, slab %.1f m over the floor), entered from %s (grid=%d, %s)" % [
			coord, cell, rect, along * 100.0, 4.0 + StreamedFacilityView3D._ramp_surface_y(ramp, cell.x + .5), from,
			int((data["grid"] as Array)[from.y][from.x]), _carve_role(data, from)]
	return "%s cell %s (no ramp), entered from %s (%s)" % [coord, cell, from, _carve_role(data, from)]
