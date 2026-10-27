class_name NightWatchGame
extends Node3D

## The Night Watch shift scene: the office, the building, the hunters and the HUD, driven by NightWatchClassic. Controls:
## A / D doors, hold Q / E lights, Space the monitor, 1-8 or the arrow keys pick a camera, Esc pauses, N mutes Zellia.
## `manual_clock` stops the real-time clock so the validators step the night themselves with advance_ms().

signal finished(result: String)

enum State { PLAYING, PAUSED, WON, LOST }

const WIN_TEXT := "You held the desk until 6 AM."

var manual_clock := false
var night := 1
var seed_value := 0
var state: State = State.PLAYING
var sim: NightWatchClassic
var office: NightWatchOffice
var building: NightWatchBuilding
var hud: NightWatchHud
var hunters_root: Node3D
var death_moment: DeathMoment
var world_env: WorldEnvironment

var door_shut := {"doorL": false, "doorR": false}
var light_held := {"doorL": false, "doorR": false}
var monitor_up := false
var monitor_room := "stage"
var last_death := {}

var _models := {}
var _players := {}
var _flinch_left := {}
var _yaw := 0.0
var _pitch := 0.0
var _call_started := false


func _ready() -> void:
	NightWatchControls.register()
	night = NightWatchSession.night
	seed_value = NightWatchSession.seed_value
	if seed_value == 0:
		seed_value = int(Time.get_ticks_usec() & 0x7fffffff)
	_build_world()
	sim = NightWatchClassic.new(night, seed_value, NightWatchSession.custom_levels)
	_spawn_hunters()
	hud.update_status(0, 100.0, 0, night)
	hud.set_cam(monitor_room, building.camera_transform(monitor_room))
	hud.queue_call(NightWatchData.call_lines(night))
	_sync_visuals()
	_capture_mouse(true)


func _build_world() -> void:
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.38, 0.40, 0.55)
	env.ambient_light_energy = 0.5
	world_env.environment = env
	add_child(world_env)
	office = NightWatchOffice.new()
	office.name = "Office"
	add_child(office)
	building = NightWatchBuilding.new()
	building.name = "Building"
	add_child(building)
	hunters_root = Node3D.new()
	hunters_root.name = "Hunters"
	add_child(hunters_root)
	hud = NightWatchHud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.camera_selected.connect(select_camera)
	hud.retry_pressed.connect(retry)
	hud.next_pressed.connect(next_night)
	hud.menu_pressed.connect(back_to_games)
	hud.resume_pressed.connect(func(): set_paused(false))
	hud.subtitles_toggled.connect(func(on: bool):
		hud.set_subtitles(on)
		NightWatchSave.set_subtitles(on))
	hud.set_subtitles(NightWatchSave.subtitles())
	death_moment = DeathMoment.new()
	death_moment.name = "DeathMoment"
	add_child(death_moment)
	death_moment.finished.connect(_after_death_moment)
	office.camera.current = true


func _spawn_hunters() -> void:
	for id in NightWatchData.CAST:
		var identity := HunterRoster.get_identity(id)
		var model := ModelSlot.instantiate_hunter(identity)
		if model == null:
			push_warning("NightWatch: no model for %s" % id)
			model = Node3D.new()
		model.name = "Hunter_%s" % id
		hunters_root.add_child(model)
		_models[id] = model
		var player := ModelSlot.find_animation_player(model)
		if player != null:
			_players[id] = player
			if player.has_animation("idle"):
				player.play("idle")
		model.visible = false


# --- player actions (also what the validators press) -----------------------------------------------------------------

func toggle_door(door: String) -> void:
	if state != State.PLAYING or sim.out:
		return
	door_shut[door] = not bool(door_shut[door])


func set_door(door: String, shut: bool) -> void:
	if state == State.PLAYING and not sim.out:
		door_shut[door] = shut


func set_light(door: String, held: bool) -> void:
	if state == State.PLAYING:
		light_held[door] = held and not sim.out


func open_monitor(room := "") -> void:
	if state != State.PLAYING or sim.out:
		return
	if room != "":
		monitor_room = room
	monitor_up = true
	hud.show_monitor(true)
	hud.set_cam(monitor_room, building.camera_transform(monitor_room))
	hud.flash_static()
	_capture_mouse(false)


func close_monitor() -> void:
	monitor_up = false
	hud.show_monitor(false)
	if state == State.PLAYING:
		_capture_mouse(true)


func toggle_monitor() -> void:
	if monitor_up:
		close_monitor()
	else:
		open_monitor()


func select_camera(room: String) -> void:
	if state != State.PLAYING or not NightWatchData.ROOMS.has(room) or int(NightWatchData.ROOMS[room]["cam"]) == 0:
		return
	monitor_room = room
	hud.set_cam(room, building.camera_transform(room))
	hud.flash_static()


func cycle_camera(step: int) -> void:
	var rooms := NightWatchData.cam_rooms()
	var i := rooms.find(monitor_room)
	select_camera(String(rooms[posmod(i + step, rooms.size())]))


func set_paused(on: bool) -> void:
	if state == State.WON or state == State.LOST:
		return
	state = State.PAUSED if on else State.PLAYING
	get_tree().paused = on
	hud.show_pause(on)
	_capture_mouse(not on and not monitor_up)


func back_to_games() -> void:
	get_tree().paused = false
	_capture_mouse(false)
	get_tree().change_scene_to_file(GameRegistry.HUB_SCENE)


func retry() -> void:
	NightWatchSession.start(night, seed_value)
	get_tree().paused = false
	get_tree().reload_current_scene()


func next_night() -> void:
	NightWatchSession.start(mini(night + 1, NightWatchData.NIGHTS))
	get_tree().paused = false
	get_tree().reload_current_scene()


func _capture_mouse(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


# --- the clock ---------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_animate_models(delta)
	_look_with_keys(delta)
	if state != State.PLAYING or manual_clock:
		return
	advance_ms(delta * 1000.0)


func current_input() -> Dictionary:
	return {"doorL": door_shut["doorL"], "doorR": door_shut["doorR"], "lightL": light_held["doorL"], "lightR": light_held["doorR"],
		"cam": monitor_up, "cam_room": monitor_room}


## Step the night by dt_ms with the doors, lights and monitor as they are, and show what happened.
func advance_ms(dt_ms: float) -> void:
	if state != State.PLAYING:
		return
	var events := sim.step(dt_ms, current_input())
	if sim.out and monitor_up:
		close_monitor()
	for e in events:
		_on_event(e)
	_sync_visuals()
	if sim.over == "win":
		_finish_win()
	elif sim.over == "caught":
		_finish_caught()


func _on_event(e: Dictionary) -> void:
	match String(e["type"]):
		"flinch":
			_flinch_left[String(e["id"])] = 0.7
		"out":
			door_shut = {"doorL": false, "doorR": false}
			light_held = {"doorL": false, "doorR": false}
			hud.show_call("The power is out.")
		"moved", "arrived", "repelled", "pushed":
			if monitor_up and (String(e["room"]) == monitor_room or String(e["from"]) == monitor_room):
				hud.flash_static()


# --- what you see ----------------------------------------------------------------------------------------------------

func _sync_visuals() -> void:
	for door in ["doorL", "doorR"]:
		office.set_light(door, bool(sim.light_on[door]))
	if manual_clock:
		office.snap_slabs(sim.door_shut)
	hud.update_status(sim.hour(), sim.power, NightWatchClassic.usage(current_input()), night)
	_place_hunters()


func _place_hunters() -> void:
	var slots := {}
	for id in NightWatchData.HUNTERS:
		var hunter := sim.hunters[id] as NightWatchStalker
		var model := _models[id] as Node3D
		var slot: int = int(slots.get(hunter.room, 0))
		slots[hunter.room] = slot + 1
		model.visible = hunter.base > 0   # a hunter at level 0 is not on tonight's floor
		var pos: Vector3
		var face: Vector3
		if hunter.room.begins_with("door"):
			pos = office.global_position + office.door_stand(hunter.room, mini(slot, 1))
			face = office.global_position + Vector3(0.0, 0.0, 0.2)
		else:
			pos = building.stand_position(hunter.room, mini(slot, 1))
			face = building.camera_transform(hunter.room).origin
		_set_model_pose(model, pos, face)
	# Nyxie: only in the dark, creeping in from the left hall toward the desk over the blackout
	var nyxie := _models["nyxie"] as Node3D
	nyxie.visible = sim.out and sim.nyxie_level > 0
	if nyxie.visible:
		var t := clampf(sim.out_ms / NightWatchData.blackout_ms(sim.nyxie_level), 0.0, 1.0)
		var from := office.global_position + office.door_stand("doorL", 0)
		var to := office.global_position + Vector3(-0.7, 0.0, -0.9)
		_set_model_pose(nyxie, from.lerp(to, t), office.global_position + Vector3(0.0, 0.0, 0.9))


func _set_model_pose(model: Node3D, pos: Vector3, face: Vector3) -> void:
	model.position = pos
	var d := face - pos
	d.y = 0.0
	if d.length() > 0.01:
		model.rotation.y = atan2(d.x, d.z) + PI   # the blocky models' front is -Z


func _animate_models(delta: float) -> void:
	for id in _flinch_left.keys():
		_flinch_left[id] = float(_flinch_left[id]) - delta
		if float(_flinch_left[id]) <= 0.0:
			_flinch_left.erase(id)
	for id in _players:
		var player := _players[id] as AnimationPlayer
		var clip := "stun" if _flinch_left.has(id) else "idle"
		if player.has_animation(clip) and player.current_animation != clip:
			player.play(clip)
	if state == State.PLAYING and not manual_clock:
		office.animate(sim.door_shut if sim != null else door_shut, delta)


# --- input -----------------------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and state == State.PLAYING and not monitor_up \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		_yaw -= m.relative.x * Settings.mouse_sensitivity
		_pitch -= m.relative.y * Settings.mouse_sensitivity
		office.look(_yaw, _pitch)
		_yaw = office.camera.rotation.y
		_pitch = office.camera.rotation.x
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if event.is_action_pressed(&"pause"):
		if state == State.PLAYING or state == State.PAUSED:
			set_paused(state == State.PLAYING)
		return
	if state != State.PLAYING:
		return
	if event.is_action_pressed(&"office_left_door"):
		toggle_door("doorL")
	elif event.is_action_pressed(&"office_right_door"):
		toggle_door("doorR")
	elif event.is_action_pressed(NightWatchControls.LIGHT_LEFT):
		set_light("doorL", true)
	elif event.is_action_released(NightWatchControls.LIGHT_LEFT):
		set_light("doorL", false)
	elif event.is_action_pressed(NightWatchControls.LIGHT_RIGHT):
		set_light("doorR", true)
	elif event.is_action_released(NightWatchControls.LIGHT_RIGHT):
		set_light("doorR", false)
	elif event.is_action_pressed(&"office_cameras") or (event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).physical_keycode == KEY_SPACE):
		toggle_monitor()
	elif event.is_action_pressed(&"office_desk_light"):
		office.lamp.visible = not office.lamp.visible
	elif event.is_action_pressed(&"office_radio"):
		hud.toggle_mute()
	elif monitor_up and ((event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).physical_keycode == KEY_LEFT) \
			or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_DPAD_LEFT)):
		cycle_camera(-1)
	elif monitor_up and ((event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).physical_keycode == KEY_RIGHT) \
			or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_DPAD_RIGHT)):
		cycle_camera(1)
	else:
		for n in range(1, 9):
			if event.is_action_pressed(NightWatchControls.camera_action(n)):
				if not monitor_up:
					open_monitor(NightWatchData.room_for_cam(n))
				else:
					select_camera(NightWatchData.room_for_cam(n))
				return


## Looking with the arrow keys or the right stick while the monitor is down.
func _look_with_keys(delta: float) -> void:
	if monitor_up or state != State.PLAYING:
		return
	var rate := NightWatchControls.look_rate()
	if rate == Vector2.ZERO:
		return
	_yaw += rate.x * 1.6 * delta
	_pitch += rate.y * 1.2 * delta
	office.look(_yaw, _pitch)
	_yaw = office.camera.rotation.y
	_pitch = office.camera.rotation.x


# --- the end of a night ----------------------------------------------------------------------------------------------

func _finish_win() -> void:
	state = State.WON
	close_monitor()
	_capture_mouse(false)
	NightWatchSave.record_clear(night)
	var more := night < NightWatchData.NIGHTS
	hud.show_end("6 AM", WIN_TEXT + ("\nNight %d is open." % (night + 1) if more else "\nYou cleared every night."), more)
	finished.emit("win")


func _finish_caught() -> void:
	state = State.LOST
	close_monitor()
	_capture_mouse(false)
	var cause := {"hunter_id": sim.by}
	if sim.by == "nyxie":
		cause["detail"] = "darkness"
	var name_text := String(NightWatchData.NAMES.get(sim.by, sim.by.capitalize()))
	var picked := DeathLines.pick(cause, "nightwatch:%d" % seed_value, night, name_text)
	last_death = {"by": sim.by, "name": name_text, "picked": picked}
	finished.emit("caught")
	if DeathMoment.plays(picked):
		death_moment.play(name_text, picked)
	else:
		_after_death_moment()


func _after_death_moment() -> void:
	if state != State.LOST:
		return
	var name_text := String(last_death.get("name", "A hunter"))
	hud.show_end("CAUGHT", "%s reached you on night %d." % [name_text, night], false)


func _exit_tree() -> void:
	NightWatchControls.unregister()
	if get_tree() != null:
		get_tree().paused = false
