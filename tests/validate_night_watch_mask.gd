extends RefCounted

## Night Watch Masked Hours (3D): the rules port reproduces the 2D game's numbers (whole shifts played by a fixed bot match the 2D logic's event
## logs, from tests/fixtures/night_watch_mask_golden.json), the hall walker, the rusher, the vent hunters, the music box, the battery, the dark
## and the controls behave as in the original's Masked Hours validator, a shift is deterministic by seed, and the shift scene (every night starts from the Shift
## Board, wins and loses, saves, Custom Night, Retry) works. Scene checks live further down.

const CAMS := ["music", "costume", "gallery", "ballroom", "crawl", "ductL", "ductR", "hall"]
const ALL_ZERO := {"thessine": 0, "umbriel": 0, "verrine": 0, "haelith": 0, "ilyra": 0, "glyra": 0, "nyxie": 0}

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _game(night: int, seed_number: int, levels := {}, custom := false, infinite := false) -> MaskLogic:
	return MaskLogic.new(night, NightWatchMulberry.new(seed_number), {"levels": levels, "custom": custom, "infinite_battery": infinite})


## One hunter (or none) on an otherwise empty floor: the 2D tests' `quiet(...)`.
func _only(overrides: Dictionary, night := 3, seed_number := 1) -> MaskLogic:
	var levels := ALL_ZERO.duplicate()
	for k in overrides:
		levels[k] = overrides[k]
	return _game(night, seed_number, levels, true)


## The state-reading bot of the golden fixture (the golden in tests/fixtures, recorded from the original 2D game).
func _bot(kind: String, g: MaskLogic) -> Dictionary:
	if kind == "idle":
		return {}
	var s := g.s
	var e := float(s["elapsed"])
	var occ := {}
	for id in MaskData.VENT_HUNTERS:
		var h := g.vent_state(id)
		if String(h["state"]) != "away":
			occ = h
			break
	var inp := {
		"mask": String(s["hall"]["thessine"]["state"]) == "office",
		"monitor": int(floor(e / 7000.0)) % 3 == 0,
		"cam": CAMS[int(floor(e / 3500.0)) % 8],
		"lightH": String(s["rush"]["state"]) == "run" and int(floor(e / 200.0)) % 2 == 0,
		"lightL": not occ.is_empty() and String(occ["state"]) == "vent" and String(occ["side"]) == "L",
		"lightR": not occ.is_empty() and String(occ["state"]) == "vent" and String(occ["side"]) == "R",
		"winding": float(s["box"]) < 60.0,
		"lamp": int(floor(e / 20000.0)) % 2 == 1,
	}
	if kind == "dark":
		inp["lightL"] = false
		inp["lightR"] = false
		inp["lightH"] = true
	return inp


static func _ev_string(e: Dictionary) -> String:
	var parts := []
	for k in ["type", "id", "room", "side", "step", "n", "by"]:
		parts.append(str(e.get(k, "")))
	return "|".join(parts)


## Play whole steps of dt ms until the shift ends: returns the event strings ("<step>|<type>|...").
func _play(g: MaskLogic, kind: String, dt: float, cap := 4000) -> Array:
	var log := []
	var n := 0
	while String(g.s["over"]) == "" and n < cap:
		for e in g.step(dt, _bot(kind, g)):
			log.append("%d|%s" % [n, _ev_string(e)])
		n += 1
	return log


func _until(g: MaskLogic, input: Dictionary, ms: float, dt := 50.0) -> Array:
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
	_check_controls()
	await _check_scene(host)
	await _check_call(host)
	await _check_admin(host)
	if _failures == 0:
		print("  night_watch_mask  the 2D rules (golden shifts, hall walker, rusher, vent hunters, music box, battery, dark, controls) and the shift scene (nights, win, loss, saves, Custom Night, retry)")
	return _failures


# --- the tables ---------------------------------------------------------------------------------------------------------

func _check_data() -> void:
	for room in MaskData.GRAPH:
		for next in MaskData.GRAPH[room]:
			_expect((MaskData.GRAPH[next] as Array).has(room), "%s -> %s is not mirrored" % [room, next])
	_expect(MaskData.cam_rooms() == ["music", "costume", "gallery", "ballroom", "crawl", "ductL", "ductR", "hall"], "the eight cameras are not numbered as in the 2D game")
	_expect(MaskData.cam_label("hall") == "CAM 8 · MAIN HALL" and MaskData.cam_label("ductL") == "CAM 6 · LEFT AIR VENT" and MaskData.cam_label("music") == "CAM 1 · PRIZE CORNER", "camera labels are not the FNAF 2 floor plan's")
	var dist := NightWatchData.distances_to("office", MaskData.GRAPH)
	_expect(dist.size() == MaskData.GRAPH.size(), "a room cannot reach the office")
	_expect(MaskLogic.next_toward("costume") == "ballroom" and MaskLogic.next_toward("ballroom") == "hall" and MaskLogic.next_toward("hall") == "office"
		and MaskLogic.next_toward("ductR") == "ventR" and MaskLogic.next_toward("crawl") == "ductL", "routes toward the office are wrong")
	_expect(MaskLogic.active_hunters(0) == ["thessine", "nyxie"] and MaskLogic.active_hunters(1).has("verrine") and MaskLogic.active_hunters(1).has("glyra")
		and not MaskLogic.active_hunters(1).has("umbriel") and MaskLogic.active_hunters(2).has("umbriel") and MaskLogic.active_hunters(5).size() == 7,
		"who is on the floor each night is wrong")
	_expect(MaskLogic.first_night("umbriel") == 3 and MaskLogic.first_night("haelith") == 4 and MaskLogic.first_night("ilyra") == 5 and MaskLogic.first_night("verrine") == 2,
		"the first night of each hunter is wrong")
	_expect(MaskLogic.flash_seconds(0) == 66.0 and MaskLogic.flash_seconds(4) == 28.0, "the flashlight seconds are not the 2D game's scaled values")
	_expect(MaskLogic.dark_grace_ms(1) == 12050.0 and MaskLogic.dark_grace_ms(20) == 4000.0, "Nyxie's dark time is wrong")
	_expect(MaskLogic.rush_flashes(3) == 3 and MaskLogic.rush_flashes(10) == 4 and MaskLogic.rush_flashes(16) == 5 and MaskLogic.rush_run_ms(10) == 2100.0 and MaskLogic.rush_door_ms(10) == 1700.0,
		"Umbriel's tuning is wrong")
	_expect(MaskLogic.box_decay_for_level(0) == 0.0 and is_equal_approx(MaskLogic.box_decay_for_level(8), 2.3), "a Custom Night Glyra level does not set the drain")
	_expect(MaskData.call_lines(1).size() == 6 and MaskData.call_lines(6).size() == 1 and MaskData.call_lines(2).size() == 2, "Zellia's script differs from the 2D game's")
	# the seeded stream is the 2D mulberry32: the first draws of seed 1 and 42
	var m := NightWatchMulberry.new(1)
	_expect(absf(m.next() - 0.6270739405881613) < 1e-12, "mulberry32(1) does not start with 0.62707394...")
	var m2 := NightWatchMulberry.new(42)
	_expect(absf(m2.next() - 0.6011037519201636) < 1e-12, "mulberry32(42) does not start with 0.60110375...")


# --- the 2D game's shifts, event for event ---------------------------------------------------------------------------------

func _check_golden() -> void:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/night_watch_mask_golden.json")
	var data = JSON.parse_string(text)
	_expect(data is Dictionary and (data["runs"] as Array).size() >= 15, "the golden fixture is missing")
	if not (data is Dictionary):
		return
	var checked := 0
	var events_total := 0
	for run in data["runs"]:
		var levels := {}
		for k in run.get("levels", {}):
			levels[k] = int(run["levels"][k])
		var g := _game(int(run["night"]), int(run["seed"]), levels, bool(run.get("custom", false)), bool(run.get("infiniteBattery", false)))
		var log := _play(g, String(run["kind"]), float(data["dt"]))
		var want: Array = run["events"]
		var label := "night %d seed %d %s" % [int(run["night"]), int(run["seed"]), run["kind"]]
		var same := log.size() == want.size()
		if same:
			for i in log.size():
				if String(log[i]) != String(want[i]):
					same = false
					print("  FAIL  %s: event %d is %s, the 2D game has %s" % [label, i, log[i], want[i]])
					_failures += 1
					break
		else:
			print("  FAIL  %s: %d events, the 2D game has %d" % [label, log.size(), want.size()])
			_failures += 1
		var sum: Dictionary = run["summary"]
		var s := g.s
		_expect(absf(float(s["elapsed"]) - float(sum["elapsed"])) < 1e-6 and absf(float(s["battery"]) - float(sum["battery"])) < 2e-6 and absf(float(s["box"]) - float(sum["box"])) < 2e-6
			and String(s["over"]) == String(sum["over"]) and String(s["by"]) == String(sum["by"]) and int(s["flashCount"]) == int(sum["flashCount"])
			and int(s["ventFlashCount"]) == int(sum["ventFlashCount"]) and int(s["rush"]["runs"]) == int(sum["rushRuns"]),
			"%s: the final state differs from the 2D game's (%s %s battery %.4f box %.4f)" % [label, s["over"], s["by"], s["battery"], s["box"]])
		checked += 1
		events_total += log.size()
	print("  mask golden: %d shifts, %d events identical to the 2D logic" % [checked, events_total])


# --- the rules ---------------------------------------------------------------------------------------------------------

func _check_rules() -> void:
	# a quiet floor and a wound box: nothing happens until 6 AM
	var quiet := _only({})
	var qlog := _until(quiet, {"winding": true}, 271000.0, 500.0)
	_expect(String(quiet.s["over"]) == "win" and qlog.size() == 1 and String(qlog[0]["type"]) == "win", "a night with every hunter at level 0 was not a quiet win")
	# determinism: same seed, same night; another seed, another night
	var a := _play(_game(5, 123), "bot", 100.0)
	var b := _play(_game(5, 123), "bot", 100.0)
	var c := _play(_game(5, 124), "bot", 100.0)
	_expect(a == b and a.size() > 20, "the same seed did not give the same night twice")
	_expect(a != c, "another seed gave the same night")
	# AI steps up at 3 AM and 4 AM
	var step_game := _game(1, 1, {"thessine": 6})
	_expect(step_game.level("thessine") == 6, "level before 3 AM")
	step_game.s["elapsed"] = 3.0 * NightWatchData.HOUR_MS
	_expect(step_game.level("thessine") == 7, "level at 3 AM")
	step_game.s["elapsed"] = 4.0 * NightWatchData.HOUR_MS
	_expect(step_game.level("thessine") == 8 and _game(1, 1, {"thessine": 0}).level("thessine") == 0, "level at 4 AM / a sleeper never wakes")
	# the hall walker: in the office, the mask sends her away; no mask and she notices after the window
	var walker := _only({"thessine": 10})
	var th: Dictionary = walker.s["hall"]["thessine"]
	th["state"] = "office"
	th["room"] = "office"
	var wlog := _until(walker, {"mask": true}, 2600.0, 100.0)
	_expect(_has(wlog, "leave") and String(th["state"]) == "away" and String(th["room"]) == "costume", "the mask did not send Thessine home")
	var bare := _only({"thessine": 10})
	var bh: Dictionary = bare.s["hall"]["thessine"]
	bh["state"] = "office"
	bh["room"] = "office"
	var blog := _until(bare, {}, 3600.0, 100.0)
	_expect(String(bare.s["over"]) == "caught" and String(bare.s["by"]) == "thessine" and _has(blog, "caught") and float(bare.s["elapsed"]) >= 3500.0 and float(bare.s["elapsed"]) <= 3600.0,
		"an unmasked Thessine did not notice after 3.5 s (%s at %.0f)" % [bare.s["over"], bare.s["elapsed"]])
	var fickle := _only({"thessine": 10})
	var fh: Dictionary = fickle.s["hall"]["thessine"]
	fh["state"] = "office"
	fh["room"] = "office"
	_until(fickle, {"mask": true}, 1000.0, 100.0)
	var flog := _until(fickle, {}, 1300.0, 100.0)
	_expect(String(fickle.s["over"]) == "caught" and _has(flog, "caught"), "taking the mask off while she lingers was not caught after 1.2 s")
	# her walk: ballroom (3-5 s), then the hall in four steps, then the office
	var stroll := _only({"thessine": 20}, 3, 7)
	var kinds := []
	for e in _until(stroll, {}, 60000.0, 50.0):
		if not kinds.has(String(e["type"])):
			kinds.append(String(e["type"]))
		if String(e["type"]) == "office":
			break
	_expect(kinds.slice(0, 4) == ["room", "hall", "step", "office"], "Thessine's walk is not room, hall, steps, office (%s)" % str(kinds))
	var hallgame := _only({"thessine": 10})
	var hh: Dictionary = hallgame.s["hall"]["thessine"]
	hh["state"] = "hall"
	hh["room"] = "hall"
	hh["need"] = 2000.0
	_until(hallgame, {"lightH": true}, 5000.0, 100.0)
	_expect(int(hh["step"]) == 0, "Thessine advanced down the hall in the hall light")
	hallgame.step(1.0, {"lightH": false})
	_until(hallgame, {"monitor": true, "cam": "hall"}, 100.0, 100.0)
	# Verrine: the matching light drives her off, the wrong side does not, the mask slows her
	var vv := _only({"verrine": 10}, 3, 3)
	vv.s["vent"].merge({"state": "vent", "room": "ventL", "side": "L", "t": 0.0, "lit": 0.0, "wait": 6000.0}, true)
	var vlog := _until(vv, {"lightL": true}, 1500.0, 50.0)
	_expect(_has(vlog, "ventRetreat") and String(vv.s["vent"]["state"]) == "away", "the matching vent light did not send Verrine off")
	var wrong := _only({"verrine": 10}, 3, 3)
	wrong.s["vent"].merge({"state": "vent", "room": "ventL", "side": "L", "t": 0.0, "lit": 0.0, "wait": 6000.0}, true)
	_until(wrong, {"lightR": true}, 6100.0, 50.0)
	_expect(String(wrong.s["over"]) == "caught" and String(wrong.s["by"]) == "verrine", "the wrong vent light saved the night")
	var masked := _only({"verrine": 10}, 3, 3)
	masked.s["vent"].merge({"state": "vent", "room": "ventL", "side": "L", "t": 0.0, "lit": 0.0, "wait": 6000.0}, true)
	_until(masked, {"mask": true}, 6300.0, 50.0)
	_expect(String(masked.s["over"]) == "" and float(masked.s["vent"]["t"]) < 6000.0, "the mask did not slow Verrine (t=%.0f)" % float(masked.s["vent"]["t"]))
	_until(masked, {"mask": true}, 600.0, 50.0)
	_expect(String(masked.s["over"]) == "caught", "a masked Verrine never reached 6 s of her clock")
	# Haelith: a throw sends her off, she fetches it to the other duct, a second throw sends her home
	var hael := _only({"haelith": 10}, 4, 3)
	hael.s["haelith"].merge({"state": "vent", "room": "ventL", "side": "L", "t": 0.0, "lit": 0.0, "step": 0, "wait": 3400.0}, true)
	var hl1 := _until(hael, {"lightL": true}, 600.0, 50.0)
	_expect(_has(hl1, "fetch") and String(hael.s["haelith"]["state"]) == "fetch", "a quick light did not send Haelith off to fetch it across")
	var hl2 := _until(hael, {}, 1600.0 + 3000.0, 50.0)
	_expect(_has(hl2, "duct") and String(hael.s["haelith"]["side"]) == "R", "Haelith did not come down the other duct")
	for i in 80:
		hael.step(50.0, {"lightR": String(hael.s["haelith"]["state"]) == "vent"})
		if String(hael.s["haelith"]["state"]) == "away":
			break
	_expect(String(hael.s["haelith"]["state"]) == "away" and String(hael.s["over"]) == "", "the second throw did not send Haelith home")
	# Ilyra: frozen in the light, creeps in the dark
	var ily := _only({"ilyra": 10}, 5, 3)
	ily.s["ilyra"].merge({"state": "duct", "room": "ductL", "side": "L", "t": 0.0, "lit": 0.0, "step": 1, "need": 2600.0}, true)
	_until(ily, {"lightL": true, "monitor": true, "cam": "ductL"}, 900.0, 50.0)
	_expect(int(ily.s["ilyra"]["step"]) == 1, "Ilyra crept in the light")
	var ilog := _until(ily, {}, 9500.0, 50.0)
	_expect(_has(ilog, "creep") and _has(ilog, "vent"), "Ilyra did not creep to the vent in the dark")
	# one vent hunter at a time, whatever the player does
	var crowd := _game(5, 99, {"verrine": 20, "haelith": 20, "ilyra": 20, "thessine": 0, "umbriel": 0, "glyra": 0, "nyxie": 0}, true, true)
	var worst := 0
	for i in 2400:
		crowd.step(100.0, {"lightL": i % 7 < 3, "lightR": i % 11 < 2})
		if String(crowd.s["over"]) != "":
			crowd = _game(5, 100 + i, {"verrine": 20, "haelith": 20, "ilyra": 20, "thessine": 0, "umbriel": 0, "glyra": 0, "nyxie": 0}, true, true)
		var out := 0
		for id in MaskData.VENT_HUNTERS:
			if String(crowd.vent_state(id)["state"]) != "away":
				out += 1
		worst = maxi(worst, out)
	_expect(worst == 1, "more than one vent hunter was out at once (or none ever came): %d" % worst)
	# the grace: no Haelith before 1 AM, no Ilyra before 2 AM
	var grace := _game(5, 4, {"verrine": 0, "haelith": 20, "ilyra": 0, "thessine": 0, "umbriel": 0, "glyra": 0, "nyxie": 0}, true, true)
	_until(grace, {}, 44000.0, 100.0)
	_expect(String(grace.s["haelith"]["state"]) == "away", "Haelith came before 1 AM")
	# the rusher: she crouches, runs, and N flashes drive her back; one fewer does not
	var rush := _only({"umbriel": 10}, 3, 5)
	rush.s["rush"].merge({"state": "poised", "room": "ballroom", "t": 0.0, "need": 100.0}, true)
	var rlog := _until(rush, {}, 300.0, 50.0)
	_expect(_has(rlog, "rush") and String(rush.s["rush"]["state"]) == "run" and int(rush.s["rush"]["goal"]) == 4, "Umbriel did not start her run with four flashes at level 10")
	for i in 3:
		rush.step(50.0, {"lightH": true})
		rush.step(50.0, {})
	_expect(String(rush.s["rush"]["state"]) == "run" and int(rush.s["rush"]["flashes"]) == 3, "three flashes counted wrong against level 10")
	var rlog2 := _until(rush, {}, 4000.0, 50.0)
	_expect(String(rush.s["over"]) == "caught" and String(rush.s["by"]) == "umbriel" and _has(rlog2, "door"), "one flash short and Umbriel still did not get through")
	var rush2 := _only({"umbriel": 10}, 3, 5)
	rush2.s["rush"].merge({"state": "poised", "room": "ballroom", "t": 0.0, "need": 100.0}, true)
	_until(rush2, {"mask": true}, 150.0, 50.0)
	var retreated := false
	for i in 4:
		rush2.step(50.0, {"lightH": true, "mask": true})
		retreated = retreated or _has(rush2.step(50.0, {}), "rushRetreat")
	retreated = retreated or String(rush2.s["rush"]["state"]) == "away"
	_expect(retreated and String(rush2.s["over"]) == "", "four hall-light flashes did not send Umbriel back to the gallery")
	# one at a time in the hall
	var one := _only({"thessine": 10, "umbriel": 10}, 3, 5)
	one.s["hall"]["thessine"].merge({"state": "hall", "room": "hall", "step": 0, "need": 1e9}, true)
	one.s["rush"].merge({"state": "poised", "room": "ballroom", "t": 0.0, "need": 50.0}, true)
	_until(one, {}, 1000.0, 50.0)
	_expect(String(one.s["rush"]["state"]) == "poised", "Umbriel ran the hall while Thessine was in it")
	# flashes cost battery; infinite battery is untouched
	var drain := _only({}, 1)
	_until(drain, {"lightH": true}, 10000.0, 50.0)
	var expected := 100.0 - 10.0 * 100.0 / 66.0 - 0.25
	_expect(absf(float(drain.s["battery"]) - expected) < 0.05, "ten seconds of the hall light cost %.3f, not %.3f" % [100.0 - float(drain.s["battery"]), 100.0 - expected])
	var inf := _game(1, 1, ALL_ZERO, true, true)
	_until(inf, {"lightH": true, "lamp": true, "monitor": true}, 5000.0, 50.0)
	_expect(float(inf.s["battery"]) == 100.0, "infinite battery drained")
	var lamp := _only({}, 1)
	_until(lamp, {"lamp": true}, 10000.0, 50.0)
	var cams := _only({}, 1)
	_until(cams, {"monitor": true}, 10000.0, 50.0)
	_expect(absf((100.0 - float(lamp.s["battery"])) / (100.0 - float(cams.s["battery"])) - 4.0) < 0.01, "the lamp is not four times the monitor's drain (a tenth against a fortieth)")
	# the music box: night 1 holds until 2 AM; empty for 6 s and Glyra has you; winding saves you
	var box := _game(1, 1, ALL_ZERO, false)
	box.levels = {"thessine": 0, "umbriel": 0, "verrine": 0, "haelith": 0, "ilyra": 0, "glyra": -1, "nyxie": 0}
	_until(box, {}, 89000.0, 500.0)
	_expect(float(box.s["box"]) == 100.0, "the box ran down before 2 AM on night 1")
	var empty := _only({"glyra": 8}, 4, 2)
	var elog := _until(empty, {}, 60000.0, 100.0)
	_expect(_has(elog, "boxEmpty") and String(empty.s["over"]) == "caught" and String(empty.s["by"]) == "glyra", "an empty music box did not bring Glyra")
	var saved := _only({"glyra": 8}, 4, 2)
	var sv := _until(saved, {}, 42000.0, 100.0)
	for i in 120:
		sv.append_array(saved.step(100.0, {"winding": true}))
	_expect(String(saved.s["over"]) == "" and float(saved.s["box"]) > 50.0, "winding did not keep the box up")
	var rescue := _only({"glyra": 20}, 4, 2)
	rescue.s["box"] = 0.0
	_until(rescue, {}, 3000.0, 100.0)
	var rescued := rescue.step(100.0, {"winding": true})
	_expect(_has(rescued, "boxSaved") and String(rescue.s["over"]) == "", "winding in time did not save the box")
	# Nyxie: nothing while there is light; with the battery gone the dark has a clock
	var dark := _only({"nyxie": 6}, 5, 1)
	dark.s["battery"] = 0.0
	var dlog := _until(dark, {}, 20000.0, 100.0)
	_expect(_has(dlog, "dark") and String(dark.s["by"]) == "nyxie" and float(dark.s["dark"]) >= MaskLogic.dark_grace_ms(6) and float(dark.s["dark"]) < MaskLogic.dark_grace_ms(6) + 150.0,
		"Nyxie did not come when the dark ran out (%s)" % str(dark.s["dark"]))
	var lit_up := _only({"nyxie": 6}, 5, 1)
	_until(lit_up, {}, 30000.0, 100.0)
	_expect(String(lit_up.s["over"]) == "", "Nyxie came while the battery was alive")
	# cameras hold a watched hunter still
	var watch := _only({"thessine": 10}, 3, 1)
	watch.s["hall"]["thessine"].merge({"state": "room", "room": "ballroom", "t": 0.0, "need": 4000.0}, true)
	_until(watch, {"monitor": true, "cam": "ballroom"}, 6000.0, 100.0)
	_expect(String(watch.s["hall"]["thessine"]["state"]) == "room" and float(watch.s["hall"]["thessine"]["t"]) == 0.0, "the ballroom camera did not hold Thessine")
	_expect(watch.cam_figures("ballroom").size() == 1 and watch.cam_figures("ballroom")[0]["id"] == "thessine" and watch.cam_figures("music").is_empty(), "the ballroom feed shows the wrong figures")
	# the dark ducts: a vent hunter is drawn only while that duct's light is on
	var duct := _only({"verrine": 10}, 3, 1)
	duct.s["vent"].merge({"state": "duct", "room": "ductL", "side": "L", "t": 0.0, "need": 4000.0}, true)
	duct.step(10.0, {})
	_expect(duct.cam_figures("ductL").is_empty() and duct.glint("ductL") and not duct.glint("ductR"), "a hunter in a dark duct was visible")
	duct.step(10.0, {"lightL": true})
	_expect(duct.cam_figures("ductL").size() == 1 and not duct.glint("ductL"), "the duct light did not show the hunter")
	duct.s["vent"].merge({"state": "vent", "room": "ventL", "side": "L"}, true)
	duct.step(10.0, {"lightL": true})
	_expect(duct.vent_seen("L") == "verrine" and duct.vent_seen("R") == "", "the lit vent does not show Verrine")
	# one vent light at a time: both held, only the left works
	var both := _only({}, 3)
	both.step(10.0, {"lightL": true, "lightR": true})
	_expect(bool(both.s["lit"]["L"]) and not bool(both.s["lit"]["R"]), "two vent lights were lit at once")


# --- the controls ---------------------------------------------------------------------------------------------------------

func _settle(c: MaskControls) -> void:
	for i in 40:
		c.step(50.0)


func _check_controls() -> void:
	var c := MaskControls.new()
	c.press("mask")
	_expect(not c.control_input()["mask"], "the mask counted before it was fully on")
	_settle(c)
	_expect(c.control_input()["mask"] and not c.control_input()["monitor"], "the mask did not come fully on")
	c.press("monitor")
	_settle(c)
	var inp := c.control_input()
	_expect(inp["monitor"] and not inp["mask"], "raising the monitor did not lower the mask first")
	# lights only with both down; a vent light on its own duct camera; winding only on CAM 1
	c.press("lightL")
	_expect(not c.control_input()["lightL"], "a vent light worked with the monitor up on the music box")
	c.press("cam:ductL")
	_expect(c.control_input()["lightL"], "the duct camera did not allow its vent light")
	c.press("cam:ductR")
	_expect(not c.control_input()["lightL"] and c.cam == "ductR", "the wrong duct's light worked")
	c.press("lightL", false)
	c.press("lightH")
	_expect(not c.control_input()["lightH"], "the hall light worked with the monitor up")
	c.press("lightH", false)
	c.press("winKey")
	_expect(c.cam == "music" and c.control_input()["winding"], "holding wind did not jump to CAM 1 and wind")
	c.press("cam:ballroom")
	_expect(not c.control_input()["winding"], "winding went on off CAM 1")
	c.press("winKey", false)
	c.press("cam:gallery")
	_expect(c.cam == "gallery", "a camera did not change with the monitor up")
	c.press("monitor")
	_settle(c)
	c.press("lightH")
	_expect(c.control_input()["lightH"] and c.clear(), "the hall light did not work with everything down")
	c.press("lightL")
	c.press("lightR")
	_expect(c.control_input()["lightR"] and not c.control_input()["lightL"], "the latest vent press did not win")
	c.press("lamp")
	_expect(c.lamp and c.control_input()["lamp"], "the lamp did not switch on")
	c.press("cam:hall")
	_expect(c.cam == "gallery", "a camera changed with the monitor down")
	# mash: never the mask and the monitor together, whatever comes in
	var f := MaskControls.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var bad := 0
	for i in 4000:
		var which := rng.randi() % 7
		if which == 0:
			f.press("mask", rng.randf() < 0.8)
		elif which == 1:
			f.press("monitor", rng.randf() < 0.8)
		elif which == 2:
			f.press(["lightL", "lightR", "lightH"][rng.randi() % 3], rng.randf() < 0.5)
		elif which == 3:
			f.press("winKey", rng.randf() < 0.5)
		elif which == 4:
			f.press("cam:" + CAMS[rng.randi() % 8])
		f.step(float(rng.randi() % 120))
		var ci := f.control_input()
		if (ci["mask"] and ci["monitor"]) or (ci["mask"] and (ci["lightL"] or ci["lightR"] or ci["lightH"])) or (ci["lightH"] and ci["monitor"]):
			bad += 1
	_expect(bad == 0, "the controls let two panels (or a panel and a light) work together %d times" % bad)


# --- the shift scene ---------------------------------------------------------------------------------------------------

func _shift(host: Node, level: int, seed_number: int, custom_levels := {}, zero := false) -> MaskGame:
	NightWatchSession.start_mode("mask", level, custom_levels, seed_number)
	if zero:
		NightWatchSession.custom_levels = ALL_ZERO.duplicate()
	var shift := (load(NightWatchModeRegistry.scene_for("mask")) as PackedScene).instantiate() as MaskGame
	shift.manual_clock = true
	host.add_child(shift)
	return shift


func _check_scene(host: Node) -> void:
	NightWatchSave.path = "user://night_watch_mask_test.cfg"
	NightWatchSave.reset()
	_expect(NightWatchModeRegistry.playable("mask") and NightWatchModeRegistry.prepare("mask", 3) == "res://game/night_watch/mask/night_watch_mask.tscn", "the registry does not start Masked Hours")
	_expect(NightWatchSession.mode_id == "mask" and NightWatchSession.night == 3, "the session did not keep the mask shift")
	# every shift of the mode starts from the board's session and builds
	var levels: Array = NightWatchModesData.mode("mask")["levels"]
	_expect(levels.size() == 6, "Masked Hours does not list six nights")
	for n in range(1, levels.size() + 1):
		var shift := _shift(host, n, 100 + n)
		await host.get_tree().process_frame
		_expect(shift.mode_id == "mask" and shift.night == n and shift.level_name() == "NIGHT %d" % n and shift.sim.night_idx == n - 1, "night %d did not start as night %d" % [n, n])
		shift.advance_ms(1000.0)
		_expect(shift.hud.clock_label.text == "12 AM" and shift.hud.power_label.text == "BATTERY 100%" and shift.hud.usage_label.text.begins_with("MUSIC BOX"),
			"the clock, battery or box label is wrong on night %d" % n)
		shift.queue_free()
		await host.get_tree().process_frame
	# the room: shared player, crosshair, prompt, stations, no doors, no audio players of its own
	var game := _shift(host, 2, 4242)
	await host.get_tree().process_frame
	_expect(game.player != null and game.hud.find_children("*", "Crosshair", true, false).size() == 1, "the shared player or crosshair is missing")
	_expect(game.office is MaskOffice and game.office.spec.id == "front_office", "Masked Hours is not in its own front office")
	for id in ["monitor", "mask", "musicbox", "ventL", "ventR", "hall_light", "lamp", "chair"]:
		_expect(game.office.stations.has(id) and not (game.office.stations[id] as NightWatchStation).disabled, "station %s is missing or disabled" % id)
	_expect(game.office.find_children("Slab*", "Node3D", true, false).is_empty() and not game.office.stations.has("doorL_door") and not game.office.stations.has("doorR_door"), "the office has a door")
	var mouth := game.office.global_position + Vector3(0.0, 1.0, MaskOffice.FRONT_Z)
	_expect(game.office.stations.has("hall_light") and mouth.z < game.office.global_position.z, "the main hall does not open straight ahead of the desk")
	_expect(game.find_children("*", "AudioStreamPlayer", true, false).is_empty() and game.find_children("*", "AudioStreamPlayer3D", true, false).is_empty(), "Masked Hours has an audio player of its own")
	for file in DirAccess.get_files_at("res://game/night_watch/mask"):
		if file.ends_with(".gd"):
			_expect(not FileAccess.get_file_as_string("res://game/night_watch/mask/" + file).contains("AudioStreamPlayer"), "%s makes its own audio player" % file)
	# the mask and the monitor: one at a time, through the machine; the overlay follows the mask
	game.press("mask")
	game.advance_ms(100.0)
	_expect(not bool(game._last_input["mask"]) and game.overlay.cover > 0.0 and game.overlay.cover < 1.0, "the mask counted before it was fully on")
	game.advance_ms(200.0)
	_expect(bool(game._last_input["mask"]) and is_equal_approx(game.overlay.cover, 1.0), "the mask did not come fully on")
	Sound.reset_test_counters()
	game.press("monitor")
	game.advance_ms(200.0)
	game.advance_ms(300.0)
	_expect(game.monitor_up and game.hud.monitor_root.visible and not bool(game._last_input["mask"]) and bool(game._last_input["monitor"]), "the monitor did not replace the mask")
	await host.get_tree().process_frame
	_expect(game.hud.cam_label.text.begins_with("CAM 1 · PRIZE CORNER") and game.hud.feed_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "the monitor did not open on CAM 1")
	_expect(Sound.play_counts.has("nw_camera"), "the monitor sound did not go through the shared Sound autoload")
	game.select_camera("ductL")
	_expect(game.hud.cam_label.text.begins_with("CAM 6 · LEFT AIR VENT") and game.hud.feed_camera.global_position.distance_to(game.world.feed_transform("ductL").origin) < 0.01, "the feed did not move to the left duct")
	game.select_camera("hall")
	_expect(game.hud.feed_camera.global_position.distance_to(game.office.global_position + Vector3(0.0, 2.6, -1.9)) < 0.01, "CAM 8 is not over the office opening looking down the main hall")
	game.press("winPtr")
	game.advance_ms(60.0)
	_expect(game.controls.cam == "music" and bool(game._last_input["winding"]), "holding the music box did not jump to CAM 1 and wind")
	game.press("winPtr", false)
	game.press("monitor")
	game.advance_ms(500.0)
	_expect(not game.monitor_up and not game.hud.monitor_root.visible, "the monitor did not come down")
	# the lights: the vent light on the left, the hall light on the right
	game.press("lightL")
	game.advance_ms(100.0)
	_expect((game.office.vent_beams["L"] as SpotLight3D).visible and not (game.office.vent_beams["R"] as SpotLight3D).visible, "the left vent light did not come on")
	game.press("lightL", false)
	game.press("lightH")
	game.advance_ms(100.0)
	_expect((game.office.door_lights["hall"] as SpotLight3D).visible, "the hall light did not come on")
	game.press("lightH", false)
	game.advance_ms(100.0)
	# the dark ducts and vents: a vent hunter is seen only in the light
	var verrine := game.sim.s["vent"] as Dictionary
	verrine.merge({"state": "duct", "room": "ductR", "side": "R", "t": 0.0, "need": 99999.0}, true)
	game.advance_ms(20.0)
	_expect(not (game._models["verrine"] as Node3D).visible and game.world.glints["ductR"].visible, "Verrine is visible in a dark duct")
	game.press("lightR")
	game.press("monitor")
	game.advance_ms(600.0)
	game.select_camera("ductR")
	game.advance_ms(60.0)
	_expect((game._models["verrine"] as Node3D).visible and not game.world.glints["ductR"].visible and (game.world.duct_lights["ductR"] as OmniLight3D).visible,
		"the duct light did not show Verrine on CAM 7")
	game.press("lightR", false)
	game.press("monitor")
	game.advance_ms(600.0)
	verrine.merge({"state": "vent", "room": "ventR", "side": "R", "t": 0.0, "lit": 0.0, "wait": 6000.0}, true)
	game.advance_ms(20.0)
	_expect(not (game._models["verrine"] as Node3D).visible and game.office.glints["ventR"].visible, "Verrine is visible in the dark vent")
	game.press("lightR")
	game.advance_ms(20.0)
	_expect((game._models["verrine"] as Node3D).visible and ((game._models["verrine"] as Node3D).position - (game.office.global_position + MaskWorld.VENT_STAND["R"])).length() < 0.1, "the vent light did not show Verrine at the right vent")
	game.advance_ms(1500.0)
	_expect(String(verrine["state"]) == "away", "holding the vent light did not send Verrine off")
	game.press("lightR", false)
	# the hall: Thessine on her last step is really in the corridor; Umbriel runs it; Glyra is in the music room
	var th := game.sim.s["hall"]["thessine"] as Dictionary
	th.merge({"state": "hall", "room": "hall", "step": 3, "t": 0.0, "need": 99999.0}, true)
	game.advance_ms(20.0)
	var tm := game._models["thessine"] as Node3D
	_expect(tm.visible and absf(tm.position.x - game.office.global_position.x) < 0.5 and tm.position.z < game.office.global_position.z - 2.5 and tm.position.z > game.office.global_position.z - 8.0, "Thessine is not in the main hall on her last step")
	th.merge({"state": "away", "room": "costume"}, true)
	var rush := game.sim.s["rush"] as Dictionary
	game.advance_ms(20.0)
	_expect((game._models["glyra"] as Node3D).visible, "Glyra is not in the music room on night 2")
	game.queue_free()
	await host.get_tree().process_frame
	# the hunters WALK: from one room to the next along the lanes, never placed in the new room
	NightWatchSession.start_mode("mask", 3, {}, 8)
	var walk := (load("res://game/night_watch/mask/night_watch_mask.tscn") as PackedScene).instantiate() as MaskGame
	host.add_child(walk)
	await host.get_tree().process_frame
	var wth := walk.sim.s["hall"]["thessine"] as Dictionary
	wth.merge({"state": "room", "room": "costume", "t": 0.0, "need": 99999.0}, true)
	walk._place_hunters()
	var from_pos := (walk._models["thessine"] as Node3D).position
	wth.merge({"room": "ballroom"}, true)
	walk._place_hunters()
	walk._animate_models(0.5)
	var after := (walk._models["thessine"] as Node3D).position
	var goal := walk.world.stand_at("ballroom", 0)
	_expect(from_pos.distance_to(after) > 0.5 and from_pos.distance_to(after) < 4.0 and after.distance_to(goal) > 2.0, "Thessine was placed in the ballroom instead of walking there")
	for i in 400:
		walk._animate_models(0.1)
	_expect((walk._models["thessine"] as Node3D).position.distance_to(goal) < 0.3, "Thessine never reached the ballroom on foot")
	var walls: Array = walk.world.wall_boxes
	var bad_wall := 0
	for a in ["costume", "music", "gallery", "ballroom", "crawl", "ductL", "ductR"]:
		for b in ["costume", "music", "gallery", "ballroom", "crawl", "ductL", "ductR"]:
			if a == b:
				continue
			var legs: Array = walk.world.route("C:" + a, "C:" + b)
			_expect(legs.size() >= 2, "no walking route from %s to %s" % [a, b])
			for k in range(1, legs.size()):
				var p0: Vector3 = legs[k - 1]["p"]
				var p1: Vector3 = legs[k]["p"]
				for q in int(ceil(p0.distance_to(p1) / 0.1)):
					var pt := p0.lerp(p1, float(q) / ceil(p0.distance_to(p1) / 0.1))
					for w in walls:
						if (w["rect"] as Rect2).has_point(Vector2(pt.x, pt.z)):
							bad_wall += 1
	_expect(bad_wall == 0, "walking routes in the wing cross walls at %d points" % bad_wall)
	# the FNAF 2 floor plan: four party rooms off the main hall, three performers on the show stage, the prize counter and the big music box, arcade cabinets, the side halls
	for n in range(1, 5):
		_expect(walk.world.find_child("PartyRoom%d" % n, true, false) != null, "party room %d is missing" % n)
	var named := {}
	for m in walk.world.find_children("*", "MeshInstance3D", true, false):
		var nm := String(m.get_meta("nw_name", ""))
		named[nm] = int(named.get(nm, 0)) + 1
	_expect(int(named.get("HeadPerformer", 0)) == 3 and int(named.get("ArcadeBody", 0)) >= 4 and walk.world.find_child("MusicBoxBig", true, false) != null and walk.world.find_child("PrizeCorner", true, false) != null
		and int(named.get("CounterPrize", 0)) == 1 and walk.world.find_child("SideHallL", true, false) != null and walk.world.find_child("SideHallR", true, false) != null,
		"the show stage performers, prize counter, music box, arcade cabinets or side halls are missing (%s)" % str([named.get("HeadPerformer", 0), named.get("ArcadeBody", 0)]))
	var to_office: Array = walk.world.route("C:ballroom", "H:in")
	var straight := to_office.size() >= 6
	for leg in to_office:
		if String(leg["key"]).begins_with("H:") or String(leg["key"]) == "GA_S" or String(leg["key"]) == "C:ballroom":
			straight = straight and absf((leg["p"] as Vector3).x) < 0.01
	_expect(straight and (to_office[to_office.size() - 1]["p"] as Vector3).z > -2.0, "the way from the game area to the office is not one straight main hall")
	var around: Array = walk.world.route("C:crawl", "C:ballroom")
	var keys := []
	for leg in around:
		keys.append(String(leg["key"]))
	_expect(keys.has("SL_2") or keys.has("SR_2"), "the vent hub is not connected to the show floor by a side hall")
	for room in MaskData.cam_rooms():
		if room != "hall":
			_expect(walk.world.route("C:%s" % room if room != "hall" else "H:15", "H:in").size() >= 2, "%s has no walk to the office" % room)
	# a hunter in a vent shaft takes the vent pose: Verrine drops in (one-shot), crawls (her own belly-low crawl), rises out; the others use the generic crawl
	_expect(NightWatchPoses.pose_for_state("vent", "verrine") == "vent_crawl_verrine" and NightWatchPoses.pose_for_state("vent", "ilyra") == "vent_crawl"
		and NightWatchPoses.pose_for_state("vent_enter", "verrine") == "vent_drop_verrine" and NightWatchPoses.pose_for_state("vent_enter", "ilyra") == "", "the vent poses are not mapped as the pose data says")
	var pv := walk.sim.s["vent"] as Dictionary
	pv.merge({"state": "duct", "room": "ductL", "side": "L", "t": 0.0, "need": 99999.0}, true)
	walk._animate_models(0.016)
	_expect(walk._vent_pose.state_of("verrine") == "vent_enter", "Verrine did not drop into the duct with the vent_enter pose")
	for i in 60:
		walk._animate_models(0.02)
	_expect(walk._vent_pose.state_of("verrine") == "vent", "Verrine did not crawl the duct in her vent pose")
	var ilyra := walk.sim.s["ilyra"] as Dictionary
	ilyra.merge({"state": "duct", "room": "ductR", "side": "R", "t": 0.0, "need": 99999.0, "step": 1}, true)
	walk._animate_models(0.016)
	_expect(walk._vent_pose.state_of("ilyra") == "vent", "Ilyra did not take the generic vent crawl (no drop)")
	pv.merge({"state": "away", "room": "crawl"}, true)
	walk._animate_models(0.016)
	_expect(walk._vent_pose.state_of("verrine") == "vent_exit", "Verrine did not rise out of the shaft with vent_exit")
	for i in 60:
		walk._animate_models(0.02)
	_expect(walk._vent_pose.state_of("verrine") == "", "Verrine kept a vent pose after leaving the shaft")
	_expect(MaskOffice.HEIGHT > 0.8 and 1.8 > 0.8, "the air vents are lower than 0.8 m")
	walk.queue_free()
	await host.get_tree().process_frame
	# a loss: Thessine unmasked in the office ends the night with the CAUGHT card
	var lose := _shift(host, 1, 5)
	await host.get_tree().process_frame
	var lh := lose.sim.s["hall"]["thessine"] as Dictionary
	lh.merge({"state": "office", "room": "office", "fooled": 0.0, "off": 0.0, "window": 3500.0}, true)
	for i in 50:
		lose.advance_ms(100.0)
	_expect(lose.state == MaskGame.State.LOST and String(lose.last_death.get("by", "")) == "thessine", "an unmasked Thessine did not lose the night")
	var closing := 0
	while lose.death_moment.is_open() and closing < 40:
		lose.death_moment.dismiss()
		closing += 1
	await host.get_tree().process_frame
	_expect(lose.hud.end_root.visible and lose.hud.end_title.text == "CAUGHT" and not lose.hud.end_next.visible, "the end card after a death is not CAUGHT with Retry and the menu")
	_expect(lose.hud.retry_pressed.is_connected(lose.retry) and lose.hud.menu_pressed.is_connected(lose.back_to_board), "Retry or the menu is not wired on the end card")
	var seed_before := lose.seed_value
	NightWatchSession.start_mode(lose.mode_id, lose.level, lose.custom, lose.seed_value)
	_expect(NightWatchSession.seed_value == seed_before and NightWatchSession.mode_id == "mask" and NightWatchSession.night == 1, "Retry would not replay the same seed")
	lose.queue_free()
	await host.get_tree().process_frame
	# a won night: saved under cleared_mask, opens the next
	var quiet := _shift(host, 1, 6, {}, true)
	await host.get_tree().process_frame
	for i in 271:
		quiet.advance_ms(1000.0)
	_expect(quiet.state == MaskGame.State.WON and quiet.hud.end_root.visible and quiet.hud.end_title.text == "NIGHT 1 COMPLETE" and quiet.hud.end_next.visible, "a quiet night was not won at 6 AM")
	_expect(NightWatchSave.cleared_levels("mask") == [1] and NightWatchSave.level_open("mask", 2) and not NightWatchSave.level_open("mask", 3) and NightWatchSave.cleared_levels("classic").is_empty(),
		"winning night 1 did not save cleared_mask and open exactly night 2")
	quiet.queue_free()
	await host.get_tree().process_frame
	# Custom Night: the sliders are the logic's levels, a win records a score and the preset's star (not a night)
	var preset := {"thessine": 12, "umbriel": 12, "verrine": 0, "haelith": 0, "ilyra": 0, "glyra": 5, "nyxie": 0}
	var cn := _shift(host, 1, 77, preset)
	await host.get_tree().process_frame
	_expect(cn.is_custom and cn.night == 5 and cn.sim.custom and cn.sim.base_level("thessine") == 12 and cn.sim.base_level("verrine") == 0 and cn.sim.base_level("umbriel") == 12
		and is_equal_approx(cn.sim._decay, MaskLogic.box_decay_for_level(5)), "the Custom Night sliders did not feed the rules")
	cn.sim.s["elapsed"] = NightWatchData.NIGHT_MS - 50.0
	cn.advance_ms(100.0)
	_expect(cn.state == MaskGame.State.WON and cn.hud.end_title.text == "CUSTOM NIGHT COMPLETE" and not cn.hud.end_next.visible, "the Custom Night was not won")
	_expect(NightWatchSave.best_score("mask") == 290 and NightWatchSave.stars("mask") == ["hall-pass"] and NightWatchSave.cleared_levels("mask") == [1], "the Custom Night did not record its score and star")
	cn.queue_free()
	await host.get_tree().process_frame
	_expect(not InputMap.has_action(NightWatchControls.LIGHT_LEFT), "the quick-key actions stayed registered after the shift closed")
	NightWatchSave.reset()
	NightWatchSave.path = NwLeakProbe.scratch_path()
	NightWatchSession.start(1)


# --- Zellia's call: rung at the night's `at` seconds on the shift clock (pauses and the admin freeze are honoured), typed line by line, skipped with mute ---------------------

func _check_call(host: Node) -> void:
	var game := _shift(host, 1, 650)
	await host.get_tree().process_frame
	var at_s := float(NightWatchCallsData.for_level("mask", 1)["at"])
	_expect(game.hud.call_script != null and not game.hud.call_script.done and not game.hud.call_script.open, "night 1's call is not waiting for its ring")
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
	_expect(game.hud.call_script.open and game.hud.call_script.line == 0 and game.hud.shown_call != NightWatchCallsData.INCOMING_TEXT, "the call did not go on to its first line")
	game.admin_skip_call()
	_expect(game.hud.shown_call.is_empty(), "skipping the call left it on screen")
	game.queue_free()
	await host.get_tree().process_frame


# --- the admin menu: the gate, the sections, the layout at three sizes, and every entry really changes the shift ---------------------------------------------

func _admin_snapshot(game: MaskGame) -> String:
	return NightWatchAdminCheck.dump(game.sim.s) + NightWatchAdminCheck.dump(game.sim.levels) + "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [game.sim.infinite_battery, game.sim.hunter_speed, game._admin_frozen,
		game._admin_god, game._admin_no_scare, game._admin_reveal, game._admin_noclip, game.controls.want, game.controls.lamp, str(game.controls.held), game.hud.shown_call, NightWatchSession.night] \
		+ str(game.hud.cam_map.blips) + str(game.sim._decay)


func _check_admin(host: Node) -> void:
	NightWatchSave.path = "user://night_watch_mask_admin_test.cfg"
	NightWatchSave.reset()
	var game := _shift(host, 4, 600)
	await host.get_tree().process_frame
	for msg in NightWatchAdminCheck.sections(game, "MASKED HOURS SPECIFIC"):
		_expect(false, "[admin] " + msg)
	_expect(game.hud.hint_label.text.contains("0 admin"), "the hint line does not list the admin key for an admin")
	for msg in await NightWatchAdminCheck.layout(host, game, "MASKED HOURS SPECIFIC"):
		_expect(false, "[admin] " + msg)
	game.advance_ms(3000.0)
	for msg in NightWatchAdminCheck.exercise(game, func(g): return _admin_snapshot(g), ["WIN THE SHIFT", "LOSE THE SHIFT"]):
		_expect(false, "[admin] " + msg)
	game.queue_free()
	await host.get_tree().process_frame
	# specific effects the snapshot cannot say: the hooks do what they claim
	var g2 := _shift(host, 4, 601)
	await host.get_tree().process_frame
	g2.admin_set_hour(3)
	_expect(g2.sim.level("thessine") == int((MaskLogic.LEVELS["thessine"] as Array)[3]) + 1, "SET TIME 3 AM did not step the AI up")
	g2.admin_set_box(0.0)
	g2.admin_set_power(40.0)
	_expect(is_equal_approx(float(g2.sim.s["box"]), 0.0) and is_equal_approx(float(g2.sim.s["battery"]), 40.0), "the box or the battery was not set")
	g2.admin_set_frozen(true)
	var before := float(g2.sim.s["elapsed"])
	g2.advance_ms(2000.0)
	_expect(float(g2.sim.s["elapsed"]) == before, "the frozen clock still ran")
	g2.admin_set_frozen(false)
	g2.admin_place_hunter("thessine", "office")
	g2.admin_set_god(true)
	g2.advance_ms(6000.0)
	_expect(g2.state == MaskGame.State.PLAYING and String(g2.sim.s["over"]) == "", "god mode did not save the night from an unmasked Thessine")
	g2.admin_set_god(false)
	g2.admin_set_no_scare(true)
	g2.admin_lose()
	_expect(g2.state == MaskGame.State.LOST and not g2.death_moment.is_open(), "LOSE THE SHIFT with no jumpscare still played the scare")
	g2.queue_free()
	await host.get_tree().process_frame
	var g3 := _shift(host, 2, 602)
	await host.get_tree().process_frame
	g3.admin_win()
	_expect(g3.state == MaskGame.State.WON, "WIN THE SHIFT did not win")
	g3.queue_free()
	await host.get_tree().process_frame
	NightWatchSave.reset()
	NightWatchSave.path = NwLeakProbe.scratch_path()
	NightWatchSession.start(1)
