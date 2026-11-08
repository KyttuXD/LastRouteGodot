extends Node

## Locker inspection (HunterInspect) seen by the hider: the camera sits where a hidden runner's eyes are, inside a real
## locker, looking out through its slats. Nyxie walks past, stops, turns, bends in to the slats, lingers (her breath),
## straightens and walks on. Record with the Movie Maker so the breath is in the clip:
##   godot --path . --write-movie OUT.avi --fixed-fps 30 --resolution 960x540 res://dev/look/locker_inspect_capture.tscn -- [hunter_id] [side]
## Any route hunter (default dovelle); nyxie plays her easter egg (closer, two breaths) with her darkness gimmick
## detached (it would pin her to a chase). "side" films the lean from beside the locker instead.

const Hall := preload("res://tests/validate_locker_inspect.gd").Hall
const SPOT := Vector2(10.5, 10.5)
const DOOR := Vector2(1, 0)
const WALK_X := 12.5
const STEP := 1.0 / 30.0

var _field
var _view: HunterView3D
var _clock := 0.0
var _started := false
var _ended_at := -1.0


func _ready() -> void:
	_field = Hall.new(Vector2i(10, 10), Vector2i(1, 0))
	var args := OS.get_cmdline_user_args()
	var hunter_id := "dovelle"
	for arg in args:
		if arg not in ["side", "front"]:
			hunter_id = arg
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.03, .03, .04)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.32, .32, .38)
	add_child(env)
	# faint hallway light behind her (on the far wall's side), so at the slats she is a silhouette with a lit edge
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(13.9, 2.4, 10.5)
	lamp.omni_range = 4.5
	lamp.light_energy = .9
	lamp.light_color = Color("#ffcf9a")
	add_child(lamp)
	var hall := OmniLight3D.new()
	hall.position = Vector3(13.6, 2.6, 4.0)
	hall.omni_range = 7.0
	hall.light_energy = .5
	hall.light_color = Color("#ffd9b0")
	add_child(hall)
	_box(Vector3(4, -.2, 1), Vector3(12, .2, 19), Color(.3, .29, .3))
	_box(Vector3(14.2, 0, 1), Vector3(.3, 3, 19), Color(.48, .46, .43))     # the hall's far wall
	_box(Vector3(9.1, 0, 1), Vector3(.3, 3, 19), Color(.36, .34, .33))      # the wall the lockers stand in
	var locker := RouteInteractable3D.new()
	locker.kind = RouteInteractable3D.Kind.HIDING_SPOT
	locker.source_cell = Vector2i(10, 10)
	locker.position = Vector3(SPOT.x, .04, SPOT.y)
	locker.rotation.y = -PI * .5   # door out along +X (HunterInspect.door_direction)
	add_child(locker)
	var brain := HunterBrain.new(Vector2(WALK_X, 3.5), "INSPECT-CAPTURE", hunter_id, "standard")
	if hunter_id == "nyxie":
		brain.gimmick = null
	brain.activate_at(brain.position)
	brain.state = HunterBrain.State.WANDER
	brain.wander_target = Vector2(WALK_X, 18.0)
	brain.has_wander_target = true
	_view = HunterView3D.new()
	_view.brain = brain
	add_child(_view)
	var camera := Camera3D.new()
	camera.fov = 62.0
	camera.near = .03
	add_child(camera)
	# the hider's real eye: right behind the vent band, at its height, with the hider's own view of the locker
	locker.set_local_hiding_view(true)
	var inside := locker.hiding_inside_position()
	camera.global_position = inside + Vector3(0, locker.hiding_eye_height(), 0)
	camera.look_at(camera.global_position + Vector3(1, 0, 0), Vector3.UP)
	camera.fov = 75.0
	if "side" in OS.get_cmdline_user_args():   # a side view of the lean (and the outside of the locker, as others see it)
		locker.set_local_hiding_view(false)
		camera.global_position = Vector3(11.6, 1.3, 13.6)
		camera.look_at(Vector3(11.4, 1.1, 10.5), Vector3.UP)
	if "front" in OS.get_cmdline_user_args():   # the locker's door as everyone else sees it
		locker.set_local_hiding_view(false)
		camera.global_position = Vector3(12.0, 1.6, 10.9)
		camera.look_at(Vector3(10.6, 1.4, 10.5), Vector3.UP)
	camera.current = true


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


func _process(_delta: float) -> void:
	_clock += STEP
	var brain := _view.brain
	var hider := {"peer_id": 1, "position": SPOT, "hidden": true, "hiding_spot": Vector2i(10, 10), "in_safe_zone": false,
		"noise": 0.0, "flashlight_on": false, "sprinting": false, "facing": DOOR, "lamp_charge": 100.0, "meters": null,
		"heater_unfrozen": false, "heater_powered": false}
	if not _started and HunterInspect.qualifies(brain, SPOT, false) and brain.position.y > SPOT.y - 1.0:
		_started = brain.start_inspect(SPOT, DOOR, _field)   # the route rolls dice here (HunterBrain.maybe_inspect); the clip always inspects
	brain.update(STEP, _field, hider, 1, 0)
	_view.set_look_target(SPOT)
	_view.sync_from_brain()
	if _started and _ended_at < 0.0 and brain.state != HunterBrain.State.INSPECT:
		_ended_at = _clock
	if (_ended_at > 0.0 and _clock > _ended_at + 2.0) or _clock > 24.0:
		print("done t=%.1f inspections=%d" % [_clock, brain.inspections])
		get_tree().quit()
