class_name PlaytestInput
extends RefCounted

## Injects bot/script input through the real input path (Input.action_press / release), so the player controller, menus and
## pause code see the same actions a keyboard or controller would send.
##
## act = {
##   "move": [strafe_right, forward]   each -1..1 (forward positive)
##   "look": [turn_right, look_down]   each -1..1, scaled like the controller stick (deterministic, no mouse capture needed)
##   "hold": {"sprint": true, "crouch": false, "jump": true}     level actions, kept until changed
##   "pulse": ["interact", "flashlight"]                          pressed for one physics frame, then released
## }

const HELD_ACTIONS := ["sprint", "crouch", "jump"]
const PULSE_ACTIONS := ["interact", "flashlight", "taser", "tool_use", "drop_item", "inventory", "toggle_map", "pause",
	"chat", "hotbar_previous", "hotbar_next", "ui_accept", "ui_cancel", "ui_up", "ui_down", "ui_left", "ui_right",
	"office_left_door", "office_right_door", "office_desk_light", "office_vent", "office_cameras", "office_radio",
	"office_breaker", "office_reboot", "office_emergency_flash", "office_rear_flash"]

var _pulsed: Array = []
var _held := {}
var _axes := {}


## Call at the start of each physics frame: releases last frame's pulses.
func begin_frame() -> void:
	for action in _pulsed:
		Input.action_release(action)
	_pulsed.clear()


func apply(act: Dictionary) -> void:
	if act.has("move"):
		var move: Array = act["move"]
		_set_axis("move_left", "move_right", float(move[0]) if move.size() > 0 else 0.0)
		_set_axis("move_up", "move_down", -float(move[1]) if move.size() > 1 else 0.0)
	if act.has("look"):
		var look: Array = act["look"]
		_set_axis("look_left", "look_right", float(look[0]) if look.size() > 0 else 0.0)
		_set_axis("look_up", "look_down", float(look[1]) if look.size() > 1 else 0.0)
	if act.has("hold"):
		var hold: Dictionary = act["hold"]
		for action in hold:
			_set_held(String(action), bool(hold[action]))
	if act.has("pulse"):
		for action in act["pulse"]:
			pulse(String(action))


func pulse(action: String) -> void:
	if not InputMap.has_action(action):
		return
	Input.action_press(action, 1.0)
	if not _pulsed.has(action):
		_pulsed.append(action)


func release_all() -> void:
	for action in _pulsed:
		Input.action_release(action)
	_pulsed.clear()
	for action in _held.keys():
		Input.action_release(action)
	_held.clear()
	for action in _axes.keys():
		Input.action_release(action)
	_axes.clear()


## A look target in radians for a stick strength that closes `error` in one physics step (clamped), used by bots.
static func look_strength(error: float, rate_per_second: float, delta: float) -> float:
	if rate_per_second <= 0.0 or delta <= 0.0:
		return 0.0
	return clampf(error / (rate_per_second * delta), -1.0, 1.0)


func _set_axis(negative: String, positive: String, value: float) -> void:
	value = clampf(value, -1.0, 1.0)
	_set_strength(negative, maxf(-value, 0.0))
	_set_strength(positive, maxf(value, 0.0))


func _set_strength(action: String, strength: float) -> void:
	if not InputMap.has_action(action):
		return
	if strength <= 0.0:
		if _axes.has(action):
			Input.action_release(action)
			_axes.erase(action)
	else:
		Input.action_press(action, strength)
		_axes[action] = strength


func _set_held(action: String, down: bool) -> void:
	if not InputMap.has_action(action):
		return
	if down:
		Input.action_press(action, 1.0)
		_held[action] = true
	elif _held.has(action):
		Input.action_release(action)
		_held.erase(action)
