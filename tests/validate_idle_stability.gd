extends RefCounted

## A hunter standing still must stand still: root position and yaw do not drift, no animation / gait / expression state flips, and
## every body part only moves as much as the idle clip itself moves (plus a small allowance for the quiet head look). Also checks a
## guest-side hunter whose replicated position arrives in network-sized steps and a hunter at a waypoint in each AI state.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- idle_stability

const FULL_SECONDS := 5.0
const QUICK_SECONDS := 2.0
const PARTS := ["Pelvis", "Chest", "Head", "L-Hand", "R-Hand", "L-Foot", "R-Foot"]
## Allowance on top of the idle clip's own range: metres for positions, radians for the head look.
const POSITION_SLACK := .03
const HEAD_LOOK_SLACK := deg_to_rad(9.0)

var _failures := 0
var verbose := false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _view(host: Node, id: String, state: int) -> HunterView3D:
	var brain := HunterBrain.new(Vector2(8.5, 8.5), "IDLE-%s" % id, id, "standard")
	brain.activate_at(Vector2(8.5, 8.5))
	brain.state = state
	brain.facing = Vector2(0, 1)
	var view := HunterView3D.new()
	view.brain = brain
	host.add_child(view)
	return view


## Range of each part's position (relative to the model root) over one idle loop, from the clip data alone.
func _clip_ranges(id: String) -> Dictionary:
	var model := (load("res://assets/hunters_blocky/%s/%s.glb" % [id, id]) as PackedScene).instantiate() as Node3D
	var player := ModelSlot.find_animation_player(model)
	var rest := {}
	HunterStride._collect_rest(model, model, rest)
	var animation := player.get_animation("idle")
	var low := {}
	var high := {}
	for i in 33:
		var pose := HunterStride.fk(model, rest, animation, animation.length * i / 32)
		for part in PARTS:
			var origin: Vector3 = (pose[part] as Transform3D).origin
			low[part] = origin if not low.has(part) else Vector3(minf(low[part].x, origin.x), minf(low[part].y, origin.y), minf(low[part].z, origin.z))
			high[part] = origin if not high.has(part) else Vector3(maxf(high[part].x, origin.x), maxf(high[part].y, origin.y), maxf(high[part].z, origin.z))
	var out := {}
	for part in PARTS:
		out[part] = (high[part] - low[part]) as Vector3
	# the idle clip's own head yaw swing (what the head does with the look layer off)
	var low_yaw := INF
	var high_yaw := -INF
	for i in 33:
		var pose := HunterStride.fk(model, rest, animation, animation.length * i / 32)
		var forward: Vector3 = (pose["Head"] as Transform3D).basis * Vector3(0, 0, -1)
		var yaw := atan2(-forward.x, -forward.z)
		low_yaw = minf(low_yaw, yaw)
		high_yaw = maxf(high_yaw, yaw)
	out["head_swing"] = high_yaw - low_yaw
	model.free()
	return out


## Stands the view still for `seconds` and measures. `feed` (a Callable(view, frame)) moves the brain between frames for the guest case.
func _stand(host: Node, view: HunterView3D, seconds: float, feed: Callable = Callable()) -> Dictionary:
	var tree := host.get_tree()
	await tree.process_frame
	await tree.process_frame
	view.sync_from_brain()
	for i in 20:
		await tree.process_frame        # let the model, physics and face settle
		view.sync_from_brain()
	var origin := view.global_position
	var yaw0 := view.rotation.y
	var low := {}
	var high := {}
	var anims := {}
	var gait := {}
	var faces := {}
	var max_drift := 0.0
	var max_yaw := 0.0
	var head_min := INF
	var head_max := -INF
	var frames := 0
	var elapsed := 0.0
	var last_anim := ""
	var anim_changes := 0
	var gait_changes := 0
	var last_gait := view._gait_moving
	var face_changes := 0
	var last_face := view._expression
	var speed_scale_max := 0.0
	var inverse := view.global_transform.affine_inverse()
	while elapsed < seconds:
		await tree.process_frame
		elapsed += host.get_process_delta_time()
		frames += 1
		if feed.is_valid():
			feed.call(view, frames)
		view.sync_from_brain()
		max_drift = maxf(max_drift, (view.global_position - origin).length())
		max_yaw = maxf(max_yaw, absf(wrapf(view.rotation.y - yaw0, -PI, PI)))
		var to_view := view.global_transform.affine_inverse()
		for part in PARTS:
			var node := view._model.find_child(part, true, false) as Node3D
			var local: Vector3 = to_view * node.global_position
			low[part] = local if not low.has(part) else Vector3(minf(low[part].x, local.x), minf(low[part].y, local.y), minf(low[part].z, local.z))
			high[part] = local if not high.has(part) else Vector3(maxf(high[part].x, local.x), maxf(high[part].y, local.y), maxf(high[part].z, local.z))
		var head_forward := ((view._model.find_child("Head", true, false) as Node3D).global_basis * Vector3(0, 0, -1))
		var head_angle: float = wrapf(atan2(-head_forward.x, -head_forward.z) - view.rotation.y, -PI, PI)
		head_min = minf(head_min, head_angle)
		head_max = maxf(head_max, head_angle)
		var animation := String(view._animation_player.assigned_animation)
		if OS.get_environment("IDLE_TRACE") != "":
			print("TRACE %s %.3f %.3f %.4f %s" % [view.brain.hunter_id, elapsed, rad_to_deg(head_angle), view.global_position.y, animation])
		anims[animation] = true
		if animation != last_anim and last_anim != "":
			anim_changes += 1
		last_anim = animation
		if view._gait_moving != last_gait:
			gait_changes += 1
		last_gait = view._gait_moving
		speed_scale_max = maxf(speed_scale_max, view._animation_player.speed_scale)
		var face := view._expression
		if face != last_face and face != "blink" and last_face != "blink":
			face_changes += 1
		last_face = face
	var ranges := {}
	for part in PARTS:
		ranges[part] = (high[part] - low[part]) as Vector3
	return {"drift": max_drift, "yaw": max_yaw, "ranges": ranges, "anims": anims.keys(), "anim_changes": anim_changes,
		"gait_changes": gait_changes, "face_changes": face_changes, "head_swing": head_max - head_min, "frames": frames}


func _check(label: String, result: Dictionary, clip: Dictionary, allow_head_look: float) -> void:
	_expect(float(result["drift"]) < .02, "%s: the root drifted %.3f m while standing" % [label, result["drift"]])
	_expect(float(result["yaw"]) < deg_to_rad(2.0), "%s: the body yawed %.1f deg while standing" % [label, rad_to_deg(result["yaw"])])
	_expect(int(result["anim_changes"]) == 0 and int(result["gait_changes"]) == 0 and int(result["face_changes"]) == 0,
		"%s: state flips (animation %d, gait %d, face %d, clips %s)" % [label, result["anim_changes"], result["gait_changes"], result["face_changes"], result["anims"]])
	_expect(result["anims"].size() == 1 and (result["anims"][0] == "idle" or String(result["anims"][0]).begins_with("scythe_idle")), "%s: playing %s instead of the idle clip" % [label, result["anims"]])
	for part in PARTS:
		# the view draws the model at HunterRoster scale; the clip ranges are in authored model units
		var seen: Vector3 = (result["ranges"][part] as Vector3) / HunterRoster.MODEL_SCALE
		var allowed: Vector3 = (clip[part] as Vector3) + Vector3.ONE * POSITION_SLACK
		if part == "Head" or part.ends_with("Hand"):
			allowed += Vector3.ONE * allow_head_look * .6      # the head (and what hangs off the chest) may follow the quiet look
		_expect(seen.x <= allowed.x and seen.y <= allowed.y and seen.z <= allowed.z,
			"%s: %s moved %s while standing, the idle clip only %s" % [label, part, seen.snapped(Vector3.ONE * .001), (clip[part] as Vector3).snapped(Vector3.ONE * .001)])
	_expect(float(result["head_swing"]) <= float(clip["head_swing"]) + allow_head_look * 2.0 + .03, "%s: the head swung %.1f deg while standing (allowed +-%.1f)" % [label, rad_to_deg(result["head_swing"]), rad_to_deg(allow_head_look)])


func run(host: Node) -> int:
	var tree := host.get_tree()
	await tree.process_frame
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(60, .2, 60)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(8.5, -.1, 8.5)
	host.add_child(floor_body)

	# detailed run: a few hunters x every standing AI state
	var deep := ["dovelle", "glyra", "xivvy", "kathy"]
	var states := {"idle": HunterBrain.State.IDLE, "wander": HunterBrain.State.WANDER, "chase": HunterBrain.State.CHASE, "search": HunterBrain.State.SEARCH}
	for id in deep:
		var clip := _clip_ranges(id)
		for state_name in states:
			var view := _view(host, id, states[state_name])
			if state_name == "chase":
				view.set_look_target(Vector2(8.5, 14.0))      # a runner she cannot reach: she stands and stares
			var result: Dictionary = await _stand(host, view, FULL_SECONDS)
			if verbose or OS.get_environment("IDLE_VERBOSE") != "":
				print("  %-8s %-7s drift %.4f yaw %.2f head swing %.1f deg  %s" % [id, state_name, result["drift"], rad_to_deg(result["yaw"]), rad_to_deg(result["head_swing"]), result["anims"]])
				for part in PARTS:
					print("      %-7s seen %s clip %s" % [part, (result["ranges"][part] as Vector3).snapped(Vector3.ONE * .001), (clip[part] as Vector3).snapped(Vector3.ONE * .001)])
			_check("%s/%s" % [id, state_name], result, clip, QuietLook.ALLOWANCE)
			view.queue_free()
			await tree.process_frame

	# every hunter, standing at a waypoint
	var ids: Array = []
	ids.append_array(HunterRoster.A_Z_IDS)
	ids.append_array(HunterRoster.VOID_IDS)
	for id in ids:
		if not ResourceLoader.exists("res://assets/hunters_blocky/%s/%s.glb" % [id, id]) or deep.has(id):
			continue
		var clip := _clip_ranges(id)
		var view := _view(host, id, HunterBrain.State.WANDER)
		var result: Dictionary = await _stand(host, view, QUICK_SECONDS)
		_check("%s/wander" % id, result, clip, QuietLook.ALLOWANCE)
		view.queue_free()
		await tree.process_frame

	# a guest: the host's position arrives 20 times a second, in steps of identical position (no real movement)
	var guest := _view(host, "dovelle", HunterBrain.State.WANDER)
	var feed := func(v: HunterView3D, frame: int) -> void:
		if frame % 3 == 0:
			v.brain.position = Vector2(8.5, 8.5) + Vector2(sin(frame * .05), cos(frame * .05)) * .002   # network rounding noise
	var guest_result: Dictionary = await _stand(host, guest, FULL_SECONDS, feed)
	_check("guest dovelle", guest_result, _clip_ranges("dovelle"), QuietLook.ALLOWANCE)
	guest.queue_free()
	floor_body.queue_free()
	if _failures == 0:
		print("  ok    idle_stability: standing hunters stand still in every state, on every model, and as guests")
	return _failures


## The quiet look a standing hunter is allowed (plus-minus, radians).
class QuietLook:
	const ALLOWANCE := deg_to_rad(9.0)
