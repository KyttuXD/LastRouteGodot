class_name PlayerSkin
extends RefCounted

## Custom player skins (docs/PLAYER_SKINS.md). A skin is a standard Minecraft-layout 64x64 PNG mapped onto the player mannequin's
## cube UVs (assets/hunters_blocky/player_mannequin): the base layer, plus an optional overlay layer (hat, jacket, sleeves, pants)
## where alpha is allowed. Everything here is data handling: bytes are validated and decoded with Image.load_png_from_buffer and
## nothing in them is ever executed. The same rules run on the backend (backend/skins.mjs) so a client cannot upload what the
## game would refuse.
##
##   var result := PlayerSkin.validate(bytes)          # {"ok", "reason", "image", "png", "hash"}
##   PlayerSkin.import_bytes(bytes)                    # validate, keep as your own, make it the active skin
##   PlayerSkin.apply(model, PlayerSkin.texture_for(hash))

const SIZE := 64
## Upper bound on an uploaded file (a plain 64x64 PNG is a few KB; this leaves room for noisy art).
const MAX_BYTES := 65536
const PNG_MAGIC := [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
const DEFAULT_ATLAS := "res://assets/hunters_blocky/player_mannequin/player_mannequin_atlas.png"
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


# ------------------------------------------------------------------------------------------------ own skin + peer cache

## Only YOUR chosen skin is written to disk (this one file, needed to wear it and to upload it). Other players' skins, downloaded
## in co-op, live in memory for the session: `_peer` is never saved and is emptied when you leave the room, the run ends, or the
## game quits.
const OWN_PATH := "user://skin.png"
const PEER_CACHE_MAX := 16

static var _peer := {}   # hash -> ImageTexture (memory only)


## Stores a validated skin as your own (replacing the previous one). Returns the hash or "".
static func store(result: Dictionary) -> String:
	if not bool(result.get("ok", false)):
		return ""
	var file := FileAccess.open(OWN_PATH, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(result["png"])
	file.close()
	_textures.erase("own")
	return String(result["hash"])


## Your own skin, re-validated from disk (a damaged or swapped file is refused). Null when none or invalid.
static func load_own() -> Image:
	if Settings.skin_hash.is_empty() or not FileAccess.file_exists(OWN_PATH):
		return null
	var result := validate(read_file(OWN_PATH))
	if not bool(result["ok"]) or String(result["hash"]) != Settings.skin_hash:
		return null
	return result["image"]


static func own_png() -> PackedByteArray:
	var result := validate(read_file(OWN_PATH))
	return result["png"] if bool(result["ok"]) and String(result["hash"]) == Settings.skin_hash else PackedByteArray()


## The texture for a skin hash: "" and anything unknown are the default skin; your own hash is your file; a peer's is the memory cache.
static func texture_for(hash: String) -> Texture2D:
	if hash.is_empty():
		return default_texture()
	if hash == Settings.skin_hash:
		if not _textures.has("own"):
			var image := load_own()
			if image == null:
				return default_texture()
			_textures["own"] = _nearest(image)
		return _textures["own"]
	var peer := peer_texture(hash)
	return peer if peer != null else default_texture()


static func peer_texture(hash: String) -> Texture2D:
	return _peer.get(hash)


## A downloaded peer skin (already validated, hash already checked by the caller) into the memory cache. Never written to disk.
static func accept_peer(hash: String, image: Image) -> void:
	if not valid_hash(hash) or image == null:
		return
	if not _peer.has(hash) and _peer.size() >= PEER_CACHE_MAX:
		_peer.erase(_peer.keys()[0])
	_peer[hash] = _nearest(image)


## A peer left: free their skin unless another connected peer still wears it.
static func release_peer(hash: String, still_worn: Array) -> void:
	if not still_worn.has(hash):
		_peer.erase(hash)


## Older builds cached downloads on disk; nothing is kept there any more.
static func purge_legacy_cache() -> void:
	var dir := DirAccess.open("user://skins")
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute("user://skins")


static func peer_cache_size() -> int:
	return _peer.size()


static func clear_peer_cache() -> void:
	_peer.clear()


## Validate + store as your own + make it active. Returns the validation result.
static func import_bytes(bytes: PackedByteArray) -> Dictionary:
	var result := validate(bytes)
	if not bool(result["ok"]):
		return result
	if store(result).is_empty():
		return _refuse("the skin could not be saved")
	Settings.set_skin_hash(String(result["hash"]))
	return result


static func reset_active() -> void:
	if FileAccess.file_exists(OWN_PATH):
		DirAccess.remove_absolute(OWN_PATH)
	_textures.erase("own")
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
