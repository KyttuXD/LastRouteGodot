class_name BedroomControls
extends RefCounted

## Bedtime's three held keys, the 2D game's: A holds the closet door, D puts a light on the hall, F on the bed. There is no walking in bed, so
## A and D are free here. Registered on entering the shift and removed on leaving it, so Last Route's input set is untouched.

const HOLD := &"nw_bed_hold"
const HALL := &"nw_bed_hall"
const BED := &"nw_bed_light"
const DEFAULTS := {&"nw_bed_hold": KEY_A, &"nw_bed_hall": KEY_D, &"nw_bed_light": KEY_F}

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
