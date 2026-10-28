extends RefCounted

## Night Watch, The Descent (mode `descent`): the rules port reproduces the 2D numbers (scripts/validate-descent.mjs and
## validate-variety-descent.mjs), a descent replays the same for a seed, every puzzle can be solved, and the shift scene starts from the
## Shift Board, can be won and lost, saves the clear, opens the next descent and feeds the Custom Night slider into the logic.

const L := preload("res://src/night_watch/descent/descent_logic.gd")
const D := preload("res://src/night_watch/descent/descent_data.gd")

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _rng(seed_number: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_number
	return r


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


## A scripted player solves whatever stage is up.
func _solve(g: L) -> Array:
	if g.ride > 0.0:
		_run(g, g.ride)
	var z := g.puzzle
	var out := []
	if z.is_empty():
		return out
	var stage := g.stage_idx
	match String(z["kind"]):
		"wires":
			for b in z["lit"]:
				out.append_array(g.act("wires", {"button": (z["wire"] as Array)[b]}))
		"memory":
			while String(z["phase"]) == "show":
				_run(g, 100.0)
			for pad in z["seq"]:
				out.append_array(g.act("memory", {"pad": pad}))
		"pipes":
			for cell in z["path"]:
				var t: Dictionary = z["tiles"][cell[0]][cell[1]]
				while g.stage_idx == stage and int(t["rot"]) != int(t["solved"]):
					out.append_array(g.act("pipes", {"r": cell[0], "c": cell[1]}))
	return out


func _solve_pipes_in_place(z: Dictionary) -> void:
	for cell in z["path"]:
		var t: Dictionary = z["tiles"][cell[0]][cell[1]]
		while int(t["rot"]) != int(t["solved"]):
			t["rot"] = (int(t["rot"]) + 1) % (L.OPEN[t["type"]] as Array).size()


func _clicks_for(t: Dictionary) -> int:
	var z := {"n": 1, "tiles": [[t.duplicate()]]}
	var k := 0
	while int(z["tiles"][0][0]["rot"]) != int(t["solved"]) and k < 8:
		L.turn_pipe(z, 0, 0)
		k += 1
	return k


func _min_clicks(z: Dictionary) -> int:
	var n := int(z["n"])
	var best := [1000000]
	var used := {0: true}
	_min_go(z, n, 0, 0, 3, 0, best, used)
	return best[0]


func _min_go(z: Dictionary, n: int, r: int, c: int, enter: int, cost: int, best: Array, used: Dictionary) -> void:
	if cost >= best[0]:
		return
	var t: Dictionary = z["tiles"][r][c]
	var m: int = (L.OPEN[t["type"]] as Array).size()
	for k in m:
		var ends: Array = (L.OPEN[t["type"]] as Array)[(int(t["rot"]) + k) % m]
		if not ends.has(enter):
			continue
		var out: int = int(ends[1]) if int(ends[0]) == enter else int(ends[0])
		if r == n - 1 and c == n - 1 and out == 1:
			best[0] = mini(best[0], cost + k)
			continue
		var nr: int = r + int(L.STEP[out][0])
		var nc: int = c + int(L.STEP[out][1])
		if nr < 0 or nc < 0 or nr >= n or nc >= n or used.has(nr * n + nc):
			continue
		used[nr * n + nc] = true
		_min_go(z, n, nr, nc, (out + 2) % 4, cost + k, best, used)
		used.erase(nr * n + nc)


func _trace(descent: int, seed_number: int, steps: int) -> String:
	var g := L.new(descent, seed_number)
	var out := []
	for i in steps:
		if g.over != "":
			break
		if i % 17 == 0:
			_solve(g)
		for e in g.step(100.0, {"hold": i % 3 == 0}):
			out.append("%d:%s" % [i, e["type"]])
	return ",".join(out) + "|%.4f" % g.threat


func run(host: Node) -> int:
	NwLeakProbe.report(host, "descent")
	_numbers()
	_wires_memory()
	_pipes()
	_dynamics()
	_variety()
	_calls()
	_map()
	await _admin(host)
	await _office(host)
	await _scene(host)
	if _failures == 0:
		print("  night_watch_descent  the 2D numbers, puzzles, variety levers, seeded replay, the shift scene (win, loss, saves, Custom Night)")
	return _failures


# --- the numbers, pinned (descent-data.js / descent-logic.js) ---------------------------------------------------------------

func _numbers() -> void:
	_expect(D.LEVELS["elise"] == [0, 5, 8, 11, 14], "Elise's levels differ from the 2D game's")
	_expect(D.RUNS[1] == ["wires"] and D.RUNS[4] == ["wires", "memory", "pipes", "hold"] and D.RUNS[5] == ["wires", "memory", "pipes", "wires", "hold"], "the descents' stages differ")
	_expect(D.WIRES_LIT == [3, 3, 4, 4, 5] and D.WIRES_BUTTONS == [4, 4, 5, 6, 6] and D.MEMORY_LENGTH == [3, 3, 4, 4, 5], "the puzzle sizes differ")
	_expect(D.PIPES_GRID == [4, 4, 4, 5, 5] and D.PIPES_DETOURS == [0, 0, 0, 1, 1] and D.PIPES_TURNS == [2, 2, 2, 2, 2], "the pipe sizes differ")
	_expect(L.RATE_PER_LEVEL == 0.22 and L.WRONG_BUMP == 13.0 and L.STAGE_RELIEF == 34.0 and L.PIPE_RATE == 0.5 and L.HOLD_RATE == 2.6, "the closeness rates differ")
	_expect(L.HOLD_MS == 3200.0 and L.HOLD_SLIP == 22.0 and L.RIDE_MS == 1800.0, "the door hold or the ride differ")
	_expect(L.SHOW_ON_MS == 520.0 and L.SHOW_OFF_MS == 260.0 and L.SHOW_LEAD_MS == 700.0, "the signal show's timing differs")
	_expect(L.SURGE_SPREAD == 0.2 and L.SURGE_EVERY_MS == 9000.0 and L.SURGE_EVERY_SPREAD == 0.33 and L.SHOW_PACE_SPREAD == 0.15 and L.LIT_SPREAD == 1 and L.LENGTH_SPREAD == 1, "the variety numbers differ")
	_expect(D.NAMES["elise"] == "Elise" and D.CAST == ["elise"], "the cast differs")
	_expect(L.stage_title("pipes") == "PIPEWORK · SHE SLOWS HERE" and L.stage_title("wires") == "FUSE BOXES" and L.stage_title("memory") == "SIGNAL PANEL" and L.stage_title("hold") == "DOOR", "the panel titles differ")
	var modes := NightWatchModesData.mode("descent")
	_expect((modes["levels"] as Array).size() == 5 and (modes["levels"] as Array)[0] == "DESCENT 1" and int(modes["scored"]) == 5, "the board's shifts are not DESCENT 1-5")


func _wires_memory() -> void:
	# wires: press each lit box's button in turn; a wrong one starts over and re-deals
	var rng := _rng(5)
	var z := L.make_wires(4, 4, 3, rng)
	var seen := {}
	for b in z["wire"]:
		seen[b] = true
	_expect(seen.size() == 4 and (z["lit"] as Array).size() == 3, "wires: each box needs its own button and 3 light")
	_expect(L.press_wire(z, int((z["wire"] as Array)[int((z["lit"] as Array)[0])]), rng) == "ok", "wires: the first right press is not ok")
	var bad := 0
	for b in 4:
		if b != int((z["wire"] as Array)[int((z["lit"] as Array)[1])]):
			bad = b
			break
	_expect(L.press_wire(z, bad, rng) == "wrong" and int(z["step"]) == 0, "wires: a wrong press does not start over")
	var r := ""
	for b in z["lit"]:
		r = L.press_wire(z, int((z["wire"] as Array)[b]), rng)
	_expect(r == "done", "wires: the run does not finish")
	# the signal panel
	rng = _rng(4)
	var m := L.make_memory(4, rng)
	_expect((m["seq"] as Array).size() == 4, "memory: the sequence is not 4 long")
	_expect(L.press_pad(m, int((m["seq"] as Array)[0])) == "none", "memory: a press during the show counts")
	var lit_seen := []
	var t := 0
	while t < 8000 and String(m["phase"]) == "show":
		L.advance_show(m, 20.0)
		if int(m["lit"]) >= 0 and (lit_seen.is_empty() or lit_seen.back() != int(m["lit"])):
			lit_seen.append(int(m["lit"]))
		t += 20
	_expect(m["phase"] == "input" and lit_seen.size() >= 1 and lit_seen[0] == (m["seq"] as Array)[0], "memory: the show does not begin with the first pad")
	_expect(L.press_pad(m, int((m["seq"] as Array)[0])) == "ok", "memory: the first pad is not ok")
	var wrong_pad := 0
	for p in 4:
		if p != int((m["seq"] as Array)[1]):
			wrong_pad = p
			break
	_expect(L.press_pad(m, wrong_pad) == "wrong" and m["phase"] == "show" and int(m["step"]) == 0, "memory: a wrong pad does not restart the show")
	t = 0
	while t < 12000 and String(m["phase"]) == "show":
		L.advance_show(m, 20.0)
		t += 20
	for p in m["seq"]:
		r = L.press_pad(m, int(p))
	_expect(r == "done", "memory: the right order does not finish")


func _pipes() -> void:
	for seed_number in range(1, 61):
		var n := 4 + (seed_number % 2)
		var z := L.make_pipes(n, _rng(seed_number))
		_expect(not L.pipes_connected(z), "pipes seed %d starts solved" % seed_number)
		var before := L.pipes_flow(z)
		_expect(not bool(before["done"]) and (before["cells"] as Array).size() <= n * n, "pipes seed %d: the flow is wrong at the start" % seed_number)
		_solve_pipes_in_place(z)
		_expect(L.pipes_connected(z), "pipes seed %d cannot be solved" % seed_number)
		var after := L.pipes_flow(z)
		var path_keys := []
		for cell in z["path"]:
			path_keys.append("%d,%d" % [cell[0], cell[1]])
		var flow_keys := []
		for cell in after["cells"]:
			flow_keys.append("%d,%d" % [cell[0], cell[1]])
		_expect(bool(after["done"]) and flow_keys == path_keys, "pipes seed %d: the water does not follow the path" % seed_number)
		for cell in z["path"]:
			_expect(L.pipe_openings(z["tiles"][cell[0]][cell[1]]).size() == 2, "a pipe piece has not two ends")
	# the pipes' clock is fair: the path only goes right and down on descents 1-3, one step up or left on 4-5, no piece needs more than 2 clicks
	for seed_number in range(1, 301):
		for i in 5:
			var z := L.make_pipes(int(D.PIPES_GRID[i]), _rng(seed_number * 5 + i), int(D.PIPES_DETOURS[i]), int(D.PIPES_TURNS[i]))
			var back := 0
			var path: Array = z["path"]
			for k in range(1, path.size()):
				var d := L._step_index(int(path[k - 1][0]), int(path[k - 1][1]), int(path[k][0]), int(path[k][1]))
				if d == 0 or d == 3:
					back += 1
			_expect(back <= int(D.PIPES_DETOURS[i]), "descent %d seed %d: %d steps up or left" % [i + 1, seed_number, back])
			for cell in path:
				var k2 := _clicks_for(z["tiles"][cell[0]][cell[1]])
				_expect(k2 >= 1 and k2 <= int(D.PIPES_TURNS[i]), "descent %d seed %d: a path piece needs %d clicks" % [i + 1, seed_number, k2])
			_expect(not L.pipes_connected(z), "descent %d seed %d: pipes start solved" % [i + 1, seed_number])
	# every dealt pipe puzzle is solved by clicking its path in through the game's own act() (descents 3-5, Custom Night levels)
	var puzzles := 0
	for d in [3, 4, 5]:
		for seed_number in range(1, 201):
			var g := L.new(d, seed_number)
			var guard := 0
			while guard < 6 and g.kind() != "pipes":
				guard += 1
				g.threat = 0.0
				_solve(g)
			if g.ride > 0.0:
				_run(g, g.ride)
			_expect(g.kind() == "pipes", "descent %d seed %d never reaches the pipes" % [d, seed_number])
			var stage := g.stage_idx
			_solve(g)
			_expect(g.stage_idx == stage + 1, "descent %d seed %d: clicking the line in does not finish the stage" % [d, seed_number])
			puzzles += 1
	_expect(puzzles == 600, "pipe puzzles checked: %d" % puzzles)


func _dynamics() -> void:
	# Descent 1 is a walk-through
	var g := L.new(1, 1)
	_expect(g.level == 0, "descent 1: Elise is not at level 0")
	_run(g, L.RIDE_MS + 20000.0)
	_expect(g.threat == 0.0, "descent 1: she got closer")
	var ev := _solve(g)
	var ty := _types(ev)
	_expect(ty.slice(ty.size() - 2) == ["stage", "win"] and g.over == "win", "descent 1: the one stage does not end it")
	# time and wrong attempts bring her closer, a finished stage pushes her back, the ride is a breather
	g = L.new(2, 2, -1, D.RUNS[2])
	_run(g, L.RIDE_MS)
	_expect(g.threat == 0.0, "something moved while the car dropped")
	_run(g, 10000.0)
	var idle := g.threat
	_expect(idle > 5.0, "time does not bring her closer")
	var z := g.puzzle
	var wrong_btn := 0
	for b in 4:
		if b != int((z["wire"] as Array)[int((z["lit"] as Array)[0])]):
			wrong_btn = b
			break
	g.act("wires", {"button": wrong_btn})
	_expect(g.threat >= idle + L.WRONG_BUMP - 0.01, "a wrong attempt does not cost")
	_solve(g)
	_expect(g.threat < idle, "a finished stage does not push her back")
	_expect(g.kind() == "memory" and g.act("wires", {"button": 0}).is_empty(), "the wrong panel does something")
	var lazy := L.new(2, 3)
	var lev := _run(lazy, 200000.0)
	_expect(_types(lev).back() == "caught" and lazy.by == "elise", "a lazy player is not caught")
	# the door hold: hold while she pushes, letting go brings her in
	g = L.new(4, 4)
	_run(g, L.RIDE_MS + 50.0)
	for k in 3:
		_solve(g)
		_run(g, L.RIDE_MS + 50.0)
	_expect(g.kind() == "hold", "descent 4 does not end on the door")
	ev = _run(g, L.HOLD_MS + 300.0, {"hold": true})
	ty = _types(ev)
	_expect(ty.slice(ty.size() - 2) == ["stage", "win"], "holding the door does not win")
	var slip := L.new(4, 4)
	_run(slip, L.RIDE_MS + 50.0)
	for k in 3:
		_solve(slip)
		_run(slip, L.RIDE_MS + 50.0)
	_run(slip, 60000.0, {})
	_expect(slip.by == "elise", "letting go of the door does not let her in")
	# she is slower on the pipes and the slowdown belongs to the pipes alone
	for d in [4, 5]:
		var h := L.new(d, 40 + d, -1, D.RUNS[d])
		var per_sec := h.level * L.RATE_PER_LEVEL
		var pi := h.stages.find("pipes")
		h.surge_mult = 1.0
		h.surge_left = 1e12
		while h.stage_idx < pi and h.over == "":
			_solve(h)
		_expect(h.kind() == "pipes" and h.ride == L.RIDE_MS, "descent %d: not riding down to the pipes" % d)
		h.threat = 20.0
		_run(h, L.RIDE_MS - 100.0)
		_expect(h.ride > 0.0 and h.threat == 20.0, "descent %d: she moves while the car rides to the pipes" % d)
		_run(h, h.ride)
		h.threat = 20.0
		_run(h, 4000.0)
		_expect(absf(h.threat - (20.0 + per_sec * L.PIPE_RATE * 4.0)) < 1e-6, "descent %d: half speed on the pipes" % d)
		_solve(h)
		_expect(h.stage_idx == pi + 1 and h.ride > 0.0, "descent %d: the pipes do not hand over to a ride" % d)
		h.threat = 20.0
		_run(h, L.RIDE_MS - 100.0)
		_expect(h.threat == 20.0, "descent %d: she moves during the ride away from the pipes" % d)
		_run(h, h.ride)
		if d == 5:
			_expect(h.kind() == "wires", "descent 5: no wires after the pipes")
			h.threat = 20.0
			_run(h, 10000.0)
			_expect(absf(h.threat - (20.0 + per_sec * 10.0)) < 1e-6, "descent 5: the wires after the pipes are not at the full rate")
			_solve(h)
			_run(h, h.ride)
		_expect(h.kind() == "hold", "descent %d: no door at the end" % d)
		h.threat = 10.0
		_run(h, 2000.0, {"hold": true})
		_expect(absf(h.threat - (10.0 + per_sec * L.HOLD_RATE * 2.0)) < 1e-6, "descent %d: the door does not run at holdRate" % d)
	# what the Outside meter says
	for d in [3, 4, 5]:
		var m := L.new(d, 50 + d)
		var pipes := 0
		while m.over == "":
			_expect(m.ride > 0.0 and not bool(m.meter_cue()["slow"]) and m.meter_cue()["label"] == "Outside", "descent %d: the ride says something about her pace" % d)
			_run(m, m.ride)
			var kind := m.kind()
			var want_slow := kind == "pipes"
			_expect(bool(m.meter_cue()["slow"]) == want_slow, "descent %d %s: the slowed cue is wrong" % [d, kind])
			if want_slow:
				pipes += 1
				_expect(m.meter_cue()["label"] == "Outside · slowed", "the slowed label differs")
			m.threat = 0.0
			if kind == "hold":
				_run(m, L.HOLD_MS + 100.0, {"hold": true})
			else:
				_solve(m)
		_expect(m.over == "win" and pipes == 1, "descent %d: not won with exactly one pipes stage" % d)
	var off := L.new(3, 7, 0)
	while off.kind() != "pipes":
		_solve(off)
	_run(off, off.ride)
	_expect(not bool(off.meter_cue()["slow"]), "with Elise at level 0 the pipes say she is slowed")
	var at := L.new(3, 1)
	at.ride = 0.0
	at.puzzle = {"kind": "pipes"}
	at.threat = 60.0
	_expect(not bool(at.meter_cue()["warn"]), "60% is already past the warning")
	at.threat = 60.01
	_expect(bool(at.meter_cue()["warn"]) and bool(at.meter_cue()["slow"]), "past 60% the meter does not warn, slowed or not")
	# a steady player clears every descent, and the same seed plays the same
	for d in range(1, 6):
		var s := L.new(d, d * 11)
		var guard := 0
		while s.over == "" and guard < 20:
			guard += 1
			_run(s, L.RIDE_MS + 50.0)
			_run(s, 9000.0, {"hold": true})
			_solve(s)
		_expect(s.over == "win", "a steady player did not clear descent %d" % d)
	_expect(_trace(5, 8, 400) == _trace(5, 8, 400), "the same seed does not replay the same descent")
	var deal8 := L.new(5, 8)
	var deal9 := L.new(5, 9)
	_expect(JSON.stringify([deal8.stages, deal8.puzzle, deal8.surge_mult]) != JSON.stringify([deal9.stages, deal9.puzzle, deal9.surge_mult]), "different seeds deal the same descent")
	# the clock is fair: a steady player's clicks fit in the time she leaves on the pipes
	for d in [3, 4, 5]:
		var need := []
		var room := []
		for seed_number in range(1, 151):
			var p := L.new(d, seed_number)
			var guard2 := 0
			while guard2 < 6 and p.over == "" and p.kind() != "pipes":
				guard2 += 1
				if p.ride > 0.0:
					_run(p, p.ride, {}, 50.0)
				match p.kind():
					"wires":
						_run(p, 1000.0 * (p.puzzle["lit"] as Array).size(), {}, 50.0)
						_solve(p)
					"memory":
						while String(p.puzzle["phase"]) == "show" and p.over == "":
							_run(p, 50.0, {}, 50.0)
						_run(p, 600.0 * (p.puzzle["seq"] as Array).size(), {}, 50.0)
						_solve(p)
			if p.ride > 0.0:
				_run(p, p.ride, {}, 50.0)
			_expect(p.kind() == "pipes", "descent %d seed %d: a steady player does not reach the pipes" % [d, seed_number])
			var avail := (100.0 - p.threat) / (p.level * L.RATE_PER_LEVEL * L.PIPE_RATE)
			var sec := 3.0 + 0.9 * _min_clicks(p.puzzle)
			need.append(sec)
			room.append(avail)
			_expect(sec <= avail, "descent %d seed %d: %.1f s of clicks do not fit in the %.1f s she leaves" % [d, seed_number, sec, avail])
		need.sort()
		room.sort()
		_expect(float(need[int(0.9 * (need.size() - 1))]) * 2.0 <= float(room[int(0.1 * (room.size() - 1))]), "descent %d: the 90th-percentile puzzle does not fit twice into the tightest tenth of clocks" % d)


func _variety() -> void:
	# her pace drifts inside its band, on average not at all
	var lo := L.jitter(1.0, L.SURGE_SPREAD, _rng(1))
	_expect(lo >= 0.8 - 1e-9 and lo <= 1.2 + 1e-9, "jitter left its band")
	var sum := 0.0
	var lmin := 1e12
	var lmax := -1e12
	for seed_number in range(1, 1001):
		var g := L.new(3, seed_number)
		_expect(g.surge_mult >= 0.8 - 1e-9 and g.surge_mult <= 1.2 + 1e-9 and g.surge_left >= 9000.0 * 0.67 - 1e-6 and g.surge_left <= 9000.0 * 1.33 + 1e-6, "seed %d: the first pace is outside its band" % seed_number)
		sum += g.surge_mult
		lmin = minf(lmin, g.surge_left)
		lmax = maxf(lmax, g.surge_left)
	_expect(absf(sum / 1000.0 - 1.0) < 0.02, "the drawn pace does not average the listed rate (%.4f)" % (sum / 1000.0))
	_expect(lmin < 9000.0 * 0.67 + 300.0 and lmax > 9000.0 * 1.33 - 300.0, "the whole redraw band is not used")
	# redraws land in the band, 6 to 12 s apart, and the door hold never redraws
	var g2 := L.new(4, 12)
	var last := g2.surge_mult
	var last_at := 0.0
	var gaps := []
	var t := 0
	while t < 600000 and g2.over == "":
		t += 50
		g2.threat = 0.0
		g2.step(50.0, {})
		if g2.ride > 0.0:
			last_at = g2.elapsed
			continue
		if g2.surge_mult != last:
			gaps.append(g2.elapsed - last_at)
			last_at = g2.elapsed
			last = g2.surge_mult
			_expect(last >= 0.8 - 1e-9 and last <= 1.2 + 1e-9, "a redrawn pace left the band")
	_expect(gaps.size() > 20, "the pace stops changing")
	var gmin := 1e12
	var gmax := 0.0
	for gap in gaps:
		gmin = minf(gmin, gap)
		gmax = maxf(gmax, gap)
	_expect(gmin >= 9000.0 * 0.67 - 60.0 and gmax <= 9000.0 * 1.33 + 60.0, "redraws are not 6 to 12 s apart (%d to %d)" % [gmin, gmax])
	var h := L.new(4, 5, -1, ["wires", "memory", "pipes", "hold"])
	h.stage_idx = 3
	h.puzzle = {"kind": "hold"}
	h.ride = 0.0
	h.threat = 0.0
	var before := h.surge_mult
	var left_before := h.surge_left
	_run(h, 2000.0, {"hold": true})
	_expect(h.surge_mult == before and h.surge_left == left_before, "the door hold redrew her pace")
	_expect(absf(h.threat - h.level * L.RATE_PER_LEVEL * L.HOLD_RATE * 2.0) < 1e-6, "the door hold is not exactly holdRate")
	# on average her closeness climbs at the listed rate
	var tot := 0.0
	var base := 0.0
	for seed_number in range(1, 201):
		var k := L.new(2, seed_number + 5000, -1, ["wires", "memory"])
		_run(k, L.RIDE_MS)
		_run(k, 20000.0)
		tot += k.threat
		base += k.level * L.RATE_PER_LEVEL * 20.0
	_expect(absf(tot / base - 1.0) < 0.04, "20 s idle: closeness averages %.3f of the listed rate" % (tot / base))
	# stage orders: every valid order turns up, the door is last
	var expected := {1: 1, 2: 2, 3: 6, 4: 6, 5: 12}
	for d in range(1, 6):
		var counts := {}
		for seed_number in range(1, 1201):
			var order := L.draw_stages(d, _rng(seed_number))
			_expect(L.valid_order(d, order), "descent %d seed %d: invalid order" % [d, seed_number])
			if (D.RUNS[d] as Array).has("hold"):
				_expect(order.back() == "hold", "the door is not last")
			counts[",".join(order)] = int(counts.get(",".join(order), 0)) + 1
		_expect(counts.size() == int(expected[d]), "descent %d: %d different orders, not %d" % [d, counts.size(), int(expected[d])])
		var want := 1200.0 / float(expected[d])
		for o in counts:
			_expect(float(counts[o]) > want * 0.7 and float(counts[o]) < want * 1.3, "descent %d order %s does not turn up about equally (%d)" % [d, o, counts[o]])
	_expect(not L.valid_order(4, ["hold", "wires", "memory", "pipes"]) and not L.valid_order(4, ["wires", "memory", "hold", "pipes"]), "the door can move")
	_expect(not L.valid_order(5, ["wires", "memory", "pipes", "memory", "hold"]) and not L.valid_order(3, ["wires", "wires", "pipes"]) and not L.valid_order(3, ["wires", "memory"]), "wrong stages are accepted")
	_expect(L.new(3, 1, -1, ["pipes", "memory", "wires"]).kind() == "pipes", "a forced order is ignored")
	_expect(L.valid_order(3, L.new(3, 1, -1, ["pipes", "pipes", "pipes"]).stages), "an invalid forced order is not ignored")
	# lit boxes and signal length: the listed number or one either side, never below the floor
	for i in 5:
		var lits := {}
		var lens := {}
		for seed_number in range(1, 401):
			var r := _rng(seed_number)
			lits[L.draw_lit(int(D.WIRES_LIT[i]), r)] = true
			lens[L.draw_length(int(D.MEMORY_LENGTH[i]), r)] = true
		for v in lits:
			_expect(int(v) >= maxi(2, int(D.WIRES_LIT[i]) - 1) and int(v) <= int(D.WIRES_LIT[i]) + 1, "descent %d: %d boxes light" % [i + 1, v])
		for v in lens:
			_expect(int(v) >= maxi(3, int(D.MEMORY_LENGTH[i]) - 1) and int(v) <= int(D.MEMORY_LENGTH[i]) + 1, "descent %d: a signal of %d" % [i + 1, v])
		_expect(lits.size() >= 2 and lens.size() >= 2, "descent %d: the lit count or signal length never varies" % [i + 1])
	# a perfect player wins every seed in every order; the modest bot's win rate is in the 2D game's band
	for d in range(1, 6):
		for seed_number in range(1, 41):
			var p := L.new(d, seed_number)
			var guard := 0
			while p.over == "" and guard < 30:
				guard += 1
				if p.kind() == "hold":
					_run(p, L.HOLD_MS + 100.0, {"hold": true}, 50.0)
				else:
					_solve(p)
			_expect(p.over == "win", "a perfect player lost descent %d seed %d (stages %s)" % [d, seed_number, str(p.stages)])


func _calls() -> void:
	# Zellia's calls never contradict the drawn order: a line may only name a stage on that descent's run, and may not rank it unless that
	# is true in every order (the door is always last).
	var terms := {"wires": "fuse box|wire", "memory": "signal", "pipes": "pipe", "hold": "door|get on"}
	var ordinal := RegEx.new()
	ordinal.compile("(?i)\\b(next|first|then|afterwards?|after that|before|second|third|fourth|last|finally)\\b")
	for d in range(1, 6):
		var lines: Array = NightWatchCallsData.for_level("descent", d).get("lines", [])
		_expect(not lines.is_empty(), "descent %d has no call" % d)
		for line in lines:
			var text := String(line)
			for kind in terms:
				var re := RegEx.new()
				re.compile("(?i)(" + String(terms[kind]) + ")")
				if re.search(text) == null:
					continue
				_expect((D.RUNS[d] as Array).has(kind), "descent %d's call names the %s stage it does not have: %s" % [d, kind, text])
				_expect(ordinal.search(text) == null or kind == "hold" or d == 1, "descent %d: '%s' ranks the %s stage" % [d, text, kind])

	_expect((NightWatchCallsData.for_level("descent", 3).get("lines", []) as Array).any(func(l): return String(l).contains("She slows down while you work the pipes, but she doesn't stop.")), "descent 3's call does not say she slows on the pipes")


# --- the admin menu (docs/NIGHT_WATCH_ADMIN.md) -----------------------------------------------------------------------------------

func _admin_game(host: Node) -> NightWatchDescentGame:
	var game := await _make(host, 4, 9)
	game.advance_ms(12000.0)   # past the ride and into Zellia's call
	return game


func _fingerprint(game: NightWatchDescentGame) -> String:
	var s := game.sim
	return "%s|%s|%d|%d|%d|%s|%s|%s|%d|%s|%s|%s|%s|%s|%s|%s|%s" % [game.admin_status(), str(s.puzzle), s.stage_idx, s.wrong, s.level, str(s.threat), str(s.over), str(game.hold_down), game.state,
		str(game.elise.visible), str(game.hud.end_root.visible), str(NightWatchSession.night), str(s.speed_mult), str(game.admin_is_reveal()), game.hud.shown_call, str(game.hud.muted), str(game.hud.call_script.get_instance_id() if game.hud.call_script != null else 0)]


func _admin(host: Node) -> void:
	var game := await _admin_game(host)
	_expect(NightWatchAdmin.attach(game, false) == null, "a non-admin got the admin menu")
	_expect(game.admin_menu != null and game.admin_menu is AdminMenu, "an admin did not get the menu")
	_expect(game.hud.hint_label.text.contains("0 admin"), "the hint line does not list the admin key for an admin")
	_expect(NightWatchAdmin.PROVIDERS.get("descent", "") == "res://src/night_watch/descent/descent_admin.gd", "The Descent has no admin provider")
	var sections := NwAdminCheck.sections(game)
	for want in ["SHIFT // THE DESCENT", "ZELLIA AND THE NIGHT", "THE DESCENT SPECIFIC"]:
		_expect(sections.has(want), "the admin menu has no %s section: %s" % [want, str(sections)])
	for p in NwAdminCheck.entry_problems(game):
		_expect(false, p)
	for p in await NwAdminCheck.layout_problems(host, game, ["SHIFT", "THE DESCENT SPECIFIC"]):
		_expect(false, p)
	game.admin_menu.call("_set_open", true)
	_expect(game.admin_menu.is_open(), "the admin menu did not open")
	game.admin_menu.close()
	# the hooks do what they say
	game.admin_set_hunter_level("elise", 17)
	_expect(game.sim.level == 17, "AI level did not change Elise")
	game.admin_place_hunter("elise", "at the edge")
	_expect(game.sim.threat > 90.0 and game.elise.visible, "SEND TO at the edge did not bring her to the glass")
	game.admin_set_god(true)
	game.advance_ms(60000.0)
	_expect(game.state == NightWatchDescentGame.State.PLAYING and game.sim.threat <= 99.0 and game.sim.over == "", "god mode let her in")
	game.admin_set_god(false)
	game.admin_set_frozen(true)
	var el := game.sim.elapsed
	game.advance_ms(5000.0)
	_expect(game.sim.elapsed == el, "the frozen clock still ran")
	game.admin_set_frozen(false)
	game.admin_set_hunter_speed(4.0)
	game.admin_set_closeness(0.0)
	game.sim.surge_mult = 1.0
	game.sim.surge_left = 1e12
	game.advance_ms(5000.0)
	var fast := game.sim.threat
	game.admin_set_hunter_speed(1.0)
	game.admin_set_closeness(0.0)
	game.advance_ms(5000.0)
	_expect(fast > game.sim.threat * 3.0, "4X speed did not close in about four times as fast (%.1f vs %.1f)" % [fast, game.sim.threat])
	game.admin_goto_stage(game.sim.stages.size())
	_expect(game.sim.stage_idx == game.sim.stages.size() - 1 and game.sim.kind() == "hold", "the elevator depth did not jump to the last floor")
	game.admin_solve_stage()
	_expect(game.state == NightWatchDescentGame.State.WON, "solving the last stage did not win")
	await _finish_admin(host, game)
	var jump := await _admin_game(host)
	jump.admin_jump_to(2)
	_expect(NightWatchSession.mode_id == "descent" and NightWatchSession.night == 2, "JUMP TO SHIFT did not set the session to descent 2")
	await _finish_admin(host, jump)
	var lose := await _admin_game(host)
	lose.admin_set_no_scare(true)
	lose.admin_lose()
	_expect(lose.state == NightWatchDescentGame.State.LOST and lose.hud.end_root.visible and lose.hud.end_title.text == "CAUGHT", "LOSE THE SHIFT did not lose it with no jumpscare")
	await _finish_admin(host, lose)
	# every entry of the menu, every item, changes state
	var make := func() -> NightWatchDescentGame:
		return await _admin_game(host)
	var fp := func(g) -> String: return _fingerprint(g)
	for p in await NwAdminCheck.exercise(make, fp, ["JUMP TO SHIFT"]):
		_expect(false, p)
	await _finish_admin(host, game)


func _finish_admin(host: Node, game) -> void:
	if is_instance_valid(game):
		game.queue_free()
	await host.get_tree().process_frame


# --- the map (docs/NIGHT_WATCH_OFFICES.md, "Maps") --------------------------------------------------------------------------

func _map() -> void:
	_expect(NightWatchMapRegistry.MAPS["descent"]["script"] == "res://src/night_watch/descent/descent_map.gd", "the registry has no map for The Descent")
	var layout := NightWatchMapRegistry.layout_for("descent")
	var rooms: Dictionary = layout["rooms"]
	for e in layout["edges"]:
		_expect(rooms.has(e[0]) and rooms.has(e[1]), "map edge %s has an unknown room" % str(e))
	for r in layout["entrances"]:
		_expect(rooms.has(r), "map entrance %s is not a room" % r)
	_expect(rooms.size() >= 8 and layout["entrances"] == ["sill_l", "sill_r"], "the stairwell map is thin or its entrances are not the two sills")
	# in step with the office: the two window entrances are the two sills, Elise's ends
	var spec := NightWatchDescentOffice.make_spec()
	_expect(spec.entrances.size() == (layout["entrances"] as Array).size(), "the office's entrances and the map's differ in number")
	for e in spec.entrances:
		_expect(layout["entrances"].has("sill_" + String(e["sim_room"]).to_lower()), "office entrance %s has no sill room on the map" % e["id"])
	# the 3D set has the stairwell levels, the pipe runs and the fuse cabinets (not just a bare car)
	var world := NightWatchDescentWorld.new()
	world.build()
	var names := {}
	for n in world.dress.get_children():
		names[String(n.get_meta("nw_name", n.name))] = true
	for want in ["StairLanding", "StairStep", "PipeRun", "PipeValve", "FuseCabinet", "BeamCross"]:
		_expect(names.has(want), "the shaft has no %s" % want)
	world.free()


# --- the office (docs/NIGHT_WATCH_OFFICES.md): lift_landing --------------------------------------------------------------------

func _office(host: Node) -> void:
	_expect(NightWatchOfficeRegistry.built("descent") and NightWatchOfficeRegistry.office_id("descent") == "lift_landing", "The Descent's office is not registered as lift_landing")
	var office := NightWatchOfficeRegistry.make("descent") as NightWatchDescentOffice
	host.add_child(office)
	await host.get_tree().process_frame
	await host.get_tree().physics_frame
	for p in office.spec.problems():
		_expect(false, "lift_landing: %s" % p)
	_expect(not office.spec.has_monitor and office.stations.has("panel") and office.stations.has("door"), "lift_landing: a monitor, or the panel / door station missing")
	_expect(office.light_count() <= NightWatchOfficeSpec.MAX_REAL_LIGHTS, "lift_landing: %d real lights" % office.light_count())
	_expect(office.world.camera != null and office.world.get_child_count() > 0 and office.find_children("*", "Camera3D", true, false).size() == 1, "lift_landing is built twice (more than one camera)")
	for e in office.spec.entrances:
		var at := Vector3((-1.0 if e["sim_room"] == "L" else 1.0) * NightWatchDescentWorld.WINDOW_X, 0.0, NightWatchDescentWorld.SILL_NEAR)
		_expect((e["position"] as Vector3).distance_to(at) < 0.05, "lift_landing: entrance %s is not where Elise stands at the glass" % e["id"])
	for problem in NwOfficeWalk.problems(office):
		_expect(false, "lift_landing: %s" % problem)
	office.queue_free()
	await host.get_tree().process_frame


# --- the shift scene ----------------------------------------------------------------------------------------------------------

func _make(host: Node, level: int, seed_number: int, custom := {}) -> NightWatchDescentGame:
	NightWatchSession.start_mode("descent", level, custom, seed_number)
	var shift := (load("res://scenes/night_watch_descent.tscn") as PackedScene).instantiate() as NightWatchDescentGame
	shift.manual_clock = true
	host.add_child(shift)
	await host.get_tree().process_frame
	return shift


func _scene_solve(shift: NightWatchDescentGame) -> void:
	var g := shift.sim
	if g.ride > 0.0:
		shift.advance_ms(g.ride + 1.0)
	var z := g.puzzle
	if z.is_empty():
		return
	var stage := g.stage_idx
	match String(z["kind"]):
		"wires":
			var lit: Array = z["lit"]
			for i in range(int(z["step"]), lit.size()):
				shift.press("wires", {"button": (z["wire"] as Array)[lit[i]]})
		"memory":
			while String(z["phase"]) == "show":
				shift.advance_ms(100.0)
			for pad in z["seq"]:
				shift.press("memory", {"pad": pad})
		"pipes":
			for cell in z["path"]:
				var t: Dictionary = z["tiles"][cell[0]][cell[1]]
				while g.stage_idx == stage and int(t["rot"]) != int(t["solved"]):
					shift.press("pipes", {"r": cell[0], "c": cell[1]})
		"hold":
			shift.set_hold(true)
			for i in 40:
				shift.advance_ms(100.0)
			shift.set_hold(false)


func _scene(host: Node) -> void:
	NightWatchSave.path = "user://night_watch_descent_test.cfg"
	NightWatchSave.reset()
	_expect(NightWatchModeRegistry.playable("descent") and NightWatchModeRegistry.SCENES.has("descent"), "the registry does not list the descent")
	_expect(NightWatchModeRegistry.prepare("descent", 3) == "res://scenes/night_watch_descent.tscn" and NightWatchSession.mode_id == "descent" and NightWatchSession.night == 3, "the board cannot start descent 3")
	# every descent starts from the board: only the first is open, a clear opens the next
	_expect(NightWatchSave.level_open("descent", 1) and not NightWatchSave.level_open("descent", 2), "descent 2 is open before descent 1 is cleared")
	# --- descent 1: win (saves the clear, opens descent 2, offers the next)
	var shift := await _make(host, 1, 777)
	_expect(shift.mode_id == "descent" and shift.level == 1 and shift.seed_value == 777 and not shift.is_custom, "the scene did not read the session")
	_expect(shift.world != null and shift.world.camera != null and shift.world.props.has("Car") and shift.world.props.has("Windows") and shift.world.props.has("Shaft"), "the car, windows and shaft are not built")
	_expect(shift.hud.clock_label.text == "FLOOR 1 / 1" and shift.hud.night_label.text.contains("DESCENT 1"), "the HUD does not say descent 1, floor 1")
	_expect(not shift.elise.visible, "Elise is out on the walk-through descent")
	var first_panel_kind: String = shift.sim.kind()
	_expect(first_panel_kind == "wires", "descent 1 does not start with the wires")
	shift.advance_ms(L.RIDE_MS + 10.0)
	shift.panel.refresh(shift.sim)
	var wire_buttons := 0
	for b in shift.panel.buttons:
		if (b as Control).name.begins_with("Wire"):
			wire_buttons += 1
	_expect(wire_buttons == int(shift.sim.puzzle["buttons"]), "the panel does not show every wire button")
	# a real click on the panel's button presses the right wire
	var target: int = int((shift.sim.puzzle["wire"] as Array)[int((shift.sim.puzzle["lit"] as Array)[0])])
	(shift.panel.buttons[target] as Button).pressed.emit()
	_expect(int(shift.sim.puzzle["step"]) == 1, "pressing the panel's button did not press the wire")
	await _scene_solve(shift)
	_expect(shift.state == NightWatchDescentGame.State.WON, "descent 1 was not won")
	_expect(NightWatchSave.cleared_levels("descent") == [1] and NightWatchSave.level_open("descent", 2) and not NightWatchSave.level_open("descent", 3), "the win did not save the clear and open descent 2 only")
	_expect(shift.hud.end_root.visible and shift.hud.end_title.text == "DESCENT 1 COMPLETE" and shift.hud.end_next.visible and shift.hud.end_next.text.begins_with("NEXT DESCENT"), "the win card is not the shared card with a next descent")
	_expect(shift.hud.end_body.text.contains("BOTTOM FLOOR") and shift.hud.end_body.text.contains("wrong attempt"), "the win card does not say the bottom floor and the wrong attempts")
	shift.queue_free()
	await host.get_tree().process_frame
	# --- Retry replays the same seed: two scenes on one session deal the same descent
	var a := await _make(host, 5, 4242)
	var b := await _make(host, 5, 4242)
	_expect(a.sim.stages == b.sim.stages and JSON.stringify(a.sim.puzzle) == JSON.stringify(b.sim.puzzle) and a.sim.side == b.sim.side, "the same seed dealt a different descent")
	_expect(a.sim.stages.size() == 5 and a.sim.stages.back() == "hold", "descent 5 is not five stages ending on the door")
	a.queue_free()
	b.queue_free()
	await host.get_tree().process_frame
	# --- a loss: the lazy player is caught, nothing is saved, the card offers Retry and Menu only
	var lost := await _make(host, 2, 31)
	_expect(not lost.elise.visible, "Elise shows during the first ride")
	lost.advance_ms(L.RIDE_MS + 10.0)
	_expect(lost.elise.visible and lost.elise.position.z < NightWatchDescentWorld.SILL_NEAR - 0.5, "Elise is not far down the sill at the start")
	var far := lost.elise.position
	lost.advance_ms(40000.0)
	_expect(lost.elise.position.z > far.z, "Elise did not come closer along the sill")
	var guard := 0
	while lost.state == NightWatchDescentGame.State.PLAYING and guard < 4000:
		guard += 1
		lost.advance_ms(100.0)
	_expect(lost.state == NightWatchDescentGame.State.LOST and lost.sim.by == "elise", "the lazy player was not caught")
	_expect(lost.elise.position.z > NightWatchDescentWorld.SILL_NEAR - 0.3, "Elise is not at the glass when she reaches the car")
	await host.get_tree().process_frame
	lost._after_death_moment()
	_expect(lost.hud.end_root.visible and lost.hud.end_title.text == "CAUGHT" and lost.hud.end_body.text == "Elise reached the car." and not lost.hud.end_next.visible, "the loss card differs")
	_expect(NightWatchSave.cleared_levels("descent") == [1], "a loss saved a clear")
	lost.queue_free()
	await host.get_tree().process_frame
	# --- a full descent 5 in the scene by a steady player wins; Elise walks (the sill position follows her closeness)
	var full := await _make(host, 5, 9001)
	var steps := 0
	while full.state == NightWatchDescentGame.State.PLAYING and steps < 40:
		steps += 1
		full.sim.threat = 0.0
		await _scene_solve(full)
		full.advance_ms(50.0)
	_expect(full.state == NightWatchDescentGame.State.WON and not full.hud.end_next.visible and full.hud.end_title.text == "DESCENT 5 COMPLETE", "descent 5 was not won, or offered a next descent")
	_expect(NightWatchSave.cleared_levels("descent") == [1, 5], "descent 5's clear was not saved")
	full.queue_free()
	await host.get_tree().process_frame
	# --- Custom Night: the Elise slider feeds the logic, record_win saves score and best (no clear)
	var cust := await _make(host, 1, 55, {"elise": 12})
	_expect(cust.is_custom and cust.sim.level == 12 and cust.sim.descent == 5, "the slider did not set Elise's level on the longest descent")
	_expect(cust.hud.night_label.text.contains("CUSTOM"), "the Custom Night is not labelled")
	steps = 0
	while cust.state == NightWatchDescentGame.State.PLAYING and steps < 40:
		steps += 1
		cust.sim.threat = 0.0
		await _scene_solve(cust)
		cust.advance_ms(50.0)
	_expect(cust.state == NightWatchDescentGame.State.WON and cust.hud.end_title.text == "CUSTOM NIGHT COMPLETE" and not cust.hud.end_next.visible, "the Custom Night was not won with the custom card")
	_expect(NightWatchSave.best_score("descent") == 120 and NightWatchSave.cleared_levels("descent") == [1, 5], "the Custom Night did not save its score only")
	cust.queue_free()
	await host.get_tree().process_frame
	var zero := await _make(host, 1, 56, {"elise": 0})
	_expect(zero.sim.level == 0 and not zero.elise.visible, "a slider at 0 keeps Elise out")
	zero.queue_free()
	await host.get_tree().process_frame
	# --- the shared pause card and the pause key
	var pz := await _make(host, 2, 3)
	pz.set_paused(true)
	_expect(pz.state == NightWatchDescentGame.State.PAUSED and pz.hud.pause_root.visible, "the shared pause card does not show")
	pz.set_paused(false)
	_expect(pz.state == NightWatchDescentGame.State.PLAYING and not pz.hud.pause_root.visible, "RESUME does not resume")
	pz.queue_free()
	await host.get_tree().process_frame
	NightWatchSave.reset()
	NightWatchSave.path = NightWatchSave.DEFAULT_PATH
	NightWatchSession.start(1)
