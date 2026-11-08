class_name NightWatchData
extends RefCounted

## Night Watch (3D): the building, the cast and the clock. Pure data, ported from the 2D game's
## the original game's Classic data and clock so the rules (NightWatchClassic) and the
## scene share one table. Times are in milliseconds, like the 2D game.

const GAME_ID := "night_watch"

## Classic's building, rules and cast live in res://data/night_watch/ (docs/NIGHT_WATCH_DATA.md, Phase 2a): the classic mode
## (nw_modes/classic) names its rules (nw_rules), building (nw_buildings) and cast (nw_casts), and the tables below are rebuilt from
## those files in exactly the shapes the old consts had (ints stay ints, grids Vector2i, map spots Vector2), so Parity.nw_hash() is
## unchanged. Behaviour stays here; a pack may override a file ("overrides": ["nw_rules/classic"]) and the tables rebuild.

## A night is 12 AM to 6 AM, four and a half real minutes (45 seconds an hour). rules: night_ms.
static var NIGHT_MS: float
static var HOUR_MS: float
## Things tuned for an eight-minute night (power use) are scaled by this to fit the real one. rules: tuned_night_ms.
static var TIME_SCALE: float

## The hunters on this game's floor (Nyxie only ever comes when the power is out): the cast file's hunters, in its order.
static var CAST: Array
const NAMES := {"dovelle": "Dovelle", "ravelle": "Ravelle", "aki": "Aki", "ilyra": "Ilyra", "nyxie": "Nyxie"}

## `cam` is the camera number (0 = none); `pan` is where the room sounds from the office (-1 west to +1 east);
## `grid` is the room's cell on the building's floor plan (3D placement); `map` its place on the camera map (percent).
static var ROOMS: Dictionary

## Walkable connections (undirected). The doors hang off the two halls.
static var GRAPH: Dictionary

## Hunters who work together: while one waits at her door, the other loses patience (the original's COMBOS). cast: a hunter's "combo".
static var COMBOS: Array

## Who is on the floor each night: AI level per night (index 0 = Night 1; later nights reuse the last), and the rules that make
## her different. `retreat_to` is where a shut door sends her, `push_to` where the light drives her. cast: the hunters with a "floor"
## slot, in slot order (the order the floor wakes them).
static var HUNTERS: Dictionary
## cast: nyxie's levels.
static var NYXIE_LEVELS: Array
static var NIGHTS: int          # Night 7 is Kathy's alone (docs: the original's KATHY_HUNT)
static var TUNED_NIGHTS: int    # the per-night tables (grace, pace, push) run to Night 6; Night 7 scales Night 6's

## Night 7: Kathy hunts, alone (2D KATHY_HUNT). She is not in HUNTERS (shared lore character; no Custom Night slider). hold_ms: how long a shut door
## has to stay shut on her before she gives up silently (lo plus an exponential with mean hold_tail_ms, cut at hi); she fades to the stage or the kitchen on a fresh
## door; the light never holds her wait; she hums every hum_ms while waiting at a door (a shut door muffles it).
## The numbers are rules: kathy; her rooms (start, fade_to, doors, meet_rooms) are the building's paths.kathy (rule params hold no strings).
static var KATHY_NIGHT: int
static var KATHY: Dictionary
## The door light's tell: while she stands at a door and its light is on, the light dips at these moments ([start, end) ms of each cycle).
static var KATHY_DIP_CYCLE_MS: float
static var KATHY_DIPS: Array
## Meet her eyes (the O key here, K in 2D): only on the feed of a hall; a miss locks the key for miss_lock_ms.
static var KATHY_MEET_ROOMS: Array
static var KATHY_MISS_LOCK_MS: float

## A shut door must stay shut this long on a hunter standing at it before she gives up.
static var T_CLOSED_MS: float
## Door pacing per night (index 0 = Night 1): the wait at an open unlit door, the stretch on every wait between moves,
## and how long the light must stay on a hunter before she backs off.
static var DOOR_GRACE_MS: Array
static var NIGHT_PACE: Array
static var LIGHT_PUSH_MS: Array
static var DOOR_CAPACITY: int
## The default for how straight a hunter walks (the 2D game draws 0.6 to 0.9 per night with its variety levers).
static var FOCUS: float

## Power: percent per second (rules: the eight-minute-night rates, scaled up for the shorter night).
static var POWER_BASE: float
static var POWER_PER_DEVICE: float

static var _loaded: bool = _load_from_data()
static var _watching: bool = ContentRegistry.watch(rebuild_from_registry)


static func rebuild_from_registry() -> void:
	_load_from_data()


## The classic mode's rules, building and cast (by the ids its mode file names; "classic" when it names none).
static func _load_from_data() -> bool:
	var mode := ContentRegistry.get_def("nw_modes", "classic")
	var rules: Dictionary = ContentRegistry.get_def("nw_rules", String(mode.get("rules", "classic"))).get("params", {})
	var building := ContentRegistry.get_def("nw_buildings", String(mode.get("building", "classic")))
	var cast: Array = ContentRegistry.get_def("nw_casts", String(mode.get("cast", "classic"))).get("hunters", [])

	NIGHT_MS = float(rules.get("night_ms", 0.0))
	HOUR_MS = NIGHT_MS / 6.0
	TIME_SCALE = NIGHT_MS / float(rules.get("tuned_night_ms", 1.0))
	NIGHTS = int(rules.get("nights", 0))
	TUNED_NIGHTS = int(rules.get("tuned_nights", 0))
	DOOR_GRACE_MS = _floats(rules.get("door_grace_ms", []))
	NIGHT_PACE = _floats(rules.get("night_pace", []))
	LIGHT_PUSH_MS = _floats(rules.get("light_push_ms", []))
	DOOR_CAPACITY = int(rules.get("door_capacity", 0))
	T_CLOSED_MS = float(rules.get("t_closed_ms", 0.0))
	FOCUS = float(rules.get("focus", 0.0))
	POWER_BASE = float(rules.get("power_base_tuned", 0.0)) / TIME_SCALE
	POWER_PER_DEVICE = float(rules.get("power_per_device_tuned", 0.0)) / TIME_SCALE

	ROOMS = {}
	var rooms: Dictionary = building.get("rooms", {})
	for id in rooms:
		var r: Dictionary = rooms[id]
		var grid: Array = r.get("grid", [-1, -1])
		var spot: Array = r.get("map", [0, 0])
		ROOMS[String(id)] = {"cam": int(r.get("cam", 0)), "label": String(r.get("label", "")), "pan": float(r.get("pan", 0.0)),
			"grid": Vector2i(int(grid[0]), int(grid[1])), "map": Vector2(float(spot[0]), float(spot[1]))}
	GRAPH = {}
	var graph: Dictionary = building.get("graph", {})
	for id in graph:
		GRAPH[String(id)] = _strings(graph[id])

	var slots := []
	CAST = []
	COMBOS = []
	NYXIE_LEVELS = []
	for h in cast:
		var id := String(h["id"])
		CAST.append(id)
		if id == "nyxie":
			NYXIE_LEVELS = _ints(h.get("levels", []))
		if h.has("floor"):
			slots.append([int(h["floor"]), h])
		if h.has("combo"):
			var c: Dictionary = h["combo"]
			COMBOS.append({"ids": [id, String(c["with"])], "min_level": int(c["min_level"]), "patience_ms": float(c["patience_ms"])})
	slots.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	HUNTERS = {}
	for slot in slots:
		var def := {}
		for key in slot[1]:
			match String(key):
				"id", "floor", "combo", "poses":
					pass
				"levels":
					def["levels"] = _ints(slot[1]["levels"])
				_:
					var v = slot[1][key]
					def[String(key)] = _strings(v) if typeof(v) == TYPE_ARRAY else v
		HUNTERS[String(slot[1]["id"])] = def

	var k: Dictionary = rules.get("kathy", {})
	var kp: Dictionary = (building.get("paths", {}) as Dictionary).get("kathy", {})
	KATHY_NIGHT = int(rules.get("kathy_night", 0))
	KATHY = {"level": int(k.get("level", 0)), "pace_scale": float(k.get("pace_scale", 1.0)), "grace_scale": float(k.get("grace_scale", 1.0)),
		"hold_ms": _floats(k.get("hold_ms", [])), "hold_tail_ms": float(k.get("hold_tail_ms", 0.0)), "start": String(kp.get("start", "")),
		"fade_to": _strings(kp.get("fade_to", [])), "doors": _strings(kp.get("doors", [])), "hum_ms": float(k.get("hum_ms", 0.0)),
		"glow_period_ms": float(k.get("glow_period_ms", 0.0)), "glow_on_ms": float(k.get("glow_on_ms", 0.0))}
	KATHY_DIP_CYCLE_MS = float(rules.get("kathy_dip_cycle_ms", 0.0))
	KATHY_DIPS = Array(rules.get("kathy_dips", [])).map(func(d): return _floats(d))
	KATHY_MEET_ROOMS = _strings(kp.get("meet_rooms", []))
	KATHY_MISS_LOCK_MS = float(rules.get("kathy_miss_lock_ms", 0.0))
	return true


## Fresh, writable, untyped copies of the registry's read-only JSON arrays, as the type the const tables had.
static func _floats(values) -> Array:
	return Array(values).map(func(v): return float(v))


static func _ints(values) -> Array:
	return Array(values).map(func(v): return int(v))


static func _strings(values) -> Array:
	return Array(values).map(func(v): return String(v))


static func cam_rooms() -> Array:
	var out := []
	for id in ROOMS:
		if int(ROOMS[id]["cam"]) > 0:
			out.append(id)
	out.sort_custom(func(a, b): return int(ROOMS[a]["cam"]) < int(ROOMS[b]["cam"]))
	return out


static func room_for_cam(cam: int) -> String:
	for id in ROOMS:
		if int(ROOMS[id]["cam"]) == cam:
			return id
	return ""


static func hour_index(elapsed_ms: float) -> int:
	return mini(5, int(floor(elapsed_ms / HOUR_MS)))


## AI steps up as the night goes on: nothing before 3 AM, +1 at 3 AM, +2 from 4 AM. A hunter at level 0 never wakes up.
static func ai_bump(hour: int) -> int:
	return 2 if hour >= 4 else (1 if hour >= 3 else 0)


static func effective_level(base: int, hour: int) -> int:
	return base + ai_bump(hour) if base > 0 else 0


static func hour_label(h: int) -> String:
	return "%d AM" % (12 if h == 0 else h)


## How often a hunter moves: after each move she waits a random time from a three-second window that slides with her level.
static func move_window(level: int) -> Vector2:
	var lo := maxf(2500.0, 13000.0 - level * 500.0)
	return Vector2(lo, lo + 3000.0)


static func level_for(id: String, night: int) -> int:
	var levels: Array = HUNTERS[id]["levels"]
	return int(levels[clampi(night, 1, levels.size()) - 1])


static func nyxie_level(night: int) -> int:
	if night == KATHY_NIGHT:
		return 0   # Night 7 is Kathy's alone
	return int(NYXIE_LEVELS[clampi(night, 1, NYXIE_LEVELS.size()) - 1])


static func is_kathy_night(night: int, custom := false) -> bool:
	return night == KATHY_NIGHT and not custom


static func kathy_dip_on(elapsed_ms: float) -> bool:
	var t := fmod(elapsed_ms, KATHY_DIP_CYCLE_MS)
	for d in KATHY_DIPS:
		if t >= float(d[0]) and t < float(d[1]):
			return true
	return false


## How long a shut door must stay shut on Kathy this time (2D rollHold): lo plus an exponential with mean `tail`, never above hi; u is a draw in [0, 1).
static func roll_hold(u: float, lo: float, hi: float, tail: float) -> float:
	if tail <= 0.0:
		return roundf(lo + u * (hi - lo))
	return roundf(lo - tail * log(1.0 - u * (1.0 - exp(-(hi - lo) / tail))))


## How long the dark lasts before Nyxie reaches the office once the power is out (11 s at level 1 down to 4 s).
static func blackout_ms(level: int) -> float:
	return maxf(4000.0, 11500.0 - level * 400.0)


static func night_index(night: int) -> int:
	return clampi(night, 1, TUNED_NIGHTS) - 1


## Breadth-first distance from every room to `target` along the graph.
static func distances_to(target: String, graph: Dictionary = GRAPH) -> Dictionary:
	var dist := {target: 0}
	var queue := [target]
	while not queue.is_empty():
		var room: String = queue.pop_front()
		for next in graph.get(room, []):
			if not dist.has(next):
				dist[next] = int(dist[room]) + 1
				queue.append(next)
	return dist


static func active_hunters(night: int) -> Array:
	if night == KATHY_NIGHT:
		return ["kathy"]
	var out := []
	for id in HUNTERS:
		if level_for(id, night) > 0:
			out.append(id)
	return out


## Classic's call lines for a night (the table is NightWatchCallsData, copied from the 2D game).
static func call_lines(night: int) -> Array:
	return NightWatchCallsData.for_level("classic", clampi(night, 1, 7)).get("lines", [])
