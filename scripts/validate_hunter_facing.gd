extends RefCounted

## Hunter facing: the body turns toward the way she actually travels (not the brain's stored facing), the head leads
## corners along the A* route, chase locks on the runner, nothing snaps, stun/emote fade the look layer out.
## Drives a real HunterView3D along a known polyline with real frame deltas.
##
##   godot --headless --path . res://scenes/validate.tscn -- hunter_facing

const SPEED := 4.0
const ROUTE := [Vector2(5.5, 5.5), Vector2(5.5, 13.5), Vector2(13.5, 13.5), Vector2(13.5, 21.5)]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _angle_between(yaw: float, direction: Vector2) -> float:
	return absf(wrapf(atan2(-direction.x, -direction.y) - yaw, -PI, PI))


func _route_cells() -> Array:
	var cells: Array = []
	for i in ROUTE.size() - 1:
		var from: Vector2 = ROUTE[i]
		var to: Vector2 = ROUTE[i + 1]
		var steps := int(from.distance_to(to))
		for s in range(1, steps + 1):
			var point := from.lerp(to, float(s) / steps)
			cells.append(Vector2i(floori(point.x), floori(point.y)))
	return cells


func _view(host: Node, hunter_id: String) -> HunterView3D:
	var brain := HunterBrain.new(ROUTE[0], "FACING-TEST", hunter_id, "standard")
	brain.activate_at(ROUTE[0])
	brain.state = HunterBrain.State.WANDER
	var view := HunterView3D.new()
	view.brain = brain
	host.add_child(view)
	view._facing.scan_scale = 0.0
	return view


func run(host: Node) -> int:
	var tree := host.get_tree()
	await tree.process_frame

	# ---- walk the polyline with a deliberately WRONG brain.facing: the body must follow the movement
	var view := _view(host, "dovelle")
	await tree.process_frame
	var brain := view.brain
	var cells := _route_cells()
	brain.position = ROUTE[0]
	view.sync_from_brain()
	var leg := 0
	var worst_step := 0.0
	var worst_error := 0.0
	var best_lead := 0.0        # head yaw toward the first corner, in the direction of the turn
	var body_at_lead := 0.0
	var max_head := 0.0
	var max_pitch := 0.0
	var settle := 0.0
	var last_yaw := view.rotation.y
	var time_left := 40.0
	while leg < ROUTE.size() - 1 and time_left > 0.0:
		await tree.process_frame
		var delta := maxf(host.get_process_delta_time(), 1.0 / 240.0)
		time_left -= delta
		var to: Vector2 = ROUTE[leg + 1]
		var tangent: Vector2 = (to - ROUTE[leg]).normalized()
		var step := minf(SPEED * delta, brain.position.distance_to(to))
		brain.position += (to - brain.position).normalized() * step
		while not cells.is_empty() and brain.position.distance_to(Vector2(cells[0]) + Vector2(.5, .5)) < .6:
			cells.pop_front()
		brain._path = cells.duplicate()
		brain.facing = -tangent
		view.sync_from_brain()
		var turn := absf(wrapf(view.rotation.y - last_yaw, -PI, PI))
		worst_step = maxf(worst_step, turn / delta)
		last_yaw = view.rotation.y
		var head := view._facing.head_yaw * view._facing.weight
		max_head = maxf(max_head, absf(head))
		max_pitch = maxf(max_pitch, absf(view._facing.head_pitch * view._facing.weight))
		var remaining := brain.position.distance_to(to)
		settle += delta
		if remaining < 3.0 and leg == 0:
			# first corner turns right -> the head should swing toward it before the body does
			var next_dir: Vector2 = (ROUTE[2] - ROUTE[1]).normalized()
			var side := signf(tangent.x * next_dir.y - tangent.y * next_dir.x)
			var lead := head * -side
			if lead > best_lead:
				best_lead = lead
				body_at_lead = _angle_between(view.rotation.y, tangent)
		if remaining < .05:
			leg += 1
			settle = 0.0
		elif remaining > 3.0 and settle > 1.2:
			worst_error = maxf(worst_error, _angle_between(view.rotation.y, tangent))
	_expect(leg == ROUTE.size() - 1, "the test hunter never finished the route")
	_expect(worst_error < deg_to_rad(15.0), "body yaw drifted %.1f deg from the path tangent after settling (limit 15)" % rad_to_deg(worst_error))
	_expect(best_lead > deg_to_rad(12.0), "the head did not lead the first corner (best lead %.1f deg)" % rad_to_deg(best_lead))
	_expect(body_at_lead < deg_to_rad(20.0), "the body had already turned %.1f deg when the head led" % rad_to_deg(body_at_lead))
	_expect(max_head <= HunterFacing.YAW_LIMIT + .001, "head yaw %.1f deg exceeds the clamp" % rad_to_deg(max_head))
	_expect(max_pitch <= HunterFacing.PITCH_LIMIT + .001, "head pitch exceeds the clamp")
	_expect(worst_step <= HunterFacing.RUN_TURN * 1.02 + .02, "body turned %.0f deg/s in one frame (snap)" % rad_to_deg(worst_step))

	# ---- standing still keeps the last heading (no moonwalk / no drift)
	brain.facing = (ROUTE[ROUTE.size() - 1] - ROUTE[ROUTE.size() - 2]).normalized()
	var yaw_before := view.rotation.y
	for i in 40:
		await tree.process_frame
		view.sync_from_brain()
	_expect(absf(wrapf(view.rotation.y - yaw_before, -PI, PI)) < deg_to_rad(3.0), "a standing hunter drifted her heading")

	# ---- chase locks on the runner; the clamp holds for a target behind her
	brain.state = HunterBrain.State.CHASE
	var forward := Vector2(0, 1)
	var side_target := brain.position + Vector2(5, 5)     # 45 deg off the heading
	view.set_look_target(side_target)
	for i in 120:
		await tree.process_frame
		view.sync_from_brain()
	# a standing chaser turns her body toward the runner as well, so the head ends near 0 -- check the target is in front
	var body_to_target := _angle_between(view.rotation.y, side_target - brain.position)
	_expect(body_to_target < deg_to_rad(20.0), "a standing chaser should face the runner (off by %.1f deg)" % rad_to_deg(body_to_target))
	# freeze the body (stunned heading) and check the pure lock angle against a target behind: clamp
	for i in 60:
		view._facing.update_head(.05, HunterFacing.Mode.LOCK, view.rotation.y, brain.position, brain.position - forward * 5.0, 0.0)
	_expect(absf(view._facing.head_yaw) <= HunterFacing.YAW_LIMIT + .001, "locked head exceeded the yaw clamp")
	_expect(absf(view._facing.head_yaw) > HunterFacing.YAW_LIMIT - deg_to_rad(8.0), "locked head should sit at the clamp for a target behind her")

	# ---- stun and emotes fade the look layer out
	brain.state = HunterBrain.State.WANDER
	view.set_look_target(null)
	view._facing.scan_scale = 1.0
	for i in 60:
		await tree.process_frame
	_expect(view._facing.weight > .9, "an idle hunter should keep the look layer on (weight %.2f)" % view._facing.weight)
	brain.apply_stun(5.0)
	for i in 120:
		await tree.process_frame
		view.sync_from_brain()
	_expect(view._facing.weight < .05, "a stunned hunter must not look around (weight %.2f)" % view._facing.weight)
	view.queue_free()

	# ---- guests: no route at all, heading and head target come from the replicated motion
	var guest := _view(host, "kathy")
	await tree.process_frame
	var gbrain := guest.brain
	gbrain.position = Vector2(5.5, 5.5)
	guest.sync_from_brain()
	var heading := Vector2(1, 0)
	for i in 90:
		await tree.process_frame
		gbrain.position += heading * SPEED * host.get_process_delta_time()
		gbrain.facing = Vector2(0, 1)
		guest.sync_from_brain()
	_expect(_angle_between(guest.rotation.y, heading) < deg_to_rad(15.0), "a guest hunter should face her replicated motion (off by %.1f deg)" % rad_to_deg(_angle_between(guest.rotation.y, heading)))
	guest.queue_free()

	# ---- cost: only the camera range gate allocates nothing; make sure the helper's pure maths is stable
	var facing := HunterFacing.new()
	var yaw := 0.0
	for i in 600:
		yaw = facing.steer(yaw, Vector2(0, 1), true, 1.0 / 60.0)
	_expect(absf(wrapf(yaw - PI, -PI, PI)) < .02, "steer() should settle on the target heading")

	if _failures == 0:
		print("  ok    hunter_facing: body follows travel, head leads corners and locks on the runner, clamps and fades hold")
	return _failures
