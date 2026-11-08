class_name AmbienceTable
extends RefCounted

## Ambient beds by region / room purpose (docs/AMBIENCE.md). Each bed is a seamless loop rendered by AmbienceSynth from
## layers: "hum" (a drone at the frequency), "noise" (low-passed room tone), "pulse" (sparse details at jittered
## intervals: drips, clanks, relay ticks; long ones are soft chimes), "chirp" (scattered soft trills: birds, rats). A region registers its own with AmbienceTable.register(key, layers);
## room purposes override the district bed when they have one. Level beds ("level:<name>", LevelAmbience) play on their own
## players under whichever district bed is on, so a level layer blends with the region rather than replacing it.

const LOOP_SECONDS := AmbienceSynth.LOOP_SECONDS

const SCHEMA := "lr.ambience/1"
## Built-in beds as data (docs/AMBIENCE.md, "Beds as data"): one lr.ambience/1 file per scope under ROOT,
## {"schema", "scope": "district" | "room" | "level", "beds": {id: [layer, ...]}}. Read once, when this script loads, so
## register() and every lookup see them; pack .ogg overrides (ContentRegistry "ambience") replace the rendered stream
## in Sound and never touch these tables.
const ROOT := "res://data/ambience"
const SCOPES := ["district", "room", "level"]

## District beds by region id; room beds by room purpose; level beds ("level:<name>", LevelAmbience) by level name: the
## maze level's building hum and far thuds, the Mezzanine's air and creaking metal, the sewers' running water, drips and
## pipe groans, the Inferno's fire, embers and deep rumble, and the void shaft's hollow wind. Their echo comes mostly
## from the Level bus reverb (LevelAmbience.REVERB).
static var _data: Dictionary = load_builtin()
static var _beds: Dictionary = _data["district"]
static var _rooms: Dictionary = _data["room"]
static var _levels: Dictionary = _data["level"]


## Every built-in bed file under ROOT -> {"district": {}, "room": {}, "level": {}}. Files load in name order; a later
## file's bed replaces an earlier one with the same id and scope. Bad files and layers are reported and skipped.
static func load_builtin(root: String = ROOT) -> Dictionary:
	var out := {}
	for scope in SCOPES:
		out[scope] = {}
	if not DirAccess.dir_exists_absolute(root):
		push_error("AmbienceTable: %s is missing" % root)
		return out
	var files := Array(DirAccess.get_files_at(root))
	files.sort()
	for file_name in files:
		if not String(file_name).ends_with(".json"):
			continue
		var path := root.path_join(file_name)
		var parsed := parse_file(path)
		for message in parsed["errors"]:
			push_error("AmbienceTable: " + message)
		if not parsed["scope"].is_empty():
			(out[parsed["scope"]] as Dictionary).merge(parsed["beds"], true)
	return out


## One lr.ambience/1 file -> {"scope", "beds": {id: layers}, "errors"}; scope is "" when the file is unusable.
static func parse_file(path: String) -> Dictionary:
	var out := {"scope": "", "beds": {}, "errors": PackedStringArray()}
	var errors: PackedStringArray = out["errors"]
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		errors.append("%s: not a JSON object" % path)
		return out
	for key in data:
		if not key in ["schema", "scope", "beds"]:
			errors.append("%s: unknown key \"%s\"" % [path, key])
	if String(data.get("schema", "")) != SCHEMA:
		errors.append("%s: schema must be %s" % [path, SCHEMA])
	if not SCOPES.has(data.get("scope")):
		errors.append("%s: scope must be one of %s" % [path, SCOPES])
		return out
	var beds = data.get("beds")
	if not beds is Dictionary:
		errors.append("%s: beds must be an object of id -> layers" % path)
		return out
	for id in beds:
		var where := "%s: beds.%s" % [path, id]
		var layers = beds[id]
		if not _is_layer_list(layers):
			errors.append("%s: must be a non-empty array of layers {\"kind\", numbers...}" % where)
			continue
		var clean := []
		for layer in layers:
			var copy: Dictionary = (layer as Dictionary).duplicate()
			if copy.has("count"):
				copy["count"] = int(copy["count"])
			clean.append(copy)
		out["beds"][String(id)] = clean
	out["scope"] = String(data["scope"])
	return out


static func _is_layer_list(layers) -> bool:
	if not layers is Array or (layers as Array).is_empty():
		return false
	for layer in layers:
		if not layer is Dictionary or typeof(layer.get("kind")) != TYPE_STRING:
			return false
		for value in (layer as Dictionary).values():
			if not typeof(value) in [TYPE_STRING, TYPE_INT, TYPE_FLOAT]:
				return false
	return true


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
