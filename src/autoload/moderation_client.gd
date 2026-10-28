class_name ModerationClient
extends Node

## Client side of server moderation (docs/ANTI_CHEAT.md). The server decides every restriction; this only reports the
## build at sign-in and room join, fetches the account's status so the player can read why something is locked, and
## carries the host's kick reports and flagged-peer lookups. A modified client can lie in every report: the build hash
## is a signal, never proof, and nothing here unlocks anything.

const DEVICE_PATH := "user://device_id"
const PEER_LOOKUP_MAX := 16

signal status_changed(status: Dictionary)
signal peers_looked_up(players: Dictionary, devices: Dictionary)

var status := {}
var _device_id := ""
var _build_hash := ""
var _hash_thread: Thread


func _ready() -> void:
	_start_build_hash()


func _exit_tree() -> void:
	if _hash_thread != null and _hash_thread.is_started():
		_hash_thread.wait_to_finish()


## A random id for this install, kept in user://. Only its hash is stored by the server.
func device_id() -> String:
	if not _device_id.is_empty():
		return _device_id
	var file := FileAccess.open(DEVICE_PATH, FileAccess.READ)
	if file != null:
		_device_id = file.get_as_text().strip_edges()
	if _device_id.length() != 32:
		var bytes := Crypto.new().generate_random_bytes(16)
		_device_id = bytes.hex_encode()
		var out := FileAccess.open(DEVICE_PATH, FileAccess.WRITE)
		if out != null:
			out.store_string(_device_id)
	return _device_id


## SHA-256 of the PCK (or the executable with an embedded PCK); "source" for editor/source runs. Hashed once on a
## thread so start-up never waits on a large file.
func build_hash() -> String:
	return _build_hash


func _start_build_hash() -> void:
	if OS.has_feature("editor") or OS.has_feature("web"):
		_build_hash = Build.SOURCE_REVISION
		return
	var exe := OS.get_executable_path()
	var pck := exe.get_basename() + ".pck"
	var path := pck if FileAccess.file_exists(pck) else exe
	_hash_thread = Thread.new()
	_hash_thread.start(func() -> void:
		var digest := FileAccess.get_sha256(path)
		call_deferred("_set_build_hash", digest if not digest.is_empty() else "unknown"))


func _set_build_hash(digest: String) -> void:
	_build_hash = digest
	if _hash_thread != null and _hash_thread.is_started():
		_hash_thread.wait_to_finish()


func _platform() -> String:
	for name in ["android", "ios", "web", "windows", "macos", "linuxbsd"]:
		if OS.has_feature(name):
			return name
	return OS.get_name().to_lower()


## context: "signin" or "join". Waits for the build hash when it is still being computed.
func report_integrity(context: String) -> void:
	if not _enabled():
		return
	while _build_hash.is_empty() and is_inside_tree():
		await get_tree().process_frame
	if _build_hash.length() != 64:
		return   # editor / source run: nothing to compare against a published build
	_post("/api/moderation/integrity", {
		"sessionToken": Backend.account_session_token,
		"deviceId": device_id(),
		"commit": Build.revision(),
		"buildHash": _build_hash,
		"platform": _platform(),
		"channel": Build.update_channel(),
		"context": context,
	}, _on_status_reply)


func refresh_status() -> void:
	if _enabled():
		_post("/api/moderation/status",
			{"sessionToken": Backend.account_session_token, "deviceId": device_id()}, _on_status_reply)


## Host only: the server checks the host token against the registered room.
func report_kick(username: String, guest_device: String, reason: String, strikes: int) -> void:
	if not _enabled() or Backend.host_token().is_empty():
		return
	_post("/api/moderation/report", {"code": RoomState.code, "hostToken": Backend.host_token(),
		"username": username, "deviceId": guest_device, "reason": reason, "strikes": strikes, "kind": "kick"},
		func(_reply: Dictionary) -> void: pass)


## Host only: which guests are flagged or under an owner's troll toggle.
func lookup_peers(usernames: Array, devices: Array) -> void:
	if not _enabled() or Backend.host_token().is_empty():
		return
	_post("/api/moderation/peers", {"code": RoomState.code, "hostToken": Backend.host_token(),
		"usernames": usernames.slice(0, PEER_LOOKUP_MAX), "deviceIds": devices.slice(0, PEER_LOOKUP_MAX)},
		func(reply: Dictionary) -> void:
			var players = reply.get("players", {})
			var found_devices = reply.get("devices", {})
			peers_looked_up.emit(players if players is Dictionary else {},
				found_devices if found_devices is Dictionary else {}))


func _on_status_reply(reply: Dictionary) -> void:
	var value = reply.get("status")
	if value is Dictionary:
		status = value
		status_changed.emit(status)


## Player-facing restriction line ("" when nothing applies). Server refusals (code FLAGGED) carry the same text.
func restriction_message() -> String:
	return String(status.get("message", ""))


func _enabled() -> bool:
	return is_inside_tree() and Backend.accounts_available() and not Backend.offline_mode


func _post(path: String, body: Dictionary, done: Callable) -> void:
	var request := HTTPRequest.new()
	request.timeout = 10.0
	add_child(request)
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray,
			bytes: PackedByteArray) -> void:
		request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			return
		var parsed = JSON.parse_string(bytes.get_string_from_utf8())
		if parsed is Dictionary:
			if code == 403 and String((parsed as Dictionary).get("code", "")) == "FLAGGED":
				status = {"flagged": true, "message": String(parsed.get("error", "")),
					"until": parsed.get("until"), "permanent": bool(parsed.get("permanent", false))}
				status_changed.emit(status)
			done.call(parsed))
	if request.request(Backend._url(path), Backend._headers(), HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		request.queue_free()
