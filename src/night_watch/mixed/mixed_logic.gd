class_name MixedLogic
extends RefCounted

## Mixed Shift's rules: a port of createMixedGame in the 2D game's modes/mixed/mixed-logic.js, number for number. A drawn roster of threats of different types
## (counter, watched, monitor, path, vent, winder) run by a small pacing director; every threat gives a tell before it can kill and has an answer. No scene, no
## input: the shift scene calls the setters (set_door, set_vent, light_vent, set_wind, set_monitor, set_room) and step(dt_ms), and draws the events. Three seeded
## streams (director, threats, feints) from NightWatchMulberry, so the same seed and inputs give the 2D game's night, event for event.
## step() returns events (type): step / appear / turned / gone / answered / arrive / tell / pulse / kill / stop / echo / feint / mood / moodtell / beat / spike /
## strain / doorshut / ventshut / ventopen / ventstrain / hum / wound / chaos / hour / rotate / win. An action of a threat has `a` (its number) and `beat`.
## (The 2D `cue` events are a pure function of these and are not generated: the scene plays sounds straight from the events.)

var seed_value := 0
var diff: Dictionary
var endless := false
var chaos := false
var breather_ms: Array
var dir_rng: NightWatchMulberry
var th_rng: NightWatchMulberry
var fx_rng: NightWatchMulberry
var roster: Array = []
var s: Dictionary = {}
var seal_max := 0.0


# --- the seeded draws (module level in 2D) -------------------------------------------------------------------------------------

static func jitter(ms: float, rng: NightWatchMulberry) -> float:
	var k := MixedData.JITTER
	return ms * (1.0 - k + 2.0 * k * rng.next())


static func _jitter_spread(base: float, spread: float, rng: NightWatchMulberry) -> float:
	var k := clampf(spread, 0.0, 0.9)
	return base * (1.0 - k + 2.0 * k * rng.next())


static func between(range_ms: Array, r: float) -> float:
	return float(range_ms[0]) + (float(range_ms[1]) - float(range_ms[0])) * r


## The tell a threat gives before it can kill: the difficulty's, scaled by its mood, never below the floor (nor the preset's minimum).
static func tell_for(d: Dictionary, mood: String, u := 0.5) -> float:
	var raw := roundf(float(d["tellMs"]) * float(MixedData.MOOD_TELL.get(mood, 1.0)) * (1.0 + MixedData.TELL_JITTER * (2.0 * u - 1.0)))
	return maxf(MixedData.TELL_FLOOR_MS, maxf(float(d.get("minTellMs", 0.0)), raw))


static func tension_floor_at(t: float) -> float:
	if t < MixedData.TENSION_FLOOR_FROM:
		return 0.0
	var k := clampf((t - MixedData.TENSION_FLOOR_FROM) / (MixedData.NIGHT_MS - MixedData.TENSION_FLOOR_FROM), 0.0, 1.0)
	return float(MixedData.TENSION_FLOOR[0]) + (float(MixedData.TENSION_FLOOR[1]) - float(MixedData.TENSION_FLOOR[0])) * k


## The night's roster, drawn with one seeded generator; always at least `minTypes` types, never more than `newMax` newcomers or MAX_WALKERS walkers.
static func draw_roster(seed_number: int, d: Dictionary, gen := 0) -> Array:
	var r := NightWatchMulberry.new(((seed_number ^ 0x524f5354) + gen * 0x9e3779b1) & 0xFFFFFFFF)
	var rng_range: Array = (MixedData.ENDLESS_RAMP["rosterByGen"] as Array)[mini(gen, (MixedData.ENDLESS_RAMP["rosterByGen"] as Array).size() - 1)] if bool(d.get("endless", false)) else d["roster"]
	var must: Array = d.get("must", [])
	var n := maxi(must.size(), int(rng_range[0]) + int(floor(r.next() * (int(rng_range[1]) - int(rng_range[0]) + 1))))
	var bag := []
	for p in MixedData.POOL:
		bag.append(p["id"])
	var i := bag.size() - 1
	while i > 0:
		var j := int(floor(r.next() * (i + 1)))
		var tmp = bag[i]
		bag[i] = bag[j]
		bag[j] = tmp
		i -= 1
	var kind := func(id) -> String: return String(MixedData.pool_entry(String(id))["type"])
	var types_of := func(ids: Array) -> Dictionary:
		var t := {}
		for id in ids:
			t[kind.call(id)] = true
		return t
	var allowed := func(have: Array, id) -> bool:
		var t: String = kind.call(id)
		var count := func(set: Array) -> int:
			var c := 0
			for x in have:
				if set.has(kind.call(x)):
					c += 1
			return c
		return not (MixedData.NEW_TYPES.has(t) and count.call(MixedData.NEW_TYPES) >= int(d.get("newMax", MixedData.NEW_TYPES.size()))) \
			and not (MixedData.WALKER_TYPES.has(t) and count.call(MixedData.WALKER_TYPES) >= MixedData.MAX_WALKERS)
	var pick: Array = must.duplicate()
	for id in bag:
		if pick.size() >= n:
			break
		if not pick.has(id) and allowed.call(pick, id):
			pick.append(id)
	var guard := 0
	while (types_of.call(pick) as Dictionary).size() < int(d.get("minTypes", 3)) and guard < 8:
		guard += 1
		var have: Dictionary = types_of.call(pick)
		var at := pick.size() - 1
		var k := pick.size() - 1
		while k >= 0:
			var same := 0
			for x in pick:
				if kind.call(x) == kind.call(pick[k]):
					same += 1
			if same > 1:
				at = k
				break
			k -= 1
		var rest := []
		for idx in pick.size():
			if idx != at:
				rest.append(pick[idx])
		var add = null
		for id in bag:
			if not have.has(kind.call(id)) and allowed.call(rest, id):
				add = id
				break
		if add == null:
			break
		pick[at] = add
	var out := []
	for p in MixedData.POOL:
		if pick.has(p["id"]):
			out.append(p["id"])
	return out


## A threat's whole state as plain data. `k` is its place in the roster (it staggers the first moves).
static func new_threat(def: Dictionary, rng: NightWatchMulberry, d: Dictionary, toggles := 0, k := 0) -> Dictionary:
	var type := String(def["type"])
	var th := {
		"id": def["id"], "type": type, "mood": MixedData.MOODS[int(floor(rng.next() * MixedData.MOODS.size()))],
		"moodLeft": 0.0, "moodCue": 0.0,
		"active": false, "armed": false, "armedMs": 0.0, "armedAt": -1.0, "tellOn": false, "tellNeed": 0.0, "side": "", "pulse": 0.0, "giveMs": 0.0, "wait": 0.0,
		"mem": {"L": 0, "R": 0, "T": 0} if type == "vent" else {"L": 0, "R": 0},
		"route": [], "routeId": "", "start": 0, "i": 0, "seen": 0.0, "c": 0.0, "hot": false, "grace": 0.0, "span": 0.0, "present": false, "steps": 0, "pend": 0, "idle": 0.0,
		"idleMax": 0.0, "decay": 0.0, "seenToggles": toggles, "dwell": 0.0, "flinch": false, "rewound": false, "tune": 1.0, "windMs": 0.0, "stopped": false, "boxRoom": "", "hum": 0.0,
	}
	th["moodLeft"] = between([MixedData.MOOD_MIN_MS, MixedData.MOOD_MAX_MS], rng.next())
	th["moodCue"] = between(MixedData.MOOD_CUE_MS, rng.next())
	if type == "counter":
		th["grace"] = jitter(float(MixedData.TIMING["counter"]["graceMs"]), rng)
		th["span"] = jitter(float(MixedData.TIMING["counter"]["spanMs"]), rng)
		th["active"] = true
	elif type == "monitor":
		th["wait"] = jitter(float(MixedData.TIMING["monitor"]["arriveMs"]), rng) + k * 1500.0
	elif type == "winder":
		th["boxRoom"] = MixedData.BOX_ROOMS[int(floor(rng.next() * MixedData.BOX_ROOMS.size()))]
		th["span"] = jitter(float(MixedData.TUNE["spanMs"]), rng)
		th["hum"] = float(MixedData.TUNE["humMs"][0])
	else:
		th["wait"] = jitter(float(d["startMs"]), rng) + k * 2500.0
	return th


## The spikes of a night: each at a jittered time inside its own slot, never in the first hour, ending END_CLEAR_MS before dawn.
static func plan_spikes(rng: NightWatchMulberry, d: Dictionary) -> Array:
	var sp: Array = d["spikes"]
	var count := int(sp[0]) + int(floor(rng.next() * (int(sp[1]) - int(sp[0]) + 1)))
	var start := MixedData.SPIKE_FIRST_MS + 8000.0
	var end_ms := MixedData.NIGHT_MS - MixedData.END_CLEAR_MS - float(MixedData.SPIKE_LEN_MS[1]) - 6000.0
	var width := (end_ms - start) / count
	var breather: Array = d.get("breather", MixedData.BREATHER_MS)
	var out := []
	for k in count:
		var length := roundf(between(MixedData.SPIKE_LEN_MS, rng.next()))
		var room := width - length - float(breather[1]) - 2000.0
		out.append({"at": roundf(start + k * width + rng.next() * room), "len": length})
	return out


static func first_endless_spike(rng: NightWatchMulberry) -> Dictionary:
	var at := roundf(MixedData.SPIKE_FIRST_MS + 8000.0 + rng.next() * 0.8 * MixedData.HOUR_MS)
	return {"at": at, "len": roundf(between(MixedData.SPIKE_LEN_MS, rng.next()))}


# --- the game ----------------------------------------------------------------------------------------------------------------

func _init(seed_number := 1, difficulty = 1) -> void:
	seed_value = seed_number
	diff = MixedData.difficulty_of(difficulty)
	endless = bool(diff.get("endless", false))
	chaos = bool(diff.get("chaos", false))
	breather_ms = diff.get("breather", MixedData.BREATHER_MS)
	dir_rng = NightWatchMulberry.new((seed_number ^ 0x44495243) & 0xFFFFFFFF)
	th_rng = NightWatchMulberry.new((seed_number ^ 0x54485254) & 0xFFFFFFFF)
	fx_rng = NightWatchMulberry.new((seed_number ^ 0x46585f31) & 0xFFFFFFFF)
	roster = draw_roster(seed_number, diff)
	var plan: Array = [first_endless_spike(dir_rng)] if endless else plan_spikes(dir_rng, diff)
	seal_max = float(MixedData.ENDLESS_SEAL["max"]) if endless else MixedData.SEAL_MAX
	var vents := {}
	for k in MixedData.VENT_KEYS:
		vents[k] = {"shut": false, "want": false, "held": 0.0, "linger": 0.0, "cool": 0.0, "flash": 0.0}
	s = {"diff": diff["id"], "elapsed": 0.0, "over": "", "by": "", "cool": 0.0, "lock": "", "actSeq": 0, "sinceAct": 0.0,
		"beat": "lull", "beatLeft": between(MixedData.BEAT_LEN["lull"], dir_rng.next()), "tension": 0.3, "plan": plan, "spikeIdx": 0, "spikeEnd": 0.0, "warned": false,
		"feintLeft": between(MixedData.FEINT_MS["lull"], fx_rng.next()),
		"seal": seal_max, "door": {"L": {"shut": false, "want": false, "held": 0.0, "cool": 0.0}, "R": {"shut": false, "want": false, "held": 0.0, "cool": 0.0}},
		"ventSeal": MixedData.VENT_SEAL_MAX, "vent": vents, "lamp": {"cool": 0.0}, "wind": false,
		"mon": {"up": false, "room": MixedData.CAM_ROOMS[0], "stay": 0.0, "toggles": 0}, "roster": roster, "threats": {}}
	var k := 0
	for id in roster:
		(s["threats"] as Dictionary)[id] = new_threat(MixedData.pool_entry(String(id)), th_rng, diff, 0, k)
		k += 1
	if chaos or endless:
		s["chaos"] = {"hr": 0, "at": -1.0, "kind": "", "until": 0.0, "strain": 0.0, "flicker": 0.0, "boxfast": 0.0, "room": "", "n": 0}
	if endless:
		s["run"] = {"gen": 0, "rotateAt": float(MixedData.ENDLESS_RAMP["rotateMs"]), "budget": float(MixedData.ENDLESS_SEAL["budget"])}


func hour_of() -> int:
	return int(floor(float(s["elapsed"]) / MixedData.HOUR_MS))


## The numbers in force now: the shift's own, except in Endless where the pace and the tell ramp up by the hour.
func live() -> Dictionary:
	if not endless:
		return diff
	var hr := hour_of()
	var d := diff.duplicate()
	d["speed"] = MixedData.endless_pace(hr)
	d["tellMs"] = MixedData.endless_tell(hr)
	return d


func list() -> Array:
	var out := []
	for id in roster:
		out.append(s["threats"][id])
	return out


func threat(id: String) -> Dictionary:
	return s["threats"].get(id, {})


# --- shared helpers ------------------------------------------------------------------------------------------------------------

func _quiet() -> bool:
	return String(s["beat"]) == "breather"


func _can_act() -> bool:
	return float(s["cool"]) <= 0.0 and not _quiet()


func _time_runs(th: Dictionary) -> bool:
	return not _quiet() and (String(s["lock"]) == "" or String(s["lock"]) == String(th["id"]))


func _speed_of(th: Dictionary) -> float:
	return float(MixedData.BEAT_RATE[s["beat"]]) * (0.8 + 0.5 * float(s["tension"])) * float(MixedData.MOOD_SPEED[th["mood"]]) * float(live()["speed"])


func _grace_ok() -> bool:
	return float(s["elapsed"]) >= float(diff["graceMs"])


func _observed(room: String) -> bool:
	return bool(s["mon"]["up"]) and String(s["mon"]["room"]) == room


func _act(ev: Array, events: Array) -> void:
	s["cool"] = MixedData.COOLDOWN_MS
	s["actSeq"] = int(s["actSeq"]) + 1
	s["sinceAct"] = 0.0
	for e in events:
		var x: Dictionary = (e as Dictionary).duplicate()
		x["t"] = s["elapsed"]
		x["a"] = s["actSeq"]
		x["beat"] = s["beat"]
		ev.append(x)


func _scare(d: float) -> void:
	s["tension"] = clampf(float(s["tension"]) + d, 0.0, 1.0)


func _side_weights(th: Dictionary) -> Dictionary:
	var out := {}
	for k in th["mem"]:
		out[k] = maxf(0.2, 1.0 / (1.0 + 0.8 * float(th["mem"][k])))
	return out


func _remember(th: Dictionary, side: String) -> void:
	if side != "":
		th["mem"][side] = mini(6, int(th["mem"][side]) + 1)


func _choose_route(th: Dictionary) -> void:
	var type := String(th["type"])
	var table: Array = []
	if type == "vent":
		table = MixedData.VENT_ROUTES
	elif type == "winder":
		for r in MixedData.ROUTES:
			if (r["rooms"] as Array).has(th["boxRoom"]):
				table.append(r)
	else:
		table = MixedData.ROUTES
	var w := _side_weights(th)
	var weights := []
	var total := 0.0
	for r in table:
		weights.append(float(w[r["side"]]))
		total += float(w[r["side"]])
	var x := th_rng.next() * total
	var k := 0
	while k < table.size() - 1 and x >= float(weights[k]):
		x -= float(weights[k])
		k += 1
	var r2: Dictionary = table[k]
	var at: int = (r2["rooms"] as Array).find(th["boxRoom"])
	th["start"] = at if type == "winder" and at >= 0 and at <= (r2["rooms"] as Array).size() - 3 else 0
	th["routeId"] = r2["id"]
	th["route"] = (r2["rooms"] as Array).slice(int(th["start"]))
	th["i"] = 0
	th["seen"] = 0.0
	th["flinch"] = false


func vent_spot_of(th: Dictionary) -> int:
	for r in MixedData.VENT_ROUTES:
		if String(r["id"]) == String(th["routeId"]):
			var spots: Array = r["spots"]
			return int(spots[int(th["i"])]) if int(th["i"]) < spots.size() else 0
	return 0


func _gate_shut(th: Dictionary) -> bool:
	return bool(s["vent"][th["side"]]["shut"]) if String(th["type"]) == "vent" else bool(s["door"][th["side"]]["shut"])


func _arm(th: Dictionary, side: String) -> void:
	s["lock"] = th["id"]
	th["armed"] = true
	th["armedMs"] = 0.0
	th["armedAt"] = -1.0
	th["tellOn"] = false
	th["giveMs"] = 0.0
	th["side"] = side
	th["pulse"] = 0.0
	th["tellNeed"] = tell_for(live(), String(th["mood"]), th_rng.next())
	if String(th["type"]) == "vent":
		if float(s["ventSeal"]) < MixedData.VENT_RESERVE:
			s["ventSeal"] = MixedData.VENT_RESERVE
	elif side != "" and float(s["seal"]) < MixedData.SEAL_RESERVE:
		if endless:
			var g := minf(MixedData.SEAL_RESERVE - float(s["seal"]), float(s["run"]["budget"]))
			s["seal"] = float(s["seal"]) + g
			s["run"]["budget"] = float(s["run"]["budget"]) - g
		else:
			s["seal"] = MixedData.SEAL_RESERVE
	_scare(-0.15)


func _start_tell(th: Dictionary, ev: Array, rearm := false) -> void:
	th["tellOn"] = true
	th["armedMs"] = 0.0
	th["armedAt"] = s["elapsed"]
	th["pulse"] = float(MixedData.PULSE_MS[MixedData.TELL_KIND[th["type"]]][0])
	ev.append({"type": "tell", "id": th["id"], "kind": th["type"], "side": th["side"], "lead": th["tellNeed"], "rearm": rearm, "t": s["elapsed"]})


func _pulses(th: Dictionary, ev: Array, dt: float, level: float) -> void:
	var kind: String = MixedData.TELL_KIND[th["type"]]
	var p: Array = MixedData.PULSE_MS[kind]
	var period := float(p[0]) + (float(p[1]) - float(p[0])) * clampf(level, 0.0, 1.0)
	th["pulse"] = float(th["pulse"]) + dt
	if float(th["pulse"]) >= period:
		th["pulse"] = float(th["pulse"]) - period
		ev.append({"type": "pulse", "id": th["id"], "kind": kind, "side": th["side"], "level": level, "armed": th["armed"], "t": s["elapsed"]})


func _kill(th: Dictionary, ev: Array) -> bool:
	var lead := float(s["elapsed"]) - float(th["armedAt"])
	if lead < MixedData.TELL_FLOOR_MS:
		return false
	_act(ev, [{"type": "kill", "id": th["id"], "kind": th["type"], "side": th["side"], "lead": lead, "tellAt": th["armedAt"], "need": th["tellNeed"]}])
	s["over"] = "caught"
	s["by"] = th["id"]
	return true


func _send_away(th: Dictionary, ev: Array, how: String) -> void:
	var side := String(th["side"])
	th["armed"] = false
	th["tellOn"] = false
	th["armedMs"] = 0.0
	th["giveMs"] = 0.0
	th["pulse"] = 0.0
	if String(s["lock"]) == String(th["id"]):
		s["lock"] = ""
	_remember(th, side)
	th["active"] = false
	th["present"] = false
	th["steps"] = 0
	th["pend"] = 0
	th["i"] = 0
	th["seen"] = 0.0
	th["dwell"] = 0.0
	th["side"] = ""
	th["flinch"] = false
	th["rewound"] = false
	if String(th["type"]) == "winder" and how == "wind":
		th["stopped"] = false
		th["wait"] = 0.0
	else:
		th["wait"] = jitter(float(MixedData.TIMING[th["type"]]["restMs"]), th_rng)
	_scare(-0.25)
	_act(ev, [{"type": "answered", "id": th["id"], "kind": th["type"], "how": how, "side": side}, {"type": "gone", "id": th["id"]}])


# --- doors and vents -----------------------------------------------------------------------------------------------------------

func _step_doors(dt: float, ev: Array) -> void:
	var open := 0
	var strained: bool = s.has("chaos") and float(s["chaos"]["strain"]) > 0.0
	var hold_ms: float = float(MixedData.CHAOS_EVENTS["strain"]["holdMs"]) if strained else MixedData.DOOR_HOLD_MS
	for side in ["L", "R"]:
		var d: Dictionary = s["door"][side]
		if float(d["cool"]) > 0.0:
			d["cool"] = maxf(0.0, float(d["cool"]) - dt)
		if bool(d["shut"]):
			d["held"] = float(d["held"]) + dt
			s["seal"] = maxf(0.0, float(s["seal"]) - dt)
			if float(d["held"]) >= hold_ms or float(s["seal"]) <= 0.0:
				d["shut"] = false
				d["want"] = false
				d["held"] = 0.0
				d["cool"] = MixedData.POP_COOL_MS
				ev.append({"type": "strain", "side": side, "t": s["elapsed"]})
		elif bool(d["want"]) and float(d["cool"]) <= 0.0 and float(s["seal"]) >= MixedData.SEAL_MIN_TO_SHUT:
			d["shut"] = true
			d["held"] = 0.0
			ev.append({"type": "doorshut", "side": side, "t": s["elapsed"]})
		if not bool(d["shut"]):
			open += 1
	if open > 0:
		var rate: float = (float(MixedData.ENDLESS_SEAL["regen"]) if endless else MixedData.SEAL_REGEN) * (float(MixedData.CHAOS_EVENTS["strain"]["regen"]) if strained else 1.0)
		var gain := rate * dt * (open / 2.0)
		if endless:
			gain = minf(gain, minf(float(s["run"]["budget"]), maxf(0.0, seal_max - float(s["seal"]))))
			s["run"]["budget"] = float(s["run"]["budget"]) - gain
		s["seal"] = minf(seal_max, float(s["seal"]) + gain)


func _step_vents(dt: float, ev: Array) -> void:
	s["lamp"]["cool"] = maxf(0.0, float(s["lamp"]["cool"]) - dt)
	var open := 0
	for key in MixedData.VENT_KEYS:
		var d: Dictionary = s["vent"][key]
		if float(d["cool"]) > 0.0:
			d["cool"] = maxf(0.0, float(d["cool"]) - dt)
		if float(d["flash"]) > 0.0:
			d["flash"] = maxf(0.0, float(d["flash"]) - dt)
		if bool(d["shut"]):
			s["ventSeal"] = maxf(0.0, float(s["ventSeal"]) - dt)
			if bool(d["want"]):
				d["held"] = float(d["held"]) + dt
			else:
				d["linger"] = maxf(0.0, float(d["linger"]) - dt)
			if float(d["held"]) >= MixedData.VENT_HOLD_MS or float(s["ventSeal"]) <= 0.0:
				d["shut"] = false
				d["want"] = false
				d["held"] = 0.0
				d["linger"] = 0.0
				d["cool"] = MixedData.VENT_POP_COOL_MS
				ev.append({"type": "ventstrain", "key": key, "t": s["elapsed"]})
			elif not bool(d["want"]) and float(d["linger"]) <= 0.0:
				d["shut"] = false
				d["held"] = 0.0
				ev.append({"type": "ventopen", "key": key, "t": s["elapsed"]})
		elif bool(d["want"]) and float(d["cool"]) <= 0.0 and float(s["ventSeal"]) >= MixedData.VENT_MIN_TO_SEAL:
			d["shut"] = true
			d["held"] = 0.0
			d["linger"] = 0.0
			ev.append({"type": "ventshut", "key": key, "t": s["elapsed"]})
		if not bool(d["shut"]):
			open += 1
	if open > 0:
		s["ventSeal"] = minf(MixedData.VENT_SEAL_MAX, float(s["ventSeal"]) + MixedData.VENT_SEAL_REGEN * dt * (float(open) / MixedData.VENT_KEYS.size()))


## Hold a vent's control (want = true) to seal it; let go and it stays shut VENT_LINGER_MS more. Returns whether it is shut.
func set_vent(key: String, want_in: bool) -> bool:
	if not s["vent"].has(key) or String(s["over"]) != "":
		return false
	var d: Dictionary = s["vent"][key]
	if want_in == bool(d["want"]):
		return bool(d["shut"])
	d["want"] = want_in
	if want_in:
		if bool(d["shut"]):
			d["linger"] = 0.0
		elif float(d["cool"]) <= 0.0 and float(s["ventSeal"]) >= MixedData.VENT_MIN_TO_SEAL:
			d["shut"] = true
			d["held"] = 0.0
			d["linger"] = 0.0
	elif bool(d["shut"]):
		d["linger"] = MixedData.VENT_LINGER_MS
	return bool(d["shut"])


## The vent light: a short pale flash down a vent (one lamp for the three). Shows the crawler if she is near that vent or at it, and she backs off.
## Returns {ok, why, seen}.
func light_vent(key: String) -> Dictionary:
	if not s["vent"].has(key) or String(s["over"]) != "":
		return {"ok": false, "why": "over", "seen": []}
	var d: Dictionary = s["vent"][key]
	if bool(d["shut"]):
		return {"ok": false, "why": "shut", "seen": []}
	if float(s["lamp"]["cool"]) > 0.0:
		return {"ok": false, "why": "cool", "seen": []}
	s["lamp"]["cool"] = MixedData.VENT_LIGHT_COOL_MS
	d["flash"] = MixedData.VENT_LIGHT_MS
	var seen := []
	for th in list():
		if String(th["type"]) != "vent":
			continue
		if (bool(th["armed"]) and String(th["side"]) == key) or (bool(th["active"]) and not bool(th["armed"]) and (MixedData.VENT_NEAR[key] as Array).has(vent_spot_of(th))):
			th["flinch"] = true
			seen.append(th["id"])
	return {"ok": true, "why": "", "seen": seen}


func _wind_jump() -> void:
	for t in list():
		if String(t["type"]) == "winder":
			if bool(s["wind"]) and bool(s["mon"]["up"]) and String(s["mon"]["room"]) != String(t["boxRoom"]):
				set_room(String(t["boxRoom"]))
			return


func set_wind(on: bool) -> void:
	if String(s["over"]) == "":
		s["wind"] = on
		_wind_jump()


func set_door(side: String, want_in: bool) -> bool:
	if not s["door"].has(side) or String(s["over"]) != "":
		return false
	var d: Dictionary = s["door"][side]
	d["want"] = want_in
	if not want_in:
		d["shut"] = false
		d["held"] = 0.0
	elif not bool(d["shut"]) and float(d["cool"]) <= 0.0 and float(s["seal"]) >= MixedData.SEAL_MIN_TO_SHUT:
		d["shut"] = true
		d["held"] = 0.0
	return bool(d["shut"])


func set_monitor(up: bool) -> void:
	if String(s["over"]) != "" or up == bool(s["mon"]["up"]):
		return
	s["mon"]["up"] = up
	s["mon"]["stay"] = 0.0
	s["mon"]["toggles"] = int(s["mon"]["toggles"]) + 1
	_wind_jump()


func set_room(room: String) -> void:
	if String(s["over"]) != "" or not MixedData.CAM_ROOMS.has(room) or room == String(s["mon"]["room"]):
		return
	s["mon"]["room"] = room
	s["mon"]["stay"] = 0.0


# --- the director --------------------------------------------------------------------------------------------------------------

func _next_idx() -> int:
	return 0 if endless else int(s["spikeIdx"])


func _start_beat(beat: String, ev: Array) -> void:
	s["beat"] = beat
	if beat == "breather":
		s["beatLeft"] = between(breather_ms, dir_rng.next())
	elif beat == "spike":
		s["beatLeft"] = float(s["plan"][_next_idx()]["len"])
	else:
		s["beatLeft"] = between(MixedData.BEAT_LEN[beat], dir_rng.next())
	ev.append({"type": "beat", "beat": beat, "tension": s["tension"], "t": s["elapsed"]})


func _end_spike(from_ms := -1.0) -> void:
	var from := float(s["elapsed"]) if from_ms < 0.0 else from_ms
	if endless:
		(s["plan"] as Array).pop_front()
		var gap := _jitter_spread(MixedData.endless_gap(hour_of()), 0.25, dir_rng)
		var at := roundf(from + float(MixedData.BREATHER_MS[1]) + gap)
		(s["plan"] as Array).append({"at": at, "len": roundf(between(MixedData.SPIKE_LEN_MS, dir_rng.next()))})
	s["spikeIdx"] = int(s["spikeIdx"]) + 1


func _step_director(dt: float, ev: Array) -> void:
	s["beatLeft"] = float(s["beatLeft"]) - dt
	var plan: Array = s["plan"]
	var nxt: Dictionary = plan[_next_idx()] if _next_idx() < plan.size() else {}
	var beat := String(s["beat"])
	if beat == "spike":
		if float(s["elapsed"]) >= float(s["spikeEnd"]) and String(s["lock"]) == "":
			ev.append({"type": "spike", "phase": "end", "t": s["elapsed"]})
			_end_spike()
			_start_beat("breather", ev)
	elif beat == "breather":
		if float(s["beatLeft"]) <= 0.0:
			_start_beat("lull", ev)
	else:
		if not nxt.is_empty() and not bool(s["warned"]) and float(s["elapsed"]) >= float(nxt["at"]) - MixedData.SPIKE_WARN_MS:
			s["warned"] = true
			ev.append({"type": "spike", "phase": "warn", "at": nxt["at"], "t": s["elapsed"]})
		if not nxt.is_empty() and float(s["elapsed"]) >= float(nxt["at"]) and String(s["lock"]) == "":
			s["warned"] = false
			s["spikeEnd"] = float(s["elapsed"]) + float(nxt["len"])
			_start_beat("spike", ev)
			ev.append({"type": "spike", "phase": "start", "t": s["elapsed"]})
			for th in list():
				if bool(th["active"]) and not bool(th["armed"]) and String(th["type"]) != "counter":
					th["wait"] = minf(float(th["wait"]), jitter(2500.0, dir_rng))
		elif float(s["beatLeft"]) <= 0.0:
			var last := float(s["elapsed"]) >= MixedData.TENSION_FLOOR_FROM
			var again := false
			if beat == "build" and float(s["tension"]) > 0.5:
				again = dir_rng.next() < (0.8 if last else 0.35)
			_start_beat("build" if beat == "lull" or again else "lull", ev)


func _step_feints(dt: float, ev: Array) -> void:
	var beat := String(s["beat"])
	if beat != "lull" and beat != "build":
		return
	s["feintLeft"] = float(s["feintLeft"]) - dt
	if float(s["feintLeft"]) > 0.0:
		return
	if String(s["lock"]) != "" or float(s["sinceAct"]) < 2500.0 or float(s["cool"]) > 0.0:
		s["feintLeft"] = 1000.0
		return
	var kind := "step" if fx_rng.next() < 0.5 else "glow"
	if kind == "step":
		ev.append({"type": "feint", "kind": kind, "room": MixedData.CAM_ROOMS[int(floor(fx_rng.next() * MixedData.CAM_ROOMS.size()))], "soft": true, "t": s["elapsed"]})
	else:
		ev.append({"type": "feint", "kind": kind, "side": "L" if fx_rng.next() < 0.5 else "R", "soft": true, "t": s["elapsed"]})
	s["feintLeft"] = between(MixedData.FEINT_MS[beat], fx_rng.next())


# --- one threat ----------------------------------------------------------------------------------------------------------------

func _step_mood(th: Dictionary, dt: float, ev: Array) -> void:
	th["moodLeft"] = float(th["moodLeft"]) - dt
	if float(th["moodLeft"]) <= 0.0:
		var others := []
		for m in MixedData.MOODS:
			if m != th["mood"]:
				others.append(m)
		th["mood"] = others[int(floor(th_rng.next() * others.size()))]
		th["moodLeft"] = between([MixedData.MOOD_MIN_MS, MixedData.MOOD_MAX_MS], th_rng.next())
		ev.append({"type": "mood", "id": th["id"], "mood": th["mood"], "t": s["elapsed"]})
	th["moodCue"] = float(th["moodCue"]) - dt
	if float(th["moodCue"]) <= 0.0:
		th["moodCue"] = between(MixedData.MOOD_CUE_MS, th_rng.next())
		if bool(th["active"]) or bool(th["present"]):
			ev.append({"type": "moodtell", "id": th["id"], "mood": th["mood"], "t": s["elapsed"]})


func _step_walker(th: Dictionary, dt: float, ev: Array) -> void:
	var type := String(th["type"])
	var watched := type == "watched"
	if bool(th["armed"]):
		_step_armed_at_gate(th, dt, ev)
		return
	if not bool(th["active"]):
		if not _time_runs(th):
			return
		th["wait"] = float(th["wait"]) - dt * _speed_of(th)
		if float(th["wait"]) > 0.0 or not _can_act():
			return
		_choose_route(th)
		th["active"] = true
		th["dwell"] = 0.0
		th["wait"] = jitter(float(MixedData.TIMING[type]["stepMs"]), th_rng)
		var e := {"type": "step", "id": th["id"], "kind": type, "room": (th["route"] as Array)[0], "from": "", "spawn": true, "base": MixedData.TIMING[type]["stepMs"], "next": th["wait"]}
		if type == "vent":
			e["spot"] = vent_spot_of(th)
		_act(ev, [e])
		return
	if type == "winder" and bool(th["rewound"]):
		if _can_act():
			_send_away(th, ev, "wind")
		return
	var route: Array = th["route"]
	var room := String(route[int(th["i"])])
	var hall := String(route[route.size() - 2])
	var seen_now := _observed(room)
	th["dwell"] = float(th["dwell"]) + dt
	if type == "vent" and bool(th["flinch"]) and float(th["dwell"]) >= MixedData.MIN_DWELL_MS and _can_act():
		th["flinch"] = false
		th["i"] = 0
		th["dwell"] = 0.0
		th["wait"] = jitter(float(MixedData.TIMING["vent"]["stepMs"]), th_rng)
		for r in MixedData.VENT_ROUTES:
			if String(r["id"]) == String(th["routeId"]):
				_remember(th, String(r["side"]))
		_scare(-0.1)
		_act(ev, [{"type": "turned", "id": th["id"], "kind": "vent", "room": room, "to": room, "how": "light", "spot": 0}])
		return
	if room == hall and type == "path" and _time_runs(th):
		if seen_now:
			th["seen"] = float(th["seen"]) + dt
			if float(th["seen"]) >= MixedData.CHOKE_MS and _can_act():
				var to := maxi(0, int(th["i"]) - 2)
				th["i"] = to
				th["seen"] = 0.0
				th["dwell"] = 0.0
				th["wait"] = jitter(float(MixedData.TIMING["path"]["stepMs"]), th_rng)
				_remember(th, MixedData.door_side(String(route[route.size() - 1])))
				_scare(-0.1)
				_act(ev, [{"type": "turned", "id": th["id"], "kind": type, "room": room, "to": route[to]}])
				return
		else:
			th["seen"] = 0.0
	if seen_now and (watched or String(th["mood"]) == "shy"):
		return
	if not _time_runs(th):
		return
	th["wait"] = float(th["wait"]) - dt * _speed_of(th)
	if float(th["wait"]) > 0.0 or float(th["dwell"]) < MixedData.MIN_DWELL_MS or not _can_act():
		return
	var nxt := String(route[int(th["i"]) + 1])
	var side := MixedData.gate_side(nxt)
	if side != "":
		if String(s["lock"]) != "" or not _grace_ok():
			return
		th["i"] = int(th["i"]) + 1
		_arm(th, side)
		_act(ev, [{"type": "arrive", "id": th["id"], "kind": type, "room": nxt, "from": room, "side": side}])
		if not _gate_shut(th):
			_start_tell(th, ev)
		return
	th["i"] = int(th["i"]) + 1
	th["dwell"] = 0.0
	th["wait"] = jitter(float(MixedData.TIMING[type]["stepMs"]), th_rng)
	var e2 := {"type": "step", "id": th["id"], "kind": type, "room": nxt, "from": room, "base": MixedData.TIMING[type]["stepMs"], "next": th["wait"]}
	if type == "vent":
		e2["spot"] = vent_spot_of(th)
	_act(ev, [e2])


func _step_armed_at_gate(th: Dictionary, dt: float, ev: Array) -> void:
	var type := String(th["type"])
	if type == "vent" and bool(th["flinch"]) and _can_act():
		_send_away(th, ev, "light")
		return
	if type == "winder" and bool(th["rewound"]) and _can_act():
		_send_away(th, ev, "wind")
		return
	if _gate_shut(th):
		th["tellOn"] = false
		th["armedMs"] = 0.0
		th["giveMs"] = float(th["giveMs"]) + dt
		if float(th["giveMs"]) >= MixedData.GIVE_UP_MS and _can_act():
			_send_away(th, ev, "seal" if type == "vent" else "door")
		return
	th["giveMs"] = 0.0
	if not bool(th["tellOn"]):
		_start_tell(th, ev, true)
		return
	th["armedMs"] = float(th["armedMs"]) + dt
	_pulses(th, ev, dt, float(th["armedMs"]) / float(th["tellNeed"]))
	if float(th["armedMs"]) >= float(th["tellNeed"]) and _can_act():
		_kill(th, ev)


func _step_winder(th: Dictionary, dt: float, ev: Array) -> void:
	var winding: bool = bool(s["wind"]) and bool(s["mon"]["up"]) and String(s["mon"]["room"]) == String(th["boxRoom"]) and String(s["over"]) == ""
	th["windMs"] = float(th["windMs"]) + dt if winding else 0.0
	var was := bool(th["stopped"])
	var before := float(th["tune"])
	if not was and _time_runs(th):
		var boxfast := float(MixedData.CHAOS_EVENTS["boxfast"]["factor"]) if s.has("chaos") and float(s["chaos"]["boxfast"]) > 0.0 else 1.0
		th["tune"] = maxf(0.0, float(th["tune"]) - dt * _speed_of(th) * boxfast / float(th["span"]))
	if winding:
		th["tune"] = minf(1.0, float(th["tune"]) + float(MixedData.TUNE["windPerSec"]) * dt / 1000.0)
		if was and float(th["tune"]) >= float(MixedData.TUNE["restartAt"]):
			th["stopped"] = false
			th["hum"] = 0.0
			th["span"] = jitter(float(MixedData.TUNE["spanMs"]), th_rng)
			ev.append({"type": "wound", "id": th["id"], "room": th["boxRoom"], "was": was, "t": s["elapsed"]})
			if bool(th["active"]) or bool(th["armed"]):
				th["rewound"] = true
			else:
				th["wait"] = 0.0
		elif not was and before < 1.0 and float(th["tune"]) >= 1.0:
			th["span"] = jitter(float(MixedData.TUNE["spanMs"]), th_rng)
	if not bool(th["stopped"]):
		if float(s["elapsed"]) < float(diff["graceMs"]):
			th["tune"] = maxf(float(th["tune"]), float(MixedData.TUNE["graceFloor"]))
		if float(th["tune"]) <= 0.0005 and float(th["windMs"]) == 0.0:
			if _can_act() and _grace_ok() and _time_runs(th):
				th["tune"] = 0.0
				th["stopped"] = true
				th["wait"] = jitter(float(MixedData.TIMING["winder"]["crankyMs"]), th_rng)
				th["hum"] = 0.0
				_act(ev, [{"type": "stop", "id": th["id"], "kind": "winder", "room": th["boxRoom"], "next": th["wait"]}])
			else:
				th["tune"] = 0.0006
		th["hum"] = float(th["hum"]) - dt
		if float(th["hum"]) <= 0.0 and not bool(th["stopped"]):
			var h: Array = MixedData.TUNE["humMs"]
			th["hum"] = float(h[0]) + (float(h[1]) - float(h[0])) * clampf(1.0 - float(th["tune"]), 0.0, 1.0)
			ev.append({"type": "hum", "id": th["id"], "room": th["boxRoom"], "tune": th["tune"], "t": s["elapsed"]})
	if bool(th["stopped"]) or bool(th["active"]) or bool(th["armed"]):
		_step_walker(th, dt, ev)


func _step_counter(th: Dictionary, dt: float, ev: Array) -> void:
	var C: Dictionary = MixedData.TIMING["counter"]
	var holding: bool = bool(s["mon"]["up"]) and float(s["mon"]["stay"]) >= float(th["grace"])
	var sp := _speed_of(th)
	var span_eff := float(th["span"]) / maxf(0.3, sp if sp != 0.0 else 0.3)
	if holding and not _quiet():
		th["c"] = minf(1.0, float(th["c"]) + dt / span_eff)
	elif not holding:
		th["c"] = maxf(0.0, float(th["c"]) - float(C["calmDecay"]) * dt / float(th["span"]))
	if float(th["c"]) > 0.0:
		th["hot"] = true
	elif bool(th["hot"]):
		th["hot"] = false
		th["grace"] = jitter(float(C["graceMs"]), th_rng)
		th["span"] = jitter(float(C["spanMs"]), th_rng)
	if not bool(th["armed"]):
		if float(th["c"]) >= float(C["armAt"]) and holding:
			if String(s["lock"]) == "" and _can_act() and _grace_ok():
				_arm(th, "")
				_act(ev, [{"type": "arrive", "id": th["id"], "kind": "counter", "room": s["mon"]["room"], "from": "", "side": ""}])
				_start_tell(th, ev)
			else:
				th["c"] = minf(float(th["c"]), float(C["armAt"]))
		elif float(th["c"]) >= float(C["cueAt"]):
			_pulses(th, ev, dt, float(th["c"]))
		return
	if not holding:
		if not _can_act():
			return
		th["armed"] = false
		th["tellOn"] = false
		th["armedMs"] = 0.0
		if String(s["lock"]) == String(th["id"]):
			s["lock"] = ""
		th["grace"] = jitter(float(C["graceMs"]), th_rng)
		th["span"] = jitter(float(C["spanMs"]), th_rng)
		_scare(-0.25)
		_act(ev, [{"type": "answered", "id": th["id"], "kind": "counter", "how": "switch" if bool(s["mon"]["up"]) else "monitor", "side": ""}])
		return
	th["armedMs"] = float(th["armedMs"]) + dt
	_pulses(th, ev, dt, maxf(float(th["c"]), float(th["armedMs"]) / float(th["tellNeed"])))
	if float(th["c"]) >= 1.0 and float(th["armedMs"]) >= float(th["tellNeed"]) and _can_act():
		_kill(th, ev)


func _step_monitor_gated(th: Dictionary, dt: float, ev: Array) -> void:
	var M: Dictionary = MixedData.TIMING["monitor"]
	var fresh := int(s["mon"]["toggles"]) - int(th["seenToggles"])
	th["seenToggles"] = s["mon"]["toggles"]
	if not bool(th["present"]):
		if not _time_runs(th):
			return
		th["wait"] = float(th["wait"]) - dt * _speed_of(th)
		if float(th["wait"]) > 0.0 or not _can_act() or String(s["lock"]) != "" or not _grace_ok():
			return
		var w := _side_weights(th)
		var side := "L" if th_rng.next() * (float(w["L"]) + float(w["R"])) < float(w["L"]) else "R"
		th["present"] = true
		th["active"] = true
		th["side"] = side
		th["steps"] = 0
		th["pend"] = 0
		th["idle"] = 0.0
		th["decay"] = 0.0
		th["giveMs"] = 0.0
		th["idleMax"] = jitter(float(M["idleLeaveMs"]), th_rng)
		_act(ev, [{"type": "arrive", "id": th["id"], "kind": "monitor", "room": "office", "from": "", "side": side, "quiet": true}])
		return
	if bool(th["armed"]):
		_step_armed_at_gate(th, dt, ev)
		return
	if _quiet():
		th["pend"] = 0
		return
	th["pend"] = mini(1, int(th["pend"]) + fresh)
	if bool(s["door"][th["side"]]["shut"]):
		th["giveMs"] = float(th["giveMs"]) + dt
		if float(th["giveMs"]) >= MixedData.GIVE_UP_MS and _can_act():
			_send_away(th, ev, "door")
			return
	else:
		th["giveMs"] = 0.0
	if not _time_runs(th):
		return
	th["idle"] = float(th["idle"]) + dt
	th["decay"] = float(th["decay"]) + dt
	if int(th["pend"]) > 0 and _can_act():
		th["pend"] = 0
		th["idle"] = 0.0
		th["decay"] = 0.0
		if int(th["steps"]) < int(M["stepsToArm"]):
			th["steps"] = int(th["steps"]) + 1
			_act(ev, [{"type": "echo", "id": th["id"], "kind": "monitor", "level": th["steps"], "side": th["side"]}])
		elif String(s["lock"]) == "" and _grace_ok():
			_arm(th, String(th["side"]))
			_act(ev, [{"type": "arrive", "id": th["id"], "kind": "monitor", "room": "office", "from": "office", "side": th["side"]}])
			if not bool(s["door"][th["side"]]["shut"]):
				_start_tell(th, ev)
		else:
			th["pend"] = 1
		return
	if float(th["decay"]) >= float(M["decayMs"]) and int(th["steps"]) > 0:
		th["steps"] = int(th["steps"]) - 1
		th["decay"] = 0.0
	if float(th["idle"]) >= float(th["idleMax"]) and _can_act():
		_send_away(th, ev, "steady")


# --- CHAOS and ENDLESS ---------------------------------------------------------------------------------------------------------

func _apply_floor() -> void:
	if endless:
		s["tension"] = maxf(float(s["tension"]), MixedData.endless_floor_at(float(s["elapsed"])))
	elif float(s["elapsed"]) >= MixedData.TENSION_FLOOR_FROM:
		s["tension"] = maxf(float(s["tension"]), tension_floor_at(float(s["elapsed"])))


func _step_hours(ev: Array) -> void:
	var c: Dictionary = s["chaos"]
	while int(c["hr"]) < hour_of():
		c["hr"] = int(c["hr"]) + 1
		if endless:
			s["run"]["budget"] = MixedData.endless_budget(int(c["hr"]))
			ev.append({"type": "hour", "hour": c["hr"], "t": s["elapsed"]})
		var roll := false
		if chaos:
			roll = int(c["hr"]) >= int(MixedData.CHAOS_HOURS[0]) and int(c["hr"]) <= int(MixedData.CHAOS_HOURS[1])
		else:
			roll = endless and int(c["hr"]) >= int(MixedData.ENDLESS_RAMP["eventFrom"]) and dir_rng.next() < float(MixedData.ENDLESS_RAMP["eventP"])
		if roll and float(c["at"]) < 0.0:
			_schedule_event(float(c["hr"]) * MixedData.HOUR_MS)


func _schedule_event(hour_start: float) -> void:
	var c: Dictionary = s["chaos"]
	var have := {}
	for t in list():
		have[t["type"]] = true
	var kinds := []
	for k in MixedData.CHAOS_ORDER:
		var needs := String(MixedData.CHAOS_EVENTS[k]["needs"])
		if needs == "" or have.has(needs):
			kinds.append(k)
	var total := 0.0
	for k in kinds:
		total += float(MixedData.CHAOS_EVENTS[k]["weight"])
	var x := dir_rng.next() * total
	var kind: String = kinds[0]
	for k in kinds:
		if x < float(MixedData.CHAOS_EVENTS[k]["weight"]):
			kind = k
			break
		x -= float(MixedData.CHAOS_EVENTS[k]["weight"])
	c["kind"] = kind
	c["until"] = hour_start + MixedData.HOUR_MS
	c["at"] = maxf(hour_start + 5000.0 + dir_rng.next() * (MixedData.HOUR_MS - 15000.0), float(diff["graceMs"]))
	if float(c["at"]) >= float(c["until"]):
		c["kind"] = ""
		c["at"] = -1.0


func _fx_running() -> bool:
	var c: Dictionary = s["chaos"]
	return float(c["strain"]) > 0.0 or float(c["flicker"]) > 0.0 or float(c["boxfast"]) > 0.0


func _step_chaos(dt: float, ev: Array) -> void:
	var c: Dictionary = s["chaos"]
	for k in ["strain", "flicker", "boxfast"]:
		if float(c[k]) > 0.0:
			c[k] = maxf(0.0, float(c[k]) - dt)
			if float(c[k]) == 0.0:
				ev.append({"type": "chaos", "kind": k, "phase": "end", "t": s["elapsed"]})
	if float(c["at"]) < 0.0 or float(s["elapsed"]) < float(c["at"]):
		return
	if float(s["elapsed"]) >= float(c["until"]):
		c["at"] = -1.0
		c["kind"] = ""
		return
	if String(s["lock"]) != "" or _fx_running() or String(s["over"]) != "":
		return
	if String(c["kind"]) == "decoy" and (float(s["sinceAct"]) < MixedData.DECOY_QUIET_MS or float(s["cool"]) > 0.0 or (String(s["beat"]) != "lull" and String(s["beat"]) != "build")):
		return
	_fire_event(String(c["kind"]), ev)
	c["at"] = -1.0
	c["kind"] = ""
	c["n"] = int(c["n"]) + 1


func _fire_event(kind: String, ev: Array) -> void:
	var c: Dictionary = s["chaos"]
	var e := {"type": "chaos", "kind": kind, "phase": "start", "t": s["elapsed"]}
	if kind == "mood":
		var l := list()
		var th: Dictionary = l[int(floor(dir_rng.next() * roster.size()))] if not l.is_empty() else {}
		if th.is_empty():
			return
		var others := []
		for m in MixedData.MOODS:
			if m != th["mood"]:
				others.append(m)
		th["mood"] = others[int(floor(dir_rng.next() * others.size()))]
		th["moodLeft"] = between([MixedData.MOOD_MIN_MS, MixedData.MOOD_MAX_MS], dir_rng.next())
		e["id"] = th["id"]
		e["mood"] = th["mood"]
	elif kind == "wake":
		var found: Dictionary = {}
		for t in list():
			if String(t["type"]) == "vent" and not bool(t["active"]) and not bool(t["armed"]):
				found = t
				break
		if found.is_empty():
			return
		found["wait"] = minf(float(found["wait"]), jitter(2500.0, dir_rng))
		e["id"] = found["id"]
	elif kind == "decoy":
		var types := []
		for t in MixedData.DECOY_TYPES:
			for x in list():
				if String(x["type"]) == t:
					types.append(t)
					break
		var tkind: String = "path"
		if not types.is_empty():
			tkind = types[int(floor(dir_rng.next() * types.size()))]
		var side := ""
		if tkind == "vent":
			side = MixedData.VENT_KEYS[int(floor(dir_rng.next() * MixedData.VENT_KEYS.size()))]
		else:
			side = "L" if dir_rng.next() < 0.5 else "R"
		e["tkind"] = tkind
		e["side"] = side
		s["cool"] = maxf(float(s["cool"]), MixedData.DECOY_QUIET_MS)
	elif kind == "flicker":
		c["room"] = MixedData.CAM_ROOMS[int(floor(dir_rng.next() * MixedData.CAM_ROOMS.size()))]
		c["flicker"] = float(MixedData.CHAOS_EVENTS["flicker"]["ms"])
		e["room"] = c["room"]
	elif kind == "strain":
		c["strain"] = float(MixedData.CHAOS_EVENTS["strain"]["ms"])
	elif kind == "boxfast":
		c["boxfast"] = float(MixedData.CHAOS_EVENTS["boxfast"]["ms"])
	ev.append(e)


## Endless: every three hours the roster is drawn again, at a moment no deadly tell is running. Whoever stays keeps her state.
func _step_rotation(ev: Array) -> void:
	var r: Dictionary = s["run"]
	if float(s["elapsed"]) < float(r["rotateAt"]) or String(s["lock"]) != "":
		return
	for t in list():
		if bool(t["armed"]):
			return
	r["gen"] = int(r["gen"]) + 1
	r["rotateAt"] = float(r["rotateAt"]) + float(MixedData.ENDLESS_RAMP["rotateMs"])
	var nxt := draw_roster(seed_value, diff, int(r["gen"]))
	var removed := []
	var added := []
	for id in roster:
		if not nxt.has(id):
			removed.append(id)
	for id in nxt:
		if not roster.has(id):
			added.append(id)
	var old: Dictionary = (s["threats"] as Dictionary).duplicate()
	(s["threats"] as Dictionary).clear()
	roster.clear()
	roster.append_array(nxt)
	var k := 0
	for id in added:
		old[id] = new_threat(MixedData.pool_entry(String(id)), th_rng, live(), int(s["mon"]["toggles"]), k)
		k += 1
	for id in nxt:
		s["threats"][id] = old[id]
	ev.append({"type": "rotate", "gen": r["gen"], "added": added, "removed": removed, "t": s["elapsed"]})


# --- the step ------------------------------------------------------------------------------------------------------------------

func step(dt: float) -> Array:
	if String(s["over"]) != "":
		return []
	var ev := []
	s["elapsed"] = float(s["elapsed"]) + dt
	s["sinceAct"] = float(s["sinceAct"]) + dt
	s["cool"] = maxf(0.0, float(s["cool"]) - dt)
	if float(s["elapsed"]) >= MixedData.NIGHT_MS and not endless:
		s["over"] = "win"
		ev.append({"type": "win", "t": s["elapsed"]})
		return ev
	if s.has("chaos"):
		_step_hours(ev)
	_apply_floor()
	if bool(s["mon"]["up"]):
		s["mon"]["stay"] = float(s["mon"]["stay"]) + dt
	_step_doors(dt, ev)
	_step_vents(dt, ev)
	_step_director(dt, ev)
	_step_feints(dt, ev)
	if s.has("chaos"):
		_step_chaos(dt, ev)
	if endless:
		_step_rotation(ev)
	for th in list():
		if String(s["over"]) != "":
			break
		_step_mood(th, dt, ev)
		match String(th["type"]):
			"counter":
				_step_counter(th, dt, ev)
			"monitor":
				_step_monitor_gated(th, dt, ev)
			"winder":
				_step_winder(th, dt, ev)
			_:
				_step_walker(th, dt, ev)
	if String(s["lock"]) == "" and float(s["sinceAct"]) > 6000.0:
		_scare(dt / 60000.0)
	_apply_floor()
	return ev


# --- what the scene draws ------------------------------------------------------------------------------------------------------

## Who is standing in each camera room (walkers on their route, not yet at a door or vent; the vent crawler is in the vent run).
func occupancy() -> Dictionary:
	var out := {}
	for r in MixedData.CAM_ROOMS:
		out[r] = []
	for th in list():
		var t := String(th["type"])
		if (MixedData.WALKER_TYPES.has(t) or t == "vent") and bool(th["active"]) and not bool(th["armed"]) and not (th["route"] as Array).is_empty():
			var room := String((th["route"] as Array)[int(th["i"])])
			if out.has(room):
				(out[room] as Array).append(th["id"])
	return out


func hour_reached() -> int:
	return hour_of() if endless else mini(6, hour_of())


func next_spike() -> Dictionary:
	var plan: Array = s["plan"]
	return plan[_next_idx()] if _next_idx() < plan.size() else {}
