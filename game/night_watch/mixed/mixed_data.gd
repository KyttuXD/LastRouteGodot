class_name MixedData
extends RefCounted

## Mixed Shift's constants, copied from the 2D game's Mixed Shift data: the pool of threats, the presets (QUIET, STEADY, RESTLESS,
## CHAOS, ENDLESS), every tuning number, the routes through Classic's building and the vent run, chaos events and the music box. Pure data.

const HOUR_MS := 45000.0
const NIGHT_MS := 270000.0

# fairness
const TELL_FLOOR_MS := 1500.0
const COOLDOWN_MS := 1200.0
const TELL_JITTER := 0.2
const JITTER := 0.3
const GIVE_UP_MS := 1200.0
const CHOKE_MS := 2000.0
const END_CLEAR_MS := 10000.0
const MIN_DWELL_MS := 2500.0
const CUE_FOOT_MS := 4000.0
# doors
const SEAL_MAX := 20000.0
const SEAL_REGEN := 0.3
const SEAL_MIN_TO_SHUT := 1500.0
const SEAL_RESERVE := 2600.0
const DOOR_HOLD_MS := 8000.0
const POP_COOL_MS := 900.0
# vents
const VENT_SEAL_MAX := 9000.0
const VENT_SEAL_REGEN := 0.35
const VENT_MIN_TO_SEAL := 1200.0
const VENT_RESERVE := 2600.0
const VENT_HOLD_MS := 6000.0
const VENT_LINGER_MS := 2200.0
const VENT_POP_COOL_MS := 1100.0
const VENT_LIGHT_MS := 700.0
const VENT_LIGHT_COOL_MS := 2400.0
const VENT_KEYS := ["L", "R", "T"]
const VENT_NAME := {"L": "left", "R": "right", "T": "top"}
# moods
const MOODS := ["patient", "hungry", "shy", "reckless"]
const MOOD_MIN_MS := 30000.0
const MOOD_MAX_MS := 60000.0
const MOOD_SPEED := {"patient": 0.8, "hungry": 1.25, "shy": 1.0, "reckless": 1.4}
const MOOD_TELL := {"patient": 1.0, "hungry": 0.85, "shy": 1.0, "reckless": 1.3}
const MOOD_CUE_MS := [14000.0, 24000.0]
# the director
const SPIKE_LEN_MS := [10000.0, 13000.0]
const SPIKE_WARN_MS := 2500.0
const BREATHER_MS := [8000.0, 11000.0]
const SPIKE_FIRST_MS := HOUR_MS
const BEAT_RATE := {"lull": 0.65, "build": 1.0, "spike": 1.8, "breather": 0.0}
const BEAT_LEN := {"lull": [12000.0, 20000.0], "build": [10000.0, 16000.0]}
const FEINT_MS := {"lull": [9000.0, 16000.0], "build": [16000.0, 26000.0]}
const TENSION_FLOOR_FROM := 5.0 * HOUR_MS
const TENSION_FLOOR := [0.35, 0.85]

## The presets. `speed`, `tellMs`, `startMs`, `roster` [lo, hi], `spikes` [lo, hi], `graceMs`, `newMax`; QUIET has `minTellMs`.
const DIFFICULTIES := [
	{"id": "quiet", "name": "QUIET", "speed": 0.8, "tellMs": 3600.0, "minTellMs": 3000.0, "startMs": 50000.0, "roster": [3, 3], "spikes": [2, 2], "graceMs": 90000.0, "newMax": 1},
	{"id": "steady", "name": "STEADY", "speed": 1.0, "tellMs": 1900.0, "startMs": 32000.0, "roster": [3, 5], "spikes": [2, 3], "graceMs": 75000.0, "newMax": 2},
	{"id": "restless", "name": "RESTLESS", "speed": 1.15, "tellMs": 1750.0, "startMs": 24000.0, "roster": [4, 5], "spikes": [3, 3], "graceMs": 75000.0, "newMax": 2},
]
const MAX_WALKERS := 4
const CHAOS_BREATHER_FLOOR_MS := 4000.0
const CHAOS := {"id": "chaos", "name": "CHAOS", "chaos": true, "speed": 1.3, "tellMs": 1650.0, "startMs": 15000.0, "roster": [6, 7], "spikes": [4, 6], "graceMs": 75000.0,
	"newMax": 2, "must": ["verrine", "glyra"], "minTypes": 4, "breather": [4500.0, 6500.0]}
const ENDLESS := {"id": "endless", "name": "ENDLESS", "endless": true, "speed": 1.0, "tellMs": 1900.0, "startMs": 32000.0, "roster": [3, 4], "spikes": [1, 1], "graceMs": 75000.0, "newMax": 2}
const ENDLESS_SEAL := {"max": 8000.0, "regen": 0.25, "budget": 2400.0}
const ENDLESS_RAMP := {
	"paceFrom": 2, "paceStep": 0.04, "paceCap": 2.0, "tellFrom": 3, "tellStep": 45.0, "tellMin": 1600.0,
	"gapStart": 46000.0, "gapStep": 3000.0, "gapMin": 10000.0, "rotateMs": 3.0 * HOUR_MS,
	"rosterByGen": [[3, 4], [4, 5], [4, 5], [5, 6]],
	"floorFrom": HOUR_MS, "floorMax": 0.85, "floorSpan": 5.0,
	"budgetFrom": 10, "budgetStep": 100.0, "budgetMin": 1400.0, "eventFrom": 4, "eventP": 0.5,
}
const ENDLESS_MAX_MS := 1000.0 * HOUR_MS
const CHAOS_EVENTS := {
	"mood": {"weight": 3, "ms": 0.0, "needs": ""},
	"wake": {"weight": 2, "ms": 0.0, "needs": "vent"},
	"strain": {"weight": 2, "ms": 60000.0, "needs": "", "holdMs": 5000.0, "regen": 0.5},
	"flicker": {"weight": 3, "ms": 20000.0, "needs": ""},
	"decoy": {"weight": 3, "ms": 0.0, "needs": ""},
	"boxfast": {"weight": 2, "ms": 30000.0, "needs": "winder", "factor": 2.0},
}
const CHAOS_ORDER := ["mood", "wake", "strain", "flicker", "decoy", "boxfast"]
const DECOY_QUIET_MS := 3000.0
const DECOY_TYPES := ["path", "watched", "monitor", "vent", "winder"]
const CHAOS_HOURS := [1, 5]

const TYPE_ORDER := ["counter", "watched", "monitor", "path", "vent", "winder"]
const TYPES := {
	"counter": {"label": "Counter", "does": "builds while you stay on one camera", "answer": "switch camera, or lower the monitor"},
	"watched": {"label": "Watched", "does": "moves only when no camera is on her", "answer": "keep a camera on her, or shut the door when she is at it"},
	"monitor": {"label": "Monitor-gated", "does": "waits in the office and steps closer as you raise or lower the monitor", "answer": "stop touching the monitor, or shut her side's door"},
	"path": {"label": "Path walker", "does": "walks a route through the building one room at a time", "answer": "shut the door she is at, or hold a camera on her at the hall to turn her back"},
	"vent": {"label": "Vent crawler", "does": "crawls the vent run (CAM 9) to one of the three office vents", "answer": "seal that vent before she arrives, or flash the vent light when she is at its branch"},
	"winder": {"label": "Winder", "does": "hums with a music box on one camera; when it runs down she walks to a door", "answer": "view the box's camera and hold wind, or shut the door she is at"},
}
const POOL := [
	{"id": "haelith", "type": "counter", "name": "Haelith"},
	{"id": "ilyra", "type": "watched", "name": "Ilyra"},
	{"id": "aki", "type": "watched", "name": "Aki"},
	{"id": "opalie", "type": "monitor", "name": "Opalie"},
	{"id": "dovelle", "type": "path", "name": "Dovelle"},
	{"id": "ravelle", "type": "path", "name": "Ravelle"},
	{"id": "verrine", "type": "vent", "name": "Verrine"},
	{"id": "glyra", "type": "winder", "name": "Glyra"},
]
const WALKER_TYPES := ["path", "watched", "winder"]
const NEW_TYPES := ["vent", "winder"]
const TIMING := {
	"path": {"stepMs": 11000.0, "restMs": 16000.0},
	"watched": {"stepMs": 9000.0, "restMs": 18000.0},
	"counter": {"graceMs": 7000.0, "spanMs": 22000.0, "armAt": 0.65, "cueAt": 0.2, "calmDecay": 3.0},
	"monitor": {"arriveMs": 30000.0, "idleLeaveMs": 16000.0, "stepsToArm": 3, "decayMs": 8000.0, "restMs": 20000.0},
	"vent": {"stepMs": 9500.0, "restMs": 18000.0},
	"winder": {"stepMs": 12000.0, "restMs": 16000.0, "crankyMs": 7000.0},
}
const PULSE_MS := {"knock": [750.0, 300.0], "breath": [800.0, 320.0], "whisper": [850.0, 340.0], "fog": [1100.0, 260.0], "scrape": [900.0, 360.0], "thump": [800.0, 320.0]}
const TELL_KIND := {"path": "knock", "watched": "breath", "monitor": "whisper", "counter": "fog", "vent": "scrape", "winder": "thump"}
const TUNE := {"spanMs": 50000.0, "windPerSec": 0.12, "restartAt": 0.12, "slowAt": 0.5, "graceFloor": 0.25, "humMs": [380.0, 880.0]}

## The camera rooms: Classic's eight, then the vent run (CAM 9). The music box may sit in the eight building rooms.
const BOX_ROOMS := ["stage", "dining", "backstage", "westhall", "closet", "kitchen", "easthall", "corner"]
const CAM_ROOMS := ["stage", "dining", "backstage", "westhall", "closet", "kitchen", "easthall", "corner", "vent"]
const VENT_OPENINGS := ["ventL", "ventR", "ventT"]
const ROOM_LABELS := {"vent": "VENT RUN", "ventL": "LEFT VENT", "ventR": "RIGHT VENT", "ventT": "TOP VENT"}

## Routes through Classic's building; the last room before the door is the choke (it has a camera).
const ROUTES := [
	{"id": "L-stage", "side": "L", "rooms": ["stage", "backstage", "westhall", "doorL"]},
	{"id": "L-kitchen", "side": "L", "rooms": ["kitchen", "dining", "westhall", "doorL"]},
	{"id": "L-closet", "side": "L", "rooms": ["closet", "westhall", "doorL"]},
	{"id": "R-stage", "side": "R", "rooms": ["stage", "dining", "easthall", "doorR"]},
	{"id": "R-kitchen", "side": "R", "rooms": ["kitchen", "dining", "easthall", "doorR"]},
	{"id": "R-corner", "side": "R", "rooms": ["corner", "easthall", "doorR"]},
]
const VENT_ROUTES := [
	{"id": "V-L", "side": "L", "rooms": ["vent", "vent", "vent", "vent", "ventL"], "spots": [0, 1, 2, 3]},
	{"id": "V-R", "side": "R", "rooms": ["vent", "vent", "vent", "vent", "ventR"], "spots": [0, 1, 2, 4]},
	{"id": "V-T", "side": "T", "rooms": ["vent", "vent", "vent", "ventT"], "spots": [0, 1, 2]},
]
const VENT_NEAR := {"L": [3], "R": [4], "T": [2]}

## The shift board: QUIET, STEADY, RESTLESS, CHAOS, ENDLESS.
static func shifts() -> Array:
	var out: Array = DIFFICULTIES.duplicate()
	out.append(CHAOS)
	out.append(ENDLESS)
	return out


static func difficulty_of(x) -> Dictionary:
	var all := shifts()
	if x is int or x is float:
		return all[clampi(int(x), 0, all.size() - 1)]
	for d in all:
		if String(d["id"]) == String(x):
			return d
	return DIFFICULTIES[1]


static func pool_entry(id: String) -> Dictionary:
	for p in POOL:
		if String(p["id"]) == id:
			return p
	return {}


static func door_side(node: String) -> String:
	return "L" if node == "doorL" else ("R" if node == "doorR" else "")


static func vent_gate_side(node: String) -> String:
	return "L" if node == "ventL" else ("R" if node == "ventR" else ("T" if node == "ventT" else ""))


static func gate_side(node: String) -> String:
	var d := door_side(node)
	return d if d != "" else vent_gate_side(node)


static func endless_pace(hr: int) -> float:
	return minf(float(ENDLESS_RAMP["paceCap"]), 1.0 + float(ENDLESS_RAMP["paceStep"]) * maxi(0, hr - int(ENDLESS_RAMP["paceFrom"])))


static func endless_tell(hr: int) -> float:
	return maxf(float(ENDLESS_RAMP["tellMin"]), float(ENDLESS["tellMs"]) - float(ENDLESS_RAMP["tellStep"]) * maxi(0, hr - int(ENDLESS_RAMP["tellFrom"])))


static func endless_budget(hr: int) -> float:
	return maxf(float(ENDLESS_RAMP["budgetMin"]), float(ENDLESS_SEAL["budget"]) - float(ENDLESS_RAMP["budgetStep"]) * maxi(0, hr - int(ENDLESS_RAMP["budgetFrom"])))


static func endless_gap(hr: int) -> float:
	return maxf(float(ENDLESS_RAMP["gapMin"]), float(ENDLESS_RAMP["gapStart"]) - float(ENDLESS_RAMP["gapStep"]) * hr)


static func endless_floor_at(t: float) -> float:
	if t < float(ENDLESS_RAMP["floorFrom"]):
		return 0.0
	return float(ENDLESS_RAMP["floorMax"]) * (1.0 - exp(-(t - float(ENDLESS_RAMP["floorFrom"])) / HOUR_MS / float(ENDLESS_RAMP["floorSpan"])))


## The clock in Endless: 12 AM to 5 AM as ever, then "HOUR 6", "HOUR 7" ...
static func endless_clock(elapsed: float) -> String:
	var h := int(floor(elapsed / HOUR_MS))
	return "%d AM" % (12 if h == 0 else h) if h < 6 else "HOUR %d" % h


static func hours_text(n: int) -> String:
	return "%d hour%s" % [n, "" if n == 1 else "s"]


## The Classic graph plus the vent run and the three vent openings (the original's map data).
static func graph() -> Dictionary:
	var g := {}
	for id in NightWatchData.GRAPH:
		g[id] = (NightWatchData.GRAPH[id] as Array).duplicate()
	for id in ["vent", "ventL", "ventR", "ventT"]:
		g[id] = []
	for pair in [["closet", "vent"], ["corner", "vent"], ["vent", "ventL"], ["vent", "ventR"], ["vent", "ventT"]]:
		(g[pair[0]] as Array).append(pair[1])
		(g[pair[1]] as Array).append(pair[0])
	return g
