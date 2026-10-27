class_name BedroomGame
extends NightWatchMode

## Bedtime (mode `bedroom`), the shift scene: you lie in bed in a dark room with no cameras and a flashlight on a battery. Hold A to keep the closet
## door shut (Loxelle breathes behind it, never seen until she gets in), D to put the light down the hall (Javelle waits where it ends), F to light
## the foot of the bed (Haelith creeps in while it is dark). One hand, so one thing at a time. The mouse looks around from the pillow (the arrow keys
## too); the shared pause key pauses. All sounds go through the shared Sound autoload (BedroomSounds). Rules: BedroomLogic. Javelle WALKS up the
## hall and back (NightWatchWalker), Haelith crosses the floor as her number rises. `manual_clock` stops the real-time clock so the validators step
## the night with advance_ms().

enum State { PLAYING, PAUSED, WON, LOST }

const LOOK_YAW := 1.25
const LOOK_PITCH := 0.7
const LOOK_SENSE := 0.0022

var night := 1
var state: State = State.PLAYING
var sim: BedroomLogic
var world: BedroomOffice
var wing: BedroomWing
var paths: BedroomPaths
var camera: Camera3D
var hud: NightWatchHud
var hunters_root: Node3D
var death_moment: DeathMoment
var world_env: WorldEnvironment
var last_death := {}
var held := {"hold": false, "hall": false, "bed": false}
var yaw := 0.0
var pitch := 0.0

var _models := {}
var _players := {}
var _walkers := {}
var _jav_state := "away"
var _hour_seen := 0
var _cue := {"loxelle": 0.0, "javelle": 0.0, "haelith": 0.0}


func _ready() -> void:
	BedroomControls.register()
	read_session()
	night = clampi(level, 1, 6)
	var opts := {"night": night, "rng": NightWatchStream.seeded(seed_value)}
	if is_custom:
		night = 5   # the 2D menu's customLevel: a Custom Night uses Night 5's battery with the sliders as the levels
		opts = {"night": 5, "rng": NightWatchStream.seeded(seed_value), "custom": true, "levels": custom}
	_build_world()
	sim = BedroomLogic.new(opts)
	paths = BedroomPaths.new()
	_spawn_hunters()
	if not is_custom:
		hud.queue_call(BedroomData.call_lines(night))
	_sync_visuals()
	if not manual_clock:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_world() -> void:
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.015, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.3, 0.5)
	env.ambient_light_energy = 0.55
	world_env.environment = env
	add_child(world_env)
	world = NightWatchOfficeRegistry.make("bedroom") as BedroomOffice
	world.name = "Bedroom"
	add_child(world)
	wing = BedroomWing.new()
	wing.name = "Wing"
	add_child(wing)
	hunters_root = Node3D.new()
	hunters_root.name = "Hunters"
	add_child(hunters_root)
	camera = Camera3D.new()
	camera.name = "Pillow"
	camera.fov = 75.0
	camera.position = BedroomOffice.EYE
	add_child(camera)
	camera.current = true
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
	hud.set_monitor_available(false)   # no camera monitor in this scene
	hud.hint_label.text = "Hold  A closet door   D hall light   F bed light   mouse / arrows look   R radio   P pause"
	death_moment = DeathMoment.new()
	death_moment.name = "DeathMoment"
	add_child(death_moment)
	death_moment.finished.connect(_after_death_moment)


func _spawn_hunters() -> void:
	for id in BedroomData.CAST:
		var model := ModelSlot.instantiate_hunter(BedroomData.identity(id))
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


# --- the hands (also what the validators press) ------------------------------------------------------------------------

## One hand: pressing one lets go of the others.
func press(name: String, on: bool) -> void:
	if state != State.PLAYING:
		return
	if on:
		held["hold"] = false
		held["hall"] = false
		held["bed"] = false
		if name == "hold":
			BedroomSounds.door(true)
		else:
			BedroomSounds.light_on()
	held[name] = on


func current_input() -> Dictionary:
	var light := ""
	if not held["hold"]:
		light = "hall" if held["hall"] else ("bed" if held["bed"] else "")
	return {"hold": held["hold"], "light": light}


func set_paused(on: bool) -> void:
	if state == State.WON or state == State.LOST:
		return
	state = State.PAUSED if on else State.PLAYING
	get_tree().paused = on
	hud.show_pause(on)
	MouseLock.claim("night_watch_pause", on)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if (on or manual_clock) else Input.MOUSE_MODE_CAPTURED


# --- the clock ---------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_animate_models(delta)
	if state != State.PLAYING:
		return
	_look_with_keys(delta)
	if manual_clock:
		return
	advance_ms(delta * 1000.0)


func advance_ms(dt_ms: float) -> void:
	if state != State.PLAYING:
		return
	var events := sim.step(dt_ms, current_input())
	var hour := NightWatchData.hour_index(sim.elapsed)
	if hour != _hour_seen:
		_hour_seen = hour
		NightWatchSounds.hour_change()
	for e in events:
		_on_event(e)
	if sim.over == "":
		_breathing_cues()
	_sync_visuals()
	if sim.over == "win":
		_finish_win()
	elif sim.over == "caught":
		_finish_caught()


## They are heard, not seen: breathing on the side each one comes from, louder as she gets close (the 2D scene's cadence).
func _breathing_cues() -> void:
	for pair in [["loxelle", sim.loxelle], ["javelle", sim.javelle]]:
		var id: String = pair[0]
		var th: Dictionary = pair[1]
		if th["state"] != "away" and sim.elapsed - float(_cue[id]) > (1100.0 if th["state"] == "near" else 1700.0):
			_cue[id] = sim.elapsed
			BedroomSounds.breath(id, 0.9 if th["state"] == "near" else 0.5)
	if float(sim.haelith["p"]) >= float(BedroomLogic.T["bedStirAt"]) and sim.elapsed - float(_cue["haelith"]) > 2400.0:
		_cue["haelith"] = sim.elapsed
		BedroomSounds.breath("haelith", 0.3 + float(sim.haelith["p"]) / 300.0)


func _on_event(e: Dictionary) -> void:
	match String(e["type"]):
		"breath":
			BedroomSounds.step_in(String(e["id"]))
			_cue[String(e["id"])] = sim.elapsed
		"near":
			BedroomSounds.breath(String(e["id"]), 1.0)
			_cue[String(e["id"])] = sim.elapsed
		"leave":
			BedroomSounds.leave(String(e["id"]))
		"stir":
			BedroomSounds.stir()
		"restless":
			BedroomSounds.restless()
			hud.show_note("THE HOUSE IS RESTLESS")


# --- what you see -------------------------------------------------------------------------------------------------------

func _sync_visuals() -> void:
	world.set_light(sim.light)
	world.set_closet_held(sim.hold)
	hud.update_status(NightWatchData.hour_index(sim.elapsed), sim.battery, 0, night)
	hud.night_label.text = "CUSTOM NIGHT" if is_custom else "NIGHT %d" % night
	hud.power_label.text = "BATTERY %d%%" % int(round(sim.battery))
	hud.usage_label.text = "RESTLESS" if sim.restless else ""
	_place_hunters()


func base_awake(id: String) -> bool:
	return sim.base_level(id) > 0


func _place_hunters() -> void:
	var eye := BedroomOffice.EYE
	# Javelle: from the living room along the hall to the bedroom door and back, on foot (BedroomPaths)
	var jv := _models["javelle"] as Node3D
	var jw := _walkers.get("javelle") as NightWatchWalker
	var jstate: String = sim.javelle["state"]
	var key := "C:living_room"
	if jstate == "breath":
		key = "H:mid"
	elif jstate == "near":
		key = "H:near"
	var target: Vector3 = paths.points[key]
	if jw == null:
		var home: Vector3 = paths.points["C:living_room"]
		jw = NightWatchWalker.new()
		_walkers["javelle"] = jw
		jw.place(home, home, eye, "away")
	if manual_clock:
		jw.place(target, target, eye, jstate)
		_jav_state = jstate
	elif jstate != _jav_state:
		jw.go(paths.legs_from(jw.pos, key), jstate, target, 2.4)
		jw.look = eye
		_jav_state = jstate
	jv.visible = base_awake("javelle") and (jstate != "away" or jw.is_walking() or jw.pos.x < BedroomMap.rect("hall").end.x + 0.2)
	jv.position = jw.pos
	jv.rotation.y = jw.yaw
	# Haelith: across the floor as her number rises, dim until the bed light finds her
	var hm := _models["haelith"] as Node3D
	var hw := _walkers.get("haelith") as NightWatchWalker
	var hp := float(sim.haelith["p"])
	var spot := world.creep_position(hp)
	if hw == null:
		hw = NightWatchWalker.new()
		_walkers["haelith"] = hw
		hw.place(spot, spot, eye, "creep")
	if manual_clock:
		hw.place(spot, spot, eye, "creep")
	else:
		hw.final = spot
		hw.look = eye
	hm.visible = base_awake("haelith") and hp >= 10.0
	hm.position = hw.pos
	hm.rotation.y = hw.yaw


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


# --- looking around from the pillow -------------------------------------------------------------------------------------

func _apply_look() -> void:
	yaw = clampf(yaw, -LOOK_YAW, LOOK_YAW)
	pitch = clampf(pitch, -LOOK_PITCH * 0.6, LOOK_PITCH)
	camera.rotation = Vector3(pitch, yaw, 0.0)


func look_by(dyaw: float, dpitch: float) -> void:
	yaw -= dyaw
	pitch -= dpitch
	_apply_look()


func _look_with_keys(delta: float) -> void:
	var dx := (1.0 if Input.is_physical_key_pressed(KEY_LEFT) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_RIGHT) else 0.0)
	var dy := (1.0 if Input.is_physical_key_pressed(KEY_UP) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_DOWN) else 0.0)
	if dx != 0.0 or dy != 0.0:
		yaw += dx * 1.4 * delta
		pitch += dy * delta
		_apply_look()


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
	if event.is_action_pressed(&"pause"):
		if state == State.PLAYING or state == State.PAUSED:
			set_paused(state == State.PLAYING)
		return
	if state != State.PLAYING:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel := (event as InputEventMouseMotion).relative
		look_by(rel.x * LOOK_SENSE, rel.y * LOOK_SENSE)
		return
	for pair in [[BedroomControls.HOLD, "hold"], [BedroomControls.HALL, "hall"], [BedroomControls.BED, "bed"]]:
		if event.is_action_pressed(pair[0]):
			press(pair[1], true)
			return
		if event.is_action_released(pair[0]):
			held[pair[1]] = false
			return
	if event.is_action_pressed(&"office_radio"):
		hud.toggle_mute()


# --- the end of a night ----------------------------------------------------------------------------------------------

func _end_cursor() -> void:
	MouseLock.claim("night_watch_end", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _finish_win() -> void:
	state = State.WON
	_end_cursor()
	NightWatchSounds.win()
	var score := record_win()
	var more := has_next_level()
	var body := "6:00 AM\nMorning came. Battery left: %d%%." % int(round(sim.battery))
	if is_custom:
		body += "\nScore %d  %s  (best %d)" % [score, NightWatchModesData.rating_of(score, 400), NightWatchSave.best_score(mode_id)]
	else:
		body += ("\nNight %d is open." % (night + 1)) if more else "\nYou cleared every night."
	hud.show_end("CUSTOM NIGHT COMPLETE" if is_custom else "NIGHT %d COMPLETE" % night, body, more)
	finished.emit("win")


func _finish_caught() -> void:
	state = State.LOST
	_end_cursor()
	NightWatchSounds.caught()
	var who: String = sim.by
	# her scare: the one moment she is seen. The closet door drifts open on her, or the light finds the other two.
	var m := _models[who] as Node3D
	m.visible = true
	match who:
		"loxelle":
			world.open_closet_wide()
			m.position = Vector3(-BedroomOffice.HALF - 0.5, 0.0, BedroomOffice.CLOSET_Z)
			world.set_light("bed")
		"javelle":
			m.position = BedroomOffice.DOORWAY + Vector3(-0.8, 0.0, 0.0)
			world.set_light("hall")
		_:
			m.position = Vector3(0.0, 0.0, 0.6)
			world.set_light("bed")
	var d := BedroomOffice.EYE - m.position
	m.rotation.y = atan2(d.x, d.z) + PI
	var name_text := String(BedroomData.NAMES.get(who, who.capitalize()))
	var picked := DeathLines.pick({"hunter_id": who}, "nightwatch:bedroom:%d" % seed_value, night, name_text)
	last_death = {"by": who, "name": name_text, "picked": picked}
	finished.emit("caught")
	if DeathMoment.plays(picked):
		death_moment.play(name_text, picked)
	else:
		_after_death_moment()


func _after_death_moment() -> void:
	if state != State.LOST:
		return
	hud.show_end("CAUGHT", "%s got to you at %s." % [last_death.get("name", "Someone"), NightWatchData.hour_label(NightWatchData.hour_index(sim.elapsed))], false)


func _exit_tree() -> void:
	MouseLock.release_all()
	BedroomControls.unregister()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if get_tree() != null:
		get_tree().paused = false
