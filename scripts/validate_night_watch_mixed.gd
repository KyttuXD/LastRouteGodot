extends RefCounted

## Night Watch Mixed Shift + Endless (3D): the rules port reproduces the 2D game's numbers (whole shifts of every preset played by a fixed bot, the drawn rosters and the
## planned spikes of many seeds, from scripts/fixtures/night_watch_mixed_golden.json), the fairness rules (tell floor, cooldown, one deadly tell, hour-1 grace, an answer for
## every type), CHAOS and ENDLESS behave as documented, a shift is deterministic by seed, and the scene (all five shifts open from the board, win, loss, Endless's best hour,
## Retry, the vent controls, the monitor and the walking hunters) works. Scene checks live further down.

const FIELDS := ["type", "id", "kind", "room", "side", "how", "mood", "phase", "tkind", "key", "a", "beat", "t", "lead", "next", "gen", "hour", "to", "added", "removed"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


static func _text(v) -> String:
	if v == null:
		return ""
	if v is Array:
		return ",".join(PackedStringArray(v))
	if v is float or v is int:
		return str(int(roundf(float(v))))
	return str(v)


static func _ev_string(e: Dictionary) -> String:
	var parts := []
	for k in FIELDS:
		parts.append(_text(e.get(k, null)))
	return "|".join(parts)


## The state-reading bot of the golden fixture (scripts/fixtures/gen_night_watch_mixed_golden.mjs).
func _bot(kind: String, g: MixedLogic) -> void:
	if kind == "idle":
		return
	var e := float(g.s["elapsed"])
	for side in ["L", "R"]:
		var want := false
		for t in g.list():
			if bool(t["armed"]) and String(t["side"]) == side and String(t["type"]) != "vent":
				want = true
		g.set_door(side, want)
	for key in ["L", "R", "T"]:
		var want2 := false
		for t in g.list():
			if bool(t["armed"]) and String(t["type"]) == "vent" and String(t["side"]) == key:
				want2 = true
		g.set_vent(key, want2)
	for key in ["L", "R", "T"]:
		g.light_vent(key)
	g.set_monitor(int(floor(e / 9000.0)) % 2 == 0)
	g.set_room(MixedData.CAM_ROOMS[int(floor(e / 4000.0)) % MixedData.CAM_ROOMS.size()])
	var winder := {}
	for t in g.list():
		if String(t["type"]) == "winder":
			winder = t
			break
	g.set_wind(not winder.is_empty() and float(winder["tune"]) < 0.6)


const KIT_MARKER := {"bench": "SeatBench", "party": "BalloonCube", "yard": "BodyContainer", "pizzeria": "CabinetPizza", "studio": "OnAirStudio", "house": "BedHouse", "lab": "ConsoleLab", "shaft": "PillarShaft", "camp": "TentCamp"}


func run(host: Node) -> int:
	_check_data()
	_check_golden()
	_check_rules()
	await _check_scene(host)
	await _check_admin(host)
	await _check_rotation(host)
	if _failures == 0:
		print("  night_watch_mixed  the 2D rules (golden shifts of all five presets, rosters, spikes, fairness, CHAOS, ENDLESS) and the shift scene (board, win, loss, best hour, vents, monitor, walking)")
	return _failures


func _check_data() -> void:
	var shifts := MixedData.shifts()
	_expect(shifts.size() == 5 and String(shifts[3]["id"]) == "chaos" and String(shifts[4]["id"]) == "endless", "the shift board is not QUIET, STEADY, RESTLESS, CHAOS, ENDLESS")
	_expect(MixedData.POOL.size() == 8 and MixedData.TYPE_ORDER.size() == 6, "the pool is not eight threats of six types")
	_expect(MixedData.TELL_FLOOR_MS == 1500.0 and MixedData.COOLDOWN_MS == 1200.0 and MixedData.SEAL_MAX == 20000.0 and MixedData.VENT_SEAL_MAX == 9000.0, "fairness or seal numbers differ from the 2D game's")
	_expect(MixedData.endless_pace(2) == 1.0 and is_equal_approx(MixedData.endless_pace(7), 1.2) and MixedData.endless_pace(60) == 2.0, "Endless's pace ramp is wrong")
	_expect(MixedData.endless_tell(3) == 1900.0 and MixedData.endless_tell(100) == 1600.0 and MixedData.endless_budget(10) == 2400.0 and MixedData.endless_budget(99) == 1400.0 and MixedData.endless_gap(0) == 46000.0 and MixedData.endless_gap(50) == 10000.0,
		"Endless's tell, budget or gap ramp is wrong")
	_expect(MixedData.endless_clock(0.0) == "12 AM" and MixedData.endless_clock(5.0 * 45000.0) == "5 AM" and MixedData.endless_clock(6.0 * 45000.0) == "HOUR 6" and MixedData.hours_text(1) == "1 hour" and MixedData.hours_text(7) == "7 hours", "Endless's clock text is wrong")
	var g := MixedData.graph()
	for room in g:
		for nxt in g[room]:
			_expect((g[nxt] as Array).has(room), "%s -> %s is not mirrored in Mixed Shift's building" % [room, nxt])
	_expect((g["vent"] as Array).size() == 5 and (g["closet"] as Array).has("vent") and (g["corner"] as Array).has("vent"), "the vent run is not linked to the closet, the corner and the three vents")
	for r in MixedData.ROUTES:
		for i in range((r["rooms"] as Array).size() - 1):
			_expect((g[r["rooms"][i]] as Array).has(r["rooms"][i + 1]), "route %s: %s is not next to %s" % [r["id"], r["rooms"][i], r["rooms"][i + 1]])
	for r in MixedData.VENT_ROUTES:
		for i in range((r["rooms"] as Array).size() - 1):
			_expect((g[r["rooms"][i]] as Array).has(r["rooms"][i + 1]) or r["rooms"][i] == r["rooms"][i + 1], "vent route %s breaks at step %d" % [r["id"], i])
	_expect(MixedData.CAM_ROOMS == NightWatchData.cam_rooms() + ["vent"] and MixedData.BOX_ROOMS == NightWatchData.cam_rooms(), "the camera rooms are not Classic's eight plus the vent run")


func _check_golden() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/fixtures/night_watch_mixed_golden.json"))
	_expect(data is Dictionary and (data["runs"] as Array).size() >= 15, "the golden fixture is missing")
	if not (data is Dictionary):
		return
	var total := 0
	var kinds := {}
	for run in data["runs"]:
		var g := MixedLogic.new(int(run["seed"]), int(run["diff"]))
		var label := "shift %d seed %d %s" % [int(run["diff"]), int(run["seed"]), run["kind"]]
		_expect(g.roster == run["roster"], "%s: the roster is %s, the 2D game's is %s" % [label, str(g.roster), str(run["roster"])])
		var log := []
		var n := 0
		while String(g.s["over"]) == "" and n < int(run["steps"]):
			_bot(String(run["kind"]), g)
			for e in g.step(float(data["dt"])):
				log.append("%d|%s" % [n, _ev_string(e)])
			n += 1
		var want: Array = run["events"]
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
		_expect(n == int(run["ran"]) and absf(float(s["elapsed"]) - float(sum["elapsed"])) < 1e-6 and String(s["over"]) == String(sum["over"]) and String(s["by"]) == String(sum["by"])
			and String(s["beat"]) == String(sum["beat"]) and absf(float(s["tension"]) - float(sum["tension"])) < 2e-6 and absf(float(s["seal"]) - float(sum["seal"])) < 2e-6
			and absf(float(s["ventSeal"]) - float(sum["ventSeal"])) < 2e-6 and int(s["actSeq"]) == int(sum["actSeq"]) and int(s["spikeIdx"]) == int(sum["spikeIdx"]),
			"%s: the final state differs from the 2D game's (%s %s tension %.4f)" % [label, s["over"], s["by"], s["tension"]])
		kinds[String(s["over"])] = true
		total += log.size()
	_expect(kinds.has("win") and kinds.has("caught"), "the golden shifts do not cover a win and a catch")
	for r in data["rosters"]:
		var got := MixedLogic.draw_roster(int(r["seed"]), MixedData.difficulty_of(int(r["diff"])))
		if got != r["roster"]:
			_expect(false, "seed %d shift %d draws %s, the 2D game %s" % [int(r["seed"]), int(r["diff"]), str(got), str(r["roster"])])
			break
	for p in data["plans"]:
		var got2 := MixedLogic.plan_spikes(NightWatchMulberry.new((int(p["seed"]) ^ 0x44495243) & 0xFFFFFFFF), MixedData.difficulty_of(int(p["diff"])))
		var same := got2.size() == (p["plan"] as Array).size()
		if same:
			for i in got2.size():
				same = same and int(got2[i]["at"]) == int(p["plan"][i][0]) and int(got2[i]["len"]) == int(p["plan"][i][1])
		if not same:
			_expect(false, "seed %d shift %d plans other spikes than the 2D game" % [int(p["seed"]), int(p["diff"])])
			break
	print("  mixed golden: %d shifts, %d events, %d rosters and %d spike plans identical to the 2D logic" % [(data["runs"] as Array).size(), total, (data["rosters"] as Array).size(), (data["plans"] as Array).size()])


func _check_rules() -> void:
	# determinism and the roster rules over many seeds
	for d in 5:
		var seen_new := 0
		for seed_number in range(1, 80):
			var r := MixedLogic.draw_roster(seed_number, MixedData.difficulty_of(d))
			var types := {}
			var walkers := 0
			var newcomers := 0
			for id in r:
				var t := String(MixedData.pool_entry(String(id))["type"])
				types[t] = true
				walkers += 1 if MixedData.WALKER_TYPES.has(t) else 0
				newcomers += 1 if MixedData.NEW_TYPES.has(t) else 0
			var dd := MixedData.difficulty_of(d)
			_expect(types.size() >= int(dd.get("minTypes", 3)) and walkers <= MixedData.MAX_WALKERS and newcomers <= int(dd["newMax"]) and r.size() >= int((dd["roster"] as Array)[0]) and r.size() <= maxi(int((dd["roster"] as Array)[1]), (dd.get("must", []) as Array).size()),
				"shift %d seed %d draws a roster that breaks the rules: %s" % [d, seed_number, str(r)])
			if d == 3:
				_expect(r.has("verrine") and r.has("glyra"), "CHAOS did not hold the Vent crawler and the Winder (seed %d)" % seed_number)
			seen_new += newcomers
	# a night: win at 6 AM for the bot, the same seed gives the same log
	var a := _log(MixedLogic.new(7, 1), "bot", 2800)
	var b := _log(MixedLogic.new(7, 1), "bot", 2800)
	var c := _log(MixedLogic.new(8, 1), "bot", 2800)
	_expect(a == b and a.size() > 100 and a != c, "the same seed did not give the same night twice, or another seed matched")
	# fairness over many nights of an idle player: no kill without a tell at least 1.5 s earlier, one deadly tell at a time, nothing at a gate in the first 75 s
	var worst_lead := 1e9
	var killers := {}
	for seed_number in range(1, 40):
		for d in range(0, 4):
			var g := MixedLogic.new(seed_number, d)
			var tell_at := {}
			var guard := 0
			while String(g.s["over"]) == "" and guard < 3000:
				guard += 1
				var armed := 0
				for t in g.list():
					if bool(t["armed"]):
						armed += 1
				_expect(armed <= 1, "two deadly tells at once (shift %d seed %d)" % [d, seed_number])
				for e in g.step(100.0):
					var type := String(e["type"])
					if type == "tell":
						tell_at[e["id"]] = float(e["t"])
					elif type == "arrive" or type == "tell" or type == "kill":
						_expect(float(e["t"]) >= float((MixedData.difficulty_of(d))["graceMs"]) - 1.0, "%s before the grace ended (shift %d seed %d at %.0f)" % [type, d, seed_number, float(e["t"])])
					if type == "kill":
						killers[String(e["kind"])] = true
						var lead: float = float(e["t"]) - float(tell_at.get(e["id"], 1e9 * -1.0))
						worst_lead = minf(worst_lead, lead)
	_expect(worst_lead >= MixedData.TELL_FLOOR_MS - 1.0, "a kill came %.0f ms after its tell began (floor 1500)" % worst_lead)
	_expect(killers.size() >= 4, "an idle player was killed by too few types: %s" % str(killers.keys()))
	# the cooldown: after any action nothing else acts for 1.2 s
	var cool := MixedLogic.new(3, 2)
	var last_a := -1
	var last_t := -1e9
	for i in 2000:
		_bot("bot", cool)
		for e in cool.step(100.0):
			if e.has("a") and int(e["a"]) != last_a:
				_expect(float(e["t"]) - last_t >= MixedData.COOLDOWN_MS - 1.0 or last_t < 0.0, "two actions %.0f ms apart (cooldown 1200)" % (float(e["t"]) - last_t))
				last_a = int(e["a"])
				last_t = float(e["t"])
		if String(cool.s["over"]) != "":
			break
	# a door: a shut door held on her sends a path walker away; the seal store drains
	var path := MixedLogic.new(2, 1)
	for t in path.list():
		if String(t["type"]) != "path":
			t["wait"] = 1e12
	var dg := _only("dovelle", 5)
	var th := dg.threat("dovelle")
	th["active"] = true
	th["route"] = ["westhall", "doorL"]
	th["routeId"] = "L-closet"
	th["i"] = 0
	th["wait"] = 0.0
	th["dwell"] = 9999.0
	dg.s["elapsed"] = 100000.0
	var arrived := false
	var answered := false
	for i in 400:
		dg.set_door("L", bool(th["armed"]))
		for e in dg.step(100.0):
			arrived = arrived or String(e["type"]) == "arrive"
			answered = answered or (String(e["type"]) == "answered" and String(e["how"]) == "door")
		if answered:
			break
	_expect(arrived and answered and String(dg.s["over"]) == "", "a shut door did not turn Dovelle away")
	_expect(float(dg.s["seal"]) < MixedData.SEAL_MAX, "a shut door cost no seal")
	# the vent: sealing sends the crawler away; the vent light backs her off at her branch
	var vg := _only("verrine", 5)
	var vt := vg.threat("verrine")
	vt["active"] = true
	vt["route"] = ["vent", "vent", "vent", "vent", "ventL"]
	vt["routeId"] = "V-L"
	vt["i"] = 3
	vt["dwell"] = 9999.0
	vt["wait"] = 0.0
	vg.s["elapsed"] = 100000.0
	var sealed := false
	for i in 400:
		vg.set_vent("L", bool(vt["armed"]))
		for e in vg.step(100.0):
			sealed = sealed or (String(e["type"]) == "answered" and String(e["how"]) == "seal")
		if sealed:
			break
	_expect(sealed and String(vg.s["over"]) == "", "sealing the vent did not turn Verrine away")
	var lg := _only("verrine", 5)
	var lt := lg.threat("verrine")
	lt["active"] = true
	lt["route"] = ["vent", "vent", "vent", "vent", "ventL"]
	lt["routeId"] = "V-L"
	lt["i"] = 3
	lt["dwell"] = 0.0
	lt["wait"] = 1e12
	var lit := lg.light_vent("L")
	_expect(bool(lit["ok"]) and (lit["seen"] as Array) == ["verrine"] and bool(lt["flinch"]), "the vent light did not show Verrine at the left branch")
	_expect(not bool(lg.light_vent("L")["ok"]) and String(lg.light_vent("R")["why"]) == "cool", "the vent light has no cooldown")
	lg.set_vent("R", true)
	_expect(String(lg.light_vent("R")["why"]) == "cool" or String(lg.light_vent("R")["why"]) == "shut", "a shut vent was lit")
	var backed := false
	for i in 60:
		for e in lg.step(100.0):
			backed = backed or String(e["type"]) == "turned"
	_expect(backed and int(lt["i"]) == 0, "the vent light did not back Verrine off down the run")
	# the Counter: held on one camera it builds and arms; switching camera answers
	var cg := _only("haelith", 5)
	var ct := cg.threat("haelith")
	cg.s["elapsed"] = 100000.0
	cg.set_monitor(true)
	var armed_seen := false
	for i in 600:
		cg.step(100.0)
		if bool(ct["armed"]):
			armed_seen = true
			break
	_expect(armed_seen, "staying on one camera never armed the Counter")
	cg.set_room("kitchen")
	var counter_answered := false
	for i in 40:
		for e in cg.step(100.0):
			counter_answered = counter_answered or String(e["type"]) == "answered"
	_expect(counter_answered or String(cg.s["over"]) == "", "switching camera did not answer the Counter")
	# the Winder: the box runs down, she walks, winding sends her back
	var wg := _only("glyra", 5)
	var wt := wg.threat("glyra")
	wg.s["elapsed"] = 100000.0
	wt["tune"] = 0.0006
	var stopped := false
	for i in 200:
		for e in wg.step(100.0):
			stopped = stopped or String(e["type"]) == "stop"
		if stopped:
			break
	_expect(stopped and bool(wt["stopped"]), "the empty music box did not stop")
	wg.set_monitor(true)
	wg.set_room(String(wt["boxRoom"]))
	wg.set_wind(true)
	var wound := false
	for i in 80:
		for e in wg.step(100.0):
			wound = wound or String(e["type"]) == "wound"
	_expect(wound and not bool(wt["stopped"]), "winding did not start the box again")
	# Endless: no 6 AM, the clock names the hours, the roster is drawn again every three hours, the best hour counts
	var eg := MixedLogic.new(5, 4)
	var rotated := false
	var hours := 0
	for i in 6000:
		_bot("bot", eg)
		for e in eg.step(100.0):
			rotated = rotated or String(e["type"]) == "rotate"
			hours = maxi(hours, int(e.get("hour", 0)))
		if String(eg.s["over"]) != "":
			break
	_expect(String(eg.s["over"]) != "win", "Endless ended at 6 AM")
	_expect(rotated or String(eg.s["over"]) == "caught", "Endless never drew its roster again")
	_expect(eg.hour_reached() >= 3 and eg.hour_reached() == eg.hour_of(), "Endless's hours survived are wrong")
	# CHAOS: chaos events from hour 1, each non-lethal
	var xg := MixedLogic.new(9, 3)
	var chaos_kinds := {}
	for i in 2700:
		_bot("bot", xg)
		for e in xg.step(100.0):
			if String(e["type"]) == "chaos" and String(e["phase"]) == "start":
				chaos_kinds[String(e["kind"])] = true
		if String(xg.s["over"]) != "":
			break
	_expect(chaos_kinds.size() >= 2, "CHAOS rolled fewer than two kinds of event in a night: %s" % str(chaos_kinds.keys()))


func _only(id: String, shift: int) -> MixedLogic:
	## A shift with just one threat of the roster awake (the others wait a very long time), for the type tests.
	var g := MixedLogic.new(1, shift)
	g.roster.clear()
	g.roster.append(id)
	g.s["threats"].clear()
	g.s["threats"][id] = MixedLogic.new_threat(MixedData.pool_entry(id), g.th_rng, g.diff, 0, 0)
	var th: Dictionary = g.s["threats"][id]
	if String(th["type"]) != "counter":
		th["wait"] = 0.0
	th["mood"] = "patient"
	th["moodLeft"] = 1e12
	th["moodCue"] = 1e12
	g.s["beat"] = "build"
	g.s["beatLeft"] = 1e12
	g.s["feintLeft"] = 1e12
	g.s["tension"] = 0.6
	g.s["plan"] = []
	return g


func _log(g: MixedLogic, kind: String, steps: int) -> Array:
	var out := []
	var n := 0
	while String(g.s["over"]) == "" and n < steps:
		_bot(kind, g)
		for e in g.step(100.0):
			out.append("%d|%s" % [n, _ev_string(e)])
		n += 1
	return out


# --- the shift scene ------------------------------------------------------------------------------------------------------

func _shift(host: Node, level: int, seed_number: int) -> MixedGame:
	NightWatchSession.start_mode("mixed", level, {}, seed_number)
	var shift := (load(NightWatchModeRegistry.scene_for("mixed")) as PackedScene).instantiate() as MixedGame
	shift.manual_clock = true
	host.add_child(shift)
	return shift


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	return ev


func _check_scene(host: Node) -> void:
	NightWatchSave.path = "user://night_watch_mixed_test.cfg"
	NightWatchSave.reset()
	_expect(NightWatchModeRegistry.playable("mixed") and NightWatchModeRegistry.prepare("mixed", 4) == "res://scenes/night_watch_mixed.tscn", "the registry does not start Mixed Shift")
	var levels: Array = NightWatchModesData.mode("mixed")["levels"]
	_expect(levels == ["QUIET", "STEADY", "RESTLESS", "CHAOS", "ENDLESS"] and int(NightWatchModesData.mode("mixed")["scored"]) == 4 and bool(NightWatchModesData.mode("mixed")["open"]) and NightWatchModesData.mode("mixed")["presets"].is_empty(),
		"the mode table is not five open shifts with four scored and no Custom Night")
	for n in range(1, 6):
		_expect(NightWatchSave.level_open("mixed", n, true), "shift %d is not open from the start" % n)
		var shift := _shift(host, n, 100 + n)
		await host.get_tree().process_frame
		_expect(shift.sim != null and shift.sim.diff["name"] == levels[n - 1] and shift.sim.endless == (n == 5) and shift.sim.chaos == (n == 4), "shift %d did not start as %s" % [n, levels[n - 1]])
		_expect(shift.office is MixedOffice and shift.office.spec.id == "hub_office", "Mixed Shift is not in its hub office")
		shift.advance_ms(1000.0)
		_expect(shift.hud.night_label.text == "9. Mixed Shift · %s" % levels[n - 1] and shift.hud.power_label.text.begins_with("DOOR SEAL") and shift.hud.usage_label.text.begins_with("VENT SEAL"), "the labels are wrong in shift %d" % n)
		shift.queue_free()
		await host.get_tree().process_frame
	# the room, the shared pieces, no captions, no audio players of its own
	var game := _shift(host, 2, 4242)
	await host.get_tree().process_frame
	_expect(game.hud.find_children("*", "Crosshair", true, false).size() == 1 and game.find_children("*", "AudioStreamPlayer", true, false).is_empty(), "the shared crosshair is missing or there is an audio player of its own")
	for id in ["monitor", "doorL_door", "doorR_door", "ventL", "ventR", "ventT", "lamp", "chair"]:
		_expect(game.office.stations.has(id), "station %s is missing" % id)
	for file in DirAccess.get_files_at("res://src/night_watch/mixed"):
		if file.ends_with(".gd"):
			_expect(not FileAccess.get_file_as_string("res://src/night_watch/mixed/" + file).contains("AudioStreamPlayer"), "%s makes its own audio player" % file)
	_expect(game.hud.call_panel == null or not game.hud.call_panel.visible, "a call box or caption is on screen in a Mixed Shift night")
	# doors toggle, the seal store drains while shut
	game.toggle_door("L")
	game.advance_ms(500.0)
	_expect(bool(game.sim.s["door"]["L"]["shut"]) and is_equal_approx(float(game.office.slab_progress["doorL"]), 1.0) and float(game.sim.s["seal"]) < MixedData.SEAL_MAX, "the left door did not shut and drain the seal")
	game.toggle_door("L")
	game.advance_ms(100.0)
	_expect(not bool(game.sim.s["door"]["L"]["shut"]), "the left door did not open")
	# the vents: seal and flash show on the office, the flash cools down
	game.set_seal("T", true)
	game.advance_ms(100.0)
	_expect(bool(game.sim.s["vent"]["T"]["shut"]) and (game.office.shutters["T"] as Node3D).visible, "the top vent did not seal")
	game.set_seal("T", false)
	var res := game.flash_vent("L")
	game.advance_ms(100.0)
	_expect(bool(res["ok"]) and (game.office.flashes["L"] as Node3D).visible and not bool(game.flash_vent("R")["ok"]), "the vent light did not flash once with its cooldown")
	# the monitor and its camera keys (CAM 9 is the vent run)
	game.manual_clock = true
	game._unhandled_input(_key(KEY_U))
	_expect(game.monitor_up and game.hud.monitor_root.visible and game.hud.cam_label.text.begins_with("CAM 1"), "the monitor did not open on CAM 1")
	game._unhandled_input(_key(KEY_9))
	_expect(game.monitor_room == "vent" and game.hud.cam_label.text == "CAM 9  %s" % String(MixedSkin.skin(game.world.dress_set)["labels"]["duct"]) and game.hud.feed_camera.global_position.distance_to(game.feed_transform("vent").origin) < 0.01, "key 9 did not show the vent run")
	game._unhandled_input(_key(KEY_3))
	_expect(game.monitor_room == "backstage", "key 3 did not pick camera 3")
	game._unhandled_input(_key(KEY_U))
	_expect(not game.monitor_up and not game.hud.monitor_root.visible, "the monitor did not close")
	# hunters walk, and the vent crawler is in the vent run; a tell at a door puts the walker in the doorway
	var walk := _shift(host, 3, 8)
	await host.get_tree().process_frame
	walk.manual_clock = false
	var th := walk.sim.list()[0] as Dictionary
	for t in walk.sim.list():
		if String(t["type"]) == "path":
			th = t
			break
	if String(th["type"]) == "path":
		th["active"] = true
		th["route"] = ["stage", "backstage", "westhall", "doorL"]
		th["routeId"] = "L-stage"
		th["i"] = 0
		walk._place_hunters()
		var model := walk._models[String(th["id"])] as Node3D
		var first := model.position
		th["i"] = 1
		walk._place_hunters()
		walk._animate_models(0.2)
		var goal := walk.world.stand_position("backstage", 0)
		_expect(first.distance_to(model.position) > 0.1 and model.position.distance_to(goal) > 0.5, "a walker was placed in her next room instead of walking")
		for i in 400:
			walk._animate_models(0.1)
		_expect(model.position.distance_to(goal) < 0.5, "a walker never reached her next room")
	# the transit hub: every sim room is a walk from every other and from both doors, no route crosses a wall, the map names and the nine cameras are MixedMap's, the dressing follows the seed
	var layout := MixedMap.map_layout()
	_expect((layout["cams"] as Array).size() == 9 and MixedMap.map_for("stage") == "platform" and MixedMap.sim_for("duct") == "vent" and MixedMap.SETS.size() == MixedSkin.SKINS.size(),
		"the transit hub's cameras, names or dressing draw are wrong")
	_expect(walk.world.dress_set >= 0 and walk.world.dress_set < MixedMap.SETS.size(), "the night's skin is not one of the rotation")
	var hub_keys := ["C:stage", "C:backstage", "C:dining", "C:westhall", "C:easthall", "C:kitchen", "C:closet", "C:corner", "D:doorL", "D:doorR"]
	var bad_wall := 0
	for ka in hub_keys:
		for kb in hub_keys:
			if ka == kb:
				continue
			var legs: Array = walk.world.route(ka, kb)
			_expect(legs.size() >= 2, "no walk from %s to %s in the hub" % [ka, kb])
			for k in range(1, legs.size()):
				var p0: Vector3 = legs[k - 1]["p"]
				var p1: Vector3 = legs[k]["p"]
				var n := int(ceil(p0.distance_to(p1) / 0.1))
				for q in n:
					var pt := p0.lerp(p1, float(q) / float(n))
					for w in walk.world.wall_boxes:
						if (w["rect"] as Rect2).has_point(Vector2(pt.x, pt.z)):
							bad_wall += 1
	_expect(bad_wall == 0, "walking routes in the transit hub cross walls at %d points" % bad_wall)
	for route_def in MixedData.ROUTES:
		var rooms_r: Array = route_def["rooms"]
		for i in range(rooms_r.size() - 1):
			_expect(walk.world.route(walk.world.key_for(String(rooms_r[i])), walk.world.key_for(String(rooms_r[i + 1]))).size() >= 2, "route %s has no walk from %s to %s" % [route_def["id"], rooms_r[i], rooms_r[i + 1]])
	for s_idx in MixedSkin.SKINS.size():
		var dressed := MixedWorld.new()
		dressed.dress_set = s_idx
		dressed.office = walk.office
		host.add_child(dressed)
		await host.get_tree().process_frame
		var seen_kind := {}
		for m in dressed.find_children("*", "MeshInstance3D", true, false):
			seen_kind[String(m.get_meta("nw_name", ""))] = true
		_expect(seen_kind.has(String(KIT_MARKER[String(MixedSkin.skin(s_idx)["kit"])])), "skin %s has none of its own props (%s)" % [MixedSkin.skin(s_idx)["id"], KIT_MARKER[String(MixedSkin.skin(s_idx)["kit"])]])
		dressed.queue_free()
		await host.get_tree().process_frame
	walk.manual_clock = true
	var vt := walk.sim.threat("verrine")
	if not vt.is_empty():
		vt["active"] = true
		vt["route"] = ["vent", "vent", "vent", "vent", "ventL"]
		vt["routeId"] = "V-L"
		vt["i"] = 2
		walk._place_hunters()
		_expect((walk._models["verrine"] as Node3D).visible and (walk._models["verrine"] as Node3D).position.distance_to(walk.vent_spot_pos(2)) < 0.1, "the vent crawler is not on her spot of the vent run")
		vt["armed"] = true
		vt["side"] = "L"
		walk.sim.s["lock"] = "verrine"
		walk._place_hunters()
		_expect((walk._models["verrine"] as Node3D).visible, "the crawler's face is not in her open vent")
		walk.sim.s["vent"]["L"]["shut"] = true
		walk._place_hunters()
		_expect(not (walk._models["verrine"] as Node3D).visible, "the crawler shows in a sealed vent")
	if not vt.is_empty():
		vt["active"] = true
		vt["i"] = 1
		walk._animate_models(0.016)
		_expect(walk._vent_pose.state_of("verrine") == "vent_enter", "the vent crawler did not drop into the vent run")
		for i in 60:
			walk._animate_models(0.02)
		_expect(walk._vent_pose.state_of("verrine") == "vent", "the vent crawler did not take her crawl pose in the vent run")
		vt["active"] = false
		vt["armed"] = false
		walk._animate_models(0.016)
		_expect(walk._vent_pose.state_of("verrine") == "vent_exit", "the vent crawler did not rise out of the run")
	walk.queue_free()
	await host.get_tree().process_frame
	# a loss: an unanswered deadly tell kills, the CAUGHT card says what would have stopped it, Retry replays the seed
	var lose := _shift(host, 1, 5)
	await host.get_tree().process_frame
	var victim := lose.sim.list()[0] as Dictionary
	victim["armed"] = true
	victim["tellOn"] = true
	victim["side"] = "L"
	victim["armedMs"] = 100.0
	victim["armedAt"] = 0.0
	victim["tellNeed"] = 3000.0
	lose.sim.s["lock"] = victim["id"]
	lose.sim.s["elapsed"] = 100000.0
	if String(victim["type"]) == "counter" or String(victim["type"]) == "vent":
		victim["type"] = "path"
	for i in 60:
		lose.advance_ms(100.0)
	_expect(lose.state == MixedGame.State.LOST and String(lose.last_death.get("by", "")) == String(victim["id"]), "an unanswered tell did not lose the shift")
	var closing := 0
	while lose.death_moment.is_open() and closing < 40:
		lose.death_moment.dismiss()
		closing += 1
	await host.get_tree().process_frame
	_expect(lose.hud.end_root.visible and lose.hud.end_title.text == "CAUGHT" and lose.hud.end_body.text.contains("Shut the") == false and lose.hud.end_body.text.length() > 20, "the CAUGHT card has no advice")
	var seed_before := lose.seed_value
	NightWatchSession.start_mode(lose.mode_id, lose.level, lose.custom, lose.seed_value)
	_expect(NightWatchSession.seed_value == seed_before and NightWatchSession.mode_id == "mixed" and lose.hud.retry_pressed.is_connected(lose.retry), "Retry would not replay the same seed")
	lose.queue_free()
	await host.get_tree().process_frame
	# a won night: saved under cleared_mixed, opens the next, no Custom Night
	var win := _shift(host, 1, 6)
	await host.get_tree().process_frame
	for t in win.sim.list():
		t["wait"] = 1e12
	win.sim.s["elapsed"] = MixedData.NIGHT_MS - 50.0
	win.advance_ms(100.0)
	_expect(win.state == MixedGame.State.WON and win.hud.end_title.text == "QUIET COMPLETE" and win.hud.end_next.visible, "a night held to 6 AM was not won")
	_expect(NightWatchSave.cleared_levels("mixed") == [1] and NightWatchSave.cleared_levels("classic").is_empty(), "winning QUIET did not save cleared_mixed")
	win.queue_free()
	await host.get_tree().process_frame
	# Endless: no 6 AM, the clock names the hours past 5 AM, caught saves the best hour and the end card says so
	var en := _shift(host, 5, 12)
	await host.get_tree().process_frame
	for t in en.sim.list():
		t["wait"] = 1e12
	en.sim.s["elapsed"] = 7.0 * MixedData.HOUR_MS
	en.advance_ms(100.0)
	_expect(en.state == MixedGame.State.PLAYING and en.hud.clock_label.text == "HOUR 7", "Endless ended at 6 AM or its clock is wrong: %s" % en.hud.clock_label.text)
	var ev := en.sim.list()[0] as Dictionary
	ev["armed"] = true
	ev["tellOn"] = true
	ev["side"] = "R"
	ev["armedMs"] = 100.0
	ev["armedAt"] = 0.0
	ev["tellNeed"] = 2000.0
	if String(ev["type"]) == "counter" or String(ev["type"]) == "vent":
		ev["type"] = "path"
	en.sim.s["lock"] = ev["id"]
	for i in 40:
		en.advance_ms(100.0)
	_expect(en.state == MixedGame.State.LOST and NightWatchSave.best_score("mixed") == 7 and int(en.last_death["hours"]) == 7, "Endless did not save its best hour (7): %d" % NightWatchSave.best_score("mixed"))
	var closing2 := 0
	while en.death_moment.is_open() and closing2 < 40:
		en.death_moment.dismiss()
		closing2 += 1
	await host.get_tree().process_frame
	_expect(en.hud.end_body.text.contains("7 hours") and not en.hud.end_next.visible, "the Endless end card does not report the hours")
	en.queue_free()
	await host.get_tree().process_frame
	_expect(not InputMap.has_action(NightWatchControls.LIGHT_LEFT) and not InputMap.has_action(MixedControls.SEAL_LEFT), "the quick-key actions stayed registered after the shift closed")
	NightWatchSave.reset()
	NightWatchSave.path = NightWatchSave.DEFAULT_PATH
	NightWatchSession.start(1)


# --- the admin menu: the gate, the sections, the layout at three sizes, and every entry really changes the shift ---------------------------------------------

func _admin_snapshot(game: MixedGame) -> String:
	return NightWatchAdminCheck.dump(game.sim.s) + str(game.sim.roster) + "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [game.sim.hunter_speed, game._admin_frozen, game._admin_god, game._admin_no_scare, game._admin_reveal,
		game._admin_noclip, game._admin_infinite_seal, game.world.dress_set, game.state, NightWatchSession.night, game.hud.cam_map.blips]


func _check_admin(host: Node) -> void:
	NightWatchSave.path = "user://night_watch_mixed_admin_test.cfg"
	NightWatchSave.reset()
	var game := _shift(host, 5, 800)
	await host.get_tree().process_frame
	for msg in NightWatchAdminCheck.sections(game, "MIXED SHIFT SPECIFIC"):
		_expect(false, "[admin] " + msg)
	_expect(game.hud.hint_label.text.contains("0 admin"), "the hint line does not list the admin key for an admin")
	for msg in await NightWatchAdminCheck.layout(host, game, "MIXED SHIFT SPECIFIC"):
		_expect(false, "[admin] " + msg)
	game.advance_ms(5000.0)
	for msg in NightWatchAdminCheck.exercise(game, func(g): return _admin_snapshot(g), ["WIN THE SHIFT", "LOSE THE SHIFT"]):
		_expect(false, "[admin] " + msg)
	game.queue_free()
	await host.get_tree().process_frame
	var g2 := _shift(host, 5, 801)
	await host.get_tree().process_frame
	g2.admin_set_hour(7)
	_expect(g2.sim.hour_of() == 7 and g2.hud.clock_label.text != "", "Endless SET THE HOUR 7 did not set the hour")
	g2.advance_ms(200.0)
	_expect(g2.hud.clock_label.text == "HOUR 7", "Endless's clock does not read HOUR 7 after the jump: %s" % g2.hud.clock_label.text)
	g2.admin_set_dressing(MixedSkin.index_of("yard"))
	_expect(g2.world.dress_set == MixedSkin.index_of("yard") and g2.world.find_children("*", "MeshInstance3D", true, false).any(func(m): return String(m.get_meta("nw_name", "")) == "BodyContainer"), "the dressing did not change to the salvage yard")
	g2.sim.admin_force_spike()
	var spike := false
	for i in 40:
		g2.advance_ms(100.0)
		spike = spike or String(g2.sim.s["beat"]) == "spike"
	_expect(spike, "FORCE A SPIKE did not start a spike")
	_expect(g2.sim.admin_force_chaos("flicker") and float(g2.sim.s["chaos"]["flicker"]) > 0.0, "FORCE A CHAOS EVENT did not start a flicker")
	g2.sim.admin_add_threat("verrine")
	g2.admin_place_hunter("verrine", "vent")
	g2._animate_models(0.016)
	_expect(String(g2.sim.threat("verrine")["routeId"]).begins_with("V-") and bool(g2.sim.threat("verrine")["active"]), "the vent crawler was not put in the run")
	g2.admin_set_frozen(true)
	var before := float(g2.sim.s["elapsed"])
	g2.advance_ms(2000.0)
	_expect(float(g2.sim.s["elapsed"]) == before, "the frozen clock still ran")
	g2.admin_set_frozen(false)
	g2.admin_set_god(true)
	g2.admin_set_hunter_speed(4.0)
	g2.admin_place_hunter(String(g2.sim.roster[0]), "doorL")
	g2.advance_ms(15000.0)
	_expect(g2.state == MixedGame.State.PLAYING, "god mode did not save the shift from a threat at the door")
	g2.admin_set_god(false)
	g2.admin_set_no_scare(true)
	g2.admin_lose()
	_expect(g2.state == MixedGame.State.LOST and not g2.death_moment.is_open(), "LOSE THE SHIFT with no jumpscare still played the scare")
	g2.queue_free()
	await host.get_tree().process_frame
	var g3 := _shift(host, 1, 802)
	await host.get_tree().process_frame
	g3.admin_win()
	_expect(g3.state == MixedGame.State.WON, "WIN THE SHIFT did not win")
	g3.queue_free()
	await host.get_tree().process_frame
	NightWatchSave.reset()
	NightWatchSave.path = NightWatchSave.DEFAULT_PATH
	NightWatchSession.start(1)


## The ROTATION through the other modes' maps (MixedSkin): every skin is visited, never the same one twice in a row, each skin's cameras/minimap/light/props are its own, and EVERY threat of the pool
## can be placed and shown on EVERY skin (door, hall, vent, camera room), because the rules' shape is the same one under every skin.
func _check_rotation(host: Node) -> void:
	var ids := MixedSkin.ids()
	_expect(ids.size() == 9, "the rotation does not have a skin for each of the nine maps")
	var modes := {}
	for sk in MixedSkin.SKINS:
		modes[String(sk["mode"])] = true
		var labels: Dictionary = sk["labels"]
		_expect(labels.size() == 9 and MixedMap.CAMS.all(func(c): return labels.has(c) and String(labels[c]) != ""), "skin %s does not name all nine cameras" % sk["id"])
		_expect(MixedSkin.SKINS.all(func(o): return o == sk or String((o["labels"] as Dictionary)["concourse"]) != String(labels["concourse"])), "skin %s shares its central room name with another" % sk["id"])
		_expect(MixedSkin.layout_for(MixedSkin.index_of(String(sk["id"])))["labels"] == labels, "layout_for(%s) does not carry the skin's names" % sk["id"])
	for m in ["classic", "mask", "lure", "bedroom", "story", "descent", "dayshift", "extra", "mixed"]:
		_expect(modes.has(m), "no skin for the %s map" % m)
	# the bag: 4 full cycles, each skin once per cycle, never twice in a row (also across the refill)
	MixedSkin.reset()
	var seq := []
	for i in 36:
		seq.append(MixedSkin.pick(1000 + i * 7))
	for i in range(1, seq.size()):
		_expect(seq[i] != seq[i - 1], "the rotation repeated skin %d back to back at night %d" % [seq[i], i])
	for c in 4:
		var seen := {}
		for i in 9:
			seen[seq[c * 9 + i]] = true
		_expect(seen.size() == 9, "rotation cycle %d did not visit every map" % c)
	# a night on each skin: the cameras (minimap labels), the props, the light; and every pool hunter everywhere
	for idx in MixedSkin.SKINS.size():
		var sk := MixedSkin.skin(idx)
		var g := _shift(host, 5, 300 + idx)
		await host.get_tree().process_frame
		g.admin_set_dressing(idx)
		await host.get_tree().process_frame
		var tag := "[skin %s] " % sk["id"]
		_expect(g.world.dress_set == idx, tag + "the world is not on the skin")
		for c in MixedMap.CAMS:
			_expect(g.hud.cam_map.label_for(c) == String((sk["labels"] as Dictionary)[c]), tag + "the minimap does not name %s '%s'" % [c, (sk["labels"] as Dictionary)[c]])
		_expect(g.world_env.environment.ambient_light_color.is_equal_approx(sk["light"]), tag + "the light is not the skin's")
		_expect(g.world.find_children("*", "MeshInstance3D", true, false).any(func(m): return String(m.get_meta("nw_name", "")) == KIT_MARKER[String(sk["kit"])]), tag + "no props of the skin")
		g.admin_set_hour(2)
		for p in MixedData.POOL:
			var id := String(p["id"])
			g.sim.admin_add_threat(id)
			for place in g.admin_places():
				g.admin_place_hunter(id, place)
				g._sync_visuals()
				var model := g._models[id] as Node3D
				var type := String(p["type"])
				if type == "counter":
					continue
				var th: Dictionary = g.sim.threat(id)
				if bool(th.get("active", false)) or bool(th.get("present", false)):
					_expect(model.position.is_finite(), tag + "%s at %s has no position" % [id, place])
					if type == "vent" and not place.begins_with("vent"):
						continue
					if String(place).begins_with("door") or place.begins_with("vent") or type == "vent":
						continue
					var legs: Array = g.world.legs_from(g.world.stand_position("stage", 0), place)
					_expect(legs.size() >= 1, tag + "%s has no walk to %s" % [id, place])
		g.queue_free()
		await host.get_tree().process_frame
	# ENDLESS keeps cycling: a rotation event moves the map on
	var e := _shift(host, 5, 801)
	await host.get_tree().process_frame
	var before := int(e.world.dress_set)
	e.sim.s["run"]["rotateAt"] = float(e.sim.s["elapsed"])
	e.advance_ms(250.0)
	_expect(e.sim.endless and int(e.world.dress_set) != before, "an ENDLESS roster rotation did not move the map on")
	e.queue_free()
	await host.get_tree().process_frame
	MixedSkin.reset()
