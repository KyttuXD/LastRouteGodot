extends Control

## Startup screen.
##
## Every play button opens a ROOM and lands on staging, including the solo
## ones. Singleplayer is a room with one player in it, hosted locally with no
## transport attached, so the route a run takes to start is already the route a
## multiplayer run will take -- see src/autoload/room_state.gd.
##
## That is what makes PLAY becoming CREATE ROOM a rename rather than a rewrite
## when there is a backend to join through.
##
## There is ONE way in. Office Mode is not a second front door -- it is a mode,
## picked in staging alongside DEFAULT and HIDE & SEEK, so the place you choose
## what to play is the place that shows you all of it. CREATE ROOM and JOIN
## ROOM are absent for the same reason: PLAY already opens a room, and a second
## button doing the same thing beside a third that cannot work is three
## questions where there was none.

@onready var play_button: Button = %PlayButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var settings_overlay: SettingsPanel = %SettingsOverlay


func _ready() -> void:
	# The menu is where every mode lands on the way out, so it is the one place
	# that can be sure the cursor should be free.
	MouseLock.release_all()
	_apply_palette()
	play_button.pressed.connect(_on_play_pressed)
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
	var panel := get_node_or_null("ButtonPanel") as PanelContainer
	if panel != null:
		panel.add_theme_stylebox_override("panel", Palette.panel_box())
	# PLAY and OFFICE MODE are the two things you can actually do, so they are
	# the primaries; everything else is secondary or waiting on a backend.
	for path in ["ButtonPanel/ButtonBox/PlayButton"]:
		var button := get_node_or_null(path) as Button
		if button != null:
			Palette.style_button(button, true)
	for path in ["ButtonPanel/ButtonBox/SettingsButton",
			"ButtonPanel/ButtonBox/QuitButton"]:
		var button := get_node_or_null(path) as Button
		if button != null:
			Palette.style_button(button, false)


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


func _on_settings_pressed() -> void:
	settings_overlay.open()


func _on_quit_pressed() -> void:
	get_tree().quit()
