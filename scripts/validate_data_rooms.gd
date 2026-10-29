extends RefCounted

## Room recipes as data (RoomRecipes, lr.room/1): the interpreter's positions, ranges, cycled types and fixed draw count;
## a content pack's new shop furnished in real mall chunks over several seeds (placed, no overlaps, doorway clear, all
## floor reachable, at least 4 free cells left for pickups, deterministic); unloading restores the built-in mall; and
## recipes that would place interactive, unknown or unsized props are refused.
##
##   godot --headless --path . res://scenes/validate.tscn -- data_rooms

const Parity := preload("res://scripts/data_parity.gd")
const Regions := preload("res://scripts/validate_regions.gd")
const ROOT := "user://data_rooms_test"
const PRINTER := "res://art/props-3d/props/maze/office_printer.glb"
const SHOP := "roomtest_record_shop"
const SEEDS := ["ROOMS-A", "ROOMS-B", "ROOMS-C"]
const FREE_CELLS := 4

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


## A mall region override replaces the whole role list. Example packs append their shops after the built-in roles,
## including music_store, so loading one does not drop the music wing's mall shop.
func _mall_keeps_music_store() -> bool:
	return StreamedRouteGenerator.MALL_ROOMS.has("music_store") \
		and String(StreamedRouteGenerator.SHOP_NAMES.get("music_store", "")) == "MUSIC & SOUND"


func run(_host: Node) -> int:
	_wipe(ROOT)
	_check_interpreter()
	var vanilla := Parity.region_hash()
	var dir := _pack("roomtest", _recipe())
	var report := ContentRegistry.load_packs([dir])
	_expect(report["ok"], "the room pack was refused: %s" % [report["errors"]])
	if report["ok"]:
		_check_generated(SHOP)
	ContentRegistry.unload_packs()
	# the shipped example (examples/mods/record_shop), installed as a player would
	var example := ROOT.path_join("record_shop")
	_copy_tree("res://examples/mods/record_shop", example)
	var example_report := ContentRegistry.load_packs([example])
	_expect(example_report["ok"], "the record_shop example was refused: %s" % [example_report["errors"]])
	if example_report["ok"]:
		_expect(_mall_keeps_music_store(), "record_shop mall override dropped music_store")
		_check_generated("record_shop_store")
	ContentRegistry.unload_packs()
	# the example packs that add rooms to the mall (examples/mods, docs/modding/examples)
	var example_rooms := {"neon_arcade": ["neon_arcade_hall"], "library_rooms": ["library_rooms_reading", "library_rooms_archive"]}
	for pack in example_rooms:
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://examples/mods/" + pack)):
			continue
		var copy := ROOT.path_join(pack)
		_copy_tree("res://examples/mods/" + pack, copy)
		var pack_report := ContentRegistry.load_packs([copy])
		_expect(pack_report["ok"], "%s was refused: %s" % [pack, pack_report["errors"]])
		if pack_report["ok"]:
			_expect(_mall_keeps_music_store(), "%s mall override dropped music_store" % pack)
			for room in example_rooms[pack]:
				_check_generated(room)
		ContentRegistry.unload_packs()
		_expect(Parity.region_hash() == vanilla, "unloading %s did not restore the built-in mall" % pack)
	_expect(not RoomRecipes.has(SHOP), "unloading left the pack's recipe")
	_expect(Parity.region_hash() == vanilla, "unloading did not restore the built-in mall")
	_check_refusals()
	_wipe(ROOT)
	if _failures == 0:
		print("  data_rooms OK")
	return _failures


## Positions, ranges, cycled types, region tokens, and one draw per chance/choose whatever the room size.
func _check_interpreter() -> void:
	var path := ROOT.path_join("probe.json")
	_write(path, JSON.stringify({"schema": "lr.room/1", "id": "probe", "items": [
		{"type": "checkoutCounter", "side": 0, "depth": "front-1", "mirror": false},
		{"type": ["a1", "a2", "a3"], "side": ["-half+1", "half", 3], "depth": "back", "mirror": false},
		{"type": "@rug", "side": 0, "depth": "mid", "when": {"min_side": 11}},
		{"choose": [{"type": "c1", "weight": 1}, {"type": "c2", "weight": 1}], "side": 2, "depth": 1,
			"when": {"chance": 0.5}}]}).to_utf8_buffer())
	var parsed := RoomRecipes.parse_file(path)
	_expect(parsed["errors"].is_empty(), "probe recipe refused: %s" % [parsed["errors"]])
	if not parsed["errors"].is_empty():
		return
	RoomRecipes.ensure_loaded()
	RoomRecipes._recipes["probe"] = parsed["def"]
	var region := {"@rug": "normalRug", "@frame": "", "@painting": ""}
	var small := SeededRandom.new("PROBE")
	var specs := RoomRecipes.specs("probe", 9, 9, small, region)
	var after_small := small.next_float()
	var big := SeededRandom.new("PROBE")
	var big_specs := RoomRecipes.specs("probe", 13, 11, big, region)
	_expect(after_small == big.next_float(), "room size changed how many draws a recipe takes")
	_expect(specs[0]["depth"] == 5 and specs[0]["side"] == 0, "front-1 in a 9-deep room is not depth 5: %s" % [specs[0]])
	var range_types := specs.filter(func(s): return String(s["type"]).begins_with("a")).map(func(s): return [s["type"], s["side"]])
	_expect(range_types == [["a1", -3], ["a2", 0], ["a3", 3]], "range/cycling wrong in a 9-wide room: %s" % [range_types])
	_expect(not specs.any(func(s): return s["type"] == "normalRug"), "a when.min_side item placed in a small room")
	_expect(big_specs.any(func(s): return s["type"] == "normalRug"), "a region token did not resolve")
	RoomRecipes._recipes.erase("probe")


## The pack's shop in real mall chunks: furnished like a built-in room, deterministic.
func _check_generated(shop: String) -> void:
	var rooms := 0
	var furnished := 0
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		var again := StreamedRouteGenerator.new(seed_text)
		for coord in Parity.chunks_of(generator, "mall", 8):
			var data := generator.chunk(coord)
			_expect(var_to_str(data) == var_to_str(again.chunk(coord)), "%s %s is not deterministic" % [seed_text, coord])
			for room in data.get("rooms", []):
				if String(room.get("room_type", "")) != shop:
					continue
				rooms += 1
				var props: Array = data.get("region_props", []).filter(func(p): return String(p.get("room_template",
					"")) == shop)
				if props.is_empty():
					continue
				furnished += 1
				var where := "%s %s" % [seed_text, coord]
				_expect(Regions._overlap(props).is_empty(), "%s: recipe props interpenetrate" % where)
				var blocked := Regions._solid_cells(props)
				var doorway: Vector2i = room["doorway"]
				var inside: Vector2i = doorway - (StreamedRouteGenerator._room_template_basis(room)["open"] as Vector2i)
				_expect(not blocked.has(doorway) and not blocked.has(inside), "%s: a recipe prop blocks the entrance" % where)
				_expect(Regions._stranded(data, room, doorway, blocked) == 0, "%s: recipe props wall off floor" % where)
				var rect: Rect2i = room["rect"]
				var free := 0
				for z in range(rect.position.y + 1, rect.end.y - 1):
					for x in range(rect.position.x + 1, rect.end.x - 1):
						if not blocked.has(Vector2i(x, z)):
							free += 1
				_expect(free >= FREE_CELLS, "%s: only %d free floor cells left" % [where, free])
	_expect(rooms > 0, "no %s room generated over %s" % [shop, SEEDS])
	_expect(furnished == rooms, "%d of %d %s rooms were furnished" % [furnished, rooms, shop])


func _check_refusals() -> void:
	var cases := [
		["interactive prop", _recipe("dinerBooth"), "interactive"],
		["unknown prop", _recipe("noSuchProp"), "not a known prop"],
		["unsized pack prop", _recipe("bad_crate", false), "needs a \"size\""],
	]
	var index := 0
	for case in cases:
		var id := "bad%d" % index
		var recipe: Dictionary = case[1]
		recipe["id"] = "%s_record_shop" % id
		var dir := _pack(id, recipe, case[0] == "unsized pack prop")
		var report := ContentRegistry.load_packs([dir])
		_expect(not report["ok"] and Array(report["errors"]).any(func(e): return String(e).contains(String(case[2]))),
			"%s: expected a refusal with \"%s\", got %s" % [case[0], case[2], report["errors"]])
		index += 1
	var bad_position := ROOT.path_join("badpos.json")
	_write(bad_position, JSON.stringify({"schema": "lr.room/1", "id": "x", "items": [{"type": "checkoutCounter",
		"side": "middle", "depth": "front+x"}]}).to_utf8_buffer())
	_expect(RoomRecipes.parse_file(bad_position)["errors"].size() == 2, "bad positions were not both refused")
	var code_dir := _pack("codeover", {"schema": "lr.room/1", "id": "bedroom", "items": [{"type": "checkoutCounter",
		"side": 0, "depth": 0}]}, false, ["rooms/bedroom"])
	var code_report := ContentRegistry.load_packs([code_dir])
	_expect(not code_report["ok"] and Array(code_report["errors"]).any(func(e): return String(e).contains("does not have")),
		"overriding a code recipe was not refused: %s" % [code_report["errors"]])


## A record shop: counter by the entrance, crates cycling along the back wall, a sized pack crate, a rug where wide.
func _recipe(extra_type: String = "", sized: bool = true) -> Dictionary:
	var items := [
		{"type": "checkoutCounter", "side": -2, "depth": "front-1", "facing": "open"},
		{"type": ["roomtest_crate", "shopShelf"], "side": ["-half+1", "half", 3], "depth": "back", "wall_backed": true,
			"facing": "open"},
		{"type": "@rug", "side": 0, "depth": "mid", "solid": false, "when": {"min_side": 9}},
	]
	if not extra_type.is_empty():
		items.append({"type": extra_type, "side": 2, "depth": "mid"})
	return {"schema": "lr.room/1", "id": SHOP, "items": items, "_sized": sized}


## A pack: the recipe, its crate prop (sized unless asked not to), and a mall that lists the shop among its roles.
func _pack(id: String, recipe: Dictionary, unsized_extra: bool = false, overrides: Array = []) -> String:
	var dir := ROOT.path_join(id)
	var room := recipe.duplicate(true)
	room.erase("_sized")
	var crate := {"id": "%s_crate" % id, "models": ["assets/crate.glb"], "size": [0.8, 0.9, 0.6]}
	# recipes name the pack's own crate (and, for the unsized case, a crate with no size); ids get this pack's prefix
	var props := [crate]
	if unsized_extra:
		props.append({"id": "%s_loose" % id, "models": ["assets/crate.glb"]})
	var text := JSON.stringify(room).replace("roomtest_crate", "%s_crate" % id).replace("bad_crate", "%s_loose" % id)
	var mall: Dictionary = ContentRegistry.get_def("regions", "mall").duplicate(true)
	mall["schema"] = "lr.region/1"
	var prop_set := []
	for choice in mall["prop_set"]:
		prop_set.append({"type": choice["type"], "size": [choice["size"].x, choice["size"].y, choice["size"].z]})
	mall["prop_set"] = prop_set
	mall["room_roles"] = (mall["room_roles"] as Array) + [String(JSON.parse_string(text)["id"])]
	var all_overrides := ["regions/mall"] + overrides
	_write(dir.path_join("pack.json"), JSON.stringify({"schema": "lr.pack/1", "id": id, "name": id, "version": "1.0.0",
		"overrides": all_overrides}).to_utf8_buffer())
	_write(dir.path_join("rooms/shop.json"), text.to_utf8_buffer())
	_write(dir.path_join("props/crates.json"), JSON.stringify({"schema": "lr.prop/1", "family": "crates",
		"props": props}).to_utf8_buffer())
	_write(dir.path_join("regions/mall.json"), JSON.stringify(mall).to_utf8_buffer())
	_write(dir.path_join("assets/crate.glb"), FileAccess.get_file_as_bytes(PRINTER))
	return dir


func _copy_tree(from: String, to: String) -> void:
	for name in DirAccess.get_files_at(from):
		_write(to.path_join(name), FileAccess.get_file_as_bytes(from.path_join(name)))
	for name in DirAccess.get_directories_at(from):
		_copy_tree(from.path_join(name), to.path_join(name))


func _write(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ContentPacks.os_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _wipe(dir: String) -> void:
	var path := ContentPacks.os_path(dir)
	if not path.contains("data_rooms_test") or not DirAccess.dir_exists_absolute(path):
		return
	_remove_tree(path)


func _remove_tree(path: String) -> void:
	for name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(name))
	for name in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)
