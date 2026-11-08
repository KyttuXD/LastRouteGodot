extends Node

## Salvage Run's map at 1280x720: a TOP-DOWN view of the whole ship and scrap yard (ceilings hidden), and the dock seen from the left gantry (docs/night_watch_modes/dayshift_map_topdown.png, dayshift_dock.png).
##   godot --path . res://dev/look/night_watch_dayshift_map_capture.tscn -- OUT_DIR

func _shot(path: String, frames := 10) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	NightWatchSession.start_mode("dayshift", 3, {}, 4242)
	var game := (load("res://game/night_watch/dayshift/night_watch_dayshift.tscn") as PackedScene).instantiate() as DayshiftGame
	game.manual_clock = true
	add_child(game)
	await get_tree().process_frame
	game.start_shift([])
	game.advance_ms(500.0)
	game.hud.visible = false
	# the dock from the gantry: Ravelle at the end of her walk
	game.player.global_position = Vector3(-3.5, 0.0, 0.0)
	game.face_player(PI * 0.5, 0.0)
	game.sim.s["ravelle"]["dist"] = 3
	game.advance_ms(50.0)
	await _shot(out + "/dayshift_dock.png")
	for node in game.find_children("*", "MeshInstance3D", true, false):
		if String(node.get_meta("nw_name", "")).begins_with("Ceiling"):
			(node as Node3D).visible = false
	game.world_env.environment.ambient_light_energy = 4.0
	game.world_env.environment.background_color = Color(0.12, 0.12, 0.18)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 58.0
	cam.position = Vector3(-2.0, 80.0, 3.0)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	cam.far = 200.0
	game.add_child(cam)
	cam.current = true
	await _shot(out + "/dayshift_map_topdown.png", 12)
	get_tree().quit()
