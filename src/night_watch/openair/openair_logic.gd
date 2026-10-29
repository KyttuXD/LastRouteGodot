class_name NightWatchOpenAirLogic
extends RefCounted

## Open Air's rules, a port of createWatchGame in the 2D openair-logic.js: three outdoor watches, each with its own hunter and its own way
## of keeping the dark off. No nodes: the shift scene feeds it what the player holds and draws what happens, and
## scripts/validate_night_watch_extra.gd replays whole watches headless.
##
##   0 ROOFTOP   Verrine climbs in by the stair door (left) or the hatch (right), a step at a time. A torch held on her side keeps her still;
##               a barred door or shut hatch sends her back at once. The lantern's oil runs the winches too: holding either shut burns it faster,
##               relighting costs some, and with none left the lantern will not light and the barriers swing open. The wind blows the lantern out
##               every so often, and in the dark she is keener.
##   1 BUS STOP  Wynelle: it is cold. Warmth falls by itself; the heat lamp raises it and burns fuel, and canisters around the shelter refill
##               it. Below 40 warmth her progress builds, and at the top the cold takes the stop.
##   2 CAMPFIRE  Two come out of the trees, one side each, a step at a time on the random wait: Verrine always on the left, Quenelle always on
##               the right. The torch on a side holds her still. Held on Verrine at the edge of the light it sends her back into the dark;
##               Quenelle does not mind the light, but if you are in the tent while she is at the edge she loses the trail and backs off.
##               The tent hides you from Quenelle only. Ysolde works the tent: while you hide she creeps to the log pile, takes a log, and in
##               the end looks in; while you are out she backs away again, more slowly. The fire burns down: throw logs on it, fetch more.
## Weather: the bus stop gets squalls of snow (the cold bites harder) and the campfire showers of rain (the fire burns faster); in the last
## eighteen seconds of the bus stop's watch the bus comes up the road, and the cold lets go of the stop (`bus` runs 0 to 1).
##
## step(dt_ms, input {torchL, torchR, barL, barR, relight, gather, tent}) returns events: close {id, dist, side}, repelled {id, side},
## gust, relit, dry, weather {kind}, weatherEnd {kind}, bus, can, creep, stolen, backoff {dist}, tentIn, tentOut, gathered, caught {by, cause}, win.

const D := preload("res://src/night_watch/openair/openair_data.gd")
const Pacer := preload("res://src/night_watch/openair/openair_pacer.gd")

## The listed numbers (T in the 2D file).
const START_DIST := 3
const AT_MS := 5200.0
const LEAVE_MS := 450.0
const GUST_MS := 22000.0
const GUST_JITTER_MS := 8000.0
const RELIGHT_MS := 1600.0
const DARK_BONUS := 4
const TORCH_DRAIN := 9.0
const TORCH_REGEN := 4.0
const OIL_BASE := 0.12
const OIL_PER_BAR := 0.45
const RELIGHT_OIL := 4.0
const COLD_DRAIN := 1.0
const LAMP_WARM := 2.8
const LAMP_FUEL := 1.6
const CHILL_LINE := 40.0
const CHILL_PER_POINT := 0.12
const CHILL_RECOVER := 3.0
const CAN_EVERY_MS := 17000.0
const CAN_FUEL := 35.0
const MAX_CANS := 3
const CAMP_DRAIN := 1.8
const LOG_FUEL := 28.0
const START_LOGS := 6
const GATHER_MS := 2200.0
const OUT_GRACE_MS := 10000.0
const FUEL_STEAL := 15.0
const CAMP_AT_MS := 5200.0
const PUSH_MS := 1500.0
const PUSH_BACK := 2
const LOST_MS := 2000.0
const LOST_BACK := 1
const TENT_PACE := 3.25
const BACK_PACE := 1.0
const LOW_FIRE := 25.0
const LOW_FIRE_BONUS := 3
## Variety (docs/VARIETY.md, "Open Air"): every draw is on the watch's one seeded stream; none touches a tell or a held defence.
const ARRIVE_SPREAD_MS := 4000.0
const GUST_FIRST_SPREAD := 0.25
const SIDE_SWITCH := 0.65
const MOOD_EVERY_MS := 45000.0
const MOOD_EVERY_SPREAD := 0.33
const MOOD_PACE := 1.3
const MOOD_CALM := 0.2
const WEATHER_LAST_SPREAD := 0.25
const CAN_SPREAD := 0.25
const CAN_FIRST_MS := 4000.0
const CAN_FIRST_SPREAD := 0.5
const COLD_SPREAD := 0.15
const COLD_EVERY_MS := 30000.0
const COLD_EVERY_SPREAD := 0.33


## The rooftop's climber: side ("L" stair door / "R" hatch), dist 3..0, her pacer, how long she has waited at the door and been sent off.
class Climber:
	extends RefCounted
	var side := "L"
	var dist := 3
	var pacer
	var at_ms := 0.0
	var leave := 0.0


## One of the campfire's two at the edge of the light.
class Edge:
	extends RefCounted
	var id := ""
	var side := "L"
	var on := false
	var lvl := 0
	var dist := 3
	var pacer
	var at_ms := 0.0
	var push := 0.0
	var lost := 0.0


## Ysolde at the campfire: dist 2 in the trees, 1 out of them, 0 at the log pile; two pacers so going in and out resets neither.
class Ysolde:
	extends RefCounted
	var dist := 2
	var fwd
	var back


var watch := 0
var hunter := ""
var elapsed := 0.0
var over := ""
var by := ""
var cause := ""
var torch := 100.0
var torch_side := ""
var bus := 0.0
var infinite_light := false
## Admin (NightWatchAdmin): god mode sends whoever would catch you back instead; speed scales how often the hunters step.
var god := false
var speed := 1.0
var weather := {}       # {on, t, next, lasts} for the bus stop and the campfire

# rooftop
var lantern := true
var gust := 0.0
var relight := 0.0
var oil := 100.0
var bars := {"L": false, "R": false}
# bus stop
var warm := 100.0
var lamp := false
var fuel := 100.0
var cans: Array = []
var can_clock := 0.0
var can_at := 0.0
var chill := 0.0
var cold_mult := 1.0
var cold_left := 0.0
# campfire
var fire := 100.0
var logs := 0
var gather := 0.0
var out := 0.0
var hidden := false
var tent_ms := 0.0
var y: Ysolde
var mood_kind := "calm"
var mood_left := 0.0
## The rooftop's climber, or the campfire's Verrine; and the campfire's Quenelle.
var v
var q

var _base := 0
var _verrine_at := 0
var _quenelle_at := 0
var _rng: Callable
var _seeded: RandomNumberGenerator


## `rng` is a Callable returning 0..1 (tests pass a constant roll); without one the watch draws from a stream seeded with `seed_number`.
## `level_override` (>= 0) replaces the watch's hunter level; `verrine_level` / `quenelle_level` set the campfire's two (default: their listed levels).
func _init(watch_index: int, seed_number: int = 0, level_override := -1, verrine_level := -1, quenelle_level := -1, rng := Callable(), infinite := false) -> void:
	watch = clampi(watch_index, 0, 2)
	hunter = String(D.WATCHES[watch]["hunter"])
	infinite_light = infinite
	if rng.is_valid():
		_rng = rng
	else:
		_seeded = RandomNumberGenerator.new()
		_seeded.seed = seed_number
		_rng = Callable(self, "_seeded_roll")
	_base = level_override if level_override >= 0 else int(D.LEVELS[hunter])
	_verrine_at = verrine_level if verrine_level >= 0 else int(D.LEVELS["verrine"])
	_quenelle_at = quenelle_level if quenelle_level >= 0 else int(D.LEVELS["quenelle"])
	var wx: Dictionary = D.WEATHER.get(watch, {})
	if not wx.is_empty():
		weather = {"on": false, "t": 0.0, "next": float(wx["first"]) * (0.75 + _r() * 0.5), "lasts": 0.0}
		weather["lasts"] = jitter(float(wx["lastsMs"]), WEATHER_LAST_SPREAD)
	if watch == 0:
		gust = jitter(GUST_MS, GUST_FIRST_SPREAD)
		v = _climber()
	elif watch == 1:
		can_at = jitter(CAN_FIRST_MS, CAN_FIRST_SPREAD)
		cold_mult = jitter(1.0, COLD_SPREAD)
		cold_left = jitter(COLD_EVERY_MS, COLD_EVERY_SPREAD)
	else:
		logs = START_LOGS
		y = Ysolde.new()
		y.fwd = Pacer.new(_rng)
		y.back = Pacer.new(_rng)
		mood_kind = _draw_mood()
		mood_left = jitter(MOOD_EVERY_MS, MOOD_EVERY_SPREAD)
		v = _edge("verrine", _verrine_at)
		q = _edge("quenelle", _quenelle_at)


func _seeded_roll() -> float:
	return minf(_seeded.randf(), 0.99999999)


func _r() -> float:
	return float(_rng.call())


func jitter(base: float, spread: float) -> float:
	var k := clampf(spread, 0.0, 0.9)
	return base * (1.0 - k + 2.0 * k * _r())


func level() -> int:
	return _base


## The watch's own hunter is at `base`; at the campfire Verrine (left) and Quenelle (right) are at their own levels.
func level_of(id: String) -> int:
	if watch == 2 and id == "verrine":
		return _verrine_at
	if watch == 2 and id == "quenelle":
		return _quenelle_at
	return _base


## The night's AI step-ups (a hunter at 0 stays at 0).
func _keen(lvl: int) -> int:
	return mini(20, NightWatchData.effective_level(lvl, NightWatchData.hour_index(elapsed)))


func _other(side: String) -> String:
	return "R" if side == "L" else "L"


func _arrival_offset() -> float:
	return (_r() * 2.0 - 1.0) * ARRIVE_SPREAD_MS


func _draw_mood() -> String:
	var u := _r()
	if u < MOOD_CALM:
		return "calm"
	return "bold" if (u - MOOD_CALM) / (1.0 - MOOD_CALM) < 0.5 else "shy"


## A climber's or an edge hunter's first wait starts up to 4 s in credit or in debt, drawn whether or not she is on.
func _climber() -> Climber:
	var h := Climber.new()
	h.side = "L" if _r() < 0.5 else "R"
	h.pacer = Pacer.new(_rng)
	h.pacer.skip(_arrival_offset())
	return h


func _edge(id: String, lvl: int) -> Edge:
	var h := Edge.new()
	h.id = id
	h.side = String(D.SIDES[id])
	h.on = lvl > 0
	h.lvl = lvl
	h.pacer = Pacer.new(_rng)
	h.pacer.skip(_arrival_offset())
	return h


func _finish(ev: Array, who: String, why: String) -> Array:
	if god:
		_god_save(who, why)
		ev.append({"type": "godsave", "by": who, "cause": why})
		return ev
	over = "caught"
	by = who
	cause = why
	ev.append({"type": "caught", "by": who, "cause": why})
	return ev


## God mode: the catch is undone (she is sent back, the cold, the dark and the tent let go) and the watch goes on.
func _god_save(who: String, why: String) -> void:
	match why:
		"cold":
			chill = 40.0
		"fire":
			out = 0.0
			fire = maxf(fire, 30.0)
		"tent":
			y.dist = 2
			y.fwd.reset()
		_:
			if watch == 0:
				v.dist = 2
				v.at_ms = 0.0
				v.leave = 0.0
				v.pacer.reset()
			else:
				var h = v if who == "verrine" else q
				if h != null and h.id == who:
					_send_back(h, 2, [])


## A hunter who comes a step at a time toward a spot, held still by the torch on her side. True once she has waited out the time.
func _approach(h: Climber, dt_ms: float, lvl: int, barred: bool, ev: Array, id: String) -> bool:
	if h.dist > 0:
		if torch_side != h.side and h.pacer.step(dt_ms * speed, _keen(lvl)):
			h.dist -= 1
			ev.append({"type": "close", "id": id, "dist": h.dist, "side": h.side})
		return false
	if barred:
		h.at_ms = 0.0
		h.leave += dt_ms
		if h.leave >= LEAVE_MS:
			h.dist = 2
			h.leave = 0.0
			h.pacer.reset()
			h.side = _other(h.side) if _r() < SIDE_SWITCH else h.side
			ev.append({"type": "repelled", "id": id, "side": h.side})
		return false
	h.leave = 0.0
	if torch_side != h.side:
		h.at_ms += dt_ms
	return h.at_ms >= AT_MS


## Who the dark lets in when the fire has been out too long: Ysolde, unless she is off; then the nearer of the two who are on.
func _dark_by() -> String:
	if _base > 0:
		return "ysolde"
	var on := []
	for h in [q, v]:
		if h.on:
			on.append(h)
	if on.is_empty():
		return "ysolde"
	var best = on[0]
	for h in on:
		if h.dist < best.dist:
			best = h
	return String(best.id)


## The campfire's two: a step at a time toward the edge of the light on her own side. At the edge she waits out CAMP_AT_MS and then she is
## at the fire. Verrine: the torch held on her there for PUSH_MS sends her back. Quenelle: the tent while she is there pauses her, and after
## LOST_MS she loses the trail and backs off a little.
func _edge_step(h: Edge, dt_ms: float, ev: Array) -> bool:
	if not h.on:
		return false
	var held := torch_side == h.side
	var lvl := _keen(h.lvl) + (LOW_FIRE_BONUS if fire < LOW_FIRE else 0)
	if h.dist > 0:
		var pace := 1.0
		if h.id == "verrine" and mood_kind != "calm":
			pace = MOOD_PACE if mood_kind == "bold" else 1.0 / MOOD_PACE
		if not held and h.pacer.step(dt_ms * pace * speed, lvl):
			h.dist -= 1
			ev.append({"type": "close", "id": h.id, "dist": h.dist, "side": h.side})
		return false
	if h.id == "verrine" and held:
		h.push += dt_ms
		if h.push >= PUSH_MS:
			_send_back(h, PUSH_BACK, ev)
		return false
	if h.id == "quenelle" and hidden:
		h.lost += dt_ms
		if h.lost >= LOST_MS:
			_send_back(h, LOST_BACK, ev)
		return false
	if not held:
		h.at_ms += dt_ms
	return h.at_ms >= CAMP_AT_MS


func _send_back(h: Edge, to: int, ev: Array) -> void:
	h.dist = to
	h.at_ms = 0.0
	h.push = 0.0
	h.lost = 0.0
	h.pacer.reset()
	ev.append({"type": "repelled", "id": h.id, "side": h.side, "dist": to})


## input: {torchL, torchR, barL, barR, relight, gather, tent} held this step.
func step(dt_ms: float, input := {}) -> Array:
	if over != "":
		return []
	var ev := []
	var dt := dt_ms / 1000.0
	elapsed += dt_ms

	# Weather comes and goes on its own clock; the bus stop's last seconds are the bus.
	var wx_mult := 1.0
	var wx: Dictionary = D.WEATHER.get(watch, {})
	if not wx.is_empty():
		if watch == 1 and elapsed >= D.WATCH_MS - D.BUS_MS:
			if weather["on"]:
				weather["on"] = false
				ev.append({"type": "weatherEnd", "kind": wx["kind"]})
			if bus == 0.0:
				ev.append({"type": "bus"})
			bus = minf(1.0, (elapsed - (D.WATCH_MS - D.BUS_MS)) / D.BUS_MS)
		else:
			weather["t"] = float(weather["t"]) + dt_ms
			if not weather["on"] and float(weather["t"]) >= float(weather["next"]):
				weather["on"] = true
				weather["t"] = 0.0
				ev.append({"type": "weather", "kind": wx["kind"]})
			elif weather["on"] and float(weather["t"]) >= float(weather["lasts"]):
				weather["on"] = false
				weather["t"] = 0.0
				weather["next"] = float(wx["everyMs"]) * (0.75 + _r() * 0.5)
				weather["lasts"] = jitter(float(wx["lastsMs"]), WEATHER_LAST_SPREAD)
				ev.append({"type": "weatherEnd", "kind": wx["kind"]})
		if weather["on"]:
			wx_mult = float(wx["mult"])

	# The torch: held on a side, it drains; let go and it recovers. Hands busy gathering, or hiding in the tent, means no torch.
	if watch == 2:
		var hide := bool(input.get("tent", false))
		if hide != hidden:
			hidden = hide
			tent_ms = 0.0
			gather = 0.0
			ev.append({"type": "tentIn" if hide else "tentOut"})
		if hidden:
			tent_ms += dt_ms
	var want := ""
	if not ((bool(input.get("gather", false)) or hidden) and watch == 2):
		if bool(input.get("torchL", false)):
			want = "L"
		elif bool(input.get("torchR", false)):
			want = "R"
	torch_side = want if want != "" and torch > 0.0 else ""
	if torch_side != "" and not infinite_light:
		torch = maxf(0.0, torch - TORCH_DRAIN * dt)
	else:
		torch = minf(100.0, torch + TORCH_REGEN * dt)

	if watch == 0:
		var held := {"L": bool(input.get("barL", false)) and oil > 0.0, "R": bool(input.get("barR", false)) and oil > 0.0}
		bars = held
		var strain := (1 if held["L"] else 0) + (1 if held["R"] else 0)
		if not infinite_light:
			oil = maxf(0.0, oil - (OIL_BASE + OIL_PER_BAR * strain) * dt)
		if lantern and oil <= 0.0:
			lantern = false
			relight = 0.0
			ev.append({"type": "dry"})
		gust -= dt_ms
		if lantern and gust <= 0.0:
			lantern = false
			relight = 0.0
			ev.append({"type": "gust"})
		if not lantern:
			relight = relight + dt_ms if bool(input.get("relight", false)) and oil >= RELIGHT_OIL else maxf(0.0, relight - dt_ms)
			if relight >= RELIGHT_MS:
				lantern = true
				relight = 0.0
				oil -= RELIGHT_OIL
				gust = GUST_MS + _r() * GUST_JITTER_MS
				ev.append({"type": "relit"})
		var barred: bool = bool(held["L"]) if v.side == "L" else bool(held["R"])
		if _approach(v, dt_ms, _base + (0 if lantern else DARK_BONUS), barred, ev, "verrine"):
			return _finish(ev, "verrine", "edge")

	if watch == 1:
		var lamp_on := lamp and fuel > 0.0
		cold_left -= dt_ms
		if cold_left <= 0.0:
			cold_mult = jitter(1.0, COLD_SPREAD)
			cold_left = jitter(COLD_EVERY_MS, COLD_EVERY_SPREAD)
		warm = maxf(0.0, minf(100.0, warm + ((LAMP_WARM if lamp_on else 0.0) - COLD_DRAIN * wx_mult * cold_mult) * dt))
		if lamp_on:
			fuel = maxf(0.0, fuel - LAMP_FUEL * dt)
			if fuel <= 0.0:
				lamp = false
				ev.append({"type": "dry"})
		can_clock += dt_ms
		if can_clock >= can_at and cans.size() < MAX_CANS:
			can_clock = 0.0
			can_at = jitter(CAN_EVERY_MS, CAN_SPREAD)
			var free := []
			for i in 3:
				if not cans.has(i):
					free.append(i)
			cans.append(free[int(floor(_r() * free.size()))])
			ev.append({"type": "can"})
		var factor := maxf(0.4, float(_base) / 10.0)
		if bus > 0.0:
			chill = maxf(0.0, chill - CHILL_RECOVER * 2.0 * dt)
		elif warm < CHILL_LINE:
			chill = minf(100.0, chill + (CHILL_LINE - warm) * CHILL_PER_POINT * factor * dt)
		else:
			chill = maxf(0.0, chill - CHILL_RECOVER * dt)
		if chill >= 100.0:
			return _finish(ev, "wynelle", "cold")

	if watch == 2:
		mood_left -= dt_ms
		if mood_left <= 0.0:
			mood_kind = _draw_mood()
			mood_left = jitter(MOOD_EVERY_MS, MOOD_EVERY_SPREAD)
		fire = maxf(0.0, fire - CAMP_DRAIN * wx_mult * dt)
		if bool(input.get("gather", false)) and not hidden:
			gather += dt_ms
			if gather >= GATHER_MS:
				gather = 0.0
				logs += 1
				ev.append({"type": "gathered"})
		else:
			gather = 0.0
		if fire <= 0.0:
			out += dt_ms
			if out >= OUT_GRACE_MS:
				return _finish(ev, _dark_by(), "fire")
		else:
			out = 0.0
		# Ysolde works the tent: while you hide she creeps out (2 -> 1), takes a log from the pile (1 -> 0) and then looks in (0 -> caught).
		if hidden:
			if y.fwd.step(dt_ms * TENT_PACE * speed, _keen(_base)):
				y.dist -= 1
				if y.dist == 1:
					ev.append({"type": "creep", "id": "ysolde"})
				elif y.dist == 0:
					if logs > 0:
						logs -= 1
					else:
						fire = maxf(0.0, fire - FUEL_STEAL)
					ev.append({"type": "stolen", "id": "ysolde"})
				else:
					return _finish(ev, "ysolde", "tent")
		elif y.dist < 2 and y.back.step(dt_ms * BACK_PACE * speed, _keen(_base)):
			y.dist += 1
			ev.append({"type": "backoff", "id": "ysolde", "dist": y.dist})
		for h in [v, q]:
			if _edge_step(h, dt_ms, ev):
				return _finish(ev, String(h.id), "edge")

	if elapsed >= D.WATCH_MS:
		over = "win"
		ev.append({"type": "win"})
	return ev


## Player actions: the heat lamp, a canister, a log on the fire. True when it did something.
func act(kind: String, a := {}) -> bool:
	if over != "":
		return false
	if kind == "lamp" and watch == 1 and (fuel > 0.0 or lamp):
		lamp = not lamp
		return true
	if kind == "can" and watch == 1 and cans.has(int(a.get("i", -1))):
		cans.erase(int(a["i"]))
		fuel = minf(100.0, fuel + CAN_FUEL)
		return true
	if kind == "log" and watch == 2 and logs > 0 and not hidden:
		logs -= 1
		fire = minf(100.0, fire + LOG_FUEL)
		return true
	return false


# --- admin (NightWatchAdmin: the game's admin_* hooks call these) ------------------------------------------------------------------

func hunter_ids() -> Array:
	return D.active_hunters(watch)


func admin_set_level(id: String, n: int) -> void:
	n = clampi(n, 0, NightWatchModesData.MAX_AI)
	if watch == 2 and id == "verrine":
		_verrine_at = n
		v.lvl = n
		v.on = n > 0
	elif watch == 2 and id == "quenelle":
		_quenelle_at = n
		q.lvl = n
		q.on = n > 0
	elif id == hunter or (watch == 2 and id == "ysolde"):
		_base = n


## Put a hunter at a step of her approach: "far" (3 steps out), "step 2", "step 1", "at the edge" (0). Ysolde: the trees (2), out of them (1), the log pile (0).
## Wynelle's place is how far the cold has got (her chill).
func admin_place(id: String, place: String) -> void:
	var dist: int = int({"far": 3, "step 2": 2, "step 1": 1, "at the edge": 0}.get(place, 3))
	if id == "wynelle" and watch == 1:
		chill = [5.0, 40.0, 70.0, 95.0][3 - int(dist)]
	elif id == "ysolde" and watch == 2:
		y.dist = clampi(int(dist), 0, 2) if int(dist) < 3 else 2
	elif watch == 0 and id == "verrine":
		v.dist = int(dist)
		v.at_ms = 0.0
		v.leave = 0.0
	elif watch == 2 and (id == "verrine" or id == "quenelle"):
		var h = v if id == "verrine" else q
		h.dist = int(dist)
		h.at_ms = 0.0
		h.push = 0.0
		h.lost = 0.0


## The rooftop's door she is at: "L" the stair door or "R" the hatch.
func admin_set_side(side: String) -> void:
	if watch == 0 and (side == "L" or side == "R"):
		v.side = side
		v.at_ms = 0.0
		v.leave = 0.0


## Set one of the watch's meters or switches: oil, lantern (bool as 0/1), warm, fuel, chill, fire, logs, mood, rain (force a squall / shower now: 1, end it: 0), can (a canister now),
## bus (jump to the bus's start). Returns true when the key applies to this watch.
func admin_set(key: String, value) -> bool:
	match key:
		"oil":
			if watch == 0:
				oil = clampf(float(value), 0.0, 100.0)
				return true
		"lantern":
			if watch == 0:
				lantern = bool(value)
				relight = 0.0
				if lantern:
					gust = GUST_MS
				return true
		"warm":
			if watch == 1:
				warm = clampf(float(value), 0.0, 100.0)
				return true
		"fuel":
			if watch == 1:
				fuel = clampf(float(value), 0.0, 100.0)
				return true
		"chill":
			if watch == 1:
				chill = clampf(float(value), 0.0, 99.0)
				return true
		"fire":
			if watch == 2:
				fire = clampf(float(value), 0.0, 100.0)
				out = 0.0
				return true
		"logs":
			if watch == 2:
				logs = maxi(0, int(value))
				return true
		"mood":
			if watch == 2 and ["calm", "bold", "shy"].has(String(value)):
				mood_kind = String(value)
				mood_left = MOOD_EVERY_MS
				return true
		"rain":
			if not weather.is_empty():
				weather["on"] = bool(value)
				weather["t"] = 0.0
				return true
		"can":
			if watch == 1 and cans.size() < MAX_CANS:
				for i in 3:
					if not cans.has(i):
						cans.append(i)
						return true
		"bus":
			if watch == 1:
				elapsed = maxf(elapsed, D.WATCH_MS - D.BUS_MS)
				return true
	return false
