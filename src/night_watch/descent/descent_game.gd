class_name NightWatchDescentGame
extends NightWatchMode

## The Descent shift scene (mode `descent`): a fixed view from inside a service elevator, driven by NightWatchDescentLogic. Click the
## service panel (or press 1-6) to repair the fuse boxes, the signal pads and the pipes; hold SPACE (or the button) to keep the door
## shut on the last stage. Elise walks the sill outside the caged window on her side and comes to the glass as the closeness bar fills.
## Not walkable, so there is no player controller: the cursor is free (MouseLock claim) and the shared pause key, Sound autoload and HUD
## (call box, pause card, end card) are used. `manual_clock` stops the real-time clock so validators step it with advance_ms().

enum State { PLAYING, PAUSED, WON, LOST }

const CLAIM := "night_watch_descent"
const ELISE_MODEL := "eirys"   # the 3D roster's E hunter wears Elise's model; Quenelle's is Quirith

var descent := 1
var state: State = State.PLAYING
var sim: NightWatchDescentLogic
var world: NightWatchDescentWorld
var office: NightWatchDescentOffice
var panel: NightWatchDescentPanel
var hud: NightWatchHud
var death_moment: DeathMoment
var elise: Node3D
var hold_down := false
var last_death := {}
## Admin (NightWatchAdmin): the menu (null for non-admins) and the live switches the admin hooks below set.
var admin_menu: AdminMenu
var _admin_frozen := false
var _admin_no_scare := false
var _admin_reveal := false

var _panel_layer: CanvasLayer
var _elise_anim: AnimationPlayer
var _elise_pos := Vector3.ZERO
var _elise_moving := false
var _side_shown := ""
var _ride_seen := true
var _bar: ColorRect
var _bar_fill: ColorRect
var _bar_label: Label


func _ready() -> void:
	read_session()
	descent = clampi(level, 1, NightWatchDescentData.DESCENTS)
	var elise_level := -1
	if is_custom:
		descent = NightWatchDescentData.DESCENTS   # a Custom Night plays the longest descent with Elise at her slider
		elise_level = clampi(int(custom.get("elise", 0)), 0, NightWatchModesData.MAX_AI)
	_build_world()
	sim = NightWatchDescentLogic.new(descent, seed_value, elise_level)
	admin_menu = NightWatchAdmin.attach(self)   # after the sim exists
	if admin_menu != null:
		hud.hint_label.text += " · 0 admin"
	hud.set_call_script(NightWatchCallScript.new([], 0.0) if is_custom else NightWatchCallScript.for_level("descent", descent))
	_ride_seen = true
	_sync_visuals()


func _build_world() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.36, 0.5)
	env.ambient_light_energy = 1.0
	world_env.environment = env
	add_child(world_env)
	office = NightWatchOfficeRegistry.make("descent") as NightWatchDescentOffice
	office.name = "Office"
	add_child(office)
	world = office.world
	_spawn_elise()
	_panel_layer = CanvasLayer.new()
	_panel_layer.name = "PanelLayer"
	_panel_layer.layer = 10
	add_child(_panel_layer)
	panel = NightWatchDescentPanel.new()
	panel.position = Vector2(240.0, 124.0) - NightWatchDescentPanel.SIZE * 0.5
	_panel_layer.add_child(panel)
	panel.wire_pressed.connect(func(b: int): press("wires", {"button": b}))
	panel.pad_pressed.connect(func(p: int): press("memory", {"pad": p}))
	panel.pipe_pressed.connect(func(r: int, c: int): press("pipes", {"r": r, "c": c}))
	panel.hold_changed.connect(func(down: bool): hold_down = down)
	hud = NightWatchHud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.retry_pressed.connect(retry)
	hud.next_pressed.connect(next_descent)
	hud.menu_pressed.connect(back_to_board)
	hud.pause_requested.connect(func(): set_paused(true))
	hud.resume_pressed.connect(func(): set_paused(false))
	hud.subtitles_toggled.connect(func(on: bool):
		hud.set_subtitles(on)
		NightWatchSave.set_subtitles(on))
	hud.set_subtitles(NightWatchSave.subtitles())
	hud.set_monitor_available(office.spec.has_monitor)
	hud.hint_label.text = "click the panel   1-6 press a button   hold SPACE to hold the door   R radio   P pause"
	hud.end_next.text = "NEXT DESCENT  ENTER"
	hud.prompt_label.text = ""
	_build_meter()
	death_moment = DeathMoment.new()
	death_moment.name = "DeathMoment"
	add_child(death_moment)
	death_moment.finished.connect(_after_death_moment)
	MouseLock.claim(CLAIM, true)


## The Outside meter: Elise's closeness, blue while the pipes slow her, red past 60%.
func _build_meter() -> void:
	_bar = ColorRect.new()
	_bar.name = "OutsideBar"
	_bar.color = Color(0.1, 0.1, 0.14, 0.85)
	_bar.position = Vector2(8, 52)
	_bar.size = Vector2(72, 5)
	hud.add_child(_bar)
	_bar_fill = ColorRect.new()
	_bar_fill.color = Color("7fd49a")
	_bar_fill.size = Vector2(0, 5)
	_bar.add_child(_bar_fill)
	_bar_label = Label.new()
	_bar_label.add_theme_font_size_override("font_size", 6)
	_bar_label.position = Vector2(0, -9)
	_bar.add_child(_bar_label)


func _spawn_elise() -> void:
	var model := ModelSlot.instantiate_hunter(HunterRoster.get_identity(ELISE_MODEL))
	if model == null:
		push_warning("Descent: no model for Elise")
		model = Node3D.new()
	model.name = "Hunter_elise"
	add_child(model)
	elise = model
	_elise_anim = ModelSlot.find_animation_player(model)
	if _elise_anim != null and _elise_anim.has_animation("idle"):
		_elise_anim.play("idle")
	model.visible = false


# --- what the player does (also what the validators press) ----------------------------------------------------------------

func press(kind: String, args := {}) -> void:
	if state != State.PLAYING:
		return
	_handle(sim.act(kind, args))
	_sync_visuals()
	_check_end()


func set_hold(down: bool) -> void:
	hold_down = down and state == State.PLAYING


func set_paused(on: bool) -> void:
	if state == State.WON or state == State.LOST:
		return
	state = State.PAUSED if on else State.PLAYING
	get_tree().paused = on
	hud.show_pause(on)
	MouseLock.claim("night_watch_pause", on)
	if on:
		hold_down = false


func has_next_level() -> bool:
	return not is_custom and level < NightWatchDescentData.DESCENTS


func next_descent() -> void:
	next_level()


# --- the clock ---------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_animate_elise(delta)
	if state != State.PLAYING or manual_clock:
		return
	advance_ms(delta * 1000.0)


## Step the descent by dt_ms with the door button as it is, and show what happened.
func advance_ms(dt_ms: float) -> void:
	if state != State.PLAYING or _admin_frozen:
		return
	_handle(sim.step(dt_ms, {"hold": hold_down}))
	hud.update_call(sim.elapsed, dt_ms)
	_sync_visuals()
	_check_end()


func _handle(events: Array) -> void:
	for e in events:
		match String(e["type"]):
			"step":
				NightWatchSounds.panel_button()
			"wrong":
				Sound.interaction_fail()
			"stage":
				Sound.collect()
			"ride":
				NightWatchSounds.door(false)
				NightWatchSounds.hour_change()


func _check_end() -> void:
	if sim.over == "win" and state == State.PLAYING:
		_finish_win()
	elif sim.over == "caught" and state == State.PLAYING:
		_finish_caught()


# --- what you see ----------------------------------------------------------------------------------------------------------

func _sync_visuals() -> void:
	var cue := sim.meter_cue()
	var shown_stage := mini(sim.stage_idx + 1, sim.stages.size())
	hud.clock_label.text = "FLOOR %d / %d" % [shown_stage, sim.stages.size()]
	hud.night_label.text = "THE DESCENT · CUSTOM NIGHT" if is_custom else "THE DESCENT · DESCENT %d" % descent
	hud.power_label.text = "%s %d%%" % [String(cue["label"]).to_upper(), int(round(sim.threat))]
	hud.usage_label.text = "WRONG %d" % sim.wrong
	_bar_fill.size.x = _bar.size.x * clampf(sim.threat / 100.0, 0.0, 1.0)
	_bar_fill.color = Color("ff5a5a") if bool(cue["warn"]) else (Color("7fe0ff") if bool(cue["slow"]) else Color("7fd49a"))
	_bar_label.text = ""
	panel.refresh(sim)
	var riding := sim.ride > 0.0 and sim.over == ""
	world.set_ride(1.0 - sim.ride / NightWatchDescentLogic.RIDE_MS if riding else 0.0)
	world.set_alarm(sim.threat if sim.level > 0 else 0.0)
	_place_elise(riding)


func _place_elise(riding: bool) -> void:
	elise.visible = (sim.level > 0 and not riding and sim.over != "win") or (_admin_reveal and sim.level > 0)
	if not elise.visible:
		_side_shown = ""
		return
	var target := world.elise_position(sim.side, sim.threat)
	if _side_shown != sim.side or manual_clock:
		_side_shown = sim.side
		_elise_pos = target
	_face_car()
	if manual_clock:
		elise.position = _elise_pos


func _face_car() -> void:
	elise.rotation.y = PI   # the blocky models' front is -Z: she looks back at the car


## Elise walks along the sill to where the closeness bar says she is (never a jump while the car is still).
func _animate_elise(delta: float) -> void:
	if elise == null or not elise.visible:
		return
	if not manual_clock and sim != null:
		var target := world.elise_position(sim.side, sim.threat)
		var step := 1.4 * delta
		var d := target - _elise_pos
		_elise_moving = d.length() > 0.02
		_elise_pos = target if d.length() <= step else _elise_pos + d.normalized() * step
		elise.position = _elise_pos
		elise.rotation.y = PI
	if _elise_anim != null:
		var clip := "walk" if _elise_moving else "idle"
		if _elise_anim.has_animation(clip) and _elise_anim.current_animation != clip:
			_elise_anim.play(clip)


# --- input ---------------------------------------------------------------------------------------------------------------------

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
					next_descent()
				return
	if event.is_action_pressed(&"pause"):
		if state == State.PLAYING or state == State.PAUSED:
			set_paused(state == State.PLAYING)
		return
	if state != State.PLAYING:
		return
	if event.is_action_pressed(&"office_radio"):
		hud.toggle_mute()
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.physical_keycode == KEY_SPACE:
			hold_down = k.pressed
		elif k.pressed and k.physical_keycode >= KEY_1 and k.physical_keycode <= KEY_6:
			var n := int(k.physical_keycode) - int(KEY_1)
			if sim.kind() == "memory":
				press("memory", {"pad": n})
			elif sim.kind() == "wires":
				press("wires", {"button": n})


# --- the end of a descent ---------------------------------------------------------------------------------------------------

func _freeze() -> void:
	hold_down = false
	MouseLock.claim("night_watch_end", true)


func _finish_win() -> void:
	state = State.WON
	_freeze()
	NightWatchSounds.win()
	record_win()
	var more := has_next_level()
	var title := "CUSTOM NIGHT COMPLETE" if is_custom else "DESCENT %d COMPLETE" % descent
	var body := "BOTTOM FLOOR\nReached the bottom with %d wrong attempt%s." % [sim.wrong, "" if sim.wrong == 1 else "s"]
	if more:
		body += "\nDescent %d is open." % (descent + 1)
	hud.show_end(title, body, more)
	finished.emit("win")


func _finish_caught() -> void:
	state = State.LOST
	_freeze()
	NightWatchSounds.caught()
	var name_text := String(NightWatchDescentData.NAMES["elise"])
	var picked := DeathLines.pick({"hunter_id": "elise", "detail": "shaft"}, "nightwatch:descent:%d" % seed_value, descent, name_text)
	last_death = {"by": "elise", "name": name_text, "picked": picked}
	finished.emit("caught")
	if DeathMoment.plays(picked) and not _admin_no_scare:
		death_moment.play(name_text, picked)
	else:
		_after_death_moment()


func _after_death_moment() -> void:
	if state != State.LOST:
		return
	hud.show_end("CAUGHT", "%s reached the car." % String(last_death.get("name", "Elise")), false)


func _exit_tree() -> void:
	MouseLock.release_all()
	if get_tree() != null:
		get_tree().paused = false


# --- admin hooks (NightWatchAdmin builds the menu from the ones a game has; each really changes the game) ---------------------

func admin_status() -> String:
	return "THE DESCENT  DESCENT %d%s  FLOOR %d / %d (%s)\nELISE  AI %d  CLOSENESS %d%%  WINDOW %s  WRONG %d\nFROZEN %s  GOD %s  NO SCARE %s  SPEED %.1fX  HOLD %s" % [descent, " (CUSTOM)" if is_custom else "",
		mini(sim.stage_idx + 1, sim.stages.size()), sim.stages.size(), sim.kind() if sim.over == "" else sim.over, sim.level, int(round(sim.threat)), sim.side, sim.wrong,
		str(_admin_frozen), str(sim.god), str(_admin_no_scare), sim.speed_mult, str(hold_down)]


func admin_jump_to(target_level: int) -> void:
	NightWatchSession.start_mode(mode_id, target_level)
	get_tree().paused = false
	if get_tree().current_scene == self:
		get_tree().reload_current_scene()


func admin_set_frozen(on: bool) -> void:
	_admin_frozen = on


func admin_is_frozen() -> bool:
	return _admin_frozen


func admin_set_god(on: bool) -> void:
	sim.god = on
	if on:
		sim.threat = minf(sim.threat, 99.0)


func admin_is_god() -> bool:
	return sim.god


func admin_set_no_scare(on: bool) -> void:
	_admin_no_scare = on


func admin_no_scare() -> bool:
	return _admin_no_scare


func admin_set_hunter_speed(mult: float) -> void:
	sim.speed_mult = mult


func admin_hunter_ids() -> Array:
	return ["elise"]


func admin_set_hunter_level(_id: String, level_value: int) -> void:
	sim.admin_set_level(level_value)
	_sync_visuals()


func admin_places() -> Array:
	return ["far", "step 2", "step 1", "at the edge"]


## Elise's place is how close she is: far down the sill, two steps, one step, at the glass.
func admin_place_hunter(_id: String, place: String) -> void:
	sim.admin_set_threat({"far": 0.0, "step 2": 40.0, "step 1": 70.0, "at the edge": 97.0}.get(place, 0.0))
	_sync_visuals()


func admin_play_call() -> void:
	var entry := NightWatchCallsData.for_level(mode_id, descent)
	hud.set_call_script(NightWatchCallScript.new(entry.get("lines", ["Zellia, on the headset."]), 0.0))
	hud.update_call(0.0, 0.0)


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
		sim.by = "elise"
		_finish_caught()


## The Descent's own section: the stage (the elevator's depth), solving, dealing again, wrong attempts, her closeness, the door hold.
func admin_goto_stage(index: int) -> void:
	sim.admin_goto_stage(index)
	_sync_visuals()


func admin_solve_stage() -> void:
	_handle(sim.admin_solve())
	_sync_visuals()
	_check_end()


func admin_redeal() -> void:
	sim.admin_redeal()
	_sync_visuals()


func admin_add_wrong(n: int) -> void:
	sim.wrong = maxi(0, sim.wrong + n)
	_sync_visuals()


func admin_set_closeness(percent: float) -> void:
	sim.admin_set_threat(percent)
	_sync_visuals()


func admin_set_hold(on: bool) -> void:
	hold_down = on and state == State.PLAYING
