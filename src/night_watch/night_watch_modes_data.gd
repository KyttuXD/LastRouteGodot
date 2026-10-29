class_name NightWatchModesData
extends RefCounted

## The 2D Night Watch's mode table, copied verbatim from games/night-watch/src/modes/registry.js (mode ids, titles, taglines,
## blurbs, shift names, presets, casts, Custom Night sliders). The Godot menus, the Custom Night page and the mode framework
## all read this, so the 3D menus and the 2D menus cannot drift apart; scripts/validate_night_watch_menus.gd checks the screens
## against it. The modes now live in res://data/night_watch/modes/ (one file each); regenerate those from the 2D registry, do not hand-edit.

const MAX_AI := 20
const POINTS_PER_LEVEL := 10
## [minimum share of the top score, rating] from the 2D account/merge.js, best first.
const RATINGS := [[1.0, "Unbeatable!"], [0.8, "Perfect!"], [0.6, "Stupendous!"], [0.4, "Amazing!"], [0.2, "Fantastic!"], [0.0, "Great Job!"]]

const NAMES := {
 "aki": "Aki",
 "briselle": "Briselle",
 "ceryth": "Ceryth",
 "dovelle": "Dovelle",
 "elise": "Elise",
 "ferryn": "Ferryn",
 "glyra": "Glyra",
 "haelith": "Haelith",
 "ilyra": "Ilyra",
 "javelle": "Javelle",
 "kathy": "Kathy",
 "loxelle": "Loxelle",
 "mavrine": "Mavrine",
 "nyxie": "Nyxie",
 "opalie": "Opalie",
 "porcelle": "Porcelle",
 "quenelle": "Quenelle",
 "ravelle": "Ravelle",
 "solyth": "Solyth",
 "thessine": "Thessine",
 "umbriel": "Umbriel",
 "verrine": "Verrine",
 "wynelle": "Wynelle",
 "xivvy": "Xivvy",
 "ysolde": "Ysolde",
 "zellia": "Zellia"
}

## The Shift Board entries, read from res://data/night_watch/modes/<id>.json (nw.mode/1 "menu", NIGHT-WATCH-DATA-PLAN.md Phase 1) in the files'
## "order", each exactly the 2D registry entry. JSON has no integers: whole numbers come back as int (the 2D table has no fractions).
static var MODES: Array = _modes_from_data()
static var _watching: bool = ContentRegistry.watch(rebuild_from_registry)


static func rebuild_from_registry() -> void:
	MODES = _modes_from_data()


static func _modes_from_data() -> Array:
	var rows := []
	for id in ContentRegistry.ids("nw_modes"):
		var def := ContentRegistry.get_def("nw_modes", id)
		rows.append([float(def.get("order", 1000.0)), String(id), def["menu"]])
	rows.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and String(x[1]) < String(y[1])))
	var out := []
	for row in rows:
		out.append(_ints(row[2]))
	return out


## JSON numbers back to the ints the table was written with; a copy, never the registry's read-only value.
static func _ints(value):
	match typeof(value):
		TYPE_FLOAT:
			return int(value) if is_equal_approx(value, roundf(value)) else value
		TYPE_ARRAY:
			return Array(value).map(func(v): return _ints(v))
		TYPE_DICTIONARY:
			var out := {}
			for key in value:
				out[key] = _ints(value[key])
			return out
	return value


static func mode(id: String) -> Dictionary:
	for m in MODES:
		if String(m["id"]) == id:
			return m
	return {}


static func rating_of(score: int, max_score: int) -> String:
	var share := float(score) / float(max_score) if max_score > 0 else 0.0
	for r in RATINGS:
		if share >= float(r[0]):
			return String(r[1])
	return String(RATINGS[RATINGS.size() - 1][1])
