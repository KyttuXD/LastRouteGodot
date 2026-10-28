class_name TouchControls
extends CanvasLayer

## On-screen controls for phones (PlatformProfile.is_phone; docs/XR_ANDROID.md). Everything feeds the game's ordinary
## Input actions (move_*, sprint, jump, crouch, interact, flashlight, tool_use, hotbar_*, inventory, toggle_map, chat,
## pause), so gameplay, networking and validators see the same inputs a keyboard would make. Look is a drag on any free
## part of the screen, turned into angles here (look_turn: screen-independent, the TOUCH LOOK settings) and applied
## through PlayerController3D.apply_look_turn on every drag event. Desktop never creates this node.
##
## Movement is a fixed D-pad in the bottom-left corner by default (Settings.touch_move "dpad"): four arrows at full
## strength, diagonals by touching between two arrows or with two fingers, and a double tap held on an arrow sprints
## that way until released. Settings.touch_move "stick" swaps in the floating analogue stick (sprint past the ring).
## No movement zone overlaps the HUD hotbar or its arrows, and while the inventory is open it gets every touch: only
## the bag and pause buttons stay. The buttons never play the menu blip (Sound skips "silent_ui" buttons).

signal look_dragged(delta: Vector2)

## Stick radius in canvas units (see MIN_TARGET).
const STICK_RADIUS := 30.0
const SPRINT_PAST := 1.15
## Minimum touch target in canvas units (the UI is laid out on the 480 x 270 base canvas and stretched): 26 units are
## about 12 % of the screen height, roughly 48 dp on a phone held landscape.
const MIN_TARGET := 26.0
## One D-pad cell; the pad is 3 x 3 cells with the arrows on the edges and a dead centre.
const PAD_CELL := 30.0
## Dragging across the screen's short side turns this far at LOOK SPEED 1.0 (the same on every screen size).
const LOOK_DEGREES_PER_SHORT_SIDE := 180.0
## LOOK SMOOTHING time constants (seconds) for "low" and "high"; "off" applies each drag at once.
const LOOK_SMOOTHING_SECONDS := {"off": 0.0, "low": 0.03, "high": 0.08}
## A second press on the same arrow within this many seconds of letting go sprints.
const DOUBLE_TAP_SECONDS := 0.3
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
	["TouchQuick", "QUICK", "quick_chat", false],
	["TouchPause", "II", "pause", false],
]
## Buttons that stay while the inventory is open (it owns every other touch).
const INVENTORY_BUTTONS := ["TouchBag", "TouchPause"]
## D-pad arrows: [node name, label, direction]
const ARROWS := [
	["PadUp", "^", Vector2(0, -1)],
	["PadDown", "v", Vector2(0, 1)],
	["PadLeft", "<", Vector2(-1, 0)],
	["PadRight", ">", Vector2(1, 0)],
]

var player: Node
var hud: Node
var _root: Control
var _stick_base: Control
var _stick_knob: Control
var _pad: Control
var _arrows := {}
var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _look_touch := -1
var _look_last := Vector2.ZERO
var _buttons := {}
var _held := {}
## D-pad touches: index -> {"dir": Vector2, "sprint": bool}
var _pad_touches := {}
## The last D-pad direction let go, and when (seconds), for the double tap.
var _last_pad_release := {"dir": Vector2.ZERO, "at": -10.0}
var _mode := ""
## Turn still to apply when LOOK SMOOTHING is on (radians: x yaw right, y pitch down).
var _pending_look := Vector2.ZERO
## The hotbar rect the last layout used: the HUD sizes its slots after this node is ready, so a change re-lays out.
var _laid_out_hotbar := Rect2()
var _inventory_open := false


## A look drag of `drag` canvas units, as radians (x: turn right, y: tilt down), on a screen whose short side is
## `short_side` units. Speed and vertical scale come from the TOUCH LOOK settings; with acceleration a fast flick
## (more than one short side per second) turns up to 2.5 times as far. Independent of the mouse sensitivity.
static func look_turn(drag: Vector2, short_side: float, speed: float, vertical: float, invert_y: bool,
		accel: bool, drag_speed: float) -> Vector2:
	var per_unit := deg_to_rad(LOOK_DEGREES_PER_SHORT_SIDE) * speed / maxf(short_side, 1.0)
	var boost := 1.0
	if accel:
		boost = 1.0 + clampf((drag_speed / maxf(short_side, 1.0) - 1.0) * 0.75, 0.0, 1.5)
	return Vector2(drag.x, drag.y * vertical * (-1.0 if invert_y else 1.0)) * per_unit * boost


static func attach(host: Node, run_player: Node, run_hud: Node = null) -> TouchControls:
	var controls := TouchControls.new()
	controls.name = "TouchControls"
	controls.player = run_player
	controls.hud = run_hud
	host.add_child(controls)
	return controls


## The D-pad direction for a point in pad-local coordinates (the pad is 3 x 3 cells of PAD_CELL): edges and corners
## give the arrow or the diagonal between two arrows, the centre cell nothing, outside the pad nothing.
static func pad_direction(local: Vector2) -> Vector2:
	var size := PAD_CELL * 3.0
	if local.x < 0.0 or local.y < 0.0 or local.x > size or local.y > size:
		return Vector2.ZERO
	var column := clampi(int(local.x / PAD_CELL), 0, 2) - 1
	var row := clampi(int(local.y / PAD_CELL), 0, 2) - 1
	return Vector2(column, row)


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
	_pad = Control.new()
	_pad.name = "DPad"
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.size = Vector2.ONE * PAD_CELL * 3.0
	_root.add_child(_pad)
	for entry in ARROWS:
		var arrow := Button.new()
		arrow.name = String(entry[0])
		arrow.text = String(entry[1])
		arrow.focus_mode = Control.FOCUS_NONE
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE   # the pad reads raw touches (slides, two fingers)
		arrow.add_theme_font_size_override("font_size", 9)
		arrow.modulate = Color(1, 1, 1, .5)
		arrow.size = Vector2.ONE * PAD_CELL
		var direction: Vector2 = entry[2]
		arrow.position = (direction + Vector2.ONE) * PAD_CELL
		arrow.set_meta("silent_ui", true)
		_pad.add_child(arrow)
		_arrows[direction] = arrow
	for entry in BUTTONS:
		_add_button(String(entry[0]), String(entry[1]), StringName(entry[2]), bool(entry[3]))
	get_viewport().size_changed.connect(_layout)
	_layout()
	_apply_mode()


func _process(delta: float) -> void:
	if _pending_look != Vector2.ZERO:
		var tau := float(LOOK_SMOOTHING_SECONDS.get(Settings.touch_look_smoothing, 0.0))
		var step := _pending_look if tau <= 0.0 else _pending_look * (1.0 - exp(-delta / tau))
		_pending_look -= step
		if _pending_look.length() < 0.0001:
			step += _pending_look
			_pending_look = Vector2.ZERO
		_turn(step)
	if not hotbar_rect().is_equal_approx(_laid_out_hotbar):
		_layout()
	if _mode != Settings.touch_move:
		_apply_mode()
	var open := hud != null and hud.has_method("inventory_is_open") and bool(hud.call("inventory_is_open"))
	if open != _inventory_open:
		_inventory_open = open
		_release_movement()
		_look_touch = -1
		for key in _buttons:
			_buttons[key]["button"].visible = not open or INVENTORY_BUTTONS.has(key)
		_pad.visible = not open and _mode == "dpad"


func _apply_mode() -> void:
	_mode = Settings.touch_move
	_release_movement()
	_pad.visible = _mode == "dpad" and not _inventory_open


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
	button.set_meta("silent_ui", true)   # set before entering the tree: Sound wires buttons as they are added
	_root.add_child(button)
	_buttons[node_name] = {"button": button, "action": action}


func _press(action: StringName) -> void:
	Input.action_press(action)
	_held[action] = true


func _release(action: StringName) -> void:
	Input.action_release(action)
	_held.erase(action)


## The HUD hotbar's rect on this canvas (its real slots when the HUD is known, else where the HUD puts it).
func hotbar_rect() -> Rect2:
	if hud != null and hud.has_method("hotbar_rect"):
		var rect: Rect2 = hud.call("hotbar_rect")
		if rect.size.x > 0.0:
			return rect
	var view := get_viewport().get_visible_rect().size
	return Rect2(view.x * .5 - view.x * .19, view.y - MIN_TARGET * 1.6, view.x * .38, MIN_TARGET * 1.6)


## Left and right insets (canvas units) that keep the controls clear of a notch, Dynamic Island or rounded corners
## (DisplayServer's safe area; zero on screens without a cutout or where the OS already letterboxes it).
func safe_insets() -> Vector2:
	var window := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if window.x <= 0.0 or safe.size.x <= 0.0 or safe.size.x >= window.x:
		return Vector2.ZERO
	var scale := get_viewport().get_visible_rect().size.x / window.x
	return Vector2(maxf(0.0, safe.position.x), maxf(0.0, window.x - safe.end.x)) * scale


## Button grid: the action cluster in the bottom-right corner, the D-pad in the bottom-left, the hotbar arrows just
## outside the HUD's centred hotbar, the menu buttons along the top-left after the FPS readout (the top-right holds the
## HUD's minimap and status).
func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	var unit := maxf(MIN_TARGET, view.y * .13)
	var gap := unit * .16
	var insets := safe_insets()
	var cluster := [["TouchInteract", 0, 0], ["TouchJump", 1, 0], ["TouchTool", 0, 1], ["TouchCrouch", 1, 1], ["TouchLight", 2, 1]]
	for entry in cluster:
		var button: Button = _buttons[String(entry[0])]["button"]
		button.size = Vector2(unit, unit)
		button.position = Vector2(view.x - insets.y - (int(entry[1]) + 1) * (unit + gap), view.y - (int(entry[2]) + 1) * (unit + gap))
	_pad.position = Vector2(insets.x + gap * 2.0, view.y - _pad.size.y - gap)
	var hotbar := hotbar_rect()
	_laid_out_hotbar = hotbar
	var prev: Button = _buttons["TouchPrev"]["button"]
	var next: Button = _buttons["TouchNext"]["button"]
	for button in [prev, next]:
		button.size = Vector2(MIN_TARGET, MIN_TARGET)
	var arrow_y := hotbar.position.y + hotbar.size.y - MIN_TARGET
	prev.position = Vector2(hotbar.position.x - MIN_TARGET - gap * .5, arrow_y)
	next.position = Vector2(hotbar.end.x + gap * .5, arrow_y)
	var top := ["TouchPause", "TouchMap", "TouchBag", "TouchChat", "TouchQuick"]
	for index in top.size():
		var button: Button = _buttons[top[index]]["button"]
		button.size = Vector2(MIN_TARGET, MIN_TARGET)
		button.position = Vector2(maxf(view.x * .08, insets.x + gap) + index * (MIN_TARGET + gap), gap)


## The movement zone: the D-pad's rect, or the stick's left 40 % (minus the hotbar and its arrows).
func movement_rect() -> Rect2:
	if _mode == "dpad":
		return Rect2(_pad.position, _pad.size)
	var view := get_viewport().get_visible_rect().size
	return Rect2(Vector2.ZERO, Vector2(view.x * .4, view.y))


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _inventory_open or _on_button(touch.position) or hotbar_rect().has_point(touch.position):
				return
			if _mode == "dpad" and movement_rect().has_point(touch.position):
				_pad_press(touch.index, touch.position)
			elif _mode == "stick" and movement_rect().has_point(touch.position) and _stick_touch < 0:
				_stick_touch = touch.index
				_stick_origin = touch.position
				_show_stick(touch.position, Vector2.ZERO)
			elif _look_touch < 0:
				_look_touch = touch.index
				_look_last = touch.position
		else:
			if _pad_touches.has(touch.index):
				_pad_release(touch.index)
			elif touch.index == _stick_touch:
				_stick_touch = -1
				_set_move(Vector2.ZERO)
				_stick_base.visible = false
				_stick_knob.visible = false
			elif touch.index == _look_touch:
				_look_touch = -1
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _pad_touches.has(drag.index):
			_pad_slide(drag.index, drag.position)
		elif drag.index == _stick_touch:
			var offset := drag.position - _stick_origin
			var stick := offset / STICK_RADIUS
			_set_move(stick)
			_show_stick(_stick_origin, offset.limit_length(STICK_RADIUS * SPRINT_PAST))
		elif drag.index == _look_touch:
			var delta := drag.position - _look_last
			_look_last = drag.position
			look_dragged.emit(delta)
			var view := get_viewport().get_visible_rect().size
			var turn := look_turn(delta, minf(view.x, view.y), Settings.touch_look_speed, Settings.touch_look_vertical,
				Settings.touch_look_invert_y, Settings.touch_look_accel, drag.velocity.length())
			if float(LOOK_SMOOTHING_SECONDS.get(Settings.touch_look_smoothing, 0.0)) > 0.0:
				_pending_look += turn
			else:
				_turn(turn)


func _turn(turn: Vector2) -> void:
	if player != null and player.has_method("apply_look_turn"):
		player.call("apply_look_turn", turn)


## A finger lands on the pad. Landing on the arrow just let go (within DOUBLE_TAP_SECONDS) sprints.
func _pad_press(index: int, at: Vector2) -> void:
	var direction := pad_direction(at - _pad.position)
	var now := Time.get_ticks_msec() / 1000.0
	var sprint := direction != Vector2.ZERO and direction == Vector2(_last_pad_release["dir"]) \
		and now - float(_last_pad_release["at"]) <= DOUBLE_TAP_SECONDS
	_pad_touches[index] = {"dir": direction, "sprint": sprint}
	_apply_pad()


## Sliding between arrows changes direction; sprint holds while the finger stays down.
func _pad_slide(index: int, at: Vector2) -> void:
	var entry: Dictionary = _pad_touches[index]
	var direction := pad_direction(at - _pad.position)
	if direction == Vector2.ZERO and not Rect2(Vector2.ZERO, _pad.size).has_point(at - _pad.position):
		direction = Vector2(entry["dir"])   # slid off the pad: keep going the way it was
	entry["dir"] = direction
	_apply_pad()


func _pad_release(index: int) -> void:
	var entry: Dictionary = _pad_touches[index]
	_pad_touches.erase(index)
	_last_pad_release = {"dir": entry["dir"], "at": Time.get_ticks_msec() / 1000.0}
	_apply_pad()


## Every finger on the pad together: the combined direction at full strength, sprint if any of them double-tapped.
func _apply_pad() -> void:
	var direction := Vector2.ZERO
	var sprint := false
	for entry in _pad_touches.values():
		direction += Vector2(entry["dir"])
		sprint = sprint or bool(entry["sprint"])
	direction = Vector2(signf(direction.x), signf(direction.y))
	set_pad(direction, sprint)


## D-pad output: each axis at full strength, sprint while a double-tapped arrow is held.
func set_pad(direction: Vector2, sprint: bool) -> void:
	for pair in [["move_left", -direction.x], ["move_right", direction.x], ["move_up", -direction.y], ["move_down", direction.y]]:
		if float(pair[1]) > 0.0:
			Input.action_press(StringName(pair[0]), 1.0)
		else:
			Input.action_release(StringName(pair[0]))
	if sprint and direction != Vector2.ZERO:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")
	for key in _arrows:
		var lit: bool = (key.x != 0.0 and key.x == direction.x) or (key.y != 0.0 and key.y == direction.y)
		(_arrows[key] as Button).modulate = Color(1, 1, 1, .9 if lit else .5)


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


func _release_movement() -> void:
	_pad_touches.clear()
	_stick_touch = -1
	if _stick_base != null:
		_stick_base.visible = false
		_stick_knob.visible = false
	for action in ["move_left", "move_right", "move_up", "move_down", "sprint"]:
		Input.action_release(action)


func button_names() -> Array:
	return _buttons.keys()


func action_for(node_name: String) -> StringName:
	return _buttons[node_name]["action"] if _buttons.has(node_name) else &""


func _exit_tree() -> void:
	for action in _held.keys():
		Input.action_release(action)
	_release_movement()
