extends RefCounted

## Hunters as data (docs/DATA_DRIVEN_CONTENT.md): every res://data/hunters file passes the schema, a migrated hunter's
## profile is exactly the constant it replaced (types, key order, roster position), the loader rejects bad files with
## the file and field named, and the parity fingerprint is printed for the before/after comparison.
##
##   godot --headless --path . res://scenes/validate.tscn -- data_hunters

const Parity := preload("res://scripts/data_parity.gd")

## Dovelle as she was in HunterRoster.PROFILES before the pilot moved her to data/hunters/dovelle.json.
const DOVELLE := {"name": "Dovelle", "tier": "easy", "speed": 0.80, "chase": 3.55, "prog": 0.18, "sight": 8.00,
	"hearing": 1.00, "spawn": 12}

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	_expect(ContentRegistry.errors().is_empty(), "res://data has errors: %s" % ", ".join(ContentRegistry.errors()))
	for id in ContentRegistry.ids("hunters"):
		_expect(HunterRoster.PROFILES.has(id), "data hunter %s is not in HunterRoster.PROFILES" % id)
		var profile: Dictionary = HunterRoster.PROFILES.get(id, {})
		_expect(["easy", "intermediate", "difficult", "special", "void"].has(String(profile.get("tier", ""))),
			"%s has an unknown tier" % id)
		_expect(typeof(profile.get("spawn")) == TYPE_INT, "%s spawn is not an int" % id)
		_expect(float(profile.get("speed", 0)) > 0.0 and float(profile.get("chase", 0)) > 0.0, "%s cannot move" % id)
	# pilot parity: identical value, identical types, identical key order, same place in the roster
	_expect(var_to_str(HunterRoster.PROFILES.get("dovelle", {})) == var_to_str(DOVELLE),
		"dovelle from data differs from the old constant: %s" % var_to_str(HunterRoster.PROFILES.get("dovelle", {})))
	var keys := HunterRoster.PROFILES.keys()
	_expect(keys.find("dovelle") == keys.find("ceryth") + 1 and keys.find("elise") == keys.find("dovelle") + 1,
		"dovelle moved in the roster order")
	_expect(HunterRoster.PROFILES.is_read_only(), "HunterRoster.PROFILES became writable")
	_check_rejections()
	print("  parity hunters %s" % Parity.hunters_hash())
	if _failures == 0:
		print("  data_hunters OK")
	return _failures


## Broken files fail with the file and the field in the message and produce no definition.
func _check_rejections() -> void:
	var cases := {
		"not json {": "line",
		'{"schema": "lr.hunter/1", "id": "x", "name": "X", "tier": "easy", "speed": 1, "chase": 1, "prog": 1, "sight": 1, "hearing": 1, "spawn": 12, "speeed": 2}': "unknown key \"speeed\"",
		'{"schema": "lr.hunter/1", "id": "x", "name": "X", "tier": "easy", "speed": "fast", "chase": 1, "prog": 1, "sight": 1, "hearing": 1, "spawn": 12}': "\"speed\" must be float",
		'{"schema": "lr.hunter/1", "id": "x", "name": "X", "tier": "easy", "speed": 1, "chase": 1, "prog": 1, "sight": 1, "hearing": 1, "spawn": 12.5}': "\"spawn\" must be int",
		'{"schema": "lr.hunter/1", "id": "../x", "name": "X"}': "\"id\" must be",
		'{"schema": "lr.prop/1", "id": "x"}': "schema must be",
	}
	var path := "user://data_hunters_fixture.json"
	for text in cases:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		var parsed := ContentRegistry.parse_file(path, "hunters")
		var joined := " | ".join(parsed["errors"])
		_expect((parsed["defs"] as Array).is_empty() and path in joined and String(cases[text]) in joined,
			"bad hunter file not rejected clearly (%s): %s" % [cases[text], joined])
	DirAccess.remove_absolute(path)
