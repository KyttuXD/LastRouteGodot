class_name StoryControls
extends RefCounted

## The Facility's two held keys, the 2D game's: F holds the beacon on whoever is in front of you, H hides you under the desk in Control. Walking, looking and
## using stations are the shared controller's (WASD, mouse, E); holding the shared crouch key (C) as you go through a door crawls. Registered on entering
## the shift and removed on leaving it, so Last Route's input set is untouched.

const BEACON := &"nw_fac_beacon"
const HIDE := &"nw_fac_hide"
const DEFAULTS := {&"nw_fac_beacon": KEY_F, &"nw_fac_hide": KEY_H}

static var _added: Array = []


static func register() -> void:
	for action in DEFAULTS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.5)
		_added.append(action)
		var k := InputEventKey.new()
		k.physical_keycode = DEFAULTS[action]
		InputMap.action_add_event(action, k)


static func unregister() -> void:
	for action in _added:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	_added.clear()
