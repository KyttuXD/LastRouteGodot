extends RefCounted

## No model import may generate mesh LODs: Godot's decimation merges and drops the cubes of these small block models at a
## distance (hunter hands and forearms vanish, prop cubes smear). Covers every .glb/.gltf import in the project.

var _failures := 0


func _scan(dir: String, found: Array) -> void:
	var access := DirAccess.open(dir)
	if access == null:
		return
	for entry in access.get_directories():
		if not entry.begins_with(".") and entry != "build":
			_scan(dir.path_join(entry), found)
	for file in access.get_files():
		if file.ends_with(".glb.import") or file.ends_with(".gltf.import"):
			found.append(dir.path_join(file))


func run(_host: Node) -> int:
	var imports := []
	_scan("res://", imports)
	var bad := []
	for path in imports:
		var config := ConfigFile.new()
		if config.load(String(path)) == OK and bool(config.get_value("params", "meshes/generate_lods", false)):
			bad.append(String(path))
	if not bad.is_empty():
		print("  FAIL  %d of %d model imports generate mesh LODs (e.g. %s)" % [bad.size(), imports.size(), bad[0]])
		_failures += 1
	var defaults = ProjectSettings.get_setting("importer_defaults/scene", {})
	if not (defaults is Dictionary and defaults.get("meshes/generate_lods", true) == false):
		print("  FAIL  project importer defaults do not turn mesh LOD generation off")
		_failures += 1
	if _failures == 0:
		print("  lods  %d model imports, none generate mesh LODs; importer default is off" % imports.size())
	return _failures
