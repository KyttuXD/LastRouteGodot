class_name XRPanelScroll
extends RefCounted

## Scrolling the 2D screens on the headset panels (XRMenuPanel, XRRoutePanel; docs/XR_ANDROID.md). Scroll containers
## only drag-scroll for touch, and the panels drive the UI with a mouse, so this moves them directly:
##
##   stick      up / down on EITHER controller scrolls the ScrollContainer under the laser (or the focused one), smoothly,
##              faster the longer it is held; left / right steps the menu carousel (ui_left / ui_right)
##   drag       holding the trigger and moving past DRAG_DEADZONE scrolls like a finger; a press that does not move
##              stays an ordinary click. Sliders and scroll bars under the laser keep their normal drag.
##
## Containers it scrolls show their scroll bar (a hidden one is switched to automatic).

const STICK_DEADZONE := 0.25
const SPEED := 260.0
const MAX_SPEED := 1100.0
const ACCEL_SECONDS := 1.2
const CARD_PUSH := 0.6
const CARD_RELEASE := 0.3
## Canvas units the pointer must travel with the trigger held before a press becomes a drag.
const DRAG_DEADZONE := 6.0

var _held_seconds := 0.0
var _residual := 0.0
var _card_latched := false
var _press_canvas := Vector2(-1, -1)
var _drag_target: ScrollContainer
var _drag_start_scroll := 0
var dragging := false
## True while the press under the laser belongs to a slider or scroll bar (passed through as a real mouse drag).
var passthrough := false


## The ScrollContainer to scroll: the first scrollable one above the control under the pointer, else above the focus.
static func target_in(viewport: Viewport) -> ScrollContainer:
	for start in [viewport.gui_get_hovered_control(), viewport.gui_get_focus_owner()]:
		var node: Node = start
		while node is Control:
			if node is ScrollContainer and can_scroll(node):
				return node
			node = node.get_parent()
	return null


static func can_scroll(container: ScrollContainer) -> bool:
	var bar := container.get_v_scroll_bar()
	return bar != null and bar.max_value - bar.page > 1.0


static func _show_bar(container: ScrollContainer) -> void:
	if container.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER:
		container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO


## One frame of the sticks (the stronger of the two): vertical scrolls, a horizontal push steps the carousel once.
func stick(viewport: Viewport, sticks: Array, delta: float) -> void:
	var pushed := Vector2.ZERO
	for value in sticks:
		var axis: Vector2 = value
		if axis.length() > pushed.length():
			pushed = axis
	if absf(pushed.y) >= STICK_DEADZONE and absf(pushed.y) >= absf(pushed.x):
		_held_seconds += delta
		var target := target_in(viewport)
		if target != null:
			_show_bar(target)
			var speed := lerpf(SPEED, MAX_SPEED, clampf(_held_seconds / ACCEL_SECONDS, 0.0, 1.0))
			var tilt := (absf(pushed.y) - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)
			_residual += -signf(pushed.y) * tilt * speed * delta   # stick up (+y) scrolls towards the top
			var whole := int(_residual)
			_residual -= whole
			target.scroll_vertical += whole
	else:
		_held_seconds = 0.0
		_residual = 0.0
	if absf(pushed.x) >= CARD_PUSH and absf(pushed.x) > absf(pushed.y):
		if not _card_latched:
			_card_latched = true
			for pressed in [true, false]:
				var step := InputEventAction.new()
				step.action = &"ui_right" if pushed.x > 0.0 else &"ui_left"
				step.pressed = pressed
				Input.parse_input_event(step)
	elif absf(pushed.x) < CARD_RELEASE:
		_card_latched = false


## The trigger went down with the pointer at `canvas` (the viewport's canvas coordinates).
func press(viewport: Viewport, canvas: Vector2) -> void:
	_press_canvas = canvas
	dragging = false
	_drag_target = null
	var hovered := viewport.gui_get_hovered_control()
	passthrough = hovered is Range or (hovered != null and hovered.get_parent() is ScrollBar)


## The pointer moved to `canvas` with the trigger held. Returns true once the press has become a drag scroll.
func move(viewport: Viewport, canvas: Vector2) -> bool:
	if _press_canvas.x < 0.0 or passthrough:
		return false
	if not dragging:
		if canvas.distance_to(_press_canvas) < DRAG_DEADZONE:
			return false
		_drag_target = target_in(viewport)
		if _drag_target == null:
			return false
		dragging = true
		_show_bar(_drag_target)
		_drag_start_scroll = _drag_target.scroll_vertical
	if is_instance_valid(_drag_target):
		_drag_target.scroll_vertical = _drag_start_scroll - int(canvas.y - _press_canvas.y)
	return true


## The trigger came up. Returns true if the press was a drag (so it must not also click).
func release() -> bool:
	var was_drag := dragging
	dragging = false
	passthrough = false
	_press_canvas = Vector2(-1, -1)
	_drag_target = null
	return was_drag
