extends RefCounted

## Deliberate private-room host handoff.
## Covers the relay notices (frames 8/9) the tunnel accepts and refuses, the successor's switch to relay host on the
## same socket, the versioned checkpoint envelope, peer-owned record remapping, resume identity proofs and the
## explicit "unsupported" answers. The relay side (named candidate, epoch, deadline, refused release keeps the room)
## is backend/enet_relay.test.mjs + server.test.mjs.
##
##   godot4 --headless res://tests/scenes/validate.tscn -- host_handoff

const TUNNEL_SCRIPT := preload("res://game/network/enet_relay_tunnel.gd")
const HANDOFF := preload("res://game/network/host_handoff.gd")
const TOKEN := "AbCdEfGhIjKlMnOpQrStUvWxYz012345"   # base64url, 32 chars like the server's

var PORT := 28491 + int(OS.get_environment("VALIDATE_PORT_OFFSET"))
var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	_check_payload_parsing()
	_check_tunnel_notices(host)
	await _check_promote_to_host(host)
	_check_envelope()
	_check_remap()
	_check_rebind_live_world()
	_check_room_state_guards()
	_check_resume_proofs()
	_check_successor_save()
	return _failures


func _frame(kind: int, session: int, payload: String) -> Dictionary:
	return TUNNEL_SCRIPT.decode_frame(TUNNEL_SCRIPT.encode_frame(kind, session, "HNDOF", payload.to_ascii_buffer()))


func _check_payload_parsing() -> void:
	_expect(TUNNEL_SCRIPT.parse_handoff_payload("LRH1|7|ready".to_ascii_buffer()) == {"epoch": 7, "tail": "ready"},
		"a ready notice did not parse")
	_expect(TUNNEL_SCRIPT.parse_handoff_payload("LRH1|3".to_ascii_buffer()) == {"epoch": 3, "tail": ""},
		"a waiting notice did not parse")
	for bad in ["", "LRH1", "LRH2|3|x", "LRH1|0|x", "LRH1|-4|x", "LRH1|x|y", "host-secret"]:
		_expect(TUNNEL_SCRIPT.parse_handoff_payload(bad.to_ascii_buffer()).is_empty(),
			"a malformed or legacy handoff payload parsed: %s" % bad)


func _check_tunnel_notices(host: Node) -> void:
	var tunnel: Node = TUNNEL_SCRIPT.new()
	host.add_child(tunnel)
	tunnel.room_code = "HNDOF"
	tunnel.mode = tunnel.Mode.GUEST
	tunnel._session_id = 4242
	var promoted := []
	var migrating := []
	tunnel.host_promoted.connect(func(epoch: int, token: String) -> void: promoted.append([epoch, token]))
	tunnel.host_migrating.connect(func(epoch: int, ready: bool) -> void: migrating.append([epoch, ready]))
	var promote := _frame(8, 4242, "LRH1|5|" + TOKEN)
	tunnel._handle_relay_frame(promote)
	_expect(promoted.is_empty(), "an UNARMED guest accepted a promotion")
	tunnel.arm_handoff(5)
	tunnel._handle_relay_frame(promote, false)
	_expect(promoted.is_empty(), "a promotion from a socket that is not the relay was accepted (spoof)")
	tunnel._handle_relay_frame(_frame(8, 9999, "LRH1|5|" + TOKEN))
	_expect(promoted.is_empty(), "a promotion for another relay session was accepted")
	tunnel._handle_relay_frame(_frame(8, 4242, "LRH1|4|" + TOKEN))
	_expect(promoted.is_empty(), "a promotion for a stale epoch was accepted")
	tunnel._handle_relay_frame(_frame(8, 4242, "LRH1|5|short"))
	tunnel._handle_relay_frame(_frame(8, 4242, "LRH1|5|" + TOKEN.substr(0, 20) + "!@#$%^&*()"))
	_expect(promoted.is_empty(), "a malformed promotion token was accepted")
	tunnel._handle_relay_frame(_frame(8, 4242, TOKEN))
	_expect(promoted.is_empty(), "a legacy (epoch-less) promotion was accepted by an armed guest")
	tunnel._handle_relay_frame(promote)
	tunnel._handle_relay_frame(promote)
	_expect(promoted == [[5, TOKEN]], "the valid promotion was not delivered exactly once (%d)" % promoted.size())
	tunnel._handle_relay_frame(_frame(9, 4242, "LRH1|5"))
	tunnel._handle_relay_frame(_frame(9, 4242, "LRH1|5"))
	tunnel._handle_relay_frame(_frame(9, 0, "LRH1|5|ready"))
	tunnel._handle_relay_frame(_frame(9, 4242, "LRH1|5|ready"))
	tunnel._handle_relay_frame(_frame(9, 4242, "LRH1|5|ready"))
	tunnel._handle_relay_frame(_frame(9, 4242, ""))
	_expect(migrating == [[5, false], [5, true]],
		"waiting/ready notices were not delivered once each for this session (%s)" % [migrating])
	tunnel.mode = tunnel.Mode.HOST
	tunnel.arm_handoff(6)
	tunnel._handle_relay_frame(_frame(8, 4242, "LRH1|6|" + TOKEN))
	_expect(promoted.size() == 1, "a HOST tunnel acted on a promotion")
	tunnel.close()
	_expect(tunnel.armed_handoff_epoch() == 0, "closing the tunnel left a handoff armed")
	tunnel.queue_free()


func _check_promote_to_host(host: Node) -> void:
	var relay := PacketPeerUDP.new()   # stands in for the relay
	if relay.bind(PORT, "127.0.0.1", 1 << 20) != OK:
		_fail("could not open the fake relay on %d" % PORT)
		return
	var tunnel: Node = TUNNEL_SCRIPT.new()
	host.add_child(tunnel)
	var local_port: int = tunnel.start_guest("HNDOF", "127.0.0.1", PORT)
	_expect(local_port > 0, "the guest tunnel did not open")
	await host.get_tree().create_timer(0.1).timeout
	var guest_endpoint := _drain_endpoint(relay)
	_expect(tunnel.promote_to_host("bad token!", 9000) != "", "promote_to_host accepted a malformed token")
	tunnel._session_id = 77
	_expect(tunnel.guest_session() == 77, "guest_session() did not report the relay session")
	var error: String = tunnel.promote_to_host(TOKEN, 9000)
	_expect(error.is_empty(), "promote_to_host failed: %s" % error)
	_expect(tunnel.mode == tunnel.Mode.HOST and not tunnel._ready, "the promoted tunnel is not a pending relay host")
	_expect(tunnel.guest_session() == 0, "the promoted tunnel still claims a guest session")
	await host.get_tree().create_timer(0.4).timeout
	var registered := false
	var alive := false
	var same_socket := false
	while relay.get_available_packet_count() > 0:
		var packet := relay.get_packet()
		var frame: Dictionary = TUNNEL_SCRIPT.decode_frame(packet)
		var token := (frame.get("payload", PackedByteArray()) as PackedByteArray).get_string_from_utf8()
		if int(frame.get("type", 0)) == 1 and token == TOKEN:
			registered = true
			same_socket = relay.get_packet_port() == int(guest_endpoint.get("port", -1))
		if int(frame.get("type", 0)) == 11 and token == TOKEN:
			alive = true
	_expect(registered, "the successor did not send HOST_REGISTER with the promoted token")
	_expect(same_socket, "the successor registered from a different socket than its guest session (relay binds that endpoint)")
	_expect(alive, "the successor's keep-alive thread did not start with the promoted token")
	# HOST_ACK makes it ready
	var readied := []
	tunnel.relay_ready.connect(func() -> void: readied.append(true))
	tunnel._handle_relay_frame(_frame(2, 0, ""))
	_expect(readied.size() == 1 and tunnel._ready, "HOST_ACK did not make the promoted tunnel ready")
	tunnel.close()
	tunnel.queue_free()
	relay.close()


func _drain_endpoint(relay: PacketPeerUDP) -> Dictionary:
	var endpoint := {}
	while relay.get_available_packet_count() > 0:
		relay.get_packet()
		endpoint = {"port": relay.get_packet_port()}
	return endpoint


func _world() -> Dictionary:
	var world := StreamedWorldState.new()
	world.waypoints.place(1, Vector2(3, 4), 0)
	world.waypoints.place(555, Vector2(5, 6), 0)
	world.waypoints.place(777, Vector2(7, 8), -1)
	world.downs.down(777, Vector3(1, 0, 1), 0, "SEVEN")
	world.downs.down(1, Vector3(2, 0, 2), 0, "HOST")
	world.hunters["H:1"] = {"position": Vector2.ZERO, "gray_peer": 1, "gray_reason": "idle"}
	world.hunters["H:2"] = {"position": Vector2.ZERO, "gray_peer": 555}
	return world.snapshot()


func _check_envelope() -> void:
	var payload := {"schema": 1, "kind": "infinite_route", "seed_text": "SEED", "run_seed": 99,
		"world_state": _world(), "player": {"position": Vector3.ZERO}, "game_state": {"depth": 2}}
	var proof := HANDOFF.resume_hash(HANDOFF.new_resume_secret())
	var envelope := HANDOFF.build_envelope("HNDOF", "SEED", 99, 3, "packhash", 555, {proof: 555}, 12, payload)
	_expect(not (envelope["world"] as Dictionary).has("player"), "the checkpoint carried the old host's own runner")
	_expect(payload.has("player"), "build_envelope mutated the caller's payload")
	var expected := {"code": "HNDOF", "run_seed": 99, "epoch": 3, "pack_hash": "packhash", "successor_old_peer": 555}
	_expect(HANDOFF.validate_envelope(envelope, expected).is_empty(),
		"a good checkpoint was refused: %s" % HANDOFF.validate_envelope(envelope, expected))
	var cases := {"code": "OTHER", "run_seed": 98, "epoch": 4, "pack_hash": "modded", "successor_old_peer": 777}
	for key in cases:
		var wrong := expected.duplicate()
		wrong[key] = cases[key]
		_expect(not HANDOFF.validate_envelope(envelope, wrong).is_empty(), "a checkpoint with the wrong %s was accepted" % key)
	var old_version := envelope.duplicate(true)
	old_version["version"] = 99
	_expect(not HANDOFF.validate_envelope(old_version, expected).is_empty(), "an unknown checkpoint version was accepted")
	var bad_identity := envelope.duplicate(true)
	bad_identity["identity"] = {"CALLSIGN-R-1234": 555}
	_expect(not HANDOFF.validate_envelope(bad_identity, expected).is_empty(),
		"a callsign-keyed identity map was accepted (identity must be a resume proof, never a label)")
	var host_identity := envelope.duplicate(true)
	host_identity["identity"] = {proof: 1}
	_expect(not HANDOFF.validate_envelope(host_identity, expected).is_empty(), "an identity mapped to the old host was accepted")
	_expect(HANDOFF.resume_hash("not-a-secret").is_empty(), "a malformed resume secret produced a proof")
	_expect(HANDOFF.new_resume_secret() != HANDOFF.new_resume_secret(), "resume secrets repeat")


func _check_remap() -> void:
	var world := _world()
	var out := HANDOFF.remap_world_snapshot(world, {555: 1}, [1])
	var waypoints: Dictionary = out["waypoints"]
	_expect(waypoints.has(1) and int(waypoints[1]["peer_id"]) == 1 and (waypoints[1]["at"] as Vector2).x == 5.5,
		"the successor's waypoint did not become peer 1's (%s)" % [waypoints])
	_expect(not waypoints.has(555), "the successor's old id kept a waypoint")
	_expect(waypoints.has(777), "a reconnecting runner's waypoint was dropped before its rebind window")
	_expect((waypoints.values().filter(func(w): return (w["at"] as Vector2).x == 3.5)).is_empty(),
		"the old host's own waypoint survived the handoff")
	var downs: Dictionary = out["downs"]
	_expect(downs.has("777") and not downs.has("1"), "revive windows were not remapped (%s)" % [downs.keys()])
	var hunters: Dictionary = out["hunters"]
	_expect(not (hunters["H:1"] as Dictionary).has("gray_peer"), "Gray stayed bound to the departed old host")
	_expect(int(hunters["H:2"]["gray_peer"]) == 1, "Gray's binding did not follow the successor")
	_expect(world["waypoints"].has(1), "remap mutated its input")
	var adopted := StreamedWorldState.new()
	_expect(adopted.adopt(out), "a remapped world snapshot no longer adopts")


func _check_rebind_live_world() -> void:
	var world := StreamedWorldState.new()
	world.adopt(HANDOFF.remap_world_snapshot(_world(), {555: 1}, [1]))
	_expect(HANDOFF.rebind_world_state(world, 777, 31337), "a proven runner's records were not rebound")
	_expect(world.waypoints.has_for(31337) and not world.waypoints.has_for(777), "the waypoint did not move to the new peer")
	_expect(world.downs.is_down(31337) and not world.downs.is_down(777), "the revive window did not move to the new peer")
	_expect(not HANDOFF.rebind_world_state(world, 1, 5), "the old host id could be rebound onto someone")
	world.waypoints.place(888, Vector2(1, 1), 0)
	_expect(HANDOFF.rebind_world_state(world, 888, 0) and not world.waypoints.has_for(888),
		"an expired rebind window did not drop the runner's records")


func _check_room_state_guards() -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	_expect(RoomState.begin_host_handoff() != "", "an offline room started a host transfer")
	_expect(RoomState.handoff_phase == RoomState.Handoff.NONE, "a refused transfer changed the handoff phase")
	# a direct-LAN / web-socket host (no gameplay relay) gets an explicit unsupported answer, not a dropped room
	RoomState.online = true
	RoomState.is_host = true
	_expect(RoomState.handoff_supported() == RoomState.HANDOFF_UNSUPPORTED,
		"a host without the gameplay relay was not told transfer is unsupported (%s)" % RoomState.handoff_supported())
	RoomState.public_route = true
	_expect(RoomState.handoff_supported() == RoomState.HANDOFF_UNSUPPORTED, "the PUBLIC route was offered a private handoff")
	RoomState.public_route = false
	_expect(RoomState.begin_host_handoff() != "" and RoomState.handoff_phase == RoomState.Handoff.NONE,
		"an unsupported host started a transfer")
	RoomState.online = false
	# a checkpoint for a guest that was not chosen is refused
	RoomState.is_host = false
	_expect(RoomState.receive_handoff_checkpoint({"kind": HANDOFF.KIND}) != "", "an unarmed guest stored a checkpoint")
	_expect(not RoomState.handoff_blocks_authority() and not RoomState.handoff_freezes_input(),
		"an idle room reports a handoff freeze")
	# a promotion without an armed epoch and stored checkpoint changes nothing
	RoomState._on_relay_host_promoted(1, TOKEN)
	_expect(not RoomState.is_host and RoomState.handoff_phase == RoomState.Handoff.NONE,
		"an unexpected promotion made this client a host")
	var source := FileAccess.get_file_as_string("res://game/autoload/room_state.gd")
	_expect(not source.contains("create_timer(1.0).timeout.connect(leave_network)"),
		"the blind one-second leave after a transfer is still there")
	_expect(not source.contains("print(\"%s\" % token") and not source.contains("print(token"), "a handoff token is printed")
	RoomState.create_local(RoomState.Mode.DEFAULT)


func _check_resume_proofs() -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var secret := HANDOFF.new_resume_secret()
	var stranger := HANDOFF.new_resume_secret()
	RoomState._handoff_pending_identity = {HANDOFF.resume_hash(secret): 777}
	RoomState._handoff_rebind_deadline_msec = Time.get_ticks_msec() + 60_000
	RoomState._handoff_rebinds_queued = []
	_expect(not RoomState.accept_resume_proof(40, stranger), "an unknown resume secret was accepted")
	_expect(not RoomState.accept_resume_proof(40, "R-1234"), "a callsign was accepted as a resume proof")
	_expect(RoomState.accept_resume_proof(41, secret), "the checkpoint's resume proof was refused")
	var queued := RoomState.take_handoff_rebinds()
	_expect(queued == [[777, 41]], "the rebind old -> new was not queued for the rebuilt scene (%s)" % [queued])
	_expect(RoomState._handoff_pending_identity.is_empty(), "a used resume proof stayed pending")
	# expiry drops the rest
	RoomState._handoff_pending_identity = {HANDOFF.resume_hash(stranger): 888}
	RoomState._handoff_rebind_deadline_msec = Time.get_ticks_msec() - 1
	RoomState._tick_handoff()
	_expect(RoomState.take_handoff_rebinds() == [[888, 0]], "an expired rebind window did not drop the runner")
	RoomState.create_local(RoomState.Mode.DEFAULT)
	_expect(RoomState._resume_secret.is_empty() and RoomState._resume_hashes.is_empty(),
		"leaving the room kept resume identities")


func _check_successor_save() -> void:
	var payload := {"schema": 1, "kind": "infinite_route", "seed_text": "SEED", "run_seed": 99,
		"world_state": _world(), "player": {"position": Vector3(9, 0, 9)}, "game_state": {"depth": 2}}
	var envelope := HANDOFF.build_envelope("HNDOF", "SEED", 99, 3, "packhash", 555, {}, 0, payload)
	var own := {"position": Vector3(1, 2, 3), "inventory_order": [], "inventory_slot_durability": []}
	var installed := HANDOFF.successor_payload(envelope, own)
	_expect((installed["player"] as Dictionary).get("position") == Vector3(1, 2, 3),
		"the successor did not restore its OWN runner")
	_expect(String((installed["authority"] as Dictionary).get("source", "")) == "host_handoff", "the install is not tagged as a handoff")
	_expect((installed["world_state"]["waypoints"] as Dictionary).has(1), "the install world was not remapped")
	_expect(RunSaves.payload_valid(installed), "the successor install is not a valid route payload")
	_expect(RunSaves.queue_handoff(installed), "the successor install could not be queued")
	var pending := RunSaves.consume_pending()
	_expect(bool(pending.get("ok", false)) and (pending.get("payload", {}) as Dictionary).get("run_seed") == 99,
		"the queued install did not come back through the CONTINUE slot")
	_expect(not RunSaves.queue_handoff({"kind": "infinite_route"}), "an invalid install was queued")
	RunSaves.clear_pending()
