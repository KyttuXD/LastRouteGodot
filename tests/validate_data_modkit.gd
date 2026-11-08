extends RefCounted

## Mod starter kit (tools/modpack, docs/modding/): init scaffolds a pack that validates as-is, validate reports the
## loader's own errors plus model and size findings, and pack's identity sha256 equals what the game, the download
## check and the published index use (the shipped ember example stays at its published hash).
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- data_modkit

const ROOT := "user://data_modkit_test"
## ember 1.0.0 as published on the pack index
const EMBER_SHA := "35c0b6ee57ddb3281a4922040006c368a68f144289421a3b5dc2655de6197923"

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	_wipe(ROOT)
	var made := ModKit.init_pack("kitpack", ROOT)
	_expect(made["errors"].is_empty(), "init failed: %s" % [made["errors"]])
	var dir: String = made["dir"]
	var checked := ModKit.validate(dir)
	_expect(checked["errors"].is_empty(), "a fresh template does not validate: %s" % [checked["errors"]])
	var hunters: Array = ContentPacks.read(dir)["defs"]["hunters"]
	_expect(hunters.size() == 1 and String(hunters[0]["id"]) == "kitpack_runner", "init did not rename the template ids")
	_expect(not ModKit.init_pack("kitpack", ROOT)["errors"].is_empty(), "init overwrote an existing pack")
	_expect(not ModKit.init_pack("No-Caps", ROOT)["errors"].is_empty(), "init accepted a bad pack id")

	# one identity everywhere: the kit, the loader, the download check
	var manifest := ModKit.manifest(dir)
	_expect(manifest["sha256"] == ContentPacks.read(dir)["sha256"], "pack sha differs from the loader's")
	_expect(manifest["sha256"] == PackDownloads._identity(manifest["files"]), "pack sha differs from the download check's")
	_expect(manifest["files"].any(func(f): return f["path"] == "pack.json"), "manifest leaves out pack.json")
	_expect(ModKit.manifest("res://examples/mods/ember")["sha256"] == EMBER_SHA, "the ember example moved off its published hash")
	_expect(ModKit.validate("res://examples/mods/ember")["errors"].is_empty(), "the ember example does not validate")

	# validate reports what the loader refuses, and models the game could not show
	_write(dir.path_join("assets/run.gd"), "extends Node".to_utf8_buffer())
	_expect(Array(ModKit.validate(dir)["errors"]).any(func(e): return String(e).contains("run.gd")), "a script was not reported")
	DirAccess.remove_absolute(ContentPacks.os_path(dir.path_join("assets/run.gd")))
	_write(dir.path_join("assets/water_cooler.glb"), _empty_glb())
	_expect(Array(ModKit.validate(dir)["errors"]).any(func(e): return String(e).contains("no visible mesh")),
		"a model with no mesh was not reported")

	# sizes against a category table (the same rules as ScaleFit)
	var ranges := {"hunter_factor": 1.5, "categories": [
		{"id": "lamp", "words": ["Lamp"], "height": [0.4, 1.0]},
		{"id": "stage", "words": ["Stage"], "exempt": "set piece"}]}
	var errors := PackedStringArray()
	var warnings := ModKit._size_findings({"x_DeskLamp": Vector3(0.4, 1.2, 0.4), "x_TallLamp": Vector3(0.4, 3.0, 0.4),
		"x_Stage": Vector3(9, 9, 9), "x_Thing": Vector3(1, 1, 1)}, errors, ranges)
	_expect(errors.size() == 1 and errors[0].contains("x_TallLamp"), "size errors wrong: %s" % [errors])
	_expect(warnings.size() == 1 and warnings[0].contains("x_Thing"), "uncategorised prop not warned: %s" % [warnings])

	_wipe(ROOT)
	if _failures == 0:
		print("  data_modkit OK")
	return _failures


## A glTF binary with a scene but no meshes.
func _empty_glb() -> PackedByteArray:
	var text := JSON.stringify({"asset": {"version": "2.0"}, "scenes": [{"nodes": [0]}], "nodes": [{"name": "Empty"}],
		"scene": 0}).to_utf8_buffer()
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


func _write(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ContentPacks.os_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


## Delete `dir` (only the data_modkit_test folder) through absolute paths.
func _wipe(dir: String) -> void:
	var path := ContentPacks.os_path(dir)
	if not path.contains("data_modkit_test") or not DirAccess.dir_exists_absolute(path):
		return
	_remove_tree(path)


func _remove_tree(path: String) -> void:
	for name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(name))
	for name in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)
