extends Node

## Open Air screenshots at 1280x720 (docs/night_watch_modes/):
##   godot --path . res://tools/look/night_watch_openair_capture.tscn -- OUT_DIR
## writes 1280x720_openair_rooftop.png, _busstop.png and _campfire.png.

func _shot(path: String, frames := 12) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _shift(level: int, seed_number: int) -> NightWatchOpenAirGame:
	NightWatchSession.start_mode("extra", level, {}, seed_number)
	var shift := (load("res://scenes/night_watch_extra.tscn") as PackedScene).instantiate() as NightWatchOpenAirGame
	shift.manual_clock = true
	add_child(shift)
	return shift


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	NightWatchSave.path = "user://night_watch_openair_capture.cfg"
	NightWatchSave.reset()
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	var roof := _shift(1, 5)
	await get_tree().process_frame
	roof.sim.v.side = "L"
	roof.sim.v.dist = 1
	roof.inp["barR"] = true
	roof.advance_ms(900.0)
	roof.face_player(PI * 0.5, -0.05)
	roof.player.global_position = Vector3(-2.5, 0, 0.5)
	roof.inp["torchL"] = true
	roof.advance_ms(50.0)
	await _shot("%s/1280x720_openair_rooftop.png" % out)
	roof.queue_free()
	await get_tree().process_frame
	var bus := _shift(2, 6)
	await get_tree().process_frame
	bus.advance_ms(7000.0)
	bus.sim.chill = 55.0
	bus.press_lamp()
	bus.advance_ms(50.0)
	bus.player.global_position = Vector3(1.0, 0, 0.6)
	bus.face_player(PI - 0.3, -0.1)
	await _shot("%s/1280x720_openair_busstop.png" % out)
	bus.queue_free()
	await get_tree().process_frame
	var camp := _shift(3, 7)
	await get_tree().process_frame
	camp.sim.v.dist = 0
	camp.sim.v.on = true
	camp.sim.y.dist = 1
	camp.advance_ms(100.0)
	camp.player.global_position = Vector3(1.0, 0, 3.0)
	camp.face_player(0.5, -0.1)
	camp.advance_ms(50.0)
	await _shot("%s/1280x720_openair_campfire.png" % out)
	camp.queue_free()
	await get_tree().process_frame
	NightWatchSave.reset()
	NightWatchSave.path = NightWatchSave.DEFAULT_PATH
	get_tree().quit()
