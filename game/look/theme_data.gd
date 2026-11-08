extends RefCounted

## District and room themes as data (docs/WALL_THEMES.md, "Themes as data"): the two extension kinds declared in
## res://data/kinds/themes.json. ContentRegistry loads the files (built-in and from packs, overrides, hash, hot-swap) and
## calls validate() on every entry; RefLook and PropModelCatalog build their tables from what it loaded.
##
##   region_themes (lr.region_theme/1), one file per district, id = the region id RefLook.wall_kind is called with:
##     "wall":    [wall kinds]   the district's wall set, picked per 4-cell patch (RefLook.wall_kind), order matters
##     "ceiling": "kind"         the district's ceiling kind
##     "accent":  {"texture": "floor"|"wall", "kind", "tint": "#rrggbb", "metal": bool}   arch / pilaster trim
##     "finish":  "Mansion"      the district's furniture finish (PropModelCatalog.region_finish), "" for none
##   room_themes (lr.room_theme/1), one file per room purpose:
##     "wall":    [wall kinds]   the purpose's own wall set (overrides the district's)
##
## Every field of a region theme is optional; a missing one falls back to the built-in theme of the same id, then to the
## maze. Kinds must be painted surfaces (RefTextures.*_PAINTERS); packs re-picture a kind through walls/ceilings, they
## do not add kinds. Finishes are model sets built by the prop tools, so a theme may only name one that exists.
## No expressions, no code: themes only pick, in order, from what the game already paints.

const FINISHES := ["Mansion"]
const ACCENT_TEXTURES := ["floor", "wall"]
const REGION_FIELDS := ["id", "wall", "ceiling", "accent", "finish"]
const ROOM_FIELDS := ["id", "wall"]
const ACCENT_FIELDS := ["texture", "kind", "tint", "metal"]
const MAX_KINDS := 16


static func validate(kind: String, entry: Dictionary, where: String) -> PackedStringArray:
	var errors := PackedStringArray()
	var fields: Array = REGION_FIELDS if kind == "region_themes" else ROOM_FIELDS
	if not kind in ["region_themes", "room_themes"]:
		errors.append("%s: theme_data does not know kind %s" % [where, kind])
		return errors
	for key in entry:
		if not fields.has(key):
			errors.append("%s: unknown key \"%s\"" % [where, key])
	if kind == "room_themes" and not entry.has("wall"):
		errors.append("%s: a room theme needs \"wall\"" % where)
	if kind == "region_themes" and entry.size() <= 1:
		errors.append("%s: a region theme needs at least one of wall, ceiling, accent, finish" % where)
	if entry.has("wall"):
		_check_kinds(entry["wall"], RefTextures.WALL_PAINTERS, "%s: wall" % where, errors)
	if entry.has("ceiling"):
		var ceiling = entry["ceiling"]
		if typeof(ceiling) != TYPE_STRING or not RefTextures.CEILING_PAINTERS.has(ceiling):
			errors.append("%s: ceiling must be a ceiling kind (%s)" % [where, ", ".join(RefTextures.CEILING_PAINTERS.keys())])
	if entry.has("accent"):
		_check_accent(entry["accent"], "%s: accent" % where, errors)
	if entry.has("finish"):
		var finish = entry["finish"]
		if typeof(finish) != TYPE_STRING or not (String(finish).is_empty() or FINISHES.has(finish)):
			errors.append("%s: finish must be \"\" or one of %s" % [where, ", ".join(FINISHES)])
	return errors


static func _check_kinds(value, painters: Dictionary, where: String, errors: PackedStringArray) -> void:
	if typeof(value) != TYPE_ARRAY or value.is_empty() or value.size() > MAX_KINDS:
		errors.append("%s must be a list of 1 to %d wall kinds" % [where, MAX_KINDS])
		return
	for item in value:
		if typeof(item) != TYPE_STRING or not painters.has(item):
			errors.append("%s: \"%s\" is not a wall kind" % [where, item])


static func _check_accent(value, where: String, errors: PackedStringArray) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s must be an object {texture, kind, tint, metal}" % where)
		return
	for key in value:
		if not ACCENT_FIELDS.has(key):
			errors.append("%s: unknown key \"%s\"" % [where, key])
	for key in ACCENT_FIELDS:
		if not value.has(key):
			errors.append("%s: missing \"%s\"" % [where, key])
	if not errors.is_empty():
		return
	if typeof(value["texture"]) != TYPE_STRING or not ACCENT_TEXTURES.has(value["texture"]):
		errors.append("%s: texture must be floor or wall" % where)
		return
	var painters: Dictionary = RefTextures.FLOOR_PAINTERS if value["texture"] == "floor" else RefTextures.WALL_PAINTERS
	if typeof(value["kind"]) != TYPE_STRING or not painters.has(value["kind"]):
		errors.append("%s: kind \"%s\" is not a %s kind" % [where, value["kind"], value["texture"]])
	if typeof(value["tint"]) != TYPE_STRING or not Color.html_is_valid(value["tint"]):
		errors.append("%s: tint must be a colour \"#rrggbb\"" % where)
	if typeof(value["metal"]) != TYPE_BOOL:
		errors.append("%s: metal must be true or false" % where)


## A region theme's accent as RefLook.ARCH_ACCENT holds it: [texture group, kind, tint, metal].
static func accent_array(accent: Dictionary) -> Array:
	return [String(accent["texture"]), String(accent["kind"]), Color(String(accent["tint"])), bool(accent["metal"])]
