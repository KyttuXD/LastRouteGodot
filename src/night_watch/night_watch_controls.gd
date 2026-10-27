class_name NightWatchControls
extends RefCounted

## Night Watch's controls: ONE table (`ACTIONS`) is the source of truth for the InputMap actions, their default keys and gamepad buttons, the labels of the
## controls tab, the on-screen hint line and the handlers (every mode's game reads these action names and nothing else for the office and the monitor).
##
## The player WALKS with the shared controller (PlayerController3D: WASD, mouse look, sprint, crouch, jump, E to use, the shared pause key, the same
## gamepad mapping): Night Watch changes none of it. Its stations are used with the same INTERACT action. The Night Watch actions are quick keys on
## keys the shared input map leaves free, plus the camera keys of the monitor: `nw_monitor` (Space, like the 2D game; U as an alias) opens and closes it, `nw_cam_1..8` (1-8 and the number
## pad) pick a camera, `nw_cam_prev` / `nw_cam_next` (Left / Right, gamepad d-pad left / right) cycle. R (office_radio, shared) mutes Zellia.
## Rebinds are saved in NightWatchSave (`key_overrides`) and applied on register(). Camera keys do nothing while the monitor is down.

const DOOR_LEFT := &"nw_door_left"
const DOOR_RIGHT := &"nw_door_right"
const LIGHT_LEFT := &"nw_light_left"
const LIGHT_RIGHT := &"nw_light_right"
const LAMP := &"nw_lamp"
const MONITOR := &"nw_monitor"
const CAM_PREV := &"nw_cam_prev"
const CAM_NEXT := &"nw_cam_next"
const MEET := &"nw_meet"        # Night 7: meet Kathy's eyes (the 2D K key)
const MUTE := &"office_radio"   # shared action, R

## {action, label (controls tab), key (physical keycode), alt (second keycode or 0), joy (gamepad button or -1)}
const ACTIONS := [
	{"action": &"nw_door_left", "label": "LEFT DOOR (QUICK KEY)", "key": KEY_Z, "alt": 0, "joy": -1},
	{"action": &"nw_door_right", "label": "RIGHT DOOR (QUICK KEY)", "key": KEY_X, "alt": 0, "joy": -1},
	{"action": &"nw_light_left", "label": "LEFT DOOR LIGHT (HOLD)", "key": KEY_G, "alt": 0, "joy": -1},
	{"action": &"nw_light_right", "label": "RIGHT DOOR LIGHT (HOLD)", "key": KEY_H, "alt": 0, "joy": -1},
	{"action": &"nw_lamp", "label": "DESK LAMP", "key": KEY_Y, "alt": 0, "joy": -1},
	{"action": &"nw_monitor", "label": "CAMERAS (OPEN / CLOSE)", "key": KEY_SPACE, "alt": KEY_U, "joy": -1},   # Space as in the 2D game, U kept as an alias
	{"action": &"nw_cam_prev", "label": "PREVIOUS CAMERA", "key": KEY_LEFT, "alt": 0, "joy": JOY_BUTTON_DPAD_LEFT},
	{"action": &"nw_cam_next", "label": "NEXT CAMERA", "key": KEY_RIGHT, "alt": 0, "joy": JOY_BUTTON_DPAD_RIGHT},
	{"action": &"nw_meet", "label": "MEET HER EYES (NIGHT 7)", "key": KEY_O, "alt": 0, "joy": -1},
	{"action": &"nw_cam_1", "label": "CAMERA 1", "key": KEY_1, "alt": KEY_KP_1, "joy": -1},
	{"action": &"nw_cam_2", "label": "CAMERA 2", "key": KEY_2, "alt": KEY_KP_2, "joy": -1},
	{"action": &"nw_cam_3", "label": "CAMERA 3", "key": KEY_3, "alt": KEY_KP_3, "joy": -1},
	{"action": &"nw_cam_4", "label": "CAMERA 4", "key": KEY_4, "alt": KEY_KP_4, "joy": -1},
	{"action": &"nw_cam_5", "label": "CAMERA 5", "key": KEY_5, "alt": KEY_KP_5, "joy": -1},
	{"action": &"nw_cam_6", "label": "CAMERA 6", "key": KEY_6, "alt": KEY_KP_6, "joy": -1},
	{"action": &"nw_cam_7", "label": "CAMERA 7", "key": KEY_7, "alt": KEY_KP_7, "joy": -1},
	{"action": &"nw_cam_8", "label": "CAMERA 8", "key": KEY_8, "alt": KEY_KP_8, "joy": -1},
]

static var _added: Array = []   # action names this file created, removed again on unregister()


## Make sure every Night Watch action exists with its key (a saved rebind wins). Safe to call more than once.
static func register() -> void:
	var overrides := NightWatchSave.key_overrides()
	for entry in ACTIONS:
		var action: StringName = entry["action"]
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.5)
		_added.append(action)
		var key := int(overrides.get(String(action), entry["key"]))
		var k := InputEventKey.new()
		k.physical_keycode = key
		InputMap.action_add_event(action, k)
		if int(entry["alt"]) != 0 and not overrides.has(String(action)):
			var alt := InputEventKey.new()
			alt.physical_keycode = int(entry["alt"])
			InputMap.action_add_event(action, alt)
		if int(entry["joy"]) >= 0:
			var j := InputEventJoypadButton.new()
			j.button_index = int(entry["joy"])
			InputMap.action_add_event(action, j)


## Take back what register() added, so Last Route's input set is untouched.
static func unregister() -> void:
	for action in _added:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	_added.clear()


## Rebind an action to a physical key now and for next time.
static func rebind(action: StringName, keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
	var k := InputEventKey.new()
	k.physical_keycode = keycode
	InputMap.action_add_event(action, k)
	NightWatchSave.set_key_override(String(action), keycode)


## The camera action for camera n (1-8).
static func camera_action(n: int) -> StringName:
	return StringName("nw_cam_%d" % n)


## The key an action is on right now, as text ("U", "Left", "1"): read from the InputMap, so a rebind shows.
static func key_text(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "?"
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var code := (e as InputEventKey).physical_keycode if (e as InputEventKey).physical_keycode != 0 else (e as InputEventKey).keycode
			# the key the physical position types on this layout (headless has no layout: use the code as is)
			var typed := code
			if code != 0 and DisplayServer.get_name() != "headless":
				typed = DisplayServer.keyboard_get_keycode_from_physical(code)
			return OS.get_keycode_string(typed)
	return "?"


## The hint line under the HUD, from the live InputMap. `active` are the actions the current office uses (default: all of them); the monitor line shows
## while the monitor is up. The numbers and arrows are listed as "1-8" / "← →" only while they are on their defaults.
static func hint_line(monitor_up := false, active: Array = []) -> String:
	var on := func(a: StringName) -> bool: return active.is_empty() or active.has(String(a))
	if monitor_up:
		var parts := PackedStringArray()
		parts.append("%s / %s or 1-8 camera" % [key_text(CAM_PREV), key_text(CAM_NEXT)] if _cams_default() else "%s / %s camera" % [key_text(CAM_PREV), key_text(CAM_NEXT)])
		if not active.is_empty() and active.has(String(MEET)):
			parts.append("%s meet her eyes" % key_text(MEET))
		parts.append("%s or %s close" % [key_text(MONITOR), key_text(&"interact")])
		parts.append("%s mute" % key_text(MUTE))
		return " · ".join(parts)
	var out := PackedStringArray()
	out.append("%s%s%s%s move" % [key_text(&"move_up"), key_text(&"move_left"), key_text(&"move_down"), key_text(&"move_right")])
	out.append("%s use (hold on LIGHT)" % key_text(&"interact"))
	if on.call(DOOR_LEFT):
		out.append("%s / %s doors" % [key_text(DOOR_LEFT), key_text(DOOR_RIGHT)])
	if on.call(LIGHT_LEFT):
		out.append("%s / %s lights" % [key_text(LIGHT_LEFT), key_text(LIGHT_RIGHT)])
	if on.call(MONITOR):
		out.append("%s cameras" % key_text(MONITOR))
	if on.call(LAMP):
		out.append("%s lamp" % key_text(LAMP))
	out.append("%s mute" % key_text(MUTE))
	out.append("%s pause" % key_text(&"pause"))
	if active.has("admin"):
		out.append("0 admin")   # only listed for an admin (the game adds "admin" to the active list)
	return " · ".join(out)


static func _cams_default() -> bool:
	for n in range(1, 9):
		if key_text(camera_action(n)) != str(n):
			return false
	return true


## Every mode's game calls this first from its _unhandled_input for the monitor keys; true when the event was used. The game must offer
## `monitor_up: bool`, `open_monitor()`, `close_monitor()`, `cycle_camera(step)`, `select_camera_number(n)` and a `state` it exposes as `is_playing()`.
## Camera keys do nothing while the monitor is down; the monitor key opens and closes it.
static func handle_monitor_event(game: Node, event: InputEvent) -> bool:
	if not game.call("is_playing"):
		return false
	if event.is_action_pressed(MONITOR):
		game.call("close_monitor" if bool(game.get("monitor_up")) else "open_monitor")
		return true
	if not bool(game.get("monitor_up")):
		return false
	if event.is_action_pressed(&"interact"):
		game.call("close_monitor")
		return true
	if event.is_action_pressed(CAM_PREV):
		game.call("cycle_camera", -1)
		return true
	if event.is_action_pressed(CAM_NEXT):
		game.call("cycle_camera", 1)
		return true
	for n in range(1, 9):
		if event.is_action_pressed(camera_action(n)):
			game.call("select_camera_number", n)
			return true
	return false


## For the per-game controls registry: the OFFICE tab, the actions in display order with their labels (movement, looking, sprint, crouch and interact are the
## shared ones). `active` limits it to the actions the current office uses.
static func controls_tab(active: Array = []) -> Dictionary:
	var list := []
	for entry in ACTIONS:
		if active.is_empty() or active.has(String(entry["action"])) or String(entry["action"]).begins_with("nw_cam"):
			list.append({"action": String(entry["action"]), "label": String(entry["label"])})
	list.append({"action": "office_radio", "label": "RADIO (MUTE ZELLIA)"})
	list.append({"action": "interact", "label": "USE (PANELS, MONITOR, CHAIR, LAMP; CLOSES THE MONITOR)"})
	return {"id": "night_watch_office", "title": "OFFICE", "game": NightWatchData.GAME_ID, "actions": list}
