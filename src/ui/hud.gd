class_name HUD
extends CanvasLayer

signal inventory_reorder_requested(from_slot: int, to_slot: int)
signal inventory_open_changed(shown: bool)
signal map_open_changed(shown: bool)
signal map_waypoint_requested(world_position: Vector2, level: int)

## Shared HUD overlay, usable from either the 2D or 3D presentation layer —
## it only touches Control nodes and never reads World/Player state directly,
## so the orchestrator (main.gd / main_3d.gd) drives it through this API.

## Meter colors, mirroring ui-controller.js's exact battery/stamina
## color-state logic (see updateHud in the original's src/ui/ui-controller.js).
const COLOR_METER_LOW := Color(0.902, 0.267, 0.318) # #e64451
const COLOR_METER_WARN := Color(0.949, 0.733, 0.384) # #f2bb62
const COLOR_METER_SAFE := Color(0.455, 0.722, 0.553) # #74b88d
const COLOR_METER_STAMINA_NORMAL := Color(0.941, 0.761, 0.392) # #f0c264

const MESSAGE_DURATION := 2.8
## A 3x3 streamed window spans 135 cells and made the small map read like a
## full-floor overview. Keep only the nearby 36-cell square on the minimap;
## the full map still shows every discovered chunk.
const STREAMED_MINIMAP_RADIUS_CELLS := 18
const THERMAL_WARNING_SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float cold : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_time = 0.0;

float hash_column(float value) {
	return fract(sin(value * 91.3458) * 47453.5453);
}

void fragment() {
	vec2 grid = vec2(160.0, 90.0);
	vec2 pixel = floor(UV * grid);
	vec2 uv = (pixel + vec2(0.5)) / grid;
	float edge_distance = min(min(uv.x, 1.0 - uv.x),
		min(uv.y, 1.0 - uv.y));
	float pulse = 0.72 + 0.28 * sin(pulse_time * 4.4);

	// Heat is a restrained warm-yellow edge haze with short upward tongues.
	float heat_edge = 1.0 - smoothstep(0.015, 0.11, edge_distance);
	float heat_column = hash_column(floor(pixel.x / 5.0));
	float heat_tongue = 1.0 - smoothstep(0.015,
		mix(0.035, 0.10, heat_column * heat_column), 1.0 - uv.y);
	float heat_shape = max(heat_edge * 0.58, heat_tongue * 0.34);
	float heat_alpha = floor(heat_shape * heat * pulse * 8.0 + 0.5) / 8.0 * 0.22;

	// Cold grows irregular white/cyan icicles from the top and frosts all edges.
	float cold_column = hash_column(floor(pixel.x / 4.0) + 31.0);
	float icicle_length = mix(0.045, 0.23, cold_column * cold_column);
	float icicle_width = step(fract(pixel.x / 4.0), 0.72);
	float icicle = (1.0 - smoothstep(icicle_length * 0.65,
		icicle_length, uv.y)) * icicle_width;
	float frost = 1.0 - smoothstep(0.015, 0.135, edge_distance);
	float cold_shape = max(frost * 0.72, icicle);
	float cold_alpha = floor(cold_shape * cold * pulse * 8.0 + 0.5) / 8.0 * 0.44;

	vec3 heat_color = vec3(1.0, 0.74, 0.12);
	vec3 cold_color = vec3(0.82, 0.96, 1.0);
	float alpha = max(heat_alpha, cold_alpha);
	vec3 color = mix(heat_color, cold_color,
		cold_alpha / max(heat_alpha + cold_alpha, 0.0001));
	COLOR = vec4(color, alpha);
}
"""
## F1 mirrors Minecraft's clean-view toggle. These are the always-on gameplay
## surfaces only; modal UI (inventory, fullscreen map and escape) deliberately
## remains usable while the HUD is hidden.
const GAMEPLAY_HUD_NODE_PATHS := [
	NodePath("ObjectivePanel"),
	NodePath("MetersPanel"),
	NodePath("HotbarPanel"),
	NodePath("CompactStaminaBar"),
	NodePath("FpsLabel"),
	NodePath("InteractionLabel"),
	NodePath("MessageLabel"),
	NodePath("ThermalWarning"),
	NodePath("Crosshair"),
	NodePath("MinimapPanel"),
]
const ITEM_TEXTURES := {
	"flashlight": preload("res://assets/ui/inventory/flashlight_item.png"),
	"taser": preload("res://assets/ui/inventory/taser_item.png"),
	"lockpick": preload("res://assets/ui/inventory/lockpick_set.png"),
	"crowbar": preload("res://assets/ui/inventory/crowbar.png"),
	"rescue_axe": preload("res://assets/ui/inventory/rescue_axe.png"),
	"battery": preload("res://assets/ui/inventory/battery.png"),
}

func _ready() -> void:
	Palette.style_title(%MapTitle)
	_build_thermal_warning()
	_cache_gameplay_hud_surfaces()
	_prepare_inventory_slots()
	_build_inventory_overlay()
	map_overlay.visibility_changed.connect(_on_map_overlay_visibility_changed)
	plan.waypoint_requested.connect(func(world_position: Vector2, level: int) -> void:
		map_waypoint_requested.emit(world_position, level))
	_on_map_overlay_visibility_changed()

@onready var depth_label: Label = %DepthLabel
@onready var relay_label: Label = %RelayLabel
@onready var danger_row: HBoxContainer = %DangerRow
@onready var danger_label: Label = %DangerLabel
@onready var danger_bar: ProgressBar = %DangerBar
@onready var battery_bar: ProgressBar = %BatteryMeter.get_node("Bar")
@onready var battery_caption: Label = %BatteryMeter.get_node("Caption")
@onready var stamina_bar: ProgressBar = %StaminaMeter.get_node("Bar")
@onready var stamina_caption: Label = %StaminaMeter.get_node("Caption")
@onready var exposure_bar: ProgressBar = %ExposureMeter.get_node("Bar")
@onready var exposure_caption: Label = %ExposureMeter.get_node("Caption")
@onready var noise_bar: ProgressBar = %NoiseMeter.get_node("Bar")
@onready var noise_caption: Label = %NoiseMeter.get_node("Caption")
@onready var interaction_label: Label = %InteractionLabel
@onready var message_label: Label = %MessageLabel
@onready var map_overlay: Control = %MapOverlay
@onready var map_title: Label = %MapTitle
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
@onready var compact_stamina_bar: ProgressBar = %CompactStaminaBar
@onready var fps_label: Label = %FpsLabel

var _message_time_left := 0.0
var _hold_message := ""
var _fps_update_left := 0.0
var _stamina_percent := 100
var _inventory_drag_from := -1
var _inventory_drag_ghost: PanelContainer
var _inventory_drag_icon: TextureRect
var _inventory_drag_source_icon: TextureRect
var _inventory_slots: Array[PanelContainer] = []
var _inventory_bars: Array[ProgressBar] = []
var _inventory_menu_slots: Array[PanelContainer] = []
var _inventory_menu_bars: Array[ProgressBar] = []
var _inventory_overlay: ColorRect
var _inventory_menu_grid: GridContainer
var _inventory_title: Label
var _selected_inventory_slot := 0
var _thermal_surface: ColorRect
var _thermal_material: ShaderMaterial
var _thermal_time := 0.0
var _hud_hidden := false
var _gameplay_hud_surfaces: Array[CanvasItem] = []
var _gameplay_hud_modulates: Array[Color] = []


func _process(delta: float) -> void:
	_thermal_time += delta
	if _thermal_material != null and _thermal_surface.visible:
		_thermal_material.set_shader_parameter("pulse_time", _thermal_time)
	_message_time_left = maxf(0.0, _message_time_left - delta)
	if _message_time_left > 0.0:
		message_label.visible = true
	elif not _hold_message.is_empty():
		message_label.text = _hold_message
		message_label.visible = true
		var pulse := 0.62 + 0.38 * sin(_thermal_time * 5.2)
		message_label.add_theme_color_override("font_color",
			Palette.ALERT.lerp(Palette.AMBER, pulse * 0.42))
	else:
		message_label.visible = false
		message_label.remove_theme_color_override("font_color")
	_fps_update_left -= delta
	if _fps_update_left <= 0.0:
		_fps_update_left = .25
		fps_label.text = "FPS %d" % Engine.get_frames_per_second()
	if _inventory_drag_ghost != null and _inventory_drag_ghost.visible:
		_inventory_drag_ghost.position = get_viewport().get_mouse_position() \
			- _inventory_drag_ghost.size * .5


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo \
				and (key.keycode == KEY_F1 or key.physical_keycode == KEY_F1):
			set_hud_hidden(not _hud_hidden)
			get_viewport().set_input_as_handled()
			return
	# Finish even when the pointer is released between slots. Plain gui_input
	# does not guarantee a release callback after leaving its source Control.
	if _inventory_drag_from >= 0 and event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and not (event as InputEventMouseButton).pressed:
		_drop_inventory_at((event as InputEventMouseButton).position)
		get_viewport().set_input_as_handled()


func _cache_gameplay_hud_surfaces() -> void:
	_gameplay_hud_surfaces.clear()
	_gameplay_hud_modulates.clear()
	for path in GAMEPLAY_HUD_NODE_PATHS:
		var surface := get_node_or_null(path) as CanvasItem
		if surface == null:
			continue
		_gameplay_hud_surfaces.append(surface)
		_gameplay_hud_modulates.append(surface.modulate)


func _build_thermal_warning() -> void:
	_thermal_surface = ColorRect.new()
	_thermal_surface.name = "ThermalWarning"
	_thermal_surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	_thermal_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thermal_surface.z_index = -9
	var shader := Shader.new()
	shader.code = THERMAL_WARNING_SHADER
	_thermal_material = ShaderMaterial.new()
	_thermal_material.shader = shader
	_thermal_surface.material = _thermal_material
	_thermal_surface.visible = false
	add_child(_thermal_surface)


func _set_thermal_warning(heat: float, cold: float) -> void:
	if _thermal_material == null:
		return
	var heat_strength := clampf(heat, 0.0, 1.0)
	var cold_strength := clampf(cold, 0.0, 1.0)
	_thermal_material.set_shader_parameter("heat", heat_strength)
	_thermal_material.set_shader_parameter("cold", cold_strength)
	_thermal_surface.visible = maxf(heat_strength, cold_strength) > .001


func thermal_effect_strengths() -> Vector2:
	if _thermal_material == null:
		return Vector2.ZERO
	return Vector2(float(_thermal_material.get_shader_parameter("heat")),
		float(_thermal_material.get_shader_parameter("cold")))


## Alpha is used instead of `visible` so timers, objectives and prompts keep
## updating behind the clean view. Restoring F1 therefore returns the exact HUD
## state that would have been visible at that moment.
func set_hud_hidden(hidden: bool) -> void:
	if hidden == _hud_hidden:
		return
	_hud_hidden = hidden
	for index in _gameplay_hud_surfaces.size():
		var surface := _gameplay_hud_surfaces[index]
		if not is_instance_valid(surface):
			continue
		if hidden:
			_gameplay_hud_modulates[index] = surface.modulate
			var transparent := surface.modulate
			transparent.a = 0.0
			surface.modulate = transparent
		else:
			surface.modulate = _gameplay_hud_modulates[index]


func hud_is_hidden() -> bool:
	return _hud_hidden


func update_objective(depth: int, relays_collected: int, relay_target: int) -> void:
	depth_label.text = "DEPTH %02d" % depth
	relay_label.text = "%d/%d SIGNAL RELAYS" % [relays_collected, relay_target]
	danger_row.visible = false


func update_infinite_status(relays_collected: int, loaded_chunks: int,
		danger_percent: int) -> void:
	var danger := clampi(danger_percent, 0, 100)
	relay_label.text = "RELAYS %d // CHUNKS %d" % [relays_collected, loaded_chunks]
	danger_row.visible = true
	danger_label.text = "DANGER %d%%" % danger
	danger_bar.value = danger
	var color := COLOR_METER_SAFE if danger < 40 else (
		COLOR_METER_WARN if danger < 75 else COLOR_METER_LOW)
	danger_label.add_theme_color_override("font_color", color)
	var fill := danger_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null:
		fill.bg_color = color


func update_inventory(selected_item: String, taser_cooldown: float,
		durability: Dictionary = {}, owned: Dictionary = {}, order: Array = [],
		maximums: Dictionary = {}, selected_slot: int = -1,
		slot_durability: Array = []) -> void:
	var resolved_order := order if order.size() >= PlayerController3D.HOTBAR_SIZE \
		else ["flashlight", "", "", "", ""]
	_selected_inventory_slot = clampi(selected_slot, 0,
		maxi(0, resolved_order.size() - 1)) if selected_slot >= 0 else 0
	_ensure_inventory_menu_capacity(resolved_order.size())
	for index in _inventory_slots.size():
		var item_id := String(resolved_order[index])
		var has_item := bool(owned.get(item_id, false))
		var is_selected := index == selected_slot if selected_slot >= 0 \
			else selected_item == item_id and has_item
		_apply_inventory_slot(_inventory_slots[index], _inventory_bars[index], index,
			item_id, has_item, is_selected, taser_cooldown, durability, maximums,
			slot_durability)
	for index in _inventory_menu_slots.size():
		var item_id := String(resolved_order[index])
		var has_item := bool(owned.get(item_id, false))
		_apply_inventory_slot(_inventory_menu_slots[index],
			_inventory_menu_bars[index], index, item_id, has_item,
			index == selected_slot, taser_cooldown, durability, maximums,
			slot_durability)
	if _inventory_title != null:
		var extra := maxi(0, resolved_order.size() - PlayerController3D.HOTBAR_SIZE)
		_inventory_title.text = "INVENTORY // %d SLOTS%s" % [resolved_order.size(),
			" // BACKPACK +%d" % extra if extra > 0 else ""]


func _apply_inventory_slot(slot: PanelContainer, bar: ProgressBar, index: int,
		item_id: String, has_item: bool, selected: bool, taser_cooldown: float,
		durability: Dictionary, maximums: Dictionary,
		slot_durability: Array = []) -> void:
	slot.add_theme_stylebox_override("panel", _hotbar_slot_style(selected))
	slot.modulate = Color.WHITE if has_item else Color(0.48, 0.5, 0.51, .72)
	var icon := slot.get_node("Stack/Icon") as TextureRect
	icon.texture = ITEM_TEXTURES.get(item_id) if has_item else null
	var caption := slot.get_node("Stack/Caption") as Label
	caption.text = str(index + 1)
	slot.tooltip_text = String(PlayerController3D.INVENTORY_LABELS.get(
		item_id, "EMPTY SLOT")).to_upper()
	bar.visible = has_item and (item_id == "taser" or maximums.has(item_id))
	if item_id == "taser":
		bar.value = clampf(1.0 - taser_cooldown / GameConfig.TASER_COOLDOWN_SECONDS,
			0.0, 1.0) * 100.0
	else:
		var max_value := maxi(1, int(maximums.get(item_id, 1)))
		var remaining := int(slot_durability[index]) \
			if index < slot_durability.size() else int(durability.get(item_id, 0))
		bar.value = clampf(float(remaining) / max_value,
			0.0, 1.0) * 100.0


func _prepare_inventory_slots() -> void:
	_inventory_slots.assign([flashlight_slot, taser_slot, lockpick_slot,
		crowbar_slot, rescue_axe_slot])
	for index in _inventory_slots.size():
		var slot := _inventory_slots[index]
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.focus_mode = Control.FOCUS_ALL
		slot.gui_input.connect(func(event: InputEvent) -> void:
			_inventory_slot_input(event, index, slot))
		slot.focus_entered.connect(func() -> void:
			slot.self_modulate = Color(1.18, 1.12, .86))
		slot.focus_exited.connect(func() -> void:
			slot.self_modulate = Color.WHITE)
		var stack := slot.get_node("Stack") as VBoxContainer
		var bar := ProgressBar.new()
		bar.name = "DurabilityBar"
		bar.custom_minimum_size = Vector2(0, 3)
		bar.max_value = 100.0
		bar.value = 100.0
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var background := StyleBoxFlat.new()
		background.bg_color = Color(0.106, 0.063, 0.086, .96)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.455, 0.722, 0.553, 1.0)
		bar.add_theme_stylebox_override("background", background)
		bar.add_theme_stylebox_override("fill", fill)
		stack.add_child(bar)
		_inventory_bars.append(bar)


func _build_inventory_overlay() -> void:
	_inventory_overlay = ColorRect.new()
	_inventory_overlay.name = "InventoryOverlay"
	_inventory_overlay.color = Color(0.0, 0.0, 0.0, .76)
	_inventory_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_inventory_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inventory_overlay.z_index = 80
	add_child(_inventory_overlay)
	_build_inventory_drag_ghost()
	var panel := PanelContainer.new()
	panel.name = "InventoryPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -150
	panel.offset_top = -122
	panel.offset_right = 150
	panel.offset_bottom = 122
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override("panel",
		Palette.panel_box(Palette.PANEL, Palette.PANEL_EDGE, 9))
	_inventory_overlay.add_child(panel)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)
	_inventory_title = Label.new()
	_inventory_title.name = "InventoryTitle"
	_inventory_title.text = "INVENTORY // 5 SLOTS"
	_inventory_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inventory_title.add_theme_color_override("font_color", Palette.AMBER)
	_inventory_title.add_theme_font_size_override("font_size", 10)
	column.add_child(_inventory_title)
	_inventory_menu_grid = GridContainer.new()
	_inventory_menu_grid.name = "InventorySlots"
	_inventory_menu_grid.columns = PlayerController3D.HOTBAR_SIZE
	_inventory_menu_grid.add_theme_constant_override("h_separation", 5)
	_inventory_menu_grid.add_theme_constant_override("v_separation", 5)
	column.add_child(_inventory_menu_grid)
	_ensure_inventory_menu_capacity(PlayerController3D.HOTBAR_SIZE)
	set_inventory_open(false)


func _build_inventory_drag_ghost() -> void:
	_inventory_drag_ghost = PanelContainer.new()
	_inventory_drag_ghost.name = "InventoryDragGhost"
	_inventory_drag_ghost.size = Vector2(48, 48)
	_inventory_drag_ghost.custom_minimum_size = Vector2(48, 48)
	_inventory_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inventory_drag_ghost.z_index = 240
	_inventory_drag_ghost.modulate = Color(1.0, 1.0, 1.0, .92)
	_inventory_drag_ghost.add_theme_stylebox_override("panel", _hotbar_slot_style(true))
	add_child(_inventory_drag_ghost)
	_inventory_drag_icon = TextureRect.new()
	_inventory_drag_icon.name = "DraggedItemIcon"
	_inventory_drag_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_inventory_drag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_inventory_drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inventory_drag_ghost.add_child(_inventory_drag_icon)
	_inventory_drag_ghost.visible = false


func _ensure_inventory_menu_capacity(capacity: int) -> void:
	if _inventory_menu_grid == null or capacity == _inventory_menu_slots.size():
		return
	for child in _inventory_menu_grid.get_children():
		child.queue_free()
	_inventory_menu_slots.clear()
	_inventory_menu_bars.clear()
	for index in capacity:
		var slot := PanelContainer.new()
		slot.name = "InventorySlot%d" % (index + 1)
		slot.custom_minimum_size = Vector2(44, 52)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.focus_mode = Control.FOCUS_ALL
		slot.add_theme_stylebox_override("panel", _hotbar_slot_style(false))
		slot.gui_input.connect(func(event: InputEvent) -> void:
			_inventory_slot_input(event, index, slot))
		slot.focus_entered.connect(func() -> void:
			slot.self_modulate = Color(1.18, 1.12, .86))
		slot.focus_exited.connect(func() -> void:
			slot.self_modulate = Color.WHITE)
		_inventory_menu_grid.add_child(slot)
		var stack := VBoxContainer.new()
		stack.name = "Stack"
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		slot.add_child(stack)
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.custom_minimum_size = Vector2(36, 36)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(icon)
		var caption := Label.new()
		caption.name = "Caption"
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_font_size_override("font_size", 8)
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(caption)
		var bar := ProgressBar.new()
		bar.name = "DurabilityBar"
		bar.custom_minimum_size = Vector2(0, 4)
		bar.max_value = 100.0
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var background := StyleBoxFlat.new()
		background.bg_color = Color(0.106, 0.063, 0.086, .96)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.455, 0.722, 0.553, 1.0)
		bar.add_theme_stylebox_override("background", background)
		bar.add_theme_stylebox_override("fill", fill)
		stack.add_child(bar)
		_inventory_menu_slots.append(slot)
		_inventory_menu_bars.append(bar)


func inventory_is_open() -> bool:
	return _inventory_overlay != null and _inventory_overlay.visible


func toggle_inventory() -> void:
	set_inventory_open(not inventory_is_open())


func set_inventory_open(shown: bool) -> void:
	if _inventory_overlay == null:
		return
	_inventory_overlay.visible = shown
	MouseLock.claim("inventory", shown)
	if shown and not _inventory_menu_slots.is_empty():
		_inventory_menu_slots[clampi(_selected_inventory_slot, 0,
			_inventory_menu_slots.size() - 1)].grab_focus.call_deferred()
	else:
		_finish_inventory_drag()
	inventory_open_changed.emit(shown)


func _inventory_slot_input(event: InputEvent, index: int,
		source_slot: PanelContainer = null) -> void:
	if event.is_action_pressed("ui_accept"):
		if _inventory_drag_from < 0:
			_inventory_drag_from = index
			_begin_inventory_drag(source_slot, false)
		else:
			if index != _inventory_drag_from:
				inventory_reorder_requested.emit(_inventory_drag_from, index)
			_finish_inventory_drag()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton \
			or (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	var mouse := event as InputEventMouseButton
	if mouse.pressed:
		_inventory_drag_from = index
		_begin_inventory_drag(source_slot)
		get_viewport().set_input_as_handled()
		return
	if _inventory_drag_from < 0:
		return
	_drop_inventory_at(mouse.position)
	get_viewport().set_input_as_handled()


func _drop_inventory_at(pointer: Vector2) -> void:
	if _inventory_drag_from < 0:
		return
	var destination := _inventory_drag_from
	for slots in [_inventory_slots, _inventory_menu_slots]:
		for slot_index in slots.size():
			if (slots[slot_index] as PanelContainer).get_global_rect().has_point(pointer):
				destination = slot_index
				break
	if destination != _inventory_drag_from:
		inventory_reorder_requested.emit(_inventory_drag_from, destination)
	_finish_inventory_drag()


func _begin_inventory_drag(source_slot: PanelContainer,
		show_pointer_ghost: bool = true) -> void:
	_finish_inventory_drag(false)
	if source_slot == null:
		return
	var source_icon := source_slot.get_node_or_null("Stack/Icon") as TextureRect
	if source_icon == null or source_icon.texture == null:
		return
	_inventory_drag_source_icon = source_icon
	_inventory_drag_source_icon.self_modulate = Color(1.0, 1.0, 1.0, .22)
	_inventory_drag_icon.texture = source_icon.texture
	_inventory_drag_ghost.visible = show_pointer_ghost
	_inventory_drag_ghost.position = get_viewport().get_mouse_position() \
		- _inventory_drag_ghost.size * .5


func _finish_inventory_drag(clear_slot: bool = true) -> void:
	if _inventory_drag_source_icon != null and is_instance_valid(
			_inventory_drag_source_icon):
		_inventory_drag_source_icon.self_modulate = Color.WHITE
	_inventory_drag_source_icon = null
	if _inventory_drag_icon != null:
		_inventory_drag_icon.texture = null
	if _inventory_drag_ghost != null:
		_inventory_drag_ghost.visible = false
	if clear_slot:
		_inventory_drag_from = -1


func _hotbar_slot_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.078, 0.043, 0.063, .94)
	var width := 2 if selected else 1
	style.set_border_width_all(width)
	style.border_color = Palette.AMBER if selected else Color(0.3, 0.14, 0.18, .92)
	style.corner_radius_top_left = 1
	style.corner_radius_top_right = 1
	style.corner_radius_bottom_left = 1
	style.corner_radius_bottom_right = 1
	return style


func _refresh_compact_status() -> void:
	compact_stamina_bar.value = _stamina_percent
	var fill := compact_stamina_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if _stamina_percent < 20:
		fill.bg_color = COLOR_METER_LOW
	elif _stamina_percent < 45:
		fill.bg_color = COLOR_METER_WARN
	else:
		fill.bg_color = COLOR_METER_STAMINA_NORMAL


func set_escape_active(active: bool) -> void:
	escape_overlay.visible = active
	# Minimal guidance content: show current grabber and the action to break
	# free if the overlay is visible. The label nodes exist in the scene; if a
	# themed design isn’t present this remains a no-op.
	var title: Label = escape_overlay.get_node_or_null("TitleLabel")
	var hint: Label = escape_overlay.get_node_or_null("HintLabel")
	if title != null:
		var id := GameState.escape_hunter_id
		if id.is_empty():
			title.text = "GRABBED"
		else:
			var name := String(HunterRoster.get_identity(id).get("display_name", id)).to_upper()
			title.text = "%s GRIP" % name
	if hint != null:
		hint.text = "PRESS E TO BREAK FREE"


func update_escape(progress: int, required: int, remaining: float, duration: float) -> void:
	escape_progress_bar.max_value = required
	escape_progress_bar.value = progress
	escape_time_bar.max_value = duration
	escape_time_bar.value = remaining
	# Optional numeric footer if present: "1.3s // 3 / 6"
	var footer: Label = escape_overlay.get_node_or_null("FooterLabel")
	if footer != null:
		var seconds := "%.1fs" % maxf(0.0, remaining)
		footer.text = "%s // %d / %d" % [seconds, progress, required]


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


## Exposure and noise remain explicit facility-pressure meters. Temperature is
## communicated in-world: Solyth/heat adds an orange haze and Wynelle/cold adds
## white pixel icicles, so there is no separate temperature bar competing with
## the chase warning.
func update_meters(meters: PlayerMeters, hunter_heat: float = 0.0,
		hunter_cold: float = 0.0) -> void:
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

	var meter_heat := clampf((meters.temperature - 76.0) / 24.0, 0.0, 1.0)
	var meter_cold := clampf((34.0 - meters.temperature) / 34.0, 0.0, 1.0)
	_set_thermal_warning(maxf(meter_heat, hunter_heat),
		maxf(meter_cold, hunter_cold))


func set_interaction_prompt(text: String) -> void:
	interaction_label.text = text


func show_message(text: String) -> void:
	message_label.remove_theme_color_override("font_color")
	# toast treatment: letter-spaced amber line with a dark outline
	message_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, .85))
	message_label.add_theme_constant_override("outline_size", 2)
	message_label.text = text
	message_label.visible = true
	_message_time_left = MESSAGE_DURATION


## Persistent HUD line for a live pressure rule. Toast messages still win
## while they are up, then this text returns until cleared.
func set_hold_message(text: String) -> void:
	_hold_message = text
	if text.is_empty():
		if _message_time_left <= 0.0:
			message_label.visible = false
			message_label.remove_theme_color_override("font_color")
		return
	if _message_time_left <= 0.0:
		message_label.text = text
		message_label.visible = true


func toggle_map_overlay() -> void:
	map_overlay.visible = not map_overlay.visible


func set_map_open(shown: bool) -> void:
	map_overlay.visible = shown


func _on_map_overlay_visibility_changed() -> void:
	var shown := map_overlay.visible
	MouseLock.claim("map", shown)
	if shown:
		plan.grab_focus.call_deferred()
	else:
		plan.set("_dragging", false)
	map_open_changed.emit(shown)


## The full map is only worth redrawing while somebody is looking at it, and
## the original charges the same price for reading it: your view of the
## room. The minimap has no such gate -- it is always up, which is exactly
## why it never gets hunter marks the way the full map does (see
## main_3d.gd's _minimap_marks): giving up peripheral vision for hunter
## intel is the original's whole trade, and a permanent widget that showed
## them for free would erase it.
func map_is_open() -> bool:
	return map_overlay.visible


func update_map(generator: FacilityGenerator, at: Vector2, facing: Vector2,
		marks: Array, player_marks: Array = [], drop_marks: Array = [],
		safe_room_marks: Array = []) -> void:
	plan.show_state(generator, at, facing, marks, player_marks, drop_marks, safe_room_marks)


func update_minimap(generator: FacilityGenerator, at: Vector2, facing: Vector2,
		marks: Array, player_marks: Array = [], drop_marks: Array = [],
		safe_room_marks: Array = []) -> void:
	minimap.show_state(generator, at, facing, marks, player_marks, drop_marks, safe_room_marks)


func update_streamed_map(chunks: Dictionary, level: int, chunk_size: int,
		at: Vector2, facing: Vector2, marks: Array,
		player_marks: Array = [], show_regions: bool = false,
		drop_marks: Array = [], safe_room_marks: Array = []) -> void:
	map_title.text = "DISCOVERED ROUTE // FLOOR %+d" % level
	plan.show_streamed_state(chunks, level, chunk_size, at, facing, marks, true,
		0, player_marks, show_regions, drop_marks, safe_room_marks)


func update_streamed_minimap(chunks: Dictionary, level: int, chunk_size: int,
		at: Vector2, facing: Vector2, marks: Array = [],
		player_marks: Array = [], show_regions: bool = false,
		drop_marks: Array = [], safe_room_marks: Array = []) -> void:
	minimap.show_streamed_state(chunks, level, chunk_size, at, facing, marks,
		false, STREAMED_MINIMAP_RADIUS_CELLS, player_marks, show_regions,
		drop_marks, safe_room_marks)
