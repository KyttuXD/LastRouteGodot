class_name RoomRecipes
extends RefCounted

## Room recipes as data (docs/DATA_DRIVEN_CONTENT.md, "Room recipes"; docs/modding/content-types.md, "Rooms"). A recipe
## furnishes one room type with the generator's own spec list -- {type, side, depth, facing, wall_backed, wall_mount,
## solid, mount_y} -- plus size-relative positions, ranges, cycled types and seeded conditions. Data recipes are used only
## for room types the generator has no code recipe for (StreamedRouteGenerator._furnished_room_props), so every built-in
## room stays exactly as it was.
##
## Axes (cells, the generator's frame): depth 0 is the first row at the BACK wall, `front` (depth_span - 3) the row whose
## middle cell is the entrance; side 0 is the centre column, `half` = side_span / 2, and side is multiplied by the room's
## seeded mirror unless "mirror": false. Draws come from the recipe's own stream (seed:ROOMDATA:room id): the mirror
## first, then exactly one per `chance` and one per `choose`, per placed value, whether or not the item ends up placed.

const SCHEMA := "lr.room/1"
const ROOT := "res://data/rooms"
const ITEM_KEYS := ["type", "choose", "side", "depth", "facing", "wall_backed", "wall_mount", "solid", "mount_y",
	"mirror", "when"]
const WHEN_KEYS := ["min_side", "max_side", "min_depth", "max_depth", "chance"]
const FACINGS := ["open", "back", "left", "right", "center"]
const REGION_TYPES := ["@frame", "@painting", "@rug"]

static var _builtin := {}
static var _recipes := {}
static var _loaded := false
static var _watching: bool = ContentRegistry.watch(rebuild_from_registry)


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if DirAccess.dir_exists_absolute(ROOT):
		var files := Array(DirAccess.get_files_at(ROOT))
		files.sort()
		for file_name in files:
			if String(file_name).ends_with(".json"):
				var parsed := parse_file(ROOT.path_join(file_name))
				for message in parsed["errors"]:
					push_error("RoomRecipes: " + message)
				if not parsed["def"].is_empty():
					_builtin[String(parsed["def"]["id"])] = parsed["def"]
	rebuild_from_registry()


## Packs changed: built-in data recipes, then the packs' rooms/ (new types and overrides).
static func rebuild_from_registry() -> void:
	if not _loaded:
		return
	_recipes = _builtin.duplicate()
	for def in ContentRegistry.pack_defs("rooms"):
		_recipes[String(def["id"])] = def


static func has(room_type: String) -> bool:
	ensure_loaded()
	return _recipes.has(room_type)


static func builtin_has(room_type: String) -> bool:
	ensure_loaded()
	return _builtin.has(room_type)


## Every prop type a recipe can place (for load-time checks), region tokens left out.
static func types_of(def: Dictionary) -> Array:
	var out := []
	for item in def["items"]:
		for type in (item["choose"].map(func(c): return c["type"]) if item.has("choose") else _as_list(item["type"])):
			if not REGION_TYPES.has(type) and not out.has(type):
				out.append(type)
	return out


## The generator's spec list for `room_type` in a room of this size. `rng` is the recipe's own stream; `region_types`
## maps @frame / @painting / @rug to this region's types ("" = none, the item is skipped).
static func specs(room_type: String, side_span: int, depth_span: int, rng: SeededRandom,
		region_types: Dictionary) -> Array:
	ensure_loaded()
	var def: Dictionary = _recipes.get(room_type, {})
	if def.is_empty():
		return []
	var mirror := -1 if rng.next_float() < .5 else 1
	var sizes := {"back": 0, "front": depth_span - 3, "mid": depth_span / 2, "half": side_span / 2}
	var out := []
	for item in def["items"]:
		var sides := _sides(item["side"], sizes)
		var when: Dictionary = item.get("when", {})
		for index in sides.size():
			# draws first, unconditionally, so sizes and placement never shift later draws
			var passed_chance := not when.has("chance") or rng.next_float() < float(when["chance"])
			var type := _choose(item["choose"], rng.next_float()) if item.has("choose") \
				else String(_as_list(item["type"])[index % _as_list(item["type"]).size()])
			if not passed_chance or not _fits(when, side_span, depth_span):
				continue
			if REGION_TYPES.has(type):
				type = String(region_types.get(type, ""))
				if type.is_empty():
					continue
			var side := int(sides[index]) * (mirror if bool(item.get("mirror", true)) else 1)
			var spec := {"type": type, "side": side, "depth": _position(item["depth"], sizes),
				"facing": String(item.get("facing", "open"))}
			for key in ["wall_backed", "wall_mount", "solid", "mount_y"]:
				if item.has(key):
					spec[key] = item[key]
			out.append(spec)
	return out


static func _fits(when: Dictionary, side_span: int, depth_span: int) -> bool:
	return side_span >= int(when.get("min_side", 0)) and side_span <= int(when.get("max_side", 1 << 20)) \
		and depth_span >= int(when.get("min_depth", 0)) and depth_span <= int(when.get("max_depth", 1 << 20))


static func _choose(options: Array, roll: float) -> String:
	var total := 0.0
	for option in options:
		total += float(option["weight"])
	var at := roll * total
	for option in options:
		at -= float(option["weight"])
		if at < 0.0:
			return String(option["type"])
	return String(options.back()["type"])


static func _sides(value, sizes: Dictionary) -> Array:
	if value is Array:
		return range(_position(value[0], sizes), _position(value[1], sizes), int(value[2]))
	return [_position(value, sizes)]


## An int, or a size word with an optional sign and offset: "front", "front-1", "mid", "half-1", "-half+1".
static func _position(value, sizes: Dictionary) -> int:
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		return int(value)
	var text := String(value)
	var sign := -1 if text.begins_with("-") else 1
	text = text.trim_prefix("-")
	var offset := 0
	for op in ["+", "-"]:
		if text.contains(op):
			offset = int(text.get_slice(op, 1)) * (1 if op == "+" else -1)
			text = text.get_slice(op, 0)
	return sign * int(sizes.get(text, 0)) + offset


static func _as_list(value) -> Array:
	return value if value is Array else [value]


## One lr.room/1 file -> {"def": {"id", "items"}, "errors"}: every item checked (keys, positions, types, conditions).
static func parse_file(path: String) -> Dictionary:
	var out := {"def": {}, "errors": PackedStringArray()}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		out["errors"].append("%s: not a JSON object" % path)
		return out
	var errors: PackedStringArray = out["errors"]
	for key in data:
		if not key in ["schema", "id", "items"]:
			errors.append("%s: unknown key \"%s\"" % [path, key])
	if String(data.get("schema", "")) != SCHEMA:
		errors.append("%s: schema must be %s" % [path, SCHEMA])
	var id = data.get("id")
	if typeof(id) != TYPE_STRING or not ContentRegistry._is_id(id):
		errors.append("%s: \"id\" must be letters, digits or _" % path)
	var items = data.get("items")
	if not items is Array or (items as Array).is_empty():
		errors.append("%s: items must be a non-empty array" % path)
		return out
	var index := 0
	for item in items:
		_check_item(item, "%s: items[%d]" % [path, index], errors)
		index += 1
	if errors.is_empty():
		out["def"] = {"id": id, "items": items}
	return out


static func _check_item(item, where: String, errors: PackedStringArray) -> void:
	if not item is Dictionary:
		errors.append("%s: not an object" % where)
		return
	for key in item:
		if not ITEM_KEYS.has(key):
			errors.append("%s: unknown key \"%s\"" % [where, key])
	if item.has("type") == item.has("choose"):
		errors.append("%s: needs exactly one of \"type\" or \"choose\"" % where)
	if item.has("type") and not (_is_type(item["type"]) or (item["type"] is Array and not item["type"].is_empty()
			and item["type"].all(_is_type))):
		errors.append("%s: type must be a prop id, @frame/@painting/@rug, or a list of them" % where)
	if item.has("choose") and not (item["choose"] is Array and not item["choose"].is_empty() and item["choose"].all(
			func(c): return c is Dictionary and _is_type(c.get("type")) and typeof(c.get("weight")) in [TYPE_INT,
				TYPE_FLOAT] and float(c["weight"]) > 0.0)):
		errors.append("%s: choose must be [{type, weight > 0}]" % where)
	if not item.has("side") or not (_is_position(item["side"]) or (item["side"] is Array and item["side"].size() == 3
			and _is_position(item["side"][0]) and _is_position(item["side"][1]) and typeof(item["side"][2]) in [TYPE_INT,
				TYPE_FLOAT] and int(item["side"][2]) != 0)):
		errors.append("%s: side must be a position or [from, to, step]" % where)
	if not item.has("depth") or not _is_position(item["depth"]):
		errors.append("%s: depth must be a position (cells, back, front, mid, with +/- offsets)" % where)
	if item.has("facing") and not FACINGS.has(item["facing"]):
		errors.append("%s: facing must be one of %s" % [where, FACINGS])
	for flag in ["wall_backed", "wall_mount", "solid", "mirror"]:
		if item.has(flag) and typeof(item[flag]) != TYPE_BOOL:
			errors.append("%s: %s must be true or false" % [where, flag])
	if item.has("mount_y") and not typeof(item["mount_y"]) in [TYPE_INT, TYPE_FLOAT]:
		errors.append("%s: mount_y must be a number (metres)" % where)
	var when = item.get("when", {})
	if not when is Dictionary:
		errors.append("%s: when must be an object" % where)
		return
	for key in when:
		if not WHEN_KEYS.has(key) or not typeof(when[key]) in [TYPE_INT, TYPE_FLOAT]:
			errors.append("%s: when.%s is not one of %s (numbers)" % [where, key, WHEN_KEYS])
	if when.has("chance") and (float(when["chance"]) < 0.0 or float(when["chance"]) > 1.0):
		errors.append("%s: when.chance must be 0-1" % where)


static func _is_type(value) -> bool:
	return typeof(value) == TYPE_STRING and (REGION_TYPES.has(value) or ContentRegistry._is_id(value))


static func _is_position(value) -> bool:
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		return float(value) == floorf(float(value))
	if typeof(value) != TYPE_STRING:
		return false
	var text := String(value).trim_prefix("-")
	var word := text
	for op in ["+", "-"]:
		if text.contains(op):
			word = text.get_slice(op, 0)
			if not text.get_slice(op, 1).is_valid_int():
				return false
	return word in ["back", "front", "mid", "half"]
