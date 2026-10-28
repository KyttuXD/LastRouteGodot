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
## The worst gap between a hunter's grip and the body point it holds, this frame (metres; the grabs suite wants it under 3 cm).
var contact_gap := 0.0
var _hunter_id := ""
var _applied_frame := -1
## Frames on which the hard clearance had to push the camera (she moved into it): the grabs suite tracks these.
var pushes := 0
var _last_camera := Transform3D.IDENTITY
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
		# room to either side of the runner (the upside-down hold swings them out to her side)
		"side": minf(float(ray.call(runner_feet + Vector3.UP, runner_feet + Vector3.UP + along.cross(Vector3.UP).normalized() * PROBE_BACK)),
			float(ray.call(runner_feet + Vector3.UP, runner_feet + Vector3.UP - along.cross(Vector3.UP).normalized() * PROBE_BACK))),
	}


## One of a hunter's arms: shoulder, elbow (forearm), hand and the grip point (the hand's prop locator, or just past the wrist on a
## rig without one, the Void hunters).
static func arm_chain(root: Node, arm_side: String) -> Dictionary:
	var names: Array = ARM_SIDES.get(arm_side, ARM_SIDES["R"])
	return {
		"arm": root.find_child(names[0], true, false),
		"forearm": root.find_child(names[1], true, false),
		"hand": root.find_child(names[2], true, false),
		"grip": root.find_child("%s-HandProp" % arm_side, true, false),
	}


static func grip_point(chain: Dictionary) -> Vector3:
	var hand := chain["hand"] as Node3D
	if chain["grip"] != null:
		return (chain["grip"] as Node3D).global_position
	var forearm := chain["forearm"] as Node3D
	var along := (hand.global_position - forearm.global_position).normalized() if forearm != null else Vector3.DOWN
	return hand.global_position + along * .1 * hand.global_basis.get_scale().y


## Shoulder to elbow plus elbow to grip: how far the arm reaches when straight.
static func reach_of(chain: Dictionary) -> float:
	if chain["arm"] == null or chain["forearm"] == null or chain["hand"] == null:
		return 0.0
	var shoulder := (chain["arm"] as Node3D).global_position
	var elbow := (chain["forearm"] as Node3D).global_position
	return shoulder.distance_to(elbow) + elbow.distance_to(grip_point(chain))


static func _turn(node: Node3D, from: Vector3, to: Vector3) -> void:
	if from.length_squared() < 1e-8 or to.length_squared() < 1e-8:
		return
	var scale := node.global_basis.get_scale()
	node.global_basis = (Basis(Quaternion(from.normalized(), to.normalized())) * node.global_basis.orthonormalized()) \
		* Basis.from_scale(scale)


## Two-bone IK: the shoulder and elbow bend so the grip point lands on `target` (`amount` of the way from where the clip put the
## hand), the elbow pointing towards `pole` (down, out and back for a reach), and the upper arm twisted so the elbow bends about
## its own hinge (local X) instead of sideways. Run after the clip has posed the arm this frame.
static func solve_arm(root: Node, arm_side: String, target: Vector3, amount: float, pole: Vector3) -> void:
	var chain := arm_chain(root, arm_side)
	var arm := chain["arm"] as Node3D
	var forearm := chain["forearm"] as Node3D
	if arm == null or forearm == null or chain["hand"] == null or amount <= 0.0:
		return
	var shoulder := arm.global_position
	var elbow := forearm.global_position
	var grip := grip_point(chain)
	var upper := shoulder.distance_to(elbow)
	var lower := elbow.distance_to(grip)
	var goal := grip.lerp(target, clampf(amount, 0.0, 1.0))
	var span := goal - shoulder
	var distance := clampf(span.length(), absf(upper - lower) + .002, upper + lower - .002)
	var direction := span.normalized()
	var bend := pole - direction * pole.dot(direction)
	if bend.length_squared() < 1e-6:
		bend = direction.cross(Vector3.UP).cross(direction)
	bend = bend.normalized()
	var cos_a := clampf((upper * upper + distance * distance - lower * lower) / (2.0 * upper * distance), -1.0, 1.0)
	var wanted_elbow := shoulder + direction * cos_a * upper + bend * sqrt(1.0 - cos_a * cos_a) * upper
	_turn(arm, elbow - shoulder, wanted_elbow - shoulder)
	# twist the upper arm about itself so its hinge axis is square to the bend
	var axis := (wanted_elbow - shoulder).normalized()
	var plane := axis.cross(goal - wanted_elbow)
	if plane.length_squared() > 1e-6:
		plane = plane.normalized()
		var hinge := arm.global_basis.x.normalized()
		hinge = (hinge - axis * hinge.dot(axis))
		if hinge.length_squared() > 1e-6:
			hinge = hinge.normalized()
			if hinge.dot(plane) < 0.0:
				plane = -plane
			var twist := hinge.signed_angle_to(plane, axis)
			var scale := arm.global_basis.get_scale()
			arm.global_basis = (Basis(axis, twist) * arm.global_basis.orthonormalized()) * Basis.from_scale(scale)
	_turn(forearm, grip_point(chain) - forearm.global_position, goal - forearm.global_position)


## Where an elbow points for a reach towards `along`: down, out to its own side and a little back.
static func elbow_pole(arm_side: String, along: Vector3, wide: bool = false) -> Vector3:
	var right := along.cross(Vector3.UP).normalized()
	var out := (1.6 if wide else .6) * (1.0 if arm_side == "R" else -1.0)
	return Vector3.DOWN * (.5 if wide else 1.0) + right * out - along * .35


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


## The body points the hunter's hands go to: [[arm side, world point, amount]] for a body placed by `feet` and `basis`.
static func contacts(feet: Vector3, basis: Basis, arms: Array) -> Array:
	var out := []
	for entry in arms:
		var point: Vector3 = GrabStyles.BODY_POINTS.get(String(entry[1]), GrabStyles.BODY_POINTS["neck"])
		out.append([String(entry[0]), feet + basis * point, float(entry[2])])
	return out


## How far the hunter must step in (x, positive towards the runner) and crouch (y, down) so every hand can reach its contact:
## within 96% of a straight arm, not so close the elbow folds shut, and low enough for a contact far below her shoulder.
static func reach_correction(view: Node3D, along: Vector3, points: Array) -> Vector2:
	var step := 0.0
	var crouch := 0.0
	for entry in points:
		var chain := arm_chain(view, String(entry[0]))
		if chain["arm"] == null or chain["forearm"] == null:
			continue
		var reach := reach_of(chain)
		var far := reach * .96
		# the hand is only part of the way there while it reaches: correct for where it is headed this frame
		var aim := grip_point(chain).lerp(entry[1] as Vector3, clampf(float(entry[2]), 0.0, 1.0))
		var span := aim - (chain["arm"] as Node3D).global_position
		var below := -span.y
		if below > far * .8:
			crouch = maxf(crouch, below - far * .8)
			span.y += below - far * .8
		var level := span.dot(along)
		var across := span.length_squared() - level * level
		if span.length() > far:
			step = maxf(step, level - sqrt(far * far - across) if far * far > across else level)
		elif span.length() < reach * .4:
			step = minf(step, span.length() - reach * .4)
	return Vector2(step, crouch)


## The hunter's hands on a runner body (IK), after `pose_hunter_body`. Returns the worst grip-to-contact gap in metres.
static func pose_arms_on(view: Node3D, along: Vector3, points: Array, wide: bool = false) -> float:
	var worst := 0.0
	for entry in points:
		solve_arm(view, String(entry[0]), entry[1], float(entry[2]), elbow_pole(String(entry[0]), along, wide))
		var chain := arm_chain(view, String(entry[0]))
		if chain["hand"] != null and float(entry[2]) >= .999:
			worst = maxf(worst, grip_point(chain).distance_to(entry[1]))
	return worst


## The hunter turns her head (and so her eyes) towards `target`, within a neck's reach (about 66 degrees either way, 30 down,
## 35 up), eased; `away` > 0 looks away to the side instead (Aki's shyness). State lives on the view, so it carries across frames.
const NECK_YAW := 1.15
const NECK_DOWN := .52
const NECK_UP := .6


static func head_look(view: Node3D, target: Vector3, delta: float, along: Vector3, away: float = 0.0) -> void:
	var head := view.find_child("Head", true, false) as Node3D
	if head == null:
		return
	var eyes := []
	for eye_name in ["L-Eye-Attachment", "R-Eye-Attachment"]:
		var eye := head.find_child(eye_name, true, false) as Node3D
		if eye != null:
			eyes.append(eye.global_position)
	var facing := along
	if eyes.size() == 2:
		facing = ((eyes[0] as Vector3) + (eyes[1] as Vector3)) * .5 - head.global_position
	var flat_facing := Vector3(facing.x, 0.0, facing.z).normalized()
	if flat_facing.length_squared() < .5:
		flat_facing = along
	var to := target - head.global_position
	var flat_to := Vector3(to.x, 0.0, to.z)
	var yaw := flat_facing.signed_angle_to(flat_to.normalized(), Vector3.UP) if flat_to.length() > .01 else 0.0
	var pitch := atan2(to.y, flat_to.length()) - asin(clampf(facing.normalized().y, -1.0, 1.0))
	if away > 0.0:
		yaw = lerpf(yaw, (-1.0 if yaw > 0.0 else 1.0) * NECK_YAW * .9, away)
		pitch = lerpf(pitch, -.35, away)
	yaw = clampf(yaw, -NECK_YAW, NECK_YAW)
	pitch = clampf(pitch, -NECK_DOWN, NECK_UP)
	var eased: Vector2 = view.get_meta("grab_head", Vector2.ZERO)
	var k := 1.0 - exp(-6.0 * delta)
	eased = eased.lerp(Vector2(yaw, pitch), k)
	view.set_meta("grab_head", eased)
	var turned := flat_facing.rotated(Vector3.UP, eased.x)
	var pitch_axis := turned.cross(Vector3.UP).normalized()
	var turn := Basis(pitch_axis, eased.y) * Basis(Vector3.UP, eased.x)
	var scale := head.global_basis.get_scale()
	head.global_basis = (turn * head.global_basis.orthonormalized()) * Basis.from_scale(scale)
	if "_head_written_q" in view:
		view.set("_head_written_q", head.quaternion)   # the view's own head look starts from the rest pose next frame


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
	var pose := GrabStyles.pose(String(packet[0]), float(packet[1]), {})
	# the grab's own frame comes from the body's facing (to the hunter, or away for a leg grab), not from where she stands
	var front := -body.global_basis.z
	front = Vector3(front.x, 0.0, front.z).normalized()
	var along := -front * float(pose["face"])
	if along.length_squared() < .5:
		along = Vector3(body.global_position.x - best.global_position.x, 0.0, body.global_position.z - best.global_position.z).normalized()
	pose_hunter_body(best, along, [packet[4], packet[5], packet[6]])
	var basis := body.global_basis.orthonormalized()
	var points := contacts(body.global_position, basis, pose["arms"])
	# the runner's own arm goes out to where the hunter holds it (the wrist yank)
	for entry in pose.get("runner_arms", []):
		solve_arm(body, String(entry[0]), body.global_position + basis * (GrabStyles.BODY_POINTS[String(entry[1])] as Vector3),
			float(pose["k"]), Vector3.DOWN - along * .3)
	pose_arms_on(best, along, points, bool(pose.get("wide", false)))
	var id := String(best.call("shown_id")) if best.has_method("shown_id") else ""
	head_look(best, body.global_position + basis * (GrabStyles.BODY_POINTS["neck"] + Vector3(0.0, .3, 0.0)),
		best.get_process_delta_time(), along, GrabStyles.look_away(id, float(packet[1])))


## The first-person camera while held (KT: the views must never look horrific). It sits at the grabbed body's head, pulled
## back (at most MAX_PULLBACK) until the hunter's face and upper body are framed at FACE_DISTANCE; it never ends inside a wall
## (ray from where the runner stood, then a sphere test) or inside the hunter (her collider and every box of her posed model,
## with CLEARANCE); it eases towards that spot and that view every frame instead of snapping; roll stays within MAX_ROLL (the
## upside-down hold flips slowly, then sways within FLIP_SWAY).
const FACE_DISTANCE := 1.45
const MAX_PULLBACK := .9
const CLEARANCE := .2
const WALL_MARGIN := .22
const EASE_RATE := 4.0
## Speed limits on the eased camera, so nothing ever snaps: metres and radians per second.
const MAX_SPEED := 2.8
const MAX_TURN := 2.4
## The hard limit, only ever enforced by a push: the near plane (.06) plus a little.
const HARD_CLEARANCE := .08
const MAX_ROLL := .26
const FLIP_SWAY := .17
const MAX_LOOK_PITCH := 1.2


## Is `point` clear of walls and of every hunter (collider, and each box of its posed model grown by CLEARANCE)? "" when it is,
## else what it is inside. Shared with the grabs suite, which runs it on every frame of every grab.
static func camera_blocked(space: PhysicsDirectSpaceState3D, point: Vector3, exclude: Array, mask: int,
		hunters: Array, clearance: float = CLEARANCE) -> String:
	var sphere := SphereShape3D.new()
	sphere.radius = clearance
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = mask
	query.exclude = exclude
	for hit in space.intersect_shape(query, 8):
		var collider = hit.get("collider")
		if collider is Node and (collider as Node).is_in_group("hunter_views"):
			return "hunter collider"
		return "wall (%s)" % (collider as Node).name if collider is Node else "wall"
	for view in hunters:
		var model := (view as Node3D).get("_model") as Node3D if "_model" in view else view as Node3D
		if model == null:
			continue
		for node in model.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := node as MeshInstance3D
			if mesh_node.mesh == null or not mesh_node.is_visible_in_tree() or String(mesh_node.name).contains("Beam"):
				continue   # her body, not the see-through vision beam
			var local := mesh_node.global_transform.affine_inverse() * point
			var scale := mesh_node.global_transform.basis.get_scale()
			var grown := mesh_node.mesh.get_aabb().grow(clearance / maxf(minf(scale.x, minf(scale.y, scale.z)), .001))
			if grown.has_point(local):
				return "hunter mesh (%s)" % mesh_node.name
	return ""


func _exclude() -> Array:
	var exclude := [_player.get_rid()]
	for node in get_tree().get_nodes_in_group("hunter_views"):
		if node is CollisionObject3D:
			exclude.append((node as CollisionObject3D).get_rid())
	return exclude


func _walls_only() -> Array:
	var out := [_player.get_rid()]
	for node in _hunters():
		for body in [node] + (node as Node).find_children("*", "CollisionObject3D", true, false):
			if body is CollisionObject3D:
				out.append((body as CollisionObject3D).get_rid())
	return out


func _hunters() -> Array:
	return get_tree().get_nodes_in_group("hunter_views")


## Where the camera looks: the hunter's face and upper body (a creature rig: the middle of its body, a little high).
func _look_point() -> Vector3:
	var head := _view.find_child("Head", true, false) as Node3D
	if head != null:
		return head.global_position + Vector3.DOWN * .1
	return _view.global_position + Vector3.UP * .7


## Moves `point` out of walls along the line from where the runner stood (always clear), then out of the hunter.
func _clear(point: Vector3, clearance: float = CLEARANCE) -> Vector3:
	var space := _player.get_world_3d().direct_space_state
	var mask := _player.collision_mask
	var walls_only := _walls_only()
	var anchor := _start + Vector3.UP * minf(1.0, _ctx["eye"])
	var fix_walls := func(p: Vector3) -> Vector3:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(anchor, p, mask, walls_only))
		if not hit.is_empty():
			p = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * WALL_MARGIN
		for _i in 10:
			if camera_blocked(space, p, walls_only, mask, [], WALL_MARGIN).is_empty():
				break
			p = p.lerp(anchor, .25)
		return p
	point = fix_walls.call(point)
	var blocked := func(p: Vector3) -> bool:
		return not camera_blocked(space, p, walls_only, mask, [_view], clearance).is_empty()
	if not blocked.call(point):
		return point
	# out of the hunter: the nearest clear spot straight back from her (found continuously, so it never steps or jitters);
	# a wall behind means rising over her reach instead
	var lo := 0.0
	var hi := -1.0
	for i in range(1, 26):
		if not blocked.call(point + _along * (i * .1)):
			hi = i * .1
			lo = (i - 1) * .1
			break
	if hi < 0.0:
		return fix_walls.call(point + Vector3.UP * .4)
	for _i in 7:
		var mid := (lo + hi) * .5
		if blocked.call(point + _along * mid):
			lo = mid
		else:
			hi = mid
	var out: Vector3 = point + _along * hi
	var walled: Vector3 = fix_walls.call(out)
	if walled.distance_to(out) > .01 and blocked.call(walled):
		lo = 0.0
		hi = 1.0
		if blocked.call(walled + Vector3.UP * hi):
			return walled + Vector3.UP * hi
		for _i in 7:
			var mid := (lo + hi) * .5
			if blocked.call(walled + Vector3.UP * mid):
				lo = mid
			else:
				hi = mid
		return walled + Vector3.UP * hi
	return walled


func _solve_camera(head_world: Vector3, roll: float, delta: float) -> Transform3D:
	var look := _look_point()
	var turned := float(current.get("look", 1.0))
	if turned < 1.0:
		var ahead := head_world - _along * float(current["face"]) * 3.0
		look = ahead.lerp(look, turned)
	var wanted := head_world
	var flat := Vector2(wanted.x - look.x, wanted.z - look.z).length()
	if flat < FACE_DISTANCE:
		var pull := minf(FACE_DISTANCE - flat, MAX_PULLBACK)
		# never pulled back into a wall behind the runner: stop short of it
		var behind := _player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(head_world,
			head_world + _along * (pull + WALL_MARGIN), _player.collision_mask, _walls_only()))
		if not behind.is_empty():
			pull = maxf(head_world.distance_to(behind["position"]) - WALL_MARGIN, 0.0)
		wanted += _along * pull
		# boxed in behind (a wall pin, a hallway's end): step to the roomier side instead, so her face is not in the lens
		if pull < (FACE_DISTANCE - flat) * .6:
			var space := _player.get_world_3d().direct_space_state
			var best := Vector3.ZERO
			var room := 0.0
			for dir in [_side, -_side]:
				var probe := space.intersect_ray(PhysicsRayQueryParameters3D.create(wanted, wanted + dir * 1.0,
					_player.collision_mask, _walls_only()))
				var free := 1.0 if probe.is_empty() else wanted.distance_to(probe["position"])
				if free > room:
					room = free
					best = dir
			wanted += best * clampf(room - WALL_MARGIN, 0.0, .55)
	wanted = _clear(wanted, CLEARANCE + .15)   # aim with room to spare, so easing towards it never grazes her
	# eased from where the camera was last frame (the first frame: the view the runner had when caught)
	var previous := _last_camera
	var at := previous.origin.lerp(wanted, 1.0 - exp(-EASE_RATE * delta))
	var move := at - previous.origin
	if move.length() > MAX_SPEED * delta:
		at = previous.origin + move.normalized() * MAX_SPEED * delta
	if not camera_blocked(_player.get_world_3d().direct_space_state, at, _walls_only(), _player.collision_mask, [_view],
			HARD_CLEARANCE).is_empty():
		at = _clear(at, HARD_CLEARANCE)   # only when she moves into the eased camera itself
		pushes += 1
	var to := look - at
	var flat_to := Vector2(to.x, to.z).length()
	var pitch := clampf(atan2(to.y, flat_to), -MAX_LOOK_PITCH, MAX_LOOK_PITCH)
	var yaw := atan2(-to.x, -to.z)
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	basis = Basis(basis.z.normalized(), -roll) * basis   # roll about the view axis
	var from := previous.basis.orthonormalized().get_rotation_quaternion()
	var to_q := basis.get_rotation_quaternion()
	var weight := 1.0 - exp(-EASE_RATE * delta)
	var gap := from.angle_to(to_q)
	if gap * weight > MAX_TURN * delta:
		weight = MAX_TURN * delta / gap
	return Transform3D(Basis(from.slerp(to_q, weight)), at)


## Runs the grab on the local runner; returns when the hold ends (the runner stays held until release()).
## `roll` is the host's roll for this catch (GrabStyles.roll_for).
func play(player: PlayerController3D, view: Node3D, hunter_id: String, roll: float, force_style: String = "") -> void:
	if playing or player == null or view == null:
		return
	_player = player
	_view = view
	_hunter_id = hunter_id
	_origin = Vector3(view.global_position.x, player.global_position.y, view.global_position.z)
	var flat := Vector3(player.global_position.x - view.global_position.x, 0.0, player.global_position.z - view.global_position.z)
	_along = flat.normalized() if flat.length() > .01 else -view.global_basis.z
	_side = _along.cross(Vector3.UP).normalized()
	var exclude := _exclude()
	for node in _hunters():
		for body in (node as Node).find_children("*", "CollisionObject3D", true, false):
			exclude.append((body as CollisionObject3D).get_rid())
	var room := probe_room(player.get_world_3d().direct_space_state, player.global_position, _origin, _along, exclude,
		player.collision_mask)
	style = force_style if GrabStyles.STYLES.has(force_style) else GrabStyles.pick(hunter_id, roll, room)
	last_room = room
	_ctx = context(view, player.global_position, _along, player._standing_camera_height, room)
	_start = player.global_position
	view.remove_meta("grab_head")
	print("[grab] hunter=%s style=%s roll=%.3f room=%s" % [hunter_id, style, roll, room])
	playing = true
	elapsed = 0.0
	pushes = 0
	player.begin_grab_view()
	_apply(0.0, 0.0)
	while elapsed < GrabStyles.TOTAL_SECONDS and is_inside_tree() and is_instance_valid(player) and is_instance_valid(view):
		await get_tree().process_frame
		var delta := get_process_delta_time()
		elapsed += delta
		_apply(elapsed, delta)
	playing = false


func _apply(t: float, delta: float) -> void:
	_applied_frame = Engine.get_process_frames()
	if t == 0.0:
		_last_camera = _player.first_person_camera.global_transform
	current = GrabStyles.pose(style, t, _ctx)
	var at: Vector3 = current["at"]
	var r := GrabStyles.smooth(t / GrabStyles.REACH_SECONDS)
	var face := float(current["face"])
	var tilt := float(current["tilt"])
	var basis := GrabStyles.body_basis(_along, face, tilt)
	var lift := at.y
	var feet := _origin + _side * at.x + _along * at.z
	_player.global_position = _start.lerp(feet, r)
	_player.velocity = Vector3.ZERO
	var body_feet := _player.global_position + Vector3.UP * lift
	# the hunter steps in or back until every hand reaches its contact, then the arms bend onto it
	var offsets: Array = (current["hunter"] as Array).duplicate()
	pose_hunter_body(_view, _along, offsets)
	var points := contacts(body_feet, basis, current["arms"])
	for _i in 3:
		var fix := reach_correction(_view, _along, points)
		if absf(fix.x) < .005 and fix.y < .005:
			break
		offsets[0] = float(offsets[0]) + fix.x
		offsets[1] = float(offsets[1]) + fix.y
		pose_hunter_body(_view, _along, offsets)
	contact_gap = pose_arms_on(_view, _along, points, bool(current.get("wide", false)))
	# the camera: from the grabbed body's head, framed on her face, clear of her and the walls, eased
	var head := basis * Vector3(0.0, _ctx["eye"], 0.0) + body_feet
	head.y = maxf(head.y, _player.global_position.y + .25)
	var roll := float(current["view_roll"])
	if style == GrabStyles.UPSIDE_DOWN:
		var flip := float(current.get("flip", 0.0))
		roll = PI * flip + clampf(roll - PI * flip, -FLIP_SWAY, FLIP_SWAY)
	else:
		roll = clampf(roll, -MAX_ROLL, MAX_ROLL)
	# her eyes go to the camera (last frame's: close enough), before the camera is fitted around her final pose
	head_look(_view, _last_camera.origin, delta, _along, GrabStyles.look_away(_hunter_id, t))
	var camera := _solve_camera(head, roll, delta)
	_last_camera = camera
	_player.set_grab_camera(camera, _body_yaw(face), String(current["hands"]), float(current["k"]), String(current["clip"]))
	if String(current["hands"]) == "held" and not points.is_empty():
		_player.hold_grab_hand_at(points[0][1])   # the runner's own (left) skinned hand is the one in her grip
	state = [style, snappedf(t, .01), snappedf(lift, .001), snappedf(tilt * face, .001), snappedf(float(offsets[0]), .001),
		snappedf(float(offsets[1]), .001), snappedf(float(offsets[2]), .001)]
	_player.grab_state = state


func _body_yaw(face: float) -> float:
	return GrabStyles.body_yaw(_along, face)


func _process(delta: float) -> void:
	# keep holding after the sequence (the death line and the end card play over it), after the clips have run
	if playing or _view == null or not is_instance_valid(_view) or current.is_empty() or _player == null:
		return
	if _applied_frame == Engine.get_process_frames():
		return
	_apply(GrabStyles.TOTAL_SECONDS, delta)


## Lets go: the runner stands back up and the hunter's model is put back (a new run, a respawn).
func release() -> void:
	playing = false
	current = {}
	state = []
	if _view != null and is_instance_valid(_view):
		pose_hunter_body(_view, _along, [0.0, 0.0, 0.0])
		_view.remove_meta("grab_head")
	if _player != null and is_instance_valid(_player):
		_player.end_grab_view()
	_view = null
