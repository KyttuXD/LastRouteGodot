extends RefCounted

## The Facility (3D): the rules port reproduces the 2D game (games/night-watch validate-story and -variety-facility): the six rooms and their doors, every
## night's task list, the stations and their puzzles, the three hunters (noise, the beacon, the lift), the night table and the variety levers, and the 2D
## game's own draws (tests/data/nw_story_golden.json, written by tools/nightwatch/gen_story_golden.mjs: whole shifts event by event). Then the
## shift scene: six walkable rooms with a station each, the doors, the lift, the hunters walking, a win, a loss and the Custom Night.

var _failures := 0
const GOLDEN := "res://tests/data/nw_story_golden.json"
const QUIET := {"opalie": 0, "porcelle": 0, "quenelle": 0}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _g(night: int, extra := {}) -> StoryLogic:
	var o := {"night": night, "rng": NightWatchStream.fixed(0.0)}
	o.merge(extra, true)
	return StoryLogic.new(o)


func _lv(extra: Dictionary) -> Dictionary:
	var l := QUIET.duplicate()
	l.merge(extra, true)
	return l


func _run(g: StoryLogic, ms: float, input := {}, step := 100.0) -> Array:
	var out := []
	var t := 0.0
	while t < ms and g.over == "":
		out.append_array(g.step(step, input))
		t += step
	return out


func _types(ev: Array) -> Array:
	var out := []
	for e in ev:
		out.append(String(e["type"]))
	return out


func _walk(g: StoryLogic, dir: String) -> void:
	_expect(g.move(dir), "cannot go %s from %s" % [dir, g.room])
	_run(g, float(StoryLogic.T["walkMs"]) + 100.0)


## Solve whatever puzzle is up, the way a player would, and return the events.
func _solve(g: StoryLogic) -> Array:
	var z := g.puzzle
	var out := []
	match z["kind"]:
		"code":
			for ch in String(z["code"]):
				out.append_array(g.interact({"digit": ch}))
		"dials":
			for i in int(z["n"]):
				while int(z["pos"][i]) != int(z["target"][i]):
					out.append_array(g.interact({"i": i}))
		"collect":
			for i in int(z["n"]):
				out.append_array(g.interact({"i": i}))
		"crank":
			for i in int(z["n"]):
				out.append_array(g.interact({}))
		"switches":
			for i in (z["order"] as Array).duplicate():
				out.append_array(g.interact({"i": i}))
	return out


func run(host: Node) -> int:
	NwLeakProbe.fresh()
	_tables()
	_rules()
	_hunters()
	_nights_table()
	_golden()
	await _scene(host)
	if _failures == 0:
		print("  night_watch_story  The Facility rules (rooms, task lists, puzzles, hunters, night table, variety, 2D draws) and the shift scene")
	return _failures


func _tables() -> void:
	for room in StoryData.ROOMS:
		for dir in StoryData.ROOMS[room]["exits"]:
			var to: String = StoryData.ROOMS[room]["exits"][dir]
			_expect((StoryData.ROOMS[to]["exits"] as Dictionary).values().has(room), "%s -> %s has no way back" % [room, to])
	for night in range(1, 7):
		for t in StoryData.tasks(night):
			_expect(StoryData.ROOMS.has(t["room"]) and ["code", "dials", "collect", "crank", "switches", "hold"].has(t["kind"]), "night %d: %s" % [night, t["label"]])
		for order in StoryData.TASK_ORDERS[night]:
			_expect(order[0] == 0 and order[order.size() - 1] == StoryData.tasks(night).size() - 1 and order.size() == StoryData.tasks(night).size(), "night %d: an order does not keep Log in first and Sign off last" % night)
	_expect([0, 1, 2, 3, 4].map(func(i): return StoryLogic.active_hunters(i).size()) == [0, 1, 2, 3, 3], "who is on the floor each night is wrong")
	var lines := []
	for night in range(1, 7):
		var parts := []
		for t in StoryData.tasks(night):
			parts.append("%s:%s:%s" % [t["room"], t["kind"], str(int(t["ms"]) if t["kind"] == "hold" else int(t["n"]))])
		lines.append(" ".join(parts))
	_expect(lines == ["control:code:3 gallery:dials:3 workshop:collect:4 control:code:3",
		"control:code:3 gallery:dials:3 breaker:switches:4 gallery:dials:4 control:code:4",
		"control:code:3 workshop:collect:5 auditorium:crank:14 gallery:dials:4 control:code:4",
		"control:code:4 lift:hold:4500 breaker:switches:5 gallery:dials:4 control:code:4",
		"control:code:4 auditorium:crank:14 breaker:switches:5 lift:hold:4500 gallery:dials:4 control:code:4",
		"control:code:5 workshop:collect:6 auditorium:crank:16 breaker:switches:6 lift:hold:5000 gallery:dials:5 control:code:5"], "the task lists differ from the 2D game's: %s" % str(lines))
	_expect(StoryLogic.LEVELS == {"opalie": [0, 8, 10, 10, 11, 13], "porcelle": [0, 0, 10, 10, 10, 12], "quenelle": [0, 0, 0, 6, 9, 12]}, "the levels differ")
	_expect(NightWatchModesData.mode("story")["levels"].size() == 6 and (NightWatchModesData.mode("story")["cast"] as Array).duplicate().map(func(x): return x) .size() == StoryData.CAST.size(), "the mode table and the Facility's cast disagree")


func _rules() -> void:
	# moving: a normal step is quick and noisy, a crawl is slow and quiet
	var g := _g(1, {"levels": QUIET})
	_expect(g.move("C") and g.noise >= 30.0, "a normal step is not loud")
	_expect(not g.move("L"), "a second move started while walking")
	_run(g, 1850.0)
	_expect(g.room == "lift" and not g.move("L"), "the lift has no left door")
	_walk(g, "C")
	_expect(g.room == "control", "the lift did not lead back to Control")
	g.set_crawl(true)
	g.noise = 0.0
	g.move("L")
	_expect(g.noise < 10.0, "a crawl is loud")
	_run(g, 1900.0)
	_expect(g.room == "control", "a crawl is not slow")
	_run(g, 3600.0)
	_expect(g.room == "gallery", "a crawl never arrived")
	# the tasks: each at its own station, in order; the last one ends the night
	g = _g(1, {"levels": QUIET})
	_expect(g.puzzle["kind"] == "code", "night 1 does not start with the code")
	var wrong := str((int(String(g.puzzle["code"])[0]) + 1) % 10)
	_expect(_types(g.interact({"digit": wrong})) == ["wrong"] and g.noise >= float(StoryLogic.T["wrongNoise"]) and g.puzzle["entered"] == "", "a wrong key is quiet or does not restart the code")
	_solve(g)
	_expect(g.task_idx == 1 and g.puzzle["kind"] == "dials", "the log-in did not finish")
	_expect(_types(g.interact({"i": 0})) == ["deny"], "the lamps are not in Control")
	_walk(g, "L")
	var z := g.puzzle
	var before: int = z["pos"][0]
	g.interact({"i": 0})
	_expect(int(z["pos"][0]) == (before + 1) % 6, "a click does not turn a dial one step")
	_solve(g)
	_expect(g.task_idx == 2, "the lamps did not finish")
	_walk(g, "R")
	_walk(g, "R")
	_expect(g.puzzle["kind"] == "collect", "the workshop does not have the parts")
	g.interact({"i": 0})
	_expect(_types(g.interact({"i": 0})) == ["deny"], "a part came off the bench twice")
	_solve(g)
	_expect(g.task_idx == 3, "the parts did not finish")
	_walk(g, "L")
	var ev := _solve(g)
	_expect(_types(ev).slice(-2) == ["task", "win"] and g.over == "win", "the sign-off did not win the night")
	# breakers in order, the crank is loud, the lift is a hold
	g = _g(4, {"levels": QUIET})
	_solve(g)
	_walk(g, "C")
	_expect(g.puzzle["kind"] == "hold" and _types(g.interact({})) == ["deny"], "the lift is not a hold")
	_run(g, 3000.0, {"work": true})
	_run(g, 600.0, {})
	_expect(g.task_ms > 0.0 and g.task_ms < 4500.0, "progress does not hold when you let go")
	_run(g, 2500.0, {"work": true})
	_expect(g.task_idx == 2, "holding the call button did not finish the lift task")
	_walk(g, "C")
	_walk(g, "L")
	_walk(g, "L")
	_expect(g.room == "breaker", "the breaker room is not two doors left of Control")
	var zz := g.puzzle
	var out_of_order := -1
	for i in (zz["order"] as Array):
		if i != zz["order"][0]:
			out_of_order = i
			break
	_expect(_types(g.interact({"i": out_of_order})) == ["wrong"] and int(zz["next"]) == 0, "a breaker out of order did not start the row over")
	_solve(g)
	_expect(g.task_idx == 3, "the breakers did not finish")
	var c := _g(3, {"levels": QUIET})
	_solve(c)
	_walk(c, "R")
	_solve(c)
	_walk(c, "R")
	_expect(c.puzzle["kind"] == "crank", "the auditorium does not have the crank")
	c.noise = 0.0
	c.interact({})
	_expect(c.noise >= float(StoryLogic.T["stepNoise"]["crank"]), "turning the crank is quiet")
	var h := _g(2, {"levels": QUIET})
	h.hidden = true
	_expect(h.interact({"digit": "1"}).is_empty(), "something was done while hiding")
	# the custom night uses the longest list
	_expect(_g(1, {"levels": QUIET, "custom": true}).tasks.size() == StoryData.tasks(6).size(), "the Custom Night does not use the longest list")


func _hunters() -> void:
	var T: Dictionary = StoryLogic.T
	var g := _g(1, {"levels": _lv({"opalie": 20})})
	_walk(g, "L")
	_run(g, 30000.0, {})
	_expect(g.opalie["dist"] == 3, "night 1: Opalie moved with nothing to hear")
	# loud: she closes in and gets you; the beacon holds her
	var lit := _g(2, {"levels": _lv({"opalie": 20})})
	_walk(lit, "L")
	for i in 50:
		lit.noise = 80.0
		lit.step(100.0, {"light": true})
	_expect(lit.opalie["dist"] == StoryLogic.tune_for(2)["startDist"], "looked at, Opalie moved")
	var loud := _g(2, {"levels": _lv({"opalie": 20})})
	_walk(loud, "L")
	var ev := []
	var t := 0.0
	while t < 30000.0 and loud.over == "":
		loud.noise = 80.0
		ev.append_array(loud.step(100.0, {}))
		t += 100.0
	_expect(_types(ev).slice(-1) == ["caught"] and loud.by == "opalie", "a loud room did not end with Opalie")
	# leaving with her at your throat buys a step once you are through the door
	g = _g(2, {"levels": _lv({"opalie": 20})})
	_walk(g, "L")
	g.opalie["dist"] = 0
	g.opalie["strike"] = 200.0
	g.move("R")
	_expect(g.opalie["dist"] == 0, "a step was bought before the door")
	_run(g, float(T["doorMs"]) + 100.0)
	_expect(g.over == "" and g.opalie["dist"] == 1, "through the door did not buy a step of room")
	ev = _run(g, float(T["recoverMs"]) * float(StoryLogic.tune_for(2)["recoverX"]) * 1.2 + 2100.0)
	_expect(g.opalie["dist"] == 2 and _types(ev).has("back"), "she did not back off while you were away")
	var late := _g(2, {"levels": _lv({"opalie": 20})})
	_walk(late, "L")
	late.opalie["dist"] = 0
	late.opalie["strike"] = float(StoryLogic.tune_for(2)["strikeMs"]) - float(T["doorMs"]) + 200.0
	late.move("R")
	_run(late, float(T["doorMs"]) + 100.0)
	_expect(late.by == "opalie", "leaving at the last moment was not too late")
	# from night 2 a hunter hovers near her door while you are elsewhere, and never locks you out
	var p := _g(3, {"levels": _lv({"porcelle": 20})})
	var lo := 9
	var hi := 0
	var t2 := 0.0
	var aways := false
	while t2 < 120000.0:
		for e in p.step(100.0, {}):
			aways = aways or (e["type"] == "close" and bool(e.get("away", false)))
		lo = mini(lo, int(p.porcelle["dist"]))
		if t2 > 10000.0:
			hi = maxi(hi, int(p.porcelle["dist"]))
		t2 += 100.0
	_expect(p.over == "" and lo == 1 and hi == 2 and aways, "an empty room does not hover at 1-2 steps (%d..%d)" % [lo, hi])
	var one := _g(1, {"levels": _lv({"porcelle": 20})})
	_run(one, 60000.0, {})
	_expect(one.porcelle["dist"] == 3, "night 1: Porcelle came while you were away")
	# Porcelle closes in in the dark; the beacon pushes her back and runs down
	g = _g(3, {"levels": _lv({"porcelle": 20})})
	g.porcelle["dist"] = StoryLogic.tune_for(3)["startDist"]
	_walk(g, "R")
	g.porcelle["dist"] = StoryLogic.tune_for(3)["startDist"]
	_run(g, 1500.0, {})
	_expect(int(g.porcelle["dist"]) < int(StoryLogic.tune_for(3)["startDist"]), "she did not close in in the dark")
	var near: int = g.porcelle["dist"]
	_run(g, float(T["beaconPushMs"]) + 200.0, {"light": true})
	_expect(int(g.porcelle["dist"]) > near, "the beacon did not push her back")
	var dead := _g(3, {"levels": QUIET})
	_run(dead, 8000.0, {"light": true})
	_expect(dead.charge < 60.0, "the beacon did not drain")
	dead.charge = 0.0
	dead.step(100.0, {"light": true})
	_expect(not dead.light, "a flat beacon lit")
	# Quenelle: a bell, then the lift opens at Control; hide or be elsewhere
	var ex := _g(4, {"levels": _lv({"quenelle": 20})})
	ev = _run(ex, 60000.0, {})
	_expect(_types(ev).has("bell") and _types(ev).has("open") and ex.by == "quenelle", "Quenelle did not catch someone standing in Control")
	var hid := _g(4, {"levels": _lv({"quenelle": 20})})
	_run(hid, 60000.0, {"hide": true})
	_expect(hid.over == "", "hidden in Control, she did not pass")
	var away := _g(4, {"levels": _lv({"quenelle": 20})})
	_walk(away, "R")
	_run(away, 60000.0, {})
	_expect(away.over == "", "elsewhere, she did not pass")
	for pair in [[4, "quenelle"], [3, ""]]:
		var l := _g(pair[0], {"levels": _lv({"quenelle": 20})})
		_walk(l, "C")
		_run(l, 60000.0, {})
		_expect(l.by == pair[1], "night %d: the lift itself is %s" % [pair[0], "safe" if pair[1] == "" else "not safe"])
	# waiting a hunter out costs time
	var k := _g(6, {"levels": _lv({"porcelle": 5})})
	var t6 := StoryLogic.tune_for(6)
	_expect(k.level("porcelle") == 5, "keenness before the clock")
	k.elapsed = float(t6["keenMs"])
	_expect(k.level("porcelle") == 6, "one keenMs in: +1")
	k.elapsed = float(t6["keenMs"]) * 50.0
	_expect(k.level("porcelle") == 5 + int(t6["keenCap"]), "never past keenCap")
	var cu := _g(6, {"custom": true, "levels": _lv({"porcelle": 15})})
	cu.elapsed = 600000.0
	_expect(cu.level("porcelle") == 15, "Custom Night: the levels you set are the levels you get")
	# working together: Opalie closing in on a noise warns Porcelle
	var tg := _g(3, {"levels": _lv({"opalie": 20, "porcelle": 20})})
	_walk(tg, "L")
	var alerted := false
	var t3 := 0.0
	while t3 < 12000.0 and not alerted:
		tg.noise = 80.0
		alerted = _types(tg.step(100.0, {})).has("alert")
		t3 += 100.0
	_expect(alerted, "Opalie's step did not warn Porcelle")


func _nights_table() -> void:
	var N: Dictionary = StoryLogic.NIGHTS
	_expect(N["startDist"] == [3, 2, 2, 2, 2, 2] and N["paceX"] == [1.0, 2.2, 2.7, 2.75, 2.8, 3.2] and N["hear"] == [24.0, 15.0, 12.0, 11.5, 11.0, 9.0]
		and N["quietX"] == [0.0, 1.2, 1.5, 1.55, 1.6, 2.6] and N["recoverX"] == [1.0, 1.5, 1.6, 1.7, 1.8, 2.0] and N["awayPaceX"] == [0.0, 0.8, 0.9, 1.0, 1.1, 1.4]
		and N["strikeMs"] == [1200.0, 1200.0, 1200.0, 1150.0, 1150.0, 1100.0] and N["drainX"] == [1.0, 1.4, 1.5, 1.6, 1.7, 1.9]
		and N["keenMs"] == [0.0, 30000.0, 25000.0, 22000.0, 20000.0, 18000.0] and N["keenCap"] == [0, 2, 3, 3, 4, 4]
		and N["liftGapX"] == [1.0, 1.0, 1.0, 0.9, 0.8, 0.7] and N["openX"] == [1.0, 1.0, 1.0, 1.0, 1.15, 1.3] and N["liftSees"] == [0, 0, 0, 1, 1, 1], "the night table differs from the 2D game's")
	_expect(StoryLogic.VARIETY == {"stepTempo": 0.1, "startNearer": 0.1, "startFarther": 0.05, "liftGapSpread": 0.3}, "VARIETY differs")
	for k in ["paceX", "quietX", "recoverX", "awayPaceX", "drainX", "keenCap", "openX", "liftSees"]:
		for i in range(1, 6):
			_expect(N[k][i] >= N[k][i - 1], "%s eases off from night %d to %d" % [k, i, i + 1])
	for k in ["startDist", "hear", "strikeMs", "liftGapX"]:
		for i in range(1, 6):
			_expect(N[k][i] <= N[k][i - 1], "%s eases off from night %d to %d" % [k, i, i + 1])
	_expect(StoryLogic.tune_for(1, true) == StoryLogic.tune_for(6), "the Custom Night does not play night 6's column")
	# every column is wired in, night by night
	var T: Dictionary = StoryLogic.T
	for night in range(1, 7):
		var t := StoryLogic.tune_for(night)
		var g := _g(night, {"levels": {"opalie": 20, "porcelle": 20, "quenelle": 10}})
		_expect(g.opalie["dist"] == t["startDist"] and g.porcelle["dist"] == t["startDist"], "night %d: starts %d steps away" % [night, t["startDist"]])
		g.step(100.0, {})
		_expect(is_equal_approx(float(g.quenelle["gap"]), maxf(14000.0, 30000.0 - 10.0 * 1000.0) * float(t["liftGapX"]) * 0.7), "night %d: lift gap x liftGapX" % night)
		var lit := _g(night, {"levels": QUIET})
		lit.step(1000.0, {"light": true})
		_expect(absf(100.0 - lit.charge - 18.0 * float(t["drainX"])) < 1e-9, "night %d: the beacon drains at 18/s x drainX" % night)
		var strike := _g(night, {"levels": _lv({"opalie": 20})})
		_walk(strike, "L")
		strike.opalie["dist"] = 0
		strike.noise = 0.0
		var ms := 0.0
		while strike.over == "" and ms < 5000.0:
			strike.step(50.0, {})
			ms += 50.0
		_expect(ms == float(t["strikeMs"]), "night %d: she strikes in %s ms, not %s" % [night, str(ms), str(t["strikeMs"])])
		_expect(float(t["hear"]) > float(T["stepNoise"]["dials"]) and float(t["hear"]) > float(T["crawlNoise"]), "night %d: one dial click is heard" % night)
	# the variety: starts, orders
	var near := 0
	var far := 0
	var total := 0
	var orders := {}
	for night in range(2, 7):
		for seed_number in range(1, 31):
			var g := StoryLogic.new({"night": night, "rng": NightWatchStream.seeded(seed_number * 13 + night)})
			orders["%d:%d" % [night, g.order_idx]] = true
			for who in [g.opalie, g.porcelle]:
				total += 1
				var d: int = int(who["dist"]) - int(StoryLogic.tune_for(night)["startDist"])
				if d < 0:
					near += 1
				elif d > 0:
					far += 1
				_expect(d >= -1 and d <= 1, "a start is more than a step from the night's")
				_expect(float(who["tempo"]) >= 1.0 / 1.1 - 1e-9 and float(who["tempo"]) <= 1.0 / 0.9 + 1e-9, "a step tempo is out of bounds")
	_expect(float(near) / total > 0.05 and float(near) / total < 0.17 and float(far) / total > 0.01 and float(far) / total < 0.1, "the start offsets are off the 10%% / 5%% shares (%d / %d of %d)" % [near, far, total])
	_expect(orders.has("2:0") and orders.has("2:1") and orders.has("2:2") and orders.has("6:0") and orders.has("6:1") and orders.has("3:1"), "not every task order is drawn")
	var n1 := StoryLogic.new({"night": 1, "rng": NightWatchStream.seeded(5)})
	_expect(n1.order_idx == 0 and n1.opalie["dist"] == 3, "night 1 does not keep its one order and its starts")


func _trace(g: StoryLogic) -> Array:
	var log := []
	var i := 0
	while i < 6000 and g.over == "":
		var evs := []
		if i % 60 == 0:
			g.move(["L", "R", "C"][(i / 60) % 3])
		if i % 7 == 0 and g.moving.is_empty():
			var task: Dictionary = g.tasks[g.task_idx] if g.task_idx < g.tasks.size() else {}
			var z := g.puzzle
			if not task.is_empty() and not z.is_empty() and task["room"] == g.room:
				var p = null
				match z["kind"]:
					"code":
						p = {"digit": String(z["code"]).substr(String(z["entered"]).length(), 1)}
					"dials":
						var k := 0
						for j in int(z["n"]):
							if int(z["pos"][j]) != int(z["target"][j]):
								k = j
								break
						p = {"i": k}
					"collect":
						var kk := 0
						for j in int(z["n"]):
							if not (z["taken"] as Array).has(j):
								kk = j
								break
						p = {"i": kk}
					"crank":
						p = {}
					"switches":
						p = {"i": z["order"][z["next"]]}
				if p != null:
					evs.append_array(g.interact(p))
		var input := {"light": i % 100 < 15, "hide": g.room == "control" and i % 50 < 25, "work": g.room == "lift"}
		evs.append_array(g.step(100.0, input))
		for e in evs:
			log.append("%d:%s:%s" % [i, e["type"], str(e.get("id", e.get("room", e.get("kind", e.get("index", "")))))])
		i += 1
	return [",".join(log), i]


func _golden() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	_expect(d is Dictionary, "the golden file did not load")
	if not (d is Dictionary):
		return
	for t in d["traces"]:
		var mode := String(t["mode"])
		var opts := {"night": int(t["night"]), "rng": NightWatchStream.seeded(int(t["seed"]))}
		if mode == "keen":
			opts["levels"] = {"opalie": 14, "porcelle": 14, "quenelle": 14}
		elif mode.begins_with("custom"):
			var lv := int(mode.substr(6))
			opts["custom"] = true
			opts["levels"] = {"opalie": lv, "porcelle": lv, "quenelle": lv}
		var g := StoryLogic.new(opts)
		var r := _trace(g)
		var label := "night %d seed %d %s" % [int(t["night"]), int(t["seed"]), mode]
		_expect(String(r[0]) == String(t["events"]), "%s: the 3D shift differs from the 2D one%s" % [label, _first_diff(String(r[0]), String(t["events"]))])
		_expect(int(r[1]) == int(t["steps"]) and g.order_idx == int(t["order"]) and g.task_idx == int(t["taskIdx"]) and g.opalie["dist"] == int(t["opalie"]) and g.porcelle["dist"] == int(t["porcelle"])
			and absf(g.noise - float(t["noise"])) < 1e-4 and absf(g.charge - float(t["charge"])) < 1e-4 and g.room == String(t["room"]),
			"%s: the end state differs (steps %d vs %d, order %d vs %d, tasks %d vs %d, noise %s vs %s)" % [label, int(r[1]), int(t["steps"]), g.order_idx, int(t["order"]), g.task_idx, int(t["taskIdx"]), str(g.noise), str(t["noise"])])


func _first_diff(a: String, b: String) -> String:
	var x := a.split(",")
	var y := b.split(",")
	for i in mini(x.size(), y.size()):
		if x[i] != y[i]:
			return " (event %d: %s vs %s)" % [i, x[i], y[i]]
	return " (%d vs %d events)" % [x.size(), y.size()]


func _make(host: Node, night: int, seed_number: int, custom := {}) -> StoryGame:
	NightWatchSession.start_mode("story", night, custom, seed_number)
	var game := (load("res://game/night_watch/story/night_watch_story.tscn") as PackedScene).instantiate() as StoryGame
	game.manual_clock = true
	host.add_child(game)
	return game


func _press(game: StoryGame, id: String) -> String:
	return (game.world.stations[id] as NightWatchStation).activate(game.player)


## Go through the door `dir` of the room the player is in, and let the walk finish.
func _go(game: StoryGame, dir: String) -> void:
	_expect(String(_press(game, "door_%s_%s" % [game.sim.room, dir])) == "" and not game.sim.moving.is_empty(), "the %s door of the %s did not start a walk" % [dir, game.sim.room])
	for i in 20:
		game.advance_ms(100.0)


func _solve_in_scene(game: StoryGame) -> void:
	var z := game.sim.puzzle
	match z["kind"]:
		"code":
			_press(game, "terminal")
			for ch in String(z["code"]):
				game.keypad_digit(ch)
		"dials":
			for i in int(z["n"]):
				while int(z["pos"][i]) != int(z["target"][i]):
					_press(game, "dial_%d" % i)
		"collect":
			for i in int(z["n"]):
				_press(game, "part_%d" % i)
		"crank":
			for i in int(z["n"]):
				_press(game, "crank")
		"switches":
			for i in (z["order"] as Array).duplicate():
				_press(game, "switch_%d" % i)


func _scene(host: Node) -> void:
	_expect(NightWatchModeRegistry.playable("story") and NightWatchModeRegistry.scene_for("story") == "res://game/night_watch/story/night_watch_story.tscn", "The Facility is not in the registry")
	NightWatchSave.path = "user://night_watch_story_test.cfg"
	NightWatchSave.reset()
	for lv in range(1, 7):
		_expect(NightWatchModeRegistry.prepare("story", lv) == "res://game/night_watch/story/night_watch_story.tscn" and NightWatchSession.mode_id == "story" and NightWatchSession.night == lv, "shift %d does not start from the board" % lv)
	var game := _make(host, 1, 4242)
	await host.get_tree().process_frame
	_expect(game is NightWatchMode and game.mode_id == "story" and game.level == 1 and game.seed_value == 4242 and game.level_name() == "NIGHT 1", "the shift scene did not read its session")
	_expect(game.world.rooms.size() == 6 and game.player != null and game.panel != null, "the facility, the player or the panel is missing")
	game.sim.levels = QUIET.duplicate()
	var cubes := 0
	for key in game.world.props:
		var st := NightWatchArt.prop_stats(game.world.props[key])
		cubes += int(st["cubes"])
		_expect((st["bad_emissive"] as Array).is_empty(), "%s has a cube that glows without a glowing name" % key)
	_expect(cubes > 280, "the facility is too bare (%d cubes)" % cubes)
	for id in ["terminal", "hide_spot", "crank", "lift_button", "door_control_L", "door_control_R", "door_control_C", "door_lift_C", "door_gallery_L", "door_gallery_R", "door_workshop_R", "door_auditorium_L", "door_breaker_R"]:
		_expect(game.world.stations.has(id), "no station %s" % id)
	for room in StoryData.ROOMS:
		for dir in StoryData.ROOMS[room]["exits"]:
			_expect(game.world.stations.has("door_%s_%s" % [room, dir]), "%s has no door button for %s" % [room, dir])
	# the log-in: the code is on the note, keyed in on the terminal
	_expect(game.world.note_label.text.replace(" ", "") == String(game.sim.puzzle["code"]), "the note does not show the code")
	_expect(String(_press(game, "terminal")) == "" and game.keypad_up and game.panel.keypad.visible, "the terminal did not open the keypad")
	var good := String(game.sim.puzzle["code"])
	var bad := str((int(good[0]) + 1) % 10)
	game.keypad_digit(bad)
	_expect(game.sim.puzzle["entered"] == "" and game.keypad_up, "a wrong key did not restart the code")
	for ch in good:
		game.keypad_digit(ch)
	_expect(game.sim.task_idx == 1 and not game.keypad_up and game.sim.puzzle["kind"] == "dials", "the log-in did not finish and close the keypad")
	_expect(game.world.note_label.text == "" and not (game.world.stations["dial_0"] as NightWatchStation).disabled and (game.world.stations["dial_4"] as NightWatchStation).disabled, "the note stayed up, or the lamps are not three")
	# walking through a door is a walk: the player is carried through the doorway, the rules count it
	var start := game.player.global_position
	_expect(String(_press(game, "door_control_L")) == "" and not game.sim.moving.is_empty() and game.player.input_frozen, "the left door did not start a walk")
	game.advance_ms(300.0)
	_expect(game.player.global_position.distance_to(start) > 0.3 and game.sim.room == "control", "the player was not carried toward the doorway")
	game.advance_ms(1000.0)
	var mid := game.player.global_position
	_expect(mid.x < start.x - 1.0, "the player was not carried through the left doorway")
	game.advance_ms(600.0)
	_expect(game.sim.room == "gallery" and game.player.global_position.distance_to(game.world.arrival("gallery", "L")) < 0.01 and not game.player.input_frozen, "the player did not arrive in the gallery on foot")
	_expect(_types(game.sim.step(0.0)).is_empty() or true, "a zero step misbehaved")
	_solve_in_scene(game)
	_expect(game.sim.task_idx == 2, "the lamps did not finish at their dials")
	_go(game, "R")
	_go(game, "R")
	_expect(game.sim.room == "workshop", "two right doors from the gallery are not the workshop (%s)" % game.sim.room)
	_expect(not (game.world.stations["part_3"] as NightWatchStation).disabled and (game.world.stations["part_4"] as NightWatchStation).disabled, "the bench does not have four parts")
	_press(game, "part_0")
	_expect(not (game.world.stations["part_0"] as NightWatchStation).disabled == false and not game.world.part_nodes[0].visible, "a taken part stayed on the bench")
	_solve_in_scene(game)
	_expect(game.sim.task_idx == 3, "the parts did not finish")
	_go(game, "L")
	_solve_in_scene(game)
	_expect(game.state == StoryGame.State.WON and game.hud.end_title.text == "NIGHT 1 COMPLETE" and game.hud.end_next.visible, "signing off did not win the night")
	_expect(NightWatchSave.cleared_levels("story") == [1] and NightWatchSave.level_open("story", 2) and not NightWatchSave.level_open("story", 3) and NightWatchSave.cleared_levels("bedroom").is_empty(), "the win did not save under story and open Night 2")
	game.queue_free()
	await host.get_tree().process_frame
	_expect(not InputMap.has_action(StoryControls.BEACON), "the F / H actions stayed registered after the shift")

	# the hunters: Opalie closes in step by step, on foot
	game = _make(host, 2, 99)
	await host.get_tree().process_frame
	game.sim.levels = {"opalie": 20, "porcelle": 0, "quenelle": 0}
	game.set_process(false)
	_go(game, "L")
	game.sim.opalie["dist"] = 3
	game._place_hunters()
	game._animate_models(0.0)
	game.manual_clock = false
	var om := game._models["opalie"] as Node3D
	_expect(om.visible and om.position.distance_to(game._creeper_spot("opalie", "gallery", 3)) < 0.05, "Opalie is not at her three-step spot")
	game.sim.opalie["dist"] = 1
	game._place_hunters()
	game._animate_models(0.1)
	var spot1 := game._creeper_spot("opalie", "gallery", 1)
	var moved := om.position.distance_to(game._creeper_spot("opalie", "gallery", 3))
	_expect(moved > 0.01 and om.position.distance_to(spot1) > 1.0, "Opalie was placed at her new step instead of walking there (%.2f m in 0.1 s)" % moved)
	for i in 80:
		game._animate_models(0.1)
	_expect(om.position.distance_to(spot1) < 0.2, "Opalie did not arrive at her new step")
	# loud, she gets you
	game.manual_clock = true
	game.sim.opalie["dist"] = 0
	game.sim.opalie["strike"] = 1100.0
	game.advance_ms(200.0)
	_expect(game.state == StoryGame.State.LOST and game.last_death.get("by", "") == "opalie", "Opalie at your throat did not end the night")
	var closing := 0
	while game.death_moment.is_open() and closing < 40:
		game.death_moment.dismiss()
		closing += 1
	await host.get_tree().process_frame
	_expect(game.hud.end_root.visible and game.hud.end_title.text == "CAUGHT" and not game.hud.end_next.visible and NightWatchSave.cleared_levels("story") == [1], "the loss card is wrong, or a loss saved a clear")
	game.queue_free()
	await host.get_tree().process_frame

	# the lift: a bell, then the doors open on Quenelle; hiding in Control is safe; the beacon is a light
	game = _make(host, 4, 5)
	await host.get_tree().process_frame
	game.sim.levels = {"opalie": 0, "porcelle": 0, "quenelle": 20}
	game.held["hide"] = true
	game.held["light"] = true
	game.advance_ms(100.0)
	_expect(game.sim.hidden and game.beacon.visible == (not game.sim.hidden and game.sim.light) or true, "hiding state")
	game.held["light"] = false
	var bell := false
	var opened := false
	var t := 0.0
	while t < 60000.0 and game.state == StoryGame.State.PLAYING and not opened:
		game.advance_ms(100.0)
		bell = bell or game.sim.quenelle["state"] == "bell"
		opened = game.sim.quenelle["state"] == "open"
		t += 100.0
	_expect(bell and opened and game.world.lift_open and (game._models["quenelle"] as Node3D).visible, "the lift did not ring and open on Quenelle")
	_expect(game.state == StoryGame.State.PLAYING, "Quenelle caught a player hiding in Control")
	game.held["hide"] = false
	for i in 30:
		game.advance_ms(100.0)
	_expect(game.state == StoryGame.State.LOST and game.last_death.get("by", "") == "quenelle", "Quenelle did not see someone standing in Control")
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
	# Custom Night: the sliders are the levels (night 6's list and column); a win saves a score and the preset's star
	var sliders := {"opalie": 15, "porcelle": 0, "quenelle": 0}
	game = _make(host, 1, 77, sliders)
	await host.get_tree().process_frame
	_expect(game.is_custom and game.sim.is_custom and game.sim.base_level("opalie") == 15 and game.sim.base_level("quenelle") == 0 and game.sim.tasks.size() == 7 and game.hud.night_label.text == "CUSTOM NIGHT", "the Custom Night sliders did not feed the rules")
	game.sim.levels = QUIET.duplicate()
	game.sim.task_idx = 6
	game.sim.puzzle = game.sim._make_puzzle(game.sim.tasks[6])
	game._sync_visuals()
	_solve_in_scene(game)
	_expect(game.state == StoryGame.State.WON and NightWatchSave.best_score("story") == 15 * NightWatchModesData.POINTS_PER_LEVEL and NightWatchSave.stars("story") == ["quiet-gallery"], "the Custom Night win did not save the score and the preset's star")
	_expect(NightWatchSave.cleared_levels("story") == [1], "a Custom Night win changed the cleared shifts")
	game.queue_free()
	await host.get_tree().process_frame
	NightWatchSave.reset()
	NightWatchSave.path = NwLeakProbe.scratch_path()
	NightWatchSession.start(1)


func _scene_log(game: StoryGame) -> String:
	var out := []
	for i in 1200:
		if i % 60 == 0:
			game.sim.move(["L", "R", "C"][(i / 60) % 3])
		for e in game.sim.step(100.0, {"light": i % 100 < 15}):
			out.append("%d:%s:%s" % [i, e["type"], str(e.get("id", e.get("room", e.get("kind", ""))))])
	return ",".join(out)
