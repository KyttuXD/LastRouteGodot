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

var _static_overlay: StaticOverlay


func _ready() -> void:
	Palette.style_title(%MapTitle)
	_static_overlay = StaticOverlay.new()
	# Above every meter and label this scene already owns, below nothing --
	# a screen effect that a HUD element could still peek through would not
	# read as covering the player's view.
	add_child(_static_overlay)
	_static_overlay.z_index = 4096


## TV static over the whole view for `duration` seconds. Generic infrastructure
## for a hunter gimmick to reach for, the same way PlayerController3D's
## force_flashlight_flicker is -- nothing here knows or cares which hunter
## asked for it.
func trigger_static(duration: float, intensity: float = 0.75) -> void:
	_static_overlay.trigger(duration, intensity)

@onready var depth_label: Label = %DepthLabel
@onready var relay_label: Label = %RelayLabel
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
@onready var interaction_label: Label = %InteractionLabel
@onready var message_label: Label = %MessageLabel
@onready var map_overlay: Control = %MapOverlay
@onready var plan: FacilityMap = %Plan
@onready var minimap: FacilityMap = %Minimap
@onready var escape_overlay: Control = %EscapeOverlay
@onready var escape_progress_bar: ProgressBar = %EscapeProgressBar
@onready var escape_time_bar: ProgressBar = %EscapeTimeBar
@onready var flashlight_slot: PanelContainer = %FlashlightSlot
@onready var taser_slot: PanelContainer = %TaserSlot
@onready var lockpick_slot: PanelContainer = %LockpickSlot
@onready var crowbar_slot: PanelContainer = %CrowbarSlot
@onready var rescue_axe_slot: PanelContainer = %RescueAxeSlot
@onready var flashlight_caption: Label = %FlashlightCaption
@onready var taser_caption: Label = %TaserCaption
@onready var lockpick_caption: Label = %LockpickCaption
@onready var crowbar_caption: Label = %CrowbarCaption
@onready var rescue_axe_caption: Label = %RescueAxeCaption
@onready var compact_status_label: Label = %CompactStatusLabel
@onready var fps_label: Label = %FpsLabel

var _message_time_left := 0.0
var _fps_update_left := 0.0
var _lamp_percent := 100
var _stamina_percent := 100


func _process(delta: float) -> void:
	_message_time_left = maxf(0.0, _message_time_left - delta)
	message_label.visible = _message_time_left > 0.0
	_fps_update_left -= delta
	if _fps_update_left <= 0.0:
		_fps_update_left = .25
		fps_label.text = "FPS %d" % Engine.get_frames_per_second()


func update_objective(depth: int, relays_collected: int, relay_target: int) -> void:
	depth_label.text = "DEPTH %02d" % depth
	relay_label.text = "%d/%d SIGNAL RELAYS" % [relays_collected, relay_target]


func update_inventory(selected_item: String, taser_cooldown: float,
		durability: Dictionary = {}, owned: Dictionary = {}) -> void:
	var slots := {
		"flashlight": flashlight_slot, "taser": taser_slot,
		"lockpick": lockpick_slot, "crowbar": crowbar_slot,
		"rescue_axe": rescue_axe_slot,
	}
	for item_id in slots:
		var slot := slots[item_id] as PanelContainer
		var has_item := bool(owned.get(item_id, false))
		slot.add_theme_stylebox_override("panel", _hotbar_slot_style(
			selected_item == item_id and has_item))
		slot.modulate = Color.WHITE if has_item else Color(0.24, 0.27, 0.28, .42)
	flashlight_caption.text = "1"
	taser_caption.text = "2\n%.1f" % taser_cooldown if taser_cooldown > .05 else "2"
	lockpick_caption.text = "3  %d" % int(durability.get("lockpick", 0))
	crowbar_caption.text = "4  %d" % int(durability.get("crowbar", 0))
	rescue_axe_caption.text = "5  %d" % int(durability.get("rescue_axe", 0))


func _hotbar_slot_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.065, 0.075, .94)
	var width := 2 if selected else 1
	style.set_border_width_all(width)
	style.border_color = Palette.AMBER if selected else Color(0.28, 0.34, 0.35, .92)
	style.corner_radius_top_left = 1
	style.corner_radius_top_right = 1
	style.corner_radius_bottom_left = 1
	style.corner_radius_bottom_right = 1
	return style


func _refresh_compact_status() -> void:
	compact_status_label.text = "LAMP %s %3d%%   STAMINA %s %3d%%" % [
		_meter_ticks(_lamp_percent), _lamp_percent,
		_meter_ticks(_stamina_percent), _stamina_percent]


func _meter_ticks(value: int) -> String:
	var filled := clampi(roundi(float(value) / 10.0), 0, 10)
	return "[" + "#".repeat(filled) + "-".repeat(10 - filled) + "]"


func set_escape_active(active: bool) -> void:
	escape_overlay.visible = active


func update_escape(progress: int, required: int, remaining: float, duration: float) -> void:
	escape_progress_bar.max_value = required
	escape_progress_bar.value = progress
	escape_time_bar.max_value = duration
	escape_time_bar.value = remaining


func update_battery(charge: float, flashlight_enabled: bool, in_safe_zone: bool, movement_mode: String) -> void:
	var rounded := int(round(charge))
	_lamp_percent = clampi(rounded, 0, 100)
	_refresh_compact_status()
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
	_stamina_percent = clampi(rounded, 0, 100)
	_refresh_compact_status()
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


func toggle_map_overlay() -> void:
	map_overlay.visible = not map_overlay.visible


## The full map is only worth redrawing while somebody is looking at it, and
## the original charges the same price for reading it: your view of the
## room. The minimap has no such gate -- it is always up, which is exactly
## why it never gets hunter marks the way the full map does (see
## main_3d.gd's _minimap_marks): giving up peripheral vision for hunter
## intel is the original's whole trade, and a permanent widget that showed
## them for free would erase it.
func map_is_open() -> bool:
	return map_overlay.visible


func update_map(generator: FacilityGenerator, at: Vector2, facing: Vector2, marks: Array) -> void:
	plan.show_state(generator, at, facing, marks)


func update_minimap(generator: FacilityGenerator, at: Vector2, facing: Vector2, marks: Array) -> void:
	minimap.show_state(generator, at, facing, marks)
