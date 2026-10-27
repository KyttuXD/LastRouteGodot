class_name LureGame
extends NightWatchMode

## Dead Air (mode `lure`), the shift scene: the same walkable security room as Classic (NightWatchOffice, the shared player, prompt and
## crosshair), with the two DOOR buttons sealing the vent openings (the slabs are the vent covers), the left and right LIGHT buttons switching
## the heater and the fan, and the monitor on the desk looking into the attraction hall (LureWorld). Rules: LureLogic. In the monitor: 1-8
## pick a camera, L lures Xivvy to the room on screen, Q / W / E / R / T reboot audio / cameras / vents / heater / fan (or click the buttons),
## N mutes Zellia. Quick keys outside it: Z / X seal the left / right vent, G / H heater / fan, U monitor, Y lamp, R mutes Zellia.
## Xivvy WALKS the hall (LurePaths, NightWatchWalker). `manual_clock` stops the real-time clock so the validators step the night with advance_ms().

enum State { PLAYING, PAUSED, WON, LOST }

var night := 1
var state: State = State.PLAYING
var sim: LureLogic
var office: NightWatchOffice
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
	if not is_custom:
		hud.queue_call(LureData.call_lines(night))
	_sync_visuals()
	_select_room(monitor_room, false)


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
	office = NightWatchOffice.new()
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
	hud.resume_pressed.connect(func(): set_paused(false))
	hud.subtitles_toggled.connect(func(on: bool):
		hud.set_subtitles(on)
		NightWatchSave.set_subtitles(on))
	hud.set_subtitles(NightWatchSave.subtitles())
	hud.hint_label.text = "WASD move   E use   Z / X seal vents   G / H heater / fan   U monitor   Y lamp   R radio   P pause"
	# the monitor: Classic's camera map goes, Dead Air's panel comes
	for b in hud.cam_buttons.values():
		(b as Control).get_parent().queue_free()
		break
	hud.cam_buttons.clear()
	panel = LurePanel.new()
	hud.monitor_root.add_child(panel)
	panel.room_selected.connect(select_camera)
	panel.lure_pressed.connect(func(): do_lure())
	panel.reboot_pressed.connect(func(system: String): do_reboot(system))
	_feed_container = hud.feed_viewport.get_parent() as Control
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
	for id in ["breaker", "vent"]:
		(st[id] as NightWatchStation).on_activate = func(_p) -> String: return String(office.prompts.get(id, ""))


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
	hud.feed_camera.transform = world.camera_transform(room)
	hud.cam_label.text = "CAM %d  %s" % [LureData.ROOMS.find(room) + 1, LureData.INFO[room]["label"]]
	if flash:
		hud.flash_static()
		NightWatchSounds.camera_switch()
	if sim != null:
		panel.refresh(sim, monitor_room)


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
	if state != State.PLAYING:
		return
	var events := sim.step(dt_ms, {"watch": watching()})
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
	for id in _players:
		var anim := _players[id] as AnimationPlayer
		var walker2 := _walkers.get(id) as NightWatchWalker
		var clip := "idle"
		if walker2 != null and walker2.moving:
			clip = "sprint" if walker2.running and anim.has_animation("sprint") else "walk"
		if anim.has_animation(clip) and anim.current_animation != clip:
			anim.play(clip)
	if state == State.PLAYING and not manual_clock and sim != null:
		office.animate({"doorL": bool(sim.seals["L"]), "doorR": bool(sim.seals["R"])}, delta)


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
	if monitor_up:
		if event.is_action_pressed(NightWatchControls.MONITOR) or event.is_action_pressed(&"interact"):
			close_monitor()
			return
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
				KEY_LEFT: cycle_camera(-1)
				KEY_RIGHT: cycle_camera(1)
			if pk in [KEY_L, KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T, KEY_N, KEY_LEFT, KEY_RIGHT]:
				return
		for n in range(1, 9):
			if event.is_action_pressed(NightWatchControls.camera_action(n)):
				select_camera(String(LureData.ROOMS[n - 1]))
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
	elif event.is_action_pressed(NightWatchControls.MONITOR):
		open_monitor()
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
	if DeathMoment.plays(picked):
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


func _exit_tree() -> void:
	MouseLock.release_all()
	NightWatchControls.unregister()
	if get_tree() != null:
		get_tree().paused = false
