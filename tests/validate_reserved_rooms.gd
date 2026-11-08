extends RefCounted

## Reserved private rooms, client side (the server side is backend/reserved_rooms.test.mjs): a join ticket becomes the
## relay nonce, owner commands from the heartbeat arrive once each and are acked, stored settings shape the hosted
## room, and the join dialog asks for the room password when the code is private.
##
##   godot4 --headless res://tests/scenes/validate.tscn -- reserved_rooms

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	_ticket_nonce()
	_commands_once()
	_codes()
	_settings()
	await _password_prompt(host)
	return _failures


func _ticket_nonce() -> void:
	var tunnel: Node = load("res://game/network/enet_relay_tunnel.gd").new()
	var raw := PackedByteArray([1, 2, 3, 250, 251, 252, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 255, 128])
	var ticket := Marshalls.raw_to_base64(raw).replace("+", "-").replace("/", "_").trim_suffix("=").trim_suffix("=")
	_expect(tunnel.start_guest("KTPRV", "127.0.0.1", 9, ticket) > 0, "the relay tunnel did not open")
	_expect(tunnel._nonce == raw, "the join ticket was not sent as the relay nonce (%s)" % tunnel._nonce)
	tunnel.start_guest("KTPRV", "127.0.0.1", 9)
	_expect(tunnel._nonce.size() == 12 and tunnel._nonce != raw, "an ordinary join reused a ticket")
	tunnel.close()
	tunnel.free()


func _commands_once() -> void:
	var seen := []
	var on_commands := func(commands: Array) -> void: seen.append_array(commands)
	Backend.reserved_commands_received.connect(on_commands)
	var view := {"settings": {"seed": "TEST SEED"}, "commands": [{"seq": 1, "command": "restart", "args": {}},
		{"seq": 2, "command": "kick", "args": {"target": "bob"}}]}
	Backend._take_reserved(view, true)
	Backend._take_reserved(view, false)   # the next heartbeat repeats them until they are acked
	_expect(seen.size() == 2, "owner commands were delivered %d times (each once)" % seen.size())
	_expect(String(Backend.reserved_settings.get("seed", "")) == "TEST SEED", "the stored settings were not kept")
	Backend.ack_reserved_command(2)
	_expect(Backend._reserved_ack == 2, "the ack was not recorded for the next heartbeat")
	Backend._take_reserved(null, true)
	_expect(Backend.reserved_settings.is_empty(), "an ordinary room kept a reserved room's settings")
	Backend.reserved_commands_received.disconnect(on_commands)
	_expect(Backend.take_join_ticket("ZZZZZ").is_empty(), "a join ticket leaked to another code")


func _codes() -> void:
	for code in ["KATHY", "AKIRI", "ABCDE"]:
		_expect(RoomState.valid_join_code(code), "the join box refuses %s" % code)
	_expect(not RoomState.valid_room_code("AKIRI"), "generated room codes now allow I")
	for bad in ["AKIR", "AK-RI", "AKIRIS"]:
		_expect(not RoomState.valid_join_code(bad), "the join box accepts %s" % bad)
	for i in 50:
		RoomState.create_local(RoomState.Mode.DEFAULT)
		_expect(RoomState.valid_room_code(RoomState.code), "a generated code %s left the spoken alphabet" % RoomState.code)


func _settings() -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.code = "KTPRV"
	RoomState._apply_reserved_settings({"seed": "TEST SEED", "difficulty": 1}, false)
	_expect(RoomState.seed_text == "TEST SEED", "the stored seed was not used (%s)" % RoomState.seed_text)
	RoomState._apply_reserved_settings({"seed": ""}, false)
	_expect(RoomState.seed_text != "TEST SEED" and RoomState.seed_text.begins_with("ROOM-KTPRV-"),
		"an empty stored seed did not give a fresh route (%s)" % RoomState.seed_text)
	var kept := RoomState.seed_text
	RoomState._apply_reserved_settings({"seed": "OTHER"}, true)
	_expect(RoomState.seed_text == kept, "a same-seed restart changed the seed")
	_expect(not RoomState.reserved, "create_local left the room marked private")
	RoomState._on_reserved_commands([{"seq": 1, "command": "end", "args": {}}])   # offline: must do nothing
	RoomState.create_local(RoomState.Mode.DEFAULT)


func _password_prompt(host: Node) -> void:
	var menu: Node = load("res://game/menus/main_menu.tscn").instantiate()
	host.add_child(menu)
	await host.get_tree().process_frame
	menu._on_join_pressed()
	Backend.reserved_room_access_needed.emit("KTPRV", "NOT ON THIS ROOM'S INVITE LIST // WRONG ROOM PASSWORD")
	var field := menu.find_child("RoomPasswordInput", true, false) as LineEdit
	_expect(field != null and field.secret, "a private room code did not ask for a hidden room password")
	var status := menu.find_child("JoinStatus", true, false) as Label
	_expect(status != null and status.text.contains("INVITE"), "the join dialog did not say why it was refused")
	if field != null:
		field.text = "room pass 1"
		menu._join_input.text = "KTPRV"
		# a headless run cannot reach the server, so HUB's offline mode would stop the join before the lookup
		var was_offline: bool = Backend.offline_mode
		Backend.offline_mode = false
		menu._submit_join()
		Backend.offline_mode = was_offline
		_expect(Backend.room_password == "room pass 1", "the typed password was not used for the lookup")
	Backend.room_password = ""
	menu._close_modal()
	menu.queue_free()
	await host.get_tree().process_frame
