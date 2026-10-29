class_name RouteLoadingScreen
extends Control

## Shared route loading surface.
##
## As the current scene it performs Godot's threaded PackedScene/resource load.
## The same scene is also instanced over Main3D with `auto_start = false`, where
## it stays opaque while a joining guest waits for the host's authoritative
## floor snapshot. That second use is important: a generated placeholder may
## exist underneath, but it is never presented as playable state.

const SIGNAL_BACKDROP_SCRIPT := preload("res://src/ui/signal_backdrop.gd")
const MIN_VISIBLE_SECONDS := 0.65

@export var auto_start := false

var _target_path := ""
var _elapsed := 0.0
var _thread_loaded := false
var _finishing := false

var _phase: Label
var _seed: Label
var _configuration: Label
var _progress: ProgressBar
var _status: Label
var _return_button: Button
var _leave_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_set_room_readout()
	if auto_start:
		WorldAudioGate.hold("route_loading_%d" % get_instance_id())
		_begin_threaded_load()
	else:
		show_building_floor()


## The pre-route loading scene is freed by the scene change into the route (it is never dismissed): the world fades in from here.
func _exit_tree() -> void:
	WorldAudioGate.release("route_loading_%d" % get_instance_id())


func _process(delta: float) -> void:
	if not auto_start or _finishing or _target_path.is_empty():
		return
	_elapsed += delta
	var progress := []
	var state := ResourceLoader.load_threaded_get_status(_target_path, progress)
	if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		var amount := float(progress[0]) if not progress.is_empty() else 0.0
		_set_phase("LOADING ROUTE RESOURCES", amount * 0.9, false)
	elif state == ResourceLoader.THREAD_LOAD_LOADED:
		_thread_loaded = true
		_set_phase("ROUTE RESOURCES READY", 0.94, false)
		if _elapsed >= MIN_VISIBLE_SECONDS:
			_finishing = true
			call_deferred("_open_loaded_route")
	elif state == ResourceLoader.THREAD_LOAD_FAILED \
			or state == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_fail_load("ROUTE RESOURCE LOAD FAILED")


func show_building_floor() -> void:
	visible = true
	WorldAudioGate.hold("route_loading_%d" % get_instance_id())   # the world stays silent behind this screen
	set_process(true)
	_set_room_readout()
	_set_phase(("BUILDING FACILITY FROM ROUTE SIGNAL"), 0.96, false)


func show_waiting_for_snapshot() -> void:
	visible = true
	WorldAudioGate.hold("route_loading_%d" % get_instance_id())   # the world stays silent behind this screen
	set_process(true)
	_set_room_readout()
	_set_phase("WAITING FOR HOST FLOOR SNAPSHOT", 1.0, true)


func show_snapshot_retry(message: String) -> void:
	visible = true
	WorldAudioGate.hold("route_loading_%d" % get_instance_id())   # the world stays silent behind this screen
	set_process(true)
	_set_phase("HOST SNAPSHOT REJECTED // RETRYING", 1.0, true)
	_status.text = message.to_upper()
	_status.add_theme_color_override("font_color", Palette.ALERT)


## A joining guest's sync step (RouteSyncGate): "SYNCING ROUTE 3/5 // NEARBY FACILITY".
func show_sync_step(index: int, total: int) -> void:
	visible = true
	WorldAudioGate.hold("route_loading_%d" % get_instance_id())   # the world stays silent behind this screen
	set_process(true)
	_set_room_readout()
	_set_phase(RouteSyncGate.label(index), float(index) / float(maxi(total, 1)), false)


## Past RouteSyncGate.TIMEOUT_SECONDS: the sync keeps trying, and the player may give up to the menu.
func show_sync_stuck() -> void:
	_status.text = "STILL SYNCING // THE HOST IS SLOW TO ANSWER"
	_status.add_theme_color_override("font_color", Palette.ALERT)
	_leave_button.visible = true


func dismiss() -> void:
	visible = false
	WorldAudioGate.release("route_loading_%d" % get_instance_id())   # fades the world in over WorldAudioGate.FADE_SECONDS
	set_process(false)
	if _leave_button != null:
		_leave_button.visible = false


func _begin_threaded_load() -> void:
	_target_path = RoomState.session_scene_path()
	if _target_path.is_empty() or _target_path == scene_file_path:
		_fail_load("NO VALID ROUTE SCENE WAS SELECTED")
		return
	_set_phase("OPENING ROUTE SIGNAL", 0.02, false)
	var error := ResourceLoader.load_threaded_request(_target_path, "", false,
		ResourceLoader.CACHE_MODE_REUSE)
	if error != OK:
		_fail_load("COULD NOT QUEUE ROUTE RESOURCES // ERROR %d" % error)


func _open_loaded_route() -> void:
	if not _thread_loaded:
		return
	_set_phase(("BUILDING FACILITY FROM ROUTE SIGNAL"), 1.0, false)
	# Give the final phase one frame on screen. Instantiating Main3D then builds
	# its procedural facility synchronously; this remains the last visible frame
	# until that work is complete.
	await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(_target_path) as PackedScene
	if packed == null:
		_fail_load("THE ROUTE SCENE COULD NOT BE OPENED")
		return
	if XRFade.active(get_tree()) != null:
		XRFade.change_scene(get_tree(), packed)   # fade the headset to black first
		return
	var error := get_tree().change_scene_to_packed(packed)
	if error != OK:
		_fail_load("THE ROUTE SCENE COULD NOT START // ERROR %d" % error)


func _fail_load(message: String) -> void:
	_finishing = true
	_status.text = message
	_status.add_theme_color_override("font_color", Palette.ALERT)
	_phase.text = "ROUTE SIGNAL LOST"
	_progress.indeterminate = false
	_progress.value = 0.0
	_return_button.visible = true


func _return_to_staging() -> void:
	if RoomState.online and RoomState.is_host and RoomState.session_active:
		RoomState.end_session("ROUTE LOAD FAILED // RETURNED TO STAGING")
		return
	RoomState.session_active = false
	RoomState.status_message = "ROUTE LOAD FAILED // RETURNED TO STAGING"
	XRFade.change_scene(get_tree(), "res://scenes/room_lobby.tscn")


func _leave_to_menu() -> void:
	RoomState.leave_network()
	RoomState.status_message = "LEFT WHILE SYNCING THE ROUTE"
	XRFade.change_scene(get_tree(), RoomState.menu_scene_path())


func _set_phase(message: String, amount: float, indeterminate: bool) -> void:
	_phase.text = message
	_progress.indeterminate = indeterminate
	_progress.value = clampf(amount, 0.0, 1.0) * 100.0
	_status.text = "SIGNAL TRANSFER IN PROGRESS" if indeterminate \
		else "%d%% // %s" % [roundi(_progress.value), message]
	_status.add_theme_color_override("font_color", Palette.MUTED)


func _set_room_readout() -> void:
	if _seed == null:
		return
	_seed.text = RoomState.seed_text if not RoomState.seed_text.is_empty() \
		else "ROUTE SIGNAL UNASSIGNED"
	var scale := String(RoomState.SCALE_LABELS.get(RoomState.map_scale, "STANDARD"))
	var difficulty := String(RoomState.DIFFICULTY_LABELS.get(RoomState.difficulty,
		"STANDARD"))
	_configuration.text = "%s // %s // %s" % [RoomState.mode_label(), scale, difficulty]


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
	panel.name = "LoadingPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -170
	panel.offset_top = -64
	panel.offset_right = 170
	panel.offset_bottom = 64
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override("panel",
		Palette.panel_box(Palette.PANEL, Color("563041"), 13))
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)

	column.add_child(_label("ROUTE SIGNAL // TRANSFER", Palette.AMBER, 7,
		"LoadingKicker"))
	var title := _label("BUILDING ROUTE", Palette.INK, 21, "LoadingTitle")
	title.add_theme_font_override("font", Palette.title_font())
	column.add_child(title)

	var readout := PanelContainer.new()
	readout.add_theme_stylebox_override("panel",
		Palette.panel_box(Palette.INSET, Palette.ACCENT_DEEP, 6))
	column.add_child(readout)
	var readout_stack := VBoxContainer.new()
	readout_stack.add_theme_constant_override("separation", 1)
	readout.add_child(readout_stack)
	_seed = _label("ROUTE SIGNAL UNASSIGNED", Palette.INK, 7, "RouteSeedLabel")
	_seed.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	readout_stack.add_child(_seed)
	_configuration = _label("DEFAULT // STANDARD // STANDARD", Palette.MUTED, 6,
		"RouteConfigurationLabel")
	readout_stack.add_child(_configuration)

	_progress = ProgressBar.new()
	_progress.name = "RouteLoadProgress"
	_progress.custom_minimum_size = Vector2(0, 8)
	_progress.show_percentage = false
	_progress.add_theme_stylebox_override("background",
		Palette.panel_box(Palette.INSET, Palette.PANEL_EDGE, 0))
	_progress.add_theme_stylebox_override("fill",
		Palette.panel_box(Palette.ACCENT, Palette.ACCENT_EDGE, 0))
	column.add_child(_progress)

	_phase = _label("OPENING ROUTE SIGNAL", Palette.BODY, 7, "RouteLoadPhase")
	column.add_child(_phase)
	_status = _label("0% // OPENING ROUTE SIGNAL", Palette.MUTED, 6,
		"RouteLoadStatus")
	column.add_child(_status)

	_return_button = Button.new()
	_return_button.name = "ReturnToStagingButton"
	_return_button.text = "RETURN TO STAGING"
	_return_button.visible = false
	_return_button.add_theme_font_size_override("font_size", 7)
	Palette.style_button(_return_button, false)
	_return_button.pressed.connect(_return_to_staging)
	column.add_child(_return_button)

	_leave_button = Button.new()
	_leave_button.name = "SyncLeaveButton"
	_leave_button.text = "STILL SYNCING // LEAVE"
	_leave_button.visible = false
	_leave_button.add_theme_font_size_override("font_size", 7)
	Palette.style_button(_leave_button, false)
	_leave_button.pressed.connect(_leave_to_menu)
	column.add_child(_leave_button)


func _label(text: String, color: Color, size: int, node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	return label
