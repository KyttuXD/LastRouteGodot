class_name SkinSync
extends Node

## Sharing player skins through the backend (docs/PLAYER_SKINS.md). Signed-in players upload their own skin once (the server keeps
## one per account, addressed by sha256); the room state carries only the hash, and every peer downloads each hash once into
## PlayerSkin's MEMORY cache. Nothing downloaded is written to disk. Guests and offline players wear their skin locally only: it is
## never uploaded and never published to the room.
##
## Child of the Backend autoload (Backend.skin_sync).

signal fetched(hash: String)

const RETRY_SECONDS := 60.0
const FETCH_LIMIT_BYTES := PlayerSkin.MAX_BYTES + 1

## The hash the server is known to hold for this account (set after a successful upload or a matching /mine).
var uploaded_hash := ""
var _upload_request: HTTPRequest
var _uploading := ""
var _next_upload_try := 0.0
var _fetch_queue: Array = []
var _fetching := ""
var _fetch_request: HTTPRequest
var _failed := {}   # hash -> earliest retry (msec)


func _ready() -> void:
	name = "SkinSync"
	PlayerSkin.purge_legacy_cache()
	_upload_request = HTTPRequest.new()
	_upload_request.name = "SkinUploadRequest"
	_upload_request.request_completed.connect(_on_upload_done)
	add_child(_upload_request)
	_fetch_request = HTTPRequest.new()
	_fetch_request.name = "SkinFetchRequest"
	_fetch_request.body_size_limit = FETCH_LIMIT_BYTES
	_fetch_request.request_completed.connect(_on_fetch_done)
	add_child(_fetch_request)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		PlayerSkin.clear_peer_cache()


func _exit_tree() -> void:
	PlayerSkin.clear_peer_cache()


## The hash to publish in the room state: your skin when the server holds it, else "" (peers see the default).
func shared_hash() -> String:
	if Settings.skin_hash.is_empty() or uploaded_hash != Settings.skin_hash:
		return ""
	return Settings.skin_hash


## Starts (at most one) upload of your own skin when signed in and the server does not hold it yet. Cheap to call often.
func sync_own() -> void:
	var hash := Settings.skin_hash
	if hash.is_empty() or hash == uploaded_hash or not _uploading.is_empty():
		return
	if not Backend.signed_in() or Backend.offline_mode:
		return
	var now := Time.get_ticks_msec() * .001
	if now < _next_upload_try:
		return
	var png := PlayerSkin.own_png()
	if png.is_empty():
		return
	_next_upload_try = now + RETRY_SECONDS
	_uploading = hash
	var headers := PackedStringArray(["content-type: application/octet-stream", "x-session-token: %s" % Backend.account_session_token])
	if _upload_request.request_raw(Backend.base_url.trim_suffix("/") + "/api/skins/upload", headers, HTTPClient.METHOD_POST, png) != OK:
		_uploading = ""


func _on_upload_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var hash := _uploading
	_uploading = ""
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary and String(parsed.get("hash", "")) == hash:
		uploaded_hash = hash
		_next_upload_try = 0.0


## Your skin was reset: tell the server to drop it (signed in), forget the upload.
func clear_own() -> void:
	uploaded_hash = ""
	if Backend.signed_in() and not Backend.offline_mode:
		var headers := PackedStringArray(["content-type: application/json"])
		var request := HTTPRequest.new()
		add_child(request)
		request.request_completed.connect(func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray) -> void: request.queue_free())
		request.request(Backend.base_url.trim_suffix("/") + "/api/skins/clear", headers, HTTPClient.METHOD_POST,
			JSON.stringify({"sessionToken": Backend.account_session_token}))


## Downloads a peer's skin into the memory cache (once per hash; failures retry after RETRY_SECONDS). Emits `fetched`.
func fetch(hash: String) -> void:
	if not PlayerSkin.valid_hash(hash) or PlayerSkin.peer_texture(hash) != null or _fetch_queue.has(hash) or _fetching == hash:
		return
	if hash == Settings.skin_hash:
		return
	if float(_failed.get(hash, 0.0)) > Time.get_ticks_msec():
		return
	_fetch_queue.append(hash)
	_next_fetch()


func _next_fetch() -> void:
	if not _fetching.is_empty() or _fetch_queue.is_empty():
		return
	_fetching = _fetch_queue.pop_front()
	var url := "%s/api/skins/files/%s.png" % [Backend.base_url.trim_suffix("/"), _fetching]
	if _fetch_request.request(url) != OK:
		_failed[_fetching] = Time.get_ticks_msec() + int(RETRY_SECONDS * 1000.0)
		_fetching = ""


func _on_fetch_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var hash := _fetching
	_fetching = ""
	accept_download(hash, result == HTTPRequest.RESULT_SUCCESS and code == 200, body)
	_next_fetch()


## Handles a downloaded body: the bytes must hash to the requested hash AND validate as a skin, else they are dropped.
func accept_download(hash: String, ok: bool, body: PackedByteArray) -> bool:
	if ok and PlayerSkin.hash_of(body) == hash:
		var validated := PlayerSkin.validate(body)
		if bool(validated["ok"]):
			PlayerSkin.accept_peer(hash, validated["image"])
			fetched.emit(hash)
			return true
	_failed[hash] = Time.get_ticks_msec() + int(RETRY_SECONDS * 1000.0)
	return false


func clear_cache() -> void:
	PlayerSkin.clear_peer_cache()
	_fetch_queue.clear()
	_failed.clear()


# --------------------------------------------------------------------------------------- other sources: a URL, a Minecraft name

const URL_TIMEOUT_SECONDS := 5.0
const MAX_REDIRECTS := 3

## Downloads `url` (https only, no redirect to anything else, 5 s, at most `limit` bytes). Returns {"ok", "body", "reason"}.
## Nothing downloaded is ever executed: callers decode it as an image or as JSON data.
func download_https(url: String, limit: int = PlayerSkin.MAX_BYTES + 1, allowed_hosts: Array = []) -> Dictionary:
	var current := url.strip_edges()
	for hop in MAX_REDIRECTS + 1:
		var refusal := PlayerSkin.check_url(current, allowed_hosts)
		if not refusal.is_empty():
			return {"ok": false, "body": PackedByteArray(), "reason": refusal}
		var request := HTTPRequest.new()
		request.max_redirects = 0
		request.timeout = URL_TIMEOUT_SECONDS
		request.body_size_limit = limit
		add_child(request)
		if request.request(current, PackedStringArray(["accept: */*"])) != OK:
			request.queue_free()
			return {"ok": false, "body": PackedByteArray(), "reason": "the request could not be started"}
		var done: Array = await request.request_completed
		request.queue_free()
		var result := int(done[0])
		var code := int(done[1])
		if result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return {"ok": false, "body": PackedByteArray(), "reason": "the file is too big"}
		if result == HTTPRequest.RESULT_TIMEOUT:
			return {"ok": false, "body": PackedByteArray(), "reason": "the server took too long (over %d s)" % int(URL_TIMEOUT_SECONDS)}
		if result != HTTPRequest.RESULT_SUCCESS:
			return {"ok": false, "body": PackedByteArray(), "reason": "the download failed"}
		if code in [301, 302, 303, 307, 308]:
			var location := ""
			for header in done[2]:
				if String(header).to_lower().begins_with("location:"):
					location = String(header).substr(9).strip_edges()
			if location.begins_with("/"):
				var origin := current.substr(0, current.find("/", 8)) if current.find("/", 8) >= 0 else current
				location = origin + location
			current = location   # re-checked at the top: a redirect to http or a local address is refused
			continue
		if code != 200:
			return {"ok": false, "body": PackedByteArray(), "reason": "the server answered %d" % code}
		return {"ok": true, "body": done[3], "reason": ""}
	return {"ok": false, "body": PackedByteArray(), "reason": "too many redirects"}


## A skin from an https URL: the same validation as a picked file. Returns PlayerSkin.validate's result (or a refusal).
func skin_from_url(url: String) -> Dictionary:
	var got: Dictionary = await download_https(url)
	if not bool(got["ok"]):
		return {"ok": false, "reason": String(got["reason"]), "image": null, "png": PackedByteArray(), "hash": ""}
	return PlayerSkin.validate(got["body"])


## A skin by Minecraft username through Mojang's official APIs (name -> uuid -> profile textures -> textures.minecraft.net),
## converted to the template (PlayerSkin.from_minecraft).
func skin_from_minecraft(name: String) -> Dictionary:
	var bad := {"ok": false, "image": null, "png": PackedByteArray(), "hash": ""}
	name = name.strip_edges()
	if not PlayerSkin.valid_minecraft_name(name):
		return bad.merged({"reason": "a Minecraft name is 1-16 letters, numbers or underscores"})
	var lookup: Dictionary = await download_https("https://api.mojang.com/users/profiles/minecraft/%s" % name, 4096, ["api.mojang.com"])
	if not bool(lookup["ok"]):
		return bad.merged({"reason": "no Minecraft player was found (%s)" % String(lookup["reason"])})
	var found: Variant = JSON.parse_string(PackedByteArray(lookup["body"]).get_string_from_utf8())
	var uuid := String(found.get("id", "")) if found is Dictionary else ""
	if uuid.length() != 32 or not uuid.is_valid_hex_number():
		return bad.merged({"reason": "no Minecraft player was found"})
	var profile_response: Dictionary = await download_https("https://sessionserver.mojang.com/session/minecraft/profile/%s" % uuid, 16384, ["sessionserver.mojang.com"])
	if not bool(profile_response["ok"]):
		return bad.merged({"reason": "the profile could not be read (%s)" % String(profile_response["reason"])})
	var profile: Variant = JSON.parse_string(PackedByteArray(profile_response["body"]).get_string_from_utf8())
	var textures: Dictionary = PlayerSkin.parse_textures(profile) if profile is Dictionary else {}
	if textures.is_empty():
		return bad.merged({"reason": "that player has no skin"})
	var file: Dictionary = await download_https(String(textures["url"]), PlayerSkin.MAX_BYTES + 1, ["textures.minecraft.net"])
	if not bool(file["ok"]):
		return bad.merged({"reason": "the skin could not be downloaded (%s)" % String(file["reason"])})
	var image := Image.new()
	if image.load_png_from_buffer(file["body"]) != OK:
		return bad.merged({"reason": "the skin file could not be read"})
	return PlayerSkin.from_minecraft(image, bool(textures["slim"]))
