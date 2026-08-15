extends Control

## Startup screen. PLAY is the only functional way to start a game right now
## — it launches a solo run directly. CREATE ROOM / JOIN ROOM stay disabled
## in the scene itself: no multiplayer backend exists yet (MIGRATION.md
## milestone 9 is unstarted), so there is nothing for them to call.

@onready var play_button: Button = %PlayButton
@onready var office_button: Button = %OfficeButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var settings_overlay: SettingsPanel = %SettingsOverlay


func _ready() -> void:
	_apply_palette()
	play_button.pressed.connect(_on_play_pressed)
	office_button.pressed.connect(_on_office_pressed)
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


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_3d.tscn")


## Office Mode is a separate, self-contained shift — it shares no state with
## a Last Route run, so it just swaps scenes (see MIGRATION.md).
func _on_office_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/office_3d.tscn")


func _on_settings_pressed() -> void:
	settings_overlay.open()


func _on_quit_pressed() -> void:
	get_tree().quit()
