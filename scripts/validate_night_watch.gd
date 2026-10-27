extends RefCounted

## Night Watch (3D): the rules port reproduces the 2D game's numbers, replays deterministically, the defences work (shut door,
## light, cameras), the power and the blackout behave, and the night can be won and lost. The scene checks live further down.

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


## A bot that plays the night: shuts the door of whoever stands at it, keeps the monitor down.
func _play(game: NightWatchClassic, step_ms: float, bot: String = "doors") -> Array:
	var log := []
	var guard := 0
	while game.over == "" and guard < 100000:
		guard += 1
		var input := {"doorL": false, "doorR": false, "lightL": false, "lightR": false, "cam": false, "cam_room": "stage"}
		if bot == "doors":
			for door in ["doorL", "doorR"]:
				if not game.at_door(door).is_empty():
					input[door] = true
		elif bot == "lights":
			for door in ["doorL", "doorR"]:
				if not game.at_door(door).is_empty():
					input["lightL" if door == "doorL" else "lightR"] = true
		for e in game.step(step_ms, input):
			log.append(e)
	return log


func run(_host: Node) -> int:
	# --- the table matches the 2D game (docs/ROADMAP.md, classic-logic.js, time.js)
	_expect(is_equal_approx(NightWatchData.NIGHT_MS, 270000.0), "a night is not 270 s")
	_expect(NightWatchData.move_window(1) == Vector2(12500, 15500), "level 1 wait is not 12.5-15.5 s")
	_expect(NightWatchData.move_window(10) == Vector2(8000, 11000), "level 10 wait is not 8-11 s")
	_expect(NightWatchData.move_window(20) == Vector2(3000, 6000), "level 20 wait is not 3-6 s")
	_expect(NightWatchData.effective_level(0, 5) == 0 and NightWatchData.effective_level(4, 3) == 5
		and NightWatchData.effective_level(4, 4) == 6 and NightWatchData.effective_level(4, 2) == 4, "AI step-ups at 3 and 4 AM are wrong")
	_expect(is_equal_approx(NightWatchData.blackout_ms(1), 11100.0) and is_equal_approx(NightWatchData.blackout_ms(20), 4000.0),
		"Nyxie's blackout time is wrong")
	_expect(NightWatchData.level_for("dovelle", 1) == 2 and NightWatchData.level_for("dovelle", 9) == 16
		and NightWatchData.level_for("ravelle", 1) == 0 and NightWatchData.level_for("aki", 3) == 4, "night levels are wrong")
	_expect(NightWatchData.DOOR_GRACE_MS[0] == 9000.0 and NightWatchData.DOOR_GRACE_MS[5] == 5800.0, "door grace times are wrong")
	# the graph is undirected, every camera room is reachable from both doors, the doors hang off the halls
	for room in NightWatchData.GRAPH:
		for next in NightWatchData.GRAPH[room]:
			_expect((NightWatchData.GRAPH[next] as Array).has(room), "%s -> %s is not mirrored" % [room, next])
	for door in ["doorL", "doorR"]:
		var dist := NightWatchData.distances_to(door)
		_expect(dist.size() == NightWatchData.GRAPH.size(), "%s cannot be reached from every room" % door)
	_expect(NightWatchData.cam_rooms().size() == 8 and NightWatchData.room_for_cam(4) == "westhall", "camera table is wrong")
	_expect(NightWatchData.active_hunters(1) == ["dovelle"] and NightWatchData.active_hunters(3).size() == 3
		and NightWatchData.active_hunters(4).size() == 4, "who is on the floor each night is wrong")

	# --- determinism: the same seed gives the same night, another seed a different one
	var a := NightWatchClassic.new(4, 12345)
	var b := NightWatchClassic.new(4, 12345)
	var c := NightWatchClassic.new(4, 999)
	var la := _play(a, 100.0)
	var lb := _play(b, 100.0)
	var lc := _play(c, 100.0)
	_expect(JSON.stringify(la) == JSON.stringify(lb), "the same seed did not replay the same night")
	_expect(JSON.stringify(la) != JSON.stringify(lc), "different seeds played the same night")
	_expect(a.over == "win" and is_equal_approx(a.elapsed, NightWatchData.NIGHT_MS), "a bot that shuts the door on every visitor did not win night 4")

	# --- a night nobody defends is lost to a hunter at the door (night 6, everyone keen), and the loss names her
	var open := NightWatchClassic.new(6, 7)
	_play(open, 100.0, "none")
	_expect(open.over == "caught" and open.by != "", "an undefended night 6 was not lost")
	_expect(NightWatchData.HUNTERS.has(open.by) or open.by == "nyxie", "the catcher is not a Night Watch hunter")

	# --- the defences, one by one (a level-20 Dovelle comes quickly)
	var shut := NightWatchClassic.new(1, 3, {"dovelle": 20, "ravelle": 0, "aki": 0, "ilyra": 0})
	var arrived := false
	var repelled := false
	var guard := 0
	while shut.over == "" and guard < 20000 and not repelled:
		guard += 1
		var closed: bool = not shut.at_door("doorL").is_empty()
		for e in shut.step(50.0, {"doorL": closed}):
			arrived = arrived or String(e["type"]) == "arrived"
			repelled = repelled or String(e["type"]) == "repelled"
	_expect(arrived and repelled and shut.over == "", "a shut door did not turn a hunter away")
	_expect((shut.hunters["dovelle"] as NightWatchStalker).room == "dining", "a shut door did not send her to the dining area (retreat_to)")

	var lit := NightWatchClassic.new(1, 3, {"dovelle": 20, "ravelle": 0, "aki": 0, "ilyra": 0})
	var pushed := false
	var flinched := false
	guard = 0
	while lit.over == "" and guard < 20000 and not pushed:
		guard += 1
		var on: bool = not lit.at_door("doorL").is_empty()
		for e in lit.step(50.0, {"lightL": on}):
			flinched = flinched or String(e["type"]) == "flinch"
			pushed = pushed or String(e["type"]) == "pushed"
	_expect(flinched and pushed, "the light did not make her flinch and then back off")
	_expect((lit.hunters["dovelle"] as NightWatchStalker).room == "stage", "the light did not drive her back to the stage (push_to)")

	var ignored := NightWatchClassic.new(1, 3, {"dovelle": 20, "ravelle": 0, "aki": 0, "ilyra": 0})
	var started := -1.0
	guard = 0
	while ignored.over == "" and guard < 40000:
		guard += 1
		ignored.step(50.0, {})
		if started < 0.0 and not ignored.at_door("doorL").is_empty():
			started = ignored.elapsed
	_expect(ignored.over == "caught" and ignored.by == "dovelle", "an unanswered door did not end the night")
	var waited := ignored.elapsed - started
	_expect(absf(waited - 9000.0) < 120.0, "night 1's door wait is not 9 s (waited %.0f ms)" % waited)

	# --- Aki only moves while the monitor is down, Ilyra freezes while her room is on the monitor
	var aki_up := NightWatchClassic.new(3, 5, {"dovelle": 0, "ravelle": 0, "aki": 20, "ilyra": 0})
	for i in 600:
		aki_up.step(100.0, {"cam": true, "cam_room": "stage", "doorR": true})
	_expect((aki_up.hunters["aki"] as NightWatchStalker).room == "closet", "Aki moved while the monitor was up")
	var aki_down := NightWatchClassic.new(3, 5, {"dovelle": 0, "ravelle": 0, "aki": 20, "ilyra": 0})
	for i in 300:
		aki_down.step(100.0, {"doorR": true})
	_expect((aki_down.hunters["aki"] as NightWatchStalker).room != "closet", "Aki never left the closet with the monitor down")
	var ilyra := NightWatchClassic.new(4, 9, {"dovelle": 0, "ravelle": 0, "aki": 0, "ilyra": 20})
	for i in 600:
		ilyra.step(100.0, {"cam": true, "cam_room": "backstage", "doorL": true})
	_expect((ilyra.hunters["ilyra"] as NightWatchStalker).room == "backstage", "Ilyra moved while her room was watched")

	# --- two hunters can share a door; a third waits in the hall
	var share := NightWatchClassic.new(5, 11)
	(share.hunters["dovelle"] as NightWatchStalker).room = "doorL"
	(share.hunters["ilyra"] as NightWatchStalker).room = "doorL"
	share.step(10.0, {"doorL": true})
	_expect(share.at_door("doorL").size() == 2, "two hunters did not share the left door")
	_expect(share._occupied("doorL", "ravelle"), "a full door was not reported full to a third hunter")

	# --- the power meter: idle drain, devices cost more, at zero the doors open and Nyxie comes
	var idle := NightWatchClassic.new(1, 1, {"dovelle": 0})
	for i in 100:
		idle.step(1000.0, {})
	_expect(absf((100.0 - idle.power) - NightWatchData.POWER_BASE * 100.0) < 0.01, "idle power drain is not the base rate")
	var busy := NightWatchClassic.new(1, 1, {"dovelle": 0})
	for i in 100:
		busy.step(1000.0, {"doorL": true, "lightR": true, "cam": true})
	_expect(absf((100.0 - busy.power) - (NightWatchData.POWER_BASE + 3.0 * NightWatchData.POWER_PER_DEVICE) * 100.0) < 0.05,
		"devices in use do not cost power")
	_expect(NightWatchClassic.usage({"doorL": true, "cam": true}) == 2, "usage count is wrong")
	var dark := NightWatchClassic.new(3, 2, {"dovelle": 0, "ravelle": 0, "aki": 0, "ilyra": 0, "nyxie": 10})
	dark.power = 0.2
	var went_out := false
	var blackout_start := -1.0
	guard = 0
	while dark.over == "" and guard < 2000:
		guard += 1
		for e in dark.step(100.0, {"doorL": true, "doorR": true, "lightL": true, "cam": true}):
			if String(e["type"]) == "out":
				went_out = true
				blackout_start = dark.elapsed
	_expect(went_out and dark.out, "the power never went out")
	_expect(not bool(dark.door_shut["doorL"]) and not bool(dark.light_on["doorL"]), "doors stayed shut and lights on with the power out")
	_expect(dark.over == "caught" and dark.by == "nyxie", "Nyxie did not come in the dark")
	var in_dark := dark.elapsed - blackout_start
	_expect(absf(in_dark - NightWatchData.blackout_ms(10)) < 200.0, "the dark did not last Nyxie's blackout time (%.0f ms)" % in_dark)

	if _failures == 0:
		print("  night_watch  rules port: 2D numbers, deterministic nights, doors, lights, cameras, sharing, power, blackout")
	return _failures
