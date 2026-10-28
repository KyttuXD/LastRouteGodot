extends RefCounted

## Props as data (docs/DATA_DRIVEN_CONTENT.md): every res://data/props family passes the schema, every model it names
## exists, finishes line up with models, the office pilot is exactly the catalog constants it replaced (paths, finishes,
## coordinated-set order), and the parity fingerprint is printed for the before/after comparison.
##
##   godot --headless --path . res://scenes/validate.tscn -- data_props

const Parity := preload("res://scripts/data_parity.gd")

const OFFICE := ["officeDesk", "officeChair", "officeCrtSecurityConsole", "officeCubiclePartition", "officePrinter",
	"officeWaterCooler", "officePhotocopier", "officeShredder", "officeFileBoxes", "officeCornerWorkstation"]
const OFFICE_FILES := ["office_desk", "office_task_chair", "office_crt_security_console", "office_cubicle_partition",
	"office_printer", "office_water_cooler", "office_photocopier", "office_shredder", "office_file_boxes",
	"office_corner_workstation"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	_expect(ContentRegistry.errors().is_empty(), "res://data has errors: %s" % ", ".join(ContentRegistry.errors()))
	for id in ContentRegistry.ids("props"):
		var def := ContentRegistry.get_def("props", id)
		for path in def["models"]:
			_expect(ResourceLoader.exists(String(path)), "%s names a missing model %s" % [id, path])
		_expect(not def.has("themes") or (def["themes"] as Array).size() == (def["models"] as Array).size(),
			"%s has %d finishes for %d models" % [id, (def.get("themes", []) as Array).size(), (def["models"] as Array).size()])
		_expect(PropModelCatalog.MODEL_PATHS.get(id, []) == def["models"], "%s is not in PropModelCatalog.MODEL_PATHS" % id)
	# pilot parity with the constants as they were
	_expect(ContentRegistry.family("office") == OFFICE, "office family order changed: %s" % [ContentRegistry.family("office")])
	for i in OFFICE.size():
		var type: String = OFFICE[i]
		var base := "res://art/props-3d/props/maze/%s" % OFFICE_FILES[i]
		_expect(var_to_str(PropModelCatalog.MODEL_PATHS.get(type)) == var_to_str([base + ".glb", base + "_charcoal.glb",
			base + "_teal.glb"]), "%s model paths differ from the old constant" % type)
		_expect(var_to_str(PropModelCatalog.VARIANT_THEMES.get(type)) == var_to_str(["neutral", "charcoal", "teal"]),
			"%s finishes differ from the old constant" % type)
	var coordinated := PropModelCatalog.COORDINATED_SET_TYPES
	var start := coordinated.find("officeDesk")
	_expect(start == coordinated.find("retroComputerTerminal") + 1 and coordinated.slice(start, start + OFFICE.size()) == OFFICE
		and coordinated.find("singleBed") == start + OFFICE.size(), "office coordinated-set entries moved")
	_expect(not coordinated.any(func(v): return String(v).begins_with(ContentRegistry.DATA)), "an unresolved @data marker is left")
	for table in [PropModelCatalog.MODEL_PATHS, PropModelCatalog.VARIANT_THEMES]:
		_expect(not table.values().has(ContentRegistry.DATA), "an unresolved @data value is left")
	_expect(PropModelCatalog.MODEL_PATHS.is_read_only(), "PropModelCatalog.MODEL_PATHS became writable")
	_check_rejections()
	_check_export_presets()
	print("  parity props %s" % Parity.props_hash())
	if _failures == 0:
		print("  data_props OK")
	return _failures


## Every export preset ships res://data: JSON is not an imported resource, so a preset without the filter would export
## a build whose migrated hunters, props and regions are simply missing.
func _check_export_presets() -> void:
	var presets := ConfigFile.new()
	if presets.load("res://export_presets.cfg") != OK:
		return
	for section in presets.get_sections():
		if not section.ends_with(".options") and presets.has_section_key(section, "include_filter"):
			_expect("data/*.json" in String(presets.get_value(section, "include_filter")),
				"export preset %s does not include data/*.json" % presets.get_value(section, "name", section))


func _check_rejections() -> void:
	var cases := {
		'{"schema": "lr.prop/1", "family": "x", "props": [{"id": "a", "models": "one.glb"}]}': "\"models\" must be strings",
		'{"schema": "lr.prop/1", "family": "x", "props": [{"id": "a", "models": [], "colour": "red"}]}': "unknown key \"colour\"",
		'{"schema": "lr.prop/1", "family": "x"}': "needs \"family\"",
		'{"schema": "lr.prop/1", "family": "x", "props": [{"models": []}]}': "\"id\" must be",
	}
	var path := "user://data_props_fixture.json"
	for text in cases:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		var parsed := ContentRegistry.parse_file(path, "props")
		var joined := " | ".join(parsed["errors"])
		_expect((parsed["defs"] as Array).is_empty() and path in joined and String(cases[text]) in joined,
			"bad prop file not rejected clearly (%s): %s" % [cases[text], joined])
	DirAccess.remove_absolute(path)
