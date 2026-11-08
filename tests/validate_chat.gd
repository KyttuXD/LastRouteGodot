extends RefCounted

## Spoken room chat and its moderation: lines are heard by distance (25 m, same level; quieter through walls; silent beyond and
## from other levels; TEAM as a quiet radio for everyone), spoken in a voice that is stable per peer, shown as a subtitle and a
## bubble over the speaker; speaking makes a hunter noise (louder when shouted); no on-screen log, a short history for the
## pause menu. Moderation (host-side): 3 lines / 10 s then a cooldown, near-duplicates within 20 s dropped, long repeats
## collapsed, 80 characters, quick-chat pings under the same limits, local mute, room mute and kick. Quick chat still pings
## both maps; phone and XR input paths.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- chat

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _check_volume() -> void:
	var me := Vector3.ZERO
	var near := {"channel": "nearby", "world": Vector3(5, 0, 0), "depth": 0}
	var mid := {"channel": "nearby", "world": Vector3(15, 0, 0), "depth": 0}
	var far := {"channel": "nearby", "world": Vector3(30, 0, 0), "depth": 0}
	var below := {"channel": "nearby", "world": Vector3(2, 0, 0), "depth": -1}
	var close_volume := RoomChat.speech_volume(near, me, 0, false, false)
	var mid_volume := RoomChat.speech_volume(mid, me, 0, false, false)
	_expect(close_volume > mid_volume and mid_volume > 0.0, "volume does not fall off with distance (%.2f, %.2f)" % [close_volume, mid_volume])
	_expect(RoomChat.speech_volume(far, me, 0, false, false) == 0.0, "a NEARBY line 30 m away is heard")
	_expect(RoomChat.speech_volume(below, me, 0, false, false) == 0.0, "a NEARBY line from another level is heard")
	_expect(is_equal_approx(RoomChat.speech_volume(near, me, 0, false, true), close_volume * RoomChat.OCCLUDED_FACTOR), "walls do not muffle")
	_expect(is_equal_approx(RoomChat.speech_volume({"channel": "team", "world": Vector3(300, 0, 0), "depth": -4}, me, 0, false, false),
		RoomChat.TEAM_RADIO_VOLUME), "TEAM is not a quiet radio for everyone")


func _check_voice_and_noise() -> void:
	var voices := [{"id": "v1", "language": "en_US"}, {"id": "v2", "language": "en_GB"}, {"id": "v3", "language": "de_DE"}]
	var a := RoomChat.voice_for(5, voices)
	_expect(a == RoomChat.voice_for(5, voices), "a peer's voice is not stable")
	_expect(String(a["id"]) in ["v1", "v2"], "English voices are not preferred")
	var differs := false
	for peer in range(2, 8):
		var other := RoomChat.voice_for(peer, voices)
		differs = differs or other["id"] != a["id"] or other["pitch"] != a["pitch"]
	_expect(differs, "every peer sounds the same")
	_expect(String(RoomChat.voice_for(3, [])["id"]).is_empty(), "no voices installed should mean the blip fallback")
	var quiet := RoomChat.noise_for("ok")
	var long := RoomChat.noise_for("the second relay is past the red door and down the stairs")
	var shout := RoomChat.noise_for("RUN NOW")
	_expect(long.y > quiet.y and long.x > quiet.x, "longer lines do not make more noise")
	_expect(shout.x > RoomChat.noise_for("run now").x, "a shouted line is not louder")


func _check_moderation(remotes: RemotePlayers) -> void:
	for i in RemotePlayers.CHAT_RATE_MAX:
		_expect(remotes.accept_line(7, {"text": "line %d about things" % i}, 1000 + i), "line %d was limited too early" % i)
	_expect(not remotes.accept_line(7, {"text": "one too many"}, 1100), "the rate limit did not stop the 4th line")
	_expect(not remotes.accept_line(7, {"text": "still cooling"}, 1100 + RemotePlayers.CHAT_COOLDOWN_MS - 10), "no cooldown after the limit")
	_expect(remotes.accept_line(7, {"text": "after the cooldown"}, 1000 + RemotePlayers.CHAT_RATE_WINDOW_MS + RemotePlayers.CHAT_COOLDOWN_MS),
		"the limit never recovers")
	_expect(remotes.accept_line(9, {"text": "Hello there!"}, 50000), "a first line was refused")
	_expect(not remotes.accept_line(9, {"text": "hello  there!!!!"}, 51000), "a near-duplicate within 20 s was spoken")
	_expect(remotes.accept_line(9, {"text": "hello there"}, 50000 + RemotePlayers.DUPLICATE_WINDOW_MS + 10), "a repeat after 20 s was refused")
	_expect(RemotePlayers.collapse_repeats("aaaaaaaa!!!!!!") == "aaa!!!", "long repeats were not collapsed")
	_expect(RemotePlayers._sanitize_chat("x".repeat(10) + "abcdefghij".repeat(20)).length() <= 80, "lines are not capped at 80")
	_expect(remotes.accept_line(11, {"text": "OVER HERE!", "ping": true}, 70000), "a first ping was refused")
	_expect(not remotes.accept_line(11, {"text": "HIDE!", "ping": true}, 70500), "pings are not under the limits")
	remotes.set_room_muted(12, true)
	_expect(not remotes.accept_line(12, {"text": "hi"}, 80000), "a room-muted player was relayed")
	remotes.set_room_muted(12, false)
	_expect(remotes.accept_line(12, {"text": "hi again"}, 80001), "unmuting did not restore the player")
	_expect(RoomState.has_method("kick_peer"), "no kick for the admin tools")
	var spoof := RemotePlayers.sanitize_payload({"text": "hi", "system": true, "channel": "evil"}, false)
	_expect(not bool(spoof["system"]) and spoof["channel"] == "team", "a peer could send a system line or an unknown channel")


func run(host: Node) -> int:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	_check_volume()
	_check_voice_and_noise()
	var remotes := RemotePlayers.new()
	host.add_child(remotes)
	_check_moderation(remotes)
	remotes._chat_times.clear()
	remotes._ping_times.clear()
	remotes._cooldown_until.clear()
	remotes._recent_lines.clear()
	var chat := RoomChat.attach(host, remotes)
	var hud := (load("res://game/hud/hud.tscn") as PackedScene).instantiate()
	host.add_child(hud)
	chat.ping_posted.connect(hud.add_map_ping)
	var speaker := Node3D.new()
	host.add_child(speaker)
	remotes._bodies[2] = speaker
	await host.get_tree().process_frame
	var was_subtitles := Settings.voice_subtitles
	Settings.voice_subtitles = true
	# a peer in range: spoken, subtitle, bubble, history; no log panel
	RoomChat.history.clear()
	chat._on_chat_message(2, "Kyttu", {"text": "relay is here", "channel": "nearby", "world": Vector3(3, 0, 0), "depth": GameState.depth})
	await host.get_tree().process_frame
	_expect(chat.subtitle_rect().size != Vector2.ZERO and chat._subtitle.text.contains("RELAY IS HERE") or chat._subtitle.text.contains("relay is here"),
		"no subtitle for a nearby line")
	var bubble := speaker.get_node_or_null("SpeechBubble") as Label3D
	_expect(bubble != null and bubble.visible and bubble.text == "relay is here", "no speech bubble over the speaker")
	_expect(String(chat.last_spoken.get("text", "")) == "relay is here", "the line was not spoken (or blipped)")
	_expect(chat.panel_rect().size == Vector2.ZERO, "spoken chat opened a log")
	_expect(RoomChat.history.size() == 1, "the pause-menu history did not keep the line")
	# out of range: silent and not shown
	chat._subtitle_left = 0.0
	chat.last_spoken = {}
	chat._on_chat_message(2, "Kyttu", {"text": "far away", "channel": "nearby", "world": Vector3(80, 0, 0), "depth": GameState.depth})
	await host.get_tree().process_frame
	_expect(chat.last_spoken.is_empty() and not chat._subtitle.visible, "an out-of-range line was spoken or shown")
	# local mute
	Settings.set_player_muted("Kyttu", true)
	chat._on_chat_message(2, "Kyttu", {"text": "muted line", "channel": "team"})
	_expect(String(chat.last_spoken.get("text", "")) != "muted line" and RoomChat.history.size() == 1, "a muted player was spoken or shown")
	Settings.set_player_muted("Kyttu", false)
	# quick chat -> pings on both maps (same limits)
	var minimap: FacilityMap = hud.get("minimap")
	var plan: FacilityMap = hud.get("plan")
	_expect(chat.send_preset(0), "the first preset was not sent")
	await host.get_tree().process_frame
	_expect(minimap.live_pings().size() == 1 and plan.live_pings().size() == 1, "a quick-chat preset did not ping both maps")
	_expect(not chat.send_preset(4), "a second ping within 2 s was not limited")
	remotes._ping_times.clear()
	chat.hunter_aim_provider = func() -> Dictionary: return {"at": Vector2(40, 12), "depth": GameState.depth}
	_expect(chat.send_preset(RoomChat.PRESETS.find("HUNTER!")), "HUNTER! was not sent")
	await host.get_tree().process_frame
	_expect((minimap.live_pings()[-1] as Dictionary)["at"] == Vector2(40, 12), "HUNTER! did not ping the aimed hunter")
	# input paths: the typing panel, XR keyboard on the field, phone QUICK
	chat.open()
	await host.get_tree().process_frame
	_expect(chat._field.is_visible_in_tree() and chat._channel_button.is_visible_in_tree(), "the chat input is not shown")
	var keyboard := XRKeyboard.new()
	host.add_child(keyboard)
	chat._field.grab_focus()
	for _i in 3:
		await host.get_tree().process_frame
	_expect(keyboard.target == chat._field, "the XR keyboard does not type into the chat field")
	keyboard.queue_free()
	chat.close()
	var has_quick := false
	for entry in TouchControls.BUTTONS:
		has_quick = has_quick or String(entry[2]) == RoomChat.QUICK_ACTION
	_expect(has_quick and InputMap.has_action(RoomChat.QUICK_ACTION), "no QUICK button / quick_chat action")
	Settings.voice_subtitles = was_subtitles
	RoomChat.history.clear()
	hud.queue_free()
	chat.queue_free()
	speaker.queue_free()
	remotes.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  chat      spoken by distance/level/walls, stable voices, subtitles + bubbles, hunter noise, no log, moderation (rate, cooldown, duplicates, repeats, 80 chars, mutes, kick), pings")
	return _failures
