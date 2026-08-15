extends RefCounted

## Headless check on the room.
##
## The point of introducing rooms before there is any networking is that
## singleplayer stops being a second code path -- so what is worth testing is
## exactly that: a solo session really is a one-player room, and the rules that
## will matter online (which modes need other people, who seats how many) are
## properties of the ROOM rather than of whichever button was pressed.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- room

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	_expect(RoomState.code.length() == RoomState.CODE_LENGTH,
		"room code is %d characters" % RoomState.code.length())
	for glyph in RoomState.code:
		_expect(RoomState.CODE_ALPHABET.contains(glyph),
			"room code contains '%s', which is not in the spoken-aloud alphabet" % glyph)
	_expect(RoomState.players.size() == 1, "a local room seated %d players"
		% RoomState.players.size())
	_expect(RoomState.is_host, "the host of a local room is not the local player")
	_expect(not RoomState.online, "a local room reports itself online")
	_expect(RoomState.seed_text.begins_with("ROOM-%s-" % RoomState.code),
		"route seed %s does not name its own room" % RoomState.seed_text)

	# The seed on screen and the facility on the floor must agree, which means
	# the run seed is derived from the text rather than stored beside it.
	var before := RoomState.run_seed()
	_expect(RoomState.run_seed() == before, "run seed is not stable for one route")
	var text := RoomState.seed_text
	RoomState.reroll_seed()
	_expect(RoomState.seed_text != text, "rerolling produced the same route")
	_expect(RoomState.code == RoomState.code, "rerolling changed the room code")
	_expect(RoomState.run_seed() != before, "a new route seed gave the same run seed")

	# HIDE & SEEK needs someone to hide from. That is the room's rule, so it
	# has to hold when set_mode is called directly and not only when a button
	# happens to be disabled.
	_expect(not RoomState.mode_available(RoomState.Mode.HIDE_SEEK),
		"HIDE & SEEK is offered with nobody else in the room")
	RoomState.set_mode(RoomState.Mode.HIDE_SEEK)
	_expect(RoomState.mode != RoomState.Mode.HIDE_SEEK,
		"set_mode let an unavailable mode through")
	_expect(not RoomState.mode_unavailable_reason(RoomState.Mode.HIDE_SEEK).is_empty(),
		"an unavailable mode gives no reason")
	for allowed in [RoomState.Mode.DEFAULT, RoomState.Mode.OFFICE]:
		_expect(RoomState.mode_available(allowed),
			"%s is unavailable solo" % RoomState.MODE_LABELS[allowed])

	# Office Mode is singleplayer by design, however the room was opened.
	RoomState.create_local(RoomState.Mode.OFFICE)
	_expect(RoomState.seats() == 1, "office mode seats %d" % RoomState.seats())
	_expect(RoomState.start_label() == "START OFFICE SHIFT",
		"office staging says '%s'" % RoomState.start_label())
	RoomState.create_local(RoomState.Mode.DEFAULT)
	_expect(RoomState.seats() == RoomState.MAX_PLAYERS,
		"a route seats %d, not %d" % [RoomState.seats(), RoomState.MAX_PLAYERS])
	_expect(RoomState.start_label() == "ENTER ROUTE",
		"route staging says '%s'" % RoomState.start_label())

	# Staging has to actually draw, since it is built entirely in code.
	var lobby: Node = load("res://scenes/room_lobby.tscn").instantiate()
	host.get_tree().root.add_child(lobby)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	_expect(lobby.get_child_count() > 1, "the staging screen drew nothing")
	lobby.queue_free()
	await host.get_tree().process_frame

	if _failures == 0:
		print("  room      %s seats %d, seed %s"
			% [RoomState.code, RoomState.seats(), RoomState.seed_text])
		print("  rules     HIDE & SEEK held back offline, office seats one")
		print("room OK")
	return _failures
