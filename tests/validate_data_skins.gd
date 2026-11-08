extends RefCounted

## Player skins as data (docs/PLAYER_SKINS.md, "Skin catalog"; docs/modding/content-types.md, "Skins"): the shipped
## data/skins catalog loads and validates through PlayerSkin, a content pack's skins/ folder adds and overrides catalog
## skins with PNGs only (no code), unloading gives back the built-in catalog, every unsafe or broken skin refuses the
## whole pack, and the SKIN tab's FROM CATALOG feeds the usual preview -> APPLY flow.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- data_skins

const ROOT := "user://data_skins_test"

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	await host.get_tree().process_frame
	_wipe(ROOT)
	ContentRegistry.unload_packs()

	# ---- the kind exists and packs may ship it
	_expect(ContentRegistry.pack_kinds().has("skins"), "packs cannot ship a skins/ folder")
	_expect(ContentRegistry.extension_spec("skins").get("schema", "") == SkinCatalog.SCHEMA, "the skins kind is not declared")
	for line in ContentRegistry.errors():
		if line.contains("skins"):
			_expect(false, "built-in skins data has an error: %s" % line)

	# ---- the shipped catalog
	var builtin := SkinCatalog.entries()
	var ids := builtin.map(func(e: Dictionary) -> String: return String(e["id"]))
	_expect(ids.has("ref_classic") and ids.has("ref_slim"), "the shipped catalog lacks the reference skins (%s)" % [ids])
	_expect(builtin.all(func(e: Dictionary) -> bool: return String(e["pack"]).is_empty()), "a built-in skin claims a pack")
	var classic := SkinCatalog.load_skin("ref_classic")
	var slim := SkinCatalog.load_skin("ref_slim")
	_expect(classic["ok"] and not classic["slim"] and PlayerSkin.valid_hash(String(classic["hash"])), "ref_classic did not load as a classic skin (%s)" % classic.get("reason"))
	_expect(slim["ok"] and slim["slim"], "ref_slim did not load as a slim skin (%s)" % slim.get("reason"))
	_expect(classic["ok"] and PlayerSkin.validate(classic["png"])["hash"] == classic["hash"], "a catalog skin is not the canonical re-encoding (its hash would not share)")
	_expect(not SkinCatalog.load_skin("nobody")["ok"], "an unknown catalog id loaded")

	# ---- a pack adds one skin and overrides a shipped one, with PNGs only
	var good := _pack("skinpack", {
		"skins/ember.json": {"schema": "lr.skin/1", "id": "skinpack_ember", "name": "Ember", "image": "assets/ember.png", "author": "validator"},
		"skins/classic.json": {"schema": "lr.skin/1", "id": "ref_classic", "name": "Ember classic", "image": "assets/ember.png", "arms": "slim"},
	}, {"assets/ember.png": _skin_png(Color(.9, .35, .1))}, ["skins/ref_classic"])
	var report := ContentRegistry.load_packs([good])
	_expect(report["ok"], "a valid skins pack was refused: %s" % "; ".join(report["errors"]))
	if report["ok"]:
		var rows := SkinCatalog.entries()
		var by_id := {}
		for row in rows:
			by_id[row["id"]] = row
		_expect(by_id.has("skinpack_ember") and by_id["skinpack_ember"]["pack"] == "skinpack", "the pack skin is not in the catalog")
		_expect(by_id.has("ref_classic") and by_id["ref_classic"]["pack"] == "skinpack" and by_id["ref_classic"]["name"] == "Ember classic", "the override did not replace ref_classic")
		_expect(String(ContentRegistry.get_def("skins", "skinpack_ember")["image"]).begins_with(good + "/"), "the pack image path was not made absolute")
		var ember := SkinCatalog.load_skin("skinpack_ember")
		_expect(ember["ok"] and not ember["slim"], "the pack skin did not load (%s)" % ember.get("reason"))
		if ember["ok"]:
			var pixel: Color = (ember["image"] as Image).get_pixel(8, 8)
			_expect(absf(pixel.r - .9) < .02 and pixel.a == 1.0, "the pack skin's pixels are wrong (%s)" % pixel)
		var pinned := SkinCatalog.load_skin("ref_classic")
		_expect(pinned["ok"] and pinned["slim"], "an entry's arms did not pin the style")

		# the SKIN tab lists pack skins and previews without applying
		var settings_scene := load("res://game/menus/settings_overlay.tscn") as PackedScene
		if settings_scene != null:
			var saved := Settings.skin_hash
			var panel := settings_scene.instantiate()
			host.add_child(panel)
			await host.get_tree().process_frame
			var section := panel.find_child("SkinSection", true, false) as SkinPanel
			_expect(section != null and section.catalog_list != null, "the SKIN tab has no catalog list")
			if section != null and section.catalog_list != null:
				section.refresh_catalog()
				var index := -1
				for i in section.catalog_list.item_count:
					if section.catalog_list.get_item_metadata(i) == "skinpack_ember":
						index = i
				_expect(index >= 0 and section.catalog_list.get_item_text(index).contains("[skinpack]"), "the catalog list does not show the pack skin with its pack")
				if index >= 0:
					section.catalog_list.select(index)
					var preview: Dictionary = section._from_catalog()
					_expect(preview.get("ok", false) and preview["hash"] == ember["hash"], "FROM CATALOG did not preview the pack skin")
					_expect(Settings.skin_hash == saved, "FROM CATALOG applied before APPLY")
			panel.queue_free()
			await host.get_tree().process_frame
	ContentRegistry.unload_packs()
	_expect(not ContentRegistry.has("skins", "skinpack_ember"), "the pack skin survived unloading")
	_expect(ContentRegistry.pack_of("skins", "ref_classic").is_empty() and ContentRegistry.get_def("skins", "ref_classic")["name"] == "Reference (classic)", "unloading did not restore ref_classic")
	_expect(SkinCatalog.entries() == builtin, "unloading did not give back the built-in catalog")
	_expect(not SkinCatalog.load_skin("skinpack_ember")["ok"], "an unloaded pack's skin still loads")

	# ---- refused packs: all or nothing, the file named
	var art := {"assets/ember.png": _skin_png(Color(.2, .6, .9))}
	var ok_entry := {"schema": "lr.skin/1", "id": "badpack_x", "name": "X", "image": "assets/ember.png"}
	var cases := [
		["wrong size", {"skins/x.json": ok_entry}, {"assets/ember.png": Image.create(48, 48, false, Image.FORMAT_RGBA8).save_png_to_buffer()}, [], "is not a skin"],
		["unknown field", {"skins/x.json": _with(ok_entry, {"script": "res://evil.gd"})}, art, [], "unknown field"],
		["bad arms", {"skins/x.json": _with(ok_entry, {"arms": "tentacles"})}, art, [], "arms"],
		["missing name", {"skins/x.json": _with(ok_entry, {}, ["name"])}, art, [], "required"],
		["empty name", {"skins/x.json": _with(ok_entry, {"name": "  "})}, art, [], "name"],
		["escape", {"skins/x.json": _with(ok_entry, {"image": "assets/../pack.json"})}, art, [], "image"],
		["outside assets", {"skins/x.json": _with(ok_entry, {"image": "ember.png"})}, art, [], "image"],
		["not listed", {"skins/x.json": _with(ok_entry, {"image": "assets/missing.png"})}, art, [], "missing.png"],
		["foreign res", {"skins/x.json": _with(ok_entry, {"image": "res://assets/ui/hunter_portraits/aki.png"})}, art, [], "image"],
		["no prefix", {"skins/x.json": _with(ok_entry, {"id": "ember"})}, art, [], "must start with"],
		["undeclared override", {"skins/x.json": _with(ok_entry, {"id": "ref_slim"})}, art, [], "ref_slim"],
		["wrong schema", {"skins/x.json": _with(ok_entry, {"schema": "lr.skin/2"})}, art, [], "schema"],
		["script", {"skins/x.json": ok_entry, "skins/x.gd": "extends Node"}, art, [], "not allowed"],
	]
	for case in cases:
		var dir := _pack("badpack", case[1], case[2], case[3])
		var refused := ContentRegistry.load_packs([dir])
		var text := "; ".join(refused["errors"])
		_expect(not refused["ok"] and text.contains(String(case[4])), "%s: not refused with \"%s\" (%s)" % [case[0], case[4], text])
		_expect(not ContentRegistry.has("skins", "badpack_x") and ContentRegistry.loaded_packs().is_empty(), "%s: a refused pack left content behind" % case[0])
		_wipe(dir)

	ContentRegistry.unload_packs()
	_wipe(ROOT)
	if _failures == 0:
		print("  ok    data_skins: shipped catalog, pack add + override (PNG only), unload, %d refusals, SKIN tab FROM CATALOG" % cases.size())
	return _failures


func _with(base: Dictionary, changes: Dictionary, drop: Array = []) -> Dictionary:
	var out := base.duplicate(true)
	out.merge(changes, true)
	for key in drop:
		out.erase(key)
	return out


## A 64x64 skin: one colour on the base layer, clear overlay.
func _skin_png(color: Color) -> PackedByteArray:
	var image := Image.create(PlayerSkin.SIZE, PlayerSkin.SIZE, false, Image.FORMAT_RGBA8)
	for y in PlayerSkin.SIZE:
		for x in PlayerSkin.SIZE:
			image.set_pixel(x, y, Color(0, 0, 0, 0) if PlayerSkin.is_overlay_pixel(x, y) else color)
	return image.save_png_to_buffer()


func _pack(id: String, json: Dictionary, binary: Dictionary, overrides: Array) -> String:
	var dir := ROOT.path_join(id)
	_wipe(dir)
	DirAccess.make_dir_recursive_absolute(ContentPacks.os_path(dir))
	var files := {"pack.json": JSON.stringify({"schema": "lr.pack/1", "id": id, "name": "Test " + id, "version": "1.0.0",
		"overrides": overrides})}
	for rel in json:
		files[rel] = json[rel] if json[rel] is String else JSON.stringify(json[rel])
	for rel in files:
		_write(dir.path_join(rel), String(files[rel]).to_utf8_buffer())
	for rel in binary:
		_write(dir.path_join(rel), binary[rel])
	return dir


func _write(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ContentPacks.os_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _wipe(dir: String) -> void:
	var path := ContentPacks.os_path(dir)
	if not path.contains("data_skins_test") or not DirAccess.dir_exists_absolute(path):
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
		if not access.is_link(name):
			_remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)
