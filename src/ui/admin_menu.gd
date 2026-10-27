class_name AdminMenu
extends CanvasLayer

signal open_changed(shown: bool)

## Developer overlay, on the 0 key.
##
## Gated behind Build.tools_enabled(): player-facing debug and release builds
## require a live primary-server owner/scoped-admin login.
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
var _dimmer: ColorRect
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
var _first_action_button: Button
var _badge: Label


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
	_build_badge()


## "ADMIN ACTIVE" tag, top centre, also while the panel is closed, so an admin in a shared route or
## room (and anyone watching their screen) can see the tools are on. Says where, and DEBUG RUN once used.
func _build_badge() -> void:
	_badge = Label.new()
	_badge.name = "AdminActiveBadge"
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_theme_font_size_override("font_size", 6)
	_badge.add_theme_color_override("font_color", Palette.ON_AMBER)
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.TEAL
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	_badge.add_theme_stylebox_override("normal", box)
	_badge.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_badge.offset_top = 16 if Backend.test_server_active else 4
	add_child(_badge)
	_refresh_badge()


func _refresh_badge() -> void:
	if _badge == null:
		return
	var where := "SOLO"
	if RoomState.public_route:
		where = "PUBLIC ROUTE"
	elif RoomState.online:
		where = "ROOM"
	_badge.text = "ADMIN ACTIVE // %s%s" % [where, " // DEBUG RUN (NOT RECORDED)" if GameState.debug_run else ""]


func is_open() -> bool:
	return _open


func close() -> void:
	if _open:
		_set_open(false)


## The panel is laid out in canvas units (the 480x270 design viewport, which expands with the window): it takes about 92% of
## the width up to MAX_SIZE and 90% of the height, is opaque, scrolls when a section does not fit, and is re-fitted
## whenever the window changes, so it is readable and on screen at every resolution.
const MAX_SIZE := Vector2(420, 300)
const MIN_SIZE := Vector2(300, 190)
## The panel is zoomed so one canvas unit is never smaller than this many pixels (8-unit text stays >= ~13 px).
const MIN_PX_PER_UNIT := 1.6
const SECTION_DEFAULT := "GENERAL"

var _tabs: TabBar
var _pages: Array[Control] = []
var _section_titles: Array[String] = []
## Dropdown rows: [{"option": OptionButton, "ids": Array}] so tests can read what each dropdown offers.
var _dropdowns: Array = []


func _build() -> void:
	_dimmer = ColorRect.new()
	_dimmer.name = "AdminModalDimmer"
	_dimmer.color = Color(0.0, 0.0, 0.0, 0.8)
	_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dimmer)

	_panel = PanelContainer.new()
	_panel.name = "AdminPanel"
	_panel.add_theme_stylebox_override("panel",
		Palette.panel_box(Color(Palette.PANEL, 1.0), Palette.AMBER, 8))
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(_panel)
	get_viewport().size_changed.connect(_fit_panel)

	var root := VBoxContainer.new()
	root.name = "AdminRoot"
	root.add_theme_constant_override("separation", 3)
	_panel.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var heading := Label.new()
	heading.text = Palette.track("ADMIN // AUTHORIZED")
	heading.add_theme_color_override("font_color", Palette.AMBER)
	heading.add_theme_font_size_override("font_size", 8)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var close_button := Button.new()
	close_button.name = "AdminClose"
	close_button.text = "0 / ESC"
	close_button.add_theme_font_size_override("font_size", 7)
	Palette.style_button(close_button, false, true)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	_tabs = TabBar.new()
	_tabs.name = "AdminTabs"
	_tabs.tab_alignment = TabBar.ALIGNMENT_LEFT
	_tabs.clip_tabs = true
	_tabs.custom_minimum_size = Vector2(60, 0)
	_tabs.add_theme_font_size_override("font_size", 7)
	_tabs.tab_changed.connect(_show_page)
	root.add_child(_tabs)

	var body := PanelContainer.new()
	body.name = "AdminBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_stylebox_override("panel", Palette.panel_box(Palette.INSET, Palette.PANEL_EDGE, 5))
	root.add_child(body)
	var stack := Control.new()
	stack.name = "AdminPages"
	body.add_child(stack)
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)

	# status page first, then one page per section
	_add_page("STATUS", stack)
	_readout = Label.new()
	_readout.add_theme_color_override("font_color", Palette.INK)
	_readout.add_theme_font_size_override("font_size", 8)
	_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_column(0).add_child(_readout)

	var sections := _group_sections()
	for section in sections:
		var page_index := _add_page(String(section["title"]), stack)
		_fill_section(_page_column(page_index), section["rows"])
	var text_rows := []
	for entry in _text_fields:
		if _entry_allowed(entry):
			text_rows.append(entry)
	if not text_rows.is_empty():
		var page_index := _add_page("FIELDS", stack)
		for entry in text_rows:
			_add_text_field(_page_column(page_index), entry)

	var hint := Label.new()
	hint.text = "0 OR ESC CLOSES  //  DROPDOWN, THEN RUN"
	hint.add_theme_color_override("font_color", Palette.MUTED)
	hint.add_theme_font_size_override("font_size", 6)
	root.add_child(hint)
	_show_page(0)
	_fit_panel()
	_set_open(false)


func _add_page(title: String, stack: Control) -> int:
	var scroll := ScrollContainer.new()
	scroll.name = "AdminPage_%s" % title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(scroll)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	scroll.add_child(column)
	_pages.append(scroll)
	_section_titles.append(title)
	_tabs.add_tab(title)
	return _pages.size() - 1


func _page_column(index: int) -> VBoxContainer:
	return _pages[index].get_node("Column") as VBoxContainer


func _show_page(index: int) -> void:
	for i in _pages.size():
		_pages[i].visible = i == index


## Pixels per canvas unit of the viewport the menu is drawn in (the window's stretch factor).
func _px_per_unit() -> float:
	return maxf(.1, get_viewport().get_final_transform().get_scale().x)


func _fit_panel() -> void:
	if _panel == null:
		return
	var view := get_viewport().get_visible_rect().size
	# Small effective scales (a phone-sized window) would shrink the text below readability: draw the panel zoomed instead
	# and give it that much less room in canvas units.
	var zoom := clampf(MIN_PX_PER_UNIT / _px_per_unit(), 1.0, 2.4)
	var room := view / zoom
	var size := Vector2(clampf(room.x * 0.94, 200.0, MAX_SIZE.x), clampf(room.y * 0.92, 150.0, MAX_SIZE.y)).min(room)
	_panel.scale = Vector2(zoom, zoom)
	_panel.size = size
	_panel.position = (view - size * zoom) * 0.5


## Turns the flat action list into sections: a heading entry WITHOUT items starts a section, an entry with items is a
## dropdown row, plain actions in one section share a single "action" dropdown, `state` entries are checkboxes and
## `hunter_tool` is the hunter picker.
func _group_sections() -> Array:
	var sections := []
	var current := {"title": SECTION_DEFAULT, "rows": []}
	for entry_value in _actions:
		var entry: Dictionary = entry_value
		if not _entry_allowed(entry):
			continue
		if entry.has("heading") and not entry.has("items") and not entry.has("hunter_tool") and not entry.has("action"):
			if not (current["rows"] as Array).is_empty():
				sections.append(current)
			current = {"title": String(entry["heading"]).split(" // ")[0], "rows": []}
			continue
		(current["rows"] as Array).append(entry)
	if not (current["rows"] as Array).is_empty():
		sections.append(current)
	return sections


func _fill_section(column: VBoxContainer, rows: Array) -> void:
	var plain := []
	for entry_value in rows:
		var entry: Dictionary = entry_value
		if entry.has("hunter_tool"):
			_add_hunter_tool(column, entry)
		elif entry.has("items"):
			_add_items_dropdown(column, entry)
		elif entry.has("state"):
			_add_checkbox(column, entry)
		elif entry.has("action"):
			plain.append(entry)
	if not plain.is_empty():
		_add_action_dropdown(column, plain)


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Palette.AMBER)
	label.add_theme_font_size_override("font_size", 7)
	return label


func _dropdown(ids: Array, labels: Dictionary) -> OptionButton:
	var option := OptionButton.new()
	option.add_theme_font_size_override("font_size", 8)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.custom_minimum_size = Vector2(120, 18)
	option.fit_to_longest_item = false
	option.focus_mode = Control.FOCUS_ALL
	Palette.style_button(option, false, true)
	var popup := option.get_popup()
	popup.add_theme_font_size_override("font_size", 8)
	for id in ids:
		option.add_item(String(labels.get(String(id), String(id))).to_upper())
	return option


func _run_button(text: String = "RUN") -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 8)
	button.custom_minimum_size = Vector2(46, 18)
	button.focus_mode = Control.FOCUS_ALL
	Palette.style_button(button, true, true)
	return button


func _remember_first(control: Control) -> void:
	if _first_action_button == null and control is Button:
		_first_action_button = control as Button


func _add_items_dropdown(column: VBoxContainer, entry: Dictionary) -> void:
	column.add_child(_caption(String(entry.get("heading", entry.get("label", "")))))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	column.add_child(row)
	var ids: Array = entry["items"]
	var option := _dropdown(ids, entry.get("labels", {}))
	row.add_child(option)
	var run := _run_button()
	row.add_child(run)
	_dropdowns.append({"option": option, "ids": ids, "entry": entry})
	var action: Callable = entry["action"]
	run.pressed.connect(func() -> void:
		if option.selected >= 0 and option.selected < ids.size():
			action.call(String(ids[option.selected]))
			_mark_debug(entry)
			_refresh())
	_remember_first(option)


func _add_action_dropdown(column: VBoxContainer, plain: Array) -> void:
	column.add_child(_caption("ACTION"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	column.add_child(row)
	var ids := []
	var labels := {}
	for index in plain.size():
		ids.append(str(index))
		labels[str(index)] = String(plain[index]["label"])
	var option := _dropdown(ids, labels)
	row.add_child(option)
	var run := _run_button()
	row.add_child(run)
	_dropdowns.append({"option": option, "ids": ids, "entries": plain})
	run.pressed.connect(func() -> void:
		var index: int = option.selected
		if index >= 0 and index < plain.size():
			var entry: Dictionary = plain[index]
			(entry["action"] as Callable).call()
			_mark_debug(entry)
			_refresh())
	_remember_first(option)


func _add_checkbox(column: VBoxContainer, entry: Dictionary) -> void:
	var state: Callable = entry["state"]
	var box := CheckBox.new()
	box.name = "Check_" + String(entry["label"]).replace(" ", "_")
	box.custom_minimum_size = Vector2(0, 17)
	box.focus_mode = Control.FOCUS_ALL
	box.button_pressed = bool(state.call())
	Palette.style_state_toggle(box, String(entry["label"]).trim_prefix("TOGGLE "), bool(state.call()), true)
	_state_buttons.append({"button": box, "state": state})
	var action: Callable = entry["action"]
	box.pressed.connect(func() -> void:
		action.call()
		_mark_debug(entry)
		_refresh())
	column.add_child(box)
	_remember_first(box)


## "Hunter" picker: one dropdown of every A-Z and Void hunter, one of what to do to it (and, for emotes, which emote), one Run.
func _add_hunter_tool(column: VBoxContainer, entry: Dictionary) -> void:
	column.add_child(_caption("HUNTER"))
	var hunters: Array = entry["hunters"]
	var hunter_option := _dropdown(hunters, entry.get("hunter_labels", {}))
	column.add_child(hunter_option)
	column.add_child(_caption("DO"))
	var actions: Array = entry["hunter_tool"]
	var action_ids := []
	var action_labels := {}
	for index in actions.size():
		action_ids.append(str(index))
		action_labels[str(index)] = String(actions[index]["label"])
	var action_option := _dropdown(action_ids, action_labels)
	column.add_child(action_option)
	var emote_ids: Array = entry.get("emotes", [])
	var emote_row := HBoxContainer.new()
	var emote_label := _caption("EMOTE")
	emote_row.add_child(emote_label)
	var emote_option := _dropdown(emote_ids, entry.get("emote_labels", {}))
	emote_row.add_child(emote_option)
	column.add_child(emote_row)
	var run := _run_button()
	column.add_child(run)
	_dropdowns.append({"option": hunter_option, "ids": hunters, "entry": entry})
	_dropdowns.append({"option": action_option, "ids": action_ids, "entry": entry})
	var sync_emote := func() -> void:
		var wants: bool = action_option.selected >= 0 and bool((actions[action_option.selected] as Dictionary).get("emote", false))
		emote_row.visible = wants
	action_option.item_selected.connect(func(_i: int) -> void: sync_emote.call())
	sync_emote.call()
	run.pressed.connect(func() -> void:
		if hunter_option.selected < 0 or action_option.selected < 0:
			return
		var act: Dictionary = actions[action_option.selected]
		var hunter_id := String(hunters[hunter_option.selected])
		var extra := String(emote_ids[emote_option.selected]) if bool(act.get("emote", false)) and emote_option.selected >= 0 else ""
		(act["call"] as Callable).call(hunter_id, extra)
		_mark_debug(entry)
		_refresh())
	_remember_first(hunter_option)


func _add_text_field(column: VBoxContainer, entry: Dictionary) -> void:
	column.add_child(_caption(String(entry["label"])))
	var field := LineEdit.new()
	field.placeholder_text = String(entry.get("placeholder", ""))
	field.add_theme_font_size_override("font_size", 8)
	field.custom_minimum_size = Vector2(0, 17)
	Palette.style_line_edit(field)
	var on_submit: Callable = entry["on_submit"]
	field.text_submitted.connect(func(value: String) -> void:
		on_submit.call(value)
		_mark_debug(entry)
		_refresh())
	column.add_child(field)


## Using a tool makes the run a DEBUG RUN: nothing from it is recorded (see GameState.debug_run).
## Roster edits and read-only entries opt out with "no_debug".
func _mark_debug(entry: Dictionary) -> void:
	if bool(entry.get("no_debug", false)):
		return
	GameState.debug_run = true
	_refresh_badge()


func _entry_allowed(entry: Dictionary) -> bool:
	if bool(entry.get("owner_only", false)):
		return Build.admin_owner_tools_enabled()
	var permission := String(entry.get("permission", ""))
	# Old/unclassified actions fail closed for delegated accounts. Owners retain
	# them, which prevents a newly added button from silently escaping the
	# permission model before its author assigns a scope.
	return Build.admin_permission(permission) if not permission.is_empty() \
		else Build.admin_owner_tools_enabled()


func _set_open(shown: bool) -> void:
	_open = shown
	_panel.visible = shown
	_dimmer.visible = shown
	# The overlay is clickable, so it needs the cursor -- and it must not take
	# it from a mode that is running normally when it is closed.
	MouseLock.claim("admin", shown)
	if shown:
		_fit_panel()
		_refresh()
		if _first_action_button != null:
			_first_action_button.grab_focus.call_deferred()
	else:
		get_viewport().gui_release_focus()
	open_changed.emit(shown)


func _refresh() -> void:
	if _status.is_valid():
		_readout.text = String(_status.call())
	for entry in _state_buttons:
		Palette.set_state_toggle(entry["button"], bool(entry["state"].call()))


func _process(_delta: float) -> void:
	_refresh_badge()
	if _open:
		_refresh()


func _input(event: InputEvent) -> void:
	var is_toggle := false
	if event is InputEventKey:
		var key := event as InputEventKey
		is_toggle = key.pressed and not key.echo and (key.physical_keycode == TOGGLE_KEY \
			or key.keycode == TOGGLE_KEY \
			or key.physical_keycode == KEY_KP_0 or key.keycode == KEY_KP_0)
	elif event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		# Right-stick click is debug-only because this menu does not exist for an
		# ordinary release player.
		is_toggle = button.pressed and button.button_index == JOY_BUTTON_RIGHT_STICK
	if _open and event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		_set_open(false)
		get_viewport().set_input_as_handled()
		return
	if is_toggle:
		_set_open(not _open)
		get_viewport().set_input_as_handled()
