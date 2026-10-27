extends Node

## Screenshot rig for KYTTU: The City. Loads the City run scene, moves the runner to named spots and saves viewport PNGs.
##
##   godot --path . res://tools/look/city_capture.tscn -- OUTDIR TAG [SEED]
##
## Environment: CAP_ONLY=<substrings of the spot names, comma separated>, CAP_HUD=1 keeps the HUD, CAP_LIST=1 prints
## the spots, CAP_FPS=1 prints the frame time and draw calls of each spot.

var _out_dir := ""
var _tag := "city"
var _scene: Node
var _only := OS.get_environment("CAP_ONLY")
var _fps := OS.get_environment("CAP_FPS") != ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var positional := []
	for argument in args:
		if String(argument).begins_with("--only="):
			_only = String(argument).trim_prefix("--only=")
		elif String(argument) == "--fps":
			_fps = true
		else:
			positional.append(argument)
	_out_dir = positional[0] if positional.size() > 0 else "/tmp"
	_tag = positional[1] if positional.size() > 1 else "city"
	RoomState.create_local(RoomState.Mode.CITY)
	RoomState.seed_text = positional[2] if positional.size() > 2 else "CITY-LOOK"
	DirAccess.make_dir_recursive_absolute(_out_dir) if _out_dir.is_absolute_path() else DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out_dir))
	Backend.enable_offline_mode()
	if _fps:
		Settings.fps_limit = 0
		Settings.vsync_enabled = false
		Settings._apply_display_performance()
	_scene = load(RoomState.CITY_ROUTE_SCENE).instantiate()
	add_child(_scene)
	_run()


func _wait(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
		var pause = _scene.get("pause_menu")
		if pause != null and pause.has_method("close") and pause.is_open():
			pause.close()
		get_tree().paused = false


## City cell -> route metres.
static func _at(gx: float, gz: float) -> Vector3:
	return Vector3(gx - CityLayout.ORIGIN_OFFSET.x, .05, gz - CityLayout.ORIGIN_OFFSET.y)


func _spots(layout: CityLayout) -> Array:
	var spots := [
		{"name": "spawn_kiosk", "pos": _at(112.5, 80.5), "yaw": 0.0, "pitch": 0.0},
		{"name": "roundabout_to_north", "pos": _at(112.5, 84.5), "yaw": 0.0, "pitch": 3.0},
		{"name": "avenue_south_to_north", "pos": _at(112.5, 105.5), "yaw": 0.0, "pitch": 2.0},
		{"name": "avenue_north_to_south", "pos": _at(112.5, 44.5), "yaw": 180.0, "pitch": 2.0},
		{"name": "main_street_east", "pos": _at(60.5, 67.5), "yaw": -90.0, "pitch": 2.0},
		{"name": "grand_plaza", "pos": _at(112.5, 24.5), "yaw": 0.0, "pitch": 4.0},
		{"name": "garden", "pos": _at(82.5, 44.5), "yaw": 90.0, "pitch": -3.0},
		{"name": "shelter_plaza", "pos": _at(67.5, 33.5), "yaw": 0.0, "pitch": 0.0},
		{"name": "alley", "pos": _at(48.5, 43.5), "yaw": 90.0, "pitch": 0.0},
		{"name": "sky", "pos": _at(112.5, 84.5), "yaw": 0.0, "pitch": 62.0},
		{"name": "rim_gate", "pos": _at(112.5, 118.5), "yaw": 180.0, "pitch": 6.0},
	]
	# The spawn kiosk (the player starts at its centre): the start view, the four inside views, and outside at 3/8/20 m.
	spots.append({"name": "spawn_start", "pos": _at(112.5, 67.5), "yaw": 0.0, "pitch": 0.0})
	for yaw in [0, 90, 180, 270]:
		spots.append({"name": "spawn_in_y%03d" % yaw, "pos": _at(112.5, 67.5), "yaw": float(yaw), "pitch": 0.0})
	spots.append({"name": "spawn_in_up", "pos": _at(112.5, 67.5), "yaw": 0.0, "pitch": 70.0})
	spots.append({"name": "spawn_in_floor", "pos": _at(112.5, 67.5), "yaw": 180.0, "pitch": -60.0})
	spots.append({"name": "spawn_door", "pos": _at(112.5, 70.5), "yaw": 180.0, "pitch": 0.0})
	for distance in [3, 8, 20]:
		spots.append({"name": "spawn_out_s%02d" % distance, "pos": _at(112.5, 71.5 + distance), "yaw": 0.0, "pitch": 4.0})
		spots.append({"name": "spawn_out_n%02d" % distance, "pos": _at(112.5, 63.5 - distance), "yaw": 180.0, "pitch": 4.0})
		spots.append({"name": "spawn_out_e%02d" % distance, "pos": _at(116.5 + distance, 67.5), "yaw": 90.0, "pitch": 4.0})
		spots.append({"name": "spawn_out_w%02d" % distance, "pos": _at(108.5 - distance, 67.5), "yaw": -90.0, "pitch": 4.0})
	# Distance series: the main street looking east from d metres away from the end, the avenue looking north, the
	# skyline and the dome frame from the roundabout.
	for distance in [3, 15, 40, 100, 180]:
		spots.append({"name": "far_main_d%03d" % distance, "pos": _at(200.5 - distance, 67.5), "yaw": -90.0, "pitch": 2.0})
		spots.append({"name": "far_avenue_d%03d" % distance, "pos": _at(112.5, 120.5 - distance), "yaw": 0.0, "pitch": 2.0})
	for yaw in [0, 90, 180, 270]:
		spots.append({"name": "far_skyline_y%03d" % yaw, "pos": _at(112.5, 84.5), "yaw": float(yaw), "pitch": 9.0})
	spots.append({"name": "far_dome", "pos": _at(112.5, 84.5), "yaw": 30.0, "pitch": 38.0})
	if not layout.buildings.is_empty():
		var building: Dictionary = layout.buildings[0]
		var interior: Rect2i = building["interior"]
		var door: Vector2i = (building["doors"] as Array)[0]
		var middle := interior.position + interior.size / 2
		var toward := Vector2(door - middle)
		spots.append({"name": "interior", "pos": _at(middle.x + .5, middle.y + .5),
			"yaw": rad_to_deg(atan2(-toward.x, -toward.y)), "pitch": 0.0})
		spots.append({"name": "facade", "pos": _at(door.x + .5 + signf(toward.x) * 7.0, door.y + .5 + signf(toward.y) * 7.0),
			"yaw": rad_to_deg(atan2(toward.x, toward.y)), "pitch": 12.0})
	spots.append({"name": "gate_far", "pos": _at(112.5, 98.5), "yaw": 180.0, "pitch": 4.0})
	spots.append({"name": "gate_close", "pos": _at(112.5, 114.5), "yaw": 180.0, "pitch": 6.0})
	# One look inside a library, a chapel and a two-room building (from just inside the first doorway).
	var shown := {}
	for building_value in layout.buildings:
		var entry: Dictionary = building_value
		if bool(entry.get("sealed", false)):
			continue
		var tag := String(entry["kind"])
		if not (entry["partition"] as Array).is_empty() and not shown.has("tworoom"):
			tag = "tworoom"
		elif tag != "library" and tag != "chapel":
			continue
		if shown.has(tag):
			continue
		shown[tag] = true
		var room: Rect2i = entry["interior"]
		var entry_door: Vector2i = (entry["doors"] as Array)[0]
		var centre := room.position + room.size / 2
		var inward := Vector2(centre - entry_door)
		var start := Vector2(entry_door) + inward.normalized() * 2.0
		spots.append({"name": "inside_%s" % tag, "pos": _at(start.x + .5, start.y + .5),
			"yaw": rad_to_deg(atan2(-inward.x, -inward.y)), "pitch": 0.0})
	return spots


func _run() -> void:
	await _wait(40)
	var facility := _scene.get_node("%StreamedFacility") as StreamedFacilityView3D
	var player := _scene.get_node("%Player") as PlayerController3D
	if OS.get_environment("CAP_HUD") == "":
		_scene.get_node("%HUD").visible = false
	var layout := (facility.generator as CityRouteGenerator).layout
	var spots := _spots(layout)
	if OS.get_environment("CAP_LIST") != "":
		for spot in spots:
			print(spot["name"], " ", spot["pos"])
	var only := _only
	for spot in spots:
		if only != "":
			var wanted := false
			for part in only.split(","):
				if String(spot["name"]).contains(part):
					wanted = true
			if not wanted:
				continue
		player.global_position = spot["pos"]
		player._yaw = deg_to_rad(float(spot["yaw"]))
		player._pitch = deg_to_rad(float(spot["pitch"]))
		player._apply_look_rotation()
		facility.refresh_at_tracked_player()
		await _wait(24)
		if _fps:
			var t0 := Time.get_ticks_usec()
			await _wait(60)
			print("%s: %.1f fps, %d draw calls, %d objects" % [spot["name"],
				60.0 / ((Time.get_ticks_usec() - t0) / 1e6),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
			continue
		var image := get_viewport().get_texture().get_image()
		image.save_png("%s/%s_%s.png" % [_out_dir, _tag, spot["name"]])
		print("saved %s" % spot["name"])
	get_tree().quit()
