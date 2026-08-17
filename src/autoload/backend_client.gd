extends Node

## HTTP rendezvous client for ENet rooms. Real-time gameplay never passes
## through this service: it only publishes a host's UDP endpoint and resolves
## a five-character room code. Every build uses the official service for room
## discovery, accounts, and updates; there is deliberately no override.

signal registration_changed(registered: bool, message: String)
signal room_resolved(code: String, endpoint: Dictionary, error: String)
signal health_checked(ok: bool, message: String)

const HEARTBEAT_SECONDS := 20.0
const PRIMARY_BASE_URL := "http://lastroute.kyttuslab.org:1105"
const base_url := PRIMARY_BASE_URL

var registered := false
var registered_code := ""
var last_error := ""

var _token := ""
var _port := 0
var _player_count := 1
var _session_active := false
var _lan_addresses := PackedStringArray()
var _host_request: HTTPRequest
var _host_operation := ""
var _heartbeat: Timer
var _requests_suppressed_for_tests := false


func _ready() -> void:
	_host_request = HTTPRequest.new()
	_host_request.name = "HostDirectoryRequest"
	add_child(_host_request)
	_host_request.request_completed.connect(_on_host_response)
	_heartbeat = Timer.new()
	_heartbeat.name = "DirectoryHeartbeat"
	_heartbeat.wait_time = HEARTBEAT_SECONDS
	_heartbeat.one_shot = false
	_heartbeat.timeout.connect(_on_directory_tick)
	add_child(_heartbeat)


func configured() -> bool:
	return not _requests_suppressed_for_tests


func directory_label() -> String:
	if not configured():
		return "ROOM DIRECTORY DISABLED"
	return "PRIMARY ROOM DIRECTORY"


## Validation opens a real local ENet socket and must not publish its throwaway
## room to the live service. This changes no endpoint and is unavailable from
## the UI and command line.
func suppress_requests_for_tests() -> void:
	assert(OS.is_debug_build())
	_requests_suppressed_for_tests = true


func register_room(code: String, port: int, player_count: int,
		session_active: bool, lan_addresses := PackedStringArray()) -> void:
	if not configured():
		return
	if not _host_operation.is_empty():
		_host_request.cancel_request()
		_host_operation = ""
	registered = false
	registered_code = code.to_upper()
	_port = port
	_player_count = clampi(player_count, 1, 16)
	_session_active = session_active
	if not lan_addresses.is_empty():
		_lan_addresses = lan_addresses
	_token = ""
	_send_host("register", "/api/enet/rooms/register", {
		"code": registered_code,
		"port": _port,
		"players": _player_count,
		"sessionActive": _session_active,
		"lanAddresses": Array(_lan_addresses),
	})
	_heartbeat.start()


func update_room(player_count: int, session_active: bool) -> void:
	_player_count = clampi(player_count, 1, 16)
	_session_active = session_active
	# The periodic heartbeat is the durable update. Sending immediately when
	# idle makes roster/session changes show up quickly without piling requests.
	if registered and _host_operation.is_empty():
		_send_heartbeat()


func unregister_room() -> void:
	_heartbeat.stop()
	if not _host_operation.is_empty():
		_host_request.cancel_request()
		_host_operation = ""
	if not configured() or _token.is_empty() or registered_code.is_empty():
		_clear_registration()
		return
	# A one-shot request means leaving never waits on an in-flight heartbeat.
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(func(_result: int, _code: int,
			_headers: PackedStringArray, _body: PackedByteArray) -> void:
		request.queue_free())
	request.request(_url("/api/enet/rooms/unregister"), _headers(),
		HTTPClient.METHOD_POST, JSON.stringify({
			"code": registered_code,
			"token": _token,
		}))
	_clear_registration()


func resolve_room(code: String) -> void:
	var clean := code.strip_edges().to_upper()
	if not configured():
		room_resolved.emit(clean, {}, "ROOM DIRECTORY IS NOT CONFIGURED")
		return
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_resolve_response.bind(request, clean))
	var error := request.request(_url("/api/enet/rooms/%s" % clean),
		PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET)
	if error != OK:
		request.queue_free()
		room_resolved.emit(clean, {}, "COULD NOT START DIRECTORY LOOKUP")


func check_health() -> void:
	if not configured():
		health_checked.emit(false, "ROOM DIRECTORY IS NOT CONFIGURED")
		return
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_health_response.bind(request))
	var error := request.request(_url("/api/health"),
		PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET)
	if error != OK:
		request.queue_free()
		health_checked.emit(false, "COULD NOT START HEALTH CHECK")


func _send_heartbeat() -> void:
	if not registered or _token.is_empty() or not _host_operation.is_empty():
		return
	_send_host("heartbeat", "/api/enet/rooms/heartbeat", {
		"code": registered_code,
		"token": _token,
		"players": _player_count,
		"sessionActive": _session_active,
	})


func _on_directory_tick() -> void:
	if registered:
		_send_heartbeat()
	elif configured() and not registered_code.is_empty() and _port > 0 \
			and _host_operation.is_empty():
		register_room(registered_code, _port, _player_count, _session_active)


func _send_host(operation: String, path: String, body: Dictionary) -> void:
	if not _host_operation.is_empty():
		return
	_host_operation = operation
	var error := _host_request.request(_url(path), _headers(),
		HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		_host_operation = ""
		last_error = "DIRECTORY REQUEST COULD NOT START (%d)" % error
		registration_changed.emit(false, last_error)


func _on_host_response(result: int, response_code: int,
		_headers_value: PackedStringArray, body: PackedByteArray) -> void:
	var operation := _host_operation
	_host_operation = ""
	var payload := _parse_body(body)
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		last_error = String(payload.get("error", "DIRECTORY %s FAILED (HTTP %d)" % [operation.to_upper(), response_code]))
		if operation == "register":
			registered = false
			_token = ""
		registration_changed.emit(false, last_error)
		# A restarted directory has forgotten every room; a rejected/unknown
		# heartbeat should create a fresh token instead of retrying the stale one
		# forever. Transport/5xx failures keep the token and retry normally.
		if operation == "heartbeat" and response_code in [403, 404]:
			registered = false
			_token = ""
			registration_changed.emit(false, "PRIMARY SERVER RESTARTED // RELISTING ROOM")
			call_deferred("register_room", registered_code, _port,
				_player_count, _session_active)
		return
	if operation == "register":
		_token = String(payload.get("token", ""))
		if _token.is_empty():
			last_error = "DIRECTORY RETURNED NO HOST TOKEN"
			registration_changed.emit(false, last_error)
			return
		registered = true
		last_error = ""
		_heartbeat.start()
		registration_changed.emit(true, "ROOM %s LISTED IN DIRECTORY" % registered_code)
	elif operation == "heartbeat":
		var recovered := not last_error.is_empty()
		registered = true
		last_error = ""
		if recovered:
			registration_changed.emit(true,
				"ROOM %s LISTED IN DIRECTORY" % registered_code)


func _on_resolve_response(result: int, response_code: int,
		_headers_value: PackedStringArray, body: PackedByteArray,
		request: HTTPRequest, code: String) -> void:
	request.queue_free()
	var payload := _parse_body(body)
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		room_resolved.emit(code, {}, String(payload.get("error",
			"ROOM %s WAS NOT FOUND" % code)))
		return
	var room = payload.get("room", {})
	if not room is Dictionary or String(room.get("address", "")).is_empty():
		room_resolved.emit(code, {}, "DIRECTORY RETURNED AN INVALID ENDPOINT")
		return
	room_resolved.emit(code, room, "")


func _on_health_response(result: int, response_code: int,
		_headers_value: PackedStringArray, body: PackedByteArray,
		request: HTTPRequest) -> void:
	request.queue_free()
	var payload := _parse_body(body)
	var ok := result == HTTPRequest.RESULT_SUCCESS and response_code == 200 \
		and bool(payload.get("ok", false))
	health_checked.emit(ok, "DIRECTORY ONLINE" if ok else "DIRECTORY UNAVAILABLE")


func _parse_body(body: PackedByteArray) -> Dictionary:
	var value = JSON.parse_string(body.get_string_from_utf8())
	return value if value is Dictionary else {}


func _headers() -> PackedStringArray:
	return PackedStringArray(["Accept: application/json", "Content-Type: application/json"])


func _url(path: String) -> String:
	return "%s%s" % [base_url, path]


func _clear_registration() -> void:
	registered = false
	registered_code = ""
	_token = ""
	_port = 0
	_lan_addresses = PackedStringArray()
	_host_operation = ""
	_heartbeat.stop()
