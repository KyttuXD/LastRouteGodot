extends Node

## Two-process ENet smoke check. This complements validate_sync.gd: that suite
## exercises gameplay state deeply in one process, while this small scene proves
## the actual transport handshake and autoload RPC path work between processes.
##
## Run the host, then the client in a second shell:
##   godot4 --headless --path . res://tests/scenes/enet_smoke.tscn -- host
##   godot4 --headless --path . res://tests/scenes/enet_smoke.tscn -- client
## Add `relay http://127.0.0.1:18105` after the role to exercise the complete
## HTTP directory + UDP relay path against a local backend.

const PORT := 18421
const TIMEOUT_SECONDS := 8.0
const RELAY_ROOM_CODE := "ABCDE"
const ACCOUNT_CLIENT_NAME := "ACCOUNT_CLIENT"

var _client_waiting_for_start := false
var _remotes: RemotePlayers
var _host_received_interaction := false
var _host_received_admin := false
var _host_received_stream := false
var _client_received_effect := false
var _client_received_snapshot := false
var _client_received_hunters := false
var _client_received_stream_event := false
var _relay_mode := false
var _resolved := false
var _resolved_endpoint := {}
var _resolve_error := ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not ["host", "client"].has(args[0]):
		_finish(false, "usage: enet_smoke.tscn -- host|client [relay BACKEND_URL]")
		return
	_relay_mode = args.size() >= 2 and args[1] == "relay"
	if _relay_mode:
		if args.size() < 3:
			_finish(false, "relay smoke needs its local backend URL")
			return
		Backend.use_test_base_url(args[2])
	else:
		# The ordinary local handshake does not publish a production throwaway.
		Backend.suppress_requests_for_tests()
	RoomState.suppress_scene_transitions_for_tests()
	if args[0] == "host":
		await _run_host()
	else:
		await _run_client()


func _run_host() -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	if _relay_mode:
		RoomState.code = RELAY_ROOM_CODE
		RoomState.reroll_seed()
	RoomState.set_map_scale(RoomState.Scale.INFINITE)
	var error := RoomState.host_room(PORT)
	if not error.is_empty():
		_finish(false, error)
		return
	_install_replication(Vector3(1, 0, 1))
	var joined := await _wait_for(func() -> bool:
		return RoomState.roster().size() == 2)
	if not joined:
		_finish(false, "host never received the client roster")
		return
	var registered := await _wait_for(func() -> bool:
		for id in RoomState.peers:
			if int(id) > 1 and String(RoomState.peers[id]) == ACCOUNT_CLIENT_NAME:
				return true
		return false)
	if not registered:
		_finish(false, "client callsign registration RPC never reached the host")
		return
	if not await _wait_for(func() -> bool: return _remotes.count() == 1):
		_finish(false, "host never instantiated the client's replicated body")
		return
	print("ENET HOST OK // room %s // %d signals" % [RoomState.code,
		RoomState.roster().size()])
	print("ENET HOST BODY OK // remote transform RPC received")
	var client_id := -1
	for id in RoomState.peers:
		if int(id) > 1:
			client_id = int(id)
			break
	if client_id < 0:
		_finish(false, "host could not identify the joined peer")
		return
	_remotes.send_player_event(client_id, {"what": "smoke_effect", "value": 37})
	_remotes.broadcast_hunters([{"entity_id": "SMOKE:HUNTER", "active": true}])
	_remotes.relay_world_event({"what": "stream_safe", "room_id": "SMOKE:SAFE",
		"integrity": 73, "breached": false})
	if not await _wait_for(func() -> bool:
		return _host_received_interaction and _host_received_admin \
			and _host_received_stream):
		_finish(false, "guest fixed/streamed/admin requests never reached host authority")
		return
	print("ENET HOST AUTHORITY OK // fixed, streamed and admin requests received")
	# Exercise the same authority RPC RoomState.enter() uses without replacing
	# this smoke-test scene on the host. The client's changed signal verifies the
	# synchronized start before its deferred scene transition can remove it.
	await get_tree().create_timer(0.25).timeout
	RoomState._receive_start.rpc(RoomState.code, RoomState.seed_text,
		RoomState.mode, RoomState.map_scale, RoomState.difficulty)
	print("ENET HOST START OK // synchronized route launch sent")
	if not await _wait_for(func() -> bool: return RoomState.roster().size() == 1):
		_finish(false, "guest leave did not remove the host roster row immediately")
		return
	print("ENET HOST LEAVE OK // guest roster row removed immediately")
	RoomState.leave_network()
	get_tree().quit(0)


func _run_client() -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var local_code := RoomState.code
	# Reproduce account verification completing after the startup room already
	# generated an anonymous callsign.
	Backend.account_username = ACCOUNT_CLIENT_NAME
	Backend.account_session_token = "smoke-account-session"
	Backend.account_session_verified = true
	RoomState._on_account_changed(true, ACCOUNT_CLIENT_NAME, false, "")
	_client_waiting_for_start = true
	RoomState.changed.connect(_on_client_room_changed)
	var error := ""
	if _relay_mode:
		Backend.room_resolved.connect(_on_relay_room_resolved)
		Backend.resolve_room(RELAY_ROOM_CODE)
		if not await _wait_for(func() -> bool: return _resolved):
			_finish(false, "relay room lookup timed out")
			return
		if not _resolve_error.is_empty():
			_finish(false, _resolve_error)
			return
		error = RoomState.join_room(String(_resolved_endpoint.get("address", "")),
			int(_resolved_endpoint.get("port", 0)),
			String(_resolved_endpoint.get("transport", "")), RELAY_ROOM_CODE)
	else:
		error = RoomState.join_room(RoomState.DEFAULT_ADDRESS, PORT)
	if not error.is_empty():
		_finish(false, error)
		return
	_install_replication(Vector3(3, 0, 3))
	var synchronized := await _wait_for(func() -> bool:
		return (RoomState.online and RoomState.roster().size() == 2
			and RoomState.map_scale == RoomState.Scale.INFINITE))
	if not synchronized:
		_finish(false, "client never received the host room/configuration")
		return
	if RoomState.code == local_code:
		_finish(false, "client kept its local room instead of adopting the host room")
		return
	if not await _wait_for(func() -> bool: return _remotes.count() == 1):
		_finish(false, "client never instantiated the host's replicated body")
		return
	print("ENET CLIENT OK // room %s // %d signals" % [RoomState.code,
		RoomState.roster().size()])
	_remotes.request_interaction({"what": "music_box"})
	_remotes.request_interaction({"what": "admin_world", "action": "rebuild"})
	_remotes.request_interaction({"what": "stream_pickup",
		"entity_id": "0:0:0:PICKUP:TOOL:0", "kind": "tool",
		"item": "flashlight"})
	if not await _wait_for(func() -> bool:
		return _client_received_effect and _client_received_snapshot \
			and _client_received_hunters and _client_received_stream_event):
		_finish(false, "Infinite authority packets or snapshot never reached the guest")
		return
	print("ENET CLIENT AUTHORITY OK // targeted effect received")
	print("ENET CLIENT SNAPSHOT OK // transferable floor payload received")
	# _on_client_room_changed quits on the host's start RPC. Staying alive here
	# also gives the reliable callsign registration time to reach the host.
	await get_tree().create_timer(TIMEOUT_SECONDS).timeout
	if _client_waiting_for_start:
		_finish(false, "client never received the synchronized route start")


func _on_relay_room_resolved(_code: String, endpoint: Dictionary, error: String) -> void:
	_resolved_endpoint = endpoint
	_resolve_error = error
	_resolved = true


func _on_client_room_changed() -> void:
	if not _client_waiting_for_start or not RoomState.session_active:
		return
	if not RoomState.online or RoomState.map_scale != RoomState.Scale.INFINITE:
		_finish(false, "route start arrived before the host room configuration")
		return
	_client_waiting_for_start = false
	print("ENET CLIENT START OK // synchronized route launch received")
	RoomState.leave_network()
	get_tree().quit(0)


func _wait_for(check: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + int(TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if check.call():
			return true
		await get_tree().create_timer(0.05).timeout
	return false


func _install_replication(at: Vector3) -> void:
	var local := Node3D.new()
	local.name = "LocalPlayer"
	local.position = at
	add_child(local)
	_remotes = RemotePlayers.new()
	_remotes.name = "RemotePlayers"
	_remotes.local_player = local
	_remotes.snapshot_source = _smoke_snapshot
	_remotes.interaction_requested.connect(_on_smoke_interaction)
	_remotes.player_event.connect(func(event: Dictionary) -> void:
		if String(event.get("what", "")) == "smoke_effect" \
				and int(event.get("value", 0)) == 37:
			_client_received_effect = true)
	_remotes.hunters_received.connect(func(data: Array) -> void:
		if data.size() == 1 and String(data[0].get("entity_id", "")) \
				== "SMOKE:HUNTER":
			_client_received_hunters = true)
	_remotes.world_event.connect(func(event: Dictionary) -> void:
		if String(event.get("what", "")) == "stream_safe" \
				and int(event.get("integrity", 0)) == 73:
			_client_received_stream_event = true)
	_remotes.world_snapshot.connect(func(state: Dictionary) -> void:
		var payload = state.get("custom_map_png", PackedByteArray())
		var fragment_probe = state.get("fragment_probe", PackedByteArray())
		var image := Image.new()
		var decoded: bool = payload is PackedByteArray and not payload.is_empty() \
			and image.load_png_from_buffer(payload) == OK
		var parsed: Dictionary = CustomMapParser.parse(image) if decoded else {"ok": false}
		if int(state.get("marker", 0)) == 91 \
				and int(state.get("snapshot_protocol", 0)) == 2 \
				and parsed.get("ok", false) and parsed.get("cols", 0) == 49 \
				and parsed.get("rows", 0) == 49 \
				and parsed.get("start", Vector2i(-1, -1)) == Vector2i(24, 24) \
				and fragment_probe is PackedByteArray \
				and fragment_probe.size() == 65536 and fragment_probe[0] == 0xA5 \
				and fragment_probe[fragment_probe.size() - 1] == 0xA5:
			_client_received_snapshot = true
			_remotes.confirm_snapshot_applied())
	add_child(_remotes)


func _on_smoke_interaction(peer_id: int, event: Dictionary) -> void:
	if peer_id <= 1:
		return
	match String(event.get("what", "")):
		"music_box":
			_host_received_interaction = true
		"admin_world":
			_host_received_admin = String(event.get("action", "")) == "rebuild"
		"stream_pickup":
			_host_received_stream = String(event.get("entity_id", "")) \
				== "0:0:0:PICKUP:TOOL:0"


func _smoke_snapshot() -> Dictionary:
	var fragment_probe := PackedByteArray()
	fragment_probe.resize(65536)
	fragment_probe.fill(0xA5)
	return {
		"marker": 91,
		"snapshot_protocol": 2,
		"floor_source": "custom",
		"custom_map_png": FileAccess.get_file_as_bytes(
			"res://assets/custom_maps/test-map.png"),
		"fragment_probe": fragment_probe,
	}


func _finish(ok: bool, message: String) -> void:
	if ok:
		print("ENET OK // %s" % message)
	else:
		push_error("ENET FAIL // %s" % message)
	RoomState.leave_network()
	get_tree().quit(0 if ok else 1)
