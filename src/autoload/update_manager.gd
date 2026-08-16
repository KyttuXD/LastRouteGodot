extends Node

## Checks the trusted room/backend service for a small channel/platform
## manifest. Installation remains platform-owned: desktop opens the published
## ZIP/installer, Web refreshes its hosted build, Steam uses Steam depots, and
## Quest production uses Meta's store. Overwriting a running executable from
## inside the game would be brittle and unsafe without a signed launcher.

signal update_available(update: Dictionary)
signal status_changed(message: String)

var available := {}
var _request: HTTPRequest


func _ready() -> void:
	_request = HTTPRequest.new()
	_request.name = "UpdateManifestRequest"
	add_child(_request)
	_request.request_completed.connect(_on_response)
	if DisplayServer.get_name() != "headless":
		check.call_deferred()


func check() -> void:
	if not Backend.configured() or _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var error := _request.request("%s/api/updates/%s/%s" % [
		Backend.base_url, Build.update_channel(), platform_key()],
		PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET)
	if error != OK:
		status_changed.emit("UPDATE CHECK UNAVAILABLE")


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
	if result != HTTPRequest.RESULT_SUCCESS or code == 404:
		return
	if code != 200:
		status_changed.emit("UPDATE CHECK UNAVAILABLE")
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary or not parsed.get("update") is Dictionary:
		return
	var candidate: Dictionary = parsed["update"]
	var version := String(candidate.get("version", ""))
	var url := String(candidate.get("url", ""))
	if url.begins_with("/api/"):
		url = "%s%s" % [Backend.base_url, url]
		candidate["url"] = url
	var trusted_transport := url.begins_with("https://") \
		or url.begins_with("%s/api/updates/files/" % Backend.base_url) \
		or (Build.tools_enabled() and (url.begins_with("http://127.0.0.1") \
			or url.begins_with("http://localhost")))
	if not _newer(version, Build.VERSION) or not trusted_transport:
		return
	available = candidate.duplicate(true)
	update_available.emit(available)
	status_changed.emit("UPDATE %s AVAILABLE" % version)


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
	for index in 3:
		var av := int(a[index]) if index < a.size() else 0
		var bv := int(b[index]) if index < b.size() else 0
		if av != bv:
			return av > bv
	return false
