class_name MixedControls
extends RefCounted

## Mixed Shift's own quick keys, on keys the shared input map leaves free (the old office_* actions on them are not read): hold V / B / N to seal the left / top / right
## vent (2D: Q / W / E); the vent light is a tap of G / Y / H (the shared nw_light_left / nw_lamp / nw_light_right actions, 2D: Z / X / C); R held winds the music box;
## Z / X the doors; U the monitor. Everything also works at the stations (hold use on a vent hatch). Registered and removed with the shift, like Classic's.

const SEAL_LEFT := &"nw_mx_seal_l"
const SEAL_TOP := &"nw_mx_seal_t"
const SEAL_RIGHT := &"nw_mx_seal_r"
const SEALS := {&"nw_mx_seal_l": ["L", KEY_V], &"nw_mx_seal_t": ["T", KEY_B], &"nw_mx_seal_r": ["R", KEY_N]}
## vent key -> the action that flashes its light
const FLASH := {"L": &"nw_light_left", "T": &"nw_lamp", "R": &"nw_light_right"}

static var _added: Array = []


static func register() -> void:
	for action in SEALS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.5)
		_added.append(action)
		var k := InputEventKey.new()
		k.physical_keycode = SEALS[action][1]
		InputMap.action_add_event(action, k)


static func unregister() -> void:
	for action in _added:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	_added.clear()


static func hint(monitor_up: bool) -> String:
	if monitor_up:
		return "%s / %s or 1-8 camera   9 vent run   %s or %s close   hold %s wind (on the box's camera)" % [NightWatchControls.key_text(NightWatchControls.CAM_PREV),
			NightWatchControls.key_text(NightWatchControls.CAM_NEXT), NightWatchControls.key_text(NightWatchControls.MONITOR), NightWatchControls.key_text(&"interact"), NightWatchControls.key_text(&"office_radio")]
	return "WASD move   E use   Z / X doors   hold V / B / N seal vents L / T / R   tap G / Y / H vent light   U monitor   hold R wind   P pause"
