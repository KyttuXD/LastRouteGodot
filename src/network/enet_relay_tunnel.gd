class_name EnetRelayTunnel
extends Node

## UDP tunnel between a local ENetMultiplayerPeer and the public Node relay.
##
## Host side: one outbound relay socket receives tagged guest datagrams. Each
## guest gets a separate loopback UDP socket into the unchanged ENet server,
## preserving the distinct source endpoint ENet uses to identify a peer.
##
## Guest side: ENet connects to a loopback proxy. The proxy wraps its raw ENet
## datagrams for the relay and unwraps host replies. Both sides therefore make
## outbound connections only; no player router ever accepts inbound traffic.

signal relay_ready
signal relay_failed(message: String)

enum Mode { CLOSED, HOST, GUEST }
enum Frame { HOST_REGISTER = 1, HOST_ACK = 2, GUEST_JOIN = 3, GUEST_ACK = 4,
	GUEST_DATA = 5, HOST_DATA = 6, ERROR = 7 }

const HEADER_BYTES := 14
const MAX_DATAGRAM_BYTES := 1472
const HOST_REGISTER_INTERVAL_MSEC := 3000
# A room is listed by HTTP just before its host's first UDP registration can
# arrive. Retrying only at eight seconds raced the entire connection timeout:
# a guest whose first join landed in that tiny window never tried again before
# both smoke test and UI gave up. This control frame is only 26 bytes.
const GUEST_JOIN_INTERVAL_MSEC := 750
const BRIDGE_TTL_MSEC := 60_000
const MAX_PENDING_PACKETS := 64
# PacketPeerUDP's ring buffer defaults to 64 KB and is drained once per frame. A 4-player room pushes ~400 KB/s
# through the host's relay socket, so any frame over ~160 ms overflowed it ("Buffer full, dropping packets!" in
# VIDEO's co-op logs, 2026-10-28) and dropped ENet fragments. 1 MB rides out multi-second hitches.
const RECEIVE_BUFFER_BYTES := 1 << 20
const MAGIC_BYTES := [76, 82, 82, 49] # "LRR1"

var mode: Mode = Mode.CLOSED
var room_code := ""
var relay_address := ""
var relay_port := 0

var _socket: PacketPeerUDP
var _host_token := ""
var _host_enet_port := 0
var _session_id := 0
var _nonce := PackedByteArray()
var _ready := false
var _next_control_msec := 0
var _last_error := ""
var _client_address := ""
var _client_port := 0
var _pending: Array[PackedByteArray] = []
var _bridges := {}


func start_host(code: String, token: String, enet_port: int,
		address: String, port: int) -> String:
	close()
	var error := _open(code, address, port)
	if not error.is_empty():
		return error
	mode = Mode.HOST
	_host_token = token
	_host_enet_port = enet_port
	_send_host_registration()
	return ""


func update_host_token(token: String) -> void:
	if mode != Mode.HOST:
		return
	_host_token = token
	_next_control_msec = 0
	_send_host_registration()


## Returns the loopback UDP port an ENet client should connect to, or zero on
## failure. It is intentionally opened before the relay acknowledges the room:
## ENet's first connect datagrams are queued and flushed once GUEST_ACK lands.
func start_guest(code: String, address: String, port: int) -> int:
	close()
	var error := _open(code, address, port)
	if not error.is_empty():
		relay_failed.emit(error)
		return 0
	mode = Mode.GUEST
	_nonce = Crypto.new().generate_random_bytes(12)
	_send_guest_join()
	return _socket.get_local_port()


func ready() -> bool:
	return _ready


func last_error() -> String:
	return _last_error


func close() -> void:
	for entry in _bridges.values():
		var peer = entry.get("peer") as PacketPeerUDP
		if peer != null:
			peer.close()
	_bridges.clear()
	if _socket != null:
		_socket.close()
	_socket = null
	mode = Mode.CLOSED
	room_code = ""
	relay_address = ""
	relay_port = 0
	_host_token = ""
	_host_enet_port = 0
	_session_id = 0
	_nonce = PackedByteArray()
	_ready = false
	_next_control_msec = 0
	_last_error = ""
	_client_address = ""
	_client_port = 0
	_pending.clear()


## ENet writes its final reliable RPC/disconnect datagram into this loopback
## socket. Give the guest proxy one synchronous drain before its UDP socket is
## closed, otherwise the host can retain a departed roster row until timeout.
func flush_guest_outbound() -> void:
	if mode == Mode.GUEST and _socket != null:
		_poll_main_socket()


func _open(code: String, address: String, port: int) -> String:
	room_code = code.strip_edges().to_upper()
	relay_address = address.strip_edges()
	relay_port = port
	if room_code.length() != 5 or relay_address.is_empty() \
			or relay_port < 1 or relay_port > 65_535:
		return "INVALID GAMEPLAY RELAY ENDPOINT"
	_socket = PacketPeerUDP.new()
	var error := _socket.bind(0, "0.0.0.0", RECEIVE_BUFFER_BYTES)
	if error != OK:
		_socket = null
		return "COULD NOT OPEN OUTBOUND GAMEPLAY RELAY (%d)" % error
	return ""


func _process(_delta: float) -> void:
	if mode == Mode.CLOSED or _socket == null:
		return
	var now := Time.get_ticks_msec()
	if now >= _next_control_msec:
		if mode == Mode.HOST:
			_send_host_registration()
		else:
			_send_guest_join()
	_poll_main_socket()
	if mode == Mode.HOST:
		_poll_host_bridges(now)


func _poll_main_socket() -> void:
	while _socket != null and _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		var source_ip := _socket.get_packet_ip()
		var source_port := _socket.get_packet_port()
		if mode == Mode.GUEST and _is_local_enet(source_ip, source_port):
			_client_address = source_ip
			_client_port = source_port
			_forward_guest_packet(packet)
			continue
		var frame := decode_frame(packet)
		if frame.is_empty() or String(frame.get("code", "")) != room_code:
			continue
		_handle_relay_frame(frame)


func _is_local_enet(source_ip: String, source_port: int) -> bool:
	return source_port != relay_port and source_port > 0 \
		and source_ip in ["127.0.0.1", "::1", "::ffff:127.0.0.1"]


func _handle_relay_frame(frame: Dictionary) -> void:
	var kind := int(frame.get("type", 0))
	if kind == Frame.ERROR:
		var message := (frame.get("payload", PackedByteArray()) as PackedByteArray) \
			.get_string_from_utf8()
		if message != _last_error:
			_last_error = message
			relay_failed.emit(message)
		return
	if mode == Mode.HOST:
		if kind == Frame.HOST_ACK:
			_mark_ready()
		elif kind == Frame.GUEST_DATA:
			_forward_to_host_enet(int(frame.get("session", 0)),
				frame.get("payload", PackedByteArray()))
	elif mode == Mode.GUEST:
		if kind == Frame.GUEST_ACK:
			_session_id = int(frame.get("session", 0))
			if _session_id != 0:
				_mark_ready()
				_flush_pending()
		elif kind == Frame.HOST_DATA and int(frame.get("session", 0)) == _session_id:
			_send_to_local_client(frame.get("payload", PackedByteArray()))


func _mark_ready() -> void:
	_last_error = ""
	if _ready:
		return
	_ready = true
	relay_ready.emit()


func _send_host_registration() -> void:
	if mode != Mode.HOST or _host_token.is_empty():
		return
	_send_relay(Frame.HOST_REGISTER, 0, _host_token.to_utf8_buffer())
	_next_control_msec = Time.get_ticks_msec() + HOST_REGISTER_INTERVAL_MSEC


func _send_guest_join() -> void:
	if mode != Mode.GUEST or _nonce.is_empty():
		return
	_send_relay(Frame.GUEST_JOIN, 0, _nonce)
	_next_control_msec = Time.get_ticks_msec() + GUEST_JOIN_INTERVAL_MSEC


func _forward_guest_packet(packet: PackedByteArray) -> void:
	if packet.size() + HEADER_BYTES > MAX_DATAGRAM_BYTES:
		return
	if _session_id == 0:
		if _pending.size() >= MAX_PENDING_PACKETS:
			_pending.pop_front()
		_pending.append(packet)
		return
	_send_relay(Frame.GUEST_DATA, _session_id, packet)


func _flush_pending() -> void:
	for packet in _pending:
		_send_relay(Frame.GUEST_DATA, _session_id, packet)
	_pending.clear()


func _forward_to_host_enet(session: int, packet: PackedByteArray) -> void:
	if session == 0 or packet.is_empty():
		return
	var entry: Dictionary = _bridges.get(session, {})
	var bridge = entry.get("peer") as PacketPeerUDP
	if bridge == null:
		bridge = PacketPeerUDP.new()
		if bridge.bind(0, "127.0.0.1", RECEIVE_BUFFER_BYTES) != OK:
			return
		entry = {"peer": bridge, "last_seen": Time.get_ticks_msec()}
		_bridges[session] = entry
	entry["last_seen"] = Time.get_ticks_msec()
	bridge.set_dest_address("127.0.0.1", _host_enet_port)
	bridge.put_packet(packet)


func _poll_host_bridges(now: int) -> void:
	for session in _bridges.keys():
		var entry: Dictionary = _bridges[session]
		var bridge = entry.get("peer") as PacketPeerUDP
		if bridge == null:
			_bridges.erase(session)
			continue
		while bridge.get_available_packet_count() > 0:
			var packet := bridge.get_packet()
			entry["last_seen"] = now
			_send_relay(Frame.HOST_DATA, int(session), packet)
		if now - int(entry.get("last_seen", now)) > BRIDGE_TTL_MSEC:
			bridge.close()
			_bridges.erase(session)


func _send_to_local_client(packet: PackedByteArray) -> void:
	if _socket == null or _client_port <= 0 or _client_address.is_empty():
		return
	_socket.set_dest_address(_client_address, _client_port)
	_socket.put_packet(packet)


func _send_relay(kind: int, session: int, payload: PackedByteArray) -> void:
	if _socket == null or payload.size() + HEADER_BYTES > MAX_DATAGRAM_BYTES:
		return
	_socket.set_dest_address(relay_address, relay_port)
	_socket.put_packet(encode_frame(kind, session, room_code, payload))


static func encode_frame(kind: int, session: int, code: String,
		payload := PackedByteArray()) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(HEADER_BYTES)
	for index in 4:
		result[index] = MAGIC_BYTES[index]
	result[4] = kind
	result.encode_u32(5, session)
	var code_bytes := code.to_ascii_buffer()
	for index in 5:
		result[9 + index] = code_bytes[index] if index < code_bytes.size() else 0
	# append_array, not a per-byte GDScript loop: ~30x cheaper at hundreds of frames a second
	result.append_array(payload)
	return result


static func decode_frame(packet: PackedByteArray) -> Dictionary:
	if packet.size() < HEADER_BYTES or packet.size() > MAX_DATAGRAM_BYTES:
		return {}
	for index in 4:
		if packet[index] != MAGIC_BYTES[index]:
			return {}
	return {
		"type": int(packet[4]),
		"session": int(packet.decode_u32(5)),
		"code": packet.slice(9, 14).get_string_from_ascii(),
		"payload": packet.slice(HEADER_BYTES),
	}
