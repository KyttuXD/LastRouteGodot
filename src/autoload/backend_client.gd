extends Node

## HTTP rendezvous client for ENet rooms. The directory issues the host token
## used by the gameplay relay and resolves a five-character room code to that
## relay. Every build uses the official service for discovery, accounts,
## updates, and relayed co-op; there is deliberately no override.

signal registration_changed(registered: bool, message: String)
signal room_resolved(code: String, endpoint: Dictionary, error: String)
## Reserved private rooms (backend reserved_rooms.mjs): nobody is hosting it and this player may (settings: stored
## route options); the room wants an invite or its password; owner commands for the room this client hosts.
signal reserved_room_hostable(code: String, settings: Dictionary)
signal reserved_room_access_needed(code: String, message: String)
signal reserved_commands_received(commands: Array)
signal health_checked(ok: bool, message: String)
signal account_changed(signed_in: bool, username: String, admin: bool, message: String)
signal account_progress_changed(available: bool, progress: Dictionary,
	saved_at: int, message: String)
## Release guest administration uses an opaque, five-minute room proof. The
## account session stays on this client; only this ticket crosses ENet, and the
## player-host asks the primary service to validate it with the host token.
signal admin_ticket_changed(ready: bool, room_code: String, message: String)
signal admin_ticket_verified(request_id: int, authorized: bool,
	expires_in: int, permissions: PackedStringArray, message: String)
signal admin_roster_changed(ok: bool, message: String, roster: Array)

const HEARTBEAT_SECONDS := 20.0
## The current Pterodactyl allocation exposes Node's plain HTTP listener
## directly. The user has explicitly enabled account/password requests for
## this exact origin. The plaintext-transport risk is documented in the repo.
const PRIMARY_BASE_URL := "http://lastroute.kyttuslab.org:8105"
## Dev/test only: the ONE extra origin a debug build may be pointed at with `--backend=`: the
## separate TEST instance on the same VPS (its own data, ports and admin key). Exact match only;
## release builds ignore it, so a shipped game can never be redirected.
const TEST_BASE_URLS := ["http://lastroute.kyttuslab.org:8205"]
const ACCOUNT_CONFIG_PATH := "user://last_route_account.cfg"
## HTTP statuses that mean the server REJECTED the stored session (it is cleared); anything else (no network, a restart,
## a 5xx) leaves the token alone so a login survives the server being down or a different server being selected.
const SESSION_REJECTED_CODES := [400, 401, 403, 404]
## The file the account session lives in: `--profile=NAME` (scripts/run_multi.sh) gives every instance its own file.
var account_config_path := ACCOUNT_CONFIG_PATH
var base_url := PRIMARY_BASE_URL
## True while a debug run is talking to the TEST instance (menu and HUD show a TEST SERVER badge).
var test_server_active := false
var offline_mode := false

var registered := false
var registered_code := ""
var last_error := ""
var account_username := ""
var account_session_token := ""
## A reserved room's password as the player typed it: memory only, sent to resolve/register, never saved.
var room_password := ""
## The relay join ticket from the last reserved resolve, and the code it is for (used once by RoomState.join_room).
var reserved_join_ticket := ""
var reserved_join_code := ""
## The reserved room this client hosts: its stored settings, and the owner commands seen / carried out.
var reserved_settings := {}
var _reserved_seen := 0
var _reserved_ack := 0
var account_admin := false
var account_admin_owner := false
var account_admin_permissions := PackedStringArray()
var account_progress: Dictionary = {}
var account_progress_saved_at := 0
var admin_roster_cache: Array = []
## Live primary-server verification is never restored from the editable local
## config file. This prevents a player from granting herself release admin by
## changing a cached boolean on disk.
var account_session_verified := false
var account_busy := false
## Account progress is one server-side JSON document. Route checkpoints and
## permanent dossier discoveries therefore share that document instead of
## racing two independent saves against each other.
var _pending_progress_save: Dictionary = {}
var _admin_ticket := ""
var _admin_ticket_room := ""
var _admin_ticket_expires_msec := 0
var _admin_ticket_permissions := PackedStringArray()

const ADMIN_PERMISSION_NAMES := [
	"hunters", "inventory", "player", "visual", "world",
]

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
## Custom skin sharing (SkinSync): uploads your skin, downloads peers' into memory.
var skin_sync: SkinSync
## Build reports, restriction status and host kick reports (docs/ANTI_CHEAT.md).
var moderation: ModerationClient


func _ready() -> void:
	offline_mode = "--offline" in OS.get_cmdline_user_args()
	_apply_loopback_override()
	skin_sync = SkinSync.new()
	add_child(skin_sync)
	moderation = ModerationClient.new()
	moderation.name = "Moderation"
	add_child(moderation)
	moderation.status_changed.connect(func(status: Dictionary) -> void:
		var message := String(status.get("message", ""))
		if not message.is_empty():
			account_changed.emit(signed_in(), account_username, account_admin, message))
	account_config_path = RunProfile.path(ACCOUNT_CONFIG_PATH)
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


## Test/dev only: `-- --backend=http://127.0.0.1:18105` points the client at a
## local backend (or, in a debug build, the TEST instance from TEST_BASE_URLS). Only those are accepted, so a shipped build can never
## be redirected to an arbitrary server this way.
func _apply_loopback_override() -> void:
	# Test-server builds (export presets "* Test Server", custom feature `test_server`) talk to the TEST instance by
	# default; `--backend=` below still overrides it. Debug templates only.
	if OS.is_debug_build() and OS.has_feature("test_server"):
		base_url = TEST_BASE_URLS[0]
		test_server_active = true
	for argument in OS.get_cmdline_user_args():
		if not String(argument).begins_with("--backend="):
			continue
		var candidate := String(argument).trim_prefix("--backend=").trim_suffix("/")
		var lowered := candidate.to_lower()
		if lowered.begins_with("http://127.0.0.1:") or lowered.begins_with("http://localhost:"):
			base_url = candidate
		elif OS.is_debug_build() and TEST_BASE_URLS.has(lowered):
			base_url = lowered
			test_server_active = true
		else:
			push_warning("ignored --backend override: only loopback origins (or the test instance in a debug build) are allowed")


## Sessions are stored per server, so signing in to the test instance never clears (or is replaced by) the main login.
func _session_section() -> String:
	return "account:" + base_url.trim_suffix("/").to_lower()


## Re-reads the stored session for the CURRENT base_url (call after changing server).
func reload_account_session() -> void:
	_load_account_session()


func configured() -> bool:
	return not _requests_suppressed_for_tests and not offline_mode


func directory_label() -> String:
	if not configured():
		return "ROOM DIRECTORY DISABLED"
	return "PRIMARY ROOM DIRECTORY"


func accounts_available() -> bool:
	return not offline_mode and (_account_transport_is_protected() \
		or base_url.trim_suffix("/").to_lower() == PRIMARY_BASE_URL.to_lower()
	)


## True when offline mode was chosen for ONE run (Create Room -> Offline). Leaving to a menu clears it (end_run_offline); a boot
## fallback or --offline stays until GO ONLINE.
var offline_for_run := false


## Create Room -> "Offline (solo, no server)": offline for this run only.
func enter_run_offline() -> void:
	if offline_mode and not offline_for_run:
		return   # already offline for the session (boot fallback / --offline): leave that to GO ONLINE
	offline_for_run = true
	enable_offline_mode()
	UpdateManager.enable_offline_mode()


## A menu is showing again: a run-scoped offline mode ends here. Returns true when it cleared (the caller re-runs the online checks).
func end_run_offline() -> bool:
	if not offline_for_run:
		return false
	offline_for_run = false
	if "--offline" in OS.get_cmdline_user_args():
		return false
	go_online()
	UpdateManager.go_online()
	return true


const OFFLINE_NOTE := "OFFLINE MODE IS ON // THE SERVER IS NOT BEING CONTACTED. GO ONLINE TO PLAY WITH FRIENDS."
const OFFLINE_JOIN_MESSAGE := "OFFLINE MODE // GO ONLINE TO JOIN ROOMS"


## Leaves offline mode without a restart (the menu's GO ONLINE): clears the flag, re-runs the health check and, when a login is
## stored, the account session check. The caller re-runs UpdateManager.check() and whatever lookup it was waiting on.
func go_online() -> void:
	offline_mode = false
	offline_for_run = false
	check_health()
	if not account_session_token.is_empty() and accounts_available() and not account_busy:
		_send_account("session", "/api/account/session", {
			"sessionToken": account_session_token,
		})


func enable_offline_mode() -> void:
	offline_mode = true
	_heartbeat.stop()
	if _host_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_host_request.cancel_request()
	if _account_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_account_request.cancel_request()
	if _admin_ticket_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_admin_ticket_request.cancel_request()
	_host_operation = ""
	_account_operation = ""
	_admin_ticket_operation = ""
	account_busy = false
	_clear_registration()


func account_transport_warning() -> String:
	if accounts_available():
		return ""
	return "ACCOUNT SIGN-IN IS DISABLED FOR THIS BACKEND ORIGIN"


func _account_transport_is_protected() -> bool:
	var origin := base_url.trim_suffix("/").to_lower()
	if origin.begins_with("https://"):
		return true
	# Debug builds may sign in to the TEST instance (plain HTTP, throwaway accounts) so a login can be tested there.
	if test_server_active and OS.is_debug_build():
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
		and account_username == account_username.strip_edges().to_upper() \
		and not account_admin_permissions.is_empty()


func admin_owner_authorized() -> bool:
	return admin_authorized() and account_admin_owner \
		and account_username in ["KYTTU", "AYTTU"]


func admin_has_permission(permission: String) -> bool:
	return admin_authorized() and permission.strip_edges().to_lower() \
		in account_admin_permissions


func admin_ticket_for_room(room_code: String) -> String:
	var clean := room_code.strip_edges().to_upper()
	if clean != _admin_ticket_room or Time.get_ticks_msec() >= _admin_ticket_expires_msec:
		return ""
	return _admin_ticket


func admin_ticket_permissions_for_room(room_code: String) -> PackedStringArray:
	return _admin_ticket_permissions.duplicate() \
		if not admin_ticket_for_room(room_code).is_empty() else PackedStringArray()


## Mint a room-bound proof after a release admin adopts the host's real room
## code. Repeated room packets are common, so a still-valid proof is reused.
func request_admin_ticket(room_code: String) -> void:
	var clean := room_code.strip_edges().to_upper()
	if not admin_authorized() or not RoomState.valid_join_code(clean):
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
			PackedStringArray(),
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
			PackedStringArray(),
			"ADMIN PROOF VERIFICATION COULD NOT START (%d)" % error)
	return request_id


func _emit_admin_ticket_verification(request_id: int, authorized: bool,
		expires_in: int, permissions: PackedStringArray, message: String) -> void:
	admin_ticket_verified.emit(request_id, authorized, expires_in, permissions,
		message)


func has_route_checkpoint() -> bool:
	return String(account_progress.get("kind", "")) == "last_route" \
		and int(account_progress.get("schema", 0)) == 1


func discovered_hunters() -> Array[String]:
	if not signed_in():
		return []
	var result: Array[String] = []
	var raw = account_progress.get("hunter_discoveries", [])
	if raw is Array:
		for value in raw:
			var hunter_id := HunterIdAliases.canonical(String(value))   # an old save may hold a pre-rename id
			if (HunterRoster.PROFILES.has(hunter_id) or SecretCreatures.has(hunter_id)) and not result.has(hunter_id):
				result.append(hunter_id)
	result.sort()
	return result


func hunter_discovered(hunter_id: String) -> bool:
	return discovered_hunters().has(HunterIdAliases.canonical(hunter_id))


## Discovery is deliberately account-only. A guest can encounter a hunter in
## the current room, but receives no permanent dossier unlock and cannot copy
## another runner's progress through ENet.
func account_discover_hunter(requested_id: String) -> bool:
	var hunter_id := HunterIdAliases.canonical(requested_id)
	if GameState.debug_run:
		return false
	if not signed_in() or not (HunterRoster.PROFILES.has(hunter_id) or SecretCreatures.has(hunter_id)):
		return false
	var discoveries := discovered_hunters()
	if discoveries.has(hunter_id):
		return false
	discoveries.append(hunter_id)
	discoveries.sort()
	var progress := account_progress.duplicate(true)
	if progress.is_empty():
		progress = {"schema": 1, "kind": "profile"}
	progress["hunter_discoveries"] = discoveries
	account_progress = progress.duplicate(true)
	account_progress_changed.emit(has_route_checkpoint(),
		account_progress.duplicate(true), account_progress_saved_at,
		"HUNTER DOSSIER ENTRY DISCOVERED")
	_queue_progress_save(progress)
	return true


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


func admin_roster_set_spec(specification: String) -> void:
	if not admin_owner_authorized():
		admin_roster_changed.emit(false, "FULL ADMIN ACCOUNT REQUIRED", [])
		return
	var parts := specification.split(":", false, 1)
	if parts.size() != 2:
		admin_roster_changed.emit(false,
			"USE USERNAME:player,world,hunters,visual,inventory", [])
		return
	var username := String(parts[0]).strip_edges().to_upper()
	var permissions := PackedStringArray()
	for value in String(parts[1]).split(",", false):
		var permission := value.strip_edges().to_lower()
		if permission in ADMIN_PERMISSION_NAMES and permission not in permissions:
			permissions.append(permission)
	if username.length() < 3 or permissions.is_empty():
		admin_roster_changed.emit(false,
			"VALID USERNAME AND AT LEAST ONE PERMISSION REQUIRED", [])
		return
	_send_account("admin_roster_set", "/api/admin/roster/set", {
		"sessionToken": account_session_token,
		"username": username,
		"permissions": Array(permissions),
	})


func admin_roster_remove(username_value: String) -> void:
	if not admin_owner_authorized():
		admin_roster_changed.emit(false, "FULL ADMIN ACCOUNT REQUIRED", [])
		return
	var username := username_value.strip_edges().to_upper()
	if username.length() < 3:
		admin_roster_changed.emit(false, "VALID USERNAME REQUIRED", [])
		return
	_send_account("admin_roster_remove", "/api/admin/roster/remove", {
		"sessionToken": account_session_token,
		"username": username,
	})


func admin_roster_refresh() -> void:
	if not admin_owner_authorized():
		admin_roster_changed.emit(false, "FULL ADMIN ACCOUNT REQUIRED", [])
		return
	_send_account("admin_roster_list", "/api/admin/roster", {
		"sessionToken": account_session_token,
	})


func admin_roster_summary() -> String:
	var parts := PackedStringArray()
	for value in admin_roster_cache:
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		var username := String(entry.get("username", ""))
		if username.is_empty():
			continue
		var access := "OWNER" if bool(entry.get("adminOwner", false)) else "+".join(
			_clean_admin_permissions(entry.get("adminPermissions", [])))
		parts.append("%s[%s]" % [username, access])
	return ", ".join(parts) if not parts.is_empty() else "NOT LOADED"


func account_logout() -> void:
	var old_token := account_session_token
	_clear_account_session()
	account_progress_changed.emit(false, {}, 0, "SIGNED OUT")
	account_changed.emit(false, "", false, "SIGNED OUT")
	if old_token.is_empty() or not accounts_available() or account_busy:
		return
	_send_account("logout", "/api/account/logout", {"sessionToken": old_token})


func account_save_progress(progress: Dictionary) -> void:
	if GameState.debug_run:
		return   # a DEBUG RUN (admin tools used) is never recorded
	if not signed_in():
		account_progress_changed.emit(has_route_checkpoint(),
			account_progress.duplicate(true), account_progress_saved_at,
			"SIGN IN TO SAVE ROUTE PROGRESS")
		return
	var merged := progress.duplicate(true)
	merged["hunter_discoveries"] = discovered_hunters()
	# other games' saves live beside the Last Route document (account_save_game_progress) and must survive its writes
	if account_progress.get("games") is Dictionary and not (account_progress["games"] as Dictionary).is_empty():
		merged["games"] = (account_progress["games"] as Dictionary).duplicate(true)
	_queue_progress_save(merged)


func account_clear_progress() -> void:
	if not signed_in():
		return
	var discoveries := discovered_hunters()
	var other_games: Dictionary = (account_progress["games"] as Dictionary).duplicate(true) \
		if account_progress.get("games") is Dictionary else {}
	if discoveries.is_empty() and other_games.is_empty():
		_send_account("save", "/api/account/save", {
			"sessionToken": account_session_token,
			"progress": null,
		})
	else:
		var profile := {"schema": 1, "kind": "profile", "hunter_discoveries": discoveries}
		if not other_games.is_empty():
			profile["games"] = other_games
		_queue_progress_save(profile)


## ---- per-game account data -------------------------------------------------------------------------------------------
## One account, one server document. Last Route's record stays where it always was (the document itself: route checkpoint
## plus hunter discoveries), so existing accounts and saves load unchanged. Every other game keeps its record under
## `games.<game_id>` in the same document; the server stores the document opaquely, so no backend change is needed.
const DEFAULT_GAME_ID := "last_route"


func game_progress(game_id: String = DEFAULT_GAME_ID) -> Dictionary:
	if game_id == DEFAULT_GAME_ID:
		return account_progress
	var games = account_progress.get("games")
	if games is Dictionary and (games as Dictionary).get(game_id) is Dictionary:
		return ((games as Dictionary)[game_id] as Dictionary).duplicate(true)
	return {}


func game_has_save(game_id: String = DEFAULT_GAME_ID) -> bool:
	if game_id == DEFAULT_GAME_ID:
		return has_route_checkpoint()
	return not game_progress(game_id).is_empty()


func account_save_game_progress(game_id: String, data: Dictionary) -> void:
	if game_id == DEFAULT_GAME_ID:
		account_save_progress(data)
		return
	if GameState.debug_run:
		return
	if not signed_in():
		return
	var document := account_progress.duplicate(true)
	if document.is_empty():
		document = {"schema": 1, "kind": "profile"}
	var games: Dictionary = (document["games"] as Dictionary).duplicate(true) if document.get("games") is Dictionary else {}
	games[game_id] = data.duplicate(true)
	document["games"] = games
	account_progress = document.duplicate(true)
	account_progress_changed.emit(has_route_checkpoint(), account_progress.duplicate(true), account_progress_saved_at,
		"%s SAVE UPDATED" % game_id.to_upper())
	_queue_progress_save(document)


func account_clear_game_progress(game_id: String) -> void:
	if game_id == DEFAULT_GAME_ID:
		account_clear_progress()
		return
	if not signed_in() or not game_has_save(game_id):
		return
	var document := account_progress.duplicate(true)
	var games: Dictionary = (document["games"] as Dictionary).duplicate(true)
	games.erase(game_id)
	if games.is_empty():
		document.erase("games")
	else:
		document["games"] = games
	account_progress = document.duplicate(true)
	account_progress_changed.emit(has_route_checkpoint(), account_progress.duplicate(true), account_progress_saved_at,
		"%s SAVE CLEARED" % game_id.to_upper())
	_queue_progress_save(document)


func _queue_progress_save(progress: Dictionary) -> void:
	if account_busy:
		_pending_progress_save = progress.duplicate(true)
		return
	_send_account("save", "/api/account/save", {
		"sessionToken": account_session_token,
		"progress": progress,
	})


func _flush_pending_progress_save() -> void:
	if account_busy or _pending_progress_save.is_empty() or not signed_in():
		return
	var progress := _pending_progress_save.duplicate(true)
	_pending_progress_save.clear()
	_queue_progress_save(progress)


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
			# Only a rejected session is forgotten. No network, a server restart or a 5xx keeps the stored token so
			# the login survives (it is verified again the next time the server answers).
			if result == HTTPRequest.RESULT_SUCCESS and response_code in SESSION_REJECTED_CODES:
				_clear_account_session()
			else:
				account_session_verified = false
		var message := String(payload.get("error", "ACCOUNT %s FAILED (HTTP %d)" % [
			operation.to_upper(), response_code]))
		if operation in ["save", "load"]:
			account_progress_changed.emit(has_route_checkpoint(),
				account_progress.duplicate(true), account_progress_saved_at, message)
		elif operation.begins_with("admin_roster_"):
			admin_roster_changed.emit(false, message, [])
		else:
			account_changed.emit(signed_in(), account_username, account_admin, message)
		return
	if operation in ["register", "login", "session"]:
		account_username = String(payload.get("username", "")).strip_edges().to_upper()
		account_session_token = String(payload.get("sessionToken", account_session_token))
		_adopt_admin_identity(payload)
		if account_username.is_empty() or account_session_token.is_empty():
			_clear_account_session()
			account_changed.emit(false, "", false, "PRIMARY SERVER RETURNED AN INVALID ACCOUNT")
			return
		account_session_verified = true
		_save_account_session()
		moderation.report_integrity("signin")
		_adopt_account_progress(payload,
			"ROUTE CHECKPOINT LOADED" if payload.get("progress") is Dictionary \
			else "NO ROUTE CHECKPOINT")
		account_changed.emit(true, account_username, account_admin,
			"SIGNED IN AS %s" % account_username)
		if account_admin_owner:
			call_deferred("admin_roster_refresh")
	elif operation in ["save", "load"]:
		_adopt_account_progress(payload,
			"ROUTE CHECKPOINT SAVED" if operation == "save" \
				and payload.get("progress") is Dictionary \
			else "ROUTE CHECKPOINT CLEARED" if operation == "save" \
			else "ROUTE CHECKPOINT LOADED")
	elif operation == "rename":
		account_username = String(payload.get("username", account_username)) \
			.strip_edges().to_upper()
		_adopt_admin_identity(payload)
		account_session_verified = not account_username.is_empty() \
			and not account_session_token.is_empty()
		_save_account_session()
		account_changed.emit(signed_in(), account_username, account_admin,
			"ACCOUNT RENAMED TO %s" % account_username)
	elif operation == "password":
		account_changed.emit(signed_in(), account_username, account_admin,
			"ACCOUNT PASSWORD UPDATED")
	elif operation in ["admin_roster_set", "admin_roster_remove", "admin_roster_list"]:
		if operation == "admin_roster_list":
			admin_roster_cache = (payload.get("roster", []) as Array).duplicate(true) \
				if payload.get("roster", []) is Array else []
		elif operation == "admin_roster_set" and payload.get("entry", {}) is Dictionary:
			var updated: Dictionary = (payload.get("entry", {}) as Dictionary).duplicate(true)
			var updated_username := String(updated.get("username", ""))
			admin_roster_cache = admin_roster_cache.filter(func(value) -> bool:
				return value is Dictionary \
					and String((value as Dictionary).get("username", "")) != updated_username)
			admin_roster_cache.append(updated)
		elif operation == "admin_roster_remove":
			var removed_username := String(payload.get("username", ""))
			admin_roster_cache = admin_roster_cache.filter(func(value) -> bool:
				return value is Dictionary \
					and String((value as Dictionary).get("username", "")) != removed_username)
		admin_roster_cache.sort_custom(func(a, b) -> bool:
			return String((a as Dictionary).get("username", "")) \
				< String((b as Dictionary).get("username", "")))
		var roster: Array = admin_roster_cache.duplicate(true)
		var message := "ADMIN ROSTER UPDATED"
		if operation == "admin_roster_list":
			message = "ADMIN ROSTER LOADED"
		elif operation == "admin_roster_remove":
			message = "ADMIN ACCESS REMOVED // %s" % String(payload.get("username", ""))
		elif payload.get("entry", {}) is Dictionary:
			message = "ADMIN ACCESS UPDATED // %s" % String(
				(payload.get("entry", {}) as Dictionary).get("username", ""))
		admin_roster_changed.emit(true, message, roster)
	if not _pending_progress_save.is_empty():
		call_deferred("_flush_pending_progress_save")


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
	if ticket.length() != 43 or not RoomState.valid_join_code(room_code):
		_clear_admin_ticket()
		admin_ticket_changed.emit(false, room_code,
			"PRIMARY SERVER RETURNED AN INVALID ADMIN PROOF")
		return
	_admin_ticket = ticket
	_admin_ticket_room = room_code
	_admin_ticket_expires_msec = Time.get_ticks_msec() + expires_in * 1000
	_admin_ticket_permissions = _clean_admin_permissions(payload.get("permissions", []))
	if _admin_ticket_permissions.is_empty():
		_clear_admin_ticket()
		admin_ticket_changed.emit(false, room_code,
			"PRIMARY SERVER RETURNED AN EMPTY ADMIN PERMISSION SET")
		return
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
	var permissions := _clean_admin_permissions(payload.get("permissions", [])) \
		if authorized else PackedStringArray()
	authorized = authorized and not permissions.is_empty()
	admin_ticket_verified.emit(request_id, authorized, expires_in, permissions,
		"ADMIN ROOM PROOF VERIFIED" if authorized else String(payload.get("error",
			"ADMIN ROOM PROOF REJECTED")))


func _clean_admin_permissions(value) -> PackedStringArray:
	var result := PackedStringArray()
	if value is Array or value is PackedStringArray:
		for entry in value:
			var permission := String(entry).strip_edges().to_lower()
			if permission in ADMIN_PERMISSION_NAMES and permission not in result:
				result.append(permission)
	return result


func _adopt_admin_identity(payload: Dictionary) -> void:
	account_admin_permissions = _clean_admin_permissions(
		payload.get("adminPermissions", []))
	var canonical_owner := account_username in ["KYTTU", "AYTTU"]
	# Backward compatibility for an authenticated session served during a
	# rolling backend deployment. Older account responses proved these same two
	# reserved accounts with `admin: true`, but did not yet include the owner or
	# scoped-permission fields. Never apply this migration to another username
	# or to an unverified/local cached session.
	var legacy_owner := canonical_owner and bool(payload.get("admin", false)) \
		and not payload.has("adminOwner") and not payload.has("adminPermissions")
	account_admin_owner = canonical_owner \
		and (bool(payload.get("adminOwner", false)) or legacy_owner)
	if account_admin_owner and account_admin_permissions.is_empty():
		account_admin_permissions = PackedStringArray(ADMIN_PERMISSION_NAMES)
	account_admin = bool(payload.get("admin", false)) \
		and not account_admin_permissions.is_empty()


func _adopt_account_progress(payload: Dictionary, message: String) -> void:
	var value = payload.get("progress")
	account_progress = value.duplicate(true) if value is Dictionary else {}
	account_progress_saved_at = int(payload.get("savedAt", 0))
	account_progress_changed.emit(has_route_checkpoint(),
		account_progress.duplicate(true), account_progress_saved_at, message)


func _load_account_session() -> void:
	var config := ConfigFile.new()
	if config.load(account_config_path) != OK:
		return
	var section := _session_section()
	if not config.has_section(section) and base_url.trim_suffix("/").to_lower() == PRIMARY_BASE_URL.to_lower():
		section = "account"   # sessions saved before they were per server belong to the main server
	account_username = String(config.get_value(section, "username", "")).strip_edges().to_upper()
	account_session_token = String(config.get_value(section, "session_token", ""))
	account_admin = false
	account_admin_owner = false
	account_admin_permissions = PackedStringArray()
	account_session_verified = false


func _save_account_session() -> void:
	var config := ConfigFile.new()
	config.load(account_config_path)   # keep the other servers' sessions
	config.set_value(_session_section(), "username", account_username)
	config.set_value(_session_section(), "session_token", account_session_token)
	config.save(account_config_path)


func _clear_account_session() -> void:
	account_username = ""
	account_session_token = ""
	account_admin = false
	account_admin_owner = false
	account_admin_permissions = PackedStringArray()
	account_session_verified = false
	account_progress = {}
	account_progress_saved_at = 0
	admin_roster_cache.clear()
	_pending_progress_save.clear()
	_clear_admin_ticket()
	var config := ConfigFile.new()
	config.load(account_config_path)
	config.set_value(_session_section(), "username", "")
	config.set_value(_session_section(), "session_token", "")
	if base_url.trim_suffix("/").to_lower() == PRIMARY_BASE_URL.to_lower() and config.has_section("account"):
		config.set_value("account", "username", "")
		config.set_value("account", "session_token", "")
	config.save(account_config_path)


func _clear_admin_ticket() -> void:
	_admin_ticket = ""
	_admin_ticket_room = ""
	_admin_ticket_expires_msec = 0
	_admin_ticket_permissions = PackedStringArray()


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
		"daytime": RoomState.is_day(),
		"game": RoomState.game_id(),
		# moderation (docs/ANTI_CHEAT.md): who hosts, so kick reports count per host and flagged accounts can't host public
		"sessionToken": account_session_token,
		"deviceId": moderation.device_id(),
		"roomPassword": room_password,   # only a reserved code needs it
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


## Room closes (explicit "host left") still on their way to the server; quitting waits briefly for them.
var _unregister_in_flight := 0


func room_close_pending() -> bool:
	return _unregister_in_flight > 0


## Quit path: give the explicit room close a moment to leave the machine (up to `timeout` seconds) before the process ends.
func wait_for_room_close(timeout: float = 1.5) -> void:
	var waited := 0.0
	while _unregister_in_flight > 0 and waited < timeout and is_inside_tree():
		await get_tree().create_timer(0.05, true, false, true).timeout
		waited += 0.05


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
	_unregister_in_flight += 1
	request.request_completed.connect(func(_result: int, _code: int,
			_headers: PackedStringArray, _body: PackedByteArray) -> void:
		_unregister_in_flight = maxi(0, _unregister_in_flight - 1)
		request.queue_free())
	request.request(_url("/api/enet/rooms/unregister"), _headers(),
		HTTPClient.METHOD_POST, JSON.stringify({
			"code": registered_code,
			"token": _token,
		}))
	_clear_registration()


func resolve_room(code: String) -> void:
	var clean := code.strip_edges().to_upper()
	if offline_mode:
		room_resolved.emit(clean, {}, OFFLINE_JOIN_MESSAGE)
		return
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
		"daytime": RoomState.is_day(),
		"commandSince": _reserved_seen,
		"commandAck": _reserved_ack,
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
	_take_reserved(payload.get("reserved"), operation == "register")
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


## The register/heartbeat answer for a reserved room: its stored settings, and owner commands not seen yet.
func _take_reserved(reserved, fresh_registration: bool) -> void:
	if not reserved is Dictionary:
		if fresh_registration:
			reserved_settings = {}
		return
	if fresh_registration:
		_reserved_seen = 0
		_reserved_ack = 0
	reserved_settings = reserved.get("settings", {}) if reserved.get("settings", {}) is Dictionary else {}
	var fresh := []
	for entry in reserved.get("commands", []):
		if entry is Dictionary and int(entry.get("seq", 0)) > _reserved_seen:
			fresh.append(entry)
			_reserved_seen = maxi(_reserved_seen, int(entry.get("seq", 0)))
	if not fresh.is_empty():
		reserved_commands_received.emit(fresh)


## The host carried out owner command `seq`; the next heartbeat tells the server so it stops sending it.
func ack_reserved_command(seq: int) -> void:
	_reserved_ack = maxi(_reserved_ack, seq)


func is_reserved_host() -> bool:
	return registered and not reserved_settings.is_empty()


## A reserved code: ask with this account (invite list) and the typed room password.
func _resolve_reserved(code: String) -> void:
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(func(result: int, response_code: int, _headers_value: PackedStringArray,
			body: PackedByteArray) -> void:
		request.queue_free()
		var payload := _parse_body(body)
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			var message := String(payload.get("error", "PRIVATE ROOM %s // ACCESS REQUIRED" % code))
			reserved_room_access_needed.emit(code, message)
			room_resolved.emit(code, {}, message)
			return
		if bool(payload.get("canHost", false)):
			var settings = payload.get("settings", {})
			reserved_room_hostable.emit(code, settings if settings is Dictionary else {})
			return
		reserved_join_ticket = String(payload.get("joinTicket", ""))
		reserved_join_code = code
		var room = payload.get("room", {})
		room_resolved.emit(code, room if room is Dictionary else {}, "" if room is Dictionary else "PRIVATE ROOM RETURNED NO ENDPOINT"))
	if request.request(_url("/api/rooms/reserved/resolve"), _headers(), HTTPClient.METHOD_POST,
			JSON.stringify({"code": code, "sessionToken": account_session_token, "password": room_password})) != OK:
		request.queue_free()
		room_resolved.emit(code, {}, "COULD NOT START PRIVATE ROOM LOOKUP")


## The relay ticket for joining `code`, used once.
func take_join_ticket(code: String) -> String:
	if reserved_join_code != code:
		return ""
	var ticket := reserved_join_ticket
	reserved_join_ticket = ""
	reserved_join_code = ""
	return ticket


## Owner: queue a command (restart, end, kick, settings, transfer) on a reserved room; whoever hosts it carries it out.
signal reserved_command_sent(ok: bool, message: String)


func send_reserved_command(code: String, command: String, args: Dictionary = {}) -> void:
	var body := {"sessionToken": account_session_token, "action": "command", "code": code, "command": command}
	body.merge(args)
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(func(result: int, response_code: int, _headers_value: PackedStringArray,
			response_body: PackedByteArray) -> void:
		request.queue_free()
		var payload := _parse_body(response_body)
		var ok := result == HTTPRequest.RESULT_SUCCESS and response_code == 202
		reserved_command_sent.emit(ok, "PRIVATE ROOM // %s QUEUED" % command.to_upper() if ok
			else String(payload.get("error", "PRIVATE ROOM COMMAND FAILED (HTTP %d)" % response_code))))
	if request.request(_url("/api/admin/reserved-rooms"), _headers(), HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		request.queue_free()
		reserved_command_sent.emit(false, "COULD NOT SEND PRIVATE ROOM COMMAND")


## Owner: add / remove / list one account on a reserved room's whitelist; `done` gets (ok, whitelist, message).
func reserved_whitelist(code: String, op: String, name: String, done: Callable) -> void:
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(func(result: int, response_code: int, _headers_value: PackedStringArray,
			response_body: PackedByteArray) -> void:
		request.queue_free()
		var payload := _parse_body(response_body)
		var ok := result == HTTPRequest.RESULT_SUCCESS and response_code == 200
		done.call(ok, payload.get("whitelist", []) if ok else [], "" if ok else String(payload.get("error", "WHITELIST FAILED"))))
	if request.request(_url("/api/admin/reserved-rooms"), _headers(), HTTPClient.METHOD_POST, JSON.stringify({
			"sessionToken": account_session_token, "action": "whitelist", "code": code, "op": op, "name": name})) != OK:
		request.queue_free()
		done.call(false, [], "COULD NOT REACH THE ROOM DIRECTORY")


## Hand the room to the next player: the relay promotes the longest-connected guest (host migration).
func release_host() -> void:
	if not registered or _token.is_empty():
		return
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		request.queue_free())
	request.request(_url("/api/enet/rooms/release-host"), _headers(), HTTPClient.METHOD_POST,
		JSON.stringify({"code": registered_code, "token": _token}))


func _on_resolve_response(result: int, response_code: int,
		_headers_value: PackedStringArray, body: PackedByteArray,
		request: HTTPRequest, code: String) -> void:
	request.queue_free()
	var payload := _parse_body(body)
	if response_code == 403 and String(payload.get("code", "")) == "ROOM_RESERVED":
		_resolve_reserved(code)
		return
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


## An empty or non-JSON body (offline, a proxy error page) is just "no payload": JSON.parse_string would log
## "Parse JSON failed" for it, so parse with a JSON object, which reports the error to us instead.
func _parse_body(body: PackedByteArray) -> Dictionary:
	var text := body.get_string_from_utf8().strip_edges()
	if text.is_empty() or not (text.begins_with("{") or text.begins_with("[")):
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	return json.data if json.data is Dictionary else {}


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
