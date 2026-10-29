extends RefCounted

## Night Watch as data, Phase 0 (docs/NIGHT_WATCH_DATA.md): the eight nw.* schemas accept a valid entry of each kind and reject the bad
## ones with the file and the field named, and the Night Watch parity fingerprint is printed for the before/after of every migration commit.
##
##   godot --headless --path . res://scenes/validate.tscn -- data_night_watch

const Parity := preload("res://scripts/data_parity.gd")

const GOOD := {
	"nw_modes": {"schema": "nw.mode/1", "id": "classic", "menu": {"id": "classic", "title": "CLASSIC", "label": "1. CLASSIC"}, "rules": "classic",
		"office": "classic_security", "cast": "classic", "levels": 7, "colors": {"accent": "#e0b04a"}},
	"nw_rules": {"schema": "nw.rules/1", "id": "classic", "ruleset": "classic", "params": {"night_ms": 270000.0, "door_grace_ms": [9000.0, 8200.0]}},
	"nw_casts": {"schema": "nw.cast/1", "id": "classic", "hunters": [{"id": "dovelle", "levels": [0, 2, 4], "poses": {"door": "peek"}}]},
	"nw_offices": {"schema": "nw.office/1", "id": "classic_security", "room": {"w": 6.0, "d": 5.0, "h": 3.6}, "spawn": [0, 0, 1.6],
		"entrances": [{"id": "doorL", "kind": "door_slab", "position": [-3, 0, 0]}], "stations": [{"id": "monitor", "position": [0, 1, -1]}],
		"pieces": [{"kind": "wall", "size": [1, 0.1, 0.03], "position": [0, 1.3, 2.45]}]},
	"nw_buildings": {"schema": "nw.building/1", "id": "classic", "rooms": {"stage": {}}, "graph": {"stage": ["hall"]}},
	"nw_calls": {"schema": "nw.calls/1", "id": "classic", "levels": [{"lines": ["Hello, hello?"]}]},
	"nw_sounds": {"schema": "nw.sounds/1", "id": "classic", "cues": {"door": {"synth": {"wave": "square", "freq": 120}}, "scare": {"file": "scare.ogg"}}},
	"nw_scares": {"schema": "nw.scare/1", "id": "classic", "scares": {"dovelle": {"duration_ms": 1200, "distance": 0.9}}},
}

## [kind, entry, a fragment the error must contain]
const BAD := [
	["nw_modes", {"id": "x", "menu": {"id": "x", "title": "X", "label": "X"}, "rules": "chess"}, "rules"],
	["nw_modes", {"id": "x", "menu": {"id": "x", "title": "X", "label": "X"}, "levels": 99}, "levels"],
	["nw_modes", {"id": "x", "menu": {"id": "x", "title": "X", "label": "X"}, "script": "res://x.gd"}, "unknown field 'script'"],
	["nw_modes", {"id": "x", "menu": {"title": "X"}}, "menu is missing 'id'"],
	["nw_rules", {"id": "x", "ruleset": "classic", "params": {"pace": "1 + 1"}}, "params.pace"],
	["nw_rules", {"id": "x", "ruleset": "poker", "params": {}}, "ruleset"],
	["nw_casts", {"id": "x", "hunters": [{"id": "a", "poses": {"dance": "x"}}]}, "poses.dance"],
	["nw_offices", {"id": "x", "room": {"w": 6.0, "d": 5.0, "h": 2.5}, "spawn": [0, 0, 0], "entrances": [], "stations": []}, "room.h"],
	["nw_offices", {"id": "x", "room": {"w": 6.0, "d": 5.0, "h": 3.6}, "spawn": [0, 0, 0], "entrances": [], "stations": [], "pieces": [{"size": [99, 1, 1]}]}, "pieces[0].size"],
	["nw_calls", {"id": "x", "levels": [{"text": "hi"}]}, "levels[0]"],
	["nw_sounds", {"id": "x", "cues": {"door": {"file": "door.mp3"}}}, "cues.door.file"],
	["nw_scares", {"id": "x", "scares": {"a": {"duration_ms": 60000}}}, "duration_ms"],
	["nw_offices", {"id": "x"}, "missing required field 'room'"],
]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	_expect(NwSchemas.SCHEMAS.size() == 8 and NwSchemas.FIELDS.size() == 8, "there are not eight nw.* kinds")
	for kind in GOOD:
		var errors := NwSchemas.validate(String(kind), GOOD[kind], "good/%s.json" % kind)
		_expect(errors.is_empty(), "a valid %s entry was rejected: %s" % [kind, errors])
	for case in BAD:
		var errors := NwSchemas.validate(String(case[0]), case[1], "bad/%s.json" % case[0])
		_expect(Array(errors).any(func(e): return String(e).contains(String(case[2])) and String(e).begins_with("bad/")),
			"a bad %s entry was not rejected on %s (got %s)" % [case[0], case[2], errors])
	_expect(DirAccess.dir_exists_absolute("res://data/night_watch"), "res://data/night_watch is missing")
	# the kinds are declared to DATA's registry (res://data/kinds/night_watch.json) and it knows them
	for kind in NwSchemas.SCHEMAS:
		_expect(ContentRegistry.pack_kinds().has(kind), "ContentRegistry does not know the Night Watch kind %s" % kind)
	_expect(ContentRegistry.errors().is_empty(), "res://data has errors: %s" % ", ".join(ContentRegistry.errors()))
	print("  parity nw %s" % Parity.nw_hash())
	if _failures == 0:
		print("  data_night_watch  8 nw.* schemas accept the valid entries and reject %d bad ones by file and field" % BAD.size())
		print("data_night_watch OK")
	return _failures
