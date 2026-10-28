class_name NeckLift
extends Node3D

## The neck-lift catch (GrabStyles.NECK_LIFT): the hunter's right arm reaches out, takes the runner by the neck with one hand, and
## raises them until their feet are off the floor, then holds. The caller ends the run afterwards. Local runner: the eye rises and
## tips back with the lift and the skinned hands come up to the hunter's wrist (PlayerController3D.set_lift_view). Everyone else: the
## runner's state carries `lift` (metres) and RemotePlayers draws the body that high on the falling clip, and poses the nearest
## lifting hunter's arm at the neck through pose_nearest_hunter, so a guest sees the same grab without any extra packet.
## The hunter itself is still simulated by the host; only its arm bones are bent here, after its animation has run.

const MAX_LIFT := 1.2
const REACH_SECONDS := .35
const RISE_SECONDS := .6
const HOLD_SECONDS := .9
const TOTAL_SECONDS := REACH_SECONDS + RISE_SECONDS + HOLD_SECONDS
## Where the neck sits on the standing runner's body (below the eye) and how far along the arm the hand takes hold.
const NECK_BELOW_EYE := .24
const HAND_REACH := .95
const HAND_DROP := .1
## The runner's neck is this far past the hunter's palm (the hand closes on the front of the throat).
const NECK_DEPTH := .14
const SEARCH_RADIUS := 2.4
## Feet to neck on the 1.60 m runner body other players see.
const BODY_NECK := 1.36

var playing := false
var elapsed := 0.0
var last_lift := 0.0
var _player: PlayerController3D
var _view: Node3D
var _neck := Vector3.ZERO
var _lift_target := 0.0


func _init() -> void:
	process_priority = 60   # after the hunter view bends its head and the clips have run


static func smooth(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


## Phase values at `t` seconds: how far the arm has reached, how far the runner has risen (both 0..1) and whether it is holding.
static func phase(t: float) -> Dictionary:
	return {
		"reach": smooth(t / REACH_SECONDS),
		"rise": smooth((t - REACH_SECONDS) / RISE_SECONDS),
		"holding": t >= REACH_SECONDS + RISE_SECONDS,
	}


## The right arm, forearm and hand nodes of a hunter model (any of them null for a rig without them).
static func arm_nodes(root: Node) -> Dictionary:
	return {
		"arm": root.find_child("R-Arm", true, false),
		"forearm": root.find_child("R-Forearm", true, false),
		"hand": root.find_child("R-Hand", true, false),
	}


## Shoulder to hand in world space, which is how far the hunter can reach.
static func arm_length(root: Node) -> float:
	var nodes := arm_nodes(root)
	if nodes["arm"] == null or nodes["hand"] == null:
		return 0.0
	return ((nodes["hand"] as Node3D).global_position - (nodes["arm"] as Node3D).global_position).length()


## Swings the right arm from wherever the clip left it towards `target`, forearm straight, `amount` 0..1 of the way.
static func pose_arm(root: Node, target: Vector3, amount: float) -> void:
	var nodes := arm_nodes(root)
	var arm := nodes["arm"] as Node3D
	var hand := nodes["hand"] as Node3D
	if arm == null or hand == null or amount <= 0.0:
		return
	var forearm := nodes["forearm"] as Node3D
	if forearm != null:
		forearm.basis = forearm.basis.orthonormalized().slerp(Basis.IDENTITY, amount) * Basis.from_scale(forearm.basis.get_scale())
	var reach := hand.global_position - arm.global_position
	var wanted := target - arm.global_position
	if reach.length_squared() < .0001 or wanted.length_squared() < .0001:
		return
	var swing := Quaternion(reach.normalized(), wanted.normalized())
	var scale := arm.global_basis.get_scale()
	var blended := Quaternion.IDENTITY.slerp(swing, clampf(amount, 0.0, 1.0))
	arm.global_basis = (Basis(blended) * arm.global_basis.orthonormalized()) * Basis.from_scale(scale)


## A lifting hunter's neck point for a runner whose feet are at `feet` raised by `lift` metres.
static func neck_of(feet: Vector3, lift: float, eye_height: float) -> Vector3:
	return feet + Vector3(0.0, eye_height - NECK_BELOW_EYE + lift, 0.0)


## Where a hunter's hand closes when it lifts a runner standing in `direction` (flat, hunter to runner): the arm nearly straight
## out at shoulder height.
static func grip_point(view: Node3D, direction: Vector3) -> Vector3:
	var arm := arm_nodes(view)["arm"] as Node3D
	var shoulder := arm.global_position if arm != null else view.global_position + Vector3.UP * 1.8
	var length := maxf(arm_length(view), .5)
	return shoulder + direction * length * HAND_REACH + Vector3.DOWN * length * HAND_DROP


## Guests and the host see another runner lifted: the nearest hunter that grabs this way (within SEARCH_RADIUS) takes them by the neck.
static func pose_nearest_hunter(from: Node, body: Node3D, _lifted: bool) -> void:
	if from == null or not from.is_inside_tree():
		return
	var best: Node3D = null
	var best_distance := SEARCH_RADIUS
	for node in from.get_tree().get_nodes_in_group("hunter_views"):
		var view := node as Node3D
		if view == null or not view.visible:
			continue
		var id := String(view.call("shown_id")) if view.has_method("shown_id") else ""
		if not GrabStyles.lifts(id):
			continue
		var flat := Vector2(view.global_position.x - body.global_position.x, view.global_position.z - body.global_position.z)
		if flat.length() < best_distance:
			best_distance = flat.length()
			best = view
	if best != null:
		pose_arm(best, body.global_position + Vector3(0.0, BODY_NECK, 0.0), 1.0)


## Runs the whole catch on the local runner; returns when the hold ends (the runner stays raised until release()).
func play(player: PlayerController3D, view: Node3D) -> void:
	if playing or player == null or view == null:
		return
	_player = player
	_view = view
	playing = true
	elapsed = 0.0
	var flat := Vector3(player.global_position.x - view.global_position.x, 0.0, player.global_position.z - view.global_position.z)
	var direction := flat.normalized() if flat.length() > .01 else -view.global_basis.z
	var eye := player._standing_camera_height
	_neck = grip_point(view, direction)
	# feet leave the floor by the gap between where the hand is and where the standing runner's neck is
	_lift_target = clampf(_neck.y - (player.global_position.y + eye - NECK_BELOW_EYE), .3, MAX_LIFT)
	var stand := Vector3(_neck.x, player.global_position.y, _neck.z) + direction * NECK_DEPTH
	var start := player.global_position
	# the runner is turned to face the hunter's head (the hand is off to one side, at her right shoulder)
	var head := view.find_child("Head", true, false) as Node3D
	var look_at_point := head.global_position if head != null else view.global_position
	var to_head := Vector3(look_at_point.x - stand.x, 0.0, look_at_point.z - stand.z)
	var start_yaw: float = player._yaw
	var start_pitch: float = player._pitch
	var face_yaw := atan2(-to_head.x, -to_head.z) if to_head.length() > .01 else start_yaw
	while elapsed < TOTAL_SECONDS and is_inside_tree() and is_instance_valid(player) and is_instance_valid(view):
		var step := get_process_delta_time()
		elapsed += step
		var p := phase(elapsed)
		player.global_position = start.lerp(stand, float(p["reach"]))
		player._yaw = lerp_angle(start_yaw, face_yaw, float(p["reach"]))
		player._pitch = lerpf(start_pitch, 0.0, float(p["reach"]))
		player.velocity = Vector3.ZERO
		last_lift = _lift_target * float(p["rise"])
		var sway := sin(elapsed * 9.0) * .03 * float(p["rise"])
		player.set_lift_view(last_lift, .25 * float(p["rise"]), .07 * float(p["rise"]) + sway, float(p["reach"]))
		# the hand closes on the standing runner's neck, then carries it up
		pose_arm(view, _neck + Vector3.UP * (last_lift - _lift_target), float(p["reach"]))
		await get_tree().process_frame
	playing = false


func _process(_delta: float) -> void:
	# keep the arm on the neck through the hold, after the clips have been applied this frame
	if playing or _view == null or not is_instance_valid(_view) or last_lift <= 0.0:
		return
	pose_arm(_view, _neck, 1.0)


## Puts the runner back down (a new run, or the catch was cancelled).
func release() -> void:
	playing = false
	last_lift = 0.0
	if _player != null and is_instance_valid(_player):
		_player.set_lift_view(0.0, 0.0, 0.0, 0.0)
	_view = null
