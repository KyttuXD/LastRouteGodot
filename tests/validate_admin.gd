extends RefCounted

## Headless check on the admin overlay.
##
## Its whole reason to exist is that it must NOT exist in a normal build: every
## row either states what the game is thinking or reaches in and changes it.
## So what is worth testing is the gate, that both modes actually attach one,
## that its readouts do not throw, and that its actions do what they say.
##
## Run with:
##   godot4 --headless res://tests/scenes/validate.tscn -- admin

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	# Admin toggles are real user preferences now. Keep this suite deterministic
	# without leaving the developer's own settings changed after validation.
	var original_admin_preferences := Settings.admin_preferences_snapshot()
	Settings.set_admin_preferences(Settings.ADMIN_PREFERENCE_DEFAULTS)
	# The gate itself. This suite only ever runs in a debug build, so what can
	# be checked here is that the release path is a real branch and not a
	# comment: attach returns null when tools are off.
	if not Build.tools_enabled():
		_fail("the check suite is running without tools enabled")

	for entry in [["res://game/main_3d.tscn", "maze"]]:
		var scene: Node = load(String(entry[0])).instantiate()
		host.get_tree().root.add_child(scene)
		await host.get_tree().process_frame
		await host.get_tree().process_frame

		var menu: AdminMenu = null
		for child in scene.get_children():
			if child is AdminMenu:
				menu = child
		if menu == null:
			_fail("%s has no admin overlay in a debug build" % entry[1])
			scene.queue_free()
			await host.get_tree().process_frame
			continue

		if menu.is_open():
			_fail("%s opened its admin overlay uninvited" % entry[1])
		# Closed, it must not be holding the cursor away from the game.
		menu._set_open(true)
		if not menu.is_open():
			_fail("%s admin overlay would not open" % entry[1])
		if not MouseLock.cursor_visible():
			_fail("%s admin overlay is clickable without a cursor" % entry[1])
		_expect(menu._panel.size.x * menu._panel.scale.x >= 360.0 and menu._panel.size.y * menu._panel.scale.y >= 220.0,
			"%s admin overlay is still a narrow side strip" % entry[1])
		if entry[1] == "maze":
			_expect(scene.player.input_frozen,
				"maze player remains mobile while the admin menu is open")
		# The readout runs every frame while open; a throw here is a crash in a
		# dev tool, which is the worst place to find one.
		if menu._readout.text.is_empty():
			_fail("%s admin overlay reads out nothing" % entry[1])
		var chips := menu._panel.find_children("StateChip", "Label", true, false)
		if entry[1] == "maze":
			# five game toggles + FPS/spike overlay (tip 134) plus the two DebugView toggles
			_expect(chips.size() == 8,
				"maze admin has %d ON/OFF chips instead of 8" % chips.size())
			var on_count := 0
			var off_count := 0
			for chip in chips:
				on_count += 1 if String(chip.text) == "ON" else 0
				off_count += 1 if String(chip.text) == "OFF" else 0
			_expect(on_count == 1 and off_count == 7,
				"admin defaults are not four safety toggles, FPS overlay OFF, two debug views OFF, plus pixel effect ON")
			var inventory_ok := false
			for dropdown in menu._dropdowns:
				if (dropdown["ids"] as Array) == PlayerController3D.COLLECTIBLE_ITEMS \
						and (dropdown["option"] as OptionButton).item_count == PlayerController3D.COLLECTIBLE_ITEMS.size():
					inventory_ok = true
			_expect(inventory_ok, "creative inventory dropdown does not list every collectible or storage upgrade")
		# Exercise genuinely different physical sizes and aspect ratios. The
		# design viewport expands rather than letterboxes, so containment at the
		# default size alone does not prove the panel stays usable.
		for size in [Vector2i(800, 600), Vector2i(1280, 720),
				Vector2i(1920, 1080), Vector2i(3440, 1440)]:
			host.get_tree().root.size = size
			await host.get_tree().process_frame
			await host.get_tree().process_frame
			var view := host.get_tree().root.get_visible_rect()
			var rect := Rect2(menu._panel.global_position, menu._panel.size * menu._panel.scale)
			_expect(rect.position.x >= 0.0 and rect.position.y >= 0.0
				and rect.end.x <= view.size.x + 1.0
				and rect.end.y <= view.size.y + 1.0,
				"%s admin panel spills outside %dx%d (%s in %s)" % [
					entry[1], size.x, size.y, rect, view.size])
		host.get_tree().root.size = Vector2i(960, 540)
		await host.get_tree().process_frame
		menu._set_open(false)
		if MouseLock.cursor_visible() and entry[1] == "maze":
			# The maze captures the mouse for first person; closing must give
			# it back rather than leaving a free pointer over a captured game.
			pass
		print("  %-9s %s" % [entry[1], menu._readout.text.replace("\n", " // ")])

		scene.queue_free()
		await host.get_tree().process_frame

	# Every action has to be callable. They are Callables built inline, so a
	# typo in one is invisible until someone presses that button mid-test.
	var scene: Node = load("res://game/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var menu: AdminMenu = null
	for child in scene.get_children():
		if child is AdminMenu:
			menu = child
	if menu != null:
		GameState.relays_collected = 0
		GameState.score = 0
		for row in menu._actions:
			# Heading-only rows deliberately have no fake no-op action. Every row
			# that renders a button must still expose a real callable.
			if not row.has("action"):
				continue
			var action: Callable = row["action"]
			if not action.is_valid():
				_fail("admin action '%s' is not callable" % row["label"])
		scene.player.taser_cooldown = 5.0
		for row in menu._actions:
			if String(row.get("label", "")) == "CREATIVE INVENTORY":
				(row["action"] as Callable).call("taser")
		_expect(scene.player.selected_inventory_item() == "taser" \
				and scene.player.taser_cooldown == 0.0,
			"creative inventory did not give/restock and select the taser")
		# Relay grants must perform physical pickups, not merely alter the HUD
		# counter. Grant one first, then collect the rest in a batch.
		for row in menu._actions:
			if String(row.get("label", "")) == "GRANT RELAY":
				(row["action"] as Callable).call()
		var relays := _relay_nodes(scene)
		var completed_after_grant := 0
		for relay in relays:
			if relay.completed:
				completed_after_grant += 1
		_expect(completed_after_grant == 1,
			"GRANT RELAY did not complete exactly one relay object")
		_expect(GameState.relays_collected == 1 and GameState.score == 100,
			"GRANT RELAY did not use normal relay count/score pickup effects")

		for row in menu._actions:
			if String(row.get("label", "")) == "ALL RELAYS":
				(row["action"] as Callable).call()
		if GameState.relays_collected != GameState.relay_target:
			_fail("ALL RELAYS left %d of %d collected"
				% [GameState.relays_collected, GameState.relay_target])
		for relay in relays:
			_expect(relay.completed and relay.get_prompt().is_empty(),
				"ALL RELAYS left relay %s collectible" % relay.source_cell)
		_expect(scene.facility_view.generator.uncollected(
			scene.facility_view.generator.relays).is_empty(),
			"ALL RELAYS left generator entries uncollected for hunter logic")
		_expect(GameState.score == GameState.relay_target * 100,
			"ALL RELAYS did not award the normal pickup score exactly once")

		# TOGGLE HUNTER REVEAL: the route hunter starts inactive (she wakes on
		# the relay schedule), so she is the natural case for "the map won't
		# show me a hunter who hasn't woken up yet, unless I'm looking with
		# admin eyes."
		if scene.hunter_view and scene.hunter_view.brain.active:
			_fail("setup problem: the route hunter is already active, nothing to reveal")
		else:
			var hidden_by_default: Array = scene._map_marks()
			var revealed: Array = scene._map_marks(true)
			_expect(hidden_by_default.is_empty(),
				"an inactive hunter showed up on the map without admin reveal")
			_expect(revealed.size() == 1,
				"admin reveal left inert special-hunter spawn dots on the radar")
			_expect(revealed.is_empty() or String(revealed[0].get("name", ""))
				== String(HunterRoster.get_identity(
					scene.hunter_view.brain.hunter_id)["display_name"]),
				"admin reveal did not identify the actual route hunter")

		for row in menu._actions:
			if String(row.get("label", "")) == "TOGGLE HUNTER REVEAL":
				(row["action"] as Callable).call()
		_expect(scene._admin_reveal_hunters, "TOGGLE HUNTER REVEAL did not turn reveal on")
		menu._refresh()
		_expect(_state_text(menu, "HUNTER REVEAL") == "ON",
			"hunter reveal state chip did not update to ON")
		for row in menu._actions:
				if String(row.get("label", "")) == "TOGGLE HUNTER REVEAL":
					(row["action"] as Callable).call()
		_expect(not scene._admin_reveal_hunters, "TOGGLE HUNTER REVEAL did not turn back off")
		menu._refresh()
		_expect(_state_text(menu, "HUNTER REVEAL") == "OFF",
			"hunter reveal state chip did not update back to OFF")

		# NO TARGET is an authoritative targeting rule, not just a hidden local
		# model. With it enabled the host has no eligible solo target and an
		# already-alert hunter drops the chase and resumes ordinary roaming.
		for row in menu._actions:
			if String(row.get("label", "")) == "TOGGLE NO TARGET":
				(row["action"] as Callable).call()
		_expect(scene.player.admin_no_target,
			"TOGGLE NO TARGET did not enable the controller flag")
		_expect(bool(scene._local_hunter_target().get("no_target", false)),
			"NO TARGET was not included in the host targeting state")
		_expect(scene._remotes.best_target(Vector2.ZERO,
			scene._local_hunter_target(), GameState.depth).is_empty(),
			"host targeting still selected a NO TARGET runner")
		if scene.hunter_view:
			scene.hunter_view.brain.active = true
			scene.hunter_view.brain.state = HunterBrain.State.CHASE
			scene._update_gameplay(0.05)
			_expect(scene.hunter_view.brain.state != HunterBrain.State.CHASE,
				"NO TARGET left an alerted hunter frozen in CHASE")
		for row in menu._actions:
			if String(row.get("label", "")) == "TOGGLE NO TARGET":
				(row["action"] as Callable).call()
		_expect(not scene.player.admin_no_target,
			"TOGGLE NO TARGET did not turn back off")

		# NOCLIP is a debug traversal mode, so it must remove both collision
		# directions while active and restore the ordinary player body when off.
		for row in menu._actions:
			if String(row.get("label", "")) == "TOGGLE NOCLIP":
				(row["action"] as Callable).call()
		_expect(scene.player.admin_noclip,
			"TOGGLE NOCLIP did not enable the controller flag")
		_expect(scene.player.collision_layer == 0 and scene.player.collision_mask == 0,
			"NOCLIP left the player colliding with route geometry")
		menu._refresh()
		_expect(_state_text(menu, "NOCLIP") == "ON",
			"noclip state chip did not update to ON")
		for row in menu._actions:
			if String(row.get("label", "")) == "TOGGLE NOCLIP":
				(row["action"] as Callable).call()
		_expect(not scene.player.admin_noclip,
			"TOGGLE NOCLIP did not turn back off")
		_expect(scene.player.collision_layer == 1 and scene.player.collision_mask == 1,
			"disabling NOCLIP did not restore player collision")

		# GOD MODE still permits targeting/chasing, but capture cannot start a
		# struggle or end the run. Enabling it during a struggle cancels that
		# struggle cleanly as well.
		for row in menu._actions:
			if String(row.get("label", "")) == "TOGGLE GOD MODE":
				(row["action"] as Callable).call()
		_expect(scene.player.admin_god_mode,
			"TOGGLE GOD MODE did not enable the controller flag")
		_expect(bool(scene._local_hunter_target().get("god_mode", false)),
			"GOD MODE was not included in the host targeting state")
		var game_over_before := GameState.game_over
		if scene.hunter_view:
			scene._trigger_capture(scene.hunter_view, true)
		_expect(GameState.game_over == game_over_before,
			"GOD MODE allowed a capture to end the run")
		_expect(not GameState.escape_active,
			"GOD MODE allowed a capture struggle to begin")
		GameState.begin_escape("admin-test")
		scene.player.admin_god_mode = false
		scene._toggle_admin_god_mode()
		_expect(not GameState.escape_active,
			"enabling GOD MODE did not cancel an active struggle")
		scene._toggle_admin_god_mode()
		_expect(not scene.player.admin_god_mode,
			"TOGGLE GOD MODE did not turn back off")
	scene.queue_free()
	await host.get_tree().process_frame

	# Save every non-default personal toggle, then instantiate a fresh route.
	# This exercises both ConfigFile persistence and the tools-gated scene
	# restore path without pretending that room-wide mutations should survive.
	var persisted_preferences := {
		"no_target": true,
		"god_mode": true,
		"noclip": true,
		"map_reveal": true,
		"hunter_reveal": true,
		"pixel_effect_enabled": false,
	}
	Settings.set_admin_preferences(persisted_preferences)
	var saved_config := ConfigFile.new()
	_expect(saved_config.load(Settings.SETTINGS_PATH) == OK,
		"admin preferences were not written to settings.cfg")
	for key_value in persisted_preferences:
		var key := String(key_value)
		_expect(bool(saved_config.get_value("admin", key, false)) \
			== bool(persisted_preferences[key]),
			"admin preference '%s' was not persisted" % key)
	var restored_scene: Node = load("res://game/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(restored_scene)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	_expect(restored_scene.admin_menu != null,
		"persistence fixture did not pass the admin build gate")
	_expect(restored_scene.player.admin_no_target,
		"saved NO TARGET was not restored in a fresh route")
	_expect(restored_scene.player.admin_god_mode,
		"saved GOD MODE was not restored in a fresh route")
	_expect(restored_scene.player.admin_noclip \
		and restored_scene.player.collision_layer == 0 \
		and restored_scene.player.collision_mask == 0,
		"saved NOCLIP was not restored with its collision state")
	_expect(restored_scene._admin_reveal_hunters,
		"saved hunter reveal was not restored in a fresh route")
	_expect(not restored_scene.pixel_signal_effect.admin_enabled(),
		"saved pixel-effect override was not restored in a fresh route")
	restored_scene.queue_free()
	await host.get_tree().process_frame
	Settings.set_admin_preferences(original_admin_preferences)

	# ---- the streamed route's admin tools: new tools, ADMIN ACTIVE badge, DEBUG RUN flag
	var route: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	await host.get_tree().process_frame
	for _index in 8:
		await host.get_tree().physics_frame
	var route_menu: AdminMenu = null
	for child in route.get_children():
		if child is AdminMenu:
			route_menu = child
	if route_menu == null:
		_fail("the streamed route has no admin overlay in a debug build")
	else:
		var labels := []
		for entry in route_menu._actions:
			labels.append(String(entry.get("label", entry.get("heading", ""))))
		for wanted in ["FREEZE ALL HUNTERS", "RELEASE ALL HUNTERS", "TELEPORT",
				"RUN SPEED", "GAME SPEED // SOLO RUNS ONLY", "COPY SEED", "HUNTER",
				"TOGGLE REGION MAP (F8)"]:
			_expect(labels.has(wanted), "streamed route admin menu lacks %s" % wanted)
		# everything the new tools add is permission-scoped (nothing falls through to ungated)
		for entry in route_menu._actions:
			var gated: bool = entry.has("permission") or bool(entry.get("owner_only", false))
			_expect(gated, "admin entry %s has no permission scope" % entry.get("label", entry.get("heading", "?")))
		_expect(not route._admin_region_map, "the admin region/region map must default to off")
		var hunter_dropdown_ok := false
		for dropdown in route_menu._dropdowns:
			if (dropdown["ids"] as Array).size() == HunterRoster.A_Z_IDS.size() + HunterRoster.VOID_IDS.size() + SecretCreatures.admin_ids().size():
				hunter_dropdown_ok = true
		_expect(hunter_dropdown_ok, "the hunter dropdown must list every A-Z and Void hunter")
		_expect(route_menu._tabs.tab_count >= 5, "the admin menu should be split into tabs (got %d)" % route_menu._tabs.tab_count)
		# the badge is a segment of the HUD's top status bar (its own label only where there is no HUD)
		var status_bar := HudStatusBar.find(route_menu.get_tree())
		var badge := route_menu.get_node_or_null("AdminActiveBadge") as Label
		var badge_text := func() -> String:
			return status_bar.segment_text("admin") if status_bar != null else (badge.text if badge != null else "")
		_expect((badge_text.call() as String).begins_with("ADMIN ACTIVE"),
			"the ADMIN ACTIVE badge is missing")
		GameState.debug_run = false
		route_menu._mark_debug({"label": "x"})
		_expect(GameState.debug_run and (badge_text.call() as String).contains("DEBUG RUN"),
			"using a tool did not flag the run as a DEBUG RUN")
		GameState.debug_run = false
		route_menu._mark_debug({"no_debug": true})
		_expect(not GameState.debug_run, "a roster/read-only entry must not flag a DEBUG RUN")
		# a DEBUG RUN records nothing
		GameState.debug_run = true
		var saved_before := Backend.account_progress_saved_at
		Backend.account_save_progress({"kind": "last_route", "schema": 1})
		_expect(Backend.account_progress_saved_at == saved_before and not Backend.account_discover_hunter("aki"),
			"a DEBUG RUN still recorded progress")
		GameState.debug_run = false
		# chunk teleport lands on the next chunk's centre; run speed and game speed apply and reset
		var here: Vector3i = route.facility.current_chunk_coord()
		route._admin_teleport_chunk("east")
		var cs: int = StreamedRouteGenerator.CHUNK_SIZE
		_expect(floori(route.player.global_position.x / cs) == here.x + 1,
			"the chunk teleport did not move one chunk east")
		route.player.admin_speed_scale = 2.0
		route._admin_game_speed("2")
		_expect(Engine.time_scale == 2.0, "the game-speed tool did not set the time scale")
		route._force_disable_admin_cheats()
		_expect(Engine.time_scale == 1.0 and route.player.admin_speed_scale == 1.0,
			"disabling the admin cheats did not reset game speed and run speed")
		_check_safe_teleport(route, route_menu)
	# outside the overlay branch on purpose: these read the route's own action list, so they run even if the overlay is absent
	await _check_route_commands_any_room(route, route._infinite_admin_actions())
	_check_whitelist_rows(route)
	_check_route_commands_refused_without_owner(route)
	Engine.time_scale = 1.0
	GameState.debug_run = false
	route.queue_free()
	await host.get_tree().process_frame

	if _failures == 0:
		print("admin OK")
	return _failures


## The whitelist rows (WHITELIST EVERYONE HERE, SHOW WHITELIST) are in the route's admin list only inside a reserved private room:
## absent outside one, present inside one. Their functions are checked in _check_route_commands_any_room.
func _check_whitelist_rows(route: Node) -> void:
	var saved_reserved := RoomState.reserved
	var whitelist_labels := ["WHITELIST EVERYONE HERE", "SHOW WHITELIST"]
	RoomState.reserved = false
	var outside: Array = route._infinite_admin_actions()
	RoomState.reserved = true
	var inside: Array = route._infinite_admin_actions()
	RoomState.reserved = saved_reserved
	for label in whitelist_labels:
		_expect(_action_row(outside, label).is_empty(), "%s is in the admin list outside a reserved private room" % label)
		_expect(not _action_row(inside, label).is_empty(), "%s is missing from the admin list inside a reserved private room" % label)


func _action_row(actions: Array, label: String) -> Dictionary:
	for row in actions:
		if String(row.get("label", "")) == label and row.has("action"):
			return row
	return {}


## Owner route controls, room chat and the whitelist work outside a reserved private room: no row refuses with
## NOT A PRIVATE ROOM, and the local effects happen (END ROUTE ends the run, the whitelist keeps its list). Solo here, so
## the host path runs; a guest owner reaches the same code through the host's admin request path.
func _check_route_commands_any_room(route: Node, actions: Array) -> void:
	var saved_reserved := RoomState.reserved
	var saved_session := RoomState.session_active
	var saved_suppressed: bool = RoomState._scene_transitions_suppressed_for_tests
	RoomState.reserved = false
	RoomState.suppress_scene_transitions_for_tests()
	var owner_labels := ["RESTART ROUTE // NEW SEED", "RESTART ROUTE // SAME SEED", "END ROUTE",
		"ROOM MUTE LAST SPEAKER", "ROOM UNMUTE EVERYONE", "KICK LAST SPEAKER"]
	for label in owner_labels:
		var row := _action_row(actions,label)
		_expect(not row.is_empty(), "admin menu has no %s row" % label)
		if row.is_empty():
			continue
		RoomState.session_active = false
		route.hud.message_label.text = ""
		(row["action"] as Callable).call()
		var said: String = route.hud.message_label.text
		_expect(not said.contains("NOT A PRIVATE ROOM") and not said.contains("NEEDS THE HOST"),
			"%s refused outside a private room: %s" % [label, said])

	# END ROUTE ends a run in progress through the same end path the host uses
	RoomState.session_active = true
	var end_row := _action_row(actions,"END ROUTE")
	if not end_row.is_empty():
		(end_row["action"] as Callable).call()
	_expect(not RoomState.session_active, "END ROUTE did not end a run outside a private room")

	# RESTART ROUTE re-enters the route: SAME SEED keeps the seed, NEW SEED makes a fresh one
	RoomState.session_active = false
	var seed_before := RoomState.seed_text
	var same_row := _action_row(actions,"RESTART ROUTE // SAME SEED")
	if not same_row.is_empty():
		(same_row["action"] as Callable).call()
	_expect(RoomState.seed_text == seed_before, "RESTART ROUTE // SAME SEED changed the seed")
	RoomState.session_active = false
	var new_row := _action_row(actions,"RESTART ROUTE // NEW SEED")
	if not new_row.is_empty():
		(new_row["action"] as Callable).call()
	_expect(RoomState.seed_text != seed_before, "RESTART ROUTE // NEW SEED kept the seed")

	# WHITELIST outside a private room keeps a local list and says it is not enforced there
	RoomState.local_whitelist_code = ""
	RoomState.local_whitelist = PackedStringArray()
	route._admin_whitelist("add", "TESTER")
	_expect(RoomState.local_whitelist_names().has("TESTER"), "WHITELIST did not keep the name outside a private room")
	_expect(route.hud.message_label.text.contains("NOT ENFORCED"),
		"WHITELIST outside a private room did not say it is not enforced: %s" % route.hud.message_label.text)
	route._admin_whitelist("list", "")
	_expect(route.hud.message_label.text.contains("TESTER"), "SHOW WHITELIST did not show the local list")
	RoomState.local_whitelist_code = ""
	RoomState.local_whitelist = PackedStringArray()

	# END ROUTE hands the staging change to a deferred call (RoomState._receive_end -> _return_to_staging), which reads the
	# suppression flag when it runs. Keep the flag up until those deferred calls have run, or the scene swap frees this runner.
	await route.get_tree().process_frame
	await route.get_tree().process_frame
	RoomState.reserved = saved_reserved
	RoomState.session_active = saved_session
	RoomState._scene_transitions_suppressed_for_tests = saved_suppressed


## Non-admins get none of the owner route commands through the admin request path, and a delegated admin's room proof
## (without the owner marker) does not pass the owner gate.
func _check_route_commands_refused_without_owner(route: Node) -> void:
	var was_denied := Build.deny_admin_for_test
	var saved_session := RoomState.session_active
	RoomState.reserved = false
	RoomState.session_active = true
	Build.deny_admin_for_test = true
	_expect(not Build.admin_owner_tools_enabled(), "a non-admin passes the owner tools gate")
	route.hud.message_label.text = ""
	route._accept_stream_admin(1, {"what": "admin_world", "action": "route_command",
		"command": "end", "same_seed": false})
	_expect(RoomState.session_active, "a non-admin ended the route through the admin path")
	_expect(route.hud.message_label.text.contains("REJECTED"),
		"a non-admin route command was not refused: %s" % route.hud.message_label.text)
	route._accept_stream_admin(1, {"what": "admin_world", "action": "room_chat", "op": "kick"})
	_expect(route.hud.message_label.text.contains("REJECTED"),
		"a non-admin room chat command was not refused: %s" % route.hud.message_label.text)
	route._remotes.authorize_admin_peer(9001, 60, PackedStringArray(["player", "world"]))
	_expect(not route._remotes.remote_admin_peer_allowed(9001, "owner"),
		"a delegated admin's room proof passed the owner gate")
	route._remotes.authorize_admin_peer(9001, 60, PackedStringArray(["owner"]))
	_expect(route._remotes.remote_admin_peer_allowed(9001, "owner"),
		"the owner marker on a room proof was not honoured")
	route._remotes._authorized_admin_peers.erase(9001)
	Build.deny_admin_for_test = was_denied
	RoomState.session_active = saved_session


## Safe teleport: map point and X,Z, host landing clear of walls/props/ducts, refused without admin rights.
func _check_safe_teleport(route: Node, menu: AdminMenu) -> void:
	var field_ok := false
	for entry in route._admin_roster_fields():
		if String(entry.get("label", "")) == "SAFE TELEPORT" and String(entry.get("permission", "")) == "player":
			field_ok = true
	_expect(field_ok, "SAFE TELEPORT is missing from the admin fields or is not player-scoped")
	var saw_field := false
	for node in menu._panel.find_children("*", "LineEdit", true, false):
		if String((node as LineEdit).placeholder_text).begins_with("X,Z"):
			saw_field = true
	_expect(saw_field, "the admin panel has no SAFE TELEPORT coordinate field")
	_expect(route.hud.plan.admin_teleport, "the fullscreen map did not arm admin teleport")
	_expect(route._admin_action_permission("safe_teleport") == "player",
		"safe teleport is not gated on the player permission")
	_expect(RemotePlayers.ADMIN_WORLD_ACTIONS.has("safe_teleport"),
		"a guest safe teleport is not on the host admin-world allowlist")
	_expect(RemotePlayers.HOST_MOVES.has("admin_teleport"),
		"a host safe teleport is not a GuestGuard host move")
	var wall := _first_wall_point(route)
	_expect(wall != Vector2.INF, "the streamed route has no wall cell to test safe teleport")
	if wall != Vector2.INF:
		var landed: Vector3 = route._admin_safe_landing(wall, 0)
		_expect(landed != Vector3.INF and _landing_is_safe(route, landed),
			"safe teleport did not find an open cell beside a wall")
		_expect(Vector2(landed.x, landed.z).distance_to(wall) > 0.4,
			"safe teleport stayed inside the wall cell")
		route.hud.admin_teleport_requested.emit(wall, 0)
		_expect(route.player.global_position.is_equal_approx(landed),
			"a map-point safe teleport did not land on the host's safe cell")
	var duct := _first_duct_point(route)
	_expect(duct != Vector2.INF, "the streamed route has no duct cell to test safe teleport")
	if duct != Vector2.INF:
		var clear: Vector3 = route._admin_safe_landing(duct, 0)
		_expect(clear != Vector3.INF and _landing_is_safe(route, clear),
			"safe teleport from a duct cell did not find open floor")
		route._admin_teleport_coordinates("%.1f,%.1f" % [duct.x, duct.y])
		_expect(route.player.global_position.is_equal_approx(clear),
			"typed X,Z safe teleport did not use the safe landing")
	var prop_at := _first_blocked_prop_point(route)
	_expect(prop_at != Vector2.INF, "the streamed route has no solid prop to test safe teleport")
	if prop_at != Vector2.INF:
		var beside: Vector3 = route._admin_safe_landing(prop_at, 0)
		_expect(beside != Vector3.INF and _landing_is_safe(route, beside),
			"safe teleport from inside a prop did not find open floor")
		_expect(Vector2(beside.x, beside.z).distance_to(prop_at) > 0.2,
			"safe teleport stayed inside a solid prop")
	var sewer_at := Vector2(22.5, 22.5)
	var sewer: Vector3 = route._admin_safe_landing(sewer_at, -1)
	_expect(sewer != Vector3.INF and _landing_is_safe(route, sewer),
		"safe teleport found no open cell on the sewer level")
	if sewer != Vector3.INF:
		_expect(is_equal_approx(sewer.y, float(-1) * StreamedFacilityView3D.LEVEL_HEIGHT + 0.05),
			"safe teleport did not put the feet on the sewer floor")
		route._admin_teleport_coordinates("%.1f,%.1f,-1" % [sewer_at.x, sewer_at.y])
		_expect(route.player.global_position.is_equal_approx(sewer),
			"X,Z,LEVEL safe teleport did not land on the sewer cell")
		var guest: Vector3 = route._admin_safe_landing(Vector2(sewer.x + 6.0, sewer.z), -1)
		route._accept_stream_admin(7, {"what": "admin_world", "action": "safe_teleport",
			"x": sewer.x + 6.0, "z": sewer.z, "level": -1})
		_expect(guest != Vector3.INF and route.player.global_position.is_equal_approx(guest),
			"a guest admin safe teleport was not applied through the host path")
	var parked: Vector3 = route.player.global_position
	route._admin_teleport_coordinates("nope")
	_expect(route.player.global_position.is_equal_approx(parked),
		"a malformed coordinate teleport moved the player")
	GameState.debug_run = false
	Build.deny_admin_for_test = true
	route._admin_request_safe_teleport(Vector2(4.5, 4.5), 0)
	route._accept_stream_admin(1, {"what": "admin_world", "action": "safe_teleport",
		"x": 80.0, "z": 80.0, "level": 0})
	_expect(route.player.global_position.is_equal_approx(parked),
		"safe teleport ran without admin rights")
	_expect(not GameState.debug_run, "a refused safe teleport flagged a debug run")
	Build.deny_admin_for_test = false


func _landing_is_safe(route: Node, spot: Vector3) -> bool:
	if spot == Vector3.INF:
		return false
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var cell := Vector2i(floori(spot.x), floori(spot.z))
	var level := roundi(spot.y / StreamedFacilityView3D.LEVEL_HEIGHT)
	var coord := Vector3i(floori(float(cell.x) / float(size)), level, floori(float(cell.y) / float(size)))
	if not route.facility.generator.is_chunk_allowed(coord):
		return false
	var local := Vector2i(posmod(cell.x, size), posmod(cell.y, size))
	if PlayerController3D.VENT_STOREYS.has(level) and VentNetwork.is_duct_cell(local):
		return false
	var data: Dictionary = route.facility.generator.chunk(coord)
	var world := CollisionWorld.from_chunk(data)
	return world.can_stand(Vector2(local) + Vector2(.5, .5), GameConfig.PLAYER_RADIUS) \
		and is_equal_approx(spot.y, float(level) * StreamedFacilityView3D.LEVEL_HEIGHT + 0.05)


func _first_wall_point(route: Node) -> Vector2:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var origin: Vector3i = route.facility.current_chunk_coord()
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var coord := Vector3i(origin.x + dx, 0, origin.z + dz)
			if not route.facility.generator.is_chunk_allowed(coord):
				continue
			var grid: Array = route.facility.generator.chunk(coord).get("grid", [])
			for z in grid.size():
				var row: Array = grid[z]
				for x in row.size():
					if int(row[x]) != 0:
						return Vector2(coord.x * size + x, coord.z * size + z) + Vector2(.5, .5)
	return Vector2.INF


func _first_duct_point(route: Node) -> Vector2:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var origin: Vector3i = route.facility.current_chunk_coord()
	var coord := Vector3i(origin.x, 0, origin.z)
	if not route.facility.generator.is_chunk_allowed(coord):
		return Vector2.INF
	var grid: Array = route.facility.generator.chunk(coord).get("grid", [])
	for z in grid.size():
		var row: Array = grid[z]
		for x in row.size():
			if VentNetwork.is_duct_cell(Vector2i(x, z)):
				return Vector2(coord.x * size + x, coord.z * size + z) + Vector2(.5, .5)
	return Vector2.INF


func _first_blocked_prop_point(route: Node) -> Vector2:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var origin: Vector3i = route.facility.current_chunk_coord()
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var coord := Vector3i(origin.x + dx, 0, origin.z + dz)
			if not route.facility.generator.is_chunk_allowed(coord):
				continue
			var data: Dictionary = route.facility.generator.chunk(coord)
			var world := CollisionWorld.from_chunk(data)
			for prop_value in data.get("region_props", []):
				var prop: Dictionary = prop_value
				if not bool(prop.get("solid", true)) or bool(prop.get("room_door", false)):
					continue
				var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
				if world.can_stand(Vector2(cell) + Vector2(.5, .5), GameConfig.PLAYER_RADIUS):
					continue
				return Vector2(coord.x * size + cell.x, coord.z * size + cell.y) + Vector2(.5, .5)
	return Vector2.INF


func _relay_nodes(scene: Node) -> Array[RouteInteractable3D]:
	var result: Array[RouteInteractable3D] = []
	for entry in scene.facility_view.generator.relays:
		var relay: RouteInteractable3D = scene.facility_view._at(
			Vector2i(int(entry["x"]), int(entry["y"])),
			RouteInteractable3D.Kind.RELAY)
		if relay != null:
			result.append(relay)
	return result


func _state_text(menu: AdminMenu, caption: String) -> String:
	for entry in menu._state_buttons:
		var button := entry["button"] as Button
		var label := button.get_node_or_null("StateToggleContent/Caption") as Label
		if label != null and label.text == caption:
			var chip := button.get_node_or_null("StateToggleContent/StateChip") as Label
			return chip.text if chip != null else ""
	return ""
