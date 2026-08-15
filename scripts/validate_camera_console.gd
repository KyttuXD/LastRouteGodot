extends SceneTree

## Headless check on the desk camera console, in the same spirit as
## scripts/validate_office_rooms.gd.
##
## The console is a physical control: eleven 2.8 cm caps on a tilted board,
## aimed at with a ray. Three things can be wrong about it in ways that no
## import check would notice, and all three make it unusable rather than
## merely ugly:
##
##   1. The drawn plan and the physical buttons disagree. The caps are placed
##      by tools/office/build_office_room.py and the plan is drawn from the
##      generated OfficeLayout; if those drift, the console still LOOKS like a
##      map while pointing at the wrong rooms.
##   2. A button cannot be aimed at. The seated cursor drives the head AND the
##      ray, so turning to look at a cap also swings the ray past it. Whether
##      every cap has a reachable cursor position is a property of that
##      feedback loop, not something that can be read off the model.
##   3. A live viewport mapped onto a screen samples the atlas patch the mesh's
##      UVs point into rather than the picture. That failure is invisible in
##      the node tree and looks like a screen that is simply off.
##
## Run with:
##   godot4 --headless --script scripts/validate_camera_console.gd
##
## It reaches into OfficeView3D's private state on purpose: this is the
## project's own harness, and the alternative is widening that class's API for
## no one but the test.

## The cursor sweep's resolution. Coarse grids lie: the console occupies about
## a fifth of the screen and a cap's reachable region is a fraction of that, so
## a low-resolution sweep reports buttons as unreachable that a player would
## find immediately.
const SWEEP := Vector2i(420, 300)


func _initialize() -> void:
	_run()


func _run() -> void:
	var failures := 0
	var scene: Node = load("res://scenes/office_3d.tscn").instantiate()
	root.add_child(scene)
	# One frame to build the world, one more for OfficeView3D to measure the
	# console off transforms that have actually settled.
	await process_frame
	await process_frame

	var view: OfficeView3D = scene.get_node("%OfficeView")
	var sim: OfficeSimulation = scene.simulation

	failures += _check_caps(view)
	failures += _check_plan(view)
	failures += _check_screens(view)
	failures += _check_reach(view)
	failures += await _check_presses(view, sim)

	if failures > 0:
		push_error("%d camera console check(s) failed" % failures)
		quit(1)
	else:
		print("camera console OK")
		quit(0)


func _fail(message: String) -> int:
	print("  FAIL  %s" % message)
	return 1


func _check_caps(view: OfficeView3D) -> int:
	var failures := 0
	if not view._console_ready:
		return _fail("console never measured -- no CamPanelScreen or no caps")
	if view._caps.size() != OfficeConfig.CAMERAS.size():
		failures += _fail("found %d caps, expected %d"
			% [view._caps.size(), OfficeConfig.CAMERAS.size()])
	for cam in OfficeConfig.CAMERAS:
		if not view._caps.has(cam):
			failures += _fail("no cap for %s" % cam)
		elif not view._cap_materials.has(cam):
			failures += _fail("cap %s has no material to light" % cam)

	# Caps that overlap cannot be told apart by pointing at them, however
	# forgiving the picking is.
	var closest := INF
	for a in view._cap_local:
		for b in view._cap_local:
			if a < b:
				closest = minf(closest, view._cap_local[a].distance_to(view._cap_local[b]))
	# Measured off the model rather than restated, so resizing the caps in the
	# builder cannot quietly invalidate this.
	var cap_size := 0.0
	for cam in view._caps:
		var box: AABB = (view._caps[cam] as MeshInstance3D).get_aabb()
		cap_size = maxf(cap_size, maxf(box.size.x, box.size.y))
	if closest < cap_size:
		failures += _fail("closest caps %.1f mm apart but a cap is %.1f mm across"
			% [closest * 1000.0, cap_size * 1000.0])
	print("  caps      %d of %.0f mm, closest pair %.1f mm apart"
		% [view._caps.size(), cap_size * 1000.0, closest * 1000.0])
	return failures


## The drawn plan has to land under the physical buttons. This is the whole
## premise of the console: press the room, not the number.
func _check_plan(view: OfficeView3D) -> int:
	var failures := 0
	var worst := 0.0
	for cam in OfficeConfig.CAMERAS:
		if not view._panel.cap_tex.has(cam) or not OfficeLayout.CAMERA_XZ.has(cam):
			failures += _fail("%s missing from the plan" % cam)
			continue
		var drawn: Vector2 = view._panel.to_tex * (OfficeLayout.CAMERA_XZ[cam] as Vector2)
		var cap: Vector2 = view._panel.cap_tex[cam]
		worst = maxf(worst, drawn.distance_to(cap))
		if not Rect2(Vector2.ZERO, Vector2(OfficePanel.PANEL_SIZE)).has_point(cap):
			failures += _fail("%s cap falls outside the panel display at %s" % [cam, cap])
	if worst > 1.0:
		failures += _fail("plan is %.2f px off the caps it is meant to sit under" % worst)
	print("  plan      drawn within %.2f px of every cap" % worst)
	return failures


## A screen's mesh UVs point into one patch of the shared atlas. The remap has
## to turn that patch back into the full 0..1 a viewport texture expects.
func _check_screens(view: OfficeView3D) -> int:
	var failures := 0
	for pair in [["CRT", view._monitor_face, view._feed_material],
			["console", view._panel_face, view._panel_material]]:
		var label: String = pair[0]
		var mesh: MeshInstance3D = pair[1]
		var material: StandardMaterial3D = pair[2]
		if mesh == null or material == null:
			failures += _fail("%s screen was never wired up" % label)
			continue
		var uvs: PackedVector2Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		var lo := uvs[0]
		var hi := uvs[0]
		for uv in uvs:
			lo = lo.min(uv)
			hi = hi.max(uv)
		var scale := Vector2(material.uv1_scale.x, material.uv1_scale.y)
		var offset := Vector2(material.uv1_offset.x, material.uv1_offset.y)
		var mapped_lo := lo * scale + offset
		var mapped_hi := hi * scale + offset
		if mapped_lo.length() > 0.001 or (mapped_hi - Vector2.ONE).length() > 0.001:
			failures += _fail("%s screen maps its atlas patch to %s..%s, not 0..1"
				% [label, mapped_lo, mapped_hi])
		else:
			print("  %-9s atlas patch %.4f..%.4f remapped to fill the face"
				% [label, lo.x, hi.x])
	return failures


## Sweep the cursor over the whole viewport and see which caps can be reached.
##
## Not a geometric check: seated, the cursor sets the head's yaw and pitch AND
## the aiming ray, so moving toward a button also turns away from it. Whether
## that loop leaves every cap reachable is only answerable by driving it.
func _check_reach(view: OfficeView3D) -> int:
	var walker: OfficeWalker = view._walker
	var rect := Vector2(view._viewport.size)
	var hits := {}
	for iy in SWEEP.y:
		for ix in SWEEP.x:
			var point := Vector2(
				(ix + 0.5) / SWEEP.x * rect.x, (iy + 0.5) / SWEEP.y * rect.y)
			walker.aim_seated(point, rect)
			var hit := view._pick(point)
			var cam := String(hit.get("cam", ""))
			if cam == "":
				continue
			hits[cam] = Rect2(point, Vector2.ZERO) if not hits.has(cam) \
				else (hits[cam] as Rect2).expand(point)
	walker.aim_seated(rect * 0.5, rect)

	var failures := 0
	var smallest := INF
	var smallest_cam := ""
	for cam in OfficeConfig.CAMERAS:
		# The narrow side of the cursor box a cap answers to, in the project's
		# 480 x 270 base pixels. That is the number a hand has to hit; an AREA
		# hides a region that is wide but one pixel tall.
		var narrow := 0.0
		if hits.has(cam):
			var box: Rect2 = hits[cam]
			narrow = minf(box.size.x, box.size.y)
		if narrow <= 0.0:
			failures += _fail("%s cannot be aimed at from the seat" % cam)
		elif narrow < smallest:
			smallest = narrow
			smallest_cam = cam
	# Four base pixels is eight on the default 960 x 540 window, and more on
	# anything larger, since the stretch scales the cursor with it.
	if smallest < 4.0:
		failures += _fail("%s answers to only %.1f base px of cursor travel"
			% [smallest_cam, smallest])
	print("  reach     all %d caps reachable, tightest is %s at %.1f base px across"
		% [OfficeConfig.CAMERAS.size(), smallest_cam, smallest])
	return failures


func _check_presses(view: OfficeView3D, sim: OfficeSimulation) -> int:
	var failures := 0
	for cam in OfficeConfig.CAMERAS:
		view._press(cam)
		if sim.current_camera != cam:
			failures += _fail("pressing %s left the feed on %s" % [cam, sim.current_camera])
	await process_frame
	if view._feed != null and view._feed._current != sim.current_camera:
		failures += _fail("feed is showing %s while the console says %s"
			% [view._feed._current, sim.current_camera])

	# A console that keeps switching feeds through a blackout is lying about a
	# system that is down.
	sim.select_camera("cam1")
	sim.blackout_timer = 3.0
	view._press("cam8")
	if sim.current_camera != "cam1":
		failures += _fail("console switched to cam8 during a blackout")
	sim.blackout_timer = 0.0
	print("  presses   all %d caps switch the feed; refused during blackout"
		% OfficeConfig.CAMERAS.size())
	return failures
