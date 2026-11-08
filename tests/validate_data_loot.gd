extends RefCounted

## Loot tables as data (lr.loot/1, res://data/loot, LootTables; docs/DATA_DRIVEN_CONTENT.md "Loot tables"): the built-in
## tables are the old code numbers, the same seed gives the same loot as the old code (draw for draw), a pack can
## override a built-in table or add one for some regions, unloading gives back the vanilla loot exactly, and bad tables
## (unknown fields such as a script, new items, relays) are refused by file and field.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- data_loot

const Parity := preload("res://tests/data_parity.gd")
const ROOT := "user://data_loot_test"

## The code tables this replaced (staging 29b79686): StreamedRouteGenerator._pickups / pick_tool / BACKPACK_TYPES,
## GameConfig.STIM_PACK_CHANCE / REVIVE_KIT_CHANCE_*, SewerRouteGenerator._pickups.
const OLD_TOOLS := ["taser", "lockpick", "crowbar", "rescue_axe"]
const OLD_WEIGHTS := {"taser": 0.3, "lockpick": 0.3, "crowbar": 0.3, "rescue_axe": 0.1}
const OLD_BACKPACKS := ["backpack_small", "backpack_medium", "backpack_large"]
## Loot parity hash (Parity.loot_hash) on staging 29b79686 before the move; printed, and equal on the commit after it.
const STAGING_LOOT_HASH := "ff29abcc6793cf9e"

const GOOD := {"id": "x", "base": ["battery"], "rolls": [{"kind": "coin", "chance": 0.5}],
	"tools": [{"item": "taser", "weight": 2}], "backpacks": ["backpack_small"],
	"aid": [{"item": "stim_pack", "chance": 0.1, "chance_coop": 0.2}], "regions": ["hotel"]}
## [entry, a fragment the error must contain]
const BAD := [
	[{"id": "x", "base": [], "rolls": [], "tools": [{"item": "taser", "weight": 1}], "script": "res://x.gd"}, "unknown field 'script'"],
	[{"id": "x", "base": ["relay"], "rolls": [], "tools": [{"item": "taser", "weight": 1}]}, "base[0]"],
	[{"id": "x", "base": [], "rolls": [{"kind": "relay", "chance": 1}], "tools": [{"item": "taser", "weight": 1}]}, "rolls[0].kind"],
	[{"id": "x", "base": [], "rolls": [{"kind": "coin", "chance": 1.5}], "tools": [{"item": "taser", "weight": 1}]}, "rolls[0].chance"],
	[{"id": "x", "base": [], "rolls": [], "tools": [{"item": "flashlight", "weight": 1}]}, "tools[0].item"],
	[{"id": "x", "base": [], "rolls": [], "tools": [{"item": "taser", "weight": 0}]}, "tools[0].weight"],
	[{"id": "x", "base": [], "rolls": [], "tools": []}, "tools needs"],
	[{"id": "x", "base": ["backpack"], "rolls": [], "tools": [{"item": "taser", "weight": 1}]}, "backpacks is needed"],
	[{"id": "x", "base": [], "rolls": [], "tools": [{"item": "taser", "weight": 1}], "backpacks": ["backpack_huge"]}, "backpacks[0]"],
	[{"id": "x", "base": [], "rolls": [], "tools": [{"item": "taser", "weight": 1}], "aid": [{"item": "stim_pack"}]}, "aid[0]: missing 'chance'"],
	[{"id": "x", "base": [], "rolls": [], "tools": [{"item": "taser", "weight": 1}], "regions": ["Hotel"]}, "regions[0]"],
	[{"id": "x", "rolls": [], "tools": [{"item": "taser", "weight": 1}]}, "missing required field 'base'"],
	[{"id": "x", "base": ["coin", "coin", "coin", "coin", "coin"], "rolls": [], "tools": [{"item": "taser", "weight": 1}]}, "more than 4"],
]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	_wipe()
	_expect(ContentRegistry.pack_kinds().has(LootTables.KIND), "ContentRegistry does not know the loot kind")
	_expect(ContentRegistry.errors().is_empty(), "res://data has errors: %s" % ", ".join(ContentRegistry.errors()))
	_check_schema()
	_check_builtin()
	_check_draw_parity()
	var vanilla := Parity.loot_hash()
	print("  parity loot %s (staging before the move: %s)" % [vanilla, STAGING_LOOT_HASH])
	_expect(Parity.loot_hash() == vanilla, "the same seed gave different loot twice")
	_check_override(vanilla)
	_check_added(vanilla)
	_check_refused(vanilla)
	_wipe()
	if _failures == 0:
		print("  data_loot  route + sewer tables match the old code draw for draw; packs override/add and unload cleanly; %d bad tables refused" % BAD.size())
		print("data_loot OK")
	return _failures


func _check_schema() -> void:
	_expect(LootTables.validate("loot", GOOD, "good.json").is_empty(), "a valid table was rejected: %s" % [
		LootTables.validate("loot", GOOD, "good.json")])
	for case in BAD:
		var errors := LootTables.validate("loot", case[0], "bad/loot.json")
		_expect(Array(errors).any(func(e): return String(e).contains(String(case[1])) and String(e).begins_with("bad/")),
			"a bad table was not refused on %s (got %s)" % [case[1], errors])


## The shipped tables hold exactly the numbers the code had.
func _check_builtin() -> void:
	var route := LootTables.table_for("hotel")
	_expect(route == ContentRegistry.get_def("loot", "route"), "a region without its own table does not use route")
	_expect(LootTables.tool_ids(route) == OLD_TOOLS and LootTables.tool_weights(route) == OLD_WEIGHTS,
		"route tools changed: %s" % [LootTables.tool_weights(route)])
	_expect(StreamedRouteGenerator.PICKUP_TYPES == OLD_TOOLS and StreamedRouteGenerator.PICKUP_WEIGHTS == OLD_WEIGHTS,
		"PICKUP_TYPES / PICKUP_WEIGHTS no longer mirror the route table")
	_expect(Array(route["base"]) == ["battery"] and route["backpacks"] == OLD_BACKPACKS, "route base/backpacks changed")
	_expect(var_to_str(route["rolls"]) == var_to_str([{"kind": "tool", "chance": 0.72}, {"kind": "battery", "chance": 0.38},
		{"kind": "coin", "chance": 0.30}, {"kind": "backpack", "chance": 0.16}]), "route rolls changed: %s" % [route["rolls"]])
	_expect(var_to_str(route["aid"]) == var_to_str([{"item": "stim_pack", "chance": 0.18},
		{"item": "revive_kit", "chance": 0.03, "chance_coop": 0.06}]), "route aid changed: %s" % [route["aid"]])
	var sewer := LootTables.table_for("sewer")
	_expect(sewer == ContentRegistry.get_def("loot", "sewer"), "the sewer does not use its own table")
	_expect(Array(sewer["base"]) == ["battery"] and var_to_str(sewer["rolls"]) == var_to_str([{"kind": "tool", "chance": 0.45}])
		and LootTables.tool_weights(sewer) == OLD_WEIGHTS and sewer.get("aid", []).is_empty(), "sewer table changed")


## Draw for draw against a copy of the old code: 3000 seeds, every roll, tool, backpack (levels 0..-12) and aid draw.
func _check_draw_parity() -> void:
	var route := LootTables.table_for("route")
	var mismatches := 0
	for i in 3000:
		var seed_text := "LOOT-%d" % i
		var level := -(i % 13)
		var old_rng := SeededRandom.new(seed_text)
		var new_rng := SeededRandom.new(seed_text)
		var old_plans := []
		for pair in [["tool", 0.72], ["battery", 0.38], ["coin", 0.30], ["backpack", 0.16]]:
			if old_rng.next_float() < float(pair[1]):
				old_plans.append(pair[0])
		var old_items := []
		for kind in old_plans:
			if kind == "tool":
				old_items.append(_old_pick_tool(old_rng))
			elif kind == "backpack":
				var depth_rank := clampi(1 + floori(maxf(0.0, -float(level)) / 4.0), 1, 3)
				old_items.append(OLD_BACKPACKS[clampi(1 + old_rng.next_index(depth_rank), 1, 3) - 1])
			else:
				old_items.append("")
		var coop := i % 2 == 1
		if old_rng.next_float() < .18:
			old_items.append("stim_pack")
		if old_rng.next_float() < (.06 if coop else .03):
			old_items.append("revive_kit")
		var new_plans := LootTables.roll(route, new_rng)
		var new_items := []
		for kind in new_plans:
			new_items.append(LootTables.item_for(kind, route, new_rng, Vector3i(0, level, 0)))
		new_items.append_array(LootTables.roll_aid(route, new_rng, coop))
		if old_plans != new_plans or old_items != new_items or old_rng.next_float() != new_rng.next_float():
			mismatches += 1
	_expect(mismatches == 0, "%d of 3000 seeds rolled different loot than the old code" % mismatches)


func _old_pick_tool(rng: SeededRandom) -> String:
	var roll := rng.next_float()
	for type in OLD_TOOLS:
		roll -= float(OLD_WEIGHTS[type])
		if roll < 0.0:
			return type
	return OLD_TOOLS[0]


## A pack overriding loot/route: every route tool is now the Axe; the sewer keeps its own table; unloading restores it.
func _check_override(vanilla: String) -> void:
	var dir := _pack("lootover", ["loot/route"], {"route": {"id": "route", "base": ["battery"],
		"rolls": [{"kind": "tool", "chance": 1.0}], "tools": [{"item": "rescue_axe", "weight": 1}]}})
	var report := ContentRegistry.load_packs([dir])
	_expect(report["ok"], "the override pack was refused: %s" % [report["errors"]])
	if report["ok"]:
		_expect(LootTables.table_for("hotel").get("tools") == [{"item": "rescue_axe", "weight": 1.0}],
			"the override did not reach the route table")
		_expect(StreamedRouteGenerator.PICKUP_TYPES == ["rescue_axe"], "PICKUP_TYPES did not rebuild on load")
		var generator := StreamedRouteGenerator.new(Parity.SEED)
		var looted := 0
		for coord in Parity.chunks_of(generator, "hotel", 4) + Parity.chunks_of(generator, "hospital", 4):
			var data := generator.chunk(coord)
			if data.get("safe_room", false):
				continue   # safe rooms hold no pickups
			looted += 1
			var tools: Array = data.get("pickups", []).filter(func(p): return p["kind"] == "tool")
			_expect(not tools.is_empty(), "an overridden route chunk %s (tool chance 1) has no tool" % coord)
			for pickup in tools:
				_expect(pickup["item"] == "rescue_axe", "an overridden route chunk still dropped %s" % pickup["item"])
		_expect(looted >= 4, "only %d of 8 chunks were not safe rooms" % looted)
		_expect(Parity.loot_hash() == Parity.loot_hash(), "the override is not deterministic")
		_expect(Parity.loot_hash() != vanilla, "the override changed nothing")
	ContentRegistry.unload_packs()
	_expect(Parity.loot_hash() == vanilla, "unloading the override did not give back the vanilla loot")
	_expect(StreamedRouteGenerator.PICKUP_TYPES == OLD_TOOLS, "PICKUP_TYPES did not rebuild on unload")


## A pack adding <pack>_hotel for the hotel only: hotel chunks get its coins, other regions are untouched.
func _check_added(vanilla: String) -> void:
	var before := {}
	var generator := StreamedRouteGenerator.new(Parity.SEED)
	var hotel := Parity.chunks_of(generator, "hotel", 4)
	var other := Parity.chunks_of(generator, "hospital", 3)
	for coord in other:
		before[coord] = generator.chunk(coord).get("pickups", [])
	var dir := _pack("lootadd", [], {"hotel": {"id": "lootadd_hotel", "regions": ["hotel"], "base": ["coin", "coin", "coin"],
		"rolls": [], "tools": [{"item": "lockpick", "weight": 1}]}})
	var report := ContentRegistry.load_packs([dir])
	_expect(report["ok"], "the adding pack was refused: %s" % [report["errors"]])
	if report["ok"]:
		_expect(LootTables.table_for("hotel").get("id") == "lootadd_hotel", "the pack table does not loot the hotel")
		_expect(LootTables.table_for("hospital").get("id") == "route", "the pack table leaked into the hospital")
		generator = StreamedRouteGenerator.new(Parity.SEED)
		var looted := 0
		for coord in hotel:
			var data := generator.chunk(coord)
			if data.get("safe_room", false):
				continue
			looted += 1
			var coins: Array = data.get("pickups", []).filter(func(p): return p["kind"] == "coin")
			_expect(coins.size() == 3, "hotel chunk %s has %d coins, not the pack's 3" % [coord, coins.size()])
		_expect(looted >= 1, "no hotel chunk outside a safe room to check")
		for coord in other:
			_expect(generator.chunk(coord).get("pickups", []) == before[coord], "a hospital chunk's loot changed")
	ContentRegistry.unload_packs()
	_expect(Parity.loot_hash() == vanilla, "unloading the adding pack did not give back the vanilla loot")


## Packs with a bad table are refused whole and change nothing.
func _check_refused(vanilla: String) -> void:
	var cases := [
		["lootbad1", [], {"a": {"id": "lootbad1_a", "base": [], "rolls": [], "tools": [{"item": "taser", "weight": 1}],
			"script": "res://evil.gd"}}, "unknown field 'script'"],
		["lootbad2", [], {"a": {"id": "lootbad2_a", "base": [], "rolls": [], "tools": [{"item": "golden_gun", "weight": 1}]}},
			"tools[0].item"],
		["lootbad3", [], {"a": {"id": "route", "base": [], "rolls": [], "tools": [{"item": "taser", "weight": 1}]}}, "route"],
	]
	for case in cases:
		var report := ContentRegistry.load_packs([_pack(case[0], case[1], case[2])])
		_expect(not report["ok"] and Array(report["errors"]).any(func(e): return String(e).contains(String(case[3]))),
			"pack %s was not refused on %s (got %s)" % [case[0], case[3], report["errors"]])
	_expect(ContentRegistry.loaded_packs().is_empty() and Parity.loot_hash() == vanilla, "a refused pack changed the loot")


func _pack(id: String, overrides: Array, files: Dictionary) -> String:
	var dir := ROOT.path_join(id)
	var manifest := {"schema": "lr.pack/1", "id": id, "name": id, "version": "1.0.0"}
	if not overrides.is_empty():
		manifest["overrides"] = overrides
	_write(dir.path_join("pack.json"), JSON.stringify(manifest))
	for name in files:
		var body: Dictionary = files[name].duplicate(true)
		body["schema"] = "lr.loot/1"
		_write(dir.path_join("loot/%s.json" % name), JSON.stringify(body))
	return dir


func _write(path: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()


## Delete the test folder (only a path carrying "data_loot_test" is ever touched).
func _wipe() -> void:
	var path := ContentPacks.os_path(ROOT)
	if path.contains("data_loot_test") and DirAccess.dir_exists_absolute(path):
		_remove_tree(path)


func _remove_tree(path: String) -> void:
	var access := DirAccess.open(path)
	if access == null:
		return
	for name in access.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name in access.get_directories():
		_remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)
