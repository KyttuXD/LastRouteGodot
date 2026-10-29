extends Node

## Xivvy's clearance-driven flying chase in the real HunterView3D: a 4.5 m hall, a 3 m doorway (1.2 m wide), a hall beyond, then a 9 m atrium.
## Side sequence: high cruise -> lands before the door -> walks through -> lifts off in the next room -> climbs in the atrium.
##   godot --path . res://tools/look/xivvy_flight_capture.tscn -- OUT_PREFIX     (OUT_PREFIX_side.png, OUT_PREFIX_chase.png)

const FRAMES := 12
const TILE := Vector2i(420, 300)
const RUN_Z := 5.5
const SPEED := 5.0

var _view: HunterView3D
var _cam_side: Camera3D
var _cam_chase: Camera3D
var _sub: SubViewport
var _clock := 0.0
var _shots: Dictionary = {"side": [], "chase": []}
var _next := .8
var _prefix := "user://xivvy"
var _x := 0.5
var _busy := false


func _ready() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		_prefix = OS.get_cmdline_user_args()[0]
	_sub = SubViewport.new()
	_sub.size = TILE
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sub)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.2, .22, .3)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.85, .82, .9)
	_sub.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	_sub.add_child(sun)
	_box(Vector3(-10, -.2, RUN_Z - 4), Vector3(100, .2, 8), Color(.55, .55, .6))                 # floor
	_box(Vector3(-10, 4.5, RUN_Z - 4), Vector3(30, .2, 8), Color(.4, .4, .5, .35))                # hall ceiling
	_box(Vector3(20, 3.0, RUN_Z - 4), Vector3(2, .2, 8), Color(.7, .35, .3, .7))                  # door lintel
	_box(Vector3(22, 4.5, RUN_Z - 4), Vector3(23, .2, 8), Color(.4, .4, .5, .35))                 # room ceiling
	_box(Vector3(45, 9.0, RUN_Z - 4), Vector3(45, .2, 8), Color(.4, .4, .5, .35))                 # atrium ceiling
	_box(Vector3(20, 0, RUN_Z + .6), Vector3(2, 3.0, .2), Color(.7, .35, .3, .9))                 # door jambs
	_box(Vector3(20, 0, RUN_Z - .8), Vector3(2, 3.0, .2), Color(.7, .35, .3, .9))
	var brain := HunterBrain.new(Vector2(_x, RUN_Z), "XIVVY-CAPTURE", "xivvy", "standard")
	brain.activate_at(brain.position)
	brain.state = HunterBrain.State.CHASE
	_view = HunterView3D.new()
	_view.brain = brain
	_sub.add_child(_view)
	(_view.brain.gimmick as XivvyGimmick).flying = true
	_cam_side = Camera3D.new()
	_cam_side.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam_side.size = 10.5
	_sub.add_child(_cam_side)
	_cam_chase = Camera3D.new()
	_cam_chase.fov = 70.0
	_sub.add_child(_cam_chase)


func _box(origin: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box.material = material
	mesh.mesh = box
	mesh.position = origin + size * .5
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var collider := BoxShape3D.new()
	collider.size = size
	shape.shape = collider
	body.add_child(shape)
	mesh.add_child(body)
	_sub.add_child(mesh)


func _process(delta: float) -> void:
	_clock += delta
	if _clock < .6:
		_view.sync_from_brain()      # let the model and physics settle before she moves
		return
	_x += SPEED * delta
	var brain := _view.brain
	brain.position = Vector2(_x, RUN_Z)
	brain.facing = Vector2(1, 0)
	var cells: Array = []
	for k in 16:
		cells.append(Vector2i(int(floor(_x)) + k, int(floor(RUN_Z))))
	brain._path = cells
	_view.set_look_target(Vector2(_x + 40.0, RUN_Z))
	_view.sync_from_brain()
	var at := _view.global_position
	_cam_side.position = Vector3(_x + 3.0, 4.2, RUN_Z + 14.0)
	_cam_side.look_at(Vector3(_x + 3.0, 4.2, RUN_Z), Vector3.UP)
	_cam_chase.position = at + Vector3(-4.0, 2.4, 0.4)
	_cam_chase.look_at(at + Vector3(3.0, 1.0, 0), Vector3.UP)
	if _clock >= _next and not _busy and _shots["side"].size() < FRAMES:
		_busy = true
		_next += .85
		await _grab("side", _cam_side)
		await _grab("chase", _cam_chase)
		print("x=%.1f altitude=%.2f fly_ok=%s fold=%.2f" % [_x, _view._flight.altitude, str((_view.brain.gimmick as XivvyGimmick).fly_ok), _view._flight.wing_fold])
		_busy = false
	if _shots["chase"].size() >= FRAMES:
		set_process(false)
		for view_name in ["side", "chase"]:
			var sheet := Image.create(3 * TILE.x, 4 * TILE.y, false, Image.FORMAT_RGB8)
			for i in FRAMES:
				sheet.blit_rect(_shots[view_name][i], Rect2i(Vector2i.ZERO, TILE), Vector2i((i % 3) * TILE.x, (i / 3) * TILE.y))
			sheet.save_png("%s_%s.png" % [_prefix, view_name])
		print("saved ", _prefix)
		get_tree().quit()


func _grab(view_name: String, camera: Camera3D) -> void:
	camera.current = true
	await get_tree().process_frame
	await get_tree().process_frame
	var image := _sub.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	_shots[view_name].append(image)
