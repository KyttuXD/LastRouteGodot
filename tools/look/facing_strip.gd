extends Node

## Corner filmstrip: a hunter walks a straight leg and turns a right-angle corner along an A* style route; one frame every
## STRIP_STEP seconds from a high 3/4 camera, laid side by side. The head should swing toward the corner before the body.
##   godot --path . res://tools/look/facing_strip.tscn -- OUT.png
## Env: HUNTERS (id), OLD=1 pins the old behaviour (body follows brain.facing = leg tangent, no head look) for the "before" strip.

const SPEED := 3.0
const ROUTE := [Vector2(0, 6), Vector2(0, 0), Vector2(6, 0)]
const FRAMES := 8
const STRIP_STEP := .45

var _view: HunterView3D
var _cells: Array = []
var _leg := 0
var _shots: Array = []
var _clock := 0.0
var _next_shot := 1.2
var _out := "/tmp/facing_strip.png"


func _ready() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		_out = OS.get_cmdline_user_args()[0]
	var id := OS.get_environment("HUNTERS") if OS.get_environment("HUNTERS") != "" else "dovelle"
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.12, .1, .14)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.7, .65, .7)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(20, .1, 20)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(3, -.05, 3)
	add_child(floor_mesh)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = plane.size
	shape.shape = box
	body.add_child(shape)
	floor_mesh.add_child(body)
	# brain y maps to world z
	var brain := HunterBrain.new(ROUTE[0], "FACING-STRIP", id, "standard")
	brain.activate_at(ROUTE[0])
	brain.state = HunterBrain.State.WANDER
	_view = HunterView3D.new()
	_view.brain = brain
	add_child(_view)
	_view._facing.scan_scale = 0.0
	var cam := Camera3D.new()
	cam.position = Vector3(5.6, 4.2, 5.6)
	cam.look_at_from_position(cam.position, Vector3(.9, .9, .9))
	cam.fov = 42.0
	add_child(cam)
	cam.current = true
	for i in ROUTE.size() - 1:
		var from: Vector2 = ROUTE[i]
		var to: Vector2 = ROUTE[i + 1]
		for s in range(1, int(from.distance_to(to)) + 1):
			var point := from.lerp(to, float(s) / int(from.distance_to(to)))
			_cells.append(Vector2i(floori(point.x), floori(point.y)))


func _process(delta: float) -> void:
	_clock += delta
	var brain := _view.brain
	if _leg < ROUTE.size() - 1:
		var to: Vector2 = ROUTE[_leg + 1]
		var tangent: Vector2 = (to - ROUTE[_leg]).normalized()
		# hold the first second still so the model finishes building
		if _clock > 1.0:
			brain.position += (to - brain.position).normalized() * minf(SPEED * delta, brain.position.distance_to(to))
		while not _cells.is_empty() and brain.position.distance_to(Vector2(_cells[0]) + Vector2(.5, .5)) < .6:
			_cells.pop_front()
		brain._path = _cells.duplicate()
		brain.facing = tangent
		if brain.position.distance_to(to) < .05:
			_leg += 1
	_view.sync_from_brain()
	if OS.get_environment("OLD") != "":
		_view._facing.weight = 0.0
	if _clock >= _next_shot and _shots.size() < FRAMES:
		_next_shot += STRIP_STEP
		_shots.append(get_viewport().get_texture().get_image())
	if _shots.size() >= FRAMES:
		var w: int = _shots[0].get_width() / 2
		var h: int = _shots[0].get_height() / 2
		var sheet := Image.create(w * 4, h * 2, false, Image.FORMAT_RGB8)
		for i in FRAMES:
			var img: Image = _shots[i]
			img.convert(Image.FORMAT_RGB8)
			img.resize(w, h, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % 4) * w, (i / 4) * h))
		sheet.save_png(_out)
		print("saved ", _out)
		get_tree().quit()
