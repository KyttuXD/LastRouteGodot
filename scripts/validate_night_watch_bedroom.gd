extends RefCounted

## Bedtime (3D): the rules port reproduces the 2D game (games/night-watch validate-bedroom and -variety-bedroom): the night table, the stages,
## the defences, the battery, the restless house, Haelith's creep, the variety levers, and the 2D game's own draws (scripts/data/nw_bedroom_golden.json,
## written by tools/nightwatch/gen_bedroom_golden.mjs: whole shifts event by event for seeds, an idle and a busy hand, and Custom Nights).
## Then the shift scene: a dark room with no cameras, one hand, Javelle walking the hall, a win, a loss and the Custom Night.

var _failures := 0
const GOLDEN := "res://scripts/data/nw_bedroom_golden.json"
const QUIET := {"loxelle": 0, "javelle": 0, "haelith": 0}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _g(night: int, extra := {}) -> BedroomLogic:
	var o := {"night": night, "rng": NightWatchStream.fixed(0.0)}
	o.merge(extra, true)
	return BedroomLogic.new(o)


func _lv(extra: Dictionary) -> Dictionary:
	var l := QUIET.duplicate()
	l.merge(extra, true)
	return l


func _run(g: BedroomLogic, ms: float, input := {}) -> Array:
	var out := []
	var t := 0.0
	while t < ms and g.over == "":
		out.append_array(g.step(100.0, input))
		t += 100.0
	return out


func _types(ev: Array) -> Array:
	var out := []
	for e in ev:
		out.append(String(e["type"]))
	return out


func _first_move(night: int, id: String) -> float:
	return float(BedroomLogic.night_row(night)["first"][id]) * (1.0 - 0.25) + NightWatchData.move_window(20).x


func run(host: Node) -> int:
	_table()
	_rules()
	_variety()
	_golden()
	await _scene(host)
	if _failures == 0:
		print("  night_watch_bedroom  Bedtime rules (2D table, stages, defences, battery, restless, creep, variety, 2D draws) and the shift scene")
	return _failures


func _table() -> void:
	var nights := BedroomLogic.nights()
	_expect(nights.size() == 6 and BedroomLogic.flash_seconds() == [68, 59, 51, 42, 34, 28], "the night table or the battery seconds differ from the 2D game's: %s" % str(BedroomLogic.flash_seconds()))
	var lox := []
	var jav := []
	var hae := []
	for r in nights:
		lox.append(r["ai"]["loxelle"])
		jav.append(r["ai"]["javelle"])
		hae.append(r["ai"]["haelith"])
	_expect(lox == [3, 7, 9, 16, 18, 20] and jav == [0, 7, 9, 11, 12, 12] and hae == [0, 0, 5, 7, 9, 9], "the AI levels per night differ from the 2D game's")
	_expect(nights[0]["breathMs"] == 3200.0 and nights[0]["nearMs"] == 4200.0 and nights[1]["breathMs"] == 2560.0 and nights[5]["nearMs"] == 3360.0, "the stage times differ")
	_expect(nights[1]["first"]["javelle"] == 4500.0 and nights[2]["first"]["javelle"] == 4000.0 and nights[3]["rest"]["loxelle"] == 2500.0 and nights[5]["rest"]["loxelle"] == 1500.0, "first waits or rests differ")
	_expect(BedroomLogic.T["holdNeedMs"] == 700.0 and BedroomLogic.T["lightNeedMs"] == 600.0 and BedroomLogic.T["stageJitter"] == 0.4 and BedroomLogic.T["afkMs"] == 14000.0
		and BedroomLogic.T["bedGain"] == 8.0 and BedroomLogic.T["bedVisibleAt"] == 80.0, "T differs from the 2D game's")
	_expect(BedroomLogic.VARIETY == {"waitSpread": 0.25, "doorTempo": 0.1, "haelithTempo": 0.2, "swapFirst": 0.3}, "VARIETY differs")
	for i in range(1, 6):
		var a: Dictionary = nights[i - 1]
		var b: Dictionary = nights[i]
		_expect(b["breathMs"] <= a["breathMs"] and b["nearMs"] <= a["nearMs"], "night %d: stages no longer" % (i + 1))
		for id in BedroomData.CAST:
			_expect(b["ai"][id] >= a["ai"][id], "night %d: %s is no lower" % [i + 1, id])
	for i in 6:
		var r: Dictionary = nights[i]
		_expect(float(r["nearMs"]) * 0.8 >= 400.0 + 700.0 + 400.0 + 600.0, "night %d: the shortest near leaves no time for both doors" % (i + 1))
		_expect(r["ai"]["haelith"] <= 11 and 8.0 + 0.9 * (r["ai"]["haelith"] + 2) < 20.0, "night %d: Haelith can jump from unseen to in" % (i + 1))
	_expect([0, 1, 2, 3, 4].map(func(i): return BedroomLogic.active_hunters(i).size()) == [1, 2, 3, 3, 3] and BedroomLogic.active_hunters(0) == ["loxelle"], "who is on the floor each night is wrong")
	var c := BedroomLogic.custom_row()
	_expect(c["breathMs"] == 3200.0 and c["first"]["javelle"] == 3000.0 and c["rest"]["loxelle"] == 7000.0, "the Custom Night row is not Night 1's timings")
	_expect(NightWatchModesData.mode("bedroom")["levels"].size() == 6 and (NightWatchModesData.mode("bedroom")["cast"] as Array) == BedroomData.CAST, "the mode table and Bedtime's cast disagree")


func _rules() -> void:
	var g := _g(1, {"levels": QUIET})
	_expect(_types(_run(g, NightWatchData.NIGHT_MS)) == ["win"], "nobody awake: something happened before 6 AM")
	# Loxelle breathes, comes near and gets in unless the closet door is held
	g = _g(2, {"levels": _lv({"loxelle": 20})})
	var ev := _run(g, 30000).filter(func(e): return e["type"] != "stir")
	_expect(_types(ev).slice(0, 3) == ["breath", "near", "caught"] and g.by == "loxelle", "Loxelle's breath, near, caught is wrong: %s" % str(_types(ev)))
	# holding the door during the breathing turns her away, and she stays away for a while
	g = _g(2, {"levels": _lv({"loxelle": 20})})
	_run(g, _first_move(2, "loxelle") + 1000.0)
	_expect(g.loxelle["state"] == "breath", "Loxelle was not breathing after her first move")
	_expect(_types(_run(g, 900.0, {"hold": true})).has("leave") and g.loxelle["state"] == "away", "holding the closet did not turn her away")
	_expect(not _types(_run(g, float(BedroomLogic.night_row(2)["rest"]["loxelle"]) * 0.75 - 400.0)).has("breath"), "the cool-down did not keep her away")
	# Javelle answers only to light on the hall; the door does nothing, and holding it blocks the light
	g = _g(2, {"levels": _lv({"javelle": 20})})
	_run(g, _first_move(2, "javelle") + 1000.0)
	_expect(g.javelle["state"] == "breath", "Javelle was not breathing")
	_run(g, 1500.0, {"hold": true})
	_expect(g.javelle["state"] != "away", "the door stopped Javelle")
	g.step(100.0, {"hold": true, "light": "hall"})
	_expect(g.light == "", "a light came on while the door was held")
	_expect(_types(_run(g, 800.0, {"light": "hall"})).has("leave"), "the hall light did not drive Javelle off")
	# sitting still is punished
	g = _g(2, {"levels": _lv({"loxelle": 1})})
	g.loxelle["cool"] = 1e9
	var early := _run(g, 13500.0)
	_expect(not g.restless and not _types(early).has("restless"), "restless too early")
	var late := _run(g, 1500.0)
	_expect(g.restless and _types(late).filter(func(t): return t == "restless").size() == 1, "the house did not turn restless once")
	g.step(100.0, {"hold": true})
	_expect(not g.restless and g.idle == 0.0, "an action did not calm the house")
	var slow := _g(2, {"levels": _lv({"javelle": 20})})
	var fast := _g(2, {"levels": _lv({"javelle": 20})})
	fast.idle = 14000.0
	for g2 in [slow, fast]:
		g2.javelle["state"] = "breath"
		g2.javelle["t"] = 0.0
	for i in 10:
		slow.step(100.0, {"hold": true})
		fast.step(100.0, {})
	_expect(float(fast.javelle["t"]) > float(slow.javelle["t"]), "a restless door was not quicker")
	# Javelle holds her stage while the hall is lit
	g = _g(2, {"levels": _lv({"javelle": 20})})
	_run(g, _first_move(2, "javelle") + 500.0)
	var t0: float = g.javelle["t"]
	g.javelle["need"] = -1e9
	_run(g, 5000.0, {"light": "hall"})
	_expect(g.javelle["t"] == t0, "her timer ran while lit")
	# Haelith
	var dark := _g(3, {"levels": _lv({"haelith": 10})})
	_run(dark, 20000.0)
	_expect(float(dark.haelith["p"]) > 15.0, "Haelith did not creep in the dark")
	var lit := _g(3, {"levels": _lv({"haelith": 10})})
	_run(lit, 20000.0, {"light": "hall"})
	_expect(float(lit.haelith["p"]) == 0.0, "light on the hall did not keep her still")
	dark.step(100.0, {"light": "bed"})
	var before: float = dark.haelith["p"]
	_run(dark, 1000.0, {"light": "bed"})
	_expect(float(dark.haelith["p"]) < before, "light on the bed did not push her back")
	g = _g(3, {"levels": _lv({"haelith": 20})})
	ev = _run(g, 120000.0)
	_expect(_types(ev).slice(-1) == ["caught"] and g.by == "haelith", "Haelith did not get in")
	# the battery
	var fs := BedroomLogic.flash_seconds()
	for i in range(1, 6):
		_expect(fs[i] < fs[i - 1], "the battery does not fall each night")
	g = _g(1, {"levels": QUIET})
	_run(g, 10000.0, {"light": "hall"})
	_expect(g.battery < 92.0 and g.battery > 80.0, "night 1 allows about 68 s of light, got %s" % str(g.battery))
	var kept := g.battery
	_run(g, 10000.0)
	_expect(g.battery == kept, "the battery recharged")
	g.battery = 0.0
	g.step(100.0, {"light": "hall"})
	_expect(g.light == "", "a flat battery lit a light")
	var free := _g(5, {"levels": QUIET, "infinite_battery": true})
	_run(free, 20000.0, {"light": "bed"})
	_expect(free.battery == 100.0, "an infinite battery drained")
	# the AI steps up at 3 and 4 AM; a sleeping hunter stays asleep
	g = _g(1, {"levels": _lv({"loxelle": 6})})
	g.elapsed = 4 * NightWatchData.HOUR_MS + 1000.0
	_expect(g.level("loxelle") == 8 and g.level("javelle") == 0, "the AI step-ups are wrong")
	# the stages, measured: the first move, breathing 0.8 x breathMs, near 0.8 x nearMs with this rng (jitter 1 - 0.2)
	for night in [2, 5]:
		for id in ["loxelle", "javelle"]:
			g = _g(night, {"levels": _lv({id: 20})})
			var at := {}
			var tms := 0.0
			while g.over == "" and tms < 40000.0:
				for e in g.step(1.0):
					at[e["type"]] = tms + 1.0
				tms += 1.0
			var r: Dictionary = BedroomLogic.night_row(night)
			_expect(absf(float(at.get("breath", -1.0)) - (float(r["first"][id]) * 0.75 + 3000.0 - 0.0)) <= 2.0, "night %d %s: the first move comes at %s" % [night, id, str(at.get("breath"))])
			_expect(absf(float(at["near"]) - float(at["breath"]) - float(r["breathMs"]) * 0.8) <= 2.0 and absf(float(at["caught"]) - float(at["near"]) - float(r["nearMs"]) * 0.8) <= 2.0, "night %d %s: the stages are not breath %s / near %s" % [night, id, str(r["breathMs"]), str(r["nearMs"])])
	# Custom Night keeps Night 1's timings
	g = _g(5, {"custom": true, "levels": _lv({"loxelle": 20})})
	var at2 := {}
	var t2 := 0.0
	while g.over == "" and t2 < 40000.0:
		for e in g.step(1.0):
			at2[e["type"]] = t2 + 1.0
		t2 += 1.0
	_expect(absf(float(at2["near"]) - float(at2["breath"]) - 3200.0 * 0.8) <= 2.0 and absf(float(at2["caught"]) - float(at2["near"]) - 4200.0 * 0.8) <= 2.0, "the Custom Night did not run on Night 1's stages")


func _input(i: int) -> Dictionary:
	return {"hold": i % 40 < 12, "light": "bed" if i % 40 > 30 else ("hall" if i % 40 > 20 else "")}


func _trace(g: BedroomLogic, busy: bool) -> Array:
	var out := []
	var i := 0
	while i < NightWatchData.NIGHT_MS / 100.0 and g.over == "":
		for e in g.step(100.0, _input(i) if busy else {}):
			out.append("%d:%s:%s" % [i, e["type"], String(e.get("id", e.get("by", "")))])
		i += 1
	return [",".join(out), i]


func _variety() -> void:
	# bounds in play and the swap's share
	var swaps := 0
	var total := 0
	for night in range(2, 7):
		for seed_number in range(1, 41):
			var g := _g(night, {"rng": NightWatchStream.seeded(seed_number * 17 + night)})
			total += 1
			if g.swapped:
				swaps += 1
			for id in ["loxelle", "javelle"]:
				var door: Dictionary = g.loxelle if id == "loxelle" else g.javelle
				var base := float(BedroomLogic.night_row(night)["first"]["javelle" if (g.swapped and id == "loxelle") else ("loxelle" if g.swapped else id)])
				_expect(float(door["cool"]) >= base * 0.75 - 1e-6 and float(door["cool"]) <= base * 1.25 + 1e-6, "night %d: a first wait is out of +/-25%%" % night)
				_expect(float(door["tempo"]) >= 1.0 / 1.1 - 1e-9 and float(door["tempo"]) <= 1.0 / 0.9 + 1e-9, "a door's tempo is out of bounds")
			_expect(float(g.haelith["tempo"]) >= 1.0 / 1.2 - 1e-9 and float(g.haelith["tempo"]) <= 1.0 / 0.8 + 1e-9, "Haelith's tempo is out of bounds")
	var share := float(swaps) / float(total)
	_expect(share > 0.18 and share < 0.42, "the doors trade first waits on %d%% of nights, not about 30%%" % int(share * 100.0))
	# the same seed, the same night; different seeds, different nights
	for night in [2, 4, 6]:
		var seen := {}
		for seed_number in range(1, 9):
			var a: String = _trace(_g(night, {"rng": NightWatchStream.seeded(seed_number)}), true)[0]
			_expect(a == _trace(_g(night, {"rng": NightWatchStream.seeded(seed_number)}), true)[0], "night %d seed %d: the same seed played two nights" % [night, seed_number])
			seen[a] = true
		_expect(seen.size() >= 7, "night %d: 8 seeds gave %d different nights" % [night, seen.size()])
	# a lone night 1 with nothing awake but Loxelle never stirs a swap
	var solo := _g(1, {"rng": NightWatchStream.seeded(5)})
	_expect(not solo.swapped, "night 1 swapped with only one door awake")


func _golden() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	_expect(d is Dictionary, "the golden file did not load")
	if not (d is Dictionary):
		return
	for t in d["traces"]:
		var mode := String(t["mode"])
		var custom := mode.begins_with("custom")
		var opts := {"night": int(t["night"]), "rng": NightWatchStream.seeded(int(t["seed"]))}
		if custom:
			var lv := int(mode.substr(6))
			opts["custom"] = true
			opts["levels"] = {"loxelle": lv, "javelle": lv, "haelith": lv}
		var g := BedroomLogic.new(opts)
		var r := _trace(g, mode != "idle")
		var label := "night %d seed %d %s" % [int(t["night"]), int(t["seed"]), mode]
		_expect(String(r[0]) == String(t["events"]), "%s: the 3D shift differs from the 2D one%s" % [label, _first_diff(String(r[0]), String(t["events"]))])
		_expect(int(r[1]) == int(t["steps"]) and g.swapped == bool(t["swapped"]) and absf(g.battery - float(t["battery"])) < 1e-4 and absf(float(g.haelith["p"]) - float(t["p"])) < 1e-4,
			"%s: the end state differs (steps %d vs %d, battery %s vs %s, swapped %s vs %s)" % [label, int(r[1]), int(t["steps"]), str(g.battery), str(t["battery"]), str(g.swapped), str(t["swapped"])])


func _first_diff(a: String, b: String) -> String:
	var x := a.split(",")
	var y := b.split(",")
	for i in mini(x.size(), y.size()):
		if x[i] != y[i]:
			return " (event %d: %s vs %s)" % [i, x[i], y[i]]
	return " (%d vs %d events)" % [x.size(), y.size()]


# --- the shift scene ---------------------------------------------------------------------------------------------------------

func _make(host: Node, night: int, seed_number: int, custom := {}) -> BedroomGame:
	NightWatchSession.start_mode("bedroom", night, custom, seed_number)
	var game := (load("res://scenes/night_watch_bedroom.tscn") as PackedScene).instantiate() as BedroomGame
	game.manual_clock = true
	host.add_child(game)
	return game


func _scene(host: Node) -> void:
	_expect(NightWatchModeRegistry.playable("bedroom") and NightWatchModeRegistry.scene_for("bedroom") == "res://scenes/night_watch_bedroom.tscn", "Bedtime is not in the registry")
	NightWatchSave.path = "user://night_watch_bedroom_test.cfg"
	NightWatchSave.reset()
	for lv in range(1, 7):
		_expect(NightWatchModeRegistry.prepare("bedroom", lv) == "res://scenes/night_watch_bedroom.tscn" and NightWatchSession.mode_id == "bedroom" and NightWatchSession.night == lv, "shift %d does not start from the board" % lv)
	var game := _make(host, 3, 4242)
	await host.get_tree().process_frame
	_expect(game is NightWatchMode and game.mode_id == "bedroom" and game.level == 3 and game.seed_value == 4242 and game.level_name() == "NIGHT 3", "the shift scene did not read its session")
	_expect(InputMap.has_action(BedroomControls.HOLD) and InputMap.has_action(BedroomControls.HALL) and InputMap.has_action(BedroomControls.BED), "the A / D / F actions are not registered")
	_expect(game.camera != null and game.camera.current and game.camera.position == BedroomOffice.EYE, "there is no camera on the pillow")
	for prop_name in ["Shell", "Bed", "Closet", "Hall", "Nightstand", "ToyShelf", "Window"]:
		_expect(game.world.props.has(prop_name), "the bedroom has no %s" % prop_name)
	var cubes := 0
	for key in game.world.props:
		var st := NightWatchArt.prop_stats(game.world.props[key])
		cubes += int(st["cubes"])
		_expect((st["bad_emissive"] as Array).is_empty(), "%s has a cube that glows without a glowing name" % key)
	_expect(cubes > 90, "the bedroom is too bare (%d cubes)" % cubes)
	_expect(not game.world.hall_light.visible and not game.world.bed_light.visible, "a light is on in the dark")
	# one hand: pressing one lets go of the others; the closet is shut only while held; lights follow
	game.press("hall", true)
	game.press("hold", true)
	_expect(game.held == {"hold": true, "hall": false, "bed": false} and game.current_input() == {"hold": true, "light": ""}, "one hand: A did not let go of D")
	game.advance_ms(50.0)
	_expect(is_zero_approx(game.world.closet_pivot.rotation.y), "the closet door is not shut while held")
	game.press("bed", true)
	_expect(game.held == {"hold": false, "hall": false, "bed": true}, "one hand: F did not let go of A")
	game.advance_ms(50.0)
	_expect(game.world.bed_light.visible and not game.world.hall_light.visible and game.world.closet_pivot.rotation.y != 0.0, "the bed light or the door is wrong")
	game.press("hall", true)
	game.advance_ms(50.0)
	_expect(game.world.hall_light.visible and not game.world.bed_light.visible and game.hud.power_label.text.begins_with("BATTERY"), "the hall light is wrong")
	game.held["hall"] = false
	game.advance_ms(50.0)
	_expect(not game.world.hall_light.visible, "letting go did not put the light out")
	# Javelle walks up the hall instead of appearing at the door
	game.sim.levels = {"loxelle": 0, "javelle": 20, "haelith": 0}
	game.manual_clock = false
	game.set_process(false)
	game._place_hunters()
	var jv := game._models["javelle"] as Node3D
	_expect(not jv.visible, "Javelle is in the hall while away")
	game.sim.javelle["state"] = "breath"
	game._place_hunters()
	game._animate_models(0.1)
	_expect(jv.visible and jv.position.distance_to(game.paths.points["C:living_room"]) < 1.5, "Javelle did not set off from the living room")
	var hall_x := jv.position.x
	for i in 10:
		game._animate_models(0.1)
	_expect(jv.position.x < hall_x - 1.0 and jv.position.x > BedroomMap.rect("hall").end.x - 1.0, "Javelle was not walking down toward the hall")
	game.sim.javelle["state"] = "near"
	game._place_hunters()
	var longest := 0.0
	var last := jv.position
	for i in 150:
		game._animate_models(0.1)
		longest = maxf(longest, jv.position.distance_to(last))
		last = jv.position
	_expect(jv.position.distance_to(BedroomOffice.HALL_NEAR) < 0.3, "Javelle did not walk up to the doorway")
	_expect(longest <= NightWatchWalker.MAX_SPEED * 0.1 + 0.01, "Javelle moved %.2f m in one step" % longest)
	game.sim.javelle["state"] = "away"
	game._place_hunters()
	for i in 150:
		game._animate_models(0.1)
	game._place_hunters()
	_expect(not jv.visible, "Javelle did not walk back into the dark and away")
	game.manual_clock = true
	game.queue_free()
	await host.get_tree().process_frame
	_expect(not InputMap.has_action(BedroomControls.HOLD), "the A / D / F actions stayed registered after the shift")
	# a loss: Loxelle gets in; the closet opens on her
	game = _make(host, 2, 7)
	await host.get_tree().process_frame
	game.sim.levels = {"loxelle": 20, "javelle": 0, "haelith": 0}
	game.sim.loxelle["state"] = "near"
	game.sim.loxelle["t"] = 99999.0
	game.advance_ms(100.0)
	_expect(game.state == BedroomGame.State.LOST and game.last_death.get("by", "") == "loxelle", "Loxelle did not get in")
	_expect((game._models["loxelle"] as Node3D).visible and absf(game.world.closet_pivot.rotation.y) > 1.0, "her scare was not the closet opening on her")
	var closing := 0
	while game.death_moment.is_open() and closing < 40:
		game.death_moment.dismiss()
		closing += 1
	await host.get_tree().process_frame
	_expect(game.hud.end_root.visible and game.hud.end_title.text == "CAUGHT" and not game.hud.end_next.visible and NightWatchSave.cleared_levels("bedroom").is_empty(), "the loss card is wrong, or a loss saved a clear")
	game.queue_free()
	await host.get_tree().process_frame
	# a win saves a clear for this mode only and opens the next shift
	game = _make(host, 1, 5)
	await host.get_tree().process_frame
	game.sim.levels = QUIET.duplicate()
	game.sim.elapsed = NightWatchData.NIGHT_MS - 150.0
	game.advance_ms(200.0)
	_expect(game.state == BedroomGame.State.WON and game.hud.end_title.text == "NIGHT 1 COMPLETE" and game.hud.end_next.visible, "the win card is wrong")
	_expect(NightWatchSave.cleared_levels("bedroom") == [1] and NightWatchSave.level_open("bedroom", 2) and not NightWatchSave.level_open("bedroom", 3) and NightWatchSave.cleared_levels("lure").is_empty(), "the win did not save under bedroom and open Night 2")
	game.queue_free()
	await host.get_tree().process_frame
	game = _make(host, 6, 5)
	await host.get_tree().process_frame
	game.sim.levels = QUIET.duplicate()
	game.sim.elapsed = NightWatchData.NIGHT_MS - 150.0
	game.advance_ms(200.0)
	_expect(game.state == BedroomGame.State.WON and not game.hud.end_next.visible and NightWatchSave.cleared_levels("bedroom") == [1, 6], "the last shift offers a next card, or was not saved")
	game.queue_free()
	await host.get_tree().process_frame
	# Retry replays the seed
	var a1 := _make(host, 5, 31337)
	await host.get_tree().process_frame
	var log1 := _scene_log(a1)
	a1.queue_free()
	await host.get_tree().process_frame
	var a2 := _make(host, 5, 31337)
	await host.get_tree().process_frame
	_expect(log1 == _scene_log(a2) and log1.length() > 0, "the same seed did not replay the same shift in the scene")
	a2.queue_free()
	await host.get_tree().process_frame
	# Custom Night: the sliders are the levels (Night 1's timings); a win saves a score and the preset's star
	var sliders := {"loxelle": 15, "javelle": 0, "haelith": 0}
	game = _make(host, 1, 77, sliders)
	await host.get_tree().process_frame
	_expect(game.is_custom and game.sim.is_custom and game.sim.base_level("loxelle") == 15 and game.sim.base_level("javelle") == 0 and game.hud.night_label.text == "CUSTOM NIGHT", "the Custom Night sliders did not feed the rules")
	game.sim.levels = QUIET.duplicate()
	game.sim.elapsed = NightWatchData.NIGHT_MS - 150.0
	game.advance_ms(200.0)
	_expect(game.state == BedroomGame.State.WON and NightWatchSave.best_score("bedroom") == 15 * NightWatchModesData.POINTS_PER_LEVEL and NightWatchSave.stars("bedroom") == ["closet-door"], "the Custom Night win did not save the score and the preset's star")
	_expect(NightWatchSave.cleared_levels("bedroom") == [1, 6], "a Custom Night win changed the cleared shifts")
	game.queue_free()
	await host.get_tree().process_frame
	NightWatchSave.reset()
	NightWatchSave.path = NightWatchSave.DEFAULT_PATH
	NightWatchSession.start(1)


func _scene_log(game: BedroomGame) -> String:
	var out := []
	for i in 600:
		for e in game.sim.step(100.0, _input(i)):
			out.append("%d:%s:%s" % [i, e["type"], String(e.get("id", e.get("by", "")))])
	return ",".join(out)
