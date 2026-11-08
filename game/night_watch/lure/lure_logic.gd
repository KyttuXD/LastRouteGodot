class_name LureLogic
extends RefCounted

## Dead Air rules, ported from the original game's Dead Air rules (same numbers, same draws in the same order, so the same
## seed plays the same shift as the 2D game). Pure: no nodes.
##
## One real hunter (Xivvy) crawls through the building toward your office vents. The other three (Ferryn, Briselle, Mavrine) are phantoms:
## harmless, but each one knocks out a system now and then.
##   Climate (Solyth and Wynelle): the building has a temperature. It drifts down while Wynelle is in (up when only Solyth is). Below 60 F
##     Wynelle slowly freezes the office; from 95 F Solyth slowly cooks it. A heater and a fan fix the number, strain the air while they
##     run, and Mavrine breaks them.
##   Lure   play a sound in a camera room and Xivvy heads there instead (needs Audio; short cooldown).
##   Seals  close a vent opening to turn her away. Sealed vents strain the air, which builds stress.
##   Reboot a broken system takes six seconds to bring back, and is offline meanwhile.
## Stress at 100 and the air gives out. Xivvy in an open vent for 5.2 s and she gets in.
## `step(dt_ms, input)` returns the events (dictionaries with a `type`). input: {"watch": room the monitor shows, or ""}.

const VARIETY := {
	"xivvyTempo": 0.25, "phantomTempo": 0.2, "phantomRestSpread": 0.3, "sameSideAgain": 0.25,
	"wakeStep": 8000.0, "startTempSpread": 3.0, "driftSpread": 0.1,
}
## Night 1 is a tutorial: only maintenance errors, the hunter is asleep.
const LEVELS := [0, 3, 5, 7, 9, 11]
const MAX_ACTIVE := 5
const CLIMATE_LEVELS := {"solyth": [0, 0, 0, 0, 0, 12], "wynelle": [0, 0, 0, 5, 8, 13]}
const CLIMATE := {
	"start": 70.0, "cold": 60.0, "hot": 100.0, "driftPerSec": 0.2, "driftPerHour": 0.12,
	"heaterPerSec": 0.9, "fanPerSec": 0.9, "applianceStress": 0.9,
	"coldPerDeg": 0.1, "heatPerDeg": 0.2, "recoverPerSec": 2.0,
}
const PHANTOM_LEVELS := {
	"ferryn": [2, 3, 5, 7, 9, 0], "briselle": [0, 0, 3, 5, 8, 10], "mavrine": [0, 0, 0, 0, 3, 9],
}
## What else a phantom's visit may take besides her own system, per night: [system, chance].
const PHANTOM_EXTRA := {
	"ferryn": [[], [], [["audio", 0.3]], [["audio", 0.3], ["vent", 0.1]], [["audio", 0.4], ["vent", 0.1]], [["audio", 0.45], ["vent", 0.35]]],
	"briselle": [[], [], [], [["cams", 0.35]], [["cams", 0.35]], [["cams", 0.45], ["vent", 0.3]]],
	"mavrine": [[], [], [], [], [["audio", 0.4]], [["audio", 0.45], ["cams", 0.4]]],
}
const T := {
	"phantomPace": 0.3, "phantomFirstMs": 4000.0, "phantomCoolMs": 10000.0,
	"lureStrainEvery": 2, "lurePace": 1.8, "officeWaitMs": 5200.0, "retreatMs": 2000.0, "lureMs": 12000.0, "lureCoolMs": 7000.0,
	"rebootMs": 6000.0, "phantomShowMs": 4000.0,
	"stressPerSealSec": 1.2, "stressBrokenSec": 3.0, "stressDecaySec": 2.0,
}
## The air on a Custom Night (never on N1-N6).
const CUSTOM_AIR := {"sealSec": 1.2, "brokenSec": 2.8, "brokenPerLevel": 0.02, "applianceStress": 0.8, "decaySec": 2.1}
const PHANTOM_IDS := ["ferryn", "briselle", "mavrine"]


## The air's rates for a game: the story nights' or the Custom Night's, with Mavrine's level for the slider.
static func air_rates(is_custom: bool, mavrine_level := 0) -> Dictionary:
	if is_custom:
		return {"seal": CUSTOM_AIR["sealSec"], "broken": float(CUSTOM_AIR["brokenSec"]) + float(CUSTOM_AIR["brokenPerLevel"]) * clampf(mavrine_level, 0, 20),
			"appliance": CUSTOM_AIR["applianceStress"], "decay": CUSTOM_AIR["decaySec"]}
	return {"seal": T["stressPerSealSec"], "broken": T["stressBrokenSec"], "appliance": CLIMATE["applianceStress"], "decay": T["stressDecaySec"]}


## Who is on the floor on a level (0-based).
static func active_hunters(level_idx: int) -> Array:
	var i := mini(level_idx, 5)
	var out := []
	for id in LureData.CAST:
		var lv := 0
		if id == "xivvy":
			lv = int(LEVELS[i])
		elif CLIMATE_LEVELS.has(id):
			lv = int(CLIMATE_LEVELS[id][i])
		else:
			lv = int(PHANTOM_LEVELS[id][i])
		if lv > 0:
			out.append(id)
	return out


# --- the night --------------------------------------------------------------------------------------------------------------

var n := 0                      # 0-based night
var rng: NightWatchStream
var choice_rng: NightWatchStream
var vr: NightWatchStream
var lvl := 0
var phantoms_on := true
var focus := 0.8
var infinite_stress := false
var is_custom := false
var phantom_levels = null       # Dictionary or null
var climate := {"solyth": 0, "wynelle": 0}
var air := {}

var elapsed := 0.0
var over := ""
var by := ""
var stress := 0.0
var killer := {}                # room, pacer, side, atMs, target, lureLeft, tempo, dist
var systems := {}
var temp := 70.0
var drift_x := 1.0
var heater_on := false
var fan_on := false
var cold := 0.0
var heat := 0.0
var seals := {"L": false, "R": false}
var lure_cool := 0.0
var lures := 0
var pending: Array = []
var phantom := {}               # {id, room, t} while a phantom is drawn on a camera, else {}
var phantom_ai := {}
var has_climate := false
var has_fan := false
## Admin (NightWatchAdmin): god mode sends a killer back instead of ending the night; the hunters' wait clocks run at this multiple (1.0 = the 2D numbers).
var god := false
var hunter_speed := 1.0
var _dist := {}


## opts: night, rng, choice_rng (default rng), var_rng, level (-1 = the night's), phantom_levels, climate_levels, phantoms (true),
## focus (0.8), infinite_stress, custom.
func _init(opts: Dictionary) -> void:
	n = clampi(int(opts.get("night", 1)), 1, 6) - 1
	rng = opts["rng"]
	choice_rng = opts.get("choice_rng", rng)
	vr = NightWatchStream.variety_of(rng, opts.get("var_rng", null))   # before the night's first draw
	var level_in := int(opts.get("level", -1))
	lvl = level_in if level_in >= 0 else int(LEVELS[n])
	phantoms_on = bool(opts.get("phantoms", true))
	focus = float(opts.get("focus", 0.8))
	infinite_stress = bool(opts.get("infinite_stress", false))
	is_custom = bool(opts.get("custom", false))
	phantom_levels = opts.get("phantom_levels", null)
	_dist = {"officeL": LureData.distances_to("officeL"), "officeR": LureData.distances_to("officeR")}
	killer = {"room": "lobby", "pacer": NightWatchPacer.new(rng), "side": "L" if choice_rng.next() < 0.5 else "R", "atMs": 0.0,
		"target": "", "lureLeft": 0.0, "tempo": NightWatchStream.tempo(vr, VARIETY["xivvyTempo"]), "dist": {}}
	for name in ["audio", "cams", "vent", "heater", "fan"]:
		systems[name] = {"state": "ok", "t": 0.0}
	temp = CLIMATE["start"]
	for id in PHANTOM_IDS:
		var pacer := NightWatchPacer.new(rng)
		var cool := NightWatchStream.spread_ms(T["phantomFirstMs"], rng)
		phantom_ai[id] = {"pacer": pacer, "cool": cool, "tempo": NightWatchStream.tempo(vr, VARIETY["phantomTempo"])}
	var climate_in = opts.get("climate_levels", null)
	for id in ["solyth", "wynelle"]:
		if climate_in != null and (climate_in as Dictionary).has(id):
			climate[id] = int(climate_in[id])
		else:
			climate[id] = int(CLIMATE_LEVELS[id][n])
	has_climate = int(climate["solyth"]) > 0 or int(climate["wynelle"]) > 0
	has_fan = int(climate["solyth"]) > 0
	# who wakes first: with two or more phantoms on the floor, shuffle which one makes her first visit earlier and which later
	var awake := []
	for id in PHANTOM_IDS:
		if phantom_base(id) > 0:
			awake.append(id)
	if phantoms_on and awake.size() >= 2 and not vr.neutral:
		var slots := []
		for i in awake.size():
			slots.append((i - (awake.size() - 1) / 2.0) * float(VARIETY["wakeStep"]))
		for i in range(slots.size() - 1, 0, -1):
			var j := NightWatchStream.pick_index(vr, i + 1)
			var tmp = slots[i]
			slots[i] = slots[j]
			slots[j] = tmp
		for i in awake.size():
			(phantom_ai[awake[i]]["pacer"] as NightWatchPacer).skip(-float(slots[i]) * float(T["phantomPace"]))
	# the weather of the night
	if has_climate:
		temp = float(CLIMATE["start"]) + (2.0 * vr.next() - 1.0) * float(VARIETY["startTempSpread"])
		drift_x = NightWatchStream.tempo(vr, VARIETY["driftSpread"])
	air = air_rates(is_custom, phantom_base("mavrine"))


func phantom_base(id: String) -> int:
	if phantom_levels != null and (phantom_levels as Dictionary).has(id):
		return int(phantom_levels[id])
	return int(PHANTOM_LEVELS[id][n])


func online(system: String) -> bool:
	return String(systems[system]["state"]) == "ok"


func _goal() -> String:
	return "officeL" if killer["side"] == "L" else "officeR"


## Where she is heading: the lure while it lasts, otherwise her vent.
func _next_room() -> String:
	var lured: bool = float(killer["lureLeft"]) > 0.0 and String(killer["target"]) != ""
	var target: String = String(killer["target"]) if lured else _goal()
	var d: Dictionary
	if lured:
		if (killer["dist"] as Dictionary).is_empty():
			killer["dist"] = LureData.distances_to(String(killer["target"]))
		d = killer["dist"]
	else:
		d = _dist[_goal()]
	var room: String = killer["room"]
	var around := []
	for r in LureData.GRAPH.get(room, []):
		if r == "officeL" and (bool(seals["L"]) or target != "officeL"):
			continue
		if r == "officeR" and (bool(seals["R"]) or target != "officeR"):
			continue
		around.append(r)
	var closer := []
	for r in around:
		if int(d.get(r, 999)) < int(d.get(room, 999)):
			closer.append(r)
	var pool: Array = around
	if not closer.is_empty() and choice_rng.next() < (0.95 if float(killer["lureLeft"]) > 0.0 else focus):
		pool = closer
	if pool.is_empty():
		return room
	return String(pool[mini(pool.size() - 1, int(floor(choice_rng.next() * pool.size())))])


func _finish(ev: Array, who: String) -> Array:
	if god:   # admin: whoever would have ended it is sent back
		match who:
			"xivvy":
				killer["room"] = "storage"
				killer["atMs"] = 0.0
				(killer["pacer"] as NightWatchPacer).reset()
			"mavrine":
				stress = 40.0
			"wynelle":
				cold = 0.0
			"solyth":
				heat = 0.0
		return ev
	over = "caught"
	by = who
	ev.append({"type": "caught", "by": who})
	return ev


func _break(system: String) -> void:
	systems[system] = {"state": "broken", "t": 0.0}
	if system == "heater":
		heater_on = false
	if system == "fan":
		fan_on = false


## Advance by dt_ms. input: {"watch": room}. Returns the events.
func step(dt_ms: float, input := {}) -> Array:
	var ev := []
	if over != "":
		return ev
	var dt := dt_ms / 1000.0
	elapsed += dt_ms
	var hour := NightWatchData.hour_index(elapsed)
	ev.append_array(pending)
	pending = []
	lure_cool = maxf(0.0, lure_cool - dt_ms)
	var k := killer
	if float(k["lureLeft"]) > 0.0:
		k["lureLeft"] = float(k["lureLeft"]) - dt_ms
		if float(k["lureLeft"]) <= 0.0:
			k["target"] = ""
			k["dist"] = {}

	# systems finish rebooting
	for name in systems:
		var sys: Dictionary = systems[name]
		if sys["state"] == "reboot":
			sys["t"] = float(sys["t"]) + dt_ms
			if float(sys["t"]) >= float(T["rebootMs"]):
				sys["state"] = "ok"
				sys["t"] = 0.0
				ev.append({"type": "fixed", "system": name})

	# phantoms break things
	if phantoms_on:
		if not phantom.is_empty():
			phantom["t"] = float(phantom["t"]) + dt_ms
			if float(phantom["t"]) >= float(T["phantomShowMs"]):
				phantom = {}
		for id in PHANTOM_IDS:
			var ph: Dictionary = phantom_ai[id]
			ph["cool"] = maxf(0.0, float(ph["cool"]) - dt_ms)
			if float(ph["cool"]) <= 0.0 and (ph["pacer"] as NightWatchPacer).step(dt_ms * float(T["phantomPace"]) * float(ph["tempo"]) * hunter_speed, NightWatchData.effective_level(phantom_base(id), hour)):
				ph["cool"] = NightWatchStream.spread_ms(maxf(5000.0, float(T["phantomCoolMs"]) - n * 800.0), rng, VARIETY["phantomRestSpread"])
				ph["tempo"] = NightWatchStream.tempo(vr, VARIETY["phantomTempo"])
				var system: String = LureData.SYSTEM_OF[id]
				phantom = {"id": id, "room": LureData.ROOMS[int(floor(rng.next() * LureData.ROOMS.size()))], "t": 0.0}
				var targets := [system]
				if id == "mavrine" and has_climate:
					if int(climate["solyth"]) > 0 and int(climate["wynelle"]) > 0:
						targets.append_array(["heater", "fan"])
					else:
						targets.append("fan" if fan_on else "heater")
				for extra in PHANTOM_EXTRA[id][n]:
					if choice_rng.next() < float(extra[1]) and not targets.has(extra[0]):
						targets.append(extra[0])
				for t in targets:
					if online(t):
						_break(t)
						ev.append({"type": "broken", "system": t, "id": id})
				ev.append({"type": "phantom", "id": id, "room": phantom["room"]})

	# the climate
	if has_climate:
		var dir := -1.0 if int(climate["wynelle"]) > 0 else 1.0
		var drift: float = float(CLIMATE["driftPerSec"]) * drift_x * (1.0 + hour * float(CLIMATE["driftPerHour"])) * dir
		var push := 0.0
		if heater_on and online("heater"):
			push += float(CLIMATE["heaterPerSec"])
		if fan_on and online("fan"):
			push -= float(CLIMATE["fanPerSec"])
		temp = maxf(20.0, minf(130.0, temp + (drift + push) * dt))
		if int(climate["wynelle"]) > 0 and temp < float(CLIMATE["cold"]):
			cold = minf(100.0, cold + (float(CLIMATE["cold"]) - temp) * float(CLIMATE["coldPerDeg"]) * maxf(0.4, int(climate["wynelle"]) / 10.0) * dt)
		else:
			cold = maxf(0.0, cold - float(CLIMATE["recoverPerSec"]) * dt)
		if int(climate["solyth"]) > 0 and temp >= float(CLIMATE["hot"]) - 5.0:
			heat = minf(100.0, heat + (temp - (float(CLIMATE["hot"]) - 5.0)) * float(CLIMATE["heatPerDeg"]) * maxf(0.4, int(climate["solyth"]) / 10.0) * dt)
		else:
			heat = maxf(0.0, heat - float(CLIMATE["recoverPerSec"]) * dt)
		if cold >= 100.0:
			return _finish(ev, "wynelle")
		if heat >= 100.0:
			return _finish(ev, "solyth")

	# the air
	var sealed := (1 if seals["L"] else 0) + (1 if seals["R"] else 0)
	var running := (1 if heater_on and online("heater") else 0) + (1 if fan_on and online("fan") else 0)
	var bad: float = sealed * float(air["seal"]) + (0.0 if online("vent") else float(air["broken"])) + running * float(air["appliance"])
	stress = maxf(0.0, minf(100.0, stress + (bad if bad > 0.0 else -float(air["decay"])) * dt))
	if stress >= 100.0 and not infinite_stress:
		return _finish(ev, "mavrine")

	# the hunter
	var room: String = k["room"]
	if room == "officeL" or room == "officeR":
		var side := "L" if room == "officeL" else "R"
		k["atMs"] = float(k["atMs"]) + dt_ms
		if seals[side]:
			if float(k["atMs"]) >= float(T["retreatMs"]):
				k["room"] = "storage"
				k["atMs"] = 0.0
				(k["pacer"] as NightWatchPacer).reset()
				k["side"] = side if NightWatchStream.chance(vr, VARIETY["sameSideAgain"]) else ("R" if side == "L" else "L")
				k["tempo"] = NightWatchStream.tempo(vr, VARIETY["xivvyTempo"])
				ev.append({"type": "retreat", "side": side})
		elif float(k["atMs"]) >= float(T["officeWaitMs"]):
			return _finish(ev, "xivvy")
	else:
		if String(input.get("watch", "")) != room and (k["pacer"] as NightWatchPacer).step(dt_ms * (float(T["lurePace"]) if float(k["lureLeft"]) > 0.0 else 1.0) * float(k["tempo"]) * hunter_speed, NightWatchData.effective_level(lvl, hour)):
			k["tempo"] = NightWatchStream.tempo(vr, VARIETY["xivvyTempo"])
			var from: String = k["room"]
			k["room"] = _next_room()
			if k["room"] != from:
				var to_office := String(k["room"]).begins_with("office")
				ev.append({"type": "atOffice" if to_office else "moved", "room": k["room"], "from": from})
				if to_office:
					k["atMs"] = 0.0
				if float(k["lureLeft"]) > 0.0 and k["room"] == k["target"]:
					k["lureLeft"] = 0.0
					k["target"] = ""
					k["dist"] = {}
	if elapsed >= NightWatchData.NIGHT_MS:
		over = "win"
		ev.append({"type": "win"})
	return ev


# --- player actions (each returns true when it did something) -------------------------------------------------------------

func lure(room: String) -> bool:
	if over != "" or not online("audio") or lure_cool > 0.0 or not LureData.ROOMS.has(room) or room.begins_with("vent"):
		return false
	killer["target"] = room
	killer["dist"] = {}
	killer["lureLeft"] = T["lureMs"]
	lure_cool = T["lureCoolMs"]
	lures += 1
	if lures % int(T["lureStrainEvery"]) == 0:
		systems["audio"] = {"state": "broken", "t": 0.0}
		pending.append({"type": "broken", "system": "audio", "id": "strain"})
	return true


func reboot(system: String) -> bool:
	if over != "" or not systems.has(system) or systems[system]["state"] != "broken" or (system == "fan" and not has_fan):
		return false
	systems[system]["state"] = "reboot"
	systems[system]["t"] = 0.0
	return true


func toggle(name: String) -> bool:
	if over != "" or not has_climate or not (name == "heater" or name == "fan") or (name == "fan" and not has_fan) or not online(name):
		return false
	if name == "heater":
		heater_on = not heater_on
		if heater_on:
			fan_on = false
	else:
		fan_on = not fan_on
		if fan_on:
			heater_on = false
	return true


func seal(side: String, on = null) -> bool:
	if over != "":
		return false
	seals[side] = (not bool(seals[side])) if on == null else bool(on)
	return true


## Everyone's AI level right now (with the night's step-ups), for the admin overlay and the validators.
func level_of(id: String) -> int:
	var hour := NightWatchData.hour_index(elapsed)
	if id == "xivvy":
		return NightWatchData.effective_level(lvl, hour)
	if climate.has(id):
		return int(climate[id])
	return NightWatchData.effective_level(phantom_base(id), hour)


## Admin: set a hunter's AI level (Xivvy, a phantom, or one of the climate pair).
func set_level(id: String, value: int) -> void:
	if id == "xivvy":
		lvl = value
	elif climate.has(id):
		climate[id] = value
		has_climate = int(climate["solyth"]) > 0 or int(climate["wynelle"]) > 0
		has_fan = int(climate["solyth"]) > 0
	else:
		if phantom_levels == null:
			phantom_levels = {}
		(phantom_levels as Dictionary)[id] = value
