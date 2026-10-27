class_name RoomChat
extends CanvasLayer

## Lightweight room chat shared by the finite and Infinite scenes. Transport
## derives the sender name from RoomState; clients never get to claim another
## player's identity in the message packet.

signal open_changed(shown: bool)

const MAX_VISIBLE_MESSAGES := 7
## The panel only exists while chat is open or a message is fresh: it grows with the messages (never taller than
## MAX_HEIGHT_FRACTION of the window) and fades out FADE_AFTER seconds after the last one unless the input is open.
const MAX_WIDTH := 220.0
const MAX_HEIGHT_FRACTION := .25
const FADE_AFTER := 6.0
const FADE_SECONDS := 1.5
const SAFE_MARGIN := 8.0
## Bottom of the panel, measured from the window bottom: clear of the hotbar, stamina bar and interaction prompt.
const BOTTOM_CLEARANCE := 104.0

var remotes: RemotePlayers
var _panel: PanelContainer
var _log: RichTextLabel
var _input: LineEdit
var _messages: Array[String] = []
var _open := false
var _fresh_left := 0.0
var _view_size := Vector2.ZERO


static func attach(parent: Node, transport: RemotePlayers) -> RoomChat:
	var chat := RoomChat.new()
	chat.name = "RoomChat"
	chat.remotes = transport
	parent.add_child(chat)
	return chat


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	_build_ui()
	if remotes != null:
		remotes.chat_received.connect(_on_chat_received)


func _process(delta: float) -> void:
	_fresh_left = maxf(0.0, _fresh_left - delta)
	_refresh_panel()


## Screen rect the panel occupies (zero-size while collapsed).
func panel_rect() -> Rect2:
	return Rect2(_panel.position, _panel.size) if _panel.visible else Rect2()


func _refresh_panel() -> void:
	var has_messages := not _messages.is_empty()
	var show_log := has_messages and (_open or _fresh_left > 0.0)
	_log.visible = show_log
	_input.visible = _open
	_panel.visible = _open or show_log
	_panel.modulate.a = 1.0 if _open else clampf(_fresh_left / FADE_SECONDS, 0.0, 1.0)
	if not _panel.visible:
		return
	var view := get_viewport().get_visible_rect().size
	var width := minf(MAX_WIDTH, view.x * .45)
	var inner := width - _panel_margin().x
	_log.custom_minimum_size.x = inner
	var column_min := (_panel.get_child(0) as Control).get_combined_minimum_size()
	var log_h := minf(_log.get_content_height() if show_log else 0.0,
		maxf(0.0, view.y * MAX_HEIGHT_FRACTION - _panel_margin().y - (_input.get_combined_minimum_size().y + 4.0 if _open else 0.0)))
	_log.custom_minimum_size.y = log_h
	var height := maxf(_panel.get_combined_minimum_size().y, column_min.y + _panel_margin().y)
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.offset_left = SAFE_MARGIN
	_panel.offset_right = SAFE_MARGIN + width
	_panel.offset_bottom = view.y - BOTTOM_CLEARANCE
	_panel.offset_top = _panel.offset_bottom - height
	_panel.size = Vector2(width, height)
	_view_size = view


func _panel_margin() -> Vector2:
	var box := _panel.get_theme_stylebox("panel")
	return box.get_minimum_size() if box != null else Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		if event.is_action_pressed("chat"):
			open()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	_open = true
	MouseLock.claim("room_chat", true)
	_input.clear()
	_input.call_deferred("grab_focus")
	open_changed.emit(true)


func close() -> void:
	if not _open:
		return
	_open = false
	_fresh_left = FADE_AFTER
	MouseLock.claim("room_chat", false)
	_input.release_focus()
	open_changed.emit(false)


func is_open() -> bool:
	return _open


func _submit(text: String) -> void:
	var message := text.strip_edges()
	if message.is_empty():
		close()
		return
	if remotes != null:
		remotes.send_chat(message)
	close()


func _on_chat_received(_peer_id: int, display_name: String, message: String) -> void:
	_messages.append("[color=#d7bd65]%s[/color]  %s" % [
		display_name.to_upper(), message])
	while _messages.size() > MAX_VISIBLE_MESSAGES:
		_messages.pop_front()
	_log.text = "\n".join(_messages)
	_fresh_left = FADE_AFTER


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel",
		Palette.panel_box(Color(0.025, 0.035, 0.04, .92), Palette.PANEL_EDGE, 7))
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_panel.add_child(column)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.fit_content = false
	_log.scroll_active = true
	_log.scroll_following = true
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_font_size_override("normal_font_size", 9)
	column.add_child(_log)
	_log.get_v_scroll_bar().modulate.a = 0.0
	_input = LineEdit.new()
	_input.name = "ChatInput"
	_input.placeholder_text = "ROOM MESSAGE // ENTER TO SEND"
	_input.max_length = RemotePlayers.MAX_CHAT_LENGTH
	_input.text_submitted.connect(_submit)
	column.add_child(_input)
	_panel.visible = false
