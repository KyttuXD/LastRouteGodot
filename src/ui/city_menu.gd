class_name CityMenu
extends Control

## Menu of KYTTU: The City (the hub's "city" entry): new solo run, a co-op room, joining a code, and back to the hub.
## Rooms are created in RoomState.Mode.CITY, so the run opens the City scene, "back to menu" returns here, and a room
## code for another game is refused (RoomState.game_matches).

const SIGNAL_BACKDROP_SCRIPT := preload("res://src/ui/signal_backdrop.gd")
const THEME_PATH := "res://src/ui/theme_city.tres"
const HUB_SCENE := "res://scenes/game_hub.tscn"
const LOBBY_SCENE := "res://scenes/room_lobby.tscn"

const SETTINGS_OVERLAY_SCENE := preload("res://scenes/settings_overlay.tscn")

## The time-of-day choice made on this menu, kept across menus and applied to every room created here.
static var daytime_choice := false

var _time_button: Button
var _settings_overlay: SettingsPanel
var _continue_button: Button
var _clear_button: Button
var _save_summary: Label
var _status: Label
var _host_button: Button
var _join_button: Button
var _join_input: LineEdit
var _hosting := false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _settings_overlay != null and _settings_overlay.visible:
		_settings_overlay.close()
		get_viewport().set_input_as_handled()


func _ready() -> void:
	MouseLock.release_all()
	GameRegistry.active_game_id = RoomState.GAME_CITY
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
	_save_summary = Label.new()
	_save_summary.name = "SavedRunSummary"
	_save_summary.theme_type_variation = &"MutedLabel"
	_save_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_save_summary.custom_minimum_size = Vector2(170, 10)
	column.add_child(_save_summary)
	_continue_button = _button("ContinueRunButton", "CONTINUE RUN", true, _on_continue_run)
	column.add_child(_continue_button)
	_clear_button = _button("ClearRunButton", "CLEAR SAVE", false, _on_clear_run)
	column.add_child(_clear_button)
	_time_button = _button("TimeButton", _time_label(), false, _on_time_toggle)
	_time_button.tooltip_text = "Daytime: bright open sky, lamps off, hunters see farther outdoors (the host decides for the room)"
	column.add_child(_time_button)
	var new_run := _button("NewRunButton", "NEW RUN // SOLO", not Backend.game_has_save(RoomState.GAME_CITY), _on_new_run)
	column.add_child(new_run)
	var public_button := _button("PublicButton", "PUBLIC CITY", false, func() -> void: pass)
	public_button.disabled = Backend.offline_mode or not Backend.configured()
	public_button.tooltip_text = "Join the always-open shared City (needs the primary server)"
	public_button.pressed.connect(func() -> void:
		public_button.disabled = true
		PublicRoute.join(RoomState.Mode.CITY))
	PublicRoute.status_changed.connect(func(message: String) -> void:
		if is_instance_valid(public_button) and not message.is_empty():
			public_button.text = message.substr(0, 38)
			public_button.disabled = not message.begins_with("PUBLIC ROUTE UNAVAILABLE") \
				and not message.begins_with("PUBLIC ROUTE NEEDS"))
	column.add_child(public_button)
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
	column.add_child(_button("AccountButton", Backend.account_username if Backend.signed_in() else "ACCOUNT", false, _on_account))
	column.add_child(_button("SettingsButton", "SETTINGS", false, _on_settings))
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
	Backend.account_changed.connect(_on_account_changed)
	Backend.account_progress_changed.connect(_on_account_progress_changed)
	_settings_overlay = SETTINGS_OVERLAY_SCENE.instantiate() as SettingsPanel
	_settings_overlay.visible = false
	add_child(_settings_overlay)
	_refresh_saved_run()
	(func() -> void:
		if is_instance_valid(new_run) and new_run.is_inside_tree():
			new_run.grab_focus()).call_deferred()


func _exit_tree() -> void:
	if Backend.account_changed.is_connected(_on_account_changed):
		Backend.account_changed.disconnect(_on_account_changed)
	if Backend.account_progress_changed.is_connected(_on_account_progress_changed):
		Backend.account_progress_changed.disconnect(_on_account_progress_changed)
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


func _time_label() -> String:
	return "TIME: DAYTIME" if daytime_choice else "TIME: NIGHT"


func _on_time_toggle() -> void:
	daytime_choice = not daytime_choice
	_time_button.text = _time_label()


func _on_account() -> void:
	AccountPanel.open(self)


func _on_settings() -> void:
	_settings_overlay.open()


func _on_account_changed(_signed_in_now: bool, _username: String, _admin: bool, _message: String) -> void:
	var account_button := find_child("AccountButton", true, false) as Button
	if account_button != null:
		account_button.text = Backend.account_username if Backend.signed_in() else "ACCOUNT"
	_refresh_saved_run()


func _on_account_progress_changed(_available: bool, _progress: Dictionary, _saved_at: int, _message: String) -> void:
	_refresh_saved_run()


## CONTINUE RUN / CLEAR SAVE appear when the signed-in account holds a City run (games.city, see CityRunSave).
func _refresh_saved_run() -> void:
	var has_save := Backend.signed_in() and Backend.game_has_save(RoomState.GAME_CITY)
	_continue_button.visible = has_save
	_clear_button.visible = has_save
	_save_summary.visible = has_save
	if has_save:
		_save_summary.text = "SAVED RUN // %s" % String(Backend.game_progress(RoomState.GAME_CITY).get("summary", "")).to_upper()
	(find_child("NewRunButton", true, false) as Button).theme_type_variation = &"" if has_save else &"PrimaryButton"
	_clear_button.text = "CLEAR SAVE"


func _on_continue_run() -> void:
	var error := RoomState.prepare_city_run(Backend.game_progress(RoomState.GAME_CITY))
	if not error.is_empty():
		_status.text = error
		return
	RoomState.enter(get_tree())


func _on_clear_run() -> void:
	if _clear_button.text == "CLEAR SAVE":
		_clear_button.text = "SURE? CLEAR SAVE"
		return
	_clear_button.text = "CLEAR SAVE"
	Backend.account_clear_game_progress(RoomState.GAME_CITY)


func _on_new_run() -> void:
	# Solo is a room of one with no network traffic, like the Last Route "offline solo" path. A signed-in runner stays online
	# so the run can save to the account.
	if not Backend.signed_in():
		Backend.enable_offline_mode()
		UpdateManager.enable_offline_mode()
	RoomState.create_local(RoomState.Mode.CITY)
	RoomState.daytime = daytime_choice
	RoomState.status_message = "CITY SOLO RUN"
	RoomState.enter(get_tree())


func _on_host() -> void:
	if _hosting:
		return
	if OS.has_feature("web"):
		RoomState.create_local(RoomState.Mode.CITY)
		RoomState.daytime = daytime_choice
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
	RoomState.daytime = daytime_choice
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
