extends RefCounted

## No restart, ever (docs/DATA_DRIVEN_CONTENT.md): in one process, a vanilla room, a modded room, vanilla again, a second
## modded room and vanilla again, through the same RoomState / RoomPacks calls the game makes. Each modded room's
## content generates and checks out; each return to vanilla gives back the exact built-in tables and parity hashes with
## no leaked objects or resources; and the guest handshake loads, refuses and names packs as the host announced them.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- data_hotswap

const Parity := preload("res://tests/data_parity.gd")
const ROOT := "user://data_hotswap_test"
const PRINTER := "res://assets/props/maze/office_printer.glb"
const AKI := "res://assets/hunters_blocky/aki/aki.glb"

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var saved_enabled: Array = Settings.mods_enabled.duplicate()
	var saved_root := RoomPacks.mods_root
	RoomPacks.mods_root = ROOT
	_wipe(ROOT)
	_make_pack("hotswap_a", "EMBER DONUTS")
	_make_pack("hotswap_b", "FROST DONUTS")

	RoomState.create_local(RoomState.Mode.DEFAULT)
	var vanilla := _snapshot()
	for pack in ["hotswap_a", "hotswap_b"]:
		_expect(_room([pack]).is_empty(), "%s room did not load" % pack)
		_check_modded(pack)
		_room([])
		_expect(_snapshot() == vanilla, "leaving the %s room did not restore the built-in game" % pack)
	_check_leaks()

	_expect(RoomPacks.host_load(true).is_empty() and ContentRegistry.loaded_packs().is_empty(),
		"a public route loaded packs")
	_check_handshake(vanilla)

	RoomState.create_local(RoomState.Mode.DEFAULT)
	Settings.mods_enabled = saved_enabled
	RoomPacks.mods_root = saved_root
	_wipe(ROOT)
	_expect(_snapshot() == vanilla, "the suite left packs loaded")
	if _failures == 0:
		print("  data_hotswap OK")
	return _failures


## Joining and leaving modded rooms frees everything the packs created: counted over load -> pack models in use ->
## leave, after one warm-up cycle so first-use caches do not count. (World generation is left out on purpose: it is the
## same with or without packs.)
func _check_leaks() -> void:
	var counts := []
	for cycle in 3:
		for pack in ["hotswap_a", "hotswap_b"]:
			_room([pack])
			for prop in ["%s_lamp" % pack, "officePrinter"]:
				var model := ModelSlot.instantiate_prop(PropModelCatalog.model_path(prop, "x", "y"))
				if model != null:
					model.free()
			_room([])
		counts.append([Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)])
	_expect(counts[2][0] <= counts[0][0] and counts[1][0] <= counts[0][0],
		"objects grow with every modded room: %s" % [counts.map(func(c): return c[0])])
	_expect(counts[2][1] <= counts[0][1] and counts[1][1] <= counts[0][1],
		"resources grow with every modded room: %s" % [counts.map(func(c): return c[1])])


## Enter a private room with `packs` enabled, as RoomState.enter() does; [] leaves (RoomState.create_local unloads).
func _room(packs: Array) -> String:
	if packs.is_empty():
		RoomState.create_local(RoomState.Mode.DEFAULT)
		return ""
	Settings.mods_enabled = packs
	return RoomPacks.host_load(false)


func _check_modded(pack: String) -> void:
	var hunter := "%s_ember" % pack
	_expect(ContentRegistry.loaded_packs().map(func(p): return p["id"]) == [pack], "%s: wrong packs loaded" % pack)
	_expect(HunterRoster.DRAW_IDS.back() == hunter, "%s: its hunter is not in the draw" % pack)
	_expect(not HunterRoster.PROFILES.has("hotswap_b_ember" if pack == "hotswap_a" else "hotswap_a_ember"),
		"%s: the other room's hunter leaked" % pack)
	_expect(StreamedRouteGenerator.SHOP_NAMES.get("donut_shop") == ("EMBER DONUTS" if pack == "hotswap_a"
		else "FROST DONUTS"), "%s: wrong shop names" % pack)
	# generate-and-check: the pack's mall generates deterministically and stays one open space; its prop set names the
	# pack's own prop (the set dresses only rooms without a furniture template, and every mall role has one), whose model
	# loads as a stripped runtime scene
	var lamp := "%s_lamp" % pack
	_expect(StreamedRouteGenerator.REGION_PROP_SETS["mall"].any(func(c): return c["type"] == lamp),
		"%s: the mall prop set does not name %s" % [pack, lamp])
	var first := Parity.region_hash()
	_expect(first == Parity.region_hash(), "%s: mall generation is not deterministic" % pack)
	var generator := StreamedRouteGenerator.new(Parity.SEED)
	for coord in Parity.chunks_of(generator, "mall", 6):
		var data := generator.chunk(coord)
		_expect(StreamedRouteGenerator._open_components(data["grid"]) == 1, "%s: mall chunk %s is split" % [pack, coord])
	var path: String = PropModelCatalog.model_path(lamp, "x", "y")
	var model := ModelSlot.instantiate_prop(path)
	_expect(model != null and not model.find_children("*", "MeshInstance3D").is_empty(), "%s: lamp model did not load" % pack)
	if model != null:
		model.free()


## The guest side: adopt what a modded host announced, refuse a modded public route, name missing packs.
func _check_handshake(vanilla: String) -> void:
	_room(["hotswap_a"])
	var announced := RoomPacks.announce()
	_room([])
	var adopted := RoomPacks.adopt(announced, false)
	_expect(adopted["ok"] and ContentRegistry.pack_hash() == announced["hash"], "guest did not adopt the host's packs: %s"
		% adopted["reason"])
	_expect(RoomPacks.adopt(announced, false)["ok"], "adopting the same packs twice failed")
	RoomPacks.leave()
	var public := RoomPacks.adopt(announced, true)
	_expect(not public["ok"] and ContentRegistry.loaded_packs().is_empty(), "a guest adopted a modded public route")
	var stranger: Dictionary = announced.duplicate(true)
	stranger["packs"][0]["sha256"] = "0".repeat(64)
	stranger["packs"][0]["name"] = "Stranger Pack"
	var refused := RoomPacks.adopt(stranger, false)
	_expect(not refused["ok"] and String(refused["reason"]).contains("STRANGER PACK") and refused["missing"].size() == 1,
		"a missing pack was not named: %s" % refused["reason"])
	_expect(_snapshot() == vanilla, "a refused handshake left packs loaded")
	var plain := RoomPacks.adopt({"hash": ContentRegistry.builtin_pack_hash(), "packs": []}, true)
	_expect(plain["ok"], "a vanilla public route was refused: %s" % plain["reason"])


func _snapshot() -> String:
	return "\n".join([var_to_str(HunterRoster.PROFILES), var_to_str(HunterRoster.DRAW_IDS),
		var_to_str(PropModelCatalog.MODEL_PATHS), var_to_str(PropModelCatalog.VARIANT_THEMES),
		var_to_str(FloorSets.HALLS), var_to_str(StreamedRouteGenerator.REGION_PROP_SETS),
		var_to_str(StreamedRouteGenerator.SHOP_NAMES), ContentRegistry.pack_hash(),
		Parity.props_hash(), Parity.hunters_hash(), Parity.region_hash()])


## A pack with its own hunter on Aki's body and a mall override dressed only with its own lamp.
func _make_pack(id: String, donut_sign: String) -> void:
	var dir := ROOT.path_join(id)
	var mall: Dictionary = ContentRegistry.get_def("regions", "mall").duplicate(true)
	mall["schema"] = "lr.region/1"
	mall["shop_names"]["donut_shop"] = donut_sign
	mall["prop_set"] = [{"type": "%s_lamp" % id, "size": [0.6, 1.2, 0.6], "solid": true}]
	_write(dir.path_join("pack.json"), JSON.stringify({"schema": "lr.pack/1", "id": id, "name": id, "version": "1.0.0",
		"overrides": ["regions/mall"]}))
	_write(dir.path_join("regions/mall.json"), JSON.stringify(mall))
	_write(dir.path_join("props/lamp.json"), JSON.stringify({"schema": "lr.prop/1", "family": "lamps",
		"props": [{"id": "%s_lamp" % id, "models": ["assets/lamp.glb"]}]}))
	_write(dir.path_join("hunters/ember.json"), JSON.stringify({"schema": "lr.hunter/1", "id": "%s_ember" % id,
		"name": "Ember", "tier": "easy", "speed": 0.8, "chase": 3.5, "prog": 0.18, "sight": 8.0, "hearing": 1.0,
		"spawn": 12, "model": AKI}))
	_write(dir.path_join("assets/lamp.glb"), FileAccess.get_file_as_bytes(PRINTER))


func _write(path: String, content) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if content is PackedByteArray:
		file.store_buffer(content)
	else:
		file.store_string(String(content))
	file.close()


## Delete `dir` and everything in it. Only test folders (their name carries "data_hotswap_test") are ever touched, and the walk
## uses absolute paths (ContentPacks.os_path) so a user data dir containing "//" cannot point it at the project.
func _wipe(dir: String) -> void:
	var path := ContentPacks.os_path(dir)
	if not path.contains("data_hotswap_test") or not DirAccess.dir_exists_absolute(path):
		return
	_remove_tree(path)


func _remove_tree(path: String) -> void:
	var access := DirAccess.open(path)
	if access == null:
		return
	access.include_hidden = true
	for name in access.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name in access.get_directories():
		if access.is_link(name):
			DirAccess.remove_absolute(path.path_join(name))
		else:
			_remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)
