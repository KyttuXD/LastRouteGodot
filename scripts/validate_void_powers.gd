extends RefCounted

## Gray (anti-idle signal route), Orange (system outages) and Purple (radar static / blackout): the Void powers ported from the 2D game
## (voids/gray.js, orange.js, purple.js). Drives each gimmick on a synthetic brain with the numbers the 2D game uses, checks the replicated
## state, then applies the events on a real player and HUD (flashlight forced off, climate/radar offline, radar overlay, the signal-route
## prompt counting E presses, the result reaching Gray on the host).
##
##   godot --headless --path . res://scenes/validate.tscn -- void_powers

const STEP := 1.0 / 20.0

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _brain(id: String, difficulty: String = "standard") -> HunterBrain:
	var brain := HunterBrain.new(Vector2(10, 10), "VOID-%s" % id, id, difficulty)
	brain.activate_at(Vector2(10, 10))
	return brain


func _target(at: Vector2 = Vector2(30, 30)) -> Dictionary:
	return {"peer_id": 1, "position": at, "hidden": false, "in_safe_zone": false, "facing": Vector2(0, 1)}


func _events(brain: HunterBrain, what: String) -> Array:
	return brain.world_events.filter(func(e): return String(e.get("what", "")) == what)


## Runs the gimmick for `seconds` with a still target; returns the first event named `what` (or {}).
func _run(brain: HunterBrain, gimmick: HunterGimmick, seconds: float, target: Dictionary, what: String) -> Dictionary:
	var t := 0.0
	while t < seconds:
		gimmick.before_perception(brain, STEP, target, null)
		gimmick.after_perception(brain, STEP, target, null)
		var found := _events(brain, what)
		if not found.is_empty():
			var event: Dictionary = found[0]
			event["at_time"] = t
			brain.world_events.clear()
			return event
		brain.world_events.clear()
		t += STEP
	return {}


func run(host: Node) -> int:
	var tree := host.get_tree()
	await tree.process_frame

	# ---- ids wire up
	for id in ["void_gray", "void_orange", "void_purple"]:
		_expect(HunterGimmick.for_id(id) != null, "%s has no gimmick class" % id)

	# ---- Gray: standard numbers
	var brain := _brain("void_gray")
	var gray := brain.gimmick as VoidGrayGimmick
	_expect(gray.hidden_from_view() and gray.holds_position() and gray.immune_to_capture(), "a dormant Gray is unseen, still and uncatchable")
	var early := _run(brain, gray, 178.0, _target(), "signal_route")
	_expect(early.is_empty(), "Gray must stay quiet through her 180 s grace window")
	var route := _run(brain, gray, 60.0, _target(), "signal_route")
	_expect(not route.is_empty(), "standing still after the grace window must open a signal route")
	# 180 s of grace + 45 s idle = the route opens 225 s after activation (178 s already run above)
	_expect(absf(float(route.get("at_time", 0.0)) - 47.0) < 1.5, "the route should open 45 s after the grace ends (opened at %.1f s into the second run)" % float(route.get("at_time", 0.0)))
	_expect(int(route["nodes"]) == 5 and absf(float(route["seconds"]) - 2.5) < .001, "five nodes, 2.5 s each")
	_expect(gray.route_active, "the route is open on the gimmick")
	_expect(gray.network_state()["route"] == true, "the route state is replicated")
	gray.route_result(brain, true)
	_expect(not gray.route_active and not gray.hunting and gray.dormant, "clearing the route keeps her dormant")
	_expect(not _events(brain, "message").is_empty() and String(_events(brain, "message")[0]["message"]) == "SIGNAL ROUTE CLEARED", "a cleared route says so")
	brain.world_events.clear()
	# failing it
	var second := _run(brain, gray, 60.0, _target(), "signal_route")
	_expect(not second.is_empty(), "she opens another route after another 45 s of idling")
	gray.route_result(brain, false)
	_expect(gray.hunting and not gray.dormant and brain.state == HunterBrain.State.CHASE, "a failed route starts her chase")
	_expect(not gray.hidden_from_view() and not gray.holds_position() and not gray.immune_to_capture(), "a hunting Gray is visible, moving and can grab")
	_expect(gray.network_state()["hunting"] == true, "the hunting state is replicated")
	var guest := VoidGrayGimmick.new()
	guest.apply_network_state(gray.network_state())
	_expect(guest.hunting and not guest.hidden_from_view(), "a guest sees Gray hunting")
	# the next relay resets her
	brain.relays_seen = 1
	gray.before_perception(brain, STEP, _target(), null)
	_expect(not gray.hunting and gray.dormant and gray.hidden_from_view(), "a collected relay puts her back to sleep")
	_expect(_events(brain, "message").any(func(e): return String(e["message"]) == "GRAY PRESSURE RESET // RELAY SECURED"), "the relay reset is announced")

	# ---- Gray: movement, hiding and safe rooms do not count as idle
	var busy := _brain("void_gray")
	var busy_gray := busy.gimmick as VoidGrayGimmick
	var walker := _target()
	var t := 0.0
	var opened := false
	while t < 400.0:
		walker["position"] = Vector2(30 + sin(t * .7) * 4.0, 30 + t * .1 - floorf(t * .1 / 20.0) * 20.0)
		busy_gray.before_perception(busy, STEP, walker, null)
		opened = opened or not _events(busy, "signal_route").is_empty()
		busy.world_events.clear()
		t += STEP
	_expect(not opened, "a runner who keeps moving never opens a route")
	for variant in ["hidden", "in_safe_zone"]:
		var calm := _brain("void_gray")
		var calm_target := _target()
		calm_target[variant] = true
		_expect(_run(calm, calm.gimmick, 300.0, calm_target, "signal_route").is_empty(), "%s is a legitimate reason to be still" % variant)

	# ---- Gray: Nightmare numbers, and the host watchdog
	var hard := _brain("void_gray", "nightmare")
	var hard_route := _run(hard, hard.gimmick, 160.0, _target(), "signal_route")
	_expect(not hard_route.is_empty() and absf(float(hard_route["at_time"]) - 150.0) < 1.5, "Nightmare: 120 s grace + 30 s idle (opened at %.1f)" % float(hard_route.get("at_time", 0.0)))
	_expect(absf(float(hard_route.get("seconds", 0.0)) - 1.8) < .001, "Nightmare: 1.8 s per node")
	var lost := _brain("void_gray")
	var lost_gray := lost.gimmick as VoidGrayGimmick
	_run(lost, lost_gray, 240.0, _target(), "signal_route")
	for i in int((5 * 2.5 + 3.5) / STEP):
		lost_gray.before_perception(lost, STEP, _target(), null)
	_expect(lost_gray.hunting, "a route whose result never arrives fails on the host's watchdog")

	# ---- Orange: every 26 s, one system, 9 s
	var orange_brain := _brain("void_orange")
	var orange := orange_brain.gimmick as VoidOrangeGimmick
	var seen := {}
	var gaps: Array = []
	var last := 0.0
	var clock := 0.0
	for i in int(2600.0 / STEP):
		orange.before_perception(orange_brain, STEP, _target(), null)
		clock += STEP
		for event in _events(orange_brain, "system_outage"):
			seen[String(event["system"])] = true
			gaps.append(clock - last)
			last = clock
			_expect(absf(float(event["seconds"]) - 9.0) < .001, "outages last 9 s")
			_expect(String(event["message"]).ends_with("OFFLINE // 9s"), "the outage toast reads '<SYSTEM> OFFLINE // 9s' (%s)" % event["message"])
		orange_brain.world_events.clear()
	_expect(seen.has("flashlight") and seen.has("climate") and seen.has("radar"), "Orange should take all three systems offline over time (%s)" % [seen.keys()])
	_expect(gaps.size() >= 90 and absf(float(gaps[3]) - 26.0) < .2, "an outage every 26 s (%d outages, gap %.2f)" % [gaps.size(), float(gaps[3]) if gaps.size() > 3 else -1.0])
	orange.apply_network_state({"outage": "radar"})
	_expect(orange.network_state()["outage"] == "radar", "the active outage is replicated")

	# ---- Purple: every 21 s, 35 % blackout (11 s) else static (8 s)
	var purple_brain := _brain("void_purple")
	var purple := purple_brain.gimmick as VoidPurpleGimmick
	var blackouts := 0
	var statics := 0
	var first_at := -1.0
	clock = 0.0
	for i in int(21.0 * 600.0 / STEP):
		purple.before_perception(purple_brain, STEP, _target(), null)
		clock += STEP
		for event in _events(purple_brain, "radar_corrupt"):
			if first_at < 0.0:
				first_at = clock
			if String(event["mode"]) == "blackout":
				blackouts += 1
				_expect(absf(float(event["seconds"]) - 11.0) < .001 and String(event["message"]) == "RADAR DEAD // REBOOTING", "blackout: 11 s, RADAR DEAD // REBOOTING")
			else:
				statics += 1
				_expect(absf(float(event["seconds"]) - 8.0) < .001 and String(event["message"]) == "RADAR CORRUPTED", "static: 8 s, RADAR CORRUPTED")
		purple_brain.world_events.clear()
	var share := float(blackouts) / maxf(blackouts + statics, 1)
	_expect(absf(first_at - 21.0) < .2, "the first corruption comes after 21 s (%.1f)" % first_at)
	_expect(blackouts + statics >= 595 and share > .29 and share < .41, "about 35 %% of corruptions black the radar out (%.2f of %d)" % [share, blackouts + statics])
	purple.apply_network_state({"radar": "static"})
	_expect(purple.network_state()["radar"] == "static", "the radar mode is replicated")

	# ---- the player's side, on a real scene
	var scene: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	await tree.process_frame
	await tree.process_frame
	var player: PlayerController3D = scene.player
	var hud: HUD = scene.hud
	var effects := VoidPlayerEffects.new(player, hud, func(_ok): pass)
	player.owns_inventory_item("flashlight")
	player.lamp_charge = 100.0
	player._set_flashlight(true)
	var had_light := player.flashlight_enabled
	_expect(effects.apply({"what": "system_outage", "system": "flashlight", "seconds": 9.0, "message": "FLASHLIGHT OFFLINE // 9s"}), "the outage event is handled")
	_expect(player.system_offline("flashlight") and not player.flashlight_enabled, "the flashlight is forced off%s" % ("" if had_light else " (it was off already)"))
	player._set_flashlight(true)
	_expect(not player.flashlight_enabled, "...and cannot be switched back on during the outage")
	effects.apply({"what": "system_outage", "system": "radar", "seconds": 9.0, "message": "RADAR OFFLINE // 9s"})
	_expect(hud.radar_mode == "offline" and hud._radar_fx.size() == 2 and (hud._radar_fx[0] as ColorRect).visible, "the radar overlay goes up over the minimap and the map")
	effects.apply({"what": "system_outage", "system": "climate", "seconds": 9.0, "message": "CLIMATE OFFLINE // 9s"})
	_expect(player.system_offline("climate") and not player.system_offline("flashlight"), "one system is offline at a time")
	effects.apply({"what": "radar_corrupt", "mode": "static", "seconds": 8.0, "message": "RADAR CORRUPTED"})
	_expect(hud.radar_mode == "static" and (hud._radar_fx[0] as ColorRect).visible, "static dusts the radar")
	effects.apply({"what": "radar_corrupt", "mode": "blackout", "seconds": 11.0, "message": "RADAR DEAD // REBOOTING"})
	_expect(hud.radar_mode == "blackout", "a blackout kills the radar")
	for i in int(12.0 / STEP):
		effects.tick(STEP)
	_expect(hud.radar_mode == "" and not (hud._radar_fx[0] as ColorRect).visible, "the radar comes back by itself")
	for i in int(10.0 / .016):
		player._physics_process(.016)
	_expect(not player.system_offline("climate") and player.outage_system == "", "an outage ends by itself after its 9 s")
	# the signal route: E presses against the per-node clock
	var results: Array = []
	var route_effects := VoidPlayerEffects.new(player, hud, func(ok): results.append(ok))
	route_effects.apply({"what": "signal_route", "nodes": 5, "seconds": 2.5})
	_expect(route_effects.route_active and route_effects.route_nodes_left == 5, "the route starts with five nodes")
	for i in int(2.6 / STEP):
		route_effects.tick(STEP)
	_expect(not route_effects.route_active and results == [false], "letting one node's clock run out fails the route (%s)" % [results])
	# the host feeds the report back to Gray
	var views: Array = []
	var gray_view := HunterView3D.new()
	gray_view.brain = _brain("void_gray")
	host.add_child(gray_view)
	views.append(gray_view)
	var gray_gimmick := gray_view.brain.gimmick as VoidGrayGimmick
	gray_gimmick.route_active = true
	gray_gimmick.route_peer = 1
	VoidPlayerEffects.host_route_result(views, 1, false)
	_expect(gray_gimmick.hunting, "the host turns a failed report into Gray's chase")
	gray_view.queue_free()
	scene.queue_free()
	await tree.process_frame

	if _failures == 0:
		print("  ok    void_powers: Gray's signal route, Orange's outages and Purple's radar static match the 2D numbers and reach the player")
	return _failures
