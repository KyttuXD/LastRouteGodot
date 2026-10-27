extends Node

## The offices of The Descent and Open Air (docs/NIGHT_WATCH_OFFICES.md), one image from the entrance and one from the main station each, 1280x720:
##   godot --path . res://tools/look/night_watch_offices_c_capture.tscn -- OUT_DIR
## writes lift_landing_door.png / _desk.png and watch_post_door.png / _desk.png (rooftop), watch_post_busstop_door / _desk, watch_post_campfire_door / _desk.

func _shot(path: String, frames := 12) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _open_air(level: int) -> NightWatchOpenAirGame:
	NightWatchSession.start_mode("extra", level, {}, 5)
	var shift := (load("res://scenes/night_watch_extra.tscn") as PackedScene).instantiate() as NightWatchOpenAirGame
	shift.manual_clock = true
	add_child(shift)
	return shift


func _view(shift: NightWatchOpenAirGame, pos: Vector3, yaw: float, pitch: float) -> void:
	shift.player.global_position = pos
	shift.face_player(yaw, pitch)
	shift.advance_ms(50.0)


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	NightWatchSave.path = "user://night_watch_offices_c_capture.cfg"
	NightWatchSave.reset()
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	# the lift: the panel from inside, the window from the sill
	NightWatchSession.start_mode("descent", 3, {}, 12)
	var lift := (load("res://scenes/night_watch_descent.tscn") as PackedScene).instantiate() as NightWatchDescentGame
	lift.manual_clock = true
	add_child(lift)
	await get_tree().process_frame
	lift.sim.threat = 40.0
	lift.advance_ms(NightWatchDescentLogic.RIDE_MS + 10.0)
	await _shot("%s/lift_landing_desk.png" % out)
	lift.world.camera.global_position = Vector3(0.3, 1.5, -3.2)
	lift.world.camera.look_at(Vector3(0.0, 1.4, -1.4))
	lift.advance_ms(10.0)
	await _shot("%s/lift_landing_door.png" % out)
	lift.queue_free()
	await get_tree().process_frame
	# the rooftop: the stair door, the lantern post
	var roof := _open_air(1)
	await get_tree().process_frame
	roof.sim.v.side = "L"
	roof.sim.v.dist = 1
	_view(roof, Vector3(-3.0, 0, 0.4), PI * 0.5, -0.05)
	await _shot("%s/watch_post_door.png" % out)
	_view(roof, Vector3(0.0, 0, -0.6), 0.0, 0.05)
	await _shot("%s/watch_post_desk.png" % out)
	roof.queue_free()
	await get_tree().process_frame
	var bus := _open_air(2)
	await get_tree().process_frame
	bus.advance_ms(7000.0)
	_view(bus, Vector3(-1.0, 0, 0.8), 0.0, 0.0)
	await _shot("%s/watch_post_busstop_door.png" % out)
	bus.press_lamp()
	_view(bus, Vector3(-0.3, 0, 3.8), PI * 0.5 + 0.2, 0.0)
	await _shot("%s/watch_post_busstop_desk.png" % out)
	bus.queue_free()
	await get_tree().process_frame
	var camp := _open_air(3)
	await get_tree().process_frame
	camp.sim.v.dist = 0
	camp.sim.y.dist = 1
	camp.advance_ms(100.0)
	_view(camp, Vector3(-2.0, 0, 0.5), PI * 0.5 + 0.1, -0.05)
	await _shot("%s/watch_post_campfire_door.png" % out)
	_view(camp, Vector3(1.2, 0, 2.2), 0.3, -0.35)
	await _shot("%s/watch_post_campfire_desk.png" % out)
	camp.queue_free()
	await get_tree().process_frame
	NightWatchSave.reset()
	NightWatchSave.path = NightWatchSave.DEFAULT_PATH
	get_tree().quit()
