extends RefCounted

## Room chat: NEARBY / TEAM hearing by distance and level, the faded-while-idle view vs the full history when open, peer-coloured
## callsigns, channel tags and system lines, the rate limits, quick-chat presets turning into map pings (minimap + full map;
## HUNTER! on the aimed hunter), and the phone (QUICK button, on-screen keyboard) and XR (keyboard on the chat field, left X)
## input paths.
##
##   godot --headless --path . res://scenes/validate.tscn -- chat

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _check_hearing() -> void:
	var me := Vector3(0, 0, 0)
	var near := {"channel": "nearby", "world": Vector3(12, 0, 9), "depth": 0}
	var far := {"channel": "nearby", "world": Vector3(30, 0, 0), "depth": 0}
	var below := {"channel": "nearby", "world": Vector3(2, -4, 0), "depth": -1}
	var team := {"channel": "team", "world": Vector3(300, 0, 0), "depth": -3}
	_expect(RoomChat.hear(near, me, 0, false) == "clear", "a NEARBY line 15 m away is not clear")
	_expect(RoomChat.hear(far, me, 0, false) == "faint", "a NEARBY line 30 m away is not greyed")
	_expect(RoomChat.hear(below, me, 0, false) == "hidden", "a NEARBY line from another level is heard")
	_expect(RoomChat.hear(team, me, 0, false) == "clear", "a TEAM line is filtered")
	_expect(RoomChat.hear(far, me, 0, true) == "clear", "my own NEARBY line is greyed")
	_expect(RoomChat.hear({"channel": "nearby", "system": true, "depth": -5}, me, 0, false) == "clear", "a system line is filtered")


func _check_rate(remotes: RemotePlayers) -> void:
	for i in RemotePlayers.CHAT_RATE_MAX:
		_expect(remotes.rate_ok(7, false, 1000 + i), "message %d was rate limited too early" % i)
	_expect(not remotes.rate_ok(7, false, 1100), "the chat rate limit did not stop a flood")
	_expect(remotes.rate_ok(7, false, 1000 + RemotePlayers.CHAT_RATE_WINDOW_MS + 50), "the rate limit never recovers")
	_expect(remotes.rate_ok(8, true, 50000), "the first ping was refused")
	_expect(not remotes.rate_ok(8, true, 50500), "a second ping within 2 s was allowed")
	_expect(remotes.rate_ok(8, true, 50000 + RemotePlayers.PING_MIN_INTERVAL_MS + 1), "pings never recover")
	var spoof := RemotePlayers.sanitize_payload({"text": "hi", "system": true, "channel": "evil"}, false)
	_expect(not bool(spoof["system"]) and spoof["channel"] == "team", "a peer could send a system line or an unknown channel")


func run(host: Node) -> int:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	_check_hearing()
	var remotes := RemotePlayers.new()
	host.add_child(remotes)
	_check_rate(remotes)
	remotes._chat_times.clear()
	remotes._ping_times.clear()
	var chat := RoomChat.attach(host, remotes)
	var hud := (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	host.add_child(hud)
	chat.ping_posted.connect(hud.add_map_ping)
	await host.get_tree().process_frame
	# look: tags, peer colours, system lines
	chat._on_chat_message(2, "Kyttu", {"text": "relay is here", "channel": "nearby", "world": Vector3.ZERO, "depth": GameState.depth})
	var line := RoomChat.format_entry(chat._entries[-1])
	_expect(line.contains("[NEAR]") and line.contains(RemotePlayers.peer_colour(2).to_html(false)) and line.contains("KYTTU"),
		"a NEARBY line lacks its tag or the sender's colour: %s" % line)
	chat.add_system("route sealed by the owner")
	_expect(RoomChat.format_entry(chat._entries[-1]).contains(Palette.AMBER.to_html(false)), "system lines are not styled apart")
	# fade vs history
	for i in 8:
		chat._on_chat_message(3, "Guest", {"text": "line %d" % i, "channel": "team"})
	await host.get_tree().process_frame
	_expect(chat._log.text.split("\n").size() == RoomChat.MAX_VISIBLE_MESSAGES, "idle chat shows %d lines, not the last %d" % [chat._log.text.split("\n").size(), RoomChat.MAX_VISIBLE_MESSAGES])
	_expect(chat.panel_rect().size != Vector2.ZERO, "fresh lines are not shown")
	chat._fresh_left = 0.0
	await host.get_tree().process_frame
	_expect(chat.panel_rect().size == Vector2.ZERO, "idle chat did not fade away")
	chat.open()
	chat._render()
	await host.get_tree().process_frame
	_expect(chat._log.text.split("\n").size() == chat._entries.size(), "the open chat does not show the whole history")
	_expect(chat._field.is_visible_in_tree() and chat._channel_button.is_visible_in_tree(), "the open chat has no input or channel toggle")
	chat.toggle_channel()
	_expect(chat.channel == "nearby" and chat._channel_button.text == "NEARBY", "the channel toggle does not switch to NEARBY")
	chat.toggle_channel()
	# XR: the headset keyboard targets the chat field while it has focus
	var keyboard := XRKeyboard.new()
	host.add_child(keyboard)
	chat._field.grab_focus()
	for _i in 3:
		await host.get_tree().process_frame
	_expect(keyboard.target == chat._field, "the XR keyboard does not type into the chat field")
	keyboard.queue_free()
	chat.close()
	# quick chat -> pings on both maps
	_expect(InputMap.has_action(RoomChat.QUICK_ACTION), "no quick_chat action")
	_expect(RoomChat.pick_for_direction(Vector2.UP, 9) == 0 and RoomChat.pick_for_direction(Vector2.RIGHT, 9) == 2,
		"stick directions pick the wrong presets")
	var minimap: FacilityMap = hud.get("minimap")
	var plan: FacilityMap = hud.get("plan")
	_expect(chat.send_preset(0), "the first preset was not sent")
	await host.get_tree().process_frame
	_expect(minimap.live_pings().size() == 1 and plan.live_pings().size() == 1, "a quick-chat preset did not ping both maps")
	_expect((chat._entries[-1] as Dictionary).get("text") == RoomChat.PRESETS[0], "the preset line is not in the chat")
	_expect(not chat.send_preset(1), "a second ping within 2 s was not rate limited")
	remotes._ping_times.clear()
	chat.hunter_aim_provider = func() -> Dictionary: return {"at": Vector2(40, 12), "depth": GameState.depth}
	_expect(chat.send_preset(RoomChat.PRESETS.find("HUNTER!")), "HUNTER! was not sent")
	await host.get_tree().process_frame
	var hunter_ping: Dictionary = minimap.live_pings()[-1]
	_expect(hunter_ping["at"] == Vector2(40, 12), "HUNTER! did not ping the aimed hunter (%s)" % hunter_ping["at"])
	# phone: QUICK touch button feeds the action
	var has_quick := false
	for entry in TouchControls.BUTTONS:
		has_quick = has_quick or String(entry[2]) == RoomChat.QUICK_ACTION
	_expect(has_quick, "phones have no QUICK button")
	hud.queue_free()
	chat.queue_free()
	remotes.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  chat      NEARBY/TEAM by distance+level, idle fade vs history, colours/tags/system, rate limits, quick-chat pings on both maps, phone + XR paths")
	return _failures
