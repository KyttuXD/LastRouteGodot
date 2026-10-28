class_name VoiceChat
extends Node

## Proximity voice chat over the room's ENet relay (child "VoiceChat" of RemotePlayers, so every peer has the same RPC path).
## Sending: the microphone feeds a muted "VoiceMic" bus with an AudioEffectCapture; blocks of 40 ms are gated (voice activation
## with a short hangover, or the push_to_talk action) and sent as ADPCM packets (VoiceCodec, about 6 KB/s while talking, nothing
## while quiet) to the host, which checks them (room mute, troll flag, size, a per-speaker byte budget) and relays them only to
## peers within HEARING_RANGE on the same level. Receiving: one AudioStreamPlayer3D per speaker at their head, a small queue
## (latency capped), quieter through walls, silent from another level, per-player volume and local mute from Settings.
## Privacy: audio exists only in these buffers; nothing is recorded, saved or sent anywhere but to the room, and the microphone is
## open only while a room is online with voice chat switched on (the pill at the bottom right shows it).

signal speaking_changed(peer_id: int, speaking: bool)

const HEARING_RANGE := 25.0
const ACTION_PTT := "push_to_talk"
const BUS_NAME := "VoiceMic"
const HANGOVER := 0.35
const MAX_BLOCKS_PER_FRAME := 6
const MAX_QUEUE_SECONDS := 0.3
const GENERATOR_SECONDS := 0.5
const MAX_SPEAKERS := 4
const SPEAKER_WINDOW := 0.3
const OCCLUDED_DB := -9.0
## A speaker's packets must arrive no faster than this many per second on average (the codec sends 25).
const MAX_PACKETS_PER_SECOND := 40

var remotes: RemotePlayers
## Local state, read by the pill, the settings meter and tests.
var mic_open := false
var speaking := false
var mic_level := 0.0
var force_muted := false
## Counters (tests and the stats line): packets sent, played, and dropped on receipt.
var sent_packets := 0
var played_packets := 0
var dropped_packets := 0
var last_sent := PackedByteArray()
## Test hook: when set, packets go here (peer_id, packet) instead of the network.
var test_sink := Callable()

var _capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _bus := -1
var _carry := {}
var _pending := PackedFloat32Array()
var _hang := 0.0
var _seq := 0
var _players := {}        # speaker id -> {"node": AudioStreamPlayer3D, "gen": AudioStreamGeneratorPlayback, "last": int, "heard": float}
var _budget := {}         # sender id -> {"bytes": float, "at": int}
var _heard_at := {}       # speaker id -> msec of the last accepted packet
var _occlusion_tick := 0.0
var _pill: Label
var _layer: CanvasLayer
var _ptt_xr := false


static func ensure_actions() -> void:
	if InputMap.has_action(ACTION_PTT):
		return
	InputMap.add_action(ACTION_PTT)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_V
	InputMap.action_add_event(ACTION_PTT, key)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_RIGHT_STICK
	InputMap.action_add_event(ACTION_PTT, pad)


func _ready() -> void:
	name = "VoiceChat"
	add_to_group("voice_chat")
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_actions()
	_build_pill()


func _exit_tree() -> void:
	_close_mic()
	for id in _players.keys():
		_drop_speaker(int(id))


## True when the local microphone should be open: in an online room, voice chat on, and not force-muted by the host.
func wants_mic() -> bool:
	return RoomState.online and Settings.voice_chat_on and not force_muted


func _process(delta: float) -> void:
	var want := wants_mic()
	if want and not mic_open:
		_open_mic()
	elif not want and mic_open:
		_close_mic()
	if mic_open:
		_capture_step(delta)
	_update_playback(delta)
	_update_pill()


# -- microphone -------------------------------------------------------------------------------------------------------------

func _open_mic() -> void:
	if mic_open:
		return
	if AudioServer.input_device != Settings.voice_input_device and Settings.voice_input_device in AudioServer.get_input_device_list():
		AudioServer.input_device = Settings.voice_input_device
	_bus = AudioServer.get_bus_index(BUS_NAME)
	if _bus < 0:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, BUS_NAME)
		AudioServer.set_bus_mute(_bus, true)   # captured but never heard back
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.5
		AudioServer.add_bus_effect(_bus, _capture)
	else:
		_capture = AudioServer.get_bus_effect(_bus, 0) as AudioEffectCapture
	if _capture == null:
		return
	_capture.clear_buffer()
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = BUS_NAME
	add_child(_mic_player)
	_mic_player.play()
	_carry = {}
	_pending.clear()
	mic_open = true


func _close_mic() -> void:
	if _mic_player != null and is_instance_valid(_mic_player):
		_mic_player.stop()
		_mic_player.queue_free()
	_mic_player = null
	if _capture != null:
		_capture.clear_buffer()
	_pending.clear()
	mic_open = false
	_set_speaking(false)
	mic_level = 0.0


func _capture_step(delta: float) -> void:
	if _capture == null:
		return
	var available := _capture.get_frames_available()
	if available > 0:
		var frames := _capture.get_buffer(available)
		_pending.append_array(VoiceCodec.downsample(frames, AudioServer.get_mix_rate(), _carry))
	# Never let a stall build a backlog that would burst-send later: keep at most two blocks.
	var cap := VoiceCodec.BLOCK_SAMPLES * 2
	if _pending.size() > cap + VoiceCodec.BLOCK_SAMPLES:
		_pending = _pending.slice(_pending.size() - cap)
	var blocks := 0
	while _pending.size() >= VoiceCodec.BLOCK_SAMPLES and blocks < MAX_BLOCKS_PER_FRAME:
		var block := _pending.slice(0, VoiceCodec.BLOCK_SAMPLES)
		_pending = _pending.slice(VoiceCodec.BLOCK_SAMPLES)
		blocks += 1
		feed_block(block, VoiceCodec.BLOCK_SAMPLES / float(VoiceCodec.RATE))


## One 40 ms block of microphone samples: gain, level, gate, send. Public so the validators can drive it without a microphone.
func feed_block(block: PackedFloat32Array, seconds: float) -> void:
	var gain := Settings.voice_mic_gain
	if gain != 1.0:
		for i in block.size():
			block[i] = clampf(block[i] * gain, -1.0, 1.0)
	mic_level = VoiceCodec.level(block)
	if gate_open(mic_level, seconds):
		send_block(block)
		_set_speaking(true)
	else:
		_set_speaking(false)


## Voice activation (level above the sensitivity threshold, with a hangover) or push to talk. Mutated state: _hang.
func gate_open(level: float, seconds: float) -> bool:
	if force_muted or not Settings.voice_chat_on:
		_hang = 0.0
		return false
	if Settings.voice_mode == "ptt":
		_hang = 0.0
		return Input.is_action_pressed(ACTION_PTT) or _ptt_xr
	if level >= threshold_for(Settings.voice_sensitivity):
		_hang = HANGOVER
		return true
	_hang = maxf(_hang - seconds, 0.0)
	return _hang > 0.0


## Sensitivity 0..1 (1 = hears whispers) to an RMS threshold.
static func threshold_for(sensitivity: float) -> float:
	return lerpf(0.06, 0.004, clampf(sensitivity, 0.0, 1.0))


func set_xr_push_to_talk(held: bool) -> void:
	_ptt_xr = held


func _set_speaking(now: bool) -> void:
	if now == speaking:
		return
	speaking = now
	speaking_changed.emit(_local_id(), now)


func send_block(block: PackedFloat32Array) -> void:
	var packet := VoiceCodec.encode(block, _seq)
	_seq = (_seq + 1) & 0xFFFF
	sent_packets += 1
	last_sent = packet
	if test_sink.is_valid():
		test_sink.call(_local_id(), packet)
	elif not RoomState.online:
		return
	elif RoomState.is_host:
		_relay(1, packet)
	else:
		_voice_up.rpc_id(1, packet)


# -- host: checks and relay --------------------------------------------------------------------------------------------------

## Host moderation in one place (the voice twin of RemotePlayers.accept_line): shape, owner/admin mute, troll flag, and a byte
## budget so one client cannot flood the relay.
func host_accepts(sender: int, packet: PackedByteArray, now_ms: int = -1) -> bool:
	if packet.size() > VoiceCodec.MAX_PACKET or not VoiceCodec.valid(packet):
		return false
	if remotes != null and (remotes.room_muted.has(sender) or remotes.troll_peers.has(sender)):
		return false
	var now := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	var entry: Dictionary = _budget.get(sender, {"bytes": float(VoiceCodec.MAX_BYTES_PER_SECOND), "at": now})
	var bytes := minf(float(VoiceCodec.MAX_BYTES_PER_SECOND),
		float(entry["bytes"]) + float(now - int(entry["at"])) / 1000.0 * float(VoiceCodec.MAX_BYTES_PER_SECOND))
	_budget[sender] = {"bytes": bytes, "at": now}
	if bytes < float(packet.size()):
		return false
	_budget[sender] = {"bytes": bytes - float(packet.size()), "at": now}
	return true


## Who hears `sender`: peers on the same level within HEARING_RANGE (map-wide quiet radio is a later addition).
func listeners_for(sender: int, peers: Array) -> Array:
	var out := []
	var origin := _world_of(sender)
	var depth := _depth_of(sender)
	for id in peers:
		var peer := int(id)
		if peer == sender:
			continue
		if _depth_of(peer) != depth:
			continue
		var there := _world_of(peer)
		if Vector2(origin.x - there.x, origin.z - there.z).length() <= HEARING_RANGE + 4.0:
			out.append(peer)
	return out


func _relay(sender: int, packet: PackedByteArray) -> void:
	var peers: Array = []
	if multiplayer.multiplayer_peer != null:
		peers = Array(multiplayer.get_peers())
	if not RoomState.is_host:
		return
	for peer in listeners_for(sender, peers + [1]):
		if int(peer) == 1:
			_play(sender, packet)
		elif NetPeers.is_live(multiplayer, int(peer)):
			_voice_down.rpc_id(int(peer), sender, packet)


@rpc("any_peer", "call_remote", "unreliable", NetChannels.VOICE)
func _voice_up(packet: PackedByteArray) -> void:
	if not RoomState.is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or not host_accepts(sender, packet):
		dropped_packets += 1
		return
	_relay(sender, packet)


@rpc("authority", "call_remote", "unreliable", NetChannels.VOICE)
func _voice_down(sender: int, packet: PackedByteArray) -> void:
	if multiplayer.get_remote_sender_id() != 1 or sender == _local_id():
		return
	_play(sender, packet)


## Host to one guest: the room mute state, so their pill says why the microphone is closed.
func notify_muted(peer_id: int, muted: bool) -> void:
	if RoomState.online and RoomState.is_host and peer_id > 1 and multiplayer.multiplayer_peer != null:
		_set_force_muted.rpc_id(peer_id, muted)


@rpc("authority", "call_remote", "reliable")
func _set_force_muted(muted: bool) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		force_muted = muted


# -- playback ---------------------------------------------------------------------------------------------------------------

## A relayed packet from `sender`: local mute, speaker cap, then queued on their 3D player. Returns false when it was dropped.
func _play(sender: int, packet: PackedByteArray) -> bool:
	var speaker_name := RoomState.peer_display_name(sender)
	if Settings.is_player_muted(speaker_name) or not VoiceCodec.valid(packet) or Settings.voice_chat_volume <= 0.0:
		dropped_packets += 1
		return false
	var now := Time.get_ticks_msec()
	if not _heard_at.has(sender):
		var active := 0
		for id in _heard_at:
			if now - int(_heard_at[id]) < int(SPEAKER_WINDOW * 1000.0):
				active += 1
		if active >= MAX_SPEAKERS:
			dropped_packets += 1
			return false
	_heard_at[sender] = now
	var entry := _speaker(sender)
	if entry.is_empty():
		dropped_packets += 1
		return false
	var last: int = entry["last"]
	var seq := VoiceCodec.seq_of(packet)
	if last >= 0 and not VoiceCodec.newer(last, seq):
		dropped_packets += 1
		return false   # late or duplicate
	entry["last"] = seq
	var playback: AudioStreamGeneratorPlayback = entry["gen"]
	var pcm := VoiceCodec.decode(packet)
	var capacity := int(GENERATOR_SECONDS * VoiceCodec.RATE)
	var queued := capacity - playback.get_frames_available()
	if float(queued) / float(VoiceCodec.RATE) > MAX_QUEUE_SECONDS or not playback.can_push_buffer(pcm.size()):
		dropped_packets += 1
		return false   # latency cap: a stalled player skips ahead instead of lagging
	if queued <= 0:
		var lead := PackedVector2Array()
		lead.resize(VoiceCodec.RATE / 25)   # 40 ms of silence primes the generator against jitter
		playback.push_buffer(lead)
	var frames := PackedVector2Array()
	frames.resize(pcm.size())
	for i in pcm.size():
		frames[i] = Vector2(pcm[i], pcm[i])
	playback.push_buffer(frames)
	played_packets += 1
	entry["heard"] = 0.4
	var node: AudioStreamPlayer3D = entry["node"]
	node.volume_db = gain_db(Settings.voice_chat_volume * Settings.player_voice_volume(speaker_name), entry.get("occluded", false))
	if not node.playing:
		node.play()
	speaking_changed.emit(sender, true)
	return true


static func gain_db(volume: float, occluded: bool) -> float:
	var db := linear_to_db(maxf(volume, 0.0001))
	return db + (OCCLUDED_DB if occluded else 0.0)


func _speaker(id: int) -> Dictionary:
	if _players.has(id):
		return _players[id]
	var body: Node3D = remotes._bodies.get(id) if remotes != null else null
	var node := AudioStreamPlayer3D.new()
	node.name = "Voice%d" % id
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = VoiceCodec.RATE
	stream.buffer_length = GENERATOR_SECONDS
	node.stream = stream
	node.unit_size = 5.0
	node.max_distance = HEARING_RANGE
	node.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	node.attenuation_filter_cutoff_hz = 9000.0
	node.max_polyphony = 1
	add_child(node)
	if body != null:
		node.global_position = body.global_position + Vector3(0, 1.5, 0)
	node.play()
	var entry := {"node": node, "gen": node.get_stream_playback(), "last": -1, "heard": 0.0, "occluded": false}
	_players[id] = entry
	return entry


func _update_playback(delta: float) -> void:
	if _players.is_empty():
		return
	_occlusion_tick -= delta
	var check_walls := _occlusion_tick <= 0.0
	if check_walls:
		_occlusion_tick = 0.25
	for id in _players.keys():
		var entry: Dictionary = _players[id]
		var body: Node3D = remotes._bodies.get(int(id)) if remotes != null else null
		var node: AudioStreamPlayer3D = entry["node"]
		if body == null:
			_drop_speaker(int(id))
			continue
		node.global_position = body.global_position + Vector3(0, 1.5, 0)
		entry["heard"] = maxf(float(entry["heard"]) - delta, 0.0)
		if float(entry["heard"]) <= 0.0 and bool(entry.get("talking", true)):
			entry["talking"] = false
			speaking_changed.emit(int(id), false)
		elif float(entry["heard"]) > 0.0:
			entry["talking"] = true
		if check_walls and float(entry["heard"]) > 0.0:
			entry["occluded"] = _occluded(node.global_position)
			node.volume_db = gain_db(Settings.voice_chat_volume * Settings.player_voice_volume(RoomState.peer_display_name(int(id))),
				entry["occluded"])
			node.attenuation_filter_cutoff_hz = 2200.0 if entry["occluded"] else 9000.0


func _occluded(speaker: Vector3) -> bool:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, speaker)
	query.collide_with_areas = false
	if remotes != null and remotes.local_player is CollisionObject3D:
		query.exclude = [(remotes.local_player as CollisionObject3D).get_rid()]
	return not camera.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _drop_speaker(id: int) -> void:
	var entry: Dictionary = _players.get(id, {})
	if entry.is_empty():
		return
	var node: AudioStreamPlayer3D = entry["node"]
	if is_instance_valid(node):
		node.stop()
		node.queue_free()
	_players.erase(id)
	_heard_at.erase(id)
	_budget.erase(id)


## A peer left: forget its player and budget.
func forget_peer(id: int) -> void:
	_drop_speaker(id)


# -- helpers and the mic pill -----------------------------------------------------------------------------------------------

func _local_id() -> int:
	return multiplayer.get_unique_id() if RoomState.online and multiplayer.multiplayer_peer != null else 1


func _world_of(id: int) -> Vector3:
	if remotes == null:
		return Vector3.ZERO
	if id == 1 and RoomState.is_host:
		return remotes.local_player.global_position if remotes.local_player != null else Vector3.ZERO
	return remotes._positions.get(id, Vector3.ZERO)


func _depth_of(id: int) -> int:
	if remotes == null:
		return 0
	if id == 1 and RoomState.is_host:
		return GameState.depth
	return int((remotes._states.get(id, {}) as Dictionary).get("depth", GameState.depth))


func _build_pill() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 89
	add_child(_layer)
	_pill = Label.new()
	_pill.name = "MicPill"
	_pill.add_theme_font_size_override("font_size", 8)
	_pill.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_pill.offset_left = -96.0
	_pill.offset_top = -22.0
	_pill.offset_right = -8.0
	_pill.offset_bottom = -8.0
	_pill.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.visible = false
	_layer.add_child(_pill)


## The text and colour the pill shows, "" when there is nothing to say (microphone closed).
func pill_state() -> Dictionary:
	if force_muted and RoomState.online:
		return {"text": "MIC MUTED BY HOST", "color": Color(0.95, 0.4, 0.35)}
	if not mic_open:
		return {"text": "", "color": Color.WHITE}
	if speaking:
		return {"text": "● MIC LIVE", "color": Color(0.45, 0.95, 0.5)}
	if Settings.voice_mode == "ptt":
		return {"text": "○ HOLD [V] TO TALK", "color": Color(0.75, 0.75, 0.75)}
	return {"text": "○ MIC ON", "color": Color(0.75, 0.75, 0.75)}


func _update_pill() -> void:
	var state := pill_state()
	_pill.visible = not String(state["text"]).is_empty()
	_pill.text = String(state["text"])
	_pill.add_theme_color_override("font_color", state["color"])
