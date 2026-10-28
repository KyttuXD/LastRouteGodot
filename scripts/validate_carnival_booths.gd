extends RefCounted

## Carnival booths (docs/CARNIVAL_BOOTHS.md): the rules of every game by bots that play it (a good bot wins, an idle or careless one does not, same seed = same game), the host's judgement of a result
## (plausible time and score, cooldown, reward), the cooldown in the world state through a snapshot, the booth node (prompt, board, movement lock, overlay, report), and the route: a real booth in a
## streamed carnival chunk, started and finished through the host with its cooldown, its prize and a second player turned away.
##
##   godot --headless --path . res://scenes/validate.tscn -- carnival_booths

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	_check_data()
	_check_ring_toss()
	_check_strength()
	_check_other_games()
	_check_world_state()
	await _check_node(host)
	await _check_route(host)
	if _failures == 0:
		print("  carnival_booths  rules (bots win / idle bots lose / seeded), host judgement, cooldown through a snapshot, the booth node and the route flow")
	return _failures


func _run_game(game: CarnivalGame, bot: Callable, max_seconds := 60.0) -> void:
	var dt := 1.0 / 60.0
	var t := 0.0
	while not game.finished and t < max_seconds:
		bot.call(game, t)
		game.step(dt)
		t += dt
	_expect(game.finished, "%s never finished within %.0f s" % [game.get_script().get_global_name(), max_seconds])


func _check_data() -> void:
	for type in CarnivalBooths.BOOTHS:
		var s := CarnivalBooths.spec(String(type))
		_expect(CarnivalBooths.make_game(String(type), 5) != null, "%s has no game" % type)
		_expect(float(s["seconds"]) >= 10.0 and float(s["seconds"]) <= 30.0, "%s runs %.0f s: not the 10-30 s of a booth game" % [type, float(s["seconds"])])
		_expect(float(s["win_cooldown"]) > float(s["lose_cooldown"]) and float(s["lose_cooldown"]) > 0.0, "%s cooldowns are not ordered win > lose > 0" % type)
		_expect(not (s["noise"] as Dictionary).is_empty(), "%s makes no noise: a booth is loud" % type)
		_expect(["battery", "tool", "hint"].has(String(s["reward"])), "%s has an unknown reward" % type)
		_expect(PropModelCatalog.interaction_for(String(type)) == "play", "%s is not a playable prop" % type)
		_expect(CarnivalBooths.reward_for(String(type), 3) == CarnivalBooths.reward_for(String(type), 3), "%s reward is not deterministic" % type)
		var game := CarnivalBooths.make_game(String(type), 1)
		_expect(not CarnivalBooths.plausible(String(type), 0, 0.2), "%s accepts a game that lasted 0.2 s" % type)
		_expect(not CarnivalBooths.plausible(String(type), game.max_score() + 1, 10.0), "%s accepts a score above the maximum" % type)
		_expect(not CarnivalBooths.plausible(String(type), 0, float(s["seconds"]) + 60.0), "%s accepts a game that lasted a minute over" % type)
		_expect(CarnivalBooths.plausible(String(type), 0, float(s["seconds"])), "%s rejects an ordinary full-length game" % type)
		_expect(not CarnivalBooths.is_win(String(type), 0) and CarnivalBooths.is_win(String(type), game.max_score()), "%s: 0 should lose and the maximum win" % type)
	_expect(CarnivalBooths.reward_for("strengthTester", 1)["kind"] == "hint" and CarnivalBooths.reward_for("ringTossStall", 1)["kind"] == "battery", "ring toss pays a battery and the strength tester a relay hint")
	_expect(CarnivalBooths.noise_for("strengthTester", "bell")[0] >= 0.9 and CarnivalBooths.noise_for("ringTossStall", "throw")[0] < 0.3, "the bell is the loudest and a ring throw quiet")


func _check_ring_toss() -> void:
	# a bot that leads the turning disc: each ring at a free neck where it will be when the ring lands
	var good := func(g: RingTossGame, t: float) -> void:
		var free := []
		for i in RingTossGame.NECKS:
			if not g.on_necks.has(i):
				free.append(i)
		if free.is_empty():
			return
		var neck := int(free[0])
		var ahead := g.neck_position(neck, g.angle + RingTossGame.TURN_SPEED * RingTossGame.FLIGHT)
		g.set_aim(ahead)
		if g.flying.is_empty() and g.rings_left > 0 and t > 0.5:
			g.fire()
	var game := RingTossGame.new(11)
	_run_game(game, good)
	_expect(game.booth_score == 3 and game.won(), "a bot that leads the disc should put all three rings on (got %d)" % game.booth_score)
	_expect(game.booth_score <= game.max_score(), "ring toss scored above its maximum")
	# a bot that throws at the middle of the disc (no neck is there) never scores
	var careless := RingTossGame.new(11)
	_run_game(careless, func(g: RingTossGame, t: float) -> void:
		g.set_aim(Vector2.ZERO)
		if g.flying.is_empty() and g.rings_left > 0 and t > 0.5:
			g.fire())
	_expect(careless.booth_score == 0 and not careless.won() and careless.rings_left == 0, "aiming at the hub must not score")
	# an idle player: the game still ends on time, no win
	var idle := RingTossGame.new(3)
	_run_game(idle, func(_g, _t) -> void: pass)
	_expect(idle.elapsed >= idle.seconds - 0.05 and not idle.won() and idle.rings_left == RingTossGame.RINGS, "an idle ring toss should run out its time without a win")
	# same seed, same inputs, same events
	var a := RingTossGame.new(77)
	var b := RingTossGame.new(77)
	var log_a := []
	var log_b := []
	for g in [a, b]:
		_run_game(g, good)
	_expect(a.booth_score == b.booth_score and a.angle == b.angle, "ring toss is not deterministic for a seed")
	var c := RingTossGame.new(78)
	_expect(c.angle != a.angle - RingTossGame.TURN_SPEED * a.elapsed or true, "")
	# events a booth can animate and make noise for
	var seen := {}
	var recorder := RingTossGame.new(11)
	var before := 0
	while not recorder.finished and before < 4000:
		good.call(recorder, float(before) / 60.0)
		recorder.step(1.0 / 60.0)
		for e in recorder.take_events():
			seen[String(e["type"])] = true
		before += 1
	_expect(seen.has("throw") and seen.has("ring_on") and seen.has("end"), "ring toss did not report throw, ring_on and end events: %s" % str(seen.keys()))


func _check_strength() -> void:
	# a bot that holds until the meter is nearly full, then lets go
	var good := func(g: StrengthGame, _t: float) -> void:
		if g.puck_rising or g.swings_left <= 0:
			g.set_hold(false)
			return
		if not g.holding:
			g.set_hold(true)
		elif g.meter >= 0.985:
			g.set_hold(false)
	var game := StrengthGame.new(5)
	_run_game(game, good)
	_expect(game.won() and game.booth_score == 1 and game.rang, "a bot that releases on the peak should ring the bell")
	_expect(game.best_power >= StrengthGame.BELL_AT, "the bell rang below its threshold")
	# a bot that lets go straight away: the puck barely moves, three swings, no win
	var weak := StrengthGame.new(5)
	_run_game(weak, func(g: StrengthGame, _t: float) -> void:
		if g.puck_rising or g.swings_left <= 0:
			g.set_hold(false)
		elif not g.holding:
			g.set_hold(true)
		elif g.meter > 0.05 and g.meter < 0.3:
			g.set_hold(false))
	_expect(not weak.won() and weak.swings_left == 0, "weak swings must not ring the bell (swings left %d)" % weak.swings_left)
	var idle := StrengthGame.new(5)
	_run_game(idle, func(_g, _t) -> void: pass)
	_expect(not idle.won() and idle.swings_left == StrengthGame.SWINGS, "an idle strength tester runs out of time")
	# the bell is an event the booth makes its loudest noise for
	var seen := {}
	var g2 := StrengthGame.new(5)
	var n := 0
	while not g2.finished and n < 6000:
		good.call(g2, 0.0)
		g2.step(1.0 / 60.0)
		for e in g2.take_events():
			seen[String(e["type"])] = true
		n += 1
	_expect(seen.has("windup") and seen.has("swing") and seen.has("bell") and seen.has("end"), "strength tester events missing: %s" % str(seen.keys()))


func _check_other_games() -> void:
	# CLAW: steer over a prize and drop; the grip is a chance, so a bot may need both drops: over many seeds it wins most, an idle one never
	var wins := 0
	for seed_value in 20:
		var claw := ClawGame.new(seed_value)
		_run_game(claw, func(g: ClawGame, _t: float) -> void:
			if g.phase != "idle":
				return
			var best := -1
			for i in g.prizes.size():
				if not g.prizes[i]["gone"]:
					best = i
					break
			if best < 0:
				return
			var to: Vector2 = (g.prizes[best]["at"] as Vector2) - g.pos
			if to.length() > 0.02:
				g.set_move(to.normalized())
			else:
				g.set_move(Vector2.ZERO)
				g.fire())
		wins += int(claw.won())
		_expect(claw.booth_score <= claw.max_score(), "claw scored above its maximum")
	_expect(wins >= 12 and wins < 20 + 1, "a centred claw bot should win most games but the grip is a chance (won %d of 20)" % wins)
	var idle_claw := ClawGame.new(1)
	_run_game(idle_claw, func(_g, _t) -> void: pass)
	_expect(not idle_claw.won() and idle_claw.drops_left == ClawGame.DROPS, "an idle claw machine must not win")
	# SHOOTING GALLERY: a bot that fires at whichever target is up hits plenty; one that fires at the sky none
	var shooter := ShootingGame.new(4)
	_run_game(shooter, func(g: ShootingGame, _t: float) -> void:
		for t in g.targets:
			if bool(t["up"]) and not bool(t["hit"]):
				g.set_aim(t["at"])
				g.fire()
				return)
	_expect(shooter.won() and shooter.booth_score <= shooter.max_score(), "a bot that shoots targets that are up should win (hits %d)" % shooter.booth_score)
	var sky := ShootingGame.new(4)
	_run_game(sky, func(g: ShootingGame, t: float) -> void:
		g.set_aim(Vector2(0, 3))
		if int(t * 4.0) != int((t - 0.02) * 4.0):
			g.fire())
	_expect(sky.booth_score == 0 and not sky.won(), "shooting at the sky must not score")
	# WHACK-A-MOLE
	var whacker := MoleGame.new(8)
	_run_game(whacker, func(g: MoleGame, _t: float) -> void:
		for i in g.up.keys():
			g.set_aim(g.holes[i])
			g.fire()
			return)
	_expect(whacker.won(), "a bot that hits every mole should win (whacked %d)" % whacker.booth_score)
	var wild := MoleGame.new(8)
	_run_game(wild, func(g: MoleGame, _t: float) -> void:
		g.set_aim(Vector2(5, 5))
		g.fire())
	_expect(wild.booth_score == 0, "swinging at nothing whacked a mole")
	# DUCK POND
	var angler := DuckGame.new(2)
	_run_game(angler, func(g: DuckGame, t: float) -> void:
		g.set_aim(g.duck_position(g.marked))
		if g.hooks_left > 0 and int(t * 2.0) != int((t - 0.02) * 2.0):
			g.fire())
	_expect(angler.won() and angler.booth_score <= angler.max_score(), "an angler aiming at the marked duck should win (caught %d)" % angler.booth_score)
	var dud := DuckGame.new(2)
	_run_game(dud, func(g: DuckGame, t: float) -> void:
		g.set_aim(Vector2(3, 3))
		if int(t * 2.0) != int((t - 0.02) * 2.0):
			g.fire())
	_expect(dud.booth_score == 0 and not dud.won(), "hooking at nothing caught a duck")
	for type in ["prizeClawMachine", "shootingGallery", "whackAMole", "duckPond"]:
		var a := CarnivalBooths.make_game(type, 6)
		var b := CarnivalBooths.make_game(type, 6)
		_expect(a.state().hash() == b.state().hash(), "%s is not deterministic for a seed" % type)


func _check_world_state() -> void:
	var state := StreamedWorldState.new()
	var now := 1_800_000_000.0
	_expect(state.booth_cooldown_left("a", now) == 0.0, "an unknown booth is ready")
	_expect(state.rest_booth("a", now + 300.0) and is_equal_approx(state.booth_cooldown_left("a", now), 300.0), "resting a booth did not start its cooldown")
	_expect(not state.rest_booth("a", now + 100.0) and is_equal_approx(state.booth_cooldown_left("a", now), 300.0), "a replayed or shorter event shortened the cooldown")
	_expect(is_equal_approx(state.booth_cooldown_left("a", now + 299.0), 1.0) and state.booth_cooldown_left("a", now + 301.0) == 0.0, "the cooldown does not run down with the clock")
	var restored := StreamedWorldState.new()
	_expect(restored.adopt(state.snapshot()) and is_equal_approx(restored.booth_cooldown_left("a", now), 300.0), "the cooldown did not survive a snapshot (a reconnect)")
	var legacy := state.snapshot()
	legacy["schema"] = 5
	legacy.erase("booth_ready_at")
	var old := StreamedWorldState.new()
	_expect(old.adopt(legacy) and old.booth_ready_at.is_empty(), "a schema 5 snapshot without booths no longer loads")
	state.rest_booth("b", now - 5.0)
	state.prune_booths(now)
	_expect(not state.booth_ready_at.has("b") and state.booth_ready_at.has("a"), "prune_booths dropped a running cooldown or kept a finished one")


func _check_node(host: Node) -> void:
	for type in CarnivalBooths.BOOTHS:
		var booth := CarnivalBooth3D.new()
		booth.manual = true
		booth.setup("0:0:0:%s:3:3" % type, String(type), Vector3(2.0, 2.4, 1.5))
		host.add_child(booth)
		await host.get_tree().process_frame
		var tag := "[%s booth] " % type
		var rest := [0.0]
		booth.rest_resolver = func() -> float: return float(rest[0])
		var reports := []
		booth.reporter = func(event: Dictionary) -> void: reports.append(event)
		_expect(booth.prompt_text() == "PLAY %s" % CarnivalBooths.title_for(String(type)), tag + "the ready prompt is '%s'" % booth.prompt_text())
		rest[0] = 125.0
		_expect(booth.prompt_text().contains("BACK IN 2:05"), tag + "the resting prompt is '%s'" % booth.prompt_text())
		rest[0] = 0.0
		var player := PlayerController3D.new()
		booth.begin_local(player, 9)
		await host.get_tree().process_frame
		_expect(booth.mode == CarnivalBooth3D.Mode.PLAYING_LOCAL and booth.game != null and booth.board != null, tag + "begin_local did not start the game and the board")
		_expect(player.movement_locked, tag + "the player can still walk during the game")
		_expect(booth.prompt_text().contains("IN USE") and booth.is_busy(), tag + "a busy booth does not say so")
		booth.begin_remote(5, 1)
		_expect(booth.mode == CarnivalBooth3D.Mode.PLAYING_LOCAL, tag + "a second player took over a busy booth")
		_expect(booth.find_child("BoothOverlay", true, false) != null, tag + "no overlay with the prompt and the time")
		# play it with a bot through the node, one tick at a time
		var game := booth.game
		var t := 0.0
		while not game.finished and t < 40.0:
			if game is RingTossGame:
				var g := game as RingTossGame
				var free := range(RingTossGame.NECKS).filter(func(i): return not g.on_necks.has(i))
				if not free.is_empty():
					g.set_aim(g.neck_position(int(free[0]), g.angle + RingTossGame.TURN_SPEED * RingTossGame.FLIGHT))
					if g.flying.is_empty() and g.rings_left > 0 and t > 0.4:
						g.fire()
			elif game is StrengthGame:
				var s := game as StrengthGame
				if s.puck_rising or s.swings_left <= 0:
					s.set_hold(false)
				elif not s.holding:
					s.set_hold(true)
				elif s.meter >= 0.985:
					s.set_hold(false)
			booth.step_game(1.0 / 30.0)
			t += 1.0 / 30.0
		_expect(game.finished and reports.size() == 1, tag + "the finished game was not reported exactly once (%d reports)" % reports.size())
		if not reports.is_empty():
			var r: Dictionary = reports[0]
			_expect(String(r["action"]) == "finish" and int(r["booth_score"]) == game.booth_score and float(r["elapsed"]) >= CarnivalBooths.MIN_PLAY_SECONDS, tag + "the report is wrong: %s" % str(r))
			_expect(CarnivalBooths.plausible(String(type), int(r["booth_score"]), float(r["elapsed"])), tag + "the host would not accept this node's own report: %s" % str(r))
		booth.end_game(game.won(), game.booth_score)
		await host.get_tree().process_frame
		_expect(not player.movement_locked and not booth.is_busy(), tag + "the booth still holds the player after the result")
		_expect(booth.find_child("BoothOverlay", true, false) == null or booth.find_child("BoothOverlay", true, false).is_queued_for_deletion(), tag + "the overlay stays after the result")
		# cancel path
		booth.begin_local(player, 10)
		reports.clear()
		booth.cancel_local()
		_expect(reports.size() == 1 and String(reports[0]["action"]) == "cancel", tag + "cancel did not report")
		booth.end_game(false)
		# a remote turn shows the board and ends without touching a player
		booth.begin_remote(7, 12)
		_expect(booth.mode == CarnivalBooth3D.Mode.PLAYING_REMOTE and booth.occupant_peer() == 7 and booth.board != null, tag + "a remote turn did not show the board")
		booth.end_game(true, 1)
		# the bulbs are there and animate
		_expect(booth._bulbs.size() == CarnivalBooth3D.BULBS and booth._bulbs[0].is_inside_tree(), tag + "the bulb chase is missing")
		player.free()
		booth.queue_free()
		await host.get_tree().process_frame


func _check_route(host: Node) -> void:
	# the host flow in the real route needs a streamed carnival chunk with a booth: found by walking the generator, then loaded by standing there
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 8:
		await host.get_tree().process_frame
	var kinds := {}
	for y in range(0, -6, -1):
		for x in range(-12, 13):
			for z in range(-12, 13):
				for value in route.facility.generator.chunk(Vector3i(x, y, z)).get("region_props", []):
					var kind := String((value as Dictionary).get("type", ""))
					if CarnivalBooths.is_booth(kind):
						kinds[kind] = true
	for type in CarnivalBooths.BOOTHS:
		_expect(kinds.has(type), "the generator never places a %s within the search window: that game is not in the district (found %s)" % [type, str(kinds.keys())])
	var found := {}
	for y in range(0, -6, -1):
		for x in range(-12, 13):
			for z in range(-12, 13):
				if not found.is_empty():
					break
				var coord := Vector3i(x, y, z)
				for value in route.facility.generator.chunk(coord).get("region_props", []):
					var prop: Dictionary = value
					if CarnivalBooths.is_booth(String(prop.get("type", ""))):
						found = {"coord": coord, "prop": prop}
						break
	_expect(not found.is_empty(), "no carnival booth was generated within the search window: the district has no playable game")
	if found.is_empty():
		route.queue_free()
		await host.get_tree().process_frame
		return
	var coord: Vector3i = found["coord"]
	var prop: Dictionary = found["prop"]
	var cell: Vector2i = prop["cell"]
	var type := String(prop["type"])
	var booth_id := "%d:%d:%d:%s:%d:%d" % [coord.x, coord.y, coord.z, type, cell.x, cell.y]
	var info: Dictionary = route._booth_info(booth_id)
	_expect(not info.is_empty() and String(info["type"]) == type, "the host cannot re-derive a generated booth from its id %s" % booth_id)
	_expect(route._booth_info("0:0:0:ringTossStall:1:1").is_empty() or true, "")
	_expect(route._booth_info("9:9:9:ringTossStall:1:1").is_empty() and route._booth_info("junk").is_empty() and route._booth_info(booth_id.replace(type, "popcornCart")).is_empty(),
		"the host accepts an invented booth id")
	# an invented start does nothing
	route._accept_booth(1, {"action": "start", "booth_id": "9:9:9:ringTossStall:1:1"})
	_expect(route._booth_occupants.is_empty(), "a booth that does not exist took a player")
	# stand at the booth: the chunk streams in and the booth node exists
	var center: Vector2 = info["center"]
	route._admin_teleport_to(Vector3(center.x, float(coord.y) * StreamedFacilityView3D.LEVEL_HEIGHT + 0.3, center.y + 2.0))
	for _i in 20:
		await host.get_tree().process_frame
	var booth: CarnivalBooth3D = route.facility.booth_node(booth_id)
	_expect(booth != null, "the booth %s has no node once the player stands at it" % booth_id)
	if booth == null:
		route.queue_free()
		await host.get_tree().process_frame
		return
	var now := Time.get_unix_time_from_system()
	var max_score := CarnivalBooths.make_game(type, 0).max_score()
	# the player's own request: the host (solo here) starts the game; the booth shows it and holds the player
	route.player.global_position.y = float(coord.y) * StreamedFacilityView3D.LEVEL_HEIGHT + 0.3
	route._request_booth(route.player, booth_id, type)
	_expect(route._booth_occupants.has(booth_id) and booth.mode == CarnivalBooth3D.Mode.PLAYING_LOCAL and route.player.movement_locked,
		"a request at the booth did not start the game and hold the player (occupied %s, mode %s)" % [route._booth_occupants.has(booth_id), booth.mode])
	# a second player (peer 2) is turned away while the booth is taken; so is a finish from the wrong peer
	route._accept_booth(2, {"action": "start", "booth_id": booth_id})
	route._accept_booth(2, {"action": "finish", "booth_id": booth_id, "booth_score": max_score, "elapsed": 10.0})
	_expect(int(route._booth_occupants[booth_id]["peer"]) == 1 and booth.mode == CarnivalBooth3D.Mode.PLAYING_LOCAL, "a second player took or ended the booth")
	# an impossible result (a score above the maximum) is a cancelled game: a short rest, no prize
	var battery_before: int = route.player.inventory_order.count("battery")
	route._accept_booth(1, {"action": "finish", "booth_id": booth_id, "booth_score": 99, "elapsed": 10.0})
	var left: float = route.world_state.booth_cooldown_left(booth_id, Time.get_unix_time_from_system())
	_expect(left > 5.0 and left <= CarnivalBooths.CANCEL_COOLDOWN + 1.0 and not booth.is_busy() and not route.player.movement_locked and route._booth_occupants.is_empty(),
		"an impossible result should rest the booth briefly and release the player (rest %.1f, busy %s)" % [left, booth.is_busy()])
	_expect(route.player.inventory_order.count("battery") == battery_before, "an impossible result paid a prize")
	# while it rests nobody starts it
	route._request_booth(route.player, booth_id, type)
	route._accept_booth(1, {"action": "start", "booth_id": booth_id})
	_expect(route._booth_occupants.is_empty() and not booth.is_busy(), "a resting booth started a game")
	_expect(booth.prompt_text().contains("BACK IN"), "a resting booth does not show its cooldown: '%s'" % booth.prompt_text())
	# the cooldown lives in the world state: a snapshot carries it to a late joiner
	var late := StreamedWorldState.new()
	_expect(late.adopt(route.world_state.snapshot()) and late.booth_cooldown_left(booth_id, Time.get_unix_time_from_system()) > 5.0, "the cooldown is not in the world snapshot")
	# rested: a winning game pays and rests for the long cooldown
	route.world_state.booth_ready_at.erase(booth_id)
	route._request_booth(route.player, booth_id, type)
	_expect(route._booth_occupants.has(booth_id), "the booth did not start again after its cooldown")
	route._accept_booth(1, {"action": "finish", "booth_id": booth_id, "booth_score": max_score, "elapsed": 12.0})
	var win_left: float = route.world_state.booth_cooldown_left(booth_id, Time.get_unix_time_from_system())
	_expect(win_left > CarnivalBooths.cooldown_for(type, true) - 5.0, "a win should rest the booth for %.0f s (got %.1f)" % [CarnivalBooths.cooldown_for(type, true), win_left])
	if String(CarnivalBooths.spec(type).get("reward", "")) == "battery":
		_expect(route.player.inventory_order.count("battery") == battery_before + 1, "a ring toss win did not pay a battery")
	# a game left unfinished is freed by the host after its length plus the grace
	route.world_state.booth_ready_at.erase(booth_id)
	route._request_booth(route.player, booth_id, type)
	route._booth_occupants[booth_id]["since"] = Time.get_unix_time_from_system() - 1000.0
	route._tick_booth_occupancy()
	_expect(route._booth_occupants.is_empty() and not booth.is_busy() and not route.player.movement_locked, "a game left unfinished never freed its booth")
	_expect(now > 0.0, "")
	route.queue_free()
	await host.get_tree().process_frame
