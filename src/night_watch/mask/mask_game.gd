class_name MaskGame
extends NightWatchMode

## Masked Hours (mode `mask`), the 3D shift scene: the Classic security room with no doors, in the dark, and a wing of seven rooms the monitor looks into.
## You are the shared player (scenes/night_watch_player.tscn) and USE stations with the shared interact action: the MASK on the desk (put it on / take it
## off), the MONITOR (cameras 1-8; the music box is CAM 1), the MUSIC BOX (hold to wind: the monitor jumps to CAM 1), the two VENT grates and the HALL
## LIGHT (hold for the light), the desk lamp, the chair. Quick keys (on keys the shared map leaves free): Z mask, U monitor, hold G / H the left / right
## vent light, hold X the hall light, hold R to wind, Y the lamp; in the monitor 1-8 or the arrows pick a camera; P pauses. The rules are MaskLogic
## (a port of mask-logic.js, seeded like the 2D game) behind MaskControls (the mask and the monitor are one exclusive pair, as in 2D).
## `manual_clock` stops the real-time clock so the validators step the shift themselves with advance_ms().

enum State { PLAYING, PAUSED, WON, LOST }

const WIN_TEXT := "You held the wing until 6 AM."
const HINT := "WASD move   E use   Z mask (no doors here)   U monitor   G / H vent lights   X hall light   R wind   Y lamp   P pause"
const HOLDS := [["lightL", "ventL", "nw_light_left"], ["lightR", "ventR", "nw_light_right"], ["lightH", "hall_light", "nw_door_right"], ["winPtr", "musicbox", ""]]

var night := 1
var state: State = State.PLAYING
var sim: MaskLogic
var controls: MaskControls
var rng: NightWatchMulberry
var office: MaskOffice
var world: MaskWorld
var player: PlayerController3D
var hud: NightWatchHud
var hunters_root: Node3D
var death_moment: DeathMoment
var world_env: WorldEnvironment
var overlay: MaskOverlay
var held_label: Label
var last_death := {}
var monitor_shown := false   # the monitor's picture is on screen (fully up)
## Whether the player is on the monitor: it is up, or on its way (the panel machine raises it in 250 ms). The camera keys and the shared handler read this.
var monitor_up: bool:
	get:
		return controls != null and controls.want == "monitor"
## The camera on the monitor.
var monitor_room: String:
	get:
		return controls.cam if controls != null else "music"

var _models := {}
var _walkers := {}
var _players := {}
var _driven := {}
var _hour_seen := 0
var _last_input := {}
var _flinch := {}
var _vent_pose := NightWatchVentPose.new()
## Admin (NightWatchAdmin): the menu (null for non-admins) and the live switches the admin hooks below set.
var admin_menu: AdminMenu
var _admin_frozen := false
var _admin_no_scare := false
var _admin_reveal := false
var _admin_noclip := false
var _admin_god := false


class MaskOverlay extends Control:
	var cover := 0.0

	func _draw() -> void:
		if cover <= 0.0:
			return
		var r := get_rect()
		var a := clampf(cover, 0.0, 1.0)
		draw_rect(Rect2(Vector2.ZERO, r.size), Color(0.88, 0.86, 0.80, 0.97 * a))
		# the eye slits you see the wing through
		var eye := Vector2(r.size.x * 0.12, r.size.y * 0.05)
		for cx in [r.size.x * 0.34, r.size.x * 0.66]:
			draw_rect(Rect2(Vector2(cx, r.size.y * 0.42) - eye * 0.5, eye), Color(0.05, 0.05, 0.08, 0.92 * a))
		draw_rect(Rect2(Vector2(r.size.x * 0.46, r.size.y * 0.62), Vector2(r.size.x * 0.08, r.size.y * 0.012)), Color(0.35, 0.33, 0.3, a))


func _ready() -> void:
	NightWatchControls.register()
	read_session()
	night = clampi(5 if is_custom else level, 1, 6)
	_build_world()
	rng = NightWatchMulberry.new(seed_value)
	controls = MaskControls.new()
	sim = MaskLogic.new(night, rng, {"levels": custom, "custom": is_custom})
	_spawn_hunters()
	hud.set_call_script(NightWatchCallScript.new([], 0.0) if is_custom else NightWatchCallScript.for_level(mode_id, night))   # Zellia rings at the night's `at`; fed the shift clock
	admin_menu = NightWatchAdmin.attach(self)   # after the sim exists
	hud.hint_label.text = _hint()
	_set_feed("music")
	_sync_visuals()


func _build_world() -> void:
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.015, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.38, 0.55)
	env.ambient_light_energy = 0.5
	world_env.environment = env
	add_child(world_env)
	office = NightWatchOfficeRegistry.make("mask") as MaskOffice
	office.name = "Office"
	add_child(office)
	world = MaskWorld.new()
	world.name = "Wing"
	world.office = office
	add_child(world)
	hunters_root = Node3D.new()
	hunters_root.name = "Hunters"
	add_child(hunters_root)
	var layer := CanvasLayer.new()
	layer.name = "MaskLayer"
	layer.layer = 15
	add_child(layer)
	overlay = MaskOverlay.new()
	overlay.name = "MaskOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)
	hud = NightWatchHud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.camera_selected.connect(select_camera)
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
	hud.hint_label.text = _hint()
	hud.mode_text = "2. Masked Hours · %s" % ("Custom Night" if is_custom else "Night %d" % night)
	_build_map_buttons()
	death_moment = DeathMoment.new()
	death_moment.name = "DeathMoment"
	add_child(death_moment)
	death_moment.finished.connect(_after_death_moment)
	player = (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	add_child(player)
	player.global_position = office.spawn_position()
	face_player(0.0, -0.1)
	player.interaction_message.connect(func(message: String): hud.show_note(message))
	office.set_lamp(false)
	_wire_stations()


## The monitor's camera map comes from the mode's layout (NightWatchMapRegistry): the prize corner, parts room, show stage, game area, vent hub, the two air vents and the main hall.
func _build_map_buttons() -> void:
	hud.set_cam_layout(NightWatchMapRegistry.layout_for("mask"))
	held_label = Label.new()
	held_label.name = "HeldLabel"
	held_label.text = "HELD STILL"
	held_label.add_theme_font_size_override("font_size", 9)
	held_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	held_label.position = Vector2(30, 40)
	held_label.visible = false
	hud.monitor_root.add_child(held_label)


func face_player(yaw: float, pitch := 0.0) -> void:
	player.rotation.y = yaw
	player.set("_yaw", yaw)
	player.set("_pitch", pitch)
	player.call("_apply_look_rotation")


func _wire_stations() -> void:
	var st: Dictionary = office.stations
	(st["monitor"] as NightWatchStation).on_activate = func(_p) -> String:
		press("monitor")
		return ""
	(st["mask"] as NightWatchStation).on_activate = func(_p) -> String:
		press("mask")
		return ""
	(st["lamp"] as NightWatchStation).on_activate = func(_p) -> String:
		press("lamp")
		return ""
	(st["chair"] as NightWatchStation).on_activate = func(p) -> String:
		return String(p.use_furniture(st["chair"], "sit"))
	for id in ["ventL", "ventR", "hall_light", "musicbox"]:
		(st[id] as NightWatchStation).on_activate = func(_p) -> String: return ""   # held, see _process


func _spawn_hunters() -> void:
	for id in MaskData.CAST:
		var model := NightWatchHunterScale.instantiate(HunterRoster.get_identity(id))
		if model == null:
			push_warning("Masked Hours: no model for %s" % id)
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


# --- player actions (also what the validators press) -----------------------------------------------------------------------

## One control input (mask, monitor, lightL, lightR, lightH, winKey, winPtr, lamp, cam:<room>) through the exclusive-panel machine.
func press(action: String, on := true) -> void:
	if state != State.PLAYING:
		return
	for e in controls.press(action, on):
		_on_control_event(e)
	if action.begins_with("cam:") and controls.is_up("monitor"):
		_set_feed(controls.cam)
	if action == "winKey" or action == "winPtr":
		if on and controls.is_up("monitor"):
			_set_feed("music")
	_refresh_lock()
	_update_hint()


func toggle_monitor() -> void:
	press("monitor")


# the camera API the shared key handler and the key-flow suite use (NightWatchControls.handle_monitor_event)
func is_playing() -> bool:
	return state == State.PLAYING


func open_monitor() -> void:
	if not monitor_up:
		press("monitor")


func close_monitor() -> void:
	if monitor_up:
		press("monitor")


func camera_rooms() -> Array:
	return MaskData.cam_rooms()


func camera_room_for(n: int) -> String:
	return MaskData.room_for_cam(n)


func select_camera_number(n: int) -> void:
	select_camera(MaskData.room_for_cam(n))


## The raise / lower animation ends at once (the player waits for it); no shift time passes.
func _settle() -> void:
	for e in controls.step(500.0):
		_on_control_event(e)
	_refresh_lock()


func _update_hint() -> void:
	if monitor_up:
		hud.hint_label.text = "%s / %s or 1-8 camera   %s or %s close   hold %s wind (CAM 1)   hold %s / %s vent light on CAM 6 / 7" % [NightWatchControls.key_text(NightWatchControls.CAM_PREV), NightWatchControls.key_text(NightWatchControls.CAM_NEXT), NightWatchControls.key_text(NightWatchControls.MONITOR), NightWatchControls.key_text(&"interact"), NightWatchControls.key_text(&"office_radio"), NightWatchControls.key_text(NightWatchControls.LIGHT_LEFT), NightWatchControls.key_text(NightWatchControls.LIGHT_RIGHT)]
	else:
		hud.hint_label.text = _hint()


func select_camera(room: String) -> void:
	if state != State.PLAYING or not MaskData.ROOMS.has(room) or int(MaskData.ROOMS[room]["cam"]) == 0:
		return
	if not monitor_up:
		return
	if not controls.is_up("monitor"):
		_settle()
	press("cam:" + room)
	hud.flash_static()
	NightWatchSounds.camera_switch()


func cycle_camera(step: int) -> void:
	var rooms := MaskData.cam_rooms()
	var i := rooms.find(controls.cam)
	select_camera(String(rooms[posmod(i + step, rooms.size())]))


## While a panel is wanted the player's hands are on it: no walking, no looking around (as Classic's monitor).
func _refresh_lock() -> void:
	var busy: bool = controls.want == "monitor" or controls.panel == "monitor"
	var frozen: bool = busy or state != State.PLAYING
	player.input_frozen = frozen
	player.look_frozen = frozen
	MouseLock.claim("night_watch_monitor", busy)


func _on_control_event(e: Dictionary) -> void:
	var panel := String(e.get("panel", ""))
	match String(e["type"]):
		"raise":
			if panel == "monitor":
				NightWatchSounds.monitor_toggle()
			else:
				NightWatchSounds.panel_button()
		"up":
			if panel == "monitor":
				monitor_shown = true
				hud.show_monitor(true)
				_set_feed(controls.cam)
				hud.flash_static()
		"lower":
			if panel == "monitor":
				monitor_shown = false
				hud.show_monitor(false)
				NightWatchSounds.monitor_toggle()
		"lamp":
			office.set_lamp(bool(e["on"]) and float(sim.s["battery"]) > 0.0)
			NightWatchSounds.panel_button()


func _set_feed(room: String) -> void:
	hud.set_cam(room, world.feed_transform(room))
	_update_cam_label(room)


func _update_cam_label(room: String) -> void:
	var text := MaskData.cam_label(room)
	if room == "music":
		text += "    BOX %d%%    HOLD TO WIND" % int(round(float(sim.s["box"]))) if sim != null else ""
	hud.cam_label.text = text


func set_paused(on: bool) -> void:
	if state == State.WON or state == State.LOST:
		return
	state = State.PAUSED if on else State.PLAYING
	get_tree().paused = on
	hud.show_pause(on)
	MouseLock.claim("night_watch_pause", on)


func has_next_level() -> bool:
	return not is_custom and level < 6


func next_night() -> void:
	next_level()


# --- the clock -------------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_animate_models(delta)
	if state != State.PLAYING:
		return
	var aimed: NightWatchStation = null
	if not monitor_shown:
		aimed = player.call("_nearest_interactable") as NightWatchStation
	hud.set_prompt(player.get_interaction_prompt() if not monitor_shown else "")
	if manual_clock:
		return
	# the held controls: a quick key, or interact held on the matching station
	for h in HOLDS:
		var by_key: bool = String(h[2]) != "" and Input.is_action_pressed(StringName(h[2]))
		var by_station: bool = Input.is_action_pressed(&"interact") and aimed != null and aimed.station_id == String(h[1])
		var want: bool = by_key or by_station
		if want != bool(controls.held[h[0]]):
			press(String(h[0]), want)
	var wind_key := Input.is_action_pressed(&"office_radio")
	if wind_key != bool(controls.held["winKey"]):
		press("winKey", wind_key)
	advance_ms(delta * 1000.0)


## Step the shift by dt_ms with the controls as they are, and show what happened.
func advance_ms(dt_ms: float) -> void:
	if state != State.PLAYING or _admin_frozen:
		return
	for e in controls.step(dt_ms):
		_on_control_event(e)
	_refresh_lock()   # the monitor finishes lowering here, not on a key press: the cursor goes back to the view when it is down
	var input := controls.control_input()
	_last_input = input
	var events := sim.step(dt_ms, input)
	hud.update_call(float(sim.s["elapsed"]), dt_ms)
	if _admin_god and String(sim.s["over"]) == "caught":
		_god_rescue()
		events = []
	var hour := NightWatchData.hour_index(float(sim.s["elapsed"]))
	if hour != _hour_seen:
		_hour_seen = hour
		NightWatchSounds.hour_change()
	for e in events:
		_on_event(e)
	_sync_visuals()
	if String(sim.s["over"]) == "win":
		_finish_win()
	elif String(sim.s["over"]) == "caught":
		_finish_caught()


func _pan_of(e: Dictionary) -> float:
	if e.has("side"):
		return -1.0 if String(e["side"]) == "L" else 1.0
	return float(MaskData.ROOMS.get(String(e.get("room", "")), {}).get("pan", 0.0))


func _on_event(e: Dictionary) -> void:
	var pan := _pan_of(e)
	match String(e["type"]):
		"room":
			NightWatchSounds.office("footsteps", pan, 0.5)
		"hall", "step":
			NightWatchSounds.office("footsteps", 0.0, 0.7 + 0.1 * float(e.get("step", 0)))
		"office":
			NightWatchSounds.office("crimson_door", 0.0, 1.0)
		"leave", "rushRetreat", "ventRetreat":
			NightWatchSounds.office("scrape", pan, 0.9)
		"rush", "door":
			NightWatchSounds.attack_warning(0.0)
		"flashHit":
			NightWatchSounds.office("presence", 0.0, 1.0)
		"duct", "fetch", "creep":
			NightWatchSounds.office("scrape", pan, 0.8)
		"vent":
			NightWatchSounds.attack_warning(pan)
		"dark":
			NightWatchSounds.power_out()
			hud.show_call("The flashlight is dead.")
		"boxEmpty":
			NightWatchSounds.attack_warning(0.0)
			hud.show_call("The music box has stopped.")
		"boxSaved":
			NightWatchSounds.panel_button()
	if monitor_shown and e.has("room") and (String(e["room"]) == controls.cam):
		hud.flash_static()


# --- what you see ----------------------------------------------------------------------------------------------------------

func _sync_visuals() -> void:
	if _admin_reveal:
		hud.cam_map.set_blips(_hunter_rooms())
	elif hud.cam_map.blips.size() > 0:
		hud.cam_map.set_blips([])
	var s := sim.s
	var lit: Dictionary = s["lit"]
	office.set_light("hall", bool(lit["H"]))
	office.set_button("hall_light", bool(lit["H"]))
	office.set_lamp(controls.lamp and float(s["battery"]) > 0.0)
	for side in ["L", "R"]:
		(office.vent_beams[side] as SpotLight3D).visible = bool(lit[side])
		office.glints["vent" + side].visible = sim.vent_glint(side)
	for duct in MaskData.DUCTS:
		var side: String = MaskData.DUCT_SIDE[duct]
		(world.duct_lights[duct] as OmniLight3D).visible = bool(lit[side]) and controls.is_up("monitor") and controls.cam == duct
		world.glints[duct].visible = sim.glint(duct)
	office.set_box(float(s["box"]))
	world.set_box(float(s["box"]))
	overlay.cover = controls.cover("mask")
	overlay.queue_redraw()
	var devices := (1 if bool(lit["L"]) or bool(lit["R"]) else 0) + (1 if bool(lit["H"]) else 0) + (1 if bool(s["lamp"]) else 0) + (1 if monitor_shown else 0)
	hud.update_status(NightWatchData.hour_index(float(s["elapsed"])), float(s["battery"]), devices, night)
	hud.power_label.text = "BATTERY %d%%" % int(ceil(float(s["battery"])))
	hud.usage_label.text = "MUSIC BOX %d%%" % int(round(float(s["box"])))
	if monitor_shown:
		_update_cam_label(controls.cam)
		held_label.visible = not (s["frozen"] as Array).is_empty()
		var ducts: bool = MaskData.DUCT_SIDE.has(controls.cam)
		var bright: bool = not ducts or bool(lit[MaskData.DUCT_SIDE[controls.cam]])
		hud.feed_camera.environment.ambient_light_energy = 1.15 if bright else 0.1
	_place_hunters()


## Where each hunter is and what she is doing, from the rules: [model position, facing, visible, driven by the rules, running].
func _target(id: String) -> Dictionary:
	var s := sim.s
	var face := player.global_position
	match id:
		"thessine":
			var h: Dictionary = s["hall"]["thessine"]
			match String(h["state"]):
				"hall":
					return {"room": "hall", "pos": world.hall_pos(int(h["step"])), "face": face}
				"office":
					return {"room": "office", "pos": world.stand_at("office", 0), "face": face}
				_:
					return {"room": String(h["room"]), "pos": world.stand_at(String(h["room"]), 0), "face": world.camera_transform(String(h["room"])).origin if world.rooms.has(String(h["room"])) else face}
		"umbriel":
			var r: Dictionary = s["rush"]
			if String(r["state"]) == "run" or String(r["state"]) == "door":
				var p := 1.0 if String(r["state"]) == "door" else minf(1.0, float(r["t"]) / maxf(1.0, float(r["need"])))
				return {"room": "hall", "pos": world.rush_pos(p), "face": face, "driven": true}
			var rr := String(r["room"])
			var cam_origin: Vector3 = world.camera_transform(rr).origin
			return {"room": rr, "pos": world.stand_at(rr, 1 if String(r["state"]) == "poised" else 0), "face": cam_origin}
		"verrine", "haelith", "ilyra":
			var v := sim.vent_state(id)
			var vs := String(v["state"])
			if vs == "vent":
				return {"room": "vent" + String(v["side"]), "pos": office.global_position + MaskWorld.VENT_STAND[String(v["side"])], "face": face, "vent": String(v["side"])}
			var room := String(v["room"])
			var at := "stand"
			if id == "ilyra" and MaskData.DUCT_SIDE.has(room):
				at = ["far", "stand", "near"][clampi(int(v["step"]) - 1, 0, 2)]
			return {"room": room, "pos": world.stand_at(room, 0 if id == "verrine" else (1 if id == "haelith" else 2) % 2, at), "face": world.camera_transform(room).origin, "duct": room if MaskData.DUCT_SIDE.has(room) else ""}
		"glyra":
			var back: float = clampf(float(s["boxZero"]) / float(MaskLogic.T["boxGraceMs"]), 0.0, 1.0)
			var base: Vector3 = world.stand_at("music", 0) + Vector3(0.6, 0.0, -1.2)
			return {"room": "music", "pos": base + Vector3(0.0, 0.0, 3.0 * back), "face": world.camera_transform("music").origin}
	return {}


func _place_hunters() -> void:
	var s := sim.s
	var lit: Dictionary = s["lit"]
	for id in MaskData.CAST:
		var model := _models[id] as Node3D
		if id == "nyxie":
			var dark := float(s["dark"]) > 0.0 and sim.base_level("nyxie") > 0
			model.visible = dark
			if dark:
				var t := clampf(float(s["dark"]) / MaskLogic.dark_grace_ms(sim.base_level("nyxie")), 0.0, 1.0)
				var from := office.global_position + Vector3(0.0, 0.0, -MaskWorld.HALL_NEAR)
				var to := office.global_position + Vector3(0.5, 0.0, -1.0)
				_set_pose(model, from.lerp(to, t), player.global_position)
			continue
		var tgt := _target(id)
		var present := true
		if id == "glyra":
			present = MaskLogic.active_hunters(night - 1).has("glyra") or (sim.levels.has("glyra") and int(sim.levels["glyra"]) > 0)
		else:
			present = sim.level(id) > 0
		var shown := present
		if tgt.has("vent"):
			shown = shown and bool(lit[String(tgt["vent"])])
		elif String(tgt.get("duct", "")) != "":
			shown = shown and bool(lit[String(MaskData.DUCT_SIDE[String(tgt["duct"])])])
		model.visible = shown
		if tgt.is_empty():
			continue
		_driven[id] = bool(tgt.get("driven", false))
		var pos: Vector3 = tgt["pos"]
		var walker := _walkers.get(id) as NightWatchWalker
		var room_key := String(tgt["room"])
		if walker == null:
			walker = NightWatchWalker.new()
			_walkers[id] = walker
			walker.place(pos, pos, tgt["face"], room_key)
		elif manual_clock or _driven[id] or tgt.has("vent") or room_key.begins_with("vent"):
			walker.place(pos, pos, tgt["face"], room_key)
		elif walker.room != room_key:
			walker.go(_legs_to(walker, room_key, pos), room_key, pos)
			walker.look = tgt["face"]
		else:
			walker.final = pos
			walker.look = tgt["face"]
		model.position = walker.pos
		model.rotation.y = walker.yaw


## The walk to a new place: along the wing's real waypoints (the show floor, the main hall, the side halls, the vent hub and the ducts); nothing jumps.
func _legs_to(walker: NightWatchWalker, room_key: String, _pos: Vector3) -> Array:
	return world.legs_from(walker.pos, room_key)


func _set_pose(model: Node3D, pos: Vector3, face: Vector3) -> void:
	model.position = pos
	var d := face - pos
	d.y = 0.0
	if d.length() > 0.01:
		model.rotation.y = atan2(d.x, d.z) + PI


## A vent hunter is in a shaft while she crawls a duct or waits in an office vent.
func _in_shaft(id: String) -> bool:
	var st := String(sim.vent_state(id)["state"])
	return st == "duct" or st == "vent"


func _animate_models(delta: float) -> void:
	for id in _walkers:
		var walker := _walkers[id] as NightWatchWalker
		if not manual_clock and not bool(_driven.get(id, false)):
			walker.step(delta)
		var model := _models[id] as Node3D
		model.position = walker.pos
		model.rotation.y = walker.yaw
	for id in _players:
		var ap := _players[id] as AnimationPlayer
		var walker2 := _walkers.get(id) as NightWatchWalker
		if sim != null and MaskData.VENT_HUNTERS.has(id) and _vent_pose.update(id, _models[id] as Node3D, _in_shaft(id), walker2 != null and walker2.moving, delta):
			continue
		var clip := "idle"
		if bool(_driven.get(id, false)):
			clip = "sprint"
		elif walker2 != null and walker2.moving:
			clip = "sprint" if walker2.running and ap.has_animation("sprint") else "walk"
		if ap.has_animation(clip) and ap.current_animation != clip:
			ap.play(clip)


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
	if event.is_action_pressed(NightWatchControls.DOOR_LEFT):
		press("mask")
	elif event.is_action_pressed(NightWatchControls.LAMP):
		press("lamp")


# --- the end of a shift ----------------------------------------------------------------------------------------------------

func _freeze_player() -> void:
	controls.cancel()
	monitor_shown = false
	hud.show_monitor(false)
	overlay.cover = 0.0
	overlay.queue_redraw()
	player.input_frozen = true
	player.look_frozen = true
	MouseLock.claim("night_watch_monitor", false)
	MouseLock.claim("night_watch_end", true)


func _finish_win() -> void:
	state = State.WON
	_freeze_player()
	NightWatchSounds.win()
	var score := record_win()
	var more := has_next_level()
	if is_custom:
		var max_score := MaskData.CAST.size() * NightWatchModesData.MAX_AI * NightWatchModesData.POINTS_PER_LEVEL
		hud.show_end("CUSTOM NIGHT COMPLETE", "6:00 AM\n%s\nScore %d of %d: %s" % [WIN_TEXT, score, max_score, NightWatchModesData.rating_of(score, max_score)], false)
	else:
		hud.show_end("NIGHT %d COMPLETE" % night, "6:00 AM\n" + WIN_TEXT + ("\nNight %d is open." % (night + 1) if more else "\nYou cleared every night."), more)
	finished.emit("win")


func _finish_caught() -> void:
	state = State.LOST
	_freeze_player()
	NightWatchSounds.caught()
	var by := String(sim.s["by"])
	var cause := {"hunter_id": by}
	if by == "nyxie":
		cause["detail"] = "darkness"
	elif by == "glyra":
		cause["detail"] = "music box"
	var name_text := String(MaskData.NAMES.get(by, by.capitalize()))
	var picked := DeathLines.pick(cause, "nightwatch:mask:%d" % seed_value, night, name_text)
	last_death = {"by": by, "name": name_text, "picked": picked}
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


# --- admin hooks (NightWatchAdmin builds the menu from the ones a game has; each really changes the game) ---------------------

func _hint() -> String:
	return HINT + ("   0 admin" if admin_menu != null else "")


## The camera rooms each hunter is in now (REVEAL puts a red dot on each).
func _hunter_rooms() -> Array:
	var rooms := []
	for id in ["thessine", "umbriel", "verrine", "haelith", "ilyra"]:
		var room := ""
		if id == "thessine":
			room = String(sim.s["hall"]["thessine"]["room"])
		elif id == "umbriel":
			room = String(sim.s["rush"]["room"])
		else:
			room = String(sim.vent_state(id)["room"])
		if MaskData.ROOMS.has(room) and int(MaskData.ROOMS[room]["cam"]) > 0 and not rooms.has(room):
			rooms.append(room)
	return rooms


## God mode: a hunter that would catch you is sent home, the box is wound, the flashlight keeps a little charge.
func _god_rescue() -> void:
	sim.s["over"] = ""
	sim.s["by"] = ""
	for id in MaskData.HALL_HUNTERS:
		var h := sim.s["hall"][id] as Dictionary
		h["state"] = "away"
		h["room"] = MaskData.HOME[id]
		h["cool"] = 4000.0
	var r := sim.s["rush"] as Dictionary
	r["state"] = "away"
	r["room"] = MaskData.HOME[MaskData.RUSHER]
	r["cool"] = 8000.0
	for id in MaskData.VENT_HUNTERS:
		var v := sim.vent_state(id)
		v["state"] = "away"
		v["room"] = MaskData.HOME[id]
		v["step"] = 0
	sim.s["vent"]["cool"] = 6000.0
	sim.s["boxZero"] = 0.0
	sim.s["box"] = maxf(float(sim.s["box"]), 50.0)
	sim.s["dark"] = 0.0
	sim.s["battery"] = maxf(float(sim.s["battery"]), 20.0)


func admin_status() -> String:
	return "MASKED HOURS  NIGHT %d  %s (SEED %d)\nBATTERY %d%%  MUSIC BOX %d%%  MASK %s\nFROZEN %s  GOD %s  NO SCARE %s  SPEED %.1fX" % [night, NightWatchData.hour_label(NightWatchData.hour_index(float(sim.s["elapsed"]))), seed_value,
		int(ceil(float(sim.s["battery"]))), int(round(float(sim.s["box"]))), "ON" if controls.is_up("mask") else "OFF", str(_admin_frozen), str(_admin_god), str(_admin_no_scare), sim.hunter_speed]


func admin_hunter_rows() -> Array:
	var rows := []
	var th := sim.s["hall"]["thessine"] as Dictionary
	rows.append("THESSINE  %s  %s" % [String(th["state"]).to_upper(), th["room"]])
	rows.append("UMBRIEL  %s  FLASHES %d/%d" % [String(sim.s["rush"]["state"]).to_upper(), int(sim.s["rush"]["flashes"]), int(sim.s["rush"]["goal"])])
	for id in MaskData.VENT_HUNTERS:
		rows.append("%s  %s  %s" % [id.to_upper(), String(sim.vent_state(id)["state"]).to_upper(), sim.vent_state(id)["room"]])
	return rows


func admin_jump_to(target_level: int) -> void:
	NightWatchSession.start_mode(mode_id, target_level)
	get_tree().paused = false
	if get_tree().current_scene == self:
		get_tree().reload_current_scene()


func admin_set_hour(hour_value: int) -> void:
	sim.s["elapsed"] = clampf(float(hour_value) * NightWatchData.HOUR_MS, 0.0, NightWatchData.NIGHT_MS - 1000.0)
	_hour_seen = hour_value
	_sync_visuals()


func admin_set_frozen(on: bool) -> void:
	_admin_frozen = on


func admin_is_frozen() -> bool:
	return _admin_frozen


## "Power" here is the flashlight's battery.
func admin_set_power(percent: float) -> void:
	sim.s["battery"] = clampf(percent, 0.0, 100.0)
	if float(sim.s["battery"]) > 0.0:
		sim.s["dark"] = 0.0
	_sync_visuals()


func admin_set_infinite_power(on: bool) -> void:
	sim.infinite_battery = on


func admin_infinite_power() -> bool:
	return sim.infinite_battery


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
	return ["thessine", "umbriel", "verrine", "haelith", "ilyra", "glyra", "nyxie"]


func admin_set_hunter_level(id: String, level_value: int) -> void:
	sim.levels[id] = level_value
	if id == "glyra":
		sim._decay = MaskLogic.box_decay_for_level(level_value)


func admin_places() -> Array:
	return ["costume", "ballroom", "hall", "office", "gallery", "ductL", "ductR", "ventL", "ventR", "crawl"]


## Put a hunter where she belongs in that place: Thessine on the floor, in the hall or in the office; Umbriel poised in the ballroom or running the hall; the vent hunters in a duct, at a
## vent or home in the crawlspace (only one vent hunter is ever out, so the others go home first).
func admin_place_hunter(id: String, place: String) -> void:
	match id:
		"thessine":
			var h := sim.s["hall"]["thessine"] as Dictionary
			if place == "office":
				h.merge({"state": "office", "room": "office", "t": 0.0, "step": 0, "fooled": 0.0, "off": 0.0, "window": float(MaskLogic.T["windowMs"])}, true)
			elif place == "hall":
				h.merge({"state": "hall", "room": "hall", "t": 0.0, "step": 2, "need": 2300.0}, true)
			elif place == "ballroom" or place == "gallery":
				h.merge({"state": "room", "room": "ballroom", "t": 0.0, "need": 4000.0}, true)
			else:
				h.merge({"state": "away", "room": MaskData.HOME["thessine"], "cool": 4000.0}, true)
		"umbriel":
			var r := sim.s["rush"] as Dictionary
			if place == "hall":
				var lv := sim.level(MaskData.RUSHER)
				r.merge({"state": "run", "room": "hall", "t": 0.0, "need": MaskLogic.rush_run_ms(lv), "flashes": 0, "goal": MaskLogic.rush_flashes(lv), "doorNeed": MaskLogic.rush_door_ms(lv)}, true)
			elif place == "ballroom":
				r.merge({"state": "poised", "room": "ballroom", "t": 0.0, "need": 4000.0}, true)
			else:
				r.merge({"state": "away", "room": MaskData.HOME[MaskData.RUSHER], "cool": 8000.0}, true)
		"verrine", "haelith", "ilyra":
			for other in MaskData.VENT_HUNTERS:
				if other != id:
					var o := sim.vent_state(other)
					o["state"] = "away"
					o["room"] = MaskData.HOME[other]
			var v := sim.vent_state(id)
			var side := "L" if place.ends_with("L") else "R"
			if place == "ductL" or place == "ductR":
				v.merge({"state": "duct", "room": place, "side": side, "t": 0.0, "need": 4000.0, "lit": 0.0, "step": 1}, true)
			elif place == "ventL" or place == "ventR":
				v.merge({"state": "vent", "room": place, "side": side, "t": 0.0, "lit": 0.0, "wait": 6000.0, "step": 0}, true)
			else:
				v.merge({"state": "away", "room": MaskData.HOME[id], "step": 0}, true)
	_sync_visuals()


func admin_all_home() -> void:
	for id in admin_hunter_ids():
		if id != "glyra" and id != "nyxie":
			admin_place_hunter(id, "crawl" if MaskData.VENT_HUNTERS.has(id) else "gallery")


func admin_set_mask(on: bool) -> void:
	if controls.is_up("mask") != on or (controls.want == "mask") != on:
		press("mask")
	for e in controls.step(500.0):
		_on_control_event(e)
	_refresh_lock()
	_sync_visuals()


func admin_set_box(percent: float) -> void:
	sim.s["box"] = clampf(percent, 0.0, 100.0)
	_sync_visuals()


func admin_set_mask_timer(ms: float) -> void:
	var h := sim.s["hall"]["thessine"] as Dictionary
	if String(h["state"]) != "office":
		admin_place_hunter("thessine", "office")
	h["fooled"] = ms


func admin_play_call() -> void:
	var entry := NightWatchCallsData.for_level(mode_id, night)
	hud.set_call_script(NightWatchCallScript.new(entry.get("lines", ["Zellia, on the headset."]), 0.0))
	hud.update_call(0.0, 0.0)


## One quick flash of the hall light (what answers Umbriel); a dead flashlight gets a little charge first.
func admin_flash_hall() -> void:
	if float(sim.s["battery"]) <= 0.0:
		admin_set_power(5.0)
	press("lightH", true)
	advance_ms(100.0)
	press("lightH", false)
	advance_ms(100.0)


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
		sim.s["over"] = "win"
		_finish_win()


func admin_lose() -> void:
	if state == State.PLAYING:
		sim.s["over"] = "caught"
		sim.s["by"] = "thessine"
		_finish_caught()


func admin_set_noclip(on: bool) -> void:
	_admin_noclip = on
	player.set_admin_noclip(on)


func admin_is_noclip() -> bool:
	return _admin_noclip


func _exit_tree() -> void:
	MouseLock.release_all()
	NightWatchControls.unregister()
	if get_tree() != null:
		get_tree().paused = false
