extends RefCounted

## The sewer layer under the Last Route maze (SewerRouteGenerator, level -1):
## deterministic per seed; every seam meets; every dry cell sits in a 3x3 dry
## block (three-wide walkways and branches) and the tunnel is nine walkable
## cells across; every link's lid is an open, prop-free maze hallway cell;
## walkers reach every link and every seam on walkways, bridges and the
## junction's grate plaza (the deep channels are never walkable); and a walker
## can go from the maze spawn down one link, through the sewer and up another.
##
##   godot --headless --path . res://scenes/validate.tscn -- sewers

const WINDOWS := [
	{"seed": "MAP-CHECK", "from": Vector2i(-3, -3), "to": Vector2i(3, 3)},
	{"seed": "SEWER-A", "from": Vector2i(0, 0), "to": Vector2i(5, 5)},
]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var total_links := 0
	for window in WINDOWS:
		total_links += _check_window(window)
	_check_opaque_window(host)
	_check_traffic()
	_check_hunter_paths()
	await _check_deep_levels(host)
	await _check_falls(host)
	await _check_stairwells(host)
	await _check_bridge_decks(host)
	await _check_streaming(host)
	_expect(total_links >= 6, "sewer windows hold %d links (want at least 6)" % total_links)
	_expect(valves_checked >= 10, "only %d valve wheels checked for a wall behind them" % valves_checked)
	if _failures == 0:
		print("  ok    sewers: %d links, all reachable both ways" % total_links)
	return _failures


var valves_checked := 0


## Rooms reserve their cells (KT: "sewer rooms are broken", a railed basin
## inside a utility room read as the channel running through it): no channel,
## falls, ramp or deck cell and no bridge inside any room footprint on -1 or -2,
## so no railing (railings stand only on walkway-water edges) runs inside one.
func _check_rooms_dry(seed_text: String, coord: Vector3i, data: Dictionary) -> void:
	var grid: Array = data["sewer_grid"]
	for room_value in data.get("rooms", []):
		var rect: Rect2i = (room_value as Dictionary).get("rect", Rect2i())
		var wet := 0
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if int(grid[z][x]) != SewerRouteGenerator.DRY:
					wet += 1
		var decks := 0
		for feature in data.get("features", []):
			if String(feature["type"]) in ["sewerBridge", "sewerGrateDeck"] and rect.grow(1).has_point(feature["cell"]):
				decks += 1
		_expect(wet == 0 and decks == 0, "%s %s: room %s at %s holds %d channel/falls/deck cells and %d bridges" % [
			seed_text, coord, (room_value as Dictionary).get("room_type", "?"), rect, wet, decks])


func _check_window(window: Dictionary) -> int:
	var seed_text: String = window["seed"]
	var surface := StreamedRouteGenerator.new(seed_text)
	var sewer := SewerRouteGenerator.new(surface)
	var again := SewerRouteGenerator.new(StreamedRouteGenerator.new(seed_text))
	var size := SewerRouteGenerator.CHUNK_SIZE
	var sewer_cells := {}     # global cell -> code
	var maze_open := {}       # global cell -> true
	var links := []
	for cz in range(window["from"].y, window["to"].y + 1):
		for cx in range(window["from"].x, window["to"].x + 1):
			var coord := Vector3i(cx, SewerRouteGenerator.LEVEL, cz)
			var data: Dictionary = sewer.chunk(coord)
			var twin: Dictionary = again.chunk(coord)
			_expect(data["sewer_grid"] == twin["sewer_grid"] and data["links"] == twin["links"],
				"%s sewer chunk %s is not deterministic" % [seed_text, coord])
			var origin := Vector2i(cx * size, cz * size)
			var grid: Array = data["sewer_grid"]
			for z in size:
				for x in size:
					if SewerRouteGenerator.is_walkable(int(grid[z][x])):
						sewer_cells[origin + Vector2i(x, z)] = int(grid[z][x])
			var surface_data: Dictionary = surface.chunk(Vector3i(cx, 0, cz))
			var sgrid: Array = surface_data["grid"]
			for z in size:
				for x in size:
					if int(sgrid[z][x]) == 0:
						maze_open[origin + Vector2i(x, z)] = true
			for feature in data["features"]:
				var fc: Vector2i = feature["cell"]
				# everything stands on floor or deck
				var standing: bool = SewerRouteGenerator.is_walkable(int(grid[fc.y][fc.x]))
				_expect(standing, "%s %s feature %s sits in solid brick" % [seed_text, coord, feature["type"]])
				# nothing hangs in the air: a wall-mounted piece (valve wheel, lamp, pipe run,
				# pump, ladder) stands on floor with brick directly behind it
				var wall: Vector2i = feature.get("wall", Vector2i.ZERO)
				if wall != Vector2i.ZERO:
					_expect(SewerRouteGenerator.wall_backed(grid, fc, wall),
						"%s %s: %s at %s floats (no brick behind it toward %s)" % [seed_text, coord, feature["type"], fc, wall])
					if feature["type"] == "sewerValveWheel":
						valves_checked += 1
			_check_channels(seed_text, coord, data)
			for level in [SewerRouteGenerator.LEVEL, SewerRouteGenerator.LOWER_LEVEL]:
				_check_rooms_dry(seed_text, Vector3i(cx, level, cz), sewer.chunk(Vector3i(cx, level, cz)))
			var ladders := {}
			for feature in data["features"]:
				if feature["type"] == "sewerLadder":
					ladders[feature["link"]] = feature["cell"]
			# KT: "archway and ladder getting stuck together": a ladder top keeps a cell clear of hall pilasters (and the
			# arches they spring) and of every doorway, archway and threshold on the maze
			var thresholds := {}
			for prop in surface_data.get("region_props", []):
				for cell in prop.get("doorway_cells", []):
					thresholds[cell] = true
			for link in data["links"]:
				var top: Vector2i = link["from_cell"]
				var clear := not RefDecor.near_pilaster(top, link.get("wall", Vector2i.ZERO))
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						if thresholds.has(top + Vector2i(dx, dz)):
							clear = false
				_expect(clear, "%s ladder %s stands within a cell of a pilaster, arch or doorway" % [seed_text, link["id"]])
			for link in data["links"]:
				_expect(link["kind"] == "ladder" and ["manhole", "grate"].has(link.get("cover", "")),
					"%s link %s is not a covered ladder" % [seed_text, link["id"]])
				_expect(ladders.get(link["id"], Vector2i(-1, -1)) == link["to_cell"],
					"%s link %s has no ladder at its foot" % [seed_text, link["id"]])
				var up: Vector2i = link["from_cell"]
				var down: Vector2i = link["to_cell"]
				var behind: Vector2i = down + Vector2i(link.get("wall", Vector2i.ZERO))
				_expect(Vector2i(link.get("wall", Vector2i.ZERO)) != Vector2i.ZERO \
					and int(grid[behind.y][behind.x]) == SewerRouteGenerator.SOLID,
					"%s link %s ladder has no brick behind its rungs" % [seed_text, link["id"]])
				_expect(int(sgrid[up.y][up.x]) == 0, "%s link %s lid is not open maze floor" % [seed_text, link["id"]])
				# flush against a hallway wall up top too, never free-standing mid-hall
				var maze_wall: Vector2i = up + Vector2i(link.get("wall", Vector2i.ZERO))
				var front: Vector2i = up - Vector2i(link.get("wall", Vector2i.ZERO))
				_expect(int(sgrid[maze_wall.y][maze_wall.x]) != 0 and int(sgrid[front.y][front.x]) == 0,
					"%s link %s ladder is not against a maze hallway wall" % [seed_text, link["id"]])
				_expect(SewerRouteGenerator.is_dry(int(grid[down.y][down.x])), "%s link %s ladder foot is not dry" % [seed_text, link["id"]])
				for prop in surface_data["region_props"] + surface_data["fixtures"] + surface_data["pickups"]:
					_expect(Vector2i(prop.get("cell", Vector2i(-9, -9))) != up,
						"%s link %s lid sits under %s" % [seed_text, link["id"], prop.get("type", prop.get("kind", "?"))])
				links.append({"up": origin + up, "down": origin + down, "id": link["id"]})
	_check_widths(seed_text, sewer_cells)
	_check_dry_reach(seed_text, sewer_cells, links, window, size)
	_check_round_trip(seed_text, surface, sewer_cells, maze_open, links)
	return links.size()


func _check_widths(seed_text: String, cells: Dictionary) -> void:
	var bad := 0
	var sample := Vector2i.ZERO
	for cell in cells:
		if not SewerRouteGenerator.is_dry(int(cells[cell])):
			continue
		var ok := false
		for oz in range(-2, 1):
			for ox in range(-2, 1):
				var full := true
				for dz in 3:
					for dx in 3:
						var c := Vector2i(cell) + Vector2i(ox + dx, oz + dz)
						if not cells.has(c) or not SewerRouteGenerator.is_dry(int(cells[c])):
							full = false
				if full:
					ok = true
		if not ok:
			bad += 1
			sample = cell
	_expect(bad == 0, "%s: %d dry sewer cells narrower than three (e.g. %s)" % [seed_text, bad, sample])


static func _flood(cells: Dictionary, start: Vector2i, dry_only: bool) -> Dictionary:
	var seen := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if seen.has(next) or not cells.has(next):
				continue
			if dry_only and not SewerRouteGenerator.is_dry(int(cells[next])):
				continue
			seen[next] = true
			queue.append(next)
	return seen


func _check_dry_reach(seed_text: String, cells: Dictionary, links: Array, window: Dictionary, size: int) -> void:
	var start := Vector2i(window["from"].x * size + SewerRouteGenerator.CENTER - SewerRouteGenerator.TUNNEL_HALF, window["from"].y * size + SewerRouteGenerator.CENTER - SewerRouteGenerator.TUNNEL_HALF)
	var reach := _flood(cells, start, true)
	for link in links:
		_expect(reach.has(link["down"]), "%s: link %s not reachable on dry walkways" % [seed_text, link["id"]])
	var dry_total := 0
	for cell in cells:
		if SewerRouteGenerator.is_dry(int(cells[cell])):
			dry_total += 1
	_expect(reach.size() == dry_total, "%s: %d of %d dry sewer cells cut off from the walkway network" % [
		seed_text, dry_total - reach.size(), dry_total])


## Maze spawn -> some link down -> sewer -> a different link up -> maze: the
## combined two-level graph a hunter's path search walks.
func _check_round_trip(seed_text: String, surface: StreamedRouteGenerator, sewer_cells: Dictionary,
		maze_open: Dictionary, links: Array) -> void:
	if links.size() < 2:
		_expect(false, "%s: fewer than two links in the window" % seed_text)
		return
	var maze_reach := _flood(maze_open, Vector2i(links[0]["up"]), false)
	var sewer_reach := _flood(sewer_cells, Vector2i(links[0]["down"]), false)
	var ups := 0
	for link in links:
		_expect(maze_reach.has(link["up"]), "%s: maze can't reach lid %s" % [seed_text, link["id"]])
		if sewer_reach.has(link["down"]):
			ups += 1
	_expect(ups == links.size(), "%s: only %d/%d ladders reachable from the first one below" % [seed_text, ups, links.size()])


## The streamed view loads the sewer 3x3 around a runner below the maze plus the
## maze chunk above it, flips back to the maze when the runner climbs out, keeps
## every chunk build inside the frame budget, and leaves each ladder shaft open
## (no maze floor drawn, no sewer ceiling) while the maze floor keeps its collider.
func _check_streaming(host: Node) -> void:
	var view := StreamedFacilityView3D.new()
	host.add_child(view)
	var player := (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	host.add_child(player)
	var level_y := float(SewerRouteGenerator.LEVEL) * StreamedFacilityView3D.LEVEL_HEIGHT
	var under := Vector3(SewerRouteGenerator.CENTER - SewerRouteGenerator.TUNNEL_HALF + .5, level_y + .04,
		SewerRouteGenerator.CENTER + .5)
	player.global_position = under
	var started := Time.get_ticks_usec()
	view.begin("SEWER-STREAM", player)
	var initial_ms := float(Time.get_ticks_usec() - started) / 1000.0
	_expect(view.current_level() == SewerRouteGenerator.LEVEL, "a runner in the sewer is not on level -1")
	var sewer_loaded := 0
	for coord in view._loaded.keys():
		if (coord as Vector3i).y == SewerRouteGenerator.LEVEL:
			sewer_loaded += 1
	_expect(sewer_loaded == 9, "the sewer window holds %d chunks, not the 3x3 around the runner" % sewer_loaded)
	_expect(view._loaded.has(Vector3i(0, 0, 0)), "the maze chunk above the runner is not loaded")
	var root: Node3D = view._loaded.get(Vector3i(0, SewerRouteGenerator.LEVEL, 0))
	var structure := root.get_node_or_null("Structure") as GridMap if root != null else null
	_expect(structure != null and structure.get_cell_item(Vector3i(floori(under.x), 0, floori(under.z))) != GridMap.INVALID_CELL_ITEM,
		"no floor collider under the runner in the sewer")
	_expect(root != null and root.get_node_or_null("SewerWater") != null, "the sewer chunk has no flowing water")
	_check_colliders_below_maze(view)
	_check_live_channel(view, Vector3i(0, SewerRouteGenerator.LEVEL, 0))
	_check_lamps_over_floor(view)
	_check_ceiling_fixtures(view)
	# Walk east one chunk along the tunnel: the window streams incrementally.
	player.global_position = under + Vector3(SewerRouteGenerator.CHUNK_SIZE, 0, 0)
	var worst_frame_ms := 0.0
	for _frame in 400:
		var t := Time.get_ticks_usec()
		view._process(1.0 / 60.0)
		worst_frame_ms = maxf(worst_frame_ms, float(Time.get_ticks_usec() - t) / 1000.0)
		await host.get_tree().process_frame
		if view._pending_loads.is_empty() and view._active_build.is_empty() and view._pending_unloads.is_empty():
			break
	_expect(view._loaded.has(Vector3i(2, SewerRouteGenerator.LEVEL, 0)), "walking east did not stream the next sewer chunk")
	_expect(worst_frame_ms < 40.0, "a streaming frame in the sewer took %.1f ms (budget 40)" % worst_frame_ms)
	# Climb out at the origin chunk's ladder: back on the maze, the sewer chunk
	# below that ladder stays loaded and the shaft is open in both chunks.
	var links: Array = view.generator.sewer().links_for(Vector3i.ZERO)
	_expect(not links.is_empty(), "the origin chunk has no ladder")
	if not links.is_empty():
		var lid: Vector2i = links[0]["from_cell"]
		player.global_position = Vector3(lid.x + .5, .04, lid.y + .5)
		view.refresh_at_tracked_player()
		_expect(view.current_level() == 0, "a runner on the maze floor is not on level 0")
		_expect(view._loaded.has(Vector3i(0, SewerRouteGenerator.LEVEL, 0)), "the sewer chunk under a ladder unloaded")
		var maze_root: Node3D = view._loaded.get(Vector3i.ZERO)
		var maze_grid := maze_root.get_node_or_null("Structure") as GridMap if maze_root != null else null
		_expect(maze_grid != null and maze_grid.get_cell_item(Vector3i(lid.x, 0, lid.y)) != GridMap.INVALID_CELL_ITEM,
			"the maze floor over a ladder lost its collider")
		# The runner climbs that ladder under their own control: hold back to climb
		# down to the sewer, hold forward to climb up, let go to hang still mid-way;
		# each end dismounts smoothly onto the floor in front of the ladder.
		var rise := StreamedFacilityView3D.LEVEL_HEIGHT
		var wall: Vector2i = links[0].get("wall", Vector2i.ZERO)
		var sewer_y := float(SewerRouteGenerator.LEVEL) * rise + .04
		var foot := Vector3(lid.x + .5 + wall.x * .12, sewer_y, lid.y + .5 + wall.y * .12)
		var front := Vector3(lid.x + .5 - wall.x * .9, 0.0, lid.y + .5 - wall.y * .9)
		var top_exit := front + Vector3(0, .04, 0)
		var bottom_exit := front + Vector3(0, sewer_y, 0)
		# down: mount at the top, hold "move_down"
		player.begin_ladder_climb(foot, rise, rise, 0.0, top_exit, bottom_exit, 0, SewerRouteGenerator.LEVEL)
		_expect(player.is_climbing() and player.collision_layer == 0, "the runner did not get onto the ladder")
		var midway := await _hold_climb(host, player, "move_down", 300)
		view.refresh_at_tracked_player()
		_expect(not player.is_climbing() and player.global_position.distance_to(bottom_exit) < .05,
			"climbing down did not step off at the bottom (at %s)" % player.global_position)
		_expect(midway > sewer_y + .5 and midway < -.5, "the climb down jumped instead of moving along the rungs")
		_expect(view.current_level() == SewerRouteGenerator.LEVEL, "after climbing down the view is not in the sewer")
		_expect(player.collision_layer == 1, "the runner kept collision off after the climb")
		# up, with a stop part-way: hold "move_up" for a second, let go, hang
		player.begin_ladder_climb(foot, rise, 0.0, 0.0, top_exit, bottom_exit, 0, SewerRouteGenerator.LEVEL)
		Input.action_press("move_up")
		for _frame in 60:
			await host.get_tree().physics_frame
		Input.action_release("move_up")
		await host.get_tree().physics_frame
		var hang := player.ladder_climb_progress()
		var hang_y := player.global_position.y
		for _frame in 45:
			await host.get_tree().physics_frame
		_expect(player.is_climbing() and hang > .15 and hang < .85,
			"letting go part-way did not leave the runner hanging on the ladder (progress %.2f)" % hang)
		_expect(absf(player.global_position.y - hang_y) < .01 and player.noise == 0.0,
			"a runner hanging still on the ladder drifted or kept making noise")
		await _hold_climb(host, player, "move_up", 300)
		view.refresh_at_tracked_player()
		_expect(not player.is_climbing() and player.global_position.distance_to(top_exit) < .05,
			"climbing up did not step off at the top (at %s)" % player.global_position)
		_expect(view.current_level() == 0, "after climbing up the view is not on the maze")
	print("  ok    sewer streaming: first window %.0f ms, worst streaming frame %.1f ms" % [initial_ms, worst_frame_ms])
	view.clear()
	view.queue_free()
	player.queue_free()


## One climber per ladder: a second one waits; a finished climb frees it and
## lands on the other level at the ladder cell.
func _check_traffic() -> void:
	var generator := StreamedRouteGenerator.new("SEWER-TRAFFIC")
	var link: Dictionary = generator.sewer().links_for(Vector3i.ZERO)[0]
	var traffic := LadderTraffic.new()
	_expect(traffic.begin("hunter:a", link, 0, 1.0), "a free ladder refused its first climber")
	_expect(not traffic.begin("hunter:b", link, 0, 1.0), "two climbers got on one ladder")
	var mid := traffic.advance("hunter:a", .5)
	_expect(absf(float(mid["height"]) - LadderTraffic.RISE * .5) < .01, "a climb down is not halfway down at half time")
	var done := traffic.advance("hunter:a", .6)
	_expect(bool(done["done"]) and int(done["to_level"]) == SewerRouteGenerator.LEVEL, "the climb did not land in the sewer")
	_expect(traffic.begin("hunter:b", link, 0, 1.0), "the ladder stayed taken after the first climber got off")
	_expect(LadderTraffic.nearest_ladder(generator, 0, LadderTraffic.ladder_point(link, 0))["id"] == link["id"],
		"nearest_ladder does not find the ladder a hunter stands on")
	_expect(LadderTraffic.climb_seconds_for_speed(1.0) < LadderTraffic.climb_seconds_for_speed(0.8),
		"faster hunters do not climb faster")


## Hunter A* on the sewer level reaches between ladders through the tunnels,
## and on the maze level reaches each ladder lid: the two-level route a hunter
## follows down and back up.
func _check_hunter_paths() -> void:
	var generator := StreamedRouteGenerator.new("SEWER-PATHS")
	# a 3 x 3 with at least three ladders: stairwells, ramps and falls take
	# quadrants a ladder could use, so the window slides east until it has them
	var coords := []
	for cx in 6:
		coords = []
		var count := 0
		for z in range(-1, 2):
			for x in range(cx - 1, cx + 2):
				coords.append(Vector3i(x, SewerRouteGenerator.LEVEL, z))
				count += generator.sewer().links_for(Vector3i(x, SewerRouteGenerator.LEVEL, z)).size()
		if count >= 3:
			break
	var below := StreamedHunterNavigation.new(generator, SewerRouteGenerator.LEVEL)
	below.refresh(SewerRouteGenerator.LEVEL, coords)
	var maze_coords := []
	for c in coords:
		maze_coords.append(Vector3i((c as Vector3i).x, 0, (c as Vector3i).z))
	var above := StreamedHunterNavigation.new(generator, 0)
	above.refresh(0, maze_coords)
	var feet := []
	for c in coords:
		for link in generator.sewer().links_for(c):
			feet.append(link)
	_expect(feet.size() >= 3, "only %d ladders around the origin to path between" % feet.size())
	var routed := 0
	var lids := 0
	var missed := []
	var missed_lids := []
	for i in range(1, feet.size()):
		var a := LadderTraffic.ladder_point(feet[0], SewerRouteGenerator.LEVEL)
		var b := LadderTraffic.ladder_point(feet[i], SewerRouteGenerator.LEVEL)
		var route: Array = below.find_path(Vector2i(floori(a.x), floori(a.y)), Vector2i(floori(b.x), floori(b.y)))
		if not route.is_empty():
			routed += 1
		else:
			missed.append(feet[i]["id"])
		for step in route:
			var cell: Vector2i = step
			var size := StreamedRouteGenerator.CHUNK_SIZE
			var code := int(generator.sewer().chunk(Vector3i(floori(float(cell.x) / size), SewerRouteGenerator.LEVEL,
				floori(float(cell.y) / size)))["sewer_grid"][posmod(cell.y, size)][posmod(cell.x, size)])
			_expect(code != SewerRouteGenerator.WATER, "a hunter route wades through the channel at %s" % cell)
	for i in feet.size():
		var lid := LadderTraffic.ladder_point(feet[i], 0)
		# from another lid: the origin chunk's centre is a safe room hunters do not enter
		var first := LadderTraffic.ladder_point(feet[(i + 1) % feet.size()], 0)
		var start := Vector2i(floori(first.x), floori(first.y))
		if not above.find_path(start, Vector2i(floori(lid.x), floori(lid.y))).is_empty():
			lids += 1
		else:
			missed_lids.append(feet[i]["id"])
	_expect(routed == feet.size() - 1, "hunter A* reached %d of %d ladders through the sewer (missed %s from %s)" % [
		routed, feet.size() - 1, missed, feet[0]["id"]])
	_expect(lids == feet.size(), "hunter A* reached %d of %d ladder lids on the maze (missed %s)" % [lids, feet.size(), missed_lids])
	print("  ok    sewer hunter paths: %d ladders, all reachable above and below" % feet.size())


## No level -1 collider may rise into level 0: every GridMap cell shape and
## every prop body under a sewer chunk tops out at or below the underside of the
## maze's floor slab (playtest GOLF: full-height wall blocks a storey down stood
## 3.5 m into open maze halls). The ladder opening needs no exception: the maze
## keeps its own floor collider over it and the sewer adds nothing there.
func _check_colliders_below_maze(view: StreamedFacilityView3D) -> void:
	# every level below the maze: its colliders stop under the floor slab of the
	# level above it (sewers, the collector, the Inferno; ramps top out at their
	# upper landing's floor)
	var worst := -INF
	var where := ""
	var checked := 0
	for coord_value in view._loaded.keys():
		var coord: Vector3i = coord_value
		if coord.y >= 0:
			continue
		var limit := float(coord.y + 1) * StreamedFacilityView3D.LEVEL_HEIGHT - StreamedFacilityView3D.SLAB + .001
		var root: Node3D = view._loaded[coord]
		var grid := root.get_node_or_null("Structure") as GridMap
		if grid != null:
			for cell_value in grid.get_used_cells():
				var cell: Vector3i = cell_value
				var shapes: Array = grid.mesh_library.get_item_shapes(grid.get_cell_item(cell))
				for i in range(0, shapes.size(), 2):
					var over := _shape_top(shapes[i], grid.to_global(grid.map_to_local(cell)), shapes[i + 1]) - limit
					checked += 1
					if over > worst:
						worst = over
						where = "%s Structure cell %s" % [coord, cell]
		for node in root.find_children("*", "CollisionShape3D", true, false):
			var shape_node := node as CollisionShape3D
			if shape_node.shape == null or shape_node.get_parent() is GridMap:
				continue
			var aabb := shape_node.global_transform * shape_node.shape.get_debug_mesh().get_aabb()
			checked += 1
			if aabb.end.y - limit > worst:
				worst = aabb.end.y - limit
				where = "%s %s" % [coord, root.get_path_to(shape_node)]
	_expect(checked > 0, "no colliders below the maze found to check")
	_expect(worst <= 0.0, "a collider rises into the level above: %s is %.2f m over its storey" % [where, worst])


static func _shape_top(shape: Shape3D, cell_origin: Vector3, local: Transform3D) -> float:
	var aabb := shape.get_debug_mesh().get_aabb()
	return (Transform3D(Basis.IDENTITY, cell_origin) * local * aabb).end.y


## Deep channels with real crossings, per chunk: the water lies well below the
## walkways over a bed a metre down; along both arms of the cross no stretch of
## open water runs longer than MAX_OPEN_WATER cells between decks; every 3 x 3
## deck carries its authored bridge.
## Crossings come about every 24 m: the longest open stretch is the 21 cells
## through the junction's open confluence between an arm's two bridges.
const MAX_OPEN_WATER := 21


func _check_channels(seed_text: String, coord: Vector3i, data: Dictionary) -> void:
	_expect(SewerRouteGenerator.WATER_SURFACE <= -.2 and SewerRouteGenerator.CHANNEL_DEPTH >= .8,
		"the sewer water is not deep (surface %.2f, bed %.2f)" % [SewerRouteGenerator.WATER_SURFACE,
			-SewerRouteGenerator.CHANNEL_DEPTH])
	var grid: Array = data["sewer_grid"]
	var c := SewerRouteGenerator.CENTER
	for arm in 2:
		var run := 0
		var longest := 0
		for i in SewerRouteGenerator.CHUNK_SIZE:
			var code := int(grid[c][i]) if arm == 0 else int(grid[i][c])
			run = run + 1 if code == SewerRouteGenerator.WATER else 0
			longest = maxi(longest, run)
		_expect(longest <= MAX_OPEN_WATER, "%s %s: %d cells of open channel without a crossing" % [seed_text, coord, longest])
	var decks := {}
	for feature in data["features"]:
		if feature["type"] in ["sewerBridge", "sewerGrateDeck"]:
			decks[feature["cell"]] = feature["type"]
	var bridge_cells := 0
	for z in grid.size():
		for x in (grid[z] as Array).size():
			if int(grid[z][x]) != SewerRouteGenerator.BRIDGE:
				continue
			bridge_cells += 1
			var covered := false
			for centre in decks:
				if absi(x - (centre as Vector2i).x) <= 1 and absi(z - (centre as Vector2i).y) <= 1:
					covered = true
			_expect(covered, "%s %s: deck cell %s has no bridge or grate prop" % [seed_text, coord, Vector2i(x, z)])
	_expect(bridge_cells == decks.size() * 9, "%s %s: %d deck cells for %d deck props" % [
		seed_text, coord, bridge_cells, decks.size()])


## The live chunk: every open-water cell has the channel collider, which stands
## above the railings so nobody steps in; every deck cell is walkable floor; the
## water mesh runs under the decks and the railings are there.
func _check_live_channel(view: StreamedFacilityView3D, coord: Vector3i) -> void:
	var root: Node3D = view._loaded.get(coord)
	if root == null:
		_expect(false, "sewer chunk %s not loaded for the channel check" % coord)
		return
	var grid := root.get_node_or_null("Structure") as GridMap
	var sewer_grid: Array = view.generator.chunk(coord)["sewer_grid"]
	var bad := 0
	for z in sewer_grid.size():
		for x in (sewer_grid[z] as Array).size():
			var item := grid.get_cell_item(Vector3i(x, 0, z))
			match int(sewer_grid[z][x]):
				SewerRouteGenerator.WATER:
					if item != view._col_channel_item:
						bad += 1
				SewerRouteGenerator.BRIDGE:
					if item != view._col_floor_item:
						bad += 1
	_expect(bad == 0, "%d channel or deck cells have the wrong collider" % bad)
	var shapes: Array = grid.mesh_library.get_item_shapes(view._col_channel_item)
	var top := _shape_top(shapes[0], Vector3.ZERO, shapes[1])
	_expect(top >= StreamedFacilityView3D.RAIL_HEIGHT, "the channel collider (top %.2f) is lower than the railings" % top)
	_expect(root.get_node_or_null("ChannelRails") != null and root.get_node_or_null("ChannelPosts") != null,
		"the sewer chunk has no channel railings")
	if bad == 0:
		print("  ok    sewer channels: deep water behind railings, decks walkable, colliders right")


## A bridge's visible deck is where a runner stands on it (KT: "the player still goes through the bridge and
## not up and over"; the deck was seated on its girders' bearings, 0.6 m above the floor collider): over the
## deck the topmost visible surface and the collider agree within 3 cm, and a runner at the game's player
## scale walks from walkway to walkway across it without stalling, dropping or bouncing.
func _check_bridge_decks(host: Node) -> void:
	var view := StreamedFacilityView3D.new()
	host.add_child(view)
	var player := (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	host.add_child(player)
	var level_y := float(SewerRouteGenerator.LEVEL) * StreamedFacilityView3D.LEVEL_HEIGHT
	var c := SewerRouteGenerator.CENTER
	var half := SewerRouteGenerator.TUNNEL_HALF
	var bridge_x := float(SewerRouteGenerator.BRIDGE_OFFSETS[0]) + .5
	var from := Vector3(bridge_x, level_y + .05, float(c - half) + 1.5)       # the north walkway's middle row
	var to := Vector3(bridge_x, level_y, float(c + half) - .5)                # the south walkway's middle row
	player.global_position = from
	view.begin("SEWER-BRIDGE", player)
	for _frame in 20:
		await host.get_tree().physics_frame
	var space := player.get_world_3d().direct_space_state
	var bridges := 0
	var worst := 0.0
	var where := ""
	for root_value in view._loaded.values():
		var root: Node3D = root_value
		for node in root.find_children("*", "Node3D", true, false):
			if String((node as Node3D).get_meta("streamed_prop_type", "")) != "sewerBridge":
				continue
			bridges += 1
			var faces := PackedVector3Array()
			for mesh_node in (node as Node3D).find_children("*", "MeshInstance3D", true, false):
				var instance := mesh_node as MeshInstance3D
				if instance.mesh == null:
					continue
				for point in instance.mesh.get_faces():
					faces.append(instance.global_transform * point)
			# the deck's walking surface: its highest vertex inside the kick plates (slats are 3.5 cm wide on a
			# 15 cm pitch, so rays at a coarse grid fall between them; their vertices sit at the slat ends, 1.40 m
			# out, and the kick plates start at 1.44 m)
			var centre := (node as Node3D).global_position
			var deck_top := -INF
			for point in faces:
				if absf(point.x - centre.x) < 1.43 and absf(point.z - centre.z) < 1.43:
					deck_top = maxf(deck_top, point.y)
			for offset in [Vector3.ZERO, Vector3(.9, 0, .9), Vector3(-.9, 0, .9), Vector3(.9, 0, -.9), Vector3(-.9, 0, -.9)]:
				var sample: Vector3 = centre + offset
				var query := PhysicsRayQueryParameters3D.create(sample + Vector3.UP * 3.0, sample + Vector3.DOWN * 3.0)
				query.exclude = [player.get_rid()]
				var hit := space.intersect_ray(query)
				var floor_y := float((hit["position"] as Vector3).y) if not hit.is_empty() else -INF
				var gap := absf(floor_y - deck_top)
				if gap > worst:
					worst = gap
					where = "deck %.2f, collider %.2f at %s" % [deck_top, floor_y, sample]
	_expect(bridges >= 4, "only %d sewer bridges loaded around the walk" % bridges)
	_expect(worst <= .03, "a bridge's visible deck and its walkable collider are %.2f m apart (%s)" % [worst, where])
	# walk across, the movement keys held, facing the far walkway
	var lowest := INF
	var highest_y := -INF
	var worst_pop := 0.0
	var last_y := player.global_position.y
	var frames := 0
	Input.action_press("move_up")
	while Vector2(player.global_position.x - to.x, player.global_position.z - to.z).length() > .35 and frames < 400:
		var heading := Vector2(to.x - player.global_position.x, to.z - player.global_position.z)
		player.rotation.y = atan2(-heading.x, -heading.y)
		await host.get_tree().physics_frame
		view._process(1.0 / 60.0)
		lowest = minf(lowest, player.global_position.y)
		highest_y = maxf(highest_y, player.global_position.y)
		worst_pop = maxf(worst_pop, absf(player.global_position.y - last_y))
		last_y = player.global_position.y
		frames += 1
	Input.action_release("move_up")
	_expect(frames < 400, "a runner got stuck crossing a sewer bridge (at %s)" % player.global_position)
	_expect(lowest > level_y - .05 and highest_y < level_y + .1,
		"a runner crossing a sewer bridge left the deck height (y %.2f..%.2f, floor %.2f)" % [lowest, highest_y, level_y])
	_expect(worst_pop < .06, "a runner crossing a sewer bridge popped %.2f m in one frame" % worst_pop)
	if bridges >= 4 and worst <= .03 and frames < 400:
		print("  ok    sewer bridges: %d decks flush with their colliders (worst %.3f m), crossed in %d frames" % [
			bridges, worst, frames])
	view.clear()
	view.queue_free()
	player.queue_free()


## Nothing hangs in the air (KT: "floating lights here in the sewer room"): every ceiling lamp below the maze is
## mounted flush (within 5 cm) on a ceiling face drawn in its own cell, at the sewer's storey height.
func _check_ceiling_fixtures(view: StreamedFacilityView3D) -> void:
	var checked := 0
	var bad := []
	for coord_value in view._loaded.keys():
		var coord: Vector3i = coord_value
		if coord.y >= 0:
			continue
		var root: Node3D = view._loaded[coord]
		var ceiling := {}
		var surface := root.get_node_or_null("Surface") as MeshInstance3D
		if surface == null or surface.mesh == null:
			continue
		var faces := surface.mesh.get_faces()
		for f in range(0, faces.size(), 3):
			var a: Vector3 = faces[f]
			if a.y > 2.0 and absf(faces[f + 1].y - a.y) < .001 and absf(faces[f + 2].y - a.y) < .001:
				var mid: Vector3 = (a + faces[f + 1] + faces[f + 2]) / 3.0
				ceiling[Vector2i(floori(mid.x), floori(mid.z))] = a.y
		if not view._lamp_field._chunks.has(coord):
			continue
		for lamp_value in view._lamp_field._chunks[coord]:
			var local: Vector3 = (lamp_value as Array)[0] - root.position
			# ceiling lamps hang at a cell centre (wall lamps sit on a cell boundary)
			if absf(local.x - floorf(local.x) - .5) > .1 or absf(local.z - floorf(local.z) - .5) > .1:
				continue
			checked += 1
			var cell := Vector2i(floori(local.x), floori(local.z))
			var mount := local.y + .5    # RefDecor._ceiling_lamp registers its light half a metre under the fitting
			# wall-mounted sewer lamps (props at FEATURE_MOUNT_Y) sit well under the vault on their wall: not ceiling fittings
			if ceiling.has(cell) and mount < float(ceiling[cell]) - .5:
				continue
			if not ceiling.has(cell) or absf(float(ceiling[cell]) - mount) > .05:
				bad.append("%s %s (mount %.2f, ceiling %s)" % [coord, cell, mount, ceiling.get(cell, "none")])
	_expect(checked > 0, "no ceiling lamps below the maze to check")
	_expect(bad.is_empty(), "%d ceiling lamps below the maze float (no ceiling face within 5 cm over them), e.g. %s" % [
		bad.size(), bad.slice(0, 4)])


## The game window is opaque (KT: the macOS desktop showed through the sewer and
## past the far distance): no transparent window, no per-pixel transparency and
## an opaque root viewport, so empty or unlit space shows the environment colour.
func _check_opaque_window(host: Node) -> void:
	_expect(not bool(ProjectSettings.get_setting("display/window/size/transparent", false)),
		"project.godot makes the game window transparent")
	_expect(not bool(ProjectSettings.get_setting("display/window/per_pixel_transparency/allowed", false)),
		"project.godot allows per-pixel window transparency")
	_expect(not host.get_tree().root.transparent_bg, "the root viewport draws a transparent background")
	_expect(RefLook.make_environment().background_mode == Environment.BG_COLOR \
		and RefLook.make_environment().background_color.a >= 1.0, "the route environment's background is not opaque")


## Holds an input action until the runner has stepped off the ladder (or
## `frames` pass); returns the height seen when the climb was half done.
func _hold_climb(host: Node, player: PlayerController3D, action: String, frames: int) -> float:
	var midway := INF
	Input.action_press(action)
	for _frame in frames:
		await host.get_tree().physics_frame
		if midway == INF and absf(player.ladder_climb_progress() - .5) < .05:
			midway = player.global_position.y
		if not player.is_climbing():
			break
	Input.action_release(action)
	return midway


## The levels under the sewer (docs/SEWERS.md): the Inferno is gone from the maze
## and is the whole of level -3; -2 is the collector sewer; every ramp agrees
## between its two levels, its top landing joins the upper level's walkways and
## its bottom landing the lower level's halls (the collector's tunnels or the
## Inferno's central hall); hunter A* reaches both landings; and a runner walks
## down a ramp onto the collector and back up, the view following.
func _check_deep_levels(host: Node) -> void:
	var generator := StreamedRouteGenerator.new("SEWER-DEEP")
	var inferno_on_maze := 0
	for z in range(-8, 9):
		for x in range(-8, 9):
			if generator.biome_for(Vector3i(x, 0, z)) == "inferno":
				inferno_on_maze += 1
	_expect(inferno_on_maze == 0, "%d maze chunks still roll the Inferno" % inferno_on_maze)
	_expect(generator.biome_for(Vector3i(3, StreamedRouteGenerator.INFERNO_LEVEL, -2)) == "inferno"
		and generator.biome_for(Vector3i(3, StreamedRouteGenerator.LOWER_SEWER_LEVEL, -2)) == "sewer",
		"level -2 is not the sewer or level -3 is not the Inferno")
	_expect(not generator.is_chunk_allowed(Vector3i(0, StreamedRouteGenerator.INFERNO_LEVEL - 1, 0)),
		"there is a level below the Inferno")
	var counts := {SewerRouteGenerator.LEVEL: 0, SewerRouteGenerator.LOWER_LEVEL: 0}
	var walk_ramp := {}
	for z in range(-3, 4):
		for x in range(-3, 4):
			for upper in counts:
				var ramp: Dictionary = generator.sewer().ramp_between(x, z, upper)
				if ramp.is_empty():
					continue
				counts[upper] = int(counts[upper]) + 1
				_check_ramp(generator, x, z, ramp)
				if upper == SewerRouteGenerator.LEVEL and walk_ramp.is_empty():
					walk_ramp = ramp.merged({"x": x, "z": z})
	_expect(int(counts[SewerRouteGenerator.LEVEL]) >= 5 and int(counts[SewerRouteGenerator.LOWER_LEVEL]) >= 5,
		"too few ramps around the origin (%s)" % [counts])
	if not walk_ramp.is_empty():
		await _walk_ramp(host, generator, walk_ramp)
	print("  ok    deep levels: Inferno only at -3, %d sewer ramps and %d Inferno ramps checked" % [
		counts[SewerRouteGenerator.LEVEL], counts[SewerRouteGenerator.LOWER_LEVEL]])


func _check_ramp(generator: StreamedRouteGenerator, x: int, z: int, ramp: Dictionary) -> void:
	var upper := int(ramp["upper"])
	var lower := upper - 1
	var top_data: Dictionary = generator.chunk(Vector3i(x, upper, z))
	var low_data: Dictionary = generator.chunk(Vector3i(x, lower, z))
	var slope: Rect2i = ramp["ramp"]
	var agree := true
	for cz in range(slope.position.y, slope.end.y):
		for cx in range(slope.position.x, slope.end.x):
			var cell := Vector2i(cx, cz)
			if not (top_data["ramp_cells"] as Dictionary).has(cell) or not (low_data["ramp_cells"] as Dictionary).has(cell):
				agree = false
	_expect(agree, "ramp %s: the two levels disagree about its slope" % ramp["link"]["id"])
	var top: Vector2i = ramp["link"]["from_cell"]
	var bottom: Vector2i = ramp["link"]["to_cell"]
	_expect(int(top_data["grid"][top.y][top.x]) == 0 and int(low_data["grid"][bottom.y][bottom.x]) == 0,
		"ramp %s: a landing is not open floor" % ramp["link"]["id"])
	# both landings join their level's halls: flood the chunk's open grid from the landing
	for pair in [[top_data, top], [low_data, bottom]]:
		var grid: Array = pair[0]["grid"]
		var seen := _flood_grid(grid, pair[1])
		_expect(seen.size() > 200, "ramp %s: a landing is cut off from its level (%d cells reached)" % [
			ramp["link"]["id"], seen.size()])


static func _flood_grid(grid: Array, start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cell + step
			if n.x < 0 or n.y < 0 or n.x >= grid.size() or n.y >= grid.size() or seen.has(n) or int(grid[n.y][n.x]) != 0:
				continue
			seen[n] = true
			queue.append(n)
	return seen


## Walks a real runner down the ramp and back up with the movement keys.
func _walk_ramp(host: Node, generator: StreamedRouteGenerator, ramp: Dictionary) -> void:
	var view := StreamedFacilityView3D.new()
	host.add_child(view)
	var player := (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	host.add_child(player)
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var origin := Vector2(int(ramp["x"]) * size, int(ramp["z"]) * size)
	var upper := int(ramp["upper"])
	var top_point := origin + Vector2(ramp["link"]["from_cell"]) + Vector2(.5, .5)
	var bottom_point := origin + Vector2(ramp["link"]["to_cell"]) + Vector2(.5, .5)
	var upper_y := float(upper) * StreamedFacilityView3D.LEVEL_HEIGHT
	player.global_position = Vector3(top_point.x, upper_y + .1, top_point.y)
	view.begin("SEWER-DEEP", player)
	# a runner reaches a ramp head over seconds of walking: let the window (both levels) stream in first
	for _frame in 90:
		await host.get_tree().physics_frame
	var unseen := {}
	for leg in [{"to": bottom_point, "level": upper - 1}, {"to": top_point, "level": upper}]:
		var target: Vector2 = leg["to"]
		var arrived := false
		Input.action_press("move_up")
		for _frame in 900:
			var here := Vector2(player.global_position.x, player.global_position.z)
			var heading := target - here
			player.rotation.y = atan2(-heading.x, -heading.y)
			await host.get_tree().physics_frame
			view._process(1.0 / 60.0)
			_link_view_frame(view, player, [upper, upper - 1], unseen, "ramp from %d" % upper)
			if here.distance_to(target) < .6:
				arrived = true
				break
		Input.action_release("move_up")
		for _frame in 10:
			await host.get_tree().physics_frame
		var want_y := float(int(leg["level"])) * StreamedFacilityView3D.LEVEL_HEIGHT
		_expect(arrived and absf(player.global_position.y - want_y) < .3,
			"walking the ramp did not reach level %d (at %s)" % [int(leg["level"]), player.global_position])
		_expect(view.current_level() == int(leg["level"]), "after the ramp the view is on level %d, not %d" % [
			view.current_level(), int(leg["level"])])
	_link_view_report(unseen, "ramp from %d" % upper)
	view.clear()
	view.queue_free()
	player.queue_free()


## The first sewer feeds the collector: at each falls site the spur channel runs
## to an open drop whose every cell lies over the cistern below (pool or its
## walkway ring), in a quadrant no ramp uses; the collector itself keeps the
## sewer rules (three-wide dry walkways, all reachable); and the live chunks
## carry the waterfall sheet, the mist and the drop's blocking colliders.
func _check_falls(host: Node) -> void:
	var generator := StreamedRouteGenerator.new("SEWER-FALLS")
	var sites := 0
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var lower_cells := {}
	var site := {}
	for z in range(-3, 4):
		for x in range(-3, 4):
			var low: Dictionary = generator.chunk(Vector3i(x, SewerRouteGenerator.LOWER_LEVEL, z))
			var low_grid: Array = low["sewer_grid"]
			for cz in size:
				for cx in size:
					if SewerRouteGenerator.is_walkable(int(low_grid[cz][cx])):
						lower_cells[Vector2i(x * size + cx, z * size + cz)] = int(low_grid[cz][cx])
			var falls: Dictionary = generator.sewer().falls_between(x, z)
			if falls.is_empty():
				continue
			sites += 1
			if site.is_empty():
				site = falls.merged({"x": x, "z": z})
			var up_grid: Array = generator.chunk(Vector3i(x, SewerRouteGenerator.LEVEL, z))["sewer_grid"]
			var drop: Rect2i = falls["void"]
			var under_ok := true
			for cz in range(drop.position.y, drop.end.y):
				for cx in range(drop.position.x, drop.end.x):
					if int(up_grid[cz][cx]) != SewerRouteGenerator.FALL or int(low_grid[cz][cx]) == SewerRouteGenerator.SOLID:
						under_ok = false
			_expect(under_ok, "falls at %s: the drop is not open over the cistern below" % Vector2i(x, z))
			var lip_z := int(float(falls["edge_z"])) + (0 if bool(falls["north"]) else -1)
			_expect(int(up_grid[lip_z][int(float(falls["edge_x0"])) + 1]) == SewerRouteGenerator.WATER,
				"falls at %s: the spur's water does not reach the lip" % Vector2i(x, z))
			for upper in [SewerRouteGenerator.LEVEL, SewerRouteGenerator.LOWER_LEVEL]:
				var ramp: Dictionary = generator.sewer().ramp_between(x, z, upper)
				_expect(ramp.is_empty() or int(ramp["quadrant"]) != int(falls["quadrant"]),
					"falls at %s share a quadrant with a ramp" % Vector2i(x, z))
	_expect(sites >= 6, "only %d falls sites around the origin" % sites)
	_check_widths("SEWER-FALLS collector", lower_cells)
	var start := Vector2i(-3 * size + SewerRouteGenerator.CENTER - SewerRouteGenerator.TUNNEL_HALF,
		-3 * size + SewerRouteGenerator.CENTER - SewerRouteGenerator.TUNNEL_HALF)
	var reach := _flood(lower_cells, start, true)
	var dry := 0
	for cell in lower_cells:
		if SewerRouteGenerator.is_dry(int(lower_cells[cell])):
			dry += 1
	_expect(reach.size() == dry, "collector: %d of %d dry cells cut off" % [dry - reach.size(), dry])
	if not site.is_empty():
		var view := StreamedFacilityView3D.new()
		host.add_child(view)
		var player := (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
		host.add_child(player)
		var qc: Vector2i = site["center"]
		var overlook: Rect2i = site["overlook"]
		player.global_position = Vector3(int(site["x"]) * size + overlook.position.x + 1.5,
			float(SewerRouteGenerator.LEVEL) * StreamedFacilityView3D.LEVEL_HEIGHT + .1, int(site["z"]) * size + overlook.position.y + 1.5)
		view.begin("SEWER-FALLS", player)
		var upper_root: Node3D = view._loaded.get(Vector3i(int(site["x"]), SewerRouteGenerator.LEVEL, int(site["z"])))
		var lower_root: Node3D = view._loaded.get(Vector3i(int(site["x"]), SewerRouteGenerator.LOWER_LEVEL, int(site["z"])))
		_expect(upper_root != null and upper_root.get_node_or_null("Waterfall") != null, "the falls chunk has no waterfall sheet")
		_expect(lower_root != null and lower_root.get_node_or_null("FallsMist") != null,
			"the cistern below the falls is not loaded or has no mist")
		if upper_root != null:
			var structure := upper_root.get_node("Structure") as GridMap
			_expect(structure.get_cell_item(Vector3i(qc.x, 0, qc.y)) == view._col_channel_item,
				"the falls' drop is not blocked to walk")
		_check_colliders_below_maze(view)
		view.clear()
		view.queue_free()
		player.queue_free()
	print("  ok    falls: %d sites feed the collector, drops over the cisterns, collector walkable" % sites)


## Every light fixture in a loaded sewer chunk (the decor's wall and ceiling lamps
## as registered with the LampField, and the authored caged lamps) hangs over
## walkable floor or a deck, never out over a channel, the falls' drop or a ramp
## tunnel (KT: lamps on the channel's edge floated over the water).
func _check_lamps_over_floor(view: StreamedFacilityView3D) -> void:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var checked := 0
	var floating := []
	for key_value in view._lamp_field._chunks:
		var coord: Vector3i = key_value
		if coord.y != SewerRouteGenerator.LEVEL and coord.y != SewerRouteGenerator.LOWER_LEVEL:
			continue
		var sewer_grid: Array = view.generator.chunk(coord)["sewer_grid"]
		for lamp_value in view._lamp_field._chunks[key_value]:
			var at: Vector3 = (lamp_value as Array)[0]
			# wall lamps only (they sit on a cell boundary, on the face they are fixed
			# to); a pendant hangs from the vault at a cell centre, anchored overhead
			var fx := absf(at.x - roundf(at.x))
			var fz := absf(at.z - roundf(at.z))
			if fx > .15 and fz > .15:
				continue
			checked += 1
			# a wall lamp sits on the line between its wall and the floor: sample just
			# around it; brick or floor is fine, water / a drop / a ramp is not
			for offset in [Vector2(.26, 0), Vector2(-.26, 0), Vector2(0, .26), Vector2(0, -.26)]:
				var cell := Vector2i(floori(at.x + offset.x) - coord.x * size, floori(at.z + offset.y) - coord.z * size)
				if cell.x < 0 or cell.y < 0 or cell.x >= size or cell.y >= size:
					continue
				var code := int(sewer_grid[cell.y][cell.x])
				if code in [SewerRouteGenerator.WATER, SewerRouteGenerator.FALL, SewerRouteGenerator.RAMP]:
					floating.append("%s %s" % [coord, cell])
					break
	for coord_value in view._loaded:
		var coord: Vector3i = coord_value
		if coord.y != SewerRouteGenerator.LEVEL and coord.y != SewerRouteGenerator.LOWER_LEVEL:
			continue
		var data: Dictionary = view.generator.chunk(coord)
		for prop in data["region_props"]:
			if String(prop["type"]) != "sewerLamp":
				continue
			checked += 1
			var cell: Vector2i = prop["cell"]
			if not SewerRouteGenerator.is_walkable(int(data["sewer_grid"][cell.y][cell.x])):
				floating.append("%s caged lamp %s" % [coord, cell])
	_expect(checked > 10, "only %d sewer lamps found to check" % checked)
	_expect(floating.is_empty(), "%d sewer lamps hang out over water, a drop or a ramp: %s" % [floating.size(), floating.slice(0, 5)])


## Stairwells (Stairwells, kinds "stairs" and "spiral"): sparse between the maze
## and the sewer, planned for +1..+3 inside one quadrant clear of the spine and
## the duct lines, always one at chunk (0, 0) going up; both ends of every
## 0 <-> -1 well agree on its cells and their landings join each level; and a
## runner walks a switchback and a spiral up and back down along the stairs
## without popping, snagging or leaving the storey bands.
func _check_stairwells(host: Node) -> void:
	var generator := StreamedRouteGenerator.new("SEWER-STAIRS")
	var counts := {0: 0, 1: 0, 2: 0, 3: 0}
	var kinds := {}
	var walk := {}
	for z in range(-4, 5):
		for x in range(-4, 5):
			for upper in counts:
				var well: Dictionary = generator.stairwell_between(x, z, upper)
				if well.is_empty():
					continue
				counts[upper] = int(counts[upper]) + 1
				kinds[well["kind"]] = true
				var box: Rect2i = well["box"]
				var clear := box.position.x >= 2 and box.position.y >= 2 and box.end.x <= 42 and box.end.y <= 42
				for line in [6, 38, 21, 22, 23]:
					if (box.position.x <= line and line < box.end.x) or (box.position.y <= line and line < box.end.y):
						clear = false
				if upper == 0:
					# the maze's own areas: outer room bands, clear of the main halls and the spine
					clear = Stairwells.MAZE_AREAS.any(func(area: Rect2i) -> bool: return area.encloses(box))
				_expect(clear, "stairwell %s breaks the placement rules (box %s)" % [well["link"]["id"], box])
				if upper == 0:
					_check_stairwell_ends(generator, x, z, well)
					if not walk.has(well["kind"]):
						walk[well["kind"]] = well.merged({"x": x, "z": z})
	for upper in [1, 2, 3]:
		_expect(not generator.stairwell_between(0, 0, upper).is_empty(), "no guaranteed stairwell up to +%d at chunk (0, 0)" % upper)
	_expect(int(counts[0]) >= 3 and int(counts[0]) <= 30, "%d maze <-> sewer stairwells in 81 chunks (want sparse)" % counts[0])
	_expect(kinds.has("stairs") and kinds.has("spiral"), "only %s stairwell kinds generated" % [kinds.keys()])
	for kind in walk:
		await _walk_stairwell(host, walk[kind])
	print("  ok    stairwells: %s per level pair in 81 chunks, kinds %s, walked %s both ways" % [counts, kinds.keys(), walk.keys()])


func _check_stairwell_ends(generator: StreamedRouteGenerator, x: int, z: int, well: Dictionary) -> void:
	var top: Dictionary = generator.chunk(Vector3i(x, 0, z))
	var bottom: Dictionary = generator.chunk(Vector3i(x, SewerRouteGenerator.LEVEL, z))
	var cells: Dictionary = well["shaft"]
	var agree := true
	for cell in cells:
		if not (top["shaft_cells"] as Dictionary).has(cell) or not (bottom["shaft_cells"] as Dictionary).has(cell):
			agree = false
	_expect(agree, "stairwell %s: the maze and the sewer disagree about its well" % well["link"]["id"])
	var landing: Vector2i = well["landing"]
	for data in [top, bottom]:
		var grid: Array = data["grid"]
		_expect(int(grid[landing.y][landing.x]) == 0, "stairwell %s: a landing is not open floor" % well["link"]["id"])
		_expect(_flood_grid(grid, landing).size() > 200, "stairwell %s: a landing is cut off from its level" % well["link"]["id"])


## Stairs and slopes (KT: "a blank area" around the stairs on the test build): while a runner walks a stairwell or a
## ramp, every chunk on either of its two levels within LINK_VIEW_CLEAR metres of the runner is in the stream window
## the whole way (never dropped at the level flip half way along), and is built and shown within LINK_VIEW_GRACE
## frames of coming that close. `unseen` collects chunk -> {"frames", "worst", "dropped"} across the walk.
const LINK_VIEW_CLEAR := 12.0
const LINK_VIEW_GRACE := 45


func _link_view_frame(view: StreamedFacilityView3D, player: PlayerController3D, levels: Array, unseen: Dictionary,
		_where: String) -> void:
	var here := Vector2(player.global_position.x, player.global_position.z)
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var cx := floori(here.x / size)
	var cz := floori(here.y / size)
	for level in levels:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var coord := Vector3i(cx + dx, int(level), cz + dz)
				if not view.generator.is_chunk_allowed(coord) \
						or StreamedFacilityView3D._distance_from_point_to_chunk(here, coord) >= LINK_VIEW_CLEAR:
					continue
				var entry: Dictionary = unseen.get(coord, {"frames": 0, "worst": 0, "dropped": false})
				if not view._wanted_now.has(coord):
					entry["dropped"] = true
				var root: Node3D = view._loaded.get(coord)
				if root == null or not root.visible:
					entry["frames"] = int(entry["frames"]) + 1
				else:
					entry["frames"] = 0
				entry["worst"] = maxi(int(entry["worst"]), int(entry["frames"]))
				unseen[coord] = entry


func _link_view_report(unseen: Dictionary, where: String) -> void:
	for coord in unseen:
		var entry: Dictionary = unseen[coord]
		_expect(not bool(entry["dropped"]), "%s: chunk %s within %.0f m left the stream window during the walk" % [
			where, coord, LINK_VIEW_CLEAR])
		_expect(int(entry["worst"]) <= LINK_VIEW_GRACE, "%s: chunk %s within %.0f m stayed unloaded for %d frames" % [
			where, coord, LINK_VIEW_CLEAR, entry["worst"]])


## Follows the stair path with the movement keys, up then down.
func _walk_stairwell(host: Node, well: Dictionary) -> void:
	var view := StreamedFacilityView3D.new()
	host.add_child(view)
	var player := (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	host.add_child(player)
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var origin := Vector3(int(well["x"]) * size, float(well["upper"] - 1) * StreamedFacilityView3D.LEVEL_HEIGHT,
		int(well["z"]) * size)
	var path: Array = well["link"]["path"]
	var start: Vector3 = path[0]
	player.global_position = origin + start + Vector3(0, .05, 0)
	view.begin("SEWER-STAIRS", player)
	for _frame in 90:
		await host.get_tree().physics_frame
	var unseen := {}
	for leg in ["up", "down"]:
		var points: Array = path.duplicate()
		if leg == "down":
			points.reverse()
		var worst_pop := 0.0
		var stalled := false
		var last_y := player.global_position.y
		Input.action_press("move_up")
		for i in range(1, points.size()):
			var target: Vector3 = origin + (points[i] as Vector3)
			var frames := 0
			while Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() > .35:
				var heading := Vector2(target.x - player.global_position.x, target.z - player.global_position.z)
				player.rotation.y = atan2(-heading.x, -heading.y)
				await host.get_tree().physics_frame
				view._process(1.0 / 60.0)
				_link_view_frame(view, player, [int(well["upper"]), int(well["upper"]) - 1], unseen, "%s stairwell" % well["kind"])
				worst_pop = maxf(worst_pop, absf(player.global_position.y - last_y))
				last_y = player.global_position.y
				frames += 1
				if frames > 400:
					stalled = true
					break
			if stalled:
				break
		Input.action_release("move_up")
		for _frame in 10:
			await host.get_tree().physics_frame
		var end: Vector3 = origin + (points[points.size() - 1] as Vector3)
		_expect(not stalled, "%s stairwell: the runner got stuck going %s (at %s)" % [well["kind"], leg, player.global_position])
		_expect(absf(player.global_position.y - end.y) < .3, "%s stairwell: going %s ended at y %.2f, not %.2f" % [
			well["kind"], leg, player.global_position.y, end.y])
		_expect(worst_pop < .12, "%s stairwell: the runner popped %.2f m in one frame going %s (snag or step)" % [
			well["kind"], worst_pop, leg])
	_link_view_report(unseen, "%s stairwell" % well["kind"])
	_check_colliders_below_maze(view)
	view.clear()
	view.queue_free()
	player.queue_free()
