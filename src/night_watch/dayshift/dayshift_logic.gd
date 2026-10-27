class_name DayshiftLogic
extends RefCounted

## Salvage Run's rules: a port of createDayGame (and the shop helpers) in the 2D game's modes/dayshift/dayshift-logic.js, number for number. No scene,
## no input: the shift scene feeds step() the doors, lights and the rack (hold on a piece) and draws what happens. Draws from NightWatchMulberry (the 2D
## mulberry32), so the same seed gives the same shift as the 2D game, event for event.
##
## step(dt_ms, input) with input {work, target (rack slot, -1 none), doorL, doorR, lightL, lightR} returns the events (`type`): item / expire /
## salvage {slot, value} / close / repelled / warned {id} / knock / window / gone {id=ysolde} / out / caught {by} / win / short {money, quota}.

const NIGHT_MS := 270000.0
const T := {
	"comboLevel": 6, "comboMs": 2200.0,
	"atDoorMs": 5200.0, "leaveMs": 450.0, "startDist": 3,
	"atDoorByWeekMs": [8000.0, 7000.0, 6200.0, 5600.0, 5200.0],
	"noisePerSec": 14.0, "noiseDecayPerSec": 10.0, "loud": 40.0, "uneasy": 20.0,
	"powerBase": 0.10 / NightWatchData.TIME_SCALE, "powerPerDevice": 0.07 / NightWatchData.TIME_SCALE, "outAttackMs": 9000.0,
	"slots": 4, "spawnMs": 11000.0, "firstSpawnMs": 2000.0, "expireMs": 30000.0,
	"windowGapMs": 42000.0, "windowGapPerLevelMs": 1800.0, "windowGapMinMs": 14000.0, "knockMs": 3000.0, "presentMs": 6000.0, "exposeMs": 1500.0,
	"knockMaxMs": 4200.0, "windowGapSpread": 0.3, "spawnSpread": 0.2, "firstSpawnSpread": 0.5, "leadSteps": 1,
}

var week_idx := 0
var rng: NightWatchMulberry
var upgrades: Array = []
var levels: Dictionary = {}
var infinite_power := false
var custom := false
var need := 0
var door_ms := 0.0
var s: Dictionary = {}


# --- the shop ---------------------------------------------------------------------------------------------------------------

static func total_cost(ids: Array) -> int:
	var sum := 0
	for id in ids:
		for u in DayshiftData.UPGRADES:
			if String(u["id"]) == String(id):
				sum += int(u["cost"])
	return sum


## Last week's surplus brought forward (only when you play on from one week to the next).
static func carry_from(money: int, quota: int) -> int:
	return maxi(0, mini(DayshiftData.CARRY_CAP, money - quota))


static func budget_for(week: int, carry := 0) -> int:
	return int(DayshiftData.BUDGET[clampi(week, 1, 5) - 1]) + maxi(0, mini(DayshiftData.CARRY_CAP, carry))


static func quota_for(week: int) -> int:
	return int(DayshiftData.QUOTA[clampi(week, 1, 5) - 1])


static func _is_upgrade(id: String) -> bool:
	for u in DayshiftData.UPGRADES:
		if String(u["id"]) == id:
			return true
	return false


## Whether a basket of upgrades can be bought with the day's budget (every id real, none twice).
static func can_buy(ids: Array, week: int, carry := 0) -> bool:
	var seen := {}
	for id in ids:
		if seen.has(id) or not _is_upgrade(String(id)):
			return false
		seen[id] = true
	return total_cost(ids) <= budget_for(week, carry)


## One click in the shop: toggles `id` in the basket. Returns the new basket, or null when it would go over the budget.
static func shop_toggle(owned: Array, id: String, week: int, carry := 0):
	var next := []
	if owned.has(id):
		for x in owned:
			if x != id:
				next.append(x)
	else:
		next = owned.duplicate()
		next.append(id)
	return next if can_buy(next, week, carry) else null


## What Ysolde hears at the glass: a light on, or salvaging. Not the noise meter and not the doors.
static func ysolde_hears(dev: Dictionary, working: int) -> bool:
	return bool(dev.get("lightL", false)) or bool(dev.get("lightR", false)) or working >= 0


static func active_hunters(week_index: int) -> Array:
	var out := []
	for id in DayshiftData.CAST:
		if int((DayshiftData.LEVELS[id] as Array)[mini(week_index, 4)]) > 0:
			out.append(id)
	return out


# --- draws ------------------------------------------------------------------------------------------------------------------

static func _jitter(base: float, spread: float, rng_in: NightWatchMulberry) -> float:
	var k := clampf(spread, 0.0, 0.9)
	return base * (1.0 - k + 2.0 * k * rng_in.next())


static func _jitter_floor(base: float, spread: float, rng_in: NightWatchMulberry, floor_ms: float) -> float:
	return maxf(floor_ms, _jitter(base, spread, rng_in))


func _spread_ms(ms: float, spread := 0.2) -> float:
	return ms * (1.0 - spread + 2.0 * spread * rng.next())


func _init(week: int, rng_in: NightWatchMulberry, opts := {}) -> void:
	week_idx = clampi(week, 1, 5) - 1
	rng = rng_in
	upgrades = opts.get("upgrades", [])
	levels = opts.get("levels", {})
	infinite_power = bool(opts.get("infinite_power", false))
	custom = bool(opts.get("custom", false))
	door_ms = float(T["atDoorMs"]) if custom else float((T["atDoorByWeekMs"] as Array)[week_idx])
	need = int(opts["quota"]) if opts.has("quota") else int(DayshiftData.QUOTA[week_idx])
	var stalker := func() -> Dictionary:
		return {"dist": int(T["startDist"]), "pacer": NightWatchMulberryPacer.new(rng), "atMs": 0.0, "leave": 0.0}
	s = {"elapsed": 0.0, "over": "", "by": "", "power": 100.0, "out": false, "outMs": 0.0, "noise": 0.0, "money": 0, "need": need,
		"items": [], "spawn": 0.0, "spawnAt": 0.0, "working": -1, "deck": {}, "lead": "",
		"ravelle": stalker.call(), "ceryth": stalker.call(),
		"ysolde": {"state": "away", "t": 0.0, "clock": 0.0, "gap": -1.0, "expose": 0.0, "stay": float(T["presentMs"]), "knock": float(T["knockMs"])},
		"dev": {"doorL": false, "doorR": false, "lightL": false, "lightR": false}, "dt": 0.0}
	# the variety draws, in this order, once: which deck, which door visitor leads, the wait for the first piece
	var total := 0
	for k in DayshiftData.DECKS:
		total += int(k["weight"])
	var r := rng.next() * total
	var pick: Dictionary = DayshiftData.DECKS[0]
	for k in DayshiftData.DECKS:
		r -= int(k["weight"])
		if r < 0.0:
			pick = k
			break
	s["deck"] = {"id": pick["id"], "left": []}
	var u := rng.next()
	if base_level("ravelle") > 0 and base_level("ceryth") > 0:
		s["lead"] = "ravelle" if u < 0.5 else "ceryth"
		var lead := String(s["lead"])
		var other := "ceryth" if lead == "ravelle" else "ravelle"
		s[lead]["dist"] = int(T["startDist"]) - int(T["leadSteps"])
		s[other]["dist"] = int(T["startDist"]) + int(T["leadSteps"])
	s["spawnAt"] = _jitter(float(T["firstSpawnMs"]), float(T["firstSpawnSpread"]), rng)


func has_upgrade(id: String) -> bool:
	return upgrades.has(id)


func base_level(id: String) -> int:
	if levels.has(id) and int(levels[id]) >= 0:
		return int(levels[id])
	return int((DayshiftData.LEVELS[id] as Array)[week_idx])


func level(id: String) -> int:
	var b := base_level(id)
	if b <= 0:
		return 0
	var noise := float(s["noise"])
	var bonus := 3 if noise >= float(T["loud"]) else (1 if noise >= float(T["uneasy"]) else 0)
	return maxi(1, mini(20, b + NightWatchData.ai_bump(NightWatchData.hour_index(float(s["elapsed"]))) + bonus - (2 if has_upgrade("soles") else 0)))


## The next piece off the deck; the deck is shuffled again when it is empty.
func _deal_kind() -> String:
	var deck: Dictionary = s["deck"]
	if (deck["left"] as Array).is_empty():
		var d: Dictionary = {}
		for k in DayshiftData.DECKS:
			if String(k["id"]) == String(deck["id"]):
				d = k
		var bag := []
		for kind in DayshiftData.ITEM_KINDS:
			for n in int(d[kind]):
				bag.append(kind)
		var i := bag.size() - 1
		while i > 0:
			var j := int(floor(rng.next() * (i + 1)))
			var tmp = bag[i]
			bag[i] = bag[j]
			bag[j] = tmp
			i -= 1
		deck["left"] = bag
	return String((deck["left"] as Array).pop_back())


func _spawn_item() -> Dictionary:
	var taken := {}
	for it in s["items"]:
		taken[int(it["slot"])] = true
	var free := []
	for i in int(T["slots"]):
		if not taken.has(i):
			free.append(i)
	if free.is_empty():
		return {}
	var kind := _deal_kind()
	var slot: int = free[mini(free.size() - 1, int(floor(rng.next() * free.size())))]
	var item := {"slot": slot, "kind": kind, "value": int(DayshiftData.ITEMS[kind]["value"]),
		"need": float(DayshiftData.ITEMS[kind]["ms"]) * (0.7 if has_upgrade("gloves") else 1.0), "progress": 0.0, "age": 0.0}
	(s["items"] as Array).append(item)
	return item


## A doorway visitor: closes in a step at a time on the random wait (held still by the light), then waits at the door. True when she gets in.
func _visitor(id: String, shut: bool, lit: bool, ev: Array) -> bool:
	var h: Dictionary = s[id]
	var dt := float(s["dt"])
	if int(h["dist"]) > 0:
		if not lit and (h["pacer"] as NightWatchMulberryPacer).step(dt, level(id)):
			h["dist"] = int(h["dist"]) - 1
			ev.append({"type": "close", "id": id, "dist": h["dist"]})
		return false
	if shut:
		h["atMs"] = 0.0
		h["leave"] = float(h["leave"]) + dt
		if float(h["leave"]) >= float(T["leaveMs"]):
			h["dist"] = 2
			h["leave"] = 0.0
			(h["pacer"] as NightWatchMulberryPacer).reset()
			ev.append({"type": "repelled", "id": id})
		return false
	h["leave"] = 0.0
	if not lit:
		h["atMs"] = float(h["atMs"]) + dt
	return float(h["atMs"]) >= door_ms


func _finish(ev: Array, by: String) -> Array:
	s["over"] = "caught"
	s["by"] = by
	ev.append({"type": "caught", "by": by})
	return ev


func step(dt_ms: float, input := {}) -> Array:
	if String(s["over"]) != "":
		return []
	var ev := []
	s["dt"] = dt_ms
	s["elapsed"] = float(s["elapsed"]) + dt_ms
	var dt := dt_ms / 1000.0
	var dev := {"doorL": false, "doorR": false, "lightL": false, "lightR": false}
	if not bool(s["out"]):
		dev = {"doorL": bool(input.get("doorL", false)), "doorR": bool(input.get("doorR", false)), "lightL": bool(input.get("lightL", false)), "lightR": bool(input.get("lightR", false))}
	s["dev"] = dev
	# Power: doors and lights draw it. At zero everything drops and someone arrives a few seconds later.
	if not bool(s["out"]):
		var doors := (1 if dev["doorL"] else 0) + (1 if dev["doorR"] else 0)
		var lights := (1 if dev["lightL"] else 0) + (1 if dev["lightR"] else 0)
		var draw := (float(T["powerBase"]) + float(T["powerPerDevice"]) * (doors * (0.5 if has_upgrade("hinges") else 1.0) + lights)) * (0.75 if has_upgrade("cell") else 1.0)
		if not infinite_power:
			s["power"] = maxf(0.0, float(s["power"]) - draw * dt)
		if float(s["power"]) <= 0.0:
			s["out"] = true
			ev.append({"type": "out"})
	else:
		s["outMs"] = float(s["outMs"]) + dt_ms
		if float(s["outMs"]) >= float(T["outAttackMs"]):
			return _finish(ev, "ravelle")
	# The rack: pieces turn up, wait, and are taken by holding on one. Salvaging is loud.
	s["noise"] = maxf(0.0, float(s["noise"]) - float(T["noiseDecayPerSec"]) * dt)
	s["spawn"] = float(s["spawn"]) + dt_ms
	if float(s["spawn"]) >= float(s["spawnAt"]):
		s["spawn"] = 0.0
		var it := _spawn_item()
		s["spawnAt"] = _jitter(float(T["spawnMs"]), float(T["spawnSpread"]), rng)
		if not it.is_empty():
			ev.append({"type": "item", "slot": it["slot"]})
	for item in (s["items"] as Array).duplicate():
		item["age"] = float(item["age"]) + dt_ms
		if float(item["age"]) >= float(T["expireMs"]):
			(s["items"] as Array).erase(item)
			ev.append({"type": "expire", "slot": item["slot"]})
	var target := {}
	for item in s["items"]:
		if int(item["slot"]) == int(input.get("target", -1)):
			target = item
			break
	s["working"] = int(target["slot"]) if bool(input.get("work", false)) and not target.is_empty() and not bool(s["out"]) else -1
	if int(s["working"]) >= 0:
		target["progress"] = float(target["progress"]) + dt_ms
		s["noise"] = minf(100.0, float(s["noise"]) + float(T["noisePerSec"]) * (0.5 if has_upgrade("bench") else 1.0) * dt + float(T["noiseDecayPerSec"]) * dt)
		if float(target["progress"]) >= float(target["need"]):
			(s["items"] as Array).erase(target)
			s["money"] = int(s["money"]) + int(target["value"])
			ev.append({"type": "salvage", "slot": target["slot"], "value": target["value"]})
	# Doorway visitors.
	var before := ev.size()
	if _visitor("ravelle", bool(dev["doorL"]), bool(dev["lightL"]), ev):
		return _finish(ev, "ravelle")
	if _visitor("ceryth", bool(dev["doorR"]), bool(dev["lightR"]), ev):
		return _finish(ev, "ceryth")
	# Working together: when one is turned away from a shut door she warns the other, who (once both are keen) is that much nearer a step.
	for e in ev.slice(before):
		if String(e["type"]) != "repelled":
			continue
		var other := "ceryth" if String(e["id"]) == "ravelle" else "ravelle"
		if int(s[other]["dist"]) > 0 and level("ravelle") >= int(T["comboLevel"]) and level("ceryth") >= int(T["comboLevel"]):
			(s[other]["pacer"] as NightWatchMulberryPacer).skip(float(T["comboMs"]))
			ev.append({"type": "warned", "id": other})
	# Ysolde: a knock, then she stays at the window; be quiet while she does.
	var u: Dictionary = s["ysolde"]
	var ul := level("ysolde")
	if ul > 0:
		var ust := String(u["state"])
		if ust == "away":
			u["clock"] = float(u["clock"]) + dt_ms
			if float(u["gap"]) < 0.0:
				u["gap"] = _jitter(maxf(float(T["windowGapMinMs"]), float(T["windowGapMs"]) - ul * float(T["windowGapPerLevelMs"])), float(T["windowGapSpread"]), rng)
			if float(u["clock"]) >= float(u["gap"]):
				u["state"] = "knock"
				u["t"] = 0.0
				u["clock"] = 0.0
				u["gap"] = -1.0
				var lo := float(T["knockMs"])
				var hi := float(T["knockMaxMs"])
				u["knock"] = _jitter_floor((lo + hi) / 2.0, (hi - lo) / (lo + hi), rng, lo)
				ev.append({"type": "knock", "id": "ysolde"})
		elif ust == "knock":
			u["t"] = float(u["t"]) + dt_ms
			if float(u["t"]) >= float(u["knock"]):
				u["state"] = "here"
				u["t"] = 0.0
				u["expose"] = 0.0
				u["stay"] = _spread_ms(float(T["presentMs"]))
				ev.append({"type": "window", "id": "ysolde"})
		else:
			u["t"] = float(u["t"]) + dt_ms
			var loud := ysolde_hears(dev, int(s["working"]))
			u["expose"] = float(u["expose"]) + dt_ms if loud else maxf(0.0, float(u["expose"]) - dt_ms)
			if float(u["expose"]) >= float(T["exposeMs"]):
				return _finish(ev, "ysolde")
			if float(u["t"]) >= float(u["stay"]):
				u["state"] = "away"
				u["t"] = 0.0
				u["expose"] = 0.0
				u["gap"] = -1.0
				ev.append({"type": "gone", "id": "ysolde"})
	# 6 AM: bring the quota in.
	if float(s["elapsed"]) >= NIGHT_MS:
		s["over"] = "win" if int(s["money"]) >= need else "short"
		ev.append({"type": String(s["over"]), "money": s["money"], "quota": need})
	return ev
