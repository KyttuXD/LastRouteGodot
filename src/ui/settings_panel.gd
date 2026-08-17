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
	"sprint": "SPRINT",
	"crouch": "CROUCH",
	"jump": "JUMP / HOP",
	"flashlight": "FLASHLIGHT",
	"interact": "INTERACT",
	"toggle_map": "TOGGLE MAP",
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
const KEY_LABEL_COLOR := Palette.AMBER
const LISTENING_TEXT := "PRESS A KEY..."

## Bindings grouped the way the web build's Controls screen groups them, in
## order. A flat alphabetical list of twenty-one actions is a wall of text; the
## same list under four headings is a thing you can scan. OFFICE MODE is last
## and named as its own section because those are the SAME physical keys shown
## by their office role, which is otherwise baffling to read.
const SECTIONS := [
	{"title": "MOVEMENT", "actions": ["move_up", "move_down", "move_left",
		"move_right", "sprint", "crouch", "jump"]},
	{"title": "ACTIONS", "actions": ["interact", "flashlight", "toggle_map"]},
	{"title": "SYSTEM", "actions": ["pause"]},
	{"title": "OFFICE MODE", "actions": ["office_left_door", "office_right_door",
		"office_desk_light", "office_vent", "office_cameras", "office_radio",
		"office_breaker", "office_reboot", "office_emergency_flash",
		"office_rear_flash"]},
]

@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_value_label: Label = %VolumeValueLabel
@onready var fullscreen_button: Button = %FullscreenButton
@onready var sensitivity_slider: HSlider = %SensitivitySlider
@onready var sensitivity_value_label: Label = %SensitivityValueLabel
@onready var pixel_effect_slider: HSlider = %PixelEffectSlider
@onready var pixel_effect_value_label: Label = %PixelEffectValueLabel
@onready var controls_list: VBoxContainer = %ControlsList
@onready var close_button: Button = %CloseButton

var _listening_action := ""
var _listening_button: Button = null
var _key_labels: Dictionary = {}


func _ready() -> void:
	volume_slider.value_changed.connect(_on_volume_changed)
	fullscreen_button.toggled.connect(Settings.set_fullscreen)
	sensitivity_slider.min_value = Settings.MIN_MOUSE_SENSITIVITY
	sensitivity_slider.max_value = Settings.MAX_MOUSE_SENSITIVITY
	sensitivity_slider.step = 0.0001
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	pixel_effect_slider.value_changed.connect(_on_pixel_effect_changed)
	# F11 works anywhere, so the toggle can be flipped from outside this panel
	# while it is open.
	Settings.display_changed.connect(_refresh_from_settings)
	close_button.pressed.connect(close)
	_apply_palette()
	_build_control_rows()
	_refresh_from_settings()


## Runs before Control's own GUI input dispatch, so a REBIND button that
## still has focus can't eat Enter/Space/arrow presses as UI navigation
## before we get a chance to capture them.
func _input(event: InputEvent) -> void:
	if _listening_action.is_empty():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()

	if event.physical_keycode == KEY_ESCAPE:
		_stop_listening()
		return

	var action := _listening_action
	_stop_listening()
	var new_event := InputEventKey.new()
	new_event.physical_keycode = event.physical_keycode
	Settings.rebind_action(action, new_event)
	_key_labels[action].text = Settings.get_action_key_label(action)


func open() -> void:
	_refresh_from_settings()
	visible = true


func close() -> void:
	_stop_listening()
	visible = false


func _refresh_from_settings() -> void:
	volume_slider.value = Settings.master_volume_percent
	_update_volume_label(Settings.master_volume_percent)
	fullscreen_button.set_pressed_no_signal(Settings.fullscreen)
	Palette.set_state_toggle(fullscreen_button, Settings.fullscreen)
	sensitivity_slider.set_value_no_signal(Settings.mouse_sensitivity)
	_update_sensitivity_label(Settings.mouse_sensitivity)
	pixel_effect_slider.set_value_no_signal(Settings.pixel_effect_percent)
	_update_pixel_effect_label(Settings.pixel_effect_percent)
	for action in _key_labels:
		_key_labels[action].text = Settings.get_action_key_label(action)


func _on_volume_changed(value: float) -> void:
	Settings.set_master_volume(value)
	_update_volume_label(value)


func _update_volume_label(value: float) -> void:
	volume_value_label.text = "%d%%" % int(round(value))


func _on_sensitivity_changed(value: float) -> void:
	Settings.set_mouse_sensitivity(value)
	_update_sensitivity_label(value)


func _on_pixel_effect_changed(value: float) -> void:
	Settings.set_pixel_effect_percent(value)
	_update_pixel_effect_label(value)


func _update_pixel_effect_label(value: float) -> void:
	pixel_effect_value_label.text = "%d%%" % int(round(value))


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
			"SensitivityRow/SensitivityLabel", "SensitivityRow/SensitivityValueLabel",
			"PixelEffectRow/PixelEffectLabel", "PixelEffectRow/PixelEffectValueLabel",
			"DisplayRow/DisplayLabel"]:
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


func _build_control_rows() -> void:
	for section in SECTIONS:
		var heading := Label.new()
		heading.text = Palette.track(String(section["title"]))
		heading.add_theme_color_override("font_color", Palette.AMBER)
		heading.add_theme_font_size_override("font_size", 8)
		controls_list.add_child(heading)
		for action in section["actions"]:
			if Settings.REBINDABLE_ACTIONS.has(action):
				_build_control_row(action)
	# Anything the sections forgot still gets a row, so adding an action to
	# Settings can never silently make it unbindable.
	var placed := {}
	for section in SECTIONS:
		for action in section["actions"]:
			placed[action] = true
	var orphans: Array = Settings.REBINDABLE_ACTIONS.filter(
		func(a: String) -> bool: return not placed.has(a))
	if not orphans.is_empty():
		var heading := Label.new()
		heading.text = Palette.track("OTHER")
		heading.add_theme_color_override("font_color", Palette.AMBER)
		heading.add_theme_font_size_override("font_size", 8)
		controls_list.add_child(heading)
		for action in orphans:
			_build_control_row(action)


func _build_control_row(action: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var name_label := Label.new()
	name_label.text = ACTION_LABELS.get(action, action.to_upper())
	name_label.custom_minimum_size = Vector2(150, 0)
	name_label.add_theme_color_override("font_color", Palette.BODY)
	row.add_child(name_label)

	var key_label := Label.new()
	key_label.text = Settings.get_action_key_label(action)
	key_label.custom_minimum_size = Vector2(56, 0)
	key_label.add_theme_color_override("font_color", KEY_LABEL_COLOR)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(key_label)
	_key_labels[action] = key_label

	var rebind_button := Button.new()
	rebind_button.text = "REBIND"
	rebind_button.custom_minimum_size = Vector2(90, 0)
	Palette.style_button(rebind_button, false)
	rebind_button.pressed.connect(_on_rebind_pressed.bind(action, rebind_button))
	row.add_child(rebind_button)

	controls_list.add_child(row)


func _on_rebind_pressed(action: String, button: Button) -> void:
	if not _listening_action.is_empty():
		_stop_listening()
	_listening_action = action
	_listening_button = button
	button.text = LISTENING_TEXT


func _stop_listening() -> void:
	if _listening_button != null:
		_listening_button.text = "REBIND"
	_listening_action = ""
	_listening_button = null
