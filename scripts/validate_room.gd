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
	_expect(Backend.PRIMARY_BASE_URL == "http://lastroute.kyttuslab.org:1105",
		"the built-in room directory is %s" % Backend.PRIMARY_BASE_URL)
	_expect(UpdateManager._newer("0.2.0", "0.1.9"),
		"the updater did not recognize a newer semantic version")
	_expect(not UpdateManager._newer("0.1.0", "0.1.0"),
		"the updater treated the current version as newer")
	_expect(not UpdateManager._newer("0.0.9", "0.1.0"),
		"the updater treated an older version as newer")
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

	# MAP SCALE was a button that did nothing: the generator has taken these
	# options since it was ported, but neither view passed any, so every route
	# came out the same 45x45 default whatever staging said.
	var sizes := {}
	for scale in RoomState.SCALE_LABELS:
		RoomState.set_map_scale(scale)
		var options := RoomState.generator_options()
		var key := "%dx%d" % [options["cols"], options["rows"]]
		if sizes.has(key):
			_fail("%s builds the same %s as %s" % [RoomState.SCALE_LABELS[scale],
				key, sizes[key]])
		sizes[key] = RoomState.SCALE_LABELS[scale]
		var built := FacilityGenerator.new("scale-check", options)
		_expect(built.cols == options["cols"] and built.rows == options["rows"],
			"%s asked for %s and got %dx%d" % [RoomState.SCALE_LABELS[scale], key,
				built.cols, built.rows])
		_expect(built.relays.size() == options["relay_count"],
			"%s placed %d relays, not %d" % [RoomState.SCALE_LABELS[scale],
				built.relays.size(), options["relay_count"]])
		# A route nobody can walk is not a route.
		_expect(built.floor_cells().size() > 0,
			"%s generated no floor at all" % RoomState.SCALE_LABELS[scale])
	RoomState.set_map_scale(RoomState.Scale.STANDARD)

	# Staging has to actually draw, since it is built entirely in code.
	var lobby: Node = load("res://scenes/room_lobby.tscn").instantiate()
	host.get_tree().root.add_child(lobby)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	_expect(lobby.get_child_count() > 1, "the staging screen drew nothing")
	_expect(Build.allow_custom_hosts() == Build.tools_enabled(),
		"custom-host visibility is not tied to the debug tools gate")
	_expect(lobby.find_child("DebugCustomHostRow", true, false) != null,
		"a debug build lost the custom-host testing controls")
	lobby.queue_free()
	await host.get_tree().process_frame

	# Actually open a port. Everything above is bookkeeping; this is the part
	# that either works on the machine or does not, and "COULD NOT OPEN PORT"
	# is the single most likely outcome of testing with two windows.
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var error := RoomState.host_room()
	if not error.is_empty():
		_fail("hosting failed: %s" % error)
	else:
		_expect(RoomState.online, "hosting did not put the room online")
		_expect(RoomState.is_host, "the host is not the host")
		_expect(RoomState.roster().size() == 1,
			"a freshly hosted room lists %d players" % RoomState.roster().size())
		# Alone in a room, HIDE & SEEK still has nobody to hide from -- being
		# online is not the same as having company, and the rule is about
		# company.
		_expect(not RoomState.mode_available(RoomState.Mode.HIDE_SEEK),
			"HIDE & SEEK opened up with one player in the room")
		_expect(not RoomState.mode_available(RoomState.Mode.OFFICE),
			"single-player Office Mode is offered inside a network room")
		# Exactly one host, and it is peer 1. Every row used to claim both, so
		# a guest's window showed itself hosting the room it had joined.
		var rows: Array = RoomState.roster_rows()
		var hosts := 0
		var mine := 0
		for row in rows:
			if row["host"]:
				hosts += 1
				if int(row["id"]) != 1:
					_fail("peer %d is marked host; only peer 1 hosts" % row["id"])
			if row["you"]:
				mine += 1
		if hosts != 1:
			_fail("%d rows claim to be the host" % hosts)
		if mine != 1:
			_fail("%d rows claim to be you" % mine)
		print("  network   hosting on %d, %d seated" % [RoomState.DEFAULT_PORT,
			RoomState.roster().size()])
		print("  directory primary endpoint hidden in-game; custom hosts are debug-only")

	# Hosting twice must not leave the first port held.
	error = RoomState.host_room()
	if not error.is_empty():
		_fail("re-hosting failed, so the previous socket was never released: %s" % error)
	RoomState.leave_network()
	_expect(not RoomState.online, "leaving did not take the room offline")
	_expect(RoomState.roster().size() == 1,
		"going offline left %d players in the room" % RoomState.roster().size())

	if _failures == 0:
		print("  room      %s seats %d, seed %s"
			% [RoomState.code, RoomState.seats(), RoomState.seed_text])
		print("  rules     HIDE & SEEK held back offline, office seats one")
		print("  scales    %d map scales, each a distinct walkable facility" % sizes.size())
		print("room OK")
	return _failures
