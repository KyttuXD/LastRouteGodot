class_name NightWatchControls
extends RefCounted

## Night Watch's controls: the shared OFFICE actions of the InputMap (office_* in project.godot, the namespace Last Route's old
## office mode used) as the starting point, plus two Night Watch actions for the door lights, and gamepad defaults added while a
## shift is open. Registration lives in this one file so hooking the game into the per-game controls registry (the world lane's
## GAME_HUB/CONTROLS work) is a few lines: `controls_tab()` returns the data it needs.
##
## Keys (the office actions' defaults): A / D shut the left / right door, hold Q / E the left / right door light, C (or Space) the
## monitor, 1-8 the cameras, L the desk lamp, R Zellia's radio (mutes her call), N / V / B / F are reserved for the other modes
## (reboot, vent hatch, breaker, flash). Mouse (or the arrow keys, or the right stick) looks around the office.
##
## Conflicts with the movement keys: Night Watch has no walking and reads no move_* action, so A / D never move you here. Last
## Route's look keys I / J / K / L would clash with the desk lamp on L, so the office reads only the mouse, the arrow keys and
## the right stick for looking, never the letter bindings of look_*. The OFFICE actions live in their own namespace, so
## rebinding a Last Route key never touches them.

const LIGHT_LEFT := &"office_light_left"
const LIGHT_RIGHT := &"office_light_right"

## action -> gamepad button added while a shift is open (when the action has no pad event of its own)
const PAD_BUTTONS := {
	&"office_left_door": JOY_BUTTON_LEFT_SHOULDER,
	&"office_right_door": JOY_BUTTON_RIGHT_SHOULDER,
	&"office_cameras": JOY_BUTTON_Y,
	&"office_desk_light": JOY_BUTTON_X,
	&"office_radio": JOY_BUTTON_B,
}

static var _added: Array = []   # [action, event] pairs this file added, removed again on unregister()


static func _has_event_of(action: StringName, type: String) -> bool:
	for e in InputMap.action_get_events(action):
		if e.get_class() == type:
			return true
	return false


static func _add(action: StringName, event: InputEvent) -> void:
	InputMap.action_add_event(action, event)
	_added.append([action, event])


## Make sure every action Night Watch reads exists and has a gamepad default. Safe to call more than once.
static func register() -> void:
	if not InputMap.has_action(LIGHT_LEFT):
		InputMap.add_action(LIGHT_LEFT, 0.5)
		var q := InputEventKey.new()
		q.physical_keycode = KEY_Q
		_add(LIGHT_LEFT, q)
		var lt := InputEventJoypadMotion.new()
		lt.axis = JOY_AXIS_TRIGGER_LEFT
		lt.axis_value = 1.0
		_add(LIGHT_LEFT, lt)
	if not InputMap.has_action(LIGHT_RIGHT):
		InputMap.add_action(LIGHT_RIGHT, 0.5)
		var e := InputEventKey.new()
		e.physical_keycode = KEY_E
		_add(LIGHT_RIGHT, e)
		var rt := InputEventJoypadMotion.new()
		rt.axis = JOY_AXIS_TRIGGER_RIGHT
		rt.axis_value = 1.0
		_add(LIGHT_RIGHT, rt)
	for action in PAD_BUTTONS:
		if InputMap.has_action(action) and not _has_event_of(action, "InputEventJoypadButton"):
			var b := InputEventJoypadButton.new()
			b.button_index = PAD_BUTTONS[action]
			_add(action, b)


## Take back what register() added (the light actions and the pad defaults), so Last Route's input set is untouched.
static func unregister() -> void:
	for pair in _added:
		var action: StringName = pair[0]
		if InputMap.has_action(action):
			if action == LIGHT_LEFT or action == LIGHT_RIGHT:
				pass
			else:
				InputMap.action_erase_event(action, pair[1])
	for action in [LIGHT_LEFT, LIGHT_RIGHT]:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	_added.clear()


## The camera hotbar action for camera n (1-8), fixed like the original (not rebindable).
static func camera_action(n: int) -> StringName:
	return StringName("office_camera_%d" % n)


## For the per-game controls registry: the OFFICE tab, the actions in display order with their labels.
static func controls_tab() -> Dictionary:
	return {
		"id": "night_watch_office", "title": "OFFICE", "game": NightWatchData.GAME_ID,
		"actions": [
			{"action": "office_left_door", "label": "LEFT DOOR"}, {"action": "office_right_door", "label": "RIGHT DOOR"},
			{"action": String(LIGHT_LEFT), "label": "LEFT DOOR LIGHT (HOLD)"}, {"action": String(LIGHT_RIGHT), "label": "RIGHT DOOR LIGHT (HOLD)"},
			{"action": "office_cameras", "label": "MONITOR"}, {"action": "office_desk_light", "label": "DESK LAMP"},
			{"action": "office_radio", "label": "RADIO (MUTE ZELLIA)"}, {"action": "office_vent", "label": "VENT HATCH (LATER MODES)"},
			{"action": "office_breaker", "label": "BREAKER (LATER MODES)"}, {"action": "office_reboot", "label": "REBOOT (LATER MODES)"},
		],
	}


## Looking around: the arrow keys and the right stick (never the I / J / K / L letters, see the header). Returns (yaw, pitch) rates.
static func look_rate() -> Vector2:
	var x := 0.0
	var y := 0.0
	if Input.is_key_pressed(KEY_LEFT):
		x += 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		x -= 1.0
	if Input.is_key_pressed(KEY_UP):
		y += 1.0
	if Input.is_key_pressed(KEY_DOWN):
		y -= 1.0
	var sx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var sy := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(sx) > 0.2:
		x -= sx
	if absf(sy) > 0.2:
		y -= sy
	return Vector2(x, y)
