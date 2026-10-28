extends Node

## Three on one waiting-room row (docs/SEATING.md): a hunter in the shared "sit" pose and two runners in their "sit"
## clip, each on their own sit point, lifted to the hunter-scale seat as peers see them. Windowed, so run it on the mini:
##   mini-run.sh <dir> props-lane --scene res://tools/look/bench_seats.tscn -- /tmp/bench_caps

const TYPE := "waitingChairs"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/bench_caps"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "BENCH-SEATS"
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	add_child(route)
	for _i in 90:
		await get_tree().process_frame
	route.set_process(false)
	route.set_physics_process(false)
	var player: PlayerController3D = route.player
	player.set_physics_process(false)
	var floor_at := Vector3(player.global_position.x, player.global_position.y, player.global_position.z - 4.2)
	var yaw := PI    # the row faces the camera
	var path := PropModelCatalog.model_path(TYPE, TYPE)
	var bench := ModelSlot.instantiate_prop(path, TYPE)
	route.add_child(bench)
	var bounds := ModelSlot.combined_local_bounds(bench)
	bench.global_position = floor_at - Vector3.UP * bounds.position.y
	bench.rotation.y = PropModelCatalog.authored_visual_yaw(yaw)
	var seat_top := StreamedFacilityView3D.seat_top(bench, path)
	var size: Vector3 = PropColliderSizes.SIZES[TYPE]
	var offsets := PropModelCatalog.seat_offsets(TYPE, size.x)
	print("BENCHCAP %d seats, seat pan %.2f m, row %.2f m" % [offsets.size(), seat_top, size.x])
	var front := Vector3(-sin(yaw), 0, -cos(yaw))
	for i in offsets.size():
		var seat := floor_at + Vector3(float(offsets[i]), 0, 0).rotated(Vector3.UP, yaw) + front * .06
		if i == 1:
			var hunter_id := "kathy"
			var hunter := ModelSlot.instantiate_hunter(HunterRoster.get_identity(hunter_id))
			route.add_child(hunter)
			hunter.scale = Vector3.ONE * HunterRoster.scale_for(hunter_id)
			hunter.global_position = seat
			hunter.rotation.y = yaw
			NightWatchPoses.play(hunter, HunterSeats.POSE)
		else:
			var runner := ModelSlot.instantiate(PlayerModels.SCENE)
			route.add_child(runner)
			runner.scale = Vector3.ONE * PlayerModels.SCALE
			runner.global_position = seat + Vector3.UP * maxf(0.0, seat_top - PlayerController3D.SIT_CLIP_SEAT)
			runner.rotation.y = yaw
			ModelSlot.apply_character_hue(runner, 110.0 * float(i))
			ModelSlot.play_if_available(ModelSlot.find_animation_player(runner), "sit")
	player._yaw = 0.0
	player._pitch = deg_to_rad(-6.0)
	player._apply_look_rotation()
	player.flashlight_enabled = true
	for _i in 60:
		await get_tree().process_frame
	_shot("%s/bench_front.png" % out)
	player.global_position += Vector3(2.6, 0, -.8)
	player._yaw = deg_to_rad(28.0)
	player._apply_look_rotation()
	for _i in 20:
		await get_tree().process_frame
	_shot("%s/bench_side.png" % out)
	print("BENCHCAP done")
	get_tree().quit()


func _shot(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	if image != null:
		image.save_png(path)
