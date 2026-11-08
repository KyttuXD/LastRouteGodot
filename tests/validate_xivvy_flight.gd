extends RefCounted

## Xivvy's flying chase, clearance-driven: she hovers about 1.2 m up in halls and open ground (lowered only where a ceiling would reach
## her head), LANDS before doors,
## doorway-sized gaps and low spaces and walks through them (normal stride-table chase), and lifts off again when the way opens, with
## hysteresis so she never flaps. Altitude stays inside [floor, ceiling - margin] everywhere, take-off/landing are smooth, wings fold on
## landing, a shadow follows her, the cues fire, and a guest follows the host's mode and altitude from the replicated gimmick state.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- xivvy_flight

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


## The model's height as it is drawn (the roster scale included), measured from its meshes the way tests/validate_hunter_scale.gd does.
func _drawn_height(host: Node) -> float:
	var model := ModelSlot.instantiate_hunter(HunterRoster.get_identity("xivvy"))
	if model == null:
		return 0.0
	model.scale = Vector3.ONE * HunterRoster.scale_for("xivvy")
	host.add_child(model)
	await host.get_tree().process_frame
	var top := -INF
	var bottom := INF
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		if m.mesh == null or not m.visible:
			continue
		var box := m.global_transform * m.get_aabb()
		top = maxf(top, box.end.y)
		bottom = minf(bottom, box.position.y)
	model.queue_free()
	return top - bottom if top > bottom else 0.0


## Xivvy flying for six seconds under a drawn vault `vault` metres above her floor, with no collider over her. The view reads the
## vault through its ceiling provider (the streamed game binds it per level, as it binds the surface height). Returns the smallest
## gap between her drawn head and the vault over the run.
func _vault_clearance(host: Node, vault: float, drawn: float) -> float:
	var tree := host.get_tree()
	var view := _view(host, Vector2(90.0, RUN_Z + 240.0))
	view.set("ceiling_height_provider", func(_at: Vector2) -> float: return vault)
	await tree.physics_frame
	await tree.process_frame
	var gimmick := view.brain.gimmick as XivvyGimmick
	gimmick.flying = true
	var clearance := INF
	for i in 360:
		await tree.physics_frame
		await tree.process_frame
		view.sync_from_brain()
		var head: float = view._flight.altitude + view._flight.float_bob + drawn
		clearance = minf(clearance, vault - head)
	view.queue_free()
	return clearance


## B3: a vault that covers only one side of her body (her centre under a 3.9 m hall, the vault's edge 0.3 m to her side). The
## survey used to read the hall at her centre and let her hover at the hall's height, so her head went through the vault's edge.
func _edge_vault_clearance(host: Node, vault: float, drawn: float) -> float:
	var tree := host.get_tree()
	var view := _view(host, Vector2(90.0, RUN_Z + 240.0))
	var edge := 90.0 + .3
	view.set("ceiling_height_provider", func(at: Vector2) -> float: return vault if at.x >= edge else INF)
	await tree.physics_frame
	await tree.process_frame
	var gimmick := view.brain.gimmick as XivvyGimmick
	gimmick.flying = true
	var clearance := INF
	for i in 360:
		await tree.physics_frame
		await tree.process_frame
		view.sync_from_brain()
		var head: float = view._flight.altitude + view._flight.float_bob + drawn
		clearance = minf(clearance, vault - head)
	view.queue_free()
	return clearance


func run(host: Node) -> int:
	var tree := host.get_tree()
	await tree.process_frame

	# ---- the pure model: a low hover (about 1.2 m), lowered only under a ceiling; take-off, swoop, landing, bank, cadence
	var probe := XivvyFlight.new()
	var hover := XivvyFlight.HOVER_HEIGHT
	var gap := XivvyFlight.CEILING_GAP
	var body := XivvyFlight.BODY_HEIGHT
	_expect(absf(hover - 1.2) < .001, "the hover is about 1.2 m (%.2f)" % hover)
	_expect(absf(probe.cruise_altitude(INF) - hover) < .001, "open ground hovers at %.2f m (%.2f)" % [hover, probe.cruise_altitude(INF)])
	_expect(absf(probe.cruise_altitude(4.0) - hover) < .02, "a 4 m hall hovers, not up to the ceiling (%.2f)" % probe.cruise_altitude(4.0))
	_expect(4.0 - (probe.cruise_altitude(4.0) + body) >= gap - .001, "a 4 m hall leaves her head at least the gap under the ceiling (%.2f m)" % (4.0 - (probe.cruise_altitude(4.0) + body)))
	_expect(absf(probe.cruise_altitude(9.0) - hover) < .001 and absf(probe.cruise_altitude(4.5) - hover) < .001, "a 4.5 m hall and a 9 m atrium hover at the same height")
	_expect(absf(probe.cruise_altitude(2.9) - (2.9 - body - gap)) < .001 and probe.cruise_altitude(2.9) < hover - .1, "a 2.9 m ceiling lowers the hover to clear her head (%.2f)" % probe.cruise_altitude(2.9))
	for headroom in [2.9, 3.6, 4.0, 4.5, 6.0, 9.0, INF]:
		var here := probe.cruise_altitude(headroom)
		_expect(here <= hover + .001, "headroom %.1f: never above the hover (%.2f)" % [headroom, here])
		_expect(here + body + gap <= headroom + .001, "headroom %.1f: the hover puts her head through the ceiling (%.2f)" % [headroom, here])
	for headroom in [2.9, 3.6, 4.0, 4.5, 6.0, 9.0, INF]:
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
		# the full hover needs the head clear of a ceiling at hover + body + gap (4.0 m with the 2.67 m drawn body); below that she is lowered
		_expect(headroom < hover + body + gap or absf(peak - hover) < .05, "headroom %.1f: she should hover at %.2f, not climb (peak %.2f)" % [headroom, hover, peak])
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
	_expect(absf(cruise - hover) < .05, "she hovers at %.2f before she closes in (%.2f)" % [hover, cruise])
	for i in 240:
		dip.update(1.0 / 60.0, true, 6.0, 0.0, XivvyFlight.GRAB_RANGE, INF)
	_expect(absf(dip.altitude - XivvyFlight.SWOOP_ALTITUDE) < .05 and dip.altitude >= 0.0, "she swoops down to the grab just above the floor (%.2f)" % dip.altitude)
	_expect(cruise - dip.altitude > .6, "the swoop drops her well below the hover (%.2f vs %.2f)" % [dip.altitude, cruise])

	# ---- the float: a gentle bob and sway on top of the hover (view only), never through a ceiling, none on the ground
	var floaty := XivvyFlight.new()
	var bob_low := 0.0
	var bob_high := 0.0
	var sway_peak := 0.0
	var crossings := 0
	var last_sign := 0.0
	for i in 1200:   # 20 s at 60 Hz; the first 5 s are the take-off
		floaty.update(1.0 / 60.0, true, 1.0, 0.0, INF, INF)
		if i > 300:
			bob_low = minf(bob_low, floaty.float_bob)
			bob_high = maxf(bob_high, floaty.float_bob)
			sway_peak = maxf(sway_peak, absf(floaty.float_sway))
			var sign_now := signf(floaty.float_bob)
			if sign_now != 0.0:
				if last_sign != 0.0 and sign_now != last_sign:
					crossings += 1
				last_sign = sign_now
	_expect(bob_high > .04 and bob_low < -.04 and bob_high <= .05 + .001 and bob_low >= -.05 - .001, "the float bobs about 5 cm either way (%.3f..%.3f)" % [bob_low, bob_high])
	_expect(sway_peak > .04 and sway_peak <= .05 + .001, "the float sways about 5 cm (%.3f)" % sway_peak)
	# 0.7 Hz over 15 s: about 21 zero crossings of the bob
	_expect(crossings >= 19 and crossings <= 23, "the float runs at about 0.7 Hz (%d crossings in 15 s)" % crossings)
	var under := XivvyFlight.new()
	for i in 600:
		under.update(1.0 / 60.0, true, 6.0, 0.0, INF, 3.0)
		_expect(under.altitude + under.float_bob + body <= 3.0 - gap + .001, "the float never lifts her head into a 3 m ceiling (%.3f)" % (under.altitude + under.float_bob + body))
	_expect(absf(under.altitude - (3.0 - body - gap)) < .001, "under a 3 m ceiling she hovers at the clearance (%.2f)" % under.altitude)
	var grounded := XivvyFlight.new()
	for i in 60:
		grounded.update(1.0 / 60.0, false, 0.0, 0.0, INF, INF)
	_expect(grounded.float_bob == 0.0 and grounded.float_sway == 0.0, "no float on the ground")
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
		# the head includes the float's bob (presentation), so the margin is checked on what is drawn
		worst_margin = minf(worst_margin, _ceiling_at(x) - (altitude + view._flight.float_bob + XivvyFlight.BODY_HEIGHT))
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
			flew_in_room = flew_in_room or altitude > .8
		if x > 62.0:
			cruise_atrium = maxf(cruise_atrium, altitude)
		if x > 8.0 and x < 11.0:
			guest_gap_hall = maxf(guest_gap_hall, guest._flight.altitude)
		if x > 19.5 and x < 22.2:
			guest_ok_door = guest_ok_door and guest._flight.altitude < .3 and not guest_gimmick.fly_ok
	_expect(frames < 2400, "the run did not finish")
	_expect(worst_margin >= .08, "her head came within %.2f m of a ceiling (needs 0.08 clear)" % worst_margin)
	_expect(min_world_y > -.02, "she went below the floor (%.2f)" % min_world_y)
	_expect(absf(cruise_hall - hover) < .05, "she should hover at %.2f in the 4.5 m hall, not climb to the ceiling (%.2f)" % [hover, cruise_hall])
	_expect(absf(cruise_atrium - hover) < .05, "in the 9 m atrium she should hover at the same height (%.2f)" % cruise_atrium)
	_expect(landed_before, "she must already be down before the door")
	_expect(grounded_at_door, "she must be on the ground (and walking) at the doorway")
	_expect(walked_through, "she should walk the normal chase clip through the door, not the flight clip")
	_expect(flew_in_room, "she should lift off again in the room beyond the door")
	_expect(view._flight.mode_switches <= 3, "the mode flapped (%d switches on a straight run with one door)" % view._flight.mode_switches)
	_expect(fold_seen > .5, "her wings should fold as she lands (%.2f)" % fold_seen)
	_expect(shadow_seen, "a shadow should sit under her when she flies")
	_expect(int(Sound.play_counts.get("xivvy_screech", 0)) > screeches, "taking off should screech")
	_expect(int(Sound.play_counts.get("xivvy_wing", 0)) > wings + 4, "flying should beat her wings")
	_expect(absf(guest_gap_hall - hover) < .05, "a guest should see the same hover in the hall (%.2f)" % guest_gap_hall)
	_expect(guest_ok_door, "a guest should see her land for the door although its own surroundings are open ground")

	# ---- caught mid-flight, she lands for the grab ("after chasing, Xivvy's body is gone while her dialogue
	# still plays"). The grab pins her model where it begins; pinned in the air she held the runner out of view.
	# starts 10 m back from the host (who hovers at 1.2 m, so her body is a low "ceiling" to a second flyer's survey 12 m ahead)
	var catcher := _view(host, Vector2(50.0, RUN_Z))
	await tree.physics_frame
	await tree.process_frame
	var catcher_gimmick := catcher.brain.gimmick as XivvyGimmick
	catcher_gimmick.flying = true
	for i in 240:
		await tree.physics_frame
		await tree.process_frame
		catcher.brain.position = Vector2(50.0 + float(i) * .02, RUN_Z)
		catcher.brain.facing = Vector2(1, 0)
		catcher.set_look_target(Vector2(120.0, RUN_Z))
		catcher.sync_from_brain()
	var caught_at := catcher._flight.altitude
	_expect(caught_at > .8, "the catch check needs her airborne first (%.2f)" % caught_at)
	HunterGrab.pose_hunter_body(catcher, Vector3(1, 0, 0), [0.0, 0.0, 0.0])
	_expect(catcher.grabbing(), "the grab should mark her as holding someone")
	_expect(not catcher_gimmick.flying and catcher._flight.altitude == 0.0, "a grab must land her (flying %s, altitude %.2f)" % [catcher_gimmick.flying, catcher._flight.altitude])
	_expect(absf(catcher.global_position.y) < .05, "she must hold the runner from her floor, not %.2f m up" % catcher.global_position.y)
	_expect(is_zero_approx(catcher._model.rotation.x) and is_zero_approx(catcher._model.rotation.z), "she must hold the runner level, not banked or pitched")
	var anchor: Transform3D = catcher.get_meta("grab_anchor")
	_expect(absf(anchor.origin.y) < .05, "the grab anchor must be on her floor (%.2f)" % anchor.origin.y)
	_expect(catcher._model.visible, "her model must stay visible while she holds the runner")
	# the host's brain may keep reading CHASE next to the runner and set flying again: while she holds, she stays down
	for i in 30:
		catcher_gimmick.flying = true
		HunterGrab.pose_hunter_body(catcher, Vector3(1, 0, 0), [0.0, 0.0, 0.0])
		catcher.sync_from_brain()
		await tree.physics_frame
		await tree.process_frame
	_expect(catcher._flight.altitude < .01 and absf(catcher.global_position.y) < .05, "she lifted off again mid-hold (%.2f)" % catcher._flight.altitude)
	catcher.grab_until_msec = 0   # let go: her own view eases the model back (HunterView3D.ease_out_grab)
	catcher.queue_free()

	# ---- free flight stays on her storey ("Xivvy flies into the next level, like she noclips"). In the
	# streamed facility the storey is LEVEL_HEIGHT and the next floor sits right above; with no ceiling collider over her
	# (open air, a well, the storey above not streamed in) the headroom read INF and her body rose through the slab, into +1.
	var storey := StreamedFacilityView3D.LEVEL_HEIGHT - StreamedFacilityView3D.SLAB
	var capped := XivvyFlight.new()
	capped.storey_headroom = storey
	_expect(capped.cruise_altitude(INF) + XivvyFlight.BODY_HEIGHT <= storey - XivvyFlight.CEILING_GAP + .001, "storey cap: open-air cruise %.2f puts her head through the slab" % capped.cruise_altitude(INF))
	_expect(absf(capped.cruise_altitude(INF) - (storey - XivvyFlight.BODY_HEIGHT - gap)) < .001, "storey cap: in a %.1f m storey she sits at the storey's clearance (%.2f)" % [storey, capped.cruise_altitude(INF)])
	var capped_peak := 0.0
	for i in 600:
		capped.update(1.0 / 60.0, true, 6.0, 0.0, INF, INF)
		capped_peak = maxf(capped_peak, capped.altitude)
	_expect(capped_peak + XivvyFlight.BODY_HEIGHT <= storey - XivvyFlight.CEILING_GAP + .02, "storey cap: she climbed to %.2f, into the storey above" % capped_peak)
	# a storey lower than the hover: the slab, not the hover, sets her height
	var low_storey := XivvyFlight.new()
	low_storey.storey_headroom = 3.0
	_expect(absf(low_storey.cruise_altitude(INF) - (3.0 - XivvyFlight.BODY_HEIGHT - XivvyFlight.CEILING_GAP)) < .001, "storey cap: a 3 m storey lowers her to the slab (%.2f)" % low_storey.cruise_altitude(INF))
	var stale := XivvyFlight.new()
	stale.storey_headroom = storey
	stale.override_cruise = 3.5   # a guest given a hint far above her storey (an older host's climb)
	for i in 600:
		stale.update(1.0 / 60.0, true, 6.0, 0.0, INF, INF)
	_expect(stale.altitude + XivvyFlight.BODY_HEIGHT <= storey - XivvyFlight.CEILING_GAP + .02, "storey cap: a guest's hint above the storey lifted her to %.2f" % stale.altitude)
	# a real view over ground with no ceiling collider at all, on a streamed storey
	var storeyed := _view(host, Vector2(60.0, RUN_Z + 120.0))
	storeyed.flight_storey_headroom = storey
	await tree.physics_frame
	await tree.process_frame
	var storeyed_gimmick := storeyed.brain.gimmick as XivvyGimmick
	storeyed_gimmick.flying = true
	var storeyed_peak := 0.0
	var storeyed_top := 0.0
	for i in 360:
		await tree.physics_frame
		await tree.process_frame
		storeyed.brain.position = Vector2(60.0 + float(i) * .05, RUN_Z + 120.0)
		storeyed.brain.facing = Vector2(1, 0)
		storeyed.set_look_target(Vector2(140.0, RUN_Z + 120.0))
		storeyed.sync_from_brain()
		storeyed_peak = maxf(storeyed_peak, storeyed._flight.altitude)
		storeyed_top = maxf(storeyed_top, storeyed.global_position.y + XivvyFlight.BODY_HEIGHT)
	_expect(absf(storeyed_peak - (storey - XivvyFlight.BODY_HEIGHT - gap)) < .05, "storey cap: the streamed view should sit at the storey's clearance (%.2f)" % storeyed_peak)
	_expect(storeyed_top <= storey - XivvyFlight.CEILING_GAP + .02, "storey cap: her head reached %.2f m, through the %.2f m slab" % [storeyed_top, storey])
	_expect(storeyed_gimmick.altitude_hint + XivvyFlight.BODY_HEIGHT <= storey - XivvyFlight.CEILING_GAP + .02, "storey cap: the replicated hint %.2f is above the storey" % storeyed_gimmick.altitude_hint)
	storeyed.queue_free()
	# the streamed game must hand every hunter view its storey height (host spawn and guest mirror)
	var streamed_src := FileAccess.get_file_as_string("res://game/infinite_route/infinite_route_test.gd")
	_expect(streamed_src.count("view.flight_storey_headroom = StreamedFacilityView3D.LEVEL_HEIGHT") >= 2, "the streamed game must cap Xivvy's flight to the storey on host and guest views")
	_expect(streamed_src.count("view.ceiling_height_provider = facility.streamed_ceiling_height.bind(") >= 3, "the streamed game must give every hunter view its drawn ceilings (host, guest and a ladder's level change)")

	# ---- B3: she is drawn at the roster scale (1.5x), and a vault she cannot collide with still bounds her flight. The sewer
	# walkways (3.2 m) and the small rooms (3.7 m) are drawn ceilings with no collider, so the headroom ray reads INF there and
	# her head went through them. The drawn height is measured from the model, not read back from BODY_HEIGHT.
	var drawn := await _drawn_height(host)
	_expect(absf(XivvyFlight.BODY_HEIGHT - drawn) < .02, "the flight body height %.2f is not the drawn height %.2f (her model is scaled %.1fx)" % [XivvyFlight.BODY_HEIGHT, drawn, HunterRoster.scale_for("xivvy")])
	for vault in [3.2, 3.7]:
		var clearance := await _vault_clearance(host, vault, drawn)
		_expect(clearance >= XivvyFlight.CEILING_GAP - .02, "a drawn %.1f m vault with no collider: her head came within %.2f m of it" % [vault, clearance])
	# B3 (footprint): her head is as wide as her body, so a vault edge that covers only one side of her still bounds her
	var edge_clearance := await _edge_vault_clearance(host, 3.2, drawn)
	_expect(edge_clearance >= XivvyFlight.CEILING_GAP - .02, "a drawn 3.2 m vault edge beside her body with no collider: her head came within %.2f m of it" % edge_clearance)

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
		print("  ok    xivvy_flight: hovers low in halls and open ground, down for doors and low spaces, up again, floats, no flapping, guests follow the host, never above her storey or a ceiling")
	return _failures
