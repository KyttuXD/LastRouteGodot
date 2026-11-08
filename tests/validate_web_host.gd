extends RefCounted

## a hidden browser tab stops the web build's game loop, so a room hosted from a browser froze for every
## guest. The web build no longer hosts co-op rooms (private CREATE ROOM, reserved rooms); it still joins rooms and
## may hold the public route. Guests hear a beat from the host every second and warn after 4 s of silence, or at once
## when a web host says its tab hid.
##
##   godot4 --headless res://tests/scenes/validate.tscn -- web_host

var TEST_PORT := 28491 + int(OS.get_environment("VALIDATE_PORT_OFFSET"))
var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	Backend.suppress_requests_for_tests()
	_check_refusal()
	_check_stall_warning()
	RoomState.simulate_web_for_tests = false
	RoomState.create_local(RoomState.Mode.DEFAULT)
	if _failures == 0:
		print("  web_host  browser refuses private hosting, keeps public route; guests warned of a quiet host")
	await host.get_tree().process_frame
	return _failures


func _check_refusal() -> void:
	# native: hosting is unchanged
	RoomState.simulate_web_for_tests = false
	RoomState.create_local(RoomState.Mode.DEFAULT)
	_expect(RoomState.web_host_refusal(false).is_empty(), "a native build was refused hosting")
	var error := RoomState.host_room(TEST_PORT)
	_expect(error.is_empty() and RoomState.online and RoomState.is_host, "native hosting broke: %s" % error)
	RoomState.leave_network()

	# web: CREATE ROOM stays a playable solo room with the reason on the staging screen
	RoomState.simulate_web_for_tests = true
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var solo_code := RoomState.code
	error = RoomState.host_primary_room(TEST_PORT)
	_expect(error == RoomState.WEB_HOST_REFUSED, "the web build hosted a private room (%s)" % error)
	_expect(not RoomState.online and RoomState.multiplayer.multiplayer_peer == null, "a refused web host still opened a transport")
	_expect(RoomState.code == solo_code and RoomState.roster().size() == 1, "a refused web host lost its solo room")
	_expect(RoomState.status_message.begins_with("SOLO ROOM") and "DESKTOP APP" in RoomState.status_message,
		"the refused web host was not told why (%s)" % RoomState.status_message)

	# web: a reserved private room is refused before the current room is touched
	RoomState.create_local(RoomState.Mode.DEFAULT)
	solo_code = RoomState.code
	error = RoomState.host_reserved_room("WEBXX", {})
	_expect(error == RoomState.WEB_HOST_REFUSED, "the web build hosted a reserved room (%s)" % error)
	_expect(RoomState.code == solo_code and not RoomState.reserved, "a refused reserved host replaced the room")

	# web: the public route may still be held (it hands over when its holder goes quiet)
	_expect(RoomState.web_host_refusal(true).is_empty(), "the web build was refused the public route")
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.public_route = true
	_expect(RoomState.web_host_refusal(RoomState.public_route).is_empty(), "public-route hosting refused on web")
	RoomState.create_local(RoomState.Mode.DEFAULT)

	# the create dialog says so on web
	var menu_source := FileAccess.get_file_as_string("res://game/menus/main_menu.gd")
	_expect(menu_source.contains("RoomState.web_host_refusal(false)"), "the CREATE ROOM dialog does not explain the web limit")
	var room_source := FileAccess.get_file_as_string("res://game/autoload/room_state.gd")
	_expect(room_source.contains('addEventListener("visibilitychange"'), "the web build does not listen for its tab hiding")
	var hud_source := FileAccess.get_file_as_string("res://game/hud/hud.gd")
	_expect(hud_source.contains("RoomState.host_stall_changed.connect"), "the HUD does not show the quiet-host warning")


func _check_stall_warning() -> void:
	RoomState.simulate_web_for_tests = false
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var seen := []
	var listener := func(stalled: bool, message: String) -> void: seen.append([stalled, message])
	RoomState.host_stall_changed.connect(listener)
	# a guest whose host is silent: fake an online guest with a peer attached
	var peer := OfflineMultiplayerPeer.new()
	RoomState.multiplayer.multiplayer_peer = peer
	RoomState.online = true
	RoomState.is_host = false
	RoomState.connecting = false
	for i in 15:
		RoomState._tick_host_presence(0.25)   # 3.75 s
	_expect(not RoomState.host_stalled, "a guest warned before %.0f s of host silence" % RoomState.HOST_STALL_SECONDS)
	RoomState._tick_host_presence(0.25)
	_expect(RoomState.host_stalled and RoomState.status_message == RoomState.HOST_STALL_NOTICE,
		"a guest did not warn after %.0f s of host silence" % RoomState.HOST_STALL_SECONDS)
	_expect(seen.size() == 1 and seen[0][0] == true, "the stall signal did not fire once (%s)" % [seen])
	RoomState._receive_host_beat()
	_expect(not RoomState.host_stalled and RoomState.status_message.is_empty(), "the host's beat did not clear the warning")
	_expect(seen.size() == 2 and seen[1] == [false, RoomState.HOST_BACK_NOTICE], "no HOST IS BACK line (%s)" % [seen])
	# the guest's OWN hidden tab: one huge frame must not read as a silent host
	RoomState._tick_host_presence(30.0)
	_expect(not RoomState.host_stalled, "one long frame on the guest (its own hidden tab) read as a silent host")
	# a web host announcing its hidden tab warns at once, and coming back clears it
	RoomState._receive_host_hidden(true)
	_expect(RoomState.host_stalled and RoomState.status_message == RoomState.HOST_HIDDEN_NOTICE, "a hidden host tab did not warn guests")
	RoomState._receive_host_hidden(false)
	_expect(not RoomState.host_stalled, "the host tab coming back did not clear the warning")
	# room updates count as hearing from the host
	for i in 20:
		RoomState._tick_host_presence(0.25)
	_expect(RoomState.host_stalled, "the stall did not come back after more silence")
	RoomState._heard_from_host()
	_expect(not RoomState.host_stalled, "hearing from the host did not clear the stall")
	# a host never warns about itself
	RoomState.is_host = true
	for i in 40:
		RoomState._tick_host_presence(0.25)
	_expect(not RoomState.host_stalled, "the host warned about itself")
	RoomState.host_stall_changed.disconnect(listener)
	RoomState.online = false
	RoomState.multiplayer.multiplayer_peer = null
	RoomState.create_local(RoomState.Mode.DEFAULT)
	_expect(not RoomState.host_stalled, "leaving kept the stall flag")
