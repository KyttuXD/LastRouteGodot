extends RefCounted

## Normal / Hard / Nightmare hunter abilities (HardAbilities): the roster per mode, the pounce (no wind-up, range, line, links, cooldown, stumble, bonk,
## rarity per mode), the sprint burst and intercept after losing sight, the door slam, the party budget, the room switch and replication.
## Drives real HunterBrains with a small stub navigation surface.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- hard_abilities

const STEP := 1.0 / 30.0

var _failures := 0


class Field:
	var line_clear := true
	var wall_from_x := INF          # can_occupy is false from this x on
	var safe_zones: Array = []
	var rooms: Array = []
	var relays: Array = []
	var vents: Array = []
	var hiding_spots: Array = []

	func has_line_of_sight(_from: Vector2, _to: Vector2) -> bool:
		return line_clear

	func can_occupy(x: float, _y: float, _radius: float = .23, _blocked_cells = null) -> bool:
		return x < wall_from_x

	func nearest_open_position(x: float, y: float, _radius: float = 1.0, _blocked = null) -> Dictionary:
		return {"x": x, "y": y}

	func room_at(_x: float, _y: float) -> Dictionary:
		return {}

	func find_path(from: Vector2i, to: Vector2i) -> Array:
		var result := [from]
		var cursor := from
		while cursor.x != to.x:
			cursor.x += 1 if to.x > cursor.x else -1
			result.append(cursor)
		return result


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _brain(id: String, difficulty: String, at: Vector2 = Vector2(10, 10), salt: int = 0) -> HunterBrain:
	var brain := HunterBrain.new(at, "HARD-%s-%s-%d" % [id, difficulty, salt], id, difficulty)
	brain.activate_at(at)
	return brain


func _target(at: Vector2, extra: Dictionary = {}) -> Dictionary:
	var target := {"peer_id": 1, "position": at, "hidden": false, "in_safe_zone": false, "noise": 6.0, "flashlight_on": true,
		"facing": Vector2(1, 0), "meters": null}
	target.merge(extra, true)
	return target


## Steps one brain against a stationary runner; returns true on the frame a pounce launches.
func _step(brain: HunterBrain, field: Field, target: Dictionary) -> bool:
	var before: int = brain.hard.leap_seq if brain.hard != null else 0
	brain.update(STEP, field, target, 1, 0)
	return brain.hard != null and brain.hard.leap_seq != before


func _chase(brain: HunterBrain) -> void:
	brain.state = HunterBrain.State.CHASE
	brain.direct_chase_visible = true


func run(host: Node) -> int:
	await host.get_tree().process_frame
	HardAbilities.reset_director()
	HardAbilities.enabled = true

	# ---- who has what, in which mode
	for ability in HardAbilities.ROSTER:
		for hunter in HardAbilities.ROSTER[ability]["nightmare"]:
			_expect(HunterRoster.PROFILES.has(hunter), "%s lists %s who is not in the roster" % [ability, hunter])
	for id in ["haelith", "elise", "dovelle", "kathy", "void_red"]:
		_expect(_brain(id, "relaxed").hard == null, "%s: Relaxed gets no abilities" % id)
	for id in [0, 1, 2, 3]:
		_expect(not String(RoomState.DIFFICULTY_BLURBS.get(id, "")).is_empty(), "difficulty %d has a menu blurb" % id)
		var blurb := String(RoomState.DIFFICULTY_BLURBS.get(id, "")).to_lower()
		for word in ["pounce", "burst", "flank", "ambush", "slam", "torch", "abilit"]:
			_expect(not word in blurb, "difficulty %d blurb names no hunter ability (%s): players discover them in-game" % [id, word])
	_expect(not "hunter_abilities" in RoomState, "no separate room switch for hunter abilities")
	_expect(_brain("dovelle", "hard").hard == null, "a hunter without an ability has no component")
	_expect(_brain("haelith", "standard").hard != null and _brain("haelith", "hard").hard != null and _brain("haelith", "nightmare").hard != null, "Haelith has the pounce on Normal, Hard and Nightmare")
	_expect(_brain("solyth", "standard").hard == null and _brain("solyth", "hard").hard != null, "Solyth's pounce starts on Hard")
	_expect(not _brain("nyxie", "hard").hard.has("pounce") if _brain("nyxie", "hard").hard != null else true, "Nyxie's pounce is Nightmare only")
	_expect(_brain("nyxie", "nightmare").hard != null and _brain("nyxie", "nightmare").hard.has("pounce"), "Nyxie pounces on Nightmare")

	# ---- the pounce, Hard
	HardAbilities.clock_override = 1000.0
	var brain := _brain("void_red", "hard")
	var field := Field.new()
	var target := _target(Vector2(13.5, 10))
	_chase(brain)
	var launched_at := -1.0
	var distance_at_launch := 0.0
	for i in 600:
		HardAbilities.clock_override = 1000.0 + i * STEP
		_chase(brain)
		brain.position = Vector2(10, 10)       # hold her at range: the test is about the roll, not the approach
		if _step(brain, field, target):
			launched_at = i * STEP
			distance_at_launch = brain.position.distance_to(target["position"])
			break
	_expect(launched_at >= 0.0, "a Hard Red in range with a clear line must pounce within 20 s")
	_expect(distance_at_launch >= 2.1 and distance_at_launch <= 4.6, "she launches from %.2f cells (2.2 to 4.5)" % distance_at_launch)
	_expect(brain.hard.leaping, "the leap is on")
	var start := brain.position
	var left_ground := 0
	var peak_speed := 0.0
	var caught := false
	for i in 40:
		HardAbilities.clock_override += STEP
		var before := brain.position
		if brain.update(STEP, field, target, 1, 0):
			caught = true
		peak_speed = maxf(peak_speed, before.distance_to(brain.position) / STEP)
		if not brain.hard.leaping:
			break
	_expect(peak_speed > 6.0 and peak_speed < 8.5, "the leap moves at about 7.2 m/s (%.1f)" % peak_speed)
	_expect(not brain.hard.leaping and brain.hard.stumble_left > 0.9, "after the leap she stumbles (%.2f s)" % brain.hard.stumble_left)
	_expect(start.distance_to(brain.position) > 1.5, "the leap covers real ground (%.1f cells)" % start.distance_to(brain.position))
	# a stumbling hunter cannot catch even when the runner is on top of her
	var on_top := _target(brain.position + Vector2(.1, 0))
	_expect(not brain.update(STEP, field, on_top, 1, 0), "no catch while she stumbles")
	_expect(brain.hard.speed_scale() < .35, "a stumbling hunter is slow (%.2f)" % brain.hard.speed_scale())
	# cooldown: no second pounce for 28 s of continuous eligibility
	var second := false
	var chase_target := _target(brain.position + Vector2(3.0, 0))
	var t0 := HardAbilities.clock_override
	for i in int(25.0 / STEP):
		HardAbilities.clock_override = t0 + i * STEP
		_chase(brain)
		chase_target["position"] = brain.position + Vector2(3.0, 0)
		if _step(brain, field, chase_target):
			second = true
	_expect(not second, "the 28 s cooldown holds on Hard")

	# ---- no pounce without a clear line, with a hidden runner, near a link, or with the room switch off
	for case in ["wall", "hidden", "link", "switch", "safe", "vent"]:
		HardAbilities.reset_director()
		var b := _brain("void_red", "nightmare")
		var f := Field.new()
		var tg := _target(Vector2(13.0, 10))
		match case:
			"wall":
				f.wall_from_x = 11.5
			"hidden":
				tg["hidden"] = true
			"link":
				b.near_link = func(_p: Vector2, _r: float) -> bool: return true
			"switch":
				HardAbilities.enabled = false
			"safe":
				tg["in_safe_zone"] = true
			"vent":
				tg["in_vent"] = true
		var fired := false
		for i in 900:
			HardAbilities.clock_override = 5000.0 + i * STEP
			_chase(b)
			if _step(b, f, tg):
				fired = true
				break
		HardAbilities.enabled = true
		_expect(not fired, "no pounce in the '%s' case" % case)

	# ---- bonk: the leap runs into something and she is stunned for a moment
	HardAbilities.reset_director()
	var bonk := _brain("void_red", "nightmare")
	var bonk_field := Field.new()
	var bonk_target := _target(Vector2(13.0, 10))
	for i in 900:
		HardAbilities.clock_override = 9000.0 + i * STEP
		_chase(bonk)
		bonk.position = Vector2(10, 10)
		if _step(bonk, bonk_field, bonk_target):
			break
	_expect(bonk.hard.leaping, "setup: the Nightmare Red launched")
	bonk_field.wall_from_x = bonk.position.x + .05
	bonk.update(STEP, bonk_field, bonk_target, 1, 0)
	_expect(not bonk.hard.leaping and bonk.stun_timer >= .7, "a leap into a wall ends in a short stun (%.2f)" % bonk.stun_timer)

	# ---- rarity per mode: pounces over a long chase-heavy hour
	var counts := {}
	for mode_name in ["standard", "hard", "nightmare"]:
		HardAbilities.reset_director()
		var runner := _brain("void_red", mode_name)
		var runner_field := Field.new()
		var count := 0
		var elapsed := 0.0
		while elapsed < 3600.0:
			HardAbilities.clock_override = 20000.0 + elapsed
			_chase(runner)
			runner.stun_timer = 0.0
			runner.position = Vector2(10, 10)
			var tg := _target(Vector2(13.0, 10))
			var seq_before: int = runner.hard.leap_seq
			runner.update(STEP * 6.0, runner_field, tg, 1, 0)      # one sample stands for six frames of eligible time
			if runner.hard.leap_seq != seq_before:
				count += 1
				runner.hard.cancel()
				runner.hard.stumble_left = 0.0
				runner.hard._pounces_this_chase = 0      # (each sample is a fresh chase)
				runner.position = Vector2(10, 10)
			elapsed += STEP * 6.0     # sparse sampling: every 6th frame counts as eligible time
		counts[mode_name] = count
	_expect(counts["standard"] < counts["hard"] and counts["hard"] < counts["nightmare"], "pounces per hour rise Normal < Hard < Nightmare (%s)" % [counts])
	_expect(counts["standard"] <= 12, "Normal is very rare: at most one per budget window (%d in an hour)" % counts["standard"])
	_expect(counts["standard"] >= 1, "...but it does happen over a long run (%d)" % counts["standard"])

	# ---- burst and intercept after losing sight
	HardAbilities.reset_director()
	var bursts := 0
	var intercepts := 0
	for trial in 20:
		HardAbilities.clock_override = 40000.0 + trial * 100.0
		var q := _brain("quenelle", "hard", Vector2(10, 10), trial)
		var qf := Field.new()
		var moving := _target(Vector2(14, 10))
		_chase(q)
		for i in 5:
			q.update(STEP, qf, moving, 1, 0)
			moving["position"] += Vector2(5.0 * STEP, 0)
			_chase(q)
		qf.line_clear = false
		q.direct_chase_visible = false
		q.update(STEP, qf, moving, 1, 0)
		if q.hard.burst_left > 0.0:
			bursts += 1
			_expect(absf(q.hard.speed_scale() - 1.25) < .001, "the Hard burst is +25%")
	_expect(bursts > 4 and bursts < 20, "Hard Quenelle bursts on most sight losses (%d / 20)" % bursts)
	HardAbilities.reset_director()
	HardAbilities.clock_override = 50000.0
	var m := _brain("mavrine", "nightmare", Vector2(10, 10))
	var mf := Field.new()
	var run_target := _target(Vector2(14, 10))
	_chase(m)
	for i in 8:
		m.update(STEP, mf, run_target, 1, 0)
		run_target["position"] += Vector2(5.0 * STEP, 0)
		_chase(m)
	var seen_at: Vector2 = run_target["position"]
	m.last_known = seen_at
	m.direct_chase_visible = false
	mf.line_clear = false
	m.update(STEP, mf, run_target, 1, 0)
	_expect(m.last_known.x > seen_at.x + 4.0, "Nightmare Mavrine aims ahead of the runner (%.1f cells past the last sighting)" % (m.last_known.x - seen_at.x))

	# ---- the door slam and the party budget
	HardAbilities.reset_director()
	HardAbilities.clock_override = 60000.0
	var e := _brain("elise", "hard")
	_chase(e)
	_expect(is_equal_approx(e.hard.door_slam_seconds(e), 20.0), "Hard: a slammed door stays open 20 s")
	_expect(e.hard.door_slam_seconds(e) == 0.0, "the budget stops a second slam at once")
	HardAbilities.clock_override += 46.0
	_expect(is_equal_approx(e.hard.door_slam_seconds(e), 20.0), "...until the Hard window (45 s) has passed")
	var en := _brain("elise", "nightmare")
	_chase(en)
	HardAbilities.clock_override += 100.0
	_expect(is_equal_approx(en.hard.door_slam_seconds(en), 35.0), "Nightmare: 35 s")
	var normal_slams := 0
	for trial in 400:
		HardAbilities.reset_director()
		var en2 := _brain("elise", "standard", Vector2(10, 10), trial)
		_chase(en2)
		if en2.hard.door_slam_seconds(en2) > 0.0:
			normal_slams += 1
	_expect(normal_slams > 10 and normal_slams < 90, "Normal slams about 10%% of the doors (%d / 400)" % normal_slams)
	_expect(_brain("javelle", "relaxed").hard == null, "Relaxed never slams")

	# ---- replication
	var leaper := _brain("void_red", "hard")
	leaper.hard.leaping = true
	leaper.hard.leap_dir = Vector2(1, 0)
	leaper.hard.leap_seq = 7
	leaper.hard.stumble_left = .7
	var guest := _brain("void_red", "hard")
	guest.hard.apply_network_state(leaper.hard.network_state())
	_expect(guest.hard.leaping and guest.hard.leap_seq == 7 and guest.hard.leap_dir == Vector2(1, 0) and guest.hard.stumble_left > .65, "a guest receives the leap state")

	# ---- the view: the leap plays the charge clip and makes exactly one footfall
	var view := HunterView3D.new()
	view.brain = _brain("void_red", "hard")
	host.add_child(view)
	var camera := Camera3D.new()
	camera.position = Vector3(10, 1.5, 12)
	host.add_child(camera)
	camera.current = true
	await host.get_tree().process_frame
	view.sync_from_brain()
	var footfalls := int(Sound.play_counts.get("hunter_footstep", 0))
	view.brain.hard.leaping = true
	view.brain.hard.leap_seq += 1
	for i in 6:
		await host.get_tree().process_frame
		view.sync_from_brain()
	_expect(view._animation_player.assigned_animation == "charge", "the pounce plays the charge clip (%s)" % view._animation_player.assigned_animation)
	_expect(int(Sound.play_counts.get("hunter_footstep", 0)) == footfalls + 1, "one footfall as she launches and no other cue (%d)" % (int(Sound.play_counts.get("hunter_footstep", 0)) - footfalls))
	view.queue_free()
	camera.queue_free()
	HardAbilities.reset_director()

	# ---- the tweak table (step 2): every key present, ordered by mode, Relaxed unchanged in kind
	var order := ["relaxed", "standard", "hard", "nightmare"]
	for key in ["hunter_sight", "hunter_hearing", "hide_random", "relay_alert_radius", "relay_alert_chance"]:
		for i in range(1, order.size()):
			_expect(GameConfig.profile_value(order[i], key) >= GameConfig.profile_value(order[i - 1], key), "%s rises with the mode (%s)" % [key, order[i]])
	for key in ["search_time", "lost_sight_grace", "hide_trail"]:
		for i in range(1, order.size()):
			_expect(GameConfig.profile_value(order[i], key) >= GameConfig.profile_value(order[i - 1], key), "%s rises with the mode (%s)" % [key, order[i]])
	for key in ["stamina_drain", "hide_tell", "hide_cooldown", "taser_stun", "escape_stun", "crowbar_stun", "axe_stun", "spawn_distance", "emote_chase_scale", "emote_spot_p"]:
		for i in range(1, order.size()):
			_expect(GameConfig.profile_value(order[i], key) <= GameConfig.profile_value(order[i - 1], key), "%s falls with the mode (%s)" % [key, order[i]])
	_expect(GameConfig.ESCAPE_PRESSES == 6, "the escape presses stay at 6 (%d)" % GameConfig.ESCAPE_PRESSES)
	_expect(GameConfig.profile_value("relaxed", "hide_random") == 0.0 and GameConfig.profile_value("standard", "hide_random") > 0.0, "random hide checks: none on Relaxed, a few on Normal")
	_expect(_brain("kathy", "nightmare").difficulty_profile["search_time"] == 5.0 and float(_brain("kathy", "standard").difficulty_profile["search_time"]) < 4.0, "the brain reads its mode's search time")
	var seeker := _brain("kathy", "nightmare")
	var seek_field := Field.new()
	seek_field.hiding_spots = [{"id": "hide-0", "x": 14, "y": 10, "room_id": ""}]
	seeker.last_known = Vector2(13.5, 10.5)
	seeker.has_last_known = true
	var hide_picks := 0
	for i in 200:
		seeker.position = Vector2(10, 10)
		if seeker._pick_search_target(seek_field).distance_to(Vector2(14.5, 10.5)) < .01:
			hide_picks += 1
	_expect(hide_picks > 50 and hide_picks < 140, "Nightmare checks the hiding spot beside the last sighting about 45%% of the time (%d/200)" % hide_picks)

	if _failures == 0:
		print("  ok    hard_abilities: pounce (range, line, links, cooldown, stumble, bonk, rarity per mode), burst, intercept, door slam, budget, switch, replication")
	return _failures
