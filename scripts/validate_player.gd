extends RefCounted

## Headless check on the shared player mannequin.
##
## The player was a teal capsule for the whole port, so nothing downstream had
## ever been exercised against a real body. Three things have to hold or the
## swap is silently worse than the capsule: the model has to load, it has to
## carry the five clips ModelSlot asks for BY NAME -- has_animation is
## case-sensitive and a miss just returns, leaving a figure frozen mid-run --
## and it has to be roughly a person's height, since the capsule it replaces
## set the collision the world was built around.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- player

const WANTED := ["idle", "walk", "chase", "sprint", "crouch"]

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func run(host: Node) -> int:
	var model: Node3D = ModelSlot.instantiate(
		"res://art/props-3d/characters/player.tscn")
	if model == null:
		_fail("the player model would not load")
		return _failures
	host.get_tree().root.add_child(model)
	await host.get_tree().process_frame

	var player := ModelSlot.find_animation_player(model)
	if player == null:
		_fail("the player model carries no AnimationPlayer")
	else:
		for clip in WANTED:
			if not player.has_animation(clip):
				_fail("the player model has no '%s' clip" % clip)

	# Its own bounds, against the 1.7 m capsule it replaces.
	var bounds := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	# A character model must carry NO collision. The exporter emits a -colonly
	# body per mesh by default, which is right for a building and wrong for a
	# body: 21 static colliders parented to the player and moving with him
	# fight the world's own and shove him through the floor.
	var colliders := model.find_children("*", "StaticBody3D", true, false)
	if not colliders.is_empty():
		_fail("the player model carries %d colliders of its own" % colliders.size())

	if first:
		_fail("the player model has no meshes")
	elif bounds.size.y < 1.4 or bounds.size.y > 2.2:
		_fail("the player stands %.2f m, which is not a person" % bounds.size.y)

	# XR is an optional camera/input layer on the same body, not a second route
	# scene. In a headless/no-runtime test it must exist but fall back silently
	# to the ordinary first-person camera.
	var route: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(route)
	await host.get_tree().process_frame
	_expect_xr(route)
	await _expect_small_hop(route, host)
	route.queue_free()
	await host.get_tree().process_frame

	if _failures == 0:
		print("  player    %.2f m tall, %d clips, %d meshes"
			% [bounds.size.y, WANTED.size(),
				model.find_children("*", "MeshInstance3D", true, false).size()])
		print("player OK")
	model.queue_free()
	await host.get_tree().process_frame
	return _failures


func _expect_xr(route: Node) -> void:
	var controller: PlayerController3D = route.player
	if controller.xr_origin == null or controller.xr_camera == null \
			or controller.xr_left == null or controller.xr_right == null:
		_fail("the route player is missing its OpenXR origin/camera/controllers")
		return
	if controller.xr_active:
		_fail("OpenXR activated without an XR export/runtime request")
	if not controller.first_person_camera.current:
		_fail("desktop fallback lost its first-person camera")
	print("  openxr    tracked rig present; no-runtime desktop fallback stays active")


func _expect_small_hop(route: Node, host: Node) -> void:
	var controller: PlayerController3D = route.player
	if not InputMap.has_action("jump") or not Settings.REBINDABLE_ACTIONS.has("jump"):
		_fail("jump is missing from the input map or Settings rebinding")
		return
	var jump_uses_space := false
	var default_jump: Dictionary = ProjectSettings.get_setting("input/jump", {})
	for event in default_jump.get("events", []):
		if event is InputEventKey and event.physical_keycode == KEY_SPACE:
			jump_uses_space = true
	var default_interact: Dictionary = ProjectSettings.get_setting("input/interact", {})
	for event in default_interact.get("events", []):
		if event is InputEventKey and event.physical_keycode == KEY_SPACE:
			_fail("Space still activates interact as well as jump")
	if not jump_uses_space:
		_fail("the default jump binding is not Space")

	Input.action_release("jump")
	for _frame in 45:
		await host.get_tree().physics_frame
		if controller.is_on_floor():
			break
	if not controller.is_on_floor():
		_fail("the route player never settled onto the floor before the hop check")
		return
	var floor_y := controller.global_position.y
	# physics_frame wakes this coroutine inside the physics tick. Injecting an
	# action there is too late for `just_pressed` bookkeeping on some headless
	# backends, so stage synthetic input during the intervening process frame,
	# matching when a real keyboard event reaches the game.
	await host.get_tree().process_frame
	controller.request_jump()
	await host.get_tree().physics_frame
	await host.get_tree().process_frame
	if controller.velocity.y <= 0.0:
		_fail("pressing jump on the floor did not start an upward hop " \
			+ "(floor=%s frozen=%s crouch=%s)" % [
				controller.is_on_floor(), controller.input_frozen,
				Input.is_action_pressed("crouch")])
		return
	var maximum_y := controller.global_position.y

	# A second press while rising must not reset the impulse. This is the
	# grounded-only rule that keeps a small hop from becoming flight.
	var rising_velocity := controller.velocity.y
	await host.get_tree().process_frame
	controller.request_jump()
	await host.get_tree().physics_frame
	await host.get_tree().process_frame
	if controller.velocity.y >= rising_velocity:
		_fail("a second midair jump reset or increased vertical velocity")

	# Freezing input in the air (pause/capture/stun) still applies gravity.
	controller.input_frozen = true
	var before_frozen_gravity := controller.velocity.y
	await host.get_tree().physics_frame
	await host.get_tree().process_frame
	if controller.velocity.y >= before_frozen_gravity:
		_fail("input freeze suspended the player instead of applying gravity")
	controller.input_frozen = false

	var landed := false
	for _frame in 120:
		await host.get_tree().physics_frame
		maximum_y = maxf(maximum_y, controller.global_position.y)
		if controller.is_on_floor():
			landed = true
			break
	var height := maximum_y - floor_y
	if height < 0.24 or height > 0.50:
		_fail("the hop rose %.3f m; expected a restrained 0.24-0.50 m arc" % height)
	if not landed or absf(controller.global_position.y - floor_y) > 0.03:
		_fail("the hop did not return cleanly to its starting floor")

	# Network state already carries a Vector3; guard the vertical component so
	# a future bandwidth cleanup cannot silently flatten jumping peers.
	var state: Dictionary = route._remotes._local_state()
	var published = state.get("at")
	if not published is Vector3 or not is_equal_approx(published.y,
			controller.global_position.y):
		_fail("remote player state dropped the hop's vertical coordinate")
	print("  hop       %.2f m apex, grounded-only, gravity survives input freeze" % height)
