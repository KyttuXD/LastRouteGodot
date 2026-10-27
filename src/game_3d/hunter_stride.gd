class_name HunterStride
extends RefCounted

## Stride reference speeds for travel clips, MEASURED from each model's real clip data (forward kinematics of the
## planted foot) by tools/look/stride_table.tscn and stored in assets/hunters_blocky/stride_table.json. The view plays a
## travel clip at speed_scale = real ground speed / reference speed, so the planted foot stays put on the ground
## instead of sliding (moonwalking) at a fixed 1.0.
##
## reference speed = how fast the planted foot moves backwards relative to the body while the clip plays at 1.0
## (mean over the contact samples, metres of world per second, model scale included).

const TABLE_PATH := "res://assets/hunters_blocky/stride_table.json"
const CREATURE_TABLE_PATH := "res://assets/city/creature_stride_table.json"
const SAMPLES := 96
const CONTACT_TOLERANCE := .03
## Playback range kept sensible: outside it the view switches to the neighbouring clip first.
const MIN_RATIO := .55
const MAX_RATIO := 1.9
const HARD_MIN := .35
const HARD_MAX := 2.6
const TRAVEL_CLIPS := ["walk", "chase", "sprint"]
const FALLBACK := {"walk": 1.4, "chase": 3.0, "sprint": 4.2, "scythe_walk": 1.4}
const HUMANOID_FEET := ["L-Foot", "R-Foot"]

static var _table := {}


static func table() -> Dictionary:
	if _table.is_empty():
		for path in [TABLE_PATH, CREATURE_TABLE_PATH]:
			var file := FileAccess.open(path, FileAccess.READ)
			if file != null:
				var parsed: Variant = JSON.parse_string(file.get_as_text())
				if parsed is Dictionary:
					_table.merge(parsed)
	return _table


static func has_clip(hunter_id: String, clip: String) -> bool:
	return table().get(hunter_id, {}).has(clip)


static func ref_speed(hunter_id: String, clip: String) -> float:
	var entry: Dictionary = table().get(hunter_id, {}).get(clip, {})
	return maxf(float(entry.get("ref", FALLBACK.get(clip, 1.5))), .3)


## The clip to play and its speed_scale for a given real ground speed. `preferred` is the state's clip
## (walk / chase / sprint / scythe_walk ...); `candidates` the clips it may swap to when the pace is out of range.
static func choose(hunter_id: String, preferred: String, speed: float, candidates: Array = TRAVEL_CLIPS) -> Dictionary:
	var clip := preferred
	var ratio := speed / ref_speed(hunter_id, preferred)
	if (ratio < MIN_RATIO or ratio > MAX_RATIO) and candidates.has(preferred):
		var best := INF
		for candidate in candidates:
			if not has_clip(hunter_id, candidate):
				continue
			var gap := absf(log(maxf(speed, .05) / ref_speed(hunter_id, candidate)))
			if gap < best:
				best = gap
				clip = candidate
	var scale := clampf(speed / ref_speed(hunter_id, clip), HARD_MIN, HARD_MAX)
	if table().get(hunter_id, {}).get(clip, {}).get("reverse", false):
		scale = -scale
	return {"clip": clip, "scale": scale}


# ------------------------------------------------------------------------------------------- measuring

## World-space ground speed of the planted foot (backwards) for one clip at speed_scale 1.0, plus the per-sample profile.
## `feet`: node names of the feet; `sole_drop`: true -> contact point is the foot's rest height below its origin (humanoid).
static func measure(model: Node3D, animation: Animation, feet: Array, sole_drop: bool, world_scale: float) -> Dictionary:
	var rest := {}
	_collect_rest(model, model, rest)
	var rest_pose := fk(model, rest, Animation.new(), 0.0)
	var drop := {}
	for foot in feet:
		drop[foot] = (rest_pose[foot] as Transform3D).origin.y if sole_drop else 0.0
	var samples := SAMPLES
	var forward := {}
	var height := {}
	var floor_y := INF
	for foot in feet:
		forward[foot] = []
		height[foot] = []
	for i in samples:
		var pose := fk(model, rest, animation, animation.length * i / samples)
		for foot in feet:
			var sole: Vector3 = (pose[foot] as Transform3D) * Vector3(0, -float(drop[foot]), 0)
			(forward[foot] as Array).append(-sole.z)
			(height[foot] as Array).append(sole.y)
			floor_y = minf(floor_y, sole.y)
	var dt := animation.length / samples
	# Stance = the part of a foot's cycle in which it travels BACKWARDS relative to the body (the planted foot slides
	# back under the body while the body moves on). Reference speed = mean backward speed over those samples.
	var sum := 0.0
	var squares := 0.0
	var count := 0
	var low_sum := 0.0
	var fsum := 0.0
	var fcount := 0
	var low_count := 0
	for foot in feet:
		var lowest := INF
		var highest := -INF
		for i in samples:
			lowest = minf(lowest, float(height[foot][i]))
			highest = maxf(highest, float(height[foot][i]))
		var lift := highest - lowest
		for i in samples:
			var j := (i + 1) % samples
			var backwards := -(float(forward[foot][j]) - float(forward[foot][i])) / dt
			if backwards < 0.0:
				fsum -= backwards
				fcount += 1
			if backwards > 0.0:
				sum += backwards
				squares += backwards * backwards
				count += 1
			# direction check: while the foot is in the lowest quarter of its own lift it must be moving backwards
			if lift > .02 and float(height[foot][i]) < lowest + .25 * lift:
				low_sum += backwards
				low_count += 1
	if count == 0:
		return {"ref": 0.0, "slip_rms": 1.0, "contacts": 0, "cycle": animation.length, "forward_ok": false}
	var mean := sum / count
	# A clip whose planted foot travels FORWARD relative to the body (a moonwalk) plays backwards instead:
	# its reference speed is then the forward travel of the same feet.
	# (only when it is clear: a near-zero low-foot speed, as a crawl's joints have, is noise, not a moonwalk)
	var low_mean := low_sum / low_count if low_count > 0 else 1.0
	var reverse := low_count > 0 and low_mean < -.2 * mean and fcount > 0
	if reverse:
		mean = fsum / fcount
	var variance := maxf(squares / count - mean * mean, 0.0)
	return {"ref": mean * world_scale, "slip_rms": sqrt(variance) / maxf(mean, .001),
		"contacts": count, "cycle": animation.length, "forward_ok": low_count == 0 or low_mean >= -.2 * maxf(mean, .001), "reverse": reverse,
		"stance": (low_sum / low_count * world_scale) if low_count > 0 else mean * world_scale}


static func _collect_rest(root: Node3D, node: Node, out: Dictionary) -> void:
	for child in node.get_children():
		if child is Node3D:
			out[String(child.name)] = (child as Node3D).transform
			_collect_rest(root, child, out)


## Global (model-space) transform of every node with `animation` sampled at `t`; tracks are matched by node name.
static func fk(model: Node3D, rest: Dictionary, animation: Animation, t: float) -> Dictionary:
	var local := rest.duplicate()
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		var bone := String(path.get_name(path.get_name_count() - 1)) if path.get_name_count() > 0 else ""
		if not local.has(bone):
			continue
		var transform: Transform3D = local[bone]
		match animation.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				transform.basis = Basis(animation.rotation_track_interpolate(track, t)).scaled(transform.basis.get_scale())
			Animation.TYPE_POSITION_3D:
				transform.origin = animation.position_track_interpolate(track, t)
		local[bone] = transform
	var out := {}
	_accumulate(model, model, Transform3D.IDENTITY, local, out)
	return out


static func _accumulate(root: Node3D, node: Node, parent: Transform3D, local: Dictionary, out: Dictionary) -> void:
	for child in node.get_children():
		if child is Node3D:
			var global: Transform3D = parent * (local[String(child.name)] as Transform3D)
			out[String(child.name)] = global
			_accumulate(root, child, global, local, out)
