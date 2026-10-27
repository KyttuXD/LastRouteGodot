extends Node

## Masked Hours screenshots at 1280x720: the dark office with the hall light on Umbriel, a vent light on Verrine, the music box on CAM 1, the hall camera,
## and the mask. Writes mask_hall.png, mask_vent.png, mask_cam1.png, mask_cam8.png, mask_mask.png into OUT_DIR.
##   godot --path . res://tools/look/night_watch_mask_capture.tscn -- OUT_DIR

func _shot(path: String, frames := 8) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	NightWatchSession.start_mode("mask", 5, {}, 4242)
	var game := (load("res://scenes/night_watch_mask.tscn") as PackedScene).instantiate() as MaskGame
	game.manual_clock = true
	add_child(game)
	await get_tree().process_frame
	game.advance_ms(2000.0)
	# Umbriel running the hall, the hall light on her
	var rush := game.sim.s["rush"] as Dictionary
	rush.merge({"state": "run", "room": "hall", "t": 1200.0, "need": 2100.0, "flashes": 1, "goal": 4, "doorNeed": 1700.0}, true)
	game.press("lightH")
	game.advance_ms(60.0)
	game.face_player(-PI * 0.5, -0.05)
	game.player.global_position = Vector3(1.4, 0.0, 0.2)
	await _shot(out + "/mask_hall.png", 10)
	game.press("lightH", false)
	rush.merge({"state": "away", "room": "gallery"}, true)
	# Verrine in the right vent, the light on her
	var verrine := game.sim.s["vent"] as Dictionary
	verrine.merge({"state": "vent", "room": "ventR", "side": "R", "t": 0.0, "lit": 0.0, "wait": 6000.0}, true)
	game.player.global_position = Vector3(0.2, 0.0, 0.6)
	game.face_player(-0.62, -0.22)
	game.press("lightR")
	game.advance_ms(60.0)
	await _shot(out + "/mask_vent.png", 10)
	game.press("lightR", false)
	verrine.merge({"state": "away", "room": "crawl"}, true)
	game.advance_ms(60.0)
	# the mask on
	game.player.global_position = NightWatchOffice.SPAWN
	game.face_player(0.0, -0.15)
	game.press("mask")
	game.advance_ms(400.0)
	await _shot(out + "/mask_mask.png", 4)
	# the monitor on CAM 1 (the music box and Glyra), then the hall camera
	game.press("monitor")
	game.advance_ms(700.0)
	game.advance_ms(300.0)
	await _shot(out + "/mask_cam1.png", 10)
	(game.sim.s["hall"]["thessine"] as Dictionary).merge({"state": "hall", "room": "hall", "step": 3, "t": 0.0, "need": 99999.0}, true)
	game.select_camera("hall")
	game.advance_ms(60.0)
	await _shot(out + "/mask_cam8.png", 10)
	get_tree().quit()
