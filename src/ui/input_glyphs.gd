class_name InputGlyphs
extends RefCounted

## Control hints in prompts ("[E] HIDE", "HOLD [W]/[S] CLIMB // [SPACE] LET GO") come from HERE, read from the live InputMap so a
## rebind changes the prompt too, and follow the device the player last used: keyboard/mouse, gamepad, phone touch buttons or a
## Quest controller. HUD._input reports every event (observe); prompts are rebuilt every frame, so a device switch shows at once.

const KEYBOARD := "keyboard"
const GAMEPAD := "gamepad"
const TOUCH := "touch"
const XR := "xr"

## Tests pin a device; "" follows the player.
static var device_override := ""
static var _last := ""

const PAD_BUTTONS := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_START: "MENU", JOY_BUTTON_BACK: "VIEW", JOY_BUTTON_DPAD_UP: "D-PAD UP", JOY_BUTTON_DPAD_DOWN: "D-PAD DOWN",
	JOY_BUTTON_DPAD_LEFT: "D-PAD LEFT", JOY_BUTTON_DPAD_RIGHT: "D-PAD RIGHT",
}
## Phone: the on-screen button that presses the action (TouchControls.BUTTONS) and the D-pad for movement.
const TOUCH_LABELS := {"interact": "USE", "jump": "JUMP", "crouch": "DUCK", "flashlight": "LIGHT", "tool_use": "TOOL",
	"inventory": "BAG", "toggle_map": "MAP", "chat": "CHAT", "move_up": "D-PAD UP", "move_down": "D-PAD DOWN",
	"move_left": "D-PAD LEFT", "move_right": "D-PAD RIGHT", "sprint": "RUN"}
## Quest controllers: trigger uses, A jumps / lets go, grip climbs (XRHands), thumbstick moves.
const XR_LABELS := {"interact": "TRIGGER", "tool_use": "TRIGGER", "jump": "A", "crouch": "B", "move_up": "STICK UP",
	"move_down": "STICK DOWN", "move_left": "STICK LEFT", "move_right": "STICK RIGHT", "climb": "GRIP", "flashlight": "Y"}


static func observe(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton:
		_last = KEYBOARD
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 2.0:
		_last = KEYBOARD
	elif event is InputEventJoypadButton:
		_last = GAMEPAD
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > .4:
		_last = GAMEPAD
	elif event is InputEventScreenTouch:
		_last = TOUCH


static func device() -> String:
	if not device_override.is_empty():
		return device_override
	var profile: Node = Engine.get_main_loop().root.get_node_or_null("/root/PlatformProfile") if Engine.get_main_loop() is SceneTree else null
	if profile != null and bool(profile.get("is_xr")):
		return XR
	if not _last.is_empty():
		return _last
	return TOUCH if profile != null and bool(profile.get("is_phone")) else KEYBOARD


## The bare name of what presses `action` on `on_device` (default: the active one): "E", "SPACE", "A", "USE", "TRIGGER".
static func name_of(action: String, on_device: String = "") -> String:
	var where := on_device if not on_device.is_empty() else device()
	match where:
		TOUCH:
			return String(TOUCH_LABELS.get(action, action.to_upper()))
		XR:
			return String(XR_LABELS.get(action, action.to_upper()))
		GAMEPAD:
			if InputMap.has_action(action):
				for event in InputMap.action_get_events(action):
					if event is InputEventJoypadButton and PAD_BUTTONS.has((event as InputEventJoypadButton).button_index):
						return String(PAD_BUTTONS[(event as InputEventJoypadButton).button_index])
					if event is InputEventJoypadMotion:
						var motion := event as InputEventJoypadMotion
						match motion.axis:
							JOY_AXIS_TRIGGER_LEFT: return "LT"
							JOY_AXIS_TRIGGER_RIGHT: return "RT"
							JOY_AXIS_LEFT_Y: return "L-STICK UP" if motion.axis_value < 0.0 else "L-STICK DOWN"
							JOY_AXIS_LEFT_X: return "L-STICK LEFT" if motion.axis_value < 0.0 else "L-STICK RIGHT"
			return action.to_upper()
	if not InputMap.has_action(action):
		return action.to_upper()
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			return OS.get_keycode_string(code).to_upper()
		if event is InputEventMouseButton:
			return Settings._mouse_button_label((event as InputEventMouseButton).button_index).to_upper()
	return action.to_upper()


## "[E]" for the action on the active device.
static func key(action: String, on_device: String = "") -> String:
	return "[%s]" % name_of(action, on_device)


## "[E] HIDE"
static func prompt(action: String, text: String, on_device: String = "") -> String:
	return "%s %s" % [key(action, on_device), text]


## "HOLD [E] RESTORE RELAY"
static func hold(action: String, text: String, on_device: String = "") -> String:
	return "HOLD %s %s" % [key(action, on_device), text]


## The ladder hint while climbing: up/down with W/S (or the stick / D-pad), jump lets go near the bottom; XR climbs by grip.
## `can_let_go`: jump only lets go near the bottom (PlayerController3D.LADDER_LET_GO_HEIGHT), so the hint says so only there.
static func climb_prompt(can_let_go: bool = true, on_device: String = "") -> String:
	var where := on_device if not on_device.is_empty() else device()
	var climb := "%s + PULL CLIMB" % key("climb", where) if where == XR \
		else "HOLD %s/%s CLIMB" % [key("move_up", where), key("move_down", where)]
	return climb + (" // %s LET GO" % key("jump", where) if can_let_go else "")
