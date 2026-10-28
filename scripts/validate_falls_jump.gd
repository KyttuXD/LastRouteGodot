extends RefCounted

## The waterfall jump (docs/SEWERS.md): at each falls lip on the first sewer there is exactly one railing gap in front of an open drop
## cell; stepping through it plunges the runner into the collector's cistern (no damage), a slow swim ends on the walkway ring, and
## the runner is soaked for a while. Static checks cover every falls site around the origin; the live check plays one plunge in a real
## streamed route.
##
##   godot --headless --path . res://scenes/validate.tscn -- falls_jump

const SEEDS := ["SEWER-FALLS", "MAP-CHECK", "JUMP-A"]
const WINDOW := Vector2i(4, 4)

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var sites := 0
	for seed_text in SEEDS:
		sites += _check_sites(seed_text)
	_expect(sites >= 8, "only %d falls sites to check around the origin" % sites)
	_check_roar_loop()
	await _check_view_gap(host)
	await _live_plunge(host)
	if _failures == 0:
		print("falls_jump OK")
	return _failures


## ---------------------------------------------------------------- every lip

func _check_sites(seed_text: String) -> int:
	var generator := StreamedRouteGenerator.new(seed_text)
	var sites := 0
	for z in range(-WINDOW.y, WINDOW.y + 1):
		for x in range(-WINDOW.x, WINDOW.x + 1):
			var falls: Dictionary = generator.sewer().falls_between(x, z)
			if falls.is_empty():
				continue
			sites += 1
			var label := "%s falls at %s" % [seed_text, Vector2i(x, z)]
			_expect(falls.has("jump"), "%s has no jump" % label)
			if not falls.has("jump"):
				continue
			var jump: Dictionary = falls["jump"]
			var upper: Array = generator.chunk(Vector3i(x, SewerRouteGenerator.LEVEL, z))["sewer_grid"]
			var lower: Array = generator.chunk(Vector3i(x, SewerRouteGenerator.LOWER_LEVEL, z))["sewer_grid"]
			var cell: Vector2i = jump["cell"]
			var start: Vector2i = jump["start"]
			var dir: Vector2i = jump["dir"]
			var pool: Rect2i = falls["pool"]
			_expect(int(upper[cell.y][cell.x]) == SewerRouteGenerator.FALL, "%s: the jump cell is not an open drop cell" % label)
			_expect(start == cell - dir and int(upper[start.y][start.x]) == SewerRouteGenerator.DRY, "%s: the jump is not entered from dry ledge" % label)
			_expect((falls["overlook"] as Rect2i).has_point(start), "%s: the jump is not entered from the overlook ledge" % label)
			_expect((falls["void"] as Rect2i).has_point(cell), "%s: the jump cell is outside the drop" % label)
			# every lip lands in a pool: the arc ends over pool water, the swim ends on the dry ring beside it
			var land: Vector2 = jump["land"]
			var land_cell := Vector2i(floori(land.x), floori(land.y))
			_expect(pool.has_point(land_cell) and int(lower[land_cell.y][land_cell.x]) == SewerRouteGenerator.WATER, "%s: the jump does not land in the pool" % label)
			var exit: Vector2 = jump["exit"]
			var exit_cell := Vector2i(floori(exit.x), floori(exit.y))
			_expect(int(lower[exit_cell.y][exit_cell.x]) == SewerRouteGenerator.DRY and not pool.has_point(exit_cell), "%s: the swim does not end on dry ground" % label)
			# nobody gets stuck under water: a short straight swim from the landing to the exit over pool cells only
			var steps := int(land.distance_to(exit) * 4.0)
			for step in steps + 1:
				var p := land.lerp(exit, float(step) / float(maxi(steps, 1)))
				var c := Vector2i(floori(p.x), floori(p.y))
				_expect(pool.has_point(c) or c == exit_cell, "%s: the swim leaves the pool at %s" % [label, c])
			_expect(land.distance_to(exit) / 1.5 >= 1.8 and land.distance_to(exit) / 1.5 <= 3.2, "%s: the swim lasts %.1f s (want about 2-3)" % [label, land.distance_to(exit) / 1.5])
			# the exit leads on: the dry ring connects to the chunk's main cross
			_expect(_reaches_cross(lower, exit_cell), "%s: the climb-out is cut off from the collector's tunnels" % label)
	return sites


func _reaches_cross(grid: Array, from: Vector2i) -> bool:
	var seen := {from: true}
	var queue := [from]
	var goal := Vector2i(SewerRouteGenerator.CENTER - SewerRouteGenerator.TUNNEL_HALF, SewerRouteGenerator.CENTER - SewerRouteGenerator.TUNNEL_HALF)
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		if at == goal:
			return true
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = at + step
			if n.x < 0 or n.y < 0 or n.x >= grid.size() or n.y >= grid.size() or seen.has(n):
				continue
			if not SewerRouteGenerator.is_walkable(int(grid[n.y][n.x])):
				continue
			seen[n] = true
			queue.append(n)
	return false


## ---------------------------------------------------------------- the gap in the view

func _check_view_gap(host: Node) -> void:
	var generator := StreamedRouteGenerator.new("SEWER-FALLS")
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var site := {}
	for z in range(-WINDOW.y, WINDOW.y + 1):
		for x in range(-WINDOW.x, WINDOW.x + 1):
			var falls: Dictionary = generator.sewer().falls_between(x, z)
			if not falls.is_empty() and site.is_empty():
				site = falls.merged({"x": x, "z": z})
	if site.is_empty():
		_expect(false, "no falls site to build a view for")
		return
	var view := StreamedFacilityView3D.new()
	host.add_child(view)
	var player := (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	host.add_child(player)
	var jump: Dictionary = site["jump"]
	var start: Vector2i = jump["start"]
	player.global_position = Vector3(int(site["x"]) * size + start.x + .5, float(SewerRouteGenerator.LEVEL) * StreamedFacilityView3D.LEVEL_HEIGHT + .1,
		int(site["z"]) * size + start.y + .5)
	view.begin("SEWER-FALLS", player)
	var root: Node3D = view._loaded.get(Vector3i(int(site["x"]), SewerRouteGenerator.LEVEL, int(site["z"])))
	_expect(root != null, "the falls chunk is not loaded")
	if root != null:
		var structure := root.get_node("Structure") as GridMap
		var cell: Vector2i = jump["cell"]
		_expect(structure.get_cell_item(Vector3i(cell.x, 0, cell.y)) == GridMap.INVALID_CELL_ITEM, "the jump cell still has a collider (the gap is closed)")
		# its neighbours in the drop stay blocked
		var blocked := 0
		for step in [Vector2i.LEFT, jump["dir"] as Vector2i]:        # the drop beside it and the drop ahead
			var n: Vector2i = cell + step
			blocked += 1 if structure.get_cell_item(Vector3i(n.x, 0, n.y)) == view._col_channel_item else 0
		_expect(blocked == 2, "the drop around the jump cell is open (%d blocked neighbours)" % blocked)
		# railings: the multimesh has fewer segments than the same chunk without the gap would
		# the fall comes out of a visible source: the sill, the crest of foam and the lip light stand on the spur's end
		for source_name in ["Waterfall", "FallsSill", "FallsCrest", "FallsLipLight"]:
			_expect(root.get_node_or_null(source_name) != null, "the falls chunk has no %s (the water comes from nothing)" % source_name)
		var rails := root.get_node_or_null("ChannelRails") as MultiMeshInstance3D
		_expect(rails != null, "the falls chunk has no railings")
		if rails != null:
			var gap_world := Vector3(cell.x + .5, 0.0, cell.y + .5)
			var near := 0
			for index in rails.multimesh.instance_count:
				var origin := rails.multimesh.get_instance_transform(index).origin
				if Vector2(origin.x, origin.z).distance_to(Vector2(start.x + .5, start.y + .5) + Vector2((jump["dir"] as Vector2i)) * .45) < .4:
					near += 1
			_expect(near == 0, "a railing still stands in the gap (%d segments)" % near)
	view.clear()
	view.queue_free()
	player.queue_free()
	await host.get_tree().process_frame


## ---------------------------------------------------------------- one live plunge

func _live_plunge(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "SEWER-FALLS"
	RoomState.map_scale = RoomState.Scale.INFINITE
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	await host.get_tree().process_frame
	for _i in 8:
		await host.get_tree().physics_frame
	var generator = route.facility.generator
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var site := {}
	for z in range(-WINDOW.y, WINDOW.y + 1):
		for x in range(-WINDOW.x, WINDOW.x + 1):
			var falls: Dictionary = generator.sewer().falls_between(x, z)
			if not falls.is_empty() and site.is_empty():
				site = falls.merged({"x": x, "z": z})
	_expect(not site.is_empty(), "no falls site in the live route")
	if site.is_empty():
		route.queue_free()
		return
	var player: PlayerController3D = route.player
	var jump: Dictionary = site["jump"]
	var start: Vector2i = jump["start"]
	var cell: Vector2i = jump["cell"]
	var origin := Vector2(int(site["x"]) * size, int(site["z"]) * size)
	var floor_y := float(SewerRouteGenerator.LEVEL) * StreamedFacilityView3D.LEVEL_HEIGHT
	route.call("_admin_teleport_to", Vector3(origin.x + start.x + .5, floor_y + .1, origin.y + start.y + .5))
	for _i in 90:
		await host.get_tree().physics_frame
	_expect(route.facility.current_level() == StreamedRouteGenerator.SEWER_LEVEL, "the runner is not on the first sewer at the ledge")
	_expect(not player.is_plunging(), "the plunge started before the runner stepped through the gap")
	# step through the gap (a teleport onto the gap cell stands in for walking into it)
	player.global_position = Vector3(origin.x + cell.x + .5, floor_y + .1, origin.y + cell.y + .5)
	var frames := 0
	var started := false
	var saw_splash_noise := false
	var min_level := 0
	while frames < 900 and not (started and not player.is_plunging()):
		await host.get_tree().physics_frame
		frames += 1
		started = started or player.is_plunging()
		if player.is_plunging() and String(player.plunge.get("phase", "")) == "splash" and player.noise >= PlayerController3D.PLUNGE_SPLASH_NOISE - .01:
			saw_splash_noise = true
		min_level = mini(min_level, route.facility.current_level())
	_expect(started, "stepping through the gap did not start the plunge")
	_expect(started and not player.is_plunging(), "the plunge never finished (%d frames)" % frames)
	_expect(saw_splash_noise, "the splash did not make a loud noise for the hunters")
	_expect(min_level == StreamedRouteGenerator.LOWER_SEWER_LEVEL, "the mid-fall level change never reached the collector (%d)" % min_level)
	_expect(route.facility.current_level() == StreamedRouteGenerator.LOWER_SEWER_LEVEL, "the runner did not end on the collector level")
	var exit := origin + Vector2(jump["exit"])
	_expect(player.grid_position().distance_to(exit) < .4, "the runner did not climb out at the exit (%.1f cells away)" % player.grid_position().distance_to(exit))
	_expect(player.collision_layer == 1 and player.collision_mask == 1, "collision was not restored after the plunge")
	_expect(player.soaked_left > PlayerController3D.SOAKED_SECONDS - 2.0, "the runner is not soaked after the plunge (%.1f s)" % player.soaked_left)
	# not stuck: standing at the exit the runner rests on the floor and can move
	var rest_y := player.global_position.y
	for _i in 40:
		await host.get_tree().physics_frame
	_expect(absf(player.global_position.y - float(StreamedRouteGenerator.LOWER_SEWER_LEVEL) * StreamedFacilityView3D.LEVEL_HEIGHT) < .3, "the runner is not standing on the collector floor after climbing out (y %.2f)" % player.global_position.y)
	_expect(absf(player.global_position.y - rest_y) < .3, "the runner sinks or rises after the plunge")
	# soaked times out
	player.soaked_left = 0.5
	for _i in 60:
		await host.get_tree().physics_frame
	_expect(player.soaked_left == 0.0, "soaked did not time out")
	route.queue_free()
	await host.get_tree().process_frame


## The falls' roar loops without a seam or a lurch (KT: "weird banging"): no click where the end meets the start, and the
## level in 100 ms windows (whole signal) and 200 ms windows (the low band alone) stay within 3 dB / 4 dB across the whole loop.
func _check_roar_loop() -> void:
	var channels := FallsLoop.samples()
	for channel in 2:
		var data: PackedFloat32Array = channels[channel]
		var frames := data.size()
		var diffs := 0.0
		for i in range(1, frames):
			diffs += pow(data[i] - data[i - 1], 2.0)
		var step := sqrt(diffs / frames)
		_expect(absf(data[0] - data[frames - 1]) <= step * 6.0, "the roar has a click at the loop seam (jump %.4f vs typical step %.4f)" % [absf(data[0] - data[frames - 1]), step])
		# 100 ms RMS windows, wrapping, over the full signal and over a one-pole low band (~200 Hz)
		var alpha := 1.0 - exp(-TAU * 200.0 / FallsLoop.RATE)
		var low := PackedFloat32Array()
		low.resize(frames)
		var state := data[frames - 1]
		for pass_index in 2:
			for i in frames:
				state += (data[i] - state) * alpha
				if pass_index == 1:
					low[i] = state
		for signal_name in ["full", "low"]:
			var source: PackedFloat32Array = data if signal_name == "full" else low
			var window := FallsLoop.RATE / 10 * (2 if signal_name == "low" else 1)
			var lo := 1.0e9
			var hi := 0.0
			for start in range(0, frames - window, window / 2):
				var sum := 0.0
				for i in window:
					sum += source[start + i] * source[start + i]
				var rms := sqrt(sum / window)
				lo = minf(lo, rms)
				hi = maxf(hi, rms)
			# the window straddling the seam
			var seam := 0.0
			for i in window:
				var v := source[(frames - window / 2 + i) % frames]
				seam += v * v
			var seam_rms := sqrt(seam / window)
			lo = minf(lo, seam_rms)
			hi = maxf(hi, seam_rms)
			_expect(hi / maxf(lo, 1e-9) <= (1.6 if signal_name == "low" else 1.41), "the roar's %s level lurches %.1f dB within the loop" % [signal_name, 20.0 * log(hi / maxf(lo, 1e-9)) / log(10.0)])
