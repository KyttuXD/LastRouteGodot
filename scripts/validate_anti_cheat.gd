extends RefCounted

## Host anti-cheat for co-op guests (docs/ANTI_CHEAT.md): synthetic cheating guests get snapped back and kicked after
## GuestGuard.STRIKE_KICK strikes; legit fast moves (sprint with lag, ladders, plunges, stairs between floors,
## respawns, admins) never trigger. Also the per-guest interaction rate limit.
##
##   godot --headless --path . res://scenes/validate.tscn -- anti_cheat

const HZ := 20.0

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _state(at: Vector3, extra := {}) -> Dictionary:
	var state := {"at": at, "position": Vector2(at.x, at.z), "depth": 0, "lamp_charge": 80.0, "sprinting": false,
		"inventory_order": ["flashlight", ""]}
	state.merge(extra, true)
	return state


## Feeds `steps` samples moving `velocity` m/s; returns the first verdict that is not empty.
func _run(guard: GuestGuard, peer: int, from: Vector3, velocity: Vector3, steps: int, t0: float, extra := {},
		space: PhysicsDirectSpaceState3D = null, gap := 1.0 / HZ) -> Dictionary:
	for i in steps + 1:
		var verdict := guard.check(peer, _state(from + velocity * gap * i, extra), t0 + gap * i, space)
		if not verdict.is_empty():
			return verdict
	return {}


func run(host: Node) -> int:
	var sprint := GuestGuard.max_speed
	# Legit.
	var guard := GuestGuard.new()
	_expect(_run(guard, 2, Vector3.ZERO, Vector3(sprint, 0, 0), 60, 0.0, {"sprinting": true}).is_empty(),
		"a 3 s sprint was flagged")
	_expect(_run(guard, 3, Vector3.ZERO, Vector3(sprint, 0, 0), 4, 0.0, {}, null, 1.0).is_empty(),
		"a sprint over 1 s lag gaps was flagged")
	_expect(_run(guard, 4, Vector3.ZERO, Vector3(0, GameConfig.LADDER_CLIMB_SPEED, 0), 80, 0.0).is_empty(),
		"climbing a ladder was flagged")
	_expect(_run(guard, 5, Vector3(0, 30, 0), Vector3(0, -25, 0), 20, 0.0).is_empty(), "a plunge was flagged")
	guard.check(6, _state(Vector3.ZERO), 0.0)
	_expect(guard.check(6, _state(Vector3(40, -4, 3), {"depth": 1}), .05).is_empty(), "taking stairs down was flagged")
	guard.legit_spot = func(at: Vector3, _depth: int) -> bool: return at.distance_to(Vector3(100, 0, 0)) < 4.0
	guard.check(7, _state(Vector3.ZERO), 0.0)
	_expect(guard.check(7, _state(Vector3(100, 0, 1)), .05).is_empty(), "a respawn at the checkpoint was flagged")
	guard.exempt = func(peer: int) -> bool: return peer == 8
	_expect(_run(guard, 8, Vector3.ZERO, Vector3(80, 0, 0), 20, 0.0).is_empty(), "an admin's fast flight was flagged")
	guard.check(9, _state(Vector3.ZERO, {"lamp_charge": 20.0, "inventory_order": ["flashlight", "battery"]}), 0.0)
	_expect(guard.check(9, _state(Vector3.ZERO, {"lamp_charge": 100.0, "inventory_order": ["flashlight", ""]}),
		.05).is_empty(), "using a battery was flagged")
	_expect(_run(guard, 10, Vector3.ZERO, Vector3(sprint, 0, 0), 20, 0.0, {"spectating": true}).is_empty() \
		and guard.check(10, _state(Vector3(300, 0, 0), {"spectating": true}), 2.0).is_empty(), "a spectator was flagged")

	# Cheats.
	var cheats := {
		"speed": _run(guard, 20, Vector3.ZERO, Vector3(sprint * 2.5, 0, 0), 60, 0.0),
		"teleport": _run(guard, 21, Vector3.ZERO, Vector3(40.0 * HZ, 0, 0), 1, 0.0),
		"fly": _run(guard, 22, Vector3.ZERO, Vector3(0, 12, 0), 60, 0.0),
		"stamina": _run(guard, 23, Vector3.ZERO, Vector3(sprint, 0, 0), 200, 0.0, {"sprinting": true}),
		"lamp": _run(guard, 24, Vector3.ZERO, Vector3.ZERO, 2, 0.0, {"lamp_charge": 150.0}),
		"position": _run(guard, 25, Vector3.ZERO, Vector3.ZERO, 2, 0.0, {"position": Vector2(30, 30)}),
	}
	guard.check(26, _state(Vector3.ZERO, {"lamp_charge": 10.0}), 0.0)
	cheats["lamp_refill"] = guard.check(26, _state(Vector3.ZERO, {"lamp_charge": 90.0}), .05)
	for reason in cheats:
		var verdict: Dictionary = cheats[reason]
		_expect(String(verdict.get("reason", "")) == String(reason).trim_suffix("_refill"),
			"%s cheat gave %s" % [reason, verdict])
	_expect((cheats["teleport"] as Dictionary).get("snap_to") == Vector3.ZERO, "the teleporter was not snapped back")

	# Strikes: repeated cheating kicks; a clean run decays strikes.
	var kicked := false
	var t := 10.0
	for i in GuestGuard.STRIKE_KICK:
		guard.check(30, _state(Vector3.ZERO), t)
		var verdict := guard.check(30, _state(Vector3(50, 0, 0)), t + .05)
		kicked = bool(verdict.get("kick", false))
		_expect(kicked == (i == GuestGuard.STRIKE_KICK - 1), "strike %d kick=%s" % [i + 1, kicked])
		t += .1
	guard.check(31, _state(Vector3.ZERO), 0.0)
	guard.check(31, _state(Vector3(50, 0, 0)), .05)
	_run(guard, 31, Vector3.ZERO, Vector3.ZERO, int(GuestGuard.STRIKE_DECAY_SECONDS * 2.0), .1, {}, null, 1.0)
	_expect(guard.strikes(31) == 0, "strikes did not decay (%d)" % guard.strikes(31))

	# No-clip: a wall between two samples, and a door that must not count.
	var root := Node3D.new()
	host.get_tree().root.add_child(root)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.2, 3, 6)
	shape.shape = box
	wall.add_child(shape)
	root.add_child(wall)
	wall.global_position = Vector3(1, 1.5, 0)
	var door := RouteInteractable3D.new()
	var door_body := StaticBody3D.new()
	var door_shape := CollisionShape3D.new()
	door_shape.shape = box
	door_body.add_child(door_shape)
	door.add_child(door_body)
	root.add_child(door)
	door_body.global_position = Vector3(1, 1.5, 20)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	var space := root.get_world_3d().direct_space_state
	var through := _run(guard, 40, Vector3(0, 0, 0), Vector3(4, 0, 0), 10, 0.0, {}, space)
	_expect(String(through.get("reason", "")) == "noclip", "walking through a wall gave %s" % through)
	_expect(_run(guard, 41, Vector3(0, 0, 20), Vector3(4, 0, 0), 10, 0.0, {}, space).is_empty(),
		"walking through a (lagging) door was flagged")
	_expect(_run(guard, 42, Vector3(0, 0, 5), Vector3(4, 0, 0), 10, 0.0, {}, space).is_empty(),
		"walking past the wall's end was flagged")
	root.queue_free()

	_lag_checks()

	# Host-caused moves (vent transit, pulled out of hiding, axe rescue, revive) never strike.
	guard.check(60, _state(Vector3.ZERO), 0.0)
	guard.allow_jump(60, .02)
	_expect(guard.check(60, _state(Vector3(30, 0, 0)), .05).is_empty(), "a host-approved vent jump was flagged")
	_expect(not guard.check(60, _state(Vector3(110, 0, 0)), 4.0).is_empty(), "the jump allowance never ran out")

	# Troll mode: hunters take only the trolled guest, hiding or not, and leave the teammate alone.
	var troll_remotes := RemotePlayers.new()
	var now := Time.get_ticks_usec()
	troll_remotes._states = {
		70: {"peer_id": 70, "position": Vector2(40, 0), "depth": 0, "hidden": true, "received_usec": now},
		71: {"peer_id": 71, "position": Vector2(2, 0), "depth": 0, "received_usec": now}}
	var plain := troll_remotes.best_target(Vector2.ZERO, {"peer_id": 1, "position": Vector2(90, 0), "depth": 0}, 0)
	_expect(int(plain.get("peer_id", 0)) == 71, "without troll mode the nearest visible runner is not chosen (%s)" % plain)
	troll_remotes.troll_peers[70] = true
	var picked := troll_remotes.best_target(Vector2.ZERO, {"peer_id": 1, "position": Vector2(1, 0), "depth": 0}, 0)
	_expect(int(picked.get("peer_id", 0)) == 70 and not bool(picked.get("hidden", true)) \
		and bool(picked.get("troll", false)), "a hidden trolled guest was not the hunters' target (%s)" % picked)
	troll_remotes.free()
	var brain := HunterBrain.new(Vector2.ZERO, "TROLL", HunterRoster.DEFAULT_ID, "standard")
	var normal_speed := brain._current_speed(0, 0)
	brain.troll_target = true
	_expect(brain._current_speed(0, 0) > normal_speed * 1.1, "hunters are not faster toward a trolled guest")
	var controller := PlayerController3D.new()
	controller.admin_god_mode = false
	controller._update_stamina(1.0, true)
	var normal_drain := GameConfig.MAX_STAMINA - controller.stamina
	controller.stamina = GameConfig.MAX_STAMINA
	controller.troll_active = true
	controller._update_stamina(1.0, true)
	_expect(GameConfig.MAX_STAMINA - controller.stamina > normal_drain * 1.4, "stamina does not drain faster when trolled")
	controller._update_troll(10.0)
	_expect(controller._troll_step_in > 0.0, "no fake hunter footstep was scheduled")
	controller.free()
	var scare := HunterJumpscare.new()
	scare.duration_scale = GameConfig.TROLL_SCARE_SCALE
	_expect(scare.duration_scale >= 2.0, "the trolled scare is not longer")
	scare.free()

	# Client messages: a server status or a FLAGGED refusal reaches the player as an account message.
	var heard := [""]
	var listener := func(_signed: bool, _name: String, _admin: bool, message: String) -> void: heard[0] = message
	Backend.account_changed.connect(listener)
	Backend.moderation._on_status_reply({"status": {"flagged": true,
		"message": "PUBLIC ROUTE AND SKIN UPLOADS LOCKED UNTIL 12:00"}})
	_expect(String(heard[0]).begins_with("PUBLIC ROUTE"), "the restriction message did not reach the player")
	_expect(Backend.moderation.restriction_message() == String(heard[0]), "restriction_message() is stale")
	Backend.account_changed.disconnect(listener)
	Backend.moderation._on_status_reply({"status": {}})
	_expect(Backend.moderation.device_id().length() == 32, "the device id is not a 32-hex id")

	await _troll_ad_checks(host)

	# Interaction rate limit.
	var remotes := RemotePlayers.new()
	var allowed := 0
	for i in 30:
		if remotes._interaction_allowed(50):
			allowed += 1
	_expect(allowed == RemotePlayers.INTERACTION_RATE_MAX, "%d of 30 instant interactions allowed" % allowed)
	remotes.free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  anti_cheat  ok")
	return _failures


## A legit runner: sprints 2.5 s, walks 1 s, turning, at 20 Hz for `seconds`. Each sample is [send_time, state].
func _legit_run(seconds: float, cheat := "") -> Array:
	var out := []
	var at := Vector3.ZERO
	var heading := 0.0
	var walk := GameConfig.PLAYER_WALK_SPEED / GameConfig.TILE_SIZE
	var seq := 0
	var t := 0.0
	while t < seconds:
		var sprinting := fmod(t, 3.5) < 2.5
		var speed := GuestGuard.max_speed if sprinting else walk
		if cheat == "speed":
			speed *= 2.5
		heading += .04
		at += Vector3(cos(heading), 0, sin(heading)) * speed / HZ
		var state := _state(at, {"sprinting": sprinting, "seq": seq})
		if cheat == "teleport" and seq == int(seconds * HZ * .5):
			at += Vector3(60, 0, 0)
			state = _state(at, {"seq": seq})
		out.append([t, state])
		seq += 1
		t += 1.0 / HZ
	return out


## Delivers `samples` over a simulated link and returns {strikes, snaps, lag_snaps}.
func _deliver(samples: Array, rtt_ms: float, jitter_ms: float, loss: float, freezes: Array, duplicate := .0,
		rng_seed := 1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var arrivals := []
	for sample in samples:
		if rng.randf() < loss:
			continue
		var arrive := float(sample[0]) + rtt_ms / 2000.0 + rng.randf_range(0.0, jitter_ms / 1000.0)
		for freeze in freezes:   # [start, length]: nothing arrives until the freeze ends
			if arrive >= float(freeze[0]) and arrive < float(freeze[0]) + float(freeze[1]):
				arrive = float(freeze[0]) + float(freeze[1]) + rng.randf_range(0.0, .05)
		arrivals.append([arrive, sample[1]])
		if rng.randf() < duplicate:
			arrivals.append([arrive + rng.randf_range(0.0, .2), sample[1]])
	arrivals.sort_custom(func(x, y) -> bool: return float(x[0]) < float(y[0]))
	var guard := GuestGuard.new()
	guard.rtt_ms = func(_peer: int) -> float: return rtt_ms
	var result := {"strikes": 0, "snaps": 0, "lag_snaps": 0}
	for arrival in arrivals:
		var verdict := guard.check(1, arrival[1], float(arrival[0]))
		if verdict.is_empty() or bool(verdict.get("drop", false)):
			continue
		result["snaps"] += 1
		if bool(verdict.get("lag", false)):
			result["lag_snaps"] += 1
	result["strikes"] = guard.strikes(1)
	return result


func _lag_checks() -> void:
	var run := _legit_run(40.0)
	var links := {
		"300 ms": [300.0, 40.0, .0, []],
		"800 ms": [800.0, 150.0, .02, []],
		"2000 ms": [2000.0, 400.0, .05, []],
		"jitter 250 ms": [120.0, 250.0, .0, []],
		"10 % loss": [150.0, 60.0, .1, []],
		"3 s freeze": [150.0, 40.0, .0, [[8.0, 3.0]]],
		"10 s freeze": [150.0, 40.0, .0, [[12.0, 10.0]]],
		"freezes + loss + reorder": [300.0, 300.0, .08, [[5.0, 4.0], [20.0, 6.0]]],
	}
	for name in links:
		var link: Array = links[name]
		var legit := _deliver(run, link[0], link[1], link[2], link[3], .05)
		_expect(int(legit["strikes"]) == 0, "legit movement over %s got %d strikes (%s)" % [name, legit["strikes"], legit])
	for name in ["300 ms", "800 ms", "2000 ms", "3 s freeze"]:
		var link: Array = links[name]
		for cheat in ["speed", "teleport"]:
			var caught := _deliver(_legit_run(20.0, cheat), link[0], link[1], link[2], link[3])
			_expect(int(caught["snaps"]) > 0, "a %s cheat over %s was never snapped back" % [cheat, name])
	var mild := _deliver(_legit_run(20.0, "speed"), 300.0, 40.0, .0, [])
	_expect(int(mild["strikes"]) > 0, "a speed cheat over 300 ms got no strikes (%s)" % mild)
	var heavy := _deliver(_legit_run(20.0, "speed"), 2000.0, 400.0, .0, [])
	_expect(int(heavy["strikes"]) == 0 and int(heavy["lag_snaps"]) > 0,
		"heavy lag snaps were not tagged lag (%s)" % heavy)
	# Duplicates and out-of-order samples are dropped, never judged.
	var guard := GuestGuard.new()
	guard.check(1, _state(Vector3.ZERO, {"seq": 5}), 0.0)
	guard.check(1, _state(Vector3(.3, 0, 0), {"seq": 6}), .05)
	_expect(bool(guard.check(1, _state(Vector3(50, 0, 0), {"seq": 6}), .06).get("drop", false)), "a duplicate was judged")
	_expect(bool(guard.check(1, _state(Vector3(50, 0, 0), {"seq": 3}), .07).get("drop", false)), "a stale sample was judged")
	_expect(guard.strikes(1) == 0, "dropped samples struck")


## Troll-mode "ads": in-universe text only, capped, never for normal players, never over a capture or death screen.
func _troll_ad_checks(host: Node) -> void:
	var ads: Array = TrollAds.all()
	_expect(ads.size() >= 20, "only %d troll ads in the data" % ads.size())
	for ad_value in ads:
		var ad := TrollAds.render(ad_value)
		var text := ("%s %s %s" % [ad["title"], ad["body"], ad["footer"]]).to_lower()
		for banned in ["http", "www.", ".com", "$", "€", "£", "{"]:
			_expect(not text.contains(banned), "ad %s has '%s' (real links/prices/placeholders are not allowed)" % [ad["id"], banned])
		_expect(String(ad["source"]) in ["mall", "company", "safety", "hunter", "lore"], "ad %s has source %s" % [ad["id"], ad["source"]])
	# The schedule: first delay, minimum gap, cap per window, nothing while blocked or off.
	var schedule := TrollAds.new(7)
	_expect(not schedule.due(100.0, false), "ads were due before troll ads turned on")
	schedule.set_enabled(true, 0.0)
	_expect(not schedule.due(TrollAds.FIRST_DELAY_SECONDS - 1.0, false), "the first ad did not wait")
	var shown: Array[float] = []
	var t := 0.0
	while t < 1800.0:
		if schedule.due(t, fmod(t, 97.0) < 20.0):   # blocked a fifth of the time (caught / menus)
			_expect(fmod(t, 97.0) >= 20.0, "an ad was due while blocked")
			schedule.mark_shown(t)
			shown.append(t)
		t += 1.0
	for i in shown.size():
		if i > 0:
			_expect(shown[i] - shown[i - 1] >= TrollAds.MIN_GAP_SECONDS, "two ads %.0f s apart" % (shown[i] - shown[i - 1]))
		var in_window := shown.filter(func(at: float) -> bool: return at <= shown[i] and shown[i] - at < TrollAds.WINDOW_SECONDS).size()
		_expect(in_window <= TrollAds.MAX_PER_WINDOW, "%d ads within one window" % in_window)
	_expect(shown.size() > 0, "no ad ever showed for a trolled player")
	schedule.set_enabled(false, 0.0)
	_expect(not schedule.due(5000.0, false), "ads still due after troll ads turned off")

	# Settings: OFF by default; the gentle profile is rarer, skips at once and its Skip never moves.
	var fresh: Node = (load("res://src/autoload/settings.gd") as GDScript).new()
	_expect(String(fresh.ads_mode) == "off", "in-world ads are not OFF by default")
	fresh.free()
	var gentle: Dictionary = TrollAds.PROFILES["gentle"]
	var annoying: Dictionary = TrollAds.PROFILES["annoying"]
	_expect(float(gentle["gap"]) > float(annoying["gap"]) and int(gentle["max"]) < int(annoying["max"]) \
		and float(gentle["countdown"]) == 0.0 and int(gentle["dodges"]) == 0, "the gentle profile is not gentle")

	# The live route.
	var saved_mode := Settings.ads_mode
	Settings.ads_mode = "off"
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 3:
		await host.get_tree().process_frame
	var force_due := func() -> void:
		route._apply_ads_mode()
		route.troll_ads._enabled_at -= 1000.0
		route.troll_ads._shown_at.clear()
		route._update_troll_ads(1.0)
	var showing := func() -> bool: return route.troll_ad_overlay != null and route.troll_ad_overlay.showing()
	force_due.call()
	_expect(not showing.call(), "a player with ads OFF (the default) saw an ad")
	# GENTLE: a pop-up with a plain Skip that works straight away.
	Settings.ads_mode = "gentle"
	force_due.call()
	_expect(route.ads_mode() == "gentle" and showing.call(), "an opted-in GENTLE player got no ad")
	if showing.call():
		var skip: Button = route.troll_ad_overlay._skip
		_expect(not skip.disabled and skip.text == "SKIP", "the gentle Skip is not a plain, working Skip")
		var index := skip.get_index()
		route.troll_ad_overlay._on_skip()
		_expect(not showing.call() and skip.get_index() == index, "the gentle Skip moved or did not close the ad")
	# Never during a chase or in VR, in any mode.
	for blocker in ["chase", "vr"]:
		for mode in ["gentle", "annoying"]:
			Settings.ads_mode = mode
			route._was_chased = blocker == "chase"
			route.player.xr_active = blocker == "vr"
			force_due.call()
			_expect(not showing.call(), "a %s ad opened during %s" % [mode, blocker])
			route._was_chased = false
			route.player.xr_active = false
			if route.troll_ad_overlay != null:
				route.troll_ad_overlay.dismiss()
	# ANNOYING by choice: the countdown and the sneaky skip.
	Settings.ads_mode = "annoying"
	force_due.call()
	_expect(showing.call() and (route.troll_ad_overlay._skip as Button).disabled, "ANNOYING has no countdown")
	route.troll_ad_overlay.dismiss()
	# Troll mode forces ANNOYING whatever the setting; an owner's ads-off mutes it.
	Settings.ads_mode = "off"
	route._apply_player_event({"what": "troll", "on": true, "ads": false})
	force_due.call()
	_expect(not showing.call(), "ads showed with the owner's ads toggle off")
	route._apply_player_event({"what": "troll", "on": true, "ads": true})
	Settings.ads_mode = "gentle"
	force_due.call()
	_expect(route.ads_mode() == "annoying" and showing.call(), "troll mode did not force ANNOYING ads (got %s)" % route.ads_mode())
	_expect(showing.call() and route.troll_ad_overlay.remaining > 0.0 \
		and (route.troll_ad_overlay._skip as Button).disabled, "the troll ad can be skipped before its countdown")
	route._death_screen_open = true
	route._update_troll_ads(1.0)
	_expect(not showing.call(), "an ad stayed over the death screen")
	force_due.call()
	_expect(not showing.call(), "an ad opened over the death screen")
	route._death_screen_open = false
	Settings.ads_mode = "off"
	route._apply_player_event({"what": "troll", "on": false})
	route._update_troll_ads(1.0)
	_expect(not showing.call() and not route.troll_ads.enabled(), "ads kept running after troll mode ended")
	Settings.ads_mode = saved_mode
	route.queue_free()
	await host.get_tree().process_frame
