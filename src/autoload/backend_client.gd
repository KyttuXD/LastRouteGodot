extends Node

## HTTP rendezvous client for ENet rooms. The directory issues the host token
## used by the gameplay relay and resolves a five-character room code to that
## relay. Every build uses the official service for discovery, accounts,
## updates, and relayed co-op; there is deliberately no override.

signal registration_changed(registered: bool, message: String)
signal room_resolved(code: String, endpoint: Dictionary, error: String)
signal health_checked(ok: bool, message: String)
signal account_changed(signed_in: bool, username: String, admin: bool, message: String)
signal account_progress_changed(available: bool, progress: Dictionary,
	saved_at: int, message: String)
## Release guest administration uses an opaque, five-minute room proof. The
## account session stays on this client; only this ticket crosses ENet, and the
## player-host asks the primary service to validate it with the host token.
signal admin_ticket_changed(ready: bool, room_code: String, message: String)
signal admin_ticket_verified(request_id: int, authorized: bool,
	expires_in: int, message: String)

const HEARTBEAT_SECONDS := 20.0
const PRIMARY_BASE_URL := "https://lastroute.kyttuslab.org:1105"
const ACCOUNT_CONFIG_PATH := "user://last_route_account.cfg"
var base_url := PRIMARY_BASE_URL

var registered := false
var registered_code := ""
var last_error := ""
var account_username := ""
var account_session_token := ""
var account_admin := false
var account_progress: Dictionary = {}
var account_progress_saved_at := 0
## Live primary-server verification is never restored from the editable local
## config file. This prevents a player from granting herself release admin by
## changing a cached boolean on disk.
var account_session_verified := false
var account_busy := false
var _admin_ticket := ""
var _admin_ticket_room := ""
var _admin_ticket_expires_msec := 0

var _token := ""
var _port := 0
var _player_count := 1
var _session_active := false
var _host_endpoint := {}
var _host_request: HTTPRequest
var _host_operation := ""
var _heartbeat: Timer
var _account_request: HTTPRequest
var _account_operation := ""
var _admin_ticket_request: HTTPRequest
var _admin_ticket_operation := ""
var _admin_verify_request_id := 0
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
	_account_request = HTTPRequest.new()
	_account_request.name = "AccountRequest"
	add_child(_account_request)
	_account_request.request_completed.connect(_on_account_response)
	_admin_ticket_request = HTTPRequest.new()
	_admin_ticket_request.name = "AdminTicketRequest"
	add_child(_admin_ticket_request)
	_admin_ticket_request.request_completed.connect(_on_admin_ticket_response)
	_load_account_session()
	if not account_session_token.is_empty() and accounts_available():
		_send_account("session", "/api/account/session", {
			"sessionToken": account_session_token,
		})


func configured() -> bool:
	return not _requests_suppressed_for_tests


func directory_label() -> String:
	if not configured():
		return "ROOM DIRECTORY DISABLED"
	return "PRIMARY ROOM DIRECTORY"


func accounts_available() -> bool:
	return _account_transport_is_protected()


func account_transport_warning() -> String:
	return ""


func _account_transport_is_protected() -> bool:
	var origin := base_url.trim_suffix("/").to_lower()
	if origin.begins_with("https://"):
		return true
	# Development loopback is allowed, but require an exact host boundary so
	# names such as `localhost.example` cannot masquerade as local transport.
	return origin == "http://127.0.0.1" or origin.begins_with("http://127.0.0.1:") \
		or origin == "http://localhost" or origin.begins_with("http://localhost:")


func signed_in() -> bool:
	return account_session_verified and not account_username.is_empty() \
		and not account_session_token.is_empty()


func admin_authorized() -> bool:
	return signed_in() and account_session_verified and account_admin \
		and account_username == "KYTTU"


func admin_ticket_for_room(room_code: String) -> String:
	var clean := room_code.strip_edges().to_upper()
	if clean != _admin_ticket_room or Time.get_ticks_msec() >= _admin_ticket_expires_msec:
		return ""
	return _admin_ticket


## Mint a room-bound proof after a release admin adopts the host's real room
## code. Repeated room packets are common, so a still-valid proof is reused.
func request_admin_ticket(room_code: String) -> void:
	var clean := room_code.strip_edges().to_upper()
	if not admin_authorized() or not RoomState.valid_room_code(clean):
		_clear_admin_ticket()
		return
	if not admin_ticket_for_room(clean).is_empty():
		admin_ticket_changed.emit(true, clean, "ADMIN ROOM PROOF READY")
		return
	if not accounts_available():
		admin_ticket_changed.emit(false, clean,
			"ADMIN ROOM PROOF IS DISABLED FOR THIS BACKEND ORIGIN")
		return
	if not _admin_ticket_operation.is_empty():
		return
	_admin_ticket_operation = "issue"
	var error := _admin_ticket_request.request(
		_url("/api/enet/admin-tickets/issue"), _headers(), HTTPClient.METHOD_POST,
		JSON.stringify({"code": clean, "sessionToken": account_session_token}))
	if error != OK:
		_admin_ticket_operation = ""
		admin_ticket_changed.emit(false, clean,
			"ADMIN ROOM PROOF REQUEST COULD NOT START (%d)" % error)


## Host-only validation. A separate one-shot HTTPRequest per intent avoids an
## admin click racing the directory heartbeat or another guest's proof.
func verify_room_admin_ticket(room_code: String, ticket: String) -> int:
	_admin_verify_request_id += 1
	var request_id := _admin_verify_request_id
	var clean := room_code.strip_edges().to_upper()
	if not registered or clean != registered_code or _token.is_empty() \
			or ticket.length() != 43:
		call_deferred("_emit_admin_ticket_verification", request_id, false, 0,
			"ROOM HOST CANNOT VERIFY THIS ADMIN PROOF")
		return request_id
	var request := HTTPRequest.new()
	request.name = "AdminTicketVerify%d" % request_id
	add_child(request)
	request.request_completed.connect(_on_admin_verify_response.bind(request,
		request_id))
	var error := request.request(_url("/api/enet/admin-tickets/verify"), _headers(),
		HTTPClient.METHOD_POST, JSON.stringify({
			"code": clean,
			"ticket": ticket,
			"hostToken": _token,
		}))
	if error != OK:
		request.queue_free()
		call_deferred("_emit_admin_ticket_verification", request_id, false, 0,
			"ADMIN PROOF VERIFICATION COULD NOT START (%d)" % error)
	return request_id


func _emit_admin_ticket_verification(request_id: int, authorized: bool,
		expires_in: int, message: String) -> void:
	admin_ticket_verified.emit(request_id, authorized, expires_in, message)


func has_route_checkpoint() -> bool:
	return String(account_progress.get("kind", "")) == "last_route" \
		and int(account_progress.get("schema", 0)) == 1


func account_register(username: String, password: String,
		admin_proof: String = "") -> void:
	_send_credentials("register", username, password, admin_proof)


func account_login(username: String, password: String) -> void:
	_send_credentials("login", username, password)


func account_rename(username: String, admin_proof: String = "") -> void:
	if not signed_in():
		account_changed.emit(false, account_username, account_admin,
			"SIGN IN TO RENAME THIS ACCOUNT")
		return
	var body := {
		"sessionToken": account_session_token,
		"username": username.strip_edges().to_upper(),
	}
	if not admin_proof.is_empty():
		body["adminProof"] = admin_proof
	_send_account("rename", "/api/account/rename", body)


func account_change_password(password: String) -> void:
	if not signed_in():
		account_changed.emit(false, account_username, account_admin,
			"SIGN IN TO CHANGE THIS ACCOUNT PASSWORD")
		return
	_send_account("password", "/api/account/password", {
		"sessionToken": account_session_token,
		"password": password,
	})


func account_logout() -> void:
	var old_token := account_session_token
	_clear_account_session()
	account_progress_changed.emit(false, {}, 0, "SIGNED OUT")
	account_changed.emit(false, "", false, "SIGNED OUT")
	if old_token.is_empty() or not accounts_available() or account_busy:
		return
	_send_account("logout", "/api/account/logout", {"sessionToken": old_token})


func account_save_progress(progress: Dictionary) -> void:
	if not signed_in():
		account_progress_changed.emit(has_route_checkpoint(),
			account_progress.duplicate(true), account_progress_saved_at,
			"SIGN IN TO SAVE ROUTE PROGRESS")
		return
	_send_account("save", "/api/account/save", {
		"sessionToken": account_session_token,
		"progress": progress,
	})


func account_clear_progress() -> void:
	if not signed_in():
		return
	_send_account("save", "/api/account/save", {
		"sessionToken": account_session_token,
		"progress": null,
	})


func account_load_progress() -> void:
	if not signed_in():
		return
	_send_account("load", "/api/account/load", {
		"sessionToken": account_session_token,
	})


func _send_credentials(operation: String, username: String, password: String,
		admin_proof: String = "") -> void:
	if not accounts_available():
		account_changed.emit(false, account_username, account_admin,
			"ACCOUNT LOGIN IS DISABLED FOR THIS BACKEND ORIGIN")
		return
	var body := {
		"username": username.strip_edges().to_upper(),
		"password": password,
	}
	if not admin_proof.is_empty():
		body["adminProof"] = admin_proof
	_send_account(operation, "/api/account/%s" % operation, body)


func _send_account(operation: String, path: String, body: Dictionary) -> void:
	if account_busy:
		account_changed.emit(signed_in(), account_username, account_admin,
			"ACCOUNT REQUEST ALREADY IN PROGRESS")
		return
	account_busy = true
	_account_operation = operation
	var error := _account_request.request(_url(path), _headers(),
		HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		account_busy = false
		_account_operation = ""
		account_changed.emit(signed_in(), account_username, account_admin,
			"ACCOUNT REQUEST COULD NOT START (%d)" % error)


func _on_account_response(result: int, response_code: int,
		_headers_value: PackedStringArray, body: PackedByteArray) -> void:
	var operation := _account_operation
	_account_operation = ""
	account_busy = false
	var payload := _parse_body(body)
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		if operation == "session":
			_clear_account_session()
		var message := String(payload.get("error", "ACCOUNT %s FAILED (HTTP %d)" % [
			operation.to_upper(), response_code]))
		if operation in ["save", "load"]:
			account_progress_changed.emit(has_route_checkpoint(),
				account_progress.duplicate(true), account_progress_saved_at, message)
		else:
			account_changed.emit(signed_in(), account_username, account_admin, message)
		return
	if operation in ["register", "login", "session"]:
		account_username = String(payload.get("username", "")).strip_edges().to_upper()
		account_session_token = String(payload.get("sessionToken", account_session_token))
		account_admin = bool(payload.get("admin", false)) and account_username == "KYTTU"
		if account_username.is_empty() or account_session_token.is_empty():
			_clear_account_session()
			account_changed.emit(false, "", false, "PRIMARY SERVER RETURNED AN INVALID ACCOUNT")
			return
		account_session_verified = true
		_save_account_session()
		_adopt_account_progress(payload,
			"ROUTE CHECKPOINT LOADED" if payload.get("progress") is Dictionary \
			else "NO ROUTE CHECKPOINT")
		account_changed.emit(true, account_username, account_admin,
			"SIGNED IN AS %s" % account_username)
	elif operation in ["save", "load"]:
		_adopt_account_progress(payload,
			"ROUTE CHECKPOINT SAVED" if operation == "save" \
				and payload.get("progress") is Dictionary \
			else "ROUTE CHECKPOINT CLEARED" if operation == "save" \
			else "ROUTE CHECKPOINT LOADED")
	elif operation == "rename":
		account_username = String(payload.get("username", account_username)) \
			.strip_edges().to_upper()
		account_admin = bool(payload.get("admin", false)) and account_username == "KYTTU"
		account_session_verified = not account_username.is_empty() \
			and not account_session_token.is_empty()
		_save_account_session()
		account_changed.emit(signed_in(), account_username, account_admin,
			"ACCOUNT RENAMED TO %s" % account_username)
	elif operation == "password":
		account_changed.emit(signed_in(), account_username, account_admin,
			"ACCOUNT PASSWORD UPDATED")


func _on_admin_ticket_response(result: int, response_code: int,
		_headers_value: PackedStringArray, body: PackedByteArray) -> void:
	var operation := _admin_ticket_operation
	_admin_ticket_operation = ""
	if operation != "issue":
		return
	var payload := _parse_body(body)
	if not admin_authorized():
		_clear_admin_ticket()
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 \
			or response_code >= 300:
		_clear_admin_ticket()
		admin_ticket_changed.emit(false, "", String(payload.get("error",
			"ADMIN ROOM PROOF FAILED (HTTP %d)" % response_code)))
		return
	var ticket := String(payload.get("ticket", ""))
	var room_code := String(payload.get("room", "")).strip_edges().to_upper()
	var expires_in := clampi(int(payload.get("expiresIn", 0)), 1, 300)
	if ticket.length() != 43 or not RoomState.valid_room_code(room_code):
		_clear_admin_ticket()
		admin_ticket_changed.emit(false, room_code,
			"PRIMARY SERVER RETURNED AN INVALID ADMIN PROOF")
		return
	_admin_ticket = ticket
	_admin_ticket_room = room_code
	_admin_ticket_expires_msec = Time.get_ticks_msec() + expires_in * 1000
	admin_ticket_changed.emit(true, room_code, "ADMIN ROOM PROOF READY")


func _on_admin_verify_response(result: int, response_code: int,
		_headers_value: PackedStringArray, body: PackedByteArray,
		request: HTTPRequest, request_id: int) -> void:
	request.queue_free()
	var payload := _parse_body(body)
	var authorized := result == HTTPRequest.RESULT_SUCCESS \
		and response_code >= 200 and response_code < 300 \
		and bool(payload.get("authorized", false))
	var expires_in := clampi(int(payload.get("expiresIn", 0)), 0, 300) \
		if authorized else 0
	admin_ticket_verified.emit(request_id, authorized, expires_in,
		"ADMIN ROOM PROOF VERIFIED" if authorized else String(payload.get("error",
			"ADMIN ROOM PROOF REJECTED")))


func _adopt_account_progress(payload: Dictionary, message: String) -> void:
	var value = payload.get("progress")
	account_progress = value.duplicate(true) if value is Dictionary else {}
	account_progress_saved_at = int(payload.get("savedAt", 0))
	account_progress_changed.emit(has_route_checkpoint(),
		account_progress.duplicate(true), account_progress_saved_at, message)


func _load_account_session() -> void:
	var config := ConfigFile.new()
	if config.load(ACCOUNT_CONFIG_PATH) != OK:
		return
	account_username = String(config.get_value("account", "username", "")).strip_edges().to_upper()
	account_session_token = String(config.get_value("account", "session_token", ""))
	account_admin = false
	account_session_verified = false


func _save_account_session() -> void:
	var config := ConfigFile.new()
	config.set_value("account", "username", account_username)
	config.set_value("account", "session_token", account_session_token)
	config.save(ACCOUNT_CONFIG_PATH)


func _clear_account_session() -> void:
	account_username = ""
	account_session_token = ""
	account_admin = false
	account_session_verified = false
	account_progress = {}
	account_progress_saved_at = 0
	_clear_admin_ticket()
	var config := ConfigFile.new()
	config.set_value("account", "username", "")
	config.set_value("account", "session_token", "")
	config.save(ACCOUNT_CONFIG_PATH)


func _clear_admin_ticket() -> void:
	_admin_ticket = ""
	_admin_ticket_room = ""
	_admin_ticket_expires_msec = 0


## Validation opens a real local ENet socket and must not publish its throwaway
## room to the live service. This changes no endpoint and is unavailable from
## the UI and command line.
func suppress_requests_for_tests() -> void:
	assert(OS.is_debug_build())
	_requests_suppressed_for_tests = true


## Headless transport smoke tests run an isolated copy of the real Node server
## on loopback. This has no UI/CLI release path and the debug assertion keeps
## the official build's primary endpoint policy intact.
func use_test_base_url(url: String) -> void:
	assert(OS.is_debug_build())
	base_url = url.strip_edges().trim_suffix("/")


func register_room(code: String, port: int, player_count: int,
		session_active: bool) -> void:
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
	_token = ""
	_send_host("register", "/api/enet/rooms/register", {
		"code": registered_code,
		"port": _port,
		"players": _player_count,
		"sessionActive": _session_active,
	})
	_heartbeat.start()


func update_room(player_count: int, session_active: bool) -> void:
	_player_count = clampi(player_count, 1, 16)
	_session_active = session_active
	# The periodic heartbeat is the durable update. Sending immediately when
	# idle makes roster/session changes show up quickly without piling requests.
	if registered and _host_operation.is_empty():
		_send_heartbeat()


func host_token() -> String:
	return _token


func host_endpoint() -> Dictionary:
	return _host_endpoint.duplicate()


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
	# CREATE ROOM waits on this probe before choosing online or solo. Keep a
	# dead primary service from turning that click into a long frozen-looking
	# menu state.
	request.timeout = 5.0
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
		_host_endpoint = payload.get("room", {}) if payload.get("room", {}) is Dictionary else {}
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
	_host_endpoint = {}
	_host_operation = ""
	_heartbeat.stop()
