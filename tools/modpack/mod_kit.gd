class_name ModKit
extends RefCounted

## The mod starter kit (docs/modding/): scaffold, validate and fingerprint a content pack with the game's own rules.
## Everything here calls the loader (ContentPacks / ContentRegistry) rather than re-implementing it, so a pack that
## passes `validate` is a pack the game loads, and `pack` prints the identity sha256 the room handshake and the pack
## index use. Run through tools/modpack/modpack.sh (init | validate | pack).

const TEMPLATE := "res://examples/mods/template"
const TEMPLATE_ID := "template"
## Person-scale prop size table; checked when this build has it.
const SIZE_RANGES := "res://data/scale/prop_size_ranges.json"


## Copy the template pack to <parent>/<id>, renamed for `id`. {"dir", "errors"}.
static func init_pack(id: String, parent: String) -> Dictionary:
	var dir := parent.path_join(id)
	if not ContentPacks._is_pack_id(id):
		return {"dir": dir, "errors": ["\"%s\" is not a pack id: 3-32 lower-case letters, digits or _, starting with a letter or digit" % id]}
	if DirAccess.dir_exists_absolute(ContentPacks.os_path(dir)):
		return {"dir": dir, "errors": ["%s already exists" % dir]}
	_copy_tree(TEMPLATE, dir)
	for rel in _files(dir):
		if rel.get_extension() != "json":
			continue
		var text := FileAccess.get_file_as_string(dir.path_join(rel))
		text = text.replace("\"%s_" % TEMPLATE_ID, "\"%s_" % id)
		if rel == "pack.json":
			text = text.replace("\"id\": \"%s\"" % TEMPLATE_ID, "\"id\": \"%s\"" % id)
		var out := FileAccess.open(dir.path_join(rel), FileAccess.WRITE)
		out.store_string(text)
		out.close()
	return {"dir": dir, "errors": []}


## Every check a pack must pass: the loader's own rules (ContentPacks.read and the cross-pack checks), every model loads
## as a stripped scene, and props sit inside their size category. {"errors", "warnings", "summary"}.
static func validate(dir: String) -> Dictionary:
	var result := {"errors": PackedStringArray(), "warnings": PackedStringArray(), "summary": {}}
	var pack := ContentPacks.read(dir, ContentPacks.LIMITS, not dir.contains("/.cache/"))
	result["errors"].append_array(pack["errors"])
	if not pack["errors"].is_empty():
		return result
	result["errors"].append_array(ContentRegistry._conflicts([pack]))
	var counts := {}
	for kind in ContentPacks.kinds():
		counts[kind] = pack["defs"][kind].size()
	var bytes := 0
	for file in pack["files"]:
		bytes += int(file["bytes"])
	result["summary"] = {"id": pack["manifest"]["id"], "version": pack["manifest"]["version"], "files": pack["files"].size(),
		"bytes": bytes, "sha256": pack["sha256"], "defs": counts}
	# models: what the game will actually instance, after scripts and extension nodes are stripped
	var sizes := {}
	for def in pack["defs"]["props"]:
		var box := AABB()
		for model in def["models"]:
			var scene := ContentPacks.load_scene(String(model))
			if scene == null:
				result["errors"].append("%s: %s does not load as a model" % [def["id"], String(model).get_file()])
				continue
			var node := scene.instantiate() as Node3D
			var bounds := _bounds(node)
			node.free()
			if bounds.size == Vector3.ZERO:
				result["errors"].append("%s: %s has no visible mesh" % [def["id"], String(model).get_file()])
			box = bounds if box.size == Vector3.ZERO else box.merge(bounds)
		sizes[def["id"]] = box.size
	result["warnings"].append_array(_size_findings(sizes, result["errors"]))
	return result


## The pack's identity and file manifest: {"sha256", "files": [{path, sha256, size}]} -- the same sha256 the game's
## handshake and the pack index use (sorted "<sha256> <path>" lines over every file, pack.json included).
static func manifest(dir: String) -> Dictionary:
	var pack := ContentPacks.read(dir, ContentPacks.LIMITS, not dir.contains("/.cache/"))
	var files := []
	for file in pack["files"]:
		files.append({"path": file["path"], "sha256": file["sha256"], "size": file["bytes"]})
	return {"errors": pack["errors"], "sha256": pack["sha256"], "files": files,
		"id": pack["manifest"].get("id", ""), "version": pack["manifest"].get("version", "")}


## Props outside their person-scale category (x hunter factor) are errors, uncategorised ones warnings. Skipped with a
## warning when this build has no size table.
static func _size_findings(sizes: Dictionary, errors: PackedStringArray, ranges: Dictionary = {}) -> PackedStringArray:
	var warnings := PackedStringArray()
	if sizes.is_empty():
		return warnings
	if ranges.is_empty():
		if not FileAccess.file_exists(SIZE_RANGES):
			warnings.append("size check skipped: %s is not in this build" % SIZE_RANGES)
			return warnings
		ranges = JSON.parse_string(FileAccess.get_file_as_string(SIZE_RANGES))
	var factor := float(ranges.get("hunter_factor", 1.5))
	var keep: Dictionary = ranges.get("keep_person_size", {})
	for id in sizes:
		var size: Vector3 = sizes[id]
		if keep.has(id) or size == Vector3.ZERO:
			continue
		var category := _category(ranges.get("categories", []), String(id))
		if category.is_empty():
			warnings.append("%s matches no size category (%s): the game cannot check its scale" % [id, SIZE_RANGES])
			continue
		if category.has("exempt"):
			continue
		var dims := {"height": size.y, "long": maxf(size.x, size.z), "short": minf(size.x, size.z)}
		for key in ["height", "long", "short"]:
			if not category.has(key):
				continue
			var lo := float(category[key][0]) * factor
			var hi := float(category[key][1]) * factor
			if float(dims[key]) < lo - .005 or float(dims[key]) > hi + .005:
				errors.append("%s (%s): %s %.2f m is outside %.2f-%.2f m (person-scale range x %.1f hunter scale)" % [id,
					category["id"], key, dims[key], lo, hi, factor])
	return warnings


## The first category whose words appear in the id and whose "not" words do not (same rule as ScaleFit).
static func _category(categories: Array, id: String) -> Dictionary:
	for value in categories:
		var category: Dictionary = value
		var hit := false
		for word in category.get("words", []):
			if id.contains(String(word)):
				hit = true
		for word in category.get("not", []):
			if id.contains(String(word)):
				hit = false
		if hit:
			return category
	return {}


static func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var have := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var transform := Transform3D.IDENTITY
		var walk: Node = mesh
		while walk != null and walk != root:
			if walk is Node3D:
				transform = (walk as Node3D).transform * transform
			walk = walk.get_parent()
		var local := transform * mesh.get_aabb()
		box = local if not have else box.merge(local)
		have = true
	return box


static func _files(dir: String, rel: String = "") -> Array:
	var out := []
	var path := ContentPacks.os_path(dir.path_join(rel))
	for name in DirAccess.get_files_at(path):
		out.append(name if rel.is_empty() else rel.path_join(name))
	for name in DirAccess.get_directories_at(path):
		out.append_array(_files(dir, name if rel.is_empty() else rel.path_join(name)))
	return out


static func _copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(ContentPacks.os_path(to))
	for name in DirAccess.get_files_at(ContentPacks.os_path(from)):
		var out := FileAccess.open(to.path_join(name), FileAccess.WRITE)
		out.store_buffer(FileAccess.get_file_as_bytes(from.path_join(name)))
		out.close()
	for name in DirAccess.get_directories_at(ContentPacks.os_path(from)):
		_copy_tree(from.path_join(name), to.path_join(name))
