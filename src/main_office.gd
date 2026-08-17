extends Control

## Office Mode's scene controller — the counterpart to src/main_3d.gd, but
## for a mode with no world, no movement and no hunters. It owns an
## OfficeSimulation (src/game/office/office_simulation.gd), forwards player
## input to its named controls, and reflects its state into the UI. The
## simulation is authoritative for everything; nothing here advances a timer
## or decides an outcome on its own.

## The office_* control shortcuts are GONE, not merely unbound.
##
## They shared physical keys with movement -- the left door was A, the vent was
## W, the emergency flash was E -- which was harmless while the player was
## pinned to a chair and unplayable once they could walk: crossing the room
## worked both doors. Every control is a switch in the world now, so there is
## nothing for a shortcut to duplicate.
##
## The rear flash keeps its key. It answers a timed prompt and has no switch to
## point at, and T collides with nothing.

var simulation: OfficeSimulation
var pause_menu: PauseMenu

# The office itself. This file drives it through one property, `can_move`,
# which is what let the 3D office replace the flat ColorRect one without this
# controller changing at all.
@onready var office_view: OfficeView3D = %OfficeView
@onready var monitor: CameraMonitor = %CameraMonitor

@onready var _power_bar: ProgressBar = %PowerBar
@onready var _power_label: Label = %PowerLabel
@onready var _usage_label: Label = %UsageLabel
@onready var _clock_label: Label = %ClockLabel
@onready var _event_label: Label = %EventLabel
@onready var _exposure_bar: ProgressBar = %ExposureBar
@onready var _systems_label: Label = %SystemsLabel

@onready var _control_bar: HBoxContainer = %ControlBar
@onready var _left_door_button: Button = %LeftDoorButton
@onready var _right_door_button: Button = %RightDoorButton
@onready var _desk_light_button: Button = %DeskLightButton
@onready var _vent_button: Button = %VentButton
@onready var _monitor_button: Button = %MonitorButton
@onready var _radio_button: Button = %RadioButton
@onready var _breaker_button: Button = %BreakerButton
@onready var _reboot_button: Button = %RebootButton
@onready var _flash_button: Button = %FlashButton

@onready var _rear_prompt: Panel = %RearPrompt
@onready var _rear_label: Label = %RearLabel
@onready var _gas_prompt: Panel = %GasPrompt
@onready var _gas_button: Button = %GasMaskButton
@onready var _gas_label: Label = %GasLabel
@onready var _parkour_panel: Panel = %ParkourPanel
@onready var _parkour_buttons: HBoxContainer = %ParkourButtons
@onready var _parkour_label: Label = %ParkourLabel
@onready var _end_panel: Panel = %EndPanel
@onready var _end_title: Label = %EndTitle
@onready var _end_cause: Label = %EndCause
@onready var _end_hint: Label = %EndHint


func _ready() -> void:
	_apply_header_typography()
	simulation = OfficeSimulation.new("OFFICE-%d" % randi())
	simulation.audio_cue.connect(_on_audio_cue)
	simulation.jumpscare.connect(func(threat_id: String) -> void:
		Sound.office_jumpscare(threat_id))
	Sound.queue_office_cue("shift")
	monitor.simulation = simulation
	# The view READS simulation state to show the doors, the desk lamp, the CRT
	# and the camera console. It never writes to it.
	office_view.simulation = simulation
	monitor.visible = false

	# Office Mode HOLDS ESC. It is singleplayer by design so nothing is waiting
	# on the player, and the whole mode is about not being able to step away --
	# a one-tap escape hatch would undercut the shift it is asking you to sit.
	pause_menu = PauseMenu.new()
	pause_menu.tap_to_pause = false
	pause_menu.abandon_label = "ABANDON SHIFT"
	pause_menu.abandon_warning = "This ends the shift with no credit and returns to the main menu."
	pause_menu.abandoned.connect(_on_abandoned)
	add_child(pause_menu)

	_left_door_button.pressed.connect(_toggle.bind("leftDoor"))
	_right_door_button.pressed.connect(_toggle.bind("rightDoor"))
	_desk_light_button.pressed.connect(_toggle.bind("deskLight"))
	_vent_button.pressed.connect(_toggle.bind("vent"))
	_monitor_button.pressed.connect(_toggle.bind("cameras"))
	_radio_button.pressed.connect(func() -> void: simulation.cycle_radio())
	_breaker_button.pressed.connect(func() -> void: simulation.reset_breaker())
	_reboot_button.pressed.connect(func() -> void: simulation.reboot_cameras())
	_flash_button.pressed.connect(func() -> void: simulation.trigger_emergency_flash())

	# Held, not clicked — the mask only helps while it's actually on your face.
	_gas_button.button_down.connect(func() -> void: simulation.set_gas_mask(true))
	_gas_button.button_up.connect(func() -> void: simulation.set_gas_mask(false))

	for position in 4:
		var button := Button.new()
		button.custom_minimum_size = Vector2(26, 20)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_parkour_node_pressed.bind(position))
		_parkour_buttons.add_child(button)

	_build_admin()
	# The controls are physical keys on the desk now (see office_view_3d's
	# control strip), so the on-screen row is hidden. Its Buttons stay in the
	# scene as the state holders _refresh already writes to; they are what the
	# keyboard shortcuts and the mode's own disable rules drive, and the desk
	# keys read the SIMULATION rather than these, so nothing depends on them
	# being visible.
	_control_bar.visible = false
	_end_panel.visible = false
	_refresh()


func _apply_header_typography() -> void:
	# Office has a different physical interface, but its screen-level readouts
	# still belong to the same archive system as staging, the route map and the
	# pause surface. The heavy face is reserved for the clock/camera/end headings
	# so dense status text remains legible at the 480x270 design resolution.
	Palette.style_title(_clock_label)
	Palette.style_title(_end_title)
	var camera_heading := get_node_or_null("CameraMonitor/RoomLabel") as Label
	if camera_heading != null:
		Palette.style_title(camera_heading)


func _toggle(control: String) -> void:
	simulation.toggle_control(control)
	if control == "cameras":
		_sync_monitor_visibility()


func _on_audio_cue(cue: String, pan: float, intensity: float) -> void:
	Sound.queue_office_cue(cue, pan, intensity)


## The monitor being up is simulation state (`monitor_open`), not a separate
## UI flag — Violet's blackout and Orange's sabotage can both force it down
## without the player touching anything, so the view always follows the sim.
func _sync_monitor_visibility() -> void:
	var raised := simulation.monitor_open
	if raised and not monitor.visible:
		monitor.play_static()
	monitor.visible = raised
	office_view.can_move = not raised


func _on_parkour_node_pressed(position: int) -> void:
	simulation.advance_gray_challenge(position)


func _unhandled_input(_event: InputEvent) -> void:
	if simulation == null or simulation.phase != OfficeSimulation.Phase.ACTIVE:
		if Input.is_action_just_pressed("interact") and simulation != null \
			and simulation.phase in [OfficeSimulation.Phase.LOST, OfficeSimulation.Phase.WON]:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return

	if Input.is_action_just_pressed("office_rear_flash"):
		simulation.answer_rear_threat()
	# Direct camera bank, only while the monitor is actually up.
	if simulation.monitor_open:
		for index in OfficeConfig.CAMERAS.size():
			if Input.is_action_just_pressed("office_camera_%d" % (index + 1)):
				monitor.select_by_index(index)


## Returns null outside a debug build, so nothing here exists in a release.
func _build_admin() -> void:
	AdminMenu.attach(self,
		func() -> String:
			return "ROOM %s  OFFICE\nPOWER %d%%  %02d:%02d ELAPSED\nAWAY %.1fs  CAM %s" % [
				RoomState.code, roundi(simulation.power),
				int(simulation.elapsed) / 60, int(simulation.elapsed) % 60,
				simulation.away_timer, simulation.current_camera],
		[
			{"label": "REFILL POWER", "action": func() -> void:
				simulation.power = 100.0},
			{"label": "SKIP TO 5 AM", "action": func() -> void:
				simulation.elapsed = simulation.shift_duration * (5.0 / 6.0)},
			{"label": "CLEAR FAULTS", "action": func() -> void:
				simulation.disabled_systems.clear()
				simulation.corrupted_cameras.clear()
				simulation.blackout_timer = 0.0},
		])


func _on_abandoned() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _process(delta: float) -> void:
	if simulation == null:
		return
	simulation.update(delta)
	_sync_monitor_visibility()
	_refresh()


func _refresh() -> void:
	_power_bar.value = simulation.power
	_power_label.text = "POWER %d%%" % roundi(simulation.power)
	_power_label.modulate = _power_color(simulation.power)
	_usage_label.text = "USAGE %s" % "|".repeat(simulation.usage)

	var remaining: float = maxf(0.0, simulation.shift_duration - simulation.elapsed)
	# Presented as a 12AM-6AM shift, the way the original frames its clock.
	var hour := int((simulation.elapsed / simulation.shift_duration) * 6.0)
	_clock_label.text = "%d AM   %02d:%02d LEFT" % [hour, int(remaining) / 60, int(remaining) % 60]

	_event_label.text = simulation.event if simulation.event_timer > 0.0 else ""
	_exposure_bar.value = simulation.exposure

	_left_door_button.button_pressed = simulation.left_door
	_right_door_button.button_pressed = simulation.right_door
	_desk_light_button.button_pressed = simulation.desk_light
	_vent_button.button_pressed = simulation.vent_sealed
	_monitor_button.button_pressed = simulation.monitor_open
	_radio_button.text = "RADIO %d" % simulation.radio_frequency
	_flash_button.disabled = not simulation.emergency_flash_ready

	_left_door_button.disabled = simulation.is_system_disabled("leftDoor")
	_right_door_button.disabled = simulation.is_system_disabled("rightDoor")
	_desk_light_button.disabled = simulation.is_system_disabled("deskLight")
	_vent_button.disabled = simulation.is_system_disabled("vent")
	_monitor_button.disabled = simulation.is_system_disabled("cameras")
	_radio_button.disabled = simulation.is_system_disabled("radio")

	_systems_label.text = "FAULT: %s" % " ".join(simulation.disabled_systems) if not simulation.disabled_systems.is_empty() else ""

	_rear_prompt.visible = simulation.rear_threat_timer > 0.0
	if _rear_prompt.visible:
		_rear_label.text = "BREATHING BEHIND YOU // [Q] FLASH  %.1f" % simulation.rear_threat_timer

	_gas_prompt.visible = simulation.gas_active
	if _gas_prompt.visible:
		_gas_label.text = "GAS LEAK // HOLD MASK   %.1f" % simulation.gas_remaining
		_gas_label.modulate = Color(1, 0.5, 0.3).lerp(Color(1, 0.1, 0.1), simulation.gas_unmasked / 1.15)

	_refresh_parkour()
	_refresh_end_state()


func _refresh_parkour() -> void:
	var challenge = simulation.gray_challenge
	_parkour_panel.visible = challenge != null
	if challenge == null:
		return
	_parkour_label.text = "GRAY PARKOUR // IN ORDER   %.1f" % challenge["remaining"]
	var order: Array = challenge["order"]
	var next: int = challenge["next"]
	for position in _parkour_buttons.get_child_count():
		var button: Button = _parkour_buttons.get_child(position)
		# The node's label is its shuffled step number — clicking by position
		# only counts when that position holds the next required step.
		button.text = "%d" % (int(order[position]) + 1)
		button.disabled = int(order[position]) < next


func _refresh_end_state() -> void:
	match simulation.phase:
		OfficeSimulation.Phase.ACTIVE:
			_end_panel.visible = false
		OfficeSimulation.Phase.JUMPSCARE:
			_end_panel.visible = true
			var threat: Dictionary = simulation.threats.get(simulation.caught_by, {})
			_end_title.text = String(threat.get("label", "VOID"))
			_end_title.modulate = threat.get("color", Color.RED)
			_end_cause.text = simulation.cause
			_end_hint.text = ""
		OfficeSimulation.Phase.LOST:
			_end_panel.visible = true
			_end_title.text = "SHIFT FAILED"
			_end_title.modulate = Color(0.9, 0.25, 0.3)
			_end_cause.text = simulation.cause
			_end_hint.text = "[E] RETURN TO MENU"
		OfficeSimulation.Phase.WON:
			_end_panel.visible = true
			_end_title.text = "6 AM"
			_end_title.modulate = Color(0.4, 0.95, 0.6)
			_end_cause.text = simulation.cause
			_end_hint.text = "[E] RETURN TO MENU"


func _power_color(value: float) -> Color:
	if value <= 15.0:
		return Color(0.95, 0.25, 0.3)
	if value <= 40.0:
		return Color(0.95, 0.75, 0.3)
	return Color(0.45, 0.9, 0.85)
