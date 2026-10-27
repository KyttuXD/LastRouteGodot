class_name OsmCityMap
extends Node

## Fetches an online-only real-place City map (docs/CITY_OSM_MAPS.md) from the primary server into memory:
## list -> ticket -> manifest (+ RSA signature check with the shipped public key) -> every file (sha256 check against the
## signed manifest). Nothing is written to disk; the bytes live in `files` until this node is freed.

signal listed(ok: bool, maps: Array, message: String)
signal progress(done: int, total: int)
signal downloaded(ok: bool, message: String)

const PUBLIC_KEY_PATH := "res://src/osm_city/maps_rsa_pub.pem"
const PARALLEL := 16

var manifest := {}
var files := {}           # file name -> PackedByteArray (gunzipped chunk / feature bytes stay as served)
var _ticket := ""
var _queue: Array = []
var _busy := 0
var _total := 0
var _failed := ""
var _map_path := ""


func fetch_list() -> void:
	if not _online():
		listed.emit.call_deferred(false, [], "Real places need the server and a signed-in account")
		return
	_post("/api/city-maps/list", {"sessionToken": Backend.account_session_token}, func(code: int, body: PackedByteArray) -> void:
		var data = JSON.parse_string(body.get_string_from_utf8()) if code > 0 else null
		if code == 200 and data is Dictionary and data.get("maps") is Array:
			listed.emit(true, data["maps"], "")
		else:
			listed.emit(false, [], _error_text(code, data)))


func download(map_id: String, version: int) -> void:
	manifest = {}
	files = {}
	if not _online():
		downloaded.emit.call_deferred(false, "Real places need the server and a signed-in account")
		return
	_post("/api/city-maps/ticket", {"sessionToken": Backend.account_session_token, "id": map_id, "version": version},
		func(code: int, body: PackedByteArray) -> void:
			var data = JSON.parse_string(body.get_string_from_utf8()) if code > 0 else null
			if code != 200 or not data is Dictionary or String(data.get("ticket", "")).is_empty():
				downloaded.emit(false, _error_text(code, data))
				return
			_ticket = String(data["ticket"])
			_map_path = "/api/city-maps/files/%s/%d/" % [map_id.uri_encode(), version]
			_fetch_manifest())


func _fetch_manifest() -> void:
	_get_file("manifest.json", func(ok: bool, manifest_bytes: PackedByteArray) -> void:
		if not ok:
			downloaded.emit(false, "Could not download the map manifest")
			return
		_get_file("manifest.rsa.sig", func(sig_ok: bool, signature: PackedByteArray) -> void:
			if not sig_ok or not verify_manifest(manifest_bytes, signature):
				downloaded.emit(false, "The map is not signed by the Last Route server")
				return
			manifest = JSON.parse_string(manifest_bytes.get_string_from_utf8())
			files["manifest.json"] = manifest_bytes
			files["manifest.rsa.sig"] = signature
			_queue = (manifest.get("files", {}) as Dictionary).keys()
			_total = _queue.size()
			_failed = ""
			for _index in mini(PARALLEL, _queue.size()):
				_next_file()))


static func verify_manifest(manifest_bytes: PackedByteArray, signature: PackedByteArray) -> bool:
	var key := CryptoKey.new()
	if key.load_from_string(FileAccess.get_file_as_string(PUBLIC_KEY_PATH), true) != OK:
		return false
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(manifest_bytes)
	return Crypto.new().verify(HashingContext.HASH_SHA256, hashing.finish(), signature, key)


func _next_file() -> void:
	if _queue.is_empty():
		if _busy == 0:
			if _failed.is_empty():
				downloaded.emit(true, "")
			else:
				files = {}
				downloaded.emit(false, _failed)
		return
	var name := String(_queue.pop_back())
	_busy += 1
	_get_file(name, func(ok: bool, bytes: PackedByteArray) -> void:
		_busy -= 1
		if not ok:
			_failed = "Could not download %s" % name
		elif _sha256(bytes) != String(manifest["files"][name]):
			_failed = "%s does not match the signed manifest" % name
		else:
			files[name] = bytes
		progress.emit(files.size(), _total)
		if not _failed.is_empty():
			_queue.clear()
		_next_file())


static func _sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


## Gunzipped LRC1 chunk: {"w", "h", "kinds": PackedByteArray, "heights": PackedByteArray} or {} if missing/corrupt.
func chunk(cx: int, cz: int) -> Dictionary:
	var bytes: PackedByteArray = files.get("c_%d_%d.bin" % [cx, cz], PackedByteArray())
	if bytes.is_empty():
		return {}
	var raw := bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if raw.size() < 8 or raw.slice(0, 4).get_string_from_ascii() != "LRC1":
		return {}
	var w := raw.decode_u16(4)
	var h := raw.decode_u16(6)
	return {"w": w, "h": h, "kinds": raw.slice(8, 8 + w * h), "heights": raw.slice(8 + w * h, 8 + 2 * w * h)}


func features() -> Dictionary:
	var bytes: PackedByteArray = files.get("features.json.gz", PackedByteArray())
	if bytes.is_empty():
		return {}
	var parsed = JSON.parse_string(bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


func _online() -> bool:
	return Backend.configured() and not Backend.offline_mode and Backend.signed_in()


func _error_text(code: int, data) -> String:
	if data is Dictionary and data.has("error"):
		return String(data["error"])
	return "The map server did not answer (HTTP %d)" % code


func _post(path: String, body: Dictionary, done: Callable) -> void:
	_request(path, HTTPClient.METHOD_POST, PackedStringArray(["Content-Type: application/json"]), JSON.stringify(body), done)


func _get_file(name: String, done: Callable) -> void:
	_request(_map_path + name, HTTPClient.METHOD_GET, PackedStringArray(["x-city-map-ticket: " + _ticket]), "",
		func(code: int, body: PackedByteArray) -> void: done.call(code == 200, body))


func _request(path: String, method: int, headers: PackedStringArray, body: String, done: Callable) -> void:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, data: PackedByteArray) -> void:
		http.queue_free()
		done.call(code if result == HTTPRequest.RESULT_SUCCESS else 0, data))
	if http.request(Backend.base_url.trim_suffix("/") + path, headers, method, body) != OK:
		http.queue_free()
		done.call(0, PackedByteArray())
