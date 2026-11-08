extends Node

## Mixed Shift captures at 1280x720: the hub office from the door and from the desk (docs/night_watch_offices/hub_office_door.png / _desk.png), the vent run on CAM 9 with
## the crawler, a walker on a camera, and the office with a vent sealed (docs/night_watch_modes/mixed_*.png).
##   godot --path . res://dev/look/night_watch_mixed_capture.tscn -- OUT_DIR

func _shot(path: String, frames := 10) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	NightWatchSession.start_mode("mixed", 4, {}, 11)
	var game := (load("res://game/night_watch/mixed/night_watch_mixed.tscn") as PackedScene).instantiate() as MixedGame
	game.manual_clock = true
	add_child(game)
	await get_tree().process_frame
	game.advance_ms(500.0)
	game.hud.visible = false
	game.player.global_position = Vector3(2.6, 0.0, 0.9)
	game.face_player(PI * 0.3, -0.08)
	await _shot(out + "/hub_office_door.png")
	game.player.global_position = Vector3(0.0, 0.0, 0.9)
	game.face_player(0.0, -0.25)
	await _shot(out + "/hub_office_desk.png")
	game.hud.visible = true
	# the vent crawler on the run, the monitor on CAM 9
	var vt := game.sim.threat("verrine")
	if not vt.is_empty():
		vt["active"] = true
		vt["route"] = ["vent", "vent", "vent", "vent", "ventL"]
		vt["routeId"] = "V-L"
		vt["i"] = 2
	game.sim.s["elapsed"] = 100000.0
	game.open_monitor("vent")
	game.advance_ms(50.0)
	await _shot(out + "/mixed_vent_run.png")
	# a walker in a camera room
	for t in game.sim.list():
		if String(t["type"]) == "path" or String(t["type"]) == "watched":
			t["active"] = true
			t["route"] = ["stage", "dining", "easthall", "doorR"]
			t["routeId"] = "R-stage"
			t["i"] = 1
			break
	game.select_camera("dining")
	game.advance_ms(50.0)
	await _shot(out + "/mixed_walker.png")
	game.close_monitor()
	# the office: the top vent sealed, the left vent flashed, a hunter at the right door
	game.set_seal("T", true)
	game.flash_vent("L")
	game.advance_ms(50.0)
	game.player.global_position = Vector3(0.0, 0.0, 0.3)
	game.face_player(0.0, 0.25)
	await _shot(out + "/mixed_vents.png")
	get_tree().quit()
