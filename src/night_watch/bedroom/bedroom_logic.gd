class_name BedroomLogic
extends RefCounted

## Bedtime rules, ported from games/night-watch/src/modes/bedroom/bedroom-logic.js (same numbers, same draws in the same order). Pure.
##
## You are in bed with one free hand. Three things come for you, each from its own side, each turned away a different way:
##   Loxelle   breathes behind the closet door (left). Hold the closet door shut until she goes.
##   Javelle   waits in the hall doorway (right). A little light on the hall makes her leave.
##   Haelith   creeps toward the bed, but only while the room is dark. Light on the bed pushes her back.
## Holding the door uses both hands, so no light while you hold it, and only one light at a time. The flashlight battery is limited and
## does not recharge. Sitting still is punished: with no light and no hand on the door for a while the house turns restless.
## step(dt_ms, input) with input {"hold": bool, "light": "hall" | "bed" | ""} returns events.

const VARIETY := {"waitSpread": 0.25, "doorTempo": 0.1, "haelithTempo": 0.2, "swapFirst": 0.3}
const T := {
	"stageJitter": 0.4, "holdNeedMs": 700.0, "lightNeedMs": 600.0, "afkMs": 14000.0, "afkBonus": 4, "afkSpeed": 1.5,
	"bedGain": 8.0, "bedGainPerLevel": 0.9, "bedLitDrainPerSec": 35.0, "bedVisibleAt": 80.0, "bedStirAt": 45.0,
}


static func _row(l: int, j: int, h: int, breath: float, near: float, jf: float, rl: float, rj: float) -> Dictionary:
	return {"ai": {"loxelle": l, "javelle": j, "haelith": h}, "breathMs": breath, "nearMs": near,
		"first": {"loxelle": 3000.0, "javelle": jf}, "rest": {"loxelle": rl, "javelle": rj}}


static func nights() -> Array:
	return [_row(3, 0, 0, 3200.0, 4200.0, 3000.0, 7000.0, 7000.0), _row(7, 7, 0, 2560.0, 3360.0, 4500.0, 5000.0, 5000.0),
		_row(9, 9, 5, 2560.0, 3360.0, 4000.0, 5000.0, 5000.0), _row(16, 11, 7, 2560.0, 3360.0, 3000.0, 2500.0, 5000.0),
		_row(18, 12, 9, 2560.0, 3360.0, 3000.0, 2000.0, 5000.0), _row(20, 12, 9, 2560.0, 3360.0, 3000.0, 1500.0, 5000.0)]


## Custom Night sets its own levels, so it keeps Night 1's timings.
static func custom_row() -> Dictionary:
	return _row(0, 0, 0, 3200.0, 4200.0, 3000.0, 7000.0, 7000.0)


static func flash_seconds() -> Array:
	var out := []
	for x in [120, 105, 90, 75, 60, 50]:
		out.append(roundi(x * NightWatchData.TIME_SCALE))
	return out


static func night_row(night: int) -> Dictionary:
	return nights()[clampi(night, 1, 6) - 1]


## Who is on the floor on a level (0-based).
static func active_hunters(level_idx: int) -> Array:
	var row: Dictionary = nights()[mini(level_idx, 5)]
	var out := []
	for id in BedroomData.CAST:
		if int(row["ai"][id]) > 0:
			out.append(id)
	return out


var n := 0
var row: Dictionary
var rng: NightWatchStream
var vr: NightWatchStream
var levels := {}
var infinite_battery := false
var is_custom := false
var flash_per_sec := 0.0
var swapped := false

var elapsed := 0.0
var over := ""
var by := ""
var battery := 100.0
var light := ""
var hold := false
var loxelle := {}
var javelle := {}
var haelith := {}
var idle := 0.0
var restless := false


## opts: night, rng, var_rng, levels (dict, optional), infinite_battery, custom.
func _init(opts: Dictionary) -> void:
	n = clampi(int(opts.get("night", 1)), 1, 6) - 1
	is_custom = bool(opts.get("custom", false))
	row = custom_row() if is_custom else nights()[n]
	rng = opts["rng"]
	vr = NightWatchStream.variety_of(rng, opts.get("var_rng", null))
	levels = opts.get("levels", {})
	infinite_battery = bool(opts.get("infinite_battery", false))
	flash_per_sec = 100.0 / float(flash_seconds()[n])
	swapped = NightWatchStream.chance(vr, VARIETY["swapFirst"]) and base_level("loxelle") > 0 and base_level("javelle") > 0
	loxelle = _door("loxelle")
	javelle = _door("javelle")
	haelith = {"p": 0.0, "pacer": NightWatchPacer.new(rng), "tempo": NightWatchStream.tempo(vr, VARIETY["haelithTempo"])}


func _first_of(id: String) -> float:
	return float(row["first"]["javelle" if id == "loxelle" else "loxelle"]) if swapped else float(row["first"][id])


func _door(id: String) -> Dictionary:
	var pacer := NightWatchPacer.new(rng)
	var cool := NightWatchStream.spread_ms(_first_of(id), rng, VARIETY["waitSpread"])
	return {"state": "away", "t": 0.0, "pacer": pacer, "cool": cool, "need": 0.0, "jitter": 1.0, "tempo": NightWatchStream.tempo(vr, VARIETY["doorTempo"])}


func base_level(id: String) -> int:
	if levels.has(id) and int(levels[id]) >= 0:
		return int(levels[id])
	return int(row["ai"][id])


## Steps up at 3 and 4 AM.
func level(id: String) -> int:
	return NightWatchData.effective_level(base_level(id), NightWatchData.hour_index(elapsed))


func _finish(ev: Array, who: String) -> Array:
	over = "caught"
	by = who
	ev.append({"type": "caught", "by": who})
	return ev


func _stage_jitter() -> float:
	return 1.0 - float(T["stageJitter"]) / 2.0 + rng.next() * float(T["stageJitter"])


func step(dt_ms: float, input := {}) -> Array:
	var ev := []
	if over != "":
		return ev
	var dt := dt_ms / 1000.0
	elapsed += dt_ms
	# one hand: holding the door means no light, and only one light at a time; a flat battery means no light
	hold = bool(input.get("hold", false))
	var lit := ""
	if not hold:
		var want := String(input.get("light", ""))
		if want == "hall" or want == "bed":
			lit = want
	if battery <= 0.0:
		lit = ""
	light = lit
	if lit != "" and not infinite_battery:
		battery = maxf(0.0, battery - flash_per_sec * dt)
	# restless: nothing done for a while
	idle = 0.0 if (hold or lit != "") else idle + dt_ms
	var is_restless := idle >= float(T["afkMs"]) and (level("loxelle") > 0 or level("javelle") > 0)
	if is_restless and not restless:
		ev.append({"type": "restless"})
	restless = is_restless
	var speed: float = float(T["afkSpeed"]) if restless else 1.0
	# the two door threats
	for pair in [["loxelle", loxelle, hold, T["holdNeedMs"]], ["javelle", javelle, lit == "hall", T["lightNeedMs"]]]:
		var id: String = pair[0]
		var th: Dictionary = pair[1]
		var answered: bool = pair[2]
		var need: float = pair[3]
		if th["state"] == "away":
			th["cool"] = maxf(0.0, float(th["cool"]) - dt_ms)
			var keen := level(id)
			if keen > 0 and restless:
				keen = mini(20, keen + int(T["afkBonus"]))
			if float(th["cool"]) <= 0.0 and (th["pacer"] as NightWatchPacer).step(dt_ms * float(th["tempo"]), keen):
				th["state"] = "breath"
				th["t"] = 0.0
				th["need"] = 0.0
				th["jitter"] = _stage_jitter()
				th["tempo"] = NightWatchStream.tempo(vr, VARIETY["doorTempo"])
				ev.append({"type": "breath", "id": id})
			continue
		if not (id == "javelle" and lit == "hall"):
			th["t"] = float(th["t"]) + dt_ms * speed   # looked at: she holds her stage while the hall is lit
		th["need"] = float(th["need"]) + dt_ms if answered else maxf(0.0, float(th["need"]) - dt_ms * 0.5)
		if float(th["need"]) >= need:
			th["state"] = "away"
			th["cool"] = NightWatchStream.spread_ms(float(row["rest"][id]), rng, VARIETY["waitSpread"])
			(th["pacer"] as NightWatchPacer).reset()
			th["need"] = 0.0
			ev.append({"type": "leave", "id": id})
		elif th["state"] == "breath" and float(th["t"]) >= float(row["breathMs"]) * float(th["jitter"]):
			th["state"] = "near"
			th["t"] = 0.0
			th["jitter"] = _stage_jitter()
			ev.append({"type": "near", "id": id})
		elif th["state"] == "near" and float(th["t"]) >= float(row["nearMs"]) * float(th["jitter"]):
			return _finish(ev, id)
	# Haelith: she only creeps while the room is dark; light on the bed pushes her back
	var b := haelith
	if lit == "" and (b["pacer"] as NightWatchPacer).step(dt_ms * float(b["tempo"]), level("haelith")):
		b["p"] = minf(100.0, float(b["p"]) + float(T["bedGain"]) + float(T["bedGainPerLevel"]) * level("haelith"))
		b["tempo"] = NightWatchStream.tempo(vr, VARIETY["haelithTempo"])
		ev.append({"type": "stir", "id": "haelith", "p": b["p"]})
	if lit == "bed":
		b["p"] = maxf(0.0, float(b["p"]) - float(T["bedLitDrainPerSec"]) * dt)
	if float(b["p"]) >= 100.0:
		return _finish(ev, "haelith")
	if elapsed >= NightWatchData.NIGHT_MS:
		over = "win"
		ev.append({"type": "win"})
	return ev
