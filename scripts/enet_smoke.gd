extends Node

## Two-process ENet smoke check. This complements validate_sync.gd: that suite
## exercises gameplay state deeply in one process, while this small scene proves
## the actual transport handshake and autoload RPC path work between processes.
##
## Run the host, then the client in a second shell:
##   godot4 --headless --path . res://scenes/enet_smoke.tscn -- host
##   godot4 --headless --path . res://scenes/enet_smoke.tscn -- client

const PORT := 18421
const TIMEOUT_SECONDS := 8.0

var _client_waiting_for_start := false
var _remotes: RemotePlayers
var _host_received_interaction := false
var _client_received_effect := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not ["host", "client"].has(args[0]):
		_finish(false, "usage: enet_smoke.tscn -- host|client")
		return
	if args[0] == "host":
		await _run_host()
	else:
		await _run_client()


func _run_host() -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.set_map_scale(RoomState.Scale.LARGE)
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
			if int(id) > 1 and not String(RoomState.peers[id]).begins_with("SIGNAL-"):
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
	if not await _wait_for(func() -> bool: return _host_received_interaction):
		_finish(false, "guest interaction request never reached host authority")
		return
	print("ENET HOST AUTHORITY OK // guest interaction request received")
	# Exercise the same authority RPC RoomState.enter() uses without replacing
	# this smoke-test scene on the host. The client's changed signal verifies the
	# synchronized start before its deferred scene transition can remove it.
	await get_tree().create_timer(0.25).timeout
	RoomState._receive_start.rpc(RoomState.code, RoomState.seed_text,
		RoomState.mode, RoomState.map_scale, RoomState.difficulty)
	print("ENET HOST START OK // synchronized route launch sent")
	await get_tree().create_timer(0.5).timeout
	RoomState.leave_network()
	get_tree().quit(0)


func _run_client() -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var local_code := RoomState.code
	_client_waiting_for_start = true
	RoomState.changed.connect(_on_client_room_changed)
	var error := RoomState.join_room(RoomState.DEFAULT_ADDRESS, PORT)
	if not error.is_empty():
		_finish(false, error)
		return
	_install_replication(Vector3(3, 0, 3))
	var synchronized := await _wait_for(func() -> bool:
		return (RoomState.online and RoomState.roster().size() == 2
			and RoomState.map_scale == RoomState.Scale.LARGE))
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
	if not await _wait_for(func() -> bool: return _client_received_effect):
		_finish(false, "host-targeted player effect never reached the guest")
		return
	print("ENET CLIENT AUTHORITY OK // targeted effect received")
	# _on_client_room_changed quits on the host's start RPC. Staying alive here
	# also gives the reliable callsign registration time to reach the host.
	await get_tree().create_timer(TIMEOUT_SECONDS).timeout
	if _client_waiting_for_start:
		_finish(false, "client never received the synchronized route start")


func _on_client_room_changed() -> void:
	if not _client_waiting_for_start or not RoomState.session_active:
		return
	if not RoomState.online or RoomState.map_scale != RoomState.Scale.LARGE:
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
	_remotes.interaction_requested.connect(func(peer_id: int, event: Dictionary) -> void:
		if peer_id > 1 and String(event.get("what", "")) == "music_box":
			_host_received_interaction = true)
	_remotes.player_event.connect(func(event: Dictionary) -> void:
		if String(event.get("what", "")) == "smoke_effect" \
				and int(event.get("value", 0)) == 37:
			_client_received_effect = true)
	add_child(_remotes)


func _finish(ok: bool, message: String) -> void:
	if ok:
		print("ENET OK // %s" % message)
	else:
		push_error("ENET FAIL // %s" % message)
	RoomState.leave_network()
	get_tree().quit(0 if ok else 1)
