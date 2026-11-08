extends Node

## Salvage Run screenshots at 1280x720: the shop, the rack with a piece being taken, Ravelle at the left door, Ysolde at the window.
## Writes dayshift_shop.png, dayshift_rack.png, dayshift_door.png, dayshift_window.png into OUT_DIR.
##   godot --path . res://dev/look/night_watch_dayshift_capture.tscn -- OUT_DIR

func _shot(path: String, frames := 8) -> void:
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
	game.shop.toggle("gloves")
	game.shop.toggle("hinges")
	await _shot(out + "/dayshift_shop.png", 4)
	game.start_shift(game.shop.owned)
	game.advance_ms(1000.0)
	game.sim.s["items"] = [{"slot": 0, "kind": "scrap", "value": 10, "need": 2000.0, "progress": 900.0, "age": 0.0}, {"slot": 2, "kind": "prize", "value": 60, "need": 5500.0, "progress": 0.0, "age": 0.0},
		{"slot": 3, "kind": "parts", "value": 25, "need": 3500.0, "progress": 0.0, "age": 0.0}]
	game.sim.s["spawnAt"] = 1e12
	game.player.global_position = Vector3(1.6, 0.0, -0.1)
	game.face_player(PI, -0.6)
	game.advance_ms(50.0)
	await _shot(out + "/dayshift_rack.png", 10)
	game.sim.s["items"] = []
	game.sim.s["ravelle"]["dist"] = 0
	game.sim.s["ravelle"]["atMs"] = 3000.0
	game.set_light("doorL", true)
	game.advance_ms(20.0)
	game.player.global_position = Vector3(-1.2, 0.0, 0.9)
	game.face_player(PI * 0.5, -0.05)
	await _shot(out + "/dayshift_door.png", 10)
	game.set_light("doorL", false)
	game.sim.s["ravelle"]["dist"] = 3
	game.sim.s["ysolde"]["state"] = "here"
	game.advance_ms(20.0)
	game.player.global_position = Vector3(-1.0, 0.0, 0.0)
	game.face_player(PI, -0.05)
	await _shot(out + "/dayshift_window.png", 10)
	get_tree().quit()
