class_name NightWatchCallsData
extends RefCounted

## Zellia's headset calls, copied verbatim from the 2D game: each mode's `CALLS` table
## ({"level": {at: seconds into the night she rings, lines: [...]}}), keyed by the 3D mode id (Open Air is `extra`). Mixed Shift and a
## Custom Night have no call (2D: `callForNight` is null / `opts.custom` gives no script). The tables now live in res://data/night_watch/calls/ (one file per mode); they are fixed reference data from the original 2D game, do not hand-edit.
## tests/validate_night_watch_calls.gd compares the same tables against the recorded 2D reference data (tests/data/night_watch_2d_calls.json).
## The 2D wording is kept exactly, including its key names (the 2D keys are A/D doors, Q/E lights, Space cameras).

## Timings from the 2D game's call box, ms.
const INCOMING_MS := 2200       # "Incoming call..." shows this long before the first line (the ring)
const WORD_MS := 250            # one more word every 250 ms
const LINE_BASE_MS := 1800      # a line stays up for this plus ...
const LINE_WORD_MS := 380       # ... this per word
const INCOMING_TEXT := "Incoming call…"

## Read from res://data/night_watch/calls/<mode>.json (nw.calls/1, NIGHT-WATCH-DATA-PLAN.md Phase 1), rebuilt in this exact shape and in the
## files' "order": {"<mode>": {"<level>": {at, lines}}}. A pack may override a mode's calls ("overrides": ["nw_calls/<mode>"]) or add its own.
static var CALLS: Dictionary = _calls_from_data()
static var _watching: bool = ContentRegistry.watch(rebuild_from_registry)


static func rebuild_from_registry() -> void:
	CALLS = _calls_from_data()


static func _calls_from_data() -> Dictionary:
	var rows := []
	for id in ContentRegistry.ids("nw_calls"):
		var def := ContentRegistry.get_def("nw_calls", id)
		rows.append([float(def.get("order", 1000.0)), String(id), def])
	rows.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and String(x[1]) < String(y[1])))
	var out := {}
	for row in rows:
		var table := {}
		for level in (row[2] as Dictionary)["levels"]:
			table[String(level["level"])] = {"at": int(level["at"]), "lines": Array(level["lines"]).duplicate()}
		out[row[1]] = table
	return out


## {at, lines} for a level of a mode, or {} when it is a quiet night.
static func for_level(mode_id: String, level: int) -> Dictionary:
	var table: Dictionary = CALLS.get(mode_id, {})
	return table.get(str(level), {})
