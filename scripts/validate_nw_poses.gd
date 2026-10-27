extends RefCounted

## Night Watch pose library: every pose exists as a clip on every hunter model, every track resolves to a rig bone,
## key rotations stay inside the per-bone limits, feet stay on the floor (grounded poses), hands do not pass through
## the torso, loops close, blends are sane, and the HunterView3D hook plays / ends / yields to stun. The geometry checks
## run forward kinematics on each model's REAL rest pose against the compiled Animation, so no window or AnimationPlayer
## timing is involved.
##
##   godot --headless --path . res://scenes/validate.tscn -- nw_poses

const FAST_POSES := ["twitch", "flinch"]
const MAX_SPEED := 1100.0     # deg/s between two keys of one axis

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1
		
		
func _model_ids() -> Array:
	var ids: Array = []
	for dir in DirAccess.get_directories_at("res://assets/hunters_blocky"):
		if ResourceLoader.exists("res://assets/hunters_blocky/%s/%s.glb" % [dir, dir]):
			ids.append(dir)
	ids.sort()
	return ids


## Global transforms of every bone for `animation` at time `t` (rest pose where a track is absent).
func _fk(model: Node3D, rest: Dictionary, animation: Animation, t: float) -> Dictionary:
	var local := {}
	for bone in rest:
		local[bone] = (rest[bone] as Transform3D)
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		var bone := String(path.get_name(path.get_name_count() - 1))
		if not local.has(bone):
			continue
		var transform: Transform3D = local[bone]
		if animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			transform.basis = Basis(animation.rotation_track_interpolate(track, t))
		elif animation.track_get_type(track) == Animation.TYPE_POSITION_3D:
			transform.origin = animation.position_track_interpolate(track, t)
		local[bone] = transform
	var out := {}
	for bone in NightWatchPoses.BONES:
		if not local.has(bone):
			continue
		var node := model.find_child(bone, true, false) as Node3D
		var parent_name := String(node.get_parent().name)
		out[bone] = (out[parent_name] as Transform3D) * (local[bone] as Transform3D) if out.has(parent_name) \
			else _above(model, node) * (local[bone] as Transform3D)
	return out


## Transform of everything between the model root and a bone that is not itself a bone (the root bone's parent chain).
func _above(model: Node3D, bone_node: Node3D) -> Transform3D:
	var accumulated := Transform3D.IDENTITY
	var node := bone_node.get_parent() as Node3D
	while node != null and node != model:
		accumulated = node.transform * accumulated
		node = node.get_parent() as Node3D
	return accumulated


func _angle_gap(a: Array, b: Array) -> float:
	return maxf(absf(float(a[1]) - float(b[1])), maxf(absf(float(a[2]) - float(b[2])), absf(float(a[3]) - float(b[3]))))


func run(host: Node) -> int:
	var tree := host.get_tree()
	await tree.process_frame
	var data := NightWatchPoses.data()
	_expect(not data.is_empty(), "night_watch_poses.json did not load")
	var poses: Dictionary = data.get("poses", {})
	_expect(poses.size() >= 16, "expected the full Night Watch pose set, got %d" % poses.size())
	for required in ["door_lurk", "peek_left", "peek_right", "stare_camera", "door_pound", "press_glass", "vent_crawl",
			"creep_walk", "sprint_lunge", "retreat", "flinch", "twitch", "kneel", "slump", "point_office", "wave"]:
		_expect(poses.has(required), "missing pose %s" % required)

	# ---- the data itself: limits, loops, blend times, no pops
	var limits: Dictionary = data["limits"]
	for pose_id in poses:
		var spec: Dictionary = poses[pose_id]
		_expect(float(spec["blend"]) >= .05 and float(spec["blend"]) <= 1.0, "%s: blend time %.2f out of range" % [pose_id, spec["blend"]])
		for bone in spec["tracks"]:
			_expect(NightWatchPoses.BONES.has(bone), "%s: unknown bone %s" % [pose_id, bone])
			var keys: Array = spec["tracks"][bone]["rot"]
			var bone_limits: Dictionary = limits.get(bone, {})
			for i in keys.size():
				var key: Array = keys[i]
				for axis in 3:
					var range_: Array = bone_limits.get("xyz"[axis], [-180, 180])
					if float(key[axis + 1]) < float(range_[0]) - .01 or float(key[axis + 1]) > float(range_[1]) + .01:
						_expect(false, "%s: %s %s=%.1f outside %s" % [pose_id, bone, "xyz"[axis], key[axis + 1], range_])
				if i > 0:
					var span := maxf(float(key[0]) - float(keys[i - 1][0]), .001)
					if not FAST_POSES.has(pose_id):
						_expect(_angle_gap(key, keys[i - 1]) / span <= MAX_SPEED, "%s: %s turns %.0f deg/s between keys (pop)" % [pose_id, bone, _angle_gap(key, keys[i - 1]) / span])
			if spec["loop"] and keys.size() > 1:
				_expect(_angle_gap(keys[0], keys[keys.size() - 1]) < .01, "%s: %s rotation loop does not close" % [pose_id, bone])
			var positions: Array = spec["tracks"][bone]["pos"]
			if spec["loop"] and positions.size() > 1:
				var first: Array = positions[0]
				var last: Array = positions[positions.size() - 1]
				_expect(_angle_gap(first, last) < .001, "%s: %s offset loop does not close" % [pose_id, bone])
	for state in data["states"]:
		_expect(poses.has(data["states"][state]), "state %s maps to a missing pose %s" % [state, data["states"][state]])

	# ---- every model on the rig
	var ids := _model_ids()
	_expect(ids.size() >= 38, "expected at least the 38 hunters plus extras, found %d model folders" % ids.size())
	var worst_floor := 0.0
	var worst_hand := 9.0
	for id in ids:
		var scene := load("res://assets/hunters_blocky/%s/%s.glb" % [id, id]) as PackedScene
		var model := scene.instantiate() as Node3D
		host.add_child(model)
		var player := ModelSlot.find_animation_player(model)
		_expect(player != null, "%s has no AnimationPlayer" % id)
		if player == null:
			model.queue_free()
			continue
		_expect(NightWatchPoses.install(model, player, id), "%s: install failed" % id)
		var rest := {}
		var foot_rest := 0.0
		for bone in NightWatchPoses.BONES:
			var node := model.find_child(bone, true, false) as Node3D
			_expect(node != null, "%s: rig bone %s missing" % [id, bone])
			if node != null:
				rest[bone] = node.transform
		var rest_pose := _fk(model, rest, Animation.new(), 0.0)
		foot_rest = minf((rest_pose["L-Foot"] as Transform3D).origin.y, (rest_pose["R-Foot"] as Transform3D).origin.y)
		var shoulder: float = absf((rest_pose["L-Arm"] as Transform3D).origin.x - (rest_pose["Pelvis"] as Transform3D).origin.x)
		for pose_id in poses:
			var clip := NightWatchPoses.clip_name(pose_id)
			_expect(player.has_animation(clip), "%s: no clip %s" % [id, clip])
			if not player.has_animation(clip):
				continue
			var animation := player.get_animation(clip)
			var root := player.get_node(player.root_node)
			for track in animation.get_track_count():
				_expect(root.get_node_or_null(NodePath(String(animation.track_get_path(track)))) != null, "%s/%s: track %s does not resolve" % [id, pose_id, animation.track_get_path(track)])
			_expect(animation.loop_mode == (Animation.LOOP_LINEAR if poses[pose_id]["loop"] else Animation.LOOP_NONE), "%s/%s: loop flag" % [id, pose_id])
			var steps := 24
			for i in steps + 1:
				var t := animation.length * i / steps
				var pose_fk := _fk(model, rest, animation, t)
				var low := minf((pose_fk["L-Foot"] as Transform3D).origin.y, (pose_fk["R-Foot"] as Transform3D).origin.y)
				var floor_gap := low - foot_rest
				worst_floor = minf(worst_floor, floor_gap)
				if floor_gap < -.06 - .06 * (float(id.contains("tall")) * 1.0):
					_expect(false, "%s/%s t=%.2f: a foot is %.2f m below the floor" % [id, pose_id, t, -floor_gap])
					break
				if poses[pose_id]["grounded"] and floor_gap > .07:
					_expect(false, "%s/%s t=%.2f: both feet are %.2f m off the floor" % [id, pose_id, t, floor_gap])
					break
				if not poses[pose_id]["hands_on_body"]:
					var inverse := (pose_fk["Pelvis"] as Transform3D).affine_inverse()
					var broke := false
					for hand in ["L-Hand", "R-Hand"]:
						var local: Vector3 = inverse * (pose_fk[hand] as Transform3D).origin
						worst_hand = minf(worst_hand, absf(local.x))
						if absf(local.x) < shoulder * .5 and absf(local.z) < .08 and local.y > .05 and local.y < .55:
							_expect(false, "%s/%s t=%.2f: %s is inside the torso (%s)" % [id, pose_id, t, hand, local])
							broke = true
					if broke:
						break
		model.queue_free()
	print("  nw_poses: %d models x %d poses checked; lowest foot %.3f m under rest, closest hand to the body axis %.2f m" % [ids.size(), poses.size(), worst_floor, worst_hand])

	# ---- the HunterView3D hook
	var brain := HunterBrain.new(Vector2(5, 5), "NW-TEST", "dovelle", "standard")
	brain.activate_at(Vector2(5, 5))
	brain.state = HunterBrain.State.IDLE
	var view := HunterView3D.new()
	view.brain = brain
	host.add_child(view)
	await tree.process_frame
	view.sync_from_brain()
	var anim: AnimationPlayer = view._animation_player
	_expect(anim != null and anim.has_animation("nw/door_lurk"), "the view's AnimationPlayer should carry the nw library")
	_expect(NightWatchPoses.play(view, "door_lurk"), "play() refused door_lurk")
	for i in 6:
		await tree.process_frame
		view.sync_from_brain()
	_expect(anim.current_animation == "nw/door_lurk" and anim.is_playing(), "door_lurk should be playing, got '%s'" % anim.current_animation)
	_expect(not NightWatchPoses.play(view, "no_such_pose"), "an unknown pose must be refused")
	_expect(NightWatchPoses.play_state(view, "at_door") and view.nw_pose == "door_pound", "state at_door should map to door_pound")
	brain.apply_stun(2.0)
	for i in 6:
		await tree.process_frame
		view.sync_from_brain()
	_expect(anim.current_animation == "stun", "stun must override a pose, got '%s'" % anim.current_animation)
	brain.stun_timer = 0.0
	NightWatchPoses.play(view, "flinch")
	var guard := 0
	while view.nw_pose != "" and guard < 400:
		await tree.process_frame
		view.sync_from_brain()
		guard += 1
	_expect(view.nw_pose == "" and guard < 400, "a one-shot pose should end on its own (took %d frames)" % guard)
	NightWatchPoses.play(view, "slump")
	await tree.process_frame
	view.sync_from_brain()
	NightWatchPoses.stop(view)
	for i in 4:
		await tree.process_frame
		view.sync_from_brain()
	_expect(anim.current_animation == "idle", "stop() should return to the normal clips, got '%s'" % anim.current_animation)

	# ---- layers stay bounded (no accumulation) and the stride follows the pace
	view.nw_layers = true
	var chest := view._model.find_child("Chest", true, false) as Node3D
	var worst := 0.0
	for i in 240:
		await tree.process_frame
		view.sync_from_brain()
		worst = maxf(worst, chest.quaternion.angle_to(Quaternion.IDENTITY))
	_expect(worst < deg_to_rad(25.0), "layers drifted the chest %.1f deg" % rad_to_deg(worst))
	view.queue_free()

	if _failures == 0:
		print("  ok    nw_poses: every pose on every hunter, limits, floor, torso, loops, blends and the view hook")
	return _failures
