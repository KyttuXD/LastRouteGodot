extends Node

## Project-wide persisted settings (master volume, key bindings, display).
## Loads and applies user://settings.cfg once at startup regardless of which
## scene boots first — the menu and main_3d.tscn both read/write through this
## autoload instead of touching ConfigFile themselves.

## Emitted when the window mode changes, including from the F11 shortcut, so
## an open settings panel does not sit there showing the old state.
signal display_changed

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_VOLUME_PERCENT := 100.0
## Radians of turn per pixel of mouse travel. Both first-person controllers
## read this rather than each carrying a constant, so one slider moves the maze
## and the office together -- they were 0.0035 and 0.0022, which felt like two
## different games.
## 0.0030 read as sluggish in play; 0.0050 is what felt right at the desk.
## The slider still spans 0.0005..0.0120, so this only moves where a fresh
## install starts.
const DEFAULT_MOUSE_SENSITIVITY := 0.0050
const MIN_MOUSE_SENSITIVITY := 0.0005
const MAX_MOUSE_SENSITIVITY := 0.0120
const MIN_VOLUME_DB := -80.0

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
	"sprint", "crouch", "flashlight", "interact",
	"toggle_map", "pause",
	"office_left_door", "office_right_door", "office_desk_light",
	"office_vent", "office_cameras", "office_radio", "office_breaker",
	"office_reboot", "office_emergency_flash", "office_rear_flash",
]

var master_volume_percent := DEFAULT_VOLUME_PERCENT
var mouse_sensitivity := DEFAULT_MOUSE_SENSITIVITY
var fullscreen := false

var _master_bus_index := -1


func _ready() -> void:
	_master_bus_index = AudioServer.get_bus_index("Master")
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


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)
	_save()


func rebind_action(action: String, event: InputEventKey) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	_save()


func get_action_key_label(action: String) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return event.as_text_physical_keycode().to_upper()
	return "?"


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


func _apply_volume() -> void:
	if _master_bus_index >= 0:
		AudioServer.set_bus_volume_db(_master_bus_index, _percent_to_db(master_volume_percent))


func _percent_to_db(percent: float) -> float:
	return MIN_VOLUME_DB if percent <= 0.0 else linear_to_db(percent / 100.0)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		_apply_volume()
		return

	master_volume_percent = config.get_value("audio", "master_volume_percent", DEFAULT_VOLUME_PERCENT)
	fullscreen = config.get_value("display", "fullscreen", false)
	mouse_sensitivity = clampf(
		config.get_value("controls", "mouse_sensitivity", DEFAULT_MOUSE_SENSITIVITY),
		MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)
	for action in REBINDABLE_ACTIONS:
		var physical_keycode: int = config.get_value("controls", action, -1)
		if physical_keycode != -1 and InputMap.has_action(action):
			var event := InputEventKey.new()
			event.physical_keycode = physical_keycode
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, event)
	_apply_volume()


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume_percent", master_volume_percent)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	for action in REBINDABLE_ACTIONS:
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				config.set_value("controls", action, event.physical_keycode)
				break
	config.save(SETTINGS_PATH)
