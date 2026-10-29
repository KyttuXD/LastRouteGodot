extends RefCounted

## Ghost spectators (docs/SPECTATORS.md, KT 2026-10-28: "more of a ghost player mode, not a free noclip thing"): a caught
## runner walks as a see-through body with world collision and gravity, never flies, makes no noise, is never a hunter
## target and can use or trigger nothing; [F] follows a teammate with a separate camera and comes back; leaving
## restores the runner. Remote copies of a ghost are drawn see-through and tinted.
##
##   godot --headless --path . res://scenes/validate.tscn -- ghost

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _frames(host: Node, count: int) -> void:
	for _i in count:
		await host.get_tree().physics_frame


func run(host: Node) -> int:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var scene: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(scene)
	for _i in 8:
		await host.get_tree().process_frame
	var player: PlayerController3D = scene.player
	player.grant_inventory_item("stim_pack", 2)
	player.select_inventory_slot(player.inventory_order.find("stim_pack"))
	await _frames(host, 10)
	var start := player.global_position
	player.enter_spectator()

	# a body: collision with the world, nothing collides with it, the ghost look
	_expect(player.player_collision != null and not player.player_collision.disabled and (player.collision_mask & 1) != 0,
		"the ghost has no world collision (noclip)")
	_expect(player.collision_layer == 0, "other bodies still collide with the ghost")

	# no flying: jump + crouch held do not lift it; gravity pulls it down from a height
	Input.action_press("crouch")
	await _frames(host, 30)
	Input.action_release("crouch")
	_expect(player.global_position.y <= start.y + .05, "the ghost flew (%.2f above the floor)" % (player.global_position.y - start.y))
	player.global_position = start + Vector3.UP * 2.5
	player.velocity = Vector3.ZERO
	await _frames(host, 60)
	_expect(player.global_position.y < start.y + .3, "the ghost hung in the air (%.2f up after 1 s)" % (player.global_position.y - start.y))

	# walks, silently
	var before := player.global_position
	Input.action_press("move_up")
	var loudest := 0.0
	for _i in 30:
		await host.get_tree().physics_frame
		loudest = maxf(loudest, player.noise)
	Input.action_release("move_up")
	_expect(Vector2(player.global_position.x - before.x, player.global_position.z - before.z).length() > .3, "the ghost cannot walk")
	_expect(loudest == 0.0, "the ghost's footsteps make noise (%.2f)" % loudest)

	# uses and triggers nothing
	Input.action_press("tool_use")
	await _frames(host, 3)
	Input.action_release("tool_use")
	player._try_interact()
	_expect(player.stim_injecting() == 0.0 and player.item_count("stim_pack") == 2, "the ghost used a stim")
	_expect(player.get_interaction_prompt().is_empty(), "the ghost gets an interaction prompt")
	var drops := []
	var watch := func(item_id: String, _c: int, _s: int) -> void: drops.append(item_id)
	player.item_drop_requested.connect(watch)
	Input.action_press("drop_item")
	await _frames(host, 3)
	Input.action_release("drop_item")
	player.item_drop_requested.disconnect(watch)
	_expect(drops.is_empty(), "the ghost dropped an item")

	# never a hunter target
	var target: Dictionary = scene._hunter_target(false)
	_expect(bool(target.get("spectating", false)) and bool(target.get("game_over", false)), "the ghost is not published as spectating")
	var remotes: RemotePlayers = scene._remotes
	_expect(remotes.best_target(Vector2(target["at"].x, target["at"].z), target, int(target.get("depth", 0))).is_empty(),
		"a hunter would still pick the ghost")

	# follow view: a separate camera; the body stays put; back to the ghost
	var spot := player.global_position
	player.spectator_follow_valid = true
	player.spectator_follow_at = spot + Vector3(6, 0, 0)
	player.set_ghost_follow(true)
	await _frames(host, 30)
	var cam := player.get_viewport().get_camera_3d()
	_expect(cam != null and cam.name == "GhostFollowCamera", "[F] did not switch to the follow camera")
	_expect(player.global_position.distance_to(spot) < .2, "following moved the ghost body")
	player.set_ghost_follow(false)
	_expect(player.get_viewport().get_camera_3d() == player.active_camera(), "[F] again did not return to the ghost")

	# a remote ghost: drawn see-through and tinted; leaving restores the runner
	var copy := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	copy.add_child(mesh)
	host.add_child(copy)
	PlayerController3D.set_ghost_look(copy, true)
	_expect(mesh.transparency > .3 and mesh.material_overlay == PlayerController3D.GHOST_OVERLAY, "the ghost look is not see-through and tinted")
	copy.queue_free()
	player.leave_spectator()
	_expect(player.collision_layer == 1 and not player.spectator_mode and not player.ghost_follow, "leaving did not restore the runner")
	scene.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  ghost  ok")
	return _failures
