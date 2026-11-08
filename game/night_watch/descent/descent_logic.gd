class_name NightWatchDescentLogic
extends RefCounted

## The Descent's rules, a port of createDescentGame in the 2D game. No nodes: the shift scene feeds it the door-hold button and
## the panel presses and draws what happens, and tests/validate_night_watch_descent.gd replays whole descents headless.
##
##   wires   boxes light in turn; press the button at the end of each lit box's wire. A wrong button starts the run over and the wires are
##           re-dealt, so memorising them does not help.
##   memory  the signal panel: four pads light in turn, then you press them back in the same order. A wrong pad starts the show again.
##   pipes   turn the pieces until one line runs from the left edge, through the grid, to the right edge. She closes in at half speed here.
##   hold    (the last stage of the late descents) she tries to get on: hold the door shut until the car stops.
## Her closeness rises with time and with every wrong attempt, and falls when a stage is done. At the top of the bar she is in. The stage
## order, how many boxes light, how long the signal runs, the colours and her pace are drawn from the descent's seed.
##
## step(dt_ms, input {hold}) returns events: step, wrong, stage {index}, ride {index}, win, caught {by}. act(kind, args) returns events too.

const RATE_PER_LEVEL := 0.22        # closeness per second = level * this
const WRONG_BUMP := 13.0
const STAGE_RELIEF := 34.0
const RIDE_MS := 1800.0
const SHOW_ON_MS := 520.0
const SHOW_OFF_MS := 260.0
const SHOW_LEAD_MS := 700.0
const HOLD_MS := 3200.0
const HOLD_SLIP := 22.0
const HOLD_RATE := 2.6
const PIPE_RATE := 0.5
const SURGE_SPREAD := 0.2
const SURGE_EVERY_MS := 9000.0
const SURGE_EVERY_SPREAD := 0.33
const SHOW_PACE_SPREAD := 0.15
const LIT_SPREAD := 1
const LENGTH_SPREAD := 1

## Pipes: N, E, S, W as 0 to 3. A straight piece has two ends on opposite sides, a corner two at right angles.
const OPEN := {"I": [[3, 1], [0, 2]], "L": [[0, 1], [1, 2], [2, 3], [3, 0]]}
const STEP := [[-1, 0], [0, 1], [1, 0], [0, -1]]

var descent := 1
var level := 0
var elapsed := 0.0
var over := ""
var by := ""
var stages: Array = []
var stage_idx := 0
var ride := RIDE_MS
var threat := 0.0
var wrong := 0
var puzzle: Dictionary = {}
var held := 0.0
var side := "L"
var surge_mult := 1.0
var surge_left := 0.0
## Admin (NightWatchAdmin): god mode keeps her out of the car, speed scales how fast she closes in.
var god := false
var speed_mult := 1.0

var _rng: RandomNumberGenerator


## `level_override` (>= 0) replaces Elise's level (Custom Night); `forced` forces the stage order (tests).
func _init(descent_number: int = 1, seed_number: int = 0, level_override := -1, forced: Array = []) -> void:
	descent = clampi(descent_number, 1, NightWatchDescentData.DESCENTS)
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_number
	var i := descent - 1
	level = level_override if level_override >= 0 else int(NightWatchDescentData.LEVELS["elise"][i])
	side = "L" if _r() < 0.5 else "R"
	stages = forced.duplicate() if not forced.is_empty() and valid_order(descent, forced) else draw_stages(descent, _rng)
	surge_mult = jitter(1.0, SURGE_SPREAD, _rng)
	surge_left = jitter(SURGE_EVERY_MS, SURGE_EVERY_SPREAD, _rng)
	puzzle = _build(stages[0])


func _r() -> float:
	return minf(_rng.randf(), 0.99999999)


# --- helpers ported from the original's jitter and the puzzle makers -------------------------------------------------------------

static func jitter(base: float, spread: float, rng: RandomNumberGenerator) -> float:
	var k := clampf(spread, 0.0, 0.9)
	return base * (1.0 - k + 2.0 * k * minf(rng.randf(), 0.99999999))


static func shuffle(a: Array, rng: RandomNumberGenerator) -> Array:
	for i in range(a.size() - 1, 0, -1):
		var j := int(floor(minf(rng.randf(), 0.99999999) * (i + 1)))
		var t = a[i]
		a[i] = a[j]
		a[j] = t
	return a


static func _range(n: int) -> Array:
	var out := []
	for i in n:
		out.append(i)
	return out


static func draw_lit(base: int, rng: RandomNumberGenerator) -> int:
	return maxi(2, base + int(floor(minf(rng.randf(), 0.99999999) * (2 * LIT_SPREAD + 1))) - LIT_SPREAD)


static func draw_length(base: int, rng: RandomNumberGenerator) -> int:
	return maxi(3, base + int(floor(minf(rng.randf(), 0.99999999) * (2 * LENGTH_SPREAD + 1))) - LENGTH_SPREAD)


## The order of a descent's stages: the listed stages in a drawn order, the door always last.
static func draw_stages(d: int, rng: RandomNumberGenerator) -> Array:
	var list: Array = NightWatchDescentData.RUNS[clampi(d, 1, 5)]
	var rest := []
	for k in list:
		if k != "hold":
			rest.append(k)
	shuffle(rest, rng)
	if list.has("hold"):
		rest.append("hold")
	return rest


static func valid_order(d: int, list: Array) -> bool:
	var want: Array = NightWatchDescentData.RUNS[clampi(d, 1, 5)]
	if list.size() != want.size():
		return false
	if want.has("hold") and list[list.size() - 1] != "hold":
		return false
	var a := list.duplicate()
	var b := want.duplicate()
	a.sort()
	b.sort()
	return a == b


static func stage_title(kind: String) -> String:
	return "%s%s" % [NightWatchDescentData.STAGE_NAMES[kind], " · SHE SLOWS HERE" if kind == "pipes" else ""]


## What the screen says about her pace: slowed only while the pipes are up, the car has stopped and she is out there at all.
func meter_cue() -> Dictionary:
	var slow := String(puzzle.get("kind", "")) == "pipes" and ride <= 0.0 and level > 0
	return {"slow": slow, "warn": threat > 60.0, "label": "Outside · slowed" if slow else "Outside"}


# --- the puzzles -----------------------------------------------------------------------------------------------------------

static func deal(z: Dictionary, rng: RandomNumberGenerator) -> void:
	z["wire"] = shuffle(_range(int(z["buttons"])), rng).slice(0, int(z["boxes"]))


static func make_wires(n: int, buttons: int, lit: int, rng: RandomNumberGenerator) -> Dictionary:
	var z := {"kind": "wires", "boxes": n, "buttons": buttons, "wire": [], "lit": [], "step": 0}
	deal(z, rng)
	z["lit"] = shuffle(_range(n), rng).slice(0, lit)
	z["colors"] = shuffle([0, 1, 2, 3, 4, 5], rng).slice(0, n)
	return z


## "ok", "done" or "wrong" (a wrong press starts over and re-deals).
static func press_wire(z: Dictionary, button: int, rng: RandomNumberGenerator) -> String:
	var wire: Array = z["wire"]
	var lit: Array = z["lit"]
	if button == int(wire[int(lit[int(z["step"])])]):
		z["step"] = int(z["step"]) + 1
		return "done" if int(z["step"]) == lit.size() else "ok"
	z["step"] = 0
	deal(z, rng)
	return "wrong"


static func make_memory(length: int, rng: RandomNumberGenerator) -> Dictionary:
	var seq := []
	for i in length:
		seq.append(int(floor(minf(rng.randf(), 0.99999999) * 4.0)))
	var pace := jitter(1.0, SHOW_PACE_SPREAD, rng)
	var hues := shuffle([0, 1, 2, 3], rng)
	return {"kind": "memory", "pads": 4, "seq": seq, "pace": pace, "hues": hues, "step": 0, "phase": "show", "t": -SHOW_LEAD_MS, "lit": -1}


static func advance_show(z: Dictionary, dt_ms: float) -> void:
	if z["phase"] != "show":
		return
	z["t"] = float(z["t"]) + dt_ms
	var pace := float(z.get("pace", 1.0))
	var on_ms := SHOW_ON_MS * pace
	var cycle := (SHOW_ON_MS + SHOW_OFF_MS) * pace
	var t := float(z["t"])
	var k := int(floor(t / cycle))
	if t < 0.0:
		z["lit"] = -1
	elif k >= (z["seq"] as Array).size():
		z["phase"] = "input"
		z["lit"] = -1
		z["step"] = 0
	else:
		z["lit"] = int((z["seq"] as Array)[k]) if fposmod(t, cycle) < on_ms else -1


## A press during the show does nothing ("none"). In the input phase: "ok", "done" when the sequence is complete, "wrong" (the show restarts).
static func press_pad(z: Dictionary, pad: int) -> String:
	if z["phase"] != "input":
		return "none"
	var seq: Array = z["seq"]
	if pad == int(seq[int(z["step"])]):
		z["step"] = int(z["step"]) + 1
		return "done" if int(z["step"]) == seq.size() else "ok"
	z["phase"] = "show"
	z["t"] = -SHOW_LEAD_MS * 1.3
	z["step"] = 0
	z["lit"] = -1
	return "wrong"


## `detours` caps the steps the hidden path may take up or left; `turns` caps the clicks any of its pieces needs.
static func make_pipes(n: int, rng: RandomNumberGenerator, detours := 1000000, turns := 3) -> Dictionary:
	var path: Array = []
	var attempt := 0
	while attempt < 80 and path.is_empty():
		attempt += 1
		var walk := [[0, 0]]
		var seen := {"0,0": true}
		var back := 0
		while walk.size() < n * n:
			var cur: Array = walk[walk.size() - 1]
			var r: int = cur[0]
			var c: int = cur[1]
			if r == n - 1 and c == n - 1:
				path = walk
				break
			var options := []
			for d in 4:
				var nr: int = r + int(STEP[d][0])
				var nc: int = c + int(STEP[d][1])
				if nr < 0 or nc < 0 or nr >= n or nc >= n or seen.has("%d,%d" % [nr, nc]):
					continue
				if (d == 0 or d == 3) and back >= detours:
					continue
				for w in (3 if d == 1 or d == 2 else 1):
					options.append([nr, nc, d])
			if options.is_empty():
				break
			var nxt: Array = options[int(floor(minf(rng.randf(), 0.99999999) * options.size()))]
			if int(nxt[2]) == 0 or int(nxt[2]) == 3:
				back += 1
			walk.append([nxt[0], nxt[1]])
			seen["%d,%d" % [nxt[0], nxt[1]]] = true
		if path.is_empty():
			var last: Array = walk[walk.size() - 1]
			if int(last[0]) == n - 1 and int(last[1]) == n - 1:
				path = walk
	if path.is_empty():
		path = [[0, 0]]
		for k in range(1, n):
			path.append([0, k])
		for k in range(1, n):
			path.append([k, n - 1])
	var tiles := []
	for r in n:
		var row := []
		for c in n:
			row.append({"type": "I" if minf(rng.randf(), 0.99999999) < 0.5 else "L", "rot": 0})
		tiles.append(row)
	for row in tiles:
		for t in row:
			t["rot"] = int(floor(minf(rng.randf(), 0.99999999) * (OPEN[t["type"]] as Array).size()))
	for k in path.size():
		var r: int = path[k][0]
		var c: int = path[k][1]
		var from := 3
		if k > 0:
			from = (_step_index(int(path[k - 1][0]), int(path[k - 1][1]), r, c) + 2) % 4
		var to := 1
		if k < path.size() - 1:
			to = _step_index(r, c, int(path[k + 1][0]), int(path[k + 1][1]))
		var t: Dictionary = tiles[r][c]
		t["type"] = "I" if (from + 2) % 4 == to else "L"
		var opens: Array = OPEN[t["type"]]
		t["solved"] = 0
		for oi in opens.size():
			if (opens[oi] as Array).has(from) and (opens[oi] as Array).has(to):
				t["solved"] = oi
				break
		var m := opens.size()
		var need := 1 + int(floor(minf(rng.randf(), 0.99999999) * mini(m - 1, turns)))
		t["rot"] = (int(t["solved"]) - need + m) % m
	return {"kind": "pipes", "n": n, "tiles": tiles, "path": path}


static func _step_index(r0: int, c0: int, r1: int, c1: int) -> int:
	for d in 4:
		if r0 + int(STEP[d][0]) == r1 and c0 + int(STEP[d][1]) == c1:
			return d
	return -1


static func pipe_openings(t: Dictionary) -> Array:
	return (OPEN[t["type"]] as Array)[int(t["rot"])]


static func turn_pipe(z: Dictionary, r: int, c: int) -> bool:
	var t: Dictionary = z["tiles"][r][c]
	t["rot"] = (int(t["rot"]) + 1) % (OPEN[t["type"]] as Array).size()
	return pipes_connected(z)


static func pipes_flow(z: Dictionary) -> Dictionary:
	var cells := []
	var n := int(z["n"])
	var r := 0
	var c := 0
	var enter := 3
	var done := false
	for guard in n * n + 2:
		var open: Array = pipe_openings(z["tiles"][r][c])
		if not open.has(enter):
			break
		cells.append([r, c])
		var out: int = int(open[1]) if int(open[0]) == enter else int(open[0])
		if r == n - 1 and c == n - 1 and out == 1:
			done = true
			break
		r += int(STEP[out][0])
		c += int(STEP[out][1])
		if r < 0 or c < 0 or r >= n or c >= n:
			break
		enter = (out + 2) % 4
	return {"cells": cells, "done": done}


static func pipes_connected(z: Dictionary) -> bool:
	return bool(pipes_flow(z)["done"])


# --- the game ----------------------------------------------------------------------------------------------------------------

func _build(kind: String) -> Dictionary:
	var i := descent - 1
	match kind:
		"wires":
			return make_wires(NightWatchDescentData.WIRES_BUTTONS[i], NightWatchDescentData.WIRES_BUTTONS[i], draw_lit(NightWatchDescentData.WIRES_LIT[i], _rng), _rng)
		"memory":
			return make_memory(draw_length(NightWatchDescentData.MEMORY_LENGTH[i], _rng), _rng)
		"pipes":
			return make_pipes(NightWatchDescentData.PIPES_GRID[i], _rng, NightWatchDescentData.PIPES_DETOURS[i], NightWatchDescentData.PIPES_TURNS[i])
	return {"kind": "hold"}


func kind() -> String:
	return String(puzzle.get("kind", ""))


func _finish_stage(ev: Array) -> void:
	threat = maxf(0.0, threat - STAGE_RELIEF)
	ev.append({"type": "stage", "index": stage_idx + 1})
	stage_idx += 1
	if stage_idx >= stages.size():
		over = "win"
		puzzle = {}
		ev.append({"type": "win"})
		return
	puzzle = _build(stages[stage_idx])
	ride = RIDE_MS
	held = 0.0
	side = "L" if _r() < 0.5 else "R"
	ev.append({"type": "ride", "index": stage_idx})


func _wrong(ev: Array) -> void:
	wrong += 1
	threat = minf(100.0, threat + (WRONG_BUMP if level > 0 else 0.0))
	ev.append({"type": "wrong"})


## input: {hold} is the door-hold button, down.
func step(dt_ms: float, input := {}) -> Array:
	if over != "":
		return []
	var ev := []
	var dt := dt_ms / 1000.0
	elapsed += dt_ms
	if ride > 0.0:
		ride = maxf(0.0, ride - dt_ms)
		return ev
	var k := kind()
	if k == "memory":
		advance_show(puzzle, dt_ms)
	# Her pace drifts: drawn again every so often, never during the door hold.
	if k != "hold":
		surge_left -= dt_ms
		if surge_left <= 0.0:
			surge_mult = jitter(1.0, SURGE_SPREAD, _rng)
			surge_left = jitter(SURGE_EVERY_MS, SURGE_EVERY_SPREAD, _rng)
	if level > 0:
		var rate := HOLD_RATE if k == "hold" else (PIPE_RATE if k == "pipes" else 1.0) * surge_mult
		threat = minf(100.0, threat + level * RATE_PER_LEVEL * dt * rate * speed_mult)
	if k == "hold":
		if bool(input.get("hold", false)):
			held += dt_ms
		elif level > 0:
			threat = minf(100.0, threat + HOLD_SLIP * dt)
		if held >= HOLD_MS:
			_finish_stage(ev)
	if god:
		threat = minf(threat, 99.0)
	if threat >= 100.0 and over == "":
		over = "caught"
		by = "elise"
		ev.append({"type": "caught", "by": "elise"})
	return ev


## A player action on the panel: kind "wires" {button}, "memory" {pad}, "pipes" {r, c}. Returns the events.
func act(act_kind: String, a := {}) -> Array:
	if over != "" or ride > 0.0:
		return []
	var ev := []
	if puzzle.is_empty() or kind() != act_kind:
		return ev
	if act_kind == "wires":
		var r := press_wire(puzzle, int(a["button"]), _rng)
		if r == "wrong":
			_wrong(ev)
		else:
			ev.append({"type": "step"})
			if r == "done":
				_finish_stage(ev)
	elif act_kind == "memory":
		var r := press_pad(puzzle, int(a["pad"]))
		if r == "wrong":
			_wrong(ev)
		elif r != "none":
			ev.append({"type": "step"})
			if r == "done":
				_finish_stage(ev)
	elif act_kind == "pipes":
		ev.append({"type": "step"})
		if turn_pipe(puzzle, int(a["r"]), int(a["c"])):
			_finish_stage(ev)
	return ev


# --- admin (NightWatchAdmin: the game's admin_* hooks call these) ------------------------------------------------------------------

## Jump the elevator to stage `index` (1-based): that stage's puzzle, the car stopped.
func admin_goto_stage(index: int) -> void:
	if over != "":
		return
	stage_idx = clampi(index - 1, 0, stages.size() - 1)
	puzzle = _build(stages[stage_idx])
	ride = 0.0
	held = 0.0


## Finish the stage that is up (its events, as if it had been repaired).
func admin_solve() -> Array:
	var ev := []
	if over == "" and not puzzle.is_empty():
		ride = 0.0
		_finish_stage(ev)
	return ev


## Deal the current stage's puzzle again.
func admin_redeal() -> void:
	if over == "" and stage_idx < stages.size():
		puzzle = _build(stages[stage_idx])
		held = 0.0


func admin_set_threat(percent: float) -> void:
	threat = clampf(percent, 0.0, 100.0 if not god else 99.0)


func admin_set_level(n: int) -> void:
	level = clampi(n, 0, NightWatchModesData.MAX_AI)
