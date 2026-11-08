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
	var legacy := image.get_width() == SIZE and image.get_height() == SIZE / 2
	if image.get_width() != SIZE or (image.get_height() != SIZE and not legacy):
		return _refuse("the image is %dx%d; a skin is %dx%d (or the old %dx%d)" % [image.get_width(), image.get_height(), SIZE, SIZE, SIZE, SIZE / 2])
	if image.is_compressed():
		return _refuse("the PNG could not be read")
	image.convert(Image.FORMAT_RGBA8)
	if legacy:
		image = upgrade_legacy(image)
	var slim := not legacy and is_slim_layout(image)   # read BEFORE the base layer is forced opaque
	for y in SIZE:
		for x in SIZE:
			if is_overlay_pixel(x, y):
				continue
			var pixel := image.get_pixel(x, y)
			if pixel.a < 1.0:
				pixel.a = 1.0
				image.set_pixel(x, y, pixel)
	var png := image.save_png_to_buffer()
	return {"ok": true, "reason": "", "image": image, "png": png, "hash": hash_of(png), "slim": slim}


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "image": null, "png": PackedByteArray(), "hash": "", "slim": false}


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


# ------------------------------------------------------------------------------------------------ URLs, Minecraft skins, copying

const MC_HOSTS := ["api.mojang.com", "sessionserver.mojang.com", "textures.minecraft.net"]
const MAX_URL_LENGTH := 512


## "" when the URL may be fetched, else why not. https only, a real public host, no credentials, no loopback / LAN / IP literals.
static func check_url(url: String, allowed_hosts: Array = []) -> String:
	var text := url.strip_edges()
	if text.is_empty() or text.length() > MAX_URL_LENGTH:
		return "that is not a usable address"
	if not text.to_lower().begins_with("https://"):
		return "only https:// addresses are allowed"
	var rest := text.substr(8)
	var host_end := rest.length()
	for stop in ["/", "?", "#"]:
		var at := rest.find(stop)
		if at >= 0:
			host_end = mini(host_end, at)
	var authority := rest.substr(0, host_end)
	if authority.contains("@"):
		return "addresses with a login are not allowed"
	var host := authority.to_lower()
	if host.contains(":"):
		if host.begins_with("["):
			return "numeric addresses are not allowed"
		var parts := host.split(":")
		if parts.size() != 2 or parts[1] != "443":
			return "only the standard https port is allowed"
		host = parts[0]
	if host.is_empty() or not host.contains(".") or host.ends_with(".") or host.begins_with("."):
		return "that is not a usable address"
	for i in host.length():
		if not "abcdefghijklmnopqrstuvwxyz0123456789-.".contains(host[i]):
			return "that is not a usable address"
	if host == "localhost" or host.ends_with(".localhost") or host.ends_with(".local") or host.ends_with(".internal") or host.ends_with(".lan"):
		return "local addresses are not allowed"
	var numeric := true
	for part in host.split("."):
		numeric = numeric and part.is_valid_int()
	if numeric:
		return "numeric addresses are not allowed"
	if not allowed_hosts.is_empty() and not allowed_hosts.has(host):
		return "that host is not allowed here"
	return ""


## The skin URL and arm model out of a Mojang profile (the decoded "textures" JSON). {} when it has none or it points anywhere
## but textures.minecraft.net.
static func parse_textures(profile: Dictionary) -> Dictionary:
	for property in profile.get("properties", []):
		if not property is Dictionary or String(property.get("name", "")) != "textures":
			continue
		var decoded: Variant = JSON.parse_string(Marshalls.base64_to_raw(String(property.get("value", ""))).get_string_from_utf8())
		if not decoded is Dictionary:
			return {}
		var skin: Variant = (decoded.get("textures", {}) as Dictionary).get("SKIN", null)
		if not skin is Dictionary:
			return {}
		var url := String(skin.get("url", ""))
		if not check_url(url, ["textures.minecraft.net"]).is_empty():
			return {}
		var metadata: Variant = skin.get("metadata", {})
		var slim: bool = metadata is Dictionary and String(metadata.get("model", "")) == "slim"
		return {"url": url, "slim": slim}
	return {}


static func valid_minecraft_name(name: String) -> bool:
	if name.is_empty() or name.length() > 16:
		return false
	for i in name.length():
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_".contains(name[i]):
			return false
	return true


## A Minecraft skin: the template IS the Minecraft 64x64 layout, so nothing is converted except the old 64x32 format (validate upgrades
## it). `slim` is the Mojang profile's model field (Alex); it wins over the pixel detection. Returns the validation result with
## "slim" set -- the mannequin then wears its slim (3 px arm) variant, so nothing is stretched or lost.
static func from_minecraft(source: Image, slim: bool = false) -> Dictionary:
	if source == null or source.get_width() != SIZE or (source.get_height() != SIZE and source.get_height() != SIZE / 2):
		return _refuse("a Minecraft skin is 64x64 (or the old 64x32)")
	var result := validate(source.save_png_to_buffer())
	if bool(result["ok"]):
		result["slim"] = slim or bool(result["slim"])
		if source.get_height() == SIZE / 2:
			result["slim"] = false   # the old format has only classic arms
	return result


## An old 64x32 skin as 64x64: the left arm and leg regions mirror the right ones (the second layer stays empty).
static func upgrade_legacy(source: Image) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.blit_rect(source, Rect2i(0, 0, SIZE, SIZE / 2), Vector2i.ZERO)
	_mirror_box(image, Vector2i(0, 16), Vector2i(16, 48))    # left leg from the right
	_mirror_box(image, Vector2i(40, 16), Vector2i(32, 48))   # left arm from the right
	return image


## Alex (slim) skins leave the arms' 4th texture column transparent in the base layer; classic skins paint it.
static func is_slim_layout(image: Image) -> bool:
	for rect in [Rect2i(50, 16, 2, 4), Rect2i(54, 20, 2, 12), Rect2i(42, 48, 2, 4), Rect2i(46, 52, 2, 12)]:
		for y in (rect as Rect2i).size.y:
			for x in (rect as Rect2i).size.x:
				if image.get_pixel(rect.position.x + x, rect.position.y + y).a > 0.0:
					return false
	return true


## Copies a limb box (4 wide, 4 deep, 12 tall) mirrored left-right: top, bottom, front and back flip; the two side faces swap.
static func _mirror_box(image: Image, from: Vector2i, to: Vector2i) -> void:
	var source := image.duplicate() as Image
	var pairs := [  # [source rect, destination rect, flip]
		[Rect2i(from.x + 4, from.y, 4, 4), Rect2i(to.x + 4, to.y, 4, 4)],
		[Rect2i(from.x + 8, from.y, 4, 4), Rect2i(to.x + 8, to.y, 4, 4)],
		[Rect2i(from.x, from.y + 4, 4, 12), Rect2i(to.x + 8, to.y + 4, 4, 12)],
		[Rect2i(from.x + 4, from.y + 4, 4, 12), Rect2i(to.x + 4, to.y + 4, 4, 12)],
		[Rect2i(from.x + 8, from.y + 4, 4, 12), Rect2i(to.x, to.y + 4, 4, 12)],
		[Rect2i(from.x + 12, from.y + 4, 4, 12), Rect2i(to.x + 12, to.y + 4, 4, 12)],
	]
	for pair in pairs:
		var src: Rect2i = pair[0]
		var dst: Rect2i = pair[1]
		for y in src.size.y:
			for x in src.size.x:
				image.set_pixel(dst.position.x + (src.size.x - 1 - x), dst.position.y + y, source.get_pixel(src.position.x + x, src.position.y + y))


## Copies a peer's skin (from the memory cache) as your own: same validation, stored as your file, active. Returns the result.
static func copy_peer(hash: String, slim: bool = false) -> Dictionary:
	var texture := peer_texture(hash)
	if texture == null:
		return _refuse("that skin is not loaded")
	var image := texture.get_image()
	if image == null:
		return _refuse("that skin is not loaded")
	var png := image.save_png_to_buffer()
	var result := validate(png)
	if not bool(result["ok"]):
		return result
	result["slim"] = slim
	return apply_result(result)


# ------------------------------------------------------------------------------------------------ the roster of co-op skins (memory only)

static var _roster := {}   # peer id -> {"name", "hash", "copyable"}


static func note_peer(id: int, display_name: String, hash: String, copyable: bool, slim: bool = false) -> void:
	_roster[id] = {"name": display_name, "hash": hash, "copyable": copyable, "slim": slim}


static func forget_peer(id: int) -> void:
	_roster.erase(id)


## Peers wearing a skin you can copy right now (their skin is downloaded and they allow it).
static func copyable_peers() -> Array:
	var found: Array = []
	for id in _roster:
		var entry: Dictionary = _roster[id]
		if bool(entry["copyable"]) and not String(entry["hash"]).is_empty() and peer_texture(String(entry["hash"])) != null:
			found.append({"id": id, "name": String(entry["name"]), "hash": String(entry["hash"]), "slim": bool(entry.get("slim", false))})
	return found


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
## Where the own skin lives. Always OWN_PATH in the game; the headless validators point it at a scratch file (tests/user_guard.gd) so a suite cannot overwrite a real skin.
static var own_path := OWN_PATH
const PEER_CACHE_MAX := 16

static var _peer := {}   # hash -> ImageTexture (memory only)


## Stores a validated skin as your own (replacing the previous one). Returns the hash or "".
static func store(result: Dictionary) -> String:
	if not bool(result.get("ok", false)):
		return ""
	var file := FileAccess.open(own_path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(result["png"])
	file.close()
	_textures.erase("own")
	return String(result["hash"])


## Your own skin, re-validated from disk (a damaged or swapped file is refused). Null when none or invalid.
static func load_own() -> Image:
	if Settings.skin_hash.is_empty() or not FileAccess.file_exists(own_path):
		return null
	var result := validate(read_file(own_path))
	if not bool(result["ok"]) or String(result["hash"]) != Settings.skin_hash:
		return null
	return result["image"]


static func own_png() -> PackedByteArray:
	var result := validate(read_file(own_path))
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
	_roster.clear()


## Validate + store as your own + make it active. Returns the validation result.
static func import_bytes(bytes: PackedByteArray) -> Dictionary:
	var result := validate(bytes)
	if not bool(result["ok"]):
		return result
	return apply_result(result)


## Makes an already validated skin (a result of validate / from_minecraft) your own: kept as your file, active, arm style recorded.
static func apply_result(result: Dictionary) -> Dictionary:
	if store(result).is_empty():
		return _refuse("the skin could not be saved")
	Settings.skin_slim = bool(result.get("slim", false))
	Settings.set_skin_hash(String(result["hash"]))
	return result


static func reset_active() -> void:
	if FileAccess.file_exists(own_path):
		DirAccess.remove_absolute(own_path)
	_textures.erase("own")
	Settings.skin_slim = false
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


# ------------------------------------------------------------------------------------------------ arm style (Steve / Alex)

const ARM_BONES := ["R-Arm", "R-Forearm", "R-Hand", "L-Arm", "L-Forearm", "L-Hand"]
static var _arm_meshes := {}   # "classic" / "slim" -> {bone -> Mesh}


static func _arm_set(slim: bool) -> Dictionary:
	var key := "slim" if slim else "classic"
	if _arm_meshes.has(key):
		return _arm_meshes[key]
	var found := {}
	var scene := load((PlayerModels.BLOCKY_SLIM if slim else PlayerModels.BLOCKY).replace(".tscn", ".glb")) as PackedScene
	if scene != null:
		var root := scene.instantiate()
		for bone in ARM_BONES:
			var mesh_node := root.find_child(bone, true, false) as MeshInstance3D
			if mesh_node != null and mesh_node.mesh != null:
				found[bone] = mesh_node.mesh
		root.free()
	_arm_meshes[key] = found
	return found


## Puts the Steve (classic, 4 px) or Alex (slim, 3 px) arms on a mannequin: the six arm meshes are swapped in place (same bones and
## pivots, so every clip, the ladder, the swing and the hand poses keep working). Call PlayerSkin.apply afterwards to re-skin them.
static func set_arms(root: Node, slim: bool) -> bool:
	var meshes := _arm_set(slim)
	if meshes.size() != ARM_BONES.size() or root == null:
		return false
	for bone in ARM_BONES:
		var mesh_node := root.find_child(bone, true, false) as MeshInstance3D
		if mesh_node == null:
			return false
		if mesh_node.mesh != meshes[bone]:
			mesh_node.mesh = meshes[bone]
			for surface in mesh_node.mesh.get_surface_count():
				mesh_node.set_surface_override_material(surface, null)
	return true
