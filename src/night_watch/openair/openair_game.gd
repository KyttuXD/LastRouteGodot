class_name NightWatchOpenAirGame
extends NightWatchMode

## The Open Air shift scene (mode `extra`, code `openair`): three outdoor watches, each a walkable set (NightWatchOpenAirWorld) with the
## shared player, shared prompt / crosshair / pause / end cards and the shared Sound autoload, driven by NightWatchOpenAirLogic. The
## watch is the level (1 ROOFTOP, 2 BUS STOP, 3 CAMPFIRE). A Custom Night runs the watches whose hunters are on one after another (the
## 2D registry's comment): the sliders feed the logic, a held watch offers NEXT WATCH, and only the last win is recorded (`record_win`).
## `manual_clock` stops the real-time clock so the validators step the watch themselves with advance_ms().

enum State { PLAYING, PAUSED, WON, LOST }

const D := preload("res://src/night_watch/openair/openair_data.gd")
const CLAIM := "night_watch_openair"

## A Custom Night's place in its chain of watches. A scene reload keeps statics, so a Retry (same seed) replays this watch and NEXT WATCH
## moves on; a Custom Night started from the board has a new seed and begins at its first watch.
static var chain_seed := -1
static var chain_step := 0

var watch := 0
var chain: Array = []
var step_index := 0
var has_more := false
var state: State = State.PLAYING
var sim: NightWatchOpenAirLogic
var world: NightWatchOpenAirWorld
var office: NightWatchOpenAirOffice
var player: PlayerController3D
var hud: NightWatchHud
var death_moment: DeathMoment
var world_env: WorldEnvironment
var last_death := {}
## What is held this step (the validators set these directly, as the 2D tests set `inp`).
var inp := {"torchL": false, "torchR": false, "barL": false, "barR": false, "relight": false, "gather": false, "tent": false}

var _models := {}
var _players := {}
var _walkers := {}
var _free_walk := {}        # hunters that follow a smoothed target instead of waypoints (Wynelle on the road)
var _meter: ColorRect
var _meter_fill: ColorRect
var _hour_seen := 0
var _weather_on := false


func _ready() -> void:
	NightWatchControls.register()
	NightWatchOpenAirControls.register()
	read_session()
	if is_custom:
		chain = NightWatchOpenAirData.custom_watches(custom)
		if chain.is_empty():
			chain = [0]
		if seed_value != chain_seed:
			chain_seed = seed_value
			chain_step = 0
		step_index = clampi(chain_step, 0, chain.size() - 1)
		watch = int(chain[step_index])
		has_more = step_index < chain.size() - 1
	else:
		watch = clampi(level - 1, 0, 2)
	var hunter_id := String(D.WATCHES[watch]["hunter"])
	var own := int(custom.get(hunter_id, 0)) if is_custom else -1
	var verrine := int(custom.get("verrine", 0)) if is_custom else -1
	var quenelle := int(custom.get("quenelle", 0)) if is_custom else -1
	sim = NightWatchOpenAirLogic.new(watch, seed_value + step_index, own, verrine, quenelle)
	_build_world()
	_spawn_hunters()
	hud.set_call_script(NightWatchCallScript.new([], 0.0) if is_custom else NightWatchCallScript.for_level("extra", watch + 1))
	_sync_visuals(0.0, true)


func watch_label() -> String:
	return String(D.WATCHES[watch]["label"])


func _build_world() -> void:
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.34, 0.5)
	env.ambient_light_energy = 1.0
	world_env.environment = env
	add_child(world_env)
	office = NightWatchOfficeRegistry.make("extra") as NightWatchOpenAirOffice
	office.name = "Office"
	office.watch = watch
	add_child(office)
	world = office.world
	hud = NightWatchHud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.retry_pressed.connect(retry)
	hud.next_pressed.connect(next_watch)
	hud.menu_pressed.connect(back_to_board)
	hud.resume_pressed.connect(func(): set_paused(false))
	hud.subtitles_toggled.connect(func(on: bool):
		hud.set_subtitles(on)
		NightWatchSave.set_subtitles(on))
	hud.set_subtitles(NightWatchSave.subtitles())
	hud.hint_label.text = [
		"WASD move   E use   Z / X bar the stair door / hatch   hold G / H the torch   hold F relight   R radio   P pause",
		"WASD move   E use (a canister, the lamp)   Y heat lamp   R radio   P pause",
		"WASD move   E use   Y a log   hold F wood   hold G / H the torch   T the tent   R radio   P pause",
	][watch]
	hud.end_next.text = "NEXT WATCH  ENTER"
	_meter = ColorRect.new()
	_meter.name = "ChillBar"
	_meter.color = Color(0.1, 0.1, 0.14, 0.85)
	_meter.position = Vector2(8, 52)
	_meter.size = Vector2(72, 5)
	_meter.visible = watch == 1
	hud.add_child(_meter)
	_meter_fill = ColorRect.new()
	_meter_fill.color = Color("7fd49a")
	_meter_fill.size = Vector2(0, 5)
	_meter.add_child(_meter_fill)
	death_moment = DeathMoment.new()
	death_moment.name = "DeathMoment"
	add_child(death_moment)
	death_moment.finished.connect(_after_death_moment)
	player = (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	add_child(player)
	player.global_position = world.spawn
	face_player(0.0, -0.1)
	player.interaction_message.connect(func(message: String): hud.show_note(message))
	_wire_stations()


func face_player(yaw: float, pitch := 0.0) -> void:
	player.rotation.y = yaw
	player.set("_yaw", yaw)
	player.set("_pitch", pitch)
	player.call("_apply_look_rotation")


func _wire_stations() -> void:
	var st := world.stations
	var held := func(_p) -> String: return ""   # held stations (the torch, the lantern, the firewood) are read in _process
	for id in st:
		(st[id] as NightWatchStation).on_activate = held
	if watch == 0:
		(st["barL"] as NightWatchStation).on_activate = func(_p) -> String:
			toggle_bar("L")
			return ""
		(st["barR"] as NightWatchStation).on_activate = func(_p) -> String:
			toggle_bar("R")
			return ""
	elif watch == 1:
		(st["lamp"] as NightWatchStation).on_activate = func(_p) -> String:
			press_lamp()
			return ""
		for i in 3:
			(st["can%d" % i] as NightWatchStation).on_activate = func(_p) -> String:
				pick_can(i)
				return ""
	else:
		(st["fire"] as NightWatchStation).on_activate = func(_p) -> String:
			throw_log()
			return ""
		(st["tent"] as NightWatchStation).on_activate = func(_p) -> String:
			toggle_tent()
			return ""


func _spawn_hunters() -> void:
	for id in NightWatchOpenAirData.active_hunters(watch):
		var model := ModelSlot.instantiate_hunter(HunterRoster.get_identity(String(D.MODELS[id])))
		if model == null:
			push_warning("OpenAir: no model for %s" % id)
			model = Node3D.new()
		model.name = "Hunter_%s" % id
		add_child(model)
		_models[id] = model
		var anim := ModelSlot.find_animation_player(model)
		if anim != null:
			_players[id] = anim
			if anim.has_animation("idle"):
				anim.play("idle")
		model.visible = false
		var walker := NightWatchWalker.new()
		_walkers[id] = walker
	if watch == 1:
		_free_walk["wynelle"] = true


# --- player actions (also what the validators press) -----------------------------------------------------------------

func toggle_bar(side: String) -> void:
	if state != State.PLAYING or watch != 0:
		return
	inp["bar" + side] = not bool(inp["bar" + side])
	NightWatchSounds.door(bool(inp["bar" + side]))


func press_lamp() -> void:
	if state == State.PLAYING and watch == 1:
		_act("lamp")


func pick_can(i: int) -> void:
	if state == State.PLAYING and watch == 1:
		_act("can", {"i": i})


func throw_log() -> void:
	if state == State.PLAYING and watch == 2:
		_act("log")


func _act(kind: String, a := {}) -> void:
	if sim.act(kind, a):
		NightWatchSounds.panel_button()
	else:
		Sound.interaction_fail()
	_sync_visuals(0.0, manual_clock)


## T: into the tent when out, out when in (the tent is where the player stands: world.in_tent).
func toggle_tent() -> void:
	if state != State.PLAYING or watch != 2:
		return
	player.global_position = world.tent_out if world.in_tent(player.global_position) else world.tent_in
	inp["tent"] = world.in_tent(player.global_position)


func set_input(name: String, on: bool) -> void:
	inp[name] = on and state == State.PLAYING


func set_paused(on: bool) -> void:
	if state == State.WON or state == State.LOST:
		return
	state = State.PAUSED if on else State.PLAYING
	get_tree().paused = on
	hud.show_pause(on)
	MouseLock.claim("night_watch_pause", on)


## The next watch of this mode: the next level, or, in a Custom Night, the next watch whose hunters are on (same seed).
func has_next_level() -> bool:
	return has_more or (not is_custom and level < NightWatchModesData.mode(mode_id).get("levels", []).size())


func next_watch() -> void:
	if is_custom and has_more:
		chain_step = step_index + 1
		NightWatchSession.start_mode(mode_id, level, custom, seed_value)
		get_tree().paused = false
		get_tree().reload_current_scene()
	else:
		next_level()


# --- the clock ---------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_animate_hunters(delta)
	if state != State.PLAYING:
		return
	var aimed := player.call("_nearest_interactable") as NightWatchStation
	hud.set_prompt(player.get_interaction_prompt())
	if manual_clock:
		return
	var interact := Input.is_action_pressed(&"interact")
	var on := func(id: String) -> bool: return interact and aimed != null and aimed.station_id == id
	inp["torchL"] = Input.is_action_pressed(NightWatchControls.LIGHT_LEFT) or on.call("torchL")
	inp["torchR"] = Input.is_action_pressed(NightWatchControls.LIGHT_RIGHT) or on.call("torchR")
	inp["relight"] = Input.is_action_pressed(NightWatchOpenAirControls.RELIGHT) or on.call("lantern")
	inp["gather"] = watch == 2 and (Input.is_action_pressed(NightWatchOpenAirControls.RELIGHT) or on.call("wood"))
	advance_ms(delta * 1000.0, delta)


## Step the watch by dt_ms with what is held, and show what happened.
func advance_ms(dt_ms: float, delta := -1.0) -> void:
	if state != State.PLAYING:
		return
	if watch == 2:
		inp["tent"] = world.in_tent(player.global_position)
	var events := sim.step(dt_ms, inp)
	hud.update_call(sim.elapsed, dt_ms)
	var hour := NightWatchData.hour_index(sim.elapsed)
	if hour != _hour_seen:
		_hour_seen = hour
		NightWatchSounds.hour_change()
	for e in events:
		_on_event(e)
	_sync_visuals(dt_ms / 1000.0 if delta < 0.0 else delta, manual_clock)
	if sim.over == "win":
		_finish_win()
	elif sim.over == "caught":
		_finish_caught()


func _on_event(e: Dictionary) -> void:
	match String(e["type"]):
		"close":
			var pan := NightWatchOpenAirData.side_pan(String(e["id"]), String(e["side"]))
			NightWatchSounds.office("footsteps", pan, 0.15 + (3 - int(e["dist"])) * 0.12)
		"repelled":
			NightWatchSounds.office("scrape", NightWatchOpenAirData.side_pan(String(e["id"]), String(e["side"])), 0.8)
		"gust", "weather":
			NightWatchSounds.office("breath", 0.0, 0.5)
		"relit", "tentIn", "tentOut":
			NightWatchSounds.panel_button()
		"can", "gathered":
			Sound.collect()
		"dry":
			Sound.interaction_fail()
		"bus":
			NightWatchSounds.hour_change()
		"creep":
			NightWatchSounds.office("presence", float(NightWatchOpenAirData.PAN["ysolde"]), 0.5)
		"stolen":
			NightWatchSounds.office("scrape", float(NightWatchOpenAirData.PAN["ysolde"]), 0.7)
		"backoff":
			NightWatchSounds.office("footsteps", float(NightWatchOpenAirData.PAN["ysolde"]), 0.3)


# --- what you see ----------------------------------------------------------------------------------------------------------

func hunter_key(id: String) -> String:
	match id:
		"verrine":
			return "%s%d" % [sim.v.side, sim.v.dist] if watch == 0 else "V%d" % sim.v.dist
		"quenelle":
			return "Q%d" % sim.q.dist
		"ysolde":
			return "Y%d" % sim.y.dist
	return ""


func hunter_on(id: String) -> bool:
	match id:
		"verrine":
			return sim.level() > 0 if watch == 0 else sim.v.on
		"quenelle":
			return sim.q.on
		"ysolde":
			return sim.level() > 0
		"wynelle":
			return sim.level() > 0
	return false


func _sync_visuals(delta: float, snap: bool) -> void:
	var cue_text := ""
	hud.clock_label.text = NightWatchData.hour_label(NightWatchData.hour_index(sim.elapsed))
	hud.night_label.text = "8. OPEN AIR · %s%s" % ["CUSTOM · " if is_custom else "", watch_label()]
	match watch:
		0:
			hud.power_label.text = "OIL %d%%  TORCH %d%%" % [int(round(sim.oil)), int(round(sim.torch))]
			hud.usage_label.text = "LANTERN " + ("ON" if sim.lantern else "OUT  (hold F)")
			world.animate(sim.bars, delta, snap)
			world.set_light_energy(2.2 if sim.lantern else 0.05)
		1:
			hud.power_label.text = "WARM %d%%  FUEL %d%%" % [int(round(sim.warm)), int(round(sim.fuel))]
			hud.usage_label.text = "CHILL %d%%%s" % [int(round(sim.chill)), "  BUS" if sim.bus > 0.0 else ""]
			_meter_fill.size.x = _meter.size.x * clampf(sim.chill / 100.0, 0.0, 1.0)
			_meter_fill.color = Color("ff5a5a") if sim.chill > 30.0 else Color("7fe0ff")
			world.set_light_energy(2.2 if sim.lamp and sim.fuel > 0.0 else 0.0)
			world.set_cans(sim.cans)
			world.set_bus(sim.bus)
		2:
			hud.power_label.text = "FIRE %d%%  LOGS %d  TORCH %d%%" % [int(round(sim.fire)), sim.logs, int(round(sim.torch))]
			var y_text := ""
			if sim.y.dist < 2:
				y_text = "  YSOLDE %s" % ("IS OUT OF THE TREES" if sim.y.dist == 1 else "IS AT THE LOGS")
			hud.usage_label.text = ("IN THE TENT %.1fs" % (sim.tent_ms / 1000.0) if sim.hidden else "TENT: OUT") + y_text
			world.set_fire(sim.fire)
			world.set_pile(sim.logs)
	var wx_on := bool(sim.weather.get("on", false)) if not sim.weather.is_empty() else false
	if wx_on != _weather_on:
		_weather_on = wx_on
		world.set_weather(wx_on)
		world_env.environment.ambient_light_energy = 0.8 if wx_on else 1.0
	world.set_torch(sim.torch_side, player.global_position)
	_place_hunters(snap)


func _place_hunters(snap: bool) -> void:
	for id in _models:
		var model := _models[id] as Node3D
		var walker := _walkers[id] as NightWatchWalker
		model.visible = hunter_on(id)
		if id == "wynelle":
			var t := clampf(sim.chill / 100.0, 0.0, 1.0)
			var target := world.point("W0").lerp(world.point("W4"), t)
			if snap or walker.room == "":
				walker.place(target, target, player.global_position, "road")
			walker.final = target
			walker.look = player.global_position
			continue
		var key := hunter_key(id)
		var pos := world.point(key)
		if walker.room == "" or snap:
			walker.place(pos, pos, player.global_position, key)
		elif walker.room != key:
			walker.go(world.paths.legs_from(walker.pos, key), key, pos, NightWatchWalker.budget_for(sim.level_of(id)))
			walker.look = player.global_position
		else:
			walker.final = pos
			walker.look = player.global_position
		model.position = walker.pos
		model.rotation.y = walker.yaw


func _animate_hunters(delta: float) -> void:
	for id in _walkers:
		var walker := _walkers[id] as NightWatchWalker
		if not manual_clock and walker.room != "":
			if id == "wynelle" and sim != null:
				# Wynelle drifts along the road after her chill (a smooth walk, never a jump)
				walker.final = world.point("W0").lerp(world.point("W4"), clampf(sim.chill / 100.0, 0.0, 1.0))
			walker.step(delta)
		var model := _models[id] as Node3D
		model.position = walker.pos
		model.rotation.y = walker.yaw
		var anim := _players.get(id) as AnimationPlayer
		if anim != null:
			var clip := "idle"
			if walker.moving:
				clip = "sprint" if walker.running and anim.has_animation("sprint") else "walk"
			if anim.has_animation(clip) and anim.current_animation != clip:
				anim.play(clip)
	if world != null and state == State.PLAYING and not manual_clock and watch == 0:
		world.animate(sim.bars, delta)


# --- input -----------------------------------------------------------------------------------------------------------------

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
					next_watch()
				return
	if event.is_action_pressed(&"pause"):
		if state == State.PLAYING or state == State.PAUSED:
			set_paused(state == State.PLAYING)
		return
	if state != State.PLAYING:
		return
	if event.is_action_pressed(&"office_radio"):
		hud.toggle_mute()
	elif event.is_action_pressed(NightWatchControls.DOOR_LEFT):
		toggle_bar("L")
	elif event.is_action_pressed(NightWatchControls.DOOR_RIGHT):
		toggle_bar("R")
	elif event.is_action_pressed(NightWatchControls.LAMP):
		if watch == 1:
			press_lamp()
		elif watch == 2:
			throw_log()
	elif event.is_action_pressed(NightWatchOpenAirControls.TENT):
		toggle_tent()


# --- the end of a watch ---------------------------------------------------------------------------------------------------

func _freeze_player() -> void:
	player.input_frozen = true
	player.look_frozen = true
	MouseLock.claim("night_watch_end", true)


func _finish_win() -> void:
	state = State.WON
	_freeze_player()
	NightWatchSounds.win()
	if not has_more:
		record_win()
	var more := has_next_level()
	var label := watch_label()
	var title := "%s HELD" % label if has_more else ("CUSTOM NIGHT COMPLETE" if is_custom else "WATCH %d COMPLETE" % (watch + 1))
	var body := "DAWN\n%s%s held until morning." % [label.substr(0, 1), label.substr(1).to_lower()]
	hud.show_end(title, body, more)
	finished.emit("win")


func _finish_caught() -> void:
	state = State.LOST
	_freeze_player()
	NightWatchSounds.caught()
	var who := sim.by
	var name_text := String(NightWatchOpenAirData.NAMES[who])
	var picked := DeathLines.pick({"hunter_id": who, "detail": sim.cause}, "nightwatch:openair:%d" % seed_value, watch + 1, name_text)
	var what := "%s got to you" % name_text
	if who == "wynelle":
		what = "The cold took the stop"
	elif watch == 2 and who == "ysolde" and sim.hidden:
		what = "Ysolde looked in the tent"
	last_death = {"by": who, "name": name_text, "picked": picked, "message": "%s at %s." % [what, NightWatchData.hour_label(NightWatchData.hour_index(sim.elapsed))]}
	finished.emit("caught")
	if DeathMoment.plays(picked):
		death_moment.play(name_text, picked)
	else:
		_after_death_moment()


func _after_death_moment() -> void:
	if state != State.LOST:
		return
	hud.show_end("CAUGHT", String(last_death.get("message", "")), false)


func _exit_tree() -> void:
	MouseLock.release_all()
	NightWatchControls.unregister()
	NightWatchOpenAirControls.unregister()
	if get_tree() != null:
		get_tree().paused = false
