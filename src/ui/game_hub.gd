class_name GameHub
extends Control

## The shell above the games: boot lands here, each game is a card, and account / settings / admin / quit are shared
## entries that do not belong to any one game. Games come from GameRegistry; a locked game (Night Watch, until its 3D
## port exists) shows its card with the reason instead of a launch button.
## Account opens the shared app-level AccountPanel (one login for every game); settings open the Last Route menu's overlay
## (GameHub.pending_menu_action) until they move out of that scene.

const SIGNAL_BACKDROP_SCRIPT := preload("res://src/ui/signal_backdrop.gd")
const MENU_SCENE := "res://scenes/main_menu.tscn"

## What the next menu should open on arrival: "", "account" or "settings".
static var pending_menu_action := ""

var _cards := {}
var _launch_buttons := {}
var _toast: Label
var _signed_in: Label
var _quit_dialog: Control


func _ready() -> void:
	GameRegistry.active_game_id = GameRegistry.DEFAULT_ID
	MouseLock.release_all()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := SIGNAL_BACKDROP_SCRIPT.new()
	backdrop.name = "SignalBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var column := VBoxContainer.new()
	column.name = "HubColumn"
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	var brand := Label.new()
	brand.name = "HubTitle"
	Palette.style_title(brand, Palette.INK)
	brand.add_theme_font_size_override("font_size", 22)
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.text = "KYTTU'S LAB"
	column.add_child(brand)
	_signed_in = Label.new()
	_signed_in.name = "HubSignedIn"
	Palette.style_label(_signed_in, Palette.MUTED, 6)
	column.add_child(_signed_in)
	_refresh_signed_in()
	Backend.account_changed.connect(_on_account_changed)
	var kicker := Label.new()
	kicker.name = "HubKicker"
	Palette.style_label(kicker, Palette.AMBER, 6)
	kicker.text = Palette.track("CHOOSE A GAME")
	column.add_child(kicker)
	var cards := HBoxContainer.new()
	cards.name = "HubCards"
	cards.add_theme_constant_override("separation", 10)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(cards)
	for game in GameRegistry.all():
		cards.add_child(_build_card(game))
	var footer := HBoxContainer.new()
	footer.name = "HubShared"
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 6)
	column.add_child(footer)
	footer.add_child(_shared_button("AccountButton", "ACCOUNT", _on_account))
	footer.add_child(_shared_button("SettingsButton", "SETTINGS", _on_settings))
	var admin := _shared_button("AdminButton", "ADMIN", _on_admin)
	admin.disabled = not Backend.admin_owner_authorized()
	admin.tooltip_text = "Admin tools open inside a run"
	footer.add_child(admin)
	# Web builds have no desktop to quit to; the browser tab is the way out.
	if not OS.has_feature("web"):
		footer.add_child(_shared_button("QuitButton", "QUIT", _ask_quit))
	_toast = Label.new()
	_toast.name = "HubToast"
	Palette.style_label(_toast, Palette.MUTED, 6)
	_toast.custom_minimum_size = Vector2(0, 10)
	column.add_child(_toast)
	_refresh_signed_in()
	_focus_default.call_deferred()


## The header shows who is signed in (and ADMIN) so every menu and the hub agree; Backend is the one source.
func _refresh_signed_in() -> void:
	if _signed_in == null:
		return
	if Backend.signed_in():
		_signed_in.text = "SIGNED IN // %s%s" % [Backend.account_username, "  [ADMIN]" if Backend.account_admin else ""]
		_signed_in.add_theme_color_override("font_color", Palette.STABLE)
	else:
		_signed_in.text = "NOT SIGNED IN"
		_signed_in.add_theme_color_override("font_color", Palette.MUTED)
	var admin_button := find_child("AdminButton", true, false) as Button
	if admin_button != null:
		admin_button.disabled = not Backend.admin_owner_authorized()
	var account_button := find_child("AccountButton", true, false) as Button
	if account_button != null:
		account_button.text = Backend.account_username if Backend.signed_in() else "ACCOUNT"


func _on_account_changed(_signed_in_now: bool, _username: String, _admin: bool, _message: String) -> void:
	if is_inside_tree():
		_refresh_signed_in()


func _exit_tree() -> void:
	if Backend.account_changed.is_connected(_on_account_changed):
		Backend.account_changed.disconnect(_on_account_changed)


func _focus_default() -> void:
	var first := _launch_buttons.get(GameRegistry.DEFAULT_ID) as Button
	if first != null and is_instance_valid(first) and first.is_inside_tree():
		first.grab_focus()


func _build_card(game: Dictionary) -> PanelContainer:
	var id := String(game["id"])
	var locked := bool(game["locked"])
	var card := PanelContainer.new()
	card.name = "Card_%s" % id
	card.custom_minimum_size = Vector2(200, 118)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.theme = load(String(game["theme"])) as Theme
	card.theme_type_variation = &"LockedGameCard" if locked else &"GameCard"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var kicker := Label.new()
	kicker.theme_type_variation = &"KickerLabel"
	kicker.text = String(game["kicker"])
	box.add_child(kicker)
	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_override("font", Palette.title_font())
	title.text = String(game["title"])
	title.add_theme_color_override("font_color", Palette.INK if not locked else Palette.DIM)
	box.add_child(title)
	var tagline := Label.new()
	tagline.name = "Tagline"
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tagline.custom_minimum_size = Vector2(180, 0)
	tagline.text = String(game["tagline"])
	box.add_child(tagline)
	if bool(game.get("in_progress", false)):
		var progress := Label.new()
		progress.name = "InProgress"
		progress.theme_type_variation = &"KickerLabel"
		progress.text = "IN PROGRESS"
		box.add_child(progress)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	if locked:
		var note := Label.new()
		note.name = "LockedNote"
		note.theme_type_variation = &"MutedLabel"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.text = "LOCKED // %s" % String(game["locked_note"])
		box.add_child(note)
	var button := Button.new()
	button.name = "Launch_%s" % id
	button.theme_type_variation = &"PrimaryButton"
	button.text = "LOCKED" if locked else "PLAY"
	button.disabled = locked
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(_launch.bind(id))
	box.add_child(button)
	_cards[id] = card
	_launch_buttons[id] = button
	return card


func _shared_button(button_name: String, label: String, handler: Callable) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = label
	button.focus_mode = Control.FOCUS_ALL
	Palette.style_button(button, false, true)
	button.pressed.connect(handler)
	return button


## "QUIT TO DESKTOP?" The only place that leaves the app. YES sits on the left, NO (the default, focused, safe answer) on
## the right; Esc, NO or a click outside the box closes the question. Esc never quits.
func _ask_quit() -> void:
	if _quit_dialog != null and is_instance_valid(_quit_dialog):
		return
	_quit_dialog = Control.new()
	_quit_dialog.name = "QuitDialog"
	_quit_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_quit_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	_quit_dialog.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_close_quit_dialog())
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quit_dialog.add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "QuitBox"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", Palette.panel_box(Palette.PANEL, Palette.ACCENT_EDGE, 10))
	_quit_dialog.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var question := Label.new()
	question.text = "QUIT TO DESKTOP?"
	Palette.style_label(question, Palette.INK, 8)
	box.add_child(question)
	var row := HBoxContainer.new()
	row.name = "QuitChoices"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var yes := _shared_button("QuitYesButton", "YES", func() -> void: get_tree().quit())
	var no := _shared_button("QuitNoButton", "NO", _close_quit_dialog)
	row.add_child(yes)
	row.add_child(no)
	# left/right keeps the visual order: YES | NO
	yes.focus_neighbor_right = yes.get_path_to(no)
	no.focus_neighbor_left = no.get_path_to(yes)
	yes.focus_neighbor_left = yes.get_path_to(yes)
	no.focus_neighbor_right = no.get_path_to(no)
	add_child(_quit_dialog)
	no.grab_focus()


func _close_quit_dialog() -> void:
	if _quit_dialog != null and is_instance_valid(_quit_dialog):
		_quit_dialog.queue_free()
	_quit_dialog = null
	var quit_button := find_child("QuitButton", true, false) as Button
	if quit_button != null:
		quit_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	# Esc on the hub does nothing, except closing the quit question.
	if event.is_action_pressed("ui_cancel"):
		if _quit_dialog != null and is_instance_valid(_quit_dialog):
			_close_quit_dialog()
		get_viewport().set_input_as_handled()


func _launch(id: String) -> void:
	if not GameRegistry.is_launchable(id):
		return
	GameRegistry.active_game_id = id
	get_tree().change_scene_to_file(String(GameRegistry.get_game(id)["scene"]))


func _on_account() -> void:
	AccountPanel.open(self)


func _on_settings() -> void:
	pending_menu_action = "settings"
	_launch(GameRegistry.DEFAULT_ID)


func _on_admin() -> void:
	_toast.text = "ADMIN TOOLS OPEN INSIDE A RUN"
