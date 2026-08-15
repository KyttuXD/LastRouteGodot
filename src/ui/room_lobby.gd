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
## wearing a room's clothes, it IS the room, so nothing here has to change when
## a transport arrives.

const ROW_HEIGHT := 13
## Clear space left between the staging panel and the edge of the screen.
const MARGIN_Y := 10

var _notice := ""


func _ready() -> void:
	MouseLock.release_all()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	RoomState.changed.connect(_rebuild)
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
	header.add_child(_label("%d / %d SIGNALS" % [RoomState.players.size(),
		RoomState.seats()], Palette.MUTED, 7))

	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 6)
	column.add_child(title)
	title.add_child(_label("ROOM", Palette.INK, 22))
	title.add_child(_label(RoomState.code, Palette.CRIMSON, 22))

	column.add_child(_seed_block())
	column.add_child(_config_block())
	column.add_child(_label(Palette.track("CONNECTED PLAYERS"), Palette.AMBER, 7))
	for name in RoomState.roster():
		column.add_child(_player_row(String(name)))
	if not _notice.is_empty():
		column.add_child(_label(_notice, Palette.ALERT, 7))
	column.add_child(_label(
		"ROOM %s // ONLINE // %d CONNECTED"
			% [RoomState.code, RoomState.roster().size()] if RoomState.online
		else "ROOM %s // LOCAL SESSION" % RoomState.code,
		Palette.MUTED, 7))
	column.add_child(_actions())


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
		"Players enter from separate marked access points. The route is shared.",
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
		func(value: int) -> bool: return RoomState.mode_available(value)))

	# Office Mode is one person at a desk; scale and difficulty are the maze's
	# dials and would be lying about doing something here.
	if RoomState.mode != RoomState.Mode.OFFICE:
		stack.add_child(_label("MAP SCALE", Palette.MUTED, 6))
		stack.add_child(_toggles(RoomState.SCALE_LABELS, RoomState.map_scale,
			func(value: int) -> void: RoomState.set_map_scale(value),
			func(_value: int) -> bool: return true))
		stack.add_child(_label("DIFFICULTY", Palette.MUTED, 6))
		stack.add_child(_toggles(RoomState.DIFFICULTY_LABELS, RoomState.difficulty,
			func(value: int) -> void: RoomState.set_difficulty(value),
			func(_value: int) -> bool: return true))

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


func _player_row(name: String) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", Palette.panel_box(Palette.INSET,
		Palette.PANEL_EDGE, 4))
	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(_label("%s // YOU" % name, Palette.BODY, 7))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_label("HOST // STAGING", Palette.MUTED, 6))
	return box


func _actions() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)

	var enter := Button.new()
	enter.text = RoomState.start_label()
	enter.add_theme_font_size_override("font_size", 10)
	enter.custom_minimum_size = Vector2(0, 18)
	Palette.style_button(enter, true)
	enter.pressed.connect(func() -> void: RoomState.enter(get_tree()))
	row.add_child(enter)

	var reroll := Button.new()
	reroll.text = "REROLL ROUTE"
	reroll.add_theme_font_size_override("font_size", 7)
	reroll.custom_minimum_size = Vector2(0, 18)
	Palette.style_button(reroll, false)
	reroll.pressed.connect(func() -> void: RoomState.reroll_seed())
	row.add_child(reroll)

	# Opening the room to the network, or reaching someone else's. Loopback by
	# default: this is here so two windows on one machine can meet before there
	# is any server to meet on.
	if not RoomState.online:
		var host := Button.new()
		host.text = "HOST ON %d" % RoomState.DEFAULT_PORT
		host.add_theme_font_size_override("font_size", 7)
		host.custom_minimum_size = Vector2(0, 18)
		Palette.style_button(host, false)
		host.pressed.connect(func() -> void: _network(RoomState.host_room()))
		row.add_child(host)

		var join := Button.new()
		join.text = "JOIN LOCAL"
		join.add_theme_font_size_override("font_size", 7)
		join.custom_minimum_size = Vector2(0, 18)
		Palette.style_button(join, false)
		join.pressed.connect(func() -> void: _network(RoomState.join_room()))
		row.add_child(join)
	else:
		var close := Button.new()
		close.text = "GO OFFLINE"
		close.add_theme_font_size_override("font_size", 7)
		close.custom_minimum_size = Vector2(0, 18)
		Palette.style_button(close, false)
		close.pressed.connect(func() -> void: RoomState.leave_network())
		row.add_child(close)

	var leave := Button.new()
	leave.text = "LEAVE ROOM"
	leave.add_theme_font_size_override("font_size", 7)
	leave.custom_minimum_size = Vector2(0, 18)
	Palette.style_button(leave, false)
	leave.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	row.add_child(leave)
	return row


## Show why a host or join failed rather than silently doing nothing -- a port
## already in use is the single most likely outcome of testing this with two
## windows, and it looks identical to a dead button.
func _network(error: String) -> void:
	if error.is_empty():
		return
	_notice = error
	_rebuild()


func _label(text: String, tint: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", tint)
	label.add_theme_font_size_override("font_size", size)
	return label
