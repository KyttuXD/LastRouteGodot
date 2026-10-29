extends RefCounted

## Dead Air (3D): the rules port reproduces the 2D game (games/night-watch validate-lure, -lure-air, -variety-lure): same tables, same
## timers, same air, the cast by night, and the 2D game's own random draws (scripts/data/nw_lure_golden.json, written by
## tools/nightwatch/gen_lure_golden.mjs from the 2D code: the first draws of mulberry32, eight whole shifts event by event, and QA's
## bots on the 20/20/20/20 Custom Night). Then the shift scene: the office with sealed vents, the heater and fan, the monitor and its
## panel, Xivvy walking the hall, winning, losing, saving per mode and the Custom Night.

var _failures := 0
const HIT := 0.999
const GOLDEN := "res://scripts/data/nw_lure_golden.json"


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _g(opts: Dictionary) -> LureLogic:
	return LureLogic.new(opts)


func _stub(night: int, extra := {}) -> Dictionary:
	var o := {"night": night, "rng": NightWatchStream.fixed(HIT), "choice_rng": NightWatchStream.fixed(0.0)}
	o.merge(extra, true)
	return o


func _run(g: LureLogic, ms: float, step := 100.0) -> Array:
	var out := []
	var t := 0.0
	while t < ms and g.over == "":
		out.append_array(g.step(step))
		t += step
	return out


func _types(ev: Array) -> Array:
	var out := []
	for e in ev:
		out.append(String(e["type"]))
	return out


func _has(ev: Array, type: String, key := "", value := "") -> bool:
	for e in ev:
		if String(e["type"]) == type and (key == "" or String(e.get(key, "")) == value):
			return true
	return false


const NO_PHANTOMS := {"ferryn": 0, "briselle": 0, "mavrine": 0}


## The plain hand of the 2D variety validator: reboot what is broken, seal where she is, the climate bands, now and then the monitor on her.
func _bot_input(g: LureLogic, i: int) -> Dictionary:
	if i % 10 == 0:
		for name in g.systems:
			if g.systems[name]["state"] == "broken":
				g.reboot(name)
		g.seal("L", g.killer["room"] == "officeL")
		g.seal("R", g.killer["room"] == "officeR")
		if g.has_climate:
			if g.temp < 63 and not g.heater_on:
				g.toggle("heater")
			if g.temp >= 69 and g.heater_on:
				g.toggle("heater")
			if g.temp > 88 and not g.fan_on:
				g.toggle("fan")
			if g.temp <= 78 and g.fan_on:
				g.toggle("fan")
	if i % 900 == 450:
		g.lure("ballpit")
	return {"watch": g.killer["room"] if i % 200 < 70 and ["storage", "ventl", "ventr"].has(g.killer["room"]) else ""}


func _near(a: float, b: float, message: String) -> void:
	_expect(absf(a - b) < 1e-9, "%s: %s != %s" % [message, str(a), str(b)])


func run(host: Node) -> int:
	NwLeakProbe.fresh()
	_tables()
	_streams()
	_rules()
	_air()
	_phantoms_and_cast()
	_climate()
	_variety()
	_golden()
	await _scene(host)
	if _failures == 0:
		print("  night_watch_lure  Dead Air rules (2D tables, timers, air, cast by night, variety, 2D draws) and the shift scene")
	return _failures


# --- the tables ------------------------------------------------------------------------------------------------------------

func _tables() -> void:
	for room in LureData.GRAPH:
		for nxt in LureData.GRAPH[room]:
			_expect((LureData.GRAPH[nxt] as Array).has(room), "%s <-> %s is not mirrored" % [room, nxt])
	_expect(LureData.ROOMS.size() == 8, "Dead Air does not have eight cameras")
	_expect(LureLogic.LEVELS == [0, 3, 5, 7, 9, 11] and LureLogic.PHANTOM_LEVELS["ferryn"] == [2, 3, 5, 7, 9, 0]
		and LureLogic.CLIMATE_LEVELS["wynelle"] == [0, 0, 0, 5, 8, 13] and LureLogic.CLIMATE_LEVELS["solyth"] == [0, 0, 0, 0, 0, 12], "the level tables differ from the 2D game's")
	_expect(LureLogic.T["officeWaitMs"] == 5200.0 and LureLogic.T["retreatMs"] == 2000.0 and LureLogic.T["rebootMs"] == 6000.0 and LureLogic.T["phantomShowMs"] == 4000.0
		and LureLogic.T["lureMs"] == 12000.0 and LureLogic.T["lureCoolMs"] == 7000.0 and LureLogic.T["phantomFirstMs"] == 4000.0 and LureLogic.T["phantomCoolMs"] == 10000.0
		and LureLogic.T["phantomPace"] == 0.3, "the timers differ from the 2D game's")
	_expect(LureLogic.VARIETY == {"xivvyTempo": 0.25, "phantomTempo": 0.2, "phantomRestSpread": 0.3, "sameSideAgain": 0.25, "wakeStep": 8000.0, "startTempSpread": 3.0, "driftSpread": 0.1}, "VARIETY differs from the 2D game's")
	for id in LureLogic.PHANTOM_IDS:
		_expect((LureLogic.PHANTOM_LEVELS[id] as Array).size() == 6 and (LureLogic.PHANTOM_EXTRA[id] as Array).size() == 6 and (LureLogic.PHANTOM_EXTRA[id][0] as Array).is_empty(), "%s's tables are not six nights" % id)
	_expect(NightWatchModesData.mode("lure")["levels"].size() == 6 and (NightWatchModesData.mode("lure")["cast"] as Array) == LureData.CAST, "the mode table and Dead Air's cast disagree")


func _streams() -> void:
	# the 2D game's mulberry32, bit for bit
	var want := {1: [0.6270739405881613, 0.002735721180215478, 0.5274470399599522], 12345: [0.9797282677609473, 0.3067522644996643, 0.484205421525985]}
	for seed_number in want:
		var s := NightWatchStream.seeded(seed_number)
		for v in want[seed_number]:
			_near(s.next(), float(v), "mulberry32(%d)" % seed_number)
	var n := NightWatchStream.make_neutral()
	_expect(n.next() == 0.5 and NightWatchStream.tempo(n, 0.3) == 1.0 and not NightWatchStream.chance(n, 1.0) and NightWatchStream.pick_index(n, 5) == 0, "the neutral stream is not neutral")
	_expect(NightWatchStream.variety_of(NightWatchStream.fixed(0.5)).neutral and not NightWatchStream.variety_of(NightWatchStream.seeded(5)).neutral, "a stub rng must get the neutral variety stream, a seeded one its own")
	for spread: float in [0.1, 0.2, 0.25, 0.3]:
		var r := NightWatchStream.seeded(int(spread * 1000))
		var sum := 0.0
		var lo := 1.0 / (1.0 + spread)
		var hi := 1.0 / (1.0 - spread)
		for i in 20000:
			var t := NightWatchStream.tempo(r, spread)
			_expect(t >= lo - 1e-9 and t <= hi + 1e-9, "tempo %s out of bounds" % str(spread))
			sum += 1.0 / t
		_expect(absf(sum / 20000.0 - 1.0) < 0.01, "the average wait is not the listed one at spread %s" % str(spread))


# --- validate-lure.mjs -----------------------------------------------------------------------------------------------------

func _rules() -> void:
	var g := _g(_stub(1, {"level": 0, "phantoms": false}))
	_expect(_types(_run(g, NightWatchData.NIGHT_MS)) == ["win"], "level 0, no phantoms: something happened before 6 AM")
	# a level-20 hunter walks lobby ... storage -> vent -> office and gets in when the vent is open
	g = _g(_stub(1, {"level": 20, "phantoms": false}))
	var ev := _run(g, 120000)
	var path := []
	for e in ev:
		if e["type"] == "moved" or e["type"] == "atOffice":
			path.append(e["room"])
	_expect(path.slice(-3) == ["storage", "ventl", "officeL"] and g.by == "xivvy", "a level-20 hunter did not come through storage and the left vent: %s" % str(path.slice(-3)))
	# a closed seal turns her away
	g = _g(_stub(1, {"level": 20, "phantoms": false}))
	g.seal("L", true)
	ev = _run(g, 120000)
	_expect(not _has(ev, "atOffice", "room", "officeL"), "she entered a sealed vent")
	g.seal("L", false)
	_expect(g.over != "win", "an unattended night was won")
	g = _g(_stub(1, {"level": 20, "phantoms": false, "infinite_stress": true}))
	_run(g, 40000)
	g.seal("L", true)
	_expect(not _types(_run(g, 12000)).has("caught"), "a seal put down at the vent did not hold her off")
	# lure pulls her toward a room, needs audio, and has a cooldown
	g = _g(_stub(1, {"level": 20, "phantoms": false}))
	_expect(not g.lure("ventl"), "a lure into a vent was allowed")
	_expect(g.lure("ballpit") and not g.lure("arcade"), "lure or its cooldown is wrong")
	_run(g, 8000)
	_expect(g.killer["room"] == "ballpit", "the lure did not bring her to the ball pit (%s)" % g.killer["room"])
	g.systems["audio"]["state"] = "broken"
	_run(g, LureLogic.T["lureCoolMs"] + 100)
	_expect(not g.lure("party"), "a lure worked with the audio down")
	# a phantom breaks its system; reboot takes six seconds and is offline meanwhile
	g = _g({"night": 1, "rng": NightWatchStream.seeded(3), "choice_rng": NightWatchStream.fixed(0.0), "level": 0, "phantom_levels": {"ferryn": 40, "briselle": 0, "mavrine": 0}})
	ev = _run(g, 60000)
	var broke := {}
	for e in ev:
		if e["type"] == "broken":
			broke = e
			break
	_expect(not broke.is_empty(), "a phantom visit breaks nothing")
	if not broke.is_empty():
		var sys := String(broke["system"])
		_expect(LureData.SYSTEM_OF[broke["id"]] == sys and not g.online(sys), "the broken system is not the phantom's own")
		_expect(g.reboot(sys) and not g.online(sys), "reboot did not start")
		_run(g, LureLogic.T["rebootMs"] - 200)
		_expect(not g.online(sys), "back online too early")
		_expect(_types(_run(g, 400)).has("fixed") and g.online(sys), "never came back after six seconds")
	# stress: a dead vent system or closed seals build it; at 100 the air gives out
	g = _g(_stub(1, {"level": 0, "phantoms": false}))
	g.systems["vent"]["state"] = "broken"
	ev = _run(g, 60000)
	_expect(_types(ev).slice(-1) == ["caught"] and g.by == "mavrine", "a dead vent system did not stifle the office")
	var h := _g(_stub(1, {"level": 0, "phantoms": false}))
	h.seal("L", true)
	_run(h, 20000)
	_expect(h.stress > 20.0, "a closed seal did not build stress")
	h.seal("L", false)
	_run(h, 20000)
	_expect(h.stress == 0.0, "clear air did not let it fall")
	# a hunter being looked at does not move
	var a := _g(_stub(2, {"level": 20, "phantoms": false}))
	_run(a, 40000)
	var b := _g(_stub(2, {"level": 20, "phantoms": false}))
	var t := 0.0
	while t < 40000.0:
		b.step(100.0, {"watch": "lobby"})
		t += 100.0
	_expect(b.killer["room"] == "lobby" and a.killer["room"] != "lobby", "a hunter on the monitor moved")
	# night 1 is a tutorial
	g = _g({"night": 1, "rng": NightWatchStream.seeded(2), "choice_rng": NightWatchStream.fixed(0.0)})
	ev = _run(g, 150000)
	_expect(not _has(ev, "moved") and not _has(ev, "atOffice") and g.killer["room"] == "lobby", "she left the lobby on night 1")
	# every second lure strains the speakers
	g = _g(_stub(2, {"level": 0, "phantoms": false}))
	_expect(g.lure("ballpit") and g.online("audio"), "the first lure strained the audio")
	_run(g, LureLogic.T["lureCoolMs"] + 100)
	_expect(g.lure("party"), "the second lure was refused")
	ev = _run(g, 200)
	_expect(_has(ev, "broken", "system", "audio") and not g.online("audio"), "the second lure did not break the audio")
	_expect(g.reboot("audio"), "audio would not reboot")
	_run(g, LureLogic.T["rebootMs"] + 100)
	_expect(g.online("audio"), "audio never came back")
	# AI steps up at 3 and 4 AM: a hunter set to 6 acts at 8 by the end; a sleeping phantom stays asleep
	g = _g(_stub(3, {"level": 6, "phantom_levels": NO_PHANTOMS, "infinite_stress": true}))
	_expect(_run(g, 5 * 80000 + 1000).filter(func(e): return e["type"] == "broken").is_empty(), "a sleeping phantom broke something")
	g.elapsed = 5 * 45000.0
	_expect(g.level_of("xivvy") == 8 and g.level_of("ferryn") == 0, "the AI step-ups are wrong")
	g.elapsed = 3 * 45000.0
	_expect(g.level_of("xivvy") == 7, "the 3 AM step-up is wrong")


# --- validate-lure-air.mjs -------------------------------------------------------------------------------------------------

func _air() -> void:
	var story := {"seal": 1.2, "broken": 3.0, "appliance": 0.9, "decay": 2.0}
	_expect(LureLogic.air_rates(false) == story and LureLogic.air_rates(false, 20) == story, "the story nights' air is not the 2D game's")
	_expect(LureLogic.CUSTOM_AIR == {"sealSec": 1.2, "brokenSec": 2.8, "brokenPerLevel": 0.02, "applianceStress": 0.8, "decaySec": 2.1}, "CUSTOM_AIR differs")
	for pair in [[0, 2.8], [1, 2.82], [10, 3.0], [12, 3.04], [20, 3.2], [25, 3.2], [-3, 2.8]]:
		var r := LureLogic.air_rates(true, pair[0])
		_near(r["broken"], pair[1], "Custom Night dead vent at Mavrine %d" % pair[0])
		_expect(r["seal"] == 1.2 and r["appliance"] == 0.8 and r["decay"] == 2.1, "Custom Night air rates")
	# measured on a running game: seals, a dead vent, the heater, then clear air
	for case in [[false, 0, story], [false, 20, story], [true, 0, LureLogic.air_rates(true, 0)], [true, 12, LureLogic.air_rates(true, 12)], [true, 20, LureLogic.air_rates(true, 20)]]:
		var g := _g({"night": 5, "rng": NightWatchStream.seeded(1), "level": 0, "phantoms": false, "custom": case[0],
			"phantom_levels": {"ferryn": 0, "briselle": 0, "mavrine": case[1]}, "climate_levels": {"solyth": 0, "wynelle": 1}})
		g.temp = 75.0
		var want: Dictionary = case[2]
		g.seal("L", true)
		g.seal("R", true)
		var seal_rate := _span(g, 5000.0) / 2.0
		g.seal("L", false)
		g.seal("R", false)
		g.systems["vent"] = {"state": "broken", "t": 0.0}
		var broken_rate := _span(g, 5000.0)
		g.systems["vent"] = {"state": "ok", "t": 0.0}
		g.toggle("heater")
		var app_rate := _span(g, 5000.0)
		g.toggle("heater")
		var decay_rate := -_span(g, 2000.0)
		g.elapsed = 4 * 45000.0
		g.systems["vent"] = {"state": "broken", "t": 0.0}
		var late := _span(g, 2000.0)
		var label := "%s (Mavrine %d)" % ["Custom" if case[0] else "story", case[1]]
		_near(snappedf(seal_rate, 1e-9), want["seal"], label + " seal per second")
		_near(snappedf(broken_rate, 1e-9), want["broken"], label + " dead vent per second")
		_near(snappedf(app_rate, 1e-9), want["appliance"], label + " appliance per second")
		_near(snappedf(decay_rate, 1e-9), want["decay"], label + " decay per second")
		_near(snappedf(late, 1e-9), want["broken"], label + " dead vent at 4 AM")
	# story nights played: every step's stress is exactly the old rule applied to what that step ran with
	var steps := 0
	for night in range(1, 7):
		for seed_number in range(1, 4):
			var g2 := _g({"night": night, "rng": NightWatchStream.seeded(seed_number * 31 + night)})
			var i := 0
			while g2.over == "":
				if i % 30 == 0:
					for nm in g2.systems:
						if g2.systems[nm]["state"] == "broken":
							g2.reboot(nm)
					g2.seal("L", g2.killer["room"] == "officeL")
					g2.seal("R", g2.killer["room"] == "officeR")
					if g2.has_climate:
						if g2.temp < 63 and not g2.heater_on:
							g2.toggle("heater")
						if g2.temp >= 69 and g2.heater_on:
							g2.toggle("heater")
						if g2.temp > 88 and not g2.fan_on:
							g2.toggle("fan")
						if g2.temp <= 78 and g2.fan_on:
							g2.toggle("fan")
				var before := g2.stress
				g2.step(100.0)
				i += 1
				if g2.over != "" and g2.by != "mavrine" and g2.by != "xivvy":
					break
				var on := func(nm: String) -> bool: return g2.systems[nm]["state"] == "ok"
				var bad := ((1 if g2.seals["L"] else 0) + (1 if g2.seals["R"] else 0)) * 1.2 + (0.0 if on.call("vent") else 3.0) \
					+ ((1 if g2.heater_on and on.call("heater") else 0) + (1 if g2.fan_on and on.call("fan") else 0)) * 0.9
				var expected := maxf(0.0, minf(100.0, before + (bad if bad > 0.0 else -2.0) * 0.1))
				if absf(g2.stress - expected) > 1e-9:
					_expect(false, "N%d seed %d at %d ms: stress %s, the old rule says %s" % [night, seed_number, i * 100, str(g2.stress), str(expected)])
					break
				steps += 1
	_expect(steps > 1000, "the story air check ran too few steps (%d)" % steps)


func _span(g: LureLogic, ms: float) -> float:
	var a := g.stress
	var t := 0.0
	while t < ms:
		g.step(50.0)
		t += 50.0
	return (g.stress - a) / (ms / 1000.0)


# --- phantoms, the cast by night, the fan --------------------------------------------------------------------------------

func _phantoms_and_cast() -> void:
	_expect(LureLogic.active_hunters(5).size() == 5, "night 6 does not have five on the floor")
	var visit := func(night: int) -> Array:
		var g := _g({"night": night, "rng": NightWatchStream.fixed(HIT), "choice_rng": NightWatchStream.fixed(0.0), "phantom_levels": {"ferryn": 20, "briselle": 0, "mavrine": 0}, "level": 0})
		var broken := []
		var t := 0.0
		while t < 60000.0 and broken.is_empty():
			for e in g.step(100.0):
				if e["type"] == "broken" and not broken.has(e["system"]):
					broken.append(e["system"])
			t += 100.0
		for i in 2:
			for e in g.step(100.0):
				if e["type"] == "broken" and not broken.has(e["system"]):
					broken.append(e["system"])
		return broken
	_expect(visit.call(1) == ["cams"], "a night-1 visit takes more than her own system: %s" % str(visit.call(1)))
	var late: Array = visit.call(6)
	_expect(late.has("cams") and late.size() >= 2, "a late visit takes only her own system: %s" % str(late))
	var roster := []
	for i in 6:
		var r: Array = LureLogic.active_hunters(i)
		r.sort()
		roster.append(r)
	_expect(roster == [["ferryn"], ["ferryn", "xivvy"], ["briselle", "ferryn", "xivvy"], ["briselle", "ferryn", "wynelle", "xivvy"],
		["briselle", "ferryn", "mavrine", "wynelle", "xivvy"], ["briselle", "mavrine", "solyth", "wynelle", "xivvy"]], "the cast by night differs: %s" % str(roster))
	# in play: someone off tonight never acts
	for seed_number in [1, 2, 3]:
		var n3 := _g({"night": 3, "rng": NightWatchStream.seeded(seed_number), "infinite_stress": true})
		var ev := _run(n3, NightWatchData.NIGHT_MS)
		_expect(not n3.has_climate, "there is a temperature before night 4")
		_expect(not _has(ev, "phantom", "id", "mavrine") and _has(ev, "phantom", "id", "briselle"), "night 3's phantoms are wrong (seed %d)" % seed_number)
		var n4 := _g({"night": 4, "rng": NightWatchStream.seeded(seed_number)})
		_expect(n4.has_climate and n4.climate["wynelle"] > 0 and n4.climate["solyth"] == 0, "night 4 is not the cold only")
		var n6 := _g({"night": 6, "rng": NightWatchStream.seeded(seed_number), "infinite_stress": true})
		ev = _run(n6, NightWatchData.NIGHT_MS)
		_expect(n6.climate["solyth"] > 0 and n6.climate["wynelle"] > 0 and not _has(ev, "phantom", "id", "ferryn"), "night 6 is not both of the pair without Ferryn")
	# the fan only exists while the heat is in
	for night in range(1, 7):
		var g := _g({"night": night, "rng": NightWatchStream.seeded(night)})
		_expect(g.has_fan == (night == 6), "night %d: the fan is %s" % [night, "missing" if night == 6 else "there"])
		if not g.has_fan:
			_expect(not g.toggle("fan"), "night %d: the fan key did something" % night)
			g.systems["fan"] = {"state": "broken", "t": 0.0}
			_expect(not g.reboot("fan"), "night %d: a fan with nothing to reboot" % night)
	var custom := func(sol: int, wyn: int) -> LureLogic:
		return _g({"night": 5, "rng": NightWatchStream.seeded(1), "level": 0, "phantom_levels": NO_PHANTOMS, "climate_levels": {"solyth": sol, "wynelle": wyn}})
	_expect(not custom.call(0, 10).has_fan and custom.call(1, 0).has_fan and custom.call(10, 10).has_fan, "the Custom Night fan follows Solyth's slider")
	_expect(_g({"night": 6, "rng": NightWatchStream.seeded(1)}).toggle("fan"), "night 6: the fan does not work")
	var m := _g({"night": 5, "rng": NightWatchStream.fixed(0.0), "choice_rng": NightWatchStream.fixed(0.0), "level": 0, "phantom_levels": {"ferryn": 0, "briselle": 0, "mavrine": 20}, "climate_levels": {"solyth": 0, "wynelle": 8}})
	var broke_fan := false
	for e in _run(m, 60000):
		broke_fan = broke_fan or (e["type"] == "broken" and e["system"] == "fan")
	_expect(not broke_fan, "Mavrine broke a fan that does not exist")
	# the climb, played: peak air stress rises every night from night 3 and the step 4 -> 5 stays moderate
	var peaks := []
	for night in [3, 4, 5, 6]:
		var sum := 0.0
		var seeds := 24
		for seed_number in range(1, seeds + 1):
			var g := _g({"night": night, "rng": NightWatchStream.seeded(1000 + seed_number)})
			var human := NightWatchStream.seeded(seed_number * 7919 + 13)
			var peak := 0.0
			var next_look := 0.0
			var tms := 0.0
			while g.over == "":
				if tms >= next_look:
					next_look = tms + 3000.0 * (0.5 + human.next())
					for nm in g.systems:
						if g.systems[nm]["state"] == "broken":
							g.reboot(nm)
					g.seal("L", g.killer["room"] == "officeL")
					g.seal("R", g.killer["room"] == "officeR")
					if g.has_climate:
						if g.temp < 63 and not g.heater_on:
							g.toggle("heater")
						if g.temp >= 69 and g.heater_on:
							g.toggle("heater")
						if g.temp > 88 and not g.fan_on:
							g.toggle("fan")
						if g.temp <= 78 and g.fan_on:
							g.toggle("fan")
				g.step(100.0)
				peak = maxf(peak, g.stress)
				tms += 100.0
			sum += peak
		peaks.append(sum / seeds)
	for i in range(1, peaks.size()):
		_expect(peaks[i] > peaks[i - 1] + 5.0, "night %d strains the air more than night %d (%s)" % [i + 3, i + 2, str(peaks)])
	_expect(peaks[2] - peaks[1] <= 35.0, "the night 4 -> 5 step is a cliff (%s)" % str(peaks))


# --- climate -----------------------------------------------------------------------------------------------------------------

func _climate() -> void:
	var idle := _g({"night": 1, "rng": NightWatchStream.fixed(HIT), "level": 0, "phantom_levels": NO_PHANTOMS})
	_expect(not idle.has_climate, "night 1 has a climate")
	_run(idle, 60000)
	_expect(idle.temp == 70.0, "the temperature moved without a climate")
	var cold := _g({"night": 2, "rng": NightWatchStream.fixed(HIT), "level": 0, "phantom_levels": NO_PHANTOMS, "climate_levels": {"solyth": 0, "wynelle": 10}})
	_run(cold, 60000)
	_expect(cold.temp < 70.0, "Wynelle: it did not go down")
	_run(cold, NightWatchData.NIGHT_MS)
	_expect(cold.over == "caught" and cold.by == "wynelle", "the cold did not freeze the office")
	var warm := _g({"night": 2, "rng": NightWatchStream.fixed(HIT), "level": 0, "phantom_levels": NO_PHANTOMS, "climate_levels": {"solyth": 0, "wynelle": 10}})
	var t := 0
	while t < 2000 and warm.over == "":
		if warm.temp < 66.0 and not warm.heater_on:
			warm.toggle("heater")
		if warm.temp > 72.0 and warm.heater_on:
			warm.toggle("heater")
		warm.step(100.0)
		t += 1
	_expect(warm.over == "" and warm.cold == 0.0, "a heater kept on and off did not hold the number")
	var hot := _g({"night": 3, "rng": NightWatchStream.fixed(HIT), "level": 0, "phantom_levels": NO_PHANTOMS, "climate_levels": {"solyth": 10, "wynelle": 0}})
	_run(hot, 60000)
	_expect(hot.temp > 70.0, "Solyth alone: it did not go up")
	_run(hot, NightWatchData.NIGHT_MS)
	_expect(hot.by == "solyth", "the heat did not roast the office")
	var fanned := _g({"night": 3, "rng": NightWatchStream.fixed(HIT), "level": 0, "phantom_levels": NO_PHANTOMS, "climate_levels": {"solyth": 10, "wynelle": 0}})
	t = 0
	while t < 2000 and fanned.over == "":
		if fanned.temp > 80.0 and not fanned.fan_on:
			fanned.toggle("fan")
		if fanned.temp < 74.0 and fanned.fan_on:
			fanned.toggle("fan")
		fanned.step(100.0)
		t += 1
	_expect(fanned.over == "", "the fan did not hold it")
	var both := _g({"night": 4, "rng": NightWatchStream.fixed(0.0), "level": 0, "phantom_levels": {"ferryn": 0, "briselle": 0, "mavrine": 20}, "climate_levels": {"solyth": 8, "wynelle": 8}})
	both.heater_on = true
	var ev := _run(both, 30000)
	var systems := []
	for e in ev:
		if e["type"] == "broken":
			systems.append(e["system"])
	_expect(systems.has("heater") and systems.has("fan"), "with both in play, Mavrine did not break both appliances")
	_expect(not both.toggle("heater"), "a broken appliance was switched on")
	var strain := _g({"night": 2, "rng": NightWatchStream.fixed(HIT), "level": 0, "phantom_levels": NO_PHANTOMS, "climate_levels": {"solyth": 0, "wynelle": 4}})
	strain.toggle("heater")
	_run(strain, 10000)
	_expect(strain.stress > 5.0, "running the heater cost no air")


# --- validate-variety-lure.mjs -------------------------------------------------------------------------------------------

func _variety() -> void:
	# bounds in play, every night
	var x_lo := 1.0 / 1.25
	var x_hi := 1.0 / 0.75
	var p_lo := 1.0 / 1.2
	var p_hi := 1.0 / 0.8
	var rests := 0
	var xs := []
	for night in range(1, 7):
		for seed_number in range(1, 9):
			var g := _g({"night": night, "rng": NightWatchStream.seeded(seed_number * 101 + night)})
			if night < 4:
				_expect(g.temp == 70.0 and g.drift_x == 1.0, "night %d: weather without a climate" % night)
			else:
				_expect(absf(g.temp - 70.0) <= 3.0 + 1e-9 and g.drift_x >= 1.0 / 1.1 - 1e-9 and g.drift_x <= 1.0 / 0.9 + 1e-9, "night %d: the weather is out of bounds" % night)
			var i := 0
			while g.over == "" and i < 2700:
				var ev := g.step(100.0, _bot_input(g, i))
				xs.append(g.killer["tempo"])
				_expect(float(g.killer["tempo"]) >= x_lo - 1e-9 and float(g.killer["tempo"]) <= x_hi + 1e-9, "Xivvy's tempo is out of bounds")
				for id in LureLogic.PHANTOM_IDS:
					var pt: float = g.phantom_ai[id]["tempo"]
					_expect(pt >= p_lo - 1e-9 and pt <= p_hi + 1e-9, "a phantom's tempo is out of bounds")
				for e in ev:
					if e["type"] == "phantom":
						rests += 1
						var base := maxf(5000.0, 10000.0 - (night - 1) * 800.0)
						var rest: float = g.phantom_ai[e["id"]]["cool"]
						_expect(rest >= base * 0.7 - 1e-6 and rest <= base * 1.3 + 1e-6, "night %d: a phantom's rest %s is out of %s +/-30%%" % [night, str(rest), str(base)])
				_expect(g.temp >= 20.0 and g.temp <= 130.0 and g.stress >= 0.0 and g.stress <= 100.0, "temperature or air left its range")
				i += 1
	_expect(rests > 60, "too few phantom visits were sampled (%d)" % rests)
	var lo := 9.0
	var hi := 0.0
	for v in xs:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	_expect(hi - lo > 0.4, "Xivvy's tempo does not vary")
	# tells, kills and defences keep their times on every seed
	for night in [2, 4, 6]:
		for seed_number in range(1, 6):
			for room in ["officeL", "officeR"]:
				var g2 := _g({"night": night, "rng": NightWatchStream.seeded(seed_number * 31 + night), "level": 0, "phantoms": false, "infinite_stress": true})
				g2.killer["room"] = room
				g2.killer["atMs"] = 0.0
				var ms := 0.0
				while g2.over == "" and ms < 20000.0:
					g2.step(100.0)
					ms += 100.0
				_expect(g2.by == "xivvy" and ms == 5200.0, "night %d seed %d: %s kills at %s ms, not 5200" % [night, seed_number, room, str(ms)])
			var g3 := _g({"night": night, "rng": NightWatchStream.seeded(seed_number * 31 + night), "level": 0, "phantoms": false, "infinite_stress": true})
			g3.killer["room"] = "officeL"
			g3.killer["atMs"] = 0.0
			g3.seal("L", true)
			var ms3 := 0.0
			var got := false
			while ms3 < 5000.0 and not got:
				for e in g3.step(100.0):
					got = got or e["type"] == "retreat"
				ms3 += 100.0
			_expect(got and ms3 == 2000.0 and g3.killer["room"] == "storage" and g3.over == "", "night %d seed %d: a seal answers after 2000 ms, not %s" % [night, seed_number, str(ms3)])
	for seed_number in range(1, 6):
		var g4 := _g({"night": 3, "rng": NightWatchStream.seeded(seed_number), "level": 0, "phantom_levels": {"ferryn": 20, "briselle": 0, "mavrine": 0}})
		var from := -1.0
		var to := -1.0
		var tt := 0.0
		while tt < 120000.0 and to < 0.0:
			g4.step(100.0)
			if not g4.phantom.is_empty() and from < 0.0:
				from = g4.elapsed
			if from >= 0.0 and g4.phantom.is_empty():
				to = g4.elapsed
			tt += 100.0
		_expect(to >= 0.0 and to - from == 4000.0, "seed %d: a phantom shows for %s ms, not 4000" % [seed_number, str(to - from)])
	# same seed, same night; different seeds, different nights
	for night in [2, 3, 5, 6]:
		var seen := {}
		for seed_number in range(1, 9):
			var a := _trace(night, seed_number)
			_expect(a == _trace(night, seed_number), "night %d seed %d: the same seed played two nights" % [night, seed_number])
			seen[a] = true
		_expect(seen.size() >= 7, "night %d: 8 seeds gave %d different nights" % [night, seen.size()])


func _trace(night: int, seed_number: int) -> String:
	var g := _g({"night": night, "rng": NightWatchStream.seeded(seed_number)})
	var out := []
	var i := 0
	while i < 2700 and g.over == "":
		for e in g.step(100.0, _bot_input(g, i)):
			out.append("%d:%s:%s" % [i, e["type"], String(e.get("room", e.get("system", e.get("id", e.get("side", e.get("by", ""))))))])
		i += 1
	return ",".join(out)


# --- the 2D game's own draws -----------------------------------------------------------------------------------------------

func _golden() -> void:
	var text := FileAccess.get_file_as_string(GOLDEN)
	var d = JSON.parse_string(text)
	_expect(d is Dictionary, "the golden file did not load")
	if not (d is Dictionary):
		return
	for seed_key in d["rng"]:
		var s := NightWatchStream.seeded(int(seed_key))
		for v in d["rng"][seed_key]:
			_near(s.next(), float(v), "golden mulberry32(%s)" % seed_key)
	for t in d["traces"]:
		var g := _g({"night": int(t["night"]), "rng": NightWatchStream.seeded(int(t["seed"]))})
		var out := []
		var i := 0
		while i < NightWatchData.NIGHT_MS / 100.0 and g.over == "":
			for e in g.step(100.0, _bot_input(g, i)):
				out.append("%d:%s:%s" % [i, e["type"], String(e.get("room", e.get("system", e.get("id", e.get("side", e.get("by", ""))))))])
			i += 1
		var got := ",".join(out)
		_expect(got == String(t["events"]), "night %d seed %d: the 3D shift differs from the 2D one%s" % [int(t["night"]), int(t["seed"]), _first_diff(got, String(t["events"]))])
		_expect(i == int(t["steps"]) and absf(g.stress - float(t["stress"])) < 1e-4 and absf(g.temp - float(t["temp"])) < 1e-4 and g.elapsed == float(t["elapsed"]),
			"night %d seed %d: the end state differs (stress %s vs %s, temp %s vs %s)" % [int(t["night"]), int(t["seed"]), str(g.stress), str(t["stress"]), str(g.temp), str(t["temp"])])
	# QA's bots on the 20/20/20/20 Custom Night
	var wins := {}
	var ai := {"wynelle": 20, "xivvy": 20, "mavrine": 20, "briselle": 20, "solyth": 20, "ferryn": 20}
	for bot in ["sharp", "sharpnl", "human", "ear"]:
		wins[bot] = 0
		for seed_number in range(int(d["custom"]["first"]), int(d["custom"]["first"]) + int(d["custom"]["count"])):
			if _qa_bot(seed_number, bot, ai):
				wins[bot] += 1
	var want: Dictionary = d["custom"]["wins"]
	_expect(int(wins["sharp"]) == int(want["sharp"]) and int(wins["sharpnl"]) == int(want["sharpnl"]) and int(wins["human"]) == int(want["human"]) and int(wins["ear"]) == int(want["ear"]),
		"the QA bots' wins on 20/20/20/20 differ from the 2D game's: %s vs %s" % [str(wins), str(want)])


func _first_diff(a: String, b: String) -> String:
	var x := a.split(",")
	var y := b.split(",")
	for i in mini(x.size(), y.size()):
		if x[i] != y[i]:
			return " (event %d: %s vs %s)" % [i, x[i], y[i]]
	return " (%d vs %d events)" % [x.size(), y.size()]


## QA's csim bots (validate-lure-air.mjs): each decides every 50 ms on what it saw LAG ms ago.
func _qa_bot(seed_number: int, bot: String, ai: Dictionary) -> bool:
	var g := _g({"night": 5, "rng": NightWatchStream.seeded(seed_number), "custom": true, "level": ai["xivvy"], "phantom_levels": ai, "climate_levels": ai})
	var lag := (300 if bot == "sharp" or bot == "sharpnl" else 800) / 50
	var hist := []
	var band := [62.0, 66.0, 91.0, 86.0] if bot == "sharp" or bot == "sharpnl" else [61.0, 68.0, 92.0, 84.0]
	while g.over == "":
		var broken := []
		for nm in g.systems:
			if g.systems[nm]["state"] == "broken":
				broken.append(nm)
		hist.append({"room": g.killer["room"], "broken": broken, "temp": g.temp})
		if hist.size() > lag + 1:
			hist.pop_front()
		var p: Dictionary = hist[0]
		for nm in p["broken"]:
			if g.systems[nm]["state"] == "broken":
				g.reboot(nm)
		for side in ["L", "R"]:
			var at: bool = p["room"] == "office" + side
			if at and not g.seals[side]:
				g.seal(side, true)
			elif not at and g.seals[side]:
				g.seal(side, false)
		var room: String = p["room"]
		if bot == "sharp" and (room == "storage" or room.begins_with("vent")) and g.online("audio") and g.lure_cool <= 0.0:
			g.lure("lobby")
		if p["temp"] < band[0] and not g.heater_on and g.online("heater"):
			g.toggle("heater")
		if g.heater_on and p["temp"] > band[1]:
			g.toggle("heater")
		if g.has_fan and p["temp"] > band[2] and not g.fan_on and g.online("fan"):
			g.toggle("fan")
		if g.fan_on and p["temp"] < band[3]:
			g.toggle("fan")
		var watch := room if bot != "ear" and g.online("cams") and (room.begins_with("storage") or room.begins_with("vent")) else ""
		g.step(50.0, {"watch": watch})
	return g.over == "win"


# --- the shift scene ---------------------------------------------------------------------------------------------------------

func _make(host: Node, night: int, seed_number: int, custom := {}) -> LureGame:
	NightWatchSession.start_mode("lure", night, custom, seed_number)
	var game := (load("res://scenes/night_watch_lure.tscn") as PackedScene).instantiate() as LureGame
	game.manual_clock = true
	host.add_child(game)
	return game


func _scene(host: Node) -> void:
	_expect(NightWatchModeRegistry.playable("lure") and NightWatchModeRegistry.scene_for("lure") == "res://scenes/night_watch_lure.tscn", "Dead Air is not in the registry")
	NightWatchSave.path = "user://night_watch_lure_test.cfg"
	NightWatchSave.reset()
	# every shift starts through the board's path
	for lv in range(1, 7):
		_expect(NightWatchModeRegistry.prepare("lure", lv) == "res://scenes/night_watch_lure.tscn" and NightWatchSession.mode_id == "lure" and NightWatchSession.night == lv, "shift %d does not start from the board" % lv)
	var game := _make(host, 4, 4242)
	await host.get_tree().process_frame
	_expect(game is NightWatchMode and game.mode_id == "lure" and game.level == 4 and game.seed_value == 4242 and game.level_name() == "NIGHT 4", "the shift scene did not read its session")
	_expect(game.office.slabs.size() == 2 and game.world.rooms.size() == 8 and game.hud.cam_buttons.size() == 8, "the office, the hall or the monitor panel is missing")
	for prop_name in ["Shell", "Details"]:
		for id in LureData.ROOMS:
			_expect(game.world.props.has("%s/%s" % [id, prop_name]), "%s has no %s" % [id, prop_name])
	var cubes := 0
	for key in game.world.props:
		var st := NightWatchArt.prop_stats(game.world.props[key])
		cubes += int(st["cubes"])
		_expect((st["bad_emissive"] as Array).is_empty(), "%s has a cube that glows without a glowing name" % key)
	_expect(cubes > 300, "the hall is too bare (%d cubes)" % cubes)
	# stations: DOOR seals the vent, LIGHT runs the heater / fan, the prompts say so
	var st: Dictionary = game.office.stations
	_expect((st["doorL_door"] as NightWatchStation).get_prompt().begins_with("SEAL LEFT VENT") and (st["doorL_light"] as NightWatchStation).get_prompt().begins_with("HEATER"), "the panel prompts do not name the vents and appliances")
	(st["doorR_door"] as NightWatchStation).activate(game.player)
	game.advance_ms(10.0)
	_expect(game.sim.seals["R"] and is_equal_approx(game.office.slab_progress["doorR"], 1.0), "the right DOOR button did not seal the right vent and shut the cover")
	(st["doorR_door"] as NightWatchStation).activate(game.player)
	game.advance_ms(10.0)
	_expect(not game.sim.seals["R"] and is_equal_approx(game.office.slab_progress["doorR"], 0.0), "pressing it again did not open the vent")
	(st["doorL_light"] as NightWatchStation).activate(game.player)
	_expect(game.sim.heater_on, "the left LIGHT button did not start the heater on night 4")
	var msg := String((st["doorR_light"] as NightWatchStation).activate(game.player))
	_expect(not game.sim.fan_on and msg.contains("NOTHING TO COOL"), "the fan did something on night 4")
	# the monitor and its panel
	game.open_monitor("lobby")
	_expect(game.monitor_up and game.hud.monitor_root.visible and game.hud.cam_label.text.contains("RECEPTION") and game.hud.feed_camera.transform == game.world.camera_transform("lobby"), "the monitor did not show the lobby camera")
	game.select_camera("ballpit")
	_expect(game.hud.cam_label.text == "CAM 4  LIVE ROOM", "the camera label is wrong: %s" % game.hud.cam_label.text)
	_expect(game.do_lure() and game.sim.lure_cool > 0.0 and game.sim.killer["target"] == "ballpit", "LURE did not call Xivvy to the room on screen")
	game.sim.systems["cams"] = {"state": "broken", "t": 0.0}
	game.advance_ms(10.0)
	_expect(game.panel.out_label.visible and game.watching() == "", "a broken camera system still showed a picture")
	_expect(game.do_reboot("cams") and game.sim.systems["cams"]["state"] == "reboot" and not game.do_reboot("cams"), "REBOOT did not start, or started twice")
	game.advance_ms(6100.0)
	_expect(game.sim.online("cams") and not game.panel.out_label.visible, "the cameras never came back")
	game.close_monitor()
	game.queue_free()
	await host.get_tree().process_frame

	# Xivvy walks the hall: moving her one room is a walk, not a placement
	game = _make(host, 3, 99)
	await host.get_tree().process_frame
	game.set_process(false)
	game.manual_clock = false
	game.sim.killer["room"] = "lobby"
	game._place_hunters()
	var model := game._models["xivvy"] as Node3D
	var from_pos := model.position
	game.sim.killer["room"] = "arcade"
	game._place_hunters()
	game._animate_models(0.1)
	_expect(model.position.distance_to(from_pos) < 1.5, "Xivvy was placed in the next room instead of walking there")
	var longest := 0.0
	var last := model.position
	for i in 120:
		game._animate_models(0.1)
		longest = maxf(longest, model.position.distance_to(last))
		last = model.position
	_expect(model.position.distance_to(game.world.stand_position("arcade", 0)) < 0.2, "Xivvy did not arrive in the arcade")
	_expect(longest <= NightWatchWalker.MAX_SPEED * 0.1 + 0.01, "Xivvy moved %.2f m in one step" % longest)
	# the vent run: storage -> left vent -> the vent opening in the office wall, with one hidden leap from the duct to the office hall
	var legs := game.paths.legs_for("storage", "officeL")
	var jumps := 0
	for leg in legs:
		if bool(leg["jump"]):
			jumps += 1
	_expect(jumps == 1 and legs.size() >= 5, "the way from the storage room to the left opening is not a walk with one hidden leap")
	var bad_pairs := 0
	for a in LureData.GRAPH:
		for b in LureData.GRAPH:
			if a != b and game.paths.legs_for(String(a), String(b)).size() < 2:
				bad_pairs += 1
	_expect(bad_pairs == 0, "%d room pairs have no route" % bad_pairs)
	# in a vent she crawls: the pose follows her into the crawlspace and out again (the drop and the rise are one-shots, the crawl loops)
	game.sim.killer["room"] = "ventl"
	game._place_hunters()
	game._animate_models(0.05)
	_expect(game._pose_state.get("xivvy", "") == "vent_enter", "Xivvy dropped into the crawlspace without the vent_enter pose (%s)" % str(game._pose_state.get("xivvy", "")))
	for i in 12:
		game._animate_models(0.1)
	_expect(game._pose_state.get("xivvy", "") == "vent", "Xivvy in the crawlspace is not crawling (%s)" % str(game._pose_state.get("xivvy", "")))
	if game._players.has("xivvy"):
		_expect((game._players["xivvy"] as AnimationPlayer).current_animation == NightWatchPoses.clip_name("vent_crawl"), "the vent crawl clip is not playing")
	game.sim.killer["room"] = "storage"
	game._place_hunters()
	game._animate_models(0.05)
	_expect(game._pose_state.get("xivvy", "") == "vent_exit", "Xivvy climbing out of the crawlspace has no vent_exit")
	for i in 12:
		game._animate_models(0.1)
	_expect(game._pose_state.get("xivvy", "") == "", "Xivvy kept the vent pose after leaving the crawlspace")
	game.manual_clock = true
	game.queue_free()
	await host.get_tree().process_frame

	# a loss: Xivvy gets in through an open vent
	game = _make(host, 2, 7)
	await host.get_tree().process_frame
	game.sim.killer["room"] = "officeL"
	game.sim.killer["atMs"] = 5100.0
	game.advance_ms(200.0)
	_expect(game.state == LureGame.State.LOST and game.last_death.get("by", "") == "xivvy", "an open vent with Xivvy in it did not lose the night")
	var closing := 0
	while game.death_moment.is_open() and closing < 40:
		game.death_moment.dismiss()
		closing += 1
	await host.get_tree().process_frame
	_expect(game.hud.end_root.visible and game.hud.end_title.text == "CAUGHT" and not game.hud.end_next.visible and NightWatchSave.cleared_levels("lure").is_empty(), "the loss card is wrong, or a loss saved a clear")
	game.queue_free()
	await host.get_tree().process_frame
	# a win saves a clear for this mode only and opens the next shift
	game = _make(host, 1, 5)
	await host.get_tree().process_frame
	game.sim.phantoms_on = false
	game.sim.elapsed = NightWatchData.NIGHT_MS - 150.0
	game.advance_ms(200.0)
	_expect(game.state == LureGame.State.WON and game.hud.end_root.visible and game.hud.end_title.text == "NIGHT 1 COMPLETE" and game.hud.end_next.visible, "the win card is wrong")
	_expect(NightWatchSave.cleared_levels("lure") == [1] and NightWatchSave.level_open("lure", 2) and not NightWatchSave.level_open("lure", 3) and NightWatchSave.cleared_levels("classic").is_empty(), "the win did not save under lure and open Night 2")
	game.queue_free()
	await host.get_tree().process_frame
	# a lost night 6 and a won night 6 end the mode (no next card)
	game = _make(host, 6, 5)
	await host.get_tree().process_frame
	_expect(game.sim.has_fan and game.level == 6, "night 6 has no fan")
	game.sim.phantoms_on = false
	game.sim.killer["room"] = "lobby"
	game.sim.lvl = 0
	game.sim.elapsed = NightWatchData.NIGHT_MS - 150.0
	game.advance_ms(200.0)
	_expect(game.state == LureGame.State.WON and not game.hud.end_next.visible and NightWatchSave.cleared_levels("lure") == [1, 6], "the last shift offers a next card, or was not saved")
	game.queue_free()
	await host.get_tree().process_frame
	# Retry replays the seed: the same session seed builds the same shift
	var a1 := _make(host, 5, 31337)
	await host.get_tree().process_frame
	var log1 := _scene_log(a1, 600)
	a1.queue_free()
	await host.get_tree().process_frame
	var a2 := _make(host, 5, 31337)
	await host.get_tree().process_frame
	var log2 := _scene_log(a2, 600)
	_expect(log1 == log2 and log1.length() > 0, "the same seed did not replay the same shift in the scene")
	a2.queue_free()
	await host.get_tree().process_frame
	# Custom Night: the sliders are the levels; a win saves a score, not a clear
	var sliders := {"wynelle": 0, "xivvy": 15, "mavrine": 3, "briselle": 3, "solyth": 0, "ferryn": 3}
	game = _make(host, 1, 77, sliders)
	await host.get_tree().process_frame
	_expect(game.is_custom and game.sim.is_custom and game.sim.lvl == 15 and game.sim.phantom_base("ferryn") == 3 and not game.sim.has_climate and game.hud.night_label.text == "CUSTOM NIGHT", "the Custom Night sliders did not feed the rules")
	game.sim.elapsed = NightWatchData.NIGHT_MS - 150.0
	game.sim.phantoms_on = false
	game.sim.killer["room"] = "lobby"
	game.sim.lvl = 0
	game.advance_ms(200.0)
	_expect(game.state == LureGame.State.WON and NightWatchSave.best_score("lure") == 24 * NightWatchModesData.POINTS_PER_LEVEL and NightWatchSave.stars("lure") == ["the-real-one"], "the Custom Night win did not save the score and the preset's star")
	_expect(NightWatchSave.cleared_levels("lure") == [1, 6], "a Custom Night win changed the cleared shifts")
	game.queue_free()
	await host.get_tree().process_frame
	NightWatchSave.reset()
	NightWatchSave.path = NightWatchSave.DEFAULT_PATH
	NightWatchSession.start(1)


func _scene_log(game: LureGame, steps: int) -> String:
	var out := []
	for i in steps:
		game.sim.seal("L", game.sim.killer["room"] == "officeL")
		for e in game.sim.step(100.0, {}):
			out.append("%d:%s:%s" % [i, e["type"], String(e.get("room", e.get("system", "")))])
	return ",".join(out)
