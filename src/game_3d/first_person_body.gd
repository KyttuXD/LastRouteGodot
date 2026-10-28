class_name FirstPersonBody
extends Node3D

## True first person (KT): while climbing or held by a hunter, the runner sees their own third-person player model (the very
## model others see, PlayerController3D._body_model, same skin, scale and clip) from its eyes. This node switches that model
## into first person (shown, head hidden), places and poses it for whoever owns the view (a grab, a ladder climb), bends its
## arms onto what the hands hold after the clip has run, and gives the camera the model's real eye position.

var model: Node3D
var animation: AnimationPlayer
var _body_visual: Node3D
var _rest := Transform3D.IDENTITY
var _clip := ""
var _hidden_head: Array = []
## The arm bones' rest transforms: put back before each frame's IK, so a clip that does not key the arms (idle) never leaves
## last frame's bend (or its rounding) to build on.
var _arm_rest := {}
## Hands to hold on to, applied after the clip has posed the arms each frame: {"L": world point, "R": ..., "pole_L": ...}.
var hand_targets := {}
## While set (a ladder climb), this camera pivot is moved to the model's eyes every frame, after the clip and the hands.
var drive_camera: Node3D
## Radians the (hidden) head is tipped back after the clip, which brings the eyes back over the shoulders: on a ladder the
## face would otherwise be against the rungs the hands are holding.
var head_tilt := 0.0


func _init() -> void:
	name = "FirstPersonBody"
	visible = false
	process_priority = 70   # after the animation players, so the clip never takes the hands off what they hold


func attach(body_model: Node3D, body_visual: Node3D, player: AnimationPlayer) -> void:
	model = body_model
	_body_visual = body_visual
	animation = player
	_rest = model.transform if model != null else Transform3D.IDENTITY
	_arm_rest.clear()
	if model == null:
		return
	for bone_name in ["L-Arm", "L-Forearm", "L-Hand", "R-Arm", "R-Forearm", "R-Hand"]:
		var bone := model.find_child(bone_name, true, false) as Node3D
		if bone != null:
			_arm_rest[bone] = bone.transform


## On: the player model is drawn in first person with its head hidden. Off: back where and how it was, hidden again.
func set_active(on: bool) -> void:
	if model == null or visible == on:
		return
	visible = on
	_body_visual.visible = on
	if on:
		_hidden_head.clear()
		var head := model.find_child("Head", true, false)
		if head != null:
			for mesh in [head] + head.find_children("*", "MeshInstance3D", true, false):
				if mesh is MeshInstance3D and (mesh as MeshInstance3D).visible:
					(mesh as MeshInstance3D).visible = false
					_hidden_head.append(mesh)
	else:
		for mesh in _hidden_head:
			if is_instance_valid(mesh):
				(mesh as MeshInstance3D).visible = true
		_hidden_head.clear()
		model.transform = _rest
		for bone in _arm_rest:
			if is_instance_valid(bone):
				(bone as Node3D).transform = _arm_rest[bone]
		hand_targets = {}
		drive_camera = null
		head_tilt = 0.0
		_clip = ""


## Feet at `feet`, turned and leaned by `basis` (GrabStyles.body_basis), playing `clip`.
func pose(feet: Vector3, basis: Basis, clip: String) -> void:
	if model == null:
		return
	set_active(true)
	model.global_transform = Transform3D(basis.orthonormalized() * Basis.from_scale(Vector3.ONE * PlayerModels.SCALE), feet)
	if clip != _clip or (animation != null and not animation.is_playing()):
		_clip = clip
		ModelSlot.play_if_available(animation, clip)
	for bone in _arm_rest:
		if is_instance_valid(bone):
			(bone as Node3D).transform = _arm_rest[bone]


## Where the model's eyes are: the camera goes exactly here.
func eye() -> Vector3:
	if model == null:
		return global_position + Vector3.UP * 1.35
	var left := model.find_child("L-Eye-Attachment", true, false) as Node3D
	var right := model.find_child("R-Eye-Attachment", true, false) as Node3D
	if left != null and right != null:
		return (left.global_position + right.global_position) * .5
	var head := model.find_child("Head", true, false) as Node3D
	return head.global_position + head.global_basis.y.normalized() * .17 if head != null else model.global_position


func _process(_delta: float) -> void:
	if not visible or model == null:
		return
	if not hand_targets.is_empty():
		for bone in _arm_rest:
			if is_instance_valid(bone):
				(bone as Node3D).transform = _arm_rest[bone]
		for key in ["L", "R"]:
			if hand_targets.has(key):
				HunterGrab.solve_arm(model, key, hand_targets[key], 1.0, hand_targets.get("pole_" + key, Vector3.DOWN))
	if not is_zero_approx(head_tilt):
		var head := model.find_child("Head", true, false) as Node3D
		if head != null:
			var scale := head.global_basis.get_scale()
			head.global_basis = (Basis(model.global_basis.x.normalized(), head_tilt) * head.global_basis.orthonormalized()) \
				* Basis.from_scale(scale)
	if drive_camera != null and is_instance_valid(drive_camera):
		drive_camera.global_position = eye()
