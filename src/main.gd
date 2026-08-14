extends Node

@onready var facility_view: FacilityView = %FacilityView
@onready var player: PlayerController = %Player
@onready var status_label: Label = %StatusLabel
@onready var pause_label: Label = %PauseLabel
@onready var interaction_label: Label = %InteractionLabel
@onready var message_label: Label = %MessageLabel
@onready var map_overlay: Control = %MapOverlay

var observed_depth := 1
var message_time_left := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.start_new_run()
	observed_depth = GameState.depth
	player.flashlight_changed.connect(_on_flashlight_changed)
	player.interaction_message.connect(_on_interaction_message)
	_build_floor()
	_update_status()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		get_tree().paused = not get_tree().paused
		pause_label.visible = get_tree().paused
	if Input.is_action_just_pressed("toggle_map"):
		map_overlay.visible = not map_overlay.visible

	if GameState.depth != observed_depth:
		observed_depth = GameState.depth
		_build_floor()

	message_time_left = maxf(0.0, message_time_left - _delta)
	message_label.visible = message_time_left > 0.0
	interaction_label.text = player.get_interaction_prompt()

	_update_status()


func _update_status() -> void:
	status_label.text = "D%02d  RELAY %d/%d  STAM %03d  LAMP %03d%% %s" % [
		GameState.depth,
		GameState.relays_collected,
		GameState.relay_target,
		int(player.stamina),
		int(player.lamp_charge),
		"ON" if player.flashlight_enabled else "OFF",
	]


func _on_flashlight_changed(_enabled: bool) -> void:
	_update_status()


func _on_interaction_message(message: String) -> void:
	message_label.text = message
	message_label.visible = true
	message_time_left = 2.8


func _build_floor() -> void:
	facility_view.generate_floor(GameState.level_seed_text())
	GameState.relay_target = facility_view.generator.relay_count
	player.position = facility_view.start_world_position()
	_configure_camera_limits()


func _configure_camera_limits() -> void:
	var camera := player.get_node("Camera2D") as Camera2D
	var facility_size := facility_view.facility_pixel_size()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(facility_size.x)
	camera.limit_bottom = int(facility_size.y)
	camera.reset_smoothing()
