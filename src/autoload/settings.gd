extends Node

## Project-wide persisted settings (master volume, key bindings, display).
## Loads and applies user://settings.cfg once at startup regardless of which
## scene boots first — the menu and main_3d.tscn both read/write through this
## autoload instead of touching ConfigFile themselves.

## Emitted when the window mode changes, including from the F11 shortcut, so
## an open settings panel does not sit there showing the old state.
signal display_changed
signal visual_changed

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_VOLUME_PERCENT := 100.0
const DEFAULT_SFX_VOLUME_PERCENT := 100.0
const DEFAULT_UI_VOLUME_PERCENT := 100.0
## Radians of turn per pixel of mouse travel. Both first-person controllers
## read this rather than each carrying a constant, so one slider moves the maze
## and the office together -- they were 0.0035 and 0.0022, which felt like two
## different games.
## 0.0030-0.0050 still read as sluggish in play; 0.0075 is the fresh-install
## baseline while preserving a broad accessibility range.
## The slider still spans 0.0005..0.0120, so this only moves where a fresh
## install starts.
const DEFAULT_MOUSE_SENSITIVITY := 0.0075
const MIN_MOUSE_SENSITIVITY := 0.0005
const MAX_MOUSE_SENSITIVITY := 0.0120
const MIN_VOLUME_DB := -80.0
## Fresh installs always receive a visible, persistent pixel-blur treatment.
const DEFAULT_PIXEL_EFFECT_PERCENT := 42.0
const DEFAULT_PLAYER_HUE_DEGREES := 0.0
const DEFAULT_VSYNC := true
const DEFAULT_FPS_LIMIT := 0
const DEFAULT_FIELD_OF_VIEW := 78.0
const MIN_FIELD_OF_VIEW := 60.0
const MAX_FIELD_OF_VIEW := 105.0
## Personal debug preferences are intentionally separate from room state.
## These values may survive a restart, but they are only ever applied after
## AdminMenu's Build.tools_enabled() gate has successfully attached a menu.
## World edits (hunters, relays, lights, rebuilt maps) remain session-only.
const ADMIN_PREFERENCE_DEFAULTS := {
	"no_target": false,
	"god_mode": false,
	"noclip": false,
	"map_reveal": false,
	"hunter_reveal": false,
	"pixel_effect_enabled": true,
}

## The design size every 2D layout is authored against, and the project's
## stretch viewport. With stretch/aspect "expand" this is a MINIMUM, not a
## fixed frame: a window that is not 16:9 shows more of the scene rather than
## black bars, which is why every top-level Control is anchored to an edge.
const DISPLAY_BASE := Vector2i(480, 270)
## Largest share of the usable desktop a windowed session may open at. Below 1
## so the window does not start pinned under a taskbar or hanging off the
## bottom of a laptop screen.
const WINDOW_SCREEN_SHARE := 0.85

## Office Mode's controls live in their own action namespace (office_*),
## mirroring the original's deliberate split: rebinding a Last Route key can
## never collide with or silently clear an Office one, so the two sets can
## share physical keys freely. The office_camera_N bank is intentionally not
## rebindable — it's a fixed 1-8 hotbar, same as the original.
const REBINDABLE_ACTIONS: Array[String] = [
	"move_left", "move_right", "move_up", "move_down",
	"look_left", "look_right", "look_up", "look_down",
	"sprint", "crouch", "jump", "flashlight", "taser", "tool_use", "interact",
	"inventory", "drop_item", "chat", "toggle_map", "pause",
	"office_left_door", "office_right_door", "office_desk_light",
	"office_vent", "office_cameras", "office_radio", "office_breaker",
	"office_reboot", "office_emergency_flash", "office_rear_flash",
]

var master_volume_percent := DEFAULT_VOLUME_PERCENT
var sfx_volume_percent := DEFAULT_SFX_VOLUME_PERCENT
var ui_volume_percent := DEFAULT_UI_VOLUME_PERCENT
var mouse_sensitivity := DEFAULT_MOUSE_SENSITIVITY
var fullscreen := false
var vsync_enabled := DEFAULT_VSYNC
var fps_limit := DEFAULT_FPS_LIMIT
var field_of_view := DEFAULT_FIELD_OF_VIEW
var pixel_effect_percent := DEFAULT_PIXEL_EFFECT_PERCENT
## 0 preserves the authored skin; 1..360 selects a lightweight texture tint.
var player_hue_degrees := DEFAULT_PLAYER_HUE_DEGREES
var _admin_preferences: Dictionary = ADMIN_PREFERENCE_DEFAULTS.duplicate()

var _master_bus_index := -1
var _sfx_bus_index := -1
var _ui_bus_index := -1
var _default_bindings := {}


func _ready() -> void:
	_master_bus_index = AudioServer.get_bus_index("Master")
	_sfx_bus_index = AudioServer.get_bus_index("SFX")
	_ui_bus_index = AudioServer.get_bus_index("UI")
	_capture_default_bindings()
	_load()
	_apply_display()


## F11 anywhere. Handled by the autoload rather than per-scene so it works on
## the menu, in a run and in the office without three copies of it, and it is
## deliberately not in REBINDABLE_ACTIONS -- it is a window control, not a
## gameplay one.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		set_fullscreen(not fullscreen)
		get_viewport().set_input_as_handled()


func set_fullscreen(on: bool) -> void:
	if fullscreen == on:
		return
	fullscreen = on
	_apply_display()
	_save()
	display_changed.emit()


func set_master_volume(percent: float) -> void:
	master_volume_percent = clampf(percent, 0.0, 100.0)
	_apply_volume()
	_save()


func set_sfx_volume(percent: float) -> void:
	sfx_volume_percent = clampf(percent, 0.0, 100.0)
	_apply_volume()
	_save()


func set_ui_volume(percent: float) -> void:
	ui_volume_percent = clampf(percent, 0.0, 100.0)
	_apply_volume()
	_save()


func set_vsync(enabled: bool) -> void:
	vsync_enabled = enabled
	_apply_display_performance()
	_save()
	display_changed.emit()


func set_fps_limit(limit: float) -> void:
	fps_limit = 0 if limit < 15.0 else clampi(roundi(limit), 30, 240)
	_apply_display_performance()
	_save()
	display_changed.emit()


func set_field_of_view(value: float) -> void:
	field_of_view = clampf(value, MIN_FIELD_OF_VIEW, MAX_FIELD_OF_VIEW)
	_save()
	visual_changed.emit()


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)
	_save()


func set_pixel_effect_percent(value: float) -> void:
	pixel_effect_percent = clampf(value, 0.0, 100.0)
	_save()
	visual_changed.emit()


func set_player_hue_degrees(value: float) -> void:
	player_hue_degrees = clampf(value, 0.0, 360.0)
	_save()
	visual_changed.emit()


func admin_preference(key: String) -> bool:
	if not ADMIN_PREFERENCE_DEFAULTS.has(key):
		return false
	return bool(_admin_preferences.get(key, ADMIN_PREFERENCE_DEFAULTS[key]))


func set_admin_preference(key: String, enabled: bool) -> void:
	if not ADMIN_PREFERENCE_DEFAULTS.has(key):
		push_warning("Settings: ignored unknown admin preference '%s'" % key)
		return
	if admin_preference(key) == enabled:
		return
	_admin_preferences[key] = enabled
	_save()


func admin_preferences_snapshot() -> Dictionary:
	return _admin_preferences.duplicate()


func set_admin_preferences(values: Dictionary) -> void:
	for key_value in ADMIN_PREFERENCE_DEFAULTS:
		var key := String(key_value)
		_admin_preferences[key] = bool(values.get(key,
			ADMIN_PREFERENCE_DEFAULTS[key]))
	_save()


func rebind_action(action: String, event: InputEvent) -> void:
	set_action_binding(action, event, false)


func set_action_binding(action: String, event: InputEvent, append: bool) -> void:
	if not InputMap.has_action(action):
		return
	if not (event is InputEventKey or event is InputEventMouseButton):
		return
	if not append:
		_erase_keyboard_mouse_bindings(action)
	else:
		for existing in InputMap.action_get_events(action):
			if _event_signature(existing) == _event_signature(event):
				return
	InputMap.action_add_event(action, event)
	_save()


func reset_action_bindings(action: String) -> void:
	if not InputMap.has_action(action) or not _default_bindings.has(action):
		return
	_erase_keyboard_mouse_bindings(action)
	for event in _default_bindings[action]:
		InputMap.action_add_event(action, (event as InputEvent).duplicate())
	_save()


## Keyboard/mouse customization is intentionally independent from the fixed
## controller layout. Erasing every event here used to silently remove a
## joypad's movement/action binding as soon as a player changed one key.
func _erase_keyboard_mouse_bindings(action: String) -> void:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey or event is InputEventMouseButton:
			InputMap.action_erase_event(action, event)


func get_action_key_label(action: String) -> String:
	var labels := []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			labels.append(event.as_text_physical_keycode().to_upper())
		elif event is InputEventMouseButton:
			labels.append(_mouse_button_label((event as InputEventMouseButton).button_index))
	return " / ".join(labels) if not labels.is_empty() else "?"


func action_binding_count(action: String) -> int:
	return InputMap.action_get_events(action).size() if InputMap.has_action(action) else 0


func _capture_default_bindings() -> void:
	for action in REBINDABLE_ACTIONS:
		if InputMap.has_action(action):
			var events := []
			for event in InputMap.action_get_events(action):
				if event is InputEventKey or event is InputEventMouseButton:
					events.append(event.duplicate())
			_default_bindings[action] = events


static func _mouse_button_label(button: MouseButton) -> String:
	match button:
		MOUSE_BUTTON_LEFT: return "MOUSE 1"
		MOUSE_BUTTON_RIGHT: return "MOUSE 2"
		MOUSE_BUTTON_MIDDLE: return "MOUSE 3"
		MOUSE_BUTTON_WHEEL_UP: return "WHEEL UP"
		MOUSE_BUTTON_WHEEL_DOWN: return "WHEEL DOWN"
		_: return "MOUSE %d" % int(button)


static func _event_signature(event: InputEvent) -> String:
	if event is InputEventKey:
		return "K:%d" % int((event as InputEventKey).physical_keycode)
	if event is InputEventMouseButton:
		return "M:%d" % int((event as InputEventMouseButton).button_index)
	return ""


## Fit the window to the machine the game is actually running on.
##
## The project file can only name one window size, and a size that suits a
## 1080p desktop is unusable on a 4K one and does not fit a small laptop at
## all. Sizing at startup instead means the same build opens sensibly
## everywhere -- and in whole multiples of the design size, so the pixel art
## lands on an exact grid rather than between texels.
func _apply_display() -> void:
	var window := get_window()
	if window == null:
		return
	_apply_display_performance()
	window.min_size = DISPLAY_BASE
	if fullscreen:
		window.mode = Window.MODE_FULLSCREEN
		return
	window.mode = Window.MODE_WINDOWED
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
	var scale := maxi(1, mini(
		floori(usable.size.x * WINDOW_SCREEN_SHARE / DISPLAY_BASE.x),
		floori(usable.size.y * WINDOW_SCREEN_SHARE / DISPLAY_BASE.y)))
	window.size = DISPLAY_BASE * scale
	window.position = usable.position + (usable.size - window.size) / 2


func _apply_display_performance() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED \
		if vsync_enabled else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_limit


func _apply_volume() -> void:
	if _master_bus_index >= 0:
		AudioServer.set_bus_volume_db(_master_bus_index, _percent_to_db(master_volume_percent))
	if _sfx_bus_index >= 0:
		AudioServer.set_bus_volume_db(_sfx_bus_index, _percent_to_db(sfx_volume_percent))
	if _ui_bus_index >= 0:
		AudioServer.set_bus_volume_db(_ui_bus_index, _percent_to_db(ui_volume_percent))


func _percent_to_db(percent: float) -> float:
	return MIN_VOLUME_DB if percent <= 0.0 else linear_to_db(percent / 100.0)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		_apply_volume()
		return

	master_volume_percent = clampf(float(config.get_value("audio",
		"master_volume_percent", DEFAULT_VOLUME_PERCENT)), 0.0, 100.0)
	sfx_volume_percent = clampf(float(config.get_value("audio",
		"sfx_volume_percent", DEFAULT_SFX_VOLUME_PERCENT)), 0.0, 100.0)
	ui_volume_percent = clampf(float(config.get_value("audio",
		"ui_volume_percent", DEFAULT_UI_VOLUME_PERCENT)), 0.0, 100.0)
	fullscreen = config.get_value("display", "fullscreen", false)
	vsync_enabled = bool(config.get_value("display", "vsync", DEFAULT_VSYNC))
	fps_limit = clampi(int(config.get_value("display", "fps_limit", DEFAULT_FPS_LIMIT)), 0, 240)
	field_of_view = clampf(float(config.get_value("display", "field_of_view",
		DEFAULT_FIELD_OF_VIEW)), MIN_FIELD_OF_VIEW, MAX_FIELD_OF_VIEW)
	pixel_effect_percent = clampf(config.get_value("display",
		"pixel_effect_percent", DEFAULT_PIXEL_EFFECT_PERCENT), 0.0, 100.0)
	player_hue_degrees = clampf(config.get_value("player",
		"hue_degrees", DEFAULT_PLAYER_HUE_DEGREES), 0.0, 360.0)
	for key_value in ADMIN_PREFERENCE_DEFAULTS:
		var key := String(key_value)
		_admin_preferences[key] = bool(config.get_value("admin", key,
			ADMIN_PREFERENCE_DEFAULTS[key]))
	mouse_sensitivity = clampf(
		config.get_value("controls", "mouse_sensitivity", DEFAULT_MOUSE_SENSITIVITY),
		MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)
	for action in REBINDABLE_ACTIONS:
		var saved = config.get_value("controls", action, null)
		if saved == null or not InputMap.has_action(action):
			continue
		# Read the original one-integer format so existing player settings migrate
		# without silently resetting. New saves preserve every keyboard/mouse bind.
		var entries: Array = saved if saved is Array else [{"type": "key", "code": int(saved)}]
		_erase_keyboard_mouse_bindings(action)
		for entry_value in entries:
			if not entry_value is Dictionary:
				continue
			var entry: Dictionary = entry_value
			if String(entry.get("type", "")) == "mouse":
				var mouse := InputEventMouseButton.new()
				mouse.button_index = int(entry.get("button", 0)) as MouseButton
				if mouse.button_index > 0:
					InputMap.action_add_event(action, mouse)
			else:
				var key := InputEventKey.new()
				key.physical_keycode = int(entry.get("code", 0))
				if key.physical_keycode > 0:
					InputMap.action_add_event(action, key)
	_apply_volume()


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume_percent", master_volume_percent)
	config.set_value("audio", "sfx_volume_percent", sfx_volume_percent)
	config.set_value("audio", "ui_volume_percent", ui_volume_percent)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "vsync", vsync_enabled)
	config.set_value("display", "fps_limit", fps_limit)
	config.set_value("display", "field_of_view", field_of_view)
	config.set_value("display", "pixel_effect_percent", pixel_effect_percent)
	config.set_value("player", "hue_degrees", player_hue_degrees)
	for key_value in ADMIN_PREFERENCE_DEFAULTS:
		var key := String(key_value)
		config.set_value("admin", key, admin_preference(key))
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	for action in REBINDABLE_ACTIONS:
		var entries := []
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				entries.append({"type": "key", "code": event.physical_keycode})
			elif event is InputEventMouseButton:
				entries.append({"type": "mouse", "button": event.button_index})
		config.set_value("controls", action, entries)
	config.save(SETTINGS_PATH)
