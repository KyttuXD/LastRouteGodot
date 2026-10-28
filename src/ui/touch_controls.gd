class_name TouchControls
extends CanvasLayer

## On-screen controls for phones (PlatformProfile.is_phone; docs/XR_ANDROID.md). Everything feeds the game's ordinary
## Input actions (move_*, sprint, jump, crouch, interact, flashlight, tool_use, hotbar_*, inventory, toggle_map, chat,
## pause), so gameplay, networking and validators see the same inputs a keyboard would make. Look is a drag on the
## right side of the screen, applied through PlayerController3D.apply_look_delta. Desktop never creates this node.
##
## Layout (screen fractions, so it holds from 844x390 to tablets): a floating move stick anywhere in the left 40 %,
## sprint by pushing past the ring; action buttons in the bottom-right, hotbar arrows above them, menus top-right.

signal look_dragged(delta: Vector2)

## Stick radius in canvas units (see MIN_TARGET).
const STICK_RADIUS := 30.0
const SPRINT_PAST := 1.15
## Minimum touch target in canvas units (the UI is laid out on the 480 x 270 base canvas and stretched): 26 units are
## about 12 % of the screen height, roughly 48 dp on a phone held landscape.
const MIN_TARGET := 26.0
## Each button: [node name, label, action, hold (true) or tap (false)]
const BUTTONS := [
	["TouchInteract", "USE", "interact", false],
	["TouchJump", "JUMP", "jump", true],
	["TouchCrouch", "DUCK", "crouch", true],
	["TouchLight", "LIGHT", "flashlight", false],
	["TouchTool", "TOOL", "tool_use", true],
	["TouchPrev", "<", "hotbar_previous", false],
	["TouchNext", ">", "hotbar_next", false],
	["TouchBag", "BAG", "inventory", false],
	["TouchMap", "MAP", "toggle_map", false],
	["TouchChat", "CHAT", "chat", false],
	["TouchPause", "II", "pause", false],
]

var player: Node
var _root: Control
var _stick_base: Control
var _stick_knob: Control
var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _look_touch := -1
var _look_last := Vector2.ZERO
var _buttons := {}
var _held := {}


static func attach(host: Node, run_player: Node) -> TouchControls:
	var controls := TouchControls.new()
	controls.name = "TouchControls"
	controls.player = run_player
	host.add_child(controls)
	return controls


func _ready() -> void:
	layer = 40
	_root = Control.new()
	_root.name = "TouchRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_stick_base = _disc("StickBase", STICK_RADIUS * 2.0, Color(1, 1, 1, .10))
	_stick_knob = _disc("StickKnob", STICK_RADIUS * .9, Color(1, 1, 1, .28))
	_stick_base.visible = false
	_stick_knob.visible = false
	for entry in BUTTONS:
		_add_button(String(entry[0]), String(entry[1]), StringName(entry[2]), bool(entry[3]))
	get_viewport().size_changed.connect(_layout)
	_layout()


func _disc(node_name: String, size: float, color: Color) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size = Vector2(size, size)
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(int(size * .5))
	panel.add_theme_stylebox_override("panel", box)
	_root.add_child(panel)
	return panel


func _add_button(node_name: String, label: String, action: StringName, hold: bool) -> void:
	var button := Button.new()
	button.name = node_name
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(MIN_TARGET, MIN_TARGET)
	button.add_theme_font_size_override("font_size", 7)
	button.modulate = Color(1, 1, 1, .55)   # see-through: the run stays visible under the thumbs
	# Hold buttons stay pressed while the finger is down; tap buttons are one press too (the action reads
	# is_action_just_pressed), so both release on button_up.
	button.button_down.connect(func() -> void: _press(action))
	button.button_up.connect(func() -> void: _release(action))
	button.set_meta("hold", hold)
	_root.add_child(button)
	_buttons[node_name] = {"button": button, "action": action}


func _press(action: StringName) -> void:
	Input.action_press(action)
	_held[action] = true


func _release(action: StringName) -> void:
	Input.action_release(action)
	_held.erase(action)


## Button grid: the action cluster in the bottom-right corner, the hotbar arrows either side of the HUD's centred hotbar,
## the menu buttons along the top-left after the FPS readout (the top-right holds the HUD's minimap and status).
func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	var unit := maxf(MIN_TARGET, view.y * .13)
	var gap := unit * .16
	var cluster := [["TouchInteract", 0, 0], ["TouchJump", 1, 0], ["TouchTool", 0, 1], ["TouchCrouch", 1, 1], ["TouchLight", 2, 1]]
	for entry in cluster:
		var button: Button = _buttons[String(entry[0])]["button"]
		button.size = Vector2(unit, unit)
		button.position = Vector2(view.x - (int(entry[1]) + 1) * (unit + gap), view.y - (int(entry[2]) + 1) * (unit + gap))
	var hotbar_half := view.x * .19
	var prev: Button = _buttons["TouchPrev"]["button"]
	var next: Button = _buttons["TouchNext"]["button"]
	for button in [prev, next]:
		button.size = Vector2(MIN_TARGET, MIN_TARGET)
	prev.position = Vector2(view.x * .5 - hotbar_half - prev.size.x - gap, view.y - prev.size.y - gap)
	next.position = Vector2(view.x * .5 + hotbar_half + gap, view.y - next.size.y - gap)
	var top := ["TouchPause", "TouchMap", "TouchBag", "TouchChat"]
	for index in top.size():
		var button: Button = _buttons[top[index]]["button"]
		button.size = Vector2(MIN_TARGET, MIN_TARGET)
		button.position = Vector2(view.x * .08 + index * (MIN_TARGET + gap), gap)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var view := get_viewport().get_visible_rect().size
		if touch.pressed:
			if _on_button(touch.position):
				return
			if touch.position.x < view.x * .4 and _stick_touch < 0:
				_stick_touch = touch.index
				_stick_origin = touch.position
				_show_stick(touch.position, Vector2.ZERO)
			elif _look_touch < 0 and touch.position.x >= view.x * .4:
				_look_touch = touch.index
				_look_last = touch.position
		else:
			if touch.index == _stick_touch:
				_stick_touch = -1
				_set_move(Vector2.ZERO)
				_stick_base.visible = false
				_stick_knob.visible = false
			elif touch.index == _look_touch:
				_look_touch = -1
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _stick_touch:
			var offset := drag.position - _stick_origin
			var stick := offset / STICK_RADIUS
			_set_move(stick)
			_show_stick(_stick_origin, offset.limit_length(STICK_RADIUS * SPRINT_PAST))
		elif drag.index == _look_touch:
			var delta := drag.position - _look_last
			_look_last = drag.position
			look_dragged.emit(delta)
			if player != null and player.has_method("apply_look_delta"):
				player.call("apply_look_delta", delta)


func _on_button(at: Vector2) -> bool:
	for key in _buttons:
		var button: Button = _buttons[key]["button"]
		if button.visible and button.get_global_rect().has_point(at):
			return true
	return false


func _show_stick(origin: Vector2, offset: Vector2) -> void:
	_stick_base.visible = true
	_stick_knob.visible = true
	_stick_base.position = origin - _stick_base.size * .5
	_stick_knob.position = origin + offset - _stick_knob.size * .5


## Stick vector (1 = the ring) -> move_* strengths, sprint past the ring.
func _set_move(stick: Vector2) -> void:
	var clamped := stick.limit_length(1.0)
	for pair in [["move_left", -clamped.x], ["move_right", clamped.x], ["move_up", -clamped.y], ["move_down", clamped.y]]:
		var strength := maxf(0.0, float(pair[1]))
		if strength > .05:
			Input.action_press(StringName(pair[0]), strength)
		else:
			Input.action_release(StringName(pair[0]))
	if stick.length() > SPRINT_PAST:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")


func button_names() -> Array:
	return _buttons.keys()


func action_for(node_name: String) -> StringName:
	return _buttons[node_name]["action"] if _buttons.has(node_name) else &""


func _exit_tree() -> void:
	for action in _held.keys():
		Input.action_release(action)
	for action in ["move_left", "move_right", "move_up", "move_down", "sprint"]:
		Input.action_release(action)
