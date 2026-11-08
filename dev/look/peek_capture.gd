extends Node

## Corner peek clip (HunterPeek) in the real HunterView3D, on the hunter_peek validator's L corridor: east along row 5,
## turning south at x = 10. Left: the runner's eye down the hall (the scare beat: her head and shoulders round the edge).
## Right: overhead, the body stays behind the corner. The runner is hidden while she settles and looks, then steps into
## view; Dovelle bursts into the chase. Writes OUT_DIR/frame_0000.png ... at 30 fps (stitch with ffmpeg).
##   godot --path . res://dev/look/peek_capture.tscn -- OUT_DIR [hunter_id]

const Corridor := preload("res://tests/validate_hunter_peek.gd").Corridor
const TILE := Vector2i(480, 360)
const FPS := 30.0
const SECONDS := 9.0
const RUNNER := Vector2(10.5, 11.0)
const WALL_H := 3.0

var _out := "user://peek_frames"
var _hunter := "dovelle"
var _field
var _view: HunterView3D
var _eye: SubViewport
var _top: SubViewport
var _frame := 0
var _clock := 0.0
var _revealed_at := -1.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_hunter = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	Engine.max_fps = 0
	_field = Corridor.new()
	_eye = _viewport()
	_top = _viewport()
	_top.world_3d = _eye.world_3d
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.05, .05, .07)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.55, .55, .62)
	_eye.add_child(env)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(10.5, 2.6, 7.0)
	lamp.omni_range = 9.0
	lamp.light_energy = 1.6
	_eye.add_child(lamp)
	var hall_lamp := OmniLight3D.new()
	hall_lamp.position = Vector3(6.0, 2.6, 5.5)
	hall_lamp.omni_range = 7.0
	_eye.add_child(hall_lamp)
	_box(Vector3(0, -.2, 0), Vector3(20, .2, 20), Color(.32, .3, .3))
	for x in range(0, 14):
		for y in range(2, 17):
			if not _field.is_floor(x + .5, y + .5):
				_box(Vector3(x, 0, y), Vector3(1, WALL_H, 1), Color(.52, .5, .46))
	var brain := HunterBrain.new(Vector2(4.5, 5.5), "PEEK-CAPTURE", _hunter, "standard")
	brain.activate_at(Vector2(10.5, 14.5))
	brain.peek_chance_override = 1.0
	_view = HunterView3D.new()
	_view.brain = brain
	_eye.add_child(_view)
	var eye_cam := Camera3D.new()
	eye_cam.fov = 38.0
	eye_cam.position = Vector3(RUNNER.x, 1.55, RUNNER.y + .6)
	_eye.add_child(eye_cam)
	eye_cam.look_at(Vector3(10.3, 1.4, 5.5), Vector3.UP)
	eye_cam.current = true
	var top_cam := Camera3D.new()
	top_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	top_cam.size = 7.0
	top_cam.position = Vector3(8.5, 12.0, 7.5)
	top_cam.rotation_degrees = Vector3(-90, 0, 0)
	_top.add_child(top_cam)
	top_cam.current = true


func _viewport() -> SubViewport:
	var sub := SubViewport.new()
	sub.size = TILE
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sub)
	return sub


func _box(origin: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
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
	_eye.add_child(mesh)


func _process(_delta: float) -> void:
	var step := 1.0 / FPS
	_clock += step
	var brain := _view.brain
	# Hidden while she settles and looks; out in the hall 0.7 s into the look.
	if _revealed_at < 0.0 and brain.peeking_out() and brain.peek_phase == HunterBrain.Peek.LOOK and brain.peek_timer < 1.0:
		_revealed_at = _clock
	var hidden := _revealed_at < 0.0
	var target := {"peer_id": 1, "position": RUNNER, "hidden": hidden, "in_safe_zone": false, "noise": 0.0,
		"flashlight_on": true, "sprinting": false, "facing": Vector2(0, -1), "lamp_charge": 100.0, "meters": null,
		"heater_unfrozen": false, "heater_powered": false}
	brain.update(step, _field, target, 1, 0)
	_view.set_look_target(RUNNER if not hidden else null)
	_view.sync_from_brain()
	if _clock < .2:
		return
	await RenderingServer.frame_post_draw
	var frame := Image.create(TILE.x * 2, TILE.y, false, Image.FORMAT_RGB8)
	for i in 2:
		var image := (_eye if i == 0 else _top).get_texture().get_image()
		image.convert(Image.FORMAT_RGB8)
		frame.blit_rect(image, Rect2i(Vector2i.ZERO, TILE), Vector2i(i * TILE.x, 0))
	frame.save_png("%s/frame_%04d.png" % [_out, _frame])
	_frame += 1
	if _frame % 30 == 0:
		print("t=%.1f state=%d phase=%d peeking=%s pos=%s" % [_clock, brain.state, brain.peek_phase, brain.peeking_out(), brain.position])
	if _clock >= SECONDS or (brain.state == HunterBrain.State.CHASE and brain.position.distance_to(RUNNER) < 1.2):
		print("frames ", _frame)
		get_tree().quit()
