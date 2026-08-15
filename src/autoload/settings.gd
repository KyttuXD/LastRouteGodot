extends Node

## Project-wide persisted settings (master volume, key bindings). Loads and
## applies user://settings.cfg once at startup regardless of which scene
## boots first — the menu and main_3d.tscn both read/write through this
## autoload instead of touching ConfigFile themselves.

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_VOLUME_PERCENT := 100.0
const MIN_VOLUME_DB := -80.0

## Office Mode's controls live in their own action namespace (office_*),
## mirroring the original's deliberate split: rebinding a Last Route key can
## never collide with or silently clear an Office one, so the two sets can
## share physical keys freely. The office_camera_N bank is intentionally not
## rebindable — it's a fixed 1-8 hotbar, same as the original.
const REBINDABLE_ACTIONS: Array[String] = [
	"move_left", "move_right", "move_up", "move_down",
	"sprint", "crouch", "flashlight", "interact",
	"toggle_map", "toggle_view", "pause",
	"office_left_door", "office_right_door", "office_desk_light",
	"office_vent", "office_cameras", "office_radio", "office_breaker",
	"office_reboot", "office_emergency_flash", "office_rear_flash",
]

var master_volume_percent := DEFAULT_VOLUME_PERCENT

var _master_bus_index := -1


func _ready() -> void:
	_master_bus_index = AudioServer.get_bus_index("Master")
	_load()


func set_master_volume(percent: float) -> void:
	master_volume_percent = clampf(percent, 0.0, 100.0)
	_apply_volume()
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
	for action in REBINDABLE_ACTIONS:
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				config.set_value("controls", action, event.physical_keycode)
				break
	config.save(SETTINGS_PATH)
