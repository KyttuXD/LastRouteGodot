class_name LureGame
extends NightWatchMode

## Dead Air (mode `lure`), the shift scene: the broadcast booth (LureOffice, the shared player, prompt and
## crosshair), with the two DOOR buttons sealing the vent openings (the slabs are the vent covers), the left and right LIGHT buttons switching
## the heater and the fan, and the monitor on the desk looking into the radio station (LureWorld, floor plan in LureMap). Rules: LureLogic. In the monitor: 1-8
## pick a camera, L lures Xivvy to the room on screen, Q / W / E / R / T reboot audio / cameras / vents / heater / fan (or click the buttons),
## N mutes Zellia. Quick keys outside it: Z / X seal the left / right vent, G / H heater / fan, U monitor, Y lamp, R mutes Zellia.
## Xivvy WALKS the hall (LurePaths, NightWatchWalker). `manual_clock` stops the real-time clock so the validators step the night with advance_ms().

enum State { PLAYING, PAUSED, WON, LOST }

var night := 1
var state: State = State.PLAYING
var sim: LureLogic
var office: LureOffice
var world: LureWorld
var player: PlayerController3D
var hud: NightWatchHud
var panel: LurePanel
var hunters_root: Node3D
var death_moment: DeathMoment
var world_env: WorldEnvironment
var paths: LurePaths

var monitor_up := false
var monitor_room := "storage"
var lamp_on := true
var last_death := {}

var _models := {}
var _walkers := {}
var _players := {}
var _hour_seen := 0
var _pose_state := {}   # hunter id -> "" | "vent_enter" | "vent" | "vent_exit": the vent crawl (NightWatchPoses)
var _vent_left := 0.0
## Admin (NightWatchAdmin): the menu (null for non-admins) and the live switches the admin hooks below set.
var admin_menu: AdminMenu
var _admin_frozen := false
var _admin_no_scare := false
var _admin_reveal := false
var _admin_noclip := false
var _feed_container: Control


func _ready() -> void:
	NightWatchControls.register()
	read_session()
	night = clampi(level, 1, 6)
	var opts := {"night": night, "rng": NightWatchStream.seeded(seed_value)}
	if is_custom:
		night = 5   # a Custom Night plays at Night 5's tables, with the sliders as the levels (the 2D menu's customLevel)
		opts = {"night": 5, "rng": NightWatchStream.seeded(seed_value), "custom": true, "level": int(custom.get("xivvy", 0)),
			"phantom_levels": custom, "climate_levels": custom}
	_build_world()
	sim = LureLogic.new(opts)
	_spawn_hunters()
	paths = LurePaths.new(world, office)
	hud.set_call_script(NightWatchCallScript.new([], 6.0) if is_custom else NightWatchCallScript.for_level(mode_id, level))
	_sync_visuals()
	_select_room(monitor_room, false)
	admin_menu = NightWatchAdmin.attach(self)   # after the sim exists
	_hint()


func _build_world() -> void:
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.38, 0.40, 0.55)
	env.ambient_light_energy = 1.0
	world_env.environment = env
	add_child(world_env)
	office = NightWatchOfficeRegistry.make("lure") as LureOffice
	office.name = "Office"
	add_child(office)
	world = LureWorld.new()
	world.name = "Hall"
	add_child(world)
	hunters_root = Node3D.new()
	hunters_root.name = "Hunters"
	add_child(hunters_root)
	hud = NightWatchHud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.retry_pressed.connect(retry)
	hud.next_pressed.connect(next_level)
	hud.menu_pressed.connect(back_to_board)
	hud.pause_requested.connect(func(): set_paused(true))
	hud.cameras_requested.connect(toggle_monitor)
	hud.resume_pressed.connect(func(): set_paused(false))
	hud.subtitles_toggled.connect(func(on: bool):
		hud.set_subtitles(on)
		NightWatchSave.set_subtitles(on))
	hud.set_subtitles(NightWatchSave.subtitles())
	hud.hint_label.text = NightWatchControls.hint_line(false, LureOffice.make_spec().controls)
	# the monitor: the camera map is the HUD's, from Dead Air's own layout (camera n = LureMap's cams[n - 1])
	hud.set_cam_layout(NightWatchMapRegistry.layout_for("lure"))
	hud.camera_selected.connect(func(map_id: String): select_camera(String(LureMap.ROOMS[map_id][0])))
	panel = LurePanel.new()
	hud.monitor_root.add_child(panel)
	panel.lure_pressed.connect(func(): do_lure())
	panel.reboot_pressed.connect(func(system: String): do_reboot(system))
	_feed_container = hud.feed_viewport.get_parent() as Control
	death_moment = DeathMoment.new()
	death_moment.name = "DeathMoment"
	add_child(death_moment)
	death_moment.finished.connect(_after_death_moment)
	player = (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	add_child(player)
	player.global_position = office.global_position + LureOffice.SPAWN
	face_player(0.0, -0.1)
	player.interaction_message.connect(func(message: String): hud.show_note(message))
	_wire_stations()


func face_player(yaw: float, pitch := 0.0) -> void:
	player.rotation.y = yaw
	player.set("_yaw", yaw)
	player.set("_pitch", pitch)
	player.call("_apply_look_rotation")


## The office's DOOR buttons seal the vents, its LIGHT buttons run the heater and the fan.
func _wire_stations() -> void:
	var st: Dictionary = office.stations
	_prompt("doorL_door", "SEAL LEFT VENT // SEAL / OPEN")
	_prompt("doorR_door", "SEAL RIGHT VENT // SEAL / OPEN")
	_prompt("doorL_light", "HEATER // ON / OFF")
	_prompt("doorR_light", "FAN // ON / OFF")
	(st["monitor"] as NightWatchStation).on_activate = func(_p) -> String:
		toggle_monitor()
		return ""
	(st["doorL_door"] as NightWatchStation).on_activate = func(_p) -> String:
		toggle_seal("L")
		NightWatchSounds.panel_button()
		return ""
	(st["doorR_door"] as NightWatchStation).on_activate = func(_p) -> String:
		toggle_seal("R")
		NightWatchSounds.panel_button()
		return ""
	(st["doorL_light"] as NightWatchStation).on_activate = func(_p) -> String:
		return toggle_appliance("heater")
	(st["doorR_light"] as NightWatchStation).on_activate = func(_p) -> String:
		return toggle_appliance("fan")
	(st["lamp"] as NightWatchStation).on_activate = func(_p) -> String:
		toggle_lamp()
		return ""
	(st["chair"] as NightWatchStation).on_activate = func(p) -> String:
		return String(p.use_furniture(st["chair"], "sit"))


func _prompt(id: String, text: String) -> void:
	(office.stations[id] as NightWatchStation).prompt_text = text
	office.prompts[id] = text


func _spawn_hunters() -> void:
	for id in LureData.CAST:
		var model := ModelSlot.instantiate_hunter(HunterRoster.get_identity(id))
		if model == null:
			push_warning("Dead Air: no model for %s" % id)
			model = Node3D.new()
		model.name = "Hunter_%s" % id
		hunters_root.add_child(model)
		_models[id] = model
		var anim := ModelSlot.find_animation_player(model)
		if anim != null:
			_players[id] = anim
			if anim.has_animation("idle"):
				anim.play("idle")
		model.visible = false


# --- player actions (also what the validators press) -----------------------------------------------------------------

func toggle_seal(side: String) -> void:
	if state != State.PLAYING:
		return
	if sim.seal(side):
		LureSounds.seal(bool(sim.seals[side]))


func set_seal(side: String, on: bool) -> void:
	if state == State.PLAYING:
		sim.seal(side, on)


func toggle_appliance(name: String) -> String:
	if state != State.PLAYING:
		return ""
	if not sim.has_climate or (name == "fan" and not sim.has_fan):
		LureSounds.deny()
		return "NOTHING TO %s TONIGHT" % ("HEAT" if name == "heater" else "COOL")
	if not sim.toggle(name):
		LureSounds.deny()
		return "%s IS DOWN // REBOOT IT ON THE MONITOR" % name.to_upper()
	LureSounds.appliance()
	return ""


func do_lure() -> bool:
	if state != State.PLAYING or not monitor_up:
		return false
	if sim.lure(monitor_room):
		LureSounds.lure(monitor_room)
		return true
	LureSounds.deny()
	return false


func do_reboot(system: String) -> bool:
	if state != State.PLAYING:
		return false
	if sim.reboot(system):
		NightWatchSounds.monitor_toggle()
		return true
	LureSounds.deny()
	return false


func open_monitor(room := "") -> void:
	if state != State.PLAYING or sim.over != "":
		return
	if room != "":
		monitor_room = room
	monitor_up = true
	player.input_frozen = true
	player.look_frozen = true
	MouseLock.claim("night_watch_monitor", true)
	hud.show_monitor(true)
	_select_room(monitor_room, false)
	hud.flash_static()
	NightWatchSounds.monitor_toggle()
	_hint()
	_sync_visuals()


func close_monitor() -> void:
	if not monitor_up:
		return
	monitor_up = false
	MouseLock.claim("night_watch_monitor", false)
	player.input_frozen = state != State.PLAYING
	player.look_frozen = state != State.PLAYING
	hud.show_monitor(false)
	NightWatchSounds.monitor_toggle()
	_hint()


func toggle_monitor() -> void:
	if monitor_up:
		close_monitor()
	else:
		open_monitor()


func select_camera(room: String) -> void:
	if state != State.PLAYING or not LureData.ROOMS.has(room):
		return
	_select_room(room, true)


func _select_room(room: String, flash: bool) -> void:
	monitor_room = room
	hud.set_cam(LureMap.sim_to_map(room), world.camera_transform(room))
	if flash:
		hud.flash_static()
		NightWatchSounds.camera_switch()
	if sim != null:
		panel.refresh(sim, monitor_room)


func is_playing() -> bool:
	return state == State.PLAYING


## Camera number 1-8 (the keys 1-8 and the number pad): the hall's cameras in LureData.ROOMS order.
func select_camera_number(n: int) -> void:
	if n >= 1 and n <= LureData.ROOMS.size():
		select_camera(String(LureData.ROOMS[n - 1]))


func camera_rooms() -> Array:
	return LureData.ROOMS


func _hint() -> void:
	var actions := office.spec.controls.duplicate()
	if admin_menu != null:
		actions.append("admin")
	hud.hint_label.text = NightWatchControls.hint_line(monitor_up, actions) + (" · L lure · Q W E R T reboot" if monitor_up else "")


func cycle_camera(step: int) -> void:
	var i := LureData.ROOMS.find(monitor_room)
	select_camera(String(LureData.ROOMS[posmod(i + step, LureData.ROOMS.size())]))


func toggle_lamp() -> void:
	lamp_on = not lamp_on
	office.set_lamp(lamp_on)


func set_paused(on: bool) -> void:
	if state == State.WON or state == State.LOST:
		return
	state = State.PAUSED if on else State.PLAYING
	get_tree().paused = on
	hud.show_pause(on)
	MouseLock.claim("night_watch_pause", on)


# --- the clock --------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_animate_models(delta)
	if state != State.PLAYING:
		return
	hud.set_prompt(player.get_interaction_prompt() if not monitor_up else "")
	if manual_clock:
		return
	advance_ms(delta * 1000.0)


## Is the monitor on a camera that works (what the rules call "watching")?
func watching() -> String:
	return monitor_room if monitor_up and sim.online("cams") else ""


func advance_ms(dt_ms: float) -> void:
	if state != State.PLAYING or _admin_frozen:
		return
	var events := sim.step(dt_ms, {"watch": watching()})
	hud.update_call(sim.elapsed, dt_ms)
	var hour := NightWatchData.hour_index(sim.elapsed)
	if hour != _hour_seen:
		_hour_seen = hour
		NightWatchSounds.hour_change()
	for e in events:
		_on_event(e)
	if sim.over != "" and monitor_up:
		close_monitor()
	_sync_visuals()
	if sim.over == "win":
		_finish_win()
	elif sim.over == "caught":
		_finish_caught()


func _on_event(e: Dictionary) -> void:
	match String(e["type"]):
		"moved":
			LureSounds.moved(String(e["room"]))
			if monitor_up and (String(e["room"]) == monitor_room or String(e["from"]) == monitor_room):
				hud.flash_static()
		"atOffice":
			LureSounds.at_vent(String(e["room"]))
			LureSounds.warning(float(LureData.INFO[e["room"]]["pan"]))
			if monitor_up and String(e["from"]) == monitor_room:
				hud.flash_static()
		"retreat":
			LureSounds.retreat(String(e["side"]))
		"phantom":
			LureSounds.phantom()
			if monitor_up:
				hud.flash_static()
		"broken":
			LureSounds.broken()
			hud.show_call("%s is down. Reboot it from the monitor." % String(LureData.SYSTEMS[e["system"]]["label"]).capitalize())
		"fixed":
			LureSounds.fixed()


# --- what you see ----------------------------------------------------------------------------------------------------

func _sync_visuals() -> void:
	var shut := {"doorL": bool(sim.seals["L"]), "doorR": bool(sim.seals["R"])}
	if manual_clock:
		office.snap_slabs(shut)
	for door in ["doorL", "doorR"]:
		office.set_light(door, false)
		office.set_button("%s_door" % door, bool(shut[door]))
	office.set_button("doorL_light", sim.heater_on)
	office.set_button("doorR_light", sim.fan_on)
	hud.update_status(NightWatchData.hour_index(sim.elapsed), 100.0, 0, night)
	hud.night_label.text = "CUSTOM NIGHT" if is_custom else "NIGHT %d" % night
	hud.power_label.text = "AIR %d%%" % int(round(100.0 - sim.stress))
	hud.usage_label.text = "TEMP %d F" % int(round(sim.temp)) if sim.has_climate else "SEALS " + ("L" if sim.seals["L"] else "-") + ("R" if sim.seals["R"] else "-")
	_climate_light()
	_feed_container.modulate = Color(1, 1, 1) if sim.online("cams") else Color(0.04, 0.04, 0.04)
	panel.refresh(sim, monitor_room)
	if _admin_reveal:
		var rooms := []
		var here := LureMap.sim_to_map(String(sim.killer["room"]))
		if not here.is_empty():
			rooms.append(here)
		if not sim.phantom.is_empty():
			rooms.append(LureMap.sim_to_map(String(sim.phantom["room"])))
		hud.cam_map.set_blips(rooms)
	elif hud.cam_map.blips.size() > 0:
		hud.cam_map.set_blips([])
	_place_hunters()


## The office's own light follows the weather and the air: bluer when it is cold, warmer when it is hot, dimmer when the air is heavy.
func _climate_light() -> void:
	var env := world_env.environment
	var base := Color(0.38, 0.40, 0.55)
	var cold_t := clampf(maxf(sim.cold / 100.0, (60.0 - sim.temp) / 60.0), 0.0, 1.0) if sim.has_climate else 0.0
	var heat_t := clampf(maxf(sim.heat / 100.0, (sim.temp - 90.0) / 40.0), 0.0, 1.0) if sim.has_climate else 0.0
	env.ambient_light_color = base.lerp(Color(0.3, 0.5, 0.95), cold_t * 0.6).lerp(Color(0.95, 0.5, 0.25), heat_t * 0.6)
	env.ambient_light_energy = lerpf(1.0, 0.55, clampf(sim.stress / 100.0, 0.0, 1.0))


func _place_hunters() -> void:
	var k: Dictionary = sim.killer
	var xivvy := _models["xivvy"] as Node3D
	xivvy.visible = sim.lvl > 0
	var room: String = k["room"]
	var pos: Vector3
	var face: Vector3
	if room.begins_with("office"):
		var door := "doorL" if room == "officeL" else "doorR"
		var progress := float(k["atMs"]) / float(LureLogic.T["officeWaitMs"])
		pos = office.global_position + office.door_stand(door, 0, progress)
		face = player.global_position
	else:
		pos = world.stand_position(room, 0)
		face = world.camera_transform(room).origin
	var walker := _walkers.get("xivvy") as NightWatchWalker
	if walker == null:
		walker = NightWatchWalker.new()
		_walkers["xivvy"] = walker
		walker.place(pos, pos, face, room)
	elif manual_clock:
		walker.place(pos, pos, face, room)
	elif walker.room != room:
		walker.go(paths.legs_from(walker.pos, room), room, pos, NightWatchWalker.budget_for(sim.level_of("xivvy")))
		walker.look = face
	else:
		walker.final = pos
		walker.look = face
	xivvy.position = walker.pos
	xivvy.rotation.y = walker.yaw
	# a phantom shows on one camera for a few seconds
	for id in LureLogic.PHANTOM_IDS:
		var m := _models[id] as Node3D
		var shown: bool = not sim.phantom.is_empty() and sim.phantom["id"] == id
		m.visible = shown
		if shown:
			_set_model_pose(m, world.stand_position(String(sim.phantom["room"]), 1), world.camera_transform(String(sim.phantom["room"])).origin)
	# the climate pair at the last stage: in the office, creeping toward the desk
	for entry in [["wynelle", sim.cold], ["solyth", sim.heat]]:
		var m2 := _models[entry[0]] as Node3D
		var amount: float = entry[1]
		m2.visible = amount >= 85.0
		if m2.visible:
			var from := office.global_position + office.door_stand("doorL" if entry[0] == "wynelle" else "doorR", 0, 0.0)
			var to := office.global_position + Vector3(-0.7 if entry[0] == "wynelle" else 0.7, 0.0, -0.9)
			_set_model_pose(m2, from.lerp(to, clampf((amount - 85.0) / 15.0, 0.0, 1.0)), player.global_position)


func _set_model_pose(model: Node3D, pos: Vector3, face: Vector3) -> void:
	model.position = pos
	var d := face - pos
	d.y = 0.0
	if d.length() > 0.01:
		model.rotation.y = atan2(d.x, d.z) + PI   # the blocky models' front is -Z


func _animate_models(delta: float) -> void:
	for id in _walkers:
		var walker := _walkers[id] as NightWatchWalker
		if not manual_clock:
			walker.step(delta)
		var model := _models[id] as Node3D
		model.position = walker.pos
		model.rotation.y = walker.yaw
	_vent_pose(delta)
	for id in _players:
		var anim := _players[id] as AnimationPlayer
		if id == "xivvy" and String(_pose_state.get("xivvy", "")) != "":
			continue   # the vent crawl owns her animation
		var walker2 := _walkers.get(id) as NightWatchWalker
		var clip := "idle"
		if walker2 != null and walker2.moving:
			clip = "sprint" if walker2.running and anim.has_animation("sprint") else "walk"
		if anim.has_animation(clip) and anim.current_animation != clip:
			anim.play(clip)
	if state == State.PLAYING and not manual_clock and sim != null:
		office.animate({"doorL": bool(sim.seals["L"]), "doorR": bool(sim.seals["R"])}, delta)


## Xivvy in a vent shaft or crawlspace crawls (NightWatchPoses): a drop in ("vent_enter", a one-shot only Verrine has), the crawl loop (the generic vent crawl, its speed
## follows how fast she is moving), a rise out ("vent_exit"), then back to walking. The crawl is 0.67 m high, well under the crawlspaces' ceiling.
const VENT_ROOMS := ["ventl", "ventr", "officeL", "officeR"]
const VENT_ONE_SHOT := 0.8


func _vent_pose(delta: float) -> void:
	if sim == null or not _models.has("xivvy"):
		return
	var model := _models["xivvy"] as Node3D
	var in_vent := VENT_ROOMS.has(String(sim.killer["room"])) and model.visible
	var cur := String(_pose_state.get("xivvy", ""))
	var next := cur
	match cur:
		"":
			if in_vent:
				next = "vent_enter"
		"vent_enter":
			_vent_left -= delta
			if not in_vent and _vent_left <= 0.0:
				next = "vent_exit"
			elif _vent_left <= 0.0:
				next = "vent"
		"vent":
			if not in_vent:
				next = "vent_exit"
		"vent_exit":
			_vent_left -= delta
			if in_vent:
				next = "vent_enter"
			elif _vent_left <= 0.0:
				next = ""
	var walker := _walkers.get("xivvy") as NightWatchWalker
	if next != cur:
		_pose_state["xivvy"] = next
		_vent_left = VENT_ONE_SHOT
		match next:
			"":
				NightWatchPoses.stop(model)
			"vent_enter", "vent_exit":
				NightWatchPoses.play_state(model, next, {"hunter_id": "xivvy"})
			"vent":
				NightWatchPoses.play_state(model, "vent", {"hunter_id": "xivvy"})
	if String(_pose_state.get("xivvy", "")) == "vent" and _players.has("xivvy"):
		var speed := 0.15
		if walker != null and walker.moving:
			speed = 2.0 if walker.running else 1.0
		(_players["xivvy"] as AnimationPlayer).speed_scale = speed


# --- input -----------------------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		var key := (event as InputEventKey).keycode
		if state == State.PAUSED and key == KEY_BACKSPACE:
			back_to_board()
			return
		if state == State.WON or state == State.LOST:
			if key == KEY_ESCAPE:
				back_to_board()
				return
			if key == KEY_ENTER or key == KEY_KP_ENTER:
				if state == State.LOST:
					retry()
				elif hud.end_next.visible:
					next_level()
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
		if event is InputEventKey and (event as InputEventKey).pressed:
			var pk := (event as InputEventKey).physical_keycode
			match pk:
				KEY_L: do_lure()
				KEY_Q: do_reboot("audio")
				KEY_W: do_reboot("cams")
				KEY_E: do_reboot("vent")
				KEY_R: do_reboot("heater")
				KEY_T: do_reboot("fan")
				KEY_N: hud.toggle_mute()
			if pk in [KEY_L, KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T, KEY_N]:
				return
		return
	if event.is_action_pressed(NightWatchControls.DOOR_LEFT):
		toggle_seal("L")
	elif event.is_action_pressed(NightWatchControls.DOOR_RIGHT):
		toggle_seal("R")
	elif event.is_action_pressed(NightWatchControls.LIGHT_LEFT):
		_note(toggle_appliance("heater"))
	elif event.is_action_pressed(NightWatchControls.LIGHT_RIGHT):
		_note(toggle_appliance("fan"))
	elif event.is_action_pressed(NightWatchControls.LAMP):
		toggle_lamp()
	elif event.is_action_pressed(&"office_radio"):
		hud.toggle_mute()


func _note(message: String) -> void:
	if not message.is_empty():
		hud.show_note(message)


# --- the end of a night ----------------------------------------------------------------------------------------------

func _freeze_player() -> void:
	player.input_frozen = true
	player.look_frozen = true
	MouseLock.claim("night_watch_end", true)


func _finish_win() -> void:
	state = State.WON
	close_monitor()
	_freeze_player()
	NightWatchSounds.win()
	var score := record_win()
	var more := has_next_level()
	var air_left := int(round(100.0 - sim.stress))
	var body := "6:00 AM\nThe air held until morning. Air left: %d%%." % air_left
	if is_custom:
		body += "\nScore %d  %s  (best %d)" % [score, NightWatchModesData.rating_of(score, 400), NightWatchSave.best_score(mode_id)]
	else:
		body += ("\nNight %d is open." % (night + 1)) if more else "\nYou cleared every night."
	hud.show_end("CUSTOM NIGHT COMPLETE" if is_custom else "NIGHT %d COMPLETE" % night, body, more)
	finished.emit("win")


func _finish_caught() -> void:
	state = State.LOST
	close_monitor()
	_freeze_player()
	NightWatchSounds.caught()
	var cause := {"hunter_id": sim.by}
	if sim.by == "wynelle":
		cause["via"] = "cold"
	var name_text := String(LureData.NAMES.get(sim.by, sim.by.capitalize()))
	var picked := DeathLines.pick(cause, "nightwatch:lure:%d" % seed_value, night, name_text)
	last_death = {"by": sim.by, "name": name_text, "picked": picked}
	finished.emit("caught")
	if DeathMoment.plays(picked) and not _admin_no_scare:
		death_moment.play(name_text, picked)
	else:
		_after_death_moment()


func _after_death_moment() -> void:
	if state != State.LOST:
		return
	var h := NightWatchData.hour_label(NightWatchData.hour_index(sim.elapsed))
	var line := "%s got in through the vent at %s." % [last_death.get("name", "Xivvy"), h]
	match String(last_death.get("by", "")):
		"mavrine":
			line = "The air gave out at %s." % h
		"wynelle":
			line = "The cold took the office at %s." % h
		"solyth":
			line = "The heat took the office at %s." % h
	hud.show_end("CAUGHT", line, false)


# --- admin hooks (NightWatchAdmin builds the menu from the ones a game has; each really changes the game) ---------------------

func admin_status() -> String:
	var k: Dictionary = sim.killer
	var rows := ["XIVVY  %s  side %s  AI %d%s" % [k["room"], k["side"], sim.level_of("xivvy"), "  LURED %ds" % int(float(k["lureLeft"]) / 1000.0) if float(k["lureLeft"]) > 0.0 else ""]]
	for id in LureLogic.PHANTOM_IDS:
		rows.append("%s  AI %d  %s" % [id.to_upper(), sim.level_of(id), "ready" if float(sim.phantom_ai[id]["cool"]) <= 0.0 else "cool %ds" % int(float(sim.phantom_ai[id]["cool"]) / 1000.0)])
	var down := []
	for name in sim.systems:
		if sim.systems[name]["state"] != "ok":
			down.append(name)
	return "DEAD AIR  NIGHT %d  %s  AIR %d%%  %d F\nSEALS %s%s  DOWN: %s\nFROZEN %s  GOD %s  NO SCARE %s  SPEED %.1fX\n%s" % [night, NightWatchData.hour_label(NightWatchData.hour_index(sim.elapsed)),
		int(round(100.0 - sim.stress)), int(round(sim.temp)), "L" if sim.seals["L"] else "-", "R" if sim.seals["R"] else "-", ", ".join(PackedStringArray(down)) if not down.is_empty() else "none",
		str(_admin_frozen), str(sim.god), str(_admin_no_scare), sim.hunter_speed, "\n".join(PackedStringArray(rows))]


func admin_jump_to(target_level: int) -> void:
	NightWatchSession.start_mode(mode_id, target_level)
	get_tree().paused = false
	if get_tree().current_scene == self:
		get_tree().reload_current_scene()


func admin_set_hour(hour_value: int) -> void:
	sim.elapsed = clampf(float(hour_value) * NightWatchData.HOUR_MS, 0.0, NightWatchData.NIGHT_MS - 1000.0)
	_hour_seen = NightWatchData.hour_index(sim.elapsed)
	_sync_visuals()


func admin_set_frozen(on: bool) -> void:
	_admin_frozen = on


func admin_is_frozen() -> bool:
	return _admin_frozen


## "Power" in Dead Air is the air: 100 = clear, 0 = the air gives out.
func admin_set_power(percent: float) -> void:
	sim.stress = clampf(100.0 - percent, 0.0, 100.0)
	_sync_visuals()


func admin_set_infinite_power(on: bool) -> void:
	sim.infinite_stress = on


func admin_infinite_power() -> bool:
	return sim.infinite_stress


func admin_set_god(on: bool) -> void:
	sim.god = on


func admin_is_god() -> bool:
	return sim.god


func admin_set_no_scare(on: bool) -> void:
	_admin_no_scare = on


func admin_no_scare() -> bool:
	return _admin_no_scare


func admin_set_noclip(on: bool) -> void:
	_admin_noclip = on
	player.set_admin_noclip(on)


func admin_is_noclip() -> bool:
	return _admin_noclip


func admin_set_reveal(on: bool) -> void:
	_admin_reveal = on
	_sync_visuals()


func admin_is_reveal() -> bool:
	return _admin_reveal


func admin_set_hunter_speed(mult: float) -> void:
	sim.hunter_speed = clampf(mult, 0.1, 8.0)


func admin_hunter_ids() -> Array:
	return LureData.CAST.duplicate()


func admin_set_hunter_level(id: String, level_value: int) -> void:
	sim.set_level(id, level_value)
	_sync_visuals()


func admin_places() -> Array:
	var places := LureData.ROOMS.duplicate()
	places.append("officeL")
	places.append("officeR")
	return places


## Xivvy goes to a room (or a vent opening); a phantom shows in that room's camera.
func admin_place_hunter(id: String, place: String) -> void:
	if id == "xivvy":
		sim.killer["room"] = place
		sim.killer["atMs"] = 0.0
		(sim.killer["pacer"] as NightWatchPacer).reset()
	elif LureLogic.PHANTOM_IDS.has(id) and LureData.ROOMS.has(place):
		sim.phantom = {"id": id, "room": place, "t": 0.0}
	_sync_visuals()


func admin_play_call() -> void:
	var entry := NightWatchCallsData.for_level(mode_id, level)
	hud.set_call_script(NightWatchCallScript.new(entry.get("lines", ["Zellia, on the headset."]), 0.0))
	hud.update_call(0.0, 0.0)


func admin_skip_call() -> void:
	if hud.call_script != null:
		hud.call_script.mute()
	hud.show_call("")


func admin_win() -> void:
	if state == State.PLAYING:
		sim.over = "win"
		_finish_win()


func admin_lose() -> void:
	if state == State.PLAYING:
		sim.over = "caught"
		sim.by = "xivvy"
		_finish_caught()


## Dead Air's own controls: lure now (no cooldown, no audio needed), a system down or back, a seal, the temperature and the appliances, the air.
func admin_force_lure(room: String) -> void:
	if LureData.ROOMS.has(room) and not room.begins_with("vent"):
		sim.killer["target"] = room
		sim.killer["dist"] = {}
		sim.killer["lureLeft"] = LureLogic.T["lureMs"]


func admin_reset_lure_cooldown() -> void:
	sim.lure_cool = 0.0


func admin_set_system(system_name: String, broken: bool) -> void:
	if not sim.systems.has(system_name):
		return
	sim.systems[system_name] = {"state": "broken" if broken else "ok", "t": 0.0}
	if broken and system_name == "heater":
		sim.heater_on = false
	if broken and system_name == "fan":
		sim.fan_on = false
	_sync_visuals()


func admin_set_seal(side: String, on: bool) -> void:
	sim.seals[side] = on
	_sync_visuals()


func admin_set_temperature(degrees: float) -> void:
	sim.temp = clampf(degrees, 20.0, 130.0)
	_sync_visuals()


func admin_set_appliance(appliance: String, on: bool) -> void:
	if appliance == "heater":
		sim.heater_on = on
		if on:
			sim.fan_on = false
	elif appliance == "fan":
		sim.fan_on = on
		if on:
			sim.heater_on = false
	_sync_visuals()


func admin_clear_climate() -> void:
	sim.cold = 0.0
	sim.heat = 0.0
	sim.temp = 70.0
	_sync_visuals()


func _exit_tree() -> void:
	MouseLock.release_all()
	NightWatchControls.unregister()
	if get_tree() != null:
		get_tree().paused = false
