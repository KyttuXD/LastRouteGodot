class_name LootTables
extends RefCounted

## What a chunk's pickups are, as data (`lr.loot/1`, res://data/loot, docs/DATA_DRIVEN_CONTENT.md "Loot tables"). The
## generators keep WHERE things lie (free floor cells, stair and seal exclusions) and the objective (relays, the sealed
## wing's bonus relay and guaranteed tool, SealRules); a table says WHAT else turns up and how often. Every chance is one
## draw of the chunk's seeded stream in file order, exactly as the code tables it replaced, so the same seed gives the
## same loot (data_loot checks the hash).
##
## Built-in tables: `route` (every streamed region without a table of its own) and `sewer` (the sewer levels). A pack
## overrides one with `"overrides": ["loot/route"]`, or adds `<pack>_<name>` with `"regions": [...]` to loot those
## regions instead (the first such pack table by id wins a region). Packs only reweight the items the game already has:
## no new kinds, no new items, no scripts. This file is also the kind's validator (res://data/kinds/loot.json).

const KIND := "loot"
const DEFAULT_ID := "route"
## What a table may place besides relays (relays are the objective, placed by the generators).
const KINDS := ["battery", "coin", "tool", "backpack"]
## World tools a table may hand out: each has a pickup model (RouteInteractable3D.TOOL_PICKUP_MODELS) and an inventory
## slot. The flashlight is not one: every runner starts with it.
const TOOL_ITEMS := ["taser", "lockpick", "crowbar", "rescue_axe", "stim_pack", "revive_kit"]
const BACKPACK_ITEMS := ["backpack_small", "backpack_medium", "backpack_large"]
## Caps so a pack cannot carpet a chunk (the free cells run out first anyway).
const MAX_BASE := 4
const MAX_ROLLS := 8
const MAX_TOOLS := 8
const MAX_AID := 4
## A backpack's size rank grows by one every this many levels down.
const BACKPACK_DEPTH_STEP := 4.0

## field -> [type, required]
const FIELDS := {"id": [TYPE_STRING, true], "regions": [TYPE_ARRAY, false], "base": [TYPE_ARRAY, true],
	"rolls": [TYPE_ARRAY, true], "tools": [TYPE_ARRAY, true], "backpacks": [TYPE_ARRAY, false], "aid": [TYPE_ARRAY, false]}

## region -> table, built on first use and dropped whenever packs change.
static var _by_region := {}
static var _watching: bool = ContentRegistry.watch(rebuild_from_registry)


static func rebuild_from_registry() -> void:
	_by_region = {}


## The table that loots `region`: a pack table naming it, else a built-in table with that id (sewer), else `route`.
static func table_for(region: String) -> Dictionary:
	if _by_region.has(region):
		return _by_region[region]
	var table := {}
	for id in ContentRegistry.added_ids(KIND):
		var def := ContentRegistry.get_def(KIND, String(id))
		if Array(def.get("regions", [])).has(region):
			table = def
			break
	if table.is_empty() and not ContentRegistry.added_ids(KIND).has(region):
		table = ContentRegistry.get_def(KIND, region)
	if table.is_empty():
		table = ContentRegistry.get_def(KIND, DEFAULT_ID)
	_by_region[region] = table
	return table


## The table's chance rolls, one draw each in file order: the kinds that came up.
static func roll(table: Dictionary, rng: SeededRandom) -> Array:
	var out := []
	for entry in table.get("rolls", []):
		if rng.next_float() < float(entry["chance"]):
			out.append(String(entry["kind"]))
	return out


## The item a planned pickup of `kind` holds ("" for relays, batteries and coins). Tools and backpacks take draws.
static func item_for(kind: String, table: Dictionary, rng: SeededRandom, coord: Vector3i) -> String:
	if kind == "tool":
		return pick_tool(table, rng)
	if kind == "backpack":
		return pick_backpack(table, rng, coord.y)
	return ""


## One world tool by weight: a single draw. Weights need not add up to 1; they are scaled when they do not.
static func pick_tool(table: Dictionary, rng: SeededRandom) -> String:
	var tools: Array = table.get("tools", [])
	var roll_value := rng.next_float()
	if tools.is_empty():
		return ""
	var total := 0.0
	for entry in tools:
		total += float(entry["weight"])
	if absf(total - 1.0) > 1e-6:
		roll_value *= total
	for entry in tools:
		roll_value -= float(entry["weight"])
		if roll_value < 0.0:
			return String(entry["item"])
	return String(tools[0]["item"])


## A backpack: deeper levels allow bigger ones (rank 1 + one per BACKPACK_DEPTH_STEP levels down), one draw for the rank.
static func pick_backpack(table: Dictionary, rng: SeededRandom, level: int) -> String:
	var packs: Array = table.get("backpacks", [])
	var n := maxi(1, packs.size())
	var depth_rank := clampi(1 + floori(maxf(0.0, -float(level)) / BACKPACK_DEPTH_STEP), 1, n)
	var rolled_rank := clampi(1 + rng.next_index(depth_rank), 1, n)
	return String(packs[rolled_rank - 1]) if not packs.is_empty() else ""


## Aid items (Stim Packs, Revive Kits): one draw each, in file order, from the chunk's own aid stream.
static func roll_aid(table: Dictionary, rng: SeededRandom, coop: bool) -> Array:
	var out := []
	for entry in table.get("aid", []):
		var chance := float(entry.get("chance_coop", entry["chance"])) if coop else float(entry["chance"])
		if rng.next_float() < chance:
			out.append(String(entry["item"]))
	return out


## Tool ids and weights of a table, in file order (the old PICKUP_TYPES / PICKUP_WEIGHTS shape).
static func tool_ids(table: Dictionary) -> Array:
	return Array(table.get("tools", [])).map(func(entry): return String(entry["item"]))


static func tool_weights(table: Dictionary) -> Dictionary:
	var out := {}
	for entry in table.get("tools", []):
		out[String(entry["item"])] = float(entry["weight"])
	return out


## ContentRegistry's validator for the `loot` kind: the problems with one entry (the file minus "schema"), each naming
## `path` and the field; empty when it is valid.
static func validate(kind: String, def: Dictionary, path: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if kind != KIND:
		return PackedStringArray(["%s: unknown loot kind %s" % [path, kind]])
	for key in def:
		if not FIELDS.has(key):
			errors.append("%s: unknown field '%s'" % [path, key])
	for key in FIELDS:
		var spec: Array = FIELDS[key]
		if not def.has(key):
			if bool(spec[1]):
				errors.append("%s: missing required field '%s'" % [path, key])
			continue
		if typeof(def[key]) != int(spec[0]):
			errors.append("%s: '%s' has the wrong type" % [path, key])
	if not errors.is_empty():
		return errors
	for i in def.get("regions", []).size():
		var region = def["regions"][i]
		if typeof(region) != TYPE_STRING or String(region).is_empty() or String(region) != String(region).to_lower():
			errors.append("%s: regions[%d] must be a lower-case region id" % [path, i])
	var base: Array = def["base"]
	if base.size() > MAX_BASE:
		errors.append("%s: base has more than %d entries" % [path, MAX_BASE])
	for i in base.size():
		if typeof(base[i]) != TYPE_STRING or not KINDS.has(base[i]):
			errors.append("%s: base[%d] must be one of %s" % [path, i, ", ".join(KINDS)])
	var rolls: Array = def["rolls"]
	if rolls.size() > MAX_ROLLS:
		errors.append("%s: rolls has more than %d entries" % [path, MAX_ROLLS])
	for i in rolls.size():
		errors.append_array(_entry(rolls[i], {"kind": KINDS, "chance": "chance"}, "%s: rolls[%d]" % [path, i]))
	var tools: Array = def["tools"]
	if tools.is_empty() or tools.size() > MAX_TOOLS:
		errors.append("%s: tools needs 1 to %d entries" % [path, MAX_TOOLS])
	for i in tools.size():
		errors.append_array(_entry(tools[i], {"item": TOOL_ITEMS, "weight": "weight"}, "%s: tools[%d]" % [path, i]))
	var backpacks: Array = def.get("backpacks", [])
	if backpacks.size() > BACKPACK_ITEMS.size():
		errors.append("%s: backpacks has more than %d entries" % [path, BACKPACK_ITEMS.size()])
	for i in backpacks.size():
		if typeof(backpacks[i]) != TYPE_STRING or not BACKPACK_ITEMS.has(backpacks[i]):
			errors.append("%s: backpacks[%d] must be one of %s" % [path, i, ", ".join(BACKPACK_ITEMS)])
	var places_backpacks := base.has("backpack") or rolls.any(func(e): return e is Dictionary and e.get("kind") == "backpack")
	if places_backpacks and backpacks.is_empty():
		errors.append("%s: backpacks is needed when base or rolls place a backpack" % path)
	var aid: Array = def.get("aid", [])
	if aid.size() > MAX_AID:
		errors.append("%s: aid has more than %d entries" % [path, MAX_AID])
	for i in aid.size():
		errors.append_array(_entry(aid[i], {"item": TOOL_ITEMS, "chance": "chance", "chance_coop": "chance?"},
			"%s: aid[%d]" % [path, i]))
	return errors


## One object of a list: `fields` maps key -> allowed strings, "chance" (0..1), "weight" (> 0); a trailing "?" = optional.
static func _entry(entry, fields: Dictionary, where: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if not entry is Dictionary:
		return PackedStringArray(["%s: not an object" % where])
	for key in entry:
		if not fields.has(key):
			errors.append("%s: unknown field '%s'" % [where, key])
	for key in fields:
		var rule = fields[key]
		var optional: bool = rule is String and String(rule).ends_with("?")
		if not entry.has(key):
			if not optional:
				errors.append("%s: missing '%s'" % [where, key])
			continue
		var value = entry[key]
		if rule is Array:
			if typeof(value) != TYPE_STRING or not rule.has(value):
				errors.append("%s.%s must be one of %s" % [where, key, ", ".join(rule)])
		elif String(rule).trim_suffix("?") == "chance":
			if not (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) or float(value) < 0.0 or float(value) > 1.0:
				errors.append("%s.%s must be a number from 0 to 1" % [where, key])
		elif String(rule) == "weight":
			if not (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) or float(value) <= 0.0 or float(value) > 100.0:
				errors.append("%s.%s must be a number above 0 (up to 100)" % [where, key])
	return errors
