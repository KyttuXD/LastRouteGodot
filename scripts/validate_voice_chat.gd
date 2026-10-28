extends RefCounted

## Proximity voice chat: the ADPCM packet round trip, resampling, voice-activated and push-to-talk gating, no audio while muted or
## voice chat is off, the host's checks (room mute, troll flag, size, byte budget) and range/level relay, playback on a fake
## room (per-player volume, local mute, late packets, speaker cap, latency cap), the 3D TTS modes, the settings, and the cost of
## a packet. No microphone or speakers are needed: blocks are fed straight into the sender.
##
##   godot --headless --path . res://scenes/validate.tscn -- voice_chat

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _tone(hz: float, amplitude: float, samples: int = VoiceCodec.BLOCK_SAMPLES, offset: int = 0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(samples)
	for i in samples:
		out[i] = sin(TAU * hz * float(i + offset) / float(VoiceCodec.RATE)) * amplitude
	return out


func _snr_db(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var signal_power := 0.0
	var noise := 0.0
	for i in mini(a.size(), b.size()):
		signal_power += a[i] * a[i]
		noise += (a[i] - b[i]) * (a[i] - b[i])
	return 10.0 * log(signal_power / maxf(noise, 1e-12)) / log(10.0)


func _check_codec() -> void:
	var tone := _tone(440.0, 0.5)
	var packet := VoiceCodec.encode(tone, 7)
	_expect(packet.size() == VoiceCodec.PACKET_SIZE and VoiceCodec.PACKET_SIZE == 245, "packet is %d bytes, not 245" % packet.size())
	_expect(VoiceCodec.seq_of(packet) == 7 and VoiceCodec.valid(packet), "sequence or validity lost")
	var back := VoiceCodec.decode(packet)
	_expect(back.size() == VoiceCodec.BLOCK_SAMPLES, "decoded block has %d samples" % back.size())
	var snr := _snr_db(tone, back)
	_expect(snr > 15.0, "a 440 Hz tone comes back at only %.1f dB SNR" % snr)
	var speech := PackedFloat32Array()
	speech.resize(VoiceCodec.BLOCK_SAMPLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in speech.size():
		speech[i] = (sin(TAU * 180.0 * i / 12000.0) * 0.4 + sin(TAU * 1100.0 * i / 12000.0) * 0.2 + rng.randf_range(-0.03, 0.03))
	_expect(_snr_db(speech, VoiceCodec.decode(VoiceCodec.encode(speech, 0))) > 14.0, "a voiced-like signal decodes badly")
	var silence := VoiceCodec.decode(VoiceCodec.encode(PackedFloat32Array(), 1))
	var peak := 0.0
	for value in silence:
		peak = maxf(peak, absf(value))
	_expect(peak < 0.01, "silence decodes to noise (%.3f)" % peak)
	_expect(VoiceCodec.decode(PackedByteArray([1, 2, 3])).is_empty(), "a short packet decoded")
	var bad := packet.duplicate()
	bad.encode_u8(4, 200)
	_expect(not VoiceCodec.valid(bad) and VoiceCodec.decode(bad).is_empty(), "an out-of-range step index decoded")
	_expect(VoiceCodec.newer(65535, 0) and not VoiceCodec.newer(0, 65535) and not VoiceCodec.newer(5, 5), "sequence wrap compare is wrong")
	var rate_kb := float(VoiceCodec.PACKET_SIZE) * 25.0 / 1000.0
	_expect(rate_kb < 6.5, "voice costs %.1f KB/s" % rate_kb)


func _check_resample() -> void:
	var carry := {}
	var all := PackedFloat32Array()
	for chunk in 10:
		var frames := PackedVector2Array()
		frames.resize(480)   # 10 ms at 48 kHz per chunk
		for i in 480:
			var v := sin(TAU * 300.0 * float(chunk * 480 + i) / 48000.0) * 0.5
			frames[i] = Vector2(v, v)
		all.append_array(VoiceCodec.downsample(frames, 48000.0, carry))
	_expect(absi(all.size() - 1200) <= 1, "100 ms of 48 kHz became %d samples at 12 kHz" % all.size())
	var tone := _tone(300.0, 0.5, all.size())
	var best := 99.0
	for lag in range(0, 6):
		best = minf(best, 99.0 if lag < 0 else -_snr_db(tone.slice(0, all.size() - 6), all.slice(lag, all.size() - 6 + lag)))
	_expect(-best > 10.0, "the downsampled tone no longer matches (%.1f dB)" % -best)


func _check_gate(voice: VoiceChat) -> void:
	var was_on := Settings.voice_chat_on
	var was_mode := Settings.voice_mode
	var was_sens := Settings.voice_sensitivity
	Settings.voice_chat_on = true
	Settings.voice_mode = "vad"
	Settings.voice_sensitivity = 0.5
	voice.force_muted = false
	voice._hang = 0.0
	var loud := VoiceChat.threshold_for(0.5) * 4.0
	var quiet := VoiceChat.threshold_for(0.5) * 0.25
	_expect(voice.gate_open(loud, 0.04), "VAD ignored a loud block")
	_expect(voice.gate_open(quiet, 0.04), "VAD cut off at once (no hangover)")
	var held := 0
	while voice.gate_open(quiet, 0.04) and held < 40:
		held += 1
	_expect(held >= 6 and held <= 12, "hangover lasted %d blocks" % held)
	_expect(not voice.gate_open(quiet, 0.04), "VAD stayed open on silence")
	_expect(VoiceChat.threshold_for(1.0) < VoiceChat.threshold_for(0.0), "higher sensitivity should hear quieter speech")
	# push to talk
	Settings.voice_mode = "ptt"
	_expect(not voice.gate_open(loud, 0.04), "PTT opened without the key")
	Input.action_press(VoiceChat.ACTION_PTT)
	_expect(voice.gate_open(quiet, 0.04), "PTT held did not open (even on quiet)")
	Input.action_release(VoiceChat.ACTION_PTT)
	_expect(not voice.gate_open(loud, 0.04), "PTT released stayed open")
	voice.set_xr_push_to_talk(true)
	_expect(voice.gate_open(quiet, 0.04), "the headset's PTT binding did not open the mic")
	voice.set_xr_push_to_talk(false)
	# no audio while muted
	Settings.voice_mode = "vad"
	var before := voice.sent_packets
	voice.force_muted = true
	voice.feed_block(_tone(300.0, 0.6), 0.04)
	_expect(voice.sent_packets == before and not voice.speaking, "audio was sent while force-muted")
	voice.force_muted = false
	Settings.voice_chat_on = false
	voice.feed_block(_tone(300.0, 0.6), 0.04)
	_expect(voice.sent_packets == before, "audio was sent with voice chat off")
	_expect(not voice.wants_mic(), "the mic wants to be open with voice chat off")
	Settings.voice_chat_on = true
	voice.feed_block(_tone(300.0, 0.6), 0.04)
	_expect(voice.sent_packets == before + 1, "a loud block was not sent")
	voice.feed_block(PackedFloat32Array(), 0.04)
	Settings.voice_chat_on = was_on
	Settings.voice_mode = was_mode
	Settings.voice_sensitivity = was_sens
	voice._hang = 0.0


func _check_host(voice: VoiceChat, remotes: RemotePlayers) -> void:
	var packet := VoiceCodec.encode(_tone(300.0, 0.4), 1)
	_expect(voice.host_accepts(2, packet, 1000), "a normal packet was refused")
	_expect(not voice.host_accepts(2, PackedByteArray([1, 2, 3]), 1000), "a malformed packet was accepted")
	var big := PackedByteArray()
	big.resize(VoiceCodec.MAX_PACKET + 1)
	_expect(not voice.host_accepts(2, big, 1000), "an oversized packet was accepted")
	remotes.set_room_muted(3, true)
	_expect(not voice.host_accepts(3, packet, 1000), "a room-muted player's voice was relayed")
	remotes.set_room_muted(3, false)
	_expect(voice.host_accepts(3, packet, 1000), "unmuting did not restore the voice")
	remotes.troll_peers[4] = true
	_expect(not voice.host_accepts(4, packet, 1000), "a troll-flagged player's voice was relayed")
	remotes.troll_peers.erase(4)
	# the byte budget: 100 packets in the same millisecond cannot all pass
	var passed := 0
	for i in 100:
		if voice.host_accepts(5, packet, 2000):
			passed += 1
	_expect(passed >= 2 and passed <= 40, "%d of 100 flood packets passed" % passed)
	_expect(voice.host_accepts(5, packet, 2000 + 1000), "the budget never refilled")


func _check_relay(voice: VoiceChat, remotes: RemotePlayers) -> void:
	var player := Node3D.new()
	voice.add_child(player)
	remotes.local_player = player
	player.global_position = Vector3.ZERO
	remotes._positions[2] = Vector3(10, 0, 0)
	remotes._positions[3] = Vector3(60, 0, 0)
	remotes._positions[4] = Vector3(5, 0, 0)
	remotes._states[2] = {"depth": GameState.depth}
	remotes._states[3] = {"depth": GameState.depth}
	remotes._states[4] = {"depth": GameState.depth + 1}
	var heard: Array = voice.listeners_for(1, [2, 3, 4])
	_expect(heard == [2], "the host's voice reached %s, not just the near peer on its level" % [heard])
	var from_two: Array = voice.listeners_for(2, [1, 3, 4])
	_expect(from_two == [1], "a guest's voice reached %s" % [from_two])
	_expect(not voice.listeners_for(3, [1, 2]).has(1), "a far guest was heard by the host")


func _check_playback(voice: VoiceChat, remotes: RemotePlayers, host: Node) -> void:
	var body := Node3D.new()
	host.add_child(body)
	body.global_position = Vector3(6, 0, 0)
	remotes._bodies[2] = body
	RoomState.peers[2] = "Kyttu"
	var packet := func(seq: int) -> PackedByteArray: return VoiceCodec.encode(_tone(300.0, 0.4), seq)
	var was_volume := Settings.voice_chat_volume
	Settings.voice_chat_volume = 1.0
	Settings.muted_players.erase("KYTTU")
	Settings.voice_player_volumes.erase("KYTTU")
	var before := voice.played_packets
	_expect(voice._play(2, packet.call(10)), "an in-range packet was not played")
	_expect(voice.played_packets == before + 1, "played counter did not advance")
	var entry: Dictionary = voice._players.get(2, {})
	_expect(not entry.is_empty() and entry["node"] is AudioStreamPlayer3D, "the speaker has no 3D player")
	var node: AudioStreamPlayer3D = entry["node"]
	voice._update_playback(0.016)
	_expect(node.global_position.distance_to(body.global_position + Vector3(0, 1.5, 0)) < 0.01, "the voice is not at the speaker's head")
	_expect(node.max_distance == VoiceChat.HEARING_RANGE, "the voice carries %.0f m" % node.max_distance)
	_expect(not voice._play(2, packet.call(10)), "a duplicate packet was played")
	_expect(not voice._play(2, packet.call(9)), "a late packet was played")
	_expect(voice._play(2, packet.call(11)), "the next packet was refused")
	# per-player and master volume
	Settings.set_player_voice_volume("Kyttu", 0.5)
	voice._play(2, packet.call(12))
	_expect(is_equal_approx(node.volume_db, linear_to_db(0.5)), "per-player volume did not apply (%.1f dB)" % node.volume_db)
	Settings.set_player_voice_volume("Kyttu", 1.0)
	_expect(VoiceChat.gain_db(1.0, true) < VoiceChat.gain_db(1.0, false), "walls do not quieten a voice")
	# local mute drops the voice and nothing is queued
	Settings.set_player_muted("Kyttu", true)
	var dropped := voice.dropped_packets
	_expect(not voice._play(2, packet.call(13)) and voice.dropped_packets == dropped + 1, "a muted player was played")
	Settings.set_player_muted("Kyttu", false)
	# latency cap: stop the player from draining and keep pushing
	var pushed := 0
	for i in 40:
		if voice._play(2, packet.call(20 + i)):
			pushed += 1
	_expect(pushed < 40 and pushed > 3, "the queue took %d of 40 packets without draining" % pushed)
	# speaker cap
	for id in [5, 6, 7, 8, 9]:
		var b := Node3D.new()
		host.add_child(b)
		remotes._bodies[id] = b
		RoomState.peers[id] = "P%d" % id
		voice._heard_at[id] = 0
	voice._heard_at.clear()
	voice._heard_at[2] = Time.get_ticks_msec()
	var admitted := 0
	for id in [5, 6, 7, 8, 9]:
		if voice._play(id, packet.call(1)):
			admitted += 1
	_expect(admitted == VoiceChat.MAX_SPEAKERS - 1, "%d extra speakers admitted, expected %d" % [admitted, VoiceChat.MAX_SPEAKERS - 1])
	# leaving frees the player
	voice.forget_peer(2)
	_expect(not voice._players.has(2), "a peer who left still has a voice player")
	# nothing recorded: no files under user:// mention voice
	var leaked := false
	for entry_name in DirAccess.get_files_at("user://"):
		if entry_name.to_lower().contains("voice") or entry_name.get_extension() in ["wav", "ogg", "opus"]:
			leaked = true
	_expect(not leaked, "audio-looking files appeared under user://")
	Settings.voice_chat_volume = was_volume


func _check_tts(host: Node) -> void:
	_expect(not RoomChat.speaks_line("off", false) and not RoomChat.speaks_line("off", true), "TTS off still speaks")
	_expect(RoomChat.speaks_line("own", true) and not RoomChat.speaks_line("own", false), "own-only TTS is wrong")
	_expect(RoomChat.speaks_line("everyone", false) and not RoomChat.speaks_line("everyone", true), "everyone TTS is wrong")
	# the voice is at the sender's position: loudness follows the distance and level
	var near := RoomChat.speech_volume({"channel": "nearby", "world": Vector3(4, 0, 0), "depth": 0}, Vector3.ZERO, 0, false, false)
	var far := RoomChat.speech_volume({"channel": "nearby", "world": Vector3(20, 0, 0), "depth": 0}, Vector3.ZERO, 0, false, false)
	var gone := RoomChat.speech_volume({"channel": "nearby", "world": Vector3(40, 0, 0), "depth": 0}, Vector3.ZERO, 0, false, false)
	_expect(near > far and far > 0.0 and gone == 0.0, "TTS loudness does not follow the sender's distance")
	var remotes := RemotePlayers.new()
	host.add_child(remotes)
	var chat := RoomChat.attach(host, remotes)
	var was_mode := Settings.tts_mode
	var was_rate := Settings.tts_rate
	var was_enabled := Settings.voice_enabled
	Settings.voice_enabled = true
	Settings.tts_rate = 1.0
	Settings.tts_mode = "off"
	chat.last_spoken = {}
	chat._on_chat_message(2, "Kyttu", {"text": "off line", "channel": "nearby", "world": Vector3(3, 0, 0), "depth": GameState.depth})
	_expect(chat.last_spoken.is_empty(), "a line was spoken with TTS off")
	Settings.tts_mode = "everyone"
	chat._on_chat_message(2, "Kyttu", {"text": "everyone line", "channel": "nearby", "world": Vector3(3, 0, 0), "depth": GameState.depth})
	var base_rate := float(chat.last_spoken.get("rate", 1.0)) if not bool(chat.last_spoken.get("blip", true)) else -1.0
	_expect(String(chat.last_spoken.get("text", "")) == "everyone line", "an everyone line was not spoken")
	if base_rate > 0.0:
		Settings.tts_rate = 1.5
		chat._on_chat_message(2, "Kyttu", {"text": "faster", "channel": "nearby", "world": Vector3(3, 0, 0), "depth": GameState.depth})
		_expect(float(chat.last_spoken.get("rate", 0.0)) > base_rate, "the TTS rate setting did not apply")
	Settings.tts_mode = "own"
	chat.last_spoken = {}
	chat._on_chat_message(2, "Kyttu", {"text": "someone else", "channel": "nearby", "world": Vector3(3, 0, 0), "depth": GameState.depth})
	_expect(chat.last_spoken.is_empty(), "own-only TTS read another player's line")
	Settings.tts_mode = was_mode
	Settings.tts_rate = was_rate
	Settings.voice_enabled = was_enabled
	chat.queue_free()
	remotes.queue_free()


func _check_settings() -> void:
	var on := Settings.voice_chat_on
	var mode := Settings.voice_mode
	var gain := Settings.voice_mic_gain
	var sens := Settings.voice_sensitivity
	var device := Settings.voice_input_device
	var volume := Settings.voice_chat_volume
	Settings.set_voice_chat(true, "bogus", 9.0, -1.0, "", 9.0)
	_expect(Settings.voice_mode == "vad" and Settings.voice_mic_gain == 2.0 and Settings.voice_sensitivity == 0.0
		and Settings.voice_input_device == "Default" and Settings.voice_chat_volume == 1.5, "voice settings are not clamped")
	Settings.set_voice_chat(on, mode, gain, sens, device, volume)
	var t_mode := Settings.tts_mode
	var t_rate := Settings.tts_rate
	var t_voice := Settings.tts_voice_id
	Settings.set_tts("loud", 9.0, "x")
	_expect(Settings.tts_mode == "everyone" and Settings.tts_rate == 2.0, "TTS settings are not clamped")
	Settings.set_tts(t_mode, t_rate, t_voice)
	_expect(Settings.voice_mode in ["vad", "ptt"] and Settings.tts_mode in ["off", "own", "everyone"], "settings restore left a bad value")


func _check_panel(host: Node) -> void:
	var was_on := Settings.voice_chat_on
	var was_mode := Settings.voice_mode
	RoomState.peers[77] = "Mirelle"
	var panel := VoicePanel.new()
	host.add_child(panel)
	for control in ["VoiceChatOnButton", "VoiceModeButton", "VoiceDeviceList", "VoiceGainSlider", "VoiceSensitivitySlider",
			"VoiceLevelMeter", "VoiceVolumeOthersSlider", "TtsModeButton", "TtsVoiceList", "TtsRateSlider", "VoicePlayer_MIRELLE"]:
		_expect(panel.find_child(control, true, false) != null, "the VOICE tab is missing %s" % control)
	var toggle := panel.find_child("VoiceChatOnButton", true, false) as Button
	toggle.pressed.emit()
	_expect(Settings.voice_chat_on == not was_on, "the VOICE CHAT button did not toggle")
	var mode := panel.find_child("VoiceModeButton", true, false) as Button
	mode.pressed.emit()
	_expect(Settings.voice_mode != was_mode, "the mode button did not switch voice activation / push to talk")
	var mirelle := panel.find_child("VoicePlayer_MIRELLE", true, false)
	if mirelle != null:
		(mirelle.get_child(0) as CheckBox).button_pressed = true
		_expect(Settings.is_player_muted("Mirelle"), "the player row's MUTE did not mute")
		(mirelle.get_child(0) as CheckBox).button_pressed = false
		(mirelle.get_child(1) as HSlider).value = 0.5
		_expect(is_equal_approx(Settings.player_voice_volume("Mirelle"), 0.5), "the player row's volume did not apply")
		(mirelle.get_child(1) as HSlider).value = 1.0
	Settings.set_voice_chat(was_on, was_mode, Settings.voice_mic_gain, Settings.voice_sensitivity, Settings.voice_input_device,
		Settings.voice_chat_volume)
	Settings.set_player_muted("Mirelle", false)
	Settings.set_player_voice_volume("Mirelle", 1.0)
	RoomState.peers.erase(77)
	panel.queue_free()


func _check_cost(voice: VoiceChat) -> void:
	var block := _tone(250.0, 0.4)
	var start := Time.get_ticks_usec()
	for i in 25:
		VoiceCodec.decode(VoiceCodec.encode(block, i))
	var per_packet := float(Time.get_ticks_usec() - start) / 25.0 / 1000.0
	print("  voice: encode+decode %.2f ms per 40 ms packet" % per_packet)
	_expect(per_packet < 6.0, "a voice packet costs %.1f ms of CPU" % per_packet)


func run(host: Node) -> int:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	_check_codec()
	_check_resample()
	var remotes := RemotePlayers.new()
	host.add_child(remotes)
	var voice := VoiceChat.new()
	voice.remotes = remotes
	host.add_child(voice)
	await host.get_tree().process_frame
	var sent: Array = []
	voice.test_sink = func(id: int, packet: PackedByteArray) -> void: sent.append([id, packet])
	_check_gate(voice)
	_expect(sent.size() == voice.sent_packets - 0 or sent.size() > 0, "the sender never produced a packet")
	var wire: PackedByteArray = voice.last_sent
	_expect(wire.size() == VoiceCodec.PACKET_SIZE and VoiceCodec.valid(wire), "the sent packet is malformed")
	_check_host(voice, remotes)
	_check_relay(voice, remotes)
	_check_playback(voice, remotes, host)
	_check_tts(host)
	_check_settings()
	_check_panel(host)
	_check_cost(voice)
	voice.queue_free()
	remotes.queue_free()
	if _failures == 0:
		print("voice_chat: all checks OK")
	return _failures
