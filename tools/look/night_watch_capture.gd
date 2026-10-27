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
	# Zellia's call at the two test sizes: ringing, then a typed line (night 3's first line)
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		get_window().size = size
		await get_tree().process_frame
		game.advance_ms(3500.0)   # 5.5 s in: the ring ("Incoming call…")
		await _shot("%s/call_ring_%dx%d.png" % [out, size.x, size.y], 4)
		game.advance_ms(5000.0)
		await _shot("%s/call_text_%dx%d.png" % [out, size.x, size.y], 4)
		game.hud.set_call_script(NightWatchCallScript.for_level("classic", 3))
		game.hud.show_call("")
		game._elapsed_ms = 0.0
		game.advance_ms(0.0)
	get_window().size = Vector2i(1280, 720)
	game.hud.set_call_script(NightWatchCallScript.new([], 0.0))
	game.hud.show_call("")
	# Dovelle at the left door, the light held on her, the player looking left
	var dovelle := game.sim.hunters["dovelle"] as NightWatchStalker
	dovelle.room = "doorL"
	dovelle.at_door_ms = 2500.0
	var ravelle := game.sim.hunters["ravelle"] as NightWatchStalker
	ravelle.room = "doorL"
	game.player.global_position = Vector3(-1.2, 0.0, 0.9)
	game.set_light("doorL", true)
	game.advance_ms(20.0)
	game.face_player(PI * 0.5, -0.05)
	await _shot(out + "/door_light.png")
	game.player.global_position = Vector3(-2.2, 0.0, 1.55)
	game.face_player(PI * 0.5, -0.08)
	await _shot(out + "/panel_prompt.png", 10)
	game.player.global_position = Vector3(-1.2, 0.0, 0.9)
	game.face_player(PI * 0.5, -0.05)
	game.set_light("doorL", false)
	game.advance_ms(20.0)
	game.face_player(PI * 0.5, -0.05)
	await _shot(out + "/door_dark.png")
	game.player.global_position = NightWatchOffice.SPAWN
	game.face_player(0.0, -0.15)
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
	# walking: the sim moves Dovelle from the dining area into the west hall; her model walks the doorway, it is not placed
	game.manual_clock = false
	dovelle.room = "dining"
	game._place_hunters()
	game._animate_models(0.016)
	dovelle.room = "westhall"
	game._place_hunters()
	game.select_camera("dining")
	for i in 14:
		game._animate_models(0.1)
	await _shot(out + "/walk_mid.png", 3)
	game.manual_clock = true
	game.close_monitor()
	game.sim.power = 0.0
	game.advance_ms(100.0)
	game.advance_ms(6000.0)
	await _shot(out + "/power_out.png", 10)
	# a top-down map of the facility: rooms, doorways, the waypoint routes and the camera mounts
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = 30.0
	game.add_child(top)
	top.global_position = NightWatchBuilding.ORIGIN + Vector3(8.0, 40.0, 8.0)
	top.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	top.make_current()
	for room in game.building.rooms:
		var cam_t := game.building.camera_transform(room)
		var marker := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 0.5, 0.5)
		marker.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.2, 0.2)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		marker.material_override = mat
		game.add_child(marker)
		marker.global_position = Vector3(cam_t.origin.x, 4.0, cam_t.origin.z)
	var lines := ImmediateMesh.new()
	var line_node := MeshInstance3D.new()
	line_node.mesh = lines
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.2, 1.0, 0.4)
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_node.material_override = lmat
	game.add_child(line_node)
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for a in NightWatchData.GRAPH:
		for b in NightWatchData.GRAPH[a]:
			if String(a) < String(b) and not String(a).begins_with("door") and not String(b).begins_with("door"):
				var legs: Array = game.paths.legs_for(String(a), String(b))
				for i in range(1, legs.size()):
					var p0: Vector3 = legs[i - 1]["p"]
					var p1: Vector3 = legs[i]["p"]
					lines.surface_add_vertex(Vector3(p0.x, 4.5, p0.z))
					lines.surface_add_vertex(Vector3(p1.x, 4.5, p1.z))
	lines.surface_end()
	await _shot(out + "/facility_map.png", 4)
	top.queue_free()
	get_tree().quit()
