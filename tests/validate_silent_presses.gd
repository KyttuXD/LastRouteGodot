extends RefCounted

## E and left click with nothing to act on are SILENT: no deny/error blip, no menu blip. Covers the empty hand, a
## non-tool in hand, a full lamp with a battery selected, E with nothing in reach, a click while the cursor is free
## (the click that re-captures the mouse, clicks on open menus), and Drop with an empty hand. A real interactable in
## reach still plays its normal cue.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- silent_presses

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


static func _count(cue: String) -> int:
	return int(Sound.play_counts.get(cue, 0))


static func _total() -> int:
	var total := 0
	for cue in Sound.play_counts:
		total += int(Sound.play_counts[cue])
	return total


func run(host: Node) -> int:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var scene: Node = load("res://game/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	for _i in 3:
		await host.get_tree().process_frame
	var player: PlayerController3D = scene.player
	player.global_position += Vector3(400, 0, 400)   # far from every interactable
	await host.get_tree().process_frame
	Sound.reset_test_counters()
	# E with nothing in reach
	player._try_interact()
	_expect(_total() == 0, "E with nothing in reach played a cue: %s" % Sound.play_counts)
	# empty hand: click and drop
	var empty_slot := player.inventory_order.find("")
	_expect(empty_slot >= 0, "the starter hotbar has no empty slot to test")
	player.select_inventory_slot(empty_slot)
	player._use_selected_item()
	player.request_drop_selected_item()
	_expect(_total() == 0, "an empty-hand click or drop played a cue: %s" % Sound.play_counts)
	# a non-tool in hand, a full lamp with a battery
	player.select_inventory_slot(player.inventory_order.find("flashlight"))
	player._use_selected_tool()
	_expect(_total() == 0, "clicking with a non-tool played a cue: %s" % Sound.play_counts)
	player.lamp_charge = GameConfig.MAX_LAMP_CHARGE
	player._use_battery()
	_expect(_total() == 0, "a battery click with a full lamp played a cue: %s" % Sound.play_counts)
	# a click while the cursor is free never acts: the controller only acts once it saw the cursor captured last frame
	MouseLock.claim("menu_test", true)
	player._cursor_was_captured = false
	Input.action_press("tool_use")
	player._physics_process(1.0 / 60.0)
	Input.action_release("tool_use")
	_expect(_total() == 0, "a click with a free cursor played a cue: %s" % Sound.play_counts)
	_expect(not player._cursor_was_captured, "the controller thinks the cursor is captured while a menu holds it")
	MouseLock.claim("menu_test", false)
	# a real interactable in reach still gives its normal feedback
	var target := RouteInteractable3D.new()
	target.kind = RouteInteractable3D.Kind.BATTERY
	scene.add_child(target)
	var camera := player.active_camera()
	target.global_position = camera.global_position - camera.global_basis.z * 0.9
	await host.get_tree().process_frame
	var messages := []
	player.interaction_message.connect(func(text: String) -> void: messages.append(text))
	Sound.reset_test_counters()
	player._try_interact()
	var reacted := _total() > 0 or not messages.is_empty() or target.completed or not target.visible
	_expect(reacted, "interacting with a real interactable gave no feedback at all")
	_expect(_count("interaction_fail") == 0, "a normal interaction played the fail cue: %s" % Sound.play_counts)
	scene.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  silent    E / left click with nothing to act on, free cursor and empty hand are silent; a real interactable still reacts")
	return _failures
