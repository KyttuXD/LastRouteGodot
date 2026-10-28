class_name PlayerSkin
extends RefCounted

## Custom player skins (docs/PLAYER_SKINS.md). A skin is a standard Minecraft-layout 64x64 PNG mapped onto the player mannequin's
## cube UVs (assets/hunters_blocky/player_mannequin): the base layer, plus an optional overlay layer (hat, jacket, sleeves, pants)
## where alpha is allowed. Everything here is data handling: bytes are validated and decoded with Image.load_png_from_buffer and
## nothing in them is ever executed. The same rules run on the backend (backend/skins.mjs) so a client cannot upload what the
## game would refuse.
##
##   var result := PlayerSkin.validate(bytes)          # {"ok", "reason", "image", "png", "hash"}
##   PlayerSkin.import_bytes(bytes)                    # validate, cache by hash, make it the active skin
##   PlayerSkin.apply(model, PlayerSkin.texture_for(hash))

const SIZE := 64
## Upper bound on an uploaded file (a plain 64x64 PNG is a few KB; this leaves room for noisy art).
const MAX_BYTES := 65536
const PNG_MAGIC := [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
const DEFAULT_ATLAS := "res://assets/hunters_blocky/player_mannequin/player_mannequin_atlas.png"
const CACHE_DIR := "user://skins"
## Where alpha is allowed: the second skin layer (head/hat, body/jacket, arm and leg sleeves/pants). Everywhere else the base is forced
## opaque, so nobody can go invisible.
const OVERLAY_RECTS := [
	Rect2i(32, 0, 32, 16),   # hat
	Rect2i(16, 32, 24, 16),  # jacket
	Rect2i(40, 32, 16, 16),  # right sleeve
	Rect2i(0, 32, 16, 16),   # right pants
	Rect2i(48, 48, 16, 16),  # left sleeve
	Rect2i(0, 48, 16, 16),   # left pants
]

static var _default_image: Image
static var _textures := {}


static func is_overlay_pixel(x: int, y: int) -> bool:
	for rect in OVERLAY_RECTS:
		if (rect as Rect2i).has_point(Vector2i(x, y)):
			return true
	return false


## Validates and normalises an uploaded file. Never trusts the bytes: size cap, PNG signature, a real decode, exact dimensions,
## base layer forced opaque. `png` is the canonical re-encoding the hash and the cache are keyed on.
static func validate(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty():
		return _refuse("the file is empty")
	if bytes.size() > MAX_BYTES:
		return _refuse("the file is %d KB; the limit is %d KB" % [ceili(bytes.size() / 1024.0), MAX_BYTES / 1024])
	if bytes.size() < PNG_MAGIC.size():
		return _refuse("not a PNG")
	for i in PNG_MAGIC.size():
		if bytes[i] != PNG_MAGIC[i]:
			return _refuse("not a PNG")
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return _refuse("the PNG could not be read")
	if image.get_width() != SIZE or image.get_height() != SIZE:
		return _refuse("the image is %dx%d; a skin is exactly %dx%d" % [image.get_width(), image.get_height(), SIZE, SIZE])
	if image.is_compressed():
		return _refuse("the PNG could not be read")
	image.convert(Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			if is_overlay_pixel(x, y):
				continue
			var pixel := image.get_pixel(x, y)
			if pixel.a < 1.0:
				pixel.a = 1.0
				image.set_pixel(x, y, pixel)
	var png := image.save_png_to_buffer()
	return {"ok": true, "reason": "", "image": image, "png": png, "hash": hash_of(png)}


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "image": null, "png": PackedByteArray(), "hash": ""}


static func hash_of(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func valid_hash(hash: String) -> bool:
	if hash.length() != 64:
		return false
	for i in hash.length():
		if not "0123456789abcdef".contains(hash[i]):
			return false
	return true


## Reads at most MAX_BYTES + 1 bytes of a file (a huge file is refused by validate() without being loaded whole).
static func read_file(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	return file.get_buffer(mini(int(file.get_length()), MAX_BYTES + 1))


# ------------------------------------------------------------------------------------------------ default + template

## The default mannequin skin (the shipped atlas), decoded as an uncompressed RGBA8 image.
static func default_image() -> Image:
	if _default_image != null:
		return _default_image
	var texture := load(DEFAULT_ATLAS) as Texture2D
	if texture != null:
		var image := texture.get_image()
		if image != null:
			if image.is_compressed():
				image.decompress()
			image.convert(Image.FORMAT_RGBA8)
			_default_image = image
	if _default_image == null:
		_default_image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		_default_image.fill(Color(.62, .5, .32, 1.0))
	return _default_image


static func default_texture() -> Texture2D:
	if not _textures.has("default"):
		_textures["default"] = _nearest(default_image())
	return _textures["default"]


## The template a player paints over: the default skin with a clear overlay layer, as a canonical PNG.
static func template_png() -> PackedByteArray:
	var image := default_image().duplicate() as Image
	for y in SIZE:
		for x in SIZE:
			if is_overlay_pixel(x, y):
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	return image.save_png_to_buffer()


static func _nearest(image: Image) -> ImageTexture:
	return ImageTexture.create_from_image(image)


# ------------------------------------------------------------------------------------------------ cache + active skin

static func cache_path(hash: String) -> String:
	return "%s/%s.png" % [CACHE_DIR, hash]


static func is_cached(hash: String) -> bool:
	return valid_hash(hash) and FileAccess.file_exists(cache_path(hash))


## Stores validated canonical bytes under their hash (idempotent). Returns the hash or "".
static func store(result: Dictionary) -> String:
	if not bool(result.get("ok", false)):
		return ""
	var hash := String(result["hash"])
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	if load_cached(hash) == null:   # absent, or a damaged / tampered file: (re)write it from the validated bytes
		var file := FileAccess.open(cache_path(hash), FileAccess.WRITE)
		if file == null:
			return ""
		file.store_buffer(result["png"])
		file.close()
	return hash


## Loads a cached skin by hash, re-validating it (a tampered cache file is refused). Null when absent or invalid.
static func load_cached(hash: String) -> Image:
	if not is_cached(hash):
		return null
	var file := FileAccess.open(cache_path(hash), FileAccess.READ)
	if file == null:
		return null
	var result := validate(file.get_buffer(file.get_length()))
	if not bool(result["ok"]) or String(result["hash"]) != hash:
		return null
	return result["image"]


## The texture for a skin hash ("" = the default skin; a missing or invalid cache entry falls back to the default).
static func texture_for(hash: String) -> Texture2D:
	if hash.is_empty():
		return default_texture()
	if _textures.has(hash):
		return _textures[hash]
	var image := load_cached(hash)
	if image == null:
		return default_texture()
	_textures[hash] = _nearest(image)
	return _textures[hash]


## Validate + cache + make active. Returns the validation result (with "hash" set when it took).
static func import_bytes(bytes: PackedByteArray) -> Dictionary:
	var result := validate(bytes)
	if bool(result["ok"]) and store(result).is_empty():
		return _refuse("the skin could not be saved")
	if bool(result["ok"]):
		Settings.set_skin_hash(String(result["hash"]))
	return result


static func reset_active() -> void:
	Settings.set_skin_hash("")


static func active_texture() -> Texture2D:
	return texture_for(Settings.skin_hash)


# ------------------------------------------------------------------------------------------------ applying to a model

## Puts `texture` on every textured surface under `root` (the mannequin body, or the first-person hand parts). Surfaces are
## duplicated per model (shared materials are untouched), nearest-filtered, tint cleared, so the skin shows as painted.
static func apply(root: Node, texture: Texture2D) -> void:
	if root == null or texture == null:
		return
	if root is MeshInstance3D:
		var mesh_node := root as MeshInstance3D
		if mesh_node.mesh != null:
			for surface in mesh_node.mesh.get_surface_count():
				var source := mesh_node.get_active_material(surface)
				if source is StandardMaterial3D and (source as StandardMaterial3D).albedo_texture != null:
					var material := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
					material.albedo_texture = texture
					material.albedo_color = Color(1, 1, 1, material.albedo_color.a)
					material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					mesh_node.set_surface_override_material(surface, material)
	for child in root.get_children():
		apply(child, texture)
