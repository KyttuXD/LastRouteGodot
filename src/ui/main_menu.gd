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
@onready var settings_button: Button = %SettingsButton
@onready var account_button: Button = %AccountButton
@onready var changelog_button: Button = %ChangelogButton
@onready var quit_button: Button = %QuitButton
@onready var update_button: Button = %UpdateButton
@onready var version_label: Label = %VersionLabel
@onready var settings_overlay: SettingsPanel = %SettingsOverlay

var _modal: Control
var _join_input: LineEdit
var _account_username: LineEdit
var _account_password: LineEdit
var _account_admin_proof: LineEdit
var _account_status: Label
var _manage_username: LineEdit
var _manage_admin_proof: LineEdit
var _manage_password: LineEdit
var _creating_room := false


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
	play_button.pressed.connect(_on_play_pressed)
	join_button.pressed.connect(_on_join_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	account_button.pressed.connect(_on_account_pressed)
	changelog_button.pressed.connect(_on_changelog_pressed)
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
	version_label.text = "VERSION %s // %s // %s" % [Build.VERSION,
		Build.update_channel().to_upper(), Build.short_revision().to_upper()]
	if not UpdateManager.available.is_empty():
		_on_update_available(UpdateManager.available)
	if Build.requires_update_gate():
		play_button.disabled = true
		play_button.text = "CHECKING FOR UPDATES"
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
			"ButtonPanel/ButtonBox/AccountButton",
			"ButtonPanel/ButtonBox/ChangelogButton",
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
	if _creating_room:
		return
	if OS.has_feature("web"):
		RoomState.create_local(RoomState.Mode.DEFAULT)
		RoomState.status_message = "WEB BUILD SOLO // NATIVE CO-OP IS UNAVAILABLE"
		get_tree().change_scene_to_file("res://scenes/room_lobby.tscn")
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
	get_tree().change_scene_to_file("res://scenes/room_lobby.tscn")


func _on_join_pressed() -> void:
	_close_modal()
	var content := _modal_content("ROUTE SIGNAL // ROOM ACCESS", "ENTER ROOM CODE",
		Vector2(220, 112))
	_join_input = LineEdit.new()
	_join_input.name = "RoomCodeInput"
	_join_input.placeholder_text = "ABC12"
	_join_input.max_length = RoomState.CODE_LENGTH
	_join_input.add_theme_font_size_override("font_size", 12)
	_join_input.custom_minimum_size = Vector2(0, 27)
	_join_input.text_changed.connect(func(value: String) -> void:
		var cleaned := value.strip_edges().to_upper()
		if cleaned != value:
			_join_input.set_deferred("text", cleaned)
		_join_input.tooltip_text = "FIVE-CHARACTER PRIMARY ROOM CODE")
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
	var join_error := RoomState.join_room(String(endpoint.get("address", "")),
		int(endpoint.get("port", RoomState.DEFAULT_PORT)),
		String(endpoint.get("transport", "relay")), code)
	if not join_error.is_empty():
		status.text = join_error
		return
	_close_modal()
	get_tree().change_scene_to_file("res://scenes/room_lobby.tscn")


func _on_settings_pressed() -> void:
	_close_modal()
	settings_overlay.open()


func _on_account_pressed() -> void:
	_close_modal()
	var content := _modal_content("ROUTE SIGNAL // ACCOUNT", "ACCOUNT", Vector2(240, 158))
	_account_status = _modal_label("", Palette.MUTED, 6)
	_account_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_account_status)
	if Backend.signed_in():
		_account_status.text = "SIGNED IN AS %s%s" % [Backend.account_username,
			" // ADMIN" if Backend.account_admin else ""]
		if not Backend.account_transport_warning().is_empty():
			_account_status.text += "\n%s" % Backend.account_transport_warning()
			_account_status.add_theme_color_override("font_color", Palette.ALERT)
		if Backend.has_route_checkpoint():
			var checkpoint := Backend.account_progress
			content.add_child(_modal_label(
				"SAVED ROUTE // DEPTH %d // SCORE %d // %s" % [
					int(checkpoint.get("depth", 1)), int(checkpoint.get("score", 0)),
					String(checkpoint.get("difficulty_id", "standard")).to_upper()],
				Palette.BODY, 6))
		else:
			content.add_child(_modal_label("NO SAVED ROUTE CHECKPOINT", Palette.MUTED, 6))
		if Backend.has_route_checkpoint():
			var checkpoint_actions := HBoxContainer.new()
			checkpoint_actions.add_theme_constant_override("separation", 5)
			content.add_child(checkpoint_actions)
			var continue_route := _modal_button("CONTINUE ROUTE", true)
			continue_route.name = "ContinueRouteButton"
			continue_route.pressed.connect(_continue_route_checkpoint)
			checkpoint_actions.add_child(continue_route)
			var clear_route := _modal_button("CLEAR SAVE", false)
			clear_route.name = "ClearRouteButton"
			clear_route.pressed.connect(Backend.account_clear_progress)
			checkpoint_actions.add_child(clear_route)
		var account_actions := HBoxContainer.new()
		account_actions.add_theme_constant_override("separation", 5)
		content.add_child(account_actions)
		var manage := _modal_button("ACCOUNT SETTINGS", false)
		manage.name = "AccountSettingsButton"
		manage.pressed.connect(_on_account_manage_pressed)
		account_actions.add_child(manage)
		var logout := _modal_button("SIGN OUT", false)
		logout.pressed.connect(Backend.account_logout)
		account_actions.add_child(logout)
		return
	_account_status.text = "NOT SIGNED IN // PLAY WITHOUT AN ACCOUNT OR SIGN IN TO SAVE ACROSS DEVICES"
	if not Backend.accounts_available():
		_account_status.text = "ACCOUNT SIGN-IN IS DISABLED FOR THIS BACKEND ORIGIN"
	elif not Backend.account_transport_warning().is_empty():
		_account_status.text += "\n%s" % Backend.account_transport_warning()
		_account_status.add_theme_color_override("font_color", Palette.ALERT)
	_account_username = LineEdit.new()
	_account_username.placeholder_text = "3-24 CHARS: A-Z 0-9 _"
	_account_username.max_length = 24
	_account_username.custom_minimum_size = Vector2(0, 22)
	Palette.style_line_edit(_account_username)
	_account_username.text_changed.connect(_on_account_username_changed)
	content.add_child(_account_username)
	_account_password = LineEdit.new()
	_account_password.placeholder_text = "6+ CHARACTERS"
	_account_password.secret = true
	_account_password.custom_minimum_size = Vector2(0, 22)
	Palette.style_line_edit(_account_password)
	content.add_child(_account_password)
	_account_admin_proof = LineEdit.new()
	_account_admin_proof.placeholder_text = "ADMIN SETUP KEY"
	_account_admin_proof.secret = true
	_account_admin_proof.custom_minimum_size = Vector2(0, 22)
	_account_admin_proof.visible = false
	_account_admin_proof.tooltip_text = "ONLY REQUIRED TO CREATE THE RESERVED KYTTU ACCOUNT"
	Palette.style_line_edit(_account_admin_proof)
	content.add_child(_account_admin_proof)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 5)
	content.add_child(actions)
	var login := _modal_button("SIGN IN", true)
	login.name = "AccountLoginButton"
	login.disabled = not Backend.accounts_available()
	login.pressed.connect(_submit_account.bind(false))
	actions.add_child(login)
	var register := _modal_button("CREATE ACCOUNT", false)
	register.name = "AccountRegisterButton"
	register.disabled = not Backend.accounts_available()
	register.pressed.connect(_submit_account.bind(true))
	actions.add_child(register)


func _submit_account(register: bool) -> void:
	if _account_username == null or _account_password == null:
		return
	_account_status.text = "CREATING ACCOUNT..." if register else "SIGNING IN..."
	if register:
		Backend.account_register(_account_username.text, _account_password.text,
			_account_admin_proof.text if _account_admin_proof != null else "")
	else:
		Backend.account_login(_account_username.text, _account_password.text)


func _on_account_username_changed(value: String) -> void:
	if _account_username == null:
		return
	var canonical := value.strip_edges().to_upper()
	if canonical != value:
		_account_username.set_deferred("text", canonical)
	if _account_admin_proof != null:
		_account_admin_proof.visible = canonical == "KYTTU"


func _on_account_manage_pressed() -> void:
	if not Backend.signed_in():
		_on_account_pressed()
		return
	_close_modal()
	var content := _modal_content("ROUTE SIGNAL // ACCOUNT", "ACCOUNT SETTINGS",
		Vector2(280, 214))
	_account_status = _modal_label("SIGNED IN AS %s" % Backend.account_username,
		Palette.MUTED, 6)
	_account_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_account_status)
	content.add_child(_modal_label("USERNAME", Palette.AMBER, 6))
	_manage_username = LineEdit.new()
	_manage_username.name = "ManageUsernameInput"
	_manage_username.text = Backend.account_username
	_manage_username.max_length = 24
	_manage_username.custom_minimum_size = Vector2(0, 20)
	Palette.style_line_edit(_manage_username)
	_manage_username.text_changed.connect(_on_manage_username_changed)
	content.add_child(_manage_username)
	_manage_admin_proof = LineEdit.new()
	_manage_admin_proof.name = "ManageAdminProofInput"
	_manage_admin_proof.placeholder_text = "ADMIN SETUP KEY"
	_manage_admin_proof.secret = true
	_manage_admin_proof.custom_minimum_size = Vector2(0, 20)
	_manage_admin_proof.visible = false
	Palette.style_line_edit(_manage_admin_proof)
	content.add_child(_manage_admin_proof)
	var rename := _modal_button("UPDATE USERNAME", false)
	rename.name = "RenameAccountButton"
	rename.pressed.connect(_submit_account_rename)
	content.add_child(rename)

	content.add_child(_modal_label("NEW PASSWORD", Palette.AMBER, 6))
	_manage_password = LineEdit.new()
	_manage_password.name = "ManagePasswordInput"
	_manage_password.placeholder_text = "6-200 CHARACTERS"
	_manage_password.secret = true
	_manage_password.custom_minimum_size = Vector2(0, 20)
	Palette.style_line_edit(_manage_password)
	content.add_child(_manage_password)
	var password := _modal_button("UPDATE PASSWORD", false)
	password.name = "ChangePasswordButton"
	password.pressed.connect(_submit_account_password)
	content.add_child(password)
	var back := _modal_button("BACK TO ACCOUNT", false)
	back.name = "BackToAccountButton"
	back.pressed.connect(_on_account_pressed)
	content.add_child(back)


func _on_manage_username_changed(value: String) -> void:
	if _manage_username == null:
		return
	var canonical := value.strip_edges().to_upper()
	if canonical != value:
		_manage_username.set_deferred("text", canonical)
	if _manage_admin_proof != null:
		_manage_admin_proof.visible = canonical == "KYTTU" \
			and Backend.account_username != "KYTTU"


func _submit_account_rename() -> void:
	if _manage_username == null:
		return
	_account_status.text = "UPDATING USERNAME..."
	Backend.account_rename(_manage_username.text,
		_manage_admin_proof.text if _manage_admin_proof != null else "")


func _submit_account_password() -> void:
	if _manage_password == null:
		return
	_account_status.text = "UPDATING PASSWORD..."
	Backend.account_change_password(_manage_password.text)
	_manage_password.clear()


func _on_account_changed(signed_in_now: bool, _username: String,
		_admin: bool, message: String) -> void:
	_refresh_account_button()
	if _account_status != null and is_instance_valid(_account_status):
		_account_status.text = message
	# Rebuild only when the account state changed sides: a successful sign-in
	# replaces the form with the signed-in card, and sign-out restores the
	# form. Rebuilding an already-signed-out form would immediately erase a
	# failed login/registration message from the server.
	var showing_sign_in_form := _account_username != null \
		and is_instance_valid(_account_username)
	var showing_management := _manage_username != null \
		and is_instance_valid(_manage_username)
	if _account_status != null and _modal != null \
		and ((signed_in_now and showing_sign_in_form) \
			or (not signed_in_now and not showing_sign_in_form)):
		_on_account_pressed()
	elif signed_in_now and showing_management and is_instance_valid(_manage_username):
		_manage_username.text = Backend.account_username


func _on_account_progress_changed(available: bool, _progress: Dictionary,
		_saved_at: int, message: String) -> void:
	if _account_status == null or _modal == null:
		return
	var showing_checkpoint := _modal.find_child("ContinueRouteButton", true, false) != null
	if Backend.signed_in() and available != showing_checkpoint:
		_on_account_pressed()
	elif is_instance_valid(_account_status):
		_account_status.text = message


func _continue_route_checkpoint() -> void:
	var error := RoomState.prepare_route_checkpoint(Backend.account_progress)
	if not error.is_empty():
		if _account_status != null:
			_account_status.text = error
		return
	_close_modal()
	RoomState.enter(get_tree())


func _refresh_account_button() -> void:
	account_button.text = Backend.account_username if Backend.signed_in() \
		else "REGISTER / SIGN IN"


func _on_changelog_pressed() -> void:
	_close_modal()
	var content := _modal_content("ARCHIVED PLAYER PATCHES", "CHANGELOG", Vector2(360, 220))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var notes := _modal_label(
		"DEBUG 0.0.1.0\n\n• Primary-server gameplay relay removes router forwarding.\n"
		+ "• Player and hunter animation rotation corrected.\n"
		+ "• Crouching now fades the character instead of using the old pose.\n"
		+ "• Original menu, staging, settings, account and dual-frame styling restored.\n"
		+ "• Account login, restart-safe sessions and solo route Continue/Clear are live.\n"
		+ "• Threaded route loading shows configuration/tips and covers guest snapshot sync.\n"
		+ "• Run reports replace timed resets; Account Settings can rename/change passwords.\n"
		+ "• Persistent account and checkpoint data stays under ignored .data storage.\n\n"
		+ "Version numbers remain fixed until an explicit bump is requested.", Palette.BODY, 7)
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
	_account_username = null
	_account_password = null
	_account_admin_proof = null
	_account_status = null
	_manage_username = null
	_manage_admin_proof = null
	_manage_password = null


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_update_available(update: Dictionary) -> void:
	var revision := String(update.get("revision", ""))
	var identity := revision.left(8).to_upper() if not revision.is_empty() \
		else String(update.get("version", ""))
	update_button.text = "PREPARING UPDATE %s" % identity
	update_button.tooltip_text = String(update.get("notes", ""))
	update_button.disabled = true
	update_button.visible = true
	if Build.requires_update_gate() or UpdateManager.update_required:
		play_button.disabled = true
		play_button.text = "UPDATE REQUIRED"


func _on_update_pressed() -> void:
	if UpdateManager.available.is_empty():
		update_button.disabled = true
		update_button.text = "CHECKING FOR UPDATES"
		UpdateManager.check()
	elif UpdateManager.ready_to_install:
		update_button.disabled = true
		UpdateManager.install_update()
	elif not UpdateManager.downloading and not UpdateManager.installing:
		update_button.disabled = true
		UpdateManager.download_update(true)
	else:
		update_button.disabled = true


func _on_update_status(message: String) -> void:
	if Build.requires_update_gate() or not UpdateManager.available.is_empty():
		update_button.visible = true
		update_button.text = message
		update_button.disabled = UpdateManager.downloading or UpdateManager.installing \
			or message.contains("VERIFYING") or message.contains("UNPACKING") \
			or message.contains("RESTARTING")
		if message.contains("FAILED") or message.contains("RETRY") \
				or message.contains("READ-ONLY") or UpdateManager.ready_to_install:
			update_button.disabled = false


func _on_update_check_finished(success: bool, needs_update: bool) -> void:
	if not Build.requires_update_gate():
		return
	if success and not needs_update:
		play_button.disabled = false
		play_button.text = "CREATE ROOM"
		update_button.visible = false
		return
	play_button.disabled = true
	if needs_update:
		play_button.text = "UPDATE REQUIRED"
		update_button.visible = true
		return
	play_button.text = "UPDATE CHECK REQUIRED"
	update_button.text = "RETRY UPDATE CHECK"
	update_button.disabled = false
	update_button.visible = true
