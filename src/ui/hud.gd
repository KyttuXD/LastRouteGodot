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
@onready var battery_bar: ProgressBar = %BatteryMeter.get_node("Bar")
@onready var battery_caption: Label = %BatteryMeter.get_node("Caption")
@onready var stamina_bar: ProgressBar = %StaminaMeter.get_node("Bar")
@onready var stamina_caption: Label = %StaminaMeter.get_node("Caption")
@onready var pause_label: Label = %PauseLabel
@onready var interaction_label: Label = %InteractionLabel
@onready var message_label: Label = %MessageLabel
@onready var map_overlay: Control = %MapOverlay

var _message_time_left := 0.0


func _process(delta: float) -> void:
	_message_time_left = maxf(0.0, _message_time_left - delta)
	message_label.visible = _message_time_left > 0.0


func update_objective(depth: int, relays_collected: int, relay_target: int) -> void:
	depth_label.text = "DEPTH %02d" % depth
	relay_label.text = "%d/%d SIGNAL RELAYS" % [relays_collected, relay_target]


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
