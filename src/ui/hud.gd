class_name HUD
extends CanvasLayer

signal inventory_reorder_requested(from_slot: int, to_slot: int)

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
const ITEM_TEXTURES := {
	"flashlight": preload("res://assets/ui/inventory/flashlight_item.png"),
	"taser": preload("res://assets/ui/inventory/taser_item.png"),
	"lockpick": preload("res://assets/ui/inventory/lockpick_set.png"),
	"crowbar": preload("res://assets/ui/inventory/crowbar.png"),
	"rescue_axe": preload("res://assets/ui/inventory/rescue_axe.png"),
}

var _static_overlay: StaticOverlay


func _ready() -> void:
	Palette.style_title(%MapTitle)
	_prepare_inventory_slots()
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
@onready var compact_status_label: Label = %CompactStatusLabel
@onready var fps_label: Label = %FpsLabel

var _message_time_left := 0.0
var _fps_update_left := 0.0
var _lamp_percent := 100
var _stamina_percent := 100
var _inventory_drag_from := -1
var _inventory_slots: Array[PanelContainer] = []
var _inventory_bars: Array[ProgressBar] = []


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
		durability: Dictionary = {}, owned: Dictionary = {}, order: Array = [],
		maximums: Dictionary = {}) -> void:
	var resolved_order := order if order.size() == _inventory_slots.size() \
		else PlayerController3D.INVENTORY_ITEMS
	for index in _inventory_slots.size():
		var slot := _inventory_slots[index]
		var item_id := String(resolved_order[index])
		var has_item := bool(owned.get(item_id, false))
		slot.add_theme_stylebox_override("panel", _hotbar_slot_style(
			selected_item == item_id and has_item))
		slot.modulate = Color.WHITE if has_item else Color(0.24, 0.27, 0.28, .42)
		var icon := slot.get_node("Stack/Icon") as TextureRect
		icon.texture = ITEM_TEXTURES.get(item_id)
		var caption := slot.get_node("Stack/Caption") as Label
		caption.text = str(index + 1)
		slot.tooltip_text = "%s // DRAG OR SHIFT+NUMBER TO MOVE" % String(
			PlayerController3D.INVENTORY_LABELS.get(item_id, item_id)).to_upper()
		var bar := _inventory_bars[index]
		bar.visible = has_item
		if item_id == "taser":
			bar.value = clampf(1.0 - taser_cooldown / GameConfig.TASER_COOLDOWN_SECONDS,
				0.0, 1.0) * 100.0
		else:
			var max_value := maxi(1, int(maximums.get(item_id, 1)))
			bar.value = clampf(float(durability.get(item_id, 0)) / max_value,
				0.0, 1.0) * 100.0


func _prepare_inventory_slots() -> void:
	_inventory_slots.assign([flashlight_slot, taser_slot, lockpick_slot,
		crowbar_slot, rescue_axe_slot])
	for index in _inventory_slots.size():
		var slot := _inventory_slots[index]
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.gui_input.connect(func(event: InputEvent) -> void:
			_inventory_slot_input(event, index))
		var stack := slot.get_node("Stack") as VBoxContainer
		var bar := ProgressBar.new()
		bar.name = "DurabilityBar"
		bar.custom_minimum_size = Vector2(0, 3)
		bar.max_value = 100.0
		bar.value = 100.0
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var background := StyleBoxFlat.new()
		background.bg_color = Color(0.055, 0.07, 0.075, .96)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.43, 0.82, 0.58, 1.0)
		bar.add_theme_stylebox_override("background", background)
		bar.add_theme_stylebox_override("fill", fill)
		stack.add_child(bar)
		_inventory_bars.append(bar)


func _inventory_slot_input(event: InputEvent, index: int) -> void:
	if not event is InputEventMouseButton \
			or (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	var mouse := event as InputEventMouseButton
	if mouse.pressed:
		_inventory_drag_from = index
		get_viewport().set_input_as_handled()
		return
	if _inventory_drag_from < 0:
		return
	var destination := index
	var pointer := get_viewport().get_mouse_position()
	for slot_index in _inventory_slots.size():
		if _inventory_slots[slot_index].get_global_rect().has_point(pointer):
			destination = slot_index
			break
	if destination != _inventory_drag_from:
		inventory_reorder_requested.emit(_inventory_drag_from, destination)
	_inventory_drag_from = -1
	get_viewport().set_input_as_handled()


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
	compact_status_label.text = "LAMP %s   STAMINA %s" % [
		_meter_ticks(_lamp_percent), _meter_ticks(_stamina_percent)]


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
