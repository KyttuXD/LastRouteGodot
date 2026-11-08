class_name DoorwayPose
extends RefCounted

## How a 1.5x hunter gets through a door frame without her head or shoulders going through it:
## a duck (knees bend, a lean and a head dip) when the opening is lower than her head plus DoorwayFrames.HEADROOM, and a
## shoulder turn (the upper body turns side-on, the head keeps looking ahead, arms and stride swing less) when the opening
## is narrower than her shoulders. Additive on whatever the clip, the head look and the Night Watch layers left on the bones,
## undone at the start of the next frame, so nothing accumulates and no .glb is touched.
##
##   pose.bind(model)                      # once per model
##   pose.restore()                        # first thing each frame, before the other layers
##   pose.update(delta, frame, at_local)   # last thing each frame (frame = DoorwayFrames.nearest)

const TURN := deg_to_rad(90.0)
const KNEE := deg_to_rad(64.0)
const LEAN := deg_to_rad(24.0)
const NOD := deg_to_rad(26.0)
## How much of the clip's arm and leg swing is kept while turned (0 = all).
const SWING_KEEP := .1
## Fully in the pose from FULL metres either side of the wall plane, easing in from START.
const FULL := 2.0
const START := 3.2
const RELEASE_SPEED := 3.0
## Extra the duck allows for the clip's bob and the head look over the measured rest height.
const DUCK_SPARE := .22
## The most the upper body shifts sideways to centre her head (metres).
const MAX_CENTRE_SHIFT := .12
const STANCE_IN := deg_to_rad(4.0)
## Hair, wings and tails that stick out sideways are swept round to trail along her way (as a frame would brush them).
const SWEEP_PARENTS := ["Pelvis", "Belly", "Chest", "Head"]
const SWEEP_MIN_REACH := .08
const BONES := ["Pelvis", "Belly", "Chest", "Head", "L-Thigh", "L-Calf", "L-Foot", "R-Thigh", "R-Calf", "R-Foot",
	"L-Arm", "L-Forearm", "L-Hand", "R-Arm", "R-Forearm", "R-Hand"]

var turn := 0.0
var duck := 0.0
## Arms and stride calmed without turning (a wide door with less than WIDE_SIDE_ROOM to spare at the shoulders).
var tuck := 0.0
## Measured on bind, in the model's parent space (metres): rest top, top at a full duck, rest width (x) and depth (z).
var rest_height := 0.0
var duck_height := 0.0
var rest_width := 0.0
var rest_depth := 0.0

var _model: Node3D
var _want_tuck := 0.0
var _bones := {}
var _extras: Array[String] = []
## Chains swept to lie along her way while she is side-on: name -> {"parent", "angle" (rest heading in the parent)}.
var _sweeps := {}
var _drop := 0.0
## Sideways offset of the head's own bounds (hair parted to one side, a single ear or horn), undone while side-on so the
## widest part of her stays in the middle of the opening.
var _head_offset := 0.0
## 1 when the head turns back to look ahead while side-on, 0 when it turns with the body (pigtails either side of the
## head are narrower that way); picked per rig on bind.
var _head_back := 1.0
var _head_offset_ducked := 0.0
var _active := false


func bind(model: Node3D) -> void:
	_model = model
	_bones.clear()
	_active = false
	turn = 0.0
	duck = 0.0
	_head_offset = 0.0
	_head_offset_ducked = 0.0
	_head_back = 1.0
	tuck = 0.0
	for bone in BONES:
		var node := model.find_child(bone, true, false) as Node3D
		if node != null:
			_bones[bone] = {"node": node, "rest_q": node.quaternion, "rest_p": node.position,
				"pre_q": node.quaternion, "pre_p": node.position, "written_q": node.quaternion, "written_p": node.position}
	if not _bones.has("Pelvis"):
		_bones.clear()
		return
	# hair, ears, tails, wings: their clip swing is calmed with the arms (a ponytail swinging out sideways hit the post)
	_extras.clear()
	_sweeps.clear()
	for node in (_bones["Pelvis"]["node"] as Node3D).find_children("*", "Node3D", true, false):
		if not BONES.has(String(node.name)) and not node.name.ends_with("Attachment") and not node.name.ends_with("Prop") \
				and node.name != "Face":
			_extras.append(String(node.name))
			_bones[String(node.name)] = {"node": node, "rest_q": node.quaternion, "rest_p": node.position,
				"pre_q": node.quaternion, "pre_p": node.position, "written_q": node.quaternion, "written_p": node.position}
			# a chain hanging off a body bone (ponytail, pigtail, wing, tail): which way it points, seen from above
			var parent_name := String(node.get_parent().name)
			if SWEEP_PARENTS.has(parent_name):
				var reach: Vector3 = bounds(node).get_center() - (node as Node3D).position
				if Vector2(reach.x, reach.z).length() > SWEEP_MIN_REACH:
					_sweeps[String(node.name)] = {"parent": parent_name, "angle": atan2(reach.x, reach.z)}
	var thigh := 0.0
	var calf := 0.0
	if _bones.has("L-Calf") and _bones.has("L-Foot"):
		thigh = (_bones["L-Calf"]["rest_p"] as Vector3).length()
		calf = (_bones["L-Foot"]["rest_p"] as Vector3).length()
	_drop = (thigh + calf) * (1.0 - cos(KNEE))
	var rest := bounds(model)
	rest_height = rest.end.y
	rest_width = rest.size.x
	rest_depth = rest.size.z
	_write(0.0, 1.0)
	duck_height = bounds(model).end.y
	restore()
	# measured side-on: where the head (and what hangs off it) ends up across the opening
	var head := _bones.get("Head", {}).get("node") as Node3D
	if head != null and model.scale.x > 0.0:
		var best := INF
		var pick := 1.0
		for back in [1.0, .75, .5, .25, 0.0]:
			_head_back = back
			_write(1.0, 0.0)
			var across := bounds(head, _chain(model, head))
			restore()
			if across.size.x < best - .01:
				best = across.size.x
				pick = back
		_head_back = pick
		var offsets := []
		for ducked in [0.0, 1.0]:
			_write(1.0, ducked)
			offsets.append(clampf(_own_box(model, head).get_center().x, -MAX_CENTRE_SHIFT, MAX_CENTRE_SHIFT)
				/ model.scale.x)
			restore()
		_head_offset = offsets[0]
		_head_offset_ducked = offsets[1]


## `node`'s parent chain from the model's parent space (the model's own transform included).
static func _chain(model: Node3D, node: Node3D) -> Transform3D:
	var path: Array[Node3D] = []
	var walk := node.get_parent_node_3d()
	while walk != null and walk != model:
		path.push_front(walk)
		walk = walk.get_parent_node_3d()
	var chain := model.transform
	for step in path:
		chain = chain * step.transform
	return chain


## A node's own mesh box (without its children) in the model's parent space; its subtree's when it has no mesh itself.
static func _own_box(model: Node3D, node: Node3D) -> AABB:
	var chain := _chain(model, node) * node.transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return chain * (node as MeshInstance3D).get_aabb()
	return bounds(node, _chain(model, node))


func bound() -> bool:
	return not _bones.is_empty()


## What this frame asks of her at `local` (her position in the frame's space): Vector2(turn, duck), 0..1 each.
func wanted(frame: Dictionary, local_along: float) -> Vector2:
	if frame.is_empty() or _bones.is_empty():
		return Vector2.ZERO
	var near := 1.0 - smoothstep(FULL, START, absf(local_along))
	if near <= 0.0:
		return Vector2.ZERO
	var want_turn := 1.0 if rest_width + DoorwayFrames.SIDE_ROOM * 2.0 > float(frame["width"]) else 0.0
	_want_tuck = near if want_turn == 0.0 and rest_width + DoorwayFrames.WIDE_SIDE_ROOM * 2.0 > float(frame["width"]) else 0.0
	var excess := rest_height + DoorwayFrames.HEADROOM + DUCK_SPARE - float(frame["height"])
	var gain := maxf(rest_height - duck_height, .01)
	var want_duck := clampf(excess / gain, 0.0, 1.0) if excess > 0.0 else 0.0
	return Vector2(want_turn, want_duck) * near


## Undoes last frame's overlay on every bone the clip did not write since (call before the other layers).
func restore() -> void:
	if not _active:
		return
	for entry_value in _bones.values():
		var entry: Dictionary = entry_value
		var node: Node3D = entry["node"]
		if node.quaternion.is_equal_approx(entry["written_q"]):
			node.quaternion = entry["pre_q"]
		if node.position.is_equal_approx(entry["written_p"]):
			node.position = entry["pre_p"]
	_active = false


## Eases toward the frame's wish (instantly into the pose, softly out of it) and applies it.
func update(delta: float, frame: Dictionary, local_along: float) -> void:
	var want := wanted(frame, local_along)
	turn = maxf(want.x, move_toward(turn, want.x, delta * RELEASE_SPEED))
	duck = maxf(want.y, move_toward(duck, want.y, delta * RELEASE_SPEED))
	tuck = maxf(_want_tuck, move_toward(tuck, _want_tuck, delta * RELEASE_SPEED))
	if turn > .001 or duck > .001 or tuck > .001:
		_write(turn, duck, tuck)


func _write(turn_w: float, duck_w: float, tuck_w: float = 0.0) -> void:
	if _bones.is_empty():
		return
	for entry_value in _bones.values():
		var entry: Dictionary = entry_value
		var node: Node3D = entry["node"]
		entry["pre_q"] = node.quaternion
		entry["pre_p"] = node.position
	var calm := (1.0 - SWING_KEEP) * maxf(maxf(turn_w, duck_w * .6), tuck_w)
	var still := maxf(turn_w, duck_w * .6)
	var knee := KNEE * duck_w
	# the clip's hip sway and bob are calmed too, so she keeps to the middle of the opening
	var pelvis_rest: Vector3 = _bones["Pelvis"]["rest_p"]
	var pelvis_at := _p("Pelvis").lerp(Vector3(pelvis_rest.x, _p("Pelvis").y, _p("Pelvis").z), still)
	_put("Pelvis", _calm("Pelvis", still), pelvis_at + Vector3.DOWN * _drop * duck_w)
	# the upper body turns side-on (shifted so her head is centred) and leans along the way she is going; the head
	# turns back to look ahead and dips
	_put("Belly", _calm("Belly", still) * Quaternion(Vector3.RIGHT, -LEAN * duck_w) * Quaternion(Vector3.UP, TURN * turn_w),
		(_bones["Belly"]["rest_p"] as Vector3) + Vector3.LEFT * lerpf(_head_offset, _head_offset_ducked, duck_w) * turn_w)
	_put("Chest", _calm("Chest", still))
	# the dip is about the axis across her way (in the turned chest's frame), whichever way the head faces
	var across := Basis(Vector3.UP, -TURN * turn_w) * Vector3.RIGHT
	_put("Head", Quaternion(across, -NOD * duck_w) * _calm("Head", still) * Quaternion(Vector3.UP, -TURN * turn_w * _head_back))
	for extra in _extras:
		var q := _calm(extra, calm)
		if _sweeps.has(extra) and turn_w > .001:
			var sweep: Dictionary = _sweeps[extra]
			var heading := float(sweep["angle"]) + _parent_yaw(String(sweep["parent"]), turn_w)
			var target := roundf(heading / PI) * PI
			q = Quaternion(Vector3.UP, (target - heading) * turn_w) * q
		_put(extra, q)
	for side in ["L-", "R-"]:
		# side-on, the feet come in a little under her
		var inward := Quaternion(Vector3.BACK, (STANCE_IN if side == "L-" else -STANCE_IN) * turn_w)
		_put(side + "Thigh", inward * _calm(side + "Thigh", calm) * Quaternion(Vector3.RIGHT, knee))
		_put(side + "Calf", _calm(side + "Calf", calm) * Quaternion(Vector3.RIGHT, -2.0 * knee))
		_put(side + "Foot", _calm(side + "Foot", calm) * Quaternion(Vector3.RIGHT, knee))
		# side-on, a bent elbow puts the hand out to the side: the arms hang straight while she squeezes through
		_put(side + "Arm", _calm(side + "Arm", calm, true))
		_put(side + "Forearm", _calm(side + "Forearm", calm, true))
		_put(side + "Hand", _calm(side + "Hand", calm, true))
	_active = true


## How far this pose turns a body bone about the vertical, relative to her hips.
func _parent_yaw(bone: String, turn_w: float) -> float:
	match bone:
		"Belly", "Chest":
			return TURN * turn_w
		"Head":
			return TURN * turn_w * (1.0 - _head_back)
	return 0.0


func _q(bone: String) -> Quaternion:
	return _bones[bone]["pre_q"] if _bones.has(bone) else Quaternion.IDENTITY


func _p(bone: String) -> Vector3:
	return _bones[bone]["pre_p"] if _bones.has(bone) else Vector3.ZERO


## The clip's rotation pulled toward the rest pose (smaller swing), or toward hanging straight (`straight`).
func _calm(bone: String, amount: float, straight: bool = false) -> Quaternion:
	if not _bones.has(bone):
		return Quaternion.IDENTITY
	var target: Quaternion = Quaternion.IDENTITY if straight else _bones[bone]["rest_q"]
	return (_bones[bone]["pre_q"] as Quaternion).slerp(target, amount)


func _put(bone: String, q: Quaternion, p: Variant = null) -> void:
	if not _bones.has(bone):
		return
	var entry: Dictionary = _bones[bone]
	var node: Node3D = entry["node"]
	node.quaternion = q
	if p != null:
		node.position = p
	entry["written_q"] = node.quaternion
	entry["written_p"] = node.position


## The model's mesh bounds in its parent's space (the model's own scale included).
static func bounds(model: Node3D, parent_space: Transform3D = Transform3D.IDENTITY) -> AABB:
	var result := AABB()
	var first := true
	for box in mesh_boxes(model, parent_space):
		result = box if first else result.merge(box)
		first = false
	return result


## One box per mesh, in `parent_space` * the model's transform (used for the per-part frame checks). `names`, when given,
## gets each box's mesh name.
static func mesh_boxes(model: Node3D, parent_space: Transform3D = Transform3D.IDENTITY, names: Array = []) -> Array[AABB]:
	var out: Array[AABB] = []
	var stack := [[model, parent_space * model.transform]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var xf: Transform3D = item[1]
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null and (node as MeshInstance3D).visible:
			out.append(xf * (node as MeshInstance3D).get_aabb())
			names.append(String(node.name))
		for child in node.get_children():
			if child is Node3D:
				stack.append([child, xf * (child as Node3D).transform])
	return out
