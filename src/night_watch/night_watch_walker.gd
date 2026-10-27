class_name NightWatchWalker
extends CharacterBody3D

## The walking player of the Night Watch security room. It uses the shared Godot 2 input actions (move_left/right/up/down, sprint,
## crouch, interact, the mouse sensitivity from Settings) and the same body (capsule 0.25 x 1.7, eye 1.6 m standing, 1.1 m
## crouched) as PlayerController3D, but not that class: the shared controller is ~1,900 lines of flashlight, taser, inventory and XR
## rules and talks only to Last Route's RouteInteractable3D, so Night Watch has this lean walker and its own stations (anything the
## player can aim at and press interact on: the monitor, the door panels, the lamp, the chair). Collisions are the room's static
## bodies on layer 1; stations are on layer 2 so the aim ray sees them and the body ignores them.
##
## The scene drives it: `frozen` stops walking (monitor view, pause, the end of a night), `sit()` / `stand()` lock the view at the desk.

signal interacted(station_id: String)
signal aim_changed(station_id: String, prompt: String)

const STATION_LAYER := 2
const REACH := 2.3
const WALK_SPEED := 2.4
const SPRINT_SPEED := 4.0
const CROUCH_SPEED := 1.2
const EYE_STANDING := 1.6
const EYE_CROUCHED := 1.1
const ACCEL := 14.0
const GRAVITY := 18.0
const MAX_PITCH := 1.45

var camera: Camera3D
var pivot: Node3D
var frozen := false
var sitting := false
var aimed_id := ""
var aimed_prompt := ""
## station id -> prompt text, filled by the office
var prompts := {}

var _eye := EYE_STANDING
var _stand_position := Vector3.ZERO
var _yaw_limit := 0.0
var _sit_yaw := 0.0


func _init() -> void:
	name = "Walker"
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 0.28
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 1.7
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.85, 0.0)
	add_child(shape)
	pivot = Node3D.new()
	pivot.name = "Pivot"
	pivot.position = Vector3(0.0, EYE_STANDING, 0.0)
	add_child(pivot)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.06
	camera.far = 160.0
	camera.fov = 78.0
	pivot.add_child(camera)


func _ready() -> void:
	if Settings != null and "field_of_view" in Settings:
		camera.fov = float(Settings.field_of_view)


func face(yaw: float, pitch := 0.0) -> void:
	rotation.y = yaw
	pivot.rotation.x = clampf(pitch, -MAX_PITCH, MAX_PITCH)


func _unhandled_input(event: InputEvent) -> void:
	if frozen:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		look_by(-m.relative.x * Settings.mouse_sensitivity, -m.relative.y * Settings.mouse_sensitivity)
	elif event.is_action_pressed(&"interact") and not (event is InputEventKey and (event as InputEventKey).echo):
		try_interact()


func look_by(d_yaw: float, d_pitch: float) -> void:
	if sitting:
		rotation.y = clampf(wrapf(rotation.y + d_yaw - _sit_yaw, -PI, PI), -_yaw_limit, _yaw_limit) + _sit_yaw
	else:
		rotation.y += d_yaw
	pivot.rotation.x = clampf(pivot.rotation.x + d_pitch, -MAX_PITCH if not sitting else -0.6, MAX_PITCH if not sitting else 0.6)


## Press interact on whatever is aimed at (the validators call this too).
func try_interact() -> void:
	if aimed_id != "":
		interacted.emit(aimed_id)


func _physics_process(delta: float) -> void:
	var crouching := not sitting and Input.is_action_pressed(&"crouch")
	var target_eye := EYE_CROUCHED if crouching else (1.2 if sitting else EYE_STANDING)
	_eye = move_toward(_eye, target_eye, delta * 4.0)
	pivot.position.y = _eye
	if frozen or sitting:
		velocity = Vector3.ZERO
	else:
		var input := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		var speed := CROUCH_SPEED if crouching else (SPRINT_SPEED if Input.is_action_pressed(&"sprint") else WALK_SPEED)
		var wish := (global_transform.basis * Vector3(input.x, 0.0, input.y)) * speed
		velocity.x = move_toward(velocity.x, wish.x, ACCEL * delta)
		velocity.z = move_toward(velocity.z, wish.z, ACCEL * delta)
		velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
		move_and_slide()
	_update_aim()


## The station under the crosshair within reach (the layer-2 bodies), or "".
func _update_aim() -> void:
	var id := ""
	if not frozen:
		var from := camera.global_position
		var to := from + (-camera.global_transform.basis.z) * REACH
		var query := PhysicsRayQueryParameters3D.create(from, to, 1 << (STATION_LAYER - 1))
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and (hit["collider"] as Node).has_meta("station_id"):
			id = String((hit["collider"] as Node).get_meta("station_id"))
	if id != aimed_id:
		aimed_id = id
		aimed_prompt = String(prompts.get(id, ""))
		aim_changed.emit(aimed_id, aimed_prompt)


## Lock the view at the desk seat: no walking, a limited look around the seat's direction.
func sit(seat: Vector3, yaw: float) -> void:
	if sitting:
		return
	_stand_position = global_position
	global_position = seat
	velocity = Vector3.ZERO
	sitting = true
	_sit_yaw = yaw
	_yaw_limit = 0.9
	rotation.y = yaw
	pivot.rotation.x = -0.1


func stand() -> void:
	if not sitting:
		return
	sitting = false
	global_position = _stand_position
	velocity = Vector3.ZERO
