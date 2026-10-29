class_name NightWatchOpenAirControls
extends RefCounted

## Open Air's two extra quick keys, on keys the shared input map leaves free (the rest are Night Watch's own: Z / X bar the stair door and
## the hatch, G / H hold the torch left / right, Y the heat lamp or a log; see NightWatchControls). Everything also works physically: aim
## at a station and press interact (E), hold interact on a torch, the lantern or the firewood.
##   F  hold: relight the lantern (rooftop) / fetch firewood (campfire)
##   T  the tent (campfire): in when you are out, out when you are in

const RELIGHT := &"nw_oa_relight"
const TENT := &"nw_oa_tent"
const DEFAULTS := {RELIGHT: KEY_F, TENT: KEY_T}

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
