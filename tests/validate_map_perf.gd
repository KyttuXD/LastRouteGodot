extends RefCounted

## Full-map performance contracts (the admin map reveal and region overlay are the heavy case):
##  - an open full map with nothing changing queues no picture (feeds at 20 Hz, or every frame on HIGH, cost nothing idle);
##  - a moving runner still redraws every frame;
##  - the full map draws a chunk as one cached mesh, so the draw count per redraw stays bounded with the reveal and the
##    region overlay on (the old per-cell draws were 40-60k a redraw);
##  - the chunk meshes rebuild only for a chunk whose content changed, never on an unchanged feed;
##  - the admin reveal survey adds only chunks it has not seen (the old survey rebuilt all 81 on every crossing).
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- map_perf

## Draw calls one full-map redraw may issue with the reveal and the region overlay on, 81 chunks. Measured headless about 260: two
## meshes a chunk (static layer, dots), the region lines and the marks. The per-cell draw it replaces issued ~58k.
const REVEAL_DRAW_BOUND := 600
const SIDE := StreamedRouteGenerator.CHUNK_SIZE

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


## A synthetic chunk: a lattice of walls with a solid prop (its collision box) and a sewer water strip in some chunks.
func _chunk(region: String, salt: int) -> Dictionary:
	var walls := PackedByteArray()
	walls.resize(SIDE * SIDE)
	for z in SIDE:
		for x in SIDE:
			walls[z * SIDE + x] = 1 if ((x * 7 + z * 13 + salt) % 5 == 0 or x == 0 or z == 0) else 0
	var water := PackedByteArray()
	water.resize(SIDE * SIDE)
	if salt % 4 == 0:
		for x in SIDE:
			water[10 * SIDE + x] = 1
	var box := PackedFloat32Array([4.0, 4.0, 1.0, 0.5, 0.0])
	return {"walls": walls, "water": water, "region": region, "stairs": [], "ladders": [],
		"spawn": Vector2i(-1, -1),
		"pickups": [{"id": "relay_%d" % salt, "kind": "relay", "cell": Vector2i(30, 12)}],
		"props": [{"id": "prop_%d" % salt, "kind": "prop", "cell": Vector2i(3, 3), "boxes": [box]},
			{"id": "decor_%d" % salt, "kind": "fixture", "cell": Vector2i(20, 20)}]}


func _synthetic_map(host: Node) -> FacilityMap:
	var map := FacilityMap.new()
	map.interactive = true
	map.size = Vector2(640, 360)
	host.add_child(map)
	return map


func _check_full_map_redraws(host: Node) -> void:
	var chunks := {}
	var regions := ["maze", "hotel", "prison", "lab", "beach"]
	for z in 5:
		for x in 5:
			chunks[Vector3i(x, 0, z)] = _chunk(regions[(x + z) % regions.size()], x * 5 + z)
	var map := _synthetic_map(host)
	var at := Vector2(2.5 * SIDE, 2.5 * SIDE)
	FacilityMap.perf_probe = true
	map.perf_redraws = 0
	map.perf_mesh_builds = 0
	map.show_streamed_state(chunks, 0, SIDE, at, Vector2.DOWN, [], false, 0, [], true, [], [])
	for _i in 10:
		await host.get_tree().process_frame
	# one feed after the layout settled (the first one after a resize queues the picture once); then idle
	map.show_streamed_state(chunks, 0, SIDE, at, Vector2.DOWN, [], false, 0, [], true, [], [])
	await host.get_tree().process_frame
	# idle: the same feed again and again, the runner still, the picture unchanged
	var idle_before := map.perf_redraws
	for _i in 60:
		map.show_streamed_state(chunks, 0, SIDE, at, Vector2.DOWN, [], false, 0, [], true, [], [])
		await host.get_tree().process_frame
	var idle_redraws := map.perf_redraws - idle_before
	_expect(idle_redraws == 0, "an open full map with nothing changing redrew %d times in 60 frames" % idle_redraws)
	# moving: a new position each frame redraws each frame
	var moving_before := map.perf_redraws
	for i in 30:
		map.show_streamed_state(chunks, 0, SIDE, at + Vector2(i * 0.05, 0.0), Vector2.DOWN, [], false, 0, [], true, [], [])
		await host.get_tree().process_frame
	var moving_redraws := map.perf_redraws - moving_before
	print("  map_perf  synthetic: %d idle frames gave %d redraws; %d moving frames gave %d" % [60, idle_redraws, 30, moving_redraws])
	_expect(moving_redraws >= 28, "a moving runner redrew only %d times in 30 frames" % moving_redraws)
	# the cached layer: no rebuild on an unchanged feed, one per changed chunk, every chunk on a region-overlay change
	_expect(map.perf_mesh_builds == 25 and map.perf_dot_builds == 25,
		"the first full-map draw built %d chunk meshes and %d dot meshes, not 25 and 25" % [map.perf_mesh_builds, map.perf_dot_builds])
	map.perf_mesh_builds = 0
	map.perf_dot_builds = 0
	map.show_streamed_state(chunks, 0, SIDE, at, Vector2.DOWN, [], false, 0, [], true, [], [])
	map.queue_redraw()
	await host.get_tree().process_frame
	_expect(map.perf_mesh_builds == 0 and map.perf_dot_builds == 0,
		"an unchanged feed rebuilt %d chunk meshes and %d dot meshes" % [map.perf_mesh_builds, map.perf_dot_builds])
	# a zoom step changes the cell size: the dots (radius held to a pixel size) are rebuilt, the static layer is not
	map.zoom_at(1.22)
	await host.get_tree().process_frame
	_expect(map.perf_dot_builds == 25 and map.perf_mesh_builds == 0,
		"a zoom step rebuilt %d dot meshes and %d chunk meshes, not 25 and 0" % [map.perf_dot_builds, map.perf_mesh_builds])
	map.perf_dot_builds = 0
	# a pickup taken: that chunk's dots only
	var taken: Dictionary = chunks[Vector3i(2, 0, 2)]
	chunks[Vector3i(2, 0, 2)] = taken.merged({"pickups": []}, true)
	map.show_streamed_state(chunks, 0, SIDE, at, Vector2.DOWN, [], false, 0, [], true, [], [])
	await host.get_tree().process_frame
	_expect(map.perf_dot_builds == 1 and map.perf_mesh_builds == 0,
		"a pickup taken rebuilt %d dot meshes and %d chunk meshes, not 1 and 0" % [map.perf_dot_builds, map.perf_mesh_builds])
	map.perf_dot_builds = 0
	map.perf_mesh_builds = 0
	chunks[Vector3i(5, 0, 0)] = _chunk("maze", 99)
	map.show_streamed_state(chunks, 0, SIDE, at, Vector2.DOWN, [], false, 0, [], true, [], [])
	await host.get_tree().process_frame
	_expect(map.perf_mesh_builds == 1 and map.perf_dot_builds == 1,
		"a newly discovered chunk rebuilt %d meshes and %d dot meshes, not 1 and 1" % [map.perf_mesh_builds, map.perf_dot_builds])
	map.perf_mesh_builds = 0
	var changed: Dictionary = chunks[Vector3i(1, 0, 1)]
	var walls: PackedByteArray = (changed["walls"] as PackedByteArray).duplicate()
	walls[5] = 1 - walls[5]
	chunks[Vector3i(1, 0, 1)] = changed.merged({"walls": walls}, true)
	map.show_streamed_state(chunks, 0, SIDE, at, Vector2.DOWN, [], false, 0, [], true, [], [])
	await host.get_tree().process_frame
	_expect(map.perf_mesh_builds == 1, "one changed chunk rebuilt %d meshes, not 1" % map.perf_mesh_builds)
	map.perf_mesh_builds = 0
	map.show_streamed_state(chunks, 0, SIDE, at, Vector2.DOWN, [], false, 0, [], false, [], [])
	await host.get_tree().process_frame
	_expect(map.perf_mesh_builds == chunks.size(), "turning the region overlay off rebuilt %d meshes, not %d" % [map.perf_mesh_builds, chunks.size()])
	# the draw count per redraw: one mesh per chunk in view, no per-cell rects, and the dynamic marks on top
	map.show_streamed_state(chunks, 0, SIDE, at, Vector2.DOWN, [], false, 0, [], true, [], [])
	map.perf_redraws = 0
	map.perf_draws = 0
	map.perf_draw_usec = 0
	map.perf_by_kind = {}
	map.queue_redraw()
	for _i in 3:
		await host.get_tree().process_frame
	var redraws := maxi(1, map.perf_redraws)
	var per_redraw := float(map.perf_draws) / redraws
	var meshes := float(int(map.perf_by_kind.get("chunk_mesh", 0))) / redraws
	var dots := float(int(map.perf_by_kind.get("chunk_dots", 0))) / redraws
	print("  map_perf  synthetic %d chunks, reveal + regions: %.0f draw calls and %.2f ms CPU a redraw, %.0f chunk meshes, %.0f dot meshes (%s)" % [
		chunks.size(), per_redraw, float(map.perf_draw_usec) / 1000.0 / redraws, meshes, dots, str(map.perf_by_kind)])
	_expect(int(map.perf_by_kind.get("wall_rect", 0)) == 0 and int(map.perf_by_kind.get("prop_circle", 0)) == 0
		and int(map.perf_by_kind.get("pickup_circle", 0)) == 0, "the full map still draws cells, decor or pickups one by one")
	_expect(is_equal_approx(meshes, chunks.size()) and is_equal_approx(dots, chunks.size()),
		"%.0f chunk meshes and %.0f dot meshes drawn for %d chunks" % [meshes, dots, chunks.size()])
	_expect(per_redraw <= chunks.size() * 6 + 60, "a full-map redraw issued %.0f draw calls for %d chunks" % [per_redraw, chunks.size()])
	map.queue_free()
	await host.get_tree().process_frame


## The real route: the reveal survey is incremental, and the open full map with the reveal and the region overlay on draws a
## bounded number of calls, with the walls and dots in chunk meshes. The map is fed here by calling the route's feed each frame:
## in this headless route instance the route's frame loop never reaches the feed (its pause_menu stays null), so it is called directly.
func _check_route_reveal(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var route: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 8:
		await host.get_tree().process_frame
	# the survey: a second pass over the same survey area remembers nothing again
	route._set_admin_map_reveal(true)
	var surveyed: int = route._discovered_chunks.size()
	_expect(surveyed >= 9, "the reveal surveyed only %d chunks" % surveyed)
	for coord in route._discovered_chunks:
		(route._discovered_chunks[coord] as Dictionary)["_survey_seen"] = true
	route._set_admin_map_reveal(true)
	var rebuilt := 0
	for coord in route._discovered_chunks:
		if not (route._discovered_chunks[coord] as Dictionary).has("_survey_seen"):
			rebuilt += 1
	_expect(rebuilt == 0, "the survey rebuilt %d of %d chunks it had already seen" % [rebuilt, surveyed])
	# one chunk forgotten (the runner's own chunk): the next survey puts that one back and rebuilds nothing else
	var center: Vector3i = route.facility.current_chunk_coord()
	route._discovered_chunks.erase(center)
	route._set_admin_map_reveal(true)
	_expect(route._discovered_chunks.size() == surveyed and route._discovered_chunks.has(center),
		"the survey did not put back the one missing chunk (%d chunks, %d expected)" % [route._discovered_chunks.size(), surveyed])
	var unseen := 0
	for coord in route._discovered_chunks:
		if coord != center and not (route._discovered_chunks[coord] as Dictionary).has("_survey_seen"):
			unseen += 1
	_expect(unseen == 0, "the survey rebuilt %d chunks that were already known" % unseen)
	# the open full map with the reveal and the region overlay: fed each frame, then measured
	route._admin_region_map = true
	route.hud.set_map_open(true)
	FacilityMap.perf_probe = true
	var plan: FacilityMap = route.hud.plan
	for _i in 20:
		route._update_streamed_maps()
		await host.get_tree().process_frame
	_expect(plan.streamed_chunks.size() == route._discovered_chunks.size(),
		"the open full map shows %d of %d discovered chunks" % [plan.streamed_chunks.size(), route._discovered_chunks.size()])
	plan.perf_redraws = 0
	plan.perf_draws = 0
	plan.perf_by_kind = {}
	plan.perf_mesh_builds = 0
	plan.perf_dot_builds = 0
	plan.perf_draw_usec = 0
	plan.queue_redraw()
	for _i in 3:
		await host.get_tree().process_frame
	var redraws := maxi(1, plan.perf_redraws)
	var per_redraw := float(plan.perf_draws) / redraws
	print("  map_perf  reveal %d chunks, %.0f draw calls per full-map redraw (%s)" % [route._discovered_chunks.size(), per_redraw, str(plan.perf_by_kind)])
	_expect(int(plan.perf_by_kind.get("wall_rect", 0)) == 0 and int(plan.perf_by_kind.get("prop_circle", 0)) == 0
		and int(plan.perf_by_kind.get("pickup_circle", 0)) == 0, "the full map with the reveal still draws cells, decor or pickups one by one")
	_expect(per_redraw <= REVEAL_DRAW_BOUND, "the full map with the reveal and region overlay issued %.0f draw calls a redraw (bound %d)" % [per_redraw, REVEAL_DRAW_BOUND])
	var first_ms := float(plan.perf_draw_usec) / 1000.0 / redraws
	# steady state: the static layer and the dots are cached now, so a redraw is the draw calls alone
	plan.perf_draw_usec = 0
	plan.perf_redraws = 0
	plan.queue_redraw()
	await host.get_tree().process_frame
	var steady_ms := float(plan.perf_draw_usec) / 1000.0 / maxi(1, plan.perf_redraws)
	print("  map_perf  live route full map: %.2f ms CPU a redraw steady (first redraw, which builds the meshes: %.2f ms)" % [steady_ms, first_ms])
	# informational: the live map fed each frame with the runner standing still (hunters still move, so this is not an idle picture)
	var live_before := plan.perf_redraws
	var feed_usec := 0
	for _i in 30:
		var feed_started := Time.get_ticks_usec()
		route._update_streamed_maps()
		feed_usec += Time.get_ticks_usec() - feed_started
		await host.get_tree().process_frame
	print("  map_perf  live route: %d full-map redraws in 30 frames, runner still (hunters move); feed %.2f ms a tick with the full map open and the reveal on" % [
		plan.perf_redraws - live_before, float(feed_usec) / 1000.0 / 30.0])
	# informational: which parts of a still feed change between frames (a redraw needs one of them to change)
	route.set_process(false)
	route.player.set_physics_process(false)
	await host.get_tree().process_frame
	var names := ["structural", "soft", "view_center", "size", "zoom", "player_at", "player_facing"]
	var before_parts := [plan._structural_key(), plan._soft_key(), plan._view_center, plan.size, plan.map_zoom, plan.player_at, plan.player_facing]
	var changed := {}
	var redraws_still := plan.perf_redraws
	for _i in 10:
		route._update_streamed_maps()
		await host.get_tree().process_frame
		var parts := [plan._structural_key(), plan._soft_key(), plan._view_center, plan.size, plan.map_zoom, plan.player_at, plan.player_facing]
		for index in parts.size():
			if parts[index] != before_parts[index]:
				changed[names[index]] = int(changed.get(names[index], 0)) + 1
		before_parts = parts
	print("  map_perf  still feed, scene process off: %d redraws in 10 frames; parts that changed: %s" % [plan.perf_redraws - redraws_still, str(changed)])
	route.set_process(true)
	route.player.set_physics_process(true)
	route.hud.set_map_open(false)
	FacilityMap.perf_probe = false
	route._admin_region_map = false
	route._set_admin_map_reveal(false)
	route.queue_free()
	await host.get_tree().process_frame


func run(host: Node) -> int:
	var old_zoom := FacilityMap.remembered_zoom
	FacilityMap.remembered_zoom = 1.0
	await _check_full_map_redraws(host)
	await _check_route_reveal(host)
	FacilityMap.perf_probe = false
	FacilityMap.remembered_zoom = old_zoom
	if _failures == 0:
		print("  map_perf  full map: idle no redraw, moving redraws, one mesh per chunk, rebuilds only on change, reveal survey incremental")
	return _failures
