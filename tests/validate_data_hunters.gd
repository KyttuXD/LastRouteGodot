extends RefCounted

## Hunters as data (docs/DATA_DRIVEN_CONTENT.md): every res://data/hunters file passes the schema, a migrated hunter's
## profile is exactly the constant it replaced (types, key order, roster position), the loader rejects bad files with
## the file and field named, and the parity fingerprint is printed for the before/after comparison.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- data_hunters

const Parity := preload("res://tests/data_parity.gd")
## Hunter fields added after the code-to-data migration. The FROZEN parity check strips exactly these (and nothing else),
## so a new field has to be listed here on purpose instead of slipping past it. chase_style: HunterChaseStyle.
## taser_immune / melee_immune: the hit immunity of the taser and the crowbar or axe (HunterRoster.taser_immune, melee_immune).
const ADDED_FIELDS := ["chase_style", "taser_immune", "melee_immune"]
## The defaults every built-in hunter file states (and a pack's absent field takes): taser immune, not melee immune.
const DEFAULT_TASER_IMMUNE := true
const DEFAULT_MELEE_IMMUNE := false

## Dovelle as she was in HunterRoster.PROFILES before the pilot moved her to data/hunters/dovelle.json.
const DOVELLE := {"name": "Dovelle", "tier": "easy", "speed": 0.80, "chase": 3.55, "prog": 0.18, "sight": 8.00,
	"hearing": 1.00, "spawn": 12}
## Phase 3 batches: each hunter as the constant was before it moved to data/hunters/<id>.json.
const FROZEN := {
	"dovelle": DOVELLE,
	"aki": {"name": "Aki", "tier": "easy", "speed": 0.82, "chase": 3.55, "prog": 0.20, "sight": 8.20, "hearing": 1.00, "spawn": 11},
	"briselle": {"name": "Briselle", "tier": "easy", "speed": 0.84, "chase": 3.62, "prog": 0.18, "sight": 7.70, "hearing": 1.00, "spawn": 12},
	"ceryth": {"name": "Ceryth", "tier": "intermediate", "speed": 0.78, "chase": 3.45, "prog": 0.17, "sight": 8.60, "hearing": 0.88, "spawn": 12},
	"elise": {"name": "Elise", "tier": "difficult", "speed": 0.82, "chase": 3.58, "prog": 0.18, "sight": 8.10, "hearing": 1.05, "spawn": 12},
	"ferryn": {"name": "Ferryn", "tier": "intermediate", "speed": 0.80, "chase": 2.75, "prog": 0.17, "sight": 8.30, "hearing": 0.92, "spawn": 12},
	"glyra": {"name": "Glyra", "tier": "easy", "speed": 0.81, "chase": 3.52, "prog": 0.18, "sight": 7.90, "hearing": 1.12, "spawn": 12},
	"haelith": {"name": "Haelith", "tier": "easy", "speed": 0.83, "chase": 3.60, "prog": 0.18, "sight": 7.80, "hearing": 1.18, "spawn": 12},
	"ilyra": {"name": "Ilyra", "tier": "intermediate", "speed": 0.77, "chase": 3.68, "prog": 0.17, "sight": 8.70, "hearing": 0.80, "spawn": 12},
	"javelle": {"name": "Javelle", "tier": "easy", "speed": 0.80, "chase": 3.56, "prog": 0.18, "sight": 8.00, "hearing": 1.00, "spawn": 12},
	"kathy": {"name": "Kathy", "tier": "difficult", "speed": 0.82, "chase": 4.15, "prog": 0.20, "sight": 8.20, "hearing": 1.00, "spawn": 16},
	"loxelle": {"name": "Loxelle", "tier": "easy", "speed": 0.80, "chase": 3.555, "prog": 0.18, "sight": 7.90, "hearing": 1.12, "spawn": 13},
	"mavrine": {"name": "Mavrine", "tier": "intermediate", "speed": 0.80, "chase": 3.50, "prog": 0.17, "sight": 8.20, "hearing": 0.95, "spawn": 12},
	"nyxie": {"name": "Nyxie", "tier": "special", "speed": 0.90, "chase": 3.90, "prog": 0.15, "sight": 8.40, "hearing": 0.00, "spawn": 10},
	"opalie": {"name": "Opalie", "tier": "easy", "speed": 0.83, "chase": 3.47, "prog": 0.18, "sight": 7.70, "hearing": 1.10, "spawn": 13},
	"porcelle": {"name": "Porcelle", "tier": "intermediate", "speed": 0.80, "chase": 3.55, "prog": 0.17, "sight": 8.00, "hearing": 0.90, "spawn": 13},
	"quenelle": {"name": "Quenelle", "tier": "easy", "speed": 0.81, "chase": 3.50, "prog": 0.17, "sight": 8.10, "hearing": 0.85, "spawn": 12},
	"ravelle": {"name": "Ravelle", "tier": "difficult", "speed": 0.81, "chase": 3.15, "prog": 0.18, "sight": 7.70, "hearing": 1.00, "spawn": 12},
	"solyth": {"name": "Solyth", "tier": "special", "speed": 0.80, "chase": 3.00, "prog": 0.17, "sight": 7.60, "hearing": 0.95, "spawn": 12},
	"thessine": {"name": "Thessine", "tier": "intermediate", "speed": 0.78, "chase": 3.44, "prog": 0.17, "sight": 8.40, "hearing": 0.90, "spawn": 13},
	"umbriel": {"name": "Umbriel", "tier": "difficult", "speed": 0.82, "chase": 3.46, "prog": 0.18, "sight": 8.50, "hearing": 0.86, "spawn": 12},
	"verrine": {"name": "Verrine", "tier": "intermediate", "speed": 0.83, "chase": 3.66, "prog": 0.18, "sight": 7.70, "hearing": 1.10, "spawn": 13},
	"wynelle": {"name": "Wynelle", "tier": "difficult", "speed": 0.81, "chase": 3.00, "prog": 0.18, "sight": 7.80, "hearing": 1.15, "spawn": 12},
	"xivvy": {"name": "Xivvy", "tier": "intermediate", "speed": 0.97, "chase": 4.35, "prog": 0.12, "sight": 6.72, "hearing": 0.84, "spawn": 13},
	"ysolde": {"name": "Ysolde", "tier": "easy", "speed": 0.80, "chase": 3.54, "prog": 0.18, "sight": 8.10, "hearing": 1.00, "spawn": 12},
	"zellia": {"name": "Zellia", "tier": "easy", "speed": 0.83, "chase": 3.60, "prog": 0.17, "sight": 8.00, "hearing": 0.95, "spawn": 12},
	"void_black": {"name": "Black", "tier": "void", "category": "void", "speed": 0.94, "chase": 4.55, "prog": 0.24, "sight": 9.4, "hearing": 1.22, "spawn": 15, "model": "res://assets/hunters_blocky/void_black/void_black.glb"},
	"void_blue": {"name": "Blue", "tier": "void", "category": "void", "speed": 0.92, "chase": 4.48, "prog": 0.25, "sight": 9.6, "hearing": 1.18, "spawn": 15, "model": "res://assets/hunters_blocky/void_blue/void_blue.glb"},
	"void_brown": {"name": "Brown", "tier": "void", "category": "void", "speed": 0.96, "chase": 4.62, "prog": 0.23, "sight": 9.0, "hearing": 1.30, "spawn": 14, "model": "res://assets/hunters_blocky/void_brown/void_brown.glb"},
	"void_cyan": {"name": "Cyan", "tier": "void", "category": "void", "speed": 0.95, "chase": 4.70, "prog": 0.26, "sight": 9.8, "hearing": 1.16, "spawn": 16, "model": "res://assets/hunters_blocky/void_cyan/void_cyan.glb"},
	"void_gray": {"name": "Gray", "tier": "void", "category": "void", "speed": 0.91, "chase": 4.42, "prog": 0.27, "sight": 10.0, "hearing": 1.12, "spawn": 17, "model": "res://assets/hunters_blocky/void_gray/void_gray.glb"},
	"void_green": {"name": "Green", "tier": "void", "category": "void", "speed": 0.97, "chase": 4.68, "prog": 0.25, "sight": 9.1, "hearing": 1.28, "spawn": 14, "model": "res://assets/hunters_blocky/void_green/void_green.glb"},
	"void_orange": {"name": "Orange", "tier": "void", "category": "void", "speed": 1.00, "chase": 4.82, "prog": 0.28, "sight": 9.2, "hearing": 1.24, "spawn": 14, "model": "res://assets/hunters_blocky/void_orange/void_orange.glb"},
	"void_pink": {"name": "Pink", "tier": "void", "category": "void", "speed": 0.93, "chase": 4.50, "prog": 0.26, "sight": 9.7, "hearing": 1.20, "spawn": 16, "model": "res://assets/hunters_blocky/void_pink/void_pink.glb"},
	"void_purple": {"name": "Purple", "tier": "void", "category": "void", "speed": 0.98, "chase": 4.75, "prog": 0.29, "sight": 9.5, "hearing": 1.15, "spawn": 16, "model": "res://assets/hunters_blocky/void_purple/void_purple.glb"},
	"void_red": {"name": "Red", "tier": "void", "category": "void", "speed": 1.02, "chase": 4.90, "prog": 0.30, "sight": 9.3, "hearing": 1.30, "spawn": 14, "model": "res://assets/hunters_blocky/void_red/void_red.glb"},
	"void_white": {"name": "White", "tier": "void", "category": "void", "speed": 0.90, "chase": 4.45, "prog": 0.24, "sight": 8.8, "hearing": 1.38, "spawn": 17, "model": "res://assets/hunters_blocky/void_white/void_white.glb"},
	"void_yellow": {"name": "Yellow", "tier": "void", "category": "void", "speed": 0.99, "chase": 4.78, "prog": 0.27, "sight": 9.8, "hearing": 1.20, "spawn": 15, "model": "res://assets/hunters_blocky/void_yellow/void_yellow.glb"},
}
## HunterRoster.PROFILES key order before Phase 3 (migrations must keep every hunter's roster position).
const ROSTER_ORDER := ["aki", "briselle", "ceryth", "dovelle", "elise", "ferryn", "glyra", "haelith", "ilyra", "javelle", "kathy", "loxelle", "mavrine", "nyxie", "opalie", "porcelle", "quenelle", "ravelle", "solyth", "thessine", "umbriel", "verrine", "wynelle", "xivvy", "ysolde", "zellia", "void_black", "void_blue", "void_brown", "void_cyan", "void_gray", "void_green", "void_orange", "void_pink", "void_purple", "void_red", "void_white", "void_yellow"]

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
		# hit immunity: every built-in file states the defaults, and the roster reads them the same way
		var file_def: Dictionary = ContentRegistry.get_def("hunters", id)
		_expect(file_def.get("taser_immune") == DEFAULT_TASER_IMMUNE and file_def.get("melee_immune") == DEFAULT_MELEE_IMMUNE,
			"%s is not taser immune and not melee immune in its data file (taser_immune %s, melee_immune %s)" % [id,
				file_def.get("taser_immune"), file_def.get("melee_immune")])
		_expect(HunterRoster.taser_immune(id) == DEFAULT_TASER_IMMUNE and HunterRoster.melee_immune(id) == DEFAULT_MELEE_IMMUNE,
			"HunterRoster reads %s's immunity as taser %s, melee %s" % [id, HunterRoster.taser_immune(id), HunterRoster.melee_immune(id)])
	# migration parity: identical value, identical types, identical key order, same place in the roster
	# fields added after the migration (ADDED_FIELDS) are not part of what it moved, so they are dropped before the compare
	for id in FROZEN:
		_expect(ContentRegistry.has("hunters", id), "%s is frozen as migrated but has no data/hunters file" % id)
		var migrated: Dictionary = HunterRoster.PROFILES.get(id, {}).duplicate()
		for field in ADDED_FIELDS:
			migrated.erase(field)
		_expect(var_to_str(migrated) == var_to_str(FROZEN[id]),
			"%s from data differs from the old constant: %s" % [id, var_to_str(migrated)])
	_expect(HunterRoster.PROFILES.keys() == ROSTER_ORDER, "the roster order changed: %s" % [HunterRoster.PROFILES.keys()])
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
		'{"schema": "lr.hunter/1", "id": "x", "name": "X", "tier": "easy", "speed": 1, "chase": 1, "prog": 1, "sight": 1, "hearing": 1, "spawn": 12, "taser_immune": "yes"}': "\"taser_immune\" must be bool",
		'{"schema": "lr.hunter/1", "id": "x", "name": "X", "tier": "easy", "speed": 1, "chase": 1, "prog": 1, "sight": 1, "hearing": 1, "spawn": 12, "melee_immune": 1}': "\"melee_immune\" must be bool",
		'{"schema": "lr.hunter/1", "id": "x", "name": "X", "tier": "easy", "speed": 1, "chase": 1, "prog": 1, "sight": 1, "hearing": 1, "spawn": 12, "taser_slow_factor": "fast"}': "\"taser_slow_factor\" must be float",
		'{"schema": "lr.hunter/1", "id": "x", "name": "X", "tier": "easy", "speed": 1, "chase": 1, "prog": 1, "sight": 1, "hearing": 1, "spawn": 12, "taser_slow_seconds": true}': "\"taser_slow_seconds\" must be float",
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
