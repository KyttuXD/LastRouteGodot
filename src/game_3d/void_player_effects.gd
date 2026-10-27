class_name VoidPlayerEffects
extends RefCounted

## The player's side of the Void powers that act on the runner (Gray's signal route, Orange's system outages, Purple's radar static).
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
	return false


func tick(delta: float) -> void:
	hud.tick_radar_state(delta)
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
