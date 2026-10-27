class_name NightWatchData
extends RefCounted

## Night Watch (3D): the building, the cast and the clock. Pure data, ported from the 2D game's
## games/night-watch/src/modes/classic/classic-data.js and core/time.js so the rules (NightWatchClassic) and the
## scene share one table. Times are in milliseconds, like the 2D game.

const GAME_ID := "night_watch"

## A night is 12 AM to 6 AM, four and a half real minutes (45 seconds an hour).
const NIGHT_MS := 270000.0
const HOUR_MS := NIGHT_MS / 6.0
## Things tuned for an eight-minute night (power use) are scaled by this to fit the real one.
const TIME_SCALE := NIGHT_MS / 480000.0

## The hunters on this game's floor (Nyxie only ever comes when the power is out).
const CAST := ["dovelle", "nyxie", "ravelle", "ilyra", "aki"]
const NAMES := {"dovelle": "Dovelle", "ravelle": "Ravelle", "aki": "Aki", "ilyra": "Ilyra", "nyxie": "Nyxie"}

## `cam` is the camera number (0 = none); `pan` is where the room sounds from the office (-1 west to +1 east);
## `grid` is the room's cell on the building's floor plan (3D placement); `map` its place on the camera map (percent).
const ROOMS := {
	"stage": {"cam": 1, "label": "SHOW STAGE", "pan": 0.0, "grid": Vector2i(1, 0), "map": Vector2(50, 12)},
	"dining": {"cam": 2, "label": "DINING AREA", "pan": -0.2, "grid": Vector2i(1, 1), "map": Vector2(50, 44)},
	"backstage": {"cam": 3, "label": "BACKSTAGE", "pan": -0.5, "grid": Vector2i(0, 0), "map": Vector2(15, 12)},
	"westhall": {"cam": 4, "label": "WEST HALL", "pan": -0.8, "grid": Vector2i(0, 1), "map": Vector2(15, 44)},
	"closet": {"cam": 5, "label": "SUPPLY CLOSET", "pan": -0.9, "grid": Vector2i(0, 2), "map": Vector2(15, 76)},
	"kitchen": {"cam": 6, "label": "KITCHEN", "pan": 0.5, "grid": Vector2i(2, 0), "map": Vector2(85, 12)},
	"easthall": {"cam": 7, "label": "EAST HALL", "pan": 0.8, "grid": Vector2i(2, 1), "map": Vector2(85, 44)},
	"corner": {"cam": 8, "label": "EAST CORNER", "pan": 0.9, "grid": Vector2i(2, 2), "map": Vector2(85, 76)},
	"doorL": {"cam": 0, "label": "LEFT DOOR", "pan": -1.0, "grid": Vector2i(-1, -1), "map": Vector2(40, 79)},
	"doorR": {"cam": 0, "label": "RIGHT DOOR", "pan": 1.0, "grid": Vector2i(-1, -1), "map": Vector2(60, 79)},
}

## Walkable connections (undirected). The doors hang off the two halls.
const GRAPH := {
	"stage": ["dining", "backstage"],
	"backstage": ["stage", "westhall"],
	"dining": ["stage", "westhall", "kitchen", "easthall"],
	"kitchen": ["dining"],
	"westhall": ["dining", "backstage", "closet", "doorL"],
	"closet": ["westhall"],
	"easthall": ["dining", "corner", "doorR"],
	"corner": ["easthall"],
	"doorL": ["westhall"],
	"doorR": ["easthall"],
}

## Hunters who work together: while one waits at her door, the other loses patience (classic-logic.js COMBOS).
const COMBOS := [{"ids": ["dovelle", "ravelle"], "min_level": 8, "patience_ms": 1400.0}]

## Who is on the floor each night: AI level per night (index 0 = Night 1; later nights reuse the last), and the rules that make
## her different. `retreat_to` is where a shut door sends her, `push_to` where the light drives her.
const HUNTERS := {
	"dovelle": {"doors": ["doorL"], "start": "stage", "retreat_to": "dining", "push_to": "stage",
		"levels": [2, 4, 6, 9, 12, 16]},
	"ravelle": {"doors": ["doorR", "doorL"], "start": "kitchen", "retreat_to": "dining", "push_to": "kitchen",
		"alternate": true, "levels": [0, 3, 5, 7, 10, 14]},
	"aki": {"doors": ["doorR"], "start": "closet", "retreat_to": "corner", "push_to": "closet",
		"levels": [0, 0, 4, 6, 9, 13], "only_when_cams_down": true},
	"ilyra": {"doors": ["doorL"], "start": "backstage", "retreat_to": "closet", "push_to": "stage",
		"levels": [0, 0, 0, 5, 8, 12], "freezes_when_watched": true},
}
const NYXIE_LEVELS := [3, 5, 7, 9, 11, 13]
const NIGHTS := 6

## A shut door must stay shut this long on a hunter standing at it before she gives up.
const T_CLOSED_MS := 450.0
## Door pacing per night (index 0 = Night 1): the wait at an open unlit door, the stretch on every wait between moves,
## and how long the light must stay on a hunter before she backs off.
const DOOR_GRACE_MS := [9000.0, 8200.0, 7500.0, 6900.0, 6400.0, 5800.0]
const NIGHT_PACE := [1.3, 1.24, 1.18, 1.12, 1.06, 1.03]
const LIGHT_PUSH_MS := [2000.0, 2500.0, 3000.0, 3500.0, 4000.0, 4500.0]
const DOOR_CAPACITY := 2
## The default for how straight a hunter walks (the 2D game draws 0.6 to 0.9 per night with its variety levers).
const FOCUS := 0.75

## Power: percent per second (scaled up for the shorter night).
const POWER_BASE := 0.10 / TIME_SCALE
const POWER_PER_DEVICE := 0.07 / TIME_SCALE


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
	return int(NYXIE_LEVELS[clampi(night, 1, NYXIE_LEVELS.size()) - 1])


## How long the dark lasts before Nyxie reaches the office once the power is out (11 s at level 1 down to 4 s).
static func blackout_ms(level: int) -> float:
	return maxf(4000.0, 11500.0 - level * 400.0)


static func night_index(night: int) -> int:
	return clampi(night, 1, NIGHTS) - 1


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
	var out := []
	for id in HUNTERS:
		if level_for(id, night) > 0:
			out.append(id)
	return out


## Classic's call lines for a night (the table is NightWatchCallsData, copied from the 2D game).
static func call_lines(night: int) -> Array:
	return NightWatchCallsData.for_level("classic", clampi(night, 1, 7)).get("lines", [])
