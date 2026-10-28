extends RefCounted

## Players never see the server's host, IP, port or URL: the BETA badge is gone, the TEST SERVER badge (debug builds on the test
## server only) carries no address, status and error lines are scrubbed (a connection failure reads CAN'T REACH THE SERVER), and
## no visible label in the hub, the Last Route menu, staging, the pause menu or the HUD names the server. Admins see it in the
## admin/debug readout only.
##
##   godot --headless --path . res://scenes/validate.tscn -- server_privacy

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _scan(root: Node, where: String) -> void:
	for node in root.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree():
			continue
		var text := ""
		if control is Label:
			text = (control as Label).text
		elif control is Button:
			text = (control as Button).text
		elif control is RichTextLabel:
			text = (control as RichTextLabel).get_parsed_text()
		elif control is LineEdit:
			text = (control as LineEdit).text + " " + (control as LineEdit).placeholder_text
		_expect(not ServerPrivacy.leaks(text), "%s: %s shows a server address: '%s'" % [where, control.name, text])


func _open(host: Node, path: String) -> Node:
	var node := (load(path) as PackedScene).instantiate()
	host.add_child(node)
	for _i in 3:
		await host.get_tree().process_frame
	return node


func run(host: Node) -> int:
	for leaky in ["BETA // lastroute.kyttuslab.org:8105", "http://127.0.0.1:18105", "join 203.0.113.5:8421", "relay :1105",
			"[2001:db8::1]:8105", "localhost:8205"]:
		_expect(ServerPrivacy.leaks(leaky), "'%s' is not recognised as an address" % leaky)
	for safe in ["DEPTH 12 // 3 RELAYS", "VERSION 0.0.1.0 // BUILD 117A18A8", "ROOM ABCDE", "12:04 KYTTU: hi", "LEVEL -1"]:
		_expect(not ServerPrivacy.leaks(safe), "'%s' is treated as an address" % safe)
	_expect(ServerPrivacy.scrub("HOST SIGNAL LOST // could not connect to 203.0.113.5:8421") == ServerPrivacy.FRIENDLY_UNREACHABLE,
		"a connection failure is not the friendly line")
	_expect(not ServerPrivacy.leaks(ServerPrivacy.scrub("ROOM LISTED ON lastroute.kyttuslab.org:8105")), "scrub left the address")
	RoomState.status_message = "PRIMARY SERVER UNAVAILABLE // SOLO ROOM // connect failed lastroute.kyttuslab.org:8105"
	_expect(RoomState.status_message == ServerPrivacy.FRIENDLY_UNREACHABLE, "RoomState.status_message keeps the address: %s" % RoomState.status_message)
	# badges: no BETA badge, TEST SERVER only for a debug build on the test server, never with an address
	var holder := Control.new()
	host.add_child(holder)
	TestServerBadge.attach(holder)
	var badge := holder.get_node_or_null("TestServerBadge") as Label
	_expect(badge == null or (Backend.test_server_active and badge.text == "TEST SERVER"), "a BETA/address badge is shown")
	holder.queue_free()
	# the screens players see
	for path in ["res://scenes/game_hub.tscn", "res://scenes/main_menu.tscn", "res://scenes/room_lobby.tscn", "res://scenes/hud.tscn"]:
		var node: Node = await _open(host, path)
		_scan(node, path.get_file())
		node.queue_free()
		await host.get_tree().process_frame
	var pause := PauseMenu.new()
	host.add_child(pause)
	await host.get_tree().process_frame
	pause.open()
	await host.get_tree().process_frame
	_scan(pause, "pause_menu")
	pause.close()
	pause.queue_free()
	_expect(ServerPrivacy.debug_line().begins_with("SERVER "), "the admin readout does not name the server")
	RoomState.status_message = ""
	await host.get_tree().process_frame
	if _failures == 0:
		print("  privacy   no host/IP/port/URL in player-facing text (hub, menu, staging, pause, HUD, statuses); badge only TEST SERVER; admin readout keeps it")
	return _failures
