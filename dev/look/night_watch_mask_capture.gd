extends Node

## Masked Hours captures at 1280x720 (docs/night_watch_modes/ and docs/night_watch_offices/): the office with its door-less opening onto the main hall (front_office_door / _desk),
## the hall light on Umbriel running the main hall, a vent light on Verrine, the monitor on the prize corner (CAM 1) and the game area (CAM 4), the mask, and a TOP-DOWN MAP of the
## whole wing (mask_map_topdown.png: ceilings hidden, an orthographic camera straight down).
##   godot --path . res://dev/look/night_watch_mask_capture.tscn -- OUT_DIR

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
	var game := (load("res://game/night_watch/mask/night_watch_mask.tscn") as PackedScene).instantiate() as MaskGame
	game.manual_clock = true
	add_child(game)
	await get_tree().process_frame
	game.advance_ms(2000.0)
	# the office from the opening side and from the desk (lamp on)
	game.office.set_lamp(true)
	game.hud.visible = false
	game.player.global_position = Vector3(1.4, 0.0, 1.5)
	game.face_player(0.35, -0.12)
	await _shot(out + "/front_office_door.png")
	game.player.global_position = MaskOffice.SPAWN
	game.face_player(0.0, -0.2)
	await _shot(out + "/front_office_desk.png")
	game.office.set_lamp(false)
	game.hud.visible = true
	# Umbriel running the main hall, the hall light on her
	var rush := game.sim.s["rush"] as Dictionary
	rush.merge({"state": "run", "room": "hall", "t": 1500.0, "need": 2100.0, "flashes": 1, "goal": 4, "doorNeed": 1700.0}, true)
	game.press("lightH")
	game.advance_ms(60.0)
	game.player.global_position = Vector3(0.0, 0.0, 0.7)
	game.face_player(0.0, -0.04)
	await _shot(out + "/mask_hall.png", 10)
	game.press("lightH", false)
	rush.merge({"state": "away", "room": "gallery"}, true)
	# Verrine in the right vent, the light on her
	var verrine := game.sim.s["vent"] as Dictionary
	verrine.merge({"state": "vent", "room": "ventR", "side": "R", "t": 0.0, "lit": 0.0, "wait": 6000.0}, true)
	game.player.global_position = Vector3(-0.4, 0.0, 1.2)
	game.face_player(-1.25, -0.2)
	game.press("lightR")
	game.advance_ms(60.0)
	await _shot(out + "/mask_vent.png", 10)
	game.press("lightR", false)
	verrine.merge({"state": "away", "room": "crawl"}, true)
	game.advance_ms(60.0)
	# the mask on
	game.player.global_position = MaskOffice.SPAWN
	game.face_player(0.0, -0.15)
	game.press("mask")
	game.advance_ms(400.0)
	await _shot(out + "/mask_mask.png", 4)
	# the monitor: the prize corner (the music box and Glyra), the game area with Thessine, the main hall
	game.press("monitor")
	game.advance_ms(700.0)
	game.advance_ms(300.0)
	await _shot(out + "/mask_cam1.png", 10)
	(game.sim.s["hall"]["thessine"] as Dictionary).merge({"state": "room", "room": "ballroom", "t": 0.0, "need": 99999.0}, true)
	game.select_camera("ballroom")
	game.advance_ms(60.0)
	await _shot(out + "/mask_cam4.png", 10)
	(game.sim.s["hall"]["thessine"] as Dictionary).merge({"state": "hall", "room": "hall", "step": 3, "t": 0.0, "need": 99999.0}, true)
	game.select_camera("hall")
	game.advance_ms(60.0)
	await _shot(out + "/mask_cam8.png", 10)
	game.press("monitor")
	game.advance_ms(500.0)
	# the top-down map of the whole wing: ceilings hidden, an orthographic camera straight down
	for node in game.find_children("Ceiling*", "Node3D", true, false):
		(node as Node3D).visible = false
	for node in game.find_children("*", "MeshInstance3D", true, false):
		if String(node.get_meta("nw_name", "")).begins_with("Ceiling"):
			(node as Node3D).visible = false
	game.hud.visible = false
	game.overlay.visible = false
	game.world_env.environment.ambient_light_energy = 4.0
	game.world_env.environment.background_color = Color(0.12, 0.12, 0.18)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 54.0
	cam.position = Vector3(0.0, 80.0, -15.0)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	cam.far = 200.0
	game.add_child(cam)
	cam.current = true
	await _shot(out + "/mask_map_topdown.png", 12)
	get_tree().quit()
