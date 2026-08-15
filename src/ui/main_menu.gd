extends Control

## Startup screen.
##
## Every play button opens a ROOM and lands on staging, including the solo
## ones. Singleplayer is a room with one player in it, hosted locally with no
## transport attached, so the route a run takes to start is already the route a
## multiplayer run will take -- see src/autoload/room_state.gd.
##
## That is what makes PLAY and OFFICE MODE becoming CREATE ROOM and JOIN ROOM
## a rename rather than a rewrite. CREATE ROOM is live now for the same reason:
## opening a room never needed a backend, only having someone else JOIN one
## does, so JOIN is the single button still waiting on milestone 9.

@onready var play_button: Button = %PlayButton
@onready var office_button: Button = %OfficeButton
@onready var create_room_button: Button = %CreateRoomButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var settings_overlay: SettingsPanel = %SettingsOverlay


func _ready() -> void:
	# The menu is where every mode lands on the way out, so it is the one place
	# that can be sure the cursor should be free.
	MouseLock.release_all()
	_apply_palette()
	play_button.pressed.connect(_on_play_pressed)
	office_button.pressed.connect(_on_office_pressed)
	create_room_button.pressed.connect(_on_create_room_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


## Restyle from Palette at load rather than in the scene file.
##
## The scene was authored in the teal the port had drifted to, and colours
## written into a .tscn are invisible to a palette change -- which is how the
## drift happened. Doing it here means the menu, the settings overlay and the
## pause screen all move together when Palette does.
func _apply_palette() -> void:
	var background := get_node_or_null("Background") as ColorRect
	if background != null:
		background.color = Palette.BACKDROP
	var title := get_node_or_null("TitleLabel") as Label
	if title != null:
		title.add_theme_color_override("font_color", Palette.INK)
	var subtitle := get_node_or_null("SubtitleLabel") as Label
	if subtitle != null:
		subtitle.add_theme_color_override("font_color", Palette.AMBER)
	var panel := get_node_or_null("ButtonPanel") as PanelContainer
	if panel != null:
		panel.add_theme_stylebox_override("panel", Palette.panel_box())
	# PLAY and OFFICE MODE are the two things you can actually do, so they are
	# the primaries; everything else is secondary or waiting on a backend.
	for path in ["ButtonPanel/ButtonBox/PlayButton", "ButtonPanel/ButtonBox/OfficeButton"]:
		var button := get_node_or_null(path) as Button
		if button != null:
			Palette.style_button(button, true)
	for path in ["ButtonPanel/ButtonBox/CreateRoomButton",
			"ButtonPanel/ButtonBox/JoinRoomButton",
			"ButtonPanel/ButtonBox/SettingsButton",
			"ButtonPanel/ButtonBox/QuitButton"]:
		var button := get_node_or_null(path) as Button
		if button != null:
			Palette.style_button(button, false)
	for path in ["ButtonPanel/ButtonBox/OfficeCaption",
			"ButtonPanel/ButtonBox/CreateRoomCaption",
			"ButtonPanel/ButtonBox/JoinRoomCaption"]:
		var caption := get_node_or_null(path) as Label
		if caption != null:
			caption.add_theme_color_override("font_color", Palette.MUTED)


## Both play buttons open a ROOM now, rather than a scene.
##
## Singleplayer is a room with one player in it, hosted locally with no
## transport attached -- so the path a run takes to start is already the path a
## multiplayer run will take. When these become CREATE ROOM and JOIN ROOM,
## nothing past this point changes: a joined room fills the same fields from
## the host instead of from create_local.
func _on_play_pressed() -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	get_tree().change_scene_to_file("res://scenes/room_lobby.tscn")


## Office Mode is a separate, self-contained shift — it shares no state with a
## Last Route run (see MIGRATION.md) — but it still stages through a room, so
## there is one way into the game rather than two.
func _on_office_pressed() -> void:
	RoomState.create_local(RoomState.Mode.OFFICE)
	get_tree().change_scene_to_file("res://scenes/room_lobby.tscn")


## CREATE ROOM does exactly what PLAY does. It is enabled now because opening
## a room never needed a backend -- only having someone else JOIN one does.
func _on_create_room_pressed() -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	get_tree().change_scene_to_file("res://scenes/room_lobby.tscn")


func _on_settings_pressed() -> void:
	settings_overlay.open()


func _on_quit_pressed() -> void:
	get_tree().quit()
