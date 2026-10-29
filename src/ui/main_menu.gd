extends Control

## Startup screen.
##
## CREATE ROOM checks the primary service, opens and lists an ENet room when it
## is reachable, and falls back to the same room as solo when it is not. JOIN
## ROOM resolves a five-character code through the primary server. Both fill
## the same RoomState contract, because singleplayer is a one-player room
## rather than a second gameplay path. Account, Settings and patch dialogs stay
## on this scene.

@onready var play_button: Button = %PlayButton
@onready var join_button: Button = %JoinButton
@onready var offline_button: Button = %OfflineButton
@onready var settings_button: Button = %SettingsButton
@onready var account_button: Button = %AccountButton
@onready var tutorial_button: Button = %TutorialButton
@onready var quit_button: Button = %QuitButton
@onready var update_button: Button = %UpdateButton
@onready var version_label: Label = %VersionLabel
@onready var settings_overlay: SettingsPanel = %SettingsOverlay

var _modal: Control
var _join_input: LineEdit
var _creating_room := false
var _routes_update_locked := false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _modal != null:
		_close_modal()
		get_viewport().set_input_as_handled()
	elif settings_overlay.visible:
		settings_overlay.close()
		get_viewport().set_input_as_handled()


func _ready() -> void:
	# The menu is where every mode lands on the way out, so it is the one place
	# that can be sure the cursor should be free.
	MouseLock.release_all()
	_apply_palette()
	_build_hint()
	TestServerBadge.attach(self)
	_build_public_button()
	_build_continue_button()
	if not RunSaves.changed.is_connected(_build_continue_button):
		RunSaves.changed.connect(_build_continue_button)
	RunSaves.cloud_sync()
	play_button.pressed.connect(_on_play_pressed)
	join_button.pressed.connect(_on_join_pressed)
	offline_button.pressed.connect(_on_offline_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	account_button.pressed.connect(_on_account_pressed)
	tutorial_button.pressed.connect(_on_tutorial_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	update_button.pressed.connect(_on_update_pressed)
	UpdateManager.update_available.connect(_on_update_available)
	UpdateManager.status_changed.connect(_on_update_status)
	UpdateManager.check_finished.connect(_on_update_check_finished)
	Backend.room_resolved.connect(_on_room_resolved)
	Backend.health_checked.connect(_on_create_health_checked)
	Backend.account_changed.connect(_on_account_changed)
	Backend.account_progress_changed.connect(_on_account_progress_changed)
	_refresh_account_button()
	# version_label.text = "VERSION %s // %s // %s" % [Build.VERSION, Build.update_channel().to_upper(), Build.short_revision().to_upper()]
	if version_label != null and Build.revision() != Build.SOURCE_REVISION:
		# every exported build updates by commit: show which one this is
		version_label.text = "VERSION %s // BUILD %s" % [Build.VERSION, Build.short_revision().to_upper()]
	if not UpdateManager.available.is_empty():
		_on_update_available(UpdateManager.available)
	if Build.requires_update_gate():
		_set_route_update_locked("UPDATING")
		update_button.visible = true
		update_button.disabled = true
		update_button.text = "CHECKING FOR UPDATES"
		if UpdateManager.check_complete:
			_on_update_check_finished(UpdateManager.check_succeeded,
				not UpdateManager.available.is_empty())
		elif not UpdateManager.checking:
			UpdateManager.check()
	if not UpdateManager.status_message.is_empty():
		_on_update_status(UpdateManager.status_message)
	if _open_update_progress_if_needed():
		return
	_focus_default_button.call_deferred()
	# Coming from the hub's shared Account / Settings entries.
	match GameHub.pending_menu_action:
		"account":
			_on_account_pressed.call_deferred()
		"settings":
			_on_settings_pressed.call_deferred()
	GameHub.pending_menu_action = ""


## Mutes the version label (the keyboard hint under the menu was removed).
func _build_hint() -> void:
	if version_label != null:
		version_label.add_theme_color_override("font_color", Palette.MUTED)
		version_label.add_theme_font_size_override("font_size", 6)


## PUBLIC ROUTE: the always-open shared route. No lobby, no host choice; the
## backend owns the room (see PublicRoute).
func _build_public_button() -> void:
	var box := get_node_or_null("ButtonPanel/ButtonBox") as VBoxContainer
	if box == null or box.has_node("PublicButton"):
		return
	var button := Button.new()
	button.name = "PublicButton"
	button.text = "PUBLIC ROUTE"
	button.focus_mode = Control.FOCUS_ALL
	Palette.style_button(button, true, true)
	button.disabled = Backend.offline_mode or not Backend.configured()
	button.tooltip_text = "Join the always-open shared route (needs the primary server)"
	button.pressed.connect(func() -> void:
		button.disabled = true
		PublicRoute.join())
	PublicRoute.status_changed.connect(func(message: String) -> void:
		if is_instance_valid(button) and not message.is_empty():
			button.text = ServerPrivacy.scrub(message).substr(0, 38)
			button.disabled = not message.begins_with("PUBLIC ROUTE UNAVAILABLE") \
				and not message.begins_with("PUBLIC ROUTE NEEDS"))
	box.add_child(button)
	box.move_child(button, 0)


## CONTINUE resumes the run's automatic save (RunSaves). It only shows when there is a run, or a save that cannot
## load: then it stays greyed out with the reason, never a crash or a broken run.
func _build_continue_button() -> void:
	var box := get_node_or_null("ButtonPanel/ButtonBox") as Container
	if box == null:
		return
	var button := box.get_node_or_null("ContinueButton") as Button
	if button == null:
		button = Button.new()
		button.name = "ContinueButton"
		button.focus_mode = Control.FOCUS_ALL
		Palette.style_button(button, true, true)
		button.pressed.connect(_on_continue_pressed)
		box.add_child(button)
		box.move_child(button, 0)
	var summary := RunSaves.summary()
	var message := String(summary.get("message", ""))
	button.visible = bool(summary.get("ok", false)) or not message.is_empty()
	button.disabled = not bool(summary.get("ok", false))
	button.text = "CONTINUE" if not button.disabled else message.substr(0, 38)
	button.tooltip_text = String(summary.get("status", message))


func _on_continue_pressed() -> void:
	var result := RunSaves.queue_continue()
	if not bool(result.get("ok", false)):
		_build_continue_button()
		return
	var payload: Dictionary = result.get("payload", {})
	_close_modal()
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = String(payload.get("seed_text", RoomState.seed_text))
	RoomState.map_scale = RoomState.Scale.INFINITE
	RoomState.difficulty = clampi(int(payload.get("difficulty",
		RoomState.Difficulty.STANDARD)), RoomState.Difficulty.RELAXED,
		RoomState.Difficulty.HARD)
	RoomState.status_message = "CONTINUING // %s" % String(result.get("place", "THE ROUTE"))
	RoomState.enter(get_tree())


func _format_save_duration(seconds: float) -> String:
	var total := maxi(0, floori(seconds))
	return "%02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]


func _focus_default_button() -> void:
	var preferred := offline_button if play_button.disabled else play_button
	if preferred != null and preferred.visible and not preferred.disabled:
		if preferred.is_inside_tree():
			preferred.grab_focus()   # a scene change can take it out of the tree first


## Restyle from Palette at load rather than in the scene file.
##
## The scene was authored in the teal the port had drifted to, and colours
## written into a .tscn are invisible to a palette change -- which is how the
## drift happened. Doing it here means the menu, the settings overlay and the
## pause screen all move together when Palette does.
func _apply_palette() -> void:
	var background := get_node_or_null("Background") as ColorRect
	if background != null:
		background.queue_redraw()
	var title := get_node_or_null("TitleLabel") as Label
	if title != null:
		Palette.style_title(title)
	var panel := get_node_or_null("ButtonPanel") as PanelContainer
	if panel != null:
		panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	# Creating or joining a route are the primary actions; everything else is
	# secondary account/settings/archive chrome.
	for path in ["ButtonPanel/ButtonBox/PlayButton",
			"ButtonPanel/ButtonBox/JoinButton"]:
		var button := get_node_or_null(path) as Button
		if button != null:
			Palette.style_button(button, true, true)
	for path in ["ButtonPanel/ButtonBox/SettingsButton",
			"ButtonPanel/ButtonBox/OfflineButton",
			"ButtonPanel/ButtonBox/AccountButton",
			"ButtonPanel/ButtonBox/TutorialButton",
			"ButtonPanel/ButtonBox/UpdateButton",
			"ButtonPanel/ButtonBox/QuitButton"]:
		var button := get_node_or_null(path) as Button
		if button != null:
			Palette.style_button(button, false, true)


## CREATE ROOM is online-first. The health check prevents an unreachable
## primary service from leaving the player staring at an indefinite
## "registering" state; the directory registration itself has a second
## fallback in RoomState in case health succeeds but registration does not.
func _on_play_pressed() -> void:
	if _creating_room or _routes_update_locked:
		return
	if OS.has_feature("web"):
		RoomState.create_local(RoomState.Mode.DEFAULT)
		RoomState.status_message = "WEB BUILD SOLO // NATIVE CO-OP IS UNAVAILABLE"
		XRFade.change_scene(get_tree(), "res://scenes/room_lobby.tscn")
		return
	_creating_room = true
	play_button.disabled = true
	play_button.text = "CONTACTING PRIMARY SERVER"
	join_button.disabled = true
	Backend.check_health()


func _on_create_health_checked(ok: bool, _message: String) -> void:
	if not _creating_room:
		return
	_creating_room = false
	RoomState.create_local(RoomState.Mode.DEFAULT)
	if ok:
		RoomState.host_primary_room()
	else:
		RoomState.status_message = "PRIMARY SERVER UNAVAILABLE // SOLO ROOM"
	XRFade.change_scene(get_tree(), "res://scenes/room_lobby.tscn")


func _on_offline_pressed() -> void:
	# Explicitly bypasses health, directory, account, and periodic update traffic.
	# It remains available when the online update gate is waiting so a local test
	# does not depend on the Pterodactyl deployment matching the worktree.
	Backend.enable_offline_mode()
	UpdateManager.enable_offline_mode()
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.status_message = "OFFLINE SOLO ROOM"
	XRFade.change_scene(get_tree(), "res://scenes/room_lobby.tscn")


func _on_join_pressed() -> void:
	if _routes_update_locked:
		return
	_close_modal()
	var content := _modal_content("ROUTE SIGNAL // ROOM ACCESS", "ENTER ROOM CODE",
		Vector2(220, 112))
	_join_input = LineEdit.new()
	_join_input.name = "RoomCodeInput"
	_join_input.placeholder_text = "ABC12"
	_join_input.max_length = RoomState.CODE_LENGTH
	_join_input.add_theme_font_size_override("font_size", 12)
	_join_input.custom_minimum_size = Vector2(0, 27)
	_join_input.tooltip_text = "FIVE-CHARACTER PRIMARY ROOM CODE"
	_join_input.text_changed.connect(_on_join_code_changed)
	_join_input.text_submitted.connect(func(_value: String) -> void: _submit_join())
	Palette.style_line_edit(_join_input)
	content.add_child(_join_input)
	var status := _modal_label("", Palette.ALERT, 6)
	status.name = "JoinStatus"
	content.add_child(status)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 5)
	content.add_child(actions)
	var cancel := _modal_button("CANCEL", false)
	cancel.pressed.connect(_close_modal)
	actions.add_child(cancel)
	var submit := _modal_button("JOIN ROOM", true)
	submit.pressed.connect(_submit_join)
	actions.add_child(submit)
	_join_input.grab_focus.call_deferred()


func _on_join_code_changed(value: String) -> void:
	_replace_normalized_text(_join_input, value, value.strip_edges().to_upper())


func _submit_join() -> void:
	if _join_input == null:
		return
	var code := _join_input.text.strip_edges().to_upper()
	var status := _modal.find_child("JoinStatus", true, false) as Label
	if not RoomState.valid_room_code(code):
		status.text = "ENTER A VALID FIVE-CHARACTER ROOM CODE"
		return
	status.text = "LOOKING UP ROOM %s..." % code
	Backend.resolve_room(code)


func _on_room_resolved(code: String, endpoint: Dictionary, error: String) -> void:
	if _modal == null or _join_input == null:
		return
	var status := _modal.find_child("JoinStatus", true, false) as Label
	if not error.is_empty():
		status.text = error
		return
	if not RoomState.game_matches(String(endpoint.get("game", "")), RoomState.GAME_LAST_ROUTE):
		status.text = "THAT ROOM IS FOR ANOTHER GAME // JOIN IT FROM ITS OWN MENU"
		return
	var join_error := RoomState.join_room(String(endpoint.get("address", "")),
		int(endpoint.get("port", RoomState.DEFAULT_PORT)),
		String(endpoint.get("transport", "relay")), code)
	if not join_error.is_empty():
		status.text = join_error
		return
	_close_modal()
	XRFade.change_scene(get_tree(), "res://scenes/room_lobby.tscn")


func _on_settings_pressed() -> void:
	_close_modal()
	settings_overlay.open()


## The account panel is the app-wide one (AccountPanel, shared with the hub and every other game's menu); this menu only
## shows the Last Route save (CONTINUE ROUTE / CLEAR SAVE below) and the signed-in name on the button.
func _on_account_pressed() -> void:
	_close_modal()
	AccountPanel.open(self)


func _on_account_changed(_signed_in_now: bool, _username: String, _admin: bool, _message: String) -> void:
	_refresh_account_button()
	RunSaves.cloud_sync()   # signing in pulls the account's run (or pushes an offline one)


func _on_account_progress_changed(_available: bool, _progress: Dictionary, _saved_at: int, _message: String) -> void:
	_build_continue_button()


func _refresh_account_button() -> void:
	account_button.text = Backend.account_username if Backend.signed_in() \
		else "REGISTER / SIGN IN"


func _on_tutorial_pressed() -> void:
	_close_modal()
	var content := _modal_content("ROUTE TRAINING // REFERENCE", "HOW TO PLAY",
		Vector2(380, 228))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var notes := _modal_label(
		"OBJECTIVE\n"
		+ "Explore the route and recover signal relays. Relaxed wakes a hunter after relay 3, Standard after relay 1, and Hard begins with an active hunter. Deeper floors become more dangerous.\n\n"
		+ "SURVIVAL\n"
		+ "The green marker is your starting safe zone. Other safe rooms become checkpoints, but hunters can breach them. The route panel and heartbeat audio warn when danger closes in. Stairs and ladders connect floors; upper levels are generally safer.\n\n"
		+ "MOVEMENT + VIEW\n"
		+ "WASD move, Shift sprints, C crouches, Space jumps, and the mouse looks. F1 hides or restores the gameplay HUD for a clean view. On a controller, use the left stick to move, right stick to look, A to jump, B to crouch, and left-stick click to sprint. M or View opens the discovered map. Place a waypoint on discovered floor space to draw a teal GPS route on the map and ground. The minimap shows only your current discovered floor.\n\n"
		+ "ITEMS + INVENTORY\n"
		+ "You begin with a flashlight. Find batteries, tasers, lockpicks, crowbars, and the rarer axes in the facility. Keys 1-5 or D-pad left/right select a slot. Tab or Y opens the inventory; drag items, or select two slots with A, to swap them. Left click or right trigger uses the held item. E, right click, or X interacts. Q or D-pad down drops the held item. G or LB fires the taser.\n\n"
		+ "CO-OP\n"
		+ "Create an online room for friends, join with its five-character code, or choose Play Offline for a server-free solo test. A single world pickup can be claimed by only one runner. The host can archive shared progress; an online solo host may also load it in place, while a room with guests must return to solo before replacing the world. The pause menu also tracks current-run statistics.",
		Palette.BODY, 7)
	notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes.custom_minimum_size = Vector2(320, 0)
	scroll.add_child(notes)


func _modal_content(kicker: String, title: String, minimum: Vector2) -> VBoxContainer:
	_modal = ColorRect.new()
	_modal.name = "MenuModal"
	_modal.color = Palette.SCRIM
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.z_index = 80
	add_child(_modal)
	var panel := PanelContainer.new()
	panel.name = "ModalPanel"
	panel.add_theme_stylebox_override("panel", Palette.panel_box(Color("0c080e"),
		Palette.PANEL_EDGE, 12))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = minimum
	panel.offset_left = -minimum.x * 0.5
	panel.offset_top = -minimum.y * 0.5
	panel.offset_right = minimum.x * 0.5
	panel.offset_bottom = minimum.y * 0.5
	_modal.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	panel.add_child(content)
	var top := HBoxContainer.new()
	content.add_child(top)
	top.add_child(_modal_label(Palette.track(kicker), Palette.AMBER, 6))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var close := _modal_button("", false)
	Palette.style_escape_close(close)
	close.pressed.connect(_close_modal)
	top.add_child(close)
	var heading := _modal_label(title, Palette.INK, 15)
	Palette.style_title(heading)
	content.add_child(heading)
	return content


func _modal_label(value: String, tint: Color, size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_color_override("font_color", tint)
	label.add_theme_font_size_override("font_size", size)
	return label


func _modal_button(value: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = value
	button.add_theme_font_size_override("font_size", 7)
	Palette.style_button(button, primary)
	return button


func _close_modal() -> void:
	if _modal != null and is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null
	_join_input = null


## The menu's last button no longer quits the app: the hub is the main menu, quitting is its own button there.
func _on_quit_pressed() -> void:
	XRFade.change_scene(get_tree(), GameRegistry.HUB_SCENE)


## CREATE and JOIN are one route-entry surface. A mandatory update must lock
## both, including a Join dialog that was already open when a periodic check
## discovered a newer revision.
func _set_route_update_locked(title: String = "UPDATING") -> void:
	_routes_update_locked = true
	# Ignore a pending health response rather than letting a room transition
	# race past an update discovered immediately after CREATE was pressed.
	_creating_room = false
	if _join_input != null:
		_close_modal()
	play_button.disabled = true
	play_button.text = title
	join_button.disabled = true
	join_button.text = title


func _clear_route_update_lock() -> void:
	_routes_update_locked = false
	play_button.disabled = false
	play_button.text = "CREATE ROOM"
	join_button.disabled = false
	join_button.text = "JOIN ROOM"
	_focus_default_button.call_deferred()


func _open_update_progress_if_needed() -> bool:
	if not UpdateManager.should_open_progress_screen():
		return false
	var error := get_tree().change_scene_to_file(UpdateManager.UPDATE_PROGRESS_SCENE)
	if error != OK:
		update_button.visible = true
		update_button.disabled = false
		update_button.text = "COULD NOT OPEN UPDATE SCREEN // RETRY"
		return false
	return true


func _on_update_available(update: Dictionary) -> void:
	var revision := String(update.get("revision", ""))
	var identity := revision.left(8).to_upper() if not revision.is_empty() \
		else String(update.get("version", ""))
	update_button.text = "PREPARING UPDATE %s" % identity
	update_button.tooltip_text = String(update.get("notes", ""))
	update_button.disabled = true
	update_button.visible = true
	if Build.requires_update_gate() or UpdateManager.update_required:
		_set_route_update_locked("UPDATING")
		_open_update_progress_if_needed()


func _on_update_pressed() -> void:
	if UpdateManager.should_open_progress_screen() or (
			UpdateManager.uses_in_progress_screen()
			and (Build.requires_update_gate() or UpdateManager.update_required)
			and (UpdateManager.downloading or UpdateManager.preparing
				or UpdateManager.ready_to_install
				or not UpdateManager.available.is_empty())):
		if _open_update_progress_if_needed():
			return
	if UpdateManager.available.is_empty():
		update_button.disabled = true
		update_button.text = "CHECKING FOR UPDATES"
		UpdateManager.check()
	elif UpdateManager.ready_to_install:
		update_button.disabled = true
		UpdateManager.install_update()
	elif not UpdateManager.downloading and not UpdateManager.preparing \
			and not UpdateManager.installing:
		update_button.disabled = true
		UpdateManager.download_update(true)
	else:
		update_button.disabled = true


func _on_update_status(message: String) -> void:
	if _open_update_progress_if_needed():
		return
	if _routes_update_locked and (UpdateManager.downloading \
			or UpdateManager.preparing or UpdateManager.installing \
			or not UpdateManager.available.is_empty()):
		_set_route_update_locked("UPDATING")
	if Build.requires_update_gate() or not UpdateManager.available.is_empty():
		update_button.visible = true
		update_button.text = message
		update_button.disabled = UpdateManager.downloading or UpdateManager.preparing \
			or UpdateManager.installing \
			or message.contains("VERIFYING") or message.contains("UNPACKING") \
			or message.contains("RESTARTING")
		if UpdateManager.is_failure_status(message) or UpdateManager.ready_to_install:
			update_button.disabled = false


func _on_update_check_finished(success: bool, needs_update: bool) -> void:
	if not Build.requires_update_gate():
		return
	if success and not needs_update:
		_clear_route_update_lock()
		update_button.visible = false
		return
	if needs_update:
		_set_route_update_locked("UPDATING")
		update_button.visible = true
		_open_update_progress_if_needed()
		return
	_set_route_update_locked("UPDATE CHECK REQUIRED")
	# Keep the specific failure visible. The old generic retry label hid whether
	# the request failed, the response was invalid, or the transport was rejected.
	update_button.text = UpdateManager.status_message \
		if not UpdateManager.status_message.is_empty() else "RETRY UPDATE CHECK"
	update_button.disabled = false
	update_button.visible = true


## Replacing LineEdit.text resets its caret. Preserve the insertion point so
## uppercase normalization cannot turn normal typing into reversed typing.
func _replace_normalized_text(field: LineEdit, value: String,
		normalized: String) -> void:
	if field == null or normalized == value:
		return
	var caret := field.caret_column
	field.text = normalized
	field.caret_column = mini(caret, normalized.length())
