class_name DeathLines
extends RefCounted

## Death lines (`kyttu-death-lines/v1`), ported from the 2D game's death-lines.js; the data file is the same one.
## A line is a plain string or {text, style?: "caption"}. The pick is seeded (FNV-1a of seed|depth|hunter|salt), never
## random, so the same death on the same route and depth shows the same line on the host and on guests.
## Lines starting with [PLACEHOLDER] only render in debug builds.

const PATH := "res://assets/data/death_lines.json"
const SCHEMA := "kyttu-death-lines/v1"
const CAUSE_KEYS := ["nyxie", "darkness", "deal", "cold"]
const PLACEHOLDER_PREFIX := "[PLACEHOLDER]"
const DEFAULT_COPY := "A hunter intercepted your signal on depth {depth}. Crouch to stay quiet, and save sprinting for a clear escape."

static var _data: Dictionary = {}
static var _loaded := false


static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		var text := FileAccess.get_file_as_string(PATH)
		var parsed = JSON.parse_string(text) if not text.is_empty() else null
		if parsed is Dictionary and validate(parsed).is_empty():
			_data = parsed
	return _data


## Test hook.
static func set_data(value: Dictionary) -> void:
	_data = value
	_loaded = true


## File ids are the lowercased dossier ids: the Godot roster's void_red is voidred there.
static func file_id(hunter_id: String) -> String:
	return hunter_id.to_lower().replace("_", "")


static func line_text(line) -> String:
	if line is String:
		return line
	if line is Dictionary and (line as Dictionary).get("text") is String:
		return String((line as Dictionary)["text"])
	return ""


static func line_style(line, hunter: Dictionary = {}) -> String:
	if line is Dictionary and String((line as Dictionary).get("style", "")) == "caption":
		return "caption"
	if String(hunter.get("style", "")) == "caption":
		return "caption"
	return ""


static func _valid_line(line) -> bool:
	if line is String:
		return not (line as String).strip_edges().is_empty()
	if not line is Dictionary:
		return false
	var d: Dictionary = line
	if not d.get("text") is String or String(d["text"]).strip_edges().is_empty():
		return false
	return not d.has("style") or String(d["style"]) == "caption"


static func validate(d: Dictionary, ids: Array = []) -> Array:
	var errors := []
	if String(d.get("schema", "")) != SCHEMA:
		errors.append("schema must be %s" % SCHEMA)
	if not d.get("hunters") is Dictionary:
		errors.append("hunters must be an object")
		return errors
	if not d.get("causes") is Dictionary:
		errors.append("causes must be an object")
		return errors
	if String(d.get("fallback", "")).strip_edges().is_empty():
		errors.append("fallback must be a non-empty string")
	var hunters: Dictionary = d["hunters"]
	for id in ids:
		if not hunters.has(id):
			errors.append("missing hunter %s" % id)
	for id in hunters:
		var entry: Dictionary = hunters[id]
		for line in entry.get("lines", []):
			if not _valid_line(line):
				errors.append("%s has an invalid line" % id)
		if entry.has("loreLine") and not _valid_line(entry["loreLine"]):
			errors.append("%s.loreLine is invalid" % id)
		if ids.size() > 0 and not ids.has(id):
			errors.append("unknown hunter %s" % id)
	for key in CAUSE_KEYS:
		var list = (d["causes"] as Dictionary).get(key)
		if not list is Array or (list as Array).is_empty():
			errors.append("causes.%s needs 1 or more valid lines" % key)
		else:
			for line in list:
				if not _valid_line(line):
					errors.append("causes.%s has an invalid line" % key)
	return errors


## FNV-1a, 32 bit, over UTF-16 code units like the JS original (the lines are ASCII, so this is byte-stable).
static func hash_text(text: String) -> int:
	var h := 0x811c9dc5
	for i in text.length():
		h ^= text.unicode_at(i)
		h = (h * 0x01000193) & 0xffffffff
	return h


static func cause_key(cause: Dictionary) -> String:
	if cause.is_empty():
		return ""
	var via := String(cause.get("via", ""))
	if via == "deal":
		return "deal"
	if via == "cold":
		return "cold"
	if file_id(String(cause.get("hunter_id", ""))) == "nyxie":
		return "darkness" if String(cause.get("detail", "")) == "darkness" else "nyxie"
	return ""


static func _usable(line, allow_placeholders: bool) -> bool:
	var text := line_text(line)
	if text.strip_edges().is_empty():
		return false
	return allow_placeholders or not text.strip_edges().to_upper().begins_with(PLACEHOLDER_PREFIX)


## {text, source: hunter|cause|fallback|default, style: caption|""}. cause = {hunter_id, via, detail}.
static func pick(cause: Dictionary, seed_text: String, depth: int, display_name: String = "",
		allow_placeholders: bool = OS.is_debug_build()) -> Dictionary:
	var d := data()
	var hunter_id := file_id(String(cause.get("hunter_id", "")))
	var hunter: Dictionary = (d.get("hunters", {}) as Dictionary).get(hunter_id, {})
	var key := cause_key(cause)
	var pool: Array = []
	if key != "":
		for line in (d.get("causes", {}) as Dictionary).get(key, []):
			if _usable(line, allow_placeholders):
				pool.append({"line": line, "source": "cause"})
	if not hunter.is_empty():
		var own: Array = []
		own.append_array(hunter.get("lines", []))
		if hunter.has("loreLine"):
			own.append(hunter["loreLine"])
		for line in own:
			if _usable(line, allow_placeholders):
				pool.append({"line": line, "source": "hunter"})
	if not pool.is_empty():
		var index := hash_text("%s|%d|%s|%s" % [seed_text, depth, hunter_id, key]) % pool.size()
		var picked: Dictionary = pool[index]
		return {"text": _fill(line_text(picked["line"]), depth, display_name),
			"source": String(picked["source"]), "style": line_style(picked["line"], hunter)}
	var fallback := String(d.get("fallback", ""))
	if not fallback.strip_edges().is_empty():
		return {"text": _fill(fallback, depth, display_name), "source": "fallback", "style": ""}
	return {"text": _fill(DEFAULT_COPY, depth, display_name), "source": "default", "style": ""}


static func _fill(text: String, depth: int, display_name: String) -> String:
	return text.replace("{depth}", str(depth)).replace("{name}", display_name)
