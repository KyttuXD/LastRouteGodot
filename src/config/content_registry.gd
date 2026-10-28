class_name ContentRegistry
extends RefCounted

## Props, regions and hunters defined as data (docs/DATA_DRIVEN_CONTENT.md). Every JSON file under res://data/<kind>/ is
## parsed once, checked against the schema below, and turned into the same runtime values the old GDScript constants
## held (Vector3 sizes, int spawn distances, keys in the old order) so a migrated entry is indistinguishable from the
## constant it replaced.
##
## Migrating an entry: the old constant keeps its key but the value becomes DATA, and the constant is renamed and wrapped
## by a static var that calls resolve() (or splice() for arrays). Readers keep using the old name; key order is kept.
## Unknown keys, wrong types and missing fields are errors with the file and field named, never silently skipped.
##
## Built-in content only for now. Mod packs (user://mods) reuse parse_file() with the same schemas in a later phase.

const DATA := "@data"
const ROOT := "res://data"
const KINDS := ["props", "regions", "hunters"]

## Field -> type. "vec3" is [x, y, z] in JSON, "strings" an array of strings. A trailing "?" marks an optional field.
const HUNTER_FIELDS := {"name": "string", "tier": "string", "category": "string?", "speed": "float",
	"chase": "float", "prog": "float", "sight": "float", "hearing": "float", "spawn": "int", "model": "string?"}
const PROP_FIELDS := {"models": "strings", "themes": "strings?", "coordinated": "bool?"}
const REGION_FIELDS := {"hall_floor": "strings", "hall_runner": "bool", "room_default_floor": "strings",
	"room_roles": "strings", "shop_names": "dict_strings?", "room_door": "string?", "double_room_door": "string?",
	"prop_set": "prop_set"}
const SCHEMAS := {"hunters": "lr.hunter/1", "props": "lr.prop/1", "regions": "lr.region/1"}

static var _loaded := false
static var _defs := {"props": {}, "regions": {}, "hunters": {}}
static var _families := {}
static var _errors := PackedStringArray()


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for kind in KINDS:
		var dir := "%s/%s" % [ROOT, kind]
		var files := Array(DirAccess.get_files_at(dir))
		files.sort()
		for file_name in files:
			if not String(file_name).ends_with(".json"):
				continue
			var parsed := parse_file("%s/%s" % [dir, file_name], kind)
			_errors.append_array(parsed["errors"])
			for def in parsed["defs"]:
				var id := String(def["id"])
				if _defs[kind].has(id):
					_errors.append("%s/%s: duplicate %s id \"%s\"" % [dir, file_name, kind, id])
					continue
				_defs[kind][id] = def
				if kind == "props":
					var family := String(def["family"])
					if not _families.has(family):
						_families[family] = []
					_families[family].append(id)
	for message in _errors:
		push_error("ContentRegistry: " + message)


static func errors() -> PackedStringArray:
	ensure_loaded()
	return _errors


static func has(kind: String, id: String) -> bool:
	ensure_loaded()
	return _defs[kind].has(id)


static func get_def(kind: String, id: String) -> Dictionary:
	ensure_loaded()
	return _defs[kind].get(id, {})


static func ids(kind: String) -> PackedStringArray:
	ensure_loaded()
	var out := PackedStringArray(_defs[kind].keys())
	out.sort()
	return out


static func family(name: String) -> Array:
	ensure_loaded()
	return _families.get(name, [])


## `code` with every DATA value replaced by `field` of the def with that key (field "" = the whole def minus id/family).
## A DATA key with no def is an error and is dropped, so a missing file fails the data_* suites instead of half-loading.
static func resolve(code: Dictionary, kind: String, field: String = "") -> Dictionary:
	var out := {}
	for key in code:
		var value = code[key]
		if typeof(value) == TYPE_STRING and value == DATA:
			var def := get_def(kind, String(key))
			if def.is_empty() or (not field.is_empty() and not def.has(field)):
				push_error("ContentRegistry: %s \"%s\" is marked as data but res://data has no %s for it"
					% [kind, key, field if not field.is_empty() else "definition"])
				continue
			value = _without_meta(def) if field.is_empty() else def[field]
		out[key] = value
	out.make_read_only()
	return out


## `code` with each "@data:<family>" element replaced by that prop family's ids whose `flag` field is true, in file order.
static func splice(code: Array, flag: String) -> Array:
	var out := []
	for value in code:
		if typeof(value) == TYPE_STRING and String(value).begins_with(DATA + ":"):
			for id in family(String(value).trim_prefix(DATA + ":")):
				if bool(get_def("props", id).get(flag, false)):
					out.append(id)
		else:
			out.append(value)
	out.make_read_only()
	return out


static func _without_meta(def: Dictionary) -> Dictionary:
	var out := def.duplicate(true)
	out.erase("id")
	out.erase("family")
	out.make_read_only()
	return out


## Parse one file of `kind`: {"defs": [runtime dicts], "errors": [messages naming file and field]}.
static func parse_file(path: String, kind: String) -> Dictionary:
	var errors := PackedStringArray()
	var defs := []
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {"defs": [], "errors": ["%s: missing or empty" % path]}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"defs": [], "errors": ["%s: line %d: %s" % [path, json.get_error_line(), json.get_error_message()]]}
	var root = json.data
	if typeof(root) != TYPE_DICTIONARY:
		return {"defs": [], "errors": ["%s: top level is not an object" % path]}
	if root.get("schema", "") != SCHEMAS[kind]:
		return {"defs": [], "errors": ["%s: schema must be \"%s\"" % [path, SCHEMAS[kind]]]}
	if kind == "props":
		for key in root:
			if not key in ["schema", "family", "props"]:
				errors.append("%s: unknown key \"%s\"" % [path, key])
		if typeof(root.get("family")) != TYPE_STRING or typeof(root.get("props")) != TYPE_ARRAY:
			errors.append("%s: a prop file needs \"family\" (string) and \"props\" (array)" % path)
			return {"defs": [], "errors": errors}
		var index := 0
		for entry in root["props"]:
			var def := _parse_entry(entry, PROP_FIELDS, "%s: props[%d]" % [path, index], errors)
			if not def.is_empty():
				def["family"] = root["family"]
				defs.append(def)
			index += 1
	else:
		var copy: Dictionary = root.duplicate()
		copy.erase("schema")
		var def := _parse_entry(copy, HUNTER_FIELDS if kind == "hunters" else REGION_FIELDS, path, errors)
		if not def.is_empty():
			defs.append(def)
	return {"defs": defs if errors.is_empty() else [], "errors": errors}


static func _parse_entry(entry, fields: Dictionary, where: String, errors: PackedStringArray) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		errors.append("%s: not an object" % where)
		return {}
	var id = entry.get("id")
	if typeof(id) != TYPE_STRING or not _is_id(id):
		errors.append("%s: \"id\" must be letters, digits or _" % where)
		return {}
	for key in entry:
		if key != "id" and not fields.has(key):
			errors.append("%s (%s): unknown key \"%s\"" % [where, id, key])
	var def := {"id": id}
	for field in fields:
		var type := String(fields[field])
		var optional := type.ends_with("?")
		type = type.trim_suffix("?")
		if not entry.has(field):
			if not optional:
				errors.append("%s (%s): missing \"%s\"" % [where, id, field])
			continue
		var value = _convert(entry[field], type)
		if value == null:
			errors.append("%s (%s): \"%s\" must be %s" % [where, id, field, type])
			continue
		def[field] = value
	return def


## JSON value -> runtime value of `type`, or null when it does not fit.
static func _convert(value, type: String):
	match type:
		"string":
			return value if typeof(value) == TYPE_STRING else null
		"bool":
			return value if typeof(value) == TYPE_BOOL else null
		"float":
			return float(value) if typeof(value) in [TYPE_FLOAT, TYPE_INT] else null
		"int":
			return int(value) if typeof(value) in [TYPE_FLOAT, TYPE_INT] and float(value) == floorf(float(value)) else null
		"vec3":
			if typeof(value) != TYPE_ARRAY or value.size() != 3 or not value.all(func(v): return typeof(v) in [TYPE_FLOAT, TYPE_INT]):
				return null
			return Vector3(value[0], value[1], value[2])
		"strings":
			if typeof(value) != TYPE_ARRAY or not value.all(func(v): return typeof(v) == TYPE_STRING):
				return null
			return value
		"dict_strings":
			if typeof(value) != TYPE_DICTIONARY or not value.values().all(func(v): return typeof(v) == TYPE_STRING):
				return null
			return value
		"prop_set":
			if typeof(value) != TYPE_ARRAY:
				return null
			var out := []
			for item in value:
				if typeof(item) != TYPE_DICTIONARY or typeof(item.get("type")) != TYPE_STRING:
					return null
				for key in item:
					if not key in ["type", "size", "solid"]:
						return null
				var size = _convert(item.get("size"), "vec3")
				if size == null or (item.has("solid") and typeof(item["solid"]) != TYPE_BOOL):
					return null
				var choice := {"type": item["type"], "size": size}
				if item.has("solid"):
					choice["solid"] = item["solid"]
				out.append(choice)
			return out
	return null


static func _is_id(value: String) -> bool:
	if value.is_empty():
		return false
	for c in value:
		if not (c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")):
			return false
	return true
