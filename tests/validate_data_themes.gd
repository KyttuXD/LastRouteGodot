extends RefCounted

## Themes as data (docs/WALL_THEMES.md, "Themes as data"): district wall sets, ceilings, arch accents and furniture
## finishes (data/themes/regions, lr.region_theme/1) and room-purpose wall sets (data/themes/rooms, lr.room_theme/1).
##   * parity: with no pack loaded every theme lookup is what the old RefLook / PropModelCatalog constants gave (hashes
##     taken on staging 29b79686, before the move), so the same seed builds the same world;
##   * packs: an override restating only some fields keeps the rest, a pack adds its own district / room theme and a
##     coordinated furniture set of its own; loading twice gives the same walls; unloading gives back the exact game;
##   * the checker refuses unknown keys, unpainted kinds, bad tints, unknown finishes and themes for nothing.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- data_themes

const Parity := preload("res://tests/data_parity.gd")
const ROOT := "user://data_packs_test/themes"
const PRINTER := "res://assets/props/maze/office_printer.glb"
const REGIONS := ["maze", "mansion", "hotel", "apartment", "beach", "gothic", "carnival", "prison", "inferno", "sewer",
	"hospital", "lab", "mall", "greenhouse", "office", "industrial", "nowhere"]
const ROOMS := ["", "bedroom", "kitchen", "storage", "chapel", "cove", "lab_office", "overgrown_room", "nothing_room"]
## Parity.sha of each fingerprint below on staging 29b79686, when these tables were still GDScript constants.
## walls / accent / style / room_style were re-frozen on purpose when the beach got its daylight-seaside look
## (new beach wall, ceiling and trim kinds, a theme for beach_hut and boardwalk_room, new legacy floor
## keys). Only beach data moved (district beach, rooms cove / tide_pool / beach_hut / boardwalk_room; the hash also asks every
## district about "cove", which only the beach generates); validate_beach_look pins the beach side and the shared kinds.
## "finish" and "variant" are untouched.
const FROZEN := {"walls": "72ee5f9487c43c53", "accent": "a52d7c8698c4b8ff", "finish": "b17ce64491abb3e4",
	"style": "d21c11971d7a98f4", "room_style": "6f9269680eee5370", "variant": "4cbbefb6419d14bf"}
## Generation does not read themes: these stay put with or without a theme pack (same staging commit).
const FROZEN_WORLD := {"mall": "0d522bcfef7f375b", "maze": "6570d74745233ad1", "mansion": "099008d66933388b",
	"props": "a6f6a236265acca0"}

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	_wipe()
	# only this suite's errors: other suites register test kinds and leave their refusals in the shared list
	var theme_errors := Array(ContentRegistry.errors()).filter(func(e): return String(e).contains("themes"))
	_expect(theme_errors.is_empty(), "built-in theme data has errors: %s" % ", ".join(theme_errors))
	_expect(ContentRegistry.ids("region_themes").size() == 16 and ContentRegistry.ids("room_themes").size() == 45,
		"expected 16 district and 45 room themes, got %d / %d" % [ContentRegistry.ids("region_themes").size(),
		ContentRegistry.ids("room_themes").size()])
	_expect(ContentRegistry.pack_kinds().has("region_themes") and ContentRegistry.pack_kinds().has("room_themes"),
		"packs cannot ship themes")
	var prints := _fingerprints()
	for key in FROZEN:
		_expect(prints[key] == FROZEN[key], "%s changed from the old constants: %s, was %s" % [key, prints[key], FROZEN[key]])
	_check_world("vanilla")
	var vanilla := _snapshot()
	_check_pack(vanilla)
	_check_rejections(vanilla)
	_wipe()
	if _failures == 0:
		print("  data_themes OK")
	return _failures


## What the view does with the theme tables, as hashes (the same function ran on the commit before the move).
func _fingerprints() -> Dictionary:
	var walls := []
	for region in REGIONS:
		for room in ROOMS:
			for x in 12:
				for z in 12:
					walls.append(RefLook.wall_kind(region, room, x * 3 - 7, z * 5 - 11))
	var style := REGIONS.map(func(r):
		var s: Dictionary = RefLook.REGION_STYLE.get(r, RefLook.REGION_STYLE["maze"])
		return [s.get("wall"), s.get("ceiling"), s.get("runner"), s.get("corridor"), s.get("room")])
	var variant := []
	for type in PropModelCatalog.VARIANT_THEMES:
		for i in 6:
			variant.append(PropModelCatalog.variant_theme(type, "c-prop-%d" % i, "room%d" % i))
			variant.append(PropModelCatalog.model_path(type, "c-prop-%d" % i, "", "Mansion"))
	return {"walls": Parity.sha(walls), "accent": Parity.sha(REGIONS.map(func(r): return RefLook.arch_accent(r))),
		"finish": Parity.sha(REGIONS.map(func(r): return PropModelCatalog.region_finish(r))), "style": Parity.sha(style),
		"room_style": Parity.sha(RefLook.ROOM_STYLE.keys().map(func(k): return [k, RefLook.ROOM_STYLE[k].get("wall"),
			RefLook.ROOM_STYLE[k].get("floor")])),
		"variant": Parity.sha([PropModelCatalog.VARIANT_THEMES, PropModelCatalog.COORDINATED_SET_TYPES, variant])}


func _check_world(label: String) -> void:
	for region in ["mall", "maze", "mansion"]:
		_expect(Parity.region_hash(region) == FROZEN_WORLD[region], "%s: %s chunks changed" % [label, region])
	_expect(Parity.props_hash() == FROZEN_WORLD["props"], "%s: office props / finishes changed" % label)


func _snapshot() -> String:
	return "\n".join([var_to_str(RefLook.REGION_STYLE), var_to_str(RefLook.ROOM_STYLE), var_to_str(RefLook.ARCH_ACCENT),
		var_to_str(PropModelCatalog.REGION_FINISHES), var_to_str(PropModelCatalog.COORDINATED_SET_TYPES),
		var_to_str(PropModelCatalog.VARIANT_THEMES), var_to_str(_fingerprints()), ContentRegistry.pack_hash()])


func _theme(id: String, fields: Dictionary, room: bool = false) -> String:
	var def := {"schema": "lr.room_theme/1" if room else "lr.region_theme/1", "id": id}
	def.merge(fields)
	return JSON.stringify(def)


func _pack(id: String, files: Dictionary, overrides: Array) -> String:
	var dir := ROOT.path_join(id)
	files["pack.json"] = JSON.stringify({"schema": "lr.pack/1", "id": id, "name": "Themes " + id, "version": "1.0.0",
		"author": "validator", "overrides": overrides})
	for rel in files:
		_write(dir.path_join(rel), files[rel])
	return dir


func _check_pack(vanilla: String) -> void:
	var trim_before := RefDecor.arch_trim_material("mansion")
	var dir := _pack("thm", {
		# override restating two fields: mansion walls become brick and its lacquered finish goes; ceiling/accent stay
		"region_themes/mansion.json": _theme("mansion", {"wall": ["brick0", "brick1"], "finish": ""}),
		# the hotel borrows the mansion finish and a steel accent
		"region_themes/hotel.json": _theme("hotel", {"finish": "Mansion", "accent": {"texture": "floor", "kind": "metal1",
			"tint": "#8a96a0", "metal": true}}),
		# a pack district of its own (for a pack region of the same id)
		"region_themes/thm_vault.json": _theme("thm_vault", {"wall": ["lab1"], "ceiling": "vault"}),
		"room_themes/bedroom.json": _theme("bedroom", {"wall": ["stone0"]}, true),
		"room_themes/thm_den.json": _theme("thm_den", {"wall": ["hedge0", "hedge1"]}, true),
		# a coordinated furniture set in a family of its own: one finish per room, like the built-in sets
		"props/thm_set.json": JSON.stringify({"schema": "lr.prop/1", "family": "thm_set", "props": [
			{"id": "thm_chair", "models": ["assets/a.glb", "assets/b.glb"], "themes": ["rose", "slate"], "coordinated": true},
			{"id": "thm_table", "models": ["assets/a.glb", "assets/b.glb"], "themes": ["rose", "slate"], "coordinated": true}]}),
	}, ["region_themes/mansion", "region_themes/hotel", "room_themes/bedroom"])
	_write(dir.path_join("assets/a.glb"), FileAccess.get_file_as_bytes(PRINTER))
	_write(dir.path_join("assets/b.glb"), FileAccess.get_file_as_bytes(PRINTER))
	var report := ContentRegistry.load_packs([dir])
	_expect(report["ok"], "the theme pack was refused: %s" % ", ".join(report["errors"]))
	if report["ok"]:
		var mansion: Dictionary = RefLook.REGION_STYLE["mansion"]
		_expect(mansion["wall"] == ["brick0", "brick1"], "mansion wall override not applied: %s" % [mansion["wall"]])
		_expect(mansion["ceiling"] == "ceil1" and mansion["runner"] == true, "mansion lost fields the override left out")
		_expect(RefLook.arch_accent("mansion")[1] == "metal0", "mansion accent lost")
		_expect(["brick0", "brick1"].has(RefLook.wall_kind("mansion", "", 5, 9)), "wall_kind ignores the override")
		_expect(PropModelCatalog.region_finish("mansion") == "" and PropModelCatalog.region_finish("hotel") == "Mansion",
			"finish overrides not applied: %s" % [PropModelCatalog.REGION_FINISHES])
		_expect(PropModelCatalog.model_path("woodenChair", "a-prop-1", "r1", PropModelCatalog.region_finish("hotel"))
			.contains("Mansion"), "the hotel finish did not reach model_path")
		_expect(RefLook.arch_accent("hotel")[1] == "metal1" and RefLook.arch_accent("hotel")[2] == Color("8a96a0"),
			"hotel accent override not applied")
		_expect(RefDecor.arch_trim_material("mansion") != trim_before, "trim material cache survived the pack load")
		_expect(RefLook.REGION_STYLE.get("thm_vault", {}).get("wall") == ["lab1"]
			and RefLook.wall_kind("thm_vault", "", 0, 0) == "lab1" and RefLook.REGION_STYLE["thm_vault"]["ceiling"] == "vault",
			"pack district theme missing")
		_expect(RefLook.wall_kind("maze", "bedroom", 3, 3) == "stone0", "room theme override not applied")
		_expect(RefLook.wall_kind("maze", "thm_den", 3, 3) in ["hedge0", "hedge1"], "pack room theme missing")
		_expect(RefLook.ROOM_STYLE["bedroom"].get("floor") == ["floral0", "parquet1"], "room override dropped the legacy floor")
		_expect(PropModelCatalog.COORDINATED_SET_TYPES.has("thm_chair") and PropModelCatalog.COORDINATED_SET_TYPES.has("thm_table"),
			"a pack's own coordinated set is not coordinated")
		var same := true
		for i in 12:
			var instance := "room%d-prop-%d" % [i, i]
			same = same and PropModelCatalog.variant_theme("thm_chair", instance) == PropModelCatalog.variant_theme("thm_table", instance + "x")
		_expect(same, "the pack set mixes finishes inside one room")
		_check_world("theme pack")
		var loaded := _snapshot()
		ContentRegistry.unload_packs()
		ContentRegistry.load_packs([dir])
		_expect(_snapshot() == loaded, "loading the same theme pack twice gave different themes")
	ContentRegistry.unload_packs()
	_expect(_snapshot() == vanilla, "unloading the theme pack did not restore the built-in themes")
	_expect(RefDecor.arch_trim_material("mansion").get_shader_parameter("tint") == RefLook.ARCH_ACCENT["mansion"][2],
		"trim material after unload is not the built-in accent")


func _check_rejections(vanilla: String) -> void:
	var cases := [
		["unknown key", {"region_themes/maze.json": _theme("maze", {"wall": ["panel0"], "glow": 1})}, ["region_themes/maze"], "glow"],
		["unpainted wall kind", {"region_themes/maze.json": _theme("maze", {"wall": ["marble9"]})}, ["region_themes/maze"], "marble9"],
		["empty wall set", {"room_themes/kitchen.json": _theme("kitchen", {"wall": []}, true)}, ["room_themes/kitchen"], "wall"],
		["room without walls", {"room_themes/thmbad_x.json": _theme("thmbad_x", {}, true)}, [], "needs \"wall\""],
		["bad ceiling", {"region_themes/maze.json": _theme("maze", {"ceiling": "sky"})}, ["region_themes/maze"], "ceiling"],
		["bad tint", {"region_themes/maze.json": _theme("maze", {"accent": {"texture": "floor", "kind": "metal0",
			"tint": "goldish", "metal": true}})}, ["region_themes/maze"], "tint"],
		["accent kind", {"region_themes/maze.json": _theme("maze", {"accent": {"texture": "floor", "kind": "paper0",
			"tint": "#ffffff", "metal": false}})}, ["region_themes/maze"], "paper0"],
		["unknown finish", {"region_themes/maze.json": _theme("maze", {"finish": "Gold"})}, ["region_themes/maze"], "finish"],
		["empty theme", {"region_themes/thmbad_y.json": _theme("thmbad_y", {})}, [], "at least one"],
		["override of nothing", {"region_themes/atlantis.json": _theme("atlantis", {"wall": ["panel0"]})},
			["region_themes/atlantis"], "does not have"],
		["unprefixed id", {"region_themes/atlantis.json": _theme("atlantis", {"wall": ["panel0"]})}, [], "must start with"],
		["script", {"region_themes/run.gd": "extends Node"}, [], "run.gd"],
	]
	var index := 0
	for case in cases:
		var dir := _pack("thmbad%d" % index if not String(case[0]).begins_with("room without") and String(case[0]) != "empty theme"
			else "thmbad", case[1], case[2])
		var report := ContentRegistry.load_packs([dir])
		var errors := ", ".join(report["errors"])
		_expect(not report["ok"] and errors.contains(String(case[3])), "%s: not refused naming \"%s\": %s" % [case[0], case[3], errors])
		_expect(_snapshot() == vanilla, "%s: a refused pack changed the themes" % case[0])
		_remove_tree(ContentPacks.os_path(dir))
		index += 1


func _write(path: String, content) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if content is PackedByteArray:
		file.store_buffer(content)
	else:
		file.store_string(String(content))
	file.close()


func _wipe() -> void:
	var path := ContentPacks.os_path(ROOT)
	if path.contains("data_packs_test") and DirAccess.dir_exists_absolute(path):
		_remove_tree(path)


func _remove_tree(path: String) -> void:
	var access := DirAccess.open(path)
	if access == null:
		return
	access.include_hidden = true
	for name in access.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name in access.get_directories():
		_remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)
