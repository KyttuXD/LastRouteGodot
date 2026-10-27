class_name DayshiftGame
extends NightWatchMode

## Salvage Run (mode `dayshift`), the 3D shift scene: first the day (the shop: spend the week's budget on upgrades), then the night in the Classic security
## room, which here has a workbench with a four-slot rack and a window. Hold USE on a piece to take it (salvaging is loud, noise makes the doors' visitors
## keener), shut the doors / hold the door lights as in Classic, and keep quiet while Ysolde is at the window. The rules are DayshiftLogic (a port of
## dayshift-logic.js, seeded like the 2D game). Shared player, prompt, crosshair and Sound only. `manual_clock` stops the real-time clock so the validators
## step the night themselves with advance_ms(); they call start_shift() instead of pressing the shop's button.

enum State { SHOP, PLAYING, PAUSED, WON, LOST }

const WIN_TEXT := "The quota is in."
static var pending_carry := 0   # last week's surplus, handed to the next week's shop only when you play on from the end card

var week := 1
var carry := 0
var state: State = State.SHOP
var sim: DayshiftLogic
var rng: NightWatchMulberry
var owned: Array = []
var office: CargoBay
var shop: DayshiftShop
var player: PlayerController3D
var hud: NightWatchHud
var hunters_root: Node3D
var death_moment: DeathMoment
var world_env: WorldEnvironment
var last_death := {}
var door_shut := {"doorL": false, "doorR": false}
var light_held := {"doorL": false, "doorR": false}
var work_slot := -1
var win_carry := 0

var _models := {}
var _walkers := {}
var _players := {}
var _hour_seen := 0


func _ready() -> void:
	NightWatchControls.register()
	read_session()
	week = clampi(4 if is_custom else level, 1, 5)
	carry = 0 if is_custom else pending_carry
	pending_carry = 0
	_build_world()
	_spawn_hunters()
	shop = DayshiftShop.new()
	shop.name = "Shop"
	shop.setup(week, carry, is_custom)
	add_child(shop)
	shop.started.connect(start_shift)
	player.input_frozen = true
	player.look_frozen = true
	MouseLock.claim("night_watch_shop", true)
	hud.update_status(0, 100.0, 0, week)
	hud.night_label.text = "CUSTOM" if is_custom else "WEEK %d" % week
	hud.visible = false   # the shop has the screen


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
	office = NightWatchOfficeRegistry.make("dayshift") as CargoBay
	office.name = "Office"
	add_child(office)
	hunters_root = Node3D.new()
	hunters_root.name = "Hunters"
	add_child(hunters_root)
	hud = NightWatchHud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.retry_pressed.connect(retry)
	hud.next_pressed.connect(next_night)
	hud.menu_pressed.connect(back_to_board)
	hud.resume_pressed.connect(func(): set_paused(false))
	hud.subtitles_toggled.connect(func(on: bool):
		hud.set_subtitles(on)
		NightWatchSave.set_subtitles(on))
	hud.set_subtitles(NightWatchSave.subtitles())
	hud.hint_label.text = "WASD move   hold E on a PIECE to salvage   E on DOOR buttons   hold E on LIGHT   Z / X doors   G / H lights   P pause"
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


func _wire_stations() -> void:
	var st: Dictionary = office.stations
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
		office.set_lamp(not office.lamp.visible)
		return ""
	(st["chair"] as NightWatchStation).on_activate = func(p) -> String:
		return String(p.use_furniture(st["chair"], "sit"))
	for id in ["breaker", "monitor", "ledger"]:
		(st[id] as NightWatchStation).on_activate = func(_p) -> String: return String(office.prompts.get(id, ""))
	for i in 4:
		(st["rack%d" % i] as NightWatchStation).on_activate = func(_p) -> String: return ""   # held, see _process


func _spawn_hunters() -> void:
	for id in DayshiftData.CAST:
		var model := ModelSlot.instantiate_hunter(HunterRoster.get_identity(id))
		if model == null:
			push_warning("Salvage Run: no model for %s" % id)
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


## The shop's START SHIFT: the upgrades are bought, the night begins.
func start_shift(basket: Array = []) -> void:
	if state != State.SHOP:
		return
	owned = basket.duplicate()
	rng = NightWatchMulberry.new(seed_value)
	sim = DayshiftLogic.new(week, rng, {"upgrades": owned, "levels": custom, "custom": is_custom, "quota": DayshiftLogic.quota_for(week)})
	state = State.PLAYING
	shop.queue_free()
	shop = null
	hud.visible = true
	MouseLock.claim("night_watch_shop", false)
	player.input_frozen = false
	player.look_frozen = false
	if not is_custom:
		hud.queue_call(DayshiftData.call_lines(week))
	_sync_visuals()


# --- player actions (also what the validators press) -----------------------------------------------------------------------

func toggle_door(door: String) -> void:
	if state != State.PLAYING or bool(sim.s["out"]):
		return
	door_shut[door] = not bool(door_shut[door])
	NightWatchSounds.door(bool(door_shut[door]))


func set_door(door: String, shut: bool) -> void:
	if state == State.PLAYING and not bool(sim.s["out"]):
		door_shut[door] = shut


func set_light(door: String, held: bool) -> void:
	if state == State.PLAYING:
		light_held[door] = held and not bool(sim.s["out"])


## Hold on rack slot i (or let go with -1).
func set_work(slot: int) -> void:
	work_slot = slot if state == State.PLAYING else -1


func set_paused(on: bool) -> void:
	if state == State.WON or state == State.LOST or state == State.SHOP:
		return
	state = State.PAUSED if on else State.PLAYING
	get_tree().paused = on
	hud.show_pause(on)
	MouseLock.claim("night_watch_pause", on)


func has_next_level() -> bool:
	return not is_custom and level < 5


## Playing on from a cleared week hands the surplus to the next week's shop (the 2D game's carry-over).
func next_night() -> void:
	pending_carry = win_carry
	next_level()


# --- the clock -------------------------------------------------------------------------------------------------------------

func current_input() -> Dictionary:
	return {"work": work_slot >= 0, "target": work_slot, "doorL": door_shut["doorL"], "doorR": door_shut["doorR"], "lightL": light_held["doorL"], "lightR": light_held["doorR"]}


func _process(delta: float) -> void:
	_animate_models(delta)
	if state != State.PLAYING:
		return
	var aimed := player.call("_nearest_interactable") as NightWatchStation
	hud.set_prompt(player.get_interaction_prompt())
	if manual_clock:
		return
	for door in ["doorL", "doorR"]:
		var action := NightWatchControls.LIGHT_LEFT if door == "doorL" else NightWatchControls.LIGHT_RIGHT
		var on_button := aimed != null and aimed.station_id == "%s_light" % door
		var want := Input.is_action_pressed(action) or (Input.is_action_pressed(&"interact") and on_button)
		if want != bool(light_held[door]):
			set_light(door, want)
	var slot := -1
	if aimed != null and aimed.station_id.begins_with("rack") and Input.is_action_pressed(&"interact"):
		slot = int(aimed.station_id.substr(4))
	if slot != work_slot:
		set_work(slot)
	advance_ms(delta * 1000.0)


## Step the night by dt_ms with the doors, lights and rack as they are, and show what happened.
func advance_ms(dt_ms: float) -> void:
	if state != State.PLAYING:
		return
	var events := sim.step(dt_ms, current_input())
	var hour := NightWatchData.hour_index(float(sim.s["elapsed"]))
	if hour != _hour_seen:
		_hour_seen = hour
		NightWatchSounds.hour_change()
	if bool(sim.s["out"]):
		door_shut = {"doorL": false, "doorR": false}
		light_held = {"doorL": false, "doorR": false}
		work_slot = -1
	for e in events:
		_on_event(e)
	_sync_visuals()
	if String(sim.s["over"]) == "win":
		_finish_win()
	elif String(sim.s["over"]) == "short":
		_finish_short()
	elif String(sim.s["over"]) == "caught":
		_finish_caught()


func _pan(id: String) -> float:
	return float(DayshiftData.PAN.get(id, 0.0))


func _on_event(e: Dictionary) -> void:
	match String(e["type"]):
		"item":
			NightWatchSounds.panel_button()
		"salvage":
			NightWatchSounds.win()
			hud.show_note("+$%d" % int(e["value"]), 1.2)
		"close":
			NightWatchSounds.office("footsteps", _pan(String(e["id"])), 0.6 + 0.2 * (3 - int(e["dist"])))
		"repelled":
			NightWatchSounds.office("scrape", _pan(String(e["id"])), 0.9)
		"warned":
			NightWatchSounds.office("presence", _pan(String(e["id"])), 0.8)
		"knock":
			NightWatchSounds.office("crimson_door", 0.0, 0.9)
		"window":
			NightWatchSounds.attack_warning(0.0)
		"gone":
			NightWatchSounds.office("scrape", 0.0, 0.6)
		"out":
			hud.show_call("The power is out.")
			NightWatchSounds.power_out()


# --- what you see ----------------------------------------------------------------------------------------------------------

func _sync_visuals() -> void:
	var s := sim.s
	var dev: Dictionary = s["dev"]
	for door in ["doorL", "doorR"]:
		office.set_light(door, bool(dev["lightL" if door == "doorL" else "lightR"]))
	if manual_clock:
		office.snap_slabs({"doorL": dev["doorL"], "doorR": dev["doorR"]})
	for door in ["doorL", "doorR"]:
		office.set_button("%s_door" % door, bool(dev[door]))
		office.set_button("%s_light" % door, bool(dev["lightL" if door == "doorL" else "lightR"]))
	var devices := 0
	for k in dev:
		if bool(dev[k]):
			devices += 1
	hud.update_status(NightWatchData.hour_index(float(s["elapsed"])), float(s["power"]), devices, week)
	hud.night_label.text = "CUSTOM" if is_custom else "WEEK %d" % week
	hud.usage_label.text = "$%d / $%d   NOISE %s" % [int(s["money"]), sim.need, "|".repeat(clampi(int(float(s["noise"]) / 10.0), 0, 10))]
	(office.stations["ledger"] as NightWatchStation).prompt_text = "BUDGET LEDGER // $%d OF $%d" % [int(s["money"]), sim.need]
	var by_slot := {}
	for it in s["items"]:
		by_slot[int(it["slot"])] = it
	for i in 4:
		var st := office.stations["rack%d" % i] as NightWatchStation
		if by_slot.has(i):
			var it: Dictionary = by_slot[i]
			var label := String(DayshiftData.ITEMS[it["kind"]]["label"]).to_upper()
			st.disabled = false
			st.prompt_text = "%s $%d // HOLD TO SALVAGE" % [label, int(it["value"])]
			office.set_slot(i, String(it["kind"]), float(it["progress"]) / float(it["need"]), true)
		else:
			st.disabled = true
			st.prompt_text = ""
			office.set_slot(i, "scrap", 0.0, false)
	_place_hunters()


func _place_hunters() -> void:
	var s := sim.s
	var face := player.global_position
	var o := office.global_position
	for id in ["ravelle", "ceryth"]:
		var door := "doorL" if id == "ravelle" else "doorR"
		var model := _models[id] as Node3D
		model.visible = sim.base_level(id) > 0
		var dist := int(s[id]["dist"])
		var pos: Vector3
		var key: String
		if dist == 0:
			var progress := float(s[id]["atMs"]) / maxf(1.0, sim.door_ms)
			pos = o + office.door_stand(door, 0, progress)
			key = "door"
		else:
			pos = o + CargoBay.hall_stand(door, dist)
			key = "d%d" % dist
		_move(id, key, pos, face)
	var u: Dictionary = s["ysolde"]
	var ys := _models["ysolde"] as Node3D
	ys.visible = String(u["state"]) == "here"
	_move("ysolde", "yard", o + CargoBay.YARD_STAND, face, true)


func _move(id: String, key: String, pos: Vector3, face: Vector3, snap := false) -> void:
	var model := _models[id] as Node3D
	var walker := _walkers.get(id) as NightWatchWalker
	if walker == null:
		walker = NightWatchWalker.new()
		_walkers[id] = walker
		walker.place(pos, pos, face, key)
	elif manual_clock or snap:
		walker.place(pos, pos, face, key)
	elif walker.room != key:
		walker.go([{"p": pos, "jump": false}], key, pos)
		walker.look = face
	else:
		walker.final = pos
		walker.look = face
	model.position = walker.pos
	model.rotation.y = walker.yaw


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
		var clip := "idle"
		if walker2 != null and walker2.moving:
			clip = "sprint" if walker2.running and ap.has_animation("sprint") else "walk"
		if ap.has_animation(clip) and ap.current_animation != clip:
			ap.play(clip)
	if state == State.PLAYING and not manual_clock and sim != null:
		office.animate({"doorL": sim.s["dev"]["doorL"], "doorR": sim.s["dev"]["doorR"]}, delta)


# --- input -----------------------------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		var key := (event as InputEventKey).keycode
		if state == State.PAUSED and key == KEY_BACKSPACE:
			back_to_board()
			return
		if state == State.SHOP and key == KEY_ESCAPE:
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
	if event.is_action_pressed(NightWatchControls.DOOR_LEFT):
		toggle_door("doorL")
	elif event.is_action_pressed(NightWatchControls.DOOR_RIGHT):
		toggle_door("doorR")


# --- the end of a night ----------------------------------------------------------------------------------------------------

func _freeze_player() -> void:
	work_slot = -1
	player.input_frozen = true
	player.look_frozen = true
	MouseLock.claim("night_watch_end", true)


func _finish_win() -> void:
	state = State.WON
	_freeze_player()
	NightWatchSounds.win()
	var score := record_win()
	var money := int(sim.s["money"])
	win_carry = 0 if is_custom else DayshiftLogic.carry_from(money, sim.need)
	var more := has_next_level()
	var detail := "Quota met: $%d of $%d." % [money, sim.need]
	if win_carry > 0 and more:
		detail += " $%d carries over to next week's shop." % win_carry
	if is_custom:
		var max_score := DayshiftData.CAST.size() * NightWatchModesData.MAX_AI * NightWatchModesData.POINTS_PER_LEVEL
		hud.show_end("CUSTOM NIGHT COMPLETE", "6:00 AM\n%s\nScore %d of %d: %s" % [detail, score, max_score, NightWatchModesData.rating_of(score, max_score)], false)
	else:
		hud.show_end("WEEK %d COMPLETE" % week, "6:00 AM\n" + detail + ("\nWeek %d is open." % (week + 1) if more else "\nYou cleared every week."), more)
	finished.emit("win")


func _finish_short() -> void:
	state = State.LOST
	_freeze_player()
	NightWatchSounds.caught()
	hud.show_end("QUOTA MISSED", "$%d of $%d at 6 AM. The week is not cleared." % [int(sim.s["money"]), sim.need], false)
	finished.emit("short")


func _finish_caught() -> void:
	state = State.LOST
	_freeze_player()
	NightWatchSounds.caught()
	var by := String(sim.s["by"])
	var name_text := String(DayshiftData.NAMES.get(by, by.capitalize()))
	var picked := DeathLines.pick({"hunter_id": by}, "nightwatch:dayshift:%d" % seed_value, week, name_text)
	last_death = {"by": by, "name": name_text, "picked": picked}
	finished.emit("caught")
	if DeathMoment.plays(picked):
		death_moment.play(name_text, picked)
	else:
		_after_death_moment()


func _after_death_moment() -> void:
	if state != State.LOST or String(sim.s["over"]) != "caught":
		return
	hud.show_end("CAUGHT", "%s reached you in week %d." % [String(last_death.get("name", "A hunter")), week], false)


func _exit_tree() -> void:
	MouseLock.release_all()
	NightWatchControls.unregister()
	if get_tree() != null:
		get_tree().paused = false
