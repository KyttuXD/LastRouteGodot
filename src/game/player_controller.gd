class_name PlayerController
extends CharacterBody2D

signal flashlight_changed(enabled: bool)
signal interaction_message(message: String)

@onready var body_visual: Polygon2D = $BodyVisual
@onready var flashlight_visual: Polygon2D = $FlashlightVisual

var flashlight_enabled := true
var stamina := GameConfig.MAX_STAMINA
var lamp_charge := GameConfig.MAX_LAMP_CHARGE
var exhausted := false
var stamina_recovery_delay := 0.0
var movement_mode := "walk"


func _ready() -> void:
	flashlight_visual.visible = flashlight_enabled


func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var movement_speed := GameConfig.PLAYER_WALK_SPEED
	var difficulty := RoomState.difficulty_profile()
	var is_moving := input_vector.length_squared() > 0.0
	var wants_to_sprint := Input.is_action_pressed("sprint") and is_moving and not exhausted
	var is_sprinting := false

	if Input.is_action_pressed("crouch"):
		movement_speed = GameConfig.PLAYER_CROUCH_SPEED * float(difficulty["crouch_speed"])
		movement_mode = "crouch"
	elif wants_to_sprint and stamina > 0.0:
		movement_speed = GameConfig.PLAYER_SPRINT_SPEED * float(difficulty["sprint_speed"])
		is_sprinting = true
		movement_mode = "sprint"
	else:
		movement_speed *= float(difficulty["player_speed"])
		movement_mode = "walk"

	_update_stamina(delta, is_sprinting)
	_update_lamp(delta, is_sprinting)

	velocity = input_vector * movement_speed
	move_and_slide()

	if input_vector.length_squared() > 0.0:
		rotation = input_vector.angle()

	if Input.is_action_just_pressed("flashlight"):
		_set_flashlight(not flashlight_enabled)

	if Input.is_action_just_pressed("interact"):
		_try_interact()


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
	var difficulty := RoomState.difficulty_profile()
	var drain := GameConfig.LAMP_IDLE_DRAIN * float(difficulty["lamp_drain"])
	if is_sprinting:
		drain += GameConfig.LAMP_SPRINT_DRAIN * float(difficulty["sprint_drain"])
	lamp_charge = maxf(0.0, lamp_charge - drain * delta)
	if lamp_charge <= 0.0:
		_set_flashlight(false)


func _set_flashlight(enabled: bool) -> void:
	flashlight_enabled = enabled and lamp_charge > 0.0
	flashlight_visual.visible = flashlight_enabled
	flashlight_changed.emit(flashlight_enabled)


func restore_lamp(amount: float) -> void:
	lamp_charge = minf(GameConfig.MAX_LAMP_CHARGE, lamp_charge + amount)


func restore_at_safe_zone() -> void:
	stamina = GameConfig.MAX_STAMINA
	lamp_charge = GameConfig.MAX_LAMP_CHARGE
	exhausted = false


## Mirrors ui-controller.js's inSafeZone battery-color branch — true while
## standing within a safe zone's rest radius, regardless of whether it has
## already been activated with [E].
func is_in_safe_zone() -> bool:
	for candidate in get_tree().get_nodes_in_group("interactable"):
		if candidate is RouteInteractable and candidate.kind == RouteInteractable.Kind.SAFE_ZONE \
			and global_position.distance_to(candidate.global_position) <= GameConfig.SAFE_ZONE_RADIUS:
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


func _nearest_interactable() -> RouteInteractable:
	var nearest: RouteInteractable = null
	var nearest_distance := GameConfig.INTERACTION_RANGE
	for candidate in get_tree().get_nodes_in_group("interactable"):
		if not candidate is RouteInteractable:
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance <= nearest_distance and not candidate.get_prompt().is_empty():
			nearest = candidate
			nearest_distance = distance
	return nearest
