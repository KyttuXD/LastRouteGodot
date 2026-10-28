class_name XRHands
extends Node

## OpenXR hand interactions for the route player (docs/XR_ANDROID.md, milestone 4). Created by PlayerController3D only
## once OpenXR has started, beside XRComfort. Every interaction ends in the same player code a keyboard drives, so
## networking, sounds and validators see nothing new:
##
##   ladder      on a ladder, hold grip and pull the hand down to climb up (hand over hand, 1:1); push up to climb down
##   swing       a fast swing of the right hand with the crowbar or rescue axe selected swings it (PlayerController3D.xr_swing)
##   poke        the right hand's fingertip touching a door, switch or relay works it like [E] (xr_poke)
##   point       the right trigger works what the right hand points at (the interaction ray follows the hand)
##   flashlight  the lamp's beam comes from the left hand
##
## Hand positions are read in the origin's own space, so walking, snap turns and the climb itself never count as hand
## movement.

const GRIP_HOLD := 0.6
const SWING_SPEED := 2.2
const SWING_COOLDOWN := 0.45
const POKE_DISTANCE := 0.12
const POKE_REARM_DISTANCE := 0.22
const FINGERTIP := Vector3(0.0, -0.02, -0.09)

var player: Node3D
var origin: XROrigin3D
var left: XRController3D
var right: XRController3D
var _last := {}
var _climb_hand := ""
var _swing_cooldown := 0.0
var _poked: Node3D


## Metres the runner climbs for one frame of a gripping hand: pulling the hand down by d lifts the body by d.
static func climb_pull(previous_height: float, height: float) -> float:
	return previous_height - height


## Whether a hand moving `travel` metres in `delta` seconds is a swing.
static func is_swing(travel: Vector3, delta: float) -> bool:
	return delta > 0.0 and travel.length() / delta >= SWING_SPEED


func setup(run_player: Node3D, xr_origin: XROrigin3D, xr_left: XRController3D, xr_right: XRController3D) -> void:
	player = run_player
	origin = xr_origin
	left = xr_left
	right = xr_right


func _hand_local(hand: XRController3D) -> Vector3:
	return origin.global_transform.affine_inverse() * hand.global_position


func step(delta: float) -> void:
	var now := {"left": _hand_local(left), "right": _hand_local(right)}
	_swing_cooldown = maxf(0.0, _swing_cooldown - delta)
	if bool(player.call("is_climbing")):
		_step_climb(now)
	else:
		_climb_hand = ""
		_step_swing(now, delta)
		_step_poke()
	_last = now
	(player.get("flashlight") as Node3D).global_transform = left.global_transform.translated_local(Vector3(0.0, 0.0, -0.06))


func _step_climb(now: Dictionary) -> void:
	# The hand that grabbed most recently holds the rung; letting go hands over to the other one if it still grips.
	for side in ["left", "right"]:
		var hand: XRController3D = left if side == "left" else right
		var gripping := hand.get_float("grip") >= GRIP_HOLD
		if gripping and _climb_hand != side and not _was_gripping(side):
			_climb_hand = side
		elif not gripping and _climb_hand == side:
			_climb_hand = ""
	if _climb_hand.is_empty():
		for side in ["left", "right"]:
			if (left if side == "left" else right).get_float("grip") >= GRIP_HOLD:
				_climb_hand = side
	_set_gripping(now)
	if _climb_hand.is_empty() or not _last.has(_climb_hand):
		return
	var pull := climb_pull(Vector3(_last[_climb_hand]).y, Vector3(now[_climb_hand]).y)
	if absf(pull) > 0.0005:
		player.call("xr_climb_pull", pull)


var _gripping := {}


func _was_gripping(side: String) -> bool:
	return bool(_gripping.get(side, false))


func _set_gripping(_now: Dictionary) -> void:
	_gripping = {"left": left.get_float("grip") >= GRIP_HOLD, "right": right.get_float("grip") >= GRIP_HOLD}


func _step_swing(now: Dictionary, delta: float) -> void:
	if _swing_cooldown > 0.0 or not _last.has("right"):
		return
	if is_swing(Vector3(now["right"]) - Vector3(_last["right"]), delta) and bool(player.call("xr_swing")):
		_swing_cooldown = SWING_COOLDOWN


func _step_poke() -> void:
	var tip := right.global_transform * FINGERTIP
	if _poked != null:
		if not is_instance_valid(_poked) or tip.distance_to(_poked.call("interaction_focus")) > POKE_REARM_DISTANCE:
			_poked = null
		return
	for candidate in get_tree().get_nodes_in_group("interactable"):
		if candidate is RouteInteractable3D and tip.distance_to(candidate.interaction_focus()) <= POKE_DISTANCE:
			_poked = candidate
			player.call("xr_poke", candidate)
			return
