class_name OfficeView3D
extends SubViewportContainer

## The office rendered in 3D, as a drop-in replacement for OfficeView.
##
## It is a SubViewportContainer -- a Control -- so it occupies exactly the same
## slot in the scene tree as the 2D view, and main_office.gd drives it through
## the same single property, `can_move`. Everything else in scenes/office.tscn
## (the HUD, the control bar, the camera monitor) is untouched, and
## scenes/office.tscn itself stays as the 2D fallback.
##
## The camera is a FIXED SEAT: it never translates, only looks. That is the
## Office Mode premise -- you cannot walk away from the desk.
##
## Look is driven by MOUSE POSITION, not captured relative motion. Capturing
## the mouse would make the control-bar buttons unclickable, and position-driven
## looking is what the 2D view already does when it pans toward a screen edge,
## so the feel carries over.
##
## The room model is art/props-3d/office/office_room.glb. Parts are found BY
## NAME -- LeftDoor, RightDoor, DeskLamp, MonitorScreen -- which is why the exporter
## preserves group names; see scripts/validate_office_rooms.gd.

const ROOM_SCENE := "res://art/props-3d/office/office_room.glb"

## Seat position in the room, in metres. The office is 6 x 5 m with the desk
## against the +Z wall spanning z 1.0-2.15, so the seat sits BEHIND it at 2.28
## -- the desk and its monitor are then in front of you and the doorways are
## forward-left and forward-right, which is the whole framing of the mode.
## At 1.85 the camera was inside the desk.
const SEAT := Vector3(0.0, 1.40, 2.28)

## How far the head may turn. +/-75 deg reaches both doorways (each about 56
## deg off centre from the seat) with room to spare, without letting the player
## spin round to the blank wall behind.
const YAW_LIMIT := 75.0
const PITCH_LIMIT := 28.0
## Lower is smoother. Matches OfficeView's SCROLL_SMOOTHING so both views ease
## at the same rate.
const LOOK_SMOOTHING := 12.0

## Set false while the monitor is up -- you cannot look around the office with
## a tablet in your face. Same contract as OfficeView.can_move.
var can_move := true

## Assigned by main_office.gd, exactly as it assigns monitor.simulation.
var simulation: OfficeSimulation

var _camera: Camera3D
var _room: Node3D
var _lamp_light: OmniLight3D
var _ceiling_light: OmniLight3D
var _left_door: Node3D
var _right_door: Node3D
var _monitor_face: MeshInstance3D
var _feed: OfficeFeed
var _feed_material: StandardMaterial3D
var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	stretch = true
	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	viewport.handle_input_locally = false
	# The room art is pixel-art at 12 texels/metre; smoothing the render would
	# undo the nearest-neighbour filtering the models were exported with.
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	add_child(viewport)

	var world := Node3D.new()
	world.name = "World"
	viewport.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.012, 0.016, 0.022)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.28, 0.32, 0.38)
	e.ambient_light_energy = 0.18
	env.environment = e
	world.add_child(env)

	var packed: PackedScene = load(ROOM_SCENE)
	if packed != null:
		_room = packed.instantiate()
		world.add_child(_room)
		_left_door = _find(_room, "LeftDoor") as Node3D
		_right_door = _find(_room, "RightDoor") as Node3D
		# "MonitorScreen" is the GROUP; the exporter emits one node per group,
		# so the cube name "MonitorFace" is not a node and never resolved.
		_monitor_face = _find(_room, "MonitorScreen") as MeshInstance3D
		_attach_lamp()
	else:
		push_warning("OfficeView3D: could not load %s" % ROOM_SCENE)

	_build_feed()

	_ceiling_light = OmniLight3D.new()
	_ceiling_light.position = Vector3(0.0, 2.7, 0.6)
	_ceiling_light.omni_range = 9.0
	_ceiling_light.light_energy = 0.55
	_ceiling_light.light_color = Color(0.62, 0.72, 0.78)
	world.add_child(_ceiling_light)

	_camera = Camera3D.new()
	_camera.position = SEAT
	_camera.fov = 72.0
	_camera.current = true
	world.add_child(_camera)
	_apply_look()


## Depth-first by name. The exporter emits a "<name>-colonly" sibling for
## collision, and Godot names the body it builds from that after the node MINUS
## the suffix -- so it shares its parent's name. First match wins, which is the
## visual node, not the collider sitting at local origin.
func _find(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child in node.get_children():
		var found := _find(child, wanted)
		if found != null:
			return found
	return null


func _attach_lamp() -> void:
	var lamp := _find(_room, "DeskLamp")
	_lamp_light = OmniLight3D.new()
	_lamp_light.position = Vector3(0.79, 1.26, 1.44)
	_lamp_light.omni_range = 3.4
	_lamp_light.light_color = Color(0.98, 0.86, 0.55)
	_lamp_light.light_energy = 0.0
	if lamp is Node3D:
		(lamp as Node3D).add_child(_lamp_light)
		_lamp_light.position = Vector3(0.0, 0.0, 0.0)
		_lamp_light.global_position = Vector3(0.79, 1.26, 1.44)
	else:
		_room.add_child(_lamp_light)


## The desk screen shows a LIVE 3D feed, not a texture: a SubViewport renders
## the selected camera's room and its ViewportTexture is the screen material.
## Unshaded, so the office's own dim lighting does not darken a CRT that is
## supposed to be emitting.
func _build_feed() -> void:
	if _monitor_face == null:
		return
	_feed = OfficeFeed.new()
	add_child(_feed)
	_feed_material = StandardMaterial3D.new()
	_feed_material.albedo_texture = _feed.get_texture()
	_feed_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_feed_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_monitor_face.material_override = _feed_material


func _process(delta: float) -> void:
	_update_look(delta)
	_reflect_simulation()


func _update_look(delta: float) -> void:
	if can_move:
		var rect := get_viewport_rect().size
		if rect.x > 0.0 and rect.y > 0.0:
			var mouse := get_viewport().get_mouse_position()
			# -1 .. 1 across the screen, so the edges are full deflection.
			var nx := clampf((mouse.x / rect.x) * 2.0 - 1.0, -1.0, 1.0)
			var ny := clampf((mouse.y / rect.y) * 2.0 - 1.0, -1.0, 1.0)
			_yaw = -nx * YAW_LIMIT
			_pitch = -ny * PITCH_LIMIT
	if _camera == null:
		return
	var target := Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0.0)
	_camera.rotation = _camera.rotation.lerp(target, clampf(LOOK_SMOOTHING * delta, 0.0, 1.0))


func _apply_look() -> void:
	if _camera != null:
		_camera.rotation = Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0.0)


## Everything here READS the simulation; nothing writes to it. The sim stays
## authoritative, exactly as it is for the 2D view.
func _reflect_simulation() -> void:
	if simulation == null:
		return

	# Doors are modelled full-height with their pivot at the TOP of the
	# opening, so closing is a Y scale of 0 -> 1: a shutter rolling down.
	_set_door(_left_door, simulation.left_door)
	_set_door(_right_door, simulation.right_door)

	var blacked_out := simulation.blackout_timer > 0.0
	if _lamp_light != null:
		var want := 1.5 if (simulation.desk_light and not blacked_out) else 0.0
		_lamp_light.light_energy = lerpf(_lamp_light.light_energy, want, 0.25)
	if _ceiling_light != null:
		_ceiling_light.light_energy = 0.0 if blacked_out else 0.55
	if _feed != null:
		_feed.select(simulation.current_camera)
	if _feed_material != null:
		# A dead feed is a dark screen, not a hidden one -- the CRT is still
		# physically there. Corrupted reads red, matching the 2D monitor.
		var tint := Color(1, 1, 1)
		if blacked_out:
			tint = Color(0.05, 0.05, 0.06)
		elif simulation.corrupted_cameras.has(simulation.current_camera):
			tint = Color(0.9, 0.35, 0.35)
		_feed_material.albedo_color = _feed_material.albedo_color.lerp(tint, 0.2)


func _set_door(door: Node3D, closed: bool) -> void:
	if door == null:
		return
	var want := 1.0 if closed else 0.0
	door.scale.y = lerpf(door.scale.y, want, 0.2)


## Kept for parity with OfficeView so either view satisfies the same surface.
## 0.0 centred, -1.0 fully left, 1.0 fully right.
func pan_ratio() -> float:
	return _yaw / -YAW_LIMIT if YAW_LIMIT > 0.0 else 0.0
