extends RefCounted

## Typing never plays the game: the in-world waypoint keys are gone (waypoints only from the full map), and while the chat field
## (or any text field) has focus, typing "bvefmq" sets no waypoint, toggles no flashlight, opens no map or inventory, fires no
## taser and drops nothing, while the field still receives the text.
##
##   godot --headless --path . res://scenes/validate.tscn -- typing_guard

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _type(host: Node, text: String) -> void:
	for character in text:
		var code := OS.find_keycode_from_string(character.to_upper())
		for pressed in [true, false]:
			var key := InputEventKey.new()
			key.physical_keycode = code
			key.keycode = code
			key.unicode = character.unicode_at(0) if pressed else 0
			key.pressed = pressed
			Input.parse_input_event(key)
			Input.flush_buffered_events()
			await host.get_tree().physics_frame
			await host.get_tree().process_frame


func run(host: Node) -> int:
	_expect(not InputMap.has_action("waypoint") and not InputMap.has_action("waypoint_clear"), "the in-world waypoint keybinds still exist")
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 10:
		await host.get_tree().process_frame
	var player: PlayerController3D = route.get("player")
	var hud: HUD = route.get("hud")
	var chat: RoomChat = route.get("_room_chat")
	var flashlight_before := player.flashlight_enabled
	var items_before := player.inventory_order.duplicate()
	chat.open()
	for _i in 30:
		await host.get_tree().physics_frame
	var waypoint_before: Dictionary = route.call("_local_waypoint")
	_expect(MouseLock.typing(), "the chat field does not have the keyboard")
	await _type(host, "bvefmq bvefmq")
	for _i in 4:
		await host.get_tree().physics_frame
	_expect(route.call("_local_waypoint") == waypoint_before, "typing set or cleared a waypoint (%s -> %s)" % [waypoint_before, route.call("_local_waypoint")])
	_expect(player.flashlight_enabled == flashlight_before, "typing toggled the flashlight")
	_expect(not hud.map_is_open(), "typing opened the map")
	_expect(not hud.inventory_is_open(), "typing opened the inventory")
	_expect(player.inventory_order == items_before, "typing dropped or changed an item")
	for action in ["interact", "flashlight", "taser", "toggle_map", "inventory", "drop_item", "move_up", "move_left", "jump"]:
		if InputMap.has_action(action):
			_expect(not Input.is_action_pressed(action), "%s is pressed while typing" % action)
	_expect(chat._field.text.to_lower().contains("bvefmq"), "the chat field did not receive the typed text ('%s')" % chat._field.text)
	chat.close()
	for _i in 3:
		await host.get_tree().process_frame
	_expect(InputMap.action_get_events("toggle_map").size() > 0 and MouseLock._stripped.is_empty(), "the bindings did not come back after typing")
	route.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  typing    no waypoint keys; typing in chat fires no gameplay action (waypoint, flashlight, map, inventory, taser, drop)")
	return _failures
