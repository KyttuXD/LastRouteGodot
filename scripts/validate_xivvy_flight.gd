extends RefCounted

## Xivvy's flying chase, clearance-driven: she cruises as high as the ceiling allows in tall halls and open ground, LANDS before doors,
## doorway-sized gaps and low spaces and walks through them (normal stride-table chase), and lifts off again when the way opens, with
## hysteresis so she never flaps. Altitude stays inside [floor, ceiling - margin] everywhere, take-off/landing are smooth, wings fold on
## landing, a shadow follows her, the cues fire, and a guest follows the host's mode and altitude from the replicated gimmick state.
##
##   godot --headless --path . res://scenes/validate.tscn -- xivvy_flight

const HALL_CEILING := 4.5
const DOOR_LINTEL := 3.0
const ATRIUM_CEILING := 9.0
const RUN_Z := 5.5

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _slab(host: Node, x0: float, x1: float, y: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(x1 - x0, .2, 8.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3((x0 + x1) * .5, y + .1, RUN_Z)
	host.add_child(body)
	return body


func _wall(host: Node, x0: float, x1: float, z: float, height: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(x1 - x0, height, .2)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3((x0 + x1) * .5, height * .5, z)
	host.add_child(body)
	return body


func _ceiling_at(x: float) -> float:
	if x < 20.0:
		return HALL_CEILING
	if x < 22.0:
		return DOOR_LINTEL
	if x < 45.0:
		return HALL_CEILING
	return ATRIUM_CEILING


func _view(host: Node, at: Vector2, id: String = "xivvy") -> HunterView3D:
	var brain := HunterBrain.new(at, "FLIGHT-TEST", id, "standard")
	brain.activate_at(at)
	brain.state = HunterBrain.State.CHASE
	var view := HunterView3D.new()
	view.brain = brain
	host.add_child(view)
	return view


func run(host: Node) -> int:
	var tree := host.get_tree()
	await tree.process_frame

	# ---- the pure model: cruise altitude vs headroom, take-off, swoop, landing, bank, cadence
	var probe := XivvyFlight.new()
	_expect(absf(probe.cruise_altitude(INF) - XivvyFlight.CRUISE_OPEN) < .001, "open ground cruises at the top altitude")
	_expect(absf(probe.cruise_altitude(4.0) - (4.0 - XivvyFlight.BODY_HEIGHT - XivvyFlight.CEILING_GAP)) < .001, "a 4 m hall cruises under the ceiling")
	_expect(probe.cruise_altitude(9.0) > probe.cruise_altitude(4.5) and probe.cruise_altitude(4.5) > probe.cruise_altitude(3.8), "altitude scales with headroom")
	for headroom in [3.6, 4.0, 4.5, 6.0, 9.0, INF]:
		var flight := XivvyFlight.new()
		var peak := 0.0
		var rose_by := 0.0
		for i in 300:
			flight.update(1.0 / 60.0, true, 6.0, 0.0, INF, headroom)
			peak = maxf(peak, flight.altitude)
			if i == 90:
				rose_by = flight.altitude
			_expect(flight.altitude >= 0.0, "negative altitude")
			_expect(flight.altitude + XivvyFlight.BODY_HEIGHT <= headroom - XivvyFlight.CEILING_GAP + .02, "headroom %.1f: altitude %.2f puts her head through the ceiling" % [headroom, flight.altitude])
		var expected := probe.cruise_altitude(headroom)
		_expect(absf(peak - expected) < .05, "headroom %.1f: cruise %.2f, expected %.2f" % [headroom, peak, expected])
		_expect(rose_by > minf(expected, 2.5) * .8, "headroom %.1f: take-off too slow (%.2f after 1.5 s)" % [headroom, rose_by])
		var landing := XivvyFlight.new()
		landing.altitude = peak
		var previous := peak
		var monotone := true
		for i in 360:
			landing.update(1.0 / 60.0, false, 0.0, 0.0, INF, headroom)
			monotone = monotone and landing.altitude <= previous + .0001
			previous = landing.altitude
		_expect(landing.altitude == 0.0 and landing.phase == XivvyFlight.Phase.GROUND, "headroom %.1f: she did not land (%.2f)" % [headroom, landing.altitude])
		_expect(monotone, "headroom %.1f: landing was not smooth" % headroom)
	var dip := XivvyFlight.new()
	for i in 360:
		dip.update(1.0 / 60.0, true, 6.0, 0.0, 20.0, INF)
	var cruise := dip.altitude
	for i in 240:
		dip.update(1.0 / 60.0, true, 6.0, 0.0, XivvyFlight.GRAB_RANGE, INF)
	_expect(dip.altitude < cruise * .2 and dip.altitude >= 0.0, "she dips close to the floor when she closes in (%.2f vs %.2f)" % [dip.altitude, cruise])
	var turn := XivvyFlight.new()
	for i in 120:
		turn.update(1.0 / 60.0, true, 6.0, 3.0, INF, INF)
	_expect(turn.bank > deg_to_rad(15.0) and turn.bank <= XivvyFlight.BANK_LIMIT + .001, "a left turn banks left (%.1f deg)" % rad_to_deg(turn.bank))
	var fast_flaps := 0
	var fast := XivvyFlight.new()
	var slow_flaps := 0
	var slow := XivvyFlight.new()
	for i in 600:
		fast.update(1.0 / 60.0, true, 7.0, 0.0, INF, INF)
		slow.update(1.0 / 60.0, true, 1.0, 0.0, INF, INF)
		fast_flaps += 1 if fast.flapped else 0
		slow_flaps += 1 if slow.flapped else 0
	_expect(fast_flaps > slow_flaps and slow_flaps > 10, "wing cadence should rise with speed (%d vs %d beats in 10 s)" % [fast_flaps, slow_flaps])

	# ---- the mode: hysteresis, immediate landing, dwell before take-off
	var mode := XivvyFlight.new()
	var noisy := 0
	for i in 600:
		mode.update_mode(.1, 3.2 + .35 * (.5 + .5 * sin(float(i) * 1.7)), false)       # wobbles inside the 3.2-3.6 band
		noisy += 1
	_expect(mode.mode_switches == 0 and mode.fly_ok, "a ceiling wobbling inside the hysteresis band must not flip the mode (%d flips)" % mode.mode_switches)
	var low := XivvyFlight.new()
	low.fly_ok = false
	for i in 600:
		low.update_mode(.1, 3.2 + .35 * (.5 + .5 * sin(float(i) * 1.7)), false)
	_expect(low.mode_switches == 0 and not low.fly_ok, "...and neither when she is walking")
	var step := XivvyFlight.new()
	step.update_mode(.1, 3.0, false)
	_expect(not step.fly_ok, "a low ceiling ahead lands her at once")
	step.update_mode(.1, 4.0, false)
	_expect(not step.fly_ok, "take-off waits for the way to stay clear")
	for i in 6:
		step.update_mode(.1, 4.0, false)
	_expect(step.fly_ok, "...then she lifts off")
	step.update_mode(.1, 9.0, true)
	_expect(not step.fly_ok, "a doorway-sized gap lands her at once, however high the ceiling")

	# ---- a real hall -> door -> room -> atrium run with real colliders
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(200, .2, 40)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(40, -.1, RUN_Z)
	host.add_child(floor_body)
	var props: Array = [floor_body]
	props.append(_slab(host, -10, 20, HALL_CEILING))
	props.append(_slab(host, 20, 22, DOOR_LINTEL))
	props.append(_slab(host, 22, 45, HALL_CEILING))
	props.append(_slab(host, 45, 90, ATRIUM_CEILING))
	props.append(_wall(host, 20, 22, RUN_Z + .6, DOOR_LINTEL))
	props.append(_wall(host, 20, 22, RUN_Z - .6, DOOR_LINTEL))
	var camera := Camera3D.new()
	camera.position = Vector3(5.0, 2.0, RUN_Z + 5.0)
	host.add_child(camera)
	camera.current = true
	var view := _view(host, Vector2(0.5, RUN_Z))
	var guest := _view(host, Vector2(0.5, RUN_Z + 60.0))
	await tree.physics_frame
	await tree.process_frame
	var gimmick := view.brain.gimmick as XivvyGimmick
	var guest_gimmick := guest.brain.gimmick as XivvyGimmick
	_expect(gimmick != null and gimmick.network_state().has("fly_ok") and gimmick.network_state().has("alt"), "the mode and altitude hint must be in the gimmick's replicated state")
	gimmick.flying = true
	var screeches := int(Sound.play_counts.get("xivvy_screech", 0))
	var wings := int(Sound.play_counts.get("xivvy_wing", 0))
	var x := 0.5
	var worst_margin := INF
	var min_world_y := 0.0
	var cruise_hall := 0.0
	var cruise_atrium := 0.0
	var grounded_at_door := true
	var landed_before := true
	var walked_through := false
	var flew_in_room := false
	var fold_seen := 0.0
	var shadow_seen := false
	var guest_gap_hall := 0.0
	var guest_ok_door := true
	var frames := 0
	while x < 75.0 and frames < 2400:
		await tree.physics_frame
		await tree.process_frame
		frames += 1
		x += 5.0 / 60.0
		view.brain.position = Vector2(x, RUN_Z)
		view.brain.facing = Vector2(1, 0)
		var cells: Array = []
		for k in range(0, 16):
			cells.append(Vector2i(int(floor(x)) + k, int(floor(RUN_Z))))
		view.brain._path = cells
		view.set_look_target(Vector2(x + 40.0, RUN_Z))
		view.sync_from_brain()
		# the guest sits in open ground, 60 m away, and only receives the host's replicated state
		guest.brain.position = Vector2(x, RUN_Z + 60.0)
		guest.brain.facing = Vector2(1, 0)
		guest.set_look_target(Vector2(x + 40.0, RUN_Z + 60.0))
		guest_gimmick.apply_network_state(gimmick.network_state())
		guest.sync_from_brain()
		var altitude: float = view._flight.altitude
		worst_margin = minf(worst_margin, _ceiling_at(x) - (altitude + XivvyFlight.BODY_HEIGHT))
		min_world_y = minf(min_world_y, view.global_position.y)
		fold_seen = maxf(fold_seen, view._flight.wing_fold)
		shadow_seen = shadow_seen or (view._flight_shadow != null and view._flight_shadow.visible)
		if x > 8.0 and x < 11.0:
			cruise_hall = maxf(cruise_hall, altitude)
		if x > 19.0 and x < 22.6:
			grounded_at_door = grounded_at_door and altitude < .06 and not gimmick.fly_ok
			if x > 20.2 and x < 21.8:
				walked_through = walked_through or ["chase", "sprint", "walk"].has(view._animation_player.assigned_animation)
		if x > 17.5 and x < 19.0:
			landed_before = landed_before and altitude < .5
		if x > 34.0 and x < 44.0:
			flew_in_room = flew_in_room or altitude > 1.5
		if x > 62.0:
			cruise_atrium = maxf(cruise_atrium, altitude)
		if x > 8.0 and x < 11.0:
			guest_gap_hall = maxf(guest_gap_hall, guest._flight.altitude)
		if x > 19.5 and x < 22.2:
			guest_ok_door = guest_ok_door and guest._flight.altitude < .3 and not guest_gimmick.fly_ok
	_expect(frames < 2400, "the run did not finish")
	_expect(worst_margin >= .08, "her head came within %.2f m of a ceiling (needs 0.08 clear)" % worst_margin)
	_expect(min_world_y > -.02, "she went below the floor (%.2f)" % min_world_y)
	_expect(cruise_hall > 2.2 and cruise_hall <= HALL_CEILING - XivvyFlight.BODY_HEIGHT, "she should cruise high in the 4.5 m hall (%.2f)" % cruise_hall)
	_expect(cruise_atrium > 4.5, "in the 9 m atrium she should climb higher still (%.2f)" % cruise_atrium)
	_expect(landed_before, "she must already be down before the door")
	_expect(grounded_at_door, "she must be on the ground (and walking) at the doorway")
	_expect(walked_through, "she should walk the normal chase clip through the door, not the flight clip")
	_expect(flew_in_room, "she should lift off again in the room beyond the door")
	_expect(view._flight.mode_switches <= 3, "the mode flapped (%d switches on a straight run with one door)" % view._flight.mode_switches)
	_expect(fold_seen > .5, "her wings should fold as she lands (%.2f)" % fold_seen)
	_expect(shadow_seen, "a shadow should sit under her when she flies")
	_expect(int(Sound.play_counts.get("xivvy_screech", 0)) > screeches, "taking off should screech")
	_expect(int(Sound.play_counts.get("xivvy_wing", 0)) > wings + 4, "flying should beat her wings")
	_expect(guest_gap_hall > 2.0, "a guest should see the lift in the hall (%.2f)" % guest_gap_hall)
	_expect(guest_ok_door, "a guest should see her land for the door although its own surroundings are open ground")

	# ---- identity and everyone else
	var face := view._model.find_child("Face", true, false) as MeshInstance3D
	_expect(face != null and BlockyFace.owns_material(face), "Xivvy's Face quad lost its own material")
	var other := _view(host, Vector2(5.5, RUN_Z + 20.0), "dovelle")
	await tree.process_frame
	for i in 30:
		await tree.process_frame
		other.sync_from_brain()
	_expect(other._flight.altitude == 0.0 and other._flight_shadow == null and other._model.rotation.is_zero_approx(), "only Xivvy flies")
	other.queue_free()
	guest.queue_free()
	view.queue_free()
	camera.queue_free()
	for node in props:
		(node as Node).queue_free()

	if _failures == 0:
		print("  ok    xivvy_flight: high in halls, down for doors and low spaces, up again, no flapping, guests follow the host")
	return _failures
