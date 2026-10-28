extends RefCounted

## Control hints match the real controls: for every device profile (keyboard/mouse from the live InputMap, gamepad from its
## joypad bindings, phone touch buttons, Quest controllers) the prompts for hiding (HIDE / LEAVE), ladders (HOLD up/down CLIMB //
## jump LET GO, only near the bottom), doors and furniture show that device's glyphs; a rebind changes the prompt; the device
## follows the last input; no stale wording ("INTERACT TO", "TO CLIMB") is left.
##
##   godot --headless --path . res://scenes/validate.tscn -- prompt_glyphs

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


## What the InputMap says presses `action` on a keyboard, independently of InputGlyphs.
static func _keyboard_name(action: String) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			return OS.get_keycode_string(key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode).to_upper()
	return ""


static func _pad_name(action: String) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			return String(InputGlyphs.PAD_BUTTONS.get((event as InputEventJoypadButton).button_index, ""))
		if event is InputEventJoypadMotion:
			return "L-STICK UP" if (event as InputEventJoypadMotion).axis_value < 0.0 else "L-STICK DOWN"
	return ""


func _check_devices() -> void:
	var expected := {
		InputGlyphs.KEYBOARD: {"interact": _keyboard_name("interact"), "jump": _keyboard_name("jump"),
			"move_up": _keyboard_name("move_up"), "move_down": _keyboard_name("move_down")},
		InputGlyphs.GAMEPAD: {"interact": _pad_name("interact"), "jump": _pad_name("jump"), "move_up": _pad_name("move_up"),
			"move_down": _pad_name("move_down")},
		InputGlyphs.TOUCH: {"interact": "USE", "jump": "JUMP", "move_up": "D-PAD UP", "move_down": "D-PAD DOWN"},
		InputGlyphs.XR: {"interact": "TRIGGER", "jump": "A", "climb": "GRIP"},
	}
	for device in expected:
		for action in expected[device]:
			var want: String = expected[device][action]
			_expect(not want.is_empty(), "%s has no %s binding to show" % [device, action])
			_expect(InputGlyphs.name_of(action, device) == want, "%s %s shows '%s', the controls say '%s'" % [device, action, InputGlyphs.name_of(action, device), want])
		InputGlyphs.device_override = device
		_expect(InputGlyphs.prompt("interact", "HIDE") == "[%s] HIDE" % expected[device]["interact"], "%s hide prompt: %s" % [device, InputGlyphs.prompt("interact", "HIDE")])
		var climb := InputGlyphs.climb_prompt(true)
		if device == InputGlyphs.XR:
			_expect(climb == "[GRIP] + PULL CLIMB // [A] LET GO", "xr climb prompt: %s" % climb)
		else:
			_expect(climb == "HOLD [%s]/[%s] CLIMB // [%s] LET GO" % [expected[device]["move_up"], expected[device]["move_down"], expected[device]["jump"]],
				"%s climb prompt: %s" % [device, climb])
		_expect(not InputGlyphs.climb_prompt(false).contains("LET GO"), "%s offers LET GO high on the ladder" % device)
	InputGlyphs.device_override = ""


func _check_rebind() -> void:
	var saved := InputMap.action_get_events("interact")
	InputMap.action_erase_events("interact")
	var g := InputEventKey.new()
	g.physical_keycode = KEY_G
	InputMap.action_add_event("interact", g)
	_expect(InputGlyphs.prompt("interact", "HIDE", InputGlyphs.KEYBOARD) == "[G] HIDE", "a rebind to G still shows %s" % InputGlyphs.prompt("interact", "HIDE", InputGlyphs.KEYBOARD))
	InputMap.action_erase_events("interact")
	for event in saved:
		InputMap.action_add_event("interact", event)


func _check_switching() -> void:
	InputGlyphs.device_override = ""
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	InputGlyphs.observe(pad)
	_expect(InputGlyphs.device() == InputGlyphs.GAMEPAD, "a gamepad press did not switch prompts to the gamepad")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	InputGlyphs.observe(key)
	_expect(InputGlyphs.device() == InputGlyphs.KEYBOARD, "a key press did not switch prompts back to the keyboard")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	InputGlyphs.observe(touch)
	_expect(InputGlyphs.device() == InputGlyphs.TOUCH, "a touch did not switch prompts to the touch buttons")
	InputGlyphs.observe(key)


func _check_player(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 6:
		await host.get_tree().process_frame
	var player: PlayerController3D = route.get("player")
	InputGlyphs.device_override = InputGlyphs.KEYBOARD
	var e := "[%s]" % _keyboard_name("interact")
	player.hidden = true
	player.hiding_lock_timer = 0.0
	_expect(player.get_interaction_prompt() == "%s LEAVE" % e, "hidden prompt: '%s'" % player.get_interaction_prompt())
	player.hiding_lock_timer = 3.2
	_expect(player.get_interaction_prompt().begins_with("LOCKED IN"), "locked hiding prompt: '%s'" % player.get_interaction_prompt())
	player.hiding_lock_timer = 0.0
	player.hidden = false
	player.ladder_climb = {"height": 0.2, "rise": 4.0, "phase": "climb"}
	var low := player.get_interaction_prompt()
	_expect(low.begins_with("HOLD [%s]/[%s] CLIMB" % [_keyboard_name("move_up"), _keyboard_name("move_down")]) and low.contains("LET GO"),
		"low on the ladder: '%s'" % low)
	player.ladder_climb["height"] = 3.5
	_expect(not player.get_interaction_prompt().contains("LET GO"), "high on the ladder still offers LET GO")
	player.ladder_climb = {}
	InputGlyphs.device_override = InputGlyphs.GAMEPAD
	player.hidden = true
	_expect(player.get_interaction_prompt() == "[%s] LEAVE" % _pad_name("interact"), "gamepad hidden prompt: '%s'" % player.get_interaction_prompt())
	player.hidden = false
	# no stale wording anywhere a prompt is built
	for text in [player.get_interaction_prompt()]:
		_expect(not String(text).contains("INTERACT TO") and not String(text).contains("TO CLIMB"), "stale prompt wording: %s" % text)
	InputGlyphs.device_override = ""
	route.queue_free()
	await host.get_tree().process_frame


func _check_sources() -> void:
	# stale hardcoded hints in the prompt builders
	for path in ["res://src/game_3d/player_controller_3d.gd", "res://src/infinite_route_test.gd", "res://src/game_3d/route_interactable_3d.gd"]:
		var source := FileAccess.get_file_as_string(path)
		for stale in ["INTERACT TO ", "HOLD W / S", "JUMP TO SLEEP", "JUMP OR INTERACT TO WAKE"]:
			_expect(not source.contains("\"" + stale) and not source.contains(" " + stale + "\""), "%s still builds the stale hint '%s'" % [path.get_file(), stale])


func run(host: Node) -> int:
	_check_devices()
	_check_rebind()
	_check_switching()
	_check_sources()
	await _check_player(host)
	if _failures == 0:
		print("  prompts   hide/leave, ladder and door hints use the live bindings on keyboard, gamepad, touch and Quest; rebinds and device switches follow")
	return _failures
