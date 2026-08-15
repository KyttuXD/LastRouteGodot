extends RefCounted

## Headless check on the desk camera console, in the same spirit as
## scripts/validate_office_rooms.gd.
##
## The console is a physical control: two 36 x 11 cm buttons on a tilted board,
## aimed at with a ray, cycling the feed. Three things can be wrong about it in
## ways no import check would notice, and all three make it unusable rather
## than merely ugly:
##
##   1. A button cannot be aimed at, or is a pinprick. The seated cursor drives
##      the head AND the ray, so turning to look at a button also swings the
##      ray past it. How much cursor travel a button actually answers to is a
##      property of that feedback loop, not something readable off the model.
##      This is the check that killed the eleven-cap floor plan the console
##      started as: five of its caps could not be reached at all.
##   2. PREV and NEXT disagree with the screen above them, or do not between
##      them reach every camera.
##   3. A live viewport mapped onto a screen samples the atlas patch the mesh's
##      UVs point into rather than the picture. That failure is invisible in
##      the node tree and looks like a screen that is simply off.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- camera_console
##
## It reaches into OfficeView3D's private state on purpose: this is the
## project's own harness, and the alternative is widening that class's API for
## no one but the test.
## The cursor sweep's resolution. Coarse grids lie: the console occupies about
## a fifth of the screen, so a low-resolution sweep reports buttons as
## unreachable that a player would find immediately.

## The suite runs inside scenes/validate.tscn, so the tree comes from the host
## node rather than from `self` -- see scripts/validate_runner.gd for why these
## are not `--script` SceneTree scripts any more.
var _host: Node


func _tree() -> SceneTree:
	return _host.get_tree()


func _root() -> Window:
	return _host.get_tree().root


func _frame() -> Signal:
	return _host.get_tree().process_frame


const SWEEP := Vector2i(420, 300)


func run(host: Node) -> int:
	_host = host
	var failures := 0
	var scene: Node = load("res://scenes/office_3d.tscn").instantiate()
	_root().add_child(scene)
	# One frame to build the world, one more for OfficeView3D to measure the
	# console off transforms that have actually settled.
	await _frame()
	await _frame()

	var view: OfficeView3D = scene.get_node("%OfficeView")
	var sim: OfficeSimulation = scene.simulation

	failures += _check_buttons(view)
	failures += _check_plan(view)
	failures += _check_screens(view)
	failures += _check_reach(view)
	failures += await _check_cycle(view, sim)

	if failures == 0:
		print("camera console OK")
	return failures


func _fail(message: String) -> int:
	print("  FAIL  %s" % message)
	return 1


func _check_buttons(view: OfficeView3D) -> int:
	var failures := 0
	if not view._console_ready:
		return _fail("console never measured -- no CamPanelScreen or no buttons")
	for key in ["prev", "next"]:
		if not view._buttons.has(key):
			failures += _fail("no %s button on the console" % key)
		elif not view._button_materials.has(key):
			failures += _fail("%s button has no material to light" % key)
	if failures > 0:
		return failures

	# The arrow has to travel with the button it is drawn on, which is what
	# being its child buys -- a glyph left behind in the world would float over
	# a pressed button.
	for key in ["prev", "next"]:
		var glyph := view._find(view._buttons[key], "Cam%sGlyph" % key.capitalize())
		if glyph == null:
			failures += _fail("%s button has no arrow attached to it" % key)

	# Overlapping pick rects would make one button unreachable, and the margin
	# that makes near-misses count is exactly what could cause that.
	var prev: Rect2 = view._button_rect["prev"]
	var next: Rect2 = view._button_rect["next"]
	if prev.intersects(next):
		failures += _fail("the PREV and NEXT pick areas overlap")
	print("  buttons   2, pick areas %.0f x %.0f mm, %.0f mm apart"
		% [prev.size.x * 1000.0, prev.size.y * 1000.0,
			(next.position.x - prev.end.x) * 1000.0])
	return failures


## The screen has to be able to draw the whole facility inside its plan square,
## or the console is showing a cropped building.
func _check_plan(view: OfficeView3D) -> int:
	var failures := 0
	var plan: Rect2 = OfficePanel.PLAN_RECT
	for cam in OfficeConfig.CAMERAS:
		if not OfficeLayout.CAMERA_XZ.has(cam):
			failures += _fail("%s missing from the generated plan" % cam)
			continue
		var at: Vector2 = view._panel._to_plan * (OfficeLayout.CAMERA_XZ[cam] as Vector2)
		if not plan.has_point(at):
			failures += _fail("%s draws at %s, outside the plan square %s" % [cam, at, plan])
	# Uniform scale, or the facility is drawn a shape it is not.
	var t: Transform2D = view._panel._to_plan
	if absf(t.x.x - t.y.y) > 0.0001:
		failures += _fail("plan is drawn at %.4f x %.4f px/m, not one scale" % [t.x.x, t.y.y])
	print("  plan      all %d cameras inside the square at %.2f px/m"
		% [OfficeConfig.CAMERAS.size(), t.x.x])
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


## Sweep the cursor over the whole viewport and see how much of it each button
## answers to.
##
## Not a geometric check: seated, the cursor sets the head's yaw and pitch AND
## the aiming ray, so moving toward a button also turns away from it. Whether
## that loop leaves a button comfortably reachable is only answerable by
## driving it.
func _check_reach(view: OfficeView3D) -> int:
	var walker: OfficeWalker = view._walker
	var rect := Vector2(view._viewport.size)
	var hits := {}
	for iy in SWEEP.y:
		for ix in SWEEP.x:
			var point := Vector2(
				(ix + 0.5) / SWEEP.x * rect.x, (iy + 0.5) / SWEEP.y * rect.y)
			walker.aim_seated(point, rect)
			var key := view._pick(point)
			if key == "":
				continue
			hits[key] = Rect2(point, Vector2.ZERO) if not hits.has(key) \
				else (hits[key] as Rect2).expand(point)
	walker.aim_seated(rect * 0.5, rect)

	var failures := 0
	var smallest := INF
	var smallest_cam := ""
	for name in view._keys:
		var tag := "ctrl:%s" % name
		if not hits.has(tag):
			failures += _fail("the %s key cannot be aimed at from the seat" % name)
	print("  keys      %d desk controls, all reachable" % view._keys.size())

	for key in ["prev", "next"]:
		# The narrow side of the cursor box a button answers to, in the
		# project's 480 x 270 base pixels. That is the number a hand has to
		# hit; an AREA hides a region that is wide but one pixel tall.
		var narrow := 0.0
		if hits.has(key):
			var box: Rect2 = hits[key]
			narrow = minf(box.size.x, box.size.y)
		if narrow <= 0.0:
			failures += _fail("%s cannot be aimed at from the seat" % key)
		elif narrow < smallest:
			smallest = narrow
			smallest_cam = key
	# Ten base pixels is twenty on the default 960 x 540 window, and more on
	# anything larger, since the stretch scales the cursor with it. The floor
	# plan this replaced managed 17 across its tightest cap -- but that was the
	# BEST of eleven, and it was the small one you had to pick out of a crowd.
	if smallest < 10.0:
		failures += _fail("%s answers to only %.1f base px of cursor travel"
			% [smallest_cam, smallest])
	print("  reach     both buttons reachable, tighter is %s at %.1f base px across"
		% [smallest_cam, smallest])
	return failures


## NEXT must walk the whole bank and come back, and PREV must undo it. Two
## buttons are only acceptable if they actually reach everything.
func _check_cycle(view: OfficeView3D, sim: OfficeSimulation) -> int:
	var failures := 0
	var order: Array = []
	sim.select_camera(OfficeConfig.CAMERAS[0])
	for i in OfficeConfig.CAMERAS.size():
		order.append(sim.current_camera)
		view._step(1)
	if sim.current_camera != OfficeConfig.CAMERAS[0]:
		failures += _fail("NEXT %d times ended on %s, not back at the start"
			% [OfficeConfig.CAMERAS.size(), sim.current_camera])
	for cam in OfficeConfig.CAMERAS:
		if not order.has(cam):
			failures += _fail("NEXT never reaches %s" % cam)
	view._step(-1)
	if sim.current_camera != OfficeConfig.CAMERAS[OfficeConfig.CAMERAS.size() - 1]:
		failures += _fail("PREV from the first camera landed on %s, not the last"
			% sim.current_camera)

	# The screen names what the buttons will do. If it can promise a camera the
	# button does not go to, the labels are worse than no labels.
	sim.select_camera("cam5")
	view._panel.simulation = sim
	var promised_next: String = view._panel.neighbour(1)
	view._step(1)
	if sim.current_camera != promised_next:
		failures += _fail("screen promised NEXT would reach %s, button went to %s"
			% [promised_next, sim.current_camera])

	await _frame()
	if view._feed != null and view._feed._current != sim.current_camera:
		failures += _fail("feed is showing %s while the console says %s"
			% [view._feed._current, sim.current_camera])

	# A console that keeps cycling through a blackout is lying about a system
	# that is down.
	sim.select_camera("cam1")
	sim.blackout_timer = 3.0
	view._step(1)
	if sim.current_camera != "cam1":
		failures += _fail("console cycled during a blackout")
	sim.blackout_timer = 0.0
	print("  cycle     NEXT walks all %d and wraps, PREV reverses, refused during blackout"
		% OfficeConfig.CAMERAS.size())
	return failures
