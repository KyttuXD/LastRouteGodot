class_name StoryLogic
extends RefCounted

## The Facility's rules, ported from the original game's Facility rules (same numbers, same draws in the same order). Pure.
##
## You walk from room to room and do each task at its room's own station. Moving loudly makes noise; crawling is slow and quiet; every action is a little
## noisy. Three hunters answer to different things, and a hunter you are shining the beacon on holds still:
##   Opalie   lives in the gallery and closes in on noise. Stay quiet, or leave.
##   Porcelle lives in the workshop and the auditorium and closes in while it is dark. The beacon holds her, and pushes her back.
##   Quenelle rides the lift. A bell rings, then it opens at Control. Be hidden, or be elsewhere.
## The night ends when the last task is done. AI steps up as tasks are completed and with time on the clock.
## step(dt_ms, input) with input {"work", "light", "hide"} returns events; move(dir) and interact(p) are the player's actions.

const VARIETY := {"stepTempo": 0.1, "startNearer": 0.1, "startFarther": 0.05, "liftGapSpread": 0.3}
const LEVELS := {"opalie": [0, 8, 10, 10, 11, 13], "porcelle": [0, 0, 10, 10, 10, 12], "quenelle": [0, 0, 0, 6, 9, 12]}
const T := {
	"startDist": 3, "strikeMs": 1200.0, "recoverMs": 6000.0, "walkMs": 1800.0, "crawlMs": 3600.0, "walkNoise": 35.0, "crawlNoise": 6.0,
	"workNoisePerSec": 6.0, "noiseDecayPerSec": 12.0, "hearNoise": 24.0, "doorMs": 500.0, "comboLevel": 5, "comboMs": 1500.0, "dialSteps": 6,
	"stepNoise": {"code": 4.0, "dials": 8.0, "collect": 10.0, "crank": 12.0, "switches": 7.0}, "wrongNoise": 16.0,
	"beaconDrainPerSec": 18.0, "beaconRegenPerSec": 3.0, "beaconPushMs": 1500.0,
	"liftBaseMs": 30000.0, "liftPerLevelMs": 1000.0, "liftMinMs": 14000.0, "bellMs": 3500.0, "openMs": 5000.0, "exposeMs": 1500.0,
}
## One column per night 1-6; Custom Night plays night 6's column.
const NIGHTS := {
	"startDist": [3, 2, 2, 2, 2, 2],
	"paceX": [1.0, 2.2, 2.7, 2.75, 2.8, 3.2],
	"hear": [24.0, 15.0, 12.0, 11.5, 11.0, 9.0],
	"quietX": [0.0, 1.2, 1.5, 1.55, 1.6, 2.6],
	"recoverX": [1.0, 1.5, 1.6, 1.7, 1.8, 2.0],
	"awayPaceX": [0.0, 0.8, 0.9, 1.0, 1.1, 1.4],
	"strikeMs": [1200.0, 1200.0, 1200.0, 1150.0, 1150.0, 1100.0],
	"drainX": [1.0, 1.4, 1.5, 1.6, 1.7, 1.9],
	"keenMs": [0.0, 30000.0, 25000.0, 22000.0, 20000.0, 18000.0],
	"keenCap": [0, 2, 3, 3, 4, 4],
	"liftGapX": [1.0, 1.0, 1.0, 0.9, 0.8, 0.7],
	"openX": [1.0, 1.0, 1.0, 1.0, 1.15, 1.3],
	"liftSees": [0, 0, 0, 1, 1, 1],
}
const PORCELLE_ROOMS := ["workshop", "auditorium"]


static func tune_for(night: int, is_custom := false) -> Dictionary:
	var i := 5 if is_custom else clampi(night, 1, 6) - 1
	var out := {}
	for k in NIGHTS:
		out[k] = NIGHTS[k][i]
	return out


## Who is on the floor on a level (0-based).
static func active_hunters(level_idx: int) -> Array:
	var out := []
	for id in StoryData.CAST:
		if int(LEVELS[id][mini(level_idx, 5)]) > 0:
			out.append(id)
	return out


var n := 0
var rng: NightWatchStream
var vr: NightWatchStream
var levels := {}
var is_custom := false
var infinite_beacon := false
var tune := {}
var order_idx := 0
var tasks: Array = []

var elapsed := 0.0
var over := ""
var by := ""
var room := "control"
var moving := {}                # {to, left, door} while walking between rooms, else {}
var crawl := false
var hidden := false
var light := false
var working := false
var noise := 0.0
var charge := 100.0
var task_idx := 0
var task_ms := 0.0
var puzzle := {}
var opalie := {}
var porcelle := {}
var quenelle := {}
var dt := 0.0
## Admin (NightWatchAdmin): god mode sends whoever would have got you a step back; the hunters' step clocks run at this multiple (1.0 = the 2D numbers).
var god := false
var hunter_speed := 1.0


## opts: night, rng, var_rng, levels, custom, infinite_beacon, order (a task order index, for tests).
func _init(opts: Dictionary) -> void:
	n = clampi(int(opts.get("night", 1)), 1, 6) - 1
	is_custom = bool(opts.get("custom", false))
	rng = opts["rng"]
	vr = NightWatchStream.variety_of(rng, opts.get("var_rng", null))
	levels = opts.get("levels", {})
	infinite_beacon = bool(opts.get("infinite_beacon", false))
	var list_night := 6 if is_custom else n + 1
	var orders: Array = StoryData.TASK_ORDERS[list_night]
	var drawn := NightWatchStream.pick_index(vr, orders.size())
	var given := int(opts.get("order", -1))
	order_idx = given if given >= 0 and given < orders.size() else drawn
	var base: Array = StoryData.tasks(list_night)
	for i in orders[order_idx]:
		tasks.append(base[i])
	tune = tune_for(int(opts.get("night", 1)), is_custom)
	opalie = _creeper()
	porcelle = _creeper()
	quenelle = {"state": "away", "t": 0.0, "clock": 0.0, "gap": -1.0, "expose": 0.0, "openFor": T["openMs"]}
	puzzle = _make_puzzle(tasks[0])


func base_level(id: String) -> int:
	if levels.has(id) and int(levels[id]) >= 0:
		return int(levels[id])
	return int(LEVELS[id][n])


## Time on the clock makes each hunter keener (not on a Custom Night).
func keen() -> int:
	if not is_custom and float(tune["keenMs"]) > 0.0:
		return mini(int(tune["keenCap"]), int(floor(elapsed / float(tune["keenMs"]))))
	return 0


## Steps up as tasks are done (+1 every two, up to +2), and with time on the clock.
func level(id: String) -> int:
	if base_level(id) <= 0:
		return 0
	return mini(20, base_level(id) + mini(2, task_idx / 2) + keen())


func _recover_draw() -> float:
	return NightWatchStream.spread_ms(float(T["recoverMs"]) * float(tune["recoverX"]), rng)


func _start_offset() -> int:
	var u := vr.next()
	if vr.neutral or (n == 0 and not is_custom):
		return 0
	if u < float(VARIETY["startNearer"]):
		return -1
	if u >= 1.0 - float(VARIETY["startFarther"]):
		return 1
	return 0


func _creeper() -> Dictionary:
	var dist: int = int(tune["startDist"]) + _start_offset()
	var pacer := NightWatchPacer.new(rng)
	var recover := _recover_draw()
	return {"dist": dist, "pacer": pacer, "strike": 0.0, "away": 0.0, "recover": recover, "push": 0.0, "alert": 0.0, "tempo": NightWatchStream.tempo(vr, VARIETY["stepTempo"])}


func _pick(count: int) -> int:
	return int(floor(rng.next() * count))


## The puzzle for a task, made when it comes up (so the same seed gives the same night).
func _make_puzzle(t: Dictionary) -> Dictionary:
	if t.is_empty():
		return {}
	var kind: String = t["kind"]
	if kind == "code":
		var code := ""
		for i in int(t["n"]):
			code += str(_pick(10))
		return {"kind": "code", "n": t["n"], "code": code, "entered": ""}
	if kind == "dials":
		var target := []
		for i in int(t["n"]):
			target.append(_pick(int(T["dialSteps"])))
		var pos := []
		for x in target:
			pos.append((int(x) + 1 + _pick(int(T["dialSteps"]) - 1)) % int(T["dialSteps"]))
		return {"kind": "dials", "n": t["n"], "target": target, "pos": pos}
	if kind == "collect":
		return {"kind": "collect", "n": t["n"], "taken": []}
	if kind == "crank":
		return {"kind": "crank", "n": t["n"], "done": 0}
	if kind == "switches":
		var order := []
		for i in int(t["n"]):
			order.append(i)
		for i in range(order.size() - 1, 0, -1):
			var j := _pick(i + 1)
			var tmp = order[i]
			order[i] = order[j]
			order[j] = tmp
		return {"kind": "switches", "n": t["n"], "order": order, "next": 0}
	return {"kind": "hold", "ms": t["ms"]}


## Opalie and Porcelle close in a step at a time while you are in their rooms; leave and they slowly step back, or from night 2 hover near the door.
func _creep(id: String, h: Dictionary, present: bool, ev: Array) -> bool:
	if not present:
		h["strike"] = 0.0
		h["push"] = 0.0   # her step timer is kept: stepping out does not restart her wait
		var hears := noise > float(tune["hear"]) if id == "opalie" else true
		if float(tune["awayPaceX"]) > 0.0 and int(h["dist"]) > 1:
			h["away"] = 0.0
			if hears and (h["pacer"] as NightWatchPacer).step(dt * float(tune["awayPaceX"]) * float(h["tempo"]) * hunter_speed, level(id)):
				h["dist"] = int(h["dist"]) - 1
				h["tempo"] = NightWatchStream.tempo(vr, VARIETY["stepTempo"])
				ev.append({"type": "close", "id": id, "dist": h["dist"], "away": true})
			return false
		h["away"] = float(h["away"]) + dt
		if float(h["away"]) >= float(h["recover"]) and int(h["dist"]) < int(tune["startDist"]):
			h["dist"] = int(h["dist"]) + 1
			h["away"] = 0.0
			h["recover"] = _recover_draw()
			ev.append({"type": "back", "id": id, "dist": h["dist"]})
		return false
	h["away"] = 0.0
	if float(h["alert"]) != 0.0:
		(h["pacer"] as NightWatchPacer).skip(float(h["alert"]))
		h["alert"] = 0.0
	if light:   # looked at: she holds still, and Porcelle is pushed back
		if id == "porcelle":
			h["push"] = float(h["push"]) + dt
			if float(h["push"]) >= float(T["beaconPushMs"]):
				h["push"] = 0.0
				if int(h["dist"]) < int(tune["startDist"]):
					h["dist"] = int(h["dist"]) + 1
					ev.append({"type": "pushed", "id": id})
	else:
		h["push"] = 0.0
		var noticed := noise > float(tune["hear"]) if id == "opalie" else true
		var pace: float = float(tune["paceX"]) if noticed else float(tune["quietX"])
		if int(h["dist"]) > 0 and pace > 0.0 and (h["pacer"] as NightWatchPacer).step(dt * pace * float(h["tempo"]) * hunter_speed, level(id)):
			h["dist"] = int(h["dist"]) - 1
			h["tempo"] = NightWatchStream.tempo(vr, VARIETY["stepTempo"])
			ev.append({"type": "close", "id": id, "dist": h["dist"], "quiet": not noticed})
	if int(h["dist"]) <= 0:
		h["strike"] = float(h["strike"]) + dt
		return float(h["strike"]) >= float(tune["strikeMs"])
	h["strike"] = 0.0
	return false


func _finish(ev: Array, who: String) -> Array:
	if god:   # admin: she is sent back
		if who == "quenelle":
			quenelle["expose"] = 0.0
			quenelle["state"] = "away"
			quenelle["t"] = 0.0
		else:
			var h: Dictionary = opalie if who == "opalie" else porcelle
			h["dist"] = 2
			h["strike"] = 0.0
		return ev
	over = "caught"
	by = who
	ev.append({"type": "caught", "by": who})
	return ev


## Slipping out of a room with her at your throat gives you a step of room (once you are through the door).
func _slip() -> void:
	if room == "gallery" and int(opalie["dist"]) == 0:
		opalie["dist"] = 1
	if PORCELLE_ROOMS.has(room) and int(porcelle["dist"]) == 0:
		porcelle["dist"] = 1


## input: {"work": bool, "light": bool, "hide": bool} held this step.
func step(dt_ms: float, input := {}) -> Array:
	var ev := []
	if over != "":
		return ev
	dt = dt_ms
	elapsed += dt_ms
	var dts := dt_ms / 1000.0
	# walking between rooms takes time; getting through the door takes doorMs, and until then you are still in the room you are leaving
	var through := false
	if not moving.is_empty():
		if float(moving["door"]) > 0.0:
			moving["door"] = float(moving["door"]) - dt_ms
			through = float(moving["door"]) <= 0.0
		moving["left"] = float(moving["left"]) - dt_ms
		if float(moving["left"]) <= 0.0:
			room = moving["to"]
			moving = {}
			ev.append({"type": "arrive", "room": room})
	var still := moving.is_empty()
	var there := still or (not moving.is_empty() and float(moving["door"]) > 0.0)
	hidden = still and room == "control" and bool(input.get("hide", false))
	light = bool(input.get("light", false)) and still and charge > 0.0
	if light:
		charge = charge if infinite_beacon else maxf(0.0, charge - float(T["beaconDrainPerSec"]) * float(tune["drainX"]) * dts)
	else:
		charge = minf(100.0, charge + float(T["beaconRegenPerSec"]) * dts)
	# the current task: hold work in the right room
	var task: Dictionary = tasks[task_idx] if task_idx < tasks.size() else {}
	noise = maxf(0.0, noise - float(T["noiseDecayPerSec"]) * dts)
	working = still and not task.is_empty() and task["kind"] == "hold" and not hidden and bool(input.get("work", false)) and task["room"] == room
	if working:
		task_ms += dt_ms
		noise = minf(100.0, noise + float(T["workNoisePerSec"]) * dts)
		if task_ms >= float(task["ms"]):
			_complete_task(ev)
		if over != "":
			return ev
	var before := ev.size()
	if _creep("opalie", opalie, there and room == "gallery", ev):
		return _finish(ev, "opalie")
	# working together: when Opalie closes in on a noise she is heard, and Porcelle (once both are keen) will be 1.5 s nearer a step
	var closed := false
	for i in range(before, ev.size()):
		if ev[i]["type"] == "close" and ev[i]["id"] == "opalie":
			closed = true
	if closed and level("opalie") >= int(T["comboLevel"]) and level("porcelle") >= int(T["comboLevel"]):
		porcelle["alert"] = T["comboMs"]
		ev.append({"type": "alert", "id": "porcelle"})
	if _creep("porcelle", porcelle, there and PORCELLE_ROOMS.has(room), ev):
		return _finish(ev, "porcelle")
	if through:
		_slip()   # through the door before her strike landed
	# Quenelle: a bell, then the lift opens at Control for a while
	var q := quenelle
	var q_level := level("quenelle")
	if q_level > 0:
		q["clock"] = float(q["clock"]) + dt_ms
		if float(q["gap"]) < 0.0:
			q["gap"] = maxf(float(T["liftMinMs"]), float(T["liftBaseMs"]) - q_level * float(T["liftPerLevelMs"])) * float(tune["liftGapX"]) \
				* (1.0 - float(VARIETY["liftGapSpread"]) + 2.0 * float(VARIETY["liftGapSpread"]) * rng.next())
		if q["state"] == "away" and float(q["clock"]) >= float(q["gap"]):
			q["state"] = "bell"
			q["t"] = 0.0
			q["clock"] = 0.0
			q["gap"] = -1.0
			ev.append({"type": "bell", "id": "quenelle"})
		elif q["state"] == "bell":
			q["t"] = float(q["t"]) + dt_ms
			if float(q["t"]) >= float(T["bellMs"]):
				q["state"] = "open"
				q["t"] = 0.0
				q["expose"] = 0.0
				q["openFor"] = NightWatchStream.spread_ms(float(T["openMs"]) * float(tune["openX"]), rng)
				ev.append({"type": "open", "id": "quenelle"})
		elif q["state"] == "open":
			q["t"] = float(q["t"]) + dt_ms
			var seen := there and ((room == "control" and not hidden) or (room == "lift" and int(tune["liftSees"]) != 0))
			q["expose"] = float(q["expose"]) + dt_ms if seen else maxf(0.0, float(q["expose"]) - dt_ms)
			if float(q["expose"]) >= float(T["exposeMs"]):
				return _finish(ev, "quenelle")
			if float(q["t"]) >= float(q["openFor"]):
				q["state"] = "away"
				q["t"] = 0.0
				q["expose"] = 0.0
				q["clock"] = 0.0
				q["gap"] = -1.0
				ev.append({"type": "leave", "id": "quenelle"})
	return ev


func _complete_task(ev: Array) -> void:
	task_ms = 0.0
	task_idx += 1
	ev.append({"type": "task", "index": task_idx})
	if task_idx >= tasks.size():
		over = "win"
		puzzle = {}
		ev.append({"type": "win"})
		return
	puzzle = _make_puzzle(tasks[task_idx])


## One action at the current task's station: {"digit"} on the keypad, {"i"} on a dial, a part or a breaker, {} on the crank. Wrong moves start the
## puzzle over and are loud. Returns events.
func interact(p := {}) -> Array:
	if over != "" or not moving.is_empty() or hidden:
		return []
	var task: Dictionary = tasks[task_idx] if task_idx < tasks.size() else {}
	var z := puzzle
	if task.is_empty() or z.is_empty() or task["room"] != room or z["kind"] == "hold":
		return [{"type": "deny"}]
	var ev := []
	var ok := true
	var done := false
	var kind: String = z["kind"]
	if kind == "code":
		var digit := str(p.get("digit", ""))
		ok = digit == (z["code"] as String).substr((z["entered"] as String).length(), 1)
		if ok:
			z["entered"] = String(z["entered"]) + digit
			done = (z["entered"] as String).length() == int(z["n"])
		else:
			z["entered"] = ""
	elif kind == "dials":
		var i := int(p.get("i", -1))
		if not (i >= 0 and i < int(z["n"])):
			return [{"type": "deny"}]
		z["pos"][i] = (int(z["pos"][i]) + 1) % int(T["dialSteps"])
		done = true
		for k in int(z["n"]):
			if int(z["pos"][k]) != int(z["target"][k]):
				done = false
	elif kind == "collect":
		var i2 := int(p.get("i", -1))
		if not (i2 >= 0 and i2 < int(z["n"])) or (z["taken"] as Array).has(i2):
			return [{"type": "deny"}]
		(z["taken"] as Array).append(i2)
		done = (z["taken"] as Array).size() == int(z["n"])
	elif kind == "crank":
		z["done"] = int(z["done"]) + 1
		done = int(z["done"]) >= int(z["n"])
	elif kind == "switches":
		var i3 := int(p.get("i", -1))
		if not (i3 >= 0 and i3 < int(z["n"])):
			return [{"type": "deny"}]
		ok = i3 == int(z["order"][int(z["next"])])
		if ok:
			z["next"] = int(z["next"]) + 1
			done = int(z["next"]) == int(z["n"])
		else:
			z["next"] = 0
	noise = minf(100.0, noise + (float(T["stepNoise"][kind]) if ok else float(T["wrongNoise"])))
	ev.append({"type": "step" if ok else "wrong", "kind": kind})
	if done:
		_complete_task(ev)
	return ev


## Start walking through a door ("L", "R" or "C"). Returns false when there is none or you are already walking.
func move(dir: String) -> bool:
	if over != "" or not moving.is_empty():
		return false
	var exits: Dictionary = StoryData.ROOMS[room]["exits"]
	if not exits.has(dir):
		return false
	hidden = false
	noise = minf(100.0, noise + (float(T["crawlNoise"]) if crawl else float(T["walkNoise"])))
	moving = {"to": exits[dir], "left": float(T["crawlMs"]) if crawl else float(T["walkMs"]), "door": T["doorMs"]}
	return true


func set_crawl(on: bool) -> void:
	crawl = on
