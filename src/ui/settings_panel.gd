class_name SettingsPanel
extends Control

## Same-scene overlay toggled by main_menu.gd, mirroring hud.gd's MapOverlay
## pattern. Pure UI — persistence and InputMap changes go through the
## Settings autoload so gameplay scenes see the same state.

const ACTION_LABELS := {
	"move_left": "MOVE LEFT",
	"move_right": "MOVE RIGHT",
	"move_up": "MOVE UP",
	"move_down": "MOVE DOWN",
	"look_left": "LOOK LEFT",
	"look_right": "LOOK RIGHT",
	"look_up": "LOOK UP",
	"look_down": "LOOK DOWN",
	"sprint": "SPRINT",
	"crouch": "CROUCH",
	"jump": "JUMP / HOP",
	"flashlight": "FLASHLIGHT",
	"taser": "TASER",
	"tool_use": "USE HELD TOOL",
	"interact": "INTERACT",
	"inventory": "INVENTORY",
	"drop_item": "DROP HELD ITEM",
	"chat": "ROOM CHAT",
	"toggle_map": "TOGGLE MAP",
	"player_list": "PLAYER LIST (HOLD)",
	"pause": "PAUSE",
	"office_left_door": "OFFICE — LEFT DOOR",
	"office_right_door": "OFFICE — RIGHT DOOR",
	"office_desk_light": "OFFICE — DESK LIGHT",
	"office_vent": "OFFICE — VENT HATCH",
	"office_cameras": "OFFICE — MONITOR",
	"office_radio": "OFFICE — RADIO",
	"office_breaker": "OFFICE — BREAKER",
	"office_reboot": "OFFICE — CAMERA REBOOT",
	"office_emergency_flash": "OFFICE — EMERGENCY FLASH",
	"office_rear_flash": "OFFICE — REAR FLASH",
}

## The web build prints a bound key in amber, the colour it uses everywhere
## for "this is a system readout".
const LISTENING_TEXT := "PRESS A KEY..."

## Bindings are grouped under tabs, the way the web build's Controls screen groups them: a flat list of every action is a wall
## of text. The tabs shown come from ControlsRegistry for the game that is open (GameRegistry.active_game_id): Last Route shows
## MOVEMENT / ACTIONS / SYSTEM; other games register their own (Night Watch: OFFICE).
var SECTIONS: Array = ControlsRegistry.tabs_for(GameRegistry.active_game_id)

@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_value_label: Label = %VolumeValueLabel
@onready var sfx_volume_slider: HSlider = %SfxVolumeSlider
@onready var sfx_volume_value_label: Label = %SfxVolumeValueLabel
@onready var ui_volume_slider: HSlider = %UiVolumeSlider
@onready var ui_volume_value_label: Label = %UiVolumeValueLabel
@onready var fullscreen_button: Button = %FullscreenButton
@onready var vsync_button: Button = %VsyncButton
@onready var fps_limit_slider: HSlider = %FpsLimitSlider
@onready var fps_limit_value_label: Label = %FpsLimitValueLabel
@onready var fov_slider: HSlider = %FovSlider
@onready var fov_value_label: Label = %FovValueLabel
@onready var sensitivity_slider: HSlider = %SensitivitySlider
@onready var sensitivity_value_label: Label = %SensitivityValueLabel
@onready var pixel_effect_slider: HSlider = %PixelEffectSlider
@onready var pixel_effect_value_label: Label = %PixelEffectValueLabel
@onready var player_hue_slider: HSlider = %PlayerHueSlider
@onready var player_hue_value_label: Label = %PlayerHueValueLabel
@onready var controls_list: VBoxContainer = %ControlsList
@onready var close_button: Button = %CloseButton

var _focus_pause_button: Button
var _waypoint_button: Button
var _listening_action := ""
var _listening_button: Button = null
var _listening_append := false
var _key_labels: Dictionary = {}
var _section_tabs: TabBar
var _active_section := 0
var _settings_tabs: TabBar
var _active_settings_category := 0
var _skin_panel: SkinPanel
var _voice_panel: VoicePanel
var _mods_panel: ModsPanel


func _ready() -> void:
	volume_slider.value_changed.connect(_on_volume_changed)
	sfx_volume_slider.value_changed.connect(_on_sfx_volume_changed)
	ui_volume_slider.value_changed.connect(_on_ui_volume_changed)
	fullscreen_button.toggled.connect(Settings.set_fullscreen)
	vsync_button.toggled.connect(Settings.set_vsync)
	fps_limit_slider.value_changed.connect(_on_fps_limit_changed)
	fov_slider.value_changed.connect(_on_fov_changed)
	sensitivity_slider.min_value = Settings.MIN_MOUSE_SENSITIVITY
	sensitivity_slider.max_value = Settings.MAX_MOUSE_SENSITIVITY
	sensitivity_slider.step = 0.0001
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	pixel_effect_slider.value_changed.connect(_on_pixel_effect_changed)
	player_hue_slider.value_changed.connect(_on_player_hue_changed)
	# F11 works anywhere, so the toggle can be flipped from outside this panel
	# while it is open.
	Settings.display_changed.connect(_refresh_from_settings)
	close_button.pressed.connect(close)
	_build_focus_pause_row()
	_build_waypoint_toggle_row()
	_build_voice_rows()
	_apply_palette()
	_build_settings_tabs()
	_build_control_rows()
	_refresh_from_settings()


## Runs before Control's own GUI input dispatch, so a REBIND button that
## still has focus can't eat Enter/Space/arrow presses as UI navigation
## before we get a chance to capture them.
func _input(event: InputEvent) -> void:
	if _listening_action.is_empty():
		return
	if not (event is InputEventKey or event is InputEventMouseButton):
		return
	if event is InputEventKey and (not event.pressed or event.echo):
		return
	if event is InputEventMouseButton and not event.pressed:
		return
	get_viewport().set_input_as_handled()

	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		_stop_listening()
		return

	var action := _listening_action
	var append := _listening_append
	_stop_listening()
	var new_event: InputEvent
	if event is InputEventKey:
		new_event = InputEventKey.new()
		(new_event as InputEventKey).physical_keycode = (event as InputEventKey).physical_keycode
	else:
		new_event = InputEventMouseButton.new()
		(new_event as InputEventMouseButton).button_index = (event as InputEventMouseButton).button_index
	Settings.set_action_binding(action, new_event, append)
	_key_labels[action].text = Settings.get_action_key_label(action)


func open() -> void:
	_refresh_from_settings()
	visible = true
	_settings_tabs.grab_focus.call_deferred()


func close() -> void:
	_stop_listening()
	visible = false


func _refresh_from_settings() -> void:
	volume_slider.value = Settings.master_volume_percent
	_update_volume_label(Settings.master_volume_percent)
	sfx_volume_slider.set_value_no_signal(Settings.sfx_volume_percent)
	_update_sfx_volume_label(Settings.sfx_volume_percent)
	ui_volume_slider.set_value_no_signal(Settings.ui_volume_percent)
	_update_ui_volume_label(Settings.ui_volume_percent)
	fullscreen_button.set_pressed_no_signal(Settings.fullscreen)
	Palette.set_state_toggle(fullscreen_button, Settings.fullscreen)
	vsync_button.set_pressed_no_signal(Settings.vsync_enabled)
	Palette.set_state_toggle(vsync_button, Settings.vsync_enabled)
	_focus_pause_button.set_pressed_no_signal(Settings.pause_on_focus_loss)
	Palette.set_state_toggle(_focus_pause_button, Settings.pause_on_focus_loss)
	fps_limit_slider.set_value_no_signal(Settings.fps_limit)
	_update_fps_limit_label(Settings.fps_limit)
	fov_slider.set_value_no_signal(Settings.field_of_view)
	_update_fov_label(Settings.field_of_view)
	sensitivity_slider.set_value_no_signal(Settings.mouse_sensitivity)
	_update_sensitivity_label(Settings.mouse_sensitivity)
	pixel_effect_slider.set_value_no_signal(Settings.pixel_effect_percent)
	_update_pixel_effect_label(Settings.pixel_effect_percent)
	player_hue_slider.set_value_no_signal(Settings.player_hue_degrees)
	_update_player_hue_label(Settings.player_hue_degrees)
	for action in _key_labels:
		_key_labels[action].text = Settings.get_action_key_label(action)


func _on_volume_changed(value: float) -> void:
	Settings.set_master_volume(value)
	_update_volume_label(value)


func _update_volume_label(value: float) -> void:
	volume_value_label.text = "%d%%" % int(round(value))


func _on_sfx_volume_changed(value: float) -> void:
	Settings.set_sfx_volume(value)
	_update_sfx_volume_label(value)


func _update_sfx_volume_label(value: float) -> void:
	sfx_volume_value_label.text = "%d%%" % roundi(value)


func _on_ui_volume_changed(value: float) -> void:
	Settings.set_ui_volume(value)
	_update_ui_volume_label(value)


func _update_ui_volume_label(value: float) -> void:
	ui_volume_value_label.text = "%d%%" % roundi(value)


func _on_fps_limit_changed(value: float) -> void:
	Settings.set_fps_limit(value)
	_update_fps_limit_label(Settings.fps_limit)


func _update_fps_limit_label(value: float) -> void:
	fps_limit_value_label.text = "UNLIMITED" if value < 15.0 else "%d" % roundi(value)


func _on_fov_changed(value: float) -> void:
	Settings.set_field_of_view(value)
	_update_fov_label(value)


func _update_fov_label(value: float) -> void:
	fov_value_label.text = "%d°" % roundi(value)


func _on_sensitivity_changed(value: float) -> void:
	Settings.set_mouse_sensitivity(value)
	_update_sensitivity_label(value)


func _on_pixel_effect_changed(value: float) -> void:
	Settings.set_pixel_effect_percent(value)
	_update_pixel_effect_label(value)


func _update_pixel_effect_label(value: float) -> void:
	pixel_effect_value_label.text = "%d%%" % int(round(value))


func _on_player_hue_changed(value: float) -> void:
	Settings.set_player_hue_degrees(value)
	_update_player_hue_label(value)


func _update_player_hue_label(value: float) -> void:
	player_hue_value_label.text = "ORIGINAL" if value < .5 else "%d°" % roundi(value)


## Shown as a plain 1-100 dial rather than radians per pixel, which is the
## number the code needs and not one anyone can reason about.
func _update_sensitivity_label(value: float) -> void:
	var span := Settings.MAX_MOUSE_SENSITIVITY - Settings.MIN_MOUSE_SENSITIVITY
	var ratio := (value - Settings.MIN_MOUSE_SENSITIVITY) / span
	sensitivity_value_label.text = "%d" % maxi(1, int(round(ratio * 100.0)))


## Same reasoning as the menu: colours come from Palette at load, never from
## the scene file, so one edit restyles every screen at once.
func _apply_palette() -> void:
	# The script extends Control but the scene node is a ColorRect, so `color`
	# is not on the static type. set() reaches it without a cast the compiler
	# would reject, and does nothing if the node is ever changed to a Panel.
	set("color", Palette.PANEL)
	var title := get_node_or_null("Title") as Label
	if title != null:
		Palette.style_title(title)
	var hint := get_node_or_null("HintLabel") as Label
	if hint != null:
		hint.add_theme_color_override("font_color", Palette.MUTED)
	for path in ["VolumeRow/VolumeLabel", "VolumeRow/VolumeValueLabel",
			"SfxVolumeRow/SfxVolumeLabel", "SfxVolumeRow/SfxVolumeValueLabel",
			"UiVolumeRow/UiVolumeLabel", "UiVolumeRow/UiVolumeValueLabel",
			"SensitivityRow/SensitivityLabel", "SensitivityRow/SensitivityValueLabel",
			"PixelEffectRow/PixelEffectLabel", "PixelEffectRow/PixelEffectValueLabel",
			"PlayerHueRow/PlayerHueLabel", "PlayerHueRow/PlayerHueValueLabel",
			"DisplayRow/DisplayLabel", "VsyncRow/VsyncLabel",
			"FpsLimitRow/FpsLimitLabel", "FpsLimitRow/FpsLimitValueLabel",
			"FovRow/FovLabel", "FovRow/FovValueLabel"]:
		var label := get_node_or_null(path) as Label
		if label != null:
			label.add_theme_color_override("font_color", Palette.BODY)
	var display_hint := get_node_or_null("DisplayRow/FullscreenHint") as Label
	if display_hint != null:
		display_hint.add_theme_color_override("font_color", Palette.MUTED)
	Palette.style_escape_close(close_button)
	var fullscreen := get_node_or_null("DisplayRow/FullscreenButton") as Button
	if fullscreen != null:
		Palette.style_state_toggle(fullscreen, "FULLSCREEN", Settings.fullscreen)
	Palette.style_state_toggle(vsync_button, "VSYNC", Settings.vsync_enabled)
	Palette.style_state_toggle(_focus_pause_button, "PAUSE WHEN WINDOW LOSES FOCUS", Settings.pause_on_focus_loss)
	if _waypoint_button != null:
		_waypoint_button.set_pressed_no_signal(Settings.teammate_waypoints)
		Palette.style_state_toggle(_waypoint_button, "TEAMMATE WAYPOINTS", Settings.teammate_waypoints)


func _build_control_rows() -> void:
	_section_tabs = TabBar.new()
	_section_tabs.name = "ControlCategoryTabs"
	_section_tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	for section in SECTIONS:
		_section_tabs.add_tab(String(section["title"]))
	_section_tabs.tab_changed.connect(_show_control_section)
	controls_list.add_child(_section_tabs)
	_show_control_section(0)


## DISPLAY: teammate waypoints on the HUD (and on the maps), on by default.
func _build_waypoint_toggle_row() -> void:
	var row := HBoxContainer.new()
	row.name = "TeammateWaypointsRow"
	row.offset_left = 20.0
	row.offset_top = 226.0
	row.offset_right = 420.0
	row.offset_bottom = 240.0
	var button := Button.new()
	button.name = "TeammateWaypointsButton"
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = "Name and distance markers for your co-op teammates, also shown on the minimap and map."
	button.toggled.connect(func(enabled: bool) -> void:
		Settings.set_teammate_waypoints(enabled)
		Palette.set_state_toggle(button, enabled))
	row.add_child(button)
	add_child(row)
	_waypoint_button = button


func _build_focus_pause_row() -> void:
	var row := HBoxContainer.new()
	row.name = "FocusPauseRow"
	row.offset_left = 20.0
	row.offset_top = 208.0
	row.offset_right = 420.0
	row.offset_bottom = 224.0
	_focus_pause_button = Button.new()
	_focus_pause_button.name = "FocusPauseButton"
	_focus_pause_button.toggle_mode = true
	_focus_pause_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_focus_pause_button.toggled.connect(func(enabled: bool) -> void:
		Settings.set_pause_on_focus_loss(enabled)
		Palette.set_state_toggle(_focus_pause_button, enabled))
	row.add_child(_focus_pause_button)
	# GRAPHICS: AUTO follows the detected device tier (PlatformProfile / QualityTier); the label shows what AUTO picked.
	var graphics_button := Button.new()
	graphics_button.name = "GraphicsQualityButton"
	graphics_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var graphics_label := func() -> String:
		return "GRAPHICS: %s" % (("AUTO (%s)" % QualityTier.name_of(PlatformProfile.tier)) \
			if Settings.graphics_quality == "AUTO" else Settings.graphics_quality)
	graphics_button.text = graphics_label.call()
	graphics_button.tooltip_text = "Detected: %s" % PlatformProfile.tier_readout()
	graphics_button.pressed.connect(func() -> void:
		var choices: Array = Settings.GRAPHICS_CHOICES
		Settings.set_graphics_quality(choices[(choices.find(Settings.graphics_quality) + 1) % choices.size()])
		graphics_button.text = graphics_label.call()
		graphics_button.tooltip_text = "Detected: %s" % PlatformProfile.tier_readout())
	row.add_child(graphics_button)
	if PlatformProfile.is_phone:
		# Phones only: the movement control for TouchControls (desktop never shows this button).
		var move_button := Button.new()
		move_button.name = "TouchMoveButton"
		move_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		move_button.text = "MOVE: %s" % ("STICK" if Settings.touch_move == "stick" else "ARROWS")
		move_button.pressed.connect(func() -> void:
			Settings.set_touch_move("dpad" if Settings.touch_move == "stick" else "stick")
			move_button.text = "MOVE: %s" % ("STICK" if Settings.touch_move == "stick" else "ARROWS"))
		row.add_child(move_button)
	add_child(row)
	# In-world ads (flavour, TrollAds): OFF / GENTLE / ANNOYING, OFF by default. Troll mode overrides it for cheaters.
	var ads_button := Button.new()
	ads_button.name = "AdsModeButton"
	ads_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ads_button.tooltip_text = "In-world joke ads on shop signs, plus pop-ups (GENTLE: rare, skip any time; ANNOYING: frequent, sneaky skip)."
	ads_button.text = "ADS: %s" % Settings.ads_mode.to_upper()
	ads_button.pressed.connect(func() -> void:
		var modes: Array = TrollAds.MODES
		Settings.set_ads_mode(modes[(modes.find(Settings.ads_mode) + 1) % modes.size()])
		ads_button.text = "ADS: %s" % Settings.ads_mode.to_upper())
	$DisplayRow.add_child(ads_button)


## AUDIO: spoken chat volume, and voices / subtitles toggles (voices off = subtitles only).
func _build_voice_rows() -> void:
	var row := HBoxContainer.new()
	row.name = "VoiceVolumeRow"
	row.offset_left = 20.0
	row.offset_top = 142.0
	row.offset_right = 420.0
	row.offset_bottom = 158.0
	var label := Label.new()
	label.text = "SPOKEN CHAT"
	label.custom_minimum_size = Vector2(96, 0)
	label.add_theme_font_size_override("font_size", 8)
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = "VoiceVolumeSlider"
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = Settings.voice_volume
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var readout := Label.new()
	readout.text = "%d%%" % int(Settings.voice_volume)
	readout.custom_minimum_size = Vector2(34, 0)
	readout.add_theme_font_size_override("font_size", 8)
	row.add_child(readout)
	slider.value_changed.connect(func(value: float) -> void:
		readout.text = "%d%%" % int(value)
		Settings.set_voice(value, Settings.voice_enabled, Settings.voice_subtitles))
	add_child(row)
	var toggles := HBoxContainer.new()
	toggles.name = "VoiceToggleRow"
	toggles.offset_left = 20.0
	toggles.offset_top = 166.0
	toggles.offset_right = 420.0
	toggles.offset_bottom = 182.0
	for pair in [["VOICES", "voice_enabled"], ["SUBTITLES", "voice_subtitles"]]:
		var button := Button.new()
		button.name = "Voice%sButton" % String(pair[0]).capitalize()
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		Palette.style_state_toggle(button, String(pair[0]), bool(Settings.get(String(pair[1]))))
		button.set_pressed_no_signal(bool(Settings.get(String(pair[1]))))
		var key := String(pair[1])
		button.toggled.connect(func(enabled: bool) -> void:
			Settings.set_voice(Settings.voice_volume, enabled if key == "voice_enabled" else Settings.voice_enabled,
				enabled if key == "voice_subtitles" else Settings.voice_subtitles)
			Palette.set_state_toggle(button, enabled))
		toggles.add_child(button)
	add_child(toggles)


func _build_settings_tabs() -> void:
	_settings_tabs = TabBar.new()
	_settings_tabs.name = "SettingsCategoryTabs"
	_settings_tabs.position = Vector2(20, 37)
	_settings_tabs.size = Vector2(400, 22)
	_settings_tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	for title in ["AUDIO", "DISPLAY", "CONTROLS", "SKIN", "VOICE", "MODS"]:
		_settings_tabs.add_tab(title)
	_settings_tabs.tab_changed.connect(_show_settings_category)
	add_child(_settings_tabs)
	_skin_panel = SkinPanel.new()
	_skin_panel.position = Vector2(20, 66)
	_skin_panel.size = Vector2(400, 176)
	add_child(_skin_panel)
	_voice_panel = VoicePanel.new()
	_voice_panel.position = Vector2(20, 66)
	_voice_panel.size = Vector2(400, 176)
	add_child(_voice_panel)
	_mods_panel = ModsPanel.new()
	_mods_panel.position = Vector2(20, 66)
	_mods_panel.size = Vector2(400, 176)
	add_child(_mods_panel)
	_show_settings_category(0)


func _show_settings_category(index: int) -> void:
	_active_settings_category = clampi(index, 0, 5)
	for name in ["VolumeRow", "SfxVolumeRow", "UiVolumeRow", "VoiceVolumeRow", "VoiceToggleRow"]:
		get_node(name).visible = _active_settings_category == 0
	for name in ["DisplayRow", "VsyncRow", "FpsLimitRow", "FovRow",
			"PixelEffectRow", "PlayerHueRow", "SensitivityRow", "FocusPauseRow", "TeammateWaypointsRow"]:
		get_node(name).visible = _active_settings_category == 1
	$ControlsScroll.visible = _active_settings_category == 2
	if _skin_panel != null:
		_skin_panel.visible = _active_settings_category == 3
	if _voice_panel != null:
		_voice_panel.visible = _active_settings_category == 4
	if _mods_panel != null:
		_mods_panel.visible = _active_settings_category == 5


func _show_control_section(index: int) -> void:
	_active_section = clampi(index, 0, SECTIONS.size() - 1)
	for child in controls_list.get_children():
		if child != _section_tabs:
			child.queue_free()
	_key_labels.clear()
	if PlatformProfile.is_phone and _active_section == 0:
		_build_touch_look_rows()
	var active: Dictionary = SECTIONS[_active_section]
	for action in active["actions"]:
		if Settings.REBINDABLE_ACTIONS.has(action):
			_build_control_row(action)
	if String(active["title"]) == "ACTIONS" and SECTIONS.size() == ControlsRegistry.LAST_ROUTE_TABS.size():
		_build_waypoint_preferences()
	# Anything omitted from the organized categories is still reachable from
	# System instead of becoming an invisible binding.
	var placed := ControlsRegistry.registered_actions()
	var orphans: Array = Settings.REBINDABLE_ACTIONS.filter(
		func(a: String) -> bool: return not placed.has(a))
	if _active_section == SECTIONS.size() - 1 and not orphans.is_empty():
		var heading := Label.new()
		heading.text = Palette.track("OTHER")
		heading.add_theme_color_override("font_color", Palette.AMBER)
		heading.add_theme_font_size_override("font_size", 8)
		controls_list.add_child(heading)
		for action in orphans:
			_build_control_row(action)


## Phones only: TOUCH LOOK (TouchControls.look_turn) at the top of the first CONTROLS section. Desktop never builds it.
func _build_touch_look_rows() -> void:
	var heading := Label.new()
	heading.name = "TouchLookHeading"
	heading.text = Palette.track("TOUCH LOOK")
	heading.add_theme_color_override("font_color", Palette.AMBER)
	heading.add_theme_font_size_override("font_size", 8)
	controls_list.add_child(heading)
	_touch_slider("LOOK SPEED", 0.25, 3.0, Settings.touch_look_speed, func(value: float) -> void:
		Settings.set_touch_look(value, Settings.touch_look_vertical, Settings.touch_look_invert_y,
			Settings.touch_look_smoothing, Settings.touch_look_accel))
	_touch_slider("VERTICAL SPEED", 0.3, 1.5, Settings.touch_look_vertical, func(value: float) -> void:
		Settings.set_touch_look(Settings.touch_look_speed, value, Settings.touch_look_invert_y,
			Settings.touch_look_smoothing, Settings.touch_look_accel))
	var row := HBoxContainer.new()
	row.name = "TouchLookToggles"
	controls_list.add_child(row)
	var invert := _touch_toggle(row, func() -> String: return "INVERT Y: %s" % ("ON" if Settings.touch_look_invert_y else "OFF"))
	invert.pressed.connect(func() -> void:
		Settings.set_touch_look(Settings.touch_look_speed, Settings.touch_look_vertical, not Settings.touch_look_invert_y,
			Settings.touch_look_smoothing, Settings.touch_look_accel)
		invert.text = "INVERT Y: %s" % ("ON" if Settings.touch_look_invert_y else "OFF"))
	var smooth := _touch_toggle(row, func() -> String: return "SMOOTHING: %s" % Settings.touch_look_smoothing.to_upper())
	smooth.pressed.connect(func() -> void:
		var order := ["off", "low", "high"]
		var next: String = order[(order.find(Settings.touch_look_smoothing) + 1) % order.size()]
		Settings.set_touch_look(Settings.touch_look_speed, Settings.touch_look_vertical, Settings.touch_look_invert_y,
			next, Settings.touch_look_accel)
		smooth.text = "SMOOTHING: %s" % Settings.touch_look_smoothing.to_upper())
	var accel := _touch_toggle(row, func() -> String: return "ACCELERATION: %s" % ("ON" if Settings.touch_look_accel else "OFF"))
	accel.pressed.connect(func() -> void:
		Settings.set_touch_look(Settings.touch_look_speed, Settings.touch_look_vertical, Settings.touch_look_invert_y,
			Settings.touch_look_smoothing, not Settings.touch_look_accel)
		accel.text = "ACCELERATION: %s" % ("ON" if Settings.touch_look_accel else "OFF"))


func _touch_slider(label_text: String, low: float, high: float, value: float, changed: Callable) -> void:
	var row := HBoxContainer.new()
	row.name = label_text.replace(" ", "") + "Row"
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(96, 0)
	label.add_theme_font_size_override("font_size", 8)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(0, 22)   # a thumb-sized track on a phone
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var readout := Label.new()
	readout.text = "%.2fx" % value
	readout.custom_minimum_size = Vector2(34, 0)
	readout.add_theme_font_size_override("font_size", 8)
	row.add_child(readout)
	slider.value_changed.connect(func(next: float) -> void:
		readout.text = "%.2fx" % next
		changed.call(next))
	controls_list.add_child(row)


func _touch_toggle(row: HBoxContainer, label: Callable) -> Button:
	var button := Button.new()
	button.text = String(label.call())
	button.custom_minimum_size = Vector2(0, 22)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 8)
	row.add_child(button)
	return button


## WAYPOINT HUD preferences, under the waypoint keys (docs/WAYPOINTS.md).
func _build_waypoint_preferences() -> void:
	var heading := Label.new()
	heading.name = "WaypointHeading"
	heading.text = Palette.track("WAYPOINT")
	heading.add_theme_color_override("font_color", Palette.AMBER)
	heading.add_theme_font_size_override("font_size", 8)
	controls_list.add_child(heading)
	var guidance := Button.new()
	guidance.name = "WaypointGuidanceButton"
	guidance.text = "GUIDANCE: %s" % Settings.waypoint_guidance.to_upper()
	guidance.tooltip_text = "OFF: pin only // ARROW: pin and screen-edge arrow // PATH: also floor chevrons along the route"
	guidance.pressed.connect(func() -> void:
		var modes: Array = Settings.WAYPOINT_GUIDANCE_MODES
		Settings.set_waypoint_guidance(modes[(modes.find(Settings.waypoint_guidance) + 1) % modes.size()])
		guidance.text = "GUIDANCE: %s" % Settings.waypoint_guidance.to_upper())
	controls_list.add_child(guidance)
	var distance := Button.new()
	distance.name = "WaypointDistanceButton"
	Palette.style_state_toggle(distance, "SHOW WAYPOINT DISTANCE", Settings.waypoint_show_distance)
	distance.pressed.connect(func() -> void:
		Settings.set_waypoint_show_distance(not Settings.waypoint_show_distance)
		Palette.style_state_toggle(distance, "SHOW WAYPOINT DISTANCE", Settings.waypoint_show_distance))
	controls_list.add_child(distance)
	var chime := Button.new()
	chime.name = "WaypointChimeButton"
	Palette.style_state_toggle(chime, "ARRIVAL CHIME", Settings.waypoint_arrival_chime)
	chime.pressed.connect(func() -> void:
		Settings.set_waypoint_arrival_chime(not Settings.waypoint_arrival_chime)
		Palette.style_state_toggle(chime, "ARRIVAL CHIME", Settings.waypoint_arrival_chime))
	controls_list.add_child(chime)
	var size_button := Button.new()
	size_button.name = "WaypointSizeButton"
	size_button.text = "PIN SIZE: %d%%" % roundi(Settings.waypoint_scale * 100.0)
	size_button.pressed.connect(func() -> void:
		var next := Settings.waypoint_scale + .2
		Settings.set_waypoint_scale(next if next <= 1.61 else .6)
		size_button.text = "PIN SIZE: %d%%" % roundi(Settings.waypoint_scale * 100.0))
	controls_list.add_child(size_button)
	var opacity_button := Button.new()
	opacity_button.name = "WaypointOpacityButton"
	opacity_button.text = "PIN OPACITY: %d%%" % roundi(Settings.waypoint_opacity * 100.0)
	opacity_button.pressed.connect(func() -> void:
		var next := Settings.waypoint_opacity - .2
		Settings.set_waypoint_opacity(next if next >= .29 else 1.0)
		opacity_button.text = "PIN OPACITY: %d%%" % roundi(Settings.waypoint_opacity * 100.0))
	controls_list.add_child(opacity_button)


func _build_control_row(action: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var name_label := Label.new()
	name_label.text = ACTION_LABELS.get(action, action.to_upper())
	name_label.custom_minimum_size = Vector2(112, 0)
	name_label.add_theme_color_override("font_color", Palette.BODY)
	row.add_child(name_label)

	var key_label := Label.new()
	key_label.text = Settings.get_action_key_label(action)
	key_label.custom_minimum_size = Vector2(92, 0)
	key_label.add_theme_color_override("font_color", Palette.AMBER)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(key_label)
	_key_labels[action] = key_label

	var rebind_button := Button.new()
	rebind_button.text = "CHANGE"
	rebind_button.custom_minimum_size = Vector2(60, 0)
	Palette.style_button(rebind_button, false)
	rebind_button.pressed.connect(_on_rebind_pressed.bind(action, rebind_button, false))
	row.add_child(rebind_button)

	var add_button := Button.new()
	add_button.text = "+"
	add_button.tooltip_text = "ADD A SECOND BINDING"
	add_button.custom_minimum_size = Vector2(28, 0)
	Palette.style_button(add_button, false)
	add_button.pressed.connect(_on_rebind_pressed.bind(action, add_button, true))
	row.add_child(add_button)

	var reset_button := Button.new()
	reset_button.text = "RESET"
	reset_button.custom_minimum_size = Vector2(48, 0)
	Palette.style_button(reset_button, false)
	reset_button.pressed.connect(func() -> void:
		Settings.reset_action_bindings(action)
		_key_labels[action].text = Settings.get_action_key_label(action))
	row.add_child(reset_button)

	controls_list.add_child(row)


func _on_rebind_pressed(action: String, button: Button, append: bool) -> void:
	if not _listening_action.is_empty():
		_stop_listening()
	_listening_action = action
	_listening_button = button
	_listening_append = append
	button.text = LISTENING_TEXT


func _stop_listening() -> void:
	if _listening_button != null:
		_listening_button.text = "+" if _listening_append else "CHANGE"
	_listening_action = ""
	_listening_button = null
	_listening_append = false
