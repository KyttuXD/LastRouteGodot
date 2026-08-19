class_name RoomChat
extends CanvasLayer

## Lightweight room chat shared by the finite and Infinite scenes. Transport
## derives the sender name from RoomState; clients never get to claim another
## player's identity in the message packet.

signal open_changed(shown: bool)

const MAX_VISIBLE_MESSAGES := 7

var remotes: RemotePlayers
var _panel: PanelContainer
var _log: RichTextLabel
var _input: LineEdit
var _messages: Array[String] = []


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


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		if event.is_action_pressed("chat"):
			open()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	MouseLock.claim("room_chat", true)
	_input.clear()
	_input.call_deferred("grab_focus")
	open_changed.emit(true)


func close() -> void:
	if not visible:
		return
	visible = false
	MouseLock.claim("room_chat", false)
	_input.release_focus()
	open_changed.emit(false)


func is_open() -> bool:
	return visible


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


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.offset_left = 8
	_panel.offset_top = -122
	_panel.offset_right = 312
	_panel.offset_bottom = -8
	_panel.add_theme_stylebox_override("panel",
		Palette.panel_box(Color(0.025, 0.035, 0.04, .92), Palette.PANEL_EDGE, 7))
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_panel.add_child(column)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.fit_content = false
	_log.scroll_active = false
	_log.custom_minimum_size = Vector2(292, 78)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_font_size_override("normal_font_size", 9)
	column.add_child(_log)
	_input = LineEdit.new()
	_input.name = "ChatInput"
	_input.placeholder_text = "ROOM MESSAGE // ENTER TO SEND"
	_input.max_length = RemotePlayers.MAX_CHAT_LENGTH
	_input.text_submitted.connect(_submit)
	column.add_child(_input)
	visible = false
