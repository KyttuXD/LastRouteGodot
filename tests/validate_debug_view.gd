extends RefCounted

## FULLBRIGHT / WIREFRAME admin debug view (DebugView): admin only, never on a public route, restores the viewport exactly,
## shows in the ADMIN ACTIVE badge, has the F7 action and an entry in every AdminMenu, and changes no gameplay light value
## (the Environment and lights are untouched). The rendered brightness check is dev/look/fullbright_check.tscn (mini).
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- debug_view

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var root := host.get_tree().root
	var before := root.debug_draw
	var env := Environment.new()
	env.ambient_light_energy = 0.07
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	host.add_child(world_env)
	var light := OmniLight3D.new()
	light.light_energy = 0.4
	host.add_child(light)
	var camera := Camera3D.new()
	var camera_env := Environment.new()
	camera.environment = camera_env
	host.add_child(camera)
	camera.make_current()
	DebugView.set_mode(DebugView.Mode.FULLBRIGHT)
	_expect(camera.environment == DebugView.fullbright_environment(), "fullbright did not take over the current camera's environment")
	_expect(DebugView.badge_text().contains("FULLBRIGHT"), "the badge does not say FULLBRIGHT")
	_expect(is_equal_approx(env.ambient_light_energy, 0.07) and is_equal_approx(light.light_energy, 0.4),
		"fullbright changed a gameplay light value")
	DebugView.set_mode(DebugView.Mode.WIREFRAME)
	_expect(root.debug_draw == Viewport.DEBUG_DRAW_WIREFRAME, "wireframe mode did not apply")
	DebugView.set_mode(DebugView.Mode.OFF)
	_expect(camera.environment == camera_env, "the camera's own environment did not come back")
	_expect(root.debug_draw == before and DebugView.mode == DebugView.Mode.OFF and DebugView.badge_text() == "",
		"turning the debug view off did not restore the viewport exactly")
	DebugView.toggle_fullbright()
	DebugView.toggle_fullbright()
	_expect(root.debug_draw == before, "toggling twice did not restore")
	# never on a public route
	var was_public := RoomState.public_route
	RoomState.public_route = true
	DebugView.set_mode(DebugView.Mode.FULLBRIGHT)
	_expect(DebugView.mode == DebugView.Mode.OFF and root.debug_draw == before, "fullbright turned on in a public route")
	RoomState.public_route = was_public
	# the action and the admin entries
	DebugView.ensure_action()
	var has_f7 := false
	for event in InputMap.action_get_events(DebugView.ACTION):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_F7:
			has_f7 = true
	_expect(has_f7, "no F7 binding for %s" % DebugView.ACTION)
	for action in InputMap.get_actions():
		if action == DebugView.ACTION or String(action).begins_with("ui_"):
			continue
		for event in InputMap.action_get_events(action):
			_expect(not (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_F7), "F7 is also bound to %s" % action)
	var menu := AdminMenu.attach(host, func() -> String: return "TEST", [], [])
	if menu != null:
		var labels := []
		for entry in menu._actions:
			labels.append(String((entry as Dictionary).get("label", "")))
		_expect(labels.has("TOGGLE FULLBRIGHT") and labels.has("TOGGLE WIREFRAME"), "the admin menu has no debug view entries")
		menu.queue_free()
	world_env.queue_free()
	light.queue_free()
	camera.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  debugview fullbright/wireframe: admin only, not on public routes, restores exactly, F7, badge, no light changes")
	return _failures
