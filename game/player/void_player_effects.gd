class_name VoidPlayerEffects
extends RefCounted

## The player's side of the Void powers that act on the runner (Gray's signal route, Orange's system outages, Purple's radar static,
## Pink's false footsteps).
## The host's gimmick decides and sends a player event; this applies it on the affected player's own machine, for both route scenes.
##
##   apply(event)  -> true when the event was one of these three
##   tick(delta)   -> once per frame (the signal route counts E presses against its clock; the radar overlay expires)
##   host_route_result(views, peer_id, ok) -> the host feeding a player's route result back into Gray's gimmick

var player: PlayerController3D
var hud: HUD
## Called with `ok` when a signal route ends; the scene forwards it to the host.
var report_route: Callable

var route_active := false
var route_nodes_left := 0
var route_nodes := 0
var route_seconds := 0.0
var route_remaining := 0.0

## Pink's false footsteps (`fake_footsteps`): a short run of quiet hunter footfalls, played on the targeted player's machine only.
## Everything the scene can answer is injectable, so a test needs no audio device and no waiting:
##   sound_sink     Callable(pan: float, volume: float, surface: String); default is Sound.hunter_footstep
##   peer_source    Callable() -> int, this machine's peer id (a step meant for another peer is ignored)
##   depth_source   Callable() -> int, the level the player is on, in the same units as a runner state's "depth"
##   surface_source Callable() -> String, the floor surface under the player (SurfaceSounds names; "" = the generic step)
## The steps are a queue counted down by tick(), the same per-frame call that runs the signal route and the radar overlay, so
## nothing blocks and nothing outlives the scene.
var sound_sink: Callable = Callable()
var peer_source: Callable = Callable()
var depth_source: Callable = Callable()
var surface_source: Callable = Callable()
var _fake_steps: Array = []   # [{"left": seconds until it sounds, "pan": float, "volume": float, "surface": String}]
var fake_steps_played := 0

## A false step is quieter than a real hunter's at the same distance (real: .09 * (1 - d / 9), silent past 9 m). The floor is the
## lowest volume Sound.hunter_footstep plays at all (its scale clamps at 0.1 of .05), so the far end stays barely audible.
const FAKE_STEP_QUIET := 0.55
const FAKE_STEP_FLOOR := 0.005
const FAKE_STEP_LEAD := 0.12
const FAKE_STEPS_MAX := 8


func _init(p_player: PlayerController3D, p_hud: HUD, p_report: Callable) -> void:
	player = p_player
	hud = p_hud
	report_route = p_report


func apply(event: Dictionary) -> bool:
	match String(event.get("what", "")):
		"signal_route":
			route_active = true
			route_nodes = int(event.get("nodes", 5))
			route_nodes_left = route_nodes
			route_seconds = float(event.get("seconds", 2.5))
			route_remaining = route_seconds
			if HunterBrain.ANNOUNCE_HUNTER_EVENTS:
				Sound.alert()
			_prompt()
			return true
		"system_outage":
			var system := String(event.get("system", ""))
			var seconds := float(event.get("seconds", 9.0))
			player.begin_outage(system, seconds)
			if system == "radar":
				hud.set_radar_state("offline", seconds)
			Sound.system_offline()
			var note := String(event.get("message", ""))
			if not note.is_empty():
				hud.show_message(note)
			return true
		"radar_corrupt":
			hud.set_radar_state(String(event.get("mode", "static")), float(event.get("seconds", 8.0)))
			Sound.radar_static()
			var radar_note := String(event.get("message", ""))
			if not radar_note.is_empty():
				hud.show_message(radar_note)
			return true
		"fake_footsteps":
			_begin_fake_footsteps(event)
			return true
	return false


## Volume of one false step at `distance` metres: the real-hunter curve, scaled down, with a floor so the far end stays audible.
static func fake_step_volume(distance: float) -> float:
	return maxf(.09 * (1.0 - clampf(distance, 0.0, 9.0) / 9.0) * FAKE_STEP_QUIET, FAKE_STEP_FLOOR)


## The steps of one `fake_footsteps` event as [{"at": seconds from the start, "pan", "volume"}]. An approach closes from `distance`
## to about two thirds of it and drifts toward the centre; otherwise the walker moves off and drifts out to the side.
static func fake_footstep_plan(event: Dictionary) -> Array:
	var steps := clampi(int(event.get("steps", 5)), 1, FAKE_STEPS_MAX)
	var gap := clampf(float(event.get("gap", .42)), .25, 1.0)
	var pan0 := clampf(float(event.get("pan", 0.0)), -1.0, 1.0)
	var distance0 := clampf(float(event.get("distance", 6.0)), 1.0, 12.0)
	var approach := bool(event.get("approach", false))
	var side := -1.0 if pan0 < 0.0 else 1.0
	var plan: Array = []
	for i in steps:
		var t := float(i) / maxf(steps - 1, 1)
		var distance := lerpf(distance0, distance0 * .65, t) if approach else lerpf(distance0, distance0 * 1.3, t)
		var pan := lerpf(pan0, pan0 * .3, t) if approach else lerpf(pan0, side * .9, t * .6)
		plan.append({"at": FAKE_STEP_LEAD + i * gap, "pan": clampf(pan, -1.0, 1.0), "volume": fake_step_volume(distance)})
	return plan


func _begin_fake_footsteps(event: Dictionary) -> void:
	if not _fake_steps.is_empty():
		return   # one run at a time
	if event.has("peer_id") and peer_source.is_valid() and int(peer_source.call()) != int(event["peer_id"]):
		return   # meant for somebody else
	if event.has("target_depth") and depth_source.is_valid() and int(depth_source.call()) != int(event["target_depth"]):
		return   # another level: sound never bleeds vertically
	if player != null and player.spectator_mode:
		return
	var surface := String(event.get("surface", surface_source.call() if surface_source.is_valid() else ""))
	for step in fake_footstep_plan(event):
		_fake_steps.append({"left": float(step["at"]), "pan": float(step["pan"]), "volume": float(step["volume"]), "surface": surface})


func _tick_fake_footsteps(delta: float) -> void:
	for queued in _fake_steps:
		queued["left"] = float(queued["left"]) - delta
	while not _fake_steps.is_empty() and float(_fake_steps[0]["left"]) <= 0.0:
		var due: Dictionary = _fake_steps.pop_front()
		fake_steps_played += 1
		if sound_sink.is_valid():
			sound_sink.call(float(due["pan"]), float(due["volume"]), String(due["surface"]))
		else:
			Sound.hunter_footstep(float(due["pan"]), float(due["volume"]), String(due["surface"]))


func tick(delta: float) -> void:
	if hud != null:
		hud.tick_radar_state(delta)
	if not _fake_steps.is_empty():
		_tick_fake_footsteps(delta)
	if not route_active:
		return
	route_remaining -= delta
	if Input.is_action_just_pressed("interact"):
		route_nodes_left -= 1
		route_remaining = route_seconds
		Sound.signal_node(1.0 - float(route_nodes_left) / maxf(route_nodes, 1))
		if route_nodes_left <= 0:
			_finish(true)
			return
	if route_remaining <= 0.0:
		_finish(false)
		return
	_prompt()


func _prompt() -> void:
	hud.show_message("[ E ] SIGNAL ROUTE // %d LEFT // %.1fs" % [route_nodes_left, maxf(route_remaining, 0.0)])


func _finish(ok: bool) -> void:
	route_active = false
	if report_route.is_valid():
		report_route.call(ok)


## Host side: a route result from `peer_id` reaches the Gray gimmick that opened it.
static func host_route_result(views: Array, peer_id: int, ok: bool) -> void:
	for view in views:
		var hunter := view as HunterView3D
		if hunter == null or hunter.brain == null or not hunter.brain.gimmick is VoidGrayGimmick:
			continue
		var gimmick := hunter.brain.gimmick as VoidGrayGimmick
		if gimmick.route_active and gimmick.route_peer == peer_id:
			gimmick.route_result(hunter.brain, ok)
			hunter.sync_from_brain()
			return
