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
@onready var update_button: Button = %UpdateButton
@onready var version_label: Label = %VersionLabel
@onready var settings_overlay: SettingsPanel = %SettingsOverlay


func _ready() -> void:
	# The menu is where every mode lands on the way out, so it is the one place
	# that can be sure the cursor should be free.
	MouseLock.release_all()
	_apply_palette()
	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	update_button.pressed.connect(_on_update_pressed)
	UpdateManager.update_available.connect(_on_update_available)
	UpdateManager.status_changed.connect(_on_update_status)
	UpdateManager.check_finished.connect(_on_update_check_finished)
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
		background.color = Palette.BACKDROP
	var title := get_node_or_null("TitleLabel") as Label
	if title != null:
		Palette.style_title(title)
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
			"ButtonPanel/ButtonBox/UpdateButton",
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
		play_button.text = "PLAY"
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
