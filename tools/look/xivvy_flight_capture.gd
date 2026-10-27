extends Node

## Xivvy's flying chase in the real HunterView3D: a straight run past a corner with a runner stand-in ahead; side view and chase-cam
## filmstrips (take-off, cruise, bank, swoop, landing).
##   godot --path . res://tools/look/xivvy_flight_capture.tscn -- OUT_PREFIX     (OUT_PREFIX_side.png, OUT_PREFIX_chase.png)
## Env: CEILING=3.1 puts a ceiling that high over the run (indoors); default is open sky.

const FRAMES := 8
const TILE := Vector2i(420, 300)

var _view: HunterView3D
var _cam_side: Camera3D
var _cam_chase: Camera3D
var _sub: SubViewport
var _clock := 0.0
var _shots: Dictionary = {"side": [], "chase": []}
var _next := 0.5
var _prefix := "user://xivvy"
var _runner: MeshInstance3D
var _angle := 0.0
var _pos := Vector2(0, 0)
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
	env.environment.ambient_light_color = Color(.8, .78, .85)
	_sub.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	_sub.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(80, .2, 80)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0, -.1, 0)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = plane.size
	shape.shape = box
	floor_body.add_child(shape)
	floor_mesh.add_child(floor_body)
	_sub.add_child(floor_mesh)
	if OS.get_environment("CEILING") != "":
		var ceil_mesh := MeshInstance3D.new()
		var slab := BoxMesh.new()
		slab.size = Vector3(80, .2, 6)
		ceil_mesh.mesh = slab
		ceil_mesh.position = Vector3(0, float(OS.get_environment("CEILING")) + .1, 0)
		var ceil_body := StaticBody3D.new()
		var ceil_shape := CollisionShape3D.new()
		var ceil_box := BoxShape3D.new()
		ceil_box.size = slab.size
		ceil_shape.shape = ceil_box
		ceil_body.add_child(ceil_shape)
		ceil_mesh.add_child(ceil_body)
		_sub.add_child(ceil_mesh)
	var brain := HunterBrain.new(Vector2(-10, 0), "XIVVY-CAPTURE", "xivvy", "standard")
	brain.activate_at(brain.position)
	brain.state = HunterBrain.State.CHASE
	_view = HunterView3D.new()
	_view.brain = brain
	_sub.add_child(_view)
	_runner = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = .3
	capsule.height = 1.7
	_runner.mesh = capsule
	_runner.position.y = .85
	_sub.add_child(_runner)
	_cam_side = Camera3D.new()
	_cam_side.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam_side.size = 6.6
	_sub.add_child(_cam_side)
	_cam_chase = Camera3D.new()
	_cam_chase.fov = 70.0
	_sub.add_child(_cam_chase)
	_pos = brain.position


func _process(delta: float) -> void:
	_clock += delta
	var brain := _view.brain
	var xivvy := brain.gimmick as XivvyGimmick
	# 0-1.2 s: ground run, 1.2 s: take-off, then a gentle left turn, at 5.2 s she is on the runner (swoop), at 7.4 s she lands
	var flying := _clock > 1.2 and _clock < 7.4
	xivvy.flying = flying
	if _clock > 3.2 and _clock < 5.4:
		_angle += delta * 0.6
	var heading := Vector2(cos(_angle), sin(_angle))
	_pos += heading * 5.0 * delta
	brain.position = _pos
	brain.facing = heading
	var runner_xz := _pos + heading * (14.0 - clampf(_clock - 2.0, 0.0, 5.0) * 2.4)
	_runner.position = Vector3(runner_xz.x, .85, runner_xz.y)
	_view.set_look_target(runner_xz)
	_view.sync_from_brain()
	if int(_clock * 4.0) != int((_clock - delta) * 4.0):
		print("t=%.2f flying=%s altitude=%.2f headroom=%s y=%.2f speed=%.2f" % [_clock, flying, _view._flight.altitude, str(_view._flight_headroom), _view.global_position.y, _view._move_speed])
	var center := Vector3(_view.global_position.x, 2.0, _view.global_position.z)
	_cam_side.position = center + Vector3(0, 0, 9)
	_cam_side.look_at(center, Vector3.UP)
	var behind := Vector3(-heading.x, 0, -heading.y) * 4.2
	_cam_chase.position = _view.global_position + behind + Vector3(0, 2.2, 0)
	_cam_chase.look_at(_view.global_position + Vector3(heading.x, 0, heading.y) * 3.0 + Vector3(0, 1.0, 0), Vector3.UP)
	if _clock >= _next and not _busy and _shots["side"].size() < FRAMES:
		_busy = true
		_next += .95
		await _grab("side", _cam_side)
		await _grab("chase", _cam_chase)
		_busy = false
	if _shots["chase"].size() >= FRAMES:
		for view_name in ["side", "chase"]:
			var sheet := Image.create(4 * TILE.x, 2 * TILE.y, false, Image.FORMAT_RGB8)
			for i in FRAMES:
				sheet.blit_rect(_shots[view_name][i], Rect2i(Vector2i.ZERO, TILE), Vector2i((i % 4) * TILE.x, (i / 4) * TILE.y))
			sheet.save_png("%s_%s.png" % [_prefix, view_name])
		print("saved ", _prefix)
		set_process(false)
		get_tree().quit()


func _grab(view_name: String, camera: Camera3D) -> void:
	camera.current = true
	await get_tree().process_frame
	await get_tree().process_frame
	var image := _sub.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	_shots[view_name].append(image)
