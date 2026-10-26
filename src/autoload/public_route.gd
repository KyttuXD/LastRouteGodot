extends Node

## The persistent PUBLIC route: one always-open, server-owned room anyone joins
## straight from the title screen (no lobby, no host choice).
##
## Division of labour:
##   * The Node backend owns what must outlive any one host: the world seed, the
##     claimed relays/items (items respawn on a timer), the last hunter snapshot,
##     each player's resume record, the UTC day and the player-scaled hunter
##     target (backend/public_route.mjs).
##   * Whoever registers ENet room code PUBLIC first is the authority: it runs the
##     same host-authoritative route as a private room and posts snapshots and
##     claims to the backend. Everyone else joins that room as a guest. If the
##     authority vanishes its listing lapses and the next client to ask becomes
##     the authority, restoring the route from the backend's copy.
##   * Every client posts its own position and inventory about once a second, so
##     a crash, reload or host handoff resumes where the runner stood.

signal status_changed(message: String)

const TICK_SECONDS := 1.0
const SNAPSHOT_SECONDS := 6.0
const JOIN_RETRY_MSEC := 2500
const PLAYER_KEY_PATH := "user://public_player.cfg"
const HOST_PORT := 8421

var active := false
var is_authority := false
var session_id := ""
var player_key := ""
var status := ""
## Last status payload from the backend.
var server := {}
var resume := {}
var claimed_ids: Array = []
var snapshot_b64 := ""
var join_grace_until_msec := 0

var _timer: Timer
var _scene: Node
var _posted_claims := {}
var _last_snapshot_msec := 0
var _busy := false
var _join_attempt_after_msec := 0
var _joining := false


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = TICK_SECONDS
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_load_player_key()


func _load_player_key() -> void:
	var config := ConfigFile.new()
	if config.load(PLAYER_KEY_PATH) == OK:
		player_key = String(config.get_value("public", "player_key", ""))
	if player_key.length() < 16:
		var crypto := Crypto.new()
		player_key = crypto.generate_random_bytes(12).hex_encode()
		config.set_value("public", "player_key", player_key)
		config.save(PLAYER_KEY_PATH)


## A second client on one machine (tests) needs its own identity.
func use_player_key(key: String) -> void:
	player_key = key


func _set_status(message: String) -> void:
	status = message
	status_changed.emit(message)


func line() -> String:
	if not active:
		return ""
	return "PUBLIC ROUTE // %d ONLINE // %d RELAYS" % [
		int(server.get("playersOnline", 1)), int(server.get("relaysCollected", 0))]


func in_join_grace() -> bool:
	return active and Time.get_ticks_msec() < join_grace_until_msec


func hunter_target_count() -> int:
	return clampi(int(server.get("hunterTargetCount", 1)), 1, PublicRoster.CAP)


# -- joining -----------------------------------------------------------------------

## Entry point for the title screen's PUBLIC button (and for automatic rejoin).
func join() -> void:
	if _joining or Backend.offline_mode or not Backend.configured():
		if Backend.offline_mode or not Backend.configured():
			_set_status("PUBLIC ROUTE NEEDS THE PRIMARY SERVER")
		return
	_joining = true
	active = true
	_set_status("CONTACTING PUBLIC ROUTE")
	_request("/api/public/join", {"playerKey": player_key,
		"name": RoomState.local_display_name()}, _on_join)


func _on_join(ok: bool, body: Dictionary) -> void:
	_joining = false
	if not ok:
		_set_status("PUBLIC ROUTE UNAVAILABLE // %s" % String(body.get("error", "TRY AGAIN")))
		if active and RoomState.public_route:
			_retry_join_later()
		else:
			active = false
		return
	server = body
	session_id = String(body.get("sessionId", ""))
	resume = body.get("resume", {}) if body.get("resume") is Dictionary else {}
	claimed_ids = body.get("claimed", []) if body.get("claimed") is Array else []
	snapshot_b64 = String(body.get("snapshot", ""))
	join_grace_until_msec = Time.get_ticks_msec() + int(body.get("joinGraceMs", 10000))
	_posted_claims.clear()
	for id in claimed_ids:
		_posted_claims[String(id)] = true
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.public_route = true
	RoomState.code = RoomState.PUBLIC_CODE
	RoomState.seed_text = String(body.get("seed", "PUBLIC-ROUTE"))
	RoomState.set_map_scale(RoomState.Scale.INFINITE)
	RoomState.difficulty = RoomState.Difficulty.STANDARD
	is_authority = false
	if bool(body.get("authorityLive", false)):
		_become_guest()
	else:
		_become_host()


func _become_host() -> void:
	_set_status("PUBLIC ROUTE // OPENING THE ROUTE")
	var error := RoomState.host_room(HOST_PORT)
	if not error.is_empty():
		_set_status(error)
		_become_guest()
		return
	if not Backend.registration_changed.is_connected(_on_registration):
		Backend.registration_changed.connect(_on_registration)


func _on_registration(listed: bool, message: String) -> void:
	if not RoomState.public_route or not RoomState.is_host or is_authority:
		return
	if listed:
		is_authority = true
		_set_status("PUBLIC ROUTE // YOU ARE HOLDING THE ROUTE")
		RoomState.enter(get_tree())
		_timer.start()
	else:
		# Someone registered first (409) or the listing failed: join them instead.
		RoomState.leave_network()
		RoomState.public_route = true
		RoomState.code = RoomState.PUBLIC_CODE
		_set_status("PUBLIC ROUTE // JOINING THE LIVE ROUTE (%s)" % message)
		_become_guest()


func _become_guest() -> void:
	if not Backend.room_resolved.is_connected(_on_resolved):
		Backend.room_resolved.connect(_on_resolved)
	Backend.resolve_room(RoomState.PUBLIC_CODE)


func _on_resolved(resolved_code: String, endpoint: Dictionary, error: String) -> void:
	if resolved_code != RoomState.PUBLIC_CODE or not RoomState.public_route or is_authority:
		return
	if RoomState.online or RoomState.connecting:
		return
	if not error.is_empty():
		# The authority's listing lapsed between the two calls: start over.
		_set_status("PUBLIC ROUTE // NO LIVE ROUTE YET, RETRYING")
		_retry_join_later()
		return
	var join_error := RoomState.join_room(String(endpoint.get("address", "")),
		int(endpoint.get("port", 0)), String(endpoint.get("transport", "relay")),
		RoomState.PUBLIC_CODE)
	if not join_error.is_empty():
		_set_status(join_error)
		_retry_join_later()
		return
	_set_status("PUBLIC ROUTE // JOINING")
	_timer.start()


func _retry_join_later() -> void:
	_join_attempt_after_msec = Time.get_ticks_msec() + JOIN_RETRY_MSEC
	_timer.start()


## RoomState calls this when its connection to the authority is gone for good
## (reconnect grace expired). In a private room that returns to staging; on the
## PUBLIC route the player simply joins again, possibly as the new authority.
func on_connection_lost() -> void:
	if not active:
		return
	is_authority = false
	_scene = null
	_retry_join_later()
	_set_status("PUBLIC ROUTE // HOST SIGNAL LOST, REJOINING")


func leave() -> void:
	if not active:
		return
	if not session_id.is_empty():
		_request("/api/public/leave", {"sessionId": session_id}, func(_ok: bool, _b: Dictionary) -> void: pass)
	active = false
	is_authority = false
	session_id = ""
	_scene = null
	_timer.stop()
	RoomState.public_route = false


# -- the route scene hooks in ---------------------------------------------------------

func attach_scene(scene: Node) -> void:
	_scene = scene
	_last_snapshot_msec = 0
	_timer.start()


func decode_snapshot() -> Dictionary:
	if snapshot_b64.is_empty():
		return {}
	var decoded = bytes_to_var(Marshalls.base64_to_raw(snapshot_b64))
	return decoded if decoded is Dictionary else {}


# -- periodic state post ----------------------------------------------------------------

func _tick() -> void:
	var now := Time.get_ticks_msec()
	if not active:
		_timer.stop()
		return
	if _join_attempt_after_msec > 0 and now >= _join_attempt_after_msec and not _joining \
			and not RoomState.online and not RoomState.connecting:
		_join_attempt_after_msec = 0
		_joining = false
		join()
		return
	if session_id.is_empty() and _scene != null and is_instance_valid(_scene) and not _joining \
			and now >= _join_attempt_after_msec:
		_refresh_session()
		return
	if _scene == null or not is_instance_valid(_scene) or session_id.is_empty() or _busy:
		return
	var player: Node3D = _scene.get("player")
	if player == null:
		return
	var body := {"sessionId": session_id,
		"position": {"x": player.global_position.x, "z": player.global_position.z},
		"inventory": _inventory_entries(player), "name": RoomState.local_display_name()}
	if is_authority:
		body["hostToken"] = Backend.host_token()
		body["claims"] = _new_claims()
		if now - _last_snapshot_msec >= int(SNAPSHOT_SECONDS * 1000.0):
			_last_snapshot_msec = now
			var snapshot: Dictionary = _scene.call("_build_stream_snapshot")
			body["snapshot"] = Marshalls.raw_to_base64(var_to_bytes(snapshot))
	_busy = true
	_request("/api/public/state", body, _on_state)


func _inventory_entries(player: Node3D) -> Array:
	var entries: Array = []
	var order: Array = player.get("inventory_order")
	var durability: Array = player.get("inventory_slot_durability")
	for slot in mini(order.size(), 24):
		var id := String(order[slot])
		if id.is_empty():
			continue
		entries.append({"id": id, "durability": int(durability[slot]) if slot < durability.size() else 0, "slot": slot})
	return entries


func _new_claims() -> Array:
	var fresh: Array = []
	var world_state: Object = _scene.get("world_state")
	for id_value in world_state.claimed_pickups:
		var id := String(id_value)
		if not _posted_claims.has(id) and fresh.size() < 100:
			_posted_claims[id] = true
			fresh.append({"id": id})
	return fresh


## The backend forgot this session (it restarted, or we stalled past the TTL) while
## the route is running: take a new session id without touching the live route.
func _refresh_session() -> void:
	_joining = true
	_request("/api/public/join", {"playerKey": player_key,
		"name": RoomState.local_display_name()}, func(ok: bool, body: Dictionary) -> void:
		_joining = false
		if ok:
			session_id = String(body.get("sessionId", ""))
			server = body
			# a restarted backend may know claims we have not re-posted
			_posted_claims.clear()
			for id in body.get("claimed", []):
				_posted_claims[String(id)] = true
		else:
			_join_attempt_after_msec = Time.get_ticks_msec() + 2000)


func _on_state(ok: bool, body: Dictionary) -> void:
	_busy = false
	if not ok:
		if String(body.get("error", "")).begins_with("UNKNOWN SESSION"):
			session_id = ""
			_join_attempt_after_msec = Time.get_ticks_msec() + 500
		return
	server = body
	var respawned: Array = body.get("respawned", []) if body.get("respawned") is Array else []
	if is_authority and not respawned.is_empty() and _scene != null and is_instance_valid(_scene):
		for id in respawned:
			_posted_claims.erase(String(id))
		_scene.call("apply_public_respawns", respawned)


# -- HTTP -----------------------------------------------------------------------------------

func _request(path: String, payload: Dictionary, done: Callable) -> void:
	var request := HTTPRequest.new()
	request.timeout = 8.0
	add_child(request)
	request.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, raw: PackedByteArray) -> void:
		request.queue_free()
		var parsed = JSON.parse_string(raw.get_string_from_utf8())
		var body: Dictionary = parsed if parsed is Dictionary else {}
		done.call(result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300, body))
	var error := request.request(Backend.base_url + path,
		PackedStringArray(["Content-Type: application/json", "Accept: application/json"]),
		HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		request.queue_free()
		done.call(false, {"error": "COULD NOT REACH THE PRIMARY SERVER"})
