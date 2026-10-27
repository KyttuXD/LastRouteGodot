class_name CityMenu
extends Control

## Menu of KYTTU: The City (the hub's "city" entry): new solo run, a co-op room, joining a code, and back to the hub.
## Rooms are created in RoomState.Mode.CITY, so the run opens the City scene, "back to menu" returns here, and a room
## code for another game is refused (RoomState.game_matches).

const SIGNAL_BACKDROP_SCRIPT := preload("res://src/ui/signal_backdrop.gd")
const THEME_PATH := "res://src/ui/theme_city.tres"
const HUB_SCENE := "res://scenes/game_hub.tscn"
const LOBBY_SCENE := "res://scenes/room_lobby.tscn"

var _status: Label
var _host_button: Button
var _join_button: Button
var _join_input: LineEdit
var _hosting := false


func _ready() -> void:
	MouseLock.release_all()
	theme = load(THEME_PATH) as Theme
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := SIGNAL_BACKDROP_SCRIPT.new()
	backdrop.name = "SignalBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var column := VBoxContainer.new()
	column.name = "CityColumn"
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.custom_minimum_size = Vector2(170, 0)
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	var kicker := Label.new()
	kicker.name = "CityKicker"
	kicker.theme_type_variation = &"KickerLabel"
	kicker.text = Palette.track("DOME SEALED // NIGHT CITY")
	column.add_child(kicker)
	var title := Label.new()
	title.name = "CityTitle"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_override("font", Palette.title_font())
	title.text = "KYTTU: THE CITY"
	column.add_child(title)
	var new_run := _button("NewRunButton", "NEW RUN // SOLO", true, _on_new_run)
	column.add_child(new_run)
	_host_button = _button("HostButton", "HOST A ROOM", false, _on_host)
	column.add_child(_host_button)
	_join_input = LineEdit.new()
	_join_input.name = "RoomCodeInput"
	_join_input.placeholder_text = "ROOM CODE"
	_join_input.max_length = RoomState.CODE_LENGTH
	_join_input.text_changed.connect(func(value: String) -> void:
		var upper := value.strip_edges().to_upper()
		if upper != value:
			_join_input.text = upper
			_join_input.caret_column = upper.length())
	_join_input.text_submitted.connect(func(_text: String) -> void: _on_join())
	column.add_child(_join_input)
	_join_button = _button("JoinButton", "JOIN A ROOM", false, _on_join)
	column.add_child(_join_button)
	column.add_child(_button("BackToGamesButton", "BACK TO GAMES", false, _on_back))
	_status = Label.new()
	_status.name = "CityStatus"
	_status.theme_type_variation = &"MutedLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(170, 10)
	_status.text = RoomState.status_message if RoomState.mode == RoomState.Mode.CITY else ""
	column.add_child(_status)
	Backend.health_checked.connect(_on_health_checked)
	Backend.room_resolved.connect(_on_room_resolved)
	new_run.grab_focus.call_deferred()


func _exit_tree() -> void:
	if Backend.health_checked.is_connected(_on_health_checked):
		Backend.health_checked.disconnect(_on_health_checked)
	if Backend.room_resolved.is_connected(_on_room_resolved):
		Backend.room_resolved.disconnect(_on_room_resolved)


func _button(button_name: String, label: String, primary: bool, handler: Callable) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = label
	button.focus_mode = Control.FOCUS_ALL
	if primary:
		button.theme_type_variation = &"PrimaryButton"
	button.pressed.connect(handler)
	return button


func _on_new_run() -> void:
	# Solo is a room of one with no network traffic, like the Last Route "offline solo" path.
	Backend.enable_offline_mode()
	UpdateManager.enable_offline_mode()
	RoomState.create_local(RoomState.Mode.CITY)
	RoomState.status_message = "CITY SOLO RUN"
	RoomState.enter(get_tree())


func _on_host() -> void:
	if _hosting:
		return
	if OS.has_feature("web"):
		RoomState.create_local(RoomState.Mode.CITY)
		RoomState.status_message = "WEB BUILD SOLO // CO-OP NEEDS THE NATIVE BUILD"
		get_tree().change_scene_to_file(LOBBY_SCENE)
		return
	_hosting = true
	_host_button.disabled = true
	_host_button.text = "CONTACTING PRIMARY SERVER"
	Backend.check_health()


func _on_health_checked(ok: bool, _message: String) -> void:
	if not _hosting:
		return
	_hosting = false
	RoomState.create_local(RoomState.Mode.CITY)
	if ok:
		RoomState.host_primary_room()
	else:
		RoomState.status_message = "PRIMARY SERVER UNAVAILABLE // SOLO ROOM"
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_join() -> void:
	var code := _join_input.text.strip_edges().to_upper()
	if not RoomState.valid_room_code(code):
		_status.text = "ENTER A VALID FIVE-CHARACTER ROOM CODE"
		return
	_status.text = "LOOKING UP ROOM %s..." % code
	Backend.resolve_room(code)


func _on_room_resolved(code: String, endpoint: Dictionary, error: String) -> void:
	if not error.is_empty():
		_status.text = error
		return
	if not RoomState.game_matches(String(endpoint.get("game", "")), RoomState.GAME_CITY):
		_status.text = "THAT ROOM IS FOR ANOTHER GAME // JOIN IT FROM ITS OWN MENU"
		return
	var join_error := RoomState.join_room(String(endpoint.get("address", "")),
		int(endpoint.get("port", RoomState.DEFAULT_PORT)),
		String(endpoint.get("transport", "relay")), code)
	if not join_error.is_empty():
		_status.text = join_error
		return
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_back() -> void:
	get_tree().change_scene_to_file(HUB_SCENE)
