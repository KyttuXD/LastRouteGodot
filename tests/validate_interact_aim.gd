extends RefCounted

## Prompt hitboxes for every interactable ("locker instruction hitbox too big", "fix prompt hitboxes for other props
## too", "make the reach closer"). For each sampled kind, built through its real setup, with the real controller
## selection (`_nearest_interactable`):
## - on: aiming at its interactive part inside its reach (RouteInteractable3D.AIM_REACH) picks it;
## - out of reach: the same aim from past the reach gives nothing;
## - near miss: aiming just beside the part (past AIM_BOX_MARGIN) gives nothing;
## - behind a wall: a wall between the eye and the part blocks it, also one straddling the part's front face;
## - neighbours: two of a kind side by side each get picked only when aimed at; on one ray the nearer one wins.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- interact_aim

var _failures := 0
var metrics := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _make(route: Node, kind_name: String) -> RouteInteractable3D:
	var node := RouteInteractable3D.new()
	match kind_name:
		"door":
			node.configure_room_door("AIM-DOOR-%d" % node.get_instance_id(), PropModelCatalog.model_path("normalRoomDoor", "aim"), false, false)
		"switch":
			node.kind = RouteInteractable3D.Kind.LIGHT_SWITCH
			node.prompt_text = "TOGGLE ROOM LIGHT"
		"battery":
			node.kind = RouteInteractable3D.Kind.BATTERY
		"relay":
			node.kind = RouteInteractable3D.Kind.RELAY
		"vent":
			node.kind = RouteInteractable3D.Kind.VENT
		"tool":
			node.configure_tool_pickup("lockpick")
		"seat":
			node.kind = RouteInteractable3D.Kind.FURNITURE
			node.configure_furniture("sit")
			node.set_meta("rest_size", Vector3(1.0, 1.3, .9))
			node.set_meta("seat_top", .57)
		"locker":
			node.kind = RouteInteractable3D.Kind.HIDING_SPOT
			node.prompt_text = "HIDE"
		"wardrobe":
			node.kind = RouteInteractable3D.Kind.HIDING_SPOT
			node.hide_style = "wardrobe"
			node.hide_size = Vector3(.6, 2.0, .6)
			node.prompt_text = "HIDE IN WARDROBE"
	route.add_child(node)
	if kind_name == "switch":
		node.configure_room_light("AIM-ROOM", true, Callable())
	node.rotation.y = PI    # its front faces the runner (who looks down -Z)
	return node


## Puts `node` so its aim box centre is `distance` ahead of the eye (plus `lateral` to the side) and aims straight.
func _place(node: RouteInteractable3D, player: PlayerController3D, distance: float, lateral: float = 0.0) -> void:
	player._yaw = 0.0
	player._pitch = 0.0
	player._apply_look_rotation()
	var eye := player.active_camera().global_position
	var box := node.aim_box()
	var want := eye + Vector3(lateral, 0.0, -(distance + box.size.z * .5))
	node.global_position = want - node.global_basis * box.get_center()


func _picked(host: Node, player: PlayerController3D) -> RouteInteractable3D:
	await host.get_tree().physics_frame
	return player._nearest_interactable()


func run(host: Node) -> int:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "INTERACT-AIM"
	var route: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 30:
		await host.get_tree().physics_frame
	var player: PlayerController3D = route.player
	route.set_process(false)
	route.set_physics_process(false)
	player.set_physics_process(false)
	# the interactables already around the spawn would compete: park them far below
	for node in host.get_tree().get_nodes_in_group("interactable"):
		if node is Node3D:
			(node as Node3D).global_position += Vector3(0, -500, 0)
	# clear air for the samples: the runner high above the generated rooms (physics is off, so she stays there)
	player.global_position += Vector3(0, 200, 0)
	var checked := {}
	for kind_name in ["door", "switch", "battery", "relay", "vent", "tool", "seat", "locker", "wardrobe"]:
		var node := _make(route, kind_name)
		await host.get_tree().physics_frame
		_expect(node.has_aim_box(), "%s has no aim box" % kind_name)
		if not node.has_aim_box():
			node.queue_free()
			continue
		if node.get_prompt().is_empty():
			_expect(false, "%s offers no prompt at all" % kind_name)
			node.queue_free()
			continue
		var reach := node.aim_reach()
		var box := node.aim_box()
		_place(node, player, reach - .25)
		_expect(await _picked(host, player) == node, "%s: aiming at it %.2f m away (reach %.2f) does not pick it" % [kind_name, reach - .25, reach])
		_place(node, player, reach + .3)
		_expect(await _picked(host, player) == null, "%s: picked from %.2f m, past its %.2f m reach" % [kind_name, reach + .3, reach])
		_place(node, player, reach - .4, box.size.x * .5 + .2)
		_expect(await _picked(host, player) == null, "%s: aiming 0.2 m beside it still picks it" % kind_name)
		# a wall between the eye and the part
		_place(node, player, reach - .25)
		var wall := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var wall_box := BoxShape3D.new()
		wall_box.size = Vector3(3.0, 3.0, .1)
		shape.shape = wall_box
		wall.add_child(shape)
		route.add_child(wall)
		wall.global_position = player.active_camera().global_position + Vector3(0, 0, -.45)
		_expect(await _picked(host, player) == null, "%s: picked through a wall" % kind_name)
		# a blocker straddling the part's front face (the hunters suite's relay case): still blocked
		wall.global_position = player.active_camera().global_position + Vector3(0, 0, -(reach - .25 - .1))
		_expect(await _picked(host, player) == null, "%s: picked through a blocker right at its face" % kind_name)
		wall.queue_free()
		await host.get_tree().physics_frame
		# neighbours: one beside the other, then one in front of the other
		var other := _make(route, kind_name)
		await host.get_tree().physics_frame
		var gap := box.size.x + .1
		_place(node, player, reach - .35, -gap * .5)
		_place(other, player, reach - .35, gap * .5)
		player._yaw = atan2(gap * .5, reach - .35 + box.size.z * .5)
		player._apply_look_rotation()
		_expect(await _picked(host, player) == node, "%s: aiming at the left of two picks %s" % [kind_name, "the right one" if player._nearest_interactable() == other else "nothing"])
		player._yaw = -atan2(gap * .5, reach - .35 + box.size.z * .5)
		player._apply_look_rotation()
		_expect(await _picked(host, player) == other, "%s: aiming at the right of two does not pick it" % kind_name)
		other.queue_free()
		node.queue_free()
		await host.get_tree().physics_frame
		checked[kind_name] = snappedf(reach, .01)
	metrics["reach"] = checked
	_expect(float(RouteInteractable3D.AIM_REACH[RouteInteractable3D.Kind.ROOM_DOOR]) <= 1.5
		and float(RouteInteractable3D.AIM_REACH[RouteInteractable3D.Kind.LIGHT_SWITCH]) <= 1.5,
		"doors and switches reach further than 1.5 m (closer, not further)")
	route.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	if _failures == 0:
		print("  interact_aim  %s" % [metrics])
	return _failures
