extends RefCounted

## Content packs (docs/DATA_DRIVEN_CONTENT.md, "Mod packs"): a valid pack in user:// loads into every registry table,
## its models load as stripped runtime scenes, unloading gives back the exact built-in tables and parity hashes, and
## every unsafe or broken pack is refused as a whole with the file named and nothing changed.
##
##   godot --headless --path . res://scenes/validate.tscn -- data_packs

const Parity := preload("res://scripts/data_parity.gd")
const ROOT := "user://data_packs_test"
const PRINTER := "res://art/props-3d/props/maze/office_printer.glb"
const AKI := "res://assets/hunters_blocky/aki/aki.glb"
const TONE := "res://scripts/fixtures/pack_tone.ogg"

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	_wipe(ROOT)
	var vanilla := _snapshot()
	_expect(ContentRegistry.pack_hash() == ContentRegistry.builtin_pack_hash(), "vanilla pack hash is not the built-in one")
	_expect(ContentRegistry.loaded_packs().is_empty(), "packs loaded at boot")

	var good := _good_pack("testpack")
	var report := ContentRegistry.load_packs([good])
	_expect(report["ok"], "the valid pack was refused: %s" % ", ".join(report["errors"]))
	if report["ok"]:
		_check_loaded(good)
	ContentRegistry.unload_packs()
	_expect(_snapshot() == vanilla, "unloading did not restore the built-in tables")

	_check_example(vanilla)
	_check_rejections(vanilla)
	_wipe(ROOT)
	if _failures == 0:
		print("  data_packs OK")
	return _failures


## Every table a pack can touch, plus the parity fingerprints, as text.
func _snapshot() -> String:
	return "\n".join([var_to_str(HunterRoster.PROFILES), var_to_str(HunterRoster.DRAW_IDS),
		var_to_str(PropModelCatalog.MODEL_PATHS), var_to_str(PropModelCatalog.VARIANT_THEMES),
		var_to_str(PropModelCatalog.COORDINATED_SET_TYPES), var_to_str(FloorSets.HALLS), var_to_str(FloorSets.ROOM_DEFAULT),
		var_to_str(StreamedRouteGenerator.REGION_PROP_SETS), var_to_str(StreamedRouteGenerator.SHOP_NAMES),
		var_to_str(StreamedRouteGenerator.MALL_ROOMS), var_to_str(_grabs()),
		var_to_str([Sound._cue_overrides.keys(), Sound._ambience_overrides.keys()]), ContentRegistry.pack_hash(),
		Parity.props_hash(), Parity.hunters_hash(), Parity.region_hash()])


## Every hunter's grab pool and look, in a stable order.
func _grabs() -> Array:
	GrabStyles.ensure_loaded()
	var ids := GrabStyles._pools.keys()
	ids.sort()
	return ids.map(func(id): return [id, GrabStyles._pools[id], GrabStyles._looks.get(id, {})])


func _check_loaded(dir: String) -> void:
	var printer := dir.path_join("assets/printer.glb")
	_expect(ContentRegistry.pack_hash() != ContentRegistry.builtin_pack_hash(), "a loaded pack did not change the hash")
	_expect(HunterRoster.PROFILES.has("testpack_ember"), "pack hunter missing from PROFILES")
	_expect(HunterRoster.DRAW_IDS.back() == "testpack_ember", "pack hunter not appended to the draw")
	_expect(HunterRoster.get_identity("testpack_ember")["model_scene"] == AKI, "pack hunter does not wear Aki's body")
	_expect(HunterRoster.PROFILES["aki"]["speed"] == 0.5, "hunter override not applied")
	_expect(PropModelCatalog.MODEL_PATHS.get("officePrinter") == [printer], "prop override not applied")
	_expect(PropModelCatalog.VARIANT_THEMES.get("officePrinter") == ["ember"], "prop override themes not applied")
	_expect(not PropModelCatalog.COORDINATED_SET_TYPES.has("officePrinter"), "uncoordinated override still coordinated")
	_expect(PropModelCatalog.model_path("officePrinter", "a", "b") == printer, "model_path ignores the override")
	_expect(PropModelCatalog.MODEL_PATHS.get("testpack_lamp") == [printer], "pack prop missing from MODEL_PATHS")
	_expect(StreamedRouteGenerator.SHOP_NAMES.get("donut_shop") == "EMBER DONUTS", "region override not applied")
	var types: Array = StreamedRouteGenerator.REGION_PROP_SETS["mall"].map(func(choice): return choice["type"])
	_expect(types.has("testpack_lamp"), "region override prop_set not applied")
	_expect(ContentRegistry.pack_of("props", "officePrinter") == "testpack", "override origin not recorded")
	var model := ModelSlot.instantiate(printer)
	_expect(model != null and not model.find_children("*", "MeshInstance3D").is_empty(), "pack model did not load")
	if model != null:
		var scripted := model.find_children("*").filter(func(node: Node): return node.get_script() != null)
		_expect(scripted.is_empty() and model.get_script() == null, "pack model kept a script")
		model.free()
	_expect(ContentRegistry.pack_scene("user://elsewhere/x.glb") == null, "loaded a model outside every pack")
	_expect(HunterDossier.portrait("testpack_ember") != null, "pack portrait did not load")
	_expect(Sound._cue_overrides.has("alert") and Sound._ambience_overrides.has("mall"), "pack sounds not loaded")
	var plays := int(Sound.play_counts.get("alert", 0))
	_expect(Sound.alert() and int(Sound.play_counts.get("alert", 0)) == plays + 1, "the replaced cue did not play")
	_expect(Sound._cue_overrides["alert"]["streams"][0] is AudioStreamOggVorbis, "the cue is not the pack's recording")
	_expect(GrabStyles.pool_for("testpack_ember") == {"wrap": 3.0, "tackle": 1.0}, "pack hunter's grabs not loaded: %s"
		% [GrabStyles.pool_for("testpack_ember")])
	_expect(GrabStyles.pool_for("aki") == {"shoulder_grab": 1.0} and GrabStyles.look_for("aki")["delay"] == 0.0,
		"grab override not applied: %s" % [GrabStyles.pool_for("aki")])
	var draws := {}
	for depth in range(1, 400):
		draws[HunterRoster.pick_for_floor("PACK-DRAW", depth)] = true
	_expect(draws.has("testpack_ember"), "pack hunter never drawn in 400 floors")


## The shipped example (examples/mods/ember) stays a valid pack: copied to user:// as a player would, it loads, recolours
## every office printer and adds Ember to the draw on Aki's body.
func _check_example(vanilla: String) -> void:
	var dir := ROOT.path_join("ember")
	_copy_tree("res://examples/mods/ember", dir)
	var report := ContentRegistry.load_packs([dir])
	_expect(report["ok"], "the example pack was refused: %s" % ", ".join(report["errors"]))
	if report["ok"]:
		var printer := dir.path_join("assets/office_printer_ember.glb")
		_expect(PropModelCatalog.model_path("officePrinter", "a", "b") == printer, "example printer override missing")
		_expect(HunterRoster.get_identity("ember_aki")["model_scene"] == AKI, "example hunter does not wear Aki's body")
		var model := ModelSlot.instantiate_prop(printer)
		_expect(model != null, "example printer model did not load")
		if model != null:
			model.free()
	ContentRegistry.unload_packs()
	_expect(_snapshot() == vanilla, "unloading the example did not restore the built-in game")


func _copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for name in DirAccess.get_files_at(from):
		_write(to.path_join(name), FileAccess.get_file_as_bytes(from.path_join(name)))
	for name in DirAccess.get_directories_at(from):
		_copy_tree(from.path_join(name), to.path_join(name))


## Each case: one broken pack (or pack set) must be refused, name the right file, and change nothing.
func _check_rejections(vanilla: String) -> void:
	var cases := []
	cases.append(["script file", [_good_pack("evil", {"assets/run.gd": "extends Node"})], "run.gd"])
	cases.append(["resource file", [_good_pack("tres", {"props/thing.tres": "[gd_resource]"})], "thing.tres"])
	cases.append(["hidden file", [_good_pack("hidden", {".secret": "x"})], ".secret"])
	cases.append(["bad json", [_good_pack("badjson", {"hunters/broken.json": "{ not json"})], "broken.json"])
	cases.append(["unknown field", [_good_pack("field", {"hunters/x.json": _hunter("field_x", {"wings": 2})})],
		"wings"])
	cases.append(["unprefixed id", [_good_pack("prefix", {"hunters/x.json": _hunter("someone")})], "must start with"])
	cases.append(["undeclared override", [_good_pack("undeclared", {"hunters/x.json": _hunter("kathy")})],
		"must start with"])
	cases.append(["override of nothing", [_good_pack("nothing", {}, ["hunters/nobody"])], "does not have"])
	cases.append(["two packs, one override", [_good_pack("one", {}, ["hunters/aki"], {"hunters/aki.json":
		_hunter("aki", {"speed": 0.6})}), _good_pack("two", {}, ["hunters/aki"], {"hunters/aki.json":
		_hunter("aki", {"speed": 0.7})})], "also defined"])
	cases.append(["missing model", [_good_pack("missing", {"props/x.json": JSON.stringify({"schema": "lr.prop/1",
		"family": "x", "props": [{"id": "missing_x", "models": ["assets/none.glb"]}]})})], "none.glb"])
	cases.append(["foreign model root", [_good_pack("foreign", {"hunters/x.json": _hunter("foreign_x",
		{"model": "res://project.godot"})})], "not a built-in hunter model"])
	cases.append(["bad png", [_good_pack("badpng", {"assets/face.png": "not a png"})], "face.png"])
	cases.append(["grabs for no hunter", [_good_pack("nohunter", {"grabs/x.json": JSON.stringify({"schema": "lr.grab/1",
		"id": "nohunter_ghost", "pool": {"tackle": 1}})})], "not a hunter"])
	cases.append(["unknown grab style", [_good_pack("badgrab", {"grabs/x.json": JSON.stringify({"schema": "lr.grab/1",
		"id": "badgrab_ember", "pool": {"backflip": 1}})})], "unknown grab style"])
	cases.append(["undeclared sound", [_good_pack("loud", {"sounds/x.json": JSON.stringify({"schema": "lr.sound/1",
		"sounds": [{"id": "taser", "files": ["assets/tone.ogg"]}]})})], "replace built-in ones"])
	cases.append(["unknown cue", [_good_pack("nocue", {}, ["sounds/not_a_cue"], {"sounds/x.json": JSON.stringify({
		"schema": "lr.sound/1", "sounds": [{"id": "not_a_cue", "files": ["assets/tone.ogg"]}]})})], "does not have"])
	cases.append(["sound not ogg", [_good_pack("wavy", {"sounds/x.json": JSON.stringify({"schema": "lr.sound/1",
		"sounds": [{"id": "alert", "files": ["assets/printer.glb"]}]})})], "is not a .ogg"])
	cases.append(["bad ogg", [_good_pack("badogg", {"assets/sound.ogg": "not ogg"})], "sound.ogg"])
	cases.append(["glTF extension", [_good_pack("gltfext", {"assets/body.glb": _glb({"asset": {"version": "2.0"},
		"extensionsUsed": ["OMI_physics_body"], "scenes": [{"nodes": []}], "scene": 0})})], "OMI_physics_body"])
	cases.append(["folder name", [_rename(_good_pack("named"), "renamed")], "folder name"])
	cases.append(["bad version", [_manifest(_good_pack("version"), {"version": "1 0"})], "version must be"])
	cases.append(["short id", [_rename(_manifest(_good_pack("shortid"), {"id": "ab"}), "ab")], "id must be"])
	cases.append(["files list", [_manifest(_good_pack("listed"), {"files": [{"path": "assets/printer.glb",
		"sha256": "0".repeat(64), "size": 1}]})], "differs from pack.json files"])
	cases.append(["one bad pack sinks the set", [_good_pack("fine"), _good_pack("sinks", {"assets/x.exe": "MZ"})],
		"x.exe"])
	for case in cases:
		var report := ContentRegistry.load_packs(case[1])
		var named := Array(report["errors"]).any(func(error: String): return error.contains(String(case[2])))
		_expect(not report["ok"] and named, "%s: expected a refusal naming \"%s\", got ok=%s %s" % [case[0], case[2],
			report["ok"], report["errors"]])
		_expect(_snapshot() == vanilla, "%s: a refused pack changed the game" % case[0])
	var big := _good_pack("big")
	var limits := ContentPacks.LIMITS.duplicate()
	limits["file_bytes"] = 1024
	var report := ContentRegistry.load_packs([big], limits)
	_expect(not report["ok"] and Array(report["errors"]).any(func(e: String): return e.contains("per-file limit")),
		"oversize file was not refused: %s" % [report["errors"]])
	var linked := _good_pack("linked")
	if DirAccess.open(ContentPacks.os_path(linked)).create_link(ProjectSettings.globalize_path(ROOT),
			ProjectSettings.globalize_path(linked.path_join("assets/escape"))) == OK:
		report = ContentRegistry.load_packs([linked])
		_expect(not report["ok"] and Array(report["errors"]).any(func(e: String): return e.contains("links")),
			"symlink was not refused: %s" % [report["errors"]])
	_expect(_snapshot() == vanilla, "the refusals left the game changed")


## A pack exercising every kind: a new hunter on Aki's body, a hunter override, a new prop, a prop override and a
## region override, plus `extra` files, `overrides` and `replace` files on top.
func _good_pack(id: String, extra: Dictionary = {}, overrides: Array = [], replace: Dictionary = {}) -> String:
	var dir := ROOT.path_join(id)
	var all_overrides := ["hunters/aki", "props/officePrinter", "regions/mall", "grabs/aki", "sounds/alert",
		"ambience/mall"] if overrides.is_empty() else overrides
	var files := {
		"pack.json": JSON.stringify({"schema": "lr.pack/1", "id": id, "name": "Test " + id, "version": "1.0.0",
			"author": "validator", "overrides": all_overrides}),
	}
	if overrides.is_empty():
		var mall: Dictionary = ContentRegistry.get_def("regions", "mall").duplicate(true)
		mall["shop_names"]["donut_shop"] = "EMBER DONUTS"
		var prop_set := []
		for choice in mall["prop_set"]:
			prop_set.append({"type": choice["type"], "size": [choice["size"].x, choice["size"].y, choice["size"].z]})
		prop_set.append({"type": "%s_lamp" % id, "size": [0.6, 1.2, 0.6]})
		mall["prop_set"] = prop_set
		mall["schema"] = "lr.region/1"
		files["regions/mall.json"] = JSON.stringify(mall)
		files["hunters/ember.json"] = _hunter("%s_ember" % id, {"model": AKI, "portrait": "assets/ember.png"})
		files["hunters/aki.json"] = _hunter("aki", {"speed": 0.5})
		files["grabs/ember.json"] = JSON.stringify({"schema": "lr.grab/1", "id": "%s_ember" % id,
			"pool": {"wrap": 3, "tackle": 1}})
		files["grabs/aki.json"] = JSON.stringify({"schema": "lr.grab/1", "id": "aki", "pool": {"shoulder_grab": 1}})
		files["sounds/cues.json"] = JSON.stringify({"schema": "lr.sound/1", "sounds": [{"id": "alert",
			"files": ["assets/tone.ogg"], "gain_db": -3}]})
		files["ambience/beds.json"] = JSON.stringify({"schema": "lr.sound/1", "sounds": [{"id": "mall",
			"files": ["assets/tone.ogg"]}]})
		files["props/ember.json"] = JSON.stringify({"schema": "lr.prop/1", "family": "ember", "props": [
			{"id": "officePrinter", "models": ["assets/printer.glb"], "themes": ["ember"]},
			{"id": "%s_lamp" % id, "models": ["assets/printer.glb"]}]})
	files.merge(replace, true)
	files.merge(extra, true)
	for rel in files:
		_write(dir.path_join(rel), files[rel])
	if overrides.is_empty() or not replace.is_empty():
		_write(dir.path_join("assets/printer.glb"), FileAccess.get_file_as_bytes(PRINTER))
		_write(dir.path_join("assets/tone.ogg"), FileAccess.get_file_as_bytes(TONE))
		var face := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		face.fill(Color.ORANGE_RED)
		DirAccess.make_dir_recursive_absolute(dir.path_join("assets"))
		face.save_png(dir.path_join("assets/ember.png"))
	return dir


func _hunter(id: String, extra: Dictionary = {}) -> String:
	var def := {"schema": "lr.hunter/1", "id": id, "name": "Ember", "tier": "easy", "speed": 0.8, "chase": 3.5,
		"prog": 0.18, "sight": 8.0, "hearing": 1.0, "spawn": 12}
	def.merge(extra, true)
	return JSON.stringify(def)


## A minimal glTF binary holding `json`.
func _glb(json: Dictionary) -> PackedByteArray:
	var text := JSON.stringify(json).to_utf8_buffer()
	while text.size() % 4 != 0:
		text.append(0x20)
	var out := PackedByteArray()
	out.resize(20)
	out.encode_u32(0, 0x46546C67)
	out.encode_u32(4, 2)
	out.encode_u32(8, 20 + text.size())
	out.encode_u32(12, text.size())
	out.encode_u32(16, 0x4E4F534A)
	out.append_array(text)
	return out


## Rewrite `dir`'s pack.json with `changes` merged in.
func _manifest(dir: String, changes: Dictionary) -> String:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("pack.json")))
	manifest.merge(changes, true)
	_write(dir.path_join("pack.json"), JSON.stringify(manifest))
	return dir


func _rename(dir: String, name: String) -> String:
	var target := ROOT.path_join(name)
	DirAccess.rename_absolute(ContentPacks.os_path(dir), ContentPacks.os_path(target))
	return target


func _write(path: String, content) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if content is PackedByteArray:
		file.store_buffer(content)
	else:
		file.store_string(String(content))
	file.close()


## Delete `dir` and everything in it. Only test folders (their name carries "data_packs_test") are ever touched, and the walk
## uses absolute paths (ContentPacks.os_path) so a user data dir containing "//" cannot point it at the project.
func _wipe(dir: String) -> void:
	var path := ContentPacks.os_path(dir)
	if not path.contains("data_packs_test") or not DirAccess.dir_exists_absolute(path):
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
