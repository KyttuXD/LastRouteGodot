class_name RunReport
extends CanvasLayer

## End-of-run archive card. Solo routes end here until the player explicitly
## restarts or leaves. In co-op, a captured guest leaves the room and a
## captured host ends the shared route; there is no invisible rejoin/life pool.

signal restart_requested
signal leave_requested

const SIGNAL_BACKDROP_SCRIPT := preload("res://src/ui/signal_backdrop.gd")

var _open := false
var _surface: Control
var _kicker: Label
var _title: Label
var _reason: Label
var _line: Label
var _stats: GridContainer
var _primary: Button
var _secondary: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120
	_build()
	set_open(false)


func is_open() -> bool:
	return _open


func open(report: Dictionary) -> void:
	var online := bool(report.get("online", false))
	var host := bool(report.get("host", false))
	var respawn := bool(report.get("respawn", false))
	_kicker.text = String(report.get("kicker",
		"RUNNER SIGNAL // INTERRUPTED" if online else "ROUTE SIGNAL // ARCHIVED"))
	_title.text = String(report.get("title",
		"SIGNAL LOST" if online else "ROUTE ENDED"))
	_reason.text = String(report.get("reason", "THE ROUTE CAUGHT UP WITH YOU"))
	var line := String(report.get("line", ""))
	_line.text = "\u201c%s\u201d" % line if not line.is_empty() else ""
	_line.visible = not line.is_empty()
	var caption := String(report.get("line_style", "")) == "caption"
	_line.add_theme_color_override("font_color", Palette.MUTED if caption else Palette.BODY)
	_clear_stats()
	_add_stat("DEPTH REACHED", str(maxi(1, int(report.get("depth", 1)))))
	_add_stat("SCORE", str(maxi(0, int(report.get("score", 0)))))
	_add_stat("FLOOR RELAYS", "%d / %d" % [
		maxi(0, int(report.get("relays", 0))),
		maxi(0, int(report.get("relay_target", 0))),
	])
	_add_stat("COINS", str(maxi(0, int(report.get("coins", 0)))))
	_add_stat("DIFFICULTY", String(report.get("difficulty", "STANDARD")))
	_add_stat("ROUTE SEED", String(report.get("seed", "UNKNOWN")))
	if respawn:
		_primary.text = "RESPAWN AT CHECKPOINT"
		_secondary.text = "LEAVE ROOM" if online else "MAIN MENU"
		_set_button_action(_primary, restart_requested)
		_secondary.visible = true
		_set_button_action(_secondary, leave_requested)
	else:
		_primary.text = ("END ROUTE" if host else "LEAVE ROOM") if online \
			else "RESTART ROUTE"
		_secondary.text = "MAIN MENU"
		_set_button_action(_primary, leave_requested if online else restart_requested)
		_secondary.visible = not online
		if not online:
			_set_button_action(_secondary, leave_requested)
	set_open(true)
	_primary.grab_focus()


func close() -> void:
	set_open(false)


func set_open(value: bool) -> void:
	_open = value
	if _surface != null:
		_surface.visible = value
	MouseLock.claim("run_report", value)


func _set_button_action(button: Button, target: Signal) -> void:
	# The report can reopen in another context during validation/editor runs.
	# Remove the previous one-shot callback instead of stacking both actions.
	for connection in button.pressed.get_connections():
		button.pressed.disconnect(connection["callable"])
	button.pressed.connect(func() -> void: target.emit())


func _clear_stats() -> void:
	for child in _stats.get_children():
		_stats.remove_child(child)
		child.queue_free()


func _add_stat(caption: String, value: String) -> void:
	var key := Label.new()
	key.text = caption
	key.add_theme_color_override("font_color", Palette.MUTED)
	key.add_theme_font_size_override("font_size", 6)
	_stats.add_child(key)
	var readout := Label.new()
	readout.name = "%sValue" % caption.to_pascal_case().replace(" ", "")
	readout.text = value
	readout.add_theme_color_override("font_color", Palette.INK)
	readout.add_theme_font_size_override("font_size", 7)
	readout.custom_minimum_size = Vector2(185, 0)
	readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	readout.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_stats.add_child(readout)


func _build() -> void:
	_surface = Control.new()
	_surface.name = "RunReportSurface"
	_surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_surface)

	var background := SIGNAL_BACKDROP_SCRIPT.new()
	background.name = "SignalBackdrop"
	background.pattern_strength = 0.72
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_surface.add_child(background)

	for frame in [["OuterFrame", 6, Palette.PANEL_EDGE],
			["InnerFrame", 9, Color("46303c")]]:
		var border := Panel.new()
		border.name = frame[0]
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		border.set_anchors_preset(Control.PRESET_FULL_RECT)
		border.offset_left = frame[1]
		border.offset_top = frame[1]
		border.offset_right = -frame[1]
		border.offset_bottom = -frame[1]
		border.add_theme_stylebox_override("panel",
			Palette.panel_box(Color(0, 0, 0, 0), frame[2], 0))
		_surface.add_child(border)

	var panel := PanelContainer.new()
	panel.name = "ReportPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -170
	panel.offset_top = -96
	panel.offset_right = 170
	panel.offset_bottom = 96
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override("panel",
		Palette.panel_box(Palette.PANEL, Color("563041"), 13))
	_surface.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	_kicker = _label("ROUTE SIGNAL // ARCHIVED", Palette.AMBER, 7, "ReportKicker")
	column.add_child(_kicker)
	_title = _label("ROUTE ENDED", Palette.INK, 22, "ReportTitle")
	_title.add_theme_font_override("font", Palette.title_font())
	column.add_child(_title)
	_reason = _label("THE ROUTE CAUGHT UP WITH YOU", Palette.ALERT, 7, "EndReason")
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_reason)
	_line = _label("", Palette.BODY, 7, "EndLine")
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.visible = false
	column.add_child(_line)

	var stat_panel := PanelContainer.new()
	stat_panel.name = "StatsPanel"
	stat_panel.add_theme_stylebox_override("panel",
		Palette.panel_box(Palette.INSET, Palette.PANEL_EDGE, 6))
	column.add_child(stat_panel)
	_stats = GridContainer.new()
	_stats.name = "RunStats"
	_stats.columns = 2
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats.add_theme_constant_override("h_separation", 12)
	_stats.add_theme_constant_override("v_separation", 2)
	stat_panel.add_child(_stats)

	var actions := HBoxContainer.new()
	actions.name = "RunReportActions"
	actions.add_theme_constant_override("separation", 6)
	column.add_child(actions)
	_primary = Button.new()
	_primary.name = "ReportPrimaryButton"
	_primary.custom_minimum_size = Vector2(92, 18)
	_primary.add_theme_font_size_override("font_size", 8)
	Palette.style_button(_primary, true)
	actions.add_child(_primary)
	_secondary = Button.new()
	_secondary.name = "ReportSecondaryButton"
	_secondary.custom_minimum_size = Vector2(76, 18)
	_secondary.add_theme_font_size_override("font_size", 7)
	Palette.style_button(_secondary, false)
	actions.add_child(_secondary)


func _label(text: String, color: Color, size: int, node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	return label
