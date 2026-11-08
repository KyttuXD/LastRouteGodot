class_name SkinCatalog
extends RefCounted

## Player skins as data (docs/PLAYER_SKINS.md, "Skin catalog"; docs/modding/content-types.md, "Skins"). The `skins` kind
## is a ContentRegistry extension kind (res://data/kinds/player_skins.json): built-in entries under res://data/skins, and
## content packs ship a skins/ folder of the same shape with a PNG under assets/. Data and images only: an entry names a
## picture, and the picture goes through PlayerSkin.validate like every other source (64x64 or 64x32 PNG, at most 64 KB,
## base layer forced opaque, decoded and never executed). Picking one ends in the usual preview -> APPLY flow, so it becomes
## your own skin and is shared by hash exactly as a picked file would be; nothing about account or co-op sharing changes.

const KIND := "skins"
const SCHEMA := "lr.skin/1"
const BUILTIN_IMAGE_ROOT := "res://assets/skins/"
const ARMS := ["auto", "classic", "slim"]
const NAME_MAX := 32
## field -> required
const FIELDS := {"id": true, "name": true, "image": true, "arms": false, "author": false}


## ContentRegistry extension validator: `entry` is the file minus "schema"; `where` the JSON file's path. A pack-relative
## image ("assets/....png") is checked against the pack folder the file sits in, so a bad picture refuses the whole pack.
static func validate(_kind: String, entry: Dictionary, where: String) -> PackedStringArray:
	var errors := PackedStringArray()
	for key in entry:
		if not FIELDS.has(key):
			errors.append("%s: unknown field \"%s\"" % [where, key])
	for key in FIELDS:
		if FIELDS[key] and not entry.has(key):
			errors.append("%s: \"%s\" is required" % [where, key])
	if not errors.is_empty():
		return errors
	for key in ["name", "image", "arms", "author"]:
		if entry.has(key) and typeof(entry[key]) != TYPE_STRING:
			errors.append("%s: \"%s\" must be a string" % [where, key])
	if not errors.is_empty():
		return errors
	var display := String(entry["name"]).strip_edges()
	if display.is_empty() or display.length() > NAME_MAX:
		errors.append("%s: \"name\" must be 1-%d characters" % [where, NAME_MAX])
	if entry.has("author") and String(entry["author"]).length() > 64:
		errors.append("%s: \"author\" is longer than 64 characters" % where)
	if not ARMS.has(String(entry.get("arms", "auto"))):
		errors.append("%s: \"arms\" must be one of %s" % [where, ARMS])
	var image := String(entry["image"])
	var path := _image_path(image, where)
	if path.is_empty():
		errors.append("%s: \"image\" must be a .png under assets/ in the pack (or a shipped %s*.png)" % [where, BUILTIN_IMAGE_ROOT])
		return errors
	var result := PlayerSkin.validate(image_bytes(path))
	if not bool(result["ok"]):
		errors.append("%s: image \"%s\" is not a skin: %s" % [where, image, result["reason"]])
	return errors


## Where an entry's image lives, or "" when the value is not allowed. Pack paths are only read after this check: lower-case
## .png under assets/, no "..", backslashes, colons or hidden parts (ContentPacks checks the file is listed in the pack too).
static func _image_path(image: String, where: String) -> String:
	if image.begins_with("res://"):
		var rest := image.trim_prefix("res://")
		if image.begins_with(BUILTIN_IMAGE_ROOT) and image.get_extension() == "png" and not rest.contains("..") \
				and not rest.contains(":") and not rest.contains("\\") and ResourceLoader.exists(image):
			return image
		return ""
	if not image.begins_with("assets/") or image.get_extension() != "png" or image.contains("..") or image.contains("\\") \
			or image.contains(":") or image.contains("/."):
		return ""
	if where.begins_with("res://"):
		return ""   # built-in entries use shipped res:// images
	return where.get_base_dir().get_base_dir().path_join(image)


## The PNG bytes of a skin image: a shipped (imported) res:// texture re-encoded, else the file itself (read capped at
## PlayerSkin.MAX_BYTES + 1, so an oversized file is refused without being loaded whole).
static func image_bytes(path: String) -> PackedByteArray:
	if path.begins_with("res://"):
		var texture := load(path) as Texture2D
		if texture == null:
			return PackedByteArray()
		var image := texture.get_image()
		if image == null:
			return PackedByteArray()
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		return image.save_png_to_buffer()
	return PlayerSkin.read_file(path)


## Every catalog skin, built-in first then pack skins, each sorted by id: [{id, name, arms, author, pack}]. `pack` is the
## pack id, "" for built-in ones (an overridden built-in id reports the overriding pack).
static func entries() -> Array:
	var builtin := []
	var packs := []
	for id in ContentRegistry.ids(KIND):
		var def := ContentRegistry.get_def(KIND, id)
		var pack := ContentRegistry.pack_of(KIND, id)
		var row := {"id": String(id), "name": String(def.get("name", id)), "arms": String(def.get("arms", "auto")),
			"author": String(def.get("author", "")), "pack": pack}
		(builtin if pack.is_empty() else packs).append(row)
	var by_id := func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"])
	builtin.sort_custom(by_id)
	packs.sort_custom(by_id)
	return builtin + packs


## A catalog skin as a PlayerSkin.validate result (what SkinPanel previews and APPLY stores). `arms` other than auto pins
## the style the skin is worn with; auto keeps what the pixels say.
static func load_skin(id: String) -> Dictionary:
	if not ContentRegistry.has(KIND, id):
		return PlayerSkin._refuse("there is no catalog skin \"%s\"" % id)
	var def := ContentRegistry.get_def(KIND, id)
	var path := String(def.get("image", ""))
	if not path.begins_with("res://") and not ContentRegistry.loaded_packs().any(
			func(pack: Dictionary) -> bool: return path.begins_with(String(pack.get("dir", "")) + "/")):
		return PlayerSkin._refuse("that skin's pack is not loaded")
	var result := PlayerSkin.validate(image_bytes(path))
	if bool(result["ok"]):
		match String(def.get("arms", "auto")):
			"classic":
				result["slim"] = false
			"slim":
				result["slim"] = true
	return result
