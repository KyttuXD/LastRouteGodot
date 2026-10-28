extends RefCounted

## KT: "locker instruction hitbox too big". A hiding spot's prompt needs the aim ray to hit the prop (its box plus
## RouteInteractable3D.AIM_BOX_MARGIN) within PlayerController3D.HIDE_AIM_REACH; two spots side by side go to the one the
## ray hits first, never to a neighbour you are not aiming at.
##
##   godot --headless --path . res://scenes/validate.tscn -- hiding_aim

const WARDROBE := Vector3(.6, 2.0, .6)    # a locker-sized spot

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _spot(route: Node, player: PlayerController3D, offset: Vector3) -> RouteInteractable3D:
	var spot := RouteInteractable3D.new()
	spot.kind = RouteInteractable3D.Kind.HIDING_SPOT
	spot.hide_style = "wardrobe"
	spot.hide_size = WARDROBE
	spot.prompt_text = "HIDE IN WARDROBE"
	route.add_child(spot)
	spot.global_position = Vector3(player.global_position.x, player.global_position.y, player.global_position.z) + offset
	spot.rotation.y = PI
	return spot


func _aim(player: PlayerController3D, yaw: float, pitch: float) -> RouteInteractable3D:
	player._yaw = yaw
	player._pitch = pitch
	player._apply_look_rotation()
	return player._nearest_interactable()


func run(host: Node) -> int:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "HIDE-AIM"
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 30:
		await host.get_tree().physics_frame
	var player: PlayerController3D = route.player
	route.set_process(false)
	route.set_physics_process(false)
	player.set_physics_process(false)
	# the interactables already around the spawn would compete; park them
	for node in host.get_tree().get_nodes_in_group("interactable"):
		if node is RouteInteractable3D:
			(node as Node3D).global_position += Vector3(0, -500, 0)
	var ahead := _spot(route, player, Vector3(0, 0, -1.3))
	await host.get_tree().physics_frame
	_expect(_aim(player, 0.0, 0.0) == ahead, "aiming straight at a wardrobe 1.3 m ahead gives no prompt")
	_expect(_aim(player, .4, -.2) == null, "aiming 23 degrees beside the wardrobe still offers it (the old cone)")
	_expect(_aim(player, 0.0, -1.2) == null, "aiming at the floor in front of the wardrobe still offers it")
	ahead.global_position += Vector3(0, 0, -1.6)    # now 2.9 m away: in the cone, out of reach
	await host.get_tree().physics_frame
	_expect(_aim(player, 0.0, 0.0) == null, "a wardrobe 2.9 m away is offered (reach %.1f m)" % PlayerController3D.HIDE_AIM_REACH)
	ahead.queue_free()
	var left := _spot(route, player, Vector3(-.7, 0, -1.3))
	var right := _spot(route, player, Vector3(.7, 0, -1.3))
	await host.get_tree().physics_frame
	_expect(_aim(player, .45, 0.0) == left, "aiming at the left of two wardrobes did not pick it")
	_expect(_aim(player, -.45, 0.0) == right, "aiming at the right of two wardrobes did not pick it")
	var near := _spot(route, player, Vector3(0, 0, -1.0))
	var behind := _spot(route, player, Vector3(0, 0, -1.75))
	left.queue_free()
	right.queue_free()
	await host.get_tree().physics_frame
	_expect(_aim(player, 0.0, 0.0) == near, "the nearer of two spots on the aim ray did not win")
	near.queue_free()
	behind.queue_free()
	route.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	if _failures == 0:
		print("  hiding_aim  prompt only on an aim-ray hit within %.1f m; nearest hit wins" % PlayerController3D.HIDE_AIM_REACH)
	return _failures
