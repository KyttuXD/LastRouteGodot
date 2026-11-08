class_name NightWatchPoseLayers
extends RefCounted

## Procedural layers added on top of whatever clip or Night Watch pose is playing: breathing, a slow
## sway and a lean into turns. Additive on Pelvis/Belly/Chest the same way the head look is (the clip's
## pose when it drives the bone, otherwise the rest pose), so nothing accumulates and nothing needs a
## model edit. Off unless the view sets `nw_layers`.

const BREATH := deg_to_rad(1.4)
const SWAY := deg_to_rad(1.6)
const LEAN_PER_TURN := .04
const LEAN_LIMIT := deg_to_rad(9.0)
const FADE_SPEED := 3.0

var weight := 0.0
var phase := 0.0
var _bones := {}
var _applied := false


func bind(model: Node) -> void:
	_bones.clear()
	for bone in ["Pelvis", "Belly", "Chest"]:
		var node := model.find_child(bone, true, false) as Node3D
		if node != null:
			_bones[bone] = {"node": node, "rest": node.quaternion, "written": node.quaternion}


## yaw_rate: radians/s of the body turn; moving: whether she is walking (lean only applies then).
func apply(delta: float, seconds: float, yaw_rate: float, moving: bool, on: bool) -> void:
	weight = move_toward(weight, 1.0 if on else 0.0, delta * FADE_SPEED)
	if _bones.is_empty():
		return
	# perf pass: faded out (the normal case for a hunter) every layer is an identity rotation, so there is nothing to write;
	# the frame the weight reaches 0 still writes once, which puts the bones back on their rest pose
	if weight <= 0.0 and not _applied:
		return
	_applied = weight > 0.0
	var breath := sin(seconds * 1.6 + phase) * BREATH * weight
	var sway := sin(seconds * .55 + phase * 1.7) * SWAY * weight
	var lean := clampf(yaw_rate * LEAN_PER_TURN, -LEAN_LIMIT, LEAN_LIMIT) * weight if moving else 0.0
	_add("Chest", Quaternion(Vector3.RIGHT, breath))
	_add("Belly", Quaternion(Vector3.FORWARD, sway * .6))
	_add("Pelvis", Quaternion(Vector3.FORWARD, sway * .4 - lean))


func _add(bone: String, delta_q: Quaternion) -> void:
	if not _bones.has(bone):
		return
	var entry: Dictionary = _bones[bone]
	var node: Node3D = entry["node"]
	var current := node.quaternion
	var base: Quaternion = entry["rest"] if current.is_equal_approx(entry["written"] as Quaternion) else current
	node.quaternion = delta_q * base
	entry["written"] = node.quaternion
