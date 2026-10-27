class_name StoryGame
extends NightWatchMode

## The Facility (mode `story`), the shift scene: you walk five blocky rooms with the shared player (WASD, mouse, E to use, the shared crosshair and prompt)
## and do the night's task list at each room's station. Walking through a door (use the door button) is the 2D game's `move`: it takes 1.8 s (3.6 crawling,
## hold C) and the player is carried through the doorway on foot while the rules count it. Hold F for the beacon, H to hide under the desk in Control,
## hold E on the lift's call button. Opalie (gallery), Porcelle (workshop, auditorium) and Quenelle (the lift) WALK in as their step counts fall.
## Rules: StoryLogic. `manual_clock` stops the real-time clock so the validators step the night with advance_ms().

enum State { PLAYING, PAUSED, WON, LOST }

var night := 1
var state: State = State.PLAYING
var sim: StoryLogic
var world: StoryWorld
var player: PlayerController3D
var hud: NightWatchHud
var panel: StoryPanel
var hunters_root: Node3D
var death_moment: DeathMoment
var world_env: WorldEnvironment
var beacon: SpotLight3D
var last_death := {}
var held := {"light": false, "hide": false, "work": false}
var keypad_up := false
var crawl_override := false   # validators: crawl through the next door

var _models := {}
var _walkers := {}
var _players := {}
var _side := {"opalie": -1.0, "porcelle": 1.0}   # which way her far end lies from where you came in
var _porcelle_room := "workshop"
var _glide := {}
var _q_state := "away"
var _tasks_seen := 0


func _ready() -> void:
	StoryControls.register()
	read_session()
	night = clampi(level, 1, 6)
	var opts := {"night": night, "rng": NightWatchStream.seeded(seed_value)}
	if is_custom:
		night = 5
		opts = {"night": 5, "rng": NightWatchStream.seeded(seed_value), "custom": true, "levels": custom}
	_build_world()
	sim = StoryLogic.new(opts)
	_spawn_hunters()
	if not is_custom:
		hud.queue_call(StoryData.call_lines(night))
	_sync_visuals()


func _build_world() -> void:
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.38, 0.40, 0.55)
	env.ambient_light_energy = 0.9
	world_env.environment = env
	add_child(world_env)
	world = StoryWorld.new()
	world.name = "Facility"
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
	hud.hint_label.text = "WASD move   E use (hold E on the lift button)   hold F beacon   hold H hide in Control   hold C through a door to crawl   P pause"
	panel = StoryPanel.new()
	hud.add_child(panel)
	panel.digit_pressed.connect(func(d: String): keypad_digit(d))
	death_moment = DeathMoment.new()
	death_moment.name = "DeathMoment"
	add_child(death_moment)
	death_moment.finished.connect(_after_death_moment)
	player = (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	add_child(player)
	player.global_position = (world.rooms["control"] as Node3D).global_position + Vector3(0.0, 0.0, 0.6)
	face_player(0.0, -0.05)
	player.interaction_message.connect(func(message: String): hud.show_note(message))
	beacon = SpotLight3D.new()
	beacon.name = "Beacon"
	beacon.light_color = Color(1.0, 0.95, 0.8)
	beacon.light_energy = 6.0
	beacon.spot_range = 9.0
	beacon.spot_angle = 30.0
	beacon.visible = false
	player.add_child(beacon)
	beacon.position = Vector3(0.2, 1.5, -0.2)
	_wire_stations()


func face_player(yaw: float, pitch := 0.0) -> void:
	player.rotation.y = yaw
	player.set("_yaw", yaw)
	player.set("_pitch", pitch)
	player.call("_apply_look_rotation")


func _wire_stations() -> void:
	var st: Dictionary = world.stations
	for id in st:
		var s := st[id] as NightWatchStation
		var sid: String = id
		s.on_activate = func(_p) -> String: return station_pressed(sid)


# --- the player's actions (also what the validators press) ------------------------------------------------------------------

## What pressing use on a station does.
func station_pressed(id: String) -> String:
	if state != State.PLAYING or keypad_up or not _glide.is_empty():
		return ""
	if id.begins_with("door_"):
		var parts := id.split("_")
		if parts[1] == sim.room:
			try_move(parts[2])
		return ""
	if id == "terminal":
		if sim.room == "control" and sim.puzzle.get("kind", "") == "code":
			open_keypad()
		else:
			StorySounds.deny()
			return "NOTHING TO KEY IN"
		return ""
	if id.begins_with("dial_") or id.begins_with("part_") or id.begins_with("switch_"):
		return do_interact({"i": int(id.get_slice("_", 1))})
	if id == "crank":
		return do_interact({})
	if id == "monitor":
		if sim.task_idx >= sim.tasks.size():
			return ""
		var t: Dictionary = sim.tasks[sim.task_idx]
		return "NEXT: %s (%s)" % [t["label"], String(StoryData.ROOMS[t["room"]]["label"]).capitalize()]
	return ""


func try_move(dir: String) -> bool:
	if state != State.PLAYING or not sim.moving.is_empty():
		return false
	sim.set_crawl(crawl_override or (not manual_clock and Input.is_action_pressed(&"crouch")))
	var from_room := sim.room
	if not sim.move(dir):
		StorySounds.deny()
		return false
	var to_room: String = sim.moving["to"]
	_glide = {"from": player.global_position, "mid": world.door_point(from_room, dir), "to": world.arrival(to_room, dir),
		"dur": float(sim.moving["left"]), "dir": dir, "room": to_room}
	player.input_frozen = true
	StorySounds.door()
	return true


## One action at the current task's station.
func do_interact(p: Dictionary) -> String:
	if state != State.PLAYING:
		return ""
	var events := sim.interact(p)
	for e in events:
		match String(e["type"]):
			"step":
				StorySounds.step_ok()
			"wrong":
				StorySounds.wrong()
			"deny":
				StorySounds.deny()
			"task":
				StorySounds.task_done()
	if sim.over == "win":
		_sync_visuals()
		_finish_win()
	else:
		_sync_visuals()
	for e in events:
		if e["type"] == "wrong":
			return "WRONG // IT STARTS OVER"
	return ""


func open_keypad() -> void:
	keypad_up = true
	panel.show_keypad(true)
	player.input_frozen = true
	player.look_frozen = true
	MouseLock.claim("night_watch_keypad", true)
	_sync_visuals()


func close_keypad() -> void:
	if not keypad_up:
		return
	keypad_up = false
	panel.show_keypad(false)
	MouseLock.claim("night_watch_keypad", false)
	player.input_frozen = state != State.PLAYING or not _glide.is_empty()
	player.look_frozen = state != State.PLAYING


func keypad_digit(d: String) -> void:
	if not keypad_up:
		return
	do_interact({"digit": d})
	if sim.puzzle.get("kind", "") != "code" or sim.over != "":
		close_keypad()


func set_paused(on: bool) -> void:
	if state == State.WON or state == State.LOST:
		return
	state = State.PAUSED if on else State.PLAYING
	get_tree().paused = on
	hud.show_pause(on)
	MouseLock.claim("night_watch_pause", on)


# --- the clock ---------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_animate_models(delta)
	if not manual_clock:
		world.animate(delta)
	if state != State.PLAYING:
		return
	var aimed := player.call("_nearest_interactable") as NightWatchStation if not keypad_up else null
	hud.set_prompt(player.get_interaction_prompt() if not keypad_up else "")
	if manual_clock:
		return
	held["light"] = Input.is_action_pressed(StoryControls.BEACON)
	held["hide"] = Input.is_action_pressed(StoryControls.HIDE)
	held["work"] = Input.is_action_pressed(&"interact") and aimed != null and aimed.station_id == "lift_button"
	advance_ms(delta * 1000.0)


func current_input() -> Dictionary:
	return {"work": held["work"], "light": held["light"], "hide": held["hide"]}


func advance_ms(dt_ms: float) -> void:
	if state != State.PLAYING:
		return
	var events := sim.step(dt_ms, current_input())
	for e in events:
		_on_event(e)
	_sync_visuals()
	if sim.over == "win":
		_finish_win()
	elif sim.over == "caught":
		_finish_caught()


func _on_event(e: Dictionary) -> void:
	match String(e["type"]):
		"arrive":
			if not _glide.is_empty():
				player.global_position = _glide["to"]
				_arrived(String(_glide["dir"]), String(_glide["room"]))
				_glide = {}
				player.input_frozen = keypad_up
			StorySounds.arrive()
		"close":
			StorySounds.hunter_close(String(e["id"]), bool(e.get("away", false)))
		"back":
			StorySounds.hunter_back(String(e["id"]))
		"pushed":
			StorySounds.pushed(String(e["id"]))
		"alert":
			StorySounds.alert()
		"bell":
			StorySounds.bell()
			hud.show_note("THE LIFT BELL")
		"open":
			StorySounds.lift_open()
		"leave":
			StorySounds.lift_leave()
		"task":
			StorySounds.task_done()


## You came into `room` through the door `dir` from the next room: which end of it each hunter comes from.
func _arrived(dir: String, room: String) -> void:
	if dir == "C":
		return
	var side := -1.0 if dir == "L" else 1.0
	if room == "gallery":
		_side["opalie"] = side
	elif StoryLogic.PORCELLE_ROOMS.has(room):
		_side["porcelle"] = side
		_porcelle_room = room


# --- what you see -------------------------------------------------------------------------------------------------------

func _sync_visuals() -> void:
	world.show_puzzle(sim.puzzle)
	world.set_lift_open(sim.quenelle["state"] == "open")
	if manual_clock:
		world.snap()
	hud.update_status(0, 100.0, 0, night)
	hud.clock_label.text = ""
	hud.power_label.text = ""
	hud.usage_label.text = ""
	hud.night_label.text = "CUSTOM NIGHT" if is_custom else "NIGHT %d" % night
	panel.refresh(sim)
	beacon.visible = sim.light
	_sync_player()
	_place_hunters()


## While the rules count a walk through a door, the player is carried through it: to the doorway first, then in.
func _sync_player() -> void:
	if _glide.is_empty() or sim.moving.is_empty():
		return
	var t := clampf(1.0 - float(sim.moving["left"]) / float(_glide["dur"]), 0.0, 1.0)
	var from: Vector3 = _glide["from"]
	var mid: Vector3 = _glide["mid"]
	var to: Vector3 = _glide["to"]
	var pos := from.lerp(mid, t / 0.45) if t < 0.45 else mid.lerp(to, (t - 0.45) / 0.55)
	player.global_position = Vector3(pos.x, player.global_position.y, pos.z)


func _creeper_spot(id: String, room_id: String, dist: int) -> Vector3:
	var c := (world.rooms[room_id] as Node3D).global_position
	var side: float = _side[id]
	var anchor_x := -side * (StoryWorld.ROOM_W * 0.5 - 1.5)
	return c + Vector3(anchor_x + side * (0.9 + dist * 0.85), 0.0, 0.5 if id == "opalie" else -0.4)


func _place_hunters() -> void:
	var look := player.global_position
	for id in ["opalie", "porcelle"]:
		var h: Dictionary = sim.opalie if id == "opalie" else sim.porcelle
		var room_id := "gallery" if id == "opalie" else _porcelle_room
		var spot := _creeper_spot(id, room_id, int(h["dist"]))
		_walk_to(id, room_id, spot, look)
		(_models[id] as Node3D).visible = sim.base_level(id) > 0
	# Quenelle: out of the lift when it opens, back in when it leaves
	var q: Dictionary = sim.quenelle
	var state_now := String(q["state"])
	var in_car := Vector3(0.0, 0.0, -4.6)
	var at_door := Vector3(0.0, 0.0, -2.9)
	var qw := _walkers.get("quenelle") as NightWatchWalker
	if qw == null:
		qw = NightWatchWalker.new()
		_walkers["quenelle"] = qw
		qw.place(in_car, in_car, at_door, "car")
	var goal := at_door if state_now == "open" else in_car
	if manual_clock:
		qw.place(goal, goal, at_door + Vector3(0, 0, 3.0), "car")
	elif state_now != _q_state:
		qw.go([{"p": qw.pos, "jump": false, "key": ""}, {"p": goal, "jump": false, "key": ""}], state_now, goal, 1.6)
		qw.look = at_door + Vector3(0, 0, 3.0)
	_q_state = state_now
	(_models["quenelle"] as Node3D).visible = sim.level("quenelle") > 0 and (state_now == "open" or qw.is_walking() or qw.pos.distance_to(in_car) > 0.4)


func _walk_to(id: String, room_id: String, spot: Vector3, look: Vector3) -> void:
	var w := _walkers.get(id) as NightWatchWalker
	if w == null:
		w = NightWatchWalker.new()
		_walkers[id] = w
		w.place(spot, spot, look, room_id)
	elif manual_clock:
		w.place(spot, spot, look, room_id)
	elif w.room != room_id:
		var door := (world.rooms[room_id] as Node3D).global_position + Vector3(-StoryWorld.ROOM_W * 0.5 if room_id == "auditorium" else StoryWorld.ROOM_W * 0.5, 0.0, 0.0)
		w.go([{"p": w.pos, "jump": false, "key": ""}, {"p": door, "jump": false, "key": ""}, {"p": spot, "jump": false, "key": ""}], room_id, spot, 2.5)
		w.look = look
	else:
		w.final = spot
		w.look = look


func _spawn_hunters() -> void:
	for id in StoryData.CAST:
		var model := ModelSlot.instantiate_hunter(StoryData.identity(id))
		if model == null:
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
		var clip := "walk" if walker2 != null and walker2.moving else "idle"
		if anim.has_animation(clip) and anim.current_animation != clip:
			anim.play(clip)


# --- input --------------------------------------------------------------------------------------------------------------

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
		if keypad_up and state == State.PLAYING:
			var d := -1
			if key >= KEY_0 and key <= KEY_9:
				d = key - KEY_0
			elif key >= KEY_KP_0 and key <= KEY_KP_9:
				d = key - KEY_KP_0
			if d >= 0:
				keypad_digit(str(d))
				return
			if key == KEY_ESCAPE:
				close_keypad()
				return
	if event.is_action_pressed(&"pause"):
		if state == State.PLAYING or state == State.PAUSED:
			set_paused(state == State.PLAYING)
		return
	if keypad_up and event.is_action_pressed(&"interact"):
		close_keypad()
		return
	if state == State.PLAYING and event.is_action_pressed(&"office_radio"):
		hud.toggle_mute()


# --- the end of a night ----------------------------------------------------------------------------------------------

func _freeze_player() -> void:
	close_keypad()
	player.input_frozen = true
	player.look_frozen = true
	MouseLock.claim("night_watch_end", true)


func _finish_win() -> void:
	state = State.WON
	_freeze_player()
	NightWatchSounds.win()
	var score := record_win()
	var more := has_next_level()
	var body := "Every task on the list is done."
	if is_custom:
		body += "\nScore %d  %s  (best %d)" % [score, NightWatchModesData.rating_of(score, 400), NightWatchSave.best_score(mode_id)]
	else:
		body += ("\nNight %d is open." % (night + 1)) if more else "\nYou cleared every night."
	hud.show_end("CUSTOM NIGHT COMPLETE" if is_custom else "NIGHT %d COMPLETE" % night, body, more)
	finished.emit("win")


func _finish_caught() -> void:
	state = State.LOST
	_freeze_player()
	NightWatchSounds.caught()
	var who: String = sim.by
	var m := _models[who] as Node3D
	m.visible = true
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	m.position = player.global_position + forward.normalized() * 1.1
	m.rotation.y = atan2(-forward.x, -forward.z) + PI
	var name_text := String(StoryData.NAMES.get(who, who.capitalize()))
	var picked := DeathLines.pick({"hunter_id": who}, "nightwatch:story:%d" % seed_value, night, name_text)
	last_death = {"by": who, "name": name_text, "picked": picked}
	finished.emit("caught")
	if DeathMoment.plays(picked):
		death_moment.play(name_text, picked)
	else:
		_after_death_moment()


func _after_death_moment() -> void:
	if state != State.LOST:
		return
	var room_label := String(StoryData.ROOMS[sim.room]["label"]).capitalize()
	var line := "%s got to you in the %s." % [last_death.get("name", "Someone"), room_label.to_lower()]
	if last_death.get("by", "") == "quenelle":
		line = "Quenelle saw you when the lift opened."
	hud.show_end("CAUGHT", line, false)


func _exit_tree() -> void:
	MouseLock.release_all()
	StoryControls.unregister()
	if get_tree() != null:
		get_tree().paused = false
