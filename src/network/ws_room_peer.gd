class_name WsRoomPeer
extends MultiplayerPeerExtension

## Godot multiplayer peer that talks to the backend's WebSocket room relay (backend/ws_relay.mjs).
##
## Browsers cannot use ENet (UDP) or listen for connections, so EVERY player, host included, makes one outbound
## WebSocket to `<server>/api/ws`; the relay forwards packets between them. It plugs into SceneMultiplayer like the
## ENet peer, so rooms, RPCs and spawners behave the same. Native builds can use it too (RoomState decides), which is
## what lets web and native players share a room.
##
## Wire format (see ws_relay.mjs): text control frames (JSON) and binary data frames
## [int32 LE peer][uint8 transfer mode][uint8 channel][payload].

signal link_ready
signal link_failed(message: String)

const HEADER_BYTES := 6
const MAX_PACKET_BYTES := 60_000
## Unreliable packets are dropped while this much is already queued on the socket (TCP would otherwise let a slow
## link pile up stale position updates).
const UNRELIABLE_BACKLOG_BYTES := 256 * 1024
const KEEPALIVE_MSEC := 20_000
const HOST_RECONNECT_MSEC := 2_000
const HELLO_TIMEOUT_MSEC := 10_000

var _ws := WebSocketPeer.new()
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _unique_id := 0
var _server := false
var _url := ""
var _code := ""
var _token := ""
var _hello_sent := false
var _link_open := false
var _link_started_msec := 0
var _last_send_msec := 0
var _reconnect_at_msec := 0
var _attempt_reported := false
var _closing := false
## Packets AND connect/disconnect events in arrival order. SceneMultiplayer drains the leading packets after each poll;
## an event is only emitted once every packet that came before it has been read (a guest's last RPC before leaving).
var _queue: Array = []
var _target := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _channel := 0
var _refusing := false
var _guest_ids := {}
var packets_in := 0
var packets_out := 0
var packets_dropped := 0


## `http://host/base` or `https://host/base` -> `ws(s)://host/base/api/ws`.
static func relay_url(base_url: String) -> String:
	var base := base_url.strip_edges().trim_suffix("/")
	if base.begins_with("https://"):
		base = "wss://" + base.trim_prefix("https://")
	elif base.begins_with("http://"):
		base = "ws://" + base.trim_prefix("http://")
	return base + "/api/ws"


## Host side: the peer is usable at once (id 1), the link to the relay opens when the directory has issued the host
## token. Nothing is lost by the wait: a room with no guests sends no packets.
func create_host(code: String) -> void:
	_reset()
	_server = true
	_unique_id = 1
	_code = code.to_upper()
	_status = MultiplayerPeer.CONNECTION_CONNECTED


func start_host_link(url: String, token: String) -> void:
	if not _server:
		return
	_url = url
	_token = token
	if _link_open or _ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		return
	_open_link()


func update_host_token(token: String) -> void:
	_token = token


## Guest side: connecting until the relay answers the hello with a peer id.
func create_guest(url: String, code: String, ticket: String = "") -> Error:
	_reset()
	_server = false
	_url = url
	_code = code.to_upper()
	_token = ticket   # a guest has no host token; a reserved room hands out a one-time join ticket instead
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	return _open_link()


func link_is_open() -> bool:
	return _link_open


func _reset() -> void:
	if _ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_ws.close(1000, "reset")
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 17
	_ws.outbound_buffer_size = 1 << 18
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_unique_id = 0
	_hello_sent = false
	_link_open = false
	_closing = false
	_queue.clear()
	_guest_ids.clear()
	_reconnect_at_msec = 0


func _open_link() -> Error:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 17
	_ws.outbound_buffer_size = 1 << 18
	_hello_sent = false
	_link_open = false
	_attempt_reported = false
	_link_started_msec = Time.get_ticks_msec()
	var error := _ws.connect_to_url(_url)
	if error != OK:
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED if not _server else _status
		link_failed.emit("COULD NOT OPEN WEB RELAY LINK")
	return error


func _poll() -> void:
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED and not _server:
		return
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED and _link_started_msec == 0 and _url.is_empty():
		return
	_drain_events()
	_ws.poll()
	state = _ws.get_ready_state()
	var now := Time.get_ticks_msec()
	match state:
		WebSocketPeer.STATE_CONNECTING:
			if now - _link_started_msec > HELLO_TIMEOUT_MSEC:
				_ws.close(4003, "connect timeout")
		WebSocketPeer.STATE_OPEN:
			if not _hello_sent:
				_send_hello()
			while _ws.get_available_packet_count() > 0:
				var packet := _ws.get_packet()
				if _ws.was_string_packet():
					_on_control(packet.get_string_from_utf8())
				else:
					_on_data(packet)
			if _link_open and now - _last_send_msec > KEEPALIVE_MSEC:
				_ws.send_text("{\"t\":\"ping\"}")
				_last_send_msec = now
			elif not _link_open and _hello_sent and now - _link_started_msec > HELLO_TIMEOUT_MSEC:
				_ws.close(4003, "hello timeout")
		WebSocketPeer.STATE_CLOSED:
			_on_link_closed()
	if _server and _reconnect_at_msec > 0 and now >= _reconnect_at_msec \
			and _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED and not _token.is_empty() and not _closing:
		_reconnect_at_msec = 0
		_open_link()
	_drain_events()


## Emits the connect/disconnect events at the head of the queue (never ahead of packets that precede them).
func _drain_events() -> void:
	while not _queue.is_empty() and _queue[0]["t"] == "e":
		var item: Dictionary = _queue.pop_front()
		var id: int = item["id"]
		if bool(item["on"]):
			peer_connected.emit(id)
		else:
			if not _server and id == 1:
				_status = MultiplayerPeer.CONNECTION_DISCONNECTED
			peer_disconnected.emit(id)


func _send_hello() -> void:
	_hello_sent = true
	var hello := {"t": "hello", "code": _code, "role": "host" if _server else "guest"}
	if _server:
		hello["token"] = _token
	elif not _token.is_empty():
		hello["ticket"] = _token
	_ws.send_text(JSON.stringify(hello))
	_last_send_msec = Time.get_ticks_msec()


func _on_control(text: String) -> void:
	var message = JSON.parse_string(text)
	if not message is Dictionary:
		return
	match String(message.get("t", "")):
		"welcome":
			_link_open = true
			if _server:
				link_ready.emit()
			else:
				_unique_id = int(message.get("id", 0))
				_status = MultiplayerPeer.CONNECTION_CONNECTED
				link_ready.emit()
				peer_connected.emit(1)
		"peer":
			var id := int(message.get("id", 0))
			if id <= 1:
				return
			if bool(message.get("on", false)):
				_guest_ids[id] = true
				_queue.append({"t": "e", "id": id, "on": true})
			elif _guest_ids.erase(id):
				_queue.append({"t": "e", "id": id, "on": false})
		"host":
			pass # the close frame follows
		"error":
			link_failed.emit(String(message.get("message", "RELAY REFUSED THE CONNECTION")))


func _on_data(packet: PackedByteArray) -> void:
	if packet.size() < HEADER_BYTES:
		return
	var from := packet.decode_s32(0)
	_queue.append({"t": "p", "from": from, "mode": packet[4], "channel": packet[5],
		"data": packet.slice(HEADER_BYTES)})
	packets_in += 1


func _on_link_closed() -> void:
	var was_open := _link_open
	_link_open = false
	_hello_sent = false
	if _closing:
		return
	if _server:
		# The relay drops every guest when the host link goes away.
		for id in _guest_ids.keys():
			_queue.append({"t": "e", "id": id, "on": false})
		_guest_ids.clear()
		if not _attempt_reported:
			_attempt_reported = true
			link_failed.emit("WEB RELAY LINK LOST // RECONNECTING" if was_open else "WEB RELAY UNREACHABLE // RETRYING")
		if _reconnect_at_msec == 0:
			_reconnect_at_msec = Time.get_ticks_msec() + HOST_RECONNECT_MSEC
	else:
		if _status == MultiplayerPeer.CONNECTION_CONNECTED:
			_queue.append({"t": "e", "id": 1, "on": false})
		elif _status == MultiplayerPeer.CONNECTION_CONNECTING:
			_status = MultiplayerPeer.CONNECTION_DISCONNECTED
			link_failed.emit("COULD NOT REACH THE ROOM THROUGH THE WEB RELAY")


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED or not _link_open:
		return ERR_UNCONFIGURED if _status == MultiplayerPeer.CONNECTION_DISCONNECTED else OK
	if buffer.size() > MAX_PACKET_BYTES:
		return ERR_OUT_OF_MEMORY
	if _mode != MultiplayerPeer.TRANSFER_MODE_RELIABLE \
			and _ws.get_current_outbound_buffered_amount() > UNRELIABLE_BACKLOG_BYTES:
		packets_dropped += 1
		return OK
	var target := _target if _server else 1
	var out := PackedByteArray()
	out.resize(HEADER_BYTES)
	out.encode_s32(0, target)
	out[4] = _mode
	out[5] = _channel & 0xff
	out.append_array(buffer)
	packets_out += 1
	_last_send_msec = Time.get_ticks_msec()
	return _ws.send(out, WebSocketPeer.WRITE_MODE_BINARY)


func _get_packet_script() -> PackedByteArray:
	if _queue.is_empty() or _queue[0]["t"] != "p":
		return PackedByteArray()
	var item: Dictionary = _queue.pop_front()
	return item["data"]


func _get_available_packet_count() -> int:
	var count := 0
	for item in _queue:
		if item["t"] != "p":
			break
		count += 1
	return count


func _get_max_packet_size() -> int:
	return MAX_PACKET_BYTES


## SceneMultiplayer asks who sent a packet BEFORE it reads that packet, so these describe the packet at the head of
## the queue (the ENet peer behaves the same way).
func _get_packet_peer() -> int:
	return int(_queue[0]["from"]) if not _queue.is_empty() and _queue[0]["t"] == "p" else 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return (int(_queue[0]["mode"]) if not _queue.is_empty() and _queue[0]["t"] == "p" \
		else MultiplayerPeer.TRANSFER_MODE_RELIABLE) as MultiplayerPeer.TransferMode


func _get_packet_channel() -> int:
	return int(_queue[0]["channel"]) if not _queue.is_empty() and _queue[0]["t"] == "p" else 0


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _set_target_peer(peer: int) -> void:
	_target = peer


func _is_server() -> bool:
	return _server


func _is_server_relay_supported() -> bool:
	return true


func _get_unique_id() -> int:
	return _unique_id


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status as MultiplayerPeer.ConnectionStatus


func _set_refuse_new_connections(enable: bool) -> void:
	_refusing = enable


func _is_refusing_new_connections() -> bool:
	return _refusing


func _disconnect_peer(peer: int, _force: bool) -> void:
	if _server:
		if _guest_ids.erase(peer):
			if _link_open:
				_ws.send_text(JSON.stringify({"t": "kick", "id": peer}))
			peer_disconnected.emit(peer)
	elif peer == 1:
		_close()


func _close() -> void:
	_closing = true
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.close(1000, "bye")
		_ws.poll() # the close frame is only written out by a poll; without it the relay would not notice us leave
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_link_open = false
	_guest_ids.clear()
	_queue.clear()
	_reconnect_at_msec = 0
