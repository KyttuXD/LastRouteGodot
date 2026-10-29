class_name NwSchemas
extends RefCounted

## Night Watch content as data (docs/NIGHT_WATCH_DATA.md): the eight `nw.*/1` schemas and their checks. ContentRegistry (DATA's) loads the
## files and runs `validate(kind, def, path)` on each entry; this file only says what a valid entry is. Same rules as the `lr.*` kinds: an
## unknown key is an error, every required key is present with the right type, numbers are in range. No expressions, no code: a pack picks
## one of the built-in rulesets (RULESETS) and tunes it.

const SCHEMAS := {
	"nw_modes": "nw.mode/1", "nw_rules": "nw.rules/1", "nw_casts": "nw.cast/1", "nw_offices": "nw.office/1",
	"nw_buildings": "nw.building/1", "nw_calls": "nw.calls/1", "nw_sounds": "nw.sounds/1", "nw_scares": "nw.scare/1",
}

## The rule engines a mode may run (KT: packs may use all nine). Each name is one logic class; its parameters are listed by the engine.
const RULESETS := ["classic", "mask", "lure", "bedroom", "story", "dayshift", "mixed", "openair", "descent"]

## The pose states a cast entry may give a pose for.
const POSE_STATES := ["idle", "walk", "peek", "door", "vent", "window", "scare"]

## Geometry bounds for a data office (the loader also runs the office contract: walkable, reachable, hunter clearance, lights).
const MAX_OFFICE_PIECES := 400
const MAX_PIECE_SIZE := 12.0
const ROOM_LIMITS := {"w": [2.0, 30.0], "d": [2.0, 30.0], "h": [3.2, 8.0]}

## field -> [type, required]. TYPE_ARRAY / TYPE_DICTIONARY hold JSON values; numbers are TYPE_FLOAT (JSON has no ints; whole numbers are
## checked where a count is meant).
const FIELDS := {
	"nw_modes": {"id": [TYPE_STRING, true], "title": [TYPE_STRING, true], "kicker": [TYPE_STRING, false], "blurb": [TYPE_STRING, true],
		"order": [TYPE_FLOAT, false], "rules": [TYPE_STRING, true], "office": [TYPE_STRING, true], "building": [TYPE_STRING, false],
		"cast": [TYPE_STRING, true], "levels": [TYPE_FLOAT, true], "presets": [TYPE_ARRAY, false], "custom": [TYPE_ARRAY, false],
		"ratings": [TYPE_ARRAY, false], "colors": [TYPE_DICTIONARY, false], "texts": [TYPE_DICTIONARY, false]},
	"nw_rules": {"id": [TYPE_STRING, true], "ruleset": [TYPE_STRING, true], "params": [TYPE_DICTIONARY, true]},
	"nw_casts": {"id": [TYPE_STRING, true], "hunters": [TYPE_ARRAY, true]},
	"nw_offices": {"id": [TYPE_STRING, true], "title": [TYPE_STRING, false], "room": [TYPE_DICTIONARY, true], "spawn": [TYPE_ARRAY, true],
		"entrances": [TYPE_ARRAY, true], "stations": [TYPE_ARRAY, true], "pieces": [TYPE_ARRAY, false], "lamps": [TYPE_ARRAY, false],
		"palette": [TYPE_DICTIONARY, false], "tone_cue": [TYPE_STRING, false]},
	"nw_buildings": {"id": [TYPE_STRING, true], "rooms": [TYPE_DICTIONARY, true], "graph": [TYPE_DICTIONARY, true], "cams": [TYPE_ARRAY, false],
		"paths": [TYPE_DICTIONARY, false]},
	"nw_calls": {"id": [TYPE_STRING, true], "order": [TYPE_FLOAT, false], "levels": [TYPE_ARRAY, true]},
	"nw_sounds": {"id": [TYPE_STRING, true], "cues": [TYPE_DICTIONARY, true]},
	"nw_scares": {"id": [TYPE_STRING, true], "scares": [TYPE_DICTIONARY, true]},
}


## The problems with one entry of `kind` (the file minus "schema", with its "id") read from `path`: empty when it is valid, each naming the file and
## the field. ContentRegistry calls this for the kinds declared in res://data/kinds/night_watch.json (DATA's extension kinds).
static func validate(kind: String, def: Dictionary, path: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if not FIELDS.has(kind):
		return PackedStringArray(["%s: unknown Night Watch kind %s" % [path, kind]])
	var fields: Dictionary = FIELDS[kind]
	for key in def:
		if not fields.has(key) and key != "schema":
			errors.append("%s: unknown field '%s'" % [path, key])
	for key in fields:
		var spec: Array = fields[key]
		if not def.has(key):
			if bool(spec[1]):
				errors.append("%s: missing required field '%s'" % [path, key])
			continue
		var want := int(spec[0])
		var got := typeof(def[key])
		if not (got == want or (want == TYPE_FLOAT and got == TYPE_INT)):
			errors.append("%s: '%s' is %s, want %s" % [path, key, type_string(got), type_string(want)])
	if not errors.is_empty():
		return errors
	match kind:
		"nw_modes":
			_check_count(def, "levels", 1, 20, path, errors)
			if not RULESETS.has(String(def["rules"])) and not String(def["rules"]).contains("_"):
				errors.append("%s: 'rules' names no ruleset or rules entry: %s" % [path, def["rules"]])
			for key in def.get("colors", {}):
				if Color.html_is_valid(String(def["colors"][key])) == false:
					errors.append("%s: colors.%s is not a colour" % [path, key])
		"nw_rules":
			if not RULESETS.has(String(def["ruleset"])):
				errors.append("%s: 'ruleset' %s is not one of %s" % [path, def["ruleset"], RULESETS])
			for key in def["params"]:
				var v = def["params"][key]
				if typeof(v) in [TYPE_STRING, TYPE_OBJECT, TYPE_CALLABLE]:
					errors.append("%s: params.%s is %s: parameters are numbers, booleans or tables of them" % [path, key, type_string(typeof(v))])
		"nw_casts":
			for i in (def["hunters"] as Array).size():
				var h = def["hunters"][i]
				if typeof(h) != TYPE_DICTIONARY or not (h as Dictionary).has("id"):
					errors.append("%s: hunters[%d] has no id" % [path, i])
					continue
				for state in (h as Dictionary).get("poses", {}):
					if not POSE_STATES.has(String(state)):
						errors.append("%s: hunters[%d].poses.%s is not a pose state %s" % [path, i, state, POSE_STATES])
		"nw_offices":
			var room: Dictionary = def["room"]
			for axis in ROOM_LIMITS:
				var limits: Array = ROOM_LIMITS[axis]
				var v := float(room.get(axis, -1.0))
				if v < float(limits[0]) or v > float(limits[1]):
					errors.append("%s: room.%s %.2f is outside %s" % [path, axis, v, limits])
			var pieces: Array = def.get("pieces", [])
			if pieces.size() > MAX_OFFICE_PIECES:
				errors.append("%s: %d pieces, the limit is %d" % [path, pieces.size(), MAX_OFFICE_PIECES])
			for i in pieces.size():
				var size: Array = (pieces[i] as Dictionary).get("size", []) if typeof(pieces[i]) == TYPE_DICTIONARY else []
				if size.size() != 3 or size.any(func(x): return typeof(x) not in [TYPE_FLOAT, TYPE_INT] or float(x) <= 0.0 or float(x) > MAX_PIECE_SIZE):
					errors.append("%s: pieces[%d].size must be three numbers in (0, %.0f]" % [path, i, MAX_PIECE_SIZE])
		"nw_calls":
			for i in (def["levels"] as Array).size():
				var level = def["levels"][i]
				if typeof(level) != TYPE_DICTIONARY or typeof((level as Dictionary).get("lines", null)) != TYPE_ARRAY:
					errors.append("%s: levels[%d] has no 'lines' list" % [path, i])
		"nw_sounds":
			for cue in def["cues"]:
				var c = def["cues"][cue]
				if typeof(c) != TYPE_DICTIONARY or not ((c as Dictionary).has("synth") or (c as Dictionary).has("file")):
					errors.append("%s: cues.%s needs 'synth' (a recipe) or 'file' (a pack .ogg/.wav)" % [path, cue])
				elif (c as Dictionary).has("file") and not String(c["file"]).get_extension().to_lower() in ["ogg", "wav"]:
					errors.append("%s: cues.%s.file must be .ogg or .wav" % [path, cue])
		"nw_scares":
			for hunter in def["scares"]:
				var s = def["scares"][hunter]
				if typeof(s) != TYPE_DICTIONARY:
					errors.append("%s: scares.%s is not a table" % [path, hunter])
					continue
				_check_count(s, "duration_ms", 200, 6000, "%s: scares.%s" % [path, hunter], errors)
	return errors


static func _check_count(def: Dictionary, key: String, lo: float, hi: float, where: String, errors: PackedStringArray) -> void:
	if not def.has(key):
		return
	var v := float(def[key])
	if v < lo or v > hi:
		errors.append("%s: '%s' %s is outside [%s, %s]" % [where, key, def[key], lo, hi])
