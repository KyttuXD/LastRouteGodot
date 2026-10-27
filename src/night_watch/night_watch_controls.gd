class_name NightWatchControls
extends RefCounted

## Night Watch's controls: the shared OFFICE actions of the InputMap (office_* in project.godot, the namespace Last Route's old
## office mode used) as the starting point, plus two Night Watch actions for the door lights, and gamepad defaults added while a
## shift is open. Registration lives in this one file so hooking the game into the per-game controls registry (the world lane's
## GAME_HUB/CONTROLS work) is a few lines: `controls_tab()` returns the data it needs.
##
## The player WALKS in the security room (WASD, mouse look, shift sprint, crouch, E to use): the shared actions of Last Route's
## controller. The old office_* defaults (A / D / L / C / R / V / B) clash with WASD, so Night Watch's quick keys are its own
## nw_* actions on non-movement keys: 1 / 2 doors, hold 3 / 4 the door lights, F the lamp, Tab the monitor, and R (office_radio,
## no clash) mutes Zellia. Inside the monitor 1-8 are the fixed camera hotbar (office_camera_1..8) as before.

const DOOR_LEFT := &"nw_door_left"
const DOOR_RIGHT := &"nw_door_right"
const LIGHT_LEFT := &"nw_light_left"
const LIGHT_RIGHT := &"nw_light_right"
const LAMP := &"nw_lamp"
const MONITOR := &"nw_monitor"

## Quick keys (Night Watch's own actions, away from the movement keys): 1 / 2 the doors, hold 3 / 4 the door lights, F the lamp, Tab
## the monitor. Everything also works physically in the room: aim at a station and press interact (E).
## action -> [key, gamepad button, gamepad trigger axis]
const DEFAULTS := {
	&"nw_door_left": [KEY_1, JOY_BUTTON_LEFT_SHOULDER, -1],
	&"nw_door_right": [KEY_2, JOY_BUTTON_RIGHT_SHOULDER, -1],
	&"nw_light_left": [KEY_3, -1, JOY_AXIS_TRIGGER_LEFT],
	&"nw_light_right": [KEY_4, -1, JOY_AXIS_TRIGGER_RIGHT],
	&"nw_lamp": [KEY_F, JOY_BUTTON_X, -1],
	&"nw_monitor": [KEY_TAB, JOY_BUTTON_Y, -1],
}

static var _added: Array = []   # action names this file created, removed again on unregister()


## Make sure every Night Watch action exists with its key and gamepad default. Safe to call more than once. The shared office_*
## actions (A / D / L / C / R ...) are left alone: they clash with walking, so this game reads none of them except
## office_radio (R, Zellia's radio) and the fixed office_camera_1..8 hotbar inside the monitor.
static func register() -> void:
	for action in DEFAULTS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.5)
		_added.append(action)
		var def: Array = DEFAULTS[action]
		var k := InputEventKey.new()
		k.physical_keycode = def[0]
		InputMap.action_add_event(action, k)
		if int(def[1]) >= 0:
			var b := InputEventJoypadButton.new()
			b.button_index = def[1]
			InputMap.action_add_event(action, b)
		if int(def[2]) >= 0:
			var t := InputEventJoypadMotion.new()
			t.axis = def[2]
			t.axis_value = 1.0
			InputMap.action_add_event(action, t)


## Take back what register() added, so Last Route's input set is untouched.
static func unregister() -> void:
	for action in _added:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	_added.clear()


## The camera hotbar action for camera n (1-8), fixed like the original (not rebindable).
static func camera_action(n: int) -> StringName:
	return StringName("office_camera_%d" % n)


## For the per-game controls registry: the OFFICE tab, the actions in display order with their labels. Movement, looking, sprint,
## crouch and interact are the shared ones (move_*, sprint, crouch, interact).
static func controls_tab() -> Dictionary:
	return {
		"id": "night_watch_office", "title": "OFFICE", "game": NightWatchData.GAME_ID,
		"actions": [
			{"action": "nw_door_left", "label": "LEFT DOOR (QUICK KEY)"}, {"action": "nw_door_right", "label": "RIGHT DOOR (QUICK KEY)"},
			{"action": "nw_light_left", "label": "LEFT DOOR LIGHT (HOLD)"}, {"action": "nw_light_right", "label": "RIGHT DOOR LIGHT (HOLD)"},
			{"action": "nw_monitor", "label": "MONITOR / LEAVE MONITOR"}, {"action": "nw_lamp", "label": "DESK LAMP"},
			{"action": "office_radio", "label": "RADIO (MUTE ZELLIA)"}, {"action": "interact", "label": "USE (PANELS, MONITOR, CHAIR, LAMP)"},
			{"action": "office_vent", "label": "VENT HATCH (LATER MODES)"}, {"action": "office_breaker", "label": "BREAKER (LATER MODES)"},
		],
	}
