class_name UpdateProgressScreen
extends Control

## Dedicated desktop update-in-progress surface.
##
## Required/debug updates switch here from the main menu so the running process
## stays visible through download, verify, and staging. The native helper only
## starts after that staged tree is ready to replace the current install.

const SIGNAL_BACKDROP_SCRIPT := preload("res://src/ui/signal_backdrop.gd")
const MIN_HANDOFF_SECONDS := 0.8

@export var auto_start := true

var _elapsed := 0.0
var _pending_install := false
var _handoff_started := false

var _phase: Label
var _status: Label
var _progress: ProgressBar
var _retry_button: Button
var _continue_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	if not auto_start:
		set_process(false)
		return
	MouseLock.release_all()
	UpdateManager.update_available.connect(_on_update_available)
	UpdateManager.status_changed.connect(_on_update_status)
	UpdateManager.check_finished.connect(_on_update_check_finished)
	UpdateManager.download_progress.connect(_on_download_progress)
	UpdateManager.update_ready.connect(_on_update_ready)
	_sync_update_state()


func _process(delta: float) -> void:
	_elapsed += delta
	if _pending_install and _elapsed >= MIN_HANDOFF_SECONDS:
		_start_install()


func _sync_update_state() -> void:
	if UpdateManager.installing:
		_on_update_status(UpdateManager.status_message)
		return
	if UpdateManager.downloading or UpdateManager.preparing:
		_on_update_status(UpdateManager.status_message)
		return
	if UpdateManager.ready_to_install:
		_on_update_ready(UpdateManager.staged_path)
		return
	if not UpdateManager.available.is_empty():
		_on_update_available(UpdateManager.available)
		if not UpdateManager.downloading and not UpdateManager.preparing \
				and not UpdateManager.installing:
			UpdateManager.download_update()
		return
	if UpdateManager.checking:
		_set_state("CHECKING FOR UPDATES", "CONTACTING PRIMARY SERVER", 0.12, true)
		return
	if UpdateManager.check_complete:
		_on_update_check_finished(UpdateManager.check_succeeded,
			not UpdateManager.available.is_empty())
		return
	_set_state("CHECKING FOR UPDATES", "CONTACTING PRIMARY SERVER", 0.12, true)
	UpdateManager.check()


func _on_update_available(update: Dictionary) -> void:
	var revision := String(update.get("revision", "")).strip_edges()
	var identity := revision.left(8).to_upper() if not revision.is_empty() \
		else String(update.get("version", ""))
	_set_state("UPDATE FOUND", "PREPARING UPDATE %s" % identity, 0.18, true)


func _on_update_check_finished(success: bool, update_needed: bool) -> void:
	if update_needed:
		if not UpdateManager.downloading and not UpdateManager.preparing \
				and not UpdateManager.installing and not UpdateManager.ready_to_install:
			UpdateManager.download_update()
		return
	if success:
		_return_to_menu("BUILD IS UP TO DATE")
		return
	if UpdateManager.available.is_empty():
		# no update known and the server is unreachable: nothing to hold the player for
		UpdateManager.enable_offline_mode()
		_return_to_menu("UPDATE SERVICE UNAVAILABLE // STARTING OFFLINE")
		return
	_show_retry(UpdateManager.status_message if not UpdateManager.status_message.is_empty() \
		else "UPDATE CHECK REQUIRED")


func _on_update_status(message: String) -> void:
	if message.is_empty():
		return
	var upper := message.to_upper()
	_status.text = upper
	if UpdateManager.is_failure_status(upper):
		_show_retry(upper)
	elif upper.contains("CHECKING"):
		_phase.text = "CHECKING FOR UPDATES"
		_set_progress(0.12, true)
	elif upper.contains("DOWNLOADING"):
		_phase.text = "DOWNLOADING UPDATE"
	elif upper.contains("VERIFYING"):
		_phase.text = "VERIFYING UPDATE"
		_set_progress(0.86, true)
	elif upper.contains("UNPACKING") or upper.contains("PREPARING"):
		_phase.text = "STAGING UPDATE"
		_set_progress(0.92, true)
	elif upper.contains("INSTALL") or upper.contains("RESTART") \
			or upper.contains("REFRESHING"):
		_phase.text = "APPLYING UPDATE"
		_set_progress(1.0, true)


func _on_download_progress(received_bytes: int, total_bytes: int) -> void:
	_phase.text = "DOWNLOADING UPDATE"
	if total_bytes <= 0:
		_set_progress(0.25, true)
		_status.text = "DOWNLOADED %s" % _format_bytes(received_bytes)
		return
	var ratio := clampf(float(received_bytes) / float(total_bytes), 0.0, 1.0)
	_set_progress(0.18 + ratio * 0.62, false)
	_status.text = "%d%% // %s OF %s" % [roundi(ratio * 100.0),
		_format_bytes(received_bytes), _format_bytes(total_bytes)]


## Never silent: a staged update waits for the player to press INSTALL & RESTART.
func _on_update_ready(_path: String) -> void:
	_set_state("UPDATE READY", "UPDATE %s STAGED // INSTALL & RESTART WHEN READY" % String(UpdateManager.available.get("revision", "")).left(8).to_upper(), 1.0, false)
	_show_install_button()


var _install_button: Button


func _show_install_button() -> void:
	if _install_button == null:
		_install_button = Button.new()
		_install_button.name = "InstallUpdateButton"
		_install_button.text = "INSTALL & RESTART"
		Palette.style_button(_install_button, true)
		_install_button.pressed.connect(func() -> void:
			_install_button.visible = false
			_start_install())
		_retry_button.get_parent().add_child(_install_button)
		_retry_button.get_parent().move_child(_install_button, 0)
	_install_button.visible = true
	_continue_button.visible = false   # the update gate: no way past this screen but installing
	_install_button.grab_focus.call_deferred()


func _start_install() -> void:
	if _handoff_started or not UpdateManager.ready_to_install:
		return
	_handoff_started = true
	_pending_install = false
	_set_state("APPLYING UPDATE", "INSTALLING UPDATE // RESTARTING", 1.0, true)
	if not UpdateManager.installing:
		UpdateManager.install_update.call_deferred()


func _retry_update() -> void:
	_retry_button.visible = false
	_continue_button.visible = false
	_pending_install = false
	_handoff_started = false
	_elapsed = 0.0
	_set_state("CHECKING FOR UPDATES", "CONTACTING PRIMARY SERVER", 0.12, true)
	if not UpdateManager.available.is_empty():
		UpdateManager.download_update(true)
	else:
		UpdateManager.check()


func _continue_offline() -> void:
	Backend.enable_offline_mode()
	UpdateManager.enable_offline_mode()
	_return_to_menu("UPDATE DEFERRED // STARTING OFFLINE")


func _return_to_menu(_message: String) -> void:
	var error := get_tree().change_scene_to_file("res://scenes/game_hub.tscn")
	if error != OK:
		_show_retry("MAIN MENU COULD NOT OPEN // ERROR %d" % error)


func _show_retry(message: String) -> void:
	_pending_install = false
	_handoff_started = false
	_phase.text = "UPDATE INTERRUPTED"
	_status.text = message
	_status.add_theme_color_override("font_color", Palette.ALERT)
	_set_progress(0.0, false)
	_retry_button.visible = true
	_continue_button.visible = false   # stay here with RETRY; no skipping the update


func _set_state(phase_text: String, status_text: String, amount: float,
		indeterminate: bool) -> void:
	_phase.text = phase_text
	_status.text = status_text
	_status.add_theme_color_override("font_color", Palette.MUTED)
	_set_progress(amount, indeterminate)


func _set_progress(amount: float, indeterminate: bool) -> void:
	_progress.indeterminate = indeterminate
	_progress.value = clampf(amount, 0.0, 1.0) * 100.0


func _format_bytes(value: int) -> String:
	if value >= 1024 * 1024:
		return "%.1f MB" % (float(value) / float(1024 * 1024))
	if value >= 1024:
		return "%.1f KB" % (float(value) / 1024.0)
	return "%d B" % value


func _build_ui() -> void:
	var background := SIGNAL_BACKDROP_SCRIPT.new()
	background.name = "SignalBackdrop"
	background.pattern_strength = 0.82
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	for frame in [["OuterFrame", 6, Palette.PANEL_EDGE],
			["InnerFrame", 9, Color("46303c")]]:
		var border := Panel.new()
		border.name = frame[0]
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		border.set_anchors_preset(Control.PRESET_FULL_RECT)
		border.offset_left = frame[1]
		border.offset_top = frame[1]
		border.offset_right = -frame[1]
		border.offset_bottom = -frame[1]
		border.add_theme_stylebox_override("panel",
			Palette.panel_box(Color(0, 0, 0, 0), frame[2], 0))
		add_child(border)

	var panel := PanelContainer.new()
	panel.name = "UpdateProgressPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -145
	panel.offset_top = -48
	panel.offset_right = 145
	panel.offset_bottom = 48
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override("panel",
		Palette.panel_box(Palette.PANEL, Color("563041"), 11))
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	column.add_child(_label("LAB SYSTEM // UPDATE", Palette.AMBER, 7,
		"UpdateKicker"))
	var title := _label("KYTTU'S LAB", Palette.INK, 18, "UpdateTitle")
	title.add_theme_font_override("font", Palette.title_font())
	column.add_child(title)

	_progress = ProgressBar.new()
	_progress.name = "UpdateProgress"
	_progress.custom_minimum_size = Vector2(0, 8)
	_progress.show_percentage = false
	_progress.add_theme_stylebox_override("background",
		Palette.panel_box(Palette.INSET, Palette.PANEL_EDGE, 0))
	_progress.add_theme_stylebox_override("fill",
		Palette.panel_box(Palette.ACCENT, Palette.ACCENT_EDGE, 0))
	column.add_child(_progress)

	_phase = _label("CHECKING FOR UPDATES", Palette.BODY, 7, "UpdatePhase")
	column.add_child(_phase)
	_status = _label("CONTACTING PRIMARY SERVER", Palette.MUTED, 6, "UpdateStatus")
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_status)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 4)
	column.add_child(actions)
	_continue_button = Button.new()
	_continue_button.name = "ContinueOfflineButton"
	_continue_button.text = "CONTINUE OFFLINE"
	_continue_button.visible = false
	Palette.style_button(_continue_button, false)
	_continue_button.pressed.connect(_continue_offline)
	actions.add_child(_continue_button)
	_retry_button = Button.new()
	_retry_button.name = "RetryUpdateButton"
	_retry_button.text = "RETRY UPDATE"
	_retry_button.visible = false
	Palette.style_button(_retry_button, true)
	_retry_button.pressed.connect(_retry_update)
	actions.add_child(_retry_button)


func _label(text: String, color: Color, size: int, node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	return label
