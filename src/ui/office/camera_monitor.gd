class_name CameraMonitor
extends Control

## The raise-able camera monitor: one feed at a time out of
## OfficeConfig.CAMERAS, a button bank to switch between them, and a static
## burst on every switch.
##
## Structure and behaviour adapted from the Cupcakes Framework's `camera.gd`
## and `tablet_manager.gd` (MIT, © Oplexitie — see
## third_party/cupcakes-framework/): the feed/button arrays kept in sync by
## index, switching that refuses to re-select the current feed, and a static
## burst fired on both switch and raise. Changed from the original: feed
## contents are driven by OfficeSimulation rather than a per-room occupancy
## array written by the framework's own AI, and the static burst is a timed
## overlay instead of an AnimationTree one-shot (no animation assets yet).

signal camera_selected(camera_id: String)

const STATIC_DURATION := 0.22

var simulation: OfficeSimulation

var _static_remaining := 0.0
var _buttons: Array[Button] = []

@onready var _static_overlay: ColorRect = %StaticOverlay
@onready var _room_label: Label = %RoomLabel
@onready var _signal_label: Label = %SignalLabel
@onready var _connections_label: Label = %ConnectionsLabel
@onready var _status_label: Label = %FeedStatusLabel
@onready var _feed_body: ColorRect = %FeedBody
@onready var _button_bank: GridContainer = %CameraButtons


func _ready() -> void:
	for index in OfficeConfig.CAMERAS.size():
		var camera_id: String = OfficeConfig.CAMERAS[index]
		var button := Button.new()
		button.text = "%d" % (index + 1)
		button.custom_minimum_size = Vector2(22, 14)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_camera_button_pressed.bind(camera_id))
		_button_bank.add_child(button)
		_buttons.append(button)
	_static_overlay.color.a = 0.0


func _on_camera_button_pressed(camera_id: String) -> void:
	select(camera_id)


## Refuses a no-op re-select of the live feed, matching the framework's
## `switch_feed` guard — otherwise every click would re-fire the static.
func select(camera_id: String) -> void:
	if simulation == null or simulation.current_camera == camera_id:
		return
	if simulation.select_camera(camera_id):
		play_static()
		camera_selected.emit(camera_id)


func select_by_index(index: int) -> void:
	if index < 0 or index >= OfficeConfig.CAMERAS.size():
		return
	select(OfficeConfig.CAMERAS[index])


func play_static() -> void:
	_static_remaining = STATIC_DURATION


func _process(delta: float) -> void:
	if _static_remaining > 0.0:
		_static_remaining = maxf(0.0, _static_remaining - delta)
	_static_overlay.color.a = (_static_remaining / STATIC_DURATION) * 0.85

	if simulation == null:
		return
	_refresh_feed()


func _refresh_feed() -> void:
	var camera_id := simulation.current_camera
	for index in _buttons.size():
		var id: String = OfficeConfig.CAMERAS[index]
		# The live feed's own button is disabled, as in the framework — it
		# doubles as the "you are here" indicator.
		_buttons[index].disabled = id == camera_id
		_buttons[index].modulate = Color(1, 0.45, 0.45) if simulation.corrupted_cameras.has(id) else Color.WHITE

	var view = simulation.camera_view(camera_id)
	_room_label.text = "%s  //  %s" % [camera_id.to_upper(), view["room"] if view else "?"]

	if simulation.blackout_timer > 0.0:
		_status_label.text = "SIGNAL LOST // REBOOTING %.1fS" % simulation.blackout_timer
		_signal_label.text = ""
		_connections_label.text = ""
		_feed_body.color = Color(0.02, 0.02, 0.03)
		return
	if simulation.corrupted_cameras.has(camera_id):
		_status_label.text = "FEED CORRUPTED // REBOOT CAMERAS"
		_signal_label.text = ""
		_connections_label.text = ""
		_feed_body.color = Color(0.08, 0.03, 0.04)
		return

	_status_label.text = ""
	_feed_body.color = view["accent"].darkened(0.55) if view else Color(0.05, 0.06, 0.07)

	var visible_signals := simulation.camera_signals(camera_id)
	if visible_signals.is_empty():
		_signal_label.text = "NO SIGNAL DETECTED"
		_signal_label.modulate = Color(0.5, 0.6, 0.6)
	else:
		var names: Array = []
		for id in visible_signals:
			names.append(String(simulation.threats[id]["label"]))
		_signal_label.text = " / ".join(names)
		_signal_label.modulate = simulation.threats[visible_signals[0]]["color"]

	_connections_label.text = "LINKS: %s" % " ".join(simulation.camera_connections(camera_id))
