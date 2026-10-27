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


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() > 0 else "/tmp"
	_tag = args[1] if args.size() > 1 else "city"
	RoomState.create_local(RoomState.Mode.CITY)
	RoomState.seed_text = args[2] if args.size() > 2 else "CITY-LOOK"
	Backend.enable_offline_mode()
	if OS.get_environment("CAP_FPS") != "":
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
	var only := OS.get_environment("CAP_ONLY")
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
		if OS.get_environment("CAP_FPS") != "":
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
