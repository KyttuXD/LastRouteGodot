extends RefCounted

## Per-hunter chase styles (HunterChaseStyle). Every route hunter has a valid style in her data file
## (data/hunters/<id>.json "chase_style"; a runtime override wins), the style id replicates, and on a real HunterView3D in a chase: the reaching
## styles put the arm(s) out at shoulder height toward the runner, aimed and clamped to +-35 degrees; the glide keeps
## the arms at the sides; no style locks the elbows straight or freezes the arms (no mummies); the layer blends in (no pop), never builds up over frames, switches off for GRAB and when not
## chasing, and touches no leg bone (the planted foot stays where foot_slip measured it).
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- chase_style

const STEP := 1.0 / 60.0

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _view(host: Node, style: String) -> HunterView3D:
	var brain := HunterBrain.new(Vector2(10.5, 10.5), "CHASE-STYLE-%s" % style, "dovelle", "standard")
	brain.activate_at(brain.position)
	brain.state = HunterBrain.State.CHASE
	brain.direct_chase_visible = true
	brain.facing = Vector2(0, 1)
	brain.chase_style = style
	var view := HunterView3D.new()
	view.brain = brain
	host.add_child(view)
	view.rotation.y = atan2(-brain.facing.x, -brain.facing.y)
	return view


func _frames(host: Node, view: HunterView3D, count: int) -> void:
	for i in count:
		view.sync_from_brain()
		await host.get_tree().process_frame


## The upper arm's direction (shoulder -> elbow) in route space, and how high the elbow is relative to the shoulder.
func _arm(view: HunterView3D, side: String) -> Dictionary:
	var arm := view.find_child("%s-Arm" % side, true, false) as Node3D
	var fore := view.find_child("%s-Forearm" % side, true, false) as Node3D
	if arm == null or fore == null:
		return {}
	var d := fore.global_position - arm.global_position
	return {"flat": Vector2(d.x, d.z).normalized(), "rise": d.y / maxf(d.length(), .001)}


func run(host: Node) -> int:
	# table: every hunter, every style used, overrides
	var ids: Array = HunterRoster.IMPLEMENTED_IDS + HunterRoster.VOID_IDS + HunterRoster.SPECIAL_IDS
	var used := {}
	for id in ids:
		var style := HunterChaseStyle.style_for(id)
		_expect(HunterChaseStyle.valid(style), "%s has no valid chase style (%s)" % [id, style])
		used[HunterChaseStyle.base(style)] = true
		_expect(HunterBrain.new(Vector2.ZERO, "S", id).chase_style == style, "%s's brain does not carry her style" % id)
	for style in HunterChaseStyle.STYLES:
		_expect(used.has(style), "no hunter uses %s" % style)
	# the styles live in the hunters' data files (data/hunters/<id>.json "chase_style")
	for id in ids:
		var field := String(ContentRegistry.get_def("hunters", id).get("chase_style", ""))
		_expect(HunterChaseStyle.valid(field) and field == HunterChaseStyle.style_for(id),
			"%s's data file has no valid chase_style (%s)" % [id, field])
	HunterChaseStyle.set_override("dovelle", "skitter")
	_expect(HunterChaseStyle.style_for("dovelle") == "skitter", "a pack override is ignored")
	HunterChaseStyle.set_override("dovelle", "moonwalk")
	_expect(HunterChaseStyle.style_for("dovelle") == "skitter", "an invalid override replaced a valid one")
	HunterChaseStyle.set_override("dovelle", "")
	_expect(HunterChaseStyle.style_for("dovelle") == "pump", "clearing an override did not restore the table")
	_expect(not ("L-Thigh" in HunterChaseStyle.BONES or "L-Calf" in HunterChaseStyle.BONES or "Pelvis" in HunterChaseStyle.BONES),
		"the chase layer drives a leg bone")
	# replication
	var brain := HunterBrain.new(Vector2.ZERO, "S", "javelle")
	var world := StreamedWorldState.new()
	world.store_hunter("h", brain, 0, Vector3i.ZERO)
	var guest := HunterBrain.new(Vector2.ZERO, "G", "dovelle")
	world.restore_hunter(guest, world.hunter_state("h"))
	_expect(guest.chase_style == "reach2", "the chase style does not replicate (%s)" % guest.chase_style)

	# reach2 straight ahead: both arms out, roughly level, forward
	var view := _view(host, "reach2")
	view.set_look_target(Vector2(10.5, 20.5))
	await _frames(host, view, 60)
	var forward := Vector2(0, 1)
	for side in ["L", "R"]:
		var arm := _arm(view, side)
		_expect(not arm.is_empty() and arm["flat"].dot(forward) > .8 and absf(arm["rise"]) < .45,
			"reach2: the %s arm is not reaching forward at shoulder height (%s)" % [side, arm])
	# aimed: the arms point at a runner off to one side, never more than 35 degrees off her body's facing (the body
	# itself may turn toward the runner too, so this measures against where she faces now)
	view.rotation.y = atan2(-forward.x, -forward.y)
	for angle in [25.0, -25.0, 80.0]:
		var target := Vector2(10.5, 10.5) + forward.rotated(deg_to_rad(angle)) * 8.0
		view.set_look_target(target)
		await _frames(host, view, 40)
		var body := Vector2(-sin(view.rotation.y), -cos(view.rotation.y))
		var runner := (target - view.brain.position).normalized()
		var arm := _arm(view, "R")
		var off_body := rad_to_deg(body.angle_to(arm["flat"])) if not arm.is_empty() else 999.0
		var want := clampf(rad_to_deg(body.angle_to(runner)), -35.0, 35.0)
		_expect(absf(off_body - want) < 14.0 and absf(off_body) < 35.0 + 12.0,
			"reach aimed %.0f degrees off her facing for a runner %.0f off it (want %.0f)" % [off_body, rad_to_deg(body.angle_to(runner)), want])
	# no build-up: the same target for a while keeps the arm where it was
	view.set_look_target(Vector2(10.5, 20.5))
	await _frames(host, view, 40)
	var before: Dictionary = _arm(view, "L")
	await _frames(host, view, 120)
	var after: Dictionary = _arm(view, "L")
	_expect(not before.is_empty() and before["flat"].dot(after["flat"]) > .97, "the reach drifts over time (the layer accumulates)")
	# GRAB switches it off: it blends out rather than popping
	view.chase_layer_enabled = false
	await _frames(host, view, 2)
	var mid := view._chase.weight
	await _frames(host, view, 200)
	_expect(mid > .5 and view._chase.weight < .01, "switching the layer off for a grab popped or never let go (%.2f -> %.2f)" % [mid, view._chase.weight])
	view.queue_free()

	# reach1: only the lead (right) arm reaches
	view = _view(host, "reach1")
	view.set_look_target(Vector2(10.5, 20.5))
	await _frames(host, view, 60)
	var lead := _arm(view, "R")
	var other := _arm(view, "L")
	_expect(not lead.is_empty() and lead["flat"].dot(forward) > .8 and other["rise"] < -.6,
		"reach1: the lead arm is not out alone (lead %s other %s)" % [lead, other])
	view.queue_free()

	# glide: arms hang at the sides; blend-in is gradual
	view = _view(host, "glide")
	await _frames(host, view, 3)
	_expect(view._chase.weight > 0.0 and view._chase.weight < .5, "the chase style popped in (%.2f after 3 frames)" % view._chase.weight)
	await _frames(host, view, 60)
	for side in ["L", "R"]:
		var arm := _arm(view, side)
		_expect(not arm.is_empty() and arm["rise"] < -.85, "glide: the %s arm swings out (%s)" % [side, arm])
	# out of the chase the layer lets go
	view.brain.state = HunterBrain.State.WANDER
	await _frames(host, view, 200)
	_expect(view._chase.weight < .01, "the chase layer stays on outside a chase")
	view.queue_free()
	# no mummies: in every style the elbows stay bent and the arms keep moving with the stride
	for style in HunterChaseStyle.STYLES:
		view = _view(host, style)
		view.set_look_target(Vector2(10.5, 20.5))
		await _frames(host, view, 70)
		var rest: Dictionary = view._chase._rest
		var bend := {}
		var lo := {}
		var hi := {}
		for i in 90:
			view.brain.position += view.brain.facing * 3.6 * STEP
			await _frames(host, view, 1)
			for bone in ["L-Arm", "R-Arm", "L-Forearm", "R-Forearm"]:
				var node := view.find_child(bone, true, false) as Node3D
				var off := rad_to_deg((node.quaternion * (rest[bone] as Quaternion).inverse()).get_angle())
				bend[bone] = float(bend.get(bone, 0.0)) + off / 90.0
				lo[bone] = minf(float(lo.get(bone, 999.0)), off)
				hi[bone] = maxf(float(hi.get(bone, -999.0)), off)
		for side in ["L", "R"]:
			var fore := "%s-Forearm" % side
			var arm := "%s-Arm" % side
			var moving := maxf(hi[arm] - lo[arm], hi[fore] - lo[fore])
			_expect(bend[fore] > 25.0, "%s: the %s elbow is locked straight (%.0f deg bend)" % [style, side, bend[fore]])
			_expect(moving > 8.0, "%s: the %s arm is frozen in the chase (%.0f deg of motion)" % [style, side, moving])
		view.queue_free()
	if _failures == 0:
		print("  chase_style  ok (%d hunters, %d styles)" % [ids.size(), HunterChaseStyle.STYLES.size()])
	return _failures
