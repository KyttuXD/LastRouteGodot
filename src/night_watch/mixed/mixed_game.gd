class_name MixedGame
extends NightWatchMode

## Mixed Shift and Endless (mode `mixed`), the 3D shift scene: the transit hub (MixedMap: its own non-Classic layout) around the security room with three permanent vents, a vent run above the building (CAM 9),
## a drawn roster of threats (3 to 7 of the pool of eight, each with a tell and an answer) run by a pacing director, and no captions: every warning is a sound, a light, a
## figure or a pulsing camera button. The rules are MixedLogic (a port of mixed-logic.js, seeded like the 2D game). You are the shared player and USE stations: the monitor,
## the DOOR buttons (toggle), the three vent hatches (hold to seal), the desk lamp, the chair. Quick keys: Z / X doors, V / B / N hold to seal the left / top / right vent,
## tap G / Y / H the vent light, R held winds the music box, U the monitor, 1-8 / arrows / 9 the cameras. Hunters WALK (NightWatchPaths / NightWatchWalker).
## The five shifts (QUIET, STEADY, RESTLESS, CHAOS, ENDLESS) are all open; Endless has no 6 AM and saves its best hour (NightWatchSave.record_best, in hours).
## `manual_clock` stops the real-time clock so the validators step the shift themselves with advance_ms().

enum State { PLAYING, PAUSED, WON, LOST }

const SIDE_DOOR := {"L": "doorL", "R": "doorR"}
const HOLDS := [[&"nw_mx_seal_l", "L"], [&"nw_mx_seal_t", "T"], [&"nw_mx_seal_r", "R"]]
const VENT_RUN_ORIGIN := Vector3(-8.0, 0.0, -62.0)

var state: State = State.PLAYING
var sim: MixedLogic
var rng_seed := 0
var office: MixedOffice
var world: MixedWorld
var player: PlayerController3D
var hud: NightWatchHud
var hunters_root: Node3D
var death_moment: DeathMoment
var world_env: WorldEnvironment
var last_death := {}
var monitor_up := false
var vent_run: Node3D
var box_prop: Node3D
var cam9_button: Button

var _models := {}
var _walkers := {}
var _players := {}
var _hour_seen := 0
var _seal_held := {"L": false, "T": false, "R": false}
var _light_down := {"L": false, "T": false, "R": false}
var _wind_held := false
var _shown_room := ""
var _vent_pose := NightWatchVentPose.new()
## Admin (NightWatchAdmin): the menu (null for non-admins) and the live switches the admin hooks below set.
var admin_menu: AdminMenu
var _admin_frozen := false
var _admin_no_scare := false
var _admin_reveal := false
var _admin_noclip := false
var _admin_god := false
var _admin_infinite_seal := false

var monitor_room: String:
	get:
		return String(sim.s["mon"]["room"]) if sim != null else MixedData.CAM_ROOMS[0]


func _ready() -> void:
	NightWatchControls.register()
	MixedControls.register()
	read_session()
	level = clampi(level, 1, 5)
	_build_world()
	sim = MixedLogic.new(seed_value, level - 1)
	_spawn_hunters()
	hud.set_call_script(NightWatchCallScript.new([], 0.0))
	hud.mode_text = "9. Mixed Shift · %s" % String(sim.diff["name"])
	admin_menu = NightWatchAdmin.attach(self)   # after the sim exists
	hud.hint_label.text = MixedControls.hint(false) + _admin_hint()
	_set_feed(MixedData.CAM_ROOMS[0])
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
	world_env.environment = env
	add_child(world_env)
	office = NightWatchOfficeRegistry.make("mixed") as MixedOffice
	office.name = "Office"
	add_child(office)
	world = MixedWorld.new()
	world.name = "Hub"
	world.dress_set = MixedMap.set_for_seed(seed_value)
	world.office = office
	add_child(world)
	_build_vent_run()
	hunters_root = Node3D.new()
	hunters_root.name = "Hunters"
	add_child(hunters_root)
	hud = NightWatchHud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.camera_selected.connect(func(map_room: String): select_camera(MixedMap.sim_for(map_room)))
	hud.retry_pressed.connect(retry)
	hud.next_pressed.connect(next_night)
	hud.menu_pressed.connect(back_to_board)
	hud.pause_requested.connect(func(): set_paused(true))
	hud.cameras_requested.connect(toggle_monitor)
	hud.resume_pressed.connect(func(): set_paused(false))
	hud.subtitles_toggled.connect(func(on: bool):
		hud.set_subtitles(on)
		NightWatchSave.set_subtitles(on))
	hud.set_subtitles(NightWatchSave.subtitles())
	hud.set_cam_layout(MixedSkin.layout_for(world.dress_set))   # the night's skin on the hub's minimap: nine cameras (CAM 9 is the vent run)
	_apply_skin_light()
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


## The vent run (CAM 9): a duct above the building, six spots along it (the far hatch, the middle, the junction, the left and right branches, the spot by the camera).
func _build_vent_run() -> void:
	vent_run = Node3D.new()
	vent_run.name = "VentRun"
	vent_run.position = VENT_RUN_ORIGIN
	add_child(vent_run)
	var A2 := NightWatchArt
	A2.box(vent_run, Vector3(8.0, 0.2, 2.2), Vector3(0, -0.1, 0), {"name": "DuctFloor", "kind": "metal", "tint": Color(0.7, 0.72, 0.78)})
	for sz in [-1.1, 1.1]:
		A2.box(vent_run, Vector3(8.0, 2.4, 0.15), Vector3(0, 1.2, sz), {"name": "DuctSide", "kind": "metal", "tint": Color(0.6, 0.62, 0.7)})
	A2.box(vent_run, Vector3(8.0, 0.15, 2.4), Vector3(0, 2.45, 0), {"name": "DuctTop", "kind": "metal", "tint": Color(0.5, 0.52, 0.6)})
	A2.box(vent_run, Vector3(0.15, 2.4, 2.2), Vector3(-4.0, 1.2, 0), {"name": "DuctEnd", "kind": "metal", "tint": Color(0.4, 0.4, 0.45)})
	for i in 7:   # ribs: thin rings (top and both sides), never a wall across the run
		A2.box(vent_run, Vector3(0.08, 0.12, 2.1), Vector3(-3.0 + i, 2.3, 0), {"name": "DuctRib", "kind": "metal", "tint": Color(0.7, 0.7, 0.75)})
		for rz in [-1.0, 1.0]:
			A2.box(vent_run, Vector3(0.08, 2.3, 0.12), Vector3(-3.0 + i, 1.2, rz), {"name": "DuctRib", "kind": "metal", "tint": Color(0.7, 0.7, 0.75)})
	for bz in [-1.0, 1.0]:
		A2.box(vent_run, Vector3(0.8, 0.02, 0.4), Vector3(0.5 if bz < 0 else 1.5, 0.01, bz * 0.7), {"name": "GlowDuct", "tint": Color(0.8, 0.8, 1.0)})


func vent_spot_pos(spot: int) -> Vector3:
	return vent_run.global_position + Vector3(-2.5 + spot, 0.0, 0.0)


func feed_transform(room: String) -> Transform3D:
	if room == "vent":
		var from := vent_run.global_position + Vector3(3.6, 1.7, 0.0)
		return Transform3D(Basis.IDENTITY, from).looking_at(vent_run.global_position + Vector3(-2.0, 0.6, 0.0), Vector3.UP)
	return world.camera_transform(room)


func face_player(yaw: float, pitch := 0.0) -> void:
	player.rotation.y = yaw
	player.set("_yaw", yaw)
	player.set("_pitch", pitch)
	player.call("_apply_look_rotation")


func _wire_stations() -> void:
	var st: Dictionary = office.stations
	(st["monitor"] as NightWatchStation).on_activate = func(_p) -> String:
		toggle_monitor()
		return ""
	(st["doorL_door"] as NightWatchStation).on_activate = func(_p) -> String:
		toggle_door("L")
		NightWatchSounds.panel_button()
		return ""
	(st["doorR_door"] as NightWatchStation).on_activate = func(_p) -> String:
		toggle_door("R")
		NightWatchSounds.panel_button()
		return ""
	(st["lamp"] as NightWatchStation).on_activate = func(_p) -> String:
		office.set_lamp(not office.lamp.visible)
		return ""
	(st["chair"] as NightWatchStation).on_activate = func(p) -> String:
		return String(p.use_furniture(st["chair"], "sit"))
	for id in ["ventL", "ventR", "ventT", "doorL_light", "doorR_light", "breaker"]:
		(st[id] as NightWatchStation).on_activate = func(_p) -> String: return ""   # held, see _process


func _spawn_hunters() -> void:
	for p in MixedData.POOL:
		var id := String(p["id"])
		var model := NightWatchHunterScale.instantiate(HunterRoster.get_identity(id))
		if model == null:
			push_warning("Mixed Shift: no model for %s" % id)
			model = Node3D.new()
		model.name = "Hunter_%s" % id
		hunters_root.add_child(model)
		_models[id] = model
		var ap := ModelSlot.find_animation_player(model)
		if ap != null:
			_players[id] = ap
			if ap.has_animation("idle"):
				ap.play("idle")
		model.visible = false
	box_prop = Node3D.new()
	box_prop.name = "MusicBox"
	add_child(box_prop)
	NightWatchArt.box(box_prop, Vector3(0.5, 0.3, 0.4), Vector3(0, 0.15, 0), {"name": "BoxMusicBody", "kind": "wood", "tint": Color(1.2, 0.9, 1.1)})
	NightWatchArt.box(box_prop, Vector3(0.3, 0.03, 0.03), Vector3(0, 0.36, 0.2), {"name": "GlowGauge"})
	box_prop.visible = false


# --- player actions (also what the validators press) -------------------------------------------------------------------------

func is_playing() -> bool:
	return state == State.PLAYING


func toggle_door(side: String) -> void:
	if state != State.PLAYING:
		return
	var want: bool = not bool(sim.s["door"][side]["want"])
	var shut := sim.set_door(side, want)
	if want and shut or not want:
		NightWatchSounds.door(shut)


## Hold a vent's seal (true) or let go (false).
func set_seal(key: String, on: bool) -> void:
	if state == State.PLAYING:
		sim.set_vent(key, on)
		_seal_held[key] = on


## Tap the vent light down vent `key`.
func flash_vent(key: String) -> Dictionary:
	if state != State.PLAYING:
		return {"ok": false, "why": "over", "seen": []}
	var res := sim.light_vent(key)
	if bool(res["ok"]):
		NightWatchSounds.panel_button()
	return res


func set_wind(on: bool) -> void:
	if state == State.PLAYING:
		sim.set_wind(on)
		_wind_held = on
		_sync_feed()


func open_monitor(room := "") -> void:
	if state != State.PLAYING or monitor_up:
		return
	monitor_up = true
	sim.set_monitor(true)
	if room != "":
		sim.set_room(room)
	player.input_frozen = true
	player.look_frozen = true
	MouseLock.claim("night_watch_monitor", true)
	hud.show_monitor(true)
	hud.hint_label.text = MixedControls.hint(true) + _admin_hint()
	_set_feed(monitor_room)
	hud.flash_static()
	NightWatchSounds.monitor_toggle()


func close_monitor() -> void:
	if not monitor_up:
		return
	monitor_up = false
	sim.set_monitor(false)
	MouseLock.claim("night_watch_monitor", false)
	player.input_frozen = state != State.PLAYING
	player.look_frozen = state != State.PLAYING
	hud.show_monitor(false)
	hud.hint_label.text = MixedControls.hint(false) + _admin_hint()
	NightWatchSounds.monitor_toggle()


func toggle_monitor() -> void:
	if monitor_up:
		close_monitor()
	else:
		open_monitor()


func camera_rooms() -> Array:
	return NightWatchData.cam_rooms()


func camera_room_for(n: int) -> String:
	return NightWatchData.room_for_cam(n)


func select_camera(room: String) -> void:
	if state != State.PLAYING or not monitor_up or not MixedData.CAM_ROOMS.has(room):
		return
	sim.set_room(room)
	_set_feed(room)
	hud.flash_static()
	NightWatchSounds.camera_switch()


func select_camera_number(n: int) -> void:
	if n >= 1 and n <= MixedData.CAM_ROOMS.size():
		select_camera(String(MixedData.CAM_ROOMS[n - 1]))


## Left / right through the eight building cameras (the vent run, CAM 9, is picked with 9 or its map button).
func cycle_camera(step: int) -> void:
	var rooms := camera_rooms()
	var i := rooms.find(monitor_room)
	if i < 0:
		i = 0 if step > 0 else rooms.size() - 1
		select_camera(String(rooms[i]))
		return
	select_camera(String(rooms[posmod(i + step, rooms.size())]))


func _set_feed(room: String) -> void:
	_shown_room = room
	hud.set_cam(MixedMap.map_for(room), feed_transform(room))


## A winding hold jumps the monitor to the music box's camera (the rules do it): follow it on screen.
func _sync_feed() -> void:
	if monitor_up and monitor_room != _shown_room:
		_set_feed(monitor_room)
		hud.flash_static()


func set_paused(on: bool) -> void:
	if state == State.WON or state == State.LOST:
		return
	state = State.PAUSED if on else State.PLAYING
	get_tree().paused = on
	hud.show_pause(on)
	MouseLock.claim("night_watch_pause", on)


## The board lists the four scored shifts; Endless (the fifth) has no next.
func has_next_level() -> bool:
	return level < scored_levels()


func next_night() -> void:
	next_level()


# --- the clock ---------------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_animate_models(delta)
	if state != State.PLAYING:
		return
	var aimed := player.call("_nearest_interactable") as NightWatchStation if not monitor_up else null
	hud.set_prompt(player.get_interaction_prompt() if not monitor_up else "")
	if manual_clock:
		return
	for h in HOLDS:
		var key := String(h[1])
		var station := "vent" + key
		var by_station: bool = Input.is_action_pressed(&"interact") and aimed != null and aimed.station_id == station
		var want: bool = Input.is_action_pressed(StringName(h[0])) or by_station
		if want != bool(_seal_held[key]):
			set_seal(key, want)
	for key in ["L", "T", "R"]:
		var down: bool = Input.is_action_pressed(MixedControls.FLASH[key])
		if down and not bool(_light_down[key]):
			flash_vent(key)
		_light_down[key] = down
	var wind: bool = Input.is_action_pressed(&"office_radio")
	if wind != _wind_held:
		set_wind(wind)
	advance_ms(delta * 1000.0)


## Step the shift by dt_ms (in steps of at most 100 ms, as the 2D game's frames) and show what happened.
func advance_ms(dt_ms: float) -> void:
	var left := dt_ms
	while left > 0.0 and state == State.PLAYING and not _admin_frozen:
		var dt := minf(left, 100.0)
		left -= dt
		var events := sim.step(dt)
		if _admin_infinite_seal:
			sim.s["seal"] = sim.seal_max
			sim.s["ventSeal"] = MixedData.VENT_SEAL_MAX
		if _admin_god and String(sim.s["over"]) == "caught":
			_god_rescue()
			events = []
		for e in events:
			_on_event(e)
		_post_step()


func _post_step() -> void:
	var hour := sim.hour_of()
	if hour != _hour_seen:
		_hour_seen = hour
		NightWatchSounds.hour_change()
	_sync_feed()
	_sync_visuals()
	if String(sim.s["over"]) == "win":
		_finish_win()
	elif String(sim.s["over"]) == "caught":
		_finish_caught()


func _pan_for_side(side: String) -> float:
	return -1.0 if side == "L" else (1.0 if side == "R" else 0.0)


func _on_event(e: Dictionary) -> void:
	var side := String(e.get("side", ""))
	match String(e["type"]):
		"step", "turned":
			var room := String(e.get("room", ""))
			NightWatchSounds.office("footsteps", float(NightWatchData.ROOMS.get(room, {}).get("pan", 0.0)), 0.8)
			if monitor_up and room == monitor_room:
				hud.flash_static()
		"arrive":
			NightWatchSounds.office("crimson_door", _pan_for_side(side), 1.0)
		"tell":
			NightWatchSounds.attack_warning(_pan_for_side(side))
		"pulse":
			NightWatchSounds.office("presence", _pan_for_side(side), 0.7)
		"echo":
			NightWatchSounds.office("camera", 0.0, 0.8)
		"stop":
			NightWatchSounds.attack_warning(0.0)
		"wound", "hum":
			NightWatchSounds.office("control", 0.0, 0.3 if String(e["type"]) == "hum" else 0.8)
		"answered", "gone":
			NightWatchSounds.office("scrape", _pan_for_side(side), 0.8)
		"strain", "ventstrain":
			NightWatchSounds.office("scrape", 0.0, 1.0)
		"doorshut", "ventshut", "ventopen":
			NightWatchSounds.panel_button()
		"feint":
			NightWatchSounds.office("footsteps" if String(e["kind"]) == "step" else "presence", _pan_for_side(side), 0.3)
		"spike":
			if String(e.get("phase", "")) == "warn":
				NightWatchSounds.office("drain", 0.0, 0.6)
		"chaos":
			if String(e.get("phase", "")) == "start":
				NightWatchSounds.office("static", 0.0, 0.8)
		"hour":
			NightWatchSounds.hour_change()
		"rotate":
			NightWatchSounds.hour_change()
			if sim.endless:   # ENDLESS keeps cycling: the roster re-draws and the map goes on to the next skin
				admin_set_dressing(MixedSkin.pick(seed_value + int(e.get("gen", 0))))
				hud.flash_static()


# --- what you see ------------------------------------------------------------------------------------------------------------

func _sync_visuals() -> void:
	if _admin_reveal:
		var maps := []
		var occ := sim.occupancy()
		for room in occ:
			if not (occ[room] as Array).is_empty():
				maps.append(MixedMap.map_for(String(room)))
		hud.cam_map.set_blips(maps)
	elif hud.cam_map.blips.size() > 0:
		hud.cam_map.set_blips([])
	var s := sim.s
	var doors: Dictionary = s["door"]
	if manual_clock:
		office.snap_slabs({"doorL": doors["L"]["shut"], "doorR": doors["R"]["shut"]})
	for side in ["L", "R"]:
		var door: String = SIDE_DOOR[side]
		office.set_button("%s_door" % door, bool(doors[side]["shut"]))
		# the doors' light pulses with a deadly tell at that door (the tell's light)
		var pulsing := false
		for th in sim.list():
			if bool(th["armed"]) and bool(th["tellOn"]) and String(th["side"]) == side and String(th["type"]) != "vent":
				pulsing = int(float(s["elapsed"]) / 300.0) % 2 == 0
		office.set_light(door, pulsing)
	for key in ["L", "R", "T"]:
		(office.shutters[key] as Node3D).visible = bool(s["vent"][key]["shut"])
		(office.flashes[key] as Node3D).visible = float(s["vent"][key]["flash"]) > 0.0
	var devices := (1 if bool(doors["L"]["shut"]) else 0) + (1 if bool(doors["R"]["shut"]) else 0) + (1 if monitor_up else 0)
	hud.update_status(sim.hour_of() % 6, 100.0 * float(s["seal"]) / sim.seal_max, devices, level)
	hud.power_label.text = "DOOR SEAL %d%%" % int(round(100.0 * float(s["seal"]) / sim.seal_max))
	hud.usage_label.text = "VENT SEAL %d%%" % int(round(100.0 * float(s["ventSeal"]) / MixedData.VENT_SEAL_MAX))
	if sim.endless:
		hud.clock_label.text = MixedData.endless_clock(float(s["elapsed"]))
	_place_hunters()
	_sync_box()


func _sync_box() -> void:
	var winder := {}
	for t in sim.list():
		if String(t["type"]) == "winder":
			winder = t
			break
	box_prop.visible = not winder.is_empty()
	if winder.is_empty():
		return
	var room := String(winder["boxRoom"])
	box_prop.global_position = world.stand_position(room, 0) + Vector3(0.9, 0.0, -0.4)
	if monitor_up and monitor_room == room:
		hud.cam_label.text += "    TUNE %d%%%s    HOLD %s TO WIND" % [int(round(100.0 * float(winder["tune"]))), " STOPPED" if bool(winder["stopped"]) else "", NightWatchControls.key_text(&"office_radio")]


## Where a threat is and what she is doing, from the rules: {room (walker key), pos, face, visible, snap}.
func _target(th: Dictionary, slot: int) -> Dictionary:
	var id := String(th["id"])
	var type := String(th["type"])
	var face := player.global_position
	var o := office.global_position
	if bool(th["armed"]):
		var side := String(th["side"])
		if type == "vent":
			return {"room": "vent" + side, "pos": o + MixedOffice.VENT_STAND[side], "face": face, "visible": not bool(sim.s["vent"][side]["shut"]), "snap": true}
		if side == "":   # the Counter: her face at the lens
			return {"room": "lens", "pos": world.stand_position(monitor_room, 1), "face": feed_transform(monitor_room).origin, "visible": monitor_up, "snap": true}
		var door: String = SIDE_DOOR[side]
		var progress := float(th["armedMs"]) / maxf(1.0, float(th["tellNeed"]))
		return {"room": door, "pos": o + office.door_stand(door, 0, progress), "face": face, "visible": true}
	match type:
		"monitor":
			if bool(th["present"]):
				var sx := -2.2 if String(th["side"]) == "L" else 2.2
				return {"room": "office", "pos": o + Vector3(sx, 0.0, 0.9 - 0.3 * int(th["steps"])), "face": face, "visible": true, "snap": true}
		"counter":
			if float(th["c"]) >= float(MixedData.TIMING["counter"]["cueAt"]) and monitor_up:
				return {"room": "lens", "pos": world.stand_position(monitor_room, 1), "face": feed_transform(monitor_room).origin, "visible": true, "snap": true}
		_:
			if bool(th["active"]) and not (th["route"] as Array).is_empty():
				var room := String((th["route"] as Array)[int(th["i"])])
				if type == "vent":
					return {"room": "run", "pos": vent_spot_pos(sim.vent_spot_of(th)), "face": feed_transform("vent").origin, "visible": true}
				return {"room": room, "pos": world.stand_position(room, mini(slot, 1)), "face": world.camera_transform(room).origin, "visible": true}
	return {"room": "away", "pos": Vector3.ZERO, "face": face, "visible": false}


func _place_hunters() -> void:
	var slots := {}
	var in_roster := {}
	for th in sim.list():
		in_roster[String(th["id"])] = true
		var key := "%s/%d" % [String(th["route"][int(th["i"])]) if bool(th["active"]) and not (th["route"] as Array).is_empty() else "-", 0]
		var slot := int(slots.get(key, 0))
		slots[key] = slot + 1
		var tgt := _target(th, slot)
		var id := String(th["id"])
		var model := _models[id] as Node3D
		model.visible = bool(tgt["visible"])
		if not bool(tgt["visible"]):
			_walkers.erase(id)
			continue
		var pos: Vector3 = tgt["pos"]
		var walker := _walkers.get(id) as NightWatchWalker
		var room_key := String(tgt["room"])
		if walker == null:
			walker = NightWatchWalker.new()
			_walkers[id] = walker
			walker.place(pos, pos, tgt["face"], room_key)
		elif manual_clock or bool(tgt.get("snap", false)):
			walker.place(pos, pos, tgt["face"], room_key)
		elif walker.room != room_key:
			walker.go(_legs_to(walker, room_key, pos), room_key, pos)
			walker.look = tgt["face"]
		else:
			walker.final = pos
			walker.look = tgt["face"]
		model.position = walker.pos
		model.rotation.y = walker.yaw
	for id in _models:
		if not in_roster.has(id):
			(_models[id] as Node3D).visible = false
			_walkers.erase(id)


## The walk to a new place: along the transit hub's waypoints (the arcades, the concourse, the door halls); the vent run is a straight crawl.
func _legs_to(walker: NightWatchWalker, room_key: String, pos: Vector3) -> Array:
	if room_key == "run":
		return [{"p": pos, "jump": false}]
	return world.legs_from(walker.pos, room_key)


## The vent crawler is in a shaft while she crawls the vent run or waits at her vent.
func _in_shaft(id: String) -> bool:
	var th := sim.threat(id)
	return not th.is_empty() and String(th["type"]) == "vent" and (bool(th["active"]) or bool(th["armed"]))


func _animate_models(delta: float) -> void:
	for id in _walkers:
		var walker := _walkers[id] as NightWatchWalker
		if not manual_clock:
			walker.step(delta)
		var model := _models[id] as Node3D
		model.position = walker.pos
		model.rotation.y = walker.yaw
	for id in _players:
		var ap := _players[id] as AnimationPlayer
		var walker2 := _walkers.get(id) as NightWatchWalker
		if sim != null and _vent_pose.update(id, _models[id] as Node3D, _in_shaft(id), walker2 != null and walker2.moving, delta):
			continue
		var clip := "idle"
		if walker2 != null and walker2.moving:
			clip = "sprint" if walker2.running and ap.has_animation("sprint") else "walk"
		if ap.has_animation(clip) and ap.current_animation != clip:
			ap.play(clip)
	if state == State.PLAYING and not manual_clock and sim != null:
		office.animate({"doorL": sim.s["door"]["L"]["shut"], "doorR": sim.s["door"]["R"]["shut"]}, delta)


# --- input -------------------------------------------------------------------------------------------------------------------

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
	if monitor_up and event is InputEventKey and (event as InputEventKey).pressed and ((event as InputEventKey).keycode == KEY_9 or (event as InputEventKey).keycode == KEY_KP_9):
		select_camera("vent")
		return
	if event.is_action_pressed(NightWatchControls.DOOR_LEFT):
		toggle_door("L")
	elif event.is_action_pressed(NightWatchControls.DOOR_RIGHT):
		toggle_door("R")


# --- the end of a shift ------------------------------------------------------------------------------------------------------

func _freeze_player() -> void:
	if monitor_up:
		close_monitor()
	player.input_frozen = true
	player.look_frozen = true
	MouseLock.claim("night_watch_end", true)


func _finish_win() -> void:
	state = State.WON
	_freeze_player()
	NightWatchSounds.win()
	record_win()
	var more := has_next_level()
	hud.show_end("%s COMPLETE" % String(sim.diff["name"]), "6:00 AM\nYou held the building until 6 AM." + ("\n%s is open." % String(MixedData.shifts()[level]["name"]) if more else ""), more)
	finished.emit("win")


## What would have stopped it, for the CAUGHT card.
func advice_for(id: String) -> String:
	var th := sim.threat(id)
	if th.is_empty():
		return ""
	var type := String(th["type"])
	var name_text := String(MixedData.pool_entry(id).get("name", id))
	return "%s (%s): %s." % [name_text, String(MixedData.TYPES[type]["label"]), String(MixedData.TYPES[type]["answer"]).capitalize()]


func _finish_caught() -> void:
	state = State.LOST
	var by := String(sim.s["by"])
	var hours := sim.hour_reached()
	if sim.endless:
		NightWatchSave.record_best(mode_id, hours)
	_freeze_player()
	NightWatchSounds.caught()
	var name_text := String(MixedData.pool_entry(by).get("name", by.capitalize()))
	var picked := DeathLines.pick({"hunter_id": by}, "nightwatch:mixed:%d" % seed_value, level, name_text)
	last_death = {"by": by, "name": name_text, "picked": picked, "hours": hours, "advice": advice_for(by)}
	finished.emit("caught")
	if DeathMoment.plays(picked) and not _admin_no_scare:
		death_moment.play(name_text, picked)
	else:
		_after_death_moment()


func _after_death_moment() -> void:
	if state != State.LOST:
		return
	var body := "%s reached you.\n%s" % [String(last_death.get("name", "A threat")), String(last_death.get("advice", ""))]
	if sim.endless:
		body += "\nYou lasted %s. Best: %s." % [MixedData.hours_text(int(last_death.get("hours", 0))), MixedData.hours_text(NightWatchSave.best_score(mode_id))]
	hud.show_end("CAUGHT", body, false)


# --- admin hooks (NightWatchAdmin builds the menu from the ones a game has; each really changes the game) ---------------------

func _admin_hint() -> String:
	return "   0 admin" if admin_menu != null else ""


## God mode: whoever would catch you is answered (sent home), the tells stop, the seals come back.
func _god_rescue() -> void:
	sim.s["over"] = ""
	sim.s["by"] = ""
	for th in sim.list():
		sim.admin_send_home(String(th["id"]))
	sim.s["lock"] = ""
	sim.s["cool"] = MixedData.COOLDOWN_MS
	sim.s["seal"] = maxf(float(sim.s["seal"]), 8000.0)
	sim.s["ventSeal"] = maxf(float(sim.s["ventSeal"]), 4000.0)


func admin_status() -> String:
	var s := sim.s
	return "MIXED SHIFT  %s  %s (SEED %d)  DRESSING %s\nROSTER %s\nSEAL %d%%  VENT SEAL %d%%  BEAT %s  TENSION %.2f\nFROZEN %s  GOD %s  NO SCARE %s  SPEED %.1fX" % [String(sim.diff["name"]),
		MixedData.endless_clock(float(s["elapsed"])) if sim.endless else NightWatchData.hour_label(mini(5, sim.hour_of())), seed_value, String(MixedMap.SETS[world.dress_set]).to_upper(), ", ".join(PackedStringArray(sim.roster)).to_upper(),
		int(round(100.0 * float(s["seal"]) / sim.seal_max)), int(round(100.0 * float(s["ventSeal"]) / MixedData.VENT_SEAL_MAX)), String(s["beat"]).to_upper(), float(s["tension"]),
		str(_admin_frozen), str(_admin_god), str(_admin_no_scare), sim.hunter_speed]


func admin_hunter_rows() -> Array:
	var rows := []
	for th in sim.list():
		var where := String(th["route"][int(th["i"])]) if bool(th["active"]) and not (th["route"] as Array).is_empty() else "AWAY"
		rows.append("%s  %s  %s  %s%s" % [String(th["id"]).to_upper(), String(th["type"]), String(th["mood"]), where, "  TELL %.1f/%.1fs" % [float(th["armedMs"]) / 1000.0, float(th["tellNeed"]) / 1000.0] if bool(th["armed"]) else ""])
	return rows


func admin_jump_to(target_level: int) -> void:
	NightWatchSession.start_mode(mode_id, target_level)
	get_tree().paused = false
	if get_tree().current_scene == self:
		get_tree().reload_current_scene()


func admin_set_hour(hour_value: int) -> void:
	sim.admin_set_hour(hour_value if sim.endless else mini(hour_value, 5))
	_hour_seen = hour_value
	_sync_visuals()


func admin_set_frozen(on: bool) -> void:
	_admin_frozen = on


func admin_is_frozen() -> bool:
	return _admin_frozen


## "Power" is the doors' seal store.
func admin_set_power(percent: float) -> void:
	sim.s["seal"] = clampf(percent, 0.0, 100.0) / 100.0 * sim.seal_max
	_sync_visuals()


func admin_set_infinite_power(on: bool) -> void:
	_admin_infinite_seal = on


func admin_infinite_power() -> bool:
	return _admin_infinite_seal


func admin_set_god(on: bool) -> void:
	_admin_god = on


func admin_is_god() -> bool:
	return _admin_god


func admin_set_no_scare(on: bool) -> void:
	_admin_no_scare = on


func admin_no_scare() -> bool:
	return _admin_no_scare


func admin_set_hunter_speed(mult: float) -> void:
	sim.hunter_speed = clampf(mult, 0.1, 8.0)


func admin_hunter_ids() -> Array:
	return sim.roster.duplicate()


func admin_places() -> Array:
	return NightWatchData.cam_rooms() + ["doorL", "doorR", "ventL", "ventR", "ventT"]


func admin_place_hunter(id: String, place: String) -> void:
	sim.admin_place(id, place)
	_sync_visuals()


func admin_set_door(side: String, shut: bool) -> void:
	sim.set_door(side, shut)
	_sync_visuals()


## ROTATION: the shift's skin (MixedSkin: 0 transit hub ... 8 campsite), rebuilt on the same shape; the minimap labels, the light and the props follow.
func admin_set_dressing(index: int) -> void:
	var next := clampi(index, 0, MixedMap.SETS.size() - 1)
	remove_child(world)
	world.free()
	world = MixedWorld.new()
	world.name = "Hub"
	world.dress_set = next
	world.office = office
	add_child(world)
	_walkers.clear()
	hud.set_cam_layout(MixedSkin.layout_for(next))
	hud.set_cam(MixedMap.map_for(monitor_room), feed_transform(monitor_room))
	_apply_skin_light()
	_sync_visuals()


## The skin's ambient light and sky.
func _apply_skin_light() -> void:
	var skin := MixedSkin.skin(world.dress_set)
	world_env.environment.ambient_light_color = skin["light"]
	world_env.environment.background_color = skin["sky"]


func admin_set_reveal(on: bool) -> void:
	_admin_reveal = on
	_sync_visuals()


func admin_is_reveal() -> bool:
	return _admin_reveal


func admin_win() -> void:
	if state == State.PLAYING:
		sim.s["over"] = "win"
		_finish_win()


func admin_lose() -> void:
	if state == State.PLAYING:
		sim.s["over"] = "caught"
		sim.s["by"] = String(sim.roster[0])
		_finish_caught()


func admin_set_noclip(on: bool) -> void:
	_admin_noclip = on
	player.set_admin_noclip(on)


func admin_is_noclip() -> bool:
	return _admin_noclip


func _exit_tree() -> void:
	MouseLock.release_all()
	NightWatchControls.unregister()
	MixedControls.unregister()
	if get_tree() != null:
		get_tree().paused = false
