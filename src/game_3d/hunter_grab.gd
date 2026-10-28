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
## Hunter meshes hidden from the camera this frame because the lens is inside them (see _cull_near).
var culled: Array = []
var _last_camera := Transform3D.IDENTITY
var _base_fov := 78.0
var _catch_camera := Transform3D.IDENTITY
var _last_wanted := Vector3.INF
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
	var was_grabbing: bool = view.call("grabbing") if view.has_method("grabbing") else true
	if "grab_until_msec" in view:
		view.set("grab_until_msec", Time.get_ticks_msec() + 250)   # no beam (Kathy) while she holds someone
	var model := view.get("_model") as Node3D if "_model" in view else null
	if model == null:
		return
	if not model.has_meta("grab_rest"):
		model.set_meta("grab_rest", model.transform)
	var releasing := offsets.is_empty()
	if releasing:
		model.transform = model.get_meta("grab_rest")
		model.remove_meta("grab_rest")
		view.remove_meta("grab_anchor")
		return
	# Her model is pinned where the grab began, turned square to the runner: on a live route the hunter keeps being
	# simulated (and walks, wanders, turns) while she holds someone, and a model riding along with that would pull her hands
	# off the body. The anchor is taken when a grab starts posing her (or after a gap of a quarter second).
	if not was_grabbing or not view.has_meta("grab_anchor"):
		var anchor := view.global_transform
		model.transform = model.get_meta("grab_rest")
		var head := view.find_child("Head", true, false) as Node3D
		var facing := face_forward(head, GrabStyles.look_for(String(view.call("shown_id")) if view.has_method("shown_id") else ""),
			along) if head != null else along
		var flat := Vector3(facing.x, 0.0, facing.z).normalized()
		if flat.length_squared() > .5:
			anchor.basis = Basis(Vector3.UP, flat.signed_angle_to(along, Vector3.UP)) * anchor.basis
		view.set_meta("grab_anchor", anchor)
	var anchored: Transform3D = view.get_meta("grab_anchor")
	model.global_transform = anchored * (model.get_meta("grab_rest") as Transform3D)
	var forward := float(offsets[0]) if offsets.size() > 0 else 0.0
	var drop := float(offsets[1]) if offsets.size() > 1 else 0.0
	var lean := float(offsets[2]) if offsets.size() > 2 else 0.0
	var placed := model.global_transform
	var axis := Vector3.UP.cross(along).normalized()
	if axis.length_squared() > .5:
		placed.basis = Basis(axis, lean) * placed.basis
	placed.origin += along * forward + Vector3.DOWN * drop
	model.global_transform = placed


## The shoulder carry: the carried runner's hips bend (thighs swung down the hunter's front), `amount` 0..1 of the way.
## Bent from each thigh's own pose every frame (after the clip); 0 puts them back.
const CARRY_HIP := 2.35


static func fold_legs(body: Node3D, amount: float) -> void:
	for thigh_name in ["L-Thigh", "R-Thigh"]:
		var thigh := body.find_child(thigh_name, true, false) as Node3D
		if thigh == null:
			continue
		if not thigh.has_meta("carry_rest"):
			if amount <= 0.0:
				continue
			thigh.set_meta("carry_rest", thigh.basis)
		var rest: Basis = thigh.get_meta("carry_rest")
		thigh.basis = Basis(Vector3.RIGHT, CARRY_HIP * amount) * rest
		if amount <= 0.0:
			thigh.remove_meta("carry_rest")


## She walks while carrying: her walk clip, at the grab's own time, so every peer shows the same step.
static func play_walk(view: Node3D, t: float) -> void:
	var player := view.get("_animation_player") as AnimationPlayer if "_animation_player" in view else null
	if player == null or not player.has_animation("walk"):
		return
	ModelSlot.play_if_available(player, "walk")
	player.seek(fmod(t, maxf(player.get_animation("walk").length, .01)), true)


## How far a style stretches her arms at `t`: up to arm_stretch, eased in with her reach.
static func stretch_for(style: String, t: float) -> float:
	if not STRETCH_STYLES.has(style):
		return 1.0
	return 1.0 + (arm_stretch - 1.0) * GrabStyles.smooth(t / GrabStyles.REACH_SECONDS)


## Her upper arm and forearm lengthened `factor` times along their own length, nothing else: the width stays, the hand keeps its
## exact size and shape, and the body is untouched (scale_consistency). Each bone is set from the rotation the animation gave it and
## its own rest scale, in world space, so the lengthened upper arm never skews the forearm or the hand under it (scaling the upper
## arm node and counter-scaling the hand sheared the hand by up to 60% when the elbow was bent). 1 puts them back.
## HunterView3D puts them back too once nothing grabs with her any more.
static func stretch_arms(view: Node3D, factor: float) -> void:
	for side in ["R", "L"]:
		var chain := arm_chain(view, side)
		var arm := chain["arm"] as Node3D
		var forearm := chain["forearm"] as Node3D
		var hand := chain["hand"] as Node3D
		if arm == null or forearm == null or hand == null:
			continue
		var bones: Array = [arm, forearm, hand]
		if not arm.has_meta("grab_scale") and is_equal_approx(factor, 1.0):
			continue
		if not arm.has_meta("grab_scale"):
			for bone in bones:
				(bone as Node3D).set_meta("grab_scale", (bone as Node3D).scale)
		var parent := arm.get_parent() as Node3D
		var size := parent.global_basis.get_scale().y
		var turn := parent.global_basis.orthonormalized()
		for index in 3:
			var bone := bones[index] as Node3D
			var rest: Vector3 = bone.get_meta("grab_scale")
			var lengthen := Vector3(1.0, factor, 1.0) if index < 2 else Vector3.ONE
			turn = turn * Basis(bone.quaternion)
			bone.global_basis = turn * Basis.from_scale(rest * lengthen * size)
		if is_equal_approx(factor, 1.0):
			for bone in bones:
				(bone as Node3D).remove_meta("grab_scale")


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


## Where a held runner's own hands go (`body` is their mannequin; the local first-person body or another player's copy):
## onto her forearm when held up by it, against her chest when pushing her off, the held wrist out to her grip, clawing at
## the floor ahead when dragged; the clip's own arms otherwise (pinned, dangling).
static func runner_hand_targets(body: Node3D, view: Node3D, pose: Dictionary, along: Vector3, t: float) -> Array:
	var hands := String(pose.get("hands", ""))
	var basis := body.global_basis.orthonormalized()
	var right := basis.x
	var out := []
	match hands:
		"grip_arm":
			var chain := arm_chain(view, "R")
			if chain["forearm"] != null and chain["hand"] != null:
				var elbow := (chain["forearm"] as Node3D).global_position
				var wrist := (chain["hand"] as Node3D).global_position
				out = [["L", elbow.lerp(wrist, .45)], ["R", elbow.lerp(wrist, .8)]]
		"push", "push_up":
			# arms out against her, at the runner's own arm's length (not up in their face)
			var chest := view.find_child("Chest", true, false) as Node3D
			var target := chest.global_position if chest != null else view.global_position + Vector3.UP
			for side in [["L", -1.0], ["R", 1.0]]:
				var shoulder := body.global_position + basis * Vector3(.3 * float(side[1]), 1.08, 0.0)
				var toward := (target - shoulder).normalized()
				out.append([side[0], shoulder + toward * .36 + Vector3.DOWN * .08])
		"held":
			for entry in pose.get("runner_arms", []):
				out.append([String(entry[0]), body.global_position + basis * (GrabStyles.BODY_POINTS[String(entry[1])] as Vector3)])
		"dangle":
			# hanging head down: the arms hang towards the floor, out to the sides, clear of the face
			for side in [["L", -1.0], ["R", 1.0]]:
				var shoulder := body.global_position + basis * Vector3(.3 * float(side[1]), 1.08, 0.0)
				out.append([side[0], shoulder + Vector3.DOWN * .38 + right * (.25 * float(side[1]))])
		"claw":
			# reaching ahead along the floor in turn, as if digging in
			var ahead := body.global_position + basis * Vector3(0.0, 1.3, -.2)
			ahead.y = body.global_position.y + .06
			for side in [["L", -1.0], ["R", 1.0]]:
				var reach := .25 + .2 * sin(t * 5.0 + (0.0 if side[1] < 0.0 else PI))
				out.append([side[0], ahead + right * (.18 * float(side[1])) - basis.z * reach])
	return out


static func pose_runner_arms(body: Node3D, view: Node3D, pose: Dictionary, along: Vector3, t: float) -> void:
	var amount := float(pose.get("k", 1.0))
	for entry in runner_hand_targets(body, view, pose, along, t):
		solve_arm(body, String(entry[0]), entry[1], amount, Vector3.DOWN * .6 + body.global_basis.orthonormalized().x
			* (.5 if entry[0] == "R" else -.5) + body.global_basis.orthonormalized().z * .4)


## The hunter turns her head (and so her eyes) towards `target`: the chest takes a share of the turn and the head the rest,
## within her neck limits (GrabStyles.look_for: by default 100 degrees either way in all, 55 down, 60 up), eased. Applied
## after her clips and the view's own head look every frame, and from the pose underneath them: if nothing rewrote a bone
## since last frame, last frame's turn is taken off first, so the turn never compounds or fades. `away` > 0 looks away to
## the side instead (Aki's shyness). The face's forward axis is where the eyes are, or the per-hunter one in the data.
static func head_look(view: Node3D, target: Vector3, delta: float, along: Vector3, away: float = 0.0) -> void:
	var head := view.find_child("Head", true, false) as Node3D
	if head == null:
		return
	var chest := view.find_child("Chest", true, false) as Node3D
	var id := String(view.call("shown_id")) if view.has_method("shown_id") else ""
	var look := GrabStyles.look_for(id)
	for bone in [chest, head]:
		if bone != null and bone.has_meta("grab_written") and bone.basis.is_equal_approx(bone.get_meta("grab_written")):
			bone.basis = bone.get_meta("grab_base")   # untouched since our turn: start again from the pose underneath
	var aim := target
	if away > 0.0:
		# looking off to the side and down, away from the runner
		var side := along.cross(Vector3.UP).normalized()
		var off := head.global_position + (side * 1.5 + Vector3.DOWN * .8 - along * .3)
		aim = target.lerp(off, away)
	var k := 1.0 - exp(-7.0 * delta)
	var share := float(look["chest"]) if chest != null else 0.0
	var limit := float(look["yaw"])
	for part in [[chest, share, "grab_chest_turn"], [head, 1.0, "grab_head_turn"]]:
		var bone := part[0] as Node3D
		if bone == null or float(part[1]) <= 0.0:
			continue
		# the turn from where her face points now to the aim, limited by the neck, a share of it for the chest, eased
		var facing := face_forward(head, look, along).normalized()
		var wanted := (aim - head.global_position).normalized()
		var full := Quaternion(facing, wanted) if facing.angle_to(wanted) > .001 else Quaternion.IDENTITY
		var angle := full.get_angle()
		if angle > limit:
			full = Quaternion.IDENTITY.slerp(full, limit / angle)
		var turn := Quaternion.IDENTITY.slerp(full, float(part[1]))
		var eased: Quaternion = view.get_meta(String(part[2]), Quaternion.IDENTITY)
		eased = eased.slerp(turn, k)
		view.set_meta(String(part[2]), eased)
		bone.set_meta("grab_base", bone.basis)
		var scale := bone.global_basis.get_scale()
		bone.global_basis = (Basis(eased) * bone.global_basis.orthonormalized()) * Basis.from_scale(scale)
		bone.set_meta("grab_written", bone.basis)
	if "_head_written_q" in view:
		view.set("_head_written_q", head.quaternion)   # the view's own head look starts from the rest pose next frame


## Where her face points: from the head to between the eyes, or the data's forward axis in the head's own frame.
static func face_forward(head: Node3D, look: Dictionary, along: Vector3) -> Vector3:
	if look.has("forward"):
		return head.global_basis.orthonormalized() * (look["forward"] as Vector3)
	var eyes := []
	for eye_name in ["L-Eye-Attachment", "R-Eye-Attachment"]:
		var eye := head.find_child(eye_name, true, false) as Node3D
		if eye != null:
			eyes.append(eye.global_position)
	if eyes.size() == 2:
		return ((eyes[0] as Vector3) + (eyes[1] as Vector3)) * .5 - head.global_position
	return along


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
	# from the body's own heading (RemotePlayers sets it as rotation.y, apart from the lean in rotation.x): a basis read back
	# would flip it for a body hung or carried head down
	var front := Vector3(-sin(body.rotation.y), 0.0, -cos(body.rotation.y))
	var along := -front * float(pose["face"])
	if along.length_squared() < .5:
		along = Vector3(body.global_position.x - best.global_position.x, 0.0, body.global_position.z - best.global_position.z).normalized()
	pose_hunter_body(best, along, [packet[4], packet[5], packet[6]])
	if bool(pose.get("walk", false)):
		play_walk(best, float(packet[1]))
	stretch_arms(best, stretch_for(String(packet[0]), float(packet[1])))
	fold_legs(body, float(pose.get("fold", 0.0)))
	var basis := body.global_basis.orthonormalized()
	var points := contacts(body.global_position, basis, pose["arms"])
	pose_arms_on(best, along, points, bool(pose.get("wide", false)))
	pose_runner_arms(body, best, pose, along, float(packet[1]))
	# then her eyes, on the runner's face (only her head turns, so the hands stay put)
	var id := String(best.call("shown_id")) if best.has_method("shown_id") else ""
	var her_target := body.global_position + basis * (GrabStyles.BODY_POINTS["neck"] + Vector3(0.0, .35, -.2))
	if bool(pose.get("her_look_ahead", false)):
		her_target = best.global_position + along * (4.0 + float(packet[4])) + Vector3.UP * 1.6
	head_look(best, her_target, best.get_process_delta_time(), along, GrabStyles.look_away(id, float(packet[1])))


## The first-person camera while held (KT: the views must never look horrific). It starts at the eyes of the runner's own body
## (FirstPersonBody, posed by the grab), drawn back to frame her face (FACE_DISTANCE), and looks at her face; it never ends
## inside a wall
## (ray from where the runner stood, then a sphere test) or inside the hunter (her collider and every box of her posed model,
## with CLEARANCE); it eases towards that spot and that view every frame instead of snapping; roll stays within MAX_ROLL (the
## upside-down hold flips slowly, then sways within FLIP_SWAY).
const CLEARANCE := .07
## The hold widens the view up to fov_widen degrees, eased, while her face is closer than FACE_DISTANCE.
const FACE_DISTANCE := 1.2
## KT's pick (option c): her arms stretched along their length while she reaches for and holds the runner
## (arm_stretch, for the styles in STRETCH_STYLES), and how far the hold may widen the view (fov_widen, degrees). Static so
## a capture rig can still compare; every peer uses the same values.
static var arm_stretch := 1.6
static var fov_widen := 25.0
const UPSIDE_DOWN_HIDDEN := ["Chest", "Belly", "Pelvis", "L-Thigh", "R-Thigh", "L-Arm", "R-Arm"]
const STRETCH_STYLES := [GrabStyles.NECK_LIFT, GrabStyles.SHOULDER_GRAB, GrabStyles.WRIST_YANK, GrabStyles.WALL_PIN, GrabStyles.WRAP,
	GrabStyles.COLLAR_DRAG, GrabStyles.LEG_GRAB, GrabStyles.UPSIDE_DOWN]
const WALL_MARGIN := .12
const EASE_RATE := 30.0
## Speed limits on the eased camera, so nothing ever snaps: metres and radians per second.
const MAX_SPEED := 5.0
const MAX_TURN := 2.4
## The hard limit, only ever enforced by a push: the near plane (.06) plus a little.
const HARD_CLEARANCE := .065
## The most a push may move the camera in one frame.
const MAX_PUSH := .18
const CATCH_EASE := .35
## Render layer for hunter parts hidden from the held runner's camera (inside its near plane this frame).
const NEAR_CULL_LAYER := 1 << 16
const MAX_ROLL := .26
const FLIP_SWAY := .17
const MAX_LOOK_PITCH := 1.45


## Is `point` clear of walls and of every hunter (collider, and each box of its posed model grown by CLEARANCE)? "" when it is,
## else what it is inside. Shared with the grabs suite, which runs it on every frame of every grab.
static func camera_blocked(space: PhysicsDirectSpaceState3D, point: Vector3, exclude: Array, mask: int,
		hunters: Array, clearance: float = CLEARANCE, skip_arms: bool = false) -> String:
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
			if skip_arms and _is_arm(mesh_node):
				continue
			if mesh_node.layers == FirstPersonBody.HEAD_LAYER:
				continue   # the runner's own head: never drawn for the first-person camera
			var local := mesh_node.global_transform.affine_inverse() * point
			var scale := mesh_node.global_transform.basis.get_scale()
			var grown := mesh_node.mesh.get_aabb().grow(clearance / maxf(minf(scale.x, minf(scale.y, scale.z)), .001))
			if grown.has_point(local):
				return "hunter mesh (%s)" % mesh_node.name
	return ""


## Any box of her model within the near plane of the camera at `at` is drawn on a layer the first-person camera skips, for
## this frame only, so the lens never shows the inside of a mesh; everything else is put back.
func _cull_near(at: Vector3) -> void:
	var camera := _player.first_person_camera
	camera.cull_mask &= ~NEAR_CULL_LAYER
	var model := _view.get("_model") as Node3D if "_model" in _view else _view
	if model == null:
		return
	var parts := model.find_children("*", "MeshInstance3D", true, false)
	var body := _player.first_person_body()
	if body.model != null and body.visible:
		for node in body.model.find_children("*", "MeshInstance3D", true, false):
			if _is_arm(node):
				parts.append(node)   # the runner's own arm at the lens (pushing her off, gripping her arm)
	for node in parts:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		if mesh_node.has_meta("grab_layers"):
			mesh_node.layers = int(mesh_node.get_meta("grab_layers"))
			mesh_node.remove_meta("grab_layers")
		var local := mesh_node.global_transform.affine_inverse() * at
		var scale := mesh_node.global_transform.basis.get_scale()
		if mesh_node.mesh.get_aabb().grow(HARD_CLEARANCE / maxf(minf(scale.x, minf(scale.y, scale.z)), .001)).has_point(local):
			mesh_node.set_meta("grab_layers", mesh_node.layers)
			mesh_node.layers = NEAR_CULL_LAYER
			culled.append(mesh_node)


func _own_torso() -> Array:
	var body := _player.first_person_body()
	if body.model == null or not body.visible:
		return []
	var out := []
	for node in body.model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null and mesh_node.is_visible_in_tree() and not _is_arm(mesh_node) \
				and mesh_node.layers != FirstPersonBody.HEAD_LAYER:
			out.append(mesh_node)
	return out


static func _is_arm(node: Node) -> bool:
	var at := node
	while at != null:
		if String(at.name) in ["L-Arm", "R-Arm"]:
			return true
		at = at.get_parent()
	return false


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
		# her face, between her eyes: centred in the runner's view (KT)
		var left := head.find_child("L-Eye-Attachment", true, false) as Node3D
		var right := head.find_child("R-Eye-Attachment", true, false) as Node3D
		if left != null and right != null:
			return (left.global_position + right.global_position) * .5
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
		# then out of whatever surface it is still too close to (the floor under a body knocked flat or hung head down, a
		# wall beside it), straight out along that surface's normal
		var sphere := SphereShape3D.new()
		sphere.radius = WALL_MARGIN * .8
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = sphere
		query.collision_mask = mask
		query.exclude = walls_only
		for _i in 10:
			query.transform = Transform3D(Basis.IDENTITY, p)
			var rest := space.get_rest_info(query)
			if rest.is_empty():
				break
			p += (rest["normal"] as Vector3) * .03
		return p
	point = fix_walls.call(point)
	# the runner's own torso and legs count as solid too (their own arms are just not drawn when at the lens: _cull_near)
	var own: Array = _own_torso()
	var blocked := func(p: Vector3) -> bool:
		# her arms reach right up to the runner's face: those are culled at the lens (_cull_near), not dodged
		if not camera_blocked(space, p, walls_only, mask, [], clearance).is_empty():
			return true
		if not camera_blocked(space, p, [_player.get_rid()], mask, [], clearance).is_empty():
			return true   # her collider (the walls-only exclusion above leaves hunters out)
		for part in own:
			var mesh_node := part as MeshInstance3D
			if mesh_node.mesh.get_aabb().grow(.02).has_point(mesh_node.global_transform.affine_inverse() * p):
				return true
		return false
	if not blocked.call(point):
		return point
	# the nearest clear spot, searched straight up (over her reach) and straight back from her, whichever is closer; found
	# continuously by bisection, so the camera never steps or jitters; walls always win
	# never back behind the eyes (KT): up over her reach, or to one side; a runner hung or carried head down has their own
	# body above the eyes, so sideways first
	var inverted := absf(float(current.get("tilt", 0.0))) > PI * .5 if not current.is_empty() else false
	for axis in ([_side, -_side, Vector3.UP] if inverted else [Vector3.UP, _side, -_side]):
		var hi := -1.0
		for i in range(1, 16):
			var probe: Vector3 = fix_walls.call(point + axis * (i * .1))
			if not blocked.call(probe):
				hi = i * .1
				break
		if hi < 0.0:
			continue
		var lo := hi - .1
		for _i in 7:
			var mid := (lo + hi) * .5
			if blocked.call(fix_walls.call(point + axis * mid)):
				lo = mid
			else:
				hi = mid
		return fix_walls.call(point + axis * hi)
	return fix_walls.call(point + Vector3.UP * .4)


func _solve_camera(head_world: Vector3, roll: float, delta: float) -> Transform3D:
	var look := _look_point()
	var down_back := float(current.get("look_down_back", 0.0))
	if down_back > 0.0:
		look = look.lerp(head_world - _along * 1.2 + Vector3.DOWN * 1.6, down_back)
	var turned := float(current.get("look", 1.0))
	if turned < 1.0:
		var ahead := head_world - _along * float(current["face"]) * 3.0
		look = ahead.lerp(look, turned)
	# at the runner's own eyes (KT: in front of the head, never behind it); the framing comes from her holding them at arm's
	# length, the view tipping up to her face and, when she is still close, a slightly wider view during the hold (_fov_for)
	var wanted := head_world
	# the eyes move smoothly (every grab pose is eased), so the camera rides them exactly: it never trails behind the head.
	# Only her collider or a wall can move it (up or to the side, never back); any part of her model at the lens is not
	# drawn for this camera that frame instead (_cull_near)
	var at := _clear(wanted, CLEARANCE)
	if at.distance_to(wanted) > .001:
		pushes += 1
	var previous := _last_camera
	# the first CATCH_EASE seconds ease from the runner's own view when caught to the grabbed body's face (a body turned round
	# for a leg grab moves it furthest)
	if elapsed < CATCH_EASE and playing:
		at = _catch_camera.origin.lerp(at, GrabStyles.smooth(elapsed / CATCH_EASE))
	var step := at - previous.origin
	# never a jump: a push (or coming back from one) moves at most MAX_PUSH a frame more than the eyes themselves moved
	var eyes_moved := wanted.distance_to(_last_wanted) if _last_wanted != Vector3.INF else 0.0
	_last_wanted = wanted
	if step.length() > eyes_moved + MAX_PUSH:
		at = previous.origin + step.limit_length(eyes_moved + MAX_PUSH)
	_cull_near(at)
	var to := look - at
	var flat_to := Vector2(to.x, to.z).length()
	var pitch := clampf(atan2(to.y, flat_to), -MAX_LOOK_PITCH, MAX_LOOK_PITCH)
	var yaw := atan2(-to.x, -to.z)
	if flat_to < .12:
		# she is almost straight overhead (knocked flat under her): keep the heading the view already has, or the turn
		# around the vertical would flip half a circle and roll the view over on the way
		var ahead := -previous.basis.z
		if Vector2(ahead.x, ahead.z).length() > .05:
			yaw = atan2(-ahead.x, -ahead.z)
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	basis = Basis(basis.z.normalized(), -roll) * basis   # roll about the view axis
	var from := previous.basis.orthonormalized().get_rotation_quaternion()
	var to_q := basis.get_rotation_quaternion()
	var weight := 1.0 - exp(-EASE_RATE * delta)
	var gap := from.angle_to(to_q)
	if gap * weight > MAX_TURN * delta:
		weight = MAX_TURN * delta / gap
	return Transform3D(Basis(from.slerp(to_q, weight)), at)


## During the hold only, the view widens (eased, at most fov_widen degrees) as far as her face is closer than
## FACE_DISTANCE, so a hunter half again the runner's size still fits the frame from the runner's own eyes.
func _widen_view(at: Vector3, t: float, delta: float) -> void:
	if _player.xr_active:
		return
	var head := _view.find_child("Head", true, false) as Node3D
	var close := 0.0
	if head != null:
		close = clampf((FACE_DISTANCE - at.distance_to(head.global_position)) / .5, 0.0, 1.0)
	var hold := GrabStyles.smooth((t - GrabStyles.REACH_SECONDS - GrabStyles.ACT_SECONDS * .5) / .5)
	var wanted := _base_fov + fov_widen * close * hold
	var camera := _player.first_person_camera
	camera.fov = move_toward(camera.fov, wanted, 20.0 * maxf(delta, 0.0))


## Runs the grab on the local runner; returns when the hold ends (the runner stays held until release()).
## `roll` is the host's roll for this catch (GrabStyles.roll_for).
func play(player: PlayerController3D, view: Node3D, hunter_id: String, roll: float, force_style: String = "") -> void:
	if playing or player == null or view == null:
		return
	_player = player
	_view = view
	_hunter_id = hunter_id
	_base_fov = player.first_person_camera.fov
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
	if STRETCH_STYLES.has(style):
		_ctx["arm"] = float(_ctx.get("arm", .66)) * arm_stretch   # she holds the runner at her (stretched) arm's length
	_start = player.global_position
	for key in ["grab_head_turn", "grab_chest_turn"]:
		view.remove_meta(key)
	print("[grab] hunter=%s style=%s roll=%.3f room=%s" % [hunter_id, style, roll, room])
	playing = true
	elapsed = 0.0
	pushes = 0
	player.begin_grab_view()
	_apply(0.0, 0.0)
	while elapsed < GrabStyles.duration(style) and is_inside_tree() and is_instance_valid(player) and is_instance_valid(view):
		await get_tree().process_frame
		var delta := get_process_delta_time()
		elapsed += delta
		_apply(elapsed, delta)
	playing = false


func _apply(t: float, delta: float) -> void:
	_applied_frame = Engine.get_process_frames()
	culled.clear()
	if t == 0.0:
		_last_camera = _player.first_person_camera.global_transform
		_catch_camera = _last_camera
		_last_wanted = Vector3.INF
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
	if bool(current.get("walk", false)):
		play_walk(_view, t)
	stretch_arms(_view, stretch_for(style, t))
	var points := contacts(body_feet, basis, current["arms"])
	for _i in 3:
		var fix := reach_correction(_view, _along, points)
		if absf(fix.x) < .005 and fix.y < .005:
			break
		offsets[0] = float(offsets[0]) + fix.x
		offsets[1] = float(offsets[1]) + fix.y
		pose_hunter_body(_view, _along, offsets)
	contact_gap = pose_arms_on(_view, _along, points, bool(current.get("wide", false)))
	# her eyes go to the camera itself (last frame's: the camera is fitted after), after the arms: only her head turns, so the
	# hands stay on what they hold
	var her_target := _last_camera.origin
	if bool(current.get("her_look_ahead", false)):
		her_target = _view.global_position + _along * (4.0 + float((current["hunter"] as Array)[0])) + Vector3.UP * 1.6
	head_look(_view, her_target, delta, _along, GrabStyles.look_away(_hunter_id, t))
	# the runner's own body, drawn from inside: posed like everyone else sees it, its hands on what they hold
	var body := _player.first_person_body()
	if not _player.xr_active:
		body.pose(body_feet, basis, String(current["clip"]))
		# hung head down, the runner looks up along their own body at her: their torso and thighs are left out of their own
		# view (others still see them; the calves and feet in her hand stay)
		body.hide_parts(UPSIDE_DOWN_HIDDEN if style == GrabStyles.UPSIDE_DOWN else [])
		_player.first_person_camera.near = PlayerController3D.MODEL_EYE_NEAR
	if body.model != null:
		pose_runner_arms(body.model, _view, current, _along, t)
	# the camera sits at that body's real eyes (no drift from the head), clear of her and the walls, eased
	var head := body.eye() if body.model != null else basis * Vector3(0.0, _ctx["eye"], 0.0) + body_feet
	head.y = maxf(head.y, _player.global_position.y + .1)
	var roll := float(current["view_roll"])
	if style == GrabStyles.UPSIDE_DOWN:
		var flip := float(current.get("flip", 0.0))
		roll = PI * flip + clampf(roll - PI * flip, -FLIP_SWAY, FLIP_SWAY)
	else:
		roll = clampf(roll, -MAX_ROLL, MAX_ROLL)
	var camera := _solve_camera(head, roll, delta)
	_last_camera = camera
	_widen_view(camera.origin, t, delta)
	_player.set_grab_camera(camera, _body_yaw(face), String(current["clip"]))
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
	_apply(GrabStyles.duration(style), delta)


## Lets go: the runner stands back up and the hunter's model is put back (a new run, a respawn).
func release() -> void:
	playing = false
	current = {}
	state = []
	var restore: Array = []
	if _view != null and is_instance_valid(_view):
		restore.append_array(_view.find_children("*", "MeshInstance3D", true, false))
	if _player != null and is_instance_valid(_player) and _player.first_person_body().model != null:
		restore.append_array(_player.first_person_body().model.find_children("*", "MeshInstance3D", true, false))
	for node in restore:
		if node.has_meta("grab_layers"):
			(node as MeshInstance3D).layers = int(node.get_meta("grab_layers"))
			node.remove_meta("grab_layers")
	if _view != null and is_instance_valid(_view):
		stretch_arms(_view, 1.0)
		for node in _view.find_children("*", "MeshInstance3D", true, false):
			if node.has_meta("grab_layers"):
				(node as MeshInstance3D).layers = int(node.get_meta("grab_layers"))
				node.remove_meta("grab_layers")
		culled.clear()
		pose_hunter_body(_view, _along, [])
		for key in ["grab_head_turn", "grab_chest_turn"]:
			_view.remove_meta(key)
		if "grab_until_msec" in _view:
			_view.set("grab_until_msec", 0)
	if _player != null and is_instance_valid(_player):
		_player.first_person_camera.fov = _base_fov
		_player.end_grab_view()
	_view = null
