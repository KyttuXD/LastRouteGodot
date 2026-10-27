class_name AccountPanel
extends CanvasLayer

## The ONE account panel for the whole app (Kyttu's Lab): sign in, register, sign out, account settings (username,
## password, the admin setup key field) and a SAVES section with one row per game from GameRegistry. It knows no game: a
## game's save row comes from GameRegistry.save_summary(), its OPEN / CLEAR actions are links into that game's menu.
## The signed-in account, its session tokens per server, admin/owner status and debug flags are app-level state in the
## Backend autoload; this panel only shows and changes it, so the hub, the Last Route menu and every other game's menu open
## the same panel and share one login.
##
##   AccountPanel.open(self)       from any scene (the panel frees with it)

signal closed

const TITLE := "KYTTU'S LAB // ACCOUNT"

var _surface: ColorRect
var _content: VBoxContainer
var _status: Label
var _username: LineEdit
var _password: LineEdit
var _admin_proof: LineEdit
var _manage_username: LineEdit
var _manage_password: LineEdit
var _manage_admin_proof: LineEdit
var _mode := "main"
var _confirm_clear := ""


static func open(host: Node) -> AccountPanel:
	var existing := host.get_tree().root.find_child("AccountPanel", true, false) as AccountPanel
	if existing != null and is_instance_valid(existing):
		existing.show_main()
		return existing
	var panel := AccountPanel.new()
	panel.name = "AccountPanel"
	host.add_child(panel)
	return panel


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	Backend.account_changed.connect(_on_account_changed)
	Backend.account_progress_changed.connect(_on_progress_changed)
	MouseLock.claim("account_panel", true)
	show_main()


func _exit_tree() -> void:
	MouseLock.claim("account_panel", false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	closed.emit()
	queue_free()


# -- layout -------------------------------------------------------------------------------------------------------

func _begin(title: String, minimum: Vector2) -> void:
	if _surface != null:
		_surface.queue_free()
	_username = null
	_password = null
	_admin_proof = null
	_manage_username = null
	_manage_password = null
	_manage_admin_proof = null
	_surface = ColorRect.new()
	_surface.name = "AccountSurface"
	_surface.color = Palette.SCRIM
	_surface.mouse_filter = Control.MOUSE_FILTER_STOP
	_surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_surface)
	var panel := PanelContainer.new()
	panel.name = "AccountBox"
	panel.add_theme_stylebox_override("panel", Palette.panel_box(Color("0c080e"), Palette.PANEL_EDGE, 12))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = minimum
	panel.offset_left = -minimum.x * 0.5
	panel.offset_top = -minimum.y * 0.5
	panel.offset_right = minimum.x * 0.5
	panel.offset_bottom = minimum.y * 0.5
	_surface.add_child(panel)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 5)
	panel.add_child(_content)
	var top := HBoxContainer.new()
	_content.add_child(top)
	var kicker := _label(Palette.track(TITLE), Palette.AMBER, 6)
	kicker.name = "AccountKicker"
	top.add_child(kicker)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var close_button := _button("", false)
	close_button.name = "AccountClose"
	Palette.style_escape_close(close_button)
	close_button.pressed.connect(close)
	top.add_child(close_button)
	var heading := _label(title, Palette.INK, 14)
	heading.name = "AccountTitle"
	Palette.style_title(heading, Palette.INK)
	_content.add_child(heading)


func _label(text: String, tint: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", tint)
	label.add_theme_font_size_override("font_size", size)
	return label


func _button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 7)
	Palette.style_button(button, primary)
	return button


func _field(placeholder: String, secret: bool, field_name: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.name = field_name
	edit.placeholder_text = placeholder
	edit.secret = secret
	edit.text_direction = Control.TEXT_DIRECTION_LTR
	edit.alignment = HORIZONTAL_ALIGNMENT_LEFT
	edit.custom_minimum_size = Vector2(0, 22)
	Palette.style_line_edit(edit)
	return edit


# -- screens ------------------------------------------------------------------------------------------------------

func show_main() -> void:
	_mode = "main"
	_confirm_clear = ""
	if Backend.signed_in():
		_show_signed_in()
	else:
		_show_sign_in()


func _show_sign_in() -> void:
	_begin("ACCOUNT", Vector2(240, 150))
	_status = _label("", Palette.MUTED, 6)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_status)
	_status.text = "NOT SIGNED IN // PLAY WITHOUT AN ACCOUNT OR SIGN IN TO SAVE ACROSS DEVICES"
	if not Backend.accounts_available():
		var warning := Backend.account_transport_warning()
		_status.text = warning if not warning.is_empty() else "ACCOUNT SIGN-IN IS DISABLED FOR THIS BACKEND ORIGIN"
		_status.add_theme_color_override("font_color", Palette.ALERT)
	elif not Backend.account_transport_warning().is_empty():
		_status.text += "\n%s" % Backend.account_transport_warning()
		_status.add_theme_color_override("font_color", Palette.ALERT)
	_username = _field("USERNAME // 3-24 CHARS: A-Z 0-9 _", false, "AccountUsernameInput")
	_username.max_length = 24
	_username.text_changed.connect(_on_username_changed)
	_content.add_child(_username)
	_password = _field("PASSWORD // 6+ CHARACTERS", true, "AccountPasswordInput")
	_content.add_child(_password)
	_admin_proof = _field("ADMIN SETUP KEY", true, "AccountAdminProofInput")
	_admin_proof.visible = false
	_admin_proof.tooltip_text = "ONLY REQUIRED TO CREATE A RESERVED OWNER ACCOUNT"
	_content.add_child(_admin_proof)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 5)
	_content.add_child(actions)
	var login := _button("SIGN IN", true)
	login.name = "AccountLoginButton"
	login.disabled = not Backend.accounts_available()
	login.pressed.connect(_submit.bind(false))
	actions.add_child(login)
	var register := _button("CREATE ACCOUNT", false)
	register.name = "AccountRegisterButton"
	register.disabled = not Backend.accounts_available()
	register.pressed.connect(_submit.bind(true))
	actions.add_child(register)
	_username.grab_focus.call_deferred()


func _show_signed_in() -> void:
	var games := GameRegistry.all()
	_begin("ACCOUNT", Vector2(260, 130 + 22 * games.size()))
	_status = _label("SIGNED IN AS %s%s" % [Backend.account_username, " // ADMIN" if Backend.account_admin else ""], Palette.MUTED, 6)
	_status.name = "AccountStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_status)
	if not Backend.account_transport_warning().is_empty():
		_status.text += "\n%s" % Backend.account_transport_warning()
		_status.add_theme_color_override("font_color", Palette.ALERT)
	_content.add_child(_label(Palette.track("SAVES"), Palette.AMBER, 6))
	var saves := VBoxContainer.new()
	saves.name = "AccountSaves"
	saves.add_theme_constant_override("separation", 3)
	_content.add_child(saves)
	for game in games:
		saves.add_child(_save_row(game))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 5)
	_content.add_child(actions)
	var manage := _button("ACCOUNT SETTINGS", false)
	manage.name = "AccountSettingsButton"
	manage.pressed.connect(_show_manage)
	actions.add_child(manage)
	var logout := _button("SIGN OUT", false)
	logout.name = "AccountSignOutButton"
	logout.pressed.connect(Backend.account_logout)
	actions.add_child(logout)


func _save_row(game: Dictionary) -> Control:
	var id := String(game["id"])
	var summary := GameRegistry.save_summary(id)
	var row := HBoxContainer.new()
	row.name = "SaveRow_%s" % id
	row.add_theme_constant_override("separation", 5)
	var text := _label("%s // %s" % [String(game["title"]), String(summary["text"])],
		Palette.BODY if bool(summary["has_save"]) else Palette.MUTED, 6)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.clip_text = true
	row.add_child(text)
	if GameRegistry.is_launchable(id):
		var open_button := _button("OPEN", false)
		open_button.name = "SaveOpen_%s" % id
		open_button.pressed.connect(func() -> void:
			get_tree().change_scene_to_file(String(game["scene"])))
		row.add_child(open_button)
	if bool(summary["has_save"]):
		var clear := _button("SURE?" if _confirm_clear == id else "CLEAR", false)
		clear.name = "SaveClear_%s" % id
		clear.pressed.connect(func() -> void:
			if _confirm_clear == id:
				_confirm_clear = ""
				Backend.account_clear_game_progress(id)
			else:
				_confirm_clear = id
				_show_signed_in())
		row.add_child(clear)
	return row


func _show_manage() -> void:
	if not Backend.signed_in():
		show_main()
		return
	_mode = "manage"
	_begin("ACCOUNT SETTINGS", Vector2(280, 214))
	_status = _label("SIGNED IN AS %s" % Backend.account_username, Palette.MUTED, 6)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_status)
	_content.add_child(_label("USERNAME", Palette.AMBER, 6))
	_manage_username = _field("", false, "ManageUsernameInput")
	_manage_username.text = Backend.account_username
	_manage_username.max_length = 24
	_manage_username.text_changed.connect(_on_manage_username_changed)
	_content.add_child(_manage_username)
	_manage_admin_proof = _field("ADMIN SETUP KEY", true, "ManageAdminProofInput")
	_manage_admin_proof.visible = false
	_content.add_child(_manage_admin_proof)
	var rename := _button("UPDATE USERNAME", false)
	rename.name = "RenameAccountButton"
	rename.pressed.connect(_submit_rename)
	_content.add_child(rename)
	_content.add_child(_label("NEW PASSWORD", Palette.AMBER, 6))
	_manage_password = _field("6-200 CHARACTERS", true, "ManagePasswordInput")
	_content.add_child(_manage_password)
	var password := _button("UPDATE PASSWORD", false)
	password.name = "ChangePasswordButton"
	password.pressed.connect(_submit_password)
	_content.add_child(password)
	var back := _button("BACK TO ACCOUNT", false)
	back.name = "BackToAccountButton"
	back.pressed.connect(show_main)
	_content.add_child(back)


# -- actions ------------------------------------------------------------------------------------------------------

func _submit(register: bool) -> void:
	if _username == null or _password == null:
		return
	_status.text = "CREATING ACCOUNT..." if register else "SIGNING IN..."
	if register:
		Backend.account_register(_username.text, _password.text, _admin_proof.text if _admin_proof != null else "")
	else:
		Backend.account_login(_username.text, _password.text)


func _on_username_changed(value: String) -> void:
	if _username == null:
		return
	var canonical := value.strip_edges().to_upper()
	_replace_text(_username, value, canonical)
	if _admin_proof != null:
		_admin_proof.visible = canonical in ["KYTTU", "AYTTU"]


func _on_manage_username_changed(value: String) -> void:
	if _manage_username == null:
		return
	var canonical := value.strip_edges().to_upper()
	_replace_text(_manage_username, value, canonical)
	if _manage_admin_proof != null:
		_manage_admin_proof.visible = canonical == "KYTTU" and Backend.account_username != "KYTTU"


## Replacing LineEdit.text resets its caret; keep the insertion point so uppercase normalisation cannot reverse typing.
func _replace_text(field: LineEdit, value: String, normalized: String) -> void:
	if field == null or normalized == value:
		return
	var caret := field.caret_column
	field.text = normalized
	field.caret_column = mini(caret, normalized.length())


func _submit_rename() -> void:
	if _manage_username == null:
		return
	_status.text = "UPDATING USERNAME..."
	Backend.account_rename(_manage_username.text, _manage_admin_proof.text if _manage_admin_proof != null else "")


func _submit_password() -> void:
	if _manage_password == null:
		return
	_status.text = "UPDATING PASSWORD..."
	Backend.account_change_password(_manage_password.text)
	_manage_password.clear()


## Sign-in / sign-out arrives from Backend (a signal, so every open menu hears it): swap between the form and the card only
## when the state changed sides, so a failed attempt's message is not erased by a rebuild.
func _on_account_changed(signed_in_now: bool, _username_value: String, _admin: bool, message: String) -> void:
	if _status != null and is_instance_valid(_status):
		_status.text = message
	var showing_form := _username != null and is_instance_valid(_username)
	var showing_management := _manage_username != null and is_instance_valid(_manage_username)
	if (signed_in_now and showing_form) or (not signed_in_now and not showing_form):
		show_main()
	elif signed_in_now and showing_management:
		_manage_username.text = Backend.account_username


func _on_progress_changed(_available: bool, _progress: Dictionary, _saved_at: int, message: String) -> void:
	if not Backend.signed_in():
		return
	if _mode == "main" and _surface != null:
		show_main()
		if _status != null and is_instance_valid(_status):
			_status.text = message
