class_name PlayerController
extends CharacterBody2D

signal flashlight_changed(enabled: bool)

@onready var body_visual: Polygon2D = $BodyVisual
@onready var flashlight_visual: Polygon2D = $FlashlightVisual

var flashlight_enabled := true


func _ready() -> void:
	flashlight_visual.visible = flashlight_enabled


func _physics_process(_delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var movement_speed := GameConfig.PLAYER_WALK_SPEED

	if Input.is_action_pressed("crouch"):
		movement_speed = GameConfig.PLAYER_CROUCH_SPEED
	elif Input.is_action_pressed("sprint"):
		movement_speed = GameConfig.PLAYER_SPRINT_SPEED

	velocity = input_vector * movement_speed
	move_and_slide()
	position = position.clamp(GameConfig.PLAYER_BOUNDS.position, GameConfig.PLAYER_BOUNDS.end)

	if input_vector.length_squared() > 0.0:
		rotation = input_vector.angle()

	if Input.is_action_just_pressed("flashlight"):
		flashlight_enabled = not flashlight_enabled
		flashlight_visual.visible = flashlight_enabled
		flashlight_changed.emit(flashlight_enabled)

