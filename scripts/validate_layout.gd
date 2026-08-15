extends RefCounted

## Headless check that the UI survives the screen it is put on.
##
## Everything 2D is authored against a 480 x 270 design size, and the project
## stretches that with aspect "expand" -- so a window that is not 16:9 does not
## get black bars, it gets MORE viewport. That is only an improvement if the
## layout is anchored: a HUD pinned by absolute offsets in a 480 x 270 grid
## drifts into the middle of a wider screen and leaves the corners empty, which
## is exactly what these scenes used to do.
##
## Anchors are invisible in a screenshot at the design size, because that is
## the one size where right and wrong agree. This drives the window through
## five real aspect ratios instead and compares.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- layout

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


const SIZES := [
	Vector2i(1920, 1080),   # 16:9, the design aspect
	Vector2i(1920, 1200),   # 16:10
	Vector2i(2560, 1080),   # 21:9 ultrawide
	Vector2i(1024, 768),    # 4:3
	Vector2i(1366, 768),    # a small laptop, below two design sizes
]

## scene -> node -> which edges it must stay glued to.
const ANCHORED := {
	"res://scenes/hud.tscn": {
		"ObjectivePanel": ["left", "bottom"],
		"MetersPanel": ["left", "right", "bottom"],
		"ControlsLabel": ["left", "top"],
		"InteractionLabel": ["hcentre", "bottom"],
		"MessageLabel": ["hcentre", "top"],
		"MapOverlay": ["hcentre", "vcentre"],
		"EscapeOverlay": ["hcentre", "vcentre"],
	},
	"res://scenes/main_menu.tscn": {
		"TitleLabel": ["hcentre", "vcentre"],
		"ButtonPanel": ["hcentre", "vcentre"],
		"SettingsOverlay": ["hcentre", "vcentre"],
	},
	# Staging is built in code and grows with the room, so it is exactly the
	# screen most likely to push its own start button off the bottom.
	"res://scenes/room_lobby.tscn": {
		"StagingPanel": ["hcentre", "vcentre"],
	},
	"res://scenes/office_3d.tscn": {
		"TopBar": ["left", "right", "top"],
		"SystemsLabel": ["left", "top"],
		"ControlBar": ["hcentre", "bottom"],
		"EventLabel": ["hcentre", "bottom"],
		"OfficeView": ["left", "right", "top", "bottom"],
	},
}

## How much the distance from an anchored edge may vary between viewport
## shapes, in design pixels. Not an absolute margin: elements are deliberately
## inset (the interaction prompt sits 79 px above the bottom), and an inset
## that stays the same on every screen is exactly what correct anchoring looks
## like. What is being caught is a gap that GROWS with the viewport, which is
## an element pinned to the design size instead of to an edge.
const DRIFT_TOLERANCE := 1.5


func run(host: Node) -> int:
	_host = host
	var failures := 0
	for path in ANCHORED:
		failures += await _check_scene(path)
	if failures == 0:
		print("layout OK")
	return failures


func _fail(message: String) -> int:
	print("  FAIL  %s" % message)
	return 1


func _check_scene(path: String) -> int:
	var failures := 0
	var packed: PackedScene = load(path)
	if packed == null:
		return _fail("could not load %s" % path)
	var scene: Node = packed.instantiate()
	_root().add_child(scene)
	await _frame()

	var widest := 0.0
	var gaps := {}          # "node/edge" -> the distances seen across sizes
	for size in SIZES:
		_root().size = size
		# Two frames: one for the window resize, one for the containers inside
		# it to settle against their new anchors.
		await _frame()
		await _frame()
		var view := _root().get_visible_rect()
		widest = maxf(widest, view.size.x)
		for name in ANCHORED[path]:
			var node := scene.find_child(name, true, false)
			if node == null or not node is Control:
				failures += _fail("%s: no Control named %s" % [path, name])
				continue
			failures += _measure(path, size, view, node as Control,
				ANCHORED[path][name], gaps)

	# Siblings must not land on each other. Containment and drift both passed
	# while the menu title sat ON the button panel: title anchored to the top,
	# panel to the centre, so a taller viewport walked them together. Nothing
	# was off-screen and nothing drifted -- they just collided.
	failures += _check_overlaps(scene, path)

	for key in gaps:
		var seen: Array = gaps[key]
		var drift: float = seen.max() - seen.min()
		if drift > DRIFT_TOLERANCE:
			failures += _fail("%s %s drifts %.0f px between viewport shapes -- it is "
				% [path.get_file(), key, drift]
				+ "pinned to the design size, not to that edge")

	_root().size = Vector2i(960, 540)
	scene.queue_free()
	await _frame()
	print("  %-28s %d nodes held across %d aspect ratios, up to %.0f design px wide"
		% [path.get_file(), ANCHORED[path].size(), SIZES.size(), widest])
	return failures


## Every anchored node in a scene, checked pairwise. Text can legitimately sit
## over a backdrop, so full-rect nodes are skipped -- they ARE the backdrop.
func _check_overlaps(scene: Node, path: String) -> int:
	var failures := 0
	var rects := {}
	var view := _root().get_visible_rect()
	for name in ANCHORED[path]:
		var node := scene.find_child(name, true, false) as Control
		if node == null or not node.visible:
			continue
		var rect := Rect2(node.global_position, node.size)
		if rect.size.x >= view.size.x * 0.95 and rect.size.y >= view.size.y * 0.95:
			continue
		rects[name] = rect
	var names: Array = rects.keys()
	names.sort()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: Rect2 = rects[names[i]]
			var b: Rect2 = rects[names[j]]
			var hit := a.intersection(b)
			if hit.size.x > 1.0 and hit.size.y > 1.0:
				failures += _fail("%s %s overlaps %s by %.0f x %.0f px"
					% [path.get_file(), names[i], names[j], hit.size.x, hit.size.y])
	return failures


func _measure(path: String, size: Vector2i, view: Rect2,
		node: Control, edges: Array, gaps: Dictionary) -> int:
	var failures := 0
	var rect := Rect2(node.global_position, node.size)
	var tag := "%s %s @%dx%d" % [path.get_file(), node.name, size.x, size.y]

	# Nothing may run off the screen, whatever it is anchored to. This is what
	# caught the meters row and the office control bar, both of which were
	# wider than the design size and had been overflowing all along.
	if rect.position.x < -1.0 or rect.position.y < -1.0 \
			or rect.end.x > view.size.x + 1.0 or rect.end.y > view.size.y + 1.0:
		failures += _fail("%s spills outside the %s viewport at %s"
			% [tag, view.size, rect])

	for edge in edges:
		var gap := 0.0
		match edge:
			"left": gap = rect.position.x
			"top": gap = rect.position.y
			"right": gap = view.size.x - rect.end.x
			"bottom": gap = view.size.y - rect.end.y
			"hcentre": gap = absf(rect.get_center().x - view.size.x * 0.5)
			"vcentre": gap = absf(rect.get_center().y - view.size.y * 0.5)
		var key := "%s/%s" % [node.name, edge]
		if not gaps.has(key):
			gaps[key] = []
		(gaps[key] as Array).append(gap)
	return failures
