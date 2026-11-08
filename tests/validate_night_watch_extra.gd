extends RefCounted

## Night Watch, Open Air (mode `extra`, code `openair`): the rules port reproduces the 2D numbers (its Open Air validators), a watch replays the same for a seed, every watch can be won and lost, the hunters have routes to walk, and
## the shift scene starts from the Shift Board, saves the clear, opens the next watch and runs a Custom Night's watches in a row.
## (Save and restore of a watch in progress is the framework's resume milestone and is not ported here.)

const L := preload("res://game/night_watch/openair/openair_logic.gd")
const D := preload("res://game/night_watch/openair/openair_data.gd")

## A pacer that is always due (one step a frame) and one that never is, as the 2D tests' `always` and `never`.
class Always:
	extends RefCounted
	func step(_dt, _lvl) -> bool:
		return true
	func reset() -> void:
		pass
	func skip(_ms) -> void:
		pass


class Never:
	extends RefCounted
	func step(_dt, _lvl) -> bool:
		return false
	func reset() -> void:
		pass
	func skip(_ms) -> void:
		pass


var _failures := 0
var _hit := func() -> float: return 0.0     # every roll succeeds, sides are L
var _miss := func() -> float: return 0.99   # no roll succeeds, sides are R


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _types(ev: Array) -> Array:
	var out := []
	for e in ev:
		out.append(String(e["type"]))
	return out


func _run(g: L, ms: float, input := {}, step := 100.0) -> Array:
	var out := []
	var t := 0.0
	while t < ms and g.over == "":
		out.append_array(g.step(step, input))
		t += step
	return out


## A watch with the variety draws set to their listed values (the 2D validator's wrapper), so the listed timings can be pinned.
func _g(watch: int, rng := Callable(), level := -1, vl := -1, ql := -1, seed_number := 0, infinite := false) -> L:
	var g := L.new(watch, seed_number, level, vl, ql, rng, infinite)
	for h in [g.v, g.q]:
		if h != null:
			h.pacer.reset()
	if watch == 0:
		g.gust = L.GUST_MS
	if not g.weather.is_empty():
		g.weather["lasts"] = float(D.WEATHER[watch]["lastsMs"])
	if watch == 1:
		g.can_at = L.CAN_FIRST_MS
		g.cold_mult = 1.0
		g.cold_left = 1e12
	if watch == 2:
		g.mood_kind = "calm"
		g.mood_left = 1e12
	return g


func _camp(o := {}) -> L:
	return _g(2, _miss, int(o.get("level", 0)), int(o.get("vl", 0)), int(o.get("ql", 0)))


func _at_edge(g: L, id: String) -> void:
	var h = g.v if id == "verrine" else g.q
	h.on = true
	h.dist = 0
	h.at_ms = 0.0
	h.push = 0.0
	h.lost = 0.0


func run(host: Node) -> int:
	NwLeakProbe.fresh()
	NwLeakProbe.report(host, "extra")
	_numbers()
	_rooftop()
	_weather_and_bus()
	_campfire()
	_hard_but_fair()
	_custom_and_misc()
	_variety()
	_paths(host)
	_map()
	await _admin(host)
	await _offices(host)
	await _scene(host)
	if _failures == 0:
		print("  night_watch_extra  the 2D numbers, three watches, variety levers, seeded replay, walking routes, the shift scene (board, win, loss, saves, Custom Night chain)")
	return _failures


func _numbers() -> void:
	_expect(D.LEVELS == {"verrine": 9, "wynelle": 8, "ysolde": 8, "quenelle": 13}, "the hunters' levels differ")
	_expect(L.AT_MS == 5200.0 and L.CAMP_AT_MS == 5200.0 and L.LEAVE_MS == 450.0 and L.PUSH_MS == 1500.0 and L.LOST_MS == 2000.0 and L.OUT_GRACE_MS == 10000.0 and L.RELIGHT_MS == 1600.0 and L.GATHER_MS == 2200.0, "the tells and held defences differ")
	_expect(L.PUSH_BACK == 2 and L.LOST_BACK == 1 and L.TENT_PACE == 3.25 and L.BACK_PACE == 1.0 and L.LOW_FIRE == 25.0 and L.LOW_FIRE_BONUS == 3 and L.START_DIST == 3, "the campfire numbers differ")
	_expect(L.GUST_MS == 22000.0 and L.GUST_JITTER_MS == 8000.0 and L.DARK_BONUS == 4 and L.TORCH_DRAIN == 9.0 and L.TORCH_REGEN == 4.0 and L.OIL_BASE == 0.12 and L.OIL_PER_BAR == 0.45 and L.RELIGHT_OIL == 4.0, "the rooftop numbers differ")
	_expect(L.COLD_DRAIN == 1.0 and L.LAMP_WARM == 2.8 and L.LAMP_FUEL == 1.6 and L.CHILL_LINE == 40.0 and L.CHILL_PER_POINT == 0.12 and L.CHILL_RECOVER == 3.0 and L.CAN_EVERY_MS == 17000.0 and L.CAN_FUEL == 35.0 and L.MAX_CANS == 3, "the bus stop numbers differ")
	_expect(L.CAMP_DRAIN == 1.8 and L.LOG_FUEL == 28.0 and L.START_LOGS == 6 and L.FUEL_STEAL == 15.0, "the fire numbers differ")
	_expect(L.ARRIVE_SPREAD_MS == 4000.0 and L.GUST_FIRST_SPREAD == 0.25 and L.SIDE_SWITCH == 0.65 and L.MOOD_EVERY_MS == 45000.0 and L.MOOD_EVERY_SPREAD == 0.33 and L.MOOD_PACE == 1.3 and L.MOOD_CALM == 0.2, "the variety numbers differ (rooftop, campfire)")
	_expect(L.WEATHER_LAST_SPREAD == 0.25 and L.CAN_SPREAD == 0.25 and L.CAN_FIRST_MS == 4000.0 and L.CAN_FIRST_SPREAD == 0.5 and L.COLD_SPREAD == 0.15 and L.COLD_EVERY_MS == 30000.0 and L.COLD_EVERY_SPREAD == 0.33, "the variety numbers differ (weather, bus stop)")
	_expect(D.WEATHER[1] == {"kind": "snow", "everyMs": 34000.0, "lastsMs": 9000.0, "mult": 1.8, "first": 20000.0} and D.WEATHER[2] == {"kind": "rain", "everyMs": 40000.0, "lastsMs": 10000.0, "mult": 2.2, "first": 25000.0}, "the weather differs")
	_expect(D.BUS_MS == 18000.0 and D.WATCH_MS == 270000.0, "the bus or the watch length differ")
	_expect(L.CAMP_AT_MS >= L.PUSH_MS + L.LOST_MS + 1000.0, "there is no second to spare to answer both at the edge")
	_expect(D.SIDES == {"verrine": "L", "quenelle": "R"} and D.PAN["verrine"] == -0.6 and D.PAN["ysolde"] == 0.3, "the sides or the pans differ")
	_expect(D.WATCHES.size() == 3 and D.WATCHES.map(func(w): return w["hunter"]) == ["verrine", "wynelle", "ysolde"], "the watches differ")
	_expect(D.active_hunters(0) == ["verrine"] and D.active_hunters(1) == ["wynelle"] and D.active_hunters(2) == ["ysolde", "verrine", "quenelle"], "who is on the floor differs")
	var modes := NightWatchModesData.mode("extra")
	_expect((modes["levels"] as Array) == ["ROOFTOP", "BUS STOP", "CAMPFIRE"] and int(modes["scored"]) == 3, "the board's shifts are not the three watches")
	# Custom Night: the campfire runs when Ysolde or Quenelle is on, Verrine's slider alone is the rooftop
	_expect(D.custom_watches({"verrine": 5, "wynelle": 0, "ysolde": 9, "quenelle": 0}) == [0, 2], "custom watches (verrine, ysolde)")
	_expect(D.custom_watches({"verrine": 5, "wynelle": 0, "ysolde": 0, "quenelle": 0}) == [0], "custom watches (verrine only)")
	_expect(D.custom_watches({"verrine": 0, "wynelle": 0, "ysolde": 0, "quenelle": 4}) == [2], "custom watches (quenelle only)")
	_expect(D.custom_watches({"verrine": 0, "wynelle": 0, "ysolde": 0, "quenelle": 0}).is_empty(), "custom watches (everyone off)")
	_expect(D.custom_watches({"verrine": 20, "wynelle": 20, "ysolde": 20, "quenelle": 20}) == [0, 1, 2], "custom watches (everyone)")
	# her steps are heard on the side she is coming from
	_expect(D.side_pan("verrine", "L") == -0.6 and D.side_pan("verrine", "R") == 0.6 and D.side_pan("verrine", "") == -0.6 and D.side_pan("quenelle", "R") == 0.6, "the steps' pans differ")
	# Zellia's calls are the shared table (verbatim 2D); the campfire's says how it works, in her words, and matches the rules
	for n in 3:
		_expect(not (NightWatchCallsData.for_level("extra", n + 1).get("lines", []) as Array).is_empty(), "watch %d has no call" % (n + 1))
	var text := " ".join(NightWatchCallsData.for_level("extra", 3).get("lines", []))
	for re_text in ["Verrine[^.]*\\bleft\\b", "Quenelle[^.]*\\bright\\b", "\\bQ and E\\b[^.]*\\btorch\\b[^.]*\\bholds her still", "torch on Verrine[^.]*\\bgoes back\\b", "only holds Quenelle[^.]*\\btent with T\\b[^.]*loses the trail", "tent only hides you from Quenelle[^.]*\\. Verrine keeps coming", "Ysolde goes for the logs[^.]*\\. Stay in too long and she looks in", "\\bSpace\\b", "\\bG fetches\\b"]:
		var re := RegEx.new()
		re.compile(re_text)
		_expect(re.search(text) != null, "Zellia's campfire call does not say /%s/" % re_text)
	_expect(not text.to_lower().contains("third") and not text.to_lower().contains("send her off"), "a trace of the old three-scares rule")


func _rooftop() -> void:
	var lit := _g(0, _hit, 20)
	_run(lit, 8000.0, {"torchL": true})
	_expect(lit.v.dist == 3, "looked at, she does not hold still")
	var g := _g(0, _hit, 20)
	_run(g, 9300.0, {"relight": true})
	_expect(g.v.dist == 0, "she is not at the door after three steps (dist %d)" % g.v.dist)
	var ev := _run(g, L.LEAVE_MS + 200.0, {"relight": true, "barL": true})
	_expect(g.v.dist == 2 and _types(ev).has("repelled"), "a barred door does not send her back")
	var open := _g(0, _hit, 20)
	var caught := _run(open, 40000.0, {"relight": true})
	_expect(_types(caught).back() == "caught" and open.by == "verrine" and open.cause == "edge", "an open door does not let her in")
	var windy := _g(0, _miss, 0)
	var e2 := _run(windy, L.GUST_MS + 500.0, {})
	_expect(_types(e2).has("gust") and not windy.lantern, "the wind does not take the lantern")
	var e3 := _run(windy, L.RELIGHT_MS + 300.0, {"relight": true})
	_expect(_types(e3).has("relit") and windy.lantern, "the lantern cannot be relit")
	var torch := _g(0, _miss, 0)
	_run(torch, 5000.0, {"torchL": true})
	_expect(torch.torch < 100.0, "the torch does not drain while held")
	_run(torch, 5000.0, {})
	_expect(torch.torch > 50.0, "the torch does not come back when let go")
	# the lantern's oil
	var calm := _g(0, _miss, 0)
	_run(calm, 20000.0, {})
	var barred := _g(0, _miss, 0)
	_run(barred, 20000.0, {"barL": true, "barR": true})
	_expect(barred.oil < calm.oil - 10.0, "holding both shut does not burn oil")
	var dry := _g(0, _miss, 0)
	dry.oil = 3.0
	_run(dry, L.GUST_MS + 200.0, {"relight": true})
	_run(dry, 5000.0, {"relight": true})
	_expect(not dry.lantern, "no oil, and the lantern lit")
	var no_oil := _g(0, _miss, 0)
	no_oil.oil = 0.0
	_run(no_oil, 500.0, {"barL": true})
	_expect(not no_oil.bars["L"], "with no oil the barrier stays shut")
	# the barrier on the other side does not answer her
	var side := _g(0, _hit, 20)
	side.v.dist = 0
	side.v.side = "L"
	_run(side, L.LEAVE_MS + 120.0, {"barR": true})
	_expect(side.v.dist == 0, "the other barrier answered her")
	# her steps are heard on the side she is coming from
	for pair in [["L", -1.0], ["R", 1.0]]:
		var s := _g(0, _hit, 20)
		s.v.side = pair[0]
		var close := _run(s, 4000.0, {"relight": true}).filter(func(e): return e["type"] == "close")
		_expect(close.size() > 0, "she does not close in from side %s" % pair[0])
		for e in close:
			_expect(e["side"] == pair[0] and signf(D.side_pan(String(e["id"]), String(e["side"]))) == pair[1], "a step from %s pans the wrong way" % pair[0])
	# every watch can be survived with a little effort; the rooftop can be held to dawn
	var roof := L.new(0, 2)
	var t := 0.0
	while t < D.WATCH_MS + 500.0 and roof.over == "":
		t += 100.0
		var v = roof.v
		roof.step(100.0, {"relight": true, "torchL": v.dist > 0 and v.side == "L", "torchR": v.dist > 0 and v.side == "R", "barL": v.dist == 0 and v.side == "L", "barR": v.dist == 0 and v.side == "R"})
	_expect(roof.over == "win", "the rooftop cannot be held to dawn")


func _weather_and_bus() -> void:
	var g := _g(1, _miss, 0)
	_expect(_types(_run(g, float(D.WEATHER[1]["first"]) * 1.3, {})).has("weather"), "a squall does not arrive")
	var calm := _g(1, _miss, 0)
	calm.weather["next"] = 1e9
	var storm := _g(1, _miss, 0)
	storm.weather["next"] = 0.0
	_run(calm, 4000.0)
	_run(storm, 4000.0)
	_expect(storm.warm < calm.warm - 1.0, "the squall does not drain warmth faster")
	var rain := _g(2, _miss, 0, 0, 0)
	rain.weather["next"] = 0.0
	var dry := _g(2, _miss, 0, 0, 0)
	dry.weather["next"] = 1e9
	_run(rain, 4000.0)
	_run(dry, 4000.0)
	_expect(rain.fire < dry.fire - 1.0, "rain does not burn the fire faster")
	_expect(_types(_run(storm, 10100.0)).has("weatherEnd"), "the squall does not pass")
	# the bus: the last eighteen seconds, no weather, the cold lets go
	var dawn := _g(1, _miss, 0, -1, -1, 0, true)
	var warm_run := func(gg: L, ms: float) -> Array:
		var out := []
		var t := 0.0
		while t < ms and gg.over == "":
			t += 100.0
			gg.warm = 100.0
			out.append_array(gg.step(100.0, {}))
		return out
	warm_run.call(dawn, D.WATCH_MS - D.BUS_MS - 200.0)
	_expect(dawn.bus == 0.0, "the bus came early")
	var late: Array = warm_run.call(dawn, 1000.0)
	_expect(_types(late).has("bus") and dawn.bus > 0.0, "the bus does not come up the road")
	_expect(_types(warm_run.call(dawn, D.BUS_MS)).has("win"), "the bus stop is not won at dawn")
	_expect(not dawn.weather["on"], "weather while the bus comes")
	# warmth, the lamp, canisters, the cold
	var cold := _g(1, _miss, 8)
	_run(cold, 60000.0)
	_expect(cold.warm < 45.0 and cold.chill < 10.0, "it does not get cold, or too fast (warm %.1f chill %.1f)" % [cold.warm, cold.chill])
	var ev := _run(cold, 200000.0)
	_expect(_types(ev).back() == "caught" and cold.by == "wynelle" and cold.cause == "cold", "the cold does not take the stop")
	var warm := _g(1, _miss, 8)
	var picked := 0
	var t := 0.0
	while t < D.WATCH_MS + 1000.0 and warm.over == "":
		t += 100.0
		if warm.warm < 55.0 and not warm.lamp:
			warm.act("lamp")
		if warm.warm > 85.0 and warm.lamp:
			warm.act("lamp")
		if not warm.cans.is_empty():
			warm.act("can", {"i": warm.cans[0]})
			picked += 1
		warm.step(100.0)
	_expect(warm.over == "win" and picked >= 3, "a lamp kept to a duty cycle and the canisters do not carry the watch")
	var empty := _g(1, _miss, 8)
	empty.fuel = 0.5
	empty.act("lamp")
	_expect(_types(_run(empty, 1000.0)).has("dry") and not empty.lamp, "an empty tank does not put the lamp out")
	_expect(_g(1, _miss).act("lamp"), "the lamp cannot be lit")


func _campfire() -> void:
	var g := _camp()
	_expect(g.act("log") and g.logs == L.START_LOGS - 1, "a log does not go on the fire")
	var burn := _camp()
	_run(burn, 40000.0)
	_expect(burn.fire < 40.0, "the fire does not burn down")
	_expect(_types(_run(burn, 60000.0)).back() == "caught" and burn.by == "ysolde" and burn.cause == "fire", "a dead fire does not let the dark in")
	var gather := _camp()
	var g1 := _run(gather, L.GATHER_MS + 200.0, {"gather": true})
	_expect(_types(g1).has("gathered") and gather.logs == L.START_LOGS + 1, "fetching wood gives no log")
	var busy := _camp()
	_run(busy, 500.0, {"gather": true, "torchL": true})
	_expect(busy.torch_side == "", "hands busy gathering still hold the torch")
	# one side each on the seeded wait
	var firsts := {"verrine": {}, "quenelle": {}}
	for seed_number in range(1, 31):
		var s := L.new(2, seed_number, 0)
		_expect(s.v.side == "L" and s.q.side == "R", "seed %d: wrong sides" % seed_number)
		var seen := {}
		var t := 0.0
		while t < 60000.0 and s.over == "":
			t += 100.0
			for e in s.step(100.0, {}):
				if e["type"] == "close":
					_expect(e["side"] == D.SIDES[e["id"]], "%s came from the wrong side" % e["id"])
					if not seen.has(e["id"]):
						seen[e["id"]] = s.elapsed
		for id in ["verrine", "quenelle"]:
			_expect(seen.has(id) and float(seen[id]) > 0.0, "%s does not come (seed %d)" % [id, seed_number])
			firsts[id][seen.get(id, -1.0)] = true
	for id in firsts:
		_expect((firsts[id] as Dictionary).size() >= 12, "%s's first step does not vary with the seed (%d)" % [id, (firsts[id] as Dictionary).size()])
	# the torch on a side holds that one still
	for row in [["verrine", "torchL", "torchR"], ["quenelle", "torchR", "torchL"]]:
		var id: String = row[0]
		var gg := _camp({"vl": 20, "ql": 20})
		var h = gg.v if id == "verrine" else gg.q
		h.pacer = Always.new()
		_run(gg, 2000.0, {row[1]: true})
		_expect(h.dist == L.START_DIST, "the torch on her side does not hold %s" % id)
		_run(gg, 100.0, {row[2]: true})
		_expect(h.dist == L.START_DIST - 1, "the other torch holds %s" % id)
		_at_edge(gg, id)
		_run(gg, 1000.0, {row[1]: true})
		_expect(h.at_ms == 0.0, "at the edge the torch does not stop %s's wait" % id)
	# both can be beaten
	var v := _camp({"vl": 9})
	_at_edge(v, "verrine")
	var ev := _run(v, L.PUSH_MS + 100.0, {"torchL": true})
	_expect(ev.any(func(e): return e["type"] == "repelled" and e["id"] == "verrine") and v.v.dist == L.PUSH_BACK, "the torch does not send Verrine back")
	var v2 := _camp({"vl": 9})
	_at_edge(v2, "verrine")
	_run(v2, L.CAMP_AT_MS - 200.0)
	_expect(v2.over == "", "Verrine got to the fire early")
	_run(v2, 400.0)
	_expect(v2.by == "verrine", "left alone at the edge, Verrine does not get to you")
	var v3 := _camp({"vl": 9})
	_at_edge(v3, "verrine")
	_run(v3, L.CAMP_AT_MS + 200.0, {"tent": true})
	_expect(v3.by == "verrine", "the tent hid you from Verrine")
	var q := _camp({"ql": 9})
	_at_edge(q, "quenelle")
	_run(q, 4000.0, {"torchR": true})
	_expect(q.q.dist == 0 and q.over == "", "the torch sent Quenelle back")
	var ev2 := _run(q, L.LOST_MS + 100.0, {"tent": true})
	_expect(ev2.any(func(e): return e["type"] == "repelled" and e["id"] == "quenelle") and q.q.dist == L.LOST_BACK, "in the tent, Quenelle does not lose the trail")
	var q2 := _camp({"ql": 9})
	_at_edge(q2, "quenelle")
	_run(q2, L.CAMP_AT_MS + 200.0)
	_expect(q2.by == "quenelle", "out in the open, Quenelle does not get to you")
	var both := _camp({"vl": 9, "ql": 9})
	_at_edge(both, "verrine")
	_at_edge(both, "quenelle")
	var e3 := _run(both, L.PUSH_MS + 300.0, {"torchL": true})
	e3.append_array(_run(both, L.LOST_MS + 300.0, {"tent": true}))
	_expect(both.over == "" and e3.filter(func(e): return e["type"] == "repelled").map(func(e): return e["id"]) == ["verrine", "quenelle"], "both cannot be sent back in time")
	# the tent
	var tg := _camp({"level": 8})
	var f0 := tg.fire
	var tev := _run(tg, 1000.0, {"tent": true, "torchL": true, "gather": true})
	_expect(tev.any(func(e): return e["type"] == "tentIn") and tg.hidden, "T does not put you in the tent")
	_expect(tg.torch_side == "" and tg.gather == 0.0, "torch or wood in the tent")
	_run(tg, 100.0, {"tent": true, "torchR": true})
	_expect(tg.torch_side == "" and not tg.act("log"), "the torch or a log works from the tent")
	_expect(tg.fire < f0, "the fire stops burning in the tent")
	tg.fire = 100.0
	var logs := tg.logs
	var all := tev.duplicate()
	all.append_array(_run(tg, 60000.0, {"tent": true}))
	var ys := all.filter(func(e): return e.get("id", "") == "ysolde").map(func(e): return e["type"])
	_expect(ys == ["creep", "stolen"], "Ysolde: out of the trees, then a log (%s)" % str(ys))
	_expect(tg.logs == logs - 1 and tg.by == "ysolde" and tg.cause == "tent", "stay too long and she does not look in")
	var out := _camp({"level": 8})
	out.y.dist = 0
	var back := _run(out, 60000.0, {}).filter(func(e): return e["type"] == "backoff").map(func(e): return e["dist"])
	_expect(back == [1, 2], "out of the tent she does not back off a step at a time (%s)" % str(back))
	var free := _camp({"level": 0})
	_run(free, 60000.0, {"tent": true})
	_expect(free.y.dist == 2, "Ysolde at 0 comes")
	_expect(L.TENT_PACE > L.BACK_PACE, "hiding is not faster than coming out")
	# Verrine's torch time adds up over separate holds
	var split := _camp({"vl": 9})
	_at_edge(split, "verrine")
	_run(split, 900.0, {"torchL": true})
	_run(split, 300.0, {})
	var ev4 := _run(split, 700.0, {"torchL": true})
	_expect(ev4.any(func(e): return e["type"] == "repelled"), "Verrine's torch time does not add up over separate holds")
	# a fire left out is credited to the nearer of the two when Ysolde is off
	var dark := _camp({"level": 0, "vl": 9, "ql": 9})
	dark.v.dist = 2
	dark.q.dist = 1
	dark.v.pacer = Never.new()
	dark.q.pacer = Never.new()
	dark.fire = 0.0
	_run(dark, L.OUT_GRACE_MS + 500.0)
	_expect(dark.by == "quenelle" and dark.cause == "fire", "the dark is not credited to the nearer hunter")


func _play_camp(seed_number: int, bot: String) -> bool:
	var g := L.new(2, seed_number)
	var inp := {}
	var heard := false
	var i := 0
	while i < 2800 and g.over == "":
		var v = g.v
		var q = g.q
		var v_edge: bool = v.on and v.dist <= 0
		var q_edge: bool = q.on and q.dist <= 0
		if bot == "perfect":
			inp = {}
			var v_left: float = L.CAMP_AT_MS - v.at_ms if v_edge else INF
			var q_left: float = L.CAMP_AT_MS - q.at_ms if q_edge else INF
			if v_edge and (not q_edge or v_left <= q_left):
				inp["torchL"] = true
			elif q_edge:
				if g.y.dist <= 1 and g.torch > 15.0 and not g.hidden:
					inp["torchR"] = true
				else:
					inp["tent"] = true
			else:
				if g.fire < 72.0:
					g.act("log")
				if g.logs < 3:
					inp["gather"] = true
		elif i % (7 if bot == "sloppy" else 3) == 0:
			inp = {}
			if g.hidden and not heard and q_edge and not (v_edge and v.at_ms > L.CAMP_AT_MS - L.PUSH_MS - 800.0):
				inp["tent"] = true
			elif v_edge:
				inp["torchL"] = true
			elif q_edge:
				inp["tent"] = true
				heard = false
			else:
				if g.fire < 72.0:
					g.act("log")
				if g.logs < 3:
					inp["gather"] = true
			if not inp.has("tent"):
				heard = false
		for e in g.step(100.0, inp):
			if e["type"] == "repelled" and e["id"] == "quenelle":
				heard = true
		i += 1
	return g.over == "win"


func _hard_but_fair() -> void:
	var careful := 0
	for s in range(1, 61):
		if _play_camp(s, "careful"):
			careful += 1
	_expect(careful >= 36, "a careful player does not hold the campfire (%d/60)" % careful)
	for hide in [false, true]:
		var wins := 0
		for s in range(1, 21):
			var g := L.new(2, s)
			var i := 0
			while i < 2800 and g.over == "":
				g.step(100.0, {"tent": true} if hide else {})
				i += 1
			if g.over == "win":
				wins += 1
		_expect(wins == 0, "%s reaches dawn at the campfire" % ("hiding" if hide else "doing nothing"))
	var perfect := 0
	for s in range(1, 41):
		if _play_camp(s, "perfect"):
			perfect += 1
	_expect(perfect == 40, "the perfect campfire player lost a seed (%d/40)" % perfect)
	# the rooftop and the bus stop: a perfect player wins every seed
	for s in range(1, 41):
		var r := L.new(0, s)
		while r.over == "":
			var v = r.v
			r.step(50.0, {"relight": true, "torchL": v.dist > 0 and v.side == "L", "torchR": v.dist > 0 and v.side == "R", "barL": v.dist == 0 and v.side == "L", "barR": v.dist == 0 and v.side == "R"})
		_expect(r.over == "win", "rooftop seed %d: the perfect player loses" % s)
		var b := L.new(1, s)
		while b.over == "":
			if not b.cans.is_empty() and b.fuel < 70.0:
				b.act("can", {"i": b.cans[0]})
			elif not b.lamp and b.warm < 55.0 and b.fuel > 0.0:
				b.act("lamp")
			elif b.lamp and b.warm > 85.0:
				b.act("lamp")
			b.step(50.0, {})
		_expect(b.over == "win", "bus stop seed %d: the perfect player loses" % s)


func _trace(watch: int, seed_number: int) -> String:
	var g := L.new(watch, seed_number)
	var out := []
	for i in 2500:
		if g.over != "":
			break
		for e in g.step(100.0, {"relight": i % 7 < 3, "torchL": i % 11 < 4, "barR": i % 13 < 6}):
			out.append("%d:%s" % [i, e["type"]])
	return ",".join(out) + "|%.3f" % g.elapsed


func _custom_and_misc() -> void:
	for w in 3:
		_expect(_trace(w, 5) == _trace(w, 5), "watch %d: the same seed does not replay the same" % w)
		_expect(_trace(w, 5) != _trace(w, 6), "watch %d: different seeds play the same" % w)
	# a hunter at 0 never comes out of the trees
	for pair in [[0, 10], [10, 0]]:
		var g := L.new(2, 3, 0, pair[0], pair[1])
		var ids := {}
		for e in _run(g, 60000.0, {}):
			if e["type"] == "close":
				ids[e["id"]] = true
		_expect(ids.keys() == ["verrine" if pair[0] > 0 else "quenelle"], "a hunter at 0 comes out of the trees (%s)" % str(ids.keys()))
	# the night's step-ups do not wake a Ysolde at 0
	for ql in [7, 0]:
		for s in range(1, 9):
			var g := L.new(2, s, 0, 0, ql)
			g.q.pacer = Never.new()
			var ys := []
			while g.elapsed < D.WATCH_MS + 500.0 and g.over == "":
				g.fire = 100.0
				for e in g.step(100.0, {"tent": true}):
					if e.get("id", "") == "ysolde":
						ys.append(e["type"])
			_expect(g.elapsed > 4.0 * D.WATCH_MS / 6.0 and ys.is_empty(), "Ysolde at 0 moved in the tent (seed %d, %s)" % [s, str(ys)])


func _variety() -> void:
	# the first step: up to 4 s sooner or later than the window says
	for row in [[0, "v", 9], [2, "v", 9], [2, "q", 13]]:
		var w := NightWatchData.move_window(int(row[2]))
		var firsts := []
		for seed_number in range(1, 121):
			var g := L.new(int(row[0]), seed_number)
			var h = g.v if row[1] == "v" else g.q
			if int(row[0]) == 2:
				g.mood_kind = "calm"
				g.mood_left = 1e12
			_expect(h.pacer.t >= -L.ARRIVE_SPREAD_MS - 1e-6 and h.pacer.t <= L.ARRIVE_SPREAD_MS + 1e-6, "watch %d %s seed %d: offset outside +/-4 s" % [row[0], row[1], seed_number])
			var n: int = h.dist
			var ms := 0
			while ms < 40000 and h.dist == n:
				g.step(20.0, {})
				ms += 20
			firsts.append(ms)
			_expect(ms >= w.x - L.ARRIVE_SPREAD_MS - 40.0 and ms <= w.y + L.ARRIVE_SPREAD_MS + 40.0, "watch %d %s seed %d: first step at %d, window %d-%d" % [row[0], row[1], seed_number, ms, w.x, w.y])
		var sum := 0.0
		for f in firsts:
			sum += f
		_expect(absf(sum / firsts.size() - (w.x + w.y) / 2.0) < 700.0, "watch %d %s: the first step does not average the window's middle (%.0f)" % [row[0], row[1], sum / firsts.size()])
	# the rooftop: the first gust and the side she tries next
	var gsum := 0.0
	var sides := {"L": 0, "R": 0}
	for seed_number in range(1, 301):
		var s := L.new(0, seed_number)
		_expect(s.gust >= 16500.0 - 1e-6 and s.gust <= 27500.0 + 1e-6, "seed %d: first gust outside 16.5 to 27.5 s" % seed_number)
		gsum += s.gust
		sides[s.v.side] += 1
	_expect(absf(gsum / 300.0 - L.GUST_MS) < 900.0 and absf(float(sides["L"]) / 300.0 - 0.5) < 0.1, "the first gust or the starting door is skewed")
	var switched := 0
	for seed_number in range(1, 601):
		var g := L.new(0, seed_number)
		g.v.dist = 0
		var before: String = g.v.side
		var ev := _run(g, L.LEAVE_MS + 120.0, {"barL": true, "barR": true})
		_expect(_types(ev).has("repelled") and g.v.dist == 2, "a barred door does not always send her back")
		if g.v.side != before:
			switched += 1
	_expect(absf(float(switched) / 600.0 - L.SIDE_SWITCH) < 0.06, "she changes door %.1f%% of the time (listed 65%%)" % (100.0 * switched / 600.0))
	# weather lengths and the bus stop's draws stay in their bands
	for w in [1, 2]:
		var wx: Dictionary = D.WEATHER[w]
		var lo := float(wx["lastsMs"]) * (1.0 - L.WEATHER_LAST_SPREAD)
		var hi := float(wx["lastsMs"]) * (1.0 + L.WEATHER_LAST_SPREAD)
		var lasts := []
		for seed_number in range(1, 41):
			var g := L.new(w, seed_number, 0, 0, 0)
			_expect(g.weather["lasts"] >= lo - 1e-6 and g.weather["lasts"] <= hi + 1e-6, "the first length is out of its band")
			var on := -1.0
			var t := 0.0
			while t < D.WATCH_MS and g.over == "":
				t += 50.0
				if w == 1:
					g.warm = 100.0
					g.fuel = 100.0
				else:
					g.fire = 100.0
				for e in g.step(50.0, {}):
					if e["type"] == "weather":
						on = g.elapsed
					elif e["type"] == "weatherEnd" and on >= 0.0:
						if g.elapsed < D.WATCH_MS - D.BUS_MS or w == 2:
							lasts.append(g.elapsed - on)
						on = -1.0
		var bad := lasts.filter(func(x): return x < lo - 60.0 or x > hi + 60.0)
		_expect(lasts.size() > 40 and bad.is_empty(), "watch %d: a %s lasted outside %d to %d" % [w, wx["kind"], lo, hi])
	var firstc := []
	var gaps := []
	for seed_number in range(1, 41):
		var g := L.new(1, seed_number, 0)
		_expect(g.cold_mult >= 0.85 - 1e-9 and g.cold_mult <= 1.15 + 1e-9 and g.can_at >= 2000.0 - 1e-6 and g.can_at <= 6000.0 + 1e-6, "first bus stop draws out of their bands")
		var last := -1.0
		var t := 0.0
		while t < D.WATCH_MS - D.BUS_MS and g.over == "":
			t += 50.0
			g.warm = 100.0
			g.fuel = 100.0
			for e in g.step(50.0, {}):
				if e["type"] == "can":
					if last < 0.0:
						firstc.append(g.elapsed)
					else:
						gaps.append(g.elapsed - last)
					last = g.elapsed
					g.cans.pop_back()
	_expect(firstc.all(func(x): return x >= 2000.0 - 60.0 and x <= 6000.0 + 60.0), "the first canister is outside 2 to 6 s")
	_expect(gaps.size() > 20 and gaps.all(func(x): return x >= 12750.0 - 60.0 and x <= 21250.0 + 60.0), "canisters are not 12.75 to 21.25 s apart")
	# Verrine's mood: calm 20 : bold 40 : shy 40, redrawn every 30 to 60 s, and the edge wait is exactly as before
	var kinds := {"calm": 0, "bold": 0, "shy": 0}
	for seed_number in range(1, 1501):
		kinds[L.new(2, seed_number).mood_kind] += 1
	_expect(absf(kinds["calm"] / 1500.0 - 0.2) < 0.05 and absf(kinds["bold"] / 1500.0 - 0.4) < 0.05 and absf(kinds["shy"] / 1500.0 - 0.4) < 0.05, "the mood mix is off: %s" % str(kinds))
	for kind in ["calm", "bold", "shy"]:
		var g := L.new(2, 5, -1, -1, 0)
		g.mood_kind = kind
		g.mood_left = 1e12
		g.v.dist = 0
		g.v.at_ms = 0.0
		var ms := 0
		while ms < 8000 and g.over == "":
			g.fire = 100.0
			g.step(10.0, {})
			ms += 10
		_expect(g.over == "caught" and g.by == "verrine" and absf(ms - L.CAMP_AT_MS) <= 20.0, "%s: unanswered, Verrine is not at the fire after exactly 5200 ms (%d)" % [kind, ms])


func _paths(host: Node) -> void:
	var needs := {
		0: ["L0", "L1", "L2", "L3", "R0", "R1", "R2", "R3"],
		1: ["W0", "W1", "W2", "W3", "W4"],
		2: ["V0", "V1", "V2", "V3", "Q0", "Q1", "Q2", "Q3", "Y0", "Y1", "Y2"],
	}
	for w in 3:
		var world := NightWatchOpenAirWorld.new()
		host.add_child(world)
		world.build(w)
		for key in needs[w]:
			_expect(world.paths.has_key(key), "watch %d has no waypoint %s" % [w, key])
		for chain in ([["L3", "L0"], ["R3", "R0"], ["L0", "R2"], ["R0", "L2"], ["L3", "R3"]] if w == 0 else [["W0", "W4"]] if w == 1 else [["V3", "V0"], ["Q3", "Q0"], ["Y2", "Y0"], ["Y0", "Y2"], ["V0", "V3"]]):
			_expect(world.paths.reachable(chain[0], chain[1]), "watch %d: no walk from %s to %s" % [w, chain[0], chain[1]])
			var legs := world.paths.route(chain[0], chain[1])
			for i in range(1, legs.size()):
				_expect((legs[i]["p"] as Vector3).distance_to(legs[i - 1]["p"]) < 30.0, "watch %d: a waypoint hop of more than 30 m" % w)
		# the set has stations to aim at, a spawn on solid ground and a place for every hunter
		_expect(world.stations.size() >= 4 and world.spawn.y == 0.0, "watch %d has no stations" % w)
		for id in world.prompts:
			_expect(not String(world.prompts[id]).is_empty(), "station %s has no prompt" % id)
		world.queue_free()
	# a hunter the sim moves walks: she is not placed in the new spot
	var roof := NightWatchOpenAirWorld.new()
	host.add_child(roof)
	roof.build(0)
	var walker := NightWatchWalker.new()
	walker.place(roof.point("L0"), roof.point("L0"), Vector3.ZERO, "L0")
	walker.go(roof.paths.legs_from(walker.pos, "R2"), "R2", roof.point("R2"), NightWatchWalker.budget_for(9))
	_expect(walker.is_walking() and walker.pos.distance_to(roof.point("R2")) > 5.0, "sent to the other door she is placed there at once")
	var steps := 0
	var worst := 0.0
	while walker.is_walking() and steps < 6000:
		var before := walker.pos
		walker.step(1.0 / 30.0)
		worst = maxf(worst, walker.pos.distance_to(before))
		steps += 1
	_expect(walker.pos.distance_to(roof.point("R2")) < 0.1 and worst <= NightWatchWalker.RUN_SPEED / 30.0 + 0.2, "the walker does not arrive, or exceeds the run speed in a step (%.2f)" % worst)
	roof.queue_free()


# --- the admin menu (docs/NIGHT_WATCH_ADMIN.md) -----------------------------------------------------------------------------------

func _fingerprint(game: NightWatchOpenAirGame) -> String:
	var s := game.sim
	var shown := []
	for id in game._models:
		shown.append((game._models[id] as Node3D).visible)
	return "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%d|%s|%s|%s|%s|%s|%s|%s" % [game.admin_status(), str(s.oil), str(s.lantern), str(s.warm), str(s.fuel), str(s.chill), str(s.fire), str(s.logs), s.mood_kind,
		str(s.cans), str(s.weather), str(s.elapsed), str(s.bus), game.state, str(shown), str(NightWatchSession.night), str(game.admin_is_reveal()), game.hud.shown_call, str(game.hud.muted), str(game.hud.call_script.get_instance_id() if game.hud.call_script != null else 0), str(game.player.admin_noclip)]


func _admin(host: Node) -> void:
	for w in 3:
		var label := "watch %d admin" % w
		var game := await _make(host, w + 1, 40 + w)
		_expect(NightWatchAdmin.attach(game, false) == null and game.admin_menu != null and game.hud.hint_label.text.contains("0 admin"), "%s: the gate or the hint line is wrong" % label)
		_expect(NightWatchAdmin.PROVIDERS.get("extra", "") == "res://game/night_watch/openair/openair_admin.gd", "Open Air has no admin provider")
		var sections := NwAdminCheck.sections(game)
		for want in ["SHIFT // OPEN AIR", "ZELLIA AND THE NIGHT", "OPEN AIR SPECIFIC"]:
			_expect(sections.has(want), "%s: no %s section: %s" % [label, want, str(sections)])
		for p in NwAdminCheck.entry_problems(game):
			_expect(false, "%s: %s" % [label, p])
		if w == 0:
			for p in await NwAdminCheck.layout_problems(host, game, ["SHIFT", "OPEN AIR SPECIFIC"]):
				_expect(false, p)
		var level := w + 1
		var make := func() -> NightWatchOpenAirGame:
			var gm := await _make(host, level, 40 + level - 1)
			gm.advance_ms(12000.0)   # into Zellia's call
			return gm
		var fp := func(g) -> String: return _fingerprint(g)
		for p in await NwAdminCheck.exercise(make, fp, ["JUMP TO SHIFT"]):
			_expect(false, "%s: %s" % [label, p])
		game.queue_free()
		await host.get_tree().process_frame
	# the hooks do what they say
	var g := await _make(host, 3, 77)
	g.admin_set_hunter_level("quenelle", 0)
	_expect(not g.sim.q.on and not g.hunter_on("quenelle"), "AI level 0 did not take Quenelle off the floor")
	g.admin_set_reveal(true)
	_expect(g.hunter_on("quenelle"), "REVEAL did not show the hunter that is off")
	g.admin_set_reveal(false)
	g.admin_set_hunter_level("verrine", 12)
	g.admin_place_hunter("verrine", "at the edge")
	_expect(g.sim.v.dist == 0 and g.sim.v.on and g.sim.level_of("verrine") == 12, "SEND TO at the edge did not put Verrine at the edge")
	g.admin_set_god(true)
	g.advance_ms(L.CAMP_AT_MS + 500.0)
	_expect(g.state == NightWatchOpenAirGame.State.PLAYING and g.sim.over == "" and g.sim.v.dist > 0, "god mode did not send Verrine back instead of being caught")
	g.admin_set_god(false)
	g.admin_set_hour(3)
	_expect(NightWatchData.hour_index(g.sim.elapsed) == 3 and g.hud.clock_label.text == "3 AM", "SET TIME did not set 3 AM")
	g.admin_set_frozen(true)
	var el := g.sim.elapsed
	g.advance_ms(3000.0)
	_expect(g.sim.elapsed == el, "the frozen clock still ran")
	g.admin_set_frozen(false)
	g.admin_set_noclip(true)
	_expect(g.admin_is_noclip() and g.player.admin_noclip, "NOCLIP did not switch the player to noclip")
	g.admin_set_noclip(false)
	g.admin_set("fire", 0.0)
	_expect(g.sim.fire == 0.0 and g.admin_set("mood", "bold") and g.sim.mood_kind == "bold" and g.admin_set("logs", 9) and g.sim.logs == 9, "the campfire's own controls did not set fire, mood and logs")
	_expect(not g.admin_set("oil", 10.0), "the rooftop's oil control applied at the campfire")
	g.admin_win()
	_expect(g.state == NightWatchOpenAirGame.State.WON and g.hud.end_root.visible, "WIN THE SHIFT did not win")
	g.queue_free()
	await host.get_tree().process_frame
	var jump := await _make(host, 3, 78)
	jump.admin_jump_to(2)
	_expect(NightWatchSession.mode_id == "extra" and NightWatchSession.night == 2, "JUMP TO SHIFT did not set the session to the bus stop")
	jump.queue_free()
	await host.get_tree().process_frame
	var lost := await _make(host, 2, 79)
	lost.admin_set_no_scare(true)
	lost.admin_lose()
	_expect(lost.state == NightWatchOpenAirGame.State.LOST and lost.hud.end_root.visible and lost.hud.end_title.text == "CAUGHT", "LOSE THE SHIFT did not lose it with no jumpscare")
	lost.queue_free()
	await host.get_tree().process_frame


# --- the map (docs/NIGHT_WATCH_OFFICES.md, "Maps"): open grounds, one layout for the three watches ----------------------------------

func _map() -> void:
	_expect(NightWatchMapRegistry.MAPS["extra"]["script"] == "res://game/night_watch/openair/openair_map.gd", "the registry has no map for Open Air")
	var layout := NightWatchMapRegistry.layout_for("extra")
	var rooms: Dictionary = layout["rooms"]
	for e in layout["edges"]:
		_expect(rooms.has(e[0]) and rooms.has(e[1]), "map edge %s has an unknown room" % str(e))
	_expect(layout["entrances"] == ["roof", "bus_shelter", "clearing"], "the map's entrances are not the three watches' offices")
	for room in ["catwalk_w", "catwalk_e", "back_catwalk", "road_stop", "road_far", "trees_w", "trees_e", "log_pile"]:
		_expect(rooms.has(room), "the map has no %s" % room)
	# each watch's office stands in its cluster of the map
	for w in 3:
		var spec := NightWatchOpenAirOffice.make_spec(w)
		_expect(spec.entrances.size() >= 1, "watch %d's office has no entrance" % w)


# --- the office (docs/NIGHT_WATCH_OFFICES.md): watch_post, built three ways ----------------------------------------------------

func _offices(host: Node) -> void:
	_expect(NightWatchOfficeRegistry.built("extra") and NightWatchOfficeRegistry.office_id("extra") == "watch_post", "Open Air's office is not registered as watch_post")
	for w in 3:
		var office := NightWatchOfficeRegistry.make("extra") as NightWatchOpenAirOffice
		office.watch = w
		host.add_child(office)
		await host.get_tree().process_frame
		await host.get_tree().physics_frame
		var label := "watch %d office" % w
		for p in office.spec.problems():
			_expect(false, "%s: %s" % [label, p])
		for sid in office.spec.required_stations:
			_expect(office.stations.has(sid), "%s: no station %s" % [label, sid])
		_expect(not office.spec.has_monitor and office.light_count() <= NightWatchOfficeSpec.MAX_REAL_LIGHTS, "%s: a monitor, or %d real lights" % [label, office.light_count()])
		for prop_name in office.props:
			_expect(int(NightWatchArt.prop_stats(office.props[prop_name])["untextured"]) == 0, "%s: prop %s has untextured cubes" % [label, prop_name])
		# the entrances are where the hunters' last waypoints are
		for e in office.spec.entrances:
			_expect(office.world.paths.has_key(String(e["sim_room"])) and (office.world.point(String(e["sim_room"])) - (e["position"] as Vector3)).length() < 0.05, "%s: entrance %s is not at its waypoint %s" % [label, e["id"], e["sim_room"]])
		for problem in NwOfficeWalk.problems(office):
			_expect(false, "%s: %s" % [label, problem])
		office.queue_free()
		await host.get_tree().process_frame


# --- the shift scene ----------------------------------------------------------------------------------------------------------

func _make(host: Node, level: int, seed_number: int, custom := {}) -> NightWatchOpenAirGame:
	NightWatchSession.start_mode("extra", level, custom, seed_number)
	var shift := (load("res://game/night_watch/night_watch_extra.tscn") as PackedScene).instantiate() as NightWatchOpenAirGame
	shift.manual_clock = true
	host.add_child(shift)
	await host.get_tree().process_frame
	return shift


func _finish(host: Node, shift: NightWatchOpenAirGame) -> void:
	shift.queue_free()
	await host.get_tree().process_frame


## Holds the watch the way a careful player would: bars the door she is at, torch on her, lantern relit, lamp and canisters, logs and the tent.
func _careful(shift: NightWatchOpenAirGame, max_steps := 5400) -> void:
	var g := shift.sim
	var n := 0
	while shift.state == NightWatchOpenAirGame.State.PLAYING and n < max_steps:
		n += 1
		g.torch = 100.0
		match shift.watch:
			0:
				var v = g.v
				shift.inp["relight"] = true
				shift.inp["torchL"] = v.dist > 0 and v.side == "L"
				shift.inp["torchR"] = v.dist > 0 and v.side == "R"
				shift.inp["barL"] = v.dist == 0 and v.side == "L"
				shift.inp["barR"] = v.dist == 0 and v.side == "R"
			1:
				g.warm = maxf(g.warm, 60.0)
				if not g.cans.is_empty():
					shift.pick_can(int(g.cans[0]))
			2:
				g.fire = maxf(g.fire, 60.0)
				shift.inp["torchL"] = g.v.on and g.v.dist <= 0
				shift.inp["torchR"] = false
				if g.q.on and g.q.dist <= 0 and not g.hidden:
					shift.toggle_tent()
				elif g.hidden and not (g.q.on and g.q.dist <= 0):
					shift.toggle_tent()
		shift.advance_ms(100.0)
	for k in shift.inp:
		shift.inp[k] = false


func _scene(host: Node) -> void:
	NightWatchSave.path = "user://night_watch_extra_test.cfg"
	NightWatchSave.reset()
	_expect(NightWatchModeRegistry.playable("extra") and NightWatchModeRegistry.SCENES["extra"] == "res://game/night_watch/night_watch_extra.tscn", "the registry does not list Open Air under its 2D id")
	_expect(NightWatchModeRegistry.prepare("extra", 2) == "res://game/night_watch/night_watch_extra.tscn" and NightWatchSession.mode_id == "extra" and NightWatchSession.night == 2, "the board cannot start the bus stop")
	_expect(NightWatchSave.level_open("extra", 1) and not NightWatchSave.level_open("extra", 2), "watch 2 is open before watch 1 is cleared")
	# each watch builds, shows its HUD and starts from the board
	for w in 3:
		var shift := await _make(host, w + 1, 100 + w)
		_expect(shift.watch == w and shift.mode_id == "extra" and shift.world != null and shift.player != null, "watch %d did not build" % w)
		_expect(shift.hud.night_label.text.contains(String(D.WATCHES[w]["label"])) and shift.hud.night_label.text.begins_with("8. OPEN AIR"), "watch %d's HUD does not say its name" % w)
		_expect(shift.player.scene_file_path == "res://game/night_watch/night_watch_player.tscn", "watch %d does not use the shared player" % w)
		_expect(shift.player.global_position.distance_to(shift.world.spawn) < 0.05, "watch %d: the player does not start at the spawn" % w)
		var shown := 0
		for id in shift._models:
			if (shift._models[id] as Node3D).visible:
				shown += 1
		_expect(shown == (1 if w < 2 else 3), "watch %d shows %d hunters" % [w, shown])
		await _finish(host, shift)
	# watch 1 (rooftop): bars, lantern, a station answered through the shared prompt; win saves the clear
	var roof := await _make(host, 1, 777)
	roof.advance_ms(100.0)
	_expect(roof.world.stations.has("barL") and (roof.world.stations["barL"] as NightWatchStation).prompt_text.contains("STAIR DOOR"), "the stair door has no station")
	roof.toggle_bar("L")
	_expect(roof.inp["barL"] and roof.sim.bars["L"] == false, "the bar is pressed")
	roof.advance_ms(100.0)
	_expect(roof.sim.bars["L"] and absf(float(roof.world.bar_progress["L"]) - 1.0) < 0.01, "the bar does not slide down")
	roof.toggle_bar("L")
	await _careful(roof)
	_expect(roof.state == NightWatchOpenAirGame.State.WON, "the rooftop was not held")
	_expect(NightWatchSave.cleared_levels("extra") == [1] and NightWatchSave.level_open("extra", 2) and not NightWatchSave.level_open("extra", 3), "the win did not save the clear and open the bus stop only")
	_expect(roof.hud.end_title.text == "WATCH 1 COMPLETE" and roof.hud.end_next.visible and roof.hud.end_next.text.begins_with("NEXT WATCH") and roof.hud.end_body.text.contains("DAWN") and roof.hud.end_body.text.contains("Rooftop held until morning."), "the win card differs")
	await _finish(host, roof)
	# the bus stop: the lamp and the canisters, the bus at dawn, a win
	var bus := await _make(host, 2, 778)
	bus.advance_ms(6500.0)
	_expect(not bus.sim.cans.is_empty() and (bus.world.can_nodes[bus.sim.cans[0]] as Node3D).visible, "a canister does not turn up on the pavement")
	bus.press_lamp()
	_expect(bus.sim.lamp, "the heat lamp does not light")
	bus.pick_can(int(bus.sim.cans[0]))
	await _careful(bus)
	_expect(bus.state == NightWatchOpenAirGame.State.WON and NightWatchSave.cleared_levels("extra") == [1, 2], "the bus stop was not held and saved")
	_expect(bus.world.bus.position.x > -4.0, "the bus did not come up the road")
	await _finish(host, bus)
	# the campfire: the tent, a log, Ysolde walks, a win; the last watch offers no next
	var camp := await _make(host, 3, 779)
	camp.advance_ms(100.0)
	camp.toggle_tent()
	camp.advance_ms(100.0)
	_expect(camp.sim.hidden and camp.world.in_tent(camp.player.global_position), "walking into the tent does not hide you")
	camp.toggle_tent()
	camp.advance_ms(100.0)
	_expect(not camp.sim.hidden, "leaving the tent does not unhide you")
	var logs_before := camp.sim.logs
	camp.throw_log()
	_expect(camp.sim.logs == logs_before - 1, "the fire does not take a log")
	await _careful(camp)
	_expect(camp.state == NightWatchOpenAirGame.State.WON and NightWatchSave.cleared_levels("extra") == [1, 2, 3], "the campfire was not held and saved")
	_expect(camp.hud.end_title.text == "WATCH 3 COMPLETE" and not camp.hud.end_next.visible, "the last watch offers a next one")
	await _finish(host, camp)
	# a loss: nothing is saved, the card is CAUGHT with Retry and Menu only
	var before := NightWatchSave.cleared_levels("extra").duplicate()
	NightWatchSave.reset()
	var lost := await _make(host, 1, 31)
	var guard := 0
	while lost.state == NightWatchOpenAirGame.State.PLAYING and guard < 4000:
		guard += 1
		lost.advance_ms(100.0)
	_expect(lost.state == NightWatchOpenAirGame.State.LOST and lost.sim.by == "verrine", "the idle rooftop was not lost")
	lost._after_death_moment()
	_expect(lost.hud.end_title.text == "CAUGHT" and lost.hud.end_body.text.begins_with("Verrine got to you at ") and not lost.hud.end_next.visible, "the loss card differs: %s" % lost.hud.end_body.text)
	_expect(NightWatchSave.cleared_levels("extra").is_empty() and before == [1, 2, 3], "a loss saved a clear")
	await _finish(host, lost)
	# Retry replays the same seed
	var a := await _make(host, 3, 4242)
	var b := await _make(host, 3, 4242)
	_expect(a.sim.v.pacer.t == b.sim.v.pacer.t and a.sim.mood_kind == b.sim.mood_kind and a.sim.weather["next"] == b.sim.weather["next"], "the same seed dealt a different campfire")
	await _finish(host, a)
	await _finish(host, b)
	# Custom Night: Dusk To Dawn runs the rooftop, then the campfire; only the last win records the score and the star
	var dusk := {"ysolde": 8, "verrine": 8, "wynelle": 0, "quenelle": 12}
	var c1 := await _make(host, 1, 9001, dusk)
	_expect(c1.chain == [0, 2] and c1.watch == 0 and c1.has_more and c1.sim.level() == 8 and c1.sim.level_of("verrine") == 8, "Dusk To Dawn does not start on the rooftop with Verrine's slider")
	await _careful(c1)
	_expect(c1.state == NightWatchOpenAirGame.State.WON and c1.hud.end_title.text == "ROOFTOP HELD" and c1.hud.end_next.visible, "the first watch of the Custom Night does not offer the next")
	_expect(NightWatchSave.best_score("extra") == 0 and NightWatchSave.cleared_levels("extra").is_empty(), "leaving a Custom Night between watches counts as a win")
	var seed_kept := c1.seed_value
	await _finish(host, c1)
	NightWatchOpenAirGame.chain_step = 1   # what NEXT WATCH sets before it reloads the scene
	var c2 := await _make(host, 1, seed_kept, dusk)
	_expect(c2.watch == 2 and not c2.has_more and c2.sim.level() == 8 and c2.sim.level_of("verrine") == 8 and c2.sim.level_of("quenelle") == 12, "the second watch is not the campfire with the sliders")
	await _careful(c2)
	_expect(c2.state == NightWatchOpenAirGame.State.WON and c2.hud.end_title.text == "CUSTOM NIGHT COMPLETE" and not c2.hud.end_next.visible, "the last watch does not end the Custom Night")
	_expect(NightWatchSave.best_score("extra") == 280 and NightWatchSave.stars("extra") == ["dusk-to-dawn"] and NightWatchSave.cleared_levels("extra").is_empty(), "the Custom Night did not save its score and star only")
	await _finish(host, c2)
	var fresh := await _make(host, 1, 123456, dusk)
	_expect(fresh.watch == 0 and NightWatchOpenAirGame.chain_step == 0, "a new Custom Night does not begin at its first watch")
	await _finish(host, fresh)
	# the shared pause card
	var pz := await _make(host, 2, 3)
	pz.set_paused(true)
	_expect(pz.state == NightWatchOpenAirGame.State.PAUSED and pz.hud.pause_root.visible, "the shared pause card does not show")
	pz.set_paused(false)
	_expect(pz.state == NightWatchOpenAirGame.State.PLAYING and not pz.hud.pause_root.visible, "RESUME does not resume")
	await _finish(host, pz)
	NightWatchSave.reset()
	NightWatchSave.path = NwLeakProbe.scratch_path()
	NightWatchSession.start(1)
