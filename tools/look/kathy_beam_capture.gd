extends Node

## Kathy's eye beam in a dark hallway, chasing (red): a runner's view from down the hall, and from inside the beam
## 2 m from her eye, looking back up it (the blow-out check). Writes OUT_PREFIX_hall.png and OUT_PREFIX_inside.png.
##   godot --path . res://tools/look/kathy_beam_capture.tscn -- OUT_PREFIX

const SIZE := Vector2i(960, 540)
const KATHY := Vector2(5.5, 3.0)

var _prefix := "user://kathy_beam"
var _view: HunterView3D
var _camera: Camera3D
var _clock := 0.0
var _shot := 0


func _ready() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		_prefix = OS.get_cmdline_user_args()[0]
	get_window().size = SIZE
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.01, .01, .015)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.07, .07, .09)
	add_child(env)
	_box(Vector3(3.5, -.2, 0), Vector3(4, .2, 24), Color(.32, .3, .3))      # floor
	_box(Vector3(3.5, 3.0, 0), Vector3(4, .2, 24), Color(.25, .25, .27))    # ceiling
	_box(Vector3(3.3, 0, 0), Vector3(.2, 3, 24), Color(.42, .4, .38))       # walls
	_box(Vector3(7.5, 0, 0), Vector3(.2, 3, 24), Color(.42, .4, .38))
	var brain := HunterBrain.new(KATHY, "KATHY-BEAM", "kathy", "standard")
	brain.activate_at(KATHY)
	brain.state = HunterBrain.State.CHASE
	brain.direct_chase_visible = true
	brain.facing = Vector2(0, 1)
	_view = HunterView3D.new()
	_view.brain = brain
	add_child(_view)
	_camera = Camera3D.new()
	_camera.fov = 70.0
	add_child(_camera)
	_camera.current = true
	_place(9.0)


func _box(origin: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box.material = material
	mesh.mesh = box
	mesh.position = origin + size * .5
	add_child(mesh)


## The runner `distance` m down the hall in front of her, at eye height, looking at her face.
func _place(distance: float) -> void:
	_camera.position = Vector3(KATHY.x, 1.45, KATHY.y + distance)
	_camera.look_at(Vector3(KATHY.x, 1.6, KATHY.y), Vector3.UP)
	_view.set_look_target(Vector2(KATHY.x, KATHY.y + distance))


func _process(delta: float) -> void:
	_clock += delta
	_view.sync_from_brain()
	if _clock < 1.5:
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s_%s.png" % [_prefix, "hall" if _shot == 0 else "inside"])
	_shot += 1
	_clock = 0.0
	if _shot == 1:
		# inside the beam: on its axis 2 m out from her eye, looking back up it
		var beam: SpotLight3D = _view._kathy_beam
		var axis := -beam.global_basis.z
		_camera.global_position = beam.global_position + axis * 2.0
		_camera.look_at(beam.global_position, Vector3.UP if absf(axis.y) < .95 else Vector3.FORWARD)
	else:
		print("saved ", _prefix)
		get_tree().quit()
