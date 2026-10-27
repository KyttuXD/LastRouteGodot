class_name NightWatchGame
extends NightWatchMode

## The Night Watch shift scene: a walkable security room, the building the cameras look into, the hunters and the HUD, driven by
## NightWatchClassic. You are the SHARED player controller (PlayerController3D from scenes/night_watch_player.tscn: the same node tree
## and parameters as the route scene) and USE stations with the shared interact action: the monitor on the desk, the DOOR and LIGHT
## buttons on the wall panels (hold interact on LIGHT), the desk lamp, the chair (the shared sit pose). Optional quick keys (nw_*
## actions on free keys): Z / X doors, hold G / H door lights, Y the lamp, U the monitor, R mutes Zellia; the shared pause key pauses;
## in the monitor 1-8 or the arrow keys pick a camera. All sounds go through the shared Sound autoload (NightWatchSounds).
## `manual_clock` stops the real-time clock so the validators step the night themselves with advance_ms().

enum State { PLAYING, PAUSED, WON, LOST }

const WIN_TEXT := "You held the desk until 6 AM."

var night := 1
var state: State = State.PLAYING
var sim: NightWatchClassic
var office: NightWatchOffice
var player: PlayerController3D
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
var paths: NightWatchPaths
var _walkers := {}   # hunter id -> NightWatchWalker
var _players := {}
var _flinch_left := {}
var _retreat_left := {}   # hunter id -> seconds left of the retreat pose after a shut door or a light turned her away
var _pose_state := {}     # hunter id -> the Night Watch pose state playing ("" = the rig's own walk / idle clips)
var _attacker := ""
## Admin (NightWatchAdmin): the menu (null for non-admins) and the live switches the admin hooks below set.
var admin_menu: AdminMenu
var _admin_frozen := false
var _admin_no_scare := false
var _admin_reveal := false
var _admin_noclip := false
var lamp_on := true
var _hour_seen := 0
var _elapsed_ms := 0.0
var _warned := {}


func _ready() -> void:
	NightWatchControls.register()
	read_session()
	night = level
	_build_world()
	sim = NightWatchClassic.new(night, seed_value, NightWatchSession.custom_levels, is_custom)
	_spawn_hunters()
	paths = NightWatchPaths.new(building, office)
	admin_menu = NightWatchAdmin.attach(self)   # after the sim exists: the Night 7 entries depend on it
	hud.mode_text = "%d. %s · %s" % [int(mode_data().get("num", 1)), String(mode_data().get("title", "CLASSIC")).capitalize(), level_name().capitalize()]
	hud.update_status(0, 100.0, 0, night)
	hud.set_cam(monitor_room, building.camera_transform(monitor_room))
	hud.set_call_script(NightWatchCallScript.new([], 0.0) if is_custom else NightWatchCallScript.for_level(mode_id, level))
	hud.set_monitor_available(office.spec.has_monitor)
	hud.hint_label.text = NightWatchControls.hint_line(false, _hint_actions())
	_sync_visuals()


func _build_world() -> void:
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.38, 0.40, 0.55)
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	MaterialLook.install(get_tree())
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
	hud.pause_requested.connect(func(): set_paused(true))
	hud.cameras_requested.connect(toggle_monitor)
	hud.subtitles_toggled.connect(func(on: bool):
		hud.set_subtitles(on)
		NightWatchSave.set_subtitles(on))
	hud.set_subtitles(NightWatchSave.subtitles())
	death_moment = DeathMoment.new()
	death_moment.name = "DeathMoment"
	add_child(death_moment)
	death_moment.finished.connect(_after_death_moment)
	player = (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	add_child(player)
	player.global_position = office.global_position + NightWatchOffice.SPAWN
	face_player(0.0, -0.1)
	player.interaction_message.connect(func(message: String): hud.show_note(message))
	_wire_stations()


## Look direction for the shared controller (it keeps its own yaw and pitch): used for the spawn and by the capture tool.
func face_player(yaw: float, pitch := 0.0) -> void:
	player.rotation.y = yaw
	player.set("_yaw", yaw)
	player.set("_pitch", pitch)
	player.call("_apply_look_rotation")


## Give every station what it does when the shared interact action presses on it.
func _wire_stations() -> void:
	var st: Dictionary = office.stations
	(st["monitor"] as NightWatchStation).on_activate = func(_p) -> String:
		toggle_monitor()
		return ""
	(st["doorL_door"] as NightWatchStation).on_activate = func(_p) -> String:
		toggle_door("doorL")
		NightWatchSounds.panel_button()
		return ""
	(st["doorR_door"] as NightWatchStation).on_activate = func(_p) -> String:
		toggle_door("doorR")
		NightWatchSounds.panel_button()
		return ""
	(st["doorL_light"] as NightWatchStation).on_activate = func(_p) -> String: return ""   # held, see _process
	(st["doorR_light"] as NightWatchStation).on_activate = func(_p) -> String: return ""
	(st["lamp"] as NightWatchStation).on_activate = func(_p) -> String:
		toggle_lamp()
		return ""
	(st["chair"] as NightWatchStation).on_activate = func(p) -> String:
		return String(p.use_furniture(st["chair"], "sit"))
	for id in ["breaker", "vent"]:
		(st[id] as NightWatchStation).on_activate = func(_p) -> String: return String(office.prompts.get(id, ""))


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
	NightWatchSounds.door(bool(door_shut[door]))


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
	player.input_frozen = true
	player.look_frozen = true
	MouseLock.claim("night_watch_monitor", true)
	hud.show_monitor(true)
	hud.hint_label.text = NightWatchControls.hint_line(true, _hint_actions())
	hud.set_monitor_guide(NightWatchControls.hint_line(true, _hint_actions()), NightWatchControls.key_text(NightWatchControls.MONITOR))
	hud.set_cam(monitor_room, building.camera_transform(monitor_room))
	hud.flash_static()
	NightWatchSounds.monitor_toggle()


func close_monitor() -> void:
	monitor_up = false
	MouseLock.claim("night_watch_monitor", false)
	player.input_frozen = state != State.PLAYING
	player.look_frozen = state != State.PLAYING
	hud.show_monitor(false)
	hud.hint_label.text = NightWatchControls.hint_line(false, _hint_actions())
	NightWatchSounds.monitor_toggle()


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
	NightWatchSounds.camera_switch()


## The actions the hint line lists: the office's, plus Night 7's meet key.
func _hint_actions() -> Array:
	var list := office.spec.controls.duplicate()
	if sim != null and sim.kathy_night:
		list.append("nw_meet")
	if admin_menu != null:
		list.append("admin")
	return list


## Night 7: meet Kathy's eyes on the feed you are watching (the 2D K key). A miss locks the key for two seconds.
func meet_her_eyes() -> String:
	if state != State.PLAYING or sim == null or not sim.kathy_night:
		return "none"
	var result: Dictionary = sim.meet(monitor_up, monitor_room, false)
	match String(result["result"]):
		"met":
			hud.show_note("Her eyes meet yours. She is gone.")
			hud.flash_static()
			_sync_visuals()
		"miss":
			hud.show_note("Nothing there.")
		"locked":
			hud.show_note("Wait.")
	return String(result["result"])


func is_playing() -> bool:
	return state == State.PLAYING


func select_camera_number(n: int) -> void:
	select_camera(NightWatchData.room_for_cam(n))


func cycle_camera(step: int) -> void:
	var rooms := NightWatchData.cam_rooms()
	var i := rooms.find(monitor_room)
	select_camera(String(rooms[posmod(i + step, rooms.size())]))


func toggle_lamp() -> void:
	lamp_on = not lamp_on
	office.set_lamp(lamp_on)


## What pressing use on a station does (the validators call this too).
func _on_station(id: String) -> void:
	if state != State.PLAYING or not office.stations.has(id):
		return
	var message := String((office.stations[id] as NightWatchStation).activate(player))
	if not message.is_empty():
		hud.show_note(message)


func set_paused(on: bool) -> void:
	if state == State.WON or state == State.LOST:
		return
	state = State.PAUSED if on else State.PLAYING
	get_tree().paused = on
	hud.show_pause(on)
	MouseLock.claim("night_watch_pause", on)


## QUIT TO HUB / MENU: back to the Shift Board (the 2D game's "hub"), where the 2D game puts you.
func back_to_games() -> void:
	back_to_board()


## Classic's nights run as far as the port goes (NightWatchData.NIGHTS); the mode table lists the 2D game's seven.
func has_next_level() -> bool:
	return not is_custom and level < NightWatchData.NIGHTS


func next_night() -> void:
	next_level()


# --- the clock ---------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_animate_models(delta)
	if state != State.PLAYING:
		return
	# the shared prompt for whatever the player is aiming at
	var aimed := player.call("_nearest_interactable") as NightWatchStation if not monitor_up else null
	hud.set_prompt(player.get_interaction_prompt() if not monitor_up else "")
	if manual_clock:
		return
	# the lights: held with the quick key, or with interact held on a LIGHT button
	for door in ["doorL", "doorR"]:
		var action := NightWatchControls.LIGHT_LEFT if door == "doorL" else NightWatchControls.LIGHT_RIGHT
		var on_button := aimed != null and aimed.station_id == "%s_light" % door
		var want := Input.is_action_pressed(action) or (Input.is_action_pressed(&"interact") and on_button)
		if want != bool(light_held[door]):
			set_light(door, want)
	advance_ms(delta * 1000.0)


func current_input() -> Dictionary:
	return {"doorL": door_shut["doorL"], "doorR": door_shut["doorR"], "lightL": light_held["doorL"], "lightR": light_held["doorR"],
		"cam": monitor_up, "cam_room": monitor_room}


## Step the night by dt_ms with the doors, lights and monitor as they are, and show what happened.
func advance_ms(dt_ms: float) -> void:
	if state != State.PLAYING or _admin_frozen:
		return
	_elapsed_ms += dt_ms
	hud.update_call(_elapsed_ms, dt_ms)
	var events := sim.step(dt_ms, current_input())
	if sim.hour() != _hour_seen:
		_hour_seen = sim.hour()
		NightWatchSounds.hour_change()
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
			NightWatchSounds.hunter_event(e)
		"out":
			door_shut = {"doorL": false, "doorR": false}
			light_held = {"doorL": false, "doorR": false}
			hud.show_call("The power is out.")
			NightWatchSounds.power_out()
		"hum":
			NightWatchSounds.office("breath", -0.8 if String(e["door"]) == "doorL" else 0.8, 0.35 if bool(e["muffled"]) else 0.9)
		"moved", "arrived", "repelled", "pushed":
			if String(e["type"]) == "repelled" or String(e["type"]) == "pushed":
				_retreat_left[String(e["id"])] = 1.4
			if not (String(e["id"]) == "kathy" and String(e["type"]) == "repelled"):   # her fading away makes no sound
				NightWatchSounds.hunter_event(e)
			if monitor_up and (String(e["room"]) == monitor_room or String(e["from"]) == monitor_room):
				hud.flash_static()


# --- what you see ----------------------------------------------------------------------------------------------------

func _sync_visuals() -> void:
	if _admin_reveal and sim != null:
		var rooms := []
		for id in sim.hunters:
			rooms.append((sim.hunters[id] as NightWatchStalker).room)
		hud.cam_map.set_blips(rooms)
	elif hud.cam_map.blips.size() > 0:
		hud.cam_map.set_blips([])
	for door in ["doorL", "doorR"]:
		office.set_light(door, bool(sim.light_on[door]) and not sim.light_dip(door))   # Night 7: her light dips (the only tell the light gives)
	if manual_clock:
		office.snap_slabs(sim.door_shut)
	for door in ["doorL", "doorR"]:
		office.set_button("%s_door" % door, bool(sim.door_shut[door]))
		office.set_button("%s_light" % door, bool(sim.light_on[door]))
	hud.update_status(sim.hour(), sim.power, NightWatchClassic.usage(current_input()), night)
	_place_hunters()


func _place_hunters() -> void:
	var slots := {}
	for id in _models:
		if id != "nyxie" and not sim.hunters.has(id):
			(_models[id] as Node3D).visible = false
	for id in sim.hunters:
		var hunter := sim.hunters[id] as NightWatchStalker
		var model := _models[id] as Node3D
		var slot: int = int(slots.get(hunter.room, 0))
		slots[hunter.room] = slot + 1
		model.visible = hunter.base > 0   # a hunter at level 0 is not on tonight's floor
		var pos: Vector3
		var face: Vector3
		if hunter.room.begins_with("door"):
			var progress := hunter.at_door_ms / maxf(1.0, hunter.attack_ms)
			pos = office.global_position + office.door_stand(hunter.room, mini(slot, 1), progress if slot == 0 else 0.0)
			face = player.global_position
		else:
			pos = building.stand_position(hunter.room, mini(slot, 1))
			face = building.camera_transform(hunter.room).origin
		var walker := _walkers.get(id) as NightWatchWalker
		if walker == null:
			walker = NightWatchWalker.new()
			_walkers[id] = walker
			walker.place(pos, pos, face, hunter.room)
		elif manual_clock:
			walker.place(pos, pos, face, hunter.room)
		elif walker.room != hunter.room:
			walker.go(paths.legs_from(walker.pos, hunter.room), hunter.room, pos, NightWatchWalker.budget_for(hunter.level))
			walker.look = face
		else:
			walker.final = pos
			walker.look = face
		model.position = walker.pos
		model.rotation.y = walker.yaw
	# Nyxie: only in the dark, creeping in from the left hall toward the desk over the blackout
	var nyxie := _models["nyxie"] as Node3D
	nyxie.visible = sim.out and sim.nyxie_level > 0
	if nyxie.visible:
		var t := clampf(sim.out_ms / NightWatchData.blackout_ms(sim.nyxie_level), 0.0, 1.0)
		var from := office.global_position + office.door_stand("doorL", 0, 0.0)
		var to := office.global_position + Vector3(-0.7, 0.0, -0.9)
		_set_model_pose(nyxie, from.lerp(to, t), player.global_position)


## The Night Watch pose state of a hunter this frame (docs/NIGHT_WATCH_POSES.md; "" = walking or nothing special: the rig's own clips). Moving hunters keep the walk / sprint
## clips; standing ones take the pose of what they are doing: peeking, pounding on a shut door, leaning in at the end of the wait, staring at the camera you watch, flinching from
## the light, backing away, lunging.
func _hunter_pose_state(id: String) -> String:
	var hunter := sim.hunters.get(id) as NightWatchStalker if sim != null else null
	var walker := _walkers.get(id) as NightWatchWalker
	if hunter == null or walker == null or not (_models[id] as Node3D).visible:
		return ""
	if id == _attacker and state == State.LOST:
		return "attack"
	if _flinch_left.has(id):
		return "light_flinch"
	if _retreat_left.has(id):
		return "retreat"
	if walker.moving:
		return ""
	if hunter.is_at_door():
		if id == "kathy":
			return "waiting"
		if bool(sim.door_shut.get(hunter.door(), false)):
			return "at_door"          # blocked by the shut door: pounding on it
		match hunter.door_pose():
			"peek":
				return "peek_left" if hunter.door() == "doorL" else "peek_right"
			"stand":
				return "door_grace"
			_:
				return "reaching"     # leaning in at the end of the wait
	if monitor_up and monitor_room == hunter.room:
		return "camera"
	return "listening" if id == "kathy" else "idle"


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
	for id in _walkers:
		var walker := _walkers[id] as NightWatchWalker
		if not manual_clock:
			walker.step(delta)
		var model := _models[id] as Node3D
		model.position = walker.pos
		model.rotation.y = walker.yaw
	for id in _retreat_left.keys():
		_retreat_left[id] = float(_retreat_left[id]) - delta
		if float(_retreat_left[id]) <= 0.0:
			_retreat_left.erase(id)
	for id in _players:
		var player := _players[id] as AnimationPlayer
		var walker := _walkers.get(id) as NightWatchWalker
		var pose_state := _hunter_pose_state(id)
		if pose_state != String(_pose_state.get(id, "-")):
			_pose_state[id] = pose_state
			if pose_state.is_empty():
				NightWatchPoses.stop(_models[id])
			else:
				NightWatchPoses.play_state(_models[id], pose_state)
		if pose_state.is_empty():
			var clip := "sprint" if walker != null and walker.moving and walker.running and player.has_animation("sprint") else ("walk" if walker != null and walker.moving else "idle")
			if player.has_animation(clip) and player.current_animation != clip:
				player.play(clip)
	if state == State.PLAYING and not manual_clock:
		office.animate(sim.door_shut if sim != null else door_shut, delta)


# --- input -----------------------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		var key := (event as InputEventKey).keycode
		if state == State.PAUSED and key == KEY_BACKSPACE:
			back_to_games()
			return
		if state == State.WON or state == State.LOST:
			if key == KEY_ESCAPE:
				back_to_games()
				return
			if key == KEY_ENTER or key == KEY_KP_ENTER:
				if state == State.LOST:
					retry()
				elif hud.end_next.visible:
					next_night()
				return
	if event.is_action_pressed(&"pause"):
		if state == State.PLAYING or state == State.PAUSED:
			set_paused(state == State.PLAYING)
		return
	if state != State.PLAYING:
		return
	if NightWatchControls.handle_monitor_event(self, event):
		return
	if monitor_up:
		if event.is_action_pressed(NightWatchControls.MEET):
			meet_her_eyes()
		elif event.is_action_pressed(NightWatchControls.MUTE):
			hud.toggle_mute()
		return
	if event.is_action_pressed(NightWatchControls.DOOR_LEFT):
		toggle_door("doorL")
	elif event.is_action_pressed(NightWatchControls.DOOR_RIGHT):
		toggle_door("doorR")
	elif event.is_action_pressed(NightWatchControls.LIGHT_LEFT):
		set_light("doorL", true)
	elif event.is_action_released(NightWatchControls.LIGHT_LEFT):
		set_light("doorL", false)
	elif event.is_action_pressed(NightWatchControls.LIGHT_RIGHT):
		set_light("doorR", true)
	elif event.is_action_released(NightWatchControls.LIGHT_RIGHT):
		set_light("doorR", false)
	elif event.is_action_pressed(NightWatchControls.LAMP):
		toggle_lamp()
	elif event.is_action_pressed(&"office_radio"):
		hud.toggle_mute()


# --- the end of a night ----------------------------------------------------------------------------------------------

## The night is over: no more walking or looking, and the cursor is free for the end card.
func _freeze_player() -> void:
	player.input_frozen = true
	player.look_frozen = true
	MouseLock.claim("night_watch_end", true)


func _finish_win() -> void:
	state = State.WON
	close_monitor()
	_freeze_player()
	NightWatchSounds.win()
	record_win()
	var more := has_next_level()
	hud.show_end("NIGHT %d COMPLETE" % night, "6:00 AM\n" + WIN_TEXT + ("\nNight %d is open." % (night + 1) if more else "\nYou cleared every night."), more)
	finished.emit("win")


func _finish_caught() -> void:
	state = State.LOST
	close_monitor()
	_freeze_player()
	NightWatchSounds.caught()
	var cause := {"hunter_id": sim.by}
	if sim.by == "nyxie":
		cause["detail"] = "darkness"
	var name_text := String(NightWatchData.NAMES.get(sim.by, sim.by.capitalize()))
	var picked := DeathLines.pick(cause, "nightwatch:%d" % seed_value, night, name_text)
	_attacker = sim.by
	last_death = {"by": sim.by, "name": name_text, "picked": picked}
	finished.emit("caught")
	if DeathMoment.plays(picked) and not _admin_no_scare:
		death_moment.play(name_text, picked)
	else:
		_after_death_moment()


func _after_death_moment() -> void:
	if state != State.LOST:
		return
	var name_text := String(last_death.get("name", "A hunter"))
	hud.show_end("CAUGHT", "%s reached you on night %d." % [name_text, night], false)


func _exit_tree() -> void:
	MouseLock.release_all()
	NightWatchControls.unregister()
	if get_tree() != null:
		get_tree().paused = false



# --- admin hooks (NightWatchAdmin builds the menu from the ones a game has; each really changes the game) ---------------------

func admin_status() -> String:
	var kind := "KATHY" if sim.kathy_night else "CLASSIC"
	return "%s  LEVEL %d  %s%s\nPOWER %d%%  OUT %s\nFROZEN %s  GOD %s  NO SCARE %s  SPEED %.1fX" % [kind, night, NightWatchData.hour_label(sim.hour()), " (SEED %d)" % seed_value,
		int(ceil(sim.power)), str(sim.out), str(_admin_frozen), str(sim.god), str(_admin_no_scare), sim.hunter_speed]


func admin_hunter_rows() -> Array:
	var rows := []
	for id in sim.hunters:
		var h := sim.hunters[id] as NightWatchStalker
		var walker := _walkers.get(id) as NightWatchWalker
		rows.append("%s  %s  AI %d%s%s" % [String(id).to_upper(), h.room, h.level, "  AT DOOR %.1fs" % (h.at_door_ms / 1000.0) if h.is_at_door() else "", "  WALKING" if walker != null and walker.moving else ""])
	return rows


func admin_jump_to(target_level: int) -> void:
	NightWatchSession.start_mode(mode_id, target_level)
	get_tree().paused = false
	if get_tree().current_scene == self:
		get_tree().reload_current_scene()


func admin_set_hour(hour_value: int) -> void:
	sim.elapsed = clampf(float(hour_value) * NightWatchData.HOUR_MS, 0.0, NightWatchData.NIGHT_MS - 1000.0)
	_hour_seen = sim.hour()
	_elapsed_ms = sim.elapsed
	_sync_visuals()


func admin_set_frozen(on: bool) -> void:
	_admin_frozen = on


func admin_is_frozen() -> bool:
	return _admin_frozen


func admin_set_power(percent: float) -> void:
	sim.power = clampf(percent, 0.0, 100.0)
	sim.out = sim.power <= 0.0
	sim.out_ms = 0.0
	if sim.out:
		_on_event({"type": "out"})
	_sync_visuals()


func admin_set_infinite_power(on: bool) -> void:
	sim.infinite_power = on


func admin_infinite_power() -> bool:
	return sim.infinite_power


func admin_set_god(on: bool) -> void:
	sim.god = on


func admin_is_god() -> bool:
	return sim.god


func admin_set_no_scare(on: bool) -> void:
	_admin_no_scare = on


func admin_no_scare() -> bool:
	return _admin_no_scare


func admin_set_hunter_speed(mult: float) -> void:
	sim.hunter_speed = clampf(mult, 0.1, 8.0)


func admin_hunter_ids() -> Array:
	return sim.hunters.keys()


func admin_set_hunter_level(id: String, level_value: int) -> void:
	if sim.hunters.has(id):
		(sim.hunters[id] as NightWatchStalker).base = level_value
		(sim.hunters[id] as NightWatchStalker).level = NightWatchData.effective_level(level_value, sim.hour())


func admin_places() -> Array:
	var places := NightWatchData.cam_rooms()
	places.append("doorL")
	places.append("doorR")
	return places


func admin_place_hunter(id: String, place: String) -> void:
	if sim.hunters.has(id):
		(sim.hunters[id] as NightWatchStalker).admin_send(place)
		_sync_visuals()


func admin_all_to_doors() -> void:
	for id in sim.hunters:
		var h := sim.hunters[id] as NightWatchStalker
		h.admin_send(h.door())
	_sync_visuals()


func admin_set_door(door: String, shut: bool) -> void:
	if bool(door_shut[door]) != shut:
		toggle_door(door)


func admin_play_call() -> void:
	var entry := NightWatchCallsData.for_level(mode_id, level)
	hud.set_call_script(NightWatchCallScript.new(entry.get("lines", ["Zellia, on the headset."]), 0.0))
	_elapsed_ms = 0.0


func admin_skip_call() -> void:
	if hud.call_script != null:
		hud.call_script.mute()
	hud.show_call("")


func admin_set_reveal(on: bool) -> void:
	_admin_reveal = on
	_sync_visuals()


func admin_is_reveal() -> bool:
	return _admin_reveal


func admin_win() -> void:
	if state == State.PLAYING:
		sim.over = "win"
		_finish_win()


func admin_lose() -> void:
	if state == State.PLAYING:
		sim.over = "caught"
		sim.by = String(sim.hunters.keys()[0])
		_finish_caught()


func admin_set_noclip(on: bool) -> void:
	_admin_noclip = on
	player.set_admin_noclip(on)


func admin_is_noclip() -> bool:
	return _admin_noclip


## Night 7: put Kathy in a hall, open the monitor on it and meet her eyes (the real meet rules run).
func admin_force_meet() -> String:
	if not sim.kathy_night:
		return "none"
	var kathy := sim.hunters["kathy"] as NightWatchStalker
	kathy.admin_send("westhall")
	open_monitor("westhall")
	return meet_her_eyes()
