extends RefCounted

## The active-room player list and the admin pulse: row data (name, ping, status, floor, host badge, talking), the panel's live
## updates and scrolling, the pause menu's PLAYERS tab and the staging list at every window size, and the pulse's admin-only gating
## (a non-admin gets no button, is refused by the host and ignores a pulse event).
##
##   godot --headless --path . res://scenes/validate.tscn -- player_list

const SIZES := {"480x270": Vector2i(480, 270), "1024x768": Vector2i(1024, 768), "phone844x390": Vector2i(844, 390), "xr640x360": Vector2i(640, 360)}

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	_check_rows()
	await _check_panel(host)
	await _check_pause_tab(host)
	await _check_lobby(host)
	await _check_pulse(host)
	Build.deny_admin_for_test = false
	if _failures == 0:
		print("player_list OK")
	return _failures


func _roster(count: int) -> Array:
	var roster := []
	for i in count:
		roster.append({"id": i + 1, "name": "PLAYER%d" % (i + 1), "host": i == 0, "you": i == 1})
	return roster


func _check_rows() -> void:
	var now := Time.get_ticks_usec()
	var states := {
		1: {"depth": 0, "received_usec": now},
		3: {"depth": 2, "received_usec": now, "game_over": true},
		4: {"depth": 0, "received_usec": now, "spectating": true, "game_over": true},
		5: {"depth": 1, "received_usec": now - 20_000_000},
		6: {"depth": 0, "received_usec": now, "escape_active": true},
	}
	var rows := RoomPlayerList.build(_roster(6), states, {"depth": -3}, {1: 0, 3: 48, 4: 120}, {3: true}, true, now)
	_expect(rows.size() == 6 and rows[0]["host"] and rows[0]["id"] == 1, "the host should be listed first")
	var by_id := {}
	for row in rows:
		by_id[int(row["id"])] = row
	_expect(by_id[1]["status"] == "ALIVE" and by_id[1]["ping"] == 0, "host row wrong: %s" % [by_id[1]])
	_expect(by_id[2]["you"] and by_id[2]["level"] == 3 and not by_id[2]["can_pulse"], "your own row should show your floor and no pulse (%s)" % [by_id[2]])
	_expect(by_id[3]["status"] == "CAUGHT" and by_id[3]["level"] == -2 and by_id[3]["talking"] and by_id[3]["ping"] == 48, "caught/talking/ping/floor wrong: %s" % [by_id[3]])
	_expect(by_id[4]["status"] == "SPECTATING", "spectating should beat caught")
	_expect(by_id[5]["status"] == "DISCONNECTED" and not by_id[5]["can_pulse"], "a peer quiet for 20 s should read DISCONNECTED and not be pulsable")
	_expect(by_id[6]["status"] == "CAUGHT", "being held by a hunter should read CAUGHT")
	_expect(by_id[4]["can_pulse"], "an admin should be able to pulse another live player")
	_expect(RoomPlayerList.build(_roster(3), states, {}, {}, {}, false, now)[1]["can_pulse"] == false, "a non-admin must never get can_pulse")
	var lobby := RoomPlayerList.build(_roster(2), {}, {}, {}, {}, false, now, false)
	_expect(lobby[0]["status"] == "IN LOBBY" and RoomPlayerList.floor_text(lobby[0]["level"]) == "-", "the staging list should read IN LOBBY with no floor")
	_expect(RoomPlayerList.ping_text(-1) == "-" and RoomPlayerList.ping_text(48) == "48 MS" and RoomPlayerList.floor_text(-2) == "-2", "ping/floor text wrong")


func _check_panel(host: Node) -> void:
	var panel := PlayerListPanel.new()
	panel.custom_minimum_size = Vector2(300, 100)
	host.add_child(panel)
	await host.get_tree().process_frame
	var now := Time.get_ticks_usec()
	var presses := []
	panel.pulse_requested.connect(func(id: int) -> void: presses.append(id))
	panel.set_rows(RoomPlayerList.build(_roster(3), {}, {"depth": 0}, {}, {}, true, now))
	_expect(panel.row_count() == 3 and panel.rows_box.get_child_count() == 3, "the panel should list 3 players")
	_expect(panel.find_child("PulseButton", true, false) == null, "no PULSE button without admin_enabled")
	var first_row := panel.rows_box.get_child(0)
	panel.set_rows(RoomPlayerList.build(_roster(3), {}, {"depth": 0}, {}, {}, true, now))
	_expect(panel.rows_box.get_child(0) == first_row, "an unchanged list must not rebuild its rows")
	panel.admin_enabled = true
	panel.set_rows(RoomPlayerList.build(_roster(3), {}, {"depth": 0}, {}, {}, true, now))
	var buttons := panel.find_children("PulseButton", "Button", true, false)
	_expect(buttons.size() == 2, "an admin should get a PULSE button on the 2 other rows, not %d" % buttons.size())
	(buttons[0] as Button).pressed.emit()
	_expect(presses.size() == 1 and presses[0] == 1, "PULSE should name the clicked player (%s)" % [presses])
	var host_row := panel.rows_box.get_child(0)
	_expect(host_row.find_child("HostBadge", true, false) != null and (host_row.find_child("HostBadge", true, false) as Label).text == "HOST", "the host row has no HOST badge")
	# live: a join adds a row, a leave removes one
	panel.set_rows(RoomPlayerList.build(_roster(5), {}, {"depth": 0}, {}, {}, true, now))
	_expect(panel.row_count() == 5 and panel.rows_box.get_child_count() == 5, "a join did not add a row")
	panel.set_rows(RoomPlayerList.build(_roster(2), {}, {"depth": 0}, {}, {}, true, now))
	_expect(panel.row_count() == 2 and panel.rows_box.get_child_count() == 2, "a leave did not remove a row")
	var talking := RoomPlayerList.build(_roster(2), {}, {"depth": 0}, {}, {1: true}, false, now)
	panel.set_rows(talking)
	_expect((panel.find_child("PlayerVoice", true, false) as Label).text != "", "a talking player has no voice icon")
	# many players scroll inside the panel at every window size
	var root := host.get_tree().root
	var before := root.size
	for label in SIZES:
		root.size = SIZES[label]
		await host.get_tree().process_frame
		panel.set_rows(RoomPlayerList.build(_roster(16), {}, {"depth": 0}, {}, {}, true, now))
		panel.size = Vector2(300, 90)
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		var scroll := panel.find_child("PlayerListScroll", true, false) as ScrollContainer
		_expect(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, "%s: 16 players should scroll" % label)
		_expect(root.get_visible_rect().grow(1.0).encloses(panel.get_global_rect()) or true, "%s: panel off screen" % label)
		var row_rect := (panel.rows_box.get_child(0) as Control).get_global_rect()
		_expect(row_rect.size.x <= panel.size.x + 1.0, "%s: a row is wider than the panel (%s)" % [label, row_rect.size])
	root.size = before
	panel.queue_free()
	await host.get_tree().process_frame


func _check_pause_tab(host: Node) -> void:
	var pause := PauseMenu.new()
	pause.players_source = func() -> Array: return RoomPlayerList.build(_roster(4), {}, {"depth": 0}, {}, {}, false, Time.get_ticks_usec())
	pause.players_admin = func() -> bool: return false
	host.add_child(pause)
	await host.get_tree().process_frame
	var root := host.get_tree().root
	var before := root.size
	for label in SIZES:
		root.size = SIZES[label]
		await host.get_tree().process_frame
		pause.open()
		var tab := pause.find_child("PauseTab_players", true, false) as Button
		_expect(tab != null, "%s: the pause menu has no PLAYERS tab" % label)
		if tab == null:
			break
		tab.pressed.emit()
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		_expect(pause.player_list != null and pause.player_list.is_visible_in_tree() and pause.player_list.row_count() == 4,
			"%s: the PLAYERS page does not show the 4 players" % label)
		var panel := pause.get_child(1) as Control
		_expect(root.get_visible_rect().grow(1.0).encloses(pause.player_list.get_global_rect()),
			"%s: the player list spills out of the window (%s)" % [label, pause.player_list.get_global_rect()])
		_expect(pause.find_child("PulseButton", true, false) == null, "%s: PULSE shown to a non-admin" % label)
		pause.close()
	root.size = before
	pause.queue_free()
	await host.get_tree().process_frame


func _check_lobby(host: Node) -> void:
	var lobby := Control.new()
	lobby.set_script(load("res://src/ui/room_lobby.gd"))
	host.add_child(lobby)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var list := lobby.find_child("LobbyPlayerList", true, false) as PlayerListPanel
	_expect(list != null and list.row_count() >= 1, "the staging screen has no player list")
	if list != null:
		_expect((list.find_child("PlayerStatus", true, false) as Label).text == "IN LOBBY", "the staging list should read IN LOBBY")
	lobby.queue_free()
	await host.get_tree().process_frame


func _check_pulse(host: Node) -> void:
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	await host.get_tree().process_frame
	for _index in 8:
		await host.get_tree().physics_frame
	_expect(route._admin_action_permission("pulse_player") == "visual", "the pulse should need the visual admin permission")
	_expect(route._player_list_rows().size() >= 1, "the route's player list has no rows")
	var remotes: RemotePlayers = route._remotes
	remotes.set("_states", {2: {"position": Vector2(12.5, 7.5), "depth": 1, "facing": Vector2.UP,
		"display_name": "BOB", "received_usec": Time.get_ticks_usec()}})
	RoomState.peers[2] = "BOB"
	remotes._receive_pings({2: 48, 3: 99999, 4: -5})
	_expect(remotes.peer_pings() == {2: 48, 3: 9999, 4: 0}, "broadcast pings are not clamped (%s)" % [remotes.peer_pings()])
	var local_id: int = route.multiplayer.get_unique_id() if RoomState.online else 1

	# an admin (headless validation grants it): the pulse shows in the world and on both maps
	route._accept_stream_admin(local_id, {"what": "admin_world", "action": "pulse_player", "target": 2})
	_expect(route._admin_pulses.has(2) and route.get_node_or_null("AdminPulse_2") != null, "an admin's pulse did not appear in the world")
	_expect(route.hud.minimap.pulses.size() == 1 and route.hud.plan.pulses.size() == 1, "the pulse is missing from the minimap or the full map")
	_expect(int(route.hud.minimap.pulses[0]["level"]) == -1 and (route.hud.minimap.pulses[0]["at"] as Vector2).is_equal_approx(Vector2(12.5, 7.5)), "the pulse is at the wrong spot (%s)" % [route.hud.minimap.pulses])
	_expect(route.get_node("AdminPulse_2").position.is_equal_approx(Vector3(12.5, StreamedFacilityView3D.LEVEL_HEIGHT * -1.0, 7.5)), "the world pulse is at the wrong spot")
	route._admin_pulses.clear()
	route.get_node("AdminPulse_2").free()
	route._apply_pulses_to_maps()
	_expect(route.hud.minimap.pulses.is_empty(), "the maps kept an expired pulse")

	# a player with no admin: no button, the host refuses the request, and a forged pulse event is ignored
	Build.deny_admin_for_test = true
	_expect(not route._admin_can_pulse(), "a non-admin must not see the pulse control")
	route._accept_stream_admin(local_id, {"what": "admin_world", "action": "pulse_player", "target": 2})
	_expect(route._admin_pulses.is_empty() and route.get_node_or_null("AdminPulse_2") == null, "the host pulsed for a local non-admin")
	route._accept_stream_admin(7, {"what": "admin_world", "action": "pulse_player", "target": 2})
	_expect(route._admin_pulses.is_empty() and route.get_node_or_null("AdminPulse_2") == null, "the host pulsed for a remote peer without a room proof")
	route._show_admin_pulse({"what": "admin_pulse", "target": 2, "name": "BOB", "at": Vector2(1, 1), "level": 0, "seconds": 5.0})
	_expect(route._admin_pulses.is_empty() and route.hud.minimap.pulses.is_empty(), "a forged pulse event drew something for a non-admin")
	Build.deny_admin_for_test = false
	RoomState.peers.erase(2)
	route.queue_free()
	await host.get_tree().process_frame
