extends RefCounted

## Streaming performance guard, measured without a GPU (CPU cost of the streaming layer only). Drives the runner across fresh
## Last Route chunks and checks the budgets the stream queue promises:
##   - no frame spends more than MAX_STREAM_CPU_MS of main-thread time on chunk building/unloading,
##   - a level change or teleport never builds the whole window synchronously (MAX_JUMP_MS),
##   - the chunk under the runner is always loaded (no pop-in where the player stands) and the queue drains,
##   - ladder trips between the maze and the sewer, and ramp walks between the two sewers: no frame over
##     MAX_LADDER_FRAME_MS around a level change, and climbing
##     back rebuilds nothing (the storey left behind is parked, not freed).
## Windowed frame times (no frame > 33 ms while streaming on the mini) come from tools/look/stream_bench.tscn; when
## STREAM_BENCH_JSON names its output, those budgets are checked here too.
##
##   godot --headless --path . res://scenes/validate.tscn -- stream_perf

const MAX_STREAM_CPU_MS := 22.0     # STREAM_BUDGET_MAX_MS plus one indivisible step (a GridMap/surface attach, one prop)
const MAX_JUMP_MS := 1500.0         # was 2.8-4.2 s headless on the Windows PCs (whole window plus shafts in one frame); now ~0.6-0.9 s
const BENCH_MAX_STREAM_FRAME_MS := 33.3
const MAX_LADDER_FRAME_MS := 60.0  # headless CPU frame on arriving at the other storey (was 170-600 ms: rebuilds, ambience synth)
const SPEED := 9.0                  # metres per frame-second, a little above a sprint

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _drive(host: Node, city: bool) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "STREAM-BENCH"
	var scene: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(scene)
	var facility: StreamedFacilityView3D = scene.get_node("%StreamedFacility")
	var player: PlayerController3D = scene.get_node("%Player")
	for _i in 10:
		await host.get_tree().process_frame
	player.admin_god_mode = true
	player.set_physics_process(false)
	var size := float(StreamedRouteGenerator.CHUNK_SIZE)
	var start := player.global_position
	var legs: Array = [Vector3(-1.5 * size, 0, 0), Vector3(1.5 * size, 0, 0)] if city else [Vector3(3 * size, 0, 0), Vector3(3 * size, 0, 2 * size)]
	var label := "city" if city else "route"
	var worst := 0.0
	var worst_step := ""
	var missing_under := 0
	facility.take_frame_stream_cost()
	for leg in legs:
		var from := player.global_position
		var target: Vector3 = start + leg
		var steps := int(from.distance_to(target) / (SPEED / 60.0))
		for i in steps:
			player.global_position = from.lerp(target, float(i + 1) / steps)
			await host.get_tree().process_frame
			var cost: Array = facility.take_frame_stream_cost()
			# chunk_changed is the game's own listeners (hunters, minimap), not chunk building: reported, not budgeted here
			if String(cost[1]).begins_with("chunk_changed"):
				continue
			if float(cost[0]) > worst:
				worst = float(cost[0])
				worst_step = String(cost[1])
			if facility.current_chunk_data().is_empty() or not facility._loaded.has(facility.current_chunk_coord()):
				missing_under += 1
	var jump := 0.0
	var jump_moves: Array = [Vector3(-3 * size, 0, 0)] if city else [Vector3(0, StreamedFacilityView3D.LEVEL_HEIGHT, 0), Vector3(5 * size, 0, 0)]
	for move in jump_moves:
		player.global_position += move
		var t0 := Time.get_ticks_usec()
		facility._refresh_stream(false)
		jump = maxf(jump, (Time.get_ticks_usec() - t0) / 1000.0)
		_expect(facility._loaded.has(facility.current_chunk_coord()), "%s: the chunk under the runner was not built on a jump" % label)
		for _i in 3000:
			await host.get_tree().process_frame
			if not facility.is_streaming():
				break
		_expect(not facility.is_streaming(), "%s: the stream queue did not drain within 3000 frames after a jump" % label)
		var wanted := facility._wanted_chunks(facility.current_chunk_coord())
		for coord in wanted:
			_expect(facility._loaded.has(coord), "%s: wanted chunk %s never loaded" % [label, coord])
	_expect(worst <= MAX_STREAM_CPU_MS, "%s: %.1f ms of streaming in one frame (budget %.1f, step %s)" % [label, worst, MAX_STREAM_CPU_MS, worst_step])
	_expect(jump <= MAX_JUMP_MS, "%s: a level change/teleport spent %.0f ms building chunks (budget %.0f)" % [label, jump, MAX_JUMP_MS])
	_expect(missing_under == 0, "%s: %d frames with no chunk loaded under the runner" % [label, missing_under])
	print("  stream_perf %s  worst stream frame %.1f ms (%s), jump %.0f ms, %d loaded" % [label, worst, worst_step, jump, facility.loaded_chunk_count()])
	scene.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame


func _check_bench(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	_expect(parsed is Dictionary, "STREAM_BENCH_JSON %s is not a bench result" % path)
	if not parsed is Dictionary:
		return
	var summary: Dictionary = parsed["summary"]
	_expect(float(summary["stream_max_ms"]) <= BENCH_MAX_STREAM_FRAME_MS,
		"bench %s: a streaming frame took %.1f ms (budget %.1f)" % [summary["tag"], summary["stream_max_ms"], BENCH_MAX_STREAM_FRAME_MS])
	print("  stream_perf bench %s  stream max %.1f ms, p99 %.1f ms" % [summary["tag"], summary["stream_max_ms"], summary["p99_ms"]])


## Down and up a real ladder near the spawn three times, holding a few seconds at each end.
func _ladder(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "STREAM-BENCH"
	var scene: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(scene)
	var facility: StreamedFacilityView3D = scene.get_node("%StreamedFacility")
	var player: PlayerController3D = scene.get_node("%Player")
	for _i in 10:
		await host.get_tree().process_frame
	player.admin_god_mode = true
	player.set_physics_process(false)
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var top := Vector3.INF
	for z in range(-3, 4):
		for x in range(-3, 4):
			var links: Array = facility.generator.sewer().links_for(Vector3i(x, 0, z))
			if top == Vector3.INF and not links.is_empty():
				var cell: Vector2i = links[0]["from_cell"]
				top = Vector3(x * size + cell.x + .5, .05, z * size + cell.y + .5)
	_expect(top != Vector3.INF, "ladder: no sewer ladder within three chunks of the spawn")
	if top == Vector3.INF:
		scene.queue_free()
		return
	var bottom := top + Vector3(0, SewerRouteGenerator.LEVEL * StreamedFacilityView3D.LEVEL_HEIGHT, 0)
	player.global_position = top
	for _i in 300:
		await host.get_tree().process_frame
		if not facility.is_streaming():
			break
	var worst := 0.0
	var worst_trip := 0
	var rebuilds := 0
	for trip in 6:
		var from := top if trip % 2 == 0 else bottom
		var to := bottom if trip % 2 == 0 else top
		var builds_before := facility.chunk_builds
		var last := Time.get_ticks_usec()
		for i in 120:   # climb over 2 s at 60 frames
			player.global_position = from.lerp(to, float(i + 1) / 120.0)
			await host.get_tree().process_frame
			var now := Time.get_ticks_usec()
			if (now - last) / 1000.0 > worst:
				worst = (now - last) / 1000.0
				worst_trip = trip
			last = now
		for i in 180:   # and stay 3 s
			await host.get_tree().process_frame
			var now := Time.get_ticks_usec()
			if (now - last) / 1000.0 > worst:
				worst = (now - last) / 1000.0
				worst_trip = trip
			last = now
		if trip >= 2:
			rebuilds += facility.chunk_builds - builds_before
		_expect(facility.current_level() == (SewerRouteGenerator.LEVEL if trip % 2 == 0 else 0),
			"ladder: trip %d did not change the runner's level" % trip)
	_expect(worst <= MAX_LADDER_FRAME_MS, "ladder: a %.0f ms frame around a level change (trip %d, budget %.0f)" % [worst, worst_trip, MAX_LADDER_FRAME_MS])
	_expect(rebuilds == 0, "ladder: climbing back and forth rebuilt %d chunks (the left storey should be parked)" % rebuilds)
	print("  stream_perf ladder  worst frame %.1f ms (trip %d), rebuilds after the first round trip %d, %d parked" % [
		worst, worst_trip, rebuilds, facility.dormant_chunk_count()])
	scene.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame


## Down and up a walkable ramp tunnel between the two sewers three times (docs/SEWERS.md). A walk has no pause at the
## level boundary, so the far storey must already be streaming when the runner reaches it: the same frame and
## no-rebuild budgets as the ladder.
func _ramp(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "STREAM-BENCH"
	var scene: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(scene)
	var facility: StreamedFacilityView3D = scene.get_node("%StreamedFacility")
	var player: PlayerController3D = scene.get_node("%Player")
	for _i in 10:
		await host.get_tree().process_frame
	player.admin_god_mode = true
	player.set_physics_process(false)
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var ramp := {}
	var column := Vector2i.ZERO
	for z in range(-3, 4):
		for x in range(-3, 4):
			if ramp.is_empty():
				ramp = facility.generator.sewer().ramp_between(x, z, SewerRouteGenerator.LEVEL)
				column = Vector2i(x, z)
	_expect(not ramp.is_empty(), "ramp: no sewer ramp within three chunks of the spawn")
	if ramp.is_empty():
		scene.queue_free()
		return
	var height := StreamedFacilityView3D.LEVEL_HEIGHT
	var top_cell: Vector2i = ramp["link"]["from_cell"]
	var bottom_cell: Vector2i = ramp["link"]["to_cell"]
	var top := Vector3(column.x * size + top_cell.x + .5, SewerRouteGenerator.LEVEL * height + .05, column.y * size + top_cell.y + .5)
	var bottom := Vector3(column.x * size + bottom_cell.x + .5, SewerRouteGenerator.LOWER_LEVEL * height + .05,
		column.y * size + bottom_cell.y + .5)
	player.global_position = top
	facility.refresh_at_tracked_player()
	for _i in 300:
		await host.get_tree().process_frame
		if not facility.is_streaming():
			break
	var worst := 0.0
	var worst_trip := 0
	var rebuilds := 0
	for trip in 6:
		var from := top if trip % 2 == 0 else bottom
		var to := bottom if trip % 2 == 0 else top
		var builds_before := facility.chunk_builds
		var last := Time.get_ticks_usec()
		for i in 300:   # walk the 15 m over 5 s, then wait 2 s at the far landing
			player.global_position = from.lerp(to, float(i + 1) / 300.0)
			await host.get_tree().process_frame
			var now := Time.get_ticks_usec()
			if (now - last) / 1000.0 > worst:
				worst = (now - last) / 1000.0
				worst_trip = trip
			last = now
		for i in 120:
			await host.get_tree().process_frame
			var now := Time.get_ticks_usec()
			if (now - last) / 1000.0 > worst:
				worst = (now - last) / 1000.0
				worst_trip = trip
			last = now
		if trip >= 2:
			rebuilds += facility.chunk_builds - builds_before
		_expect(facility.current_level() == (SewerRouteGenerator.LOWER_LEVEL if trip % 2 == 0 else SewerRouteGenerator.LEVEL),
			"ramp: trip %d did not change the runner's level" % trip)
	_expect(worst <= MAX_LADDER_FRAME_MS, "ramp: a %.0f ms frame around a level change (trip %d, budget %.0f)" % [worst, worst_trip, MAX_LADDER_FRAME_MS])
	_expect(rebuilds == 0, "ramp: walking back and forth rebuilt %d chunks (the left storey should be parked)" % rebuilds)
	print("  stream_perf ramp  worst frame %.1f ms (trip %d), rebuilds after the first round trip %d, %d parked" % [
		worst, worst_trip, rebuilds, facility.dormant_chunk_count()])
	scene.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame


func run(host: Node) -> int:
	await _drive(host, false)
	await _ladder(host)
	await _ramp(host)
	var bench := OS.get_environment("STREAM_BENCH_JSON")
	if bench != "":
		for path in bench.split(","):
			_check_bench(path)
	return _failures
