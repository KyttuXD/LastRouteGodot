extends Node

## Top-down captures of The Descent's and Open Air's maps at 1280x720 (docs/night_watch_modes/):
##   godot --path . res://dev/look/night_watch_maps_c_capture.tscn -- OUT_DIR
## writes 1280x720_map_descent_top.png, _map_descent_section.png (a side section down the shaft), _map_openair_rooftop.png, _map_openair_busstop.png, _map_openair_campfire.png.

func _shot(path: String, frames := 12) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _bright(shift: Node) -> void:
	for we in shift.find_children("*", "WorldEnvironment", true, false):
		(we as WorldEnvironment).environment.ambient_light_energy = 3.0


func _ortho(parent: Node, pos: Vector3, look: Vector3, size: float, up := Vector3.UP) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	cam.far = 300.0
	parent.add_child(cam)
	cam.global_position = pos
	cam.look_at(look, up)
	cam.current = true
	return cam


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	NightWatchSave.path = "user://night_watch_maps_c_capture.cfg"
	NightWatchSave.reset()
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	NightWatchSession.start_mode("descent", 3, {}, 12)
	var lift := (load("res://game/night_watch/descent/night_watch_descent.tscn") as PackedScene).instantiate() as NightWatchDescentGame
	lift.manual_clock = true
	add_child(lift)
	await get_tree().process_frame
	lift.advance_ms(NightWatchDescentLogic.RIDE_MS + 10.0)
	lift.hud.visible = false
	lift._panel_layer.visible = false
	lift.world.set_alarm(0.0)
	_bright(lift)
	_ortho(lift, Vector3(0, 40, -6), Vector3(0, 0, -6), 20.0, Vector3(0, 0, -1))
	await _shot("%s/1280x720_map_descent_top.png" % out)
	_ortho(lift, Vector3(4.1, 1, -4), Vector3(0, 1, -4), 16.0)
	await _shot("%s/1280x720_map_descent_section.png" % out)
	lift.queue_free()
	await get_tree().process_frame
	var views := [
		[1, "rooftop", Vector3(0, 40, -4), 40.0],
		[2, "busstop", Vector3(-8, 40, 2), 44.0],
		[3, "campfire", Vector3(0, 40, -3), 36.0],
	]
	for v in views:
		NightWatchSession.start_mode("extra", int(v[0]), {}, 5)
		var shift := (load("res://game/night_watch/night_watch_extra.tscn") as PackedScene).instantiate() as NightWatchOpenAirGame
		shift.manual_clock = true
		add_child(shift)
		await get_tree().process_frame
		shift.advance_ms(100.0)
		shift.hud.visible = false
		_bright(shift)
		var at: Vector3 = v[2]
		_ortho(shift, at, Vector3(at.x, 0, at.z), float(v[3]), Vector3(0, 0, -1))
		await _shot("%s/1280x720_map_openair_%s.png" % [out, v[1]])
		shift.queue_free()
		await get_tree().process_frame
	NightWatchSave.reset()
	NightWatchSave.path = NightWatchSave.DEFAULT_PATH
	get_tree().quit()
