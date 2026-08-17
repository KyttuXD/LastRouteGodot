extends Node

## Checks the trusted room/backend service for a small channel/platform
## manifest. Installation remains platform-owned: desktop opens the published
## ZIP/installer, Web refreshes its hosted build, Steam uses Steam depots, and
## Quest production uses Meta's store. Overwriting a running executable from
## inside the game would be brittle and unsafe without a signed launcher.

signal update_available(update: Dictionary)
signal status_changed(message: String)
signal check_finished(success: bool, update_needed: bool)

var available := {}
var check_complete := false
var check_succeeded := false
var update_required := false
var checking := false
var _request: HTTPRequest


func _ready() -> void:
	_request = HTTPRequest.new()
	_request.name = "UpdateManifestRequest"
	add_child(_request)
	_request.request_completed.connect(_on_response)
	if DisplayServer.get_name() != "headless":
		check.call_deferred()


func check() -> void:
	if checking or _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	check_complete = false
	check_succeeded = false
	update_required = false
	available = {}
	if not Backend.configured():
		_finish_check(false, false, "UPDATE CHECK UNAVAILABLE")
		return
	checking = true
	status_changed.emit("CHECKING FOR UPDATES")
	var error := _request.request("%s/api/updates/%s/%s" % [
		Backend.base_url, Build.update_channel(), platform_key()],
		PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET)
	if error != OK:
		_finish_check(false, false, "UPDATE CHECK UNAVAILABLE")


func platform_key() -> String:
	if OS.has_feature("web"):
		return "web"
	if OS.has_feature("quest"):
		return "quest"
	if OS.has_feature("windows") and OS.has_feature("xr"):
		return "steamvr"
	if OS.has_feature("macos"):
		return "macos"
	if OS.has_feature("windows"):
		return "windows"
	return "linux"


func _on_response(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_finish_check(false, false, "UPDATE CHECK UNAVAILABLE")
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary or not parsed.get("update") is Dictionary:
		_finish_check(false, false, "INVALID UPDATE RESPONSE")
		return
	var candidate: Dictionary = parsed["update"]
	var version := String(candidate.get("version", ""))
	var revision := String(candidate.get("revision", "")).strip_edges().to_lower()
	var url := String(candidate.get("url", ""))
	if url.begins_with("/api/"):
		url = "%s%s" % [Backend.base_url, url]
		candidate["url"] = url
	var trusted_transport := url.begins_with("https://") \
		or url.begins_with("%s/api/updates/files/" % Backend.base_url) \
		or (Build.tools_enabled() and (url.begins_with("http://127.0.0.1") \
			or url.begins_with("http://localhost")))
	if not trusted_transport:
		_finish_check(false, false, "UNTRUSTED UPDATE RESPONSE")
		return
	if not _update_needed(version, Build.VERSION, revision, Build.revision()):
		_finish_check(true, false, "UP TO DATE")
		return
	available = candidate.duplicate(true)
	update_required = bool(candidate.get("required", false))
	update_available.emit(available)
	var identity := revision.left(8) if not revision.is_empty() else version
	_finish_check(true, true, "UPDATE %s AVAILABLE" % identity)


func open_download() -> void:
	var url := String(available.get("url", ""))
	var backend_asset := url.begins_with("%s/api/updates/files/" % Backend.base_url)
	if url.begins_with("https://") or backend_asset or (Build.tools_enabled() \
			and (url.begins_with("http://127.0.0.1") \
				or url.begins_with("http://localhost"))):
		OS.shell_open(url)


static func _newer(candidate: String, current: String) -> bool:
	var a := candidate.trim_prefix("v").split(".")
	var b := current.trim_prefix("v").split(".")
	for index in maxi(a.size(), b.size()):
		var av := int(a[index]) if index < a.size() else 0
		var bv := int(b[index]) if index < b.size() else 0
		if av != bv:
			return av > bv
	return false


static func _update_needed(candidate_version: String, current_version: String,
		candidate_revision: String, current_revision: String) -> bool:
	if _newer(candidate_version, current_version):
		return true
	if _newer(current_version, candidate_version):
		return false
	var candidate := candidate_revision.strip_edges().to_lower()
	var current := current_revision.strip_edges().to_lower()
	return _valid_revision(candidate) and _valid_revision(current) and candidate != current


static func _valid_revision(value: String) -> bool:
	if value.length() < 7 or value.length() > 40:
		return false
	for character in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true


func _finish_check(success: bool, needs_update: bool, message: String) -> void:
	checking = false
	check_complete = true
	check_succeeded = success
	status_changed.emit(message)
	check_finished.emit(success, needs_update)
