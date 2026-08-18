class_name AdminMenu
extends CanvasLayer

## Developer overlay, on the 0 key.
##
## Gated behind Build.tools_enabled(): debug builds always have it; release
## builds require a live primary-server login as the canonical KYTTU account.
## Everything here either states what the game is currently thinking or
## reaches in and changes it, so a display name is never sufficient proof.
##
## Deliberately NOT a rebindable action. The key is read raw so it never
## appears in the Settings controls list, because a player who rebinds into a
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
## [{"button": Button, "state": Callable}] for actions that expose a live
## ON/OFF chip. Kept separately so the normal every-frame status refresh also
## updates the chips when state changes somewhere other than the button.
var _state_buttons: Array = []
## Ordered [{"label": String, "placeholder": String, "on_submit": Callable(String)}]
## -- a LineEdit per entry, for the rare admin action that needs a value typed
## in (a URL, say) rather than just a press. Enter submits; the field is not
## cleared automatically, since re-submitting the same value (reload the same
## map) is a real thing to want.
var _text_fields: Array = []
var _status: Callable = Callable()


static func attach(host: Node, status: Callable, actions: Array, text_fields: Array = []) -> AdminMenu:
	if not Build.tools_enabled():
		return null
	var menu := AdminMenu.new()
	menu._status = status
	menu._actions = actions
	menu._text_fields = text_fields
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
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 8
	_panel.offset_top = 8
	_panel.offset_right = 178
	_panel.offset_bottom = -8
	_panel.custom_minimum_size = Vector2(170, 0)
	add_child(_panel)

	# The action list is deliberately taller than a 270p design viewport. A
	# bounded ScrollContainer keeps the panel on screen and makes every action
	# reachable instead of letting its minimum height push past the lower rail.
	var scroll := ScrollContainer.new()
	scroll.name = "AdminScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(scroll)

	var column := VBoxContainer.new()
	column.name = "AdminActions"
	column.custom_minimum_size = Vector2(148, 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 3)
	scroll.add_child(column)

	var heading := Label.new()
	heading.text = Palette.track("ADMIN // AUTHORIZED")
	heading.add_theme_color_override("font_color", Palette.AMBER)
	heading.add_theme_font_size_override("font_size", 6)
	column.add_child(heading)

	_readout = Label.new()
	_readout.add_theme_color_override("font_color", Palette.BODY)
	_readout.add_theme_font_size_override("font_size", 7)
	_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_readout)

	for entry in _actions:
		if entry.has("heading"):
			var section := Label.new()
			section.text = String(entry["heading"])
			section.add_theme_color_override("font_color", Palette.AMBER)
			section.add_theme_font_size_override("font_size", 6)
			column.add_child(section)
			if entry.has("items"):
				var grid := GridContainer.new()
				grid.columns = 2
				grid.add_theme_constant_override("h_separation", 3)
				grid.add_theme_constant_override("v_separation", 3)
				column.add_child(grid)
				var item_action: Callable = entry["action"]
				var labels: Dictionary = entry.get("labels", {})
				for item_value in entry["items"]:
					var item_id := String(item_value)
					var item_button := Button.new()
					item_button.text = String(labels.get(item_id, item_id)).to_upper()
					item_button.add_theme_font_size_override("font_size", 6)
					item_button.custom_minimum_size = Vector2(70, 13)
					item_button.focus_mode = Control.FOCUS_NONE
					Palette.style_button(item_button, false, true)
					item_button.pressed.connect(func() -> void:
						item_action.call(item_id)
						_refresh())
					grid.add_child(item_button)
			continue
		var button := Button.new()
		button.text = String(entry["label"])
		button.add_theme_font_size_override("font_size", 7)
		button.custom_minimum_size = Vector2(0, 13)
		button.focus_mode = Control.FOCUS_NONE
		if entry.has("state"):
			var state: Callable = entry["state"]
			Palette.style_state_toggle(button,
				String(entry["label"]).trim_prefix("TOGGLE "),
				bool(state.call()), true)
			_state_buttons.append({"button": button, "state": state})
		else:
			Palette.style_button(button, false, true)
		var action: Callable = entry["action"]
		button.pressed.connect(func() -> void:
			action.call()
			_refresh())
		column.add_child(button)

	for entry in _text_fields:
		var field_label := Label.new()
		field_label.text = String(entry["label"])
		field_label.add_theme_color_override("font_color", Palette.MUTED)
		field_label.add_theme_font_size_override("font_size", 6)
		column.add_child(field_label)

		var field := LineEdit.new()
		field.placeholder_text = String(entry.get("placeholder", ""))
		field.add_theme_font_size_override("font_size", 7)
		field.custom_minimum_size = Vector2(0, 15)
		Palette.style_line_edit(field)
		var on_submit: Callable = entry["on_submit"]
		field.text_submitted.connect(func(value: String) -> void:
			on_submit.call(value)
			_refresh())
		column.add_child(field)

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
	for entry in _state_buttons:
		Palette.set_state_toggle(entry["button"], bool(entry["state"].call()))


func _process(_delta: float) -> void:
	if _open:
		_refresh()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	var is_toggle := key.physical_keycode == TOGGLE_KEY \
		or key.keycode == TOGGLE_KEY \
		or key.physical_keycode == KEY_KP_0 or key.keycode == KEY_KP_0
	if key.pressed and not key.echo and is_toggle:
		_set_open(not _open)
		get_viewport().set_input_as_handled()
