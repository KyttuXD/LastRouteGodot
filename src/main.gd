extends Node

## HUD meter colors, mirroring ui-controller.js's exact battery/stamina
## color-state logic (see updateHud in the original's src/ui/ui-controller.js).
const COLOR_METER_LOW := Color(0.902, 0.267, 0.318) # #e64451
const COLOR_METER_WARN := Color(0.949, 0.733, 0.384) # #f2bb62
const COLOR_METER_SAFE := Color(0.455, 0.722, 0.553) # #74b88d
const COLOR_METER_STAMINA_NORMAL := Color(0.561, 0.816, 0.878) # #8fd0e0

@onready var facility_view: FacilityView = %FacilityView
@onready var player: PlayerController = %Player
@onready var depth_label: Label = %DepthLabel
@onready var relay_label: Label = %RelayLabel
@onready var battery_bar: ProgressBar = %BatteryMeter.get_node("Bar")
@onready var battery_caption: Label = %BatteryMeter.get_node("Caption")
@onready var stamina_bar: ProgressBar = %StaminaMeter.get_node("Bar")
@onready var stamina_caption: Label = %StaminaMeter.get_node("Caption")
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
	_update_hud()


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

	_update_hud()


func _update_hud() -> void:
	depth_label.text = "DEPTH %02d" % GameState.depth
	relay_label.text = "%d/%d SIGNAL RELAYS" % [GameState.relays_collected, GameState.relay_target]
	_update_battery_meter()
	_update_stamina_meter()


func _update_battery_meter() -> void:
	var charge := int(round(player.lamp_charge))
	battery_bar.value = clampf(player.lamp_charge, 0.0, 100.0)
	var fill := battery_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if charge < 22:
		fill.bg_color = COLOR_METER_LOW
	elif player.is_in_safe_zone():
		fill.bg_color = COLOR_METER_SAFE
	else:
		fill.bg_color = COLOR_METER_WARN

	var movement_suffix := " // LOUD" if player.movement_mode == "sprint" else (" // QUIET" if player.movement_mode == "crouch" else "")
	if charge <= 0:
		battery_caption.text = "BATTERY DEAD%s" % movement_suffix
	else:
		var light_suffix := " // F" if player.flashlight_enabled else " // OFF"
		battery_caption.text = "BATTERY %d%%%s%s" % [charge, light_suffix, movement_suffix]


func _update_stamina_meter() -> void:
	var stamina := int(round(player.stamina))
	stamina_bar.value = clampf(player.stamina, 0.0, 100.0)
	var fill := stamina_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if player.exhausted:
		fill.bg_color = COLOR_METER_LOW
	elif stamina < 30:
		fill.bg_color = COLOR_METER_WARN
	else:
		fill.bg_color = COLOR_METER_STAMINA_NORMAL

	stamina_caption.text = "STAMINA SPENT // WALK" if player.exhausted else "STAMINA %d%%" % stamina


func _on_flashlight_changed(_enabled: bool) -> void:
	_update_hud()


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
