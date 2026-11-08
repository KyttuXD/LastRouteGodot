extends RefCounted

## Night Watch Salvage Run (3D): the rules port reproduces the 2D game's numbers (whole shifts played by a fixed bot match the 2D logic's event logs, from
## tests/fixtures/night_watch_dayshift_golden.json), the shop, the rack, the noise, the door visitors and Ysolde at the window behave as in
## validate-dayshift.mjs, a shift is deterministic by seed, and the scene (the shop, every week from the Shift Board, win, short, caught, Custom Night,
## carry-over, Retry) works.

const ZERO := {"ravelle": 0, "ceryth": 0, "ysolde": 0}

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _game(week: int, seed_number: int, opts := {}) -> DayshiftLogic:
	return DayshiftLogic.new(week, NightWatchMulberry.new(seed_number), opts)


## One hunter (or none) on the floor.
func _only(overrides: Dictionary, week := 3, seed_number := 1, upgrades := []) -> DayshiftLogic:
	var levels := ZERO.duplicate()
	for k in overrides:
		levels[k] = overrides[k]
	return _game(week, seed_number, {"levels": levels, "custom": false, "upgrades": upgrades})


func _bot(kind: String, g: DayshiftLogic) -> Dictionary:
	if kind == "idle":
		return {}
	var s := g.s
	var u: Dictionary = s["ysolde"]
	var quiet := String(u["state"]) == "knock" or String(u["state"]) == "here"
	var first: Dictionary = (s["items"] as Array)[0] if not (s["items"] as Array).is_empty() else {}
	return {"work": not quiet and not first.is_empty(), "target": int(first["slot"]) if not first.is_empty() else -1,
		"doorL": int(s["ravelle"]["dist"]) == 0, "doorR": int(s["ceryth"]["dist"]) == 0,
		"lightL": not quiet and int(s["ravelle"]["dist"]) == 1, "lightR": not quiet and int(s["ceryth"]["dist"]) == 1}


static func _ev_string(e: Dictionary) -> String:
	var parts := []
	for k in ["type", "id", "slot", "dist", "value", "by", "money", "quota"]:
		parts.append(str(e.get(k, "")))
	return "|".join(parts)


func _play(g: DayshiftLogic, kind: String, dt: float, cap := 4000) -> Array:
	var log := []
	var n := 0
	while String(g.s["over"]) == "" and n < cap:
		for e in g.step(dt, _bot(kind, g)):
			log.append("%d|%s" % [n, _ev_string(e)])
		n += 1
	return log


func _until(g: DayshiftLogic, input: Dictionary, ms: float, dt := 50.0) -> Array:
	var log := []
	var t := 0.0
	while t < ms and String(g.s["over"]) == "":
		log.append_array(g.step(dt, input))
		t += dt
	return log


func _has(events: Array, type: String) -> bool:
	for e in events:
		if String(e["type"]) == type:
			return true
	return false


func run(host: Node) -> int:
	NwLeakProbe.fresh()
	_check_data()
	_check_golden()
	_check_rules()
	await _check_scene(host)
	await _check_call(host)
	await _check_admin(host)
	if _failures == 0:
		print("  night_watch_dayshift  the 2D rules (golden shifts, shop, rack, noise, doors, window, power) and the shift scene (shop, weeks, win, short, loss, saves, Custom Night, carry-over, retry)")
	return _failures


func _check_data() -> void:
	_expect(DayshiftData.BUDGET == [90, 100, 110, 120, 130] and DayshiftData.QUOTA == [140, 210, 280, 340, 380], "the budgets or quotas differ from the 2D game's")
	_expect(DayshiftData.UPGRADES.size() == 5 and DayshiftLogic.total_cost(["hinges", "cell", "soles", "gloves", "bench"]) == 190, "the upgrades differ from the 2D game's")
	_expect(DayshiftLogic.active_hunters(0) == ["ravelle"] and DayshiftLogic.active_hunters(1) == ["ravelle", "ceryth"] and DayshiftLogic.active_hunters(2).size() == 3, "who is on each week is wrong")
	_expect(DayshiftLogic.budget_for(1) == 90 and DayshiftLogic.budget_for(2, 25) == 125 and DayshiftLogic.budget_for(2, 99) == 140 and DayshiftLogic.carry_from(300, 210) == 40 and DayshiftLogic.carry_from(215, 210) == 5
		and DayshiftLogic.carry_from(100, 210) == 0, "the budget or carry-over is wrong")
	_expect(DayshiftLogic.can_buy(["hinges", "cell"], 1) and not DayshiftLogic.can_buy(["hinges", "cell", "gloves"], 1) and not DayshiftLogic.can_buy(["hinges", "hinges"], 5)
		and not DayshiftLogic.can_buy(["nothing"], 5), "can_buy is wrong")
	var basket = DayshiftLogic.shop_toggle([], "hinges", 1)
	_expect(basket == ["hinges"] and DayshiftLogic.shop_toggle(basket, "hinges", 1) == [] and DayshiftLogic.shop_toggle(["gloves", "bench"], "cell", 1) == null, "the shop's toggle is wrong")
	_expect(DayshiftLogic.T["atDoorByWeekMs"] == [8000.0, 7000.0, 6200.0, 5600.0, 5200.0], "the door waits differ from the 2D game's")
	_expect(DayshiftData.call_lines(1).size() == 3 and DayshiftData.call_lines(3).size() == 2 and DayshiftData.call_lines(5).size() == 1, "Zellia's script differs from the 2D game's")


func _check_golden() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/night_watch_dayshift_golden.json"))
	_expect(data is Dictionary and (data["runs"] as Array).size() >= 20, "the golden fixture is missing")
	if not (data is Dictionary):
		return
	var events_total := 0
	var kinds := {}
	for run in data["runs"]:
		var levels := {}
		for k in run.get("levels", {}):
			levels[k] = int(run["levels"][k])
		var opts := {"upgrades": run["upgrades"], "levels": levels, "custom": bool(run.get("custom", false)), "infinite_power": bool(run.get("infinitePower", false))}
		if run.has("quota"):
			opts["quota"] = int(run["quota"])
		var g := _game(int(run["week"]), int(run["seed"]), opts)
		var log := _play(g, String(run["kind"]), float(data["dt"]))
		var want: Array = run["events"]
		var label := "week %d seed %d %s" % [int(run["week"]), int(run["seed"]), run["kind"]]
		if log.size() != want.size():
			print("  FAIL  %s: %d events, the 2D game has %d" % [label, log.size(), want.size()])
			_failures += 1
		else:
			for i in log.size():
				if String(log[i]) != String(want[i]):
					print("  FAIL  %s: event %d is %s, the 2D game has %s" % [label, i, log[i], want[i]])
					_failures += 1
					break
		var sum: Dictionary = run["summary"]
		var s := g.s
		_expect(absf(float(s["elapsed"]) - float(sum["elapsed"])) < 1e-6 and absf(float(s["power"]) - float(sum["power"])) < 2e-6 and absf(float(s["noise"]) - float(sum["noise"])) < 2e-6
			and int(s["money"]) == int(sum["money"]) and String(s["over"]) == String(sum["over"]) and String(s["by"]) == String(sum["by"]) and (s["items"] as Array).size() == int(sum["items"])
			and String(s["deck"]["id"]) == String(sum["deck"]) and String(s["lead"]) == String(sum["lead"]) and String(s["ysolde"]["state"]) == String(sum["ysolde"]),
			"%s: the final state differs from the 2D game's (%s %s $%s)" % [label, s["over"], s["by"], s["money"]])
		kinds[String(s["over"])] = true
		events_total += log.size()
	_expect(kinds.has("win") and kinds.has("short") and kinds.has("caught"), "the golden shifts do not cover a win, a short night and a catch")
	print("  dayshift golden: %d shifts, %d events identical to the 2D logic" % [(data["runs"] as Array).size(), events_total])


func _check_rules() -> void:
	# determinism
	var a := _play(_game(4, 123), "bot", 100.0)
	var b := _play(_game(4, 123), "bot", 100.0)
	var c := _play(_game(4, 124), "bot", 100.0)
	_expect(a == b and a.size() > 20 and a != c, "the same seed did not give the same shift twice / another seed matched")
	# a quiet floor and no work: short at 6 AM with $0
	var quiet := _only({})
	_until(quiet, {}, 271000.0, 500.0)
	_expect(String(quiet.s["over"]) == "short" and int(quiet.s["money"]) == 0, "a quiet shift without salvage was not a short night")
	# the deck: nine pieces make exactly the deck
	var deck := _only({}, 3, 5)
	var counts := {"scrap": 0, "parts": 0, "prize": 0}
	for i in 9:
		counts[deck._deal_kind()] += 1
	var d: Dictionary = {}
	for k in DayshiftData.DECKS:
		if String(k["id"]) == String(deck.s["deck"]["id"]):
			d = k
	_expect(counts["scrap"] == int(d["scrap"]) and counts["parts"] == int(d["parts"]) and counts["prize"] == int(d["prize"]), "nine pieces off the deck are not the deck")
	# salvage: hold on a piece until it is taken (gloves: 30% faster); noise follows; bench halves it
	var rack := _only({}, 3, 1)
	rack.s["items"] = [{"slot": 2, "kind": "parts", "value": 25, "need": 3500.0, "progress": 0.0, "age": 0.0}]
	rack.s["spawnAt"] = 1e12
	var rlog := _until(rack, {"work": true, "target": 2}, 3600.0, 50.0)
	_expect(_has(rlog, "salvage") and int(rack.s["money"]) == 25 and (rack.s["items"] as Array).is_empty(), "holding on a piece did not take it in 3.5 s")
	_expect(float(rack.s["noise"]) > 30.0, "salvaging made no noise")
	var gloved := _only({}, 3, 1, ["gloves"])
	gloved.s["items"] = [{"slot": 0, "kind": "parts", "value": 25, "need": 3500.0 * 0.7, "progress": 0.0, "age": 0.0}]
	gloved.s["spawnAt"] = 1e12
	_until(gloved, {"work": true, "target": 0}, 2500.0, 50.0)
	_expect(int(gloved.s["money"]) == 25, "gloves did not make salvaging 30% faster")
	var loud := _only({}, 3, 1)
	var soft := _only({}, 3, 1, ["bench"])
	for g in [loud, soft]:
		g.s["items"] = [{"slot": 1, "kind": "prize", "value": 60, "need": 5500.0, "progress": 0.0, "age": 0.0}]
		g.s["spawnAt"] = 1e12
		_until(g, {"work": true, "target": 1}, 3000.0, 50.0)
	_expect(float(soft.s["noise"]) < float(loud.s["noise"]) * 0.6, "the padded bench did not halve the noise")
	var released := _only({}, 3, 1)
	released.s["items"] = [{"slot": 1, "kind": "prize", "value": 60, "need": 5500.0, "progress": 0.0, "age": 0.0}]
	released.s["spawnAt"] = 1e12
	_until(released, {"work": true, "target": 3}, 1000.0, 50.0)
	_expect(float((released.s["items"] as Array)[0]["progress"]) == 0.0, "work on an empty slot progressed another piece")
	# noise makes the doors' visitors keener
	var keen := _only({"ravelle": 6}, 3, 1)
	_expect(keen.level("ravelle") == 6, "level before noise")
	keen.s["noise"] = 25.0
	_expect(keen.level("ravelle") == 7, "uneasy noise did not add a level")
	keen.s["noise"] = 45.0
	_expect(keen.level("ravelle") == 9, "loud noise did not add three levels")
	var soles := _only({"ravelle": 6}, 3, 1, ["soles"])
	_expect(soles.level("ravelle") == 4, "soft soles did not take two levels off")
	# a door visitor: shut door sends her off in 0.45 s, an open dark door ends the night after the week's wait, a light holds her
	var door := _only({"ravelle": 10}, 1, 1)
	door.s["ravelle"]["dist"] = 0
	var dlog := _until(door, {"doorL": true}, 600.0, 50.0)
	_expect(_has(dlog, "repelled") and int(door.s["ravelle"]["dist"]) == 2, "a shut door did not turn Ravelle away")
	var open := _only({"ravelle": 10}, 1, 1)
	open.s["ravelle"]["dist"] = 0
	_until(open, {}, 8100.0, 50.0)
	_expect(String(open.s["over"]) == "caught" and String(open.s["by"]) == "ravelle" and float(open.s["elapsed"]) >= 8000.0, "an open door did not lose week 1 after 8 s")
	var lit := _only({"ravelle": 10}, 1, 1)
	lit.s["ravelle"]["dist"] = 0
	_until(lit, {"lightL": true}, 20000.0, 50.0)
	_expect(String(lit.s["over"]) == "" and float(lit.s["ravelle"]["atMs"]) == 0.0, "the door light did not hold Ravelle at the door")
	var away := _only({"ravelle": 12}, 1, 1)
	away.s["ravelle"]["dist"] = 3
	_until(away, {"lightL": true}, 40000.0, 100.0)
	_expect(int(away.s["ravelle"]["dist"]) == 3, "the door light did not hold a visitor still down the hall")
	# working together: a turned-away visitor warns the other
	var pair := _only({"ravelle": 10, "ceryth": 10}, 3, 1)
	pair.s["ravelle"]["dist"] = 0
	pair.s["ceryth"]["dist"] = 2
	var plog := _until(pair, {"doorL": true}, 600.0, 50.0)
	_expect(_has(plog, "warned"), "a turned-away visitor did not warn the other")
	# Ysolde: knock, window, quiet gets her gone; light or salvage while she is there loses
	var ys := _only({"ysolde": 8}, 3, 1)
	ys.s["ysolde"].merge({"state": "here", "t": 0.0, "expose": 0.0, "stay": 6000.0}, true)
	var ylog := _until(ys, {}, 6100.0, 50.0)
	_expect(_has(ylog, "gone") and String(ys.s["over"]) == "", "a quiet office did not send Ysolde away")
	var noisy := _only({"ysolde": 8}, 3, 1)
	noisy.s["ysolde"].merge({"state": "here", "t": 0.0, "expose": 0.0, "stay": 6000.0}, true)
	_until(noisy, {"lightL": true}, 1700.0, 50.0)
	_expect(String(noisy.s["over"]) == "caught" and String(noisy.s["by"]) == "ysolde", "a light at the window did not lose to Ysolde")
	var salv := _only({"ysolde": 8}, 3, 1)
	salv.s["ysolde"].merge({"state": "here", "t": 0.0, "expose": 0.0, "stay": 6000.0}, true)
	salv.s["items"] = [{"slot": 0, "kind": "prize", "value": 60, "need": 5500.0, "progress": 0.0, "age": 0.0}]
	salv.s["spawnAt"] = 1e12
	_until(salv, {"work": true, "target": 0}, 1700.0, 50.0)
	_expect(String(salv.s["over"]) == "caught" and String(salv.s["by"]) == "ysolde", "salvaging at the window did not lose to Ysolde")
	var knocks := _only({"ysolde": 8}, 3, 1)
	var klog := _until(knocks, {}, 60000.0, 100.0)
	var order := []
	for e in klog:
		if ["knock", "window", "gone"].has(String(e["type"])):
			order.append(String(e["type"]))
	_expect(order.size() >= 3 and order.slice(0, 3) == ["knock", "window", "gone"], "Ysolde's visit is not knock, window, gone (%s)" % str(order))
	# power: doors and lights draw it, hinges halve the doors, the cell is a quarter slower, at zero someone comes in 9 s
	var p0 := _only({}, 3, 1)
	var p1 := _only({}, 3, 1, ["hinges"])
	for g in [p0, p1]:
		_until(g, {"doorL": true, "doorR": true}, 10000.0, 50.0)
	_expect((100.0 - float(p1.s["power"])) < (100.0 - float(p0.s["power"])) and (100.0 - float(p1.s["power"])) > 0.0, "sturdy hinges did not cut the doors' drain")
	var cell := _only({}, 3, 1, ["cell"])
	var plain := _only({}, 3, 1)
	for g in [cell, plain]:
		_until(g, {"lightL": true}, 10000.0, 50.0)
	_expect(absf((100.0 - float(cell.s["power"])) / (100.0 - float(plain.s["power"])) - 0.75) < 0.001, "the extra cell is not a quarter slower")
	var dark := _only({}, 3, 1)
	dark.s["power"] = 0.0
	var olog := _until(dark, {}, 10000.0, 100.0)
	_expect(_has(olog, "out") and String(dark.s["over"]) == "caught" and String(dark.s["by"]) == "ravelle" and float(dark.s["outMs"]) >= 9000.0, "the dark did not bring Ravelle after 9 s")
	# 6 AM: the quota decides
	var rich := _only({}, 3, 1)
	rich.s["money"] = 280
	_until(rich, {}, 271000.0, 500.0)
	_expect(String(rich.s["over"]) == "win", "the quota in hand was not a win at 6 AM")
	var poor := _only({}, 3, 1)
	poor.s["money"] = 279
	var plog2 := _until(poor, {}, 271000.0, 500.0)
	_expect(String(poor.s["over"]) == "short" and _has(plog2, "short"), "a dollar short was not a short night")


# --- the shift scene -------------------------------------------------------------------------------------------------------

func _shift(host: Node, level: int, seed_number: int, custom_levels := {}, zero := false) -> DayshiftGame:
	NightWatchSession.start_mode("dayshift", level, custom_levels, seed_number)
	if zero:
		NightWatchSession.custom_levels = ZERO.duplicate()
	var shift := (load(NightWatchModeRegistry.scene_for("dayshift")) as PackedScene).instantiate() as DayshiftGame
	shift.manual_clock = true
	host.add_child(shift)
	return shift


func _check_scene(host: Node) -> void:
	NightWatchSave.path = "user://night_watch_dayshift_test.cfg"
	NightWatchSave.reset()
	DayshiftGame.pending_carry = 0
	_expect(NightWatchModeRegistry.playable("dayshift") and NightWatchModeRegistry.prepare("dayshift", 2) == "res://game/night_watch/dayshift/night_watch_dayshift.tscn", "the registry does not start Salvage Run")
	var weeks: Array = NightWatchModesData.mode("dayshift")["levels"]
	_expect(weeks.size() == 5, "Salvage Run does not list five weeks")
	for n in range(1, weeks.size() + 1):
		var shift := _shift(host, n, 100 + n)
		await host.get_tree().process_frame
		_expect(shift.state == DayshiftGame.State.SHOP and shift.week == n and shift.level_name() == "WEEK %d" % n and shift.shop != null, "week %d did not open on the shop" % n)
		_expect(shift.shop.budget() == DayshiftData.BUDGET[n - 1] and shift.shop.quota() == DayshiftData.QUOTA[n - 1], "week %d's shop shows the wrong budget or quota" % n)
		shift.start_shift([])
		_expect(shift.state == DayshiftGame.State.PLAYING and shift.sim != null and shift.sim.week_idx == n - 1, "week %d did not start its night" % n)
		shift.advance_ms(1000.0)
		_expect(shift.hud.clock_label.text == "12 AM" and shift.hud.night_label.text == "7. Salvage Run · Week %d" % n and shift.hud.usage_label.text.begins_with("$0 / $%d" % DayshiftData.QUOTA[n - 1]), "the clock, week or money label is wrong in week %d" % n)
		shift.queue_free()
		await host.get_tree().process_frame
	# the shop: buttons follow the budget, START SHIFT hands the basket to the rules
	var game := _shift(host, 1, 4242)
	await host.get_tree().process_frame
	var shop := game.shop
	_expect(shop.toggle("hinges") and shop.toggle("cell") and not shop.toggle("gloves") and (shop.buttons["gloves"] as Button).disabled and not (shop.buttons["hinges"] as Button).disabled,
		"the shop's buttons do not follow the budget")
	_expect(shop.budget_label.text == "Budget $20 of $90" and shop.quota_label.text == "Tonight's quota $140", "the shop's budget line differs from the 2D game's: %s" % shop.budget_label.text)
	shop.toggle("hinges")
	shop.toggle("bench")
	shop.start_button.pressed.emit()
	_expect(game.state == DayshiftGame.State.PLAYING and game.sim.has_upgrade("cell") and game.sim.has_upgrade("bench") and not game.sim.has_upgrade("hinges"), "the bought upgrades did not reach the rules")
	# the room: shared player and crosshair, rack stations, window, no audio players
	_expect(game.hud.find_children("*", "Crosshair", true, false).size() == 1 and game.find_children("*", "AudioStreamPlayer", true, false).is_empty(), "the shared crosshair is missing or there is an audio player of its own")
	_expect(game.office is CargoBay and game.office.spec.id == "cargo_bay", "Salvage Run is not in its own cargo bay")
	for i in 4:
		_expect(game.office.stations.has("rack%d" % i), "rack slot %d has no station" % i)
	_expect(game.office.find_child("Window", false, false) != null and game.office.find_child("Workbench", false, false) != null, "the window or the workbench is missing")
	for file in DirAccess.get_files_at("res://game/night_watch/dayshift"):
		if file.ends_with(".gd"):
			_expect(not FileAccess.get_file_as_string("res://game/night_watch/dayshift/" + file).contains("AudioStreamPlayer"), "%s makes its own audio player" % file)
	# a piece turns up, shows on its slot, and holding on it takes it
	game.sim.s["items"] = [{"slot": 1, "kind": "scrap", "value": 10, "need": 2000.0, "progress": 0.0, "age": 0.0}]
	game.sim.s["spawnAt"] = 1e12
	game.advance_ms(50.0)
	var st1 := game.office.stations["rack1"] as NightWatchStation
	_expect(not st1.disabled and st1.prompt_text.contains("SCRAP") and (game.office.pieces[1] as Node3D).visible and (game.office.stations["rack0"] as NightWatchStation).disabled, "the piece does not show on its slot")
	game.set_work(1)
	for i in 45:
		game.advance_ms(50.0)
	_expect(int(game.sim.s["money"]) == 10 and not (game.office.pieces[1] as Node3D).visible and game.hud.usage_label.text.begins_with("$10 / $140"), "holding on the piece did not take it")
	game.set_work(-1)
	# doors and lights as Classic
	game.toggle_door("doorL")
	game.advance_ms(100.0)
	_expect(bool(game.sim.s["dev"]["doorL"]) and is_equal_approx(float(game.office.slab_progress["doorL"]), 1.0), "the left door did not shut")
	game.toggle_door("doorL")
	game.set_light("doorR", true)
	game.advance_ms(100.0)
	_expect((game.office.door_lights["doorR"] as SpotLight3D).visible, "the right door light did not come on")
	game.set_light("doorR", false)
	# the hunters WALK down the hall (never placed), Ysolde is at the window only while she is there
	game.manual_clock = false
	game.sim.s["ravelle"]["dist"] = 3
	game._place_hunters()
	var rm := game._models["ravelle"] as Node3D
	var far := rm.position
	game.sim.s["ravelle"]["dist"] = 2
	game._place_hunters()
	game._animate_models(0.2)
	_expect(far.distance_to(rm.position) > 0.1 and rm.position.distance_to(game.office.global_position + CargoBay.hall_stand("doorL", 2)) > 0.3, "Ravelle was placed at her next step instead of walking")
	for i in 80:
		game._animate_models(0.1)
	_expect(rm.position.distance_to(game.office.global_position + CargoBay.hall_stand("doorL", 2)) < 0.3, "Ravelle never walked to her next step")
	game.manual_clock = true
	game.sim.s["ysolde"]["state"] = "knock"
	game._place_hunters()
	_expect((game._models["ysolde"] as Node3D).visible, "Ysolde is not on her way across the yard during the knock")
	game.sim.s["ysolde"]["state"] = "here"
	game._place_hunters()
	_expect((game._models["ysolde"] as Node3D).visible and (game._models["ysolde"] as Node3D).position.z > NightWatchOffice.HALF_D, "Ysolde is not outside the window")
	# the map: a ship and its scrap yard around the bay; every room is a walk from every other, no route crosses a wall, the hunters come in from their ends of the ship
	var layout := DayshiftMap.map_layout()
	var yard := game.yard
	for id in (layout["rooms"] as Dictionary):
		_expect(yard.points.has("C:%s" % id) or id == "gantryL" and yard.points.has("G:L") or id == "gantryR" and yard.points.has("G:R"), "the map room %s has no waypoint" % id)
	var keys := ["C:airlock", "C:dockL", "C:engine", "C:bridge", "C:hold", "C:yard", "C:crane", "G:L", "G:R", "W:stand", "D:L3", "D:R3"]
	var bad_wall := 0
	for ka in keys:
		for kb in keys:
			if ka == kb:
				continue
			var legs: Array = yard.route(ka, kb)
			_expect(legs.size() >= 2, "no walk from %s to %s" % [ka, kb])
			for k in range(1, legs.size()):
				var p0: Vector3 = legs[k - 1]["p"]
				var p1: Vector3 = legs[k]["p"]
				var n := int(ceil(p0.distance_to(p1) / 0.1))
				for q in n:
					var pt := p0.lerp(p1, float(q) / float(n))
					for w in yard.wall_boxes:
						if (w["rect"] as Rect2).has_point(Vector2(pt.x, pt.z)):
							bad_wall += 1
	_expect(bad_wall == 0, "walking routes in the ship cross walls at %d points" % bad_wall)
	var named := {}
	for m in yard.find_children("*", "MeshInstance3D", true, false):
		var nm := String(m.get_meta("nw_name", ""))
		named[nm] = int(named.get(nm, 0)) + 1
	_expect(int(named.get("BlockEngine", 0)) == 1 and int(named.get("ConsoleBridge", 0)) == 1 and int(named.get("BodyForklift", 0)) == 1 and int(named.get("BoomCrane", 0)) == 1
		and int(named.get("FrameAirlock", 0)) >= 3 and int(named.get("ScrapBlock", 0)) >= 20 and int(named.get("StackHold", 0)) >= 3, "the engine, bridge, dock, airlock, crane, hold or scrap yard is missing")
	_expect(game.office.find_children("*", "MeshInstance3D", true, false).filter(func(m): return String(m.get_meta("nw_name", "")) == "HallLEnd").is_empty(), "the left hall still has its end wall")
	var route_l: Array = yard.legs_to("ravelle", "D:L3")
	_expect(route_l.size() >= 5 and String(route_l[0]["key"]) == "C:airlock" and String(route_l[route_l.size() - 1]["key"]) == "D:L3" and (route_l[0]["p"] as Vector3).x < -25.0, "Ravelle's walk does not start at the airlock and end at the left gantry")
	game.queue_free()
	await host.get_tree().process_frame
	var live := _shift(host, 3, 21)
	await host.get_tree().process_frame
	live.manual_clock = false
	live.start_shift([])
	var rav := live._models["ravelle"] as Node3D
	_expect(rav.position.x < -20.0, "Ravelle did not start her shift at the airlock (x %.1f)" % rav.position.x)
	for i in 120:
		live._animate_models(0.1)
	_expect(rav.position.distance_to(live.office.global_position + CargoBay.hall_stand("doorL", int(live.sim.s["ravelle"]["dist"]))) < 0.5, "Ravelle did not walk in from the airlock to the end of her gantry")
	live.sim.s["ysolde"]["state"] = "knock"
	live._place_hunters()
	var ysm := live._models["ysolde"] as Node3D
	_expect(ysm.visible and ysm.position.z > 12.0, "Ysolde does not start her knock at the crane")
	for i in 60:
		live._animate_models(0.1)
	_expect(ysm.position.distance_to(live.office.global_position + CargoBay.YARD_STAND) < 0.5, "Ysolde did not cross the yard to the window")
	live.manual_clock = true
	live.queue_free()
	await host.get_tree().process_frame
	# a loss: an unanswered door ends the night with the CAUGHT card
	var lose := _shift(host, 1, 5)
	await host.get_tree().process_frame
	lose.start_shift([])
	lose.sim.s["ravelle"]["dist"] = 0
	for i in 100:
		lose.advance_ms(100.0)
	_expect(lose.state == DayshiftGame.State.LOST and String(lose.last_death.get("by", "")) == "ravelle", "an unanswered door did not lose the week")
	var closing := 0
	while lose.death_moment.is_open() and closing < 40:
		lose.death_moment.dismiss()
		closing += 1
	await host.get_tree().process_frame
	_expect(lose.hud.end_root.visible and lose.hud.end_title.text == "CAUGHT" and not lose.hud.end_next.visible and lose.hud.retry_pressed.is_connected(lose.retry), "the end card after a catch is not CAUGHT with Retry")
	var seed_before := lose.seed_value
	NightWatchSession.start_mode(lose.mode_id, lose.level, lose.custom, lose.seed_value)
	_expect(NightWatchSession.seed_value == seed_before and NightWatchSession.mode_id == "dayshift", "Retry would not replay the same seed")
	lose.queue_free()
	await host.get_tree().process_frame
	# a short night: the quota missed is a loss with its own card, nothing saved
	var short := _shift(host, 1, 6, {}, true)
	await host.get_tree().process_frame
	short.start_shift([])
	for i in 271:
		short.advance_ms(1000.0)
	_expect(short.state == DayshiftGame.State.LOST and short.hud.end_title.text == "QUOTA MISSED" and NightWatchSave.cleared_levels("dayshift").is_empty(), "a quota missed was not a loss that saves nothing")
	short.queue_free()
	await host.get_tree().process_frame
	# a won week: saved under cleared_dayshift, opens the next; the surplus is carried only when you play on
	var win := _shift(host, 1, 7, {}, true)
	await host.get_tree().process_frame
	win.start_shift([])
	win.sim.s["money"] = 190
	for i in 271:
		win.advance_ms(1000.0)
	_expect(win.state == DayshiftGame.State.WON and win.hud.end_title.text == "WEEK 1 COMPLETE" and win.hud.end_next.visible and win.win_carry == 40, "a quota in hand was not won with the surplus carried")
	_expect(NightWatchSave.cleared_levels("dayshift") == [1] and NightWatchSave.level_open("dayshift", 2) and not NightWatchSave.level_open("dayshift", 3) and NightWatchSave.cleared_levels("classic").is_empty(),
		"winning week 1 did not save cleared_dayshift and open exactly week 2")
	win.win_carry = 15
	DayshiftGame.pending_carry = win.win_carry   # what next_night() hands over before the scene reloads
	win.queue_free()
	await host.get_tree().process_frame
	var week2 := _shift(host, 2, 8)
	await host.get_tree().process_frame
	_expect(week2.carry == 15 and week2.shop.budget() == 115 and DayshiftGame.pending_carry == 0 and week2.shop.budget_label.text.contains("$15 carried over"), "the surplus did not carry into week 2's shop")
	week2.queue_free()
	await host.get_tree().process_frame
	var again := _shift(host, 2, 9)
	await host.get_tree().process_frame
	_expect(again.carry == 0 and again.shop.budget() == 100, "a week started from the board kept the carry-over")
	again.queue_free()
	await host.get_tree().process_frame
	# Custom Night: week 4's quota, the door wait of week 5, the sliders are the levels; a win records a score and the preset's star
	var presets: Array = NightWatchModesData.mode("dayshift")["presets"]
	var first: Dictionary = presets[0]
	var cn := _shift(host, 1, 77, first["ai"])
	await host.get_tree().process_frame
	_expect(cn.is_custom and cn.week == 4 and cn.shop.quota() == 340 and cn.shop.budget() == 120, "the Custom Night is not week 4's shop")
	cn.start_shift([])
	_expect(cn.sim.custom and cn.sim.door_ms == 5200.0 and cn.sim.need == 340 and cn.sim.base_level("ravelle") == int(first["ai"]["ravelle"]) and cn.sim.base_level("ceryth") == int(first["ai"]["ceryth"]),
		"the Custom Night sliders did not feed the rules")
	cn.sim.s["money"] = 340
	cn.sim.s["elapsed"] = NightWatchData.NIGHT_MS - 50.0
	cn.advance_ms(100.0)
	_expect(cn.state == DayshiftGame.State.WON and cn.hud.end_title.text == "CUSTOM NIGHT COMPLETE" and NightWatchSave.best_score("dayshift") > 0 and NightWatchSave.stars("dayshift") == [String(first["id"])]
		and NightWatchSave.cleared_levels("dayshift") == [1], "the Custom Night did not record its score and star")
	cn.queue_free()
	await host.get_tree().process_frame
	_expect(not InputMap.has_action(NightWatchControls.LIGHT_LEFT), "the quick-key actions stayed registered after the shift closed")
	NightWatchSave.reset()
	NightWatchSave.path = NwLeakProbe.scratch_path()
	DayshiftGame.pending_carry = 0
	NightWatchSession.start(1)


# --- Zellia's call: rung at the week's `at` seconds on the shift clock (not during the shop), typed line by line, skipped with mute ----------------------------------------

func _check_call(host: Node) -> void:
	var game := _shift(host, 1, 750)
	await host.get_tree().process_frame
	game.advance_ms(60000.0)
	_expect(game.state == DayshiftGame.State.SHOP and (game.hud.call_script == null or not game.hud.call_script.open), "the call rang during the shop")
	game.start_shift([])
	var at_s := float(NightWatchCallsData.for_level("dayshift", 1)["at"])
	game.advance_ms((at_s - 1.0) * 1000.0)
	_expect(not game.hud.call_script.open and game.hud.shown_call.is_empty(), "the call rang before its time")
	game.admin_set_frozen(true)
	game.advance_ms(5000.0)
	_expect(not game.hud.call_script.open, "a frozen shift still rang the call")
	game.admin_set_frozen(false)
	for i in 15:
		game.advance_ms(100.0)
	_expect(game.hud.call_script.open and game.hud.shown_call == NightWatchCallsData.INCOMING_TEXT, "the call did not ring at %.0f s of the shift clock (%s)" % [at_s, game.hud.shown_call])
	for i in 40:
		game.advance_ms(100.0)
	_expect(game.hud.call_script.open and game.hud.call_script.line == 0, "the call did not go on to its first line")
	game.admin_skip_call()
	_expect(game.hud.shown_call.is_empty(), "skipping the call left it on screen")
	game.queue_free()
	await host.get_tree().process_frame


# --- the admin menu: the gate, the sections, the layout at three sizes, and every entry really changes the shift ---------------------------------------------

func _admin_snapshot(game: DayshiftGame) -> String:
	return NightWatchAdminCheck.dump(game.sim.s) + NightWatchAdminCheck.dump(game.sim.levels) + str(game.sim.upgrades) + "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [game.sim.infinite_power, game.sim.hunter_speed, game._admin_frozen,
		game._admin_god, game._admin_no_scare, game._admin_noclip, game.sim.need, game.door_shut, game.light_held, game.hud.shown_call, NightWatchSession.night]


func _check_admin(host: Node) -> void:
	NightWatchSave.path = "user://night_watch_dayshift_admin_test.cfg"
	NightWatchSave.reset()
	var game := _shift(host, 4, 700)
	await host.get_tree().process_frame
	game.start_shift([])
	for msg in NightWatchAdminCheck.sections(game, "SALVAGE RUN SPECIFIC"):
		_expect(false, "[admin] " + msg)
	_expect(game.hud.hint_label.text.contains("0 admin"), "the hint line does not list the admin key for an admin")
	for msg in await NightWatchAdminCheck.layout(host, game, "SALVAGE RUN SPECIFIC"):
		_expect(false, "[admin] " + msg)
	game.advance_ms(3000.0)
	for msg in NightWatchAdminCheck.exercise(game, func(g): return _admin_snapshot(g), ["WIN THE SHIFT", "LOSE THE SHIFT"]):
		_expect(false, "[admin] " + msg)
	game.queue_free()
	await host.get_tree().process_frame
	var g2 := _shift(host, 4, 701)
	await host.get_tree().process_frame
	g2.start_shift([])
	g2.admin_set_hour(3)
	_expect(g2.sim.level("ravelle") == int((DayshiftData.LEVELS["ravelle"] as Array)[3]) + 1, "SET TIME 3 AM did not step the AI up")
	g2.admin_set_money(250)
	g2.admin_set_quota(100)
	_expect(int(g2.sim.s["money"]) == 250 and g2.sim.need == 100 and g2.hud.usage_label.text.begins_with("$250 / $100"), "the money or the quota was not set")
	g2.admin_add_piece("prize")
	_expect((g2.sim.s["items"] as Array).size() == 1 and String(g2.sim.s["items"][0]["kind"]) == "prize" and not (g2.office.stations["rack0"] as NightWatchStation).disabled, "ADD A PRIZE did not put a piece on the rack")
	g2.admin_set_frozen(true)
	var before := float(g2.sim.s["elapsed"])
	g2.advance_ms(2000.0)
	_expect(float(g2.sim.s["elapsed"]) == before, "the frozen clock still ran")
	g2.admin_set_frozen(false)
	g2.admin_place_hunter("ravelle", "door")
	g2.admin_set_god(true)
	g2.advance_ms(12000.0)
	_expect(g2.state == DayshiftGame.State.PLAYING and String(g2.sim.s["over"]) == "", "god mode did not save the week from an unanswered door")
	g2.admin_set_god(false)
	g2.admin_set_no_scare(true)
	g2.admin_lose()
	_expect(g2.state == DayshiftGame.State.LOST and not g2.death_moment.is_open(), "LOSE THE SHIFT with no jumpscare still played the scare")
	g2.queue_free()
	await host.get_tree().process_frame
	var g3 := _shift(host, 2, 702)
	await host.get_tree().process_frame
	g3.start_shift([])
	g3.admin_win()
	_expect(g3.state == DayshiftGame.State.WON, "WIN THE SHIFT did not win")
	g3.queue_free()
	await host.get_tree().process_frame
	NightWatchSave.reset()
	NightWatchSave.path = NwLeakProbe.scratch_path()
	NightWatchSession.start(1)
