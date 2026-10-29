extends Node

## The Mezzanine void (VoidRegion) looking down and up its shaft. Windowed:
##   mini-run.sh <dir> <lane> --scene res://tools/look/void_capture.tscn -- /tmp/void_caps


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/void_caps"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "SOAKTEST"
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	add_child(route)
	for _i in 30:
		await get_tree().process_frame
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var gen_seed: String = route.facility.generator.world_seed
	var rect := VoidRegion.footprint(gen_seed)
	print("VOIDCAP seed ", gen_seed, " footprint ", rect, " void chunk at level0 of rect.pos: ", route.facility.generator.is_void_column(Vector3i(rect.position.x, 0, rect.position.y)))
	var centre := Vector2(rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y / 2) * size + Vector2(.5, .5)
	var west_rim := Vector3(rect.position.x * size + 1.5, 0.0, centre.y)
	var camera := Camera3D.new()
	camera.fov = 80.0
	camera.far = 400.0
	add_child(camera)
	var tower := VoidRegion.tower_chunk(gen_seed)
	var tower_at := Vector3(tower.x * size + 11.5, 0.0, tower.y * size + 12.0)
	var cross := Vector2(UpperLevelTools.CENTER + .5, UpperLevelTools.CENTER + .5)
	var near_chunk := Vector2((rect.position.x + 2) * size, (rect.position.y + 2) * size) + cross
	var shots := [
		# name, player level to stream, camera position, look-at target
		["1_down_from_catwalk", 1, Vector3(near_chunk.x, 4.0 + 1.7, near_chunk.y - 14.0), Vector3(near_chunk.x, -9.0, near_chunk.y + 12.0)],
		["2_level0_ledge_across", 0, Vector3(west_rim.x, 1.7, west_rim.z), Vector3(centre.x - 4.0, 2.5, centre.y - 24.0)],
		["3_pit_ledge_looking_up", -3, Vector3(west_rim.x, -12.0 + 1.7, west_rim.z), Vector3(centre.x + 6.0, 4.0, centre.y - 10.0)],
		["4_down_60_from_ledge_rail", 1, Vector3(west_rim.x, 4.0 + 1.7, west_rim.z), Vector3(west_rim.x + 10.0, 4.0 + 1.7 - 17.3, west_rim.z)],
		["5_side_across_at_minus1", -1, Vector3(west_rim.x, -4.0 + 1.7, west_rim.z), Vector3(centre.x + 60.0, -4.0 + 1.7, centre.y)],
		["6_top_down", 1, Vector3(centre.x, 150.0, centre.y), Vector3(centre.x, 0.0, centre.y + .1)],
	]
	var fullbright := "fullbright" in args
	for shot in shots:
		var cam_pos: Vector3 = shot[2]
		route._admin_teleport_to(Vector3(cam_pos.x, float(shot[1]) * 4.0 + 0.3, cam_pos.z))
		for _i in 150:
			await get_tree().process_frame
		camera.current = true
		route.player.set_physics_process(false)
		route.player.velocity = Vector3.ZERO
		route.player.global_position = Vector3(cam_pos.x, float(shot[1]) * 4.0 + 0.3, cam_pos.z)
		if fullbright:
			DebugView.tool_override = true
			DebugView.set_mode(DebugView.Mode.FULLBRIGHT, get_viewport())
		camera.global_position = cam_pos
		camera.look_at(shot[3], Vector3.UP if absf((shot[3] as Vector3 - cam_pos).normalized().y) < .95 else Vector3.FORWARD)
		route.player.flashlight_enabled = true
		for _i in 12:
			await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		if image != null:
			image.save_png("%s/%s.png" % [out, shot[0]])
		print("VOIDCAP %s" % shot[0])
		camera.current = false
		route.player.set_physics_process(true)
	print("VOIDCAP done")
	get_tree().quit()
