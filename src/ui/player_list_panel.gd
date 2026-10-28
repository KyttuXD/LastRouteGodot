class_name PlayerListPanel
extends PanelContainer

## The active-room player list as a panel: header, then one row per RoomPlayerList row (host badge, name, ping, status, floor, voice
## icon) and, only when `admin_enabled`, a PULSE button on other players' rows. The rows scroll at small window sizes. set_rows() is
## cheap to call every tick: the rows are rebuilt only when something shown changed. Plain Labels and Buttons, so the XR panel works.

signal pulse_requested(peer_id: int)

const NAME_W := 92
const COLUMNS := [["PING", 38], ["STATUS", 70], ["FLOOR", 32]]

var admin_enabled := false
var rows_box: VBoxContainer
var _scroll: ScrollContainer
var _signature := ""
var _last_rows: Array = []


func _init() -> void:
	name = "PlayerListPanel"
	add_theme_stylebox_override("panel", Palette.panel_box(Palette.PANEL, Palette.PANEL_EDGE, 6))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	add_child(column)
	var title := Label.new()
	title.name = "PlayerListTitle"
	title.text = "PLAYERS IN THIS ROOM"
	title.add_theme_font_size_override("font_size", 7)
	title.add_theme_color_override("font_color", Palette.AMBER)
	column.add_child(title)
	column.add_child(_header())
	_scroll = ScrollContainer.new()
	_scroll.name = "PlayerListScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 40)
	column.add_child(_scroll)
	rows_box = VBoxContainer.new()
	rows_box.name = "PlayerListRows"
	rows_box.add_theme_constant_override("separation", 2)
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(rows_box)


func _header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "PlayerListHeader"
	row.add_theme_constant_override("separation", 4)
	row.add_child(_cell("", 34, Palette.MUTED, 6))
	row.add_child(_cell("NAME", NAME_W, Palette.MUTED, 6))
	for column in COLUMNS:
		row.add_child(_cell(column[0], column[1], Palette.MUTED, 6))
	row.add_child(_cell("VOICE", 26, Palette.MUTED, 6))
	return row


func _cell(text: String, width: int, tint: Color, size: int = 7) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", tint)
	return label


func row_count() -> int:
	return _last_rows.size()


func set_rows(rows: Array) -> void:
	var signature := "%s|%s" % [admin_enabled, JSON.stringify(rows)]
	if signature == _signature:
		return
	_signature = signature
	_last_rows = rows.duplicate(true)
	for child in rows_box.get_children():
		child.free()
	for row in rows:
		rows_box.add_child(_build_row(row))


func _build_row(row: Dictionary) -> Control:
	var line := HBoxContainer.new()
	line.name = "Player_%d" % int(row["id"])
	line.add_theme_constant_override("separation", 4)
	var badge := _cell("HOST" if row["host"] else "", 34, Palette.ON_AMBER, 6)
	if row["host"]:
		badge.add_theme_stylebox_override("normal", _tag(Palette.ACCENT))
	badge.name = "HostBadge"
	line.add_child(badge)
	var name_label := _cell(String(row["name"]) + (" (YOU)" if row["you"] else ""), NAME_W,
		Palette.INK if row["you"] else Palette.BODY)
	name_label.name = "PlayerName"
	line.add_child(name_label)
	var ping_label := _cell(RoomPlayerList.ping_text(int(row["ping"])), COLUMNS[0][1], Palette.BODY)
	ping_label.name = "PlayerPing"
	line.add_child(ping_label)
	var status := String(row["status"])
	var status_tint := Palette.STABLE if status == RoomPlayerList.STATUS_ALIVE \
		else (Palette.ALERT if status in [RoomPlayerList.STATUS_CAUGHT, RoomPlayerList.STATUS_DISCONNECTED] else Palette.AMBER)
	var status_label := _cell(status, COLUMNS[1][1], status_tint)
	status_label.name = "PlayerStatus"
	line.add_child(status_label)
	var floor_label := _cell(RoomPlayerList.floor_text(row["level"]), COLUMNS[2][1], Palette.BODY)
	floor_label.name = "PlayerFloor"
	line.add_child(floor_label)
	var voice := _cell("))" if row["talking"] else "", 26, Palette.TEAL)
	voice.name = "PlayerVoice"
	line.add_child(voice)
	if admin_enabled and row["can_pulse"]:
		var pulse := Button.new()
		pulse.name = "PulseButton"
		pulse.text = "PULSE"
		pulse.custom_minimum_size = Vector2(36, 12)
		pulse.add_theme_font_size_override("font_size", 6)
		Palette.style_button(pulse, false, true)
		var id := int(row["id"])
		pulse.pressed.connect(func() -> void: pulse_requested.emit(id))
		line.add_child(pulse)
	return line


func _tag(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.content_margin_left = 2
	box.content_margin_right = 2
	return box
