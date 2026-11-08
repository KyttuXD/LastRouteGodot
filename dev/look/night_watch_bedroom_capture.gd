extends Node

## Bedtime screenshots at 1280x720:
##   godot --path . res://dev/look/night_watch_bedroom_capture.tscn -- OUT_DIR
## writes 1280x720_bedroom_hall.png (the hall light on Javelle at the doorway) and 1280x720_bedroom_bed.png (the bed light on Haelith).

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
	NightWatchSession.start_mode("bedroom", 3, {}, 4242)
	var game := (load("res://game/night_watch/bedroom/night_watch_bedroom.tscn") as PackedScene).instantiate() as BedroomGame
	game.manual_clock = true
	add_child(game)
	await get_tree().process_frame
	game.advance_ms(1000.0)
	game.sim.javelle["state"] = "near"
	game.sim.javelle["t"] = 0.0
	game.press("hall", true)
	game.look_by(0.9, 0.0)
	game.advance_ms(20.0)
	await _shot(out + "/1280x720_bedroom_hall.png", 10)
	game.sim.javelle["state"] = "away"
	game.sim.haelith["p"] = 70.0
	game.press("bed", true)
	game.look_by(-0.9, 0.05)
	game.advance_ms(20.0)
	await _shot(out + "/1280x720_bedroom_bed.png", 10)
	NightWatchSave.reset()
	NightWatchSave.path = NightWatchSave.DEFAULT_PATH
	get_tree().quit()
