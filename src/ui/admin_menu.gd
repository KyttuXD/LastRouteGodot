class_name AdminMenu
extends CanvasLayer

## Developer overlay, on the 0 key.
##
## Gated behind Build.tools_enabled(), which is false in a release export
## whatever anyone forgets to strip. This is the first real customer for that
## policy: everything here either states what the game is currently thinking or
## reaches in and changes it, and both are things a normal build must not offer.
##
## Deliberately NOT a rebindable action. The key is read raw so it never
## appears in the Controls list, because a player who rebinds their way into a
## dev menu has found a bug, not a feature.
##
## Actions are supplied by whoever builds it, so this file knows nothing about
## maze or office specifics -- it draws rows and calls Callables. That is what
## keeps one overlay serving two modes that share almost no state.

const TOGGLE_KEY := KEY_0

var _panel: PanelContainer
var _readout: Label
var _open := false
## Ordered [{"label": String, "action": Callable}] and a Callable returning the
## status text, both handed in by the mode that built this.
var _actions: Array = []
var _status: Callable = Callable()


static func attach(host: Node, status: Callable, actions: Array) -> AdminMenu:
	if not Build.tools_enabled():
		return null
	var menu := AdminMenu.new()
	menu._status = status
	menu._actions = actions
	host.add_child(menu)
	return menu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120
	_build()


func is_open() -> bool:
	return _open


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel",
		Palette.panel_box(Palette.PANEL, Palette.AMBER, 8))
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.offset_left = 8
	_panel.offset_top = 8
	_panel.custom_minimum_size = Vector2(150, 0)
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	_panel.add_child(column)

	var heading := Label.new()
	heading.text = Palette.track("ADMIN // NOT IN RELEASE")
	heading.add_theme_color_override("font_color", Palette.AMBER)
	heading.add_theme_font_size_override("font_size", 6)
	column.add_child(heading)

	_readout = Label.new()
	_readout.add_theme_color_override("font_color", Palette.BODY)
	_readout.add_theme_font_size_override("font_size", 7)
	column.add_child(_readout)

	for entry in _actions:
		var button := Button.new()
		button.text = String(entry["label"])
		button.add_theme_font_size_override("font_size", 7)
		button.custom_minimum_size = Vector2(0, 13)
		button.focus_mode = Control.FOCUS_NONE
		Palette.style_button(button, false)
		var action: Callable = entry["action"]
		button.pressed.connect(func() -> void:
			action.call()
			_refresh())
		column.add_child(button)

	var hint := Label.new()
	hint.text = "0 CLOSES"
	hint.add_theme_color_override("font_color", Palette.MUTED)
	hint.add_theme_font_size_override("font_size", 6)
	column.add_child(hint)

	_set_open(false)


func _set_open(shown: bool) -> void:
	_open = shown
	_panel.visible = shown
	# The overlay is clickable, so it needs the cursor -- and it must not take
	# it from a mode that is running normally when it is closed.
	MouseLock.claim("admin", shown)
	if shown:
		_refresh()


func _refresh() -> void:
	if _status.is_valid():
		_readout.text = String(_status.call())


func _process(_delta: float) -> void:
	if _open:
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.physical_keycode == TOGGLE_KEY:
		_set_open(not _open)
		get_viewport().set_input_as_handled()
