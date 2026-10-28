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
	await _check_streaming(host)
	_expect(total_links >= 6, "sewer windows hold %d links (want at least 6)" % total_links)
	_expect(valves_checked >= 10, "only %d valve wheels checked for a wall behind them" % valves_checked)
	if _failures == 0:
		print("  ok    sewers: %d links, all reachable both ways" % total_links)
	return _failures


var valves_checked := 0


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
				# the overflow weir stands in its basin's water; everything else on floor or deck
				var standing: bool = SewerRouteGenerator.is_walkable(int(grid[fc.y][fc.x])) \
					or (feature["type"] == "sewerOverflowGrate" and int(grid[fc.y][fc.x]) == SewerRouteGenerator.WATER)
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
			var ladders := {}
			for feature in data["features"]:
				if feature["type"] == "sewerLadder":
					ladders[feature["link"]] = feature["cell"]
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
		# The runner climbs down that ladder and back up: smooth, collision off on
		# the rungs, and the view follows onto each level.
		var rise := StreamedFacilityView3D.LEVEL_HEIGHT
		var top := Vector3(lid.x + .5, .04, lid.y + .5)
		for leg in [{"from": top, "rise": -rise, "level": SewerRouteGenerator.LEVEL},
				{"from": top - Vector3(0, rise, 0), "rise": rise, "level": 0}]:
			player.begin_ladder_climb(leg["from"], leg["rise"], .6, 0.0, leg["level"])
			_expect(player.is_climbing() and player.collision_layer == 0, "the runner did not get onto the ladder")
			var midway_y := INF
			for _frame in 120:
				await host.get_tree().physics_frame
				if player.ladder_climb_progress() > .45 and midway_y == INF:
					midway_y = player.global_position.y
				if not player.is_climbing():
					break
			view.refresh_at_tracked_player()
			var want_y := float(Vector3(leg["from"]).y) + float(leg["rise"])
			_expect(not player.is_climbing() and absf(player.global_position.y - want_y) < .05,
				"the climb did not end on the far floor (y %.2f, want %.2f)" % [player.global_position.y, want_y])
			_expect(midway_y > minf(float(Vector3(leg["from"]).y), want_y) + .5 \
				and midway_y < maxf(float(Vector3(leg["from"]).y), want_y) - .5,
				"the climb jumped instead of moving along the rungs")
			_expect(view.current_level() == int(leg["level"]), "after the climb the view is on level %d, not %d" % [
				view.current_level(), int(leg["level"])])
			_expect(player.collision_layer == 1, "the runner kept collision off after the climb")
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
	var coords := []
	for z in range(-1, 2):
		for x in range(-1, 2):
			coords.append(Vector3i(x, SewerRouteGenerator.LEVEL, z))
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
	for i in range(1, feet.size()):
		var a := LadderTraffic.ladder_point(feet[0], SewerRouteGenerator.LEVEL)
		var b := LadderTraffic.ladder_point(feet[i], SewerRouteGenerator.LEVEL)
		var route: Array = below.find_path(Vector2i(floori(a.x), floori(a.y)), Vector2i(floori(b.x), floori(b.y)))
		if not route.is_empty():
			routed += 1
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
	_expect(routed == feet.size() - 1, "hunter A* reached %d of %d ladders through the sewer" % [routed, feet.size() - 1])
	_expect(lids == feet.size(), "hunter A* reached %d of %d ladder lids on the maze" % [lids, feet.size()])
	print("  ok    sewer hunter paths: %d ladders, all reachable above and below" % feet.size())


## No level -1 collider may rise into level 0: every GridMap cell shape and
## every prop body under a sewer chunk tops out at or below the underside of the
## maze's floor slab (playtest GOLF: full-height wall blocks a storey down stood
## 3.5 m into open maze halls). The ladder opening needs no exception: the maze
## keeps its own floor collider over it and the sewer adds nothing there.
func _check_colliders_below_maze(view: StreamedFacilityView3D) -> void:
	var ceiling := -StreamedFacilityView3D.SLAB + .001
	var worst := -INF
	var where := ""
	var checked := 0
	for coord_value in view._loaded.keys():
		var coord: Vector3i = coord_value
		if coord.y != SewerRouteGenerator.LEVEL:
			continue
		var root: Node3D = view._loaded[coord]
		var grid := root.get_node_or_null("Structure") as GridMap
		if grid != null:
			for cell_value in grid.get_used_cells():
				var cell: Vector3i = cell_value
				var shapes: Array = grid.mesh_library.get_item_shapes(grid.get_cell_item(cell))
				for i in range(0, shapes.size(), 2):
					var top := _shape_top(shapes[i], grid.to_global(grid.map_to_local(cell)), shapes[i + 1])
					checked += 1
					if top > worst:
						worst = top
						where = "%s Structure cell %s" % [coord, cell]
		for node in root.find_children("*", "CollisionShape3D", true, false):
			var shape_node := node as CollisionShape3D
			if shape_node.shape == null or shape_node.get_parent() is GridMap:
				continue
			var aabb := shape_node.global_transform * shape_node.shape.get_debug_mesh().get_aabb()
			checked += 1
			if aabb.end.y > worst:
				worst = aabb.end.y
				where = "%s %s" % [coord, root.get_path_to(shape_node)]
	_expect(checked > 0, "no sewer colliders found to check")
	_expect(worst <= ceiling, "a sewer collider rises into the maze: %s tops out at y %.2f (limit %.2f)" % [where, worst, ceiling])


static func _shape_top(shape: Shape3D, cell_origin: Vector3, local: Transform3D) -> float:
	var aabb := shape.get_debug_mesh().get_aabb()
	return (Transform3D(Basis.IDENTITY, cell_origin) * local * aabb).end.y


## Deep channels with real crossings, per chunk: the water lies well below the
## walkways over a bed a metre down; along both arms of the cross no stretch of
## open water runs longer than MAX_OPEN_WATER cells between decks; every 3 x 3
## deck carries its authored prop (a bridge on the tunnels, grate tiles on the
## junction plaza); and the overflow basin is open water too. Crossings come
## about every 24 m: within a chunk the longest open stretch is 9 cells (two such
## stretches meet across a seam).
const MAX_OPEN_WATER := 10


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
