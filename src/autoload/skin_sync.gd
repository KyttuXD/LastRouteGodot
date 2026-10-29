class_name SkinSync
extends Node

## Player skins live on the ACCOUNT (docs/PLAYER_SKINS.md "Account skins"): signing in downloads the account's skin and keeps it in
## user://skin.png only as the offline fallback; changing the skin uploads it (PUT /api/v1/skins/<ACCOUNT>); co-op peers are looked up
## by account (GET /api/v1/skins/<ACCOUNT>) and their PNG fetched by hash. An existing local skin is uploaded on first sign-in when the
## account has none. Guests and offline rooms keep wearing the local file (and the old peer-to-peer hash path stays as the fallback).
##
## Sharing player skins through the backend (docs/PLAYER_SKINS.md). Signed-in players upload their own skin once (the server keeps
## one per account, addressed by sha256); the room state carries only the hash, and every peer downloads each hash once into
## PlayerSkin's MEMORY cache. Nothing downloaded is written to disk. Guests and offline players wear their skin locally only: it is
## never uploaded and never published to the room.
##
## Child of the Backend autoload (Backend.skin_sync).

signal fetched(hash: String)
## A peer's account skin lookup finished: hash ("" = none) and the arm style the account chose.
signal account_resolved(account: String, hash: String, arms: String)
## Your own skin was replaced by the account's (sign-in on another computer): the UI and your body should redraw.
signal own_skin_adopted

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
var _legacy_upload := false   # the server predates /api/v1/skins: use the old upload route
var _pull_request: HTTPRequest
var _pulling := false
var _account_cache := {}      # ACCOUNT -> {hash, arms, at (msec)}
var _account_pending := {}    # ACCOUNT -> true while a lookup is in flight
const ACCOUNT_CACHE_MSEC := 30000


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
	_pull_request = HTTPRequest.new()
	_pull_request.name = "SkinPullRequest"
	_pull_request.body_size_limit = FETCH_LIMIT_BYTES
	add_child(_pull_request)
	Backend.account_changed.connect(_on_account_changed)


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
	var headers := PackedStringArray(["content-type: application/octet-stream", "x-session-token: %s" % Backend.account_session_token,
		"x-skin-arms: %s" % Settings.skin_arms])
	var url := upload_url(Backend.base_url, Backend.account_username, _legacy_upload)
	var method := HTTPClient.METHOD_POST if _legacy_upload else HTTPClient.METHOD_PUT
	if _upload_request.request_raw(url, headers, method, png) != OK:
		_uploading = ""


## PUT /api/v1/skins/<ACCOUNT> (the account's own skin), or the old POST /api/skins/upload on a server that predates it.
static func upload_url(base_url: String, account: String, legacy: bool = false) -> String:
	var base := base_url.trim_suffix("/")
	return base + "/api/skins/upload" if legacy else "%s/api/v1/skins/%s" % [base, account.to_upper()]


func _on_upload_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var hash := _uploading
	_uploading = ""
	if result == HTTPRequest.RESULT_SUCCESS and code in [404, 405] and not _legacy_upload:
		_legacy_upload = true   # an older server: retry once on the old route
		_next_upload_try = 0.0
		sync_own()
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary and String(parsed.get("hash", "")) == hash:
		uploaded_hash = hash
		Settings.set_skin_pending_upload(false)
		_next_upload_try = 0.0


## Your skin was reset: tell the server to drop it (signed in), forget the upload.
func clear_own() -> void:
	uploaded_hash = ""
	Settings.set_skin_pending_upload(false)
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


# --------------------------------------------------------------------------------------- the account's skin (cloud)

## What to do at sign-in, given the local skin, whether it is waiting to be uploaded and the account's server skin:
## "adopt" (download the account's skin as yours), "upload" (the account has none, or you changed yours while offline), "nothing".
static func account_decision(local_hash: String, local_pending: bool, server_hash: String) -> String:
	if server_hash.is_empty():
		return "upload" if not local_hash.is_empty() else "nothing"
	if server_hash == local_hash:
		return "nothing"
	if not local_hash.is_empty() and local_pending:
		return "upload"
	return "adopt"


func _on_account_changed(signed_in: bool, _username: String, _admin: bool, _message: String) -> void:
	if signed_in and not Backend.offline_mode:
		pull_account_skin()


## Sign-in: ask the server which skin the account has, then adopt it, upload the local one, or leave things (account_decision).
func pull_account_skin() -> void:
	if _pulling or not Backend.signed_in() or Backend.offline_mode:
		return
	_pulling = true
	var account := Backend.account_username
	var meta := await _get_json("%s/api/v1/skins/%s" % [Backend.base_url.trim_suffix("/"), account.to_upper()])
	if meta.is_empty() or not Backend.signed_in() or Backend.account_username != account:
		_pulling = false
		sync_own()   # an older server without the route: the old upload flow still applies
		return
	var server_hash := String(meta.get("hash", ""))
	if not server_hash.is_empty() and not PlayerSkin.valid_hash(server_hash):
		server_hash = ""
	match account_decision(Settings.skin_hash, Settings.skin_pending_upload, server_hash):
		"adopt":
			var body := await _get_bytes("%s/api/skins/files/%s.png" % [Backend.base_url.trim_suffix("/"), server_hash])
			if not body.is_empty():
				adopt_account_skin(server_hash, String(meta.get("arms", "auto")), body)
		"upload":
			uploaded_hash = ""
			sync_own()
		_:
			if server_hash == Settings.skin_hash:
				uploaded_hash = server_hash
				Settings.set_skin_pending_upload(false)
	_pulling = false


## The downloaded bytes become your skin (kept in user://skin.png as the offline fallback), after the same hash + format checks as
## any skin. Returns true when adopted.
func adopt_account_skin(hash: String, arms: String, body: PackedByteArray) -> bool:
	if PlayerSkin.hash_of(body) != hash:
		return false
	var validated := PlayerSkin.validate(body)
	if not bool(validated["ok"]) or String(validated["hash"]) != hash:
		return false
	var applied := PlayerSkin.apply_result(validated)
	if not bool(applied.get("ok", false)):
		return false
	Settings.set_skin_arms(arms if ["auto", "classic", "slim"].has(arms) else "auto")
	Settings.set_skin_pending_upload(false)
	uploaded_hash = hash
	own_skin_adopted.emit()
	return true


## A co-op peer's skin by ACCOUNT: the server's answer is cached for ACCOUNT_CACHE_MSEC. Returns the cached {hash, arms} (or {}) and
## starts a lookup when there is none; account_resolved fires when it arrives. The caller then fetch()es the hash.
func account_skin(account: String) -> Dictionary:
	var key := account.to_upper()
	var cached: Dictionary = _account_cache.get(key, {})
	if not cached.is_empty() and Time.get_ticks_msec() - int(cached["at"]) < ACCOUNT_CACHE_MSEC:
		return cached
	if key.is_empty() or _account_pending.has(key) or Backend.offline_mode:
		return cached
	_account_pending[key] = true
	_lookup_account(key)
	return cached


func _lookup_account(key: String) -> void:
	var meta := await _get_json("%s/api/v1/skins/%s" % [Backend.base_url.trim_suffix("/"), key])
	_account_pending.erase(key)
	if meta.is_empty():
		return
	var hash := String(meta.get("hash", ""))
	if not hash.is_empty() and not PlayerSkin.valid_hash(hash):
		hash = ""
	var arms := String(meta.get("arms", "auto"))
	_account_cache[key] = {"hash": hash, "arms": arms if ["auto", "classic", "slim"].has(arms) else "auto",
		"at": Time.get_ticks_msec()}
	account_resolved.emit(key, hash, String(_account_cache[key]["arms"]))


func _get_json(url: String) -> Dictionary:
	var body := await _get_bytes(url, 8192)
	if body.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	return parsed if parsed is Dictionary and bool(parsed.get("ok", false)) else {}


func _get_bytes(url: String, limit: int = FETCH_LIMIT_BYTES) -> PackedByteArray:
	var request := HTTPRequest.new()
	request.body_size_limit = limit
	request.timeout = 10.0
	add_child(request)
	if request.request(url, PackedStringArray(["accept: */*"])) != OK:
		request.queue_free()
		return PackedByteArray()
	var done: Array = await request.request_completed
	request.queue_free()
	if int(done[0]) != HTTPRequest.RESULT_SUCCESS or int(done[1]) != 200:
		return PackedByteArray()
	return done[3]


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
