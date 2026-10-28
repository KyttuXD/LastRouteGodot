class_name HunterClipAudit
extends RefCounted

## Samples every clip of a blocky hunter model (assets/hunters_blocky/<id>/<id>.glb) at many timesteps and reports:
##   sway_in_body  a swaying/attached part (hair chain, braid, tail, ear, wing, horn, halo...) cutting deeper into the body
##                 than it does at rest, beyond TOLERANCE
##   detached      a part's pivot drifting from its parent's pivot (bone length changes) beyond DETACH_TOLERANCE
##   feet          standing/walking clips: the lowest sole floats or sinks beyond FOOT_TOLERANCE
## Body = the core rig meshes; everything else with a mesh is an accessory. Depth comes from a 3D oriented-box SAT between the
## accessory part and each body part, minimum translation distance, so a braid grazing the arm reports ~0 and one passing
## through the torso reports its penetration in metres.

const CORE := ["Pelvis", "Belly", "Chest", "Head", "L-Arm", "L-Forearm", "L-Hand", "R-Arm", "R-Forearm", "R-Hand",
	"L-Thigh", "L-Calf", "L-Foot", "R-Thigh", "R-Calf", "R-Foot"]
const SAMPLES := 16
## 5.5 cm of extra penetration over the rest pose (a 1.8 m hunter): hair brushing a leaning torso, not passing through it.
const TOLERANCE := 0.055
## Legs and arms sweeping through a hanging braid or fish tail (sprint, crouch): looser, 17 cm. The worst left today is the
## mermaid tails (Opalie, Loxelle) against the sprinting legs, ~16 cm; clearing it needs the tail root moved, not just rotated.
const LIMB_TOLERANCE := 0.17
const TORSO := ["Pelvis", "Belly", "Chest", "Head"]
const DETACH_TOLERANCE := 0.02
const FOOT_TOLERANCE := 0.07
## Clips the player sees most, held to TOLERANCE. Every other clip (emotes, climb, stun, jumpscare, flight) poses the whole body
## far from rest: a head rolled onto the shoulder or arms thrown overhead moves the body into hair/cue/wing pivots that rotation cannot
## clear, so those only fail beyond EXTREME_TOLERANCE (a part passing clean through the body).
const STRICT := ["idle", "walk", "chase", "sprint", "crouch", "charge"]
const EXTREME_TOLERANCE := 0.30
## Soles are the foot box's lowest corner: a toe or heel dips past the pivot-based sole at stride.
const FOOT_SINK_TOLERANCE := 0.13
## Clips where a foot should stay on the floor.
const GROUND := ["idle", "walk", "chase", "sprint", "charge"]
## Held-prop empties and the expression quad are not body or accessories.
const IGNORE := ["Face"]
## Void "Cue-*" parts are floating silhouette clouds (motes, spores, phase) that surround the body on purpose.
const CLOUD_PREFIX := "Cue-"


## Findings: [{hunter, clip, kind, part, other, depth, t}] worst per (clip, kind, part, other).
static func audit(model: Node3D, hunter_id: String) -> Array:
	var out: Array = []
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		return out
	var meshes: Dictionary = {}
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if not IGNORE.has(node.name):
			meshes[String(node.name)] = node
	var body: Array = []
	var parts: Array = []
	for key in meshes:
		(body if CORE.has(key) else parts).append(key)
	player.stop()
	# rest overlaps: the baseline an accessory is allowed (a horn sits in the head by design)
	var rest := _depths(meshes, parts, body)
	var rest_gap := _gaps(meshes, parts)
	var foot_rest := 0.0   # soles are measured against the floor (y = 0): the model stands on it at rest
	for clip in player.get_animation_list():
		var name := String(clip)
		if name == "RESET":
			continue
		var length := player.get_animation(name).length
		var worst: Dictionary = {}
		var low := 1e9
		var high := -1e9
		for s in SAMPLES:
			player.play(name)
			player.seek(length * float(s) / SAMPLES, true)
			var depths := _depths(meshes, parts, body)
			for pair in depths:
				var extra: float = float(depths[pair]) - float(rest.get(pair, 0.0))
				if String(pair).begins_with(CLOUD_PREFIX):
					continue
				var torso := TORSO.has(String(pair).split(">")[1])
				var allowed := TOLERANCE if torso else LIMB_TOLERANCE
				if not STRICT.has(name.replace("-loop", "")):
					allowed = maxf(allowed, EXTREME_TOLERANCE)
				if extra > allowed and extra > float(worst.get("sway:" + pair, {}).get("depth", 0.0)):
					worst["sway:" + pair] = {"kind": "sway_in_body" if torso else "sway_in_limb", "pair": pair, "depth": extra, "t": float(s) / SAMPLES}
			var gaps := _gaps(meshes, parts)
			for key in gaps:
				var drift: float = absf(float(gaps[key]) - float(rest_gap.get(key, 0.0)))
				if drift > DETACH_TOLERANCE and drift > float(worst.get("det:" + key, {}).get("depth", 0.0)):
					worst["det:" + key] = {"kind": "detached", "pair": key, "depth": drift, "t": float(s) / SAMPLES}
			var soles := _soles(meshes)
			low = minf(low, soles)
			high = maxf(high, soles)
		var base := name.replace("-loop", "")
		if GROUND.has(base):
			if high > FOOT_TOLERANCE + 0.0 and high - foot_rest > FOOT_TOLERANCE:
				worst["feet_float"] = {"kind": "feet_float", "pair": "feet", "depth": high - foot_rest, "t": 0.0}
		if low - foot_rest < -FOOT_SINK_TOLERANCE and not base.begins_with("emote"):
			worst["feet_sink"] = {"kind": "feet_sink", "pair": "feet", "depth": foot_rest - low, "t": 0.0}
		for key in worst:
			var finding: Dictionary = worst[key]
			finding["hunter"] = hunter_id
			finding["clip"] = base
			out.append(finding)
	player.stop()
	return out


static func _boxes(meshes: Dictionary, keys: Array) -> Dictionary:
	var boxes := {}
	for key in keys:
		var node := meshes[key] as MeshInstance3D
		if node.mesh == null:
			continue
		boxes[key] = [node.global_transform, node.mesh.get_aabb()]
	return boxes


static func _depths(meshes: Dictionary, parts: Array, body: Array) -> Dictionary:
	var out := {}
	var part_boxes := _boxes(meshes, parts)
	var body_boxes := _boxes(meshes, body)
	for p in part_boxes:
		for b in body_boxes:
			var depth := _obb_depth(part_boxes[p][0], part_boxes[p][1], body_boxes[b][0], body_boxes[b][1])
			if depth > 0.0:
				out["%s>%s" % [p, b]] = depth
	return out


## Distance between a part's pivot and its parent mesh's pivot: constant on a rigid rig; drift = a detaching part.
static func _gaps(meshes: Dictionary, parts: Array) -> Dictionary:
	var out := {}
	for p in parts:
		var node := meshes[p] as Node3D
		var parent := node.get_parent() as Node3D
		if parent != null:
			out[p] = node.global_position.distance_to(parent.global_position)
	return out


static func _soles(meshes: Dictionary) -> float:
	var low := 1e9
	for foot in ["L-Foot", "R-Foot"]:
		var node := meshes.get(foot) as MeshInstance3D
		if node == null or node.mesh == null:
			continue
		var box: AABB = node.mesh.get_aabb()
		for i in 8:
			low = minf(low, (node.global_transform * box.get_endpoint(i)).y)
	return low


## Penetration depth of two oriented boxes (a = local AABB under a transform), 0 when apart. Minimum over the 15 SAT axes.
static func _obb_depth(ta: Transform3D, a: AABB, tb: Transform3D, b: AABB) -> float:
	var ca := ta * (a.position + a.size * 0.5)
	var cb := tb * (b.position + b.size * 0.5)
	var ha := a.size * 0.5 * ta.basis.get_scale().abs()
	var hb := b.size * 0.5 * tb.basis.get_scale().abs()
	var axes_a := [ta.basis.x.normalized(), ta.basis.y.normalized(), ta.basis.z.normalized()]
	var axes_b := [tb.basis.x.normalized(), tb.basis.y.normalized(), tb.basis.z.normalized()]
	var axes: Array = []
	axes.append_array(axes_a)
	axes.append_array(axes_b)
	for u in axes_a:
		for v in axes_b:
			var c: Vector3 = u.cross(v)
			if c.length() > 1e-4:
				axes.append(c.normalized())
	var d := cb - ca
	var best := 1e9
	for axis in axes:
		var ra: float = _radius(axes_a, ha, axis)
		var rb: float = _radius(axes_b, hb, axis)
		var overlap: float = ra + rb - absf(d.dot(axis))
		if overlap <= 0.0:
			return 0.0
		best = minf(best, overlap)
	return best


static func _radius(axes: Array, half: Vector3, axis: Vector3) -> float:
	return half.x * absf(axes[0].dot(axis)) * 1.0 + half.y * absf(axes[1].dot(axis)) + half.z * absf(axes[2].dot(axis))
