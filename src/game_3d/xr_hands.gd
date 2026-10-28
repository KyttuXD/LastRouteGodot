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
##
## The controllers track Godot's "default" pose, which OpenXR binds to the AIM pose (the laser direction, pitched well
## down from how the hand holds the controller). The hand models were built for the GRIP pose, so each frame they are
## turned by aim->grip from the controller's own tracker (exact for every controller; KT saw them about 90 degrees off).

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
	for hand in [left, right]:
		hand.add_child(_hand_mesh(hand == left, Settings.effective_slim()))
	Settings.visual_changed.connect(_wear_skin)


## The runner's own hand on each controller: the mannequin's forearm and hand cubes (the same parts as the first-person hand on
## flat screens), wearing the player's skin. Falls back to the plain glove boxes if the mannequin cannot be read.
static func _hand_mesh(is_left: bool, slim: bool = false) -> Node3D:
	var hand := Node3D.new()
	hand.name = "HandModel"
	var parts := PlayerController3D._mannequin_hand_parts(slim)
	if not parts.is_empty():
		var rig := Node3D.new()
		rig.name = "SkinnedHand"
		rig.set_meta("slim", slim)
		# the parts are relative to the mannequin's right-hand prop point; mirror for the left, runner scale
		rig.basis = Basis.from_scale(Vector3(-1.0 if is_left else 1.0, 1.0, 1.0) * PlayerModels.SCALE)
		for part_value in parts:
			var part: Array = part_value
			var mesh_node := MeshInstance3D.new()
			mesh_node.mesh = part[0]
			if part[1] != null:
				mesh_node.material_override = part[1]
			mesh_node.transform = part[2]
			mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			rig.add_child(mesh_node)
		hand.add_child(rig)
		PlayerSkin.apply(rig, PlayerSkin.active_texture())
		return hand
	var glove := StandardMaterial3D.new()
	glove.albedo_color = Color(0.16, 0.13, 0.17)
	for part in [[Vector3(0.07, 0.03, 0.1), Vector3(0, 0, 0.02)], [Vector3(0.025, 0.025, 0.06), Vector3(0.045 if is_left else -0.045, 0.005, -0.01)]]:
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = part[0]
		box.mesh = mesh
		box.material_override = glove
		box.position = part[1]
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hand.add_child(box)
	return hand


func _wear_skin() -> void:
	for hand in [left, right]:
		var rig := hand.find_child("SkinnedHand", true, false) as Node3D if hand != null else null
		if rig != null and bool(rig.get_meta("slim", false)) != Settings.effective_slim():
			var old := rig.get_parent()
			var placed := (old as Node3D).transform
			hand.remove_child(old)
			old.free()
			var fresh := _hand_mesh(hand == left, Settings.effective_slim())
			fresh.transform = placed
			hand.add_child(fresh)
			rig = fresh.find_child("SkinnedHand", true, false) as Node3D
		if rig != null:
			PlayerSkin.apply(rig, PlayerSkin.active_texture())


func _hand_local(hand: XRController3D) -> Vector3:
	return origin.global_transform.affine_inverse() * hand.global_position


## The hand model's transform under an aim-pose controller that puts it on the grip pose (identity without a grip pose).
static func grip_offset(tracker: XRPositionalTracker) -> Transform3D:
	if tracker == null:
		return Transform3D.IDENTITY
	var aim := tracker.get_pose(&"default")
	var grip := tracker.get_pose(&"grip")
	if aim == null or grip == null or not aim.has_tracking_data or not grip.has_tracking_data:
		return Transform3D.IDENTITY
	return aim.transform.affine_inverse() * grip.transform


func _fit_hands_to_grip() -> void:
	for hand in [left, right]:
		var model := hand.get_node_or_null(^"HandModel") as Node3D
		if model != null:
			model.transform = grip_offset(XRServer.get_tracker(hand.tracker) as XRPositionalTracker)


func step(delta: float) -> void:
	_fit_hands_to_grip()
	var now := {"left": _hand_local(left), "right": _hand_local(right)}
	_swing_cooldown = maxf(0.0, _swing_cooldown - delta)
	if bool(player.call("is_climbing")):
		_step_climb(now)
	else:
		_climb_hand = ""
		_step_swing(now, delta)
		_step_poke()
	_last = now
	var lamp_source: Node3D = left if left.get_has_tracking_data() else player.get("xr_camera") as Node3D
	var offset := Vector3(0.0, 0.0, -0.06) if lamp_source == left else Vector3(0.0, -0.08, -0.18)
	(player.get("flashlight") as Node3D).global_transform = lamp_source.global_transform.translated_local(offset)


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
