class_name HUD
extends CanvasLayer

## Shared HUD overlay, usable from either the 2D or 3D presentation layer —
## it only touches Control nodes and never reads World/Player state directly,
## so the orchestrator (main.gd / main_3d.gd) drives it through this API.

## Meter colors, mirroring ui-controller.js's exact battery/stamina
## color-state logic (see updateHud in the original's src/ui/ui-controller.js).
const COLOR_METER_LOW := Color(0.902, 0.267, 0.318) # #e64451
const COLOR_METER_WARN := Color(0.949, 0.733, 0.384) # #f2bb62
const COLOR_METER_SAFE := Color(0.455, 0.722, 0.553) # #74b88d
const COLOR_METER_STAMINA_NORMAL := Color(0.561, 0.816, 0.878) # #8fd0e0

const MESSAGE_DURATION := 2.8

@onready var depth_label: Label = %DepthLabel
@onready var relay_label: Label = %RelayLabel
@onready var lives_label: Label = %LivesLabel
@onready var battery_bar: ProgressBar = %BatteryMeter.get_node("Bar")
@onready var battery_caption: Label = %BatteryMeter.get_node("Caption")
@onready var stamina_bar: ProgressBar = %StaminaMeter.get_node("Bar")
@onready var stamina_caption: Label = %StaminaMeter.get_node("Caption")
@onready var exposure_bar: ProgressBar = %ExposureMeter.get_node("Bar")
@onready var exposure_caption: Label = %ExposureMeter.get_node("Caption")
@onready var noise_bar: ProgressBar = %NoiseMeter.get_node("Bar")
@onready var noise_caption: Label = %NoiseMeter.get_node("Caption")
@onready var temperature_bar: ProgressBar = %TemperatureMeter.get_node("Bar")
@onready var temperature_caption: Label = %TemperatureMeter.get_node("Caption")
@onready var pause_label: Label = %PauseLabel
@onready var interaction_label: Label = %InteractionLabel
@onready var message_label: Label = %MessageLabel
@onready var map_overlay: Control = %MapOverlay
@onready var escape_overlay: Control = %EscapeOverlay
@onready var escape_progress_bar: ProgressBar = %EscapeProgressBar
@onready var escape_time_bar: ProgressBar = %EscapeTimeBar

var _message_time_left := 0.0


func _process(delta: float) -> void:
	_message_time_left = maxf(0.0, _message_time_left - delta)
	message_label.visible = _message_time_left > 0.0


func update_objective(depth: int, relays_collected: int, relay_target: int, lives_remaining: int) -> void:
	depth_label.text = "DEPTH %02d" % depth
	relay_label.text = "%d/%d SIGNAL RELAYS" % [relays_collected, relay_target]
	lives_label.text = "LIVES %d" % lives_remaining


func set_escape_active(active: bool) -> void:
	escape_overlay.visible = active


func update_escape(progress: int, required: int, remaining: float, duration: float) -> void:
	escape_progress_bar.max_value = required
	escape_progress_bar.value = progress
	escape_time_bar.max_value = duration
	escape_time_bar.value = remaining


func update_battery(charge: float, flashlight_enabled: bool, in_safe_zone: bool, movement_mode: String) -> void:
	var rounded := int(round(charge))
	battery_bar.value = clampf(charge, 0.0, 100.0)
	var fill := battery_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if rounded < 22:
		fill.bg_color = COLOR_METER_LOW
	elif in_safe_zone:
		fill.bg_color = COLOR_METER_SAFE
	else:
		fill.bg_color = COLOR_METER_WARN

	var movement_suffix := " // LOUD" if movement_mode == "sprint" else (" // QUIET" if movement_mode == "crouch" else "")
	if rounded <= 0:
		battery_caption.text = "BATTERY DEAD%s" % movement_suffix
	else:
		var light_suffix := " // F" if flashlight_enabled else " // OFF"
		battery_caption.text = "BATTERY %d%%%s%s" % [rounded, light_suffix, movement_suffix]


func update_stamina(stamina: float, exhausted: bool) -> void:
	var rounded := int(round(stamina))
	stamina_bar.value = clampf(stamina, 0.0, 100.0)
	var fill := stamina_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if exhausted:
		fill.bg_color = COLOR_METER_LOW
	elif rounded < 30:
		fill.bg_color = COLOR_METER_WARN
	else:
		fill.bg_color = COLOR_METER_STAMINA_NORMAL

	stamina_caption.text = "STAMINA SPENT // WALK" if exhausted else "STAMINA %d%%" % rounded


## The three facility-pressure meters (src/game/player_meters.gd). Exposure and
## noise read as "how findable am I right now"; temperature is the one that can
## kill on its own — both extremes are called out explicitly rather than left
## for the player to infer from a bar position.
func update_meters(meters: PlayerMeters) -> void:
	var exposure := int(round(meters.exposure))
	exposure_bar.value = clampf(meters.exposure, 0.0, 100.0)
	var exposure_fill := exposure_bar.get_theme_stylebox("fill") as StyleBoxFlat
	exposure_fill.bg_color = COLOR_METER_LOW if exposure >= 70 else (COLOR_METER_WARN if exposure >= 40 else COLOR_METER_SAFE)
	exposure_caption.text = "EXPOSURE %d%%" % exposure

	var noise_level := int(round(meters.noise_meter))
	noise_bar.value = clampf(meters.noise_meter, 0.0, 100.0)
	var noise_fill := noise_bar.get_theme_stylebox("fill") as StyleBoxFlat
	noise_fill.bg_color = COLOR_METER_LOW if noise_level >= 70 else (COLOR_METER_WARN if noise_level >= 35 else COLOR_METER_SAFE)
	noise_caption.text = "NOISE %d%%" % noise_level

	var temperature := int(round(meters.temperature))
	temperature_bar.value = clampf(meters.temperature, 0.0, 100.0)
	var temperature_fill := temperature_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if meters.overheating or meters.freezing:
		temperature_fill.bg_color = COLOR_METER_LOW
	elif temperature >= 78 or temperature <= 28:
		temperature_fill.bg_color = COLOR_METER_WARN
	else:
		temperature_fill.bg_color = COLOR_METER_SAFE

	if meters.overheating:
		temperature_caption.text = "OVERHEATING %dF" % temperature
	elif meters.freezing:
		temperature_caption.text = "FREEZING %dF" % temperature
	else:
		temperature_caption.text = "TEMP %dF" % temperature


func set_interaction_prompt(text: String) -> void:
	interaction_label.text = text


func show_message(text: String) -> void:
	message_label.text = text
	message_label.visible = true
	_message_time_left = MESSAGE_DURATION


func set_paused(is_paused: bool) -> void:
	pause_label.visible = is_paused


func toggle_map_overlay() -> void:
	map_overlay.visible = not map_overlay.visible
