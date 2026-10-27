extends Node

## Mixed Shift's transit hub at 1280x720, top-down (ceilings hidden), once per nightly dressing: mixed_map_station.png, mixed_map_party.png, mixed_map_yard.png (docs/night_watch_modes/).
##   godot --path . res://tools/look/night_watch_mixed_map_capture.tscn -- OUT_DIR

func _shot(path: String, frames := 12) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	var names := ["station", "party", "yard"]
	for s in 3:
		NightWatchSession.start_mode("mixed", 2, {}, 3 + s)
		var game := (load("res://scenes/night_watch_mixed.tscn") as PackedScene).instantiate() as MixedGame
		game.manual_clock = true
		add_child(game)
		await get_tree().process_frame
		game.hud.visible = false
		for node in game.find_children("*", "MeshInstance3D", true, false):
			if String(node.get_meta("nw_name", "")).begins_with("Ceiling"):
				(node as Node3D).visible = false
		game.world_env.environment.ambient_light_energy = 4.0
		game.world_env.environment.background_color = Color(0.12, 0.12, 0.18)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 66.0
		cam.position = Vector3(0.0, 80.0, -16.0)
		cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		cam.far = 200.0
		game.add_child(cam)
		cam.current = true
		await _shot(out + "/mixed_map_%s.png" % names[s])
		game.queue_free()
		await get_tree().process_frame
	get_tree().quit()
