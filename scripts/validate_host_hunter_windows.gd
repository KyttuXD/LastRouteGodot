extends RefCounted

## Host hunter windows round remote runners (InfiniteRouteTest._refresh_hunter_stream): when a teammate walks onto
## ground nobody has generated, the host must not generate their window's chunks on the main thread. Each refresh
## stays cheap, the worker generates the window, and the teammate's window joins the hunter stream once it is ready.
## Prints the main-thread cost of each refresh as a remote runner keeps moving into new chunks.
##
##   godot --headless --path . res://scenes/validate.tscn -- host_hunter_windows

const MAX_REFRESH_MS := 25.0   # main took ~320 ms; typical is 0.2 ms, the margin covers a loaded test machine

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "HOSTWINDOWS"
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 30:
		await host.get_tree().process_frame
	var facility: StreamedFacilityView3D = route.facility
	var remotes = route._remotes
	var own: Vector3i = facility.current_chunk_coord()
	var size := float(StreamedRouteGenerator.CHUNK_SIZE)
	var costs: Array = []
	var joined := 0
	# a teammate (peer 2) runs east across fresh chunks, one chunk per step, 8 to 15 chunks from this host
	for step in 8:
		var chunk := own + Vector3i(8 + step, 0, 0)
		remotes._states[2] = {"position": Vector2((chunk.x + .5) * size, (chunk.z + .5) * size), "depth": -chunk.y,
			"received_usec": Time.get_ticks_usec()}
		var t := Time.get_ticks_usec()
		route._refresh_hunter_stream()
		costs.append(snappedf((Time.get_ticks_usec() - t) / 1000.0, .1))
		# the host's authority tick keeps refreshing while the worker generates
		for _i in 300:
			await host.get_tree().process_frame
			remotes._states[2]["received_usec"] = Time.get_ticks_usec()
			if not route._hunter_stream_waiting:
				break
			var t2 := Time.get_ticks_usec()
			route._refresh_hunter_stream()
			costs.append(snappedf((Time.get_ticks_usec() - t2) / 1000.0, .1))
		var navigation := route._navigations.get(chunk.y) as StreamedHunterNavigation
		if navigation != null and navigation.active_coordinates().has(chunk):
			joined += 1
	var worst := 0.0
	for ms in costs:
		worst = maxf(worst, float(ms))
	print("  host_hunter_windows  %d refreshes while a teammate crossed 8 fresh chunks: worst %.1f ms, all %s; teammate's chunk in the hunter window %d of 8" % [
		costs.size(), worst, str(costs.slice(0, 24)), joined])
	_expect(worst <= MAX_REFRESH_MS, "a hunter-window refresh took %.1f ms on the main thread (generating a teammate's window?)" % worst)
	_expect(joined >= 6, "the teammate's chunk joined the hunter window only %d of 8 times" % joined)
	remotes._states.erase(2)
	route.queue_free()
	await host.get_tree().process_frame
	return _failures
