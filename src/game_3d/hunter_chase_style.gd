class_name HunterChaseStyle
extends RefCounted

## Per-hunter chase styles (KT 2026-10-28: "make hunter chase animations different per hunter ... hands reaching out
## toward you"; table approved as proposed). An additive UPPER-BODY layer on top of the chase/sprint clip: arms,
## forearms (the elbow bones), chest, belly and head only. The legs keep the measured stride (HunterStride), so the
## planted foot stays exactly where foot_slip measured it, and nothing here changes how fast a hunter really moves.
##
##   reach2     both arms forward at the runner (aimed, clamped to +-AIM_LIMIT), elbows soft, a grasping wobble
##   reach1     the lead arm reaches at the runner, the other keeps pumping
##   pump       the clip's own run (variants: fast / big arm swing, fists, wings)
##   lope       chest low, head forward, arms loose
##   glide      arms held at the sides, torso upright and still
##   skitter    folded low over the arms, claws forward
##   stalk      head tilted, straightening and leaning in the longer the chase goes on
##   stopstart  every couple of seconds the arms lock and the head twitches for half a second
##
## The style comes from the hunter's data file (data/hunters/<id>.json "chase_style", "style" or "style:variant"; a
## pack's hunter file sets its own) or a runtime override, else DEFAULT; the brain carries the id, so co-op only syncs
## that string.

const STYLES := ["reach2", "reach1", "pump", "lope", "glide", "skitter", "stalk", "stopstart"]
const DEFAULT := "pump"
const AIM_LIMIT := deg_to_rad(35.0)
const BLEND_SPEED := 3.0          # weight per second, in and out of a chase


## Runtime overrides (tools, tests): hunter id -> style string; they win over the data file.
static var _overrides := {}


static func set_override(hunter_id: String, style: String) -> void:
	if style.is_empty():
		_overrides.erase(hunter_id)
	elif valid(style):
		_overrides[hunter_id] = style


static func valid(style: String) -> bool:
	return STYLES.has(style.get_slice(":", 0))


static func style_for(hunter_id: String) -> String:
	var override := String(_overrides.get(hunter_id, ""))
	if not override.is_empty():
		return override
	var from_data := String((HunterRoster.PROFILES.get(hunter_id, {}) as Dictionary).get("chase_style", ""))   # packs too
	return from_data if valid(from_data) else DEFAULT


static func base(style: String) -> String:
	var name := style.get_slice(":", 0)
	return name if STYLES.has(name) else DEFAULT


static func variant(style: String) -> String:
	return style.get_slice(":", 1) if style.contains(":") else ""


static func reaches(style: String) -> bool:
	return base(style) in ["reach2", "reach1"]


# ------------------------------------------------------------------------------------------------ the layer

const BONES := ["L-Arm", "R-Arm", "L-Forearm", "R-Forearm", "Chest", "Belly", "Head"]

var _model: Node3D
var _nodes := {}
var _rest := {}
var _written := {}
var weight := 0.0
var chase_time := 0.0


func bind(model: Node3D) -> void:
	_model = model
	_nodes.clear()
	_rest.clear()
	_written.clear()
	if model == null:
		return
	for bone in BONES:
		var node := model.find_child(bone, true, false) as Node3D
		if node != null:
			_nodes[bone] = node
			_rest[bone] = node.quaternion


## Undo last frame's layer on any bone the clip did not rewrite since (so it never accumulates), like DoorwayPose.
func restore() -> void:
	for bone in _written:
		var node := _nodes.get(bone) as Node3D
		var entry: Array = _written[bone]
		if node != null and node.quaternion.is_equal_approx(entry[1]):
			node.quaternion = entry[0]
	_written.clear()


static func _q(degrees: Vector3) -> Quaternion:
	return NightWatchPoses.key_quaternion(degrees)


func _put(bone: String, value: Quaternion) -> void:
	var node := _nodes.get(bone) as Node3D
	if node == null:
		return
	_written[bone] = [node.quaternion, value]
	node.quaternion = value


func _now(bone: String) -> Quaternion:
	var node := _nodes.get(bone) as Node3D
	return node.quaternion if node != null else Quaternion.IDENTITY


## Scales how far the clip has swung a bone away from its rest pose (arm swing amplitude).
func _swing(bone: String, scale: float) -> Quaternion:
	var rest: Quaternion = _rest.get(bone, Quaternion.IDENTITY)
	var delta := _now(bone) * rest.inverse()
	var angle := delta.get_angle()
	if angle < .0001:
		return _now(bone)
	return Quaternion(delta.get_axis(), angle * scale) * rest


## `chasing`: the eased target (CHASE, not stunned, not posing). `aim`: signed yaw (radians) from the body's forward to
## the runner, already clamped. `clock`: seconds, any shared clock.
func apply(style: String, chasing: bool, delta: float, aim: float, clock: float) -> void:
	weight = move_toward(weight, 1.0 if chasing else 0.0, delta * BLEND_SPEED)
	chase_time = chase_time + delta if chasing else 0.0
	if weight <= .001 or _nodes.is_empty():
		return
	var w := weight * weight * (3.0 - 2.0 * weight)
	var kind := base(style)
	var extra := variant(style)
	match kind:
		"reach2", "reach1":
			var arms := ["L-Arm", "R-Arm"] if kind == "reach2" else ["R-Arm"]
			for arm in arms:
				var wobble := sin(clock * 7.0 + (0.0 if arm == "L-Arm" else 1.7)) * 4.0
				var reach := Quaternion(Vector3.UP, aim * w) * _q(Vector3(80.0 + wobble, 0, 0) * w)
				_put(arm, reach * _rest.get(arm, Quaternion.IDENTITY).slerp(_now(arm), 1.0 - w))
				var fore: String = arm.replace("Arm", "Forearm")
				_put(fore, _q(Vector3(14.0, 0, 0) * w) * _rest.get(fore, Quaternion.IDENTITY).slerp(_now(fore), 1.0 - w))
		"pump":
			match extra:
				"fast", "big":
					var amount := 1.35 if extra == "fast" else 1.55
					for arm in ["L-Arm", "R-Arm", "L-Forearm", "R-Forearm"]:
						_put(arm, _now(arm).slerp(_swing(arm, amount), w))
				"fists":
					for fore in ["L-Forearm", "R-Forearm"]:
						_put(fore, _q(Vector3(38.0, 0, 0) * w) * _now(fore))
				"wings":
					for arm in ["L-Arm", "R-Arm"]:
						var side := -1.0 if arm == "L-Arm" else 1.0
						var flap := sin(clock * 9.0) * 8.0
						_put(arm, _q(Vector3(10.0, 0, (70.0 + flap) * side) * w) * _rest.get(arm, Quaternion.IDENTITY).slerp(_now(arm), 1.0 - w))
		"lope":
			_put("Chest", _q(Vector3(-14, 0, 0) * w) * _now("Chest"))
			_put("Belly", _q(Vector3(-10, 0, 0) * w) * _now("Belly"))
			_put("Head", _q(Vector3(18, 0, 0) * w) * _now("Head"))
			for arm in ["L-Arm", "R-Arm"]:
				_put(arm, _q(Vector3(15, 0, 0) * w) * _now(arm).slerp(_rest.get(arm, Quaternion.IDENTITY), .5 * w))
		"glide":
			for bone in ["L-Arm", "R-Arm", "L-Forearm", "R-Forearm", "Chest", "Belly"]:
				_put(bone, _now(bone).slerp(_rest.get(bone, Quaternion.IDENTITY), .85 * w))
		"skitter":
			_put("Belly", _q(Vector3(-24, 0, 0) * w) * _now("Belly"))
			_put("Chest", _q(Vector3(-18, 0, 0) * w) * _now("Chest"))
			_put("Head", _q(Vector3(32, 0, 0) * w) * _now("Head"))
			for arm in ["L-Arm", "R-Arm"]:
				var fore: String = arm.replace("Arm", "Forearm")
				_put(arm, _q(Vector3(40, 0, 0) * w) * _now(arm).slerp(_rest.get(arm, Quaternion.IDENTITY), .6 * w))
				_put(fore, _q(Vector3(42, 0, 0) * w) * _now(fore))
		"stalk":
			# starts slow and tilted, straightens and leans in as the chase drags on (presentation; her speed is hers)
			var urge := clampf(chase_time / 4.0, 0.0, 1.0)
			_put("Head", _q(Vector3(6, 0, lerpf(18.0, 6.0, urge)) * w) * _now("Head"))
			_put("Chest", _q(Vector3(lerpf(-4.0, -16.0, urge), 0, 0) * w) * _now("Chest"))
			for arm in ["L-Arm", "R-Arm"]:
				_put(arm, _q(Vector3(lerpf(5.0, 30.0, urge), 0, 0) * w) * _now(arm).slerp(_rest.get(arm, Quaternion.IDENTITY), (1.0 - urge) * .6 * w))
		"stopstart":
			# a half-second lock every ~2 s: arms pinned mid-swing, the head twitching (the legs keep running)
			var cycle := fmod(clock + float(abs(hash(style)) % 100) * .01, 2.1)
			if cycle < .5:
				var lock := sin(cycle / .5 * PI)
				for arm in ["L-Arm", "R-Arm"]:
					_put(arm, _now(arm).slerp(_q(Vector3(28, 0, 0)) * _rest.get(arm, Quaternion.IDENTITY), lock * w))
				_put("Head", _q(Vector3(0, sin(clock * 47.0) * 9.0, sin(clock * 31.0) * 6.0) * lock * w) * _now("Head"))
