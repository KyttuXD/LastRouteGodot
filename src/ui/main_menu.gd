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
	play_button.pressed.connect(_on_play_pressed)
	office_button.pressed.connect(_on_office_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


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
