extends Node

## Dead Air screenshots at 1280x720:
##   godot --path . res://tools/look/night_watch_lure_capture.tscn -- OUT_DIR
## writes 1280x720_lure_office.png (the office, Xivvy in the left vent opening) and 1280x720_lure_monitor.png (the monitor on the ball pit).

func _shot(path: String, frames := 8) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	NightWatchSave.path = "user://night_watch_capture.cfg"
	NightWatchSave.reset()
	NightWatchSession.start_mode("lure", 4, {}, 4242)
	var game := (load("res://scenes/night_watch_lure.tscn") as PackedScene).instantiate() as LureGame
	game.manual_clock = true
	add_child(game)
	await get_tree().process_frame
	game.advance_ms(2000.0)
	game.sim.killer["room"] = "officeL"
	game.sim.killer["atMs"] = 2200.0
	game.sim.toggle("heater")
	game.player.global_position = Vector3(-1.4, 0.0, 0.9)
	game.face_player(PI * 0.5, -0.05)
	game.advance_ms(20.0)
	await _shot(out + "/1280x720_lure_office.png", 10)
	game.sim.killer["room"] = "ballpit"
	game.sim.phantom = {"id": "ferryn", "room": "ballpit", "t": 0.0}
	game.sim.systems["audio"] = {"state": "broken", "t": 0.0}
	game.sim.systems["vent"] = {"state": "reboot", "t": 2500.0}
	game.advance_ms(20.0)
	game.open_monitor("ballpit")
	await _shot(out + "/1280x720_lure_monitor.png", 12)
	NightWatchSave.reset()
	NightWatchSave.path = NightWatchSave.DEFAULT_PATH
	get_tree().quit()
