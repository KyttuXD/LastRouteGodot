class_name OfficeWalker
extends CharacterBody3D

## First-person movement for the walkable office.
##
## Deliberately NOT PlayerController3D. That one belongs to maze mode: it
## requires a sibling ../TopDownCamera, a Flashlight and a BodyVisual, and it
## tracks stamina, lamp charge and noise -- none of which Office Mode has. This
## is the small subset the office actually needs: walk, look, collide.
##
## The mouse is captured while walking and released while seated, because the
## office's control bar is real UI that has to stay clickable. Sitting down is
## therefore not just a camera position, it is the mode in which you can press
## buttons -- which is the same trade the game already makes with the monitor.
## The cursor itself is claimed through MouseLock rather than set here, so a
## pause menu can take it without this fighting for it every frame.

signal seated_changed(seated: bool)

const WALK_SPEED := 2.6
const ACCEL := 12.0
const MOUSE_SENSITIVITY := 0.0022
const PITCH_LIMIT := deg_to_rad(85.0)
## Sitting back down within this distance of the seat.
const SIT_RANGE := 1.1
## Seated look range. Wide enough to reach both doorways (each about 56 deg
## off centre) and to look down at the desk console, without letting the player
## spin round to the blank wall behind.
const SEATED_YAW := 75.0
const SEATED_PITCH := 28.0

@export var seat_position := Vector3(0.0, 1.40, 2.28)
@export var eye_height := 1.62

var seated := true

var _camera: Camera3D
var _pivot: Node3D
var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	# A capsule roughly a person's width, so doorways and the vent read
	# correctly against the authored openings.
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.70
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.85, 0.0)
	add_child(shape)

	_pivot = Node3D.new()
	_pivot.position = Vector3(0.0, eye_height, 0.0)
	add_child(_pivot)
	_camera = Camera3D.new()
	_camera.fov = 72.0
	_camera.current = true
	_pivot.add_child(_camera)

	sit()


func camera() -> Camera3D:
	return _camera


## Return to the desk. The seat is the only place the control bar works, so
## this is also what hands the mouse back to the UI.
func sit() -> void:
	seated = true
	global_position = Vector3(seat_position.x, 0.0, seat_position.z)
	_pivot.position.y = seat_position.y
	velocity = Vector3.ZERO
	MouseLock.set_gameplay_capture(true)
	MouseLock.claim("seated", true)
	seated_changed.emit(true)


func stand() -> void:
	seated = false
	_pivot.position.y = eye_height
	MouseLock.claim("seated", false)
	seated_changed.emit(false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not seated:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - motion.relative.y * MOUSE_SENSITIVITY,
			-PITCH_LIMIT, PITCH_LIMIT)


func _physics_process(delta: float) -> void:
	if seated:
		aim_seated(get_viewport().get_mouse_position(),
			get_viewport().get_visible_rect().size)
		return

	_apply_look()
	# project.godot names the forward/back actions move_up / move_down.
	var input := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down"))
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y))
	dir.y = 0.0
	if dir.length() > 0.01:
		dir = dir.normalized()
	var target := dir * WALK_SPEED
	velocity.x = move_toward(velocity.x, target.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * delta)
	velocity.y = 0.0
	move_and_slide()


## Point the seated head at a screen position, in a viewport of size `rect`.
##
## Seated look is driven by mouse POSITION rather than captured motion, so the
## cursor stays free for the control bar. It is a method rather than inline in
## _physics_process because the head and the desk console's aiming ray are
## driven by the SAME cursor -- turning to look at a button also swings the ray
## -- so anything checking whether a button can be aimed at has to be able to
## reproduce this exactly rather than approximate it.
func aim_seated(mouse: Vector2, rect: Vector2) -> void:
	if rect.x > 0.0 and rect.y > 0.0:
		_yaw = -clampf((mouse.x / rect.x) * 2.0 - 1.0, -1.0, 1.0) * deg_to_rad(SEATED_YAW)
		_pitch = -clampf((mouse.y / rect.y) * 2.0 - 1.0, -1.0, 1.0) * deg_to_rad(SEATED_PITCH)
	_apply_look()


func _apply_look() -> void:
	rotation.y = _yaw
	if _pivot != null:
		_pivot.rotation.x = _pitch


## Whether the player is close enough to the desk to sit back down.
func can_sit() -> bool:
	return global_position.distance_to(
		Vector3(seat_position.x, global_position.y, seat_position.z)) <= SIT_RANGE
