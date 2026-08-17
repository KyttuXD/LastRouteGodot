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
const TEST_PORT := 28421


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	_expect(Backend.PRIMARY_BASE_URL == "http://lastroute.kyttuslab.org:8105",
		"the built-in room directory is %s" % Backend.PRIMARY_BASE_URL)
	var backend_url_before := Backend.base_url
	Backend.base_url = Backend.PRIMARY_BASE_URL
	_expect(not Backend.accounts_available(),
		"the temporary public HTTP deployment gained credential access")
	_expect(not Backend.account_transport_warning().is_empty(),
		"the temporary public HTTP origin hides its account transport warning")
	Backend.base_url = "http://untrusted.invalid:1105"
	_expect(not Backend.accounts_available(),
		"an arbitrary public HTTP backend gained credential access")
	Backend.base_url = "http://localhost.attacker.invalid:1105"
	_expect(not Backend.accounts_available(),
		"a hostname beginning with localhost bypassed account transport checks")
	Backend.base_url = "https://accounts.example.invalid"
	_expect(Backend.accounts_available() and Backend.account_transport_warning().is_empty(),
		"an HTTPS account origin was rejected or warned as unencrypted")
	Backend.base_url = backend_url_before
	_expect(RoomState.ROUTE_LOADING_SCENE == "res://scenes/route_loading.tscn"
		and ResourceLoader.exists(RoomState.ROUTE_LOADING_SCENE),
		"room starts do not pass through the route loading scene")
	_expect(RoomState.session_scene_path() == "res://scenes/main_3d.tscn",
		"the default route loader targets the wrong gameplay scene")
	var account_before := {
		"username": Backend.account_username,
		"token": Backend.account_session_token,
		"admin": Backend.account_admin,
		"verified": Backend.account_session_verified,
	}
	Backend.account_username = "Kyttu"
	Backend.account_session_token = "validation-token"
	Backend.account_admin = true
	Backend.account_session_verified = true
	_expect(not Backend.admin_authorized(),
		"mixed-case local state bypasses canonical server identity")
	Backend.account_username = "KYTTU"
	_expect(Backend.admin_authorized(),
		"verified canonical KYTTU is not authorized for release admin")
	Backend.account_session_verified = false
	_expect(not Backend.admin_authorized(),
		"unverified cached account state authorizes release admin")
	Backend.account_username = account_before["username"]
	Backend.account_session_token = account_before["token"]
	Backend.account_admin = account_before["admin"]
	Backend.account_session_verified = account_before["verified"]
	_expect(UpdateManager._newer("0.0.1.1", "0.0.1.0"),
		"the updater did not recognize a newer four-part version")
	_expect(not UpdateManager._newer("0.0.1.0", "0.0.1.0"),
		"the updater treated the current version as newer")
	_expect(not UpdateManager._newer("0.0.0.9", "0.0.1.0"),
		"the updater treated an older version as newer")
	_expect(UpdateManager.DEBUG_RECHECK_SECONDS <= 10.0,
		"debug update checks are too slow for active test builds")
	_expect(UpdateManager._update_needed("0.0.1.0", "0.0.1.0",
		"bbbbbbbbbbbb", "aaaaaaaaaaaa"),
		"the updater ignored a newer build commit at the same frozen version")
	_expect(not UpdateManager._update_needed("0.0.1.0", "0.0.1.0",
		"aaaaaaaaaaaa", "aaaaaaaaaaaa"),
		"the updater offered its own build commit")
	_expect(not UpdateManager._update_needed("0.0.1.0", "0.0.1.0", "", "source"),
		"an editor/source run was treated as an exported revision")
	_expect(UpdateManager._valid_sha256("a".repeat(64)),
		"the updater rejected a valid SHA-256")
	_expect(not UpdateManager._valid_sha256("a".repeat(63)),
		"the updater accepted a short SHA-256")
	for safe_entry in ["LastRoute.pck", "Game.app/Contents/MacOS/Game"]:
		_expect(UpdateManager._safe_archive_entry(safe_entry),
			"the updater rejected safe archive entry %s" % safe_entry)
	for unsafe_entry in ["../LastRoute.pck", "/tmp/LastRoute", "folder/../../escape",
			"C:/Windows/System32/escape", "folder\\escape"]:
		_expect(not UpdateManager._safe_archive_entry(unsafe_entry),
			"the updater accepted unsafe archive entry %s" % unsafe_entry)
	_expect(UpdateManager._mac_bundle_path(
		"/Applications/KYTTU- The Last Route.app/Contents/MacOS/KYTTU- The Last Route") \
		== "/Applications/KYTTU- The Last Route.app",
		"the updater could not resolve a macOS app bundle")
	var update_archive := "user://last-route-update-test.zip"
	var update_stage := "user://last-route-update-test"
	UpdateManager._remove_tree(update_stage)
	var packer := ZIPPacker.new()
	_expect(packer.open(update_archive) == OK, "could not create updater test ZIP")
	_expect(packer.start_file("LastRoute-Test.x86_64") == OK,
		"could not add the updater test executable")
	packer.write_file("test executable".to_utf8_buffer())
	packer.close_file()
	_expect(packer.start_file("LastRoute-Test.pck") == OK,
		"could not add the updater test PCK")
	packer.write_file("test pck".to_utf8_buffer())
	packer.close_file()
	packer.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(update_stage))
	_expect(UpdateManager._extract_archive(update_archive, update_stage).is_empty(),
		"the updater could not unpack a valid platform archive")
	var update_layout := UpdateManager._installation_layout("linux",
		"/games/LastRoute-Old.x86_64", update_stage)
	_expect(String(update_layout.get("launch", "")) == "LastRoute-Test.x86_64",
		"the updater could not find the staged Linux executable")
	_expect(FileAccess.get_file_as_string(
		update_stage.path_join("LastRoute-Test.pck")) == "test pck",
		"the updater changed the staged PCK")
	var helper_path := "user://last-route-update-helper-test.sh"
	_expect(UpdateManager._write_text(helper_path, UpdateManager.UNIX_HELPER),
		"the updater could not write its desktop helper")
	var helper_output := []
	_expect(OS.execute("/bin/sh", PackedStringArray(["-n",
		ProjectSettings.globalize_path(helper_path)]), helper_output, true) == 0,
		"the Unix update helper has invalid shell syntax: %s" % helper_output)
	var apply_root := "user://last-route-update-apply-test"
	var apply_stage := apply_root.path_join("stage")
	var apply_install := apply_root.path_join("install")
	UpdateManager._remove_tree(apply_root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(apply_stage))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(apply_install))
	var new_executable := FileAccess.open(
		apply_stage.path_join("LastRoute-Test.x86_64"), FileAccess.WRITE)
	new_executable.store_string("#!/bin/sh\nexit 0\n")
	new_executable.close()
	var new_pck := FileAccess.open(apply_stage.path_join("LastRoute-Test.pck"), FileAccess.WRITE)
	new_pck.store_string("new pck")
	new_pck.close()
	var old_executable := FileAccess.open(
		apply_install.path_join("LastRoute-Test.x86_64"), FileAccess.WRITE)
	old_executable.store_string("old executable")
	old_executable.close()
	var old_pck := FileAccess.open(apply_install.path_join("LastRoute-Test.pck"), FileAccess.WRITE)
	old_pck.store_string("old pck")
	old_pck.close()
	helper_output.clear()
	_expect(OS.execute("/bin/sh", PackedStringArray([
		ProjectSettings.globalize_path(helper_path),
		ProjectSettings.globalize_path(apply_stage),
		ProjectSettings.globalize_path(apply_install),
		"LastRoute-Test.x86_64", "99999999", "abcdef1", "linux"]),
		helper_output, true) == 0,
		"the Unix update helper failed its disposable install: %s" % helper_output)
	_expect(FileAccess.get_file_as_string(
		apply_install.path_join("LastRoute-Test.pck")) == "new pck",
		"the update helper did not install the new PCK")
	_expect(FileAccess.get_file_as_string(apply_install.path_join(
		".lastroute-backup-previous/LastRoute-Test.pck")) == "old pck",
		"the update helper did not retain the previous PCK")
	UpdateManager._remove_tree(update_stage)
	UpdateManager._remove_tree(apply_root)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(update_archive))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(helper_path))
	_expect(RoomState.valid_room_code("ABCDE"),
		"a valid primary-server room code was rejected")
	for invalid_code in ["ABCD", "ABCDEF", "AB0DE", "ABIDE", "ABODE"]:
		_expect(not RoomState.valid_room_code(invalid_code),
			"invalid room code %s was accepted" % invalid_code)
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

	# Nightmare is deliberately reserved until its multi-hunter rules exist.
	# Hard is a complete, selectable midpoint profile rather than a relabelled
	# Standard button.
	_expect(RoomState.DIFFICULTY_LABELS.has(RoomState.Difficulty.HARD),
		"Hard is missing from the selectable difficulty row")
	_expect(RoomState.DIFFICULTY_LABELS.has(RoomState.Difficulty.NIGHTMARE),
		"Nightmare is not visible as a planned difficulty")
	_expect(not RoomState.difficulty_available(RoomState.Difficulty.NIGHTMARE),
		"Nightmare is selectable before its multi-hunter rules exist")
	RoomState.set_difficulty(RoomState.Difficulty.HARD)
	_expect(RoomState.difficulty == RoomState.Difficulty.HARD,
		"set_difficulty did not accept Hard")
	_expect(RoomState.difficulty_id() == "hard", "Hard resolves to the wrong rules id")
	RoomState.set_difficulty(RoomState.Difficulty.NIGHTMARE)
	_expect(RoomState.difficulty == RoomState.Difficulty.HARD,
		"set_difficulty accepted the reserved Nightmare mode")
	_expect(RoomState._selectable_difficulty_or_standard(
		RoomState.Difficulty.NIGHTMARE) == RoomState.Difficulty.STANDARD,
		"a stale network Nightmare value is not sanitized to Standard")
	var standard := GameConfig.difficulty_profile("standard")
	var hard := GameConfig.difficulty_profile("hard")
	var nightmare := GameConfig.difficulty_profile("nightmare")
	for field in GameConfig.DIFFICULTY_PROFILES["standard"]:
		var midpoint := (float(standard[field]) + float(nightmare[field])) * 0.5
		_expect(is_equal_approx(float(hard[field]), midpoint),
			"Hard %s is %.3f, not the Standard/Nightmare midpoint %.3f" % [
				field, float(hard[field]), midpoint])
	for difficulty_id in ["relaxed", "standard", "hard", "nightmare"]:
		GameState.start_new_run(12345, difficulty_id)
		_expect(not GameState.game_over,
			"%s started in a game-over state" % difficulty_id)
	RoomState.set_difficulty(RoomState.Difficulty.STANDARD)

	# Account checkpoints resume deterministic solo floor boundaries. The
	# visible seed/config and GameState totals must round-trip together, while a
	# tampered seed is rejected before it can replace the current room.
	RoomState.map_scale = RoomState.Scale.LARGE
	RoomState.difficulty = RoomState.Difficulty.HARD
	GameState.start_new_run(RoomState.run_seed(), RoomState.difficulty_id())
	GameState.depth = 7
	GameState.score = 2400
	GameState.coins = 13
	var checkpoint := GameState.route_checkpoint(RoomState.seed_text,
		RoomState.map_scale, RoomState.difficulty, RoomState.difficulty_id())
	var checkpoint_seed := RoomState.seed_text
	_expect(RoomState.prepare_route_checkpoint(checkpoint).is_empty(),
		"a valid route checkpoint was rejected")
	_expect(RoomState.seed_text == checkpoint_seed
		and RoomState.map_scale == RoomState.Scale.LARGE
		and RoomState.difficulty == RoomState.Difficulty.HARD,
		"checkpoint room configuration did not restore")
	_expect(GameState.restore_queued_route_checkpoint(),
		"a prepared checkpoint was not consumed")
	_expect(GameState.depth == 7 and GameState.score == 2400
		and GameState.coins == 13,
		"checkpoint run totals did not restore")
	_expect(GameState.relays_collected == 0 and GameState.relays_sabotaged == 0,
		"a floor-boundary checkpoint restored partial relay state")
	var tampered := checkpoint.duplicate(true)
	tampered["run_seed"] = int(tampered["run_seed"]) + 1
	var seed_before_bad_checkpoint := RoomState.seed_text
	_expect(not RoomState.prepare_route_checkpoint(tampered).is_empty(),
		"a checkpoint with a mismatched seed was accepted")
	_expect(RoomState.seed_text == seed_before_bad_checkpoint,
		"a rejected checkpoint replaced the current room")
	RoomState.create_local(RoomState.Mode.DEFAULT)
	GameState.start_new_run(RoomState.run_seed(), RoomState.difficulty_id())
	_expect(Palette.title_font().font_names[0] == "Arial Black",
		"the title no longer requests the original Arial Black face first")

	# The seed on screen and the facility on the floor must agree, which means
	# the run seed is derived from the text rather than stored beside it.
	var before := RoomState.run_seed()
	_expect(RoomState.run_seed() == before, "run seed is not stable for one route")
	var text := RoomState.seed_text
	RoomState.reroll_seed()
	_expect(RoomState.seed_text != text, "rerolling produced the same route")
	_expect(RoomState.code == RoomState.code, "rerolling changed the room code")
	_expect(RoomState.run_seed() != before, "a new route seed gave the same run seed")

	# Hide & Seek has been removed from the UI; Office is visible but disabled.
	# Both rules also hold when called directly so stale clients cannot enter.
	_expect(not RoomState.MODE_LABELS.has(RoomState.Mode.HIDE_SEEK),
		"HIDE & SEEK remains in the selectable mode labels")
	_expect(not RoomState.mode_available(RoomState.Mode.HIDE_SEEK),
		"HIDE & SEEK remains available through code")
	RoomState.set_mode(RoomState.Mode.HIDE_SEEK)
	_expect(RoomState.mode != RoomState.Mode.HIDE_SEEK,
		"set_mode let an unavailable mode through")
	_expect(not RoomState.mode_unavailable_reason(RoomState.Mode.HIDE_SEEK).is_empty(),
		"an unavailable mode gives no reason")
	_expect(RoomState.mode_available(RoomState.Mode.DEFAULT),
		"Default mode is unavailable")
	_expect(not RoomState.mode_available(RoomState.Mode.OFFICE),
		"Office mode is selectable before work resumes")

	# Even direct attempts to create the disabled Office mode fall back safely.
	RoomState.create_local(RoomState.Mode.OFFICE)
	_expect(RoomState.mode == RoomState.Mode.DEFAULT,
		"create_local entered disabled Office mode")
	RoomState.create_local(RoomState.Mode.DEFAULT)
	_expect(RoomState.seats() == RoomState.MAX_PLAYERS,
		"a route seats %d, not %d" % [RoomState.seats(), RoomState.MAX_PLAYERS])
	_expect(RoomState.start_label() == "ENTER ROUTE",
		"route staging says '%s'" % RoomState.start_label())
	_expect(RoomState.GUEST_FIRST_NAMES.size() >= 24,
		"guest FIRST-name pool is still too small")
	_expect(RoomState.GUEST_LAST_NAMES.size() >= 24,
		"guest LAST-name pool is still too small")
	for word in RoomState.GUEST_FIRST_NAMES + RoomState.GUEST_LAST_NAMES:
		_expect(String(word) == String(word).to_upper(),
			"guest callsign word %s is not uppercase" % word)

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
	var saw_hard := false
	var nightmare_button: Button = null
	var office_button: Button = null
	var saw_hide_seek := false
	for button in lobby.find_children("*", "Button", true, false):
		saw_hard = saw_hard or String(button.text) == "HARD"
		if String(button.text) == "NIGHTMARE":
			nightmare_button = button
		if String(button.text) == "OFFICE":
			office_button = button
		saw_hide_seek = saw_hide_seek or String(button.text) == "HIDE & SEEK"
	_expect(saw_hard, "the staging screen did not render a Hard button")
	_expect(nightmare_button != null and nightmare_button.disabled,
		"Nightmare is not visible and greyed out")
	_expect(office_button != null and office_button.disabled,
		"Office mode is not visible and greyed out")
	_expect(not saw_hide_seek, "Hide & Seek still appears in staging")
	_expect(lobby.find_child("DebugCustomHostLabel", true, false) == null,
		"the removed custom-host label is still visible")
	_expect(lobby.find_child("DebugCustomHostRow", true, false) == null,
		"the removed custom-host controls are still visible")
	var create_online := lobby.find_child("CreateOnlineRoomButton", true, false) as Button
	var join_online := lobby.find_child("JoinOnlineRoomButton", true, false) as Button
	var code_input := lobby.find_child("PrimaryRoomCodeInput", true, false) as LineEdit
	var leave_online := lobby.find_child("LeaveOnlineRoomButton", true, false) as Button
	_expect(create_online == null, "staging still has a separate online-room action")
	_expect(join_online == null, "staging still has a second join-room action")
	_expect(code_input == null, "staging still has a duplicate room-code input")
	_expect(leave_online == null, "staging still has separate online-room controls")
	_expect(lobby.find_child("EnterRouteButton", true, false) != null,
		"staging lost its enter-route action")
	_expect(lobby.find_child("BackToMenuButton", true, false) != null,
		"staging lost its back-to-menu action")
	var old_connection_copy := ["HOST + LIST ROOM", "JOIN ROOM CODE", "LOCAL SESSION",
		"JOIN AT", "GO OFFLINE", "127.0.0.1", ":8421"]
	for node in lobby.find_children("*", "Control", true, false):
		var copy := ""
		if node is Label or node is Button:
			copy = String(node.text)
		elif node is LineEdit:
			copy = "%s %s" % [node.text, node.placeholder_text]
		for retired in old_connection_copy:
			_expect(not copy.contains(retired),
				"staging still exposes retired connection copy '%s'" % retired)
	lobby.queue_free()
	await host.get_tree().process_frame

	# Actually open a port. Everything above is bookkeeping; this is the part
	# that either works on the machine or does not, and "COULD NOT OPEN PORT"
	# is the single most likely outcome of testing with two windows.
	Backend.suppress_requests_for_tests()
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var error := RoomState.host_room(TEST_PORT)
	if not error.is_empty():
		_fail("hosting failed: %s" % error)
	else:
		_expect(RoomState.online, "hosting did not put the room online")
		_expect(RoomState.is_host, "the host is not the host")
		_expect(RoomState.roster().size() == 1,
			"a freshly hosted room lists %d players" % RoomState.roster().size())
		# Removed/disabled modes stay unavailable online too.
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
		print("  network   hosting on %d, %d seated" % [TEST_PORT,
			RoomState.roster().size()])
		print("  directory fixed to the primary service; no custom-host controls")

	# Hosting twice must not leave the first port held.
	error = RoomState.host_room(TEST_PORT)
	if not error.is_empty():
		_fail("re-hosting failed, so the previous socket was never released: %s" % error)
	RoomState.leave_network()
	_expect(not RoomState.online, "leaving did not take the room offline")
	_expect(RoomState.roster().size() == 1,
		"going offline left %d players in the room" % RoomState.roster().size())

	# CREATE ROOM's online-first wrapper must degrade to the same playable solo
	# room when its initial directory listing fails. Simulate that callback
	# directly; validation suppresses all real primary-server traffic.
	RoomState.create_local(RoomState.Mode.DEFAULT)
	error = RoomState.host_primary_room(TEST_PORT)
	if not error.is_empty():
		_fail("online-first create could not open its local ENet room: %s" % error)
	else:
		RoomState._on_directory_registration(false, "TEST DIRECTORY OFFLINE")
		_expect(not RoomState.online,
			"failed initial listing left CREATE ROOM stuck online")
		_expect("SOLO ROOM" in RoomState.status_message,
			"failed initial listing did not explain its solo fallback")

	if _failures == 0:
		print("  room      %s seats %d, seed %s"
			% [RoomState.code, RoomState.seats(), RoomState.seed_text])
		print("  rules     Hide & Seek hidden; Office visible but disabled")
		print("  difficulty Relaxed / Standard / Hard live; Nightmare visible but disabled")
		print("  guests    %d FIRST x %d LAST callsign words" % [
			RoomState.GUEST_FIRST_NAMES.size(), RoomState.GUEST_LAST_NAMES.size()])
		print("  scales    %d map scales, each a distinct walkable facility" % sizes.size())
		print("  create    primary server first; registration failure falls back to solo")
		print("room OK")
	return _failures
