extends Control

## The staging screen: the room you are about to enter a route from.
##
## Built from Palette in code rather than as a scene, for the same reason the
## pause overlay is -- colours written into a .tscn are invisible to a palette
## change. Layout follows the web build's own staging screen: amber system
## line, the room code, the route seed in an inset block with a crimson rule,
## then the host's configuration and the seats.
##
## Offline this shows exactly what it shows online, minus the modes that need
## other people. That is deliberate: the screen is not a singleplayer menu
## wearing a room's clothes, it IS the room; ENet only changes who occupies it.

const ROW_HEIGHT := 13
## Clear space left between the staging panel and the edge of the screen.
const MARGIN_Y := 10

var _notice := ""
var _join_code := ""


func _ready() -> void:
	MouseLock.release_all()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	RoomState.changed.connect(_rebuild)
	Backend.room_resolved.connect(_on_room_resolved)
	if not RoomState.status_message.is_empty():
		_notice = RoomState.status_message
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	var background := ColorRect.new()
	background.color = Palette.BACKDROP
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var panel := PanelContainer.new()
	panel.name = "StagingPanel"
	panel.add_theme_stylebox_override("panel", Palette.panel_box(Palette.PANEL,
		Palette.PANEL_EDGE, 12))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = -190
	panel.offset_right = 190
	# Bounded to the viewport with a real margin rather than sized by its
	# content. Staging grows -- more players, more config -- and a panel that
	# sizes itself pushes ENTER ROUTE off the bottom of the screen, which is
	# the one button that has to be reachable.
	panel.offset_top = MARGIN_Y
	panel.offset_bottom = -MARGIN_Y
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	# ...and scrolls if it still does not fit, so nothing is ever simply
	# unreachable on a short window.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	header.add_child(_label(Palette.track("CO-OP STAGING SIGNAL"), Palette.AMBER, 7))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(_label("%d / %d SIGNALS" % [RoomState.roster().size(),
		RoomState.seats()], Palette.MUTED, 7))

	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 6)
	column.add_child(title)
	title.add_child(_label("ROOM", Palette.INK, 22))
	title.add_child(_label(RoomState.code, Palette.CRIMSON, 22))

	column.add_child(_seed_block())
	column.add_child(_config_block())
	column.add_child(_label(Palette.track("CONNECTED PLAYERS"), Palette.AMBER, 7))
	for row in RoomState.roster_rows():
		column.add_child(_player_row(row))
	var notice := _notice if not _notice.is_empty() else RoomState.status_message
	if not notice.is_empty():
		column.add_child(_label(notice, Palette.ALERT, 7))
	column.add_child(_label(_connection_summary(), Palette.MUTED, 7))
	column.add_child(_actions())


func _connection_summary() -> String:
	if RoomState.connecting:
		return "JOINING THROUGH PRIMARY SERVER..."
	if RoomState.online and RoomState.is_host and not Backend.registered:
		return "REGISTERING ROOM %s WITH PRIMARY SERVER..." % RoomState.code
	if RoomState.online:
		return "ROOM %s // PRIMARY SERVER // %d CONNECTED" % [RoomState.code,
			RoomState.roster().size()]
	return "SOLO ROOM %s // NOT LISTED ONLINE" % RoomState.code


func _seed_block() -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel",
		Palette.panel_box(Palette.INSET, Palette.CRIMSON_DEEP, 6))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 1)
	box.add_child(stack)
	stack.add_child(_label(Palette.track("ROUTE SEED"), Palette.AMBER, 6))
	stack.add_child(_label(RoomState.seed_text, Palette.INK, 9))
	stack.add_child(_label(
		"Players enter from separate nearby access points. The route is shared.",
		Palette.MUTED, 6))
	return box


func _config_block() -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", Palette.panel_box(Palette.INSET,
		Palette.PANEL_EDGE, 6))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 3)
	box.add_child(stack)

	var head := HBoxContainer.new()
	stack.add_child(head)
	head.add_child(_label(Palette.track("ROUTE CONFIGURATION"), Palette.AMBER, 7))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(_label("HOST CONTROLS" if RoomState.is_host else "HOST DECIDES",
		Palette.MUTED, 6))

	stack.add_child(_label("MODE", Palette.MUTED, 6))
	stack.add_child(_toggles(RoomState.MODE_LABELS, RoomState.mode,
			func(value: int) -> void: RoomState.set_mode(value),
			func(value: int) -> bool:
				return RoomState.is_host and RoomState.mode_available(value)))

	# Office Mode is one person at a desk; scale and difficulty are the maze's
	# dials and would be lying about doing something here.
	if RoomState.mode != RoomState.Mode.OFFICE:
		stack.add_child(_label("MAP SCALE", Palette.MUTED, 6))
		stack.add_child(_toggles(RoomState.SCALE_LABELS, RoomState.map_scale,
			func(value: int) -> void: RoomState.set_map_scale(value),
			func(_value: int) -> bool: return RoomState.is_host))
		stack.add_child(_label("DIFFICULTY", Palette.MUTED, 6))
		stack.add_child(_toggles(RoomState.DIFFICULTY_LABELS, RoomState.difficulty,
			func(value: int) -> void: RoomState.set_difficulty(value),
			func(_value: int) -> bool: return RoomState.is_host))

	var note := RoomState.mode_unavailable_reason(RoomState.Mode.HIDE_SEEK)
	stack.add_child(_label(note if not note.is_empty()
		else "The host configures the shared route.", Palette.MUTED, 6))
	return box


## A row of mutually exclusive buttons, amber-filled when selected -- the web
## build's quick button groups.
func _toggles(labels: Dictionary, selected: int, on_pick: Callable,
		is_allowed: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	for value in labels:
		var button := Button.new()
		button.text = String(labels[value])
		button.add_theme_font_size_override("font_size", 7)
		button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		button.focus_mode = Control.FOCUS_ALL
		var allowed: bool = is_allowed.call(value)
		Palette.style_button(button, false)
		if value == selected:
			button.add_theme_stylebox_override("normal",
				Palette.button_box(Palette.AMBER_FILL, Palette.AMBER))
			button.add_theme_color_override("font_color", Palette.ON_AMBER)
		button.disabled = not allowed
		if allowed:
			button.pressed.connect(func() -> void: on_pick.call(value))
		row.add_child(button)
	return row


## One seat. Every part of this used to be hardcoded, so a guest's window
## showed itself as the host.
func _player_row(entry: Dictionary) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", Palette.panel_box(Palette.INSET,
		Palette.PANEL_EDGE, 4))
	var row := HBoxContainer.new()
	box.add_child(row)
	var you: bool = entry["you"]
	var label: String = String(entry["name"])
	if you:
		label += "  //  YOU"
	row.add_child(_label(label, Palette.INK if you else Palette.BODY, 7))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var role: String = "HOST" if entry["host"] else "GUEST"
	row.add_child(_label("%s // STAGING" % role,
		Palette.AMBER if entry["host"] else Palette.MUTED, 6))
	return box


func _actions() -> Control:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	stack.add_child(row)

	var enter := Button.new()
	enter.name = "EnterRouteButton"
	enter.text = "CONNECTING..." if RoomState.connecting else (
		"WAITING FOR HOST" if RoomState.online and not RoomState.is_host
		else "WAITING FOR PRIMARY SERVER" if RoomState.online and not Backend.registered
		else RoomState.start_label())
	enter.add_theme_font_size_override("font_size", 10)
	enter.custom_minimum_size = Vector2(0, 18)
	Palette.style_button(enter, true)
	enter.disabled = RoomState.connecting or (RoomState.online and not RoomState.is_host) \
		or (RoomState.online and RoomState.is_host and not Backend.registered) \
		or not RoomState.mode_available(RoomState.mode)
	if not enter.disabled:
		enter.pressed.connect(func() -> void: RoomState.enter(get_tree()))
	row.add_child(enter)

	var reroll := Button.new()
	reroll.text = "REROLL ROUTE"
	reroll.add_theme_font_size_override("font_size", 7)
	reroll.custom_minimum_size = Vector2(0, 18)
	Palette.style_button(reroll, false)
	reroll.disabled = RoomState.connecting or (RoomState.online and not RoomState.is_host)
	if not reroll.disabled:
		reroll.pressed.connect(func() -> void: RoomState.reroll_seed())
	row.add_child(reroll)

	var leave := Button.new()
	leave.name = "BackToMenuButton"
	leave.text = "BACK TO MAIN MENU"
	leave.add_theme_font_size_override("font_size", 7)
	leave.custom_minimum_size = Vector2(0, 18)
	Palette.style_button(leave, false)
	leave.pressed.connect(func() -> void:
		RoomState.leave_network()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	row.add_child(leave)

	# The official directory is the only connection surface. It resolves room
	# codes into ENet endpoints internally; raw addresses are never shown or
	# accepted by the lobby.
	if not RoomState.online and not RoomState.connecting:
		stack.add_child(_label("PRIMARY CO-OP SERVER // ROOM CODES", Palette.MUTED, 6))
		var directory_row := HBoxContainer.new()
		directory_row.add_theme_constant_override("separation", 5)
		stack.add_child(directory_row)
		var host := Button.new()
		host.name = "CreateOnlineRoomButton"
		host.text = "CREATE ONLINE ROOM"
		host.add_theme_font_size_override("font_size", 7)
		host.custom_minimum_size = Vector2(0, 18)
		Palette.style_button(host, false)
		host.disabled = not Backend.configured() or OS.has_feature("web")
		host.tooltip_text = "Native ENet co-op is unavailable in Web builds." \
			if OS.has_feature("web") else "Create a room and list its code on the primary server."
		if not host.disabled:
			host.pressed.connect(_create_online_room)
		directory_row.add_child(host)

		var room_code := LineEdit.new()
		room_code.name = "PrimaryRoomCodeInput"
		room_code.text = _join_code
		room_code.placeholder_text = "ROOM CODE"
		room_code.max_length = RoomState.CODE_LENGTH
		room_code.custom_minimum_size = Vector2(88, 18)
		room_code.add_theme_font_size_override("font_size", 7)
		directory_row.add_child(room_code)
		var code_join := Button.new()
		code_join.name = "JoinOnlineRoomButton"
		code_join.text = "JOIN ONLINE ROOM"
		code_join.add_theme_font_size_override("font_size", 7)
		code_join.custom_minimum_size = Vector2(0, 18)
		Palette.style_button(code_join, false)
		code_join.disabled = not RoomState.valid_room_code(_join_code) \
			or not Backend.configured() or OS.has_feature("web")
		code_join.tooltip_text = "Enter the five-character room code from the host."
		room_code.text_changed.connect(func(value: String) -> void:
			_join_code = value.strip_edges().to_upper()
			code_join.disabled = not RoomState.valid_room_code(_join_code) \
				or not Backend.configured() or OS.has_feature("web"))
		room_code.text_submitted.connect(func(_value: String) -> void:
			if not code_join.disabled:
				_resolve_online_room())
		code_join.pressed.connect(_resolve_online_room)
		directory_row.add_child(code_join)
		if OS.has_feature("web"):
			stack.add_child(_label("WEB BUILD IS SOLO // ONLINE CO-OP NEEDS WEBRTC",
				Palette.ALERT, 6))

	else:
		var network_row := HBoxContainer.new()
		network_row.add_theme_constant_override("separation", 5)
		stack.add_child(network_row)
		var close := Button.new()
		close.name = "LeaveOnlineRoomButton"
		close.text = "CANCEL JOIN" if RoomState.connecting else (
			"CLOSE ONLINE ROOM" if RoomState.is_host else "LEAVE ONLINE ROOM")
		close.add_theme_font_size_override("font_size", 7)
		close.custom_minimum_size = Vector2(0, 18)
		Palette.style_button(close, false)
		close.pressed.connect(func() -> void:
			_notice = "RETURNED TO SOLO ROOM"
			RoomState.status_message = _notice
			RoomState.leave_network())
		network_row.add_child(close)
	return stack


## Show why creating or joining through the primary service failed rather than
## silently doing nothing.
func _network(error: String) -> void:
	if error.is_empty():
		return
	_notice = error
	_rebuild()


func _create_online_room() -> void:
	_notice = ""
	_network(RoomState.host_room())


func _resolve_online_room() -> void:
	if not RoomState.valid_room_code(_join_code):
		_notice = "ENTER A VALID FIVE-CHARACTER ROOM CODE"
		_rebuild()
		return
	_notice = "LOOKING UP ROOM %s ON PRIMARY SERVER..." % _join_code
	Backend.resolve_room(_join_code)
	_rebuild()


func _on_room_resolved(_code: String, endpoint: Dictionary, error: String) -> void:
	if not error.is_empty():
		_notice = error
		_rebuild()
		return
	var address := String(endpoint.get("address", ""))
	var port := int(endpoint.get("port", RoomState.DEFAULT_PORT))
	_notice = ""
	_network(RoomState.join_room(address, port))
func _label(text: String, tint: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", tint)
	label.add_theme_font_size_override("font_size", size)
	return label
