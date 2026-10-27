class_name NightWatchControls
extends RefCounted

## Night Watch's controls. Registration lives in this one file so hooking the game into the per-game controls registry (the world
## lane's GAME_HUB/CONTROLS work) is a few lines: `controls_tab()` returns the data it needs.
##
## The player WALKS with the shared controller (PlayerController3D: WASD, mouse look, sprint, crouch, jump, E to use, the shared pause key,
## the same gamepad mapping): Night Watch changes none of it. Its stations are used with the same INTERACT action. The only Night Watch
## actions are optional quick keys on keys the shared input map leaves free (the validator checks that none is bound to anything else
## except the old office_* actions): Z / X the left / right door, hold G / H the left / right door light, Y the desk lamp, U the monitor;
## R (office_radio, no clash) mutes Zellia. Digits 1-5 stay the shared inventory slots; inside the monitor 1-8 are the fixed camera
## hotbar (office_camera_1..8) as before. Gamepad: no new button mapping (the shared mapping stands; the quick keys have none, the
## panels and the monitor are used with the shared interact button).

const DOOR_LEFT := &"nw_door_left"
const DOOR_RIGHT := &"nw_door_right"
const LIGHT_LEFT := &"nw_light_left"
const LIGHT_RIGHT := &"nw_light_right"
const LAMP := &"nw_lamp"
const MONITOR := &"nw_monitor"

## Quick keys (Night Watch's own actions, on keys the shared input map leaves free). Everything also works physically in the room:
## aim at a station and press interact (E). action -> key
const DEFAULTS := {
	&"nw_door_left": KEY_Z,
	&"nw_door_right": KEY_X,
	&"nw_light_left": KEY_G,
	&"nw_light_right": KEY_H,
	&"nw_lamp": KEY_Y,
	&"nw_monitor": KEY_U,
}

static var _added: Array = []   # action names this file created, removed again on unregister()


## Make sure every Night Watch action exists with its key. Safe to call more than once. The old office_* actions (A / D / L / C ...)
## clash with walking, so this game reads none of them except office_radio (R, Zellia's radio) and the fixed office_camera_1..8
## hotbar inside the monitor.
static func register() -> void:
	for action in DEFAULTS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.5)
		_added.append(action)
		var k := InputEventKey.new()
		k.physical_keycode = DEFAULTS[action]
		InputMap.action_add_event(action, k)


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
			{"action": "nw_monitor", "label": "MONITOR (QUICK KEY)"}, {"action": "nw_lamp", "label": "DESK LAMP"},
			{"action": "office_radio", "label": "RADIO (MUTE ZELLIA)"}, {"action": "interact", "label": "USE (PANELS, MONITOR, CHAIR, LAMP)"},
			{"action": "office_vent", "label": "VENT HATCH (LATER MODES)"}, {"action": "office_breaker", "label": "BREAKER (LATER MODES)"},
		],
	}
