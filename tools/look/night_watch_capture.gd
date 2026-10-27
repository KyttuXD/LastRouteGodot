extends Node

## Night Watch screenshots: the office, a hunter at the left door in the door light, and the monitor feeds.
##   godot --path . res://tools/look/night_watch_capture.tscn -- OUT_DIR
## writes office.png, door_light.png, feed_dining.png, feed_westhall.png, power_out.png into OUT_DIR.

func _shot(path: String, frames := 6) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	NightWatchSession.start(3, 4242)
	var game := (load("res://scenes/night_watch.tscn") as PackedScene).instantiate() as NightWatchGame
	game.manual_clock = true
	add_child(game)
	await get_tree().process_frame
	game.advance_ms(2000.0)
	await _shot(out + "/office.png")
	# Dovelle at the left door, the light held on her, the player looking left
	var dovelle := game.sim.hunters["dovelle"] as NightWatchStalker
	dovelle.room = "doorL"
	dovelle.at_door_ms = 2500.0
	var ravelle := game.sim.hunters["ravelle"] as NightWatchStalker
	ravelle.room = "doorL"
	game.walker.global_position = Vector3(-1.2, 0.0, 0.9)
	game.set_light("doorL", true)
	game.advance_ms(20.0)
	game.walker.face(PI * 0.5, -0.05)
	await _shot(out + "/door_light.png")
	game.set_light("doorL", false)
	game.advance_ms(20.0)
	game.walker.face(PI * 0.5, -0.05)
	await _shot(out + "/door_dark.png")
	game.walker.global_position = NightWatchOffice.SPAWN
	game.walker.face(0.0, -0.15)
	# the monitor on two rooms with hunters in them
	(game.sim.hunters["aki"] as NightWatchStalker).room = "dining"
	dovelle.room = "dining"
	game.advance_ms(20.0)
	game.open_monitor("dining")
	await _shot(out + "/feed_dining.png", 10)
	game.select_camera("westhall")
	await _shot(out + "/feed_westhall.png", 10)
	game.select_camera("stage")
	await _shot(out + "/feed_stage.png", 10)
	game.close_monitor()
	game.sim.power = 0.0
	game.advance_ms(100.0)
	game.advance_ms(6000.0)
	await _shot(out + "/power_out.png", 10)
	get_tree().quit()
