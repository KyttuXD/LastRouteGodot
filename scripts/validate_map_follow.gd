extends RefCounted

## The full-screen map follows the runner: it opens centred on them, glides after them while open (smooth, never overshooting),
## a manual pan (drag / stick / arrows / touch) stops following, RECENTER restores it, zooming while following keeps them
## centred, pinch zooms on touch, and the zoom is remembered between opens.
##
##   godot --headless --path . res://scenes/validate.tscn -- map_follow

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _map(host: Node) -> FacilityMap:
	var map := FacilityMap.new()
	map.interactive = true
	map.size = Vector2(400, 220)
	host.add_child(map)
	return map


func _at(map: FacilityMap, at: Vector2) -> void:
	map.show_streamed_state({Vector3i(0, 0, 0): {"region": "maze"}, Vector3i(1, 0, 1): {"region": "maze"}}, 0, 16, at, Vector2.RIGHT, [])


func run(host: Node) -> int:
	var old_zoom := FacilityMap.remembered_zoom
	FacilityMap.remembered_zoom = 1.0
	var map := _map(host)
	await host.get_tree().process_frame
	_at(map, Vector2(10, 5))
	map.recenter(true)
	_expect(map.follow_player and map.view_center() == Vector2(10, 5), "the map did not open on the runner: %s" % map.view_center())
	# follow: glides after the runner, closer every frame, never past them
	_at(map, Vector2(20, 9))
	var last := map.view_center().distance_to(Vector2(20, 9))
	map._process(1.0 / 60.0)
	var first := map.view_center().distance_to(Vector2(20, 9))
	_expect(first < last and first > 0.0, "the follow jumped instead of gliding (%.3f -> %.3f)" % [last, first])
	for _i in 120:
		var before := map.view_center().distance_to(Vector2(20, 9))
		map._process(1.0 / 60.0)
		_expect(map.view_center().distance_to(Vector2(20, 9)) <= before + 0.0001, "the follow jittered away from the runner")
	_expect(map.view_center().distance_to(Vector2(20, 9)) < 0.05, "the follow did not reach the runner: %s" % map.view_center())
	# zoom while following keeps the runner centred
	map.zoom_at(1.5, Vector2(30, 30))
	_expect(map.view_center().distance_to(Vector2(20, 9)) < 0.05 and map.follow_player, "zooming moved the view off the runner")
	# the player arrow keeps a constant on-screen size on the full map at the smallest and largest zoom
	for zoom in [FacilityMap.MIN_MAP_ZOOM, 1.0, FacilityMap.MAX_MAP_ZOOM]:
		var reach := FacilityMap.arrow_reach(map._base_cell_scale * zoom, true)
		_expect(reach >= FacilityMap.PLAYER_ARROW_MIN and reach <= FacilityMap.PLAYER_ARROW_MAX,
			"the full-map arrow is %.1f units at zoom %.2f (keep %.0f..%.0f)" % [reach, zoom, FacilityMap.PLAYER_ARROW_MIN, FacilityMap.PLAYER_ARROW_MAX])
	_expect(is_equal_approx(FacilityMap.arrow_reach(40.0, true), FacilityMap.arrow_reach(2.0, true)), "the full-map arrow grows with zoom")
	_expect(FacilityMap.arrow_reach(40.0, true) <= 40.0, "the zoomed-in arrow is bigger than a cell")
	# manual pan stops following
	map.pan_screen(Vector2(40, 0))
	_expect(not map.follow_player, "panning did not turn follow off")
	var parked := map.view_center()
	_at(map, Vector2(30, 12))
	for _i in 30:
		map._process(1.0 / 60.0)
	_expect(map.view_center() == parked, "the map kept following after a pan")
	# recenter restores follow
	map.recenter()
	_expect(map.follow_player, "recenter did not turn follow back on")
	for _i in 180:
		map._process(1.0 / 60.0)
	_expect(map.view_center().distance_to(Vector2(30, 12)) < 0.05, "recenter did not bring the runner back to the centre")
	# touch: one-finger drag pans (stops follow), two-finger pinch zooms
	map.recenter(true)
	var zoom_before := map.map_zoom
	for index in [0, 1]:
		var touch := InputEventScreenTouch.new()
		touch.index = index
		touch.pressed = true
		touch.position = Vector2(150 + index * 40, 100)
		map._gui_input(touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = Vector2(270, 100)
	map._gui_input(drag)
	_expect(map.map_zoom > zoom_before, "a pinch did not zoom in (%.2f -> %.2f)" % [zoom_before, map.map_zoom])
	for index in [0, 1]:
		var up := InputEventScreenTouch.new()
		up.index = index
		up.pressed = false
		map._gui_input(up)
	# the zoom is remembered for the next map
	var zoom_now := map.map_zoom
	map.queue_free()
	var reopened := _map(host)
	await host.get_tree().process_frame
	_expect(is_equal_approx(reopened.map_zoom, zoom_now), "the zoom was not remembered (%.2f vs %.2f)" % [reopened.map_zoom, zoom_now])
	reopened.queue_free()
	# the HUD opens the map on the runner with RECENTER hidden until a pan
	var hud := (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	host.add_child(hud)
	await host.get_tree().process_frame
	var plan: FacilityMap = hud.get("plan")
	_at(plan, Vector2(7, 7))
	hud.call("set_map_open", true)
	await host.get_tree().process_frame
	_expect(plan.follow_player and plan.view_center() == Vector2(7, 7), "opening the HUD map did not centre on the runner")
	var button := hud.find_child("RecenterButton", true, false) as Button
	_expect(button == null or not button.visible, "RECENTER shows while following")
	plan.pan_screen(Vector2(25, 10))
	await host.get_tree().process_frame
	button = hud.find_child("RecenterButton", true, false) as Button
	_expect(button != null and button.visible and button.text.ends_with("RECENTER"), "RECENTER is not offered after a pan")
	if button != null:
		button.pressed.emit()
	_expect(plan.follow_player, "the RECENTER button did not turn follow back on")
	hud.call("set_map_open", false)
	hud.queue_free()
	FacilityMap.remembered_zoom = old_zoom
	await host.get_tree().process_frame
	if _failures == 0:
		print("  mapfollow full map opens on the runner, glides after them, pan stops / RECENTER resumes, pinch zoom, zoom remembered")
	return _failures
