extends RefCounted

## A host's room lives exactly as long as its process ("when a host quits its room ... make the room invalid",
## "drop 1s or no delay"). The relay tunnel's keep-alive thread sends HOST_ALIVE every 250 ms on its own socket:
## a main loop frozen for 5 s keeps sending (a loading hitch must not kill a live room), a closed tunnel stops at
## once, and a guest hears HOST_LEFT. The relay side (1 s timeout, guests told, code invalid) is
## backend/enet_relay.test.mjs.
##
##   godot4 --headless res://tests/scenes/validate.tscn -- host_alive

var PORT := 28471 + int(OS.get_environment("VALIDATE_PORT_OFFSET"))

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	var relay := PacketPeerUDP.new()   # stands in for the relay
	if relay.bind(PORT, "127.0.0.1", 1 << 20) != OK:
		_fail("could not open the fake relay on %d" % PORT)
		return _failures
	var tunnel: Node = load("res://game/network/enet_relay_tunnel.gd").new()
	host.add_child(tunnel)
	_expect(tunnel.start_host("ABCDE", "host-token", 7777, "127.0.0.1", PORT).is_empty(), "the host tunnel did not open")

	# the main loop freezes for 5 s: the keep-alive thread must keep the room alive the whole time
	# The main loop never returns to the engine for 5 s (this loop polls the fake relay itself, with real arrival
	# times). The relay drops a host 1 s after its last HOST_ALIVE, so the longest gap is what matters.
	var frozen_at := Time.get_ticks_msec()
	var last_at := frozen_at
	var worst_gap := 0
	var frames := 0
	while Time.get_ticks_msec() - frozen_at < 5000:
		var arrived := _drain(relay)
		if arrived > 0:
			var now := Time.get_ticks_msec()
			worst_gap = maxi(worst_gap, now - last_at)
			last_at = now
			frames += arrived
		OS.delay_msec(5)
	worst_gap = maxi(worst_gap, Time.get_ticks_msec() - last_at)
	print("  alive     main loop blocked 5 s: %d HOST_ALIVE frames, longest gap %d ms (relay timeout 1000 ms)" % [frames, worst_gap])
	_expect(frames >= 10, "only %d keep-alives in a 5 s main-loop freeze" % frames)
	_expect(worst_gap < 800, "a %d ms gap between keep-alives during the freeze: the relay would have dropped the room" % worst_gap)

	# a token refresh is picked up by the thread
	var sent_before: int = tunnel.alive_sent
	tunnel.update_host_token("new-token")
	await host.get_tree().create_timer(0.6).timeout
	var tokens := _tokens(relay)
	_expect(tokens.has("new-token"), "the keep-alive kept sending the old host token (got %s; thread sent %d)" % [
		tokens, tunnel.alive_sent - sent_before])

	# quit: closing the tunnel stops the keep-alive at once
	tunnel.close()
	_drain(relay)
	await host.get_tree().create_timer(0.6).timeout
	_expect(_drain(relay) == 0, "keep-alives went on after the host closed its room")

	# a guest hears that the host left
	var heard := []
	tunnel.host_left.connect(func(message: String) -> void: heard.append(message))
	tunnel.room_code = "ABCDE"
	tunnel.mode = tunnel.Mode.GUEST
	tunnel._handle_relay_frame(tunnel.decode_frame(tunnel.encode_frame(10, 0, "ABCDE", "HOST LEFT // ROOM CLOSED".to_utf8_buffer())))
	_expect(heard == ["HOST LEFT // ROOM CLOSED"], "a guest did not hear HOST_LEFT (%s)" % [heard])
	tunnel.queue_free()
	relay.close()
	return _failures


## How many HOST_ALIVE frames are waiting at the fake relay; with `token`, only those carrying it.
func _drain(relay: PacketPeerUDP, token: String = "") -> int:
	var count := 0
	while relay.get_available_packet_count() > 0:
		var frame := EnetRelayTunnel.decode_frame(relay.get_packet())
		if int(frame.get("type", 0)) != 11:
			continue
		if not token.is_empty() and (frame.get("payload", PackedByteArray()) as PackedByteArray).get_string_from_utf8() != token:
			continue
		count += 1
	return count


## Tokens carried by the HOST_ALIVE frames waiting at the fake relay.
func _tokens(relay: PacketPeerUDP) -> Array:
	var out := []
	while relay.get_available_packet_count() > 0:
		var frame := EnetRelayTunnel.decode_frame(relay.get_packet())
		if int(frame.get("type", 0)) == 11:
			out.append((frame.get("payload", PackedByteArray()) as PackedByteArray).get_string_from_utf8())
	return out
