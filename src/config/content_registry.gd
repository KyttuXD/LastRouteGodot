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
## Built-in content is the res://data tree; player packs (ContentPacks, user://mods) layer on top through load_packs()
## and come off again with unload_packs(), no restart. Every table built by resolve() is rebuilt on both, so with no
## pack loaded everything is exactly the built-in game.

const DATA := "@data"
const ROOT := "res://data"
const KINDS := ["props", "regions", "hunters"]

## Field -> type. "vec3" is [x, y, z] in JSON, "strings" an array of strings. A trailing "?" marks an optional field.
const HUNTER_FIELDS := {"name": "string", "tier": "string", "category": "string?", "speed": "float",
	"chase": "float", "prog": "float", "sight": "float", "hearing": "float", "spawn": "int", "model": "string?", "portrait": "string?"}
## `batchable`: may the view draw repeated placements of this prop in one MultiMesh. Absent = the default in
## PropModelCatalog.is_batchable() (pure dressing yes, anything interactive no).
const PROP_FIELDS := {"models": "strings", "themes": "strings?", "coordinated": "bool?", "batchable": "bool?"}
const REGION_FIELDS := {"hall_floor": "strings", "hall_runner": "bool", "room_default_floor": "strings",
	"room_roles": "strings", "shop_names": "dict_strings?", "room_door": "string?", "double_room_door": "string?",
	"prop_set": "prop_set"}
const SCHEMAS := {"hunters": "lr.hunter/1", "props": "lr.prop/1", "regions": "lr.region/1"}

static var _loaded := false
## Built-in definitions (res://data) and families, never changed after loading.
static var _builtin := {"props": {}, "regions": {}, "hunters": {}}
static var _builtin_families := {}
static var _builtin_hash := ""
## What readers see: built-in plus the loaded packs.
static var _defs := {"props": {}, "regions": {}, "hunters": {}}
static var _families := {}
static var _errors := PackedStringArray()
## Loaded packs (ContentPacks.read() results) sorted by pack id; per kind, id -> pack id for every pack definition and
## the sorted ids packs added (as opposed to overrode).
static var _packs: Array = []
static var _origin := {"props": {}, "regions": {}, "hunters": {}}
static var _added := {"props": [], "regions": [], "hunters": []}
## Pack asset path -> stripped PackedScene (models) or ImageTexture (PNGs), dropped on unload.
static var _assets := {}
## Rebuild callbacks of the tables built from the registry (watch()). The registry never names its readers, so loading
## it never loads them: a reader loaded later builds its tables from whatever packs are loaded at that moment.
static var _watchers: Array[Callable] = []
## Code tables whose keys are built-in ids that are not (yet) data, read by path for the same reason.
const _CODE_IDS := {"hunters": ["res://src/config/hunter_roster.gd", "_CODE_PROFILES"],
	"props": ["res://src/config/prop_model_catalog.gd", "_CODE_MODEL_PATHS"],
	"regions": ["res://src/game/streamed_route_generator.gd", "REGIONS"]}


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var hash_lines := PackedStringArray()
	for kind in KINDS:
		var dir := "%s/%s" % [ROOT, kind]
		var files := Array(DirAccess.get_files_at(dir))
		files.sort()
		for file_name in files:
			if not String(file_name).ends_with(".json"):
				continue
			var path := "%s/%s" % [dir, file_name]
			hash_lines.append("%s %s" % [ContentPacks._sha256(FileAccess.get_file_as_bytes(path)), path])
			var parsed := parse_file(path, kind)
			_errors.append_array(parsed["errors"])
			for def in parsed["defs"]:
				var id := String(def["id"])
				if _builtin[kind].has(id):
					_errors.append("%s/%s: duplicate %s id \"%s\"" % [dir, file_name, kind, id])
					continue
				_builtin[kind][id] = def
				if kind == "props":
					var family := String(def["family"])
					if not _builtin_families.has(family):
						_builtin_families[family] = []
					_builtin_families[family].append(id)
	_builtin_hash = ContentPacks._sha256("\n".join(hash_lines).to_utf8_buffer())
	_apply([])
	for message in _errors:
		push_error("ContentRegistry: " + message)


## Load exactly `dirs` (pack folders), replacing whatever packs were loaded. All or nothing: any error in any pack leaves
## the current state untouched. Returns {"ok", "packs": [summary], "errors", "hash"}.
static func load_packs(dirs: Array, limits: Dictionary = ContentPacks.LIMITS, folder_is_id: bool = true) -> Dictionary:
	ensure_loaded()
	var report := {"ok": false, "packs": [], "errors": PackedStringArray(), "hash": pack_hash()}
	var read := []
	for dir in dirs:
		var pack := ContentPacks.read(String(dir), limits, folder_is_id)
		report["errors"].append_array(pack["errors"])
		read.append(pack)
	if report["errors"].is_empty():
		report["errors"].append_array(_conflicts(read))
	if not report["errors"].is_empty():
		return report
	read.sort_custom(func(a: Dictionary, b: Dictionary): return String(a["manifest"]["id"]) < String(b["manifest"]["id"]))
	_packs = read
	_apply(read)
	_rebuild_consumers()
	report["ok"] = true
	report["packs"] = loaded_packs()
	report["hash"] = pack_hash()
	return report


## Back to the built-in game. Nodes already instanced from pack models belong to the world being torn down.
static func unload_packs() -> void:
	ensure_loaded()
	if _packs.is_empty():
		return
	_packs = []
	_apply([])
	_rebuild_consumers()


## [{id, name, version, author, size, sha256, dir}] of the loaded packs, sorted by id. `size` is the pack's bytes.
static func loaded_packs() -> Array:
	var out := []
	for pack in _packs:
		var manifest: Dictionary = pack["manifest"]
		var size := 0
		for file in pack["files"]:
			size += int(file["bytes"])
		out.append({"id": manifest["id"], "name": manifest["name"], "version": manifest["version"],
			"author": manifest.get("author", ""), "size": size, "sha256": pack["sha256"], "dir": pack["dir"]})
	return out


## Fingerprint of everything that shapes a world: the built-in data files and each loaded pack's id, version and files.
## Two peers with the same hash and seed generate the same world.
static func pack_hash() -> String:
	ensure_loaded()
	var lines := PackedStringArray(["builtin " + _builtin_hash])
	for pack in loaded_packs():
		lines.append("%s %s %s" % [pack["id"], pack["version"], pack["sha256"]])
	return ContentPacks._sha256("\n".join(lines).to_utf8_buffer())


## The vanilla fingerprint (no packs), for public rooms.
static func builtin_pack_hash() -> String:
	ensure_loaded()
	return ContentPacks._sha256(("builtin " + _builtin_hash).to_utf8_buffer())


## Pack id that defines `id` of `kind`, "" when it is built-in.
static func pack_of(kind: String, id: String) -> String:
	ensure_loaded()
	return String(_origin[kind].get(id, ""))


## Ids that loaded packs added (not overrides), sorted.
static func added_ids(kind: String) -> Array:
	ensure_loaded()
	return _added[kind]


## A loaded pack's model, stripped of scripts and extension nodes; null for anything outside a loaded pack.
static func pack_scene(path: String) -> PackedScene:
	if _assets.has(path):
		return _assets[path]
	if not _packs.any(func(pack: Dictionary): return path.begins_with(String(pack["dir"]) + "/")):
		push_warning("ContentRegistry: %s is not part of a loaded pack" % path)
		return null
	var scene := ContentPacks.load_scene(path)
	_assets[path] = scene
	return scene


## A loaded pack's PNG as a nearest-filtered texture; null for anything outside a loaded pack.
static func pack_texture(path: String) -> Texture2D:
	if _assets.has(path):
		return _assets[path]
	if not _packs.any(func(pack: Dictionary): return path.begins_with(String(pack["dir"]) + "/")):
		push_warning("ContentRegistry: %s is not part of a loaded pack" % path)
		return null
	var image := Image.load_from_file(path)
	var texture: Texture2D = ImageTexture.create_from_image(image) if image != null else null
	_assets[path] = texture
	return texture


static func _apply(packs: Array) -> void:
	_assets.clear()
	_defs = {}
	_origin = {}
	_added = {}
	for kind in KINDS:
		_defs[kind] = _builtin[kind].duplicate()
		_origin[kind] = {}
		_added[kind] = []
	_families = {}
	for family in _builtin_families:
		_families[family] = _builtin_families[family].duplicate()
	for pack in packs:
		var pack_id := String(pack["manifest"]["id"])
		for kind in KINDS:
			for def in pack["defs"][kind]:
				var id := String(def["id"])
				_defs[kind][id] = def
				_origin[kind][id] = pack_id
				if not pack["manifest"].get("overrides", []).has("%s/%s" % [kind, id]):
					_added[kind].append(id)
				if kind == "props":
					_families.get_or_add(String(def["family"]), []).append(id)
	for kind in KINDS:
		_added[kind].sort()
		_added[kind].make_read_only()


## Errors only visible across packs: one id from two packs, overrides of ids the game does not have, prop sets naming
## unknown props.
static func _conflicts(packs: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	var by_id := {}
	var props := {}
	for pack in packs:
		var pack_id := String(pack["manifest"]["id"])
		if by_id.has(pack_id):
			errors.append("%s: pack id \"%s\" is also used by %s" % [pack["dir"], pack_id, by_id[pack_id]])
		by_id[pack_id] = pack["dir"]
		for entry in pack["manifest"].get("overrides", []):
			var parts := String(entry).split("/")
			if not _is_builtin_id(parts[0], parts[1]):
				errors.append("%s: overrides \"%s\", which the game does not have" % [pack["dir"], entry])
		for kind in KINDS:
			for def in pack["defs"][kind]:
				var key := "%s/%s" % [kind, def["id"]]
				if seen.has(key):
					errors.append("%s: %s is also defined by pack %s" % [pack["dir"], key, seen[key]])
				seen[key] = pack_id
				if kind == "props":
					props[def["id"]] = true
	for pack in packs:
		for def in pack["defs"]["regions"]:
			for choice in def["prop_set"]:
				var type := String(choice["type"])
				if not props.has(type) and not _is_builtin_id("props", type):
					errors.append("%s: region %s prop_set type \"%s\" is not a known prop" % [pack["dir"], def["id"],
						type])
	return errors


static func _is_builtin_id(kind: String, id: String) -> bool:
	if _builtin[kind].has(id):
		return true
	var source: Array = _CODE_IDS[kind]
	return load(source[0]).get_script_constant_map()[source[1]].has(id)


## Register `rebuild`, called whenever the loaded packs change. Returns true, for use in a static var initializer:
##   static var _watching: bool = ContentRegistry.watch(rebuild_from_registry)
static func watch(rebuild: Callable) -> bool:
	_watchers.append(rebuild)
	return true


static func _rebuild_consumers() -> void:
	for rebuild in _watchers:
		rebuild.call()


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
	return resolve_with(code, kind, func(def: Dictionary): return _without_meta(def) if field.is_empty() else def.get(field),
		field)


## resolve() with `project` turning a def into the table's value (for tables built from several fields).
## Loaded packs: an overridden key takes the pack's def (an optional field the override leaves out falls back to the
## built-in value), and ids packs added are appended after the code keys, sorted. No packs = the code table as before.
static func resolve_with(code: Dictionary, kind: String, project: Callable, field: String = "") -> Dictionary:
	ensure_loaded()
	var out := {}
	for key in code:
		var value = code[key]
		if _origin[kind].has(String(key)):
			var override := get_def(kind, String(key))
			if field.is_empty() or override.has(field):
				out[key] = project.call(override)
				continue
			var builtin: Dictionary = _builtin[kind].get(String(key), {})
			if builtin.has(field):
				out[key] = project.call(builtin)
			elif not (typeof(value) == TYPE_STRING and value == DATA):
				out[key] = value
			continue
		if typeof(value) == TYPE_STRING and value == DATA:
			var def := get_def(kind, String(key))
			if def.is_empty() or (not field.is_empty() and not def.has(field)):
				push_error("ContentRegistry: %s \"%s\" is marked as data but res://data has no %s for it"
					% [kind, key, field if not field.is_empty() else "definition"])
				continue
			value = project.call(def)
		out[key] = value
	for id in _added[kind]:
		var def := get_def(kind, id)
		if field.is_empty() or def.has(field):
			out[id] = project.call(def)
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
		"files":
			if typeof(value) != TYPE_ARRAY or not value.all(func(v): return typeof(v) == TYPE_DICTIONARY \
					and typeof(v.get("path")) == TYPE_STRING and typeof(v.get("sha256")) == TYPE_STRING \
					and typeof(v.get("size")) in [TYPE_INT, TYPE_FLOAT]):
				return null
			return value
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
