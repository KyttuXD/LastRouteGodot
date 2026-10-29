class_name ContentPacks
extends RefCounted

## Player content packs (docs/DATA_DRIVEN_CONTENT.md, "Mod packs"): JSON in the same schemas as res://data plus
## png/ogg/glb assets, never scripts. read() turns one pack folder into definitions and a file list, or into errors that
## name the file; nothing here touches ContentRegistry, so a rejected pack leaves the game exactly as it was.
##
##   user://mods/<pack_id>/pack.json            {"schema": "lr.pack/1", "id", "name", "version", "author"?, "overrides"?}
##   user://mods/<pack_id>/{props,regions,hunters}/*.json
##   user://mods/<pack_id>/assets/**.{glb,png,ogg}
##
## Ids a pack adds must start with "<pack_id>_" so they can never collide with the game or another pack. A pack may
## replace a built-in id only when its manifest lists it under "overrides" as "<kind>/<id>".

const ROOT := "user://mods"
const SCHEMA := "lr.pack/1"
## Folders a pack may ship: ContentRegistry.pack_kinds() (built-in pack kinds plus other lanes' extension kinds).
static func kinds() -> Array:
	return ContentRegistry.pack_kinds()
## Kinds that only replace built-in things (a new id would never be used): every entry must be listed in overrides.
const OVERRIDE_ONLY_KINDS := ["sounds", "ambience", "floors", "walls", "ceilings"]
const ASSET_EXTENSIONS := ["glb", "png", "ogg"]
## Finder litter that is skipped (and left out of the hash) rather than rejecting a hand-installed pack.
const IGNORED_NAMES := [".DS_Store"]
const LIMITS := {"file_bytes": 16 * 1024 * 1024, "pack_bytes": 128 * 1024 * 1024, "files": 512}
## Shared with the TOOLS pack index (backend/README.md, "Mod packs"): keep the two in step.
const MANIFEST_FIELDS := {"schema": "string", "id": "string", "name": "string", "version": "string",
	"author": "string?", "description": "string?", "game_version": "string?", "overrides": "strings?", "files": "files?"}
## glTF extensions a pack model may use. Anything else (physics bodies, lights, vendor extensions) rejects the pack.
const GLTF_EXTENSIONS := ["KHR_materials_emissive_strength", "KHR_materials_unlit", "KHR_texture_transform",
	"KHR_mesh_quantization"]
## Node classes kept from a pack model; everything else the glTF importer creates is dropped.
const MODEL_NODE_CLASSES := ["Node3D", "MeshInstance3D", "ImporterMeshInstance3D", "Skeleton3D", "BoneAttachment3D",
	"AnimationPlayer"]
## Built-in folders a pack hunter may borrow a body from (a variant wearing a shipped hunter's model).
const BUILTIN_MODEL_ROOTS := ["res://assets/hunters_blocky/", "res://art/props-3d/characters/"]
## A pack hunter may use a shipped portrait instead of its own PNG (HunterDossier.PORTRAIT_DIR).
const BUILTIN_PORTRAIT_ROOT := "res://assets/ui/hunter_portraits/"
## Pack hunters join the seeded route draw, so they must sit in a tier the draw weights.
const DRAW_TIERS := ["easy", "intermediate", "difficult"]


## `path` as an absolute OS path for DirAccess. Listing a user:// folder through DirAccess goes wrong when the user data
## dir itself contains "//" (a TMPDIR or HOME ending in "/"): it lists the working directory instead. FileAccess is not
## affected, so only directory operations go through this.
static func os_path(path: String) -> String:
	return ProjectSettings.globalize_path(path).simplify_path() if path.begins_with("user://") else path


## Hand-installed packs: every folder under `root` holding a pack.json, sorted.
static func discover(root: String = ROOT) -> PackedStringArray:
	var out := PackedStringArray()
	for name in DirAccess.get_directories_at(os_path(root)):
		if not String(name).begins_with(".") and FileAccess.file_exists(root.path_join(name).path_join("pack.json")):
			out.append(root.path_join(name))
	out.sort()
	return out


## One pack folder -> {"dir", "manifest", "defs": {kind: [def]}, "files": [{path, bytes, sha256}], "sha256", "errors"}.
## `defs` hold runtime values with pack-relative asset paths made absolute and prop families namespaced by pack id.
static func read(dir: String, limits: Dictionary = LIMITS, folder_is_id: bool = true) -> Dictionary:
	var pack := {"dir": dir, "manifest": {}, "defs": _empty_defs(), "files": [],
		"sha256": "", "errors": PackedStringArray()}
	var errors: PackedStringArray = pack["errors"]
	var paths := []
	_list(dir, "", paths, errors)
	paths.sort()
	if paths.size() > int(limits["files"]):
		errors.append("%s: %d files, the limit is %d" % [dir, paths.size(), limits["files"]])
		return pack
	var folded := {}
	var total := 0
	for rel in paths:
		var where := "%s/%s" % [dir, rel]
		var problem := _placement_problem(rel)
		if not problem.is_empty():
			errors.append("%s: %s" % [where, problem])
			continue
		if folded.has(rel.to_lower()):
			errors.append("%s: same name as %s apart from letter case" % [where, folded[rel.to_lower()]])
			continue
		folded[rel.to_lower()] = rel
		var bytes := FileAccess.get_file_as_bytes(dir.path_join(rel))
		if bytes.size() > int(limits["file_bytes"]):
			errors.append("%s: %d bytes, the per-file limit is %d" % [where, bytes.size(), limits["file_bytes"]])
			continue
		total += bytes.size()
		pack["files"].append({"path": rel, "bytes": bytes.size(), "sha256": _sha256(bytes)})
	if total > int(limits["pack_bytes"]):
		errors.append("%s: %d bytes in all, the pack limit is %d" % [dir, total, limits["pack_bytes"]])
	if not errors.is_empty():
		return pack
	var lines := PackedStringArray()
	for file in pack["files"]:
		lines.append("%s %s" % [file["sha256"], file["path"]])
	pack["sha256"] = _sha256("\n".join(lines).to_utf8_buffer())

	var manifest := _read_manifest(dir, folder_is_id, errors)
	if manifest.is_empty():
		return pack
	pack["manifest"] = manifest
	if manifest.has("files"):
		_check_file_list(manifest["files"], pack["files"], dir, errors)
	var pack_id := String(manifest["id"])
	var assets := {}
	for file in pack["files"]:
		if String(file["path"]).begins_with("assets/"):
			assets[file["path"]] = true
	for file in pack["files"]:
		var rel := String(file["path"])
		var kind := rel.get_base_dir()
		if not kinds().has(kind):
			continue
		var parsed := ContentRegistry.parse_file(dir.path_join(rel), kind)
		errors.append_array(parsed["errors"])
		for def in parsed["defs"]:
			var finished := _finish_def(def, kind, manifest, dir, rel, assets, errors)
			if not finished.is_empty():
				pack["defs"][kind].append(finished)
	for rel in assets:
		_check_asset(dir.path_join(rel), "%s/%s" % [dir, rel], errors)
	if not errors.is_empty():
		pack["defs"] = _empty_defs()
	return pack


static func _empty_defs() -> Dictionary:
	var out := {}
	for kind in kinds():
		out[kind] = []
	return out


## A pack model as a scene with every script, extension node, light, camera and physics body removed, or null.
static func load_scene(path: String) -> PackedScene:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	var root := doc.generate_scene(state)
	if root == null:
		return null
	_strip(root, root)
	var scene := PackedScene.new()
	var packed := scene.pack(root) == OK
	root.free()
	return scene if packed else null


static func _strip(node: Node, root: Node) -> void:
	node.set_script(null)
	for child in node.get_children():
		if not MODEL_NODE_CLASSES.has(child.get_class()):
			node.remove_child(child)
			child.free()
			continue
		child.owner = root
		_strip(child, root)


static func _list(dir: String, rel: String, out: Array, errors: PackedStringArray) -> void:
	var access := DirAccess.open(os_path(dir.path_join(rel)))
	if access == null:
		errors.append("%s: cannot be opened" % dir.path_join(rel))
		return
	access.include_hidden = true
	access.list_dir_begin()
	var name := access.get_next()
	while not name.is_empty():
		var child := name if rel.is_empty() else "%s/%s" % [rel, name]
		if access.is_link(name):
			errors.append("%s/%s: links are not allowed in a pack" % [dir, child])
		elif access.current_is_dir():
			_list(dir, child, out, errors)
		elif not IGNORED_NAMES.has(name):
			out.append(child)
		name = access.get_next()
	access.list_dir_end()


## "" when `rel` may sit in a pack, else why not. Only the manifest, kind JSON one level deep and assets are allowed.
static func _placement_problem(rel: String) -> String:
	if rel.contains("\\") or rel.contains(":") or rel.begins_with("/") or rel.split("/").has(".."):
		return "path escapes the pack"
	for part in rel.split("/"):
		if part.begins_with("."):
			return "hidden files are not allowed in a pack"
	if rel == "pack.json":
		return ""
	var parts := rel.split("/")
	if parts.size() == 2 and kinds().has(parts[0]) and rel.get_extension() == "json":
		return ""
	if parts[0] == "assets" and parts.size() >= 2 and ASSET_EXTENSIONS.has(rel.get_extension().to_lower()):
		return "" if rel.get_extension() == rel.get_extension().to_lower() else "extension must be lower case"
	return "not allowed in a pack (only pack.json, %s/*.json and assets/*.{%s})" % ["|".join(kinds()),
		",".join(ASSET_EXTENSIONS)]


static func _read_manifest(dir: String, folder_is_id: bool, errors: PackedStringArray) -> Dictionary:
	var path := dir.path_join("pack.json")
	var json := JSON.new()
	if not FileAccess.file_exists(path) or json.parse(FileAccess.get_file_as_string(path)) != OK \
			or typeof(json.data) != TYPE_DICTIONARY:
		errors.append("%s: missing or not a JSON object" % path)
		return {}
	var data: Dictionary = json.data
	var start := errors.size()
	for key in data:
		if not MANIFEST_FIELDS.has(key):
			errors.append("%s: unknown key \"%s\"" % [path, key])
	for field in MANIFEST_FIELDS:
		var type := String(MANIFEST_FIELDS[field])
		if not data.has(field):
			if not type.ends_with("?"):
				errors.append("%s: missing \"%s\"" % [path, field])
			continue
		if ContentRegistry._convert(data[field], type.trim_suffix("?")) == null:
			errors.append("%s: \"%s\" must be %s" % [path, field, type.trim_suffix("?")])
	if errors.size() > start:
		return {}
	if data["schema"] != SCHEMA:
		errors.append("%s: schema must be \"%s\"" % [path, SCHEMA])
	var id := String(data["id"])
	if not _is_pack_id(id):
		errors.append("%s: id must be 3-32 lower-case letters, digits or _, starting with a letter or digit" % path)
	elif folder_is_id and dir.get_file() != id:
		errors.append("%s: id \"%s\" must match the folder name \"%s\"" % [path, id, dir.get_file()])
	if not _is_version(String(data["version"])):
		errors.append("%s: version must be 1-32 of 0-9 A-Z a-z . + -, starting with a letter or digit" % path)
	for entry in data.get("overrides", []):
		var parts := String(entry).split("/")
		if parts.size() != 2 or not kinds().has(parts[0]) or not ContentRegistry._is_id(parts[1], parts[0] == "ambience"):
			errors.append("%s: override \"%s\" must be <kind>/<id> with kind one of %s" % [path, entry, kinds()])
	return data if errors.size() == start else {}


## Pack-specific rules on top of the schema: namespaced ids, declared overrides, pack-local assets, drawable tiers.
static func _finish_def(def: Dictionary, kind: String, manifest: Dictionary, dir: String, rel: String, assets: Dictionary,
		errors: PackedStringArray) -> Dictionary:
	var id := String(def["id"])
	var where := "%s/%s (%s)" % [dir, rel, id]
	var pack_id := String(manifest["id"])
	var overriding: bool = manifest.get("overrides", []).has("%s/%s" % [kind, id])
	if not overriding and OVERRIDE_ONLY_KINDS.has(kind):
		errors.append("%s: %s replace built-in ones; list \"%s/%s\" under overrides" % [where, kind, kind, id])
		return {}
	if not overriding and not id.begins_with(pack_id + "_"):
		errors.append("%s: a new id must start with \"%s_\" (or list \"%s/%s\" under overrides)" % [where, pack_id,
			kind, id])
		return {}
	var out := def.duplicate(true)
	match kind:
		"sounds", "ambience":
			var files := []
			for file in def["files"]:
				var absolute := _asset(String(file), "ogg", dir, assets, where, errors)
				if absolute.is_empty():
					return {}
				files.append(absolute)
			if files.is_empty():
				errors.append("%s: files is empty" % where)
				return {}
			out["files"] = files
		"floors", "walls", "ceilings":
			var image := _asset(String(def["image"]), "png", dir, assets, where, errors)
			if image.is_empty():
				return {}
			out["image"] = image
		"props":
			out["family"] = "%s:%s" % [pack_id, def["family"]]
			var models := []
			for model in def["models"]:
				var absolute := _asset(String(model), "glb", dir, assets, where, errors)
				if absolute.is_empty():
					return {}
				models.append(absolute)
			out["models"] = models
		"hunters":
			if not DRAW_TIERS.has(String(def["tier"])) and not overriding:
				errors.append("%s: tier must be one of %s" % [where, DRAW_TIERS])
				return {}
			if def.has("model"):
				var model := String(def["model"])
				if model.begins_with("res://"):
					var allowed := BUILTIN_MODEL_ROOTS.any(func(root: String): return model.begins_with(root))
					if not allowed or not (model.get_extension() in ["glb", "tscn"]) or not ResourceLoader.exists(model):
						errors.append("%s: model \"%s\" is not a built-in hunter model" % [where, model])
						return {}
				else:
					var absolute := _asset(model, "glb", dir, assets, where, errors)
					if absolute.is_empty():
						return {}
					out["model"] = absolute
			if def.has("portrait"):
				var portrait := String(def["portrait"])
				if portrait.begins_with("res://"):
					if not portrait.begins_with(BUILTIN_PORTRAIT_ROOT) or not ResourceLoader.exists(portrait):
						errors.append("%s: portrait \"%s\" is not a built-in hunter portrait" % [where, portrait])
						return {}
				else:
					var absolute := _asset(portrait, "png", dir, assets, where, errors)
					if absolute.is_empty():
						return {}
					out["portrait"] = absolute
	return out


static func _asset(rel: String, extension: String, dir: String, assets: Dictionary, where: String,
		errors: PackedStringArray) -> String:
	if not assets.has(rel) or rel.get_extension() != extension:
		errors.append("%s: \"%s\" is not a .%s under assets/ in this pack" % [where, rel, extension])
		return ""
	return dir.path_join(rel)


## A manifest "files" list ({path, sha256, size} per file, pack.json left out) must match the folder exactly.
static func _check_file_list(listed: Array, files: Array, dir: String, errors: PackedStringArray) -> void:
	var actual := {}
	for file in files:
		if file["path"] != "pack.json":
			actual[file["path"]] = file
	var seen := {}
	for entry in listed:
		var rel := String(entry.get("path", ""))
		seen[rel] = true
		if not actual.has(rel):
			errors.append("%s/pack.json: files lists %s, which is not in the pack" % [dir, rel])
		elif String(entry.get("sha256", "")) != actual[rel]["sha256"] or int(entry.get("size", -1)) != actual[rel]["bytes"]:
			errors.append("%s/%s: size or sha256 differs from pack.json files" % [dir, rel])
	for rel in actual:
		if not seen.has(rel):
			errors.append("%s/%s: not listed in pack.json files" % [dir, rel])


static func _check_asset(path: String, where: String, errors: PackedStringArray) -> void:
	match path.get_extension():
		"png":
			if Image.load_from_file(path) == null:
				errors.append("%s: not a readable PNG" % where)
		"ogg":
			if AudioStreamOggVorbis.load_from_file(path) == null:
				errors.append("%s: not a readable Ogg Vorbis file" % where)
		"glb":
			# the extension list is read from the file's own JSON chunk, before the importer sees it
			var json := _glb_json(path)
			if json.is_empty():
				errors.append("%s: not a readable glTF binary" % where)
				return
			for key in ["extensionsUsed", "extensionsRequired"]:
				for extension in json.get(key, []):
					if not GLTF_EXTENSIONS.has(String(extension)):
						errors.append("%s: glTF extension \"%s\" is not allowed in packs" % [where, extension])
						return
			if GLTFDocument.new().append_from_file(path, GLTFState.new()) != OK:
				errors.append("%s: not a readable glTF binary" % where)


## The JSON chunk of a .glb, or {} when the file is not one.
static func _glb_json(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 20 or bytes.decode_u32(0) != 0x46546C67 or bytes.decode_u32(16) != 0x4E4F534A:
		return {}
	var length := bytes.decode_u32(12)
	if 20 + length > bytes.size():
		return {}
	var json := JSON.new()
	if json.parse(bytes.slice(20, 20 + length).get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return json.data


static func _is_pack_id(value: String) -> bool:
	if value.length() < 3 or value.length() > 32 or value.begins_with("_"):
		return false
	for c in value:
		if not (c == "_" or (c >= "a" and c <= "z") or (c >= "0" and c <= "9")):
			return false
	return true


## Same rule as the TOOLS index: starts with a letter or digit, then letters, digits and . + -, at most 32.
static func _is_version(value: String) -> bool:
	if value.is_empty() or value.length() > 32 or value[0] in ".+-":
		return false
	for c in value:
		if not (c in ".+-" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")):
			return false
	return true


static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
