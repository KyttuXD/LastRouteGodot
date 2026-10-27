extends Node

## Furniture hiding captures (docs/HIDING_PROPS.md) on a real generated route: for the nearest bed and wardrobe hiding
## spots, the approach (prompt in view), the view from inside, and the hunter-check tell. Windowed, so run it on the mini:
##   mini-run.sh <dir> props-lane --scene res://tools/look/hiding_props.tscn -- /tmp/hide_caps


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/hide_caps"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "HIDE-ROUTE"
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	add_child(route)
	for _i in 90:
		await get_tree().process_frame
	var player: PlayerController3D = route.player
	for style in ["bed", "wardrobe"]:
		var spot := _nearest(player, style)
		if spot == null:
			print("HIDECAP no %s spot loaded" % style)
			continue
		var front := spot.global_basis * Vector3(0, 0, -1)
		front.y = 0.0
		front = front.normalized()
		var reach := spot.hide_size.z * .5 + .9
		player.global_position = Vector3(spot.global_position.x, player.global_position.y, spot.global_position.z) + front * reach
		player._yaw = atan2(front.x, front.z)
		player.rotation.y = player._yaw
		player._pitch = deg_to_rad(-38.0 if style == "bed" else -8.0)
		player.first_person_pivot.rotation.x = player._pitch
		player.flashlight_enabled = true
		for _i in 20:
			await get_tree().process_frame
		_shot("%s/%s_approach.png" % [out, style])
		print("HIDECAP %s prompt: %s" % [style, spot.get_prompt()])
		spot.activate(player)
		for step in 4:    # the enter move, about every 0.15 s of its 0.6 s
			await get_tree().create_timer(.15).timeout
			_shot("%s/%s_enter_%d.png" % [out, style, step])
		for _i in 20:
			await get_tree().process_frame
		_shot("%s/%s_inside.png" % [out, style])
		spot.play_search_tell(1.6)
		for _i in 6:
			await get_tree().process_frame
		_shot("%s/%s_inside_tell.png" % [out, style])
		player.leave_hiding()
		for _i in 30:
			await get_tree().process_frame
	print("HIDECAP done")
	get_tree().quit()


func _nearest(player: PlayerController3D, style: String) -> RouteInteractable3D:
	var best: RouteInteractable3D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("streamed_hiding_spot"):
		var spot := node as RouteInteractable3D
		if spot == null or spot.hide_style != style:
			continue
		var distance := spot.global_position.distance_to(player.global_position)
		if distance < best_distance:
			best = spot
			best_distance = distance
	return best


func _shot(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	if image != null:
		image.save_png(path)
