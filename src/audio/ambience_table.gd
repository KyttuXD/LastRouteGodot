class_name AmbienceTable
extends RefCounted

## Ambient beds by region / room purpose (docs/AMBIENCE.md). Each bed is a seamless loop rendered by AmbienceSynth from
## layers: "hum" (a drone at the frequency), "noise" (low-passed room tone), "pulse" (sparse details at jittered
## intervals: drips, clanks, relay ticks; long ones are soft chimes), "chirp" (scattered soft trills: birds, rats). A region registers its own with AmbienceTable.register(key, layers);
## room purposes override the district bed when they have one. Level beds ("level:<name>", LevelAmbience) play on their own
## players under whichever district bed is on, so a level layer blends with the region rather than replacing it.

const LOOP_SECONDS := AmbienceSynth.LOOP_SECONDS

static var _beds := {
	"maze": [{"kind": "hum", "hz": 120.0, "vol": .010}, {"kind": "noise", "hz": 260.0, "vol": .006}],
	"mansion": [{"kind": "noise", "hz": 180.0, "vol": .006}, {"kind": "pulse", "hz": 70.0, "vol": .012, "every": 2.9, "len": .25}],
	"hotel": [{"kind": "hum", "hz": 60.0, "vol": .009}, {"kind": "noise", "hz": 300.0, "vol": .004}],
	"apartment": [{"kind": "hum", "hz": 100.0, "vol": .006}, {"kind": "pulse", "hz": 1800.0, "vol": .003, "every": 1.5, "len": .02}],
	"beach": [{"kind": "noise", "hz": 420.0, "vol": .014, "swell": 6.0}, {"kind": "chirp", "hz": 2600.0, "vol": .004, "count": 3}],
	"gothic": [{"kind": "noise", "hz": 220.0, "vol": .012, "swell": 3.0}, {"kind": "pulse", "hz": 85.0, "vol": .010, "every": 2.3, "len": .35}],
	"carnival": [{"kind": "pulse", "hz": 523.0, "vol": .006, "every": .5, "len": .3}, {"kind": "pulse", "hz": 392.0, "vol": .005, "every": .75, "len": .3},
		{"kind": "noise", "hz": 200.0, "vol": .004}],
	"prison": [{"kind": "hum", "hz": 50.0, "vol": .008}, {"kind": "pulse", "hz": 140.0, "vol": .014, "every": 3.0, "len": .12, "wave": "square"}],
	"hospital": [{"kind": "hum", "hz": 120.0, "vol": .011}, {"kind": "hum", "hz": 240.0, "vol": .004},
		{"kind": "pulse", "hz": 980.0, "vol": .006, "every": 1.5, "len": .09}],
	"lab": [{"kind": "noise", "hz": 650.0, "vol": .009}, {"kind": "hum", "hz": 120.0, "vol": .003},
		{"kind": "pulse", "hz": 3000.0, "vol": .004, "every": 6.0, "len": .7, "wave": "saw"}],
	"greenhouse": [{"kind": "noise", "hz": 2200.0, "vol": .004, "swell": 3.0}, {"kind": "pulse", "hz": 1400.0, "vol": .004, "every": 1.2, "len": .04},
		{"kind": "chirp", "hz": 3200.0, "vol": .005, "count": 4}],
	"sewer": [{"kind": "noise", "hz": 300.0, "vol": .014, "swell": 6.0}, {"kind": "pulse", "hz": 1250.0, "vol": .006, "every": 1.0, "len": .05},
		{"kind": "chirp", "hz": 4200.0, "vol": .003, "count": 2}],
	"mall": [{"kind": "pulse", "hz": 440.0, "vol": .005, "every": 1.0, "len": .5}, {"kind": "pulse", "hz": 554.0, "vol": .004, "every": 1.5, "len": .5},
		{"kind": "hum", "hz": 70.0, "vol": .008}],
	"inferno": [{"kind": "noise", "hz": 140.0, "vol": .016, "swell": 2.0}, {"kind": "hum", "hz": 41.0, "vol": .012}],
}

static var _rooms := {
	"archive": [{"kind": "noise", "hz": 160.0, "vol": .004}],
	"chapel": [{"kind": "hum", "hz": 110.0, "vol": .006}, {"kind": "noise", "hz": 200.0, "vol": .005, "swell": 6.0}],
	"kitchen": [{"kind": "hum", "hz": 180.0, "vol": .007}, {"kind": "pulse", "hz": 2200.0, "vol": .003, "every": 2.0, "len": .03}],
	"big_top": [{"kind": "pulse", "hz": 659.0, "vol": .007, "every": .4, "len": .25}, {"kind": "pulse", "hz": 523.0, "vol": .006, "every": .6, "len": .25}],
	"office_reception": [{"kind": "hum", "hz": 120.0, "vol": .010}, {"kind": "noise", "hz": 500.0, "vol": .004}],
	"cubicle_room": [{"kind": "hum", "hz": 120.0, "vol": .011}, {"kind": "noise", "hz": 500.0, "vol": .005}],
}

## Level beds (docs/AMBIENCE.md, "Level layer"): the maze level's building hum and far thuds, the Mezzanine's air and
## creaking metal, the sewers' running water, drips and pipe groans, the Inferno's fire, embers and deep rumble, and the
## void shaft's hollow wind. Their echo comes mostly from the Level bus reverb (LevelAmbience.REVERB).
static var _levels := {
	"maze": [{"kind": "hum", "hz": 55.0, "vol": .007}, {"kind": "thump", "hz": 48.0, "vol": .03, "every": 4.2}],
	"mezzanine": [{"kind": "wind", "hz": 520.0, "vol": .010, "q": 1.1, "gust": 7.0},
		{"kind": "creak", "hz": 410.0, "vol": .007, "every": 3.4}],
	"sewer": [{"kind": "water", "hz": 1300.0, "vol": .009, "density": 55.0, "swell": 5.0},
		{"kind": "pulse", "hz": 1500.0, "vol": .005, "every": 1.1, "len": .04},
		{"kind": "groan", "hz": 85.0, "vol": .010, "every": 5.5}, {"kind": "thump", "hz": 60.0, "vol": .012, "every": 6.5}],
	"inferno": [{"kind": "noise", "hz": 300.0, "vol": .012, "swell": 4.0}, {"kind": "crackle", "hz": 2100.0, "vol": .006, "rate": 3.5},
		{"kind": "noise", "hz": 55.0, "vol": .016, "swell": 9.0}, {"kind": "thump", "hz": 32.0, "vol": .02, "every": 6.0}],
	"void": [{"kind": "wind", "hz": 170.0, "vol": .016, "q": 4.0, "gust": 9.0}, {"kind": "wind", "hz": 420.0, "vol": .005, "q": 2.0, "gust": 5.0},
		{"kind": "hum", "hz": 38.0, "vol": .004}],
}


## Registers (or replaces) a bed: `key` is a region id or a room purpose. Regions call this once, e.g.
## AmbienceTable.register("hospital", [{"kind": "hum", "hz": 120.0, "vol": .01}, {"kind": "pulse", "hz": 980.0, ...}])
static func register(key: String, layers: Array, room_purpose: bool = false) -> void:
	if key.begins_with("level:"):
		_levels[key.trim_prefix("level:")] = layers.duplicate(true)
	elif room_purpose:
		_rooms[key] = layers.duplicate(true)
	else:
		_beds[key] = layers.duplicate(true)


static func has_bed(key: String) -> bool:
	if key.begins_with("level:"):
		return _levels.has(key.trim_prefix("level:"))
	return _beds.has(key) or _rooms.has(key)


## The bed for where the player stands: the room purpose's own, else the district's ("" = none).
static func key_for(region: String, room_type: String) -> String:
	if room_type != "" and _rooms.has(room_type):
		return "room:" + room_type
	return region if _beds.has(region) else ""


static func layers(key: String) -> Array:
	if key.begins_with("room:"):
		return _rooms.get(key.trim_prefix("room:"), [])
	if key.begins_with("level:"):
		return _levels.get(key.trim_prefix("level:"), [])
	return _beds.get(key, [])


static func regions() -> Array:
	return _beds.keys()


static func room_purposes() -> Array:
	return _rooms.keys()


## Level bed keys ("level:maze", ...).
static func levels() -> Array:
	return _levels.keys().map(func(name: String) -> String: return "level:" + name)
