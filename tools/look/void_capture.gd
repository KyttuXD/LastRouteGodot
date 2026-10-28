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
	var rect := VoidRegion.footprint(RoomState.seed_text)
	var centre := Vector2(rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y / 2) * size + Vector2(.5, .5)
	var west_rim := Vector3(rect.position.x * size + 1.5, 0.0, centre.y)
	var camera := Camera3D.new()
	camera.fov = 80.0
	add_child(camera)
	var shots := [
		# name, player level to stream, camera position, look-at target
		["down_from_mezzanine", 1, Vector3(centre.x, 4.0 + 1.7, centre.y - 18.0), Vector3(centre.x, -12.0, centre.y + 6.0)],
		["down_from_ledge", 1, Vector3(west_rim.x, 4.0 + 1.7, west_rim.z), Vector3(centre.x, -4.0, centre.y)],
		["up_from_pit_ledge", -3, Vector3(west_rim.x, -12.0 + 1.7, west_rim.z), Vector3(centre.x, 10.0, centre.y)],
		["across_at_level0", 0, Vector3(west_rim.x, 1.7, west_rim.z), Vector3(centre.x + 20.0, 0.5, centre.y)],
		["tower_from_below", -2, Vector3(centre.x - 30.0, -8.0 + 1.7, centre.y - 30.0), Vector3(centre.x - 2.0, 0.0, centre.y - 2.0)],
	]
	for shot in shots:
		var cam_pos: Vector3 = shot[2]
		route._admin_teleport_to(Vector3(cam_pos.x, float(shot[1]) * 4.0 + 0.3, cam_pos.z))
		for _i in 150:
			await get_tree().process_frame
		camera.current = true
		camera.global_position = cam_pos
		camera.look_at(shot[3], Vector3.UP)
		route.player.flashlight_enabled = true
		for _i in 12:
			await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		if image != null:
			image.save_png("%s/%s.png" % [out, shot[0]])
		print("VOIDCAP %s" % shot[0])
		camera.current = false
	print("VOIDCAP done")
	get_tree().quit()
