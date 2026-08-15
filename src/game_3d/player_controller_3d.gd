class_name PlayerController3D
extends CharacterBody3D

## 3D counterpart to src/game/player_controller.gd. Same stamina/lamp/
## interaction rules (GameConfig is shared, untouched), CharacterBody3D
## movement on the XZ ground plane instead of CharacterBody2D on XY, and two
## camera rigs (orthographic top-down, perspective first-person) toggled by
## FIRST PERSON only.
##
## There was a top-down view on the V key, inherited from the 2D original. It
## rendered black in the 3D build and survived three attempts to fix it -- the
## camera was current, the world was in front of it, the ceiling was hidden and
## a directional light was on it, and it was still black. It is also redundant:
## the facility is a real 3D building now, and the memory map is the thing that
## reads a floor plan. So it is gone rather than carried as a broken option.

signal flashlight_changed(enabled: bool)
signal interaction_message(message: String)

const CAMERA_HEIGHT := 1.6
const BODY_MODEL_SCENE := "res://art/props-3d/characters/player.tscn"

## Sibling, not a child — the top-down camera must NOT inherit the player's
## facing rotation (it stays fixed, looking straight down, and only follows
## position each frame). See _physics_process.
@onready var first_person_camera: Camera3D = $FirstPersonPivot/FirstPersonCamera
@onready var first_person_pivot: Node3D = $FirstPersonPivot
@onready var flashlight: SpotLight3D = $FirstPersonPivot/Flashlight
## Empty container — its child model comes from ModelSlot (see _ready), so
## replacing BODY_MODEL_SCENE's contents with a real model needs no changes
## here.
@onready var body_visual: Node3D = $BodyVisual

var flashlight_enabled := true
## True while the facility's heater station is running — warms the ambient,
## and is Wynelle's counterplay (see heater_station in route_interactable_3d).
var heater_on := false
var stamina := GameConfig.MAX_STAMINA
var lamp_charge := GameConfig.MAX_LAMP_CHARGE
var exhausted := false
var stamina_recovery_delay := 0.0
var movement_mode := "walk"
## Noise emitted this frame by movement, consumed by hunter hearing
## (hunter_brain.gd) — matches the original's per-frame emittedNoise.
var noise := 0.0
## Frozen during the capture/escape struggle (main_3d.gd) — movement and
## interaction stop, but the scene keeps rendering/ticking around the player.
var input_frozen := false

## Exposure / noise / temperature, shared with hunter gimmicks that read them
## (see src/game/player_meters.gd).
var meters := PlayerMeters.new()
## Facing on the facility's XZ ground plane, for beam-aim checks (Nyxie's
## dispel). Derived from body yaw, which both control schemes already set.
var facing := Vector2(0, 1)

var _yaw := 0.0
var _pitch := 0.0
var _animation_player: AnimationPlayer
## The clip this body is playing, published so remote copies can play the same
## one. Set where the local body is told to play, so the two cannot disagree.
var _clip := "idle"


func _ready() -> void:
	var model := ModelSlot.instantiate(BODY_MODEL_SCENE)
	if model:
		body_visual.add_child(model)
		_animation_player = ModelSlot.find_animation_player(model)
	# Explicitly through _set_flashlight rather than by poking `visible`, so the
	# lamp-charge gate applies at spawn exactly as it does on a manual toggle.
	# The maze is lit almost entirely by this beam; starting dark reads as a
	# broken build rather than as atmosphere.
	_set_flashlight(true)
	_enter_first_person()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_yaw -= event.relative.x * Settings.mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * Settings.mouse_sensitivity, -1.4, 1.4)
		rotation.y = _yaw
		first_person_pivot.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if input_frozen:
		velocity = Vector3.ZERO
		move_and_slide()
		noise = 0.0
		_clip = "idle"
		ModelSlot.play_if_available(_animation_player, _clip)
		return

	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var movement_speed := GameConfig.PLAYER_WALK_SPEED
	var is_moving := input_vector.length_squared() > 0.0
	var wants_to_sprint := Input.is_action_pressed("sprint") and is_moving and not exhausted
	var is_sprinting := false

	if Input.is_action_pressed("crouch"):
		movement_speed = GameConfig.PLAYER_CROUCH_SPEED
		movement_mode = "crouch"
	elif wants_to_sprint and stamina > 0.0:
		movement_speed = GameConfig.PLAYER_SPRINT_SPEED
		is_sprinting = true
		movement_mode = "sprint"
	else:
		movement_mode = "walk"

	noise = 0.0 if not is_moving else (GameConfig.NOISE_CROUCH if movement_mode == "crouch" else (GameConfig.NOISE_SPRINT if is_sprinting else GameConfig.NOISE_WALK))

	meters.update(delta, {
		"flashlight_on": flashlight_enabled,
		"noise": noise,
		"crouching": movement_mode == "crouch",
		"hidden": false,
		"in_safe_zone": is_in_safe_zone(),
		"heater_on": heater_on,
	})

	_update_stamina(delta, is_sprinting)
	_update_lamp(delta, is_sprinting)
	_clip = movement_mode if is_moving else "idle"
	ModelSlot.play_if_available(_animation_player, _clip)

	var move_direction: Vector3
	# Movement is camera-relative: forward is where you are looking.
	if true:
		# Relative to facing: forward/back on move_up/move_down, strafe on move_left/move_right.
		move_direction = (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized() if is_moving else Vector3.ZERO
	else:
		# Fixed world axes, matching the 2D top-down control scheme.
		move_direction = Vector3(input_vector.x, 0.0, input_vector.y)
		if is_moving:
			rotation.y = atan2(input_vector.x, input_vector.y)
			_yaw = rotation.y

	# GameConfig's speed constants are px/s at TILE_SIZE=16px per 2D tile;
	# the 3D world uses 1 tile = 1 meter (see art/props-3d/README.md), so
	# converting px/s -> tiles/s gives the equivalent m/s. Freezing slows you.
	var speed_mps := movement_speed * meters.movement_scale() / GameConfig.TILE_SIZE
	# Grid-space facing: the facility's (x, y) maps onto XZ, and body yaw is
	# measured with atan2(x, z), so this is the same direction the beam points.
	facing = Vector2(sin(rotation.y), cos(rotation.y))

	velocity.x = move_direction.x * speed_mps
	velocity.z = move_direction.z * speed_mps
	velocity.y = 0.0
	move_and_slide()


	if Input.is_action_just_pressed("flashlight"):
		_set_flashlight(not flashlight_enabled)

	if Input.is_action_just_pressed("interact"):
		_try_interact()


## First person is the only view. The body is hidden because you are inside it,
## and the mouse is captured because the camera is aimed with it.
## What this body is playing, for RemotePlayers to send on.
func current_clip() -> String:
	return _clip


func _enter_first_person() -> void:
	first_person_camera.current = true
	body_visual.visible = false
	# Stated as a preference, not set directly: a menu on top has to be able to
	# hand the cursor back without this taking it again next frame.
	MouseLock.set_gameplay_capture(true)


func _update_stamina(delta: float, is_sprinting: bool) -> void:
	if is_sprinting:
		stamina = maxf(0.0, stamina - GameConfig.STAMINA_SPRINT_DRAIN * delta)
		stamina_recovery_delay = GameConfig.STAMINA_RECOVERY_DELAY
		if stamina <= 0.0:
			exhausted = true
		return

	stamina_recovery_delay = maxf(0.0, stamina_recovery_delay - delta)
	if stamina_recovery_delay <= 0.0:
		stamina = minf(GameConfig.MAX_STAMINA, stamina + GameConfig.STAMINA_RECOVERY * delta)
	if exhausted and stamina >= GameConfig.STAMINA_EXHAUSTED_RECOVERY:
		exhausted = false


func _update_lamp(delta: float, is_sprinting: bool) -> void:
	if not flashlight_enabled:
		return
	var drain := GameConfig.LAMP_IDLE_DRAIN
	if is_sprinting:
		drain += GameConfig.LAMP_SPRINT_DRAIN
	lamp_charge = maxf(0.0, lamp_charge - drain * meters.drain_scale() * delta)
	if lamp_charge <= 0.0:
		_set_flashlight(false)


func _set_flashlight(enabled: bool) -> void:
	flashlight_enabled = enabled and lamp_charge > 0.0
	flashlight.visible = flashlight_enabled
	flashlight_changed.emit(flashlight_enabled)


func restore_lamp(amount: float) -> void:
	lamp_charge = minf(GameConfig.MAX_LAMP_CHARGE, lamp_charge + amount)


## World position projected onto facility_generator.gd's grid-cell space —
## valid because the 3D world uses 1 cell = 1 meter with the grid's (x,y)
## mapped directly onto the XZ ground plane (see facility_view_3d.gd).
func grid_position() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func restore_at_safe_zone() -> void:
	stamina = GameConfig.MAX_STAMINA
	lamp_charge = GameConfig.MAX_LAMP_CHARGE
	exhausted = false


## Mirrors ui-controller.js's inSafeZone battery-color branch — true while
## standing within a safe zone's rest radius, regardless of whether it has
## already been activated with [E].
func is_in_safe_zone() -> bool:
	var radius_m := GameConfig.SAFE_ZONE_RADIUS / GameConfig.TILE_SIZE
	for candidate in get_tree().get_nodes_in_group("interactable"):
		if candidate is RouteInteractable3D and candidate.kind == RouteInteractable3D.Kind.SAFE_ZONE \
			and global_position.distance_to(candidate.global_position) <= radius_m:
			return true
	return false


func get_interaction_prompt() -> String:
	var target := _nearest_interactable()
	if target == null:
		return ""
	var prompt: String = target.get_prompt()
	return "[E] %s" % prompt if not prompt.is_empty() else ""


func _try_interact() -> void:
	var target := _nearest_interactable()
	if target == null:
		interaction_message.emit("Nothing is within reach.")
		return
	interaction_message.emit(target.activate(self))


func _nearest_interactable() -> RouteInteractable3D:
	var nearest: RouteInteractable3D = null
	var nearest_distance := GameConfig.INTERACTION_RANGE / GameConfig.TILE_SIZE
	for candidate in get_tree().get_nodes_in_group("interactable"):
		if not candidate is RouteInteractable3D:
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance <= nearest_distance and not candidate.get_prompt().is_empty():
			nearest = candidate
			nearest_distance = distance
	return nearest
