class_name BootLoadingScreen
extends Control

## Startup/update gate shown before the main menu.
##
## The menu is loaded on a worker thread while the updater checks the primary
## backend. Exported debug builds do not pass this screen until that check is
## successful. A discovered desktop required/debug update continues on the
## dedicated in-progress screen after the menu, so the running window stays
## visible through download, verify, and staging.

const SIGNAL_BACKDROP_SCRIPT := preload("res://src/ui/signal_backdrop.gd")
const MAIN_MENU_PATH := "res://scenes/game_hub.tscn"
const MIN_VISIBLE_SECONDS := 0.8

@export var auto_start := true

var _elapsed := 0.0
var _menu_loaded := false
var _may_open_menu := false
var _opening_menu := false
var _update_discovered := false

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
	_begin_menu_load()
	if "--offline" in OS.get_cmdline_user_args():
		Backend.enable_offline_mode()
		UpdateManager.enable_offline_mode()
		_allow_main_menu("OFFLINE MODE")
		return
	_sync_update_state()


func _process(delta: float) -> void:
	_elapsed += delta
	_poll_menu_load()
	if _may_open_menu and _menu_loaded and _elapsed >= MIN_VISIBLE_SECONDS \
			and not _opening_menu:
		_opening_menu = true
		_open_main_menu.call_deferred()


func _begin_menu_load() -> void:
	var error := ResourceLoader.load_threaded_request(MAIN_MENU_PATH, "", false,
		ResourceLoader.CACHE_MODE_REUSE)
	if error != OK:
		_show_terminal_error("MAIN MENU LOAD COULD NOT START // ERROR %d" % error)
		return
	_set_state("INITIALIZING ROUTE SYSTEM", "LOADING GAME DATA", 0.08, true)


func _poll_menu_load() -> void:
	if _menu_loaded or _opening_menu:
		return
	var progress := []
	var state := ResourceLoader.load_threaded_get_status(MAIN_MENU_PATH, progress)
	if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if not UpdateManager.checking and not UpdateManager.downloading \
				and not _update_discovered:
			var amount := float(progress[0]) if not progress.is_empty() else 0.0
			_set_progress(0.08 + amount * 0.72, false)
	elif state == ResourceLoader.THREAD_LOAD_LOADED:
		_menu_loaded = true
		if _may_open_menu:
			_set_state("ROUTE SYSTEM READY", "OPENING MAIN MENU", 1.0, false)
	elif state == ResourceLoader.THREAD_LOAD_FAILED \
			or state == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_show_terminal_error("MAIN MENU RESOURCES COULD NOT BE LOADED")


const UPDATE_SCREEN_PATH := "res://scenes/update_progress.tscn"


## An update was found: the hub and the games never load; the update screen takes over until it is installed.
func _open_update_screen() -> void:
	# no blocking screen: the update downloads in the background (UpdateBadge) and applies on quit / RESTART NOW
	_allow_main_menu("UPDATE AVAILABLE // DOWNLOADING IN THE BACKGROUND")


func _handoff_desktop_update() -> bool:
	return UpdateManager.uses_in_progress_screen() \
		and (UpdateManager.downloading or UpdateManager.preparing \
			or UpdateManager.installing or UpdateManager.ready_to_install \
			or not UpdateManager.available.is_empty())


func _sync_update_state() -> void:
	if UpdateManager.is_dev_build() and not UpdateManager.available.is_empty():
		_allow_main_menu("DEV BUILD // UPDATE AVAILABLE")
		return
	if _handoff_desktop_update():
		_update_discovered = true
		_open_update_screen()
		return
	if UpdateManager.installing:
		_on_update_status(UpdateManager.status_message)
		return
	if UpdateManager.downloading:
		_update_discovered = true
		_on_update_status(UpdateManager.status_message)
		return
	if UpdateManager.ready_to_install:
		_update_discovered = true
		_on_update_ready(UpdateManager.staged_path)
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
	if UpdateManager.is_dev_build():
		return   # _on_update_check_finished shows the dev notice
	_update_discovered = true
	var revision := String(update.get("revision", "")).strip_edges()
	var identity := revision.left(8).to_upper() if not revision.is_empty() \
		else String(update.get("version", ""))
	_set_state("UPDATE FOUND", "PREPARING UPDATE %s" % identity, 0.18, true)
	if _handoff_desktop_update():
		_open_update_screen()


var _dev_notice := false


## A dev (unstamped) build hears about the published build but is never held: notice + CONTINUE (online).
func _show_dev_notice() -> void:
	_dev_notice = true
	_may_open_menu = false
	_set_state("UPDATE AVAILABLE (BUILD %d)" % int(UpdateManager.available.get("build", 0)),
		"DEV BUILD // NOT UPDATED AUTOMATICALLY", 1.0, false)
	_retry_button.visible = false
	_continue_button.text = "CONTINUE"
	_continue_button.visible = true
	_continue_button.grab_focus.call_deferred()


func _on_update_check_finished(success: bool, update_needed: bool) -> void:
	if update_needed and UpdateManager.is_dev_build():
		_allow_main_menu("DEV BUILD // UPDATE AVAILABLE")   # the badge says so
		return
	if update_needed:
		_update_discovered = true
		if not UpdateManager.downloading and not UpdateManager.preparing \
				and not UpdateManager.installing and not UpdateManager.ready_to_install:
			UpdateManager.download_update()
		if _handoff_desktop_update():
			_open_update_screen()
		return
	if success:
		_allow_main_menu("BUILD IS UP TO DATE")
		return
	# server unreachable or the check timed out (UpdateManager.MANIFEST_TIMEOUT_SECONDS): play offline, never block
	UpdateManager.enable_offline_mode()
	_allow_main_menu("UPDATE SERVICE UNAVAILABLE // STARTING OFFLINE")


func _on_update_status(message: String) -> void:
	if message.is_empty():
		return
	var upper := message.to_upper()
	_status.text = upper
	if UpdateManager.is_failure_status(upper):
		if _update_discovered or not UpdateManager.available.is_empty():
			_allow_main_menu("UPDATE DOWNLOAD FAILED // PLAYING THIS BUILD")   # the badge retries later; never blocks
		else:
			_show_retry(upper, false)
	elif upper.contains("CHECKING"):
		_phase.text = "CHECKING FOR UPDATES"
		_set_progress(0.12, true)
	elif upper.contains("DOWNLOADING"):
		_phase.text = "DOWNLOADING UPDATE"
	elif upper.contains("VERIFYING"):
		_phase.text = "VERIFYING UPDATE"
		_set_progress(0.86, true)
	elif upper.contains("UNPACKING"):
		_phase.text = "PREPARING UPDATE"
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


func _on_update_ready(_path: String) -> void:
	_update_discovered = true
	if _handoff_desktop_update():
		_open_update_screen()
		return
	_set_state("APPLYING UPDATE", "INSTALLING UPDATE // RESTARTING", 1.0, true)
	if not UpdateManager.installing and UpdateManager._should_install_automatically():
		UpdateManager.install_update.call_deferred()


func _retry_update() -> void:
	_retry_button.visible = false
	_continue_button.visible = false
	_update_discovered = false
	_set_state("CHECKING FOR UPDATES", "CONTACTING PRIMARY SERVER", 0.12, true)
	if not UpdateManager.available.is_empty():
		UpdateManager.download_update(true)
	else:
		UpdateManager.check()


func _continue_offline() -> void:
	if _dev_notice:
		_allow_main_menu("DEV BUILD // UPDATE SKIPPED")
		return
	Backend.enable_offline_mode()
	UpdateManager.enable_offline_mode()
	_allow_main_menu("UPDATE DEFERRED // STARTING OFFLINE")


func _allow_main_menu(message: String) -> void:
	_may_open_menu = true
	_retry_button.visible = false
	_continue_button.visible = false
	_set_state("ROUTE SYSTEM READY", message, 1.0, false)


func _show_retry(message: String, allow_continue: bool) -> void:
	_may_open_menu = false
	_phase.text = "UPDATE INTERRUPTED"
	_status.text = message
	_status.add_theme_color_override("font_color", Palette.ALERT)
	_set_progress(0.0, false)
	_retry_button.visible = true
	# Even mandatory-update debug builds must retain a deliberate offline test
	# path. It never opens a directory room and is visibly separate from online.
	_continue_button.visible = true


func _show_terminal_error(message: String) -> void:
	_may_open_menu = false
	_opening_menu = true
	_phase.text = "STARTUP FAILED"
	_status.text = message
	_status.add_theme_color_override("font_color", Palette.ALERT)
	_set_progress(0.0, false)


func _open_main_menu() -> void:
	var packed := ResourceLoader.load_threaded_get(MAIN_MENU_PATH) as PackedScene
	if packed == null:
		_show_terminal_error("MAIN MENU RESOURCES COULD NOT BE OPENED")
		return
	var error := get_tree().change_scene_to_packed(packed)
	if error != OK:
		_show_terminal_error("MAIN MENU COULD NOT START // ERROR %d" % error)


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
	panel.name = "BootLoadingPanel"
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
	column.add_child(_label("LAB SYSTEM // STARTUP", Palette.AMBER, 7,
		"BootKicker"))
	var title := _label("KYTTU'S LAB", Palette.INK, 18, "BootTitle")
	title.add_theme_font_override("font", Palette.title_font())
	column.add_child(title)

	_progress = ProgressBar.new()
	_progress.name = "BootProgress"
	_progress.custom_minimum_size = Vector2(0, 8)
	_progress.show_percentage = false
	_progress.add_theme_stylebox_override("background",
		Palette.panel_box(Palette.INSET, Palette.PANEL_EDGE, 0))
	_progress.add_theme_stylebox_override("fill",
		Palette.panel_box(Palette.ACCENT, Palette.ACCENT_EDGE, 0))
	column.add_child(_progress)

	_phase = _label("INITIALIZING ROUTE SYSTEM", Palette.BODY, 7, "BootPhase")
	column.add_child(_phase)
	_status = _label("LOADING GAME DATA", Palette.MUTED, 6, "BootStatus")
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
