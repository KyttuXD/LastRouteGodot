class_name HunterGrab
extends Node3D

## Plays a caught runner's grab (GrabStyles: neck lift, tackle, leg grab, upside-down hold, ...) and holds it until the run ends.
## The local runner: the body slides to where the grab puts it, the first-person eye follows the head (lifted, knocked flat,
## upside down) and the skinned hands react (PlayerController3D.set_grab_view). Everyone else: the runner's state carries
## `grab` = [style, t, lift, body pitch, hunter forward, hunter drop, hunter lean] and RemotePlayers redraws the body from it and
## calls pose_nearest_hunter, so a guest sees the same grab with no extra packet. The hunter is still simulated by the host;
## only its model's lean/offset and arm bones are bent here, after its animation has run, and put back on release.

const SEARCH_RADIUS := 3.0
const ARM_SIDES := {"R": ["R-Arm", "R-Forearm", "R-Hand"], "L": ["L-Arm", "L-Forearm", "L-Hand"]}
## How far the surroundings are probed for room (GrabStyles.fits).
const PROBE_UP := 4.0
const PROBE_BACK := 3.0

var playing := false
var style := ""
var elapsed := 0.0
## The last pose and the state packet entry that describes it to other players (empty when nobody is held).
var current := {}
var state := []
var last_room := {}
var _player: PlayerController3D
var _view: Node3D
var _origin := Vector3.ZERO
var _along := Vector3.FORWARD
var _side := Vector3.RIGHT
var _ctx := {}
var _start := Vector3.ZERO


func _init() -> void:
	process_priority = 60   # after the hunter view's clips and head look have run this frame


## The hunter's shoulder, arm length and the room around the runner, measured in the frame from hunter to runner.
static func context(view: Node3D, runner_feet: Vector3, along: Vector3, eye: float, room: Dictionary) -> Dictionary:
	var side := along.cross(Vector3.UP).normalized()
	var arm := view.find_child("R-Arm", true, false) as Node3D
	var hand := view.find_child("R-Hand", true, false) as Node3D
	var ctx := {"eye": eye, "back": float(room.get("back", 99.0))}
	if arm != null and hand != null:
		var offset := arm.global_position - view.global_position
		ctx["shoulder_side"] = offset.dot(side)
		ctx["shoulder_fwd"] = offset.dot(along)
		ctx["shoulder_y"] = offset.y
		ctx["arm"] = maxf((hand.global_position - arm.global_position).length(), .4)
	return ctx


## How much room the runner has: clear height above them, clear floor behind them (away from the hunter) and behind the hunter.
static func probe_room(space: PhysicsDirectSpaceState3D, runner_feet: Vector3, hunter_feet: Vector3, along: Vector3,
		exclude: Array, mask: int) -> Dictionary:
	var ray := func(from: Vector3, to: Vector3) -> float:
		var query := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
		var hit := space.intersect_ray(query)
		return from.distance_to(hit["position"]) if not hit.is_empty() else from.distance_to(to)
	return {
		"ceiling": float(ray.call(runner_feet + Vector3.UP * .2, runner_feet + Vector3.UP * PROBE_UP)) + .2,
		# chest height and knee height: a body knocked flat needs the low props out of the way too
		"back": minf(float(ray.call(runner_feet + Vector3.UP, runner_feet + Vector3.UP + along * PROBE_BACK)),
			float(ray.call(runner_feet + Vector3.UP * .35, runner_feet + Vector3.UP * .35 + along * PROBE_BACK))),
		"hunter_back": float(ray.call(hunter_feet + Vector3.UP, hunter_feet + Vector3.UP - along * PROBE_BACK)),
	}


## Swings one of a hunter's arms from wherever its clip left it towards `target`, forearm straight, `amount` 0..1 of the way.
static func pose_arm(root: Node, arm_side: String, target: Vector3, amount: float) -> void:
	var names: Array = ARM_SIDES.get(arm_side, ARM_SIDES["R"])
	var arm := root.find_child(names[0], true, false) as Node3D
	var forearm := root.find_child(names[1], true, false) as Node3D
	var hand := root.find_child(names[2], true, false) as Node3D
	if arm == null or hand == null or amount <= 0.0:
		return
	if forearm != null:
		forearm.basis = forearm.basis.orthonormalized().slerp(Basis.IDENTITY, amount) * Basis.from_scale(forearm.basis.get_scale())
	var reach := hand.global_position - arm.global_position
	var wanted := target - arm.global_position
	if reach.length_squared() < .0001 or wanted.length_squared() < .0001:
		return
	var swing := Quaternion(reach.normalized(), wanted.normalized())
	var scale := arm.global_basis.get_scale()
	arm.global_basis = (Basis(Quaternion.IDENTITY.slerp(swing, clampf(amount, 0.0, 1.0))) * arm.global_basis.orthonormalized()) \
		* Basis.from_scale(scale)


## Leans, lowers and moves a hunter's model (not the simulated hunter) towards `along`: [forward, drop, lean]. Zeros put it back.
static func pose_hunter_body(view: Node3D, along: Vector3, offsets: Array) -> void:
	var model := view.get("_model") as Node3D if "_model" in view else null
	if model == null:
		return
	if not model.has_meta("grab_rest"):
		model.set_meta("grab_rest", model.transform)
	model.transform = model.get_meta("grab_rest")
	var forward := float(offsets[0]) if offsets.size() > 0 else 0.0
	var drop := float(offsets[1]) if offsets.size() > 1 else 0.0
	var lean := float(offsets[2]) if offsets.size() > 2 else 0.0
	if is_zero_approx(forward) and is_zero_approx(drop) and is_zero_approx(lean):
		model.remove_meta("grab_rest")
		return
	var placed := model.global_transform
	var axis := Vector3.UP.cross(along).normalized()
	if axis.length_squared() > .5:
		placed.basis = Basis(axis, lean) * placed.basis
	placed.origin += along * forward + Vector3.DOWN * drop
	model.global_transform = placed


## The hunter's hands on a runner body: `feet` and `basis` place the body (GrabStyles.body_basis), `arms` from the pose.
static func pose_arms_on(view: Node3D, feet: Vector3, basis: Basis, arms: Array, body_scale: float = 1.0) -> void:
	for entry in arms:
		var point: Vector3 = GrabStyles.BODY_POINTS.get(String(entry[1]), GrabStyles.BODY_POINTS["neck"])
		pose_arm(view, String(entry[0]), feet + basis * (point * body_scale), float(entry[2]))


## A guest's (or the host's) copy of a held runner: the nearest hunter takes the grab pose the runner's state describes.
static func pose_nearest_hunter(from: Node, body: Node3D, packet: Array) -> void:
	if from == null or not from.is_inside_tree() or packet.size() < 7:
		return
	var best: Node3D = null
	var best_distance := SEARCH_RADIUS
	for node in from.get_tree().get_nodes_in_group("hunter_views"):
		var view := node as Node3D
		if view == null or not view.visible:
			continue
		var flat := Vector2(view.global_position.x - body.global_position.x, view.global_position.z - body.global_position.z)
		if flat.length() < best_distance:
			best_distance = flat.length()
			best = view
	if best == null:
		return
	var along := Vector3(body.global_position.x - best.global_position.x, 0.0, body.global_position.z - best.global_position.z)
	along = along.normalized() if along.length() > .01 else Vector3.FORWARD
	var pose := GrabStyles.pose(String(packet[0]), float(packet[1]), {})
	pose_hunter_body(best, along, [packet[4], packet[5], packet[6]])
	var basis := body.global_basis.orthonormalized()
	pose_arms_on(best, body.global_position, basis, pose["arms"])


## Runs the grab on the local runner; returns when the hold ends (the runner stays held until release()).
## `roll` is the host's roll for this catch (GrabStyles.roll_for).
func play(player: PlayerController3D, view: Node3D, hunter_id: String, roll: float, force_style: String = "") -> void:
	if playing or player == null or view == null:
		return
	_player = player
	_view = view
	_origin = Vector3(view.global_position.x, player.global_position.y, view.global_position.z)
	var flat := Vector3(player.global_position.x - view.global_position.x, 0.0, player.global_position.z - view.global_position.z)
	_along = flat.normalized() if flat.length() > .01 else -view.global_basis.z
	_side = _along.cross(Vector3.UP).normalized()
	var exclude := [player.get_rid()]
	for node in get_tree().get_nodes_in_group("hunter_views"):
		for body in (node as Node).find_children("*", "CollisionObject3D", true, false):
			exclude.append((body as CollisionObject3D).get_rid())
	var room := probe_room(player.get_world_3d().direct_space_state, player.global_position, _origin, _along, exclude,
		player.collision_mask)
	style = force_style if GrabStyles.STYLES.has(force_style) else GrabStyles.pick(hunter_id, roll, room)
	last_room = room
	_ctx = context(view, player.global_position, _along, player._standing_camera_height, room)
	_start = player.global_position
	print("[grab] hunter=%s style=%s roll=%.3f room=%s" % [hunter_id, style, roll, room])
	playing = true
	elapsed = 0.0
	player.begin_grab_view()
	while elapsed < GrabStyles.TOTAL_SECONDS and is_inside_tree() and is_instance_valid(player) and is_instance_valid(view):
		elapsed += get_process_delta_time()
		_apply(elapsed)
		await get_tree().process_frame
	playing = false


func _apply(t: float) -> void:
	current = GrabStyles.pose(style, t, _ctx)
	var at: Vector3 = current["at"]
	var r := GrabStyles.smooth(t / GrabStyles.REACH_SECONDS)
	var feet := _origin + _side * at.x + _along * at.z
	_player.global_position = _start.lerp(feet, r)
	_player.velocity = Vector3.ZERO
	var basis := GrabStyles.body_basis(_along, float(current["face"]), float(current["tilt"]))
	var lift := at.y
	# the eye sits where the body's head is: lifted, knocked flat, or hanging upside down
	var head := basis * Vector3(0.0, _ctx["eye"], 0.0) + Vector3.UP * lift
	head.y = maxf(head.y, .22)
	head += _along * float(current.get("eye_back", 0.0))
	var face := float(current["face"])
	var tilt := float(current["tilt"])
	var yaw := GrabStyles.body_yaw(_along, face)
	var look_pitch := float(current["view_pitch"]) + (tilt if face > 0.0 else 0.0) * .85
	pose_hunter_body(_view, _along, current["hunter"])
	var hunter_head := _view.find_child("Head", true, false) as Node3D
	if face > 0.0 and absf(tilt) < .6 and hunter_head != null:
		# standing face to face with something a head taller: look up at its face, not into its chest
		var to := hunter_head.global_position + Vector3.UP * .2 - (_player.global_position + head)
		var flat := Vector2(to.x, to.z).length()
		if flat > .05:
			yaw = lerp_angle(yaw, atan2(-to.x, -to.z), r)
			look_pitch = lerpf(look_pitch, clampf(atan2(to.y, flat), -.4, .95) + float(current["view_pitch"]) * .3, r)
	_player.set_grab_view(head, yaw, look_pitch, float(current["view_roll"]), String(current["hands"]), float(current["k"]),
		String(current["clip"]))
	pose_arms_on(_view, _player.global_position + Vector3.UP * lift, basis, current["arms"])
	var hunter: Array = current["hunter"]
	# body pitch is sent as the lean itself (an euler read-back flips yaw and pitch for an upside-down body)
	state = [style, snappedf(t, .01), snappedf(lift, .01), snappedf(tilt * face, .01), snappedf(hunter[0], .01),
		snappedf(hunter[1], .01), snappedf(hunter[2], .01)]
	_player.grab_state = state


func _process(_delta: float) -> void:
	# keep holding after the sequence (the death line and the end card play over it), after the clips have run
	if playing or _view == null or not is_instance_valid(_view) or current.is_empty() or _player == null:
		return
	_apply(GrabStyles.TOTAL_SECONDS)


## Lets go: the runner stands back up and the hunter's model is put back (a new run, a respawn).
func release() -> void:
	playing = false
	current = {}
	state = []
	if _view != null and is_instance_valid(_view):
		pose_hunter_body(_view, _along, [0.0, 0.0, 0.0])
	if _player != null and is_instance_valid(_player):
		_player.end_grab_view()
	_view = null
