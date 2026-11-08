extends RefCounted

## Every closed room door in the streamed window can be focused and opened from BOTH sides at eye height with the real
## controller selection (`_nearest_interactable`): the playtest found a hotel door the player could not select from the hall.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- door_focus

const SEEDS := ["ALPHA", "DOOR-B"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		if _failures < 20:
			print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var checked := 0
	for seed_text in SEEDS:
		RoomState.create_local(RoomState.Mode.DEFAULT)
		RoomState.seed_text = seed_text
		Backend.enable_offline_mode()
		var scene: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
		host.add_child(scene)
		for _frame in 12:
			await host.get_tree().process_frame
		var player := scene.get_node("%Player") as PlayerController3D
		var facility := scene.get_node("%StreamedFacility") as StreamedFacilityView3D
		# the playtest's hotel door (-6, 102) on ALPHA is a few chunks from the spawn: also scan around it
		var spots := [player.global_position]
		if seed_text == "ALPHA":
			spots.append(Vector3(-5.5, .05, 99.5))
		for spot in spots:
			if spot != spots[0]:
				scene.call("_admin_teleport_to", spot)
				for _frame in 12:
					await host.get_tree().process_frame
			var found: int = await _scan(scene, player, facility, host, seed_text)
			print("  door_focus: %s around %s: %d door sides" % [seed_text, Vector2(spot.x, spot.z), found])
			checked += found
		scene.queue_free()
		await host.get_tree().process_frame
	RoomState.create_local(RoomState.Mode.DEFAULT)
	_expect(checked > 20, "only %d door sides checked" % checked)
	if _failures == 0:
		print("  door_focus  %d door sides, every closed door selectable at eye height from both sides" % checked)
	return _failures


func _scan(scene: Node, player: PlayerController3D, facility: StreamedFacilityView3D, host: Node, seed_text: String) -> int:
	var checked := 0
	if true:
		var navigation: StreamedHunterNavigation = scene.get("_navigation")
		for door_value in (facility._door_nodes as Dictionary).values():
			if not is_instance_valid(door_value):
				continue   # a door of an unloaded chunk
			var door := door_value as RouteInteractable3D
			if door == null or door.get_prompt().is_empty():
				continue
			var normal := door.global_basis.z
			normal.y = 0.0
			normal = normal.normalized()
			for side in [-1.0, 1.0]:
				var stand: Vector3 = door.global_position + normal * float(side) * 1.25
				if navigation != null and not navigation.is_floor(stand.x, stand.z):
					continue
				player.global_position = Vector3(stand.x, door.global_position.y + .04, stand.z)
				await host.get_tree().physics_frame
				var eye := player.active_camera().global_position
				var to := door.interaction_focus() - eye
				player._yaw = atan2(-to.x, -to.z)
				player._pitch = asin(clampf(to.y / maxf(to.length(), .001), -1.0, 1.0))
				player._apply_look_rotation()
				await host.get_tree().physics_frame
				checked += 1
				var chosen: RouteInteractable3D = player._nearest_interactable()
				_expect(chosen == door, "%s: door at %s cannot be selected from the %s side (picked %s)" % [
					seed_text, Vector2(door.global_position.x, door.global_position.z).snapped(Vector2(.1, .1)),
					"front" if side > 0 else "back", chosen.name if chosen != null else "nothing"])
	return checked
